//! Silero VAD 分段。默认：threshold 0.5、min_silence 0.45、min_speech 0.25、max_speech 12、buffer 120s。
use crate::{error::CoreError, Result};
use sherpa_onnx::{SileroVadModelConfig, VadModelConfig, VoiceActivityDetector};
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Segment { pub start: i64, pub samples: Vec<f32> }

#[derive(Debug, Clone)]
pub struct VadConfig {
    pub threshold: f32,
    pub min_silence: f32,
    pub min_speech: f32,
    pub max_speech: f32,
    pub buffer_sec: f32,
}
impl Default for VadConfig {
    fn default() -> Self {
        Self { threshold: 0.5, min_silence: 0.45, min_speech: 0.25, max_speech: 12.0, buffer_sec: 120.0 }
    }
}

pub struct Segmenter { vad: VoiceActivityDetector, pending: Vec<f32>, window: usize }

impl Segmenter {
    pub fn new(silero_model: &Path, min_silence: f32, max_speech: f32) -> Result<Self> {
        Self::with_config(silero_model, VadConfig { min_silence, max_speech, ..Default::default() })
    }
    pub fn with_config(silero_model: &Path, c: VadConfig) -> Result<Self> {
        if !silero_model.exists() {
            return Err(CoreError::Model(format!("模型缺失: {}", silero_model.display())));
        }
        let window = 512;
        let cfg = VadModelConfig {
            silero_vad: SileroVadModelConfig {
                model: Some(silero_model.to_string_lossy().into_owned()),
                threshold: c.threshold,
                min_silence_duration: c.min_silence,
                min_speech_duration: c.min_speech,
                window_size: window as i32,
                max_speech_duration: c.max_speech,
                ..Default::default()
            },
            sample_rate: crate::SAMPLE_RATE as i32,
            num_threads: 1,
            provider: Some("cpu".into()),
            debug: false,
            ..Default::default()
        };
        let vad = VoiceActivityDetector::create(&cfg, c.buffer_sec)
            .ok_or_else(|| CoreError::Model("无法加载 Silero VAD".into()))?;
        Ok(Segmenter { vad, pending: vec![], window })
    }
    pub fn push(&mut self, pcm: &[f32]) -> Vec<Segment> {
        self.pending.extend_from_slice(pcm);
        let n = self.pending.len() / self.window * self.window;
        for chunk in self.pending[..n].chunks(self.window) { self.vad.accept_waveform(chunk); }
        self.pending.drain(..n);
        self.drain()
    }
    pub fn finish(&mut self) -> Vec<Segment> {
        if !self.pending.is_empty() {
            let mut p = std::mem::take(&mut self.pending);
            p.resize(self.window, 0.0);
            self.vad.accept_waveform(&p);
        }
        self.vad.flush();
        self.drain()
    }
    pub fn speaking(&self) -> bool { self.vad.detected() }
    pub fn reset(&mut self) {
        self.pending.clear();
        self.vad.reset();
        self.vad.clear();
    }
    fn drain(&mut self) -> Vec<Segment> {
        let mut out = vec![];
        while !self.vad.is_empty() {
            if let Some(s) = self.vad.front() {
                out.push(Segment { start: s.start(), samples: s.samples().to_vec() });
            }
            self.vad.pop();
        }
        out
    }
}
