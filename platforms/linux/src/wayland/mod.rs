//! Wayland backend: wlroots (wtype / FIFO) + GNOME/KDE portals (ashpd).
//!
//! Verified: headless sway (clipboard, wtype paste, sway IPC, FIFO, Pulse E2E).
//! Portal path implemented; authorization dialogs need a real GNOME/KDE session
//! (or a headless portal that auto-approves).
pub mod appctx;
pub mod clipboard;
pub mod hotkey;
pub mod inject;
pub mod portal;

use inject::WaylandInjector;

/// Capabilities discovered at runtime (binaries + env + portal interfaces).
#[derive(Debug, Clone, Default)]
pub struct Capabilities {
    pub wayland_display: bool,
    pub wl_copy: bool,
    pub wl_paste: bool,
    pub wtype: bool,
    pub ydotool: bool,
    pub xclip: bool,
    pub portal_bus: bool,
    pub portal_remote_desktop: bool,
    pub portal_global_shortcuts: bool,
    pub portal_clipboard: bool,
}

pub fn probe() -> Capabilities {
    let has = |bin: &str| std::process::Command::new("sh").arg("-c")
        .arg(format!("command -v {bin} >/dev/null 2>&1")).status().map(|s| s.success()).unwrap_or(false);
    let bus = std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_some()
        || std::path::Path::new(&format!("/run/user/{}/bus", nix_uid())).exists();
    let mut c = Capabilities {
        wayland_display: std::env::var_os("WAYLAND_DISPLAY").map(|v| !v.is_empty()).unwrap_or(false),
        wl_copy: has("wl-copy"),
        wl_paste: has("wl-paste"),
        wtype: has("wtype"),
        ydotool: has("ydotool"),
        xclip: has("xclip"),
        portal_bus: bus,
        ..Default::default()
    };
    if bus {
        let p = portal::probe_interfaces();
        c.portal_remote_desktop = p.remote_desktop;
        c.portal_global_shortcuts = p.global_shortcuts;
        c.portal_clipboard = p.clipboard;
    }
    c
}

fn nix_uid() -> u32 {
    std::process::Command::new("id").arg("-u").output().ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| s.trim().parse().ok()).unwrap_or(1000)
}

pub fn open_injector(restore_ms: u64, is_terminal: Box<dyn Fn(&str) -> bool + Send>) -> Result<WaylandInjector, String> {
    WaylandInjector::new(restore_ms, is_terminal)
}

pub fn limits_report(c: &Capabilities) -> String {
    let mut lines = vec![format!("Wayland capabilities: {c:?}")];
    if !c.wayland_display { lines.push("无 WAYLAND_DISPLAY — 无法测剪贴板/注入".into()); }
    if c.wl_copy && c.wl_paste { lines.push("剪贴板：wl-copy/wl-paste".into()); }
    else { lines.push("剪贴板：缺 wl-clipboard".into()); }
    if c.xclip { lines.push("剪贴板兜底：xclip（XWayland，供 GNOME 无 data-control 时使用）".into()); }
    else { lines.push("剪贴板兜底：未装 xclip".into()); }
    if c.wtype { lines.push("wlroots 虚拟键盘：wtype 已安装".into()); }
    else { lines.push("wlroots 虚拟键盘：未装 wtype".into()); }
    if c.ydotool { lines.push("ydotool 兜底：已安装（需 ydotoold + uinput）".into()); }
    else { lines.push("ydotool 兜底：未安装".into()); }
    if c.portal_global_shortcuts {
        lines.push("GlobalShortcuts portal：接口可用（需用户授权；失败则 FIFO toggle）".into());
    } else {
        lines.push("GlobalShortcuts portal：不可用 → FIFO toggle".into());
    }
    if c.portal_remote_desktop {
        lines.push("RemoteDesktop portal：接口可用（restore_token 持久化；失败则 wtype/ydotool/键符）".into());
    } else {
        lines.push("RemoteDesktop portal：不可用".into());
    }
    lines.join("\n")
}
