#!/usr/bin/env python3
"""Saycribe relay v1 - stdlib only."""
import hashlib, http.client, json, os, queue, secrets, sqlite3, ssl, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
KEY = os.environ.get("DEEPSEEK_API_KEY", "")
ADMIN = os.environ.get("SC_ADMIN_TOKEN", "")
MODEL = os.environ.get("SC_MODEL", "deepseek-flash")
EDIT_MODEL = os.environ.get("SC_EDIT_MODEL", MODEL)
TEMP = float(os.environ.get("SC_TEMPERATURE", "0.2"))
PORT = int(os.environ.get("SC_PORT", "18780"))
DB = os.environ.get("SC_DB", "/var/lib/saycribe-relay/tokens.db")
UP_HOST = "api.deepseek.com"
PROMPT_VERSION = "2026-10-30"
API_VERSION = "1.1"
MAX_CHARS, MAX_BODY, RATE = 8000, 65536, 60

def rd(n): return open(os.path.join(HERE, "prompts", n), encoding="utf-8").read()
P = {k: rd(k + ".md") for k in ("clean", "edit", "translate", "interpret")}
STYLES = json.loads(rd("styles.json"))

_db_lock = threading.Lock()
def db():
    c = sqlite3.connect(DB, check_same_thread=False)
    c.execute("create table if not exists tokens(id text primary key, hash text unique, user text, device text, created real, revoked real)")
    cols=[r[1] for r in c.execute("pragma table_info(tokens)")]
    if "platform" not in cols: c.execute("alter table tokens add column platform text default 'mac'"); c.commit()
    return c
PLATFORMS=("mac","windows","linux","ios","android")
CONN = None
def h(t): return hashlib.sha256(t.encode()).hexdigest()
def issue(user, device, platform):
    if platform not in PLATFORMS: raise ValueError("platform must be one of " + "/".join(PLATFORMS))
    if not user or not device: raise ValueError("user and device required")
    tid = "t_" + secrets.token_hex(4); tok = "sct_" + secrets.token_urlsafe(24)
    with _db_lock:
        CONN.execute("insert into tokens(id,hash,user,device,created,revoked,platform) values(?,?,?,?,?,null,?)", (tid, h(tok), user, device, time.time(), platform)); CONN.commit()
    return tid, tok
def revoke(tid):
    with _db_lock:
        n = CONN.execute("update tokens set revoked=? where id=? and revoked is null", (time.time(), tid)).rowcount; CONN.commit()
    return n
def lookup(tok):
    with _db_lock:
        return CONN.execute("select id,user,device,revoked,platform from tokens where hash=?", (h(tok),)).fetchone()

# upstream keep-alive pool
_pool = queue.LifoQueue()
_ctx = ssl.create_default_context()
def get_conn():
    try: return _pool.get_nowait()
    except queue.Empty: return http.client.HTTPSConnection(UP_HOST, timeout=30, context=_ctx)
def put_conn(c):
    if _pool.qsize() < 8: _pool.put(c)
    else: c.close()

class UpErr(Exception):
    def __init__(s, status, code, msg): s.status, s.code, s.msg = status, code, msg

def upstream(model, system, user, timeout, stream):
    body = json.dumps({"model": model, "temperature": TEMP, "thinking": {"type": "disabled"}, "stream": stream,
                       **({"stream_options": {"include_usage": True}} if stream else {}),
                       "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}).encode()
    hdr = {"Authorization": "Bearer " + KEY, "Content-Type": "application/json", "Connection": "keep-alive"}
    for attempt in (0, 1):
        c = get_conn(); c.timeout = timeout
        try:
            if c.sock: c.sock.settimeout(timeout)
            c.request("POST", "/chat/completions", body, hdr); r = c.getresponse(); return c, r
        except (TimeoutError, OSError) as e:
            c.close()
            if isinstance(e, TimeoutError) or "timed out" in str(e): raise UpErr(504, "upstream_timeout", "model timeout")
            if attempt: raise UpErr(502, "upstream_error", "connect failed")
        except http.client.HTTPException:
            c.close()
            if attempt: raise UpErr(502, "upstream_error", "bad upstream response")

def build(path, b):
    dic = b.get("dictionary") or []
    if not isinstance(dic, list): raise ValueError("dictionary must be array")
    dline = ["【个人词典】" + "、".join(map(str, dic))] if dic else []
    style = STYLES.get(b.get("style") or "notes", STYLES.get("notes", ""))
    if path == "/v1/clean":
        t = req_str(b, "transcript"); ctx = b.get("context") or ""
        parts = [style] + dline + (["【前文】" + str(ctx)[-300:]] if ctx else []) + [f"<transcript>{t}</transcript>"]
        return MODEL, P["clean"], "\n".join(parts), 4 + len(t) * 0.02, len(t)
    if path == "/v1/translate":
        t = req_str(b, "transcript"); d = req_str(b, "direction")
        parts = [f"【翻译方向】{d}", style] + dline + [f"<transcript>{t}</transcript>"]
        return MODEL, P["translate"], "\n".join(parts), 5 + len(t) * 0.03, len(t)
    if path == "/v1/interpret":
        t = req_str(b, "transcript"); ctx = b.get("context") or []
        parts = (["【前文】\n" + "\n".join(map(str, ctx))] if ctx else []) + dline + [f"<transcript>{t}</transcript>"]
        return MODEL, P["interpret"], "\n".join(parts), 6 + len(t) * 0.03, len(t)
    if path == "/v1/edit":
        s = req_str(b, "selection"); i = req_str(b, "instruction")
        return EDIT_MODEL, P["edit"], f"<selection>{s}</selection>\n<instruction>{i}</instruction>", 6 + len(s) * 0.03, len(s) + len(i)
    return None

def req_str(b, k):
    v = b.get(k)
    if not isinstance(v, str): raise ValueError(f"missing {k}")
    return v

def usage_of(u):
    u = u or {}
    return {"prompt_tokens": u.get("prompt_tokens", 0), "completion_tokens": u.get("completion_tokens", 0),
            "total_tokens": u.get("total_tokens", 0), "cache_hit_tokens": u.get("prompt_cache_hit_tokens", 0)}

_rate = {}; _rlock = threading.Lock()
def rate_ok(tid):
    now = time.time()
    with _rlock:
        q = [t for t in _rate.get(tid, []) if now - t < 60]
        if len(q) >= RATE: _rate[tid] = q; return False
        q.append(now); _rate[tid] = q; return True

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "saycribe-relay/1"
    def log_message(s, fmt, *a): sys.stderr.write("%s %s\n" % (s.command, fmt % a))
    def send_json(s, status, obj):
        d = json.dumps(obj, ensure_ascii=False).encode()
        s.send_response(status); s.send_header("Content-Type", "application/json; charset=utf-8")
        s.send_header("Content-Length", str(len(d))); s.end_headers(); s.wfile.write(d)
    def err(s, status, code, msg): s.send_json(status, {"error": {"code": code, "message": msg}})
    def bearer(s):
        a = s.headers.get("Authorization", "")
        return a[7:].strip() if a.startswith("Bearer ") else ""
    def auth(s):
        tok = s.bearer(); row = lookup(tok) if tok else None
        if not row: s.err(401, "unauthorized", "missing or invalid token"); return None
        if row[3]: s.err(403, "revoked", "token revoked"); return None
        return row
    def is_admin(s):
        if ADMIN and secrets.compare_digest(s.bearer(), ADMIN): return True
        s.err(401, "unauthorized", "admin token required"); return False
    def body(s):
        n = int(s.headers.get("Content-Length") or 0)
        if n > MAX_BODY: s.rfile.read(n); raise OverflowError
        raw = s.rfile.read(n) if n else b"{}"
        b = json.loads(raw or b"{}")
        if not isinstance(b, dict): raise ValueError("body must be object")
        return b
    def do_GET(s):
        if s.path in ("/v1/ping", "/health"): return s.send_json(200, {"ok": True, "api_version": API_VERSION})
        if s.path == "/v1/me":
            r = s.auth()
            if r: s.send_json(200, {"token_id": r[0], "user": r[1], "device": r[2], "platform": r[4]})
            return
        from urllib.parse import urlsplit, parse_qs, unquote
        u = urlsplit(s.path); q = parse_qs(u.query)
        user = None
        if u.path == "/v1/admin/tokens": user = (q.get("user") or [None])[0]
        elif u.path.startswith("/v1/admin/users/") and u.path.endswith("/devices"): user = unquote(u.path.split("/")[4])
        else: return s.err(404, "not_found", "no such endpoint")
        if not s.is_admin(): return
        sql = "select id,user,platform,device,created,revoked from tokens" + (" where user=?" if user else "") + " order by created"
        with _db_lock: rows = CONN.execute(sql, (user,) if user else ()).fetchall()
        items = [dict(zip(("token_id", "user", "platform", "device", "created", "revoked"), r)) for r in rows]
        if u.path.endswith("/devices"):
            return s.send_json(200, {"user": user, "devices": [i for i in items if not i["revoked"]]})
        return s.send_json(200, {"tokens": items})
    def do_POST(s):
        t0 = time.time()
        try: b = s.body()
        except OverflowError: return s.err(413, "too_large", "body too large")
        except (ValueError, json.JSONDecodeError) as e: return s.err(400, "bad_request", str(e))
        if s.path == "/v1/admin/tokens":
            if not s.is_admin(): return
            try: tid, tok = issue(str(b.get("user", "")), str(b.get("device", "")), str(b.get("platform", "")))
            except ValueError as e: return s.err(400, "bad_request", str(e))
            return s.send_json(200, {"token_id": tid, "token": tok})
        if s.path.startswith("/v1/admin/tokens/") and s.path.endswith("/revoke"):
            if not s.is_admin(): return
            n = revoke(s.path.split("/")[4])
            return s.send_json(200 if n else 404, {"revoked": bool(n)})
        if s.path not in ("/v1/clean", "/v1/edit", "/v1/translate", "/v1/interpret"):
            return s.err(404, "not_found", "no such endpoint")
        row = s.auth()
        if not row: return
        if not rate_ok(row[0]): return s.err(429, "rate_limited", "too many requests")
        try: model, system, user, timeout, nchars = build(s.path, b)
        except ValueError as e: return s.err(400, "bad_request", str(e))
        if nchars > MAX_CHARS: return s.err(413, "too_large", f"max {MAX_CHARS} chars, split into segments")
        meta = {"session_id": b.get("session_id"), "seq": b.get("seq"), "model": model, "prompt_version": PROMPT_VERSION}
        stream = bool(b.get("stream"))
        try:
            c, r = upstream(model, system, user, timeout, stream)
        except UpErr as e: return s.err(e.status, e.code, e.msg)
        if r.status != 200:
            data = r.read(); put_conn(c)
            sys.stderr.write(f"upstream {r.status}: {data[:200]!r}\n")
            return s.err(504 if r.status == 408 else 502, "upstream_error", f"model service {r.status}")
        try:
            if not stream:
                d = json.loads(r.read()); put_conn(c)
                t1 = time.time()
                txt = (d["choices"][0]["message"].get("content") or "").strip()
                tm = {"upstream_ms": int((t1 - t0) * 1000), "total_ms": int((time.time() - t0) * 1000)}
                s.log_usage(row, d.get("usage"), tm)
                return s.send_json(200, {"text": txt, **meta, "usage": usage_of(d.get("usage")), "timing": tm})
            s.send_response(200); s.send_header("Content-Type", "text/event-stream; charset=utf-8")
            s.send_header("Cache-Control", "no-cache"); s.send_header("X-Accel-Buffering", "no")
            s.send_header("Connection", "close"); s.end_headers(); s.close_connection = True
            def ev(name, obj):
                s.wfile.write(f"event: {name}\ndata: {json.dumps(obj, ensure_ascii=False)}\n\n".encode()); s.wfile.flush()
            buf, usage, first = [], None, None
            for line in r:
                line = line.strip()
                if not line.startswith(b"data:"): continue
                p = line[5:].strip()
                if p == b"[DONE]": break
                j = json.loads(p)
                if j.get("usage"): usage = j["usage"]
                for ch in j.get("choices") or []:
                    piece = (ch.get("delta") or {}).get("content")
                    if piece:
                        if first is None: first = int((time.time() - t0) * 1000)
                        buf.append(piece); ev("delta", {"text": piece})
            put_conn(c)
            tm = {"first_token_ms": first, "upstream_ms": int((time.time() - t0) * 1000), "total_ms": int((time.time() - t0) * 1000)}
            s.log_usage(row, usage, tm)
            ev("done", {"text": "".join(buf).strip(), **meta, "usage": usage_of(usage), "timing": tm})
        except (TimeoutError, OSError) as e:
            c.close()
            try: s.err(504, "upstream_timeout", "model timeout")
            except Exception: pass
    def log_usage(s, row, u, tm):
        u = usage_of(u)
        sys.stderr.write(f"usage {row[0]} {s.path} tok={u['total_tokens']} cache={u['cache_hit_tokens']} ms={tm['total_ms']}\n")

def main():
    global CONN
    os.makedirs(os.path.dirname(DB), exist_ok=True); CONN = db()
    a = sys.argv[1:]
    if a[:1] == ["issue"]:
        g = lambda k: a[a.index(k) + 1] if k in a else ""
        print(*issue(g("--user"), g("--device"), g("--platform"))); return
    if a[:1] == ["revoke"]: print("revoked" if revoke(a[1]) else "not found"); return
    if a[:1] == ["list"]:
        g = a[1:2]
        for r in CONN.execute("select id,user,platform,device,created,revoked from tokens" + (" where user=?" if g else ""), g): print(*r)
        return
    if not KEY: sys.exit("DEEPSEEK_API_KEY missing")
    # warm upstream connection
    try:
        c = get_conn(); c.connect(); put_conn(c)
    except Exception: pass
    srv = ThreadingHTTPServer((os.environ.get("SC_BIND", "127.0.0.1"), PORT), H); srv.daemon_threads = True
    sys.stderr.write(f"saycribe-relay on {PORT} model={MODEL}\n"); srv.serve_forever()

if __name__ == "__main__": main()
