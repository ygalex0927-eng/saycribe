//! Interfaces the Linux platform layer needs from the shared core
//! (`platforms/core`, owned by Saycribe·中转与Windows).
//!
//! Everything in this file is the *contract*; `core_stub/` is a thin
//! temporary implementation. When the real core crate lands, replace
//! `core_stub` with an adapter that implements these traits on top of it,
//! and nothing under `x11/`, `app.rs` or `ui` needs to change.

use std::fmt;

/// Relay errors, classified so the platform layer only maps them to UI text.
#[derive(Debug, Clone, PartialEq)]
pub enum RelayError {
    /// DNS / connect refused / TLS / socket error: show "需要联网", no local fallback.
    Offline(String),
    Unauthorized,  // 401
    Revoked,       // 403
    TooLarge,      // 413
    RateLimited,   // 429
    Upstream(String), // 502 / 504 (after one retry)
    Unavailable,   // 503
    BadRequest(String), // 400 – client bug
    Protocol(String),   // unexpected response shape
}

impl RelayError {
    /// User-facing HUD message (Chinese, as on Mac).
    pub fn user_message(&self) -> &'static str {
        match self {
            RelayError::Offline(_) => "需要联网",
            RelayError::Unauthorized | RelayError::Revoked => "请在设置里填写/重新获取 token",
            RelayError::TooLarge => "内容过长",
            RelayError::RateLimited => "请求太频繁，请稍后重试",
            RelayError::Upstream(_) => "整理服务出错，请重试",
            RelayError::Unavailable => "服务维护中",
            RelayError::BadRequest(_) | RelayError::Protocol(_) => "客户端错误",
        }
    }
}

impl fmt::Display for RelayError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

/// Result of one /v1/clean, /v1/edit … call.
#[derive(Debug, Clone, PartialEq)]
pub struct RelayText {
    pub text: String,
    pub seq: Option<u32>,
}

/// One segment of a (possibly long) recording.
#[derive(Debug, Clone)]
pub struct Segment {
    pub seq: u32,
    pub transcript: String,
    pub is_final: bool,
}

pub trait Relay: Send + Sync {
    /// Fire-and-forget pre-connect (called on hotkey *press*).
    fn ping(&self) -> Result<(), RelayError>;
    /// GET /v1/me – returns "user/device".
    fn me(&self) -> Result<String, RelayError>;
    /// Clean a list of segments of one session, merged in `seq` order.
    /// `on_delta` receives streamed partial text (may never be called).
    fn clean_session(
        &self,
        segments: &[Segment],
        style: &str,
        dictionary: &[String],
        on_delta: &mut dyn FnMut(&str),
    ) -> Result<String, RelayError>;
    /// Rewrite a selection with a spoken instruction.
    fn edit(&self, selection: &str, instruction: &str) -> Result<String, RelayError>;
}

/// Speech recognition (SenseVoice + Silero VAD in core).
/// Input: 16 kHz mono f32 PCM. Output: segments split at pauses.
pub trait Recognizer: Send {
    fn recognize(&mut self, pcm16k: &[f32]) -> Result<Vec<Segment>, String>;
}

/// Receives captured 16 kHz mono f32 PCM while the key is held.
pub type PcmSink = Box<dyn FnMut(&[f32]) + Send>;

/// Audio capture stays in the platform layer (PipeWire/Pulse on Linux);
/// core only consumes PCM, streamed into the dictation session as it arrives.
pub trait AudioSource: Send {
    fn start(&mut self, sink: PcmSink) -> Result<(), String>;
    /// Stops capture; returns after every captured sample has reached the sink.
    fn stop(&mut self);
}

/// Result of one hold-to-talk session.
#[derive(Debug, Clone)]
pub struct DictationResult {
    /// Recognized raw text (all segments, seq order).
    pub raw: String,
    /// Relay clean result (None when cleaning was not requested).
    pub cleaned: Option<Result<String, RelayError>>,
    /// Total SenseVoice decode time across segments.
    pub asr_ms: u64,
    pub segments: u32,
}

/// Recognition + clean session. Real impl: core `pipeline::Session`
/// (Silero VAD segments while recording, SenseVoice per segment, /v1/clean
/// per segment with ≤3 in flight, merged by seq).
pub trait Dictation: Send {
    /// Called on hotkey press (also pre-connects the relay). Returns the PCM sink.
    fn begin(&mut self, style: &str, dictionary: &[String]) -> Result<PcmSink, String>;
    /// Called after audio has stopped: flush VAD, wait for recognition + clean.
    fn finish(&mut self) -> Result<DictationResult, String>;
    fn cancel(&mut self);
}

/// Device-token storage. Linux: Secret Service (libsecret); fallback 0600 file.
pub trait SecretStore: Send + Sync {
    fn get(&self) -> Option<String>;
    fn set(&self, token: &str) -> Result<(), String>;
    fn delete(&self) -> Result<(), String>;
}

/// App → style mapping. Key is an opaque string (Linux: WM_CLASS class/instance).
pub trait StyleMap: Send + Sync {
    fn style_for(&self, app_key: &str) -> String;
}

/// History sink (core decides retention / "don't save").
pub trait History: Send + Sync {
    fn record(&self, raw: &str, final_text: Option<&str>, app_key: &str);
}
