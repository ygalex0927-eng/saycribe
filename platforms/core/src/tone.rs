use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// App→语气 映射。键是平台给出的 App 标识字符串（大小写不敏感）：
/// Windows `code.exe`、mac `com.microsoft.VSCode`、Linux `code` (WM_CLASS / app_id)。
/// 值为语气 chat/email/code/notes。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct AppToneMap(pub BTreeMap<String, String>);

impl AppToneMap {
    pub fn with_defaults() -> Self {
        let mut m = BTreeMap::new();
        for (k, v) in [
            ("code.exe", "code"), ("cursor.exe", "code"), ("windowsterminal.exe", "code"), ("idea64.exe", "code"),
            ("com.microsoft.vscode", "code"), ("com.todesktop.230313mzl4w4u92", "code"), ("com.apple.terminal", "code"), ("code", "code"),
            ("wechat.exe", "chat"), ("weixin.exe", "chat"), ("slack.exe", "chat"), ("telegram.exe", "chat"), ("com.tencent.xinwechat", "chat"), ("slack", "chat"),
            ("outlook.exe", "email"), ("thunderbird.exe", "email"), ("com.apple.mail", "email"), ("thunderbird", "email"),
        ] { m.insert(k.into(), v.into()); }
        AppToneMap(m)
    }
    pub fn set(&mut self, app: &str, style: &str) { self.0.insert(app.to_lowercase(), style.into()); }
    pub fn remove(&mut self, app: &str) { self.0.remove(&app.to_lowercase()); }
    /// 查找语气；未命中返回 default。
    pub fn style_for<'a>(&'a self, app: &str, default: &'a str) -> &'a str {
        self.0.get(&app.to_lowercase()).map(|s| s.as_str()).unwrap_or(default)
    }
}
