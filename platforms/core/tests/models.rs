//! ModelManager：本地 HTTP 服务模拟 Range 续传、中途断线、错误 sha、多地址回退。
use saycribe_core::models::{sha256_file, ModelFile, ModelManager, ModelSpec};
use std::io::{BufRead, BufReader, Write};
use std::sync::{atomic::{AtomicUsize, Ordering}, Arc, Mutex};

fn data() -> Vec<u8> { (0..200_000u32).map(|i| (i * 31 % 251) as u8).collect() }
fn sha(b: &[u8]) -> String { use sha2::Digest; hex::encode(sha2::Sha256::digest(b)) }

/// mode: "ok" 正常；"cut" 第一次只发一半就断；"bad" 发错误内容；"404"
struct Srv { url: String, ranges: Arc<Mutex<Vec<Option<u64>>>>, hits: Arc<AtomicUsize> }
fn serve(mode: &'static str) -> Srv {
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/f.bin", l.local_addr().unwrap());
    let ranges = Arc::new(Mutex::new(vec![])); let hits = Arc::new(AtomicUsize::new(0));
    let (r2, h2) = (ranges.clone(), hits.clone());
    std::thread::spawn(move || for s in l.incoming() { let mut s = s.unwrap();
        let mut rd = BufReader::new(s.try_clone().unwrap()); let mut from = None;
        loop { let mut line = String::new(); if rd.read_line(&mut line).unwrap() == 0 { break; }
            let lw = line.to_ascii_lowercase();
            if let Some(v) = lw.strip_prefix("range: bytes=") { from = v.trim().trim_end_matches('-').parse().ok(); }
            if line == "\r\n" { break; } }
        let n = h2.fetch_add(1, Ordering::SeqCst); r2.lock().unwrap().push(from);
        if mode == "404" { let _ = s.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"); continue; }
        let mut d = data(); if mode == "bad" { d[10] ^= 1; }
        let st = from.unwrap_or(0) as usize; let body = &d[st..];
        let head = if from.is_some() { format!("HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {st}-{}/{}\r\n", d.len()-1, d.len()) } else { "HTTP/1.1 200 OK\r\n".into() };
        let _ = s.write_all(format!("{head}Content-Length: {}\r\nConnection: close\r\n\r\n", body.len()).as_bytes());
        if mode == "cut" && n == 0 { let _ = s.write_all(&body[..body.len()/2]); let _ = s.flush(); drop(s); continue; }
        let _ = s.write_all(body);
    });
    Srv { url, ranges, hits }
}
fn spec(urls: Vec<String>, sha: String) -> ModelSpec {
    ModelSpec { id: "m".into(), archive: None, files: vec![ModelFile { name: "f.bin".into(), size: 200_000, sha256: sha, urls }] }
}
fn tmp(n: &str) -> std::path::PathBuf { let p = std::env::temp_dir().join(format!("saycribe-mm-{n}-{}", std::process::id())); let _ = std::fs::remove_dir_all(&p); p }

#[test] fn resume_after_cut() {
    let s = serve("cut"); let root = tmp("cut"); let mm = ModelManager::new(&root);
    let dir = mm.ensure(&spec(vec![s.url.clone()], sha(&data())), |_, _| {}).unwrap();
    assert_eq!(std::fs::read(dir.join("f.bin")).unwrap(), data());
    let r = s.ranges.lock().unwrap().clone();
    assert_eq!(r.len(), 2); assert_eq!(r[0], None); assert_eq!(r[1], Some(100_000)); // 第二次从断点续传
    assert!(!dir.join("f.bin.part").exists()); let _ = std::fs::remove_dir_all(root);
}
#[test] fn resume_existing_part() {
    let s = serve("ok"); let root = tmp("part"); std::fs::create_dir_all(root.join("m")).unwrap();
    std::fs::write(root.join("m/f.bin.part"), &data()[..50_000]).unwrap();
    let mm = ModelManager::new(&root);
    mm.ensure(&spec(vec![s.url.clone()], sha(&data())), |_, _| {}).unwrap();
    assert_eq!(s.ranges.lock().unwrap().clone(), vec![Some(50_000)]);
    assert!(mm.verify(&spec(vec![], sha(&data())))); let _ = std::fs::remove_dir_all(root);
}
#[test] fn bad_sha_falls_back_to_next_url() {
    let bad = serve("bad"); let nf = serve("404"); let good = serve("ok"); let root = tmp("fb"); let mm = ModelManager::new(&root);
    let dir = mm.ensure(&spec(vec![nf.url.clone(), bad.url.clone(), good.url.clone()], sha(&data())), |_, _| {}).unwrap();
    assert_eq!(sha256_file(&dir.join("f.bin")).unwrap(), sha(&data()));
    assert_eq!((nf.hits.load(Ordering::SeqCst), bad.hits.load(Ordering::SeqCst), good.hits.load(Ordering::SeqCst)), (1, 1, 1));
    let _ = std::fs::remove_dir_all(root);
}
#[test] fn bad_sha_never_installs() {
    let bad = serve("bad"); let root = tmp("bad"); let mm = ModelManager::new(&root);
    assert!(mm.ensure(&spec(vec![bad.url.clone()], sha(&data())), |_, _| {}).is_err());
    assert!(!root.join("m/f.bin").exists()); assert!(!root.join("m/f.bin.part").exists());
    let _ = std::fs::remove_dir_all(root);
}

/// 真实网络（默认忽略）：`cargo test --test models -- --ignored`
#[test] #[ignore] fn real_download_tokens_hf() {
    use saycribe_core::models::sense_voice;
    let root = tmp("real-tok"); let mm = ModelManager::new(&root);
    let mut sv = sense_voice(); sv.files.retain(|f| f.name == "tokens.txt"); sv.archive = None;
    let t = std::time::Instant::now(); mm.ensure(&sv, |_, _| {}).unwrap(); eprintln!("tokens.txt {:?}", t.elapsed());
    assert!(mm.verify(&sv)); let _ = std::fs::remove_dir_all(root);
}
#[test] #[ignore] fn real_download_silero_github() {
    use saycribe_core::models::silero_vad;
    let root = tmp("real-vad"); let mm = ModelManager::new(&root);
    let t = std::time::Instant::now(); mm.ensure(&silero_vad(), |_, _| {}).unwrap(); eprintln!("silero_vad {:?}", t.elapsed());
    assert!(mm.verify(&silero_vad())); let _ = std::fs::remove_dir_all(root);
}
