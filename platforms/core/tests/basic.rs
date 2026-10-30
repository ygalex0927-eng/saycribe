use saycribe_core::{config::*, dictionary::Dictionary, error::RelayErrorKind, history::*, paths::Paths, relay::*, token::*, tone::AppToneMap, Platform};
use std::io::{BufRead, BufReader, Write};

fn tmp() -> (tempfile::TempDir, Paths) { let d = tempfile::tempdir().unwrap(); let p = Paths::under(d.path()); p.ensure().unwrap(); (d, p) }

#[test] fn config_roundtrip_default_relay() {
    let (_d, p) = tmp();
    let mut c = Config::load(&p).unwrap(); assert_eq!(c.relay_url, "https://saycribe-api.motomotos.com");
    c.relay_url = "http://x".into(); c.app_tones.set("Code.exe", "code"); c.save(&p).unwrap();
    let c2 = Config::load(&p).unwrap(); assert_eq!(c2.relay_url, "http://x"); assert_eq!(c2.app_tones.style_for("code.EXE", "notes"), "code");
}

#[test] fn token_store_file() {
    let (_d, p) = tmp(); let s = FileTokenStore::new(p.token_file());
    assert!(s.read().unwrap().is_none());
    let t = DeviceToken { token: "sct_x".into(), platform: Platform::Linux, device: "d".into(), token_id: Some("t_1".into()) };
    s.write(&t).unwrap(); assert_eq!(s.read().unwrap(), Some(t));
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; assert_eq!(std::fs::metadata(p.token_file()).unwrap().permissions().mode() & 0o777, 0o600); }
    assert!(std::fs::read_to_string(p.token_file()).unwrap().contains("\"platform\":\"linux\""));
    s.delete().unwrap(); assert!(s.read().unwrap().is_none()); s.delete().unwrap();
}

#[test] fn history_disable_prune_export() {
    let (_d, p) = tmp();
    let off = History::open(&p, false, 30); off.append(&HistoryEntry::new("x")).unwrap(); assert!(off.list().unwrap().is_empty());
    let h = History::open(&p, true, 7);
    let mut old = HistoryEntry::new("旧"); old.time = chrono::Utc::now() - chrono::Duration::days(10); h.append(&old).unwrap();
    let mut e = HistoryEntry::new("原文, \"引号\""); e.text = Some("整理后".into()); h.append(&e).unwrap();
    assert_eq!(h.prune().unwrap(), 1); assert_eq!(h.list().unwrap().len(), 1);
    assert!(h.export(ExportFormat::Csv).unwrap().contains("\"原文, \"\"引号\"\"\""));
    assert!(h.export(ExportFormat::Markdown).unwrap().contains("整理后"));
    assert!(h.export(ExportFormat::Json).unwrap().contains("整理后"));
}

#[test] fn dictionary_learn() {
    let mut d = Dictionary::default();
    let c = d.learn_from_edit("我用深度求索写代码", "我用DeepSeek写代码"); assert!(c.contains(&"DeepSeek".to_string()));
    assert!(d.words.is_empty()); d.accept("DeepSeek"); assert_eq!(d.words, vec!["DeepSeek"]); assert!(d.candidates.is_empty());
}

#[test] fn tone_defaults() { let m = AppToneMap::with_defaults(); assert_eq!(m.style_for("WeChat.exe", "notes"), "chat"); assert_eq!(m.style_for("unknown", "notes"), "notes"); }

/// 本地 mock 中转：按路径返回固定状态码
fn mock(status: u16, body: &'static str, sse: bool) -> String {
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap(); let addr = l.local_addr().unwrap();
    std::thread::spawn(move || for s in l.incoming().take(4) { let mut s = s.unwrap();
        let mut r = BufReader::new(s.try_clone().unwrap()); let mut len = 0; let mut auth = String::new();
        loop { let mut line = String::new(); r.read_line(&mut line).unwrap(); if line == "\r\n" { break; }
            let ll = line.to_lowercase(); if ll.starts_with("content-length:") { len = ll[15..].trim().parse().unwrap(); } if ll.starts_with("authorization:") { auth = line.clone(); } }
        let mut b = vec![0; len]; std::io::Read::read_exact(&mut r, &mut b).unwrap();
        let ct = if sse { "text/event-stream" } else { "application/json" };
        let body = if status == 200 && !sse { body.replace("ECHO", &String::from_utf8_lossy(&b).replace('"', "'")).replace("AUTH", auth.trim()) } else { body.to_string() };
        write!(s, "HTTP/1.1 {status} X\r\nContent-Type: {ct}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap(); });
    format!("http://{addr}")
}

fn tok() -> Option<DeviceToken> { Some(DeviceToken { token: "sct_t".into(), platform: Platform::Windows, device: "d".into(), token_id: None }) }

#[test] fn relay_ok_and_seq() {
    let c = RelayClient::new(&mock(200, r#"{"text":"ECHO|AUTH","seq":2,"session_id":"s","usage":{"total_tokens":5}}"#, false), tok());
    let req = RelayRequest::Clean { transcript: "嗯三点不对四点".into(), style: Some("chat".into()), dictionary: vec![], context: None, meta: SegmentMeta { session_id: Some("s".into()), seq: Some(2), r#final: Some(true) } };
    let r = c.call(&req).unwrap();
    assert_eq!(r.seq, Some(2)); assert_eq!(r.usage.total_tokens, 5);
    assert!(r.text.contains("'seq':2") && r.text.contains("'final':true") && r.text.contains("Bearer sct_t"), "{}", r.text);
}

#[test] fn relay_stream() {
    let body = "event: delta\ndata: {\"text\":\"四\"}\n\nevent: delta\ndata: {\"text\":\"点\"}\n\nevent: done\ndata: {\"text\":\"四点\",\"seq\":0}\n\n";
    let c = RelayClient::new(&mock(200, body, true), tok());
    let mut d = String::new(); let r = c.call_stream(&RelayRequest::clean("x", None, vec![]), |s| d.push_str(s)).unwrap();
    assert_eq!(d, "四点"); assert_eq!(r.text, "四点");
}

#[test] fn relay_error_classes() {
    for (st, code, k) in [(401, "unauthorized", RelayErrorKind::Unauthorized), (403, "revoked", RelayErrorKind::Revoked), (429, "rate_limited", RelayErrorKind::RateLimited), (502, "upstream_error", RelayErrorKind::Upstream), (504, "upstream_timeout", RelayErrorKind::Timeout)] {
        let body: &'static str = Box::leak(format!(r#"{{"error":{{"code":"{code}","message":"m"}}}}"#).into_boxed_str());
        let c = RelayClient::new(&mock(st, body, false), tok());
        assert_eq!(c.call(&RelayRequest::clean("x", None, vec![])).unwrap_err().relay_kind(), Some(k), "{st}");
    }
    // 断网：连接拒绝
    let port = { let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap(); l.local_addr().unwrap().port() };
    let c = RelayClient::new(&format!("http://127.0.0.1:{port}"), tok());
    let e = c.call(&RelayRequest::clean("x", None, vec![])).unwrap_err();
    assert_eq!(e.relay_kind(), Some(RelayErrorKind::Offline)); assert_eq!(RelayErrorKind::Offline.user_message(), "需要联网");
    // 非阻塞
    let (tx, rx) = std::sync::mpsc::channel();
    c.call_async(RelayRequest::clean("x", None, vec![]), move |r| { tx.send(r.unwrap_err().relay_kind()).unwrap(); });
    assert_eq!(rx.recv().unwrap(), Some(RelayErrorKind::Offline));
}

#[test] fn relay_me_platform() {
    let c = RelayClient::new(&mock(200, r#"{"token_id":"t_1","user":"zjh","device":"win-test","platform":"windows"}"#, false), tok());
    let me = c.me().unwrap(); assert_eq!(me.platform.as_deref(), Some("windows")); assert_eq!(me.device, "win-test");
    let c = RelayClient::new(&mock(200, r#"{"token_id":"t_1","user":"zjh","device":"d"}"#, false), tok());
    assert_eq!(c.me().unwrap().platform, None);
}
