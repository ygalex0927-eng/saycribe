//! 设备 token 存储。平台层可实现 TokenStore 接入系统钥匙串（mac Keychain、Windows 凭据管理器、Linux Secret Service），
//! core 提供 0600 文件兜底实现 FileTokenStore。
use crate::{Platform, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceToken {
    /// sct_...
    pub token: String,
    pub platform: Platform,
    pub device: String,
    #[serde(default)]
    pub token_id: Option<String>,
}

pub trait TokenStore: Send + Sync {
    fn read(&self) -> Result<Option<DeviceToken>>;
    fn write(&self, token: &DeviceToken) -> Result<()>;
    fn delete(&self) -> Result<()>;
}

/// 0600 权限 JSON 文件（Windows 上落在用户 AppData，依赖 ACL）。
pub struct FileTokenStore { path: PathBuf }
impl FileTokenStore { pub fn new(path: impl Into<PathBuf>) -> Self { Self { path: path.into() } } }

impl TokenStore for FileTokenStore {
    fn read(&self) -> Result<Option<DeviceToken>> {
        match std::fs::read(&self.path) {
            Ok(b) => Ok(Some(serde_json::from_slice(&b)?)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e.into()),
        }
    }
    fn write(&self, token: &DeviceToken) -> Result<()> {
        if let Some(p) = self.path.parent() { std::fs::create_dir_all(p)?; }
        write_atomic(&self.path, &serde_json::to_vec(token)?, true)
    }
    fn delete(&self) -> Result<()> {
        match std::fs::remove_file(&self.path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
            _ => Ok(()),
        }
    }
}

/// 原子写（临时文件+rename），secret=true 时 unix 上 0600。
pub(crate) fn write_atomic(path: &Path, data: &[u8], secret: bool) -> Result<()> {
    use std::io::Write;
    let tmp = path.with_extension("tmp");
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    if secret { use std::os::unix::fs::OpenOptionsExt; opts.mode(0o600); }
    let _ = secret;
    let mut f = opts.open(&tmp)?;
    f.write_all(data)?; f.sync_all()?; drop(f);
    std::fs::rename(&tmp, path)?;
    Ok(())
}
