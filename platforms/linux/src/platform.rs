//! Platform-layer traits (Linux side) and display-server auto-detection.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayServer {
    X11,
    /// Native Wayland session. `xwayland` tells whether DISPLAY is also set.
    Wayland { xwayland: bool },
    None,
}

/// Pure detection from environment variables (testable).
/// Order: XDG_SESSION_TYPE, then WAYLAND_DISPLAY, then DISPLAY.
/// `SAYCRIBE_BACKEND=x11|wayland` overrides.
pub fn detect_with(get: &dyn Fn(&str) -> Option<String>) -> DisplayServer {
    let has = |k: &str| get(k).map(|v| !v.is_empty()).unwrap_or(false);
    let xw = has("DISPLAY");
    match get("SAYCRIBE_BACKEND").as_deref() {
        Some("x11") => return DisplayServer::X11,
        Some("wayland") => return DisplayServer::Wayland { xwayland: xw },
        _ => {}
    }
    match get("XDG_SESSION_TYPE").as_deref() {
        Some("x11") if xw => return DisplayServer::X11,
        Some("wayland") if has("WAYLAND_DISPLAY") => return DisplayServer::Wayland { xwayland: xw },
        _ => {}
    }
    if has("WAYLAND_DISPLAY") { return DisplayServer::Wayland { xwayland: xw }; }
    if xw { return DisplayServer::X11; }
    DisplayServer::None
}

pub fn detect() -> DisplayServer { detect_with(&|k| std::env::var(k).ok()) }

/// Writes text at the cursor of the focused app.
pub trait Injector {
    fn insert(&mut self, text: &str, app_key: &str) -> Result<(), String>;
}
/// Reads the current selection of the focused app.
pub trait SelectionReader {
    fn selection(&mut self, app_key: &str) -> Option<String>;
}
/// Foreground app identity (opaque key for StyleMap).
pub trait AppContext {
    fn foreground_app(&mut self) -> String;
}

#[derive(Debug, Clone, PartialEq)]
pub enum HudState { Hidden, Listening, Processing, Done, Error(String) }

pub trait Hud {
    fn show(&mut self, s: HudState);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyEvent { Pressed, Released, Cancelled }

#[cfg(test)]
mod tests {
    use super::*;
    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let v: Vec<(String, String)> = pairs.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect();
        move |k| v.iter().find(|(a, _)| a == k).map(|(_, b)| b.clone())
    }
    #[test]
    fn detection() {
        assert_eq!(detect_with(&env(&[("DISPLAY", ":0"), ("XDG_SESSION_TYPE", "x11")])), DisplayServer::X11);
        assert_eq!(detect_with(&env(&[("DISPLAY", ":0"), ("WAYLAND_DISPLAY", "wayland-0"), ("XDG_SESSION_TYPE", "wayland")])),
                   DisplayServer::Wayland { xwayland: true });
        assert_eq!(detect_with(&env(&[("WAYLAND_DISPLAY", "wayland-1")])), DisplayServer::Wayland { xwayland: false });
        assert_eq!(detect_with(&env(&[("DISPLAY", ":99")])), DisplayServer::X11);
        assert_eq!(detect_with(&env(&[("XDG_SESSION_TYPE", "tty")])), DisplayServer::None);
        assert_eq!(detect_with(&env(&[("DISPLAY", ":0"), ("WAYLAND_DISPLAY", "w"), ("SAYCRIBE_BACKEND", "x11")])), DisplayServer::X11);
        // WSLg: both set, session type usually unset → Wayland with XWayland
        assert_eq!(detect_with(&env(&[("DISPLAY", ":0"), ("WAYLAND_DISPLAY", "wayland-0")])), DisplayServer::Wayland { xwayland: true });
    }
}
