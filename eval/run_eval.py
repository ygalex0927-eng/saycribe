"""Run the cleanup prompt against eval/cases.jsonl and score with simple contain/absent checks.

Usage: python3 eval/run_eval.py [--model deepseek-flash] [--only id1,id2]
Key is read from ~/.config/suikou/secrets.env.
"""
import argparse, concurrent.futures as cf, json, os, pathlib, re, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROMPTS = ROOT / "Resources" / "prompts"


def load_key():
    for line in (pathlib.Path.home() / ".config/suikou/secrets.env").read_text().splitlines():
        if line.startswith("DEEPSEEK_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("DEEPSEEK_API_KEY missing")


def build_user_msg(style_text, dictionary, transcript):
    # Keep in sync with Sources/Suikou/Cleaner.swift
    parts = [style_text]
    if dictionary:
        parts.append("【个人词典】" + "、".join(dictionary))
    parts.append(f"<transcript>{transcript}</transcript>")
    return "\n".join(parts)


def call(key, model, system, user):
    body = {
        "model": model,
        "temperature": 0.2,
        "thinking": {"type": "disabled"},
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
    }
    req = urllib.request.Request(
        "https://api.deepseek.com/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    t = time.time()
    d = json.load(urllib.request.urlopen(req, timeout=60))
    return d["choices"][0]["message"]["content"].strip(), time.time() - t


def check(case, out):
    errs = []
    if "exact" in case:
        if out != case["exact"]:
            errs.append(f"exact≠{case['exact']!r}")
        return errs
    for alt in case.get("has", []):
        if not any(a in out for a in alt.split("|")):
            errs.append(f"缺:{alt!r}")
    for bad in case.get("not", []):
        if bad in out:
            errs.append(f"多:{bad!r}")
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="deepseek-flash")
    ap.add_argument("--only")
    args = ap.parse_args()
    key = load_key()
    system = (PROMPTS / "clean.md").read_text()
    styles = json.loads((PROMPTS / "styles.json").read_text())
    cases = [json.loads(l) for l in (ROOT / "eval/cases.jsonl").read_text().splitlines() if l.strip()]
    if args.only:
        cases = [c for c in cases if c["id"] in args.only.split(",")]

    def run(c):
        out, dt = call(key, args.model, system, build_user_msg(styles[c["style"]], c.get("dict", []), c["in"]))
        return c, out, dt, check(c, out)

    passed = 0
    with cf.ThreadPoolExecutor(8) as ex:
        for c, out, dt, errs in ex.map(run, cases):
            passed += not errs
            mark = "✅" if not errs else "❌"
            print(f"{mark} {c['id']:<18} {dt:4.1f}s  {out!r}" + (f"   {'; '.join(errs)}" if errs else ""))
    print(f"\n{args.model}: {passed}/{len(cases)} passed ({passed / len(cases):.0%})")


if __name__ == "__main__":
    main()
