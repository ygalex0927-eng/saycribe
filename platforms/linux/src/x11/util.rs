use x11rb::connection::Connection;
use x11rb::protocol::xproto::*;
use x11rb::protocol::xtest::ConnectionExt as _;
use x11rb::protocol::Event;
use x11rb::rust_connection::RustConnection;
use x11rb::wrapper::ConnectionExt as _;
use std::time::{Duration, Instant};

x11rb::atom_manager! {
    pub Atoms: AtomsCookie {
        CLIPBOARD, UTF8_STRING, TARGETS, TEXT, INCR,
        _NET_ACTIVE_WINDOW, _NET_WM_NAME, SAYCRIBE_SEL,
    }
}

pub fn connect() -> Result<(RustConnection, Window, Atoms), String> {
    let (c, screen) = x11rb::connect(None).map_err(|e| format!("X11 connect: {e}"))?;
    let root = c.setup().roots[screen].root;
    let atoms = Atoms::new(&c).map_err(|e| e.to_string())?.reply().map_err(|e| e.to_string())?;
    Ok((c, root, atoms))
}

/// Invisible helper window for selection transfers.
pub fn helper_window(c: &RustConnection, root: Window) -> Result<Window, String> {
    let w = c.generate_id().map_err(|e| e.to_string())?;
    c.create_window(0, w, root, -10, -10, 1, 1, 0, WindowClass::INPUT_OUTPUT, 0,
        &CreateWindowAux::new().event_mask(EventMask::PROPERTY_CHANGE))
        .map_err(|e| e.to_string())?;
    c.flush().map_err(|e| e.to_string())?;
    Ok(w)
}

pub fn keysym_from_name(name: &str) -> Option<u32> {
    Some(match name {
        "Alt_R" => 0xffea, "Alt_L" => 0xffe9, "Control_L" => 0xffe3, "Control_R" => 0xffe4,
        "Shift_L" => 0xffe1, "Shift_R" => 0xffe2, "Super_L" => 0xffeb, "Super_R" => 0xffec,
        "Escape" => 0xff1b, "Menu" => 0xff67, "ISO_Level3_Shift" => 0xfe03,
        "Caps_Lock" => 0xffe5, "Scroll_Lock" => 0xff14, "Pause" => 0xff13,
        "v" => 0x76, "c" => 0x63,
        n if n.len() >= 2 && n.starts_with('F') => {
            let k: u32 = n[1..].parse().ok()?;
            if (1..=35).contains(&k) { 0xffbe + k - 1 } else { return None; }
        }
        _ => return None,
    })
}

pub fn keycode_for(c: &RustConnection, keysym: u32) -> Option<u8> {
    let s = c.setup();
    let (min, max) = (s.min_keycode, s.max_keycode);
    let m = c.get_keyboard_mapping(min, max - min + 1).ok()?.reply().ok()?;
    let per = m.keysyms_per_keycode as usize;
    m.keysyms.chunks(per).position(|ks| ks.contains(&keysym)).map(|i| min + i as u8)
}

/// Press modifiers + key via XTEST and release in reverse order.
pub fn send_chord(c: &RustConnection, root: Window, keysyms: &[u32]) -> Result<(), String> {
    let codes: Vec<u8> = keysyms.iter()
        .map(|k| keycode_for(c, *k).ok_or(format!("no keycode for keysym {k:#x}")))
        .collect::<Result<_, _>>()?;
    for &k in &codes { c.xtest_fake_input(KEY_PRESS_EVENT, k, 0, root, 0, 0, 0).map_err(|e| e.to_string())?; }
    for &k in codes.iter().rev() { c.xtest_fake_input(KEY_RELEASE_EVENT, k, 0, root, 0, 0, 0).map_err(|e| e.to_string())?; }
    c.sync().map_err(|e| e.to_string())?;
    Ok(())
}

/// Read a selection as UTF-8 text. None when no owner / no text / timeout.
pub fn read_selection(c: &RustConnection, win: Window, a: &Atoms, selection: Atom) -> Option<String> {
    let owner = c.get_selection_owner(selection).ok()?.reply().ok()?.owner;
    if owner == x11rb::NONE { return None; }
    for target in [a.UTF8_STRING, AtomEnum::STRING.into()] {
        c.convert_selection(win, selection, target, a.SAYCRIBE_SEL, x11rb::CURRENT_TIME).ok()?;
        c.flush().ok()?;
        let deadline = Instant::now() + Duration::from_millis(500);
        let mut got: Option<bool> = None;
        while Instant::now() < deadline {
            match c.poll_for_event() {
                Ok(Some(Event::SelectionNotify(e))) if e.requestor == win => {
                    got = Some(e.property != x11rb::NONE); break;
                }
                Ok(Some(_)) => {}
                Ok(None) => std::thread::sleep(Duration::from_millis(2)),
                Err(_) => return None,
            }
        }
        match got {
            Some(true) => {
                let p = c.get_property(true, win, a.SAYCRIBE_SEL, AtomEnum::ANY, 0, u32::MAX / 4).ok()?.reply().ok()?;
                if p.type_ == a.INCR { return None; } // large transfers: not supported yet
                return Some(String::from_utf8_lossy(&p.value).into_owned());
            }
            Some(false) => continue, // try STRING
            None => return None,
        }
    }
    None
}

pub fn get_text_property(c: &RustConnection, w: Window, prop: Atom) -> Option<Vec<u8>> {
    let r = c.get_property(false, w, prop, AtomEnum::ANY, 0, 4096).ok()?.reply().ok()?;
    if r.value.is_empty() { None } else { Some(r.value) }
}
