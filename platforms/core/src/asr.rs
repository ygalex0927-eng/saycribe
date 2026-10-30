//! SenseVoice 离线识别（sherpa-onnx）。同一识别器不可并发（BUSY → CoreError::Asr 含 "BUSY"）。
use crate::{error::CoreError, Result};
use sherpa_onnx::{OfflineModelConfig, OfflineRecognizer, OfflineRecognizerConfig, OfflineSenseVoiceModelConfig};
use std::path::Path;
use std::sync::Mutex;

#[derive(Debug, Clone, Default)]
pub struct Transcript {
    pub text: String,
    /// SenseVoice 语言标签，如 "<|zh|>"；无法取得时为空
    pub lang: String,
    pub audio_seconds: f64,
    pub decode_ms: u64,
    pub start_sample: i64,
}

fn lang_from_tokens(tokens: &[String]) -> String {
    const KNOWN: &[&str] = &["<|zh|>", "<|en|>", "<|ja|>", "<|ko|>", "<|yue|>", "<|auto|>"];
    tokens.iter().find(|t| KNOWN.contains(&t.as_str())).cloned().unwrap_or_default()
}

pub struct Recognizer { inner: Mutex<OfflineRecognizer> }

impl Recognizer {
    /// model_dir 内需有 model.int8.onnx 与 tokens.txt；language: "auto"/"zh"/...；provider: "cpu"/"cuda"。
    pub fn new(model_dir: &Path, language: &str, threads: i32, provider: Option<&str>) -> Result<Self> {
        for f in ["model.int8.onnx", "tokens.txt"] {
            if !model_dir.join(f).exists() {
                return Err(CoreError::Model(format!("模型缺失: {}", model_dir.join(f).display())));
            }
        }
        let s = |p: &str| Some(model_dir.join(p).to_string_lossy().into_owned());
        let mut cfg = OfflineRecognizerConfig::default();
        cfg.model_config = OfflineModelConfig {
            sense_voice: OfflineSenseVoiceModelConfig {
                model: s("model.int8.onnx"),
                language: Some(if language.is_empty() { "auto".into() } else { language.into() }),
                use_itn: true,
            },
            tokens: s("tokens.txt"),
            num_threads: if threads <= 0 { 4 } else { threads },
            provider: Some(provider.unwrap_or("cpu").into()),
            ..Default::default()
        };
        let inner = OfflineRecognizer::create(&cfg)
            .ok_or_else(|| CoreError::Model(format!("无法加载 SenseVoice: {}", model_dir.display())))?;
        Ok(Recognizer { inner: Mutex::new(inner) })
    }

    /// 识别一段 16kHz 单声道 f32 PCM。上限 300 秒。
    pub fn transcribe(&self, pcm: &[f32]) -> Result<Transcript> {
        self.transcribe_at(pcm, 0)
    }

    pub fn transcribe_at(&self, pcm: &[f32], start_sample: i64) -> Result<Transcript> {
        if pcm.len() as f64 / crate::SAMPLE_RATE as f64 > 300.0 {
            return Err(CoreError::Asr("音频超过 300 秒，请用 VAD 分段".into()));
        }
        let Ok(inner) = self.inner.try_lock() else {
            return Err(CoreError::Asr("BUSY: 识别器正在使用".into()));
        };
        let t0 = std::time::Instant::now();
        let st = inner.create_stream();
        st.accept_waveform(crate::SAMPLE_RATE as i32, pcm);
        inner.decode(&st);
        let r = st.get_result().ok_or_else(|| CoreError::Asr("解码无结果".into()))?;
        Ok(Transcript {
            text: r.text.trim().to_string(),
            lang: lang_from_tokens(&r.tokens),
            audio_seconds: pcm.len() as f64 / crate::SAMPLE_RATE as f64,
            decode_ms: t0.elapsed().as_millis() as u64,
            start_sample,
        })
    }
}

/// 读 WAV（仅测试/CLI）。返回 (samples, sample_rate)。
pub fn read_wav(path: &Path) -> Result<(Vec<f32>, u32)> {
    let w = sherpa_onnx::Wave::read(&path.to_string_lossy())
        .ok_or_else(|| CoreError::Asr(format!("无法读取 {}", path.display())))?;
    Ok((w.samples().to_vec(), w.sample_rate() as u32))
}
