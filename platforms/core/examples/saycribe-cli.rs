//! 自测 CLI：cargo run --release --example saycribe-cli -- <wav> [--models DIR] [--relay URL] [--clean] [--provider cuda] [--chunk-ms 100]
//! token 从环境变量 SAYCRIBE_TOKEN 读取（不落盘）。模拟实时：按 chunk 推 PCM，测 finish()→Done 延迟（松开到出字）。
use saycribe_core::{asr::{read_wav, Recognizer}, models::{ModelManager, sense_voice, silero_vad}, paths::Paths, pipeline::*, relay::RelayClient, token::DeviceToken, Platform};
use std::{path::PathBuf, sync::{mpsc, Arc}, time::Instant};

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let get = |k: &str| a.iter().position(|x| x == k).and_then(|i| a.get(i + 1)).cloned();
    let wav = PathBuf::from(&a[0]);
    let models = get("--models").map(PathBuf::from).unwrap_or_else(|| Paths::standard().unwrap().models_dir());
    let relay_url = get("--relay").unwrap_or_else(|| saycribe_core::config::DEFAULT_RELAY_URL.into());
    let clean = a.iter().any(|x| x == "--clean");
    let chunk_ms: usize = get("--chunk-ms").and_then(|s| s.parse().ok()).unwrap_or(100);
    let mm = ModelManager::new(&models);
    let t = Instant::now();
    let sv = mm.ensure(&sense_voice(), |_, _| {}).expect("SenseVoice");
    let vad = mm.ensure(&silero_vad(), |_, _| {}).expect("VAD").join("silero_vad.onnx");
    println!("models ready in {} ms: {}", t.elapsed().as_millis(), models.display());
    let t = Instant::now();
    let rec = Recognizer::new(&sv, "auto", 4, get("--provider").as_deref()).expect("load");
    println!("recognizer loaded in {} ms", t.elapsed().as_millis());
    let (pcm, sr) = read_wav(&wav).expect("wav"); assert_eq!(sr, 16000, "需要 16kHz wav");
    println!("audio {:.2}s", pcm.len() as f64 / 16000.0);
    // 整段直接识别（短句路径）
    let tr = rec.transcribe(&pcm).unwrap();
    println!("[whole] {} ms: {}", tr.decode_ms, tr.text);
    let token = std::env::var("SAYCRIBE_TOKEN").ok().map(|t| DeviceToken { token: t, platform: Platform::current(), device: "cli".into(), token_id: None });
    let relay = RelayClient::new(&relay_url, token);
    if clean { let t = Instant::now(); match relay.ping() { Ok(_) => println!("ping {} ms", t.elapsed().as_millis()), Err(e) => println!("ping err: {e}") } }
    let engine = Arc::new(Engine { recognizer: Arc::new(rec), vad_model: vad, relay, min_silence: 0.45, max_concurrent: 3 });
    let (tx, rx) = mpsc::channel();
    let t0 = Arc::new(std::sync::Mutex::new(Instant::now()));
    let t0c = t0.clone();
    let sink: EventSink = Arc::new(move |e| { let ms = t0c.lock().unwrap().elapsed().as_millis(); match &e { SessionEvent::Done { .. } => { tx.send((ms, e)).ok(); } _ => println!("  +{ms}ms {e:?}") } });
    let s = Session::start(engine, SessionOptions { style: Some("notes".into()), dictionary: vec![], clean }, sink).unwrap();
    let chunk = 16 * chunk_ms;
    for c in pcm.chunks(chunk) { s.push(c); std::thread::sleep(std::time::Duration::from_millis(chunk_ms as u64)); }
    *t0.lock().unwrap() = Instant::now();
    s.finish();
    let (ms, done) = rx.recv().unwrap();
    println!("[release→Done] {ms} ms\n{done:#?}");
    s.join();
}
