//! 标准目录：Linux XDG（~/.config/saycribe、~/.local/share/saycribe）、
//! Windows %APPDATA%\Saycribe\config / %LOCALAPPDATA%\Saycribe\data、macOS ~/Library/Application Support/com.saycribe.Saycribe。
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct Paths { pub config_dir: PathBuf, pub data_dir: PathBuf, pub cache_dir: PathBuf }

impl Paths {
    /// 平台标准目录。
    pub fn standard() -> Option<Paths> {
        let d = directories::ProjectDirs::from("com", "saycribe", "Saycribe")?;
        Some(Paths { config_dir: d.config_dir().into(), data_dir: d.data_local_dir().into(), cache_dir: d.cache_dir().into() })
    }
    /// 自定义根目录（测试/便携版）。
    pub fn under(root: &Path) -> Paths {
        Paths { config_dir: root.join("config"), data_dir: root.join("data"), cache_dir: root.join("cache") }
    }
    pub fn config_file(&self) -> PathBuf { self.config_dir.join("config.json") }
    pub fn token_file(&self) -> PathBuf { self.config_dir.join("token.json") }
    pub fn history_file(&self) -> PathBuf { self.data_dir.join("history.jsonl") }
    pub fn dictionary_file(&self) -> PathBuf { self.config_dir.join("dictionary.json") }
    pub fn models_dir(&self) -> PathBuf { self.data_dir.join("models") }
    pub fn ensure(&self) -> std::io::Result<()> {
        for d in [&self.config_dir, &self.data_dir, &self.cache_dir] { std::fs::create_dir_all(d)?; }
        Ok(())
    }
}
