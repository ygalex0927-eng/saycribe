//! 历史：JSONL 追加写；不保存开关；保留天数；导出 JSON/CSV/Markdown。
use crate::{paths::Paths, Result};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HistoryEntry {
    pub id: String,
    pub time: DateTime<Utc>,
    /// 原始识别文本
    pub raw: String,
    /// 整理后文本（断网/失败时为 None，原文仍保留）
    pub text: Option<String>,
    pub app: Option<String>,
    pub style: Option<String>,
    pub mode: Option<String>,
    pub audio_seconds: Option<f64>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub enum ExportFormat { Json, Csv, Markdown }

pub struct History { path: PathBuf, pub enabled: bool, pub retention_days: u32 }

impl History {
    pub fn open(paths: &Paths, enabled: bool, retention_days: u32) -> Self {
        History { path: paths.history_file(), enabled, retention_days }
    }
    pub fn append(&self, e: &HistoryEntry) -> Result<()> {
        if !self.enabled { return Ok(()); }
        if let Some(p) = self.path.parent() { std::fs::create_dir_all(p)?; }
        let mut f = std::fs::OpenOptions::new().create(true).append(true).open(&self.path)?;
        writeln!(f, "{}", serde_json::to_string(e)?)?;
        Ok(())
    }
    pub fn list(&self) -> Result<Vec<HistoryEntry>> {
        let s = match std::fs::read_to_string(&self.path) { Ok(s) => s, Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(vec![]), Err(e) => return Err(e.into()) };
        Ok(s.lines().filter_map(|l| serde_json::from_str(l).ok()).collect())
    }
    /// 删除超出保留天数的条目（0 = 永久）。返回删除数。
    pub fn prune(&self) -> Result<usize> {
        if self.retention_days == 0 { return Ok(0); }
        let cut = Utc::now() - Duration::days(self.retention_days as i64);
        let all = self.list()?; let keep: Vec<_> = all.iter().filter(|e| e.time >= cut).collect();
        let n = all.len() - keep.len();
        if n > 0 { self.rewrite(&keep)?; }
        Ok(n)
    }
    pub fn delete(&self, id: &str) -> Result<()> { let all = self.list()?; self.rewrite(&all.iter().filter(|e| e.id != id).collect::<Vec<_>>()) }
    pub fn clear(&self) -> Result<()> { match std::fs::remove_file(&self.path) { Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()), _ => Ok(()) } }
    fn rewrite(&self, es: &[&HistoryEntry]) -> Result<()> {
        let mut s = String::new(); for e in es { s.push_str(&serde_json::to_string(e)?); s.push('\n'); }
        crate::token::write_atomic(&self.path, s.as_bytes(), false)
    }
    pub fn export(&self, fmt: ExportFormat) -> Result<String> {
        let es = self.list()?;
        Ok(match fmt {
            ExportFormat::Json => serde_json::to_string_pretty(&es)?,
            ExportFormat::Csv => {
                let q = |s: &str| format!("\"{}\"", s.replace('"', "\"\""));
                let mut o = String::from("time,app,style,raw,text\n");
                for e in &es { o += &format!("{},{},{},{},{}\n", e.time.to_rfc3339(), q(e.app.as_deref().unwrap_or("")), q(e.style.as_deref().unwrap_or("")), q(&e.raw), q(e.text.as_deref().unwrap_or(""))); }
                o
            }
            ExportFormat::Markdown => {
                let mut o = String::from("# Saycribe 历史\n\n");
                for e in &es { o += &format!("## {}{}\n\n{}\n\n", e.time.format("%Y-%m-%d %H:%M"), e.app.as_ref().map(|a| format!(" · {a}")).unwrap_or_default(), e.text.as_deref().unwrap_or(&e.raw)); }
                o
            }
        })
    }
}

impl HistoryEntry {
    pub fn new(raw: impl Into<String>) -> Self {
        HistoryEntry { id: uuid::Uuid::new_v4().to_string(), time: Utc::now(), raw: raw.into(), text: None, app: None, style: None, mode: None, audio_seconds: None, error: None }
    }
}
