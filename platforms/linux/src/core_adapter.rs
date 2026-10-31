//! Adapter over the real `saycribe-core` crate (platforms/core):
//! asr::Recognizer + vad::Segmenter via pipeline::Session.
//! Parameters per docs/识别接口.md: min_speech 0.25 s and VAD buffer 120 s are
//! set inside core's Segmenter; min_silence 0.45 s and ≤3 concurrent cleans here.
use crate::core_api::*;
use saycribe_core::{asr::Recognizer as CoreRecognizer, models::{ModelManager, sense_voice, silero_vad},
    pipeline::{Engine, EventSink, Session, SessionEvent, SessionOptions}, relay::RelayClient, token::DeviceToken,
    paths::Paths, Platform, RelayErrorKind};
use std::path::PathBuf;
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

pub const MIN_SILENCE: f32 = 0.45;

pub fn models_dir() -> PathBuf {
    if let Ok(d) = std::env::var("SAYCRIBE_MODELS_DIR") { return d.into(); }
    Paths::standard().map(|p| p.models_dir()).unwrap_or_else(|| PathBuf::from("models"))
}

pub fn relay_client(url: &str, token: Option<String>) -> RelayClient {
    RelayClient::new(url, token.map(|t| DeviceToken { token: t, platform: Platform::Linux, device: "linux".into(), token_id: None }))
}

pub fn map_kind(k: RelayErrorKind) -> RelayError {
    match k {
        RelayErrorKind::Offline => RelayError::Offline("network".into()),
        RelayErrorKind::Unauthorized => RelayError::Unauthorized,
        RelayErrorKind::Revoked => RelayError::Revoked,
        RelayErrorKind::RateLimited => RelayError::RateLimited,
        RelayErrorKind::Upstream => RelayError::Upstream("upstream".into()),
        RelayErrorKind::Timeout => RelayError::Upstream("timeout".into()),
        RelayErrorKind::BadRequest => RelayError::BadRequest("bad_request".into()),
    }
}

/// Load SenseVoice once (≈1–3 s, ~300 MB), in the background at startup.
pub fn load_engine(relay: RelayClient) -> Result<Arc<Engine>, String> {
    let mm = ModelManager::new(models_dir());
    let sv = sense_voice();
    let vad = silero_vad();
    if !mm.is_installed(&sv) || !mm.is_installed(&vad) {
        return Err(format!("模型未下载：运行 saycribe --download-models（目录 {}）", models_dir().display()));
    }
    if !mm.verify(&sv) || !mm.verify(&vad) {
        return Err(format!("模型 sha256 校验失败：请删掉后重跑 saycribe --download-models（目录 {}）", models_dir().display()));
    }
    let t = Instant::now();
    let threads = std::env::var("SAYCRIBE_ASR_THREADS").ok().and_then(|s| s.parse().ok()).unwrap_or(4);
    let rec = CoreRecognizer::new(&mm.dir(&sv), "auto", threads, None).map_err(|e| e.to_string())?;
    eprintln!("[asr] SenseVoice loaded in {} ms", t.elapsed().as_millis());
    Ok(Arc::new(Engine { recognizer: Arc::new(rec), vad_model: mm.dir(&vad).join("silero_vad.onnx"),
        relay, min_silence: MIN_SILENCE, max_concurrent: 3 }))
}

pub fn download_models() -> Result<(), String> {
    let mm = ModelManager::new(models_dir());
    for m in [silero_vad(), sense_voice()] {
        let label = if m.id.is_empty() { "silero_vad".into() } else { m.id.clone() };
        let mut last = 0u64;
        mm.ensure(&m, |got, total| {
            if got - last > 8 << 20 { last = got; eprintln!("  {label} {} / {} MB", got >> 20, total >> 20); }
        }).map_err(|e| e.to_string())?;
        if !mm.verify(&m) {
            return Err(format!("[models] {label} 下载后 sha256 校验失败"));
        }
        eprintln!("[models] {label} ok");
    }
    Ok(())
}

type Done = (String, Option<Result<String, RelayError>>, u32);

pub struct CoreDictation {
    engine: Arc<OnceLock<Result<Arc<Engine>, String>>>,
    session: Option<(Arc<Session>, mpsc::Receiver<Done>, Arc<Mutex<u64>>)>,
    pub clean: bool,
}

impl CoreDictation {
    /// Starts loading the recognizer in the background immediately.
    pub fn new(relay: RelayClient) -> Self {
        let cell = Arc::new(OnceLock::new());
        let c = cell.clone();
        std::thread::spawn(move || { let _ = c.set(load_engine(relay)); });
        CoreDictation { engine: cell, session: None, clean: true }
    }
    fn engine(&self) -> Result<Arc<Engine>, String> {
        let t = Instant::now();
        while self.engine.get().is_none() {
            if t.elapsed() > Duration::from_secs(30) { return Err("识别模型加载超时".into()); }
            std::thread::sleep(Duration::from_millis(10));
        }
        self.engine.get().unwrap().clone()
    }
}

impl Dictation for CoreDictation {
    fn begin(&mut self, style: &str, dictionary: &[String]) -> Result<PcmSink, String> {
        let engine = self.engine()?;
        let (tx, rx) = mpsc::channel::<Done>();
        let asr_ms = Arc::new(Mutex::new(0u64));
        let a = asr_ms.clone();
        let sink: EventSink = Arc::new(move |e| match e {
            SessionEvent::Recognized { decode_ms, .. } => { *a.lock().unwrap() += decode_ms; }
            SessionEvent::Done { raw, text, error, segments, .. } => {
                let cleaned = match (text, error) { (_, Some(k)) => Some(Err(map_kind(k))), (Some(t), None) => Some(Ok(t)), (None, None) => None };
                let _ = tx.send((raw, cleaned, segments));
            }
            _ => {}
        });
        // Session::start also pre-connects the relay (warm_up → /v1/ping).
        let s = Arc::new(Session::start(engine, SessionOptions { style: Some(style.into()), dictionary: dictionary.to_vec(), clean: self.clean }, sink)
            .map_err(|e| e.to_string())?);
        let s2 = s.clone();
        self.session = Some((s, rx, asr_ms));
        Ok(Box::new(move |pcm| s2.push(pcm)))
    }
    fn finish(&mut self) -> Result<DictationResult, String> {
        let (s, rx, asr_ms) = self.session.take().ok_or("no session")?;
        s.finish();
        let (raw, cleaned, segments) = rx.recv_timeout(Duration::from_secs(30)).map_err(|_| "识别/整理超时".to_string())?;
        let cleaned = if self.clean { cleaned } else { None };
        let asr_ms = *asr_ms.lock().unwrap();
        Ok(DictationResult { raw, cleaned, asr_ms, segments })
    }
    fn cancel(&mut self) { if let Some((s, ..)) = self.session.take() { s.cancel(); } }
}
