//! X11 backend: hotkey (XGrabKey + XKB detectable auto-repeat), clipboard
//! paste via XTEST, PRIMARY / Ctrl+C selection, WM_CLASS app context, HUD.
pub mod util;
pub mod clipboard;
pub mod hotkey;
pub mod inject;
pub mod appctx;
pub mod hud;
