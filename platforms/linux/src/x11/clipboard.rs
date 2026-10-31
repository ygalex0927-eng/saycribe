//! CLIPBOARD owner thread: serves our text to paste targets, and keeps
//! serving the restored previous text afterwards (the original owner lost it).
use super::util::{connect, helper_window, Atoms};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use x11rb::connection::Connection;
use x11rb::protocol::xproto::*;
use x11rb::protocol::Event;
use x11rb::rust_connection::RustConnection;

enum Cmd { Set(Option<String>) }

#[derive(Clone)]
pub struct ClipboardServer {
    tx: std::sync::mpsc::Sender<Cmd>,
    /// Number of SelectionRequests answered (for tests/diagnostics).
    pub served: Arc<Mutex<u32>>,
}

impl ClipboardServer {
    pub fn start() -> Result<Self, String> {
        let (c, root, a) = connect()?;
        let win = helper_window(&c, root)?;
        let (tx, rx) = std::sync::mpsc::channel::<Cmd>();
        let served = Arc::new(Mutex::new(0u32));
        let served2 = served.clone();
        std::thread::spawn(move || {
            let mut content: Option<String> = None;
            loop {
                while let Ok(Cmd::Set(t)) = rx.try_recv() {
                    content = t;
                    let owner = if content.is_some() { win } else { x11rb::NONE };
                    let _ = c.set_selection_owner(owner, a.CLIPBOARD, x11rb::CURRENT_TIME);
                    let _ = c.flush();
                }
                match c.poll_for_event() {
                    Ok(Some(Event::SelectionRequest(e))) => {
                        serve(&c, &a, &e, content.as_deref());
                        *served2.lock().unwrap() += 1;
                    }
                    Ok(Some(Event::SelectionClear(_))) => content = None,
                    Ok(Some(_)) => {}
                    Ok(None) => std::thread::sleep(Duration::from_millis(2)),
                    Err(_) => break,
                }
            }
        });
        Ok(ClipboardServer { tx, served })
    }
    /// Take CLIPBOARD ownership with `text` (None = release ownership).
    pub fn set(&self, text: Option<String>) {
        let _ = self.tx.send(Cmd::Set(text));
        std::thread::sleep(Duration::from_millis(15));
    }
}

fn serve(c: &RustConnection, a: &Atoms, e: &SelectionRequestEvent, content: Option<&str>) {
    let prop = if e.property == x11rb::NONE { e.target } else { e.property };
    let ok = match content {
        None => false,
        Some(text) => {
            if e.target == a.TARGETS {
                let t = [a.TARGETS, a.UTF8_STRING, a.TEXT, AtomEnum::STRING.into()];
                c.change_property32(PropMode::REPLACE, e.requestor, prop, AtomEnum::ATOM, &t).is_ok()
            } else if e.target == a.UTF8_STRING || e.target == a.TEXT || e.target == u32::from(AtomEnum::STRING) {
                let ty = if e.target == a.TEXT { a.UTF8_STRING } else { e.target };
                c.change_property8(PropMode::REPLACE, e.requestor, prop, ty, text.as_bytes()).is_ok()
            } else { false }
        }
    };
    let ev = SelectionNotifyEvent {
        response_type: SELECTION_NOTIFY_EVENT, sequence: 0, time: e.time, requestor: e.requestor,
        selection: e.selection, target: e.target, property: if ok { prop } else { x11rb::NONE },
    };
    let _ = c.send_event(false, e.requestor, EventMask::NO_EVENT, ev);
    let _ = c.flush();
}

use x11rb::wrapper::ConnectionExt as _;
