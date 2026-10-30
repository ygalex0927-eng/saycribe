use crate::{paths::Paths, tone::AppToneMap, Result};
use serde::{Deserialize, Serialize};

pub const DEFAULT_RELAY_URL: &str = "https://saycribe-api.motomotos.com";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// 中转地址，可配置（之后会换域名）
    pub relay_url: String,
    /// 识别语言："auto" / "zh" / "en" / ...
    pub language: String,
    /// 默认语气 chat/email/code/notes
    pub default_style: String,
    /// App→语气 映射（键为字符串：Windows exe 名、mac bundle id、Linux WM_CLASS/app_id）
    pub app_tones: AppToneMap,
    /// 历史
    pub history_enabled: bool,
    pub history_retention_days: u32,
    /// VAD 分段停顿（秒）
    pub vad_min_silence: f32,
    /// 并发整理段数上限（协议 ≤3）
    pub max_concurrent_segments: usize,
    /// 识别线程数
    pub asr_threads: i32,
    /// 平台层扩展字段，core 原样保存
    pub platform_extra: serde_json::Map<String, serde_json::Value>,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            relay_url: DEFAULT_RELAY_URL.into(), language: "auto".into(), default_style: "notes".into(),
            app_tones: AppToneMap::default(), history_enabled: true, history_retention_days: 30,
            vad_min_silence: 0.45, max_concurrent_segments: 3, asr_threads: 4,
            platform_extra: Default::default(),
        }
    }
}

impl Config {
    pub fn load(paths: &Paths) -> Result<Config> {
        match std::fs::read(paths.config_file()) {
            Ok(b) => Ok(serde_json::from_slice(&b)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
            Err(e) => Err(e.into()),
        }
    }
    pub fn save(&self, paths: &Paths) -> Result<()> {
        std::fs::create_dir_all(&paths.config_dir)?;
        crate::token::write_atomic(&paths.config_file(), &serde_json::to_vec_pretty(self)?, false)?;
        Ok(())
    }
}
