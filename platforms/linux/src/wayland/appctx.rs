//! Foreground app on Wayland.
//! wlroots/sway: sway IPC (`swaymsg -t get_tree`) → focused node app_id / X11 class.
//! GNOME: no public API → "wayland" (default style). KDE: future KWin DBus.
use crate::platform::AppContext;

pub struct WaylandAppContext;
impl WaylandAppContext {
    pub fn new() -> Self { Self }
}

/// Find the focused leaf in a sway tree JSON; returns lowercase app_id or class.
pub fn focused_app_from_tree(v: &serde_json::Value) -> Option<String> {
    if v.get("focused").and_then(|f| f.as_bool()) == Some(true) {
        let id = v.get("app_id").and_then(|a| a.as_str()).filter(|s| !s.is_empty())
            .or_else(|| v.pointer("/window_properties/class").and_then(|a| a.as_str()));
        if let Some(id) = id { return Some(id.to_lowercase()); }
    }
    for key in ["nodes", "floating_nodes"] {
        if let Some(arr) = v.get(key).and_then(|n| n.as_array()) {
            for n in arr { if let Some(r) = focused_app_from_tree(n) { return Some(r); } }
        }
    }
    None
}

fn sway_focused() -> Option<String> {
    std::env::var_os("SWAYSOCK")?;
    let o = std::process::Command::new("swaymsg").args(["-t", "get_tree", "-r"]).output().ok()?;
    if !o.status.success() { return None; }
    let v: serde_json::Value = serde_json::from_slice(&o.stdout).ok()?;
    focused_app_from_tree(&v)
}

impl AppContext for WaylandAppContext {
    fn foreground_app(&mut self) -> String {
        sway_focused().unwrap_or_else(|| "wayland".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sway_tree_focus() {
        let t: serde_json::Value = serde_json::from_str(r#"{"focused":false,"nodes":[{"focused":false,"nodes":[
            {"focused":false,"app_id":"firefox"},{"focused":true,"app_id":"foot"}]}],
            "floating_nodes":[]}"#).unwrap();
        assert_eq!(focused_app_from_tree(&t).as_deref(), Some("foot"));
        let x: serde_json::Value = serde_json::from_str(r#"{"nodes":[{"focused":true,"app_id":null,
            "window_properties":{"class":"Google-chrome"}}]}"#).unwrap();
        assert_eq!(focused_app_from_tree(&x).as_deref(), Some("google-chrome"));
    }
}
