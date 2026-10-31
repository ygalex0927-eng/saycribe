//! Clipboard: wl-copy/wl-paste (wlroots) → xclip via XWayland (GNOME/KDE without
//! wlr-data-control) → Err (caller may fall back to portal keysym typing).
use std::io::Write;
use std::process::{Command, Stdio};

pub fn set_clipboard(text: &str) -> Result<(), String> {
    if which("wl-copy").is_some() {
        match set_wl(text) {
            Ok(()) => {
                // Confirm the compositor accepted it (GNOME often accepts the
                // process exit but never stores the bytes — wl-paste then fails).
                for _ in 0..10 {
                    if get_wl().as_deref() == Some(text) { return Ok(()); }
                    std::thread::sleep(std::time::Duration::from_millis(20));
                }
                // Fall through to xclip.
            }
            Err(e) => eprintln!("[clipboard] wl-copy: {e}"),
        }
    }
    if which("xclip").is_some() && std::env::var_os("DISPLAY").is_some() {
        return set_xclip(text);
    }
    Err("无法写入剪贴板：wl-copy 不可用且无 XWayland/xclip（GNOME 可装 xclip，或走 portal 键符输入）".into())
}

pub fn get_clipboard() -> Option<String> {
    get_wl().or_else(get_xclip)
}

pub fn get_primary() -> Option<String> {
    get_wl_primary().or_else(get_xclip_primary)
}

fn which(bin: &str) -> Option<String> {
    let o = Command::new("sh").arg("-c").arg(format!("command -v {bin}")).output().ok()?;
    if o.status.success() { Some(String::from_utf8_lossy(&o.stdout).trim().into()) } else { None }
}

fn set_wl(text: &str) -> Result<(), String> {
    let mut c = Command::new("wl-copy").stdin(Stdio::piped()).spawn()
        .map_err(|e| format!("wl-copy: {e}"))?;
    c.stdin.take().ok_or("wl-copy stdin")?.write_all(text.as_bytes())
        .map_err(|e| format!("wl-copy write: {e}"))?;
    let st = c.wait().map_err(|e| e.to_string())?;
    if st.success() { Ok(()) } else { Err(format!("wl-copy exit {st}")) }
}

fn get_wl() -> Option<String> {
    let o = Command::new("wl-paste").arg("-n").output().ok()?;
    if !o.status.success() { return None; }
    let s = String::from_utf8_lossy(&o.stdout).to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn get_wl_primary() -> Option<String> {
    let o = Command::new("wl-paste").arg("-n").arg("--primary").output().ok()?;
    if !o.status.success() { return None; }
    let s = String::from_utf8_lossy(&o.stdout).to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn set_xclip(text: &str) -> Result<(), String> {
    let mut c = Command::new("xclip").args(["-selection", "clipboard"])
        .stdin(Stdio::piped()).spawn().map_err(|e| format!("xclip: {e}"))?;
    c.stdin.take().ok_or("xclip stdin")?.write_all(text.as_bytes())
        .map_err(|e| format!("xclip write: {e}"))?;
    let st = c.wait().map_err(|e| e.to_string())?;
    if st.success() { Ok(()) } else { Err(format!("xclip exit {st}")) }
}

fn get_xclip() -> Option<String> {
    let o = Command::new("xclip").args(["-selection", "clipboard", "-o"]).output().ok()?;
    if !o.status.success() { return None; }
    let s = String::from_utf8_lossy(&o.stdout).to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn get_xclip_primary() -> Option<String> {
    let o = Command::new("xclip").args(["-selection", "primary", "-o"]).output().ok()?;
    if !o.status.success() { return None; }
    let s = String::from_utf8_lossy(&o.stdout).to_string();
    if s.is_empty() { None } else { Some(s) }
}
