//! Minimal JSONL history (stub; retention/export belong to core).
use crate::core_api::History;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

pub struct JsonlHistory { path: PathBuf, enabled: bool, lock: Mutex<()> }
impl JsonlHistory {
    pub fn new(path: PathBuf, enabled: bool) -> Self { JsonlHistory { path, enabled, lock: Mutex::new(()) } }
}
impl History for JsonlHistory {
    fn record(&self, raw: &str, final_text: Option<&str>, app_key: &str) {
        if !self.enabled { return; }
        let _g = self.lock.lock().unwrap();
        if let Some(p) = self.path.parent() { let _ = std::fs::create_dir_all(p); }
        let ts = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
        let line = serde_json::json!({"ts": ts, "raw": raw, "text": final_text, "app": app_key});
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&self.path) {
            let _ = writeln!(f, "{line}");
        }
    }
}
