//! Paste injection: clipboard + (wtype | portal RemoteDesktop | ydotool | type | clipboard-only).
use super::clipboard;
use super::portal;
use crate::platform::{Injector, SelectionReader};
use std::process::Command;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasteMethod {
    Wtype,
    PortalPaste,
    PortalType,
    Ydotool,
    ClipboardOnly,
}

pub struct WaylandInjector {
    pub restore_ms: u64,
    is_terminal: Box<dyn Fn(&str) -> bool + Send>,
    pub last_method: Option<PasteMethod>,
    /// When true, insert() may succeed with ClipboardOnly (HUD should hint Ctrl+V).
    pub allow_clipboard_only: bool,
}

impl WaylandInjector {
    pub fn new(restore_ms: u64, is_terminal: Box<dyn Fn(&str) -> bool + Send>) -> Result<Self, String> {
        // Clipboard helpers are optional on GNOME (portal keysym typing works without them).
        Ok(Self { restore_ms, is_terminal, last_method: None, allow_clipboard_only: true })
    }
}

fn which(bin: &str) -> Option<String> {
    let o = Command::new("sh").arg("-c").arg(format!("command -v {bin}")).output().ok()?;
    if o.status.success() { Some(String::from_utf8_lossy(&o.stdout).trim().into()) } else { None }
}

fn paste_chord_wtype(terminal: bool) -> Result<(), String> {
    // wtype uses zwp_virtual_keyboard_v1 when the compositor advertises it.
    // Each wtype run uploads a fresh keymap; keys sent immediately can be lost
    // before the client applies it (~15% on sway). `-s 80` waits first → 40/40.
    let args: Vec<&str> = if terminal {
        vec!["-s","80","-M","ctrl","-M","shift","-k","v","-m","shift","-m","ctrl"]
    } else {
        vec!["-s","80","-M","ctrl","-k","v","-m","ctrl"]
    };
    let st = Command::new("wtype").args(&args).status().map_err(|e| e.to_string())?;
    if st.success() { Ok(()) } else { Err(format!("wtype exit {st}")) }
}

fn paste_chord_ydotool(terminal: bool) -> Result<(), String> {
    // key codes: LeftCtrl=29, LeftShift=42, V=47
    let seq = if terminal { "29:1 42:1 47:1 47:0 42:0 29:0" } else { "29:1 47:1 47:0 29:0" };
    let st = Command::new("ydotool").args(["key"]).args(seq.split_whitespace()).status()
        .map_err(|e| e.to_string())?;
    if st.success() { Ok(()) } else { Err(format!("ydotool exit {st}")) }
}

impl Injector for WaylandInjector {
    fn insert(&mut self, text: &str, app_key: &str) -> Result<(), String> {
        if text.is_empty() { return Ok(()); }
        let old = clipboard::get_clipboard();
        let clip_ok = match clipboard::set_clipboard(text) {
            Ok(()) => {
                for _ in 0..15 {
                    if clipboard::get_clipboard().as_deref() == Some(text) { break; }
                    std::thread::sleep(Duration::from_millis(20));
                }
                true
            }
            Err(e) => {
                eprintln!("[wayland] clipboard set failed: {e}");
                false
            }
        };
        let terminal = (self.is_terminal)(app_key);

        // Preference: wtype (wlroots) → portal paste chord → ydotool → portal type → clipboard-only
        let method = if clip_ok && which("wtype").is_some() {
            match paste_chord_wtype(terminal) {
                Ok(()) => PasteMethod::Wtype,
                Err(e) => {
                    eprintln!("[wayland] wtype paste failed: {e}");
                    try_portal_or_ydotool(clip_ok, terminal, text)
                }
            }
        } else {
            try_portal_or_ydotool(clip_ok, terminal, text)
        };

        self.last_method = Some(method);
        if method == PasteMethod::ClipboardOnly && !self.allow_clipboard_only {
            return Err("无法注入：无 virtual-keyboard / portal / ydotool；已写入剪贴板".into());
        }
        if matches!(method, PasteMethod::Wtype | PasteMethod::PortalPaste | PasteMethod::Ydotool) {
            let ms = self.restore_ms;
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(ms));
                let _ = match old { Some(t) => clipboard::set_clipboard(&t), None => Ok(()) };
            });
        }
        Ok(())
    }
}

fn try_portal_or_ydotool(clip_ok: bool, terminal: bool, text: &str) -> PasteMethod {
    if clip_ok {
        match portal::remote_desktop_cached() {
            Ok(rd) => match rd.paste_chord(terminal) {
                Ok(()) => return PasteMethod::PortalPaste,
                Err(e) => eprintln!("[wayland] portal paste failed: {e}"),
            },
            Err(e) => eprintln!("[wayland] portal rd connect: {e}"),
        }
        if which("ydotool").is_some() {
            if paste_chord_ydotool(terminal).is_ok() {
                return PasteMethod::Ydotool;
            }
        }
        return PasteMethod::ClipboardOnly;
    }
    // No clipboard: type via portal keysyms (GNOME without data-control).
    match portal::remote_desktop_cached() {
        Ok(rd) => match rd.type_text(text) {
            Ok(()) => PasteMethod::PortalType,
            Err(e) => {
                eprintln!("[wayland] portal type failed: {e}");
                PasteMethod::ClipboardOnly
            }
        },
        Err(e) => {
            eprintln!("[wayland] portal rd connect: {e}");
            PasteMethod::ClipboardOnly
        }
    }
}

impl SelectionReader for WaylandInjector {
    fn selection(&mut self, _app_key: &str) -> Option<String> {
        // Primary selection only (same as X11). Never fall back to CLIPBOARD:
        // stale clipboard text would be mistaken for a selection and trigger
        // edit/replace mode (found in sway E2E). GNOME without primary → None.
        clipboard::get_primary().filter(|s| !s.is_empty())
    }
}
