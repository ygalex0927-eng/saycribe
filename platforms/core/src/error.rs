use thiserror::Error;

/// 中转错误分类（平台层据此决定 HUD 文案与是否重试）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelayErrorKind {
    /// 网络错误/DNS/连接拒绝/连接超时 → HUD「需要联网」，不做本地兜底
    Offline,
    /// 401 token 缺失或无效
    Unauthorized,
    /// 403 token 已吊销
    Revoked,
    /// 429 限流
    RateLimited,
    /// 502 上游出错 / 503 维护
    Upstream,
    /// 504 或读超时
    Timeout,
    /// 400/413 等客户端问题
    BadRequest,
}

impl RelayErrorKind {
    /// 是否值得自动重试一次（协议：502/504 可重试 1 次）
    pub fn retryable(&self) -> bool { matches!(self, RelayErrorKind::Upstream | RelayErrorKind::Timeout) }
    /// 默认中文提示
    pub fn user_message(&self) -> &'static str {
        match self {
            RelayErrorKind::Offline => "需要联网",
            RelayErrorKind::Unauthorized | RelayErrorKind::Revoked => "请在设置里填写/重新获取 token",
            RelayErrorKind::RateLimited => "请求太频繁，请稍后再试",
            RelayErrorKind::Upstream => "整理服务暂时出错",
            RelayErrorKind::Timeout => "整理超时",
            RelayErrorKind::BadRequest => "请求无效",
        }
    }
}

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("中转错误 {kind:?}: {message}")]
    Relay { kind: RelayErrorKind, code: Option<String>, message: String },
    #[error("模型错误: {0}")]
    Model(String),
    #[error("识别错误: {0}")]
    Asr(String),
    #[error("IO: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("{0}")]
    Other(String),
}

impl CoreError {
    pub fn relay_kind(&self) -> Option<RelayErrorKind> {
        if let CoreError::Relay { kind, .. } = self { Some(*kind) } else { None }
    }
}

pub type Result<T> = std::result::Result<T, CoreError>;
