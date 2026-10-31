//! Platform-independent controller: press → record + ping; release →
//! recognize → relay (clean / edit) → insert. Uses only traits, so the X11
//! and future Wayland backends and the core adapter are all swappable.
use crate::core_api::*;
use crate::platform::*;
use std::sync::Arc;
use std::time::Instant;

pub trait TextIo: Injector + SelectionReader {}
impl<T: Injector + SelectionReader> TextIo for T {}

pub struct App {
    pub relay: Arc<dyn Relay>,
    pub dictation: Box<dyn Dictation>,
    pub audio: Box<dyn AudioSource>,
    pub io: Box<dyn TextIo>,
    pub appctx: Box<dyn AppContext>,
    pub hud: Box<dyn Hud>,
    pub history: Arc<dyn History>,
    pub styles: Arc<dyn StyleMap>,
    pub dictionary: Vec<String>,
    pub edit_on_selection: bool,
    state: Option<Recording>,
    pub hide_at: Option<Instant>,
}

struct Recording { app_key: String, style: String, selection: Option<String> }

#[derive(Debug, PartialEq)]
pub enum Outcome { Inserted(String), Replaced(String), Empty, Cancelled, Failed(String) }

impl App {
    #[allow(clippy::too_many_arguments)]
    pub fn new(relay: Arc<dyn Relay>, dictation: Box<dyn Dictation>, audio: Box<dyn AudioSource>,
               io: Box<dyn TextIo>, appctx: Box<dyn AppContext>, hud: Box<dyn Hud>,
               history: Arc<dyn History>, styles: Arc<dyn StyleMap>, dictionary: Vec<String>,
               edit_on_selection: bool) -> Self {
        App { relay, dictation, audio, io, appctx, hud, history, styles, dictionary,
              edit_on_selection, state: None, hide_at: None }
    }

    pub fn on_press(&mut self) {
        if self.state.is_some() { return; }
        let app_key = self.appctx.foreground_app();
        let style = self.styles.style_for(&app_key);
        // begin() pre-connects the relay (ping) and opens the VAD/ASR session.
        let sink = match self.dictation.begin(&style, &self.dictionary) {
            Ok(s) => s,
            Err(e) => { self.show_error(&e); return; }
        };
        if let Err(e) = self.audio.start(sink) {
            self.dictation.cancel();
            self.show_error(&format!("麦克风不可用：{e}"));
            return;
        }
        self.hide_at = None;
        self.hud.show(HudState::Listening);
        self.state = Some(Recording { app_key, style, selection: None });
    }

    pub fn on_cancel(&mut self) -> Outcome {
        if self.state.take().is_some() { self.audio.stop(); self.dictation.cancel(); }
        self.hud.show(HudState::Hidden);
        Outcome::Cancelled
    }

    pub fn on_release(&mut self) -> Outcome {
        let Some(mut rec) = self.state.take() else { return Outcome::Empty };
        let t0 = Instant::now();
        self.audio.stop();
        // Selection is probed after the hotkey is up: a Ctrl+C probe sent while
        // the (Alt) hotkey is still held would arrive as Ctrl+Alt+C.
        if self.edit_on_selection { rec.selection = self.io.selection(&rec.app_key); }
        self.hud.show(HudState::Processing);
        let d = match self.dictation.finish() {
            Ok(d) => d,
            Err(e) => return self.fail("识别失败", &e, ""),
        };
        let raw = d.raw.clone();
        if raw.trim().is_empty() { self.hud.show(HudState::Hidden); return Outcome::Empty; }
        let t_asr = t0.elapsed();
        let style = rec.style.clone();
        let result = match &rec.selection {
            Some(sel) => self.relay.edit(sel, &raw),
            None => d.cleaned.clone().unwrap_or(Ok(raw.clone())),
        };
        match result {
            Ok(text) if text.trim().is_empty() => {
                self.history.record(&raw, Some(""), &rec.app_key);
                self.hud.show(HudState::Hidden);
                Outcome::Empty
            }
            Ok(text) => {
                if let Err(e) = self.io.insert(&text, &rec.app_key) {
                    return self.fail("写入失败", &e, &raw);
                }
                eprintln!("[latency] release→recognized+cleaned={}ms (asr decode {}ms, {} seg) release→insert={}ms app={} style={}",
                    t_asr.as_millis(), d.asr_ms, d.segments, t0.elapsed().as_millis(), rec.app_key, style);
                eprintln!("[text] raw={raw} | final={text}");
                self.history.record(&raw, Some(&text), &rec.app_key);
                self.hud.show(HudState::Done);
                self.hide_at = Some(Instant::now() + std::time::Duration::from_millis(800));
                if rec.selection.is_some() { Outcome::Replaced(text) } else { Outcome::Inserted(text) }
            }
            Err(e) => {
                eprintln!("[relay] {e}");
                self.history.record(&raw, None, &rec.app_key); // raw text kept in history
                self.hud.show(HudState::Error(e.user_message().to_string()));
                self.hide_at = Some(Instant::now() + std::time::Duration::from_millis(2500));
                Outcome::Failed(e.user_message().to_string())
            }
        }
    }

    fn show_error(&mut self, msg: &str) {
        eprintln!("[error] {msg}");
        self.hud.show(HudState::Error(msg.to_string()));
        self.hide_at = Some(Instant::now() + std::time::Duration::from_millis(2500));
    }

    fn fail(&mut self, msg: &str, detail: &str, raw: &str) -> Outcome {
        eprintln!("[error] {msg}: {detail}");
        if !raw.is_empty() { self.history.record(raw, None, ""); }
        self.hud.show(HudState::Error(msg.to_string()));
        self.hide_at = Some(Instant::now() + std::time::Duration::from_millis(2500));
        Outcome::Failed(msg.to_string())
    }

    pub fn tick(&mut self) {
        if let Some(t) = self.hide_at { if Instant::now() >= t { self.hide_at = None; self.hud.show(HudState::Hidden); } }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct FakeRelay { fail: Option<RelayError>, pings: Mutex<u32> }
    impl Relay for FakeRelay {
        fn ping(&self) -> Result<(), RelayError> { *self.pings.lock().unwrap() += 1; Ok(()) }
        fn me(&self) -> Result<String, RelayError> { Ok("u/d".into()) }
        fn clean_session(&self, s: &[Segment], style: &str, _d: &[String], _f: &mut dyn FnMut(&str)) -> Result<String, RelayError> {
            if let Some(e) = &self.fail { return Err(e.clone()); }
            Ok(format!("[{style}]{}", s.iter().map(|x| x.transcript.clone()).collect::<String>()))
        }
        fn edit(&self, sel: &str, ins: &str) -> Result<String, RelayError> { Ok(format!("{sel}<{ins}>")) }
    }
    /// Fake dictation: recognizes `segs`, cleans via the fake relay.
    struct Dict { segs: Vec<Segment>, relay: Arc<FakeRelay>, style: String }
    impl Dictation for Dict {
        fn begin(&mut self, style: &str, _: &[String]) -> Result<PcmSink, String> { self.style = style.into(); let _ = self.relay.ping(); Ok(Box::new(|_| {})) }
        fn finish(&mut self) -> Result<DictationResult, String> {
            let raw: String = self.segs.iter().map(|s| s.transcript.clone()).collect();
            let cleaned = if raw.is_empty() { None } else { Some(self.relay.clean_session(&self.segs, &self.style, &[], &mut |_| {})) };
            Ok(DictationResult { raw, cleaned, asr_ms: 0, segments: self.segs.len() as u32 })
        }
        fn cancel(&mut self) {}
    }
    struct Aud; impl AudioSource for Aud { fn start(&mut self, _: PcmSink) -> Result<(), String> { Ok(()) } fn stop(&mut self) {} }
    #[derive(Clone, Default)] struct Io { out: Arc<Mutex<Vec<String>>>, sel: Option<String> }
    impl Injector for Io { fn insert(&mut self, t: &str, _: &str) -> Result<(), String> { self.out.lock().unwrap().push(t.into()); Ok(()) } }
    impl SelectionReader for Io { fn selection(&mut self, _: &str) -> Option<String> { self.sel.clone() } }
    struct Ctx; impl AppContext for Ctx { fn foreground_app(&mut self) -> String { "xterm/XTerm".into() } }
    #[derive(Clone, Default)] struct H(Arc<Mutex<Vec<HudState>>>);
    impl Hud for H { fn show(&mut self, s: HudState) { self.0.lock().unwrap().push(s) } }
    struct Hist; impl History for Hist { fn record(&self, _: &str, _: Option<&str>, _: &str) {} }

    fn mk(fail: Option<RelayError>, sel: Option<String>, segs: Vec<Segment>) -> (App, Io, H) {
        let io = Io { sel, ..Default::default() }; let h = H::default();
        let relay = Arc::new(FakeRelay { fail, pings: Mutex::new(0) });
        let app = App::new(relay.clone(), Box::new(Dict { segs, relay, style: String::new() }), Box::new(Aud),
            Box::new(io.clone()), Box::new(Ctx), Box::new(h.clone()), Arc::new(Hist),
            Arc::new(crate::core_stub::config::Config::default()), vec![], true);
        (app, io, h)
    }
    fn seg(t: &str) -> Vec<Segment> { vec![Segment { seq: 0, transcript: t.into(), is_final: true }] }

    #[test] fn insert_flow_uses_style() {
        let (mut a, io, h) = mk(None, None, seg("你好"));
        a.on_press();
        assert_eq!(a.on_release(), Outcome::Inserted("[code]你好".into()));
        assert_eq!(io.out.lock().unwrap()[0], "[code]你好");
        assert_eq!(h.0.lock().unwrap()[..], [HudState::Listening, HudState::Processing, HudState::Done]);
    }
    #[test] fn offline_shows_needs_network_and_inserts_nothing() {
        let (mut a, io, h) = mk(Some(RelayError::Offline("x".into())), None, seg("你好"));
        a.on_press();
        assert_eq!(a.on_release(), Outcome::Failed("需要联网".into()));
        assert!(io.out.lock().unwrap().is_empty());
        assert_eq!(h.0.lock().unwrap().last(), Some(&HudState::Error("需要联网".into())));
    }
    #[test] fn selection_means_edit() {
        let (mut a, io, _) = mk(None, Some("原文".into()), seg("改礼貌点"));
        a.on_press();
        assert_eq!(a.on_release(), Outcome::Replaced("原文<改礼貌点>".into()));
        assert_eq!(io.out.lock().unwrap()[0], "原文<改礼貌点>");
    }
    #[test] fn cancel_and_empty() {
        let (mut a, io, _) = mk(None, None, seg("你好"));
        a.on_press(); assert_eq!(a.on_cancel(), Outcome::Cancelled);
        assert_eq!(a.on_release(), Outcome::Empty);
        let (mut b, _, _) = mk(None, None, vec![]);
        b.on_press(); assert_eq!(b.on_release(), Outcome::Empty);
        assert!(io.out.lock().unwrap().is_empty());
    }
}
