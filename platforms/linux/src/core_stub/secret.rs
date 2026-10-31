//! Token storage: Secret Service via `secret-tool` (libsecret) when available,
//! else a 0600 file under $XDG_CONFIG_HOME/saycribe/token (WSL / bare WMs).
use crate::core_api::SecretStore;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

const ATTRS: [&str; 4] = ["service", "saycribe", "kind", "device-token"];

pub struct LinuxSecretStore { file: PathBuf, use_secret_tool: bool }

impl LinuxSecretStore {
    pub fn new(config_dir: PathBuf) -> Self {
        let has = Command::new("secret-tool").arg("--version").stdout(Stdio::null())
            .stderr(Stdio::null()).status().is_ok()
            && std::env::var("DBUS_SESSION_BUS_ADDRESS").is_ok();
        LinuxSecretStore { file: config_dir.join("token"), use_secret_tool: has }
    }
    pub fn file_only(config_dir: PathBuf) -> Self {
        LinuxSecretStore { file: config_dir.join("token"), use_secret_tool: false }
    }
}

impl SecretStore for LinuxSecretStore {
    fn get(&self) -> Option<String> {
        if let Ok(t) = std::env::var("SAYCRIBE_TOKEN") { return Some(t); }
        if self.use_secret_tool {
            if let Ok(o) = Command::new("secret-tool").arg("lookup").args(ATTRS).output() {
                let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if o.status.success() && !s.is_empty() { return Some(s); }
            }
        }
        std::fs::read_to_string(&self.file).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
    }
    fn set(&self, token: &str) -> Result<(), String> {
        if self.use_secret_tool {
            let mut c = Command::new("secret-tool").args(["store", "--label=Saycribe device token"])
                .args(ATTRS).stdin(Stdio::piped()).spawn().map_err(|e| e.to_string())?;
            c.stdin.take().unwrap().write_all(token.as_bytes()).map_err(|e| e.to_string())?;
            if c.wait().map_err(|e| e.to_string())?.success() { return Ok(()); }
        }
        use std::os::unix::fs::OpenOptionsExt;
        if let Some(p) = self.file.parent() { std::fs::create_dir_all(p).map_err(|e| e.to_string())?; }
        let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600)
            .open(&self.file).map_err(|e| e.to_string())?;
        f.write_all(token.as_bytes()).map_err(|e| e.to_string())
    }
    fn delete(&self) -> Result<(), String> {
        if self.use_secret_tool {
            let _ = Command::new("secret-tool").arg("clear").args(ATTRS).status();
        }
        match std::fs::remove_file(&self.file) {
            Ok(_) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn file_fallback_roundtrip_0600() {
        let d = std::env::temp_dir().join(format!("sc-secret-{}", std::process::id()));
        let s = LinuxSecretStore::file_only(d.clone());
        std::env::remove_var("SAYCRIBE_TOKEN");
        s.set("sct_abc").unwrap();
        assert_eq!(s.get().as_deref(), Some("sct_abc"));
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(std::fs::metadata(d.join("token")).unwrap().permissions().mode() & 0o777, 0o600);
        s.delete().unwrap();
        assert_eq!(s.get(), None);
        let _ = std::fs::remove_dir_all(d);
    }
}
