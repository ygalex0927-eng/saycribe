//! 中转客户端（协议见 docs/中转接口.md）。阻塞接口 + 非阻塞（后台线程 + 回调）+ 流式 SSE 回调。
//! ureq Agent 复用连接（keep-alive）；按下热键时调 `warm_up()` 预连接。
use crate::{error::{CoreError, RelayErrorKind}, token::DeviceToken, Result};
use serde::{Deserialize, Serialize};
use std::io::BufRead;
use std::sync::Arc;
use std::time::Duration;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Usage { #[serde(default)] pub prompt_tokens: u64, #[serde(default)] pub completion_tokens: u64, #[serde(default)] pub total_tokens: u64, #[serde(default)] pub cache_hit_tokens: u64 }

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RelayResponse {
    pub text: String,
    #[serde(default)] pub session_id: Option<String>,
    #[serde(default)] pub seq: Option<u32>,
    #[serde(default)] pub model: Option<String>,
    #[serde(default)] pub prompt_version: Option<String>,
    #[serde(default)] pub usage: Usage,
    #[serde(default)] pub timing: serde_json::Value,
    /// 客户端测得的往返耗时
    #[serde(skip)] pub client_ms: u64,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct SegmentMeta {
    #[serde(skip_serializing_if = "Option::is_none")] pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")] pub seq: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")] pub r#final: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
pub enum RelayRequest {
    Clean { transcript: String, #[serde(skip_serializing_if = "Option::is_none")] style: Option<String>, #[serde(skip_serializing_if = "Vec::is_empty")] dictionary: Vec<String>, #[serde(skip_serializing_if = "Option::is_none")] context: Option<String>, #[serde(flatten)] meta: SegmentMeta },
    Edit { selection: String, instruction: String },
    Translate { transcript: String, direction: String, #[serde(skip_serializing_if = "Option::is_none")] style: Option<String>, #[serde(skip_serializing_if = "Vec::is_empty")] dictionary: Vec<String> },
    Interpret { transcript: String, #[serde(skip_serializing_if = "Vec::is_empty")] context: Vec<String>, #[serde(skip_serializing_if = "Vec::is_empty")] dictionary: Vec<String> },
}

impl RelayRequest {
    pub fn clean(transcript: impl Into<String>, style: Option<&str>, dictionary: Vec<String>) -> Self {
        RelayRequest::Clean { transcript: transcript.into(), style: style.map(Into::into), dictionary, context: None, meta: SegmentMeta::default() }
    }
    fn path(&self) -> &'static str {
        match self { RelayRequest::Clean { .. } => "/v1/clean", RelayRequest::Edit { .. } => "/v1/edit", RelayRequest::Translate { .. } => "/v1/translate", RelayRequest::Interpret { .. } => "/v1/interpret" }
    }
    fn char_len(&self) -> usize {
        match self { RelayRequest::Clean { transcript, .. } | RelayRequest::Translate { transcript, .. } | RelayRequest::Interpret { transcript, .. } => transcript.chars().count(), RelayRequest::Edit { selection, .. } => selection.chars().count() }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Me { pub token_id: String, pub user: String, pub device: String, /// mac/windows/linux/ios/android（旧 token 可能没有）
    #[serde(default)] pub platform: Option<String> }

#[derive(Clone)]
pub struct RelayClient { inner: Arc<Inner> }
struct Inner { base: String, token: Option<DeviceToken>, agent: ureq::Agent }

impl RelayClient {
    pub fn new(base_url: &str, token: Option<DeviceToken>) -> Self {
        let agent = ureq::AgentBuilder::new().timeout_connect(Duration::from_secs(3)).max_idle_connections_per_host(4).user_agent(concat!("saycribe-core/", env!("CARGO_PKG_VERSION"))).build();
        RelayClient { inner: Arc::new(Inner { base: base_url.trim_end_matches('/').to_string(), token, agent }) }
    }
    pub fn base_url(&self) -> &str { &self.inner.base }

    fn req(&self, method: &str, path: &str, timeout: Duration) -> ureq::Request {
        let mut r = self.inner.agent.request(method, &format!("{}{}", self.inner.base, path)).timeout(timeout);
        if let Some(t) = &self.inner.token { r = r.set("Authorization", &format!("Bearer {}", t.token)).set("X-Saycribe-Platform", t.platform.as_str()); }
        r
    }

    /// 预连接：按下热键时调用（后台线程，不阻塞），松开时 TCP/TLS 已就绪。
    pub fn warm_up(&self) { let c = self.clone(); std::thread::spawn(move || { let _ = c.ping(); }); }
    pub fn ping(&self) -> Result<()> { self.req("GET", "/v1/ping", Duration::from_secs(4)).call().map_err(classify)?; Ok(()) }
    pub fn me(&self) -> Result<Me> { Ok(self.req("GET", "/v1/me", Duration::from_secs(5)).call().map_err(classify)?.into_json()?) }

    /// 协议建议整体超时：4 + 字数×0.02 秒
    pub fn timeout_for(chars: usize) -> Duration { Duration::from_millis(4000 + chars as u64 * 20) }

    /// 阻塞调用（非流式），502/504 自动重试 1 次。
    pub fn call(&self, req: &RelayRequest) -> Result<RelayResponse> {
        match self.call_once(req) {
            Err(e) if e.relay_kind().map(|k| k.retryable()).unwrap_or(false) => self.call_once(req),
            r => r,
        }
    }
    fn call_once(&self, req: &RelayRequest) -> Result<RelayResponse> {
        let t0 = std::time::Instant::now();
        let resp = self.req("POST", req.path(), Self::timeout_for(req.char_len())).send_json(req).map_err(classify)?;
        let mut r: RelayResponse = resp.into_json().map_err(io_classify)?;
        r.client_ms = t0.elapsed().as_millis() as u64;
        Ok(r)
    }

    /// 阻塞流式：每个 delta 回调一次，返回 done 的完整结果。
    pub fn call_stream(&self, req: &RelayRequest, mut on_delta: impl FnMut(&str)) -> Result<RelayResponse> {
        let t0 = std::time::Instant::now();
        let mut body = serde_json::to_value(req)?; body["stream"] = true.into();
        let resp = self.req("POST", req.path(), Self::timeout_for(req.char_len()) + Duration::from_secs(10)).send_json(body).map_err(classify)?;
        let reader = std::io::BufReader::new(resp.into_reader());
        let mut event = String::new();
        for line in reader.lines() {
            let line = line.map_err(io_classify)?;
            if let Some(e) = line.strip_prefix("event:") { event = e.trim().to_string(); continue; }
            let Some(data) = line.strip_prefix("data:") else { continue };
            let v: serde_json::Value = serde_json::from_str(data.trim())?;
            match event.as_str() {
                "delta" => on_delta(v["text"].as_str().unwrap_or("")),
                "done" => { let mut r: RelayResponse = serde_json::from_value(v)?; r.client_ms = t0.elapsed().as_millis() as u64; return Ok(r); }
                "error" => { let code = v["error"]["code"].as_str().unwrap_or("").to_string(); return Err(CoreError::Relay { kind: kind_from_code(&code, 0), message: v["error"]["message"].as_str().unwrap_or("").into(), code: Some(code) }); }
                _ => {}
            }
        }
        Err(CoreError::Relay { kind: RelayErrorKind::Upstream, code: None, message: "流提前结束".into() })
    }

    /// 非阻塞：后台线程执行，完成时回调。返回 JoinHandle 便于平台层需要时 join。
    pub fn call_async(&self, req: RelayRequest, done: impl FnOnce(Result<RelayResponse>) + Send + 'static) -> std::thread::JoinHandle<()> {
        let c = self.clone(); std::thread::spawn(move || done(c.call(&req)))
    }
    /// 非阻塞流式。
    pub fn call_stream_async(&self, req: RelayRequest, on_delta: impl FnMut(&str) + Send + 'static, done: impl FnOnce(Result<RelayResponse>) + Send + 'static) -> std::thread::JoinHandle<()> {
        let c = self.clone(); std::thread::spawn(move || done(c.call_stream(&req, on_delta)))
    }
}

fn kind_from_code(code: &str, status: u16) -> RelayErrorKind {
    match (code, status) {
        ("unauthorized", _) | (_, 401) => RelayErrorKind::Unauthorized,
        ("revoked", _) | (_, 403) => RelayErrorKind::Revoked,
        ("rate_limited", _) | (_, 429) => RelayErrorKind::RateLimited,
        ("upstream_timeout", _) | (_, 504) => RelayErrorKind::Timeout,
        ("upstream_error", _) | ("unavailable", _) | (_, 502) | (_, 503) | (_, 500) => RelayErrorKind::Upstream,
        _ => RelayErrorKind::BadRequest,
    }
}

fn io_classify(e: std::io::Error) -> CoreError {
    let kind = if matches!(e.kind(), std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock) { RelayErrorKind::Timeout } else { RelayErrorKind::Offline };
    CoreError::Relay { kind, code: None, message: e.to_string() }
}

/// 把 ureq 错误归类为 RelayErrorKind。
pub fn classify(e: ureq::Error) -> CoreError {
    match e {
        ureq::Error::Status(status, resp) => {
            let v: serde_json::Value = resp.into_json().unwrap_or_default();
            let code = v["error"]["code"].as_str().unwrap_or("").to_string();
            CoreError::Relay { kind: kind_from_code(&code, status), message: v["error"]["message"].as_str().unwrap_or("").to_string(), code: if code.is_empty() { None } else { Some(code) } }
        }
        ureq::Error::Transport(t) => {
            let msg = t.to_string();
            let timeout = matches!(t.kind(), ureq::ErrorKind::Io) && (msg.contains("timed out") || msg.contains("Timeout") || msg.contains("超时"));
            // 连接阶段超时（connect 3s）视为断网，读超时视为 Timeout
            let connect = matches!(t.kind(), ureq::ErrorKind::Dns | ureq::ErrorKind::ConnectionFailed | ureq::ErrorKind::ProxyConnect);
            let kind = if connect { RelayErrorKind::Offline } else if timeout { RelayErrorKind::Timeout } else { RelayErrorKind::Offline };
            CoreError::Relay { kind, code: None, message: msg }
        }
    }
}
