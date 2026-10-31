//! StatusNotifierItem tray (works on X11 and Wayland panels that support SNI).
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

pub struct SaycribeTray { pub status: String, pub quit: Arc<AtomicBool> }

#[cfg(feature = "tray")]
impl ksni::Tray for SaycribeTray {
    fn id(&self) -> String { "saycribe".into() }
    fn title(&self) -> String { format!("Saycribe · {}", self.status) }
    fn icon_name(&self) -> String { "audio-input-microphone".into() }
    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::*;
        vec![
            StandardItem { label: format!("状态：{}", self.status), enabled: false, ..Default::default() }.into(),
            MenuItem::Separator,
            StandardItem { label: "退出".into(), activate: Box::new(|t: &mut Self| t.quit.store(true, Ordering::SeqCst)),
                ..Default::default() }.into(),
        ]
    }
}

pub struct TrayHandle {
    #[cfg(feature = "tray")] h: Option<ksni::blocking::Handle<SaycribeTray>>,
}

impl TrayHandle {
    pub fn start(quit: Arc<AtomicBool>) -> TrayHandle {
        #[cfg(feature = "tray")]
        {
            if std::env::var("DBUS_SESSION_BUS_ADDRESS").is_err() {
                eprintln!("[tray] no session bus; tray disabled");
                return TrayHandle { h: None };
            }
            use ksni::blocking::TrayMethods;
            match (SaycribeTray { status: "就绪".into(), quit }).spawn() {
                Ok(h) => return TrayHandle { h: Some(h) },
                Err(e) => { eprintln!("[tray] unavailable: {e}"); return TrayHandle { h: None }; }
            }
        }
        #[allow(unreachable_code)]
        { let _ = quit; TrayHandle { #[cfg(feature = "tray")] h: None } }
    }
    pub fn set_status(&self, s: &str) {
        #[cfg(feature = "tray")]
        if let Some(h) = &self.h { let s = s.to_string(); h.update(move |t| t.status = s); }
        #[cfg(not(feature = "tray"))]
        let _ = s;
    }
}
