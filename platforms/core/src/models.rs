//! 模型管理：下载到标准目录 models/，校验 sha256，解包 .tar.bz2。
//! 约定见 docs/识别接口.md：SenseVoice 目录、silero_vad.onnx 直接在 models/。
use crate::{error::CoreError, Result};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct ModelSpec {
    /// 本地目录名；空串表示文件直接落在 models_dir 下（silero_vad.onnx）
    pub id: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub archive: bool,
    pub required: &'static [&'static str],
}

pub const SENSE_VOICE: ModelSpec = ModelSpec {
    id: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09",
    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2",
    sha256: "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63",
    archive: true,
    required: &["model.int8.onnx", "tokens.txt"],
};

pub const SILERO_VAD: ModelSpec = ModelSpec {
    id: "",
    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
    sha256: "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6",
    archive: false,
    required: &["silero_vad.onnx"],
};

pub struct ModelManager { root: PathBuf }

impl ModelManager {
    pub fn new(models_dir: impl Into<PathBuf>) -> Self { Self { root: models_dir.into() } }
    pub fn dir(&self, m: &ModelSpec) -> PathBuf {
        if m.id.is_empty() { self.root.clone() } else { self.root.join(m.id) }
    }
    pub fn is_installed(&self, m: &ModelSpec) -> bool {
        m.required.iter().all(|f| self.dir(m).join(f).exists())
    }

    /// 确保已安装；未安装则下载+校验+解包。progress(已下载, 总字节)。
    pub fn ensure(&self, m: &ModelSpec, mut progress: impl FnMut(u64, Option<u64>)) -> Result<PathBuf> {
        let dir = self.dir(m);
        if self.is_installed(m) { return Ok(dir); }
        std::fs::create_dir_all(&self.root)?;
        let file_name = m.url.rsplit('/').next().unwrap_or("model");
        let tmp = self.root.join(format!("{file_name}.part"));
        let resp = ureq::get(m.url).call().map_err(|e| CoreError::Model(format!("下载失败: {e}")))?;
        let total = resp.header("Content-Length").and_then(|s| s.parse().ok());
        let mut rd = resp.into_reader();
        let mut f = std::fs::File::create(&tmp)?;
        let mut h = Sha256::new();
        let mut buf = vec![0u8; 1 << 16];
        let mut got = 0u64;
        loop {
            let n = rd.read(&mut buf)?;
            if n == 0 { break; }
            h.update(&buf[..n]);
            f.write_all(&buf[..n])?;
            got += n as u64;
            progress(got, total);
        }
        drop(f);
        let digest = hex::encode(h.finalize());
        if digest != m.sha256 {
            let _ = std::fs::remove_file(&tmp);
            return Err(CoreError::Model(format!("sha256 不匹配: {digest}")));
        }
        if m.archive {
            let staging = self.root.join(format!("{}.staging", m.id));
            let _ = std::fs::remove_dir_all(&staging);
            std::fs::create_dir_all(&staging)?;
            tar::Archive::new(bzip2::read::BzDecoder::new(std::fs::File::open(&tmp)?)).unpack(&staging)?;
            std::fs::remove_file(&tmp)?;
            let inner = single_subdir(&staging).unwrap_or(staging.clone());
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::rename(&inner, &dir)?;
            let _ = std::fs::remove_dir_all(&staging);
        } else {
            // 单文件：直接放到 models_dir（或 id 子目录）
            std::fs::create_dir_all(&dir)?;
            let dest = dir.join(file_name);
            let _ = std::fs::remove_file(&dest);
            std::fs::rename(&tmp, &dest)?;
        }
        if !self.is_installed(m) {
            return Err(CoreError::Model("安装后缺少必需文件".into()));
        }
        Ok(dir)
    }
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
