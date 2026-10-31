#![allow(dead_code)] // some interface/stub items are used only by one backend
mod app;
mod audio;
#[cfg(feature = "core")]
mod core_adapter;
mod core_api;
mod core_stub;
mod platform;
mod tray;
mod x11;
mod wayland;

use core_api::{Relay, SecretStore};
use core_stub::config::{config_dir, data_dir, Config};
use platform::{DisplayServer, HotkeyEvent};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let cfg = Config::load();
    let secrets = core_stub::secret::LinuxSecretStore::new(config_dir());
    match args.get(1).map(String::as_str) {
        Some("--detect") => { println!("{:?}", platform::detect()); return; }
        Some("--set-token") => {
            let mut t = String::new(); std::io::stdin().read_line(&mut t).unwrap();
            secrets.set(t.trim()).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
            println!("token saved"); return;
        }
        Some("--check") => {
            let r = core_stub::relay_http::HttpRelay::new(&cfg.relay_url, secrets.get());
            match r.me() { Ok(m) => println!("连接正常：{m}"), Err(e) => { println!("{}（{e}）", e.user_message()); std::process::exit(1) } }
            return;
        }
        Some("--toggle") => { wayland::hotkey::poke_toggle().unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) }); return; }
        Some("--wayland-caps") => { println!("{}", wayland::limits_report(&wayland::probe())); return; }
        Some("--portal-caps") => {
            println!("{}", wayland::portal::probe_interfaces());
            println!("{}", wayland::limits_report(&wayland::probe()));
            return;
        }
        Some("--portal-rd-test") => {
            // Establish RemoteDesktop (may show a permission dialog) and send a no-op status.
            match wayland::portal::RemoteDesktopHandle::connect() {
                Ok(h) => { println!("ok {}", h.status()); }
                Err(e) => { eprintln!("{e}"); std::process::exit(1); }
            }
            return;
        }
        Some("--relay-bench") => { relay_bench(&cfg, &secrets); return; }
        Some("--download-models") => {
            #[cfg(feature = "core")]
            { match core_adapter::download_models() { Ok(()) => return, Err(e) => { eprintln!("{e}"); std::process::exit(1) } } }
            #[cfg(not(feature = "core"))]
            { eprintln!("built without the `core` feature"); std::process::exit(1) }
        }
        Some("--transcribe") => { transcribe_cli(&args[2..], &cfg, &secrets); return; }
        // Diagnostics (also used by tests/run_selftest.sh)
        Some("--clip-get") | Some("--primary-get") if is_wayland() => {
            let v = if args[1] == "--clip-get" { wayland::clipboard::get_clipboard() } else { wayland::clipboard::get_primary() };
            println!("{}", v.unwrap_or_else(|| "<none>".into())); return;
        }
        Some("--clip-set") if is_wayland() => {
            // wl-copy forks its own serving process; no need to stay alive.
            wayland::clipboard::set_clipboard(args.get(2).map(|s| s.as_str()).unwrap_or(""))
                .unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
            return;
        }
        Some("--paste") if is_wayland() => {
            // Diagnostic: inject TEXT into the focused Wayland window like a dictation result.
            use platform::{AppContext, Injector};
            let text = args.get(2).cloned().unwrap_or_default();
            let app = wayland::appctx::WaylandAppContext::new().foreground_app();
            let terms = cfg.clone();
            let mut io = wayland::open_injector(cfg.clipboard_restore_ms, Box::new(move |k| terms.is_terminal(k)))
                .unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
            let r = io.insert(&text, &app);
            println!("app={app} method={:?} result={r:?}", io.last_method);
            std::thread::sleep(Duration::from_millis(cfg.clipboard_restore_ms + 800));
            return;
        }
        Some("--clip-get") | Some("--primary-get") => {
            let io = x11::inject::X11Injector::new(0, Box::new(|_| false)).unwrap();
            let v = if args[1] == "--clip-get" { io.read_clipboard() } else { io.read_primary() };
            println!("{}", v.unwrap_or_else(|| "<none>".into())); return;
        }
        Some("--clip-set") => {
            let io = x11::inject::X11Injector::new(0, Box::new(|_| false)).unwrap();
            io.clip.set(args.get(2).cloned()); std::thread::sleep(Duration::from_secs(3600)); return;
        }
        Some("--app") => {
            use platform::AppContext;
            if matches!(platform::detect(), DisplayServer::Wayland { .. }) {
                println!("{}", wayland::appctx::WaylandAppContext::new().foreground_app());
            } else {
                println!("{}", x11::appctx::X11AppContext::new().unwrap().foreground_app());
            }
            return;
        }
        Some("--help") | Some("-h") => {
            println!("saycribe [--detect | --set-token (stdin) | --check]\nconfig: {}/config.json", config_dir().display());
            return;
        }
        _ => {}
    }
    match platform::detect() {
        DisplayServer::X11 => run_x11(cfg, secrets),
        DisplayServer::Wayland { xwayland } => {
            eprintln!("[detect] Wayland (XWayland={xwayland})");
            eprintln!("{}", wayland::limits_report(&wayland::probe()));
            run_wayland(cfg, secrets);
        }
        
        DisplayServer::None => { eprintln!("未检测到图形会话（DISPLAY/WAYLAND_DISPLAY 均未设置）"); std::process::exit(2); }
    }
}

fn run_x11(cfg: Config, secrets: core_stub::secret::LinuxSecretStore) {
    let token = secrets.get();
    if token.is_none() { eprintln!("[warn] 未设置设备 token：saycribe --set-token"); }
    let token_for_core = token.clone();
    let relay: Arc<dyn Relay> = core_stub::relay_http::shared(&cfg.relay_url, token);
    let (tx, rx) = std::sync::mpsc::channel();
    let info = x11::hotkey::spawn(&cfg.hotkey, tx).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    eprintln!("[hotkey] {} keycode={} detectable_autorepeat={}", cfg.hotkey, info.keycode, info.detectable_autorepeat);
    let terms = cfg.clone();
    let mut io = x11::inject::X11Injector::new(cfg.clipboard_restore_ms, Box::new(move |k| terms.is_terminal(k)))
        .unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    io.copy_fallback = cfg.selection_copy_fallback;
    let hud = x11::hud::X11Hud::new().unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    let quit = Arc::new(AtomicBool::new(false));
    let tray = tray::TrayHandle::start(quit.clone());
    let history = Arc::new(core_stub::history::JsonlHistory::new(data_dir().join("history.jsonl"), cfg.save_history));
    let (dictation, audio) = make_dictation(&cfg, token_for_core, relay.clone());
    let mut app = app::App::new(relay, dictation, audio, Box::new(io),
        Box::new(x11::appctx::X11AppContext::new().unwrap()), Box::new(hud), history,
        Arc::new(cfg.clone()), cfg.dictionary.clone(), true);
    eprintln!("[ready] relay={}", cfg.relay_url);
    while !quit.load(Ordering::SeqCst) {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(HotkeyEvent::Pressed) => { eprintln!("[event] pressed"); tray.set_status("听写中"); app.on_press(); }
            Ok(HotkeyEvent::Released) => {
                eprintln!("[event] released");
                let o = app.on_release(); eprintln!("[outcome] {o:?}"); tray.set_status("就绪");
            }
            Ok(HotkeyEvent::Cancelled) => { eprintln!("[event] cancelled"); app.on_cancel(); tray.set_status("就绪"); }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => app.tick(),
            Err(_) => break,
        }
    }
}

/// Real path: core pipeline::Session + PipeWire/Pulse capture.
/// $SAYCRIBE_STUB_TRANSCRIPT → stub (tests without models), $SAYCRIBE_TEST_WAV → WAV instead of mic.
fn make_dictation(cfg: &Config, token: Option<String>, relay: Arc<dyn Relay>)
    -> (Box<dyn core_api::Dictation>, Box<dyn core_api::AudioSource>) {
    let audio: Box<dyn core_api::AudioSource> = match std::env::var("SAYCRIBE_TEST_WAV") {
        Ok(p) => Box::new(audio::WavAudio::new(p)),
        Err(_) => Box::new(audio::PipeAudio::new()),
    };
    if std::env::var_os("SAYCRIBE_STUB_TRANSCRIPT").is_some() {
        eprintln!("[asr] STUB recognizer ($SAYCRIBE_STUB_TRANSCRIPT)");
        return (Box::new(core_stub::recognizer::StubDictation::new(relay)), Box::new(audio::NoAudio));
    }
    #[cfg(feature = "core")]
    { let _ = &relay; (Box::new(core_adapter::CoreDictation::new(core_adapter::relay_client(&cfg.relay_url, token))), audio) }
    #[cfg(not(feature = "core"))]
    { let _ = (cfg, token); (Box::new(core_stub::recognizer::StubDictation::new(relay)), audio) }
}

/// saycribe --transcribe WAV [--clean] [--style S]: realtime-paced recognition (+clean) of a
/// 16 kHz mono WAV through core pipeline::Session; prints raw/clean text and release→done latency.
fn transcribe_cli(a: &[String], cfg: &Config, secrets: &core_stub::secret::LinuxSecretStore) {
    #[cfg(feature = "core")]
    {
        use core_api::{AudioSource, Dictation};
        let Some(wav) = a.first() else { eprintln!("usage: --transcribe WAV [--clean] [--style S]"); std::process::exit(2) };
        let style = a.iter().position(|x| x == "--style").and_then(|i| a.get(i + 1)).cloned().unwrap_or("notes".into());
        let mut d = core_adapter::CoreDictation::new(core_adapter::relay_client(&cfg.relay_url, secrets.get()));
        d.clean = a.iter().any(|x| x == "--clean");
        let secs = audio::read_wav16k(wav).map(|p| p.len() as f64 / 16000.0).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
        let sink = d.begin(&style, &cfg.dictionary).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
        let mut au = audio::WavAudio::new(wav.clone());
        au.start(sink).unwrap();
        std::thread::sleep(Duration::from_secs_f64(secs + 0.05)); // "hold" for the whole clip
        let t0 = std::time::Instant::now();
        au.stop();
        match d.finish() {
            Ok(r) => {
                let ms = t0.elapsed().as_millis();
                println!("audio={secs:.2}s segments={} asr_decode_ms={} release_to_done_ms={ms}", r.segments, r.asr_ms);
                println!("raw\t{}", r.raw);
                match r.cleaned { Some(Ok(t)) => println!("clean\t{t}"), Some(Err(e)) => println!("clean_error\t{}", e.user_message()), None => {} }
            }
            Err(e) => { eprintln!("{e}"); std::process::exit(1) }
        }
    }
    #[cfg(not(feature = "core"))]
    { let _ = (a, cfg, secrets); eprintln!("built without the `core` feature"); std::process::exit(1) }
}

struct StderrHud;
impl platform::Hud for StderrHud {
    fn show(&mut self, s: platform::HudState) { eprintln!("[hud] {s:?}"); }
}

fn is_wayland() -> bool { matches!(platform::detect(), DisplayServer::Wayland { .. }) }

fn run_wayland(cfg: Config, secrets: core_stub::secret::LinuxSecretStore) {
    let caps = wayland::probe();
    if !caps.wayland_display {
        eprintln!("WAYLAND_DISPLAY 未设置"); std::process::exit(2);
    }
    if !caps.wl_copy && !caps.xclip && !caps.portal_remote_desktop {
        eprintln!("需要 wl-clipboard、xclip 或 RemoteDesktop portal 之一"); std::process::exit(2);
    }
    let token = secrets.get();
    if token.is_none() { eprintln!("[warn] 未设置设备 token：saycribe --set-token"); }
    let token_for_core = token.clone();
    let relay: Arc<dyn Relay> = core_stub::relay_http::shared(&cfg.relay_url, token);
    let (tx, rx) = std::sync::mpsc::channel();
    let quit = Arc::new(AtomicBool::new(false));
    let trigger = wayland::portal::preferred_trigger_from_hotkey(&cfg.hotkey);
    let fifo = wayland::hotkey::spawn(tx, quit.clone(), &trigger)
        .unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    if let Some(ref f) = fifo {
        // SAFETY: single-threaded startup before worker threads read the var.
        unsafe { std::env::set_var("SAYCRIBE_TOGGLE_FIFO", f); }
    }
    let terms = cfg.clone();
    let io = wayland::open_injector(cfg.clipboard_restore_ms, Box::new(move |k| terms.is_terminal(k)))
        .unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1) });
    let hud: Box<dyn platform::Hud> = if std::env::var_os("DISPLAY").is_some() {
        match x11::hud::X11Hud::new() {
            Ok(h) => Box::new(h),
            Err(_) => Box::new(StderrHud),
        }
    } else {
        Box::new(StderrHud)
    };
    let tray = tray::TrayHandle::start(quit.clone());
    let history = Arc::new(core_stub::history::JsonlHistory::new(data_dir().join("history.jsonl"), cfg.save_history));
    let (dictation, audio) = make_dictation(&cfg, token_for_core, relay.clone());
    let mut app = app::App::new(relay, dictation, audio, Box::new(io),
        Box::new(wayland::appctx::WaylandAppContext::new()), hud, history,
        Arc::new(cfg.clone()), cfg.dictionary.clone(), true);
    match &fifo {
        Some(f) => eprintln!("[ready] wayland relay={} hotkey=fifo:{}", cfg.relay_url, f.display()),
        None => eprintln!("[ready] wayland relay={} hotkey=GlobalShortcuts({})", cfg.relay_url, trigger),
    }
    while !quit.load(Ordering::SeqCst) {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(HotkeyEvent::Pressed) => { eprintln!("[event] pressed"); tray.set_status("听写中"); app.on_press(); }
            Ok(HotkeyEvent::Released) => {
                eprintln!("[event] released");
                let o = app.on_release(); eprintln!("[outcome] {o:?}"); tray.set_status("就绪");
            }
            Ok(HotkeyEvent::Cancelled) => { eprintln!("[event] cancelled"); app.on_cancel(); tray.set_status("就绪"); }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => app.tick(),
            Err(_) => break,
        }
    }
    if let Some(ref f) = fifo { wayland::hotkey::cleanup_fifo(f); }
}

fn relay_bench(cfg: &Config, secrets: &core_stub::secret::LinuxSecretStore) {
    use std::time::Instant;
    let r = core_stub::relay_http::HttpRelay::new(&cfg.relay_url, secrets.get());
    for label in ["cold", "warm1", "warm2", "warm3"] {
        let t0 = Instant::now();
        let ping = r.ping();
        let ping_ms = t0.elapsed().as_millis();
        let t1 = Instant::now();
        let me = r.me();
        let me_ms = t1.elapsed().as_millis();
        let t2 = Instant::now();
        let clean = r.clean_session(
            &[core_api::Segment { seq: 0, transcript: "嗯那个我们明天下午三点开会吧就是说讨论一下方案".into(), is_final: true }],
            "notes", &[], &mut |_| {});
        let clean_ms = t2.elapsed().as_millis();
        let p = match &ping { Ok(()) => "ok".into(), Err(e) => e.user_message().to_string() };
        let m = match &me { Ok(s) => s.clone(), Err(e) => e.user_message().to_string() };
        let c = match &clean { Ok(s) => s.clone(), Err(e) => e.user_message().to_string() };
        println!("{label}\tping={ping_ms}ms {p}\tme={me_ms}ms {m}\tclean={clean_ms}ms {c}");
    }
}
