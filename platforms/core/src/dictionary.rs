//! 用户词典：确认词随整理请求发送；候选词（从用户修改中学到）需确认后才生效。
use crate::{paths::Paths, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Dictionary { pub words: Vec<String>, pub candidates: Vec<String> }

impl Dictionary {
    pub fn load(paths: &Paths) -> Result<Self> {
        match std::fs::read(paths.dictionary_file()) {
            Ok(b) => Ok(serde_json::from_slice(&b)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(e.into()),
        }
    }
    pub fn save(&self, paths: &Paths) -> Result<()> {
        std::fs::create_dir_all(&paths.config_dir)?;
        crate::token::write_atomic(&paths.dictionary_file(), &serde_json::to_vec_pretty(self)?, false)
    }
    pub fn add(&mut self, w: &str) { let w = w.trim(); if !w.is_empty() && !self.words.iter().any(|x| x == w) { self.words.push(w.into()); } self.candidates.retain(|x| x != w); }
    pub fn remove(&mut self, w: &str) { self.words.retain(|x| x != w); }
    pub fn propose(&mut self, w: &str) { let w = w.trim(); if !w.is_empty() && !self.words.iter().any(|x| x == w) && !self.candidates.iter().any(|x| x == w) { self.candidates.push(w.into()); } }
    pub fn accept(&mut self, w: &str) { self.add(w); }
    pub fn reject(&mut self, w: &str) { self.candidates.retain(|x| x != w); }

    /// 对比「插入文本」与「用户改后文本」，提取新增的词作为候选（简单启发：新出现的 ASCII 词 / 2–8 字连续汉字串）。
    pub fn learn_from_edit(&mut self, inserted: &str, edited: &str) -> Vec<String> {
        let mut out = vec![];
        for tok in tokens(edited) { if !inserted.contains(&tok) && !self.words.contains(&tok) { self.propose(&tok); out.push(tok); } }
        out
    }
}

fn tokens(s: &str) -> Vec<String> {
    let mut v = vec![]; let mut cur = String::new(); let mut kind = 0u8;
    let flush = |cur: &mut String, kind: u8, v: &mut Vec<String>| {
        let n = cur.chars().count();
        if (kind == 1 && n >= 2) || (kind == 2 && (2..=8).contains(&n)) { v.push(cur.clone()); }
        cur.clear();
    };
    for c in s.chars() {
        let k = if c.is_ascii_alphanumeric() { 1 } else if ('\u{4e00}'..='\u{9fff}').contains(&c) { 2 } else { 0 };
        if k != kind { flush(&mut cur, kind, &mut v); kind = k; }
        if k != 0 { cur.push(c); }
    }
    flush(&mut cur, kind, &mut v); v
}
