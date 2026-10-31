//! Paste-based injection + selection reading for X11.
use super::clipboard::ClipboardServer;
use super::util::*;
use crate::platform::{Injector, SelectionReader};
use std::time::Duration;
use x11rb::protocol::xproto::*;
use x11rb::rust_connection::RustConnection;

const CTRL: u32 = 0xffe3; const SHIFT: u32 = 0xffe1; const KEY_V: u32 = 0x76; const KEY_C: u32 = 0x63;

pub struct X11Injector {
    c: RustConnection, root: Window, a: Atoms, win: Window,
    pub clip: ClipboardServer,
    pub restore_ms: u64,
    is_terminal: Box<dyn Fn(&str) -> bool>,
    /// PRIMARY value already seen/consumed: X11 apps keep PRIMARY after the
    /// user deselects, so only a *changed* PRIMARY counts as a live selection.
    last_primary: Option<String>,
    pub copy_fallback: bool,
    /// (generation, clipboard value to restore) while a restore is pending.
    pending: std::sync::Arc<std::sync::Mutex<(u64, Option<Option<String>>)>>,
}

impl X11Injector {
    pub fn new(restore_ms: u64, is_terminal: Box<dyn Fn(&str) -> bool>) -> Result<Self, String> {
        let (c, root, a) = connect()?;
        let win = helper_window(&c, root)?;
        let mut me = X11Injector { c, root, a, win, clip: ClipboardServer::start()?, restore_ms, is_terminal,
            last_primary: None, copy_fallback: true, pending: Default::default() };
        me.last_primary = me.read_primary(); // ignore a selection that predates startup
        Ok(me)
    }
    pub fn read_clipboard(&self) -> Option<String> { read_selection(&self.c, self.win, &self.a, self.a.CLIPBOARD) }
    pub fn read_primary(&self) -> Option<String> { read_selection(&self.c, self.win, &self.a, AtomEnum::PRIMARY.into()) }
}

impl Injector for X11Injector {
    fn insert(&mut self, text: &str, app_key: &str) -> Result<(), String> {
        if text.is_empty() { return Ok(()); }
        // If a previous restore is still pending, the "real" old clipboard is that one.
        let old = match self.pending.lock().unwrap().1.clone() { Some(o) => o, None => self.read_clipboard() };
        self.clip.set(Some(text.to_string()));
        let chord: &[u32] = if (self.is_terminal)(app_key) { &[CTRL, SHIFT, KEY_V] } else { &[CTRL, KEY_V] };
        send_chord(&self.c, self.root, chord)?;
        // Restore the previous text clipboard after a (configurable) delay, off-thread.
        // Non-text clipboard content (images, files) is not preserved yet.
        let gen = { let mut p = self.pending.lock().unwrap(); p.0 += 1; p.1 = Some(old.clone()); p.0 };
        let (pending, clip, ms) = (self.pending.clone(), self.clip.clone(), self.restore_ms);
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(ms));
            let mut p = pending.lock().unwrap();
            if p.0 == gen { clip.set(old); p.1 = None; }
        });
        Ok(())
    }
}

impl SelectionReader for X11Injector {
    /// PRIMARY first (only if changed since last seen); otherwise, fall back to Ctrl+C
    /// (Ctrl+Shift+C in terminals) and read CLIPBOARD, then restore it.
    fn selection(&mut self, app_key: &str) -> Option<String> {
        let p = self.read_primary().filter(|s| !s.is_empty());
        if p.is_some() && p != self.last_primary {
            self.last_primary = p.clone();
            return p;
        }
        if !self.copy_fallback { return None; }
        let before = match self.pending.lock().unwrap().1.clone() { Some(o) => o, None => self.read_clipboard() };
        // Put a sentinel so we can tell whether Ctrl+C copied anything.
        let sentinel = format!("\u{2063}saycribe-{}", std::process::id());
        self.clip.set(Some(sentinel.clone()));
        let chord: &[u32] = if (self.is_terminal)(app_key) { &[CTRL, SHIFT, KEY_C] } else { &[CTRL, KEY_C] };
        send_chord(&self.c, self.root, chord).ok()?;
        let mut got = None;
        for _ in 0..8 { // ≤160 ms when nothing is selected
            std::thread::sleep(Duration::from_millis(20));
            match self.read_clipboard() {
                Some(t) if t != sentinel => { got = Some(t); break; }
                _ => {}
            }
        }
        self.clip.set(before);
        got.filter(|s| !s.is_empty())
    }
}
