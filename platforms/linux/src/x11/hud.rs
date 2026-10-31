//! Simple HUD: an override-redirect capsule at bottom-center that never takes
//! focus. Colour = state; text drawn with the core "fixed" font (ASCII label);
//! the Chinese message is set as _NET_WM_NAME (shown by AT tools / used in tests).
//! TODO(M1.1): render CJK text via fontconfig/cairo or a GTK layer.
use super::util::*;
use crate::platform::{Hud, HudState};
use x11rb::connection::Connection;
use x11rb::protocol::xproto::*;
use x11rb::rust_connection::RustConnection;
use x11rb::wrapper::ConnectionExt as _;

pub struct X11Hud { c: RustConnection, win: Window, gc: Gcontext, a: Atoms, mapped: bool, w: u16, h: u16 }

impl X11Hud {
    pub fn new() -> Result<Self, String> {
        let (c, root, a) = connect()?;
        let scr = &c.setup().roots[0];
        let (w, h) = (340u16, 36u16);
        let x = (scr.width_in_pixels as i16 - w as i16) / 2;
        let y = scr.height_in_pixels as i16 - h as i16 - 60;
        let win = c.generate_id().map_err(|e| e.to_string())?;
        c.create_window(x11rb::COPY_DEPTH_FROM_PARENT, win, root, x, y, w, h, 0, WindowClass::INPUT_OUTPUT, 0,
            &CreateWindowAux::new().override_redirect(1).background_pixel(0x202020)
                .event_mask(EventMask::EXPOSURE)).map_err(|e| e.to_string())?;
        c.change_property8(PropMode::REPLACE, win, AtomEnum::WM_CLASS, AtomEnum::STRING, b"saycribe-hud\0Saycribe\0")
            .map_err(|e| e.to_string())?;
        let font = c.generate_id().map_err(|e| e.to_string())?;
        c.open_font(font, b"fixed").map_err(|e| e.to_string())?;
        let gc = c.generate_id().map_err(|e| e.to_string())?;
        c.create_gc(gc, win, &CreateGCAux::new().foreground(0xffffff).background(0x202020).font(font))
            .map_err(|e| e.to_string())?;
        c.flush().map_err(|e| e.to_string())?;
        Ok(X11Hud { c, win, gc, a, mapped: false, w, h })
    }
    pub fn window(&self) -> Window { self.win }
}

impl Hud for X11Hud {
    fn show(&mut self, s: HudState) {
        let (bg, label, zh): (u32, String, String) = match &s {
            HudState::Hidden => {
                let _ = self.c.unmap_window(self.win); let _ = self.c.flush(); self.mapped = false; return;
            }
            HudState::Listening => (0x1f6feb, "Listening...".into(), "听写中".into()),
            HudState::Processing => (0x6e40c9, "Processing...".into(), "整理中".into()),
            HudState::Done => (0x238636, "Done".into(), "完成".into()),
            HudState::Error(m) => (0xda3633, format!("Error: {}", ascii_hint(m)), m.clone()),
        };
        let _ = self.c.change_property8(PropMode::REPLACE, self.win, self.a._NET_WM_NAME, self.a.UTF8_STRING, zh.as_bytes());
        let _ = self.c.change_window_attributes(self.win, &ChangeWindowAttributesAux::new().background_pixel(bg));
        if !self.mapped {
            let _ = self.c.map_window(self.win);
            let _ = self.c.configure_window(self.win, &ConfigureWindowAux::new().stack_mode(StackMode::ABOVE));
            self.mapped = true;
        }
        let _ = self.c.clear_area(false, self.win, 0, 0, self.w, self.h);
        let _ = self.c.change_gc(self.gc, &ChangeGCAux::new().background(bg));
        let _ = self.c.image_text8(self.win, self.gc, 14, 23, label.as_bytes());
        let _ = self.c.flush();
    }
}

fn ascii_hint(m: &str) -> &'static str {
    match m {
        "需要联网" => "network required",
        x if x.contains("token") => "token missing/invalid",
        "请求太频繁，请稍后重试" => "rate limited",
        "服务维护中" => "service unavailable",
        _ => "relay error",
    }
}
