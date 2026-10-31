//! Foreground app via _NET_ACTIVE_WINDOW (EWMH) or input focus, → WM_CLASS.
use super::util::*;
use crate::platform::AppContext;
use x11rb::protocol::xproto::*;
use x11rb::rust_connection::RustConnection;

pub struct X11AppContext { c: RustConnection, root: Window, a: Atoms }

impl X11AppContext {
    pub fn new() -> Result<Self, String> { let (c, root, a) = connect()?; Ok(X11AppContext { c, root, a }) }

    fn active_window(&self) -> Option<Window> {
        let r = self.c.get_property(false, self.root, self.a._NET_ACTIVE_WINDOW, AtomEnum::WINDOW, 0, 1).ok()?.reply().ok()?;
        if let Some(w) = r.value32().and_then(|mut i| i.next()).filter(|w| *w != 0) { return Some(w); }
        let f = self.c.get_input_focus().ok()?.reply().ok()?.focus;
        if f <= 1 || f == self.root { None } else { Some(f) }
    }

    /// "instance/class" for a window, walking up to the first ancestor with WM_CLASS.
    pub fn wm_class_of(&self, mut w: Window) -> Option<String> {
        for _ in 0..16 {
            if let Some(v) = get_text_property(&self.c, w, AtomEnum::WM_CLASS.into()) {
                let parts: Vec<String> = v.split(|b| *b == 0).filter(|s| !s.is_empty())
                    .map(|s| String::from_utf8_lossy(s).into_owned()).collect();
                if !parts.is_empty() { return Some(parts.join("/")); }
            }
            let t = self.c.query_tree(w).ok()?.reply().ok()?;
            if t.parent == 0 || t.parent == self.root { break; }
            w = t.parent;
        }
        // Reparenting WMs: WM_CLASS may sit on a child of the frame.
        let t = self.c.query_tree(w).ok()?.reply().ok()?;
        for ch in t.children {
            if let Some(v) = get_text_property(&self.c, ch, AtomEnum::WM_CLASS.into()) {
                let parts: Vec<String> = v.split(|b| *b == 0).filter(|s| !s.is_empty())
                    .map(|s| String::from_utf8_lossy(s).into_owned()).collect();
                if !parts.is_empty() { return Some(parts.join("/")); }
            }
        }
        None
    }
}

impl AppContext for X11AppContext {
    fn foreground_app(&mut self) -> String {
        self.active_window().and_then(|w| self.wm_class_of(w)).unwrap_or_default()
    }
}
