//! Saycribe 共享核心。平台层负责录音、热键、注入、UI；core 只接收 16kHz 单声道 f32 PCM。
//! 详见 docs/识别接口.md。
pub mod error;
pub mod paths;
pub mod config;
pub mod token;
pub mod relay;
pub mod history;
pub mod dictionary;
pub mod tone;
pub mod models;
#[cfg(feature = "asr")]
pub mod asr;
#[cfg(feature = "asr")]
pub mod vad;
#[cfg(feature = "asr")]
pub use vad::VadConfig;
#[cfg(feature = "asr")]
pub mod pipeline;
#[cfg(feature = "asr")]
pub mod ffi;

pub use error::{CoreError, RelayErrorKind, Result};

/// 平台标识，随 token 与请求头 `X-Saycribe-Platform` 上报。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Platform { Mac, Windows, Linux, Ios, Android }

impl Platform {
    pub fn as_str(&self) -> &'static str {
        match self { Platform::Mac => "mac", Platform::Windows => "windows", Platform::Linux => "linux", Platform::Ios => "ios", Platform::Android => "android" }
    }
    /// 当前编译目标对应的平台。
    pub fn current() -> Platform {
        if cfg!(target_os = "windows") { Platform::Windows }
        else if cfg!(target_os = "macos") { Platform::Mac }
        else if cfg!(target_os = "ios") { Platform::Ios }
        else if cfg!(target_os = "android") { Platform::Android }
        else { Platform::Linux }
    }
}

/// core 要求的采样率。平台层录音后需重采样到 16kHz 单声道 f32 [-1,1]。
pub const SAMPLE_RATE: u32 = 16_000;
