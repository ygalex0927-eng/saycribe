//! STUB dictation, used when built without the `core` feature or when
//! $SAYCRIBE_STUB_TRANSCRIPT is set (segments separated by '|'), so the
//! platform flow can be tested without models or a microphone.
use crate::core_api::*;
use std::sync::Arc;

pub struct StubRecognizer;
impl Recognizer for StubRecognizer {
    fn recognize(&mut self, _pcm: &[f32]) -> Result<Vec<Segment>, String> {
        let t = std::env::var("SAYCRIBE_STUB_TRANSCRIPT").unwrap_or_default();
        let parts: Vec<&str> = t.split('|').filter(|s| !s.trim().is_empty()).collect();
        let n = parts.len();
        Ok(parts.into_iter().enumerate().map(|(i, s)| Segment {
            seq: i as u32, transcript: s.trim().to_string(), is_final: i + 1 == n,
        }).collect())
    }
}

/// Stub recognizer + linux HttpRelay clean_session.
pub struct StubDictation { relay: Arc<dyn Relay>, style: String, dictionary: Vec<String> }
impl StubDictation {
    pub fn new(relay: Arc<dyn Relay>) -> Self { StubDictation { relay, style: String::new(), dictionary: vec![] } }
}
impl Dictation for StubDictation {
    fn begin(&mut self, style: &str, dictionary: &[String]) -> Result<PcmSink, String> {
        self.style = style.into(); self.dictionary = dictionary.to_vec();
        let r = self.relay.clone();
        std::thread::spawn(move || { let _ = r.ping(); }); // pre-connect
        Ok(Box::new(|_| {}))
    }
    fn finish(&mut self) -> Result<DictationResult, String> {
        let segs = StubRecognizer.recognize(&[])?;
        let raw: String = segs.iter().map(|s| s.transcript.as_str()).collect();
        let n = segs.len() as u32;
        let cleaned = if raw.trim().is_empty() { None }
            else { Some(self.relay.clean_session(&segs, &self.style, &self.dictionary, &mut |_| {})) };
        Ok(DictationResult { raw, cleaned, asr_ms: 0, segments: n })
    }
    fn cancel(&mut self) {}
}
