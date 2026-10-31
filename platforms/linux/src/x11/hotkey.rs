//! Hold-to-talk global hotkey: XGrabKey on root (any modifiers), XKB
//! "detectable auto-repeat" so a held key yields one press + one release;
//! software filter as a fallback. Escape is grabbed only while held → Cancelled.
use super::util::*;
use crate::platform::HotkeyEvent;
use std::sync::mpsc::Sender;
use std::time::Duration;
use x11rb::connection::Connection;
use x11rb::protocol::xkb::{self, ConnectionExt as _};
use x11rb::protocol::xproto::*;
use x11rb::protocol::Event;

pub struct HotkeyInfo { pub keycode: u8, pub detectable_autorepeat: bool }

pub fn spawn(keysym_name: &str, tx: Sender<HotkeyEvent>) -> Result<HotkeyInfo, String> {
    let (c, root, _a) = connect()?;
    let ks = keysym_from_name(keysym_name).ok_or(format!("unknown hotkey {keysym_name}"))?;
    let kc = keycode_for(&c, ks).ok_or(format!("no keycode for {keysym_name}"))?;
    let esc = keycode_for(&c, 0xff1b).unwrap_or(9);
    let mut dar = false;
    if c.xkb_use_extension(1, 0).ok().and_then(|r| r.reply().ok()).map(|r| r.supported).unwrap_or(false) {
        let f = xkb::PerClientFlag::DETECTABLE_AUTO_REPEAT;
        if let Ok(r) = c.xkb_per_client_flags(xkb::ID::USE_CORE_KBD.into(), f, f,
            xkb::BoolCtrl::from(0u32), xkb::BoolCtrl::from(0u32), xkb::BoolCtrl::from(0u32)).map(|x| x.reply()) {
            dar = r.map(|r| r.value.contains(f)).unwrap_or(false);
        }
    }
    c.grab_key(false, root, ModMask::ANY, kc, GrabMode::ASYNC, GrabMode::ASYNC)
        .map_err(|e| e.to_string())?.check()
        .map_err(|e| format!("XGrabKey failed (another app owns the key?): {e:?}"))?;
    c.flush().map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let mut down = false;
        let mut pending_release: Option<u32> = None; // time of a release awaiting repeat check
        loop {
            let ev = if pending_release.is_some() {
                std::thread::sleep(Duration::from_millis(25));
                c.poll_for_event().ok().flatten()
            } else { c.wait_for_event().ok() };
            match ev {
                Some(Event::KeyPress(e)) if e.detail == kc => {
                    if pending_release.take() == Some(e.time) { continue; } // auto-repeat pair
                    if let Some(_) = pending_release.take() {}
                    if !down {
                        down = true;
                        let _ = c.grab_key(false, root, ModMask::ANY, esc, GrabMode::ASYNC, GrabMode::ASYNC);
                        let _ = c.flush();
                        if tx.send(HotkeyEvent::Pressed).is_err() { break; }
                    }
                }
                Some(Event::KeyRelease(e)) if e.detail == kc && down => {
                    if dar { release(&c, root, esc, &mut down, &tx, HotkeyEvent::Released); }
                    else { pending_release = Some(e.time); }
                }
                Some(Event::KeyPress(e)) if e.detail == esc && down => {
                    pending_release = None;
                    release(&c, root, esc, &mut down, &tx, HotkeyEvent::Cancelled);
                }
                None if pending_release.is_some() => {
                    pending_release = None;
                    release(&c, root, esc, &mut down, &tx, HotkeyEvent::Released);
                }
                None => {}
                Some(_) => {}
            }
        }
    });
    Ok(HotkeyInfo { keycode: kc, detectable_autorepeat: dar })
}

fn release(c: &x11rb::rust_connection::RustConnection, root: Window, esc: u8, down: &mut bool,
           tx: &Sender<HotkeyEvent>, ev: HotkeyEvent) {
    *down = false;
    let _ = c.ungrab_key(esc, root, ModMask::ANY);
    let _ = c.flush();
    let _ = tx.send(ev);
}
