//! Audio capture (platform layer). Real: PulseAudio/PipeWire via `parecord`
//! (or `pw-record`) writing 16 kHz mono s16le to a pipe — no extra C deps.
//! Test: $SAYCRIBE_TEST_WAV streams a 16 kHz mono WAV in real time.
use crate::core_api::{AudioSource, PcmSink};
use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

fn s16le_to_f32(b: &[u8]) -> Vec<f32> {
    b.chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]]) as f32 / 32768.0).collect()
}

/// Pick a capture command available on this system.
pub fn capture_command() -> Option<Vec<String>> {
    let has = |c: &str| std::env::var_os("PATH").map(|p| std::env::split_paths(&p).any(|d| d.join(c).is_file())).unwrap_or(false);
    let v = |a: &[&str]| Some(a.iter().map(|s| s.to_string()).collect());
    if has("parecord") { return v(&["parecord", "--raw", "--format=s16le", "--rate=16000", "--channels=1", "--latency-msec=20"]); }
    if has("pw-record") { return v(&["pw-record", "--format=s16", "--rate=16000", "--channels=1", "-"]); }
    if has("arecord") { return v(&["arecord", "-q", "-t", "raw", "-f", "S16_LE", "-r", "16000", "-c", "1"]); }
    None
}

pub struct PipeAudio { child: Option<Child>, reader: Option<JoinHandle<()>> }
impl PipeAudio { pub fn new() -> Self { PipeAudio { child: None, reader: None } } }
impl AudioSource for PipeAudio {
    fn start(&mut self, mut sink: PcmSink) -> Result<(), String> {
        let cmd = capture_command().ok_or("找不到录音工具（parecord / pw-record / arecord）")?;
        let mut child = Command::new(&cmd[0]).args(&cmd[1..]).stdout(Stdio::piped()).stderr(Stdio::null())
            .spawn().map_err(|e| format!("{}: {e}", cmd[0]))?;
        let mut out = child.stdout.take().unwrap();
        self.reader = Some(std::thread::spawn(move || {
            let mut buf = vec![0u8; 3200]; // 100 ms
            let mut odd: Option<u8> = None;
            loop {
                let n = match out.read(&mut buf) { Ok(0) | Err(_) => break, Ok(n) => n };
                let mut bytes: Vec<u8> = odd.take().into_iter().collect();
                bytes.extend_from_slice(&buf[..n]);
                if bytes.len() % 2 == 1 { odd = bytes.pop(); }
                sink(&s16le_to_f32(&bytes));
            }
        }));
        self.child = Some(child);
        Ok(())
    }
    fn stop(&mut self) {
        if let Some(mut c) = self.child.take() {
            // SIGTERM lets parecord flush what it has buffered.
            unsafe_kill_term(c.id());
            let _ = c.wait();
        }
        if let Some(r) = self.reader.take() { let _ = r.join(); }
    }
}

fn unsafe_kill_term(pid: u32) { let _ = Command::new("kill").arg("-TERM").arg(pid.to_string()).status(); }

/// Streams a WAV file in real time (100 ms chunks) while "recording";
/// on stop, the rest of the file is pushed at once (the speaker finished).
pub struct WavAudio { path: String, stop: Arc<AtomicBool>, th: Option<JoinHandle<()>> }
impl WavAudio {
    pub fn new(path: String) -> Self { WavAudio { path, stop: Arc::new(AtomicBool::new(false)), th: None } }
}
pub fn read_wav16k(path: &str) -> Result<Vec<f32>, String> {
    let b = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
    if b.len() < 12 || &b[0..4] != b"RIFF" || &b[8..12] != b"WAVE" { return Err("not a WAV".into()); }
    let (mut i, mut fmt_ok) = (12, false);
    while i + 8 <= b.len() {
        let id = &b[i..i + 4]; let sz = u32::from_le_bytes([b[i+4], b[i+5], b[i+6], b[i+7]]) as usize;
        let body = &b[i + 8..(i + 8 + sz).min(b.len())];
        if id == b"fmt " {
            let ch = u16::from_le_bytes([body[2], body[3]]); let sr = u32::from_le_bytes([body[4], body[5], body[6], body[7]]);
            let bits = u16::from_le_bytes([body[14], body[15]]);
            if ch != 1 || sr != 16000 || bits != 16 { return Err(format!("需要 16kHz 单声道 16bit WAV（{sr}Hz {ch}ch {bits}bit）")); }
            fmt_ok = true;
        } else if id == b"data" && fmt_ok { return Ok(s16le_to_f32(body)); }
        i += 8 + sz + (sz & 1);
    }
    Err("WAV 无 data 块".into())
}
impl AudioSource for WavAudio {
    fn start(&mut self, mut sink: PcmSink) -> Result<(), String> {
        let pcm = read_wav16k(&self.path)?;
        self.stop.store(false, Ordering::SeqCst);
        let stop = self.stop.clone();
        self.th = Some(std::thread::spawn(move || {
            let mut i = 0;
            while i < pcm.len() {
                if stop.load(Ordering::SeqCst) { sink(&pcm[i..]); return; }
                let e = (i + 1600).min(pcm.len()); sink(&pcm[i..e]); i = e;
                std::thread::sleep(Duration::from_millis(100));
            }
            // file ended while still held: keep feeding silence
            while !stop.load(Ordering::SeqCst) { sink(&[0.0; 1600]); std::thread::sleep(Duration::from_millis(100)); }
        }));
        Ok(())
    }
    fn stop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(t) = self.th.take() { let _ = t.join(); }
    }
}

/// No capture (stub dictation ignores PCM).
pub struct NoAudio;
impl AudioSource for NoAudio {
    fn start(&mut self, _sink: PcmSink) -> Result<(), String> { Ok(()) }
    fn stop(&mut self) {}
}

#[cfg(test)]
mod tests {
    #[test]
    fn s16_conv() { assert_eq!(super::s16le_to_f32(&[0x00, 0x80, 0xff, 0x7f]), vec![-1.0, 32767.0 / 32768.0]); }
}
