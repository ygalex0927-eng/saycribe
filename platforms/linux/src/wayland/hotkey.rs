//! Wayland global hotkey.
//! Preferred: xdg-desktop-portal GlobalShortcuts (hold-to-talk).
//! Fallback: toggle FIFO + `saycribe --toggle` (press-to-toggle, not press-and-hold).
use super::portal;
use crate::platform::HotkeyEvent;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;

/// Start hotkey: try GlobalShortcuts first; on failure fall back to FIFO toggle.
/// Returns the FIFO path when FIFO is used (also set as SAYCRIBE_TOGGLE_FIFO by caller),
/// or None when portal GlobalShortcuts is active.
pub fn spawn(tx: Sender<HotkeyEvent>, quit: Arc<AtomicBool>, preferred_trigger: &str)
    -> Result<Option<std::path::PathBuf>, String>
{
    match portal::spawn_global_shortcuts(tx.clone(), quit.clone(), preferred_trigger) {
        Ok(()) => {
            eprintln!("[wayland/hotkey] GlobalShortcuts portal active (trigger preferred={preferred_trigger})");
            Ok(None)
        }
        Err(e) => {
            eprintln!("[wayland/hotkey] GlobalShortcuts unavailable ({e}); falling back to toggle FIFO");
            let path = spawn_toggle(tx, quit)?;
            Ok(Some(path))
        }
    }
}

/// Toggle-mode hotkey via named FIFO.
pub fn spawn_toggle(tx: Sender<HotkeyEvent>, quit: Arc<AtomicBool>) -> Result<std::path::PathBuf, String> {
    let path = std::env::temp_dir().join(format!("saycribe-toggle-{}", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let st = std::process::Command::new("mkfifo").arg(&path).status().map_err(|e| e.to_string())?;
    if !st.success() { return Err(format!("mkfifo {st}")); }
    let pressed = Arc::new(AtomicBool::new(false));
    let path2 = path.clone();
    std::thread::spawn(move || {
        loop {
            if quit.load(Ordering::SeqCst) { break; }
            match std::fs::OpenOptions::new().read(true).open(&path2) {
                Ok(mut f) => {
                    use std::io::Read;
                    let mut b = [0u8; 8];
                    let _ = f.read(&mut b);
                    if pressed.fetch_xor(true, Ordering::SeqCst) {
                        let _ = tx.send(HotkeyEvent::Released);
                    } else {
                        let _ = tx.send(HotkeyEvent::Pressed);
                    }
                }
                Err(_) => std::thread::sleep(std::time::Duration::from_millis(200)),
            }
        }
    });
    eprintln!("[wayland/hotkey] toggle FIFO {}", path.display());
    Ok(path)
}

/// Write a byte to a running saycribe toggle FIFO (`saycribe --toggle`).
/// Stale FIFOs (owner pid gone) are removed; writes are non-blocking so a FIFO
/// without a reader fails fast (ENXIO) instead of hanging.
pub fn poke_toggle() -> Result<(), String> {
    if let Ok(p) = std::env::var("SAYCRIBE_TOGGLE_FIFO") {
        return write_nonblock(std::path::Path::new(&p));
    }
    let mut last_err = None;
    if let Ok(rd) = std::fs::read_dir(std::env::temp_dir()) {
        for e in rd.flatten() {
            let p = e.path();
            let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
            let Some(pid) = name.strip_prefix("saycribe-toggle-").and_then(|s| s.parse::<u32>().ok()) else { continue };
            if !std::path::Path::new(&format!("/proc/{pid}")).exists() {
                let _ = std::fs::remove_file(&p);
                continue;
            }
            match write_nonblock(&p) { Ok(()) => return Ok(()), Err(e) => last_err = Some(e) }
        }
    }
    Err(last_err.unwrap_or_else(|| "无运行中的 Wayland toggle FIFO（先启动 saycribe；若用 GlobalShortcuts 则直接按绑定键）".into()))
}

fn write_nonblock(p: &std::path::Path) -> Result<(), String> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    const O_NONBLOCK: i32 = 0o4000;
    let mut f = std::fs::OpenOptions::new().write(true).custom_flags(O_NONBLOCK).open(p)
        .map_err(|e| format!("{}: {e}", p.display()))?;
    f.write_all(b"1").map_err(|e| e.to_string())
}

pub fn cleanup_fifo(p: &std::path::Path) { let _ = std::fs::remove_file(p); }

#[cfg(test)]
mod tests {
    #[test]
    fn nonblock_write_without_reader_fails_fast() {
        let p = std::env::temp_dir().join(format!("sc-test-fifo-{}", std::process::id()));
        let _ = std::fs::remove_file(&p);
        assert!(std::process::Command::new("mkfifo").arg(&p).status().unwrap().success());
        let t = std::time::Instant::now();
        assert!(super::write_nonblock(&p).is_err());
        assert!(t.elapsed() < std::time::Duration::from_secs(1));
        std::fs::remove_file(&p).unwrap();
    }
}
