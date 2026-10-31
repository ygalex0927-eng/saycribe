//! Config file ($XDG_CONFIG_HOME/saycribe/config.json) + App→style map.
use crate::core_api::StyleMap;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

pub const DEFAULT_RELAY: &str = "https://saycribe-api.motomotos.com";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Config {
    pub relay_url: String,
    /// X keysym name of the hold-to-talk key.
    pub hotkey: String,
    /// Delay before restoring the previous clipboard after paste.
    pub clipboard_restore_ms: u64,
    /// WM_CLASS (lowercase, class or instance) → style (chat/email/code/notes).
    pub style_map: BTreeMap<String, String>,
    pub default_style: String,
    /// WM_CLASS values treated as terminals (paste with Ctrl+Shift+V).
    pub terminals: Vec<String>,
    pub dictionary: Vec<String>,
    pub save_history: bool,
    /// When PRIMARY has no fresh selection, probe with Ctrl+C (Ctrl+Shift+C in
    /// terminals). Note: some editors (VS Code) copy the whole line when
    /// nothing is selected; disable here or in that editor.
    pub selection_copy_fallback: bool,
}

impl Default for Config {
    fn default() -> Self {
        let sm = [
            ("xterm", "code"), ("xfce4-terminal", "code"), ("gnome-terminal-server", "code"), ("konsole", "code"),
            ("alacritty", "code"), ("kitty", "code"), ("code", "code"), ("jetbrains-idea", "code"),
            ("thunderbird", "email"), ("evolution", "email"),
            ("telegram-desktop", "chat"), ("wechat", "chat"), ("slack", "chat"), ("discord", "chat"),
            ("obsidian", "notes"),
        ];
        Config {
            relay_url: DEFAULT_RELAY.into(),
            hotkey: "Alt_R".into(),
            clipboard_restore_ms: 300,
            style_map: sm.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect(),
            default_style: "notes".into(),
            terminals: ["xterm", "uxterm", "gnome-terminal-server", "konsole", "alacritty", "kitty",
                "terminator", "xfce4-terminal", "tilix", "wezterm", "urxvt", "st-256color", "foot"]
                .iter().map(|s| s.to_string()).collect(),
            dictionary: vec![],
            save_history: true,
            selection_copy_fallback: true,
        }
    }
}

pub fn config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into())).join(".config"))
        .join("saycribe")
}
pub fn data_dir() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME").map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into())).join(".local/share"))
        .join("saycribe")
}

impl Config {
    pub fn load_from(path: &std::path::Path) -> Config {
        let mut c: Config = std::fs::read_to_string(path).ok()
            .and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
        if let Ok(u) = std::env::var("SAYCRIBE_RELAY_URL") { c.relay_url = u; }
        c
    }
    pub fn load() -> Config { Self::load_from(&config_dir().join("config.json")) }
    pub fn save_to(&self, path: &std::path::Path) -> std::io::Result<()> {
        if let Some(p) = path.parent() { std::fs::create_dir_all(p)?; }
        std::fs::write(path, serde_json::to_string_pretty(self).unwrap())
    }
    pub fn is_terminal(&self, app_key: &str) -> bool {
        app_key.split('/').any(|k| self.terminals.iter().any(|t| t.eq_ignore_ascii_case(k)))
    }
}

impl StyleMap for Config {
    /// app_key = "instance/class" from WM_CLASS; either part may match.
    fn style_for(&self, app_key: &str) -> String {
        for k in app_key.split('/') {
            if let Some(s) = self.style_map.get(&k.to_lowercase()) { return s.clone(); }
        }
        self.default_style.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn defaults_and_roundtrip() {
        let c = Config::default();
        assert_eq!(c.relay_url, DEFAULT_RELAY);
        assert_eq!(c.style_for("xterm/XTerm"), "code");
        assert_eq!(c.style_for("Navigator/firefox"), "notes");
        assert!(c.is_terminal("gnome-terminal-server/Gnome-terminal"));
        assert!(!c.is_terminal("gedit/Gedit"));
        let p = std::env::temp_dir().join(format!("sc-cfg-{}.json", std::process::id()));
        let mut c2 = c.clone(); c2.relay_url = "http://x".into();
        c2.save_to(&p).unwrap();
        std::env::remove_var("SAYCRIBE_RELAY_URL");
        assert_eq!(Config::load_from(&p), c2);
        std::fs::write(&p, r#"{"hotkey":"F9"}"#).unwrap();
        let c3 = Config::load_from(&p);
        assert_eq!(c3.hotkey, "F9"); assert_eq!(c3.relay_url, DEFAULT_RELAY);
        let _ = std::fs::remove_file(p);
    }
}
