#!/usr/bin/env python3
"""Mock Saycribe relay following docs/中转接口.md v1.1 (for local self-tests only).
Usage: mock_relay.py PORT [TOKEN]   (default token: sct_test)
Fault injection inside transcript: '#502once' (502 then OK), '#504' (always 504),
'#429', '#503', '#slow' (sleep 1s). Requests are appended to $MOCK_LOG (JSONL)."""
import json, os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]); TOKEN = sys.argv[2] if len(sys.argv) > 2 else "sct_test"
LOG = os.environ.get("MOCK_LOG"); seen_502 = set()

def clean(t):
    t = re.sub(r"(嗯|呃|那个|就是说)", "", t)
    t = re.sub(r"#\w+", "", t).strip()
    if t and t[-1] not in "。！？.!?": t += "。"
    return t if re.sub(r"[。\s]", "", t) else ""

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def send(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def err(self, code, c): self.send(code, {"error": {"code": c, "message": c}})
    def authed(self):
        a = self.headers.get("Authorization", "")
        if a == "Bearer sct_revoked": self.err(403, "revoked"); return False
        if a != f"Bearer {TOKEN}": self.err(401, "unauthorized"); return False
        return True
    def do_GET(self):
        if self.path in ("/v1/ping", "/health"): return self.send(200, {"ok": True, "api_version": "1.1"})
        if self.path == "/v1/me":
            if self.authed(): self.send(200, {"token_id": "t_mock", "user": "zjh", "platform": "linux", "device": "linux-test"})
            return
        self.err(404, "not_found")
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); raw = self.rfile.read(n)
        if not self.authed(): return
        if n > 65536: return self.err(413, "too_large")
        try: b = json.loads(raw)
        except Exception: return self.err(400, "bad_request")
        if LOG:
            with open(LOG, "a") as f: f.write(json.dumps({"path": self.path, **b}, ensure_ascii=False) + "\n")
        src = b.get("transcript") or b.get("selection") or ""
        if len(src) > 8000: return self.err(413, "too_large")
        for tag, code, c in (("#504", 504, "upstream_timeout"), ("#429", 429, "rate_limited"), ("#503", 503, "unavailable")):
            if tag in src: return self.err(code, c)
        if "#502once" in src and src not in seen_502: seen_502.add(src); return self.err(502, "upstream_error")
        if "#slow" in src: time.sleep(1)
        if self.path == "/v1/clean":
            if "transcript" not in b: return self.err(400, "bad_request")
            text = clean(b["transcript"])
        elif self.path == "/v1/edit":
            if "selection" not in b or "instruction" not in b: return self.err(400, "bad_request")
            text = f"{b['selection']}（已按“{b['instruction']}”改写）"
        elif self.path == "/v1/translate":
            text = f"[{b.get('direction','')}] {b.get('transcript','')}"
        else: return self.err(404, "not_found")
        meta = {"session_id": b.get("session_id"), "seq": b.get("seq"), "model": "mock", "prompt_version": "mock"}
        if b.get("stream"):
            self.send_response(200); self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close"); self.end_headers()
            for i in range(0, len(text), 4):
                self.wfile.write(f"event: delta\ndata: {json.dumps({'text': text[i:i+4]}, ensure_ascii=False)}\n\n".encode()); self.wfile.flush()
            self.wfile.write(f"event: done\ndata: {json.dumps({'text': text, **meta}, ensure_ascii=False)}\n\n".encode())
            self.close_connection = True
            return
        self.send(200, {"text": text, **meta, "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}, "timing": {"upstream_ms": 1, "total_ms": 1}})

ThreadingHTTPServer.handle_error = lambda *a: None  # client closed keep-alive
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
