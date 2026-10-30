//! 模型管理（docs/模型下载.md）：按文件 sha256 校验、HTTP Range 断点续传、
//! 多地址依次尝试（国内先 hf-mirror，再 huggingface，最后 GitHub 整包），
//! 下载到 `<文件>.part`，校验通过后才改名为正式文件。
//! 目录约定见 docs/识别接口.md：`models/<id>/...`，silero_vad.onnx 直接在 `models/`。
use crate::{error::CoreError, Result};
use sha2::{Digest, Sha256};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

/// 单个文件：相对 `dir(spec)` 的路径、大小、sha256、候选地址（按顺序尝试）。
#[derive(Debug, Clone)]
pub struct ModelFile { pub name: String, pub size: u64, pub sha256: String, pub urls: Vec<String> }

/// 整包兜底（GitHub release 只有 tar.bz2）：单文件地址都失败时使用。
#[derive(Debug, Clone)]
pub struct ModelArchive { pub size: u64, pub sha256: String, pub urls: Vec<String> }

#[derive(Debug, Clone)]
pub struct ModelSpec {
    /// 本地目录名；空串表示文件直接落在 models_dir 下
    pub id: String,
    pub files: Vec<ModelFile>,
    pub archive: Option<ModelArchive>,
}

pub const SENSE_VOICE_ID: &str = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09";

fn hf(file: &str) -> Vec<String> {
    ["https://hf-mirror.com", "https://huggingface.co"].iter()
        .map(|h| format!("{h}/csukuangfj/{SENSE_VOICE_ID}/resolve/main/{file}")).collect()
}

pub fn sense_voice() -> ModelSpec {
    ModelSpec {
        id: SENSE_VOICE_ID.into(),
        files: vec![
            ModelFile { name: "model.int8.onnx".into(), size: 237_115_547,
                sha256: "12ca1a2ae7ecf3e0019ef2822307ee0b5cadc9196569e379b4c4026f8205276d".into(), urls: hf("model.int8.onnx") },
            ModelFile { name: "tokens.txt".into(), size: 315_894,
                sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc".into(), urls: hf("tokens.txt") },
        ],
        archive: Some(ModelArchive { size: 165_783_878,
            sha256: "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63".into(),
            urls: vec![format!("https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{SENSE_VOICE_ID}.tar.bz2")] }),
    }
}

pub fn silero_vad() -> ModelSpec {
    ModelSpec {
        id: String::new(),
        files: vec![ModelFile { name: "silero_vad.onnx".into(), size: 643_854,
            sha256: "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6".into(),
            urls: vec!["https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx".into()] }],
        archive: None,
    }
}

pub struct ModelManager { root: PathBuf, agent: ureq::Agent }

impl ModelManager {
    pub fn new(models_dir: impl Into<PathBuf>) -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(std::time::Duration::from_secs(10))
            .timeout_read(std::time::Duration::from_secs(30)).build();
        Self { root: models_dir.into(), agent }
    }
    pub fn dir(&self, m: &ModelSpec) -> PathBuf {
        if m.id.is_empty() { self.root.clone() } else { self.root.join(&m.id) }
    }
    /// 只看文件存在且大小对；完整 sha 校验用 `verify`。
    pub fn is_installed(&self, m: &ModelSpec) -> bool {
        m.files.iter().all(|f| std::fs::metadata(self.dir(m).join(&f.name)).map(|md| md.len() == f.size).unwrap_or(false))
    }
    pub fn verify(&self, m: &ModelSpec) -> bool {
        m.files.iter().all(|f| sha256_file(&self.dir(m).join(&f.name)).map(|h| h == f.sha256).unwrap_or(false))
    }

    /// 确保已安装。progress(已下载, 总字节)，按整个 spec 累计。
    pub fn ensure(&self, m: &ModelSpec, mut progress: impl FnMut(u64, u64)) -> Result<PathBuf> {
        let dir = self.dir(m);
        if self.is_installed(m) { return Ok(dir); }
        std::fs::create_dir_all(&dir)?;
        let total: u64 = m.files.iter().map(|f| f.size).sum();
        let mut done = 0u64;
        let mut err = None;
        for f in &m.files {
            let dest = dir.join(&f.name);
            if std::fs::metadata(&dest).map(|md| md.len() == f.size).unwrap_or(false) { done += f.size; continue; }
            let base = done;
            match self.download(&f.urls, &dest, &f.sha256, |g, _| progress(base + g, total)) {
                Ok(()) => done += f.size,
                Err(e) => { err = Some(e); break; }
            }
        }
        if err.is_none() && self.is_installed(m) { return Ok(dir); }
        if let Some(a) = &m.archive {
            self.install_archive(m, a, |g, t| progress(g, t))?;
            if self.is_installed(m) { return Ok(dir); }
            return Err(CoreError::Model("整包解开后缺少必需文件".into()));
        }
        Err(err.unwrap_or_else(|| CoreError::Model("安装后缺少必需文件".into())))
    }

    fn install_archive(&self, m: &ModelSpec, a: &ModelArchive, progress: impl FnMut(u64, u64)) -> Result<()> {
        let tmp = self.root.join(format!("{}.tar.bz2", if m.id.is_empty() { "model" } else { &m.id }));
        self.download(&a.urls, &tmp, &a.sha256, progress)?;
        let staging = self.root.join(format!("{}.staging", m.id));
        let _ = std::fs::remove_dir_all(&staging);
        std::fs::create_dir_all(&staging)?;
        let r = tar::Archive::new(bzip2::read::BzDecoder::new(std::fs::File::open(&tmp)?)).unpack(&staging);
        let _ = std::fs::remove_file(&tmp);
        r?;
        let inner = single_subdir(&staging).unwrap_or(staging.clone());
        let dir = self.dir(m);
        std::fs::create_dir_all(&dir)?;
        for f in &m.files {
            let src = inner.join(&f.name);
            if sha256_file(&src)? != f.sha256 { let _ = std::fs::remove_dir_all(&staging); return Err(CoreError::Model(format!("整包内 {} sha256 不匹配", f.name))); }
            let dest = dir.join(&f.name);
            if let Some(p) = dest.parent() { std::fs::create_dir_all(p)?; }
            std::fs::rename(&src, &dest)?;
        }
        let _ = std::fs::remove_dir_all(&staging);
        Ok(())
    }

    /// 依次尝试 urls，下载到 `dest.part`（支持续传），sha256 对上才改名为 dest。
    pub fn download(&self, urls: &[String], dest: &Path, sha256: &str, mut progress: impl FnMut(u64, u64)) -> Result<()> {
        let part = part_path(dest);
        if let Some(p) = dest.parent() { std::fs::create_dir_all(p)?; }
        let mut errs: Vec<String> = vec![];
        let mut last = String::new();
        for url in urls {
            // 每个地址最多续传 3 次（网络中断后从 .part 末尾接着下）
            for _ in 0..3 {
                match self.fetch_once(url, &part, &mut progress) {
                    Ok(()) => {
                        let h = sha256_file(&part)?;
                        if h == sha256 { std::fs::rename(&part, dest)?; return Ok(()); }
                        let _ = std::fs::remove_file(&part);
                        last = format!("{url}: sha256 不匹配 {h}");
                        break; // 内容不对，换下一个地址
                    }
                    Err(Fetch::Fatal(e)) => { last = format!("{url}: {e}"); break; }
                    Err(Fetch::Retry(e)) => { last = format!("{url}: {e}"); }
                }
            }
            if !last.is_empty() { errs.push(std::mem::take(&mut last)); }
        }
        if errs.is_empty() { errs.push("没有可用地址".into()); }
        Err(CoreError::Model(format!("下载失败：{}", errs.join("；"))))
    }

    fn fetch_once(&self, url: &str, part: &Path, progress: &mut impl FnMut(u64, u64)) -> std::result::Result<(), Fetch> {
        let have = std::fs::metadata(part).map(|m| m.len()).unwrap_or(0);
        let mut req = self.agent.get(url);
        if have > 0 { req = req.set("Range", &format!("bytes={have}-")); }
        let resp = match req.call() {
            Ok(r) => r,
            Err(ureq::Error::Status(416, _)) => { let _ = std::fs::remove_file(part); return Err(Fetch::Retry("416，重新下载".into())); }
            Err(ureq::Error::Status(c, _)) => return Err(Fetch::Fatal(format!("HTTP {c}"))),
            Err(e) => return Err(Fetch::Retry(e.to_string())),
        };
        let resumed = resp.status() == 206 && have > 0;
        let len: Option<u64> = resp.header("Content-Length").and_then(|s| s.parse().ok());
        let start = if resumed { have } else { 0 };
        let total = len.map(|l| l + start).unwrap_or(0);
        let mut f = std::fs::OpenOptions::new().create(true).write(true).open(part).map_err(|e| Fetch::Fatal(e.to_string()))?;
        if resumed { f.seek(SeekFrom::Start(have)) } else { f.set_len(0).and_then(|_| f.seek(SeekFrom::Start(0))) }
            .map_err(|e| Fetch::Fatal(e.to_string()))?;
        let mut rd = resp.into_reader();
        let mut buf = vec![0u8; 1 << 16];
        let mut got = start;
        loop {
            let n = rd.read(&mut buf).map_err(|e| Fetch::Retry(e.to_string()))?;
            if n == 0 { break; }
            f.write_all(&buf[..n]).map_err(|e| Fetch::Fatal(e.to_string()))?;
            got += n as u64;
            progress(got, total);
        }
        f.flush().map_err(|e| Fetch::Fatal(e.to_string()))?;
        if let Some(l) = len { if got - start < l { return Err(Fetch::Retry(format!("连接中断：{}/{}", got, total))); } }
        Ok(())
    }
}

enum Fetch { Retry(String), Fatal(String) }

fn part_path(dest: &Path) -> PathBuf {
    let mut s = dest.as_os_str().to_owned(); s.push(".part"); PathBuf::from(s)
}

fn single_subdir(p: &Path) -> Option<PathBuf> {
    let v: Vec<_> = std::fs::read_dir(p).ok()?.filter_map(|e| e.ok()).collect();
    if v.len() == 1 && v[0].path().is_dir() { Some(v[0].path()) } else { None }
}

pub fn sha256_file(p: &Path) -> Result<String> {
    let mut f = std::fs::File::open(p)?;
    let mut h = Sha256::new();
    std::io::copy(&mut f, &mut h)?;
    Ok(hex::encode(h.finalize()))
}
