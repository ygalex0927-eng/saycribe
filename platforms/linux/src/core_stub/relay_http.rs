//! Relay client following docs/中转接口.md v1.1 (HttpRelay kept for edit/ping; core RelayClient does clean).
use crate::core_api::{Relay, RelayError, Segment};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::sync::Arc;
use std::time::Duration;

pub struct HttpRelay {
    base: String,
    token: Option<String>,
    agent: ureq::Agent,
    session_counter: std::sync::atomic::AtomicU64,
}

/// Characters of already-cleaned text sent as `context` (protocol: last 300).
pub const CONTEXT_CHARS: usize = 300;
/// Max concurrent segment requests (protocol: ≤3).
pub const MAX_CONCURRENCY: usize = 3;
/// Stream when one segment is at least this long (chars).
pub const STREAM_THRESHOLD: usize = 120;

pub fn tail_chars(s: &str, n: usize) -> String {
    let count = s.chars().count();
    s.chars().skip(count.saturating_sub(n)).collect()
}

/// Overall timeout: 4 s + 0.02 s per char (same as Mac).
pub fn overall_timeout(chars: usize) -> Duration {
    Duration::from_millis(4000 + (chars as u64) * 20)
}

/// Map an HTTP status + body to a RelayError.
pub fn map_status(status: u16, body: &str) -> RelayError {
    let code = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| v["error"]["code"].as_str().map(String::from))
        .unwrap_or_default();
    match (status, code.as_str()) {
        (401, _) | (_, "unauthorized") => RelayError::Unauthorized,
        (403, _) | (_, "revoked") => RelayError::Revoked,
        (413, _) | (_, "too_large") => RelayError::TooLarge,
        (429, _) | (_, "rate_limited") => RelayError::RateLimited,
        (502, _) | (504, _) | (_, "upstream_error") | (_, "upstream_timeout") => {
            RelayError::Upstream(code)
        }
        (503, _) | (_, "unavailable") => RelayError::Unavailable,
        (400, _) => RelayError::BadRequest(body.to_string()),
        _ => RelayError::Protocol(format!("HTTP {status}: {body}")),
    }
}

/// Parse an SSE stream; returns done.text. Calls on_delta per delta event.
pub fn parse_sse<R: BufRead>(r: R, on_delta: &mut dyn FnMut(&str)) -> Result<Value, RelayError> {
    let mut event = String::new();
    let mut data = String::new();
    for line in r.lines() {
        let line = line.map_err(|e| RelayError::Offline(e.to_string()))?;
        if line.is_empty() {
            if !data.is_empty() {
                let v: Value = serde_json::from_str(&data)
                    .map_err(|e| RelayError::Protocol(format!("bad sse json: {e}")))?;
                match event.as_str() {
                    "delta" => on_delta(v["text"].as_str().unwrap_or("")),
                    "done" => return Ok(v),
                    "error" => {
                        let code = v["error"]["code"].as_str().unwrap_or("").to_string();
                        return Err(match code.as_str() {
                            "upstream_error" | "upstream_timeout" => RelayError::Upstream(code),
                            "unavailable" => RelayError::Unavailable,
                            "rate_limited" => RelayError::RateLimited,
                            _ => RelayError::Protocol(code),
                        });
                    }
                    _ => {}
                }
            }
            event.clear();
            data.clear();
        } else if let Some(e) = line.strip_prefix("event:") {
            event = e.trim().to_string();
        } else if let Some(d) = line.strip_prefix("data:") {
            if !data.is_empty() {
                data.push('\n');
            }
            data.push_str(d.trim_start());
        }
    }
    Err(RelayError::Protocol("sse ended without done".into()))
}

/// Merge `(seq, text)` results in seq order, skipping empty texts.
pub fn merge_by_seq(mut parts: Vec<(u32, String)>) -> String {
    parts.sort_by_key(|p| p.0);
    let mut out = String::new();
    for (_, t) in parts {
        let t = t.trim();
        if t.is_empty() {
            continue;
        }
        if !out.is_empty() {
            let last = out.chars().last().unwrap();
            let first = t.chars().next().unwrap();
            if last.is_ascii_alphanumeric() && first.is_ascii_alphanumeric() {
                out.push(' ');
            } else if last != '\n' && "。！？.!?".contains(last) {
                // CJK sentence boundary: no separator needed
            }
        }
        out.push_str(t);
    }
    out
}

impl HttpRelay {
    pub fn new(base: &str, token: Option<String>) -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(3))
            .max_idle_connections_per_host(4) // keep-alive pool
            .build();
        HttpRelay {
            base: base.trim_end_matches('/').to_string(),
            token,
            agent,
            session_counter: Default::default(),
        }
    }

    fn new_session_id(&self) -> String {
        let n = self.session_counter.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        format!("{:x}-{:x}-{}", t, std::process::id(), n)
    }

    fn req(&self, method: &str, path: &str, timeout: Duration) -> ureq::Request {
        let mut r = self
            .agent
            .request(method, &format!("{}{}", self.base, path))
            .timeout(timeout)
            .set("Content-Type", "application/json; charset=utf-8");
        if let Some(t) = &self.token {
            r = r.set("Authorization", &format!("Bearer {t}"));
        }
        r
    }

    fn call_once(&self, path: &str, body: &Value, chars: usize, stream: bool,
                 on_delta: &mut dyn FnMut(&str)) -> Result<Value, RelayError> {
        let resp = self.req("POST", path, overall_timeout(chars)).send_json(body.clone());
        match resp {
            Ok(r) => {
                if stream && r.content_type() == "text/event-stream" {
                    parse_sse(BufReader::new(r.into_reader()), on_delta)
                } else {
                    r.into_json::<Value>().map_err(|e| RelayError::Protocol(e.to_string()))
                }
            }
            Err(ureq::Error::Status(code, r)) => {
                Err(map_status(code, &r.into_string().unwrap_or_default()))
            }
            Err(ureq::Error::Transport(t)) => Err(RelayError::Offline(t.to_string())),
        }
    }

    /// One call with the protocol's "retry once on 502/504".
    fn call(&self, path: &str, body: Value, chars: usize, stream: bool,
            on_delta: &mut dyn FnMut(&str)) -> Result<Value, RelayError> {
        match self.call_once(path, &body, chars, stream, on_delta) {
            Err(RelayError::Upstream(_)) => self.call_once(path, &body, chars, stream, on_delta),
            other => other,
        }
    }

    fn text_of(v: &Value) -> Result<String, RelayError> {
        v["text"].as_str().map(String::from)
            .ok_or_else(|| RelayError::Protocol(format!("no text in {v}")))
    }
}

impl Relay for HttpRelay {
    fn ping(&self) -> Result<(), RelayError> {
        match self.req("GET", "/v1/ping", Duration::from_secs(8)).call() {
            Ok(r) => {
                // v1.1 returns {"ok":true,"api_version":"1.1"}; tolerate missing api_version (old mock).
                let _ = r.into_json::<Value>();
                Ok(())
            }
            Err(ureq::Error::Status(c, r)) => Err(map_status(c, &r.into_string().unwrap_or_default())),
            Err(ureq::Error::Transport(t)) => Err(RelayError::Offline(t.to_string())),
        }
    }

    fn me(&self) -> Result<String, RelayError> {
        match self.req("GET", "/v1/me", Duration::from_secs(4)).call() {
            Ok(r) => {
                let v: Value = r.into_json().map_err(|e| RelayError::Protocol(e.to_string()))?;
                Ok(format!("{}/{}/{}", v["user"].as_str().unwrap_or("?"), v["platform"].as_str().unwrap_or("?"), v["device"].as_str().unwrap_or("?")))
            }
            Err(ureq::Error::Status(c, r)) => Err(map_status(c, &r.into_string().unwrap_or_default())),
            Err(ureq::Error::Transport(t)) => Err(RelayError::Offline(t.to_string())),
        }
    }

    fn clean_session(&self, segments: &[Segment], style: &str, dictionary: &[String],
                     on_delta: &mut dyn FnMut(&str)) -> Result<String, RelayError> {
        let session = self.new_session_id();
        let mut done: Vec<(u32, String)> = Vec::new();
        // Single segment: optionally stream for HUD preview.
        if segments.len() == 1 {
            let s = &segments[0];
            let stream = s.transcript.chars().count() >= STREAM_THRESHOLD;
            let body = json!({"transcript": s.transcript, "style": style, "dictionary": dictionary,
                "session_id": session, "seq": s.seq, "final": true, "stream": stream});
            let v = self.call("/v1/clean", body, s.transcript.chars().count(), stream, on_delta)?;
            return Self::text_of(&v);
        }
        // Long recording: waves of ≤3 concurrent requests; context = merged tail.
        for wave in segments.chunks(MAX_CONCURRENCY) {
            let context = tail_chars(&merge_by_seq(done.clone()), CONTEXT_CHARS);
            let results: Vec<Result<(u32, String), RelayError>> = std::thread::scope(|sc| {
                let hs: Vec<_> = wave.iter().map(|s| {
                    let body = json!({"transcript": s.transcript, "style": style,
                        "dictionary": dictionary, "context": context, "session_id": session,
                        "seq": s.seq, "final": s.is_final, "stream": false});
                    let n = s.transcript.chars().count();
                    let seq = s.seq;
                    sc.spawn(move || {
                        let v = self.call("/v1/clean", body, n, false, &mut |_| {})?;
                        let echoed = v["seq"].as_u64().map(|x| x as u32).unwrap_or(seq);
                        Ok((echoed, Self::text_of(&v)?))
                    })
                }).collect();
                hs.into_iter().map(|h| h.join().unwrap()).collect()
            });
            for r in results {
                done.push(r?);
            }
            on_delta(&merge_by_seq(done.clone()));
        }
        Ok(merge_by_seq(done))
    }

    fn edit(&self, selection: &str, instruction: &str) -> Result<String, RelayError> {
        let body = json!({"selection": selection, "instruction": instruction});
        let n = selection.chars().count() + instruction.chars().count();
        Self::text_of(&self.call("/v1/edit", body, n, false, &mut |_| {})?)
    }
}

pub fn shared(base: &str, token: Option<String>) -> Arc<dyn Relay> {
    Arc::new(HttpRelay::new(base, token))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn status_mapping() {
        assert_eq!(map_status(401, r#"{"error":{"code":"unauthorized","message":""}}"#), RelayError::Unauthorized);
        assert_eq!(map_status(403, ""), RelayError::Revoked);
        assert_eq!(map_status(429, ""), RelayError::RateLimited);
        assert!(matches!(map_status(504, r#"{"error":{"code":"upstream_timeout"}}"#), RelayError::Upstream(_)));
        assert_eq!(map_status(503, ""), RelayError::Unavailable);
        assert_eq!(map_status(413, ""), RelayError::TooLarge);
    }
    #[test]
    fn sse_parse() {
        let s = "event: delta\ndata: {\"text\":\"整\"}\n\nevent: delta\ndata: {\"text\":\"理\"}\n\nevent: done\ndata: {\"text\":\"整理好了\",\"seq\":0}\n\n";
        let mut d = String::new();
        let v = parse_sse(s.as_bytes(), &mut |t| d.push_str(t)).unwrap();
        assert_eq!(d, "整理");
        assert_eq!(v["text"], "整理好了");
        let e = "event: error\ndata: {\"error\":{\"code\":\"upstream_timeout\",\"message\":\"x\"}}\n\n";
        assert!(matches!(parse_sse(e.as_bytes(), &mut |_| {}), Err(RelayError::Upstream(_))));
    }
    #[test]
    fn merge_order_and_tail() {
        let m = merge_by_seq(vec![(2, "丙。".into()), (0, "甲。".into()), (1, "".into()), (3, "end".into())]);
        assert_eq!(m, "甲。丙。end");
        assert_eq!(merge_by_seq(vec![(1, "world".into()), (0, "hello".into())]), "hello world");
        assert_eq!(tail_chars("一二三四五", 2), "四五");
        assert_eq!(overall_timeout(100), Duration::from_millis(6000));
    }
    #[test]
    fn offline_is_offline() {
        let r = HttpRelay::new("http://127.0.0.1:1", None);
        assert!(matches!(r.ping(), Err(RelayError::Offline(_))));
        assert_eq!(RelayError::Offline("x".into()).user_message(), "需要联网");
    }

    /// Runs only when MOCK_RELAY_URL is set (tests/run_selftest.sh starts the mock).
    #[test]
    fn against_mock_relay() {
        let Ok(url) = std::env::var("MOCK_RELAY_URL") else { eprintln!("skip: MOCK_RELAY_URL unset"); return; };
        let ok = HttpRelay::new(&url, Some("sct_test".into()));
        assert!(ok.ping().is_ok());
        assert_eq!(ok.me().unwrap(), "zjh/linux-test");
        assert_eq!(HttpRelay::new(&url, None).me(), Err(RelayError::Unauthorized));
        assert_eq!(HttpRelay::new(&url, Some("sct_revoked".into())).me(), Err(RelayError::Revoked));
        let seg = |i: u32, t: &str, f: bool| Segment { seq: i, transcript: t.into(), is_final: f };
        let mut deltas = 0;
        assert_eq!(ok.clean_session(&[seg(0, "嗯那个明天下午吃饭", true)], "chat", &[], &mut |_| deltas += 1).unwrap(), "明天下午吃饭。");
        assert_eq!(deltas, 0, "short input must be non-streaming");
        assert_eq!(ok.clean_session(&[seg(0, "嗯呃", true)], "chat", &[], &mut |_| {}).unwrap(), "");
        // streaming (≥120 chars)
        let long = "这是一段很长的话".repeat(20);
        let mut acc = String::new();
        let out = ok.clean_session(&[seg(0, &long, true)], "notes", &[], &mut |d| acc.push_str(d)).unwrap();
        assert_eq!(out, format!("{long}。")); assert_eq!(acc, out);
        // retry once on 502
        assert_eq!(ok.clean_session(&[seg(0, "重试一次#502once", true)], "chat", &[], &mut |_| {}).unwrap(), "重试一次。");
        assert!(matches!(ok.clean_session(&[seg(0, "x#504", true)], "chat", &[], &mut |_| {}), Err(RelayError::Upstream(_))));
        assert_eq!(ok.clean_session(&[seg(0, "x#429", true)], "chat", &[], &mut |_| {}), Err(RelayError::RateLimited));
        assert_eq!(ok.clean_session(&[seg(0, "x#503", true)], "chat", &[], &mut |_| {}), Err(RelayError::Unavailable));
        // long recording: 5 segments, slow ones finish out of order, merged by seq
        let segs = vec![seg(0, "第一段#slow", false), seg(1, "第二段", false), seg(2, "嗯第三段", false),
                        seg(3, "第四段#slow", false), seg(4, "第五段", true)];
        let t = std::time::Instant::now();
        assert_eq!(ok.clean_session(&segs, "notes", &["Saycribe".into()], &mut |_| {}).unwrap(), "第一段。第二段。第三段。第四段。第五段。");
        assert!(t.elapsed() < Duration::from_millis(2600), "segments should run concurrently: {:?}", t.elapsed());
        assert_eq!(ok.edit("你好", "改礼貌点").unwrap(), "你好（已按“改礼貌点”改写）");
    }
}
