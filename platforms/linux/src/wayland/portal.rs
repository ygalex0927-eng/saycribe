//! xdg-desktop-portal helpers for GNOME / KDE (ashpd).
//!
//! - GlobalShortcuts → hold-to-talk (Activated / Deactivated)
//! - RemoteDesktop → keyboard paste / keysym typing (+ restore_token)
//! - Clipboard on GNOME (no wlr-data-control): wl-copy → xclip(XWayland) →
//!   keysym type via RemoteDesktop
//!
//! wlroots paths (wtype / FIFO) stay preferred when they work; portal is the
//! GNOME/KDE fallback. Portal dialogs block up to SAYCRIBE_PORTAL_TIMEOUT_MS
//! (default 12000) so headless does not hang forever.
use ashpd::desktop::{
    global_shortcuts::{GlobalShortcuts, NewShortcut},
    remote_desktop::{DeviceType, KeyState, RemoteDesktop},
    PersistMode,
};
use futures_util::StreamExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use crate::platform::HotkeyEvent;

const SHORTCUT_ID: &str = "saycribe-hold";

fn rt() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("saycribe-portal")
            .build()
            .expect("tokio runtime")
    })
}

fn portal_timeout() -> Duration {
    let ms = std::env::var("SAYCRIBE_PORTAL_TIMEOUT_MS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(12_000u64);
    Duration::from_millis(ms)
}

fn token_path() -> PathBuf {
    crate::core_stub::config::data_dir().join("rd_restore_token")
}

fn load_restore_token() -> Option<String> {
    std::fs::read_to_string(token_path())
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn save_restore_token(tok: &str) {
    let p = token_path();
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&p, tok);
}

fn uid() -> u32 {
    std::process::Command::new("id")
        .arg("-u")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(1000)
}

/// Probe which portal interfaces answer on the session bus (no authorization dialogs).
pub fn probe_interfaces() -> PortalProbe {
    let bus = std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_some()
        || Path::new(&format!("/run/user/{}/bus", uid())).exists()
        || Path::new("/tmp/xdg-runtime-box/bus").exists();
    if !bus {
        return PortalProbe::default();
    }
    let timeout = portal_timeout();
    let handle = rt().spawn(async {
        let mut p = PortalProbe {
            session_bus: true,
            ..Default::default()
        };
        if let Ok(proxy) = RemoteDesktop::new().await {
            p.remote_desktop = true;
            p.rd_devices = proxy
                .available_device_types()
                .await
                .ok()
                .map(|f| format!("{f:?}"));
        }
        if GlobalShortcuts::new().await.is_ok() {
            p.global_shortcuts = true;
        }
        if ashpd::desktop::clipboard::Clipboard::new().await.is_ok() {
            p.clipboard = true;
        }
        p
    });
    rt().block_on(async {
        match tokio::time::timeout(timeout, handle).await {
            Ok(Ok(p)) => p,
            _ => PortalProbe {
                session_bus: true,
                ..Default::default()
            },
        }
    })
}

#[derive(Debug, Clone, Default)]
pub struct PortalProbe {
    pub session_bus: bool,
    pub remote_desktop: bool,
    pub global_shortcuts: bool,
    pub clipboard: bool,
    pub rd_version: Option<u32>,
    pub rd_devices: Option<String>,
}

impl std::fmt::Display for PortalProbe {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "portal: bus={} RemoteDesktop={} (v={:?}, devices={:?}) GlobalShortcuts={} Clipboard={}",
            self.session_bus,
            self.remote_desktop,
            self.rd_version,
            self.rd_devices,
            self.global_shortcuts,
            self.clipboard
        )
    }
}

// ── RemoteDesktop ─────────────────────────────────────────────────────────

enum RdCmd {
    Paste {
        terminal: bool,
        reply: tokio::sync::oneshot::Sender<Result<(), String>>,
    },
    TypeText {
        text: String,
        reply: tokio::sync::oneshot::Sender<Result<(), String>>,
    },
    Status {
        reply: tokio::sync::oneshot::Sender<String>,
    },
}

/// Sync façade around a long-lived RemoteDesktop session worker.
#[derive(Clone)]
pub struct RemoteDesktopHandle {
    tx: tokio::sync::mpsc::UnboundedSender<RdCmd>,
}

impl RemoteDesktopHandle {
    /// Create (or resume via restore_token) a keyboard RemoteDesktop session.
    /// Blocks until the portal dialog is accepted or the timeout elapses.
    pub fn connect() -> Result<Self, String> {
        let (cmd_tx, cmd_rx) = tokio::sync::mpsc::unbounded_channel::<RdCmd>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<Result<(), String>>();
        let restore = load_restore_token();

        rt().spawn(async move {
            if let Err(e) = rd_worker(cmd_rx, restore, ready_tx).await {
                eprintln!("[portal/rd] worker ended: {e}");
            }
        });

        match rt().block_on(async { tokio::time::timeout(portal_timeout(), ready_rx).await }) {
            Ok(Ok(Ok(()))) => Ok(Self { tx: cmd_tx }),
            Ok(Ok(Err(e))) => Err(e),
            Ok(Err(_)) => Err("RemoteDesktop worker 启动通道关闭".into()),
            Err(_) => Err(format!(
                "RemoteDesktop 授权超时（{}ms）。请在弹窗中允许键盘控制，或增大 SAYCRIBE_PORTAL_TIMEOUT_MS",
                portal_timeout().as_millis()
            )),
        }
    }

    pub fn paste_chord(&self, terminal: bool) -> Result<(), String> {
        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
        self.tx
            .send(RdCmd::Paste {
                terminal,
                reply: reply_tx,
            })
            .map_err(|_| "RemoteDesktop worker 已退出".to_string())?;
        rt().block_on(reply_rx)
            .map_err(|_| "RemoteDesktop paste 无应答".to_string())?
    }

    pub fn type_text(&self, text: &str) -> Result<(), String> {
        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
        self.tx
            .send(RdCmd::TypeText {
                text: text.to_string(),
                reply: reply_tx,
            })
            .map_err(|_| "RemoteDesktop worker 已退出".to_string())?;
        rt().block_on(reply_rx)
            .map_err(|_| "RemoteDesktop type 无应答".to_string())?
    }

    pub fn status(&self) -> String {
        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
        if self.tx.send(RdCmd::Status { reply: reply_tx }).is_err() {
            return "dead".into();
        }
        rt().block_on(reply_rx).unwrap_or_else(|_| "no-reply".into())
    }
}

async fn rd_worker(
    mut rx: tokio::sync::mpsc::UnboundedReceiver<RdCmd>,
    restore: Option<String>,
    ready: tokio::sync::oneshot::Sender<Result<(), String>>,
) -> Result<(), String> {
    let proxy = RemoteDesktop::new()
        .await
        .map_err(|e| format!("RemoteDesktop proxy: {e}"))?;
    let session = match proxy.create_session().await {
        Ok(s) => s,
        Err(e) => {
            let _ = ready.send(Err(format!("CreateSession: {e}")));
            return Err(format!("CreateSession: {e}"));
        }
    };

    if let Err(e) = proxy
        .select_devices(
            &session,
            DeviceType::Keyboard.into(),
            restore.as_deref(),
            PersistMode::ExplicitlyRevoked,
        )
        .await
    {
        let _ = ready.send(Err(format!("SelectDevices: {e}")));
        return Err(format!("SelectDevices: {e}"));
    }

    let response = match proxy.start(&session, None).await {
        Ok(req) => match req.response() {
            Ok(r) => r,
            Err(e) => {
                let msg = format!("Start response (用户拒绝或无会话？): {e}");
                let _ = ready.send(Err(msg.clone()));
                return Err(msg);
            }
        },
        Err(e) => {
            let msg = format!("Start request: {e}");
            let _ = ready.send(Err(msg.clone()));
            return Err(msg);
        }
    };

    if let Some(tok) = response.restore_token() {
        save_restore_token(tok);
        eprintln!("[portal/rd] restore_token saved ({} bytes)", tok.len());
    }
    eprintln!(
        "[portal/rd] session ready devices={:?}",
        response.devices()
    );
    let _ = ready.send(Ok(()));

    const KEY_LEFTCTRL: i32 = 29;
    const KEY_LEFTSHIFT: i32 = 42;
    const KEY_V: i32 = 47;

    while let Some(cmd) = rx.recv().await {
        match cmd {
            RdCmd::Paste { terminal, reply } => {
                let r = async {
                    proxy
                        .notify_keyboard_keycode(&session, KEY_LEFTCTRL, KeyState::Pressed)
                        .await
                        .map_err(|e| e.to_string())?;
                    if terminal {
                        proxy
                            .notify_keyboard_keycode(&session, KEY_LEFTSHIFT, KeyState::Pressed)
                            .await
                            .map_err(|e| e.to_string())?;
                    }
                    proxy
                        .notify_keyboard_keycode(&session, KEY_V, KeyState::Pressed)
                        .await
                        .map_err(|e| e.to_string())?;
                    tokio::time::sleep(Duration::from_millis(40)).await;
                    proxy
                        .notify_keyboard_keycode(&session, KEY_V, KeyState::Released)
                        .await
                        .map_err(|e| e.to_string())?;
                    if terminal {
                        proxy
                            .notify_keyboard_keycode(&session, KEY_LEFTSHIFT, KeyState::Released)
                            .await
                            .map_err(|e| e.to_string())?;
                    }
                    proxy
                        .notify_keyboard_keycode(&session, KEY_LEFTCTRL, KeyState::Released)
                        .await
                        .map_err(|e| e.to_string())?;
                    Ok(())
                }
                .await;
                let _ = reply.send(r);
            }
            RdCmd::TypeText { text, reply } => {
                let r = type_via_keysyms(&proxy, &session, &text).await;
                let _ = reply.send(r);
            }
            RdCmd::Status { reply } => {
                let _ = reply.send(format!("ok devices={:?}", response.devices()));
            }
        }
    }
    Ok(())
}

async fn type_via_keysyms(
    proxy: &RemoteDesktop<'_>,
    session: &ashpd::desktop::Session<'_, RemoteDesktop<'_>>,
    text: &str,
) -> Result<(), String> {
    for ch in text.chars() {
        let keysym: i32 = if (ch as u32) < 0x100 {
            ch as i32
        } else {
            (0x0100_0000 | ch as u32) as i32
        };
        proxy
            .notify_keyboard_keysym(session, keysym, KeyState::Pressed)
            .await
            .map_err(|e| e.to_string())?;
        tokio::time::sleep(Duration::from_millis(8)).await;
        proxy
            .notify_keyboard_keysym(session, keysym, KeyState::Released)
            .await
            .map_err(|e| e.to_string())?;
        tokio::time::sleep(Duration::from_millis(4)).await;
    }
    Ok(())
}

static RD: Mutex<Option<RemoteDesktopHandle>> = Mutex::new(None);

pub fn remote_desktop_cached() -> Result<RemoteDesktopHandle, String> {
    let mut g = RD.lock().map_err(|e| e.to_string())?;
    if let Some(h) = g.as_ref() {
        return Ok(h.clone());
    }
    let h = RemoteDesktopHandle::connect()?;
    *g = Some(h.clone());
    Ok(h)
}

pub fn clear_rd_cache() {
    if let Ok(mut g) = RD.lock() {
        *g = None;
    }
}

// ── GlobalShortcuts ───────────────────────────────────────────────────────

/// Map config hotkey names (X keysym style) to an XDG shortcuts preferred_trigger.
pub fn preferred_trigger_from_hotkey(hotkey: &str) -> String {
    match hotkey {
        "Alt_R" | "Alt_L" => "Alt_R".into(),
        "Super_L" | "Super_R" | "Meta_L" | "Meta_R" => "Super_L".into(),
        "Control_R" | "Control_L" => "Control_R".into(),
        other if other.contains('+') => other.to_string(),
        other => other.to_string(),
    }
}

/// Bind hold-to-talk via GlobalShortcuts. On success, Activated→Pressed and
/// Deactivated→Released. Returns Err on missing portal / reject / timeout so
/// the caller can fall back to FIFO toggle.
pub fn spawn_global_shortcuts(
    tx: Sender<HotkeyEvent>,
    quit: Arc<AtomicBool>,
    preferred_trigger: &str,
) -> Result<(), String> {
    let trigger = preferred_trigger.to_string();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<Result<(), String>>();

    rt().spawn(async move {
        let proxy = match GlobalShortcuts::new().await {
            Ok(p) => p,
            Err(e) => { let _ = ready_tx.send(Err(format!("GlobalShortcuts proxy: {e}"))); return; }
        };
        let session = match proxy.create_session().await {
            Ok(s) => s,
            Err(e) => { let _ = ready_tx.send(Err(format!("GS CreateSession: {e}"))); return; }
        };
        let shortcut = NewShortcut::new(SHORTCUT_ID, "Saycribe hold-to-talk")
            .preferred_trigger(trigger.as_str());
        let bound = match proxy.bind_shortcuts(&session, &[shortcut], None).await {
            Ok(req) => match req.response() {
                Ok(r) => r,
                Err(e) => { let _ = ready_tx.send(Err(format!("BindShortcuts response (用户拒绝？): {e}"))); return; }
            },
            Err(e) => { let _ = ready_tx.send(Err(format!("BindShortcuts: {e}"))); return; }
        };
        let desc: Vec<_> = bound.shortcuts().iter()
            .map(|s| format!("{}={}", s.id(), s.trigger_description())).collect();
        eprintln!("[portal/gs] bound: {}", desc.join(", "));
        let _ = ready_tx.send(Ok(()));

        let mut activated = match proxy.receive_activated().await {
            Ok(s) => s,
            Err(e) => { eprintln!("[portal/gs] receive_activated: {e}"); return; }
        };
        let mut deactivated = match proxy.receive_deactivated().await {
            Ok(s) => s,
            Err(e) => { eprintln!("[portal/gs] receive_deactivated: {e}"); return; }
        };
        loop {
            if quit.load(Ordering::SeqCst) { break; }
            tokio::select! {
                ev = activated.next() => {
                    match ev {
                        Some(a) if a.shortcut_id() == SHORTCUT_ID => { let _ = tx.send(HotkeyEvent::Pressed); }
                        Some(_) => {}
                        None => break,
                    }
                }
                ev = deactivated.next() => {
                    match ev {
                        Some(d) if d.shortcut_id() == SHORTCUT_ID => { let _ = tx.send(HotkeyEvent::Released); }
                        Some(_) => {}
                        None => break,
                    }
                }
                _ = tokio::time::sleep(Duration::from_millis(200)) => {}
            }
        }
        drop(session);
    });

    match rt().block_on(async { tokio::time::timeout(portal_timeout(), ready_rx).await }) {
        Ok(Ok(Ok(()))) => Ok(()),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("GlobalShortcuts 启动通道关闭".into()),
        Err(_) => Err(format!("GlobalShortcuts 授权超时（{}ms）", portal_timeout().as_millis())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn trigger_map() {
        assert_eq!(preferred_trigger_from_hotkey("Alt_R"), "Alt_R");
        assert_eq!(preferred_trigger_from_hotkey("CTRL+SPACE"), "CTRL+SPACE");
    }
}
