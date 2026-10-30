//! 录音会话流水线：PCM → VAD 分段 → SenseVoice → 中转整理（并发 ≤N，按 seq 拼接）。
//! 全部在后台线程运行，结果通过回调推给平台层（非阻塞）。
use crate::{asr::Recognizer, error::{CoreError, RelayErrorKind}, relay::{RelayClient, RelayRequest, SegmentMeta}, vad::Segmenter, Result};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{mpsc, Arc, Mutex};

#[derive(Debug, Clone)]
pub enum SessionEvent {
    /// 某段识别完成（原文）
    Recognized { seq: u32, raw: String, decode_ms: u64 },
    /// 按 seq 顺序可插入/显示的整理结果（已连续）
    Cleaned { seq: u32, text: String, relay_ms: u64 },
    /// 会话结束。`text` 为全部整理拼接；中转失败时 text=None、error 带分类，raw 仍可写入历史。
    Done { raw: String, text: Option<String>, error: Option<RelayErrorKind>, segments: u32, audio_seconds: f64 },
}

pub type EventSink = Arc<dyn Fn(SessionEvent) + Send + Sync>;

#[derive(Debug, Clone, Default)]
pub struct SessionOptions { pub style: Option<String>, pub dictionary: Vec<String>, /// false=只识别不整理
    pub clean: bool }

pub struct Engine { pub recognizer: Arc<Recognizer>, pub vad_model: PathBuf, pub relay: RelayClient, pub min_silence: f32, pub max_concurrent: usize }

enum Msg { Pcm(Vec<f32>), Finish, Cancel }

pub struct Session { tx: mpsc::Sender<Msg>, handle: Option<std::thread::JoinHandle<()>> }

impl Session {
    /// 开始会话（同时对中转预连接）。
    pub fn start(engine: Arc<Engine>, opts: SessionOptions, sink: EventSink) -> Result<Session> {
        let mut seg = Segmenter::new(&engine.vad_model, engine.min_silence, 12.0)?;
        if opts.clean { engine.relay.warm_up(); }
        let (tx, rx) = mpsc::channel();
        let handle = std::thread::spawn(move || {
            let sid = uuid::Uuid::new_v4().to_string();
            let st = Arc::new(Mutex::new(State::default()));
            let mut workers: Vec<std::thread::JoinHandle<()>> = vec![];
            let mut seq = 0u32; let mut raws: Vec<String> = vec![]; let mut total = 0usize;
            let mut handle_segs = |segs: Vec<crate::vad::Segment>, last: bool, workers: &mut Vec<std::thread::JoinHandle<()>>, seq: &mut u32, raws: &mut Vec<String>| {
                let n = segs.len();
                for (i, s) in segs.into_iter().enumerate() {
                    let t = match engine.recognizer.transcribe_at(&s.samples, s.start) { Ok(t) => t, Err(_) => continue };
                    if t.text.is_empty() { continue; }
                    let my = *seq; *seq += 1;
                    sink(SessionEvent::Recognized { seq: my, raw: t.text.clone(), decode_ms: t.decode_ms });
                    let ctx: String = { let all = raws.join(""); let c: Vec<char> = all.chars().collect(); c[c.len().saturating_sub(300)..].iter().collect() };
                    raws.push(t.text.clone());
                    if !opts.clean { { let mut g = st.lock().unwrap(); g.done.insert(my, Ok((t.text.clone(), 0))); } continue; }
                    while workers.len() >= engine.max_concurrent.max(1) { let _ = workers.remove(0).join(); }
                    let req = RelayRequest::Clean { transcript: t.text, style: opts.style.clone(), dictionary: opts.dictionary.clone(), context: if ctx.is_empty() { None } else { Some(ctx) }, meta: SegmentMeta { session_id: Some(sid.clone()), seq: Some(my), r#final: Some(last && i + 1 == n) } };
                    let (relay, st, sink) = (engine.relay.clone(), st.clone(), sink.clone());
                    workers.push(std::thread::spawn(move || {
                        let r = relay.call(&req).map(|r| (r.text, r.client_ms)).map_err(|e| e.kind());
                        let mut g = st.lock().unwrap(); g.done.insert(my, r);
                        // 按序发出连续完成的段
                        while let Some(Ok((text, ms))) = g.done.get(&g.next).cloned().map(|r| r.map_err(|_| ())) { let s = g.next; g.next += 1; sink(SessionEvent::Cleaned { seq: s, text, relay_ms: ms }); }
                    }));
                }
            };
            loop {
                match rx.recv() {
                    Ok(Msg::Pcm(p)) => { total += p.len(); let s = seg.push(&p); if !s.is_empty() { handle_segs(s, false, &mut workers, &mut seq, &mut raws); } }
                    Ok(Msg::Finish) => { let s = seg.finish(); handle_segs(s, true, &mut workers, &mut seq, &mut raws); break; }
                    Ok(Msg::Cancel) | Err(_) => return,
                }
            }
            for w in workers { let _ = w.join(); }
            let g = st.lock().unwrap();
            let mut text = String::new(); let mut err = None;
            for i in 0..seq { match g.done.get(&i) { Some(Ok((t, _))) => text.push_str(t), Some(Err(k)) => { err.get_or_insert(*k); } None => {} } }
            sink(SessionEvent::Done { raw: raws.join(""), text: if err.is_some() { None } else { Some(text) }, error: err, segments: seq, audio_seconds: total as f64 / crate::SAMPLE_RATE as f64 });
        });
        Ok(Session { tx, handle: Some(handle) })
    }
    /// 送入 16kHz 单声道 f32 PCM（任意块大小，非阻塞）。
    pub fn push(&self, pcm: &[f32]) { let _ = self.tx.send(Msg::Pcm(pcm.to_vec())); }
    /// 录音结束（非阻塞），之后会收到 Done。
    pub fn finish(&self) { let _ = self.tx.send(Msg::Finish); }
    pub fn cancel(&self) { let _ = self.tx.send(Msg::Cancel); }
    /// 阻塞等到会话线程结束（测试/CLI 用）。
    pub fn join(mut self) { if let Some(h) = self.handle.take() { let _ = h.join(); } }
}

#[derive(Default)]
struct State { next: u32, done: BTreeMap<u32, std::result::Result<(String, u64), RelayErrorKind>> }

trait IntoKind { fn kind(self) -> RelayErrorKind; }
impl IntoKind for CoreError { fn kind(self) -> RelayErrorKind { self.relay_kind().unwrap_or(RelayErrorKind::Upstream) } }
