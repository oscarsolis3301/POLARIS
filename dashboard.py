#!/usr/bin/env python3
# POLARIS v5 — live board. One file, Python 3.8+ stdlib ONLY (no pip, ever).
# Read-only by design: every mutation goes through `ops/polaris`. This server
# renders the board, locks, telemetry and Learned log, and streams changes
# over SSE the second the filesystem moves. Bind stays on 127.0.0.1 unless
# you explicitly pass --host (then it warns).
#
#   bash ops/polaris dash            # or: python3 ops/dashboard.py
#   → http://127.0.0.1:7373
import argparse, hashlib, json, os, re, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COLUMNS = ["backlog", "ready", "active", "review", "blocked", "done"]

# ------------------------------------------------------------------ repo I/O
def sh(root, *args):
    try:
        r = subprocess.run(["git", "-C", root] + list(args), capture_output=True,
                           text=True, errors="replace", timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""

def repo_root(start):
    top = sh(start, "rev-parse", "--show-toplevel")
    return top or os.path.abspath(start)

def locks_dir(root):
    gcd = sh(root, "rev-parse", "--git-common-dir")
    if not gcd:
        return None
    if not os.path.isabs(gcd):
        gcd = os.path.join(root, gcd)
    return os.path.join(os.path.abspath(gcd), "polaris-locks")

def read_text(path, limit=200_000):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""

# ----------------------------------------------------- frontmatter (mirrors ops/polaris)
def parse_task(path):
    raw = read_text(path)
    fm, body, fence = {}, [], 0
    lastkey = None
    for line in raw.splitlines():
        s = line.rstrip("\r")
        if re.match(r"^---\s*$", s):
            fence += 1
            continue
        if fence == 1:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", s)
            if m:
                k, v = m.group(1), re.sub(r"[ \t]#.*$", "", m.group(2)).strip()
                if v in ("", "[]"):
                    fm[k] = [] if v == "[]" else fm.get(k, "")
                    lastkey = k
                else:
                    fm[k] = v
                    lastkey = None
                continue
            m = re.match(r"^[ \t]*-[ \t]+(.*)$", s)
            if m and lastkey:
                item = re.sub(r"[ \t]#.*$", "", m.group(1)).strip()
                if not isinstance(fm.get(lastkey), list):
                    fm[lastkey] = [fm[lastkey]] if fm.get(lastkey) else []
                if item:
                    fm[lastkey].append(item)
                continue
            lastkey = None
        elif fence >= 2:
            body.append(s)
    return fm, "\n".join(body).strip()

def as_list(v):
    if isinstance(v, list):
        return v
    return [v] if v not in (None, "", "null") else []

def numf(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d

# ------------------------------------------------------------------- state
def read_conv(ops):
    cfg = {}
    for line in read_text(os.path.join(ops, "CONVENTIONS.md")).splitlines():
        m = re.match(r"^([a-z_]+):\s*(.*)$", line.rstrip("\r"))
        if m:
            cfg.setdefault(m.group(1), re.sub(r"[ \t]#.*$", "", m.group(2)).strip())
    return cfg

def read_sprint(ops):
    txt = read_text(os.path.join(ops, "SPRINT.md"))
    lines = [l.rstrip("\r") for l in txt.splitlines()]
    head = next((l.lstrip("# ").strip() for l in lines if l.strip()), "")
    learned, on = [], False
    for l in lines:
        if re.match(r"^##\s*Learned", l):
            on = True
            continue
        if on and l.startswith("## "):
            break
        if on and l.strip().startswith(("-", "*")):
            learned.append(l.strip().lstrip("-*").strip())
    return head, learned[-6:]

def read_events(board):
    out = []
    for line in read_text(os.path.join(board, "EVENTS.ndjson"), 2_000_000).splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            if isinstance(e, dict) and "ev" in e:
                out.append(e)
        except ValueError:
            continue
    return out

def metrics(events, tasks_by_col, points_of):
    now = time.time()
    claimed, done_ts, kb = {}, {}, 0
    kb7 = d7 = 0
    for e in events:
        ts, ev, tid = e.get("ts", 0), e.get("ev"), e.get("id", "")
        if ev == "claim" and tid not in claimed:
            claimed[tid] = ts
        elif ev == "kickback":
            kb += 1
            if now - ts < 7 * 86400:
                kb7 += 1
        elif ev == "done":
            done_ts[tid] = ts
            if now - ts < 7 * 86400:
                d7 += 1
    cycles = sorted(done_ts[t] - claimed[t] for t in done_ts if t in claimed and done_ts[t] >= claimed[t])
    p50 = cycles[(len(cycles) - 1) // 2] / 3600 if cycles else None
    avg = (sum(cycles) / len(cycles) / 3600) if cycles else None
    # burndown: done points per day, last 10 days (joined to task points)
    days = []
    for back in range(9, -1, -1):
        d0 = time.strftime("%m-%d", time.localtime(now - back * 86400))
        pts = sum(points_of.get(t, 0) for t, ts in done_ts.items()
                  if time.strftime("%m-%d", time.localtime(ts)) == d0
                  and now - ts < 10 * 86400)
        days.append({"d": d0, "pts": round(pts, 1)})
    total_done = len(done_ts)
    return {
        "wip": len(tasks_by_col.get("active", [])),
        "review": len(tasks_by_col.get("review", [])),
        "done7": d7, "done_total": total_done,
        "cycle_avg_h": round(avg, 1) if avg is not None else None,
        "cycle_p50_h": round(p50, 1) if p50 is not None else None,
        "kickbacks": kb, "kb7": kb7,
        "kb_rate": round(100 * kb / total_done) if total_done else None,
        "burndown": days,
    }

def read_state(root):
    ops = os.path.join(root, "ops")
    board = os.path.join(ops, "board")
    ld = locks_dir(root)
    locks = {}
    if ld and os.path.isdir(ld):
        for name in sorted(os.listdir(ld)):
            if name.startswith("."):
                continue
            meta = read_text(os.path.join(ld, name, "meta"), 500).splitlines()
            ts = int(meta[0]) if meta and meta[0].strip().isdigit() else None
            locks[name] = {"ts": ts, "who": meta[1].strip() if len(meta) > 1 else "?"}

    cols, points_of = {}, {}
    for col in COLUMNS:
        cdir = os.path.join(board, col)
        items = []
        if os.path.isdir(cdir):
            for fn in sorted(os.listdir(cdir)):
                if not fn.endswith(".md") or fn == "IDEAS.md":
                    continue
                path = os.path.join(cdir, fn)
                fm, body = parse_task(path)
                tid = fm.get("id") or fn[:-3]
                pts = numf(fm.get("points"), 0)
                points_of[tid] = pts
                items.append({
                    "id": tid, "col": col,
                    "title": fm.get("title", "") or "(untitled)",
                    "type": fm.get("type", ""), "points": pts,
                    "wsjf": round(numf(fm.get("wsjf"), 0), 2),
                    "risk": fm.get("risk", "normal"),
                    "owner": (fm.get("owner") or "").replace("null", ""),
                    "branch": (fm.get("branch") or "").replace("null", ""),
                    "depends_on": as_list(fm.get("depends_on")),
                    "owned_n": len(as_list(fm.get("files_owned"))),
                    "verify_n": len(as_list(fm.get("verify"))),
                    "contract": fm.get("contract", ""),
                    "map_delta": as_list(fm.get("map_delta")),
                    "lock": locks.get(tid),
                    "mtime": int(os.path.getmtime(path)),
                    "body": body[:8000],
                })
        if col == "ready":
            items.sort(key=lambda t: -t["wsjf"])
        cols[col] = items

    events = read_events(board)
    goal, learned = read_sprint(ops)
    # v5: points at a glance + the drift subset computable without the glob matcher
    # (ownership-overlap needs the ONE matcher in ops/polaris — `ops/polaris drift` owns it)
    pts = {c: round(sum(t["points"] for t in cols.get(c, [])), 1) for c in COLUMNS}
    done_ids = {t["id"] for t in cols.get("done", [])}
    drift = {"no_contract": [], "deps_open": [], "todo_n": 0}
    for t in cols.get("ready", []):
        c = t.get("contract") or ""
        if not c or not os.path.isfile(os.path.join(root, c)):
            drift["no_contract"].append(t["id"])
        if any(d not in done_ids for d in t.get("depends_on", [])):
            drift["deps_open"].append(t["id"])
    todo_rx = re.compile(r"TODO\([A-Za-z][A-Za-z0-9._-]*-[0-9A-Za-z]")
    for c in COLUMNS:
        for t in cols.get(c, []):
            drift["todo_n"] += len(todo_rx.findall(t.get("body", "")))
    rules_n = 0
    for line in read_text(os.path.join(ops, "RULES.tsv")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            rules_n += 1
    cfg = read_conv(ops)
    stale_h = numf(cfg.get("stale_hours"), 4)
    state = {
        "v": 5, "now": int(time.time()),
        "pts": pts, "drift": drift, "rules_n": rules_n,
        "goal": goal, "learned": learned,
        "cfg": {k: cfg.get(k, "") for k in ("base", "claim", "integration", "test", "stale_hours")},
        "columns": cols, "locks": locks, "stale_h": stale_h,
        "metrics": metrics(events, cols, points_of),
        "recent": [e for e in events[-8:]][::-1],
        "git": {
            "head": sh(root, "rev-parse", "--short", "HEAD"),
            "branch": sh(root, "rev-parse", "--abbrev-ref", "HEAD"),
            "last_board": sh(root, "log", "-1", "--format=%s · %cr", "--", "ops/board"),
            "feat_n": len([b for b in sh(root, "branch", "--list", "feat/*").splitlines() if b.strip()]),
        },
        "root": os.path.basename(root),
    }
    return state

def signature(root):
    ops = os.path.join(root, "ops")
    board = os.path.join(ops, "board")
    h = hashlib.md5()
    for col in COLUMNS:
        cdir = os.path.join(board, col)
        if os.path.isdir(cdir):
            for fn in sorted(os.listdir(cdir)):
                p = os.path.join(cdir, fn)
                try:
                    st = os.stat(p)
                    h.update(("%s/%s:%d:%d;" % (col, fn, st.st_mtime_ns, st.st_size)).encode())
                except OSError:
                    pass
    cdir = os.path.join(ops, "contracts")
    if os.path.isdir(cdir):
        for fn in sorted(os.listdir(cdir)):
            h.update(("c:%s;" % fn).encode())
    for f in ("SPRINT.md", "CONVENTIONS.md", "MAP.md", "RULES.tsv", os.path.join("board", "EVENTS.ndjson")):
        p = os.path.join(ops, f)
        try:
            st = os.stat(p)
            h.update(("%s:%d:%d;" % (f, st.st_mtime_ns, st.st_size)).encode())
        except OSError:
            pass
    ld = locks_dir(root)
    if ld and os.path.isdir(ld):
        for name in sorted(os.listdir(ld)):
            h.update(name.encode())
    return h.hexdigest()

# -------------------------------------------------------------------- HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "polaris/5"
    root = "."

    def log_message(self, *a):  # keep the terminal quiet
        pass

    def _send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            boot = json.dumps(read_state(self.root)).replace("</", "<\\/")
            self._send(200, "text/html; charset=utf-8",
                       PAGE.replace("__BOOT__", boot).encode("utf-8"))
        elif path == "/state":
            self._send(200, "application/json",
                       json.dumps(read_state(self.root)).encode("utf-8"))
        elif path == "/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            last, last_beat = "", 0.0
            try:
                while True:
                    sig = signature(self.root)
                    now = time.time()
                    if sig != last:
                        payload = json.dumps(read_state(self.root))
                        self.wfile.write(("event: state\ndata: " + payload + "\n\n").encode())
                        self.wfile.flush()
                        last, last_beat = sig, now
                    elif now - last_beat > 15:
                        self.wfile.write(b"event: ping\ndata: {}\n\n")
                        self.wfile.flush()
                        last_beat = now
                    time.sleep(1)
            except (BrokenPipeError, ConnectionResetError, OSError):
                return
        else:
            self._send(404, "text/plain", b"not found")

# ---------------------------------------------------------------- frontend
PAGE = r"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>POLARIS — live board</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700&family=Geist+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root{
  --void:#070A14; --nebula:rgba(148,163,255,.045); --line:rgba(148,163,255,.13);
  --ink:#E9EBF8; --dim:#8A93B8; --faint:#5A6284;
  --polaris:#4F46E5; --signal:#67E8F9;
  --ready:#A5B4FC; --active:#67E8F9; --review:#FBBF24; --done:#34D399;
  --blocked:#F87171; --risk:#FB7185; --backlog:#5A6284;
  --sans:"DM Sans",ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  --mono:"Geist Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
*{box-sizing:border-box;margin:0}
html,body{height:100%}
body{background:
  radial-gradient(1100px 500px at 78% -10%, rgba(79,70,229,.16), transparent 60%),
  radial-gradient(700px 380px at 8% 110%, rgba(103,232,249,.05), transparent 60%),
  var(--void);
  color:var(--ink); font:14px/1.45 var(--sans); -webkit-font-smoothing:antialiased}
a{color:inherit}
.wrap{max-width:1460px;margin:0 auto;padding:18px 22px 40px}
.glass{background:var(--nebula);border:1px solid var(--line);border-radius:14px;
  backdrop-filter:blur(14px) saturate(1.25);-webkit-backdrop-filter:blur(14px) saturate(1.25)}
/* top bar */
header{display:flex;align-items:center;gap:16px;flex-wrap:wrap;padding:4px 2px 14px}
.mark{display:flex;align-items:baseline;gap:10px}
.mark b{font-weight:700;letter-spacing:.14em;font-size:15px}
.mark .star{color:var(--polaris);font-size:17px}
.goal{color:var(--dim);font-size:13.5px;max-width:56ch;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.spacer{flex:1}
.live{display:flex;align-items:center;gap:8px;font:12px var(--mono);color:var(--dim)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--done);box-shadow:0 0 10px rgba(52,211,153,.8)}
.dot.err{background:var(--review);box-shadow:0 0 10px rgba(251,191,36,.8)}
.ro{font:11px var(--mono);color:var(--faint);border:1px solid var(--line);border-radius:99px;padding:3px 10px}
/* metrics strip */
.strip{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-bottom:14px}
.kpi{padding:12px 14px}
.kpi .n{font:600 20px/1.1 var(--mono)}
.kpi .l{color:var(--dim);font-size:11.5px;margin-top:3px;letter-spacing:.04em}
.kpi svg{display:block;margin-top:6px}
/* constellation */
#sky{position:relative;margin-bottom:14px;padding:10px 12px 4px;overflow:hidden}
#sky .cap{position:absolute;top:10px;left:14px;font:11px var(--mono);color:var(--faint);letter-spacing:.1em}
#constellation{width:100%;height:190px;display:block}
.edge{stroke:rgba(148,163,255,.16);stroke-width:1}
.star-lab{font:10px var(--mono);fill:var(--faint)}
.stage-lab{font:10px var(--mono);fill:var(--faint);letter-spacing:.12em}
.north{fill:var(--polaris)}
.pulse{animation:pulse 1.6s ease-out 1}
@keyframes pulse{0%{filter:drop-shadow(0 0 0 rgba(103,232,249,0))}30%{filter:drop-shadow(0 0 14px rgba(103,232,249,.95))}100%{filter:drop-shadow(0 0 0 rgba(103,232,249,0))}}
/* board */
.board{display:grid;grid-template-columns:repeat(6,minmax(198px,1fr));gap:10px}
.col{padding:10px;min-height:120px}
.col h2{display:flex;align-items:center;gap:8px;font-size:12px;letter-spacing:.12em;
  color:var(--dim);font-weight:600;text-transform:uppercase;margin:2px 2px 10px}
.col h2 .cnt{margin-left:auto;font:600 12px var(--mono);color:var(--ink)}
.col h2 .swatch{width:8px;height:8px;border-radius:3px}
.card{position:relative;padding:10px 11px;margin-bottom:8px;cursor:pointer;transition:border-color .15s, transform .15s}
.card:hover{border-color:rgba(148,163,255,.35);transform:translateY(-1px)}
.card:focus-visible{outline:2px solid var(--signal);outline-offset:2px}
.card .id{font:600 11px var(--mono);color:var(--signal)}
.card .t{margin:3px 0 7px;font-size:13px;font-weight:500;line-height:1.3}
.meta{display:flex;flex-wrap:wrap;gap:5px;font:11px var(--mono);color:var(--dim)}
.chip{border:1px solid var(--line);border-radius:6px;padding:1px 6px}
.chip.risk{color:var(--risk);border-color:rgba(251,113,133,.4)}
.chip.age{color:var(--active)}
.chip.stale{color:var(--review);border-color:rgba(251,191,36,.45)}
.chip.dep{color:var(--faint)}
.empty{color:var(--faint);font:12px var(--mono);text-align:center;padding:10px 0 6px}
/* rails */
.rails{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:10px;margin-top:14px}
.rail{padding:12px 14px}
.rail h3{font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:var(--dim);margin-bottom:8px;font-weight:600}
.rail table{width:100%;border-collapse:collapse;font:12px var(--mono)}
.rail td{padding:4px 6px 4px 0;color:var(--dim);border-top:1px solid rgba(148,163,255,.07)}
.rail td:first-child{color:var(--signal)}
.rail li{margin:0 0 6px 16px;color:var(--dim);font-size:12.5px}
/* drawer */
#veil{position:fixed;inset:0;background:rgba(4,6,14,.6);opacity:0;pointer-events:none;transition:opacity .2s}
#drawer{position:fixed;top:0;right:0;bottom:0;width:min(520px,94vw);transform:translateX(102%);
  transition:transform .22s ease;padding:20px;overflow:auto;border-radius:14px 0 0 14px;background:#0B0F20ee;border-left:1px solid var(--line)}
body.open #veil{opacity:1;pointer-events:auto} body.open #drawer{transform:none}
#drawer .id{font:600 12px var(--mono);color:var(--signal)}
#drawer h2{font-size:17px;margin:6px 0 12px}
#drawer .meta{margin-bottom:14px}
#drawer .body{font-size:13.5px;color:var(--ink)}
#drawer .body h4{margin:14px 0 6px;font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--dim)}
#drawer .body li{margin:0 0 4px 18px}
#drawer .body code{font:12px var(--mono);background:rgba(148,163,255,.1);padding:1px 5px;border-radius:5px}
#drawer .body pre{background:rgba(148,163,255,.07);border:1px solid var(--line);border-radius:10px;padding:10px;overflow:auto;font:12px var(--mono);margin:8px 0}
#drawer .ck{font-family:var(--mono);color:var(--done);margin-right:6px}
#drawer .ck.todo{color:var(--faint)}
#close{position:absolute;top:14px;right:14px;background:none;border:1px solid var(--line);border-radius:8px;color:var(--dim);padding:4px 10px;cursor:pointer;font:12px var(--mono)}
/* filter + footer */
#filter{background:rgba(148,163,255,.06);border:1px solid var(--line);border-radius:10px;color:var(--ink);
  font:12.5px var(--mono);padding:7px 12px;width:220px}
#filter::placeholder{color:var(--faint)}
footer{margin-top:16px;color:var(--faint);font:11.5px var(--mono);display:flex;gap:14px;flex-wrap:wrap}
@media (max-width:1100px){.board{grid-template-columns:repeat(3,1fr)}.rails{grid-template-columns:1fr}}
@media (max-width:640px){.board{grid-template-columns:1fr 1fr}.goal{display:none}}
@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
</style></head><body>
<div class="wrap">
  <header>
    <div class="mark"><span class="star">✦</span><b>POLARIS</b></div>
    <div class="goal" id="goal"></div>
    <div class="spacer"></div>
    <input id="filter" type="search" placeholder="filter id · title · owner" aria-label="Filter tasks">
    <button id="bell" class="ro" style="cursor:pointer;background:none" title="Notify on task transitions" aria-pressed="false">🔕 notify</button>
    <span class="ro">read-only · mutations go through ops/polaris</span>
    <div class="live"><span class="dot" id="dot"></span><span id="upd">—</span></div>
  </header>
  <div class="strip" id="strip"></div>
  <div class="glass" id="sky"><span class="cap">CONSTELLATION · x stage · y wsjf · size pts</span>
    <svg id="constellation" role="img" aria-label="Task constellation"></svg></div>
  <div class="board" id="board"></div>
  <div class="rails">
    <div class="glass rail"><h3>Locks</h3><div id="locks"></div></div>
    <div class="glass rail"><h3>Drift — board hygiene</h3><div id="drift"></div></div>
    <div class="glass rail"><h3>Learned — last integrations</h3><div id="learned"></div></div>
  </div>
  <footer id="foot"></footer>
</div>
<div id="veil"></div>
<aside id="drawer" role="dialog" aria-modal="true"><button id="close">esc</button><div id="dbody"></div></aside>
<script>
"use strict";
const BOOT = __BOOT__;
const COLS = ["backlog","ready","active","review","blocked","done"];
const CCOL = {backlog:"var(--backlog)",ready:"var(--ready)",active:"var(--active)",
              review:"var(--review)",blocked:"var(--blocked)",done:"var(--done)"};
let S = null, prevM = {}, filter = "", prevCol = null, notify = false;
const $ = s => document.querySelector(s);
const esc = s => String(s??"").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const ago = s => s<90?`${s}s`:s<5400?`${Math.round(s/60)}m`:s<172800?`${(s/3600).toFixed(1)}h`:`${Math.round(s/86400)}d`;

function kpis(m,cfg){
  const bd = m.burndown||[], mx = Math.max(1,...bd.map(d=>d.pts));
  const pts = bd.map((d,i)=>`${8+i*(120/Math.max(1,bd.length-1))},${34-28*(d.pts/mx)}`).join(" ");
  const spark = `<svg width="136" height="38" aria-hidden="true"><polyline points="${pts}" fill="none" stroke="var(--signal)" stroke-width="1.5"/></svg>`;
  const cell=(n,l,extra="")=>`<div class="glass kpi"><div class="n">${n}</div><div class="l">${l}</div>${extra}</div>`;
  const tp=S.pts||{};
  return cell(m.wip,"ACTIVE NOW")+cell(m.review,"IN REVIEW")
       + cell(tp.ready??"—","READY PTS")+cell(tp.active??"—","WIP PTS")
       + cell(m.done7,"LANDED · 7D")
       + cell(m.cycle_p50_h!=null?m.cycle_p50_h+"h":"—","CYCLE P50 · CLAIM→DONE")
       + cell(m.kb_rate!=null?m.kb_rate+"%":"—","KICKBACK RATE")
       + cell("", "DONE PTS · 10D", spark)
       + cell(`<span style="font-size:12px">${esc(cfg.test||"—")}</span>`,"SUITE");
}

function constellation(){
  const svg=$("#constellation"), W=svg.clientWidth||1200, H=190;
  svg.setAttribute("viewBox",`0 0 ${W} ${H}`); svg.innerHTML="";
  const NS="http://www.w3.org/2000/svg", el=(t,a)=>{const e=document.createElementNS(NS,t);for(const k in a)e.setAttribute(k,a[k]);return e};
  const padL=90,padR=40,step=(W-padL-padR)/(COLS.length-1);
  const all=[].concat(...COLS.map(c=>S.columns[c]||[]));
  const wmax=Math.max(1,...all.map(t=>t.wsjf||0));
  const pos={};
  COLS.forEach((c,i)=>{
    svg.appendChild(el("text",{x:padL+i*step,y:H-8,"text-anchor":"middle",class:"stage-lab"})).textContent=c.toUpperCase();
    (S.columns[c]||[]).forEach((t,j)=>{
      const y=26+(1-(t.wsjf||0)/wmax)*(H-70)+(j%3)*7;
      pos[t.id]={x:padL+i*step+((j%2)?14:-14)*Math.min(1,j),y,t};
    });
  });
  for(const id in pos){ const t=pos[id].t;
    (t.depends_on||[]).forEach(d=>{ if(pos[d]) svg.appendChild(el("line",{x1:pos[d].x,y1:pos[d].y,x2:pos[id].x,y2:pos[id].y,class:"edge"})); });
  }
  const north=el("text",{x:26,y:26,class:"north","font-size":"18"}); north.textContent="✦"; svg.appendChild(north);
  const nl=el("text",{x:44,y:29,class:"star-lab"}); nl.textContent=(S.goal||"").slice(0,42); svg.appendChild(nl);
  for(const id in pos){ const {x,y,t}=pos[id];
    const g=el("g",{tabindex:"0",style:"cursor:pointer"});
    const r=4+(t.points||1)*1.5;
    const c=el("circle",{cx:x,cy:y,r,fill:CCOL[t.col],"fill-opacity":t.col==="done"?".55":".9"});
    if(prevM[id]!==undefined && prevM[id]!==t.mtime) c.setAttribute("class","pulse");
    if(t.risk==="high") g.appendChild(el("circle",{cx:x,cy:y,r:r+3.5,fill:"none",stroke:"var(--risk)","stroke-width":"1","stroke-dasharray":"2 3"}));
    g.appendChild(c);
    const lab=el("text",{x:x+r+4,y:y+3,class:"star-lab"}); lab.textContent=t.id; g.appendChild(lab);
    g.addEventListener("click",()=>openTask(t.id)); g.addEventListener("keydown",e=>{if(e.key==="Enter")openTask(t.id)});
    const ti=el("title",{}); ti.textContent=`${t.id} · ${t.title} · ${t.points}pts wsjf ${t.wsjf}`; g.appendChild(ti);
    svg.appendChild(g);
  }
}

function card(t){
  const lk=t.lock, now=S.now;
  const age=lk&&lk.ts?now-lk.ts:null;
  const stale=age!=null && age>S.stale_h*3600 && t.col==="active";
  const hit=!filter||(t.id+" "+t.title+" "+(t.owner||"")).toLowerCase().includes(filter);
  return `<div class="glass card" data-id="${esc(t.id)}" tabindex="0" role="button" ${hit?"":"hidden"}>
    <span class="id">${esc(t.id)}</span>
    <div class="t">${esc(t.title)}</div>
    <div class="meta">
      <span class="chip">${t.points}pt</span><span class="chip">wsjf ${t.wsjf}</span>
      ${t.risk==="high"?'<span class="chip risk">RISK</span>':""}
      ${(t.depends_on||[]).map(d=>`<span class="chip dep">⇠ ${esc(d)}</span>`).join("")}
      ${t.owner?`<span class="chip">${esc(t.owner.split("@")[0])}</span>`:""}
      ${age!=null?`<span class="chip age ${stale?"stale":""}" data-ts="${lk.ts}">${stale?"⚠ ":""}${ago(age)}</span>`:""}
      ${t.verify_n?`<span class="chip">✓×${t.verify_n}</span>`:""}
    </div></div>`;
}

function render(){
  $("#goal").textContent=S.goal||"";
  $("#strip").innerHTML=kpis(S.metrics,S.cfg);
  $("#board").innerHTML=COLS.map(c=>{
    const items=S.columns[c]||[];
    return `<div class="glass col"><h2><span class="swatch" style="background:${CCOL[c]}"></span>${c}
      <span class="cnt">${items.length}</span></h2>
      ${items.length?items.map(card).join(""):'<div class="empty">—</div>'}</div>`;
  }).join("");
  const lk=Object.entries(S.locks||{});
  $("#locks").innerHTML=lk.length?`<table>${lk.map(([id,l])=>{
      const t=findTask(id);
      return `<tr><td>${esc(id)}</td><td>${esc((l.who||"?"))}</td>
        <td data-ts="${l.ts||""}">${l.ts?ago(S.now-l.ts):"?"}</td>
        <td>${t?t.col:"<span style='color:var(--review)'>ORPHAN?</span>"}</td></tr>`;
    }).join("")}</table>`:'<div class="empty">no locks held</div>';
  const dr=S.drift||{}, drx=[];
  (dr.no_contract||[]).forEach(id=>drx.push(`<li><b>${esc(id)}</b> in ready/ without its contract — ready-gate violation</li>`));
  (dr.deps_open||[]).forEach(id=>drx.push(`<li><b>${esc(id)}</b> in ready/ with unmet depends_on</li>`));
  if(dr.todo_n) drx.push(`<li>${dr.todo_n} TODO(task) forward-ref${dr.todo_n===1?"":"s"} in task bodies</li>`);
  $("#drift").innerHTML=(drx.length?`<ul>${drx.join("")}</ul>`:'<div class="empty">no drift in this view</div>')
    +`<div class="empty" style="text-align:left;padding-top:4px">ownership-overlap check: <code>ops/polaris drift</code></div>`;
  $("#learned").innerHTML=S.learned&&S.learned.length
    ?`<ul>${S.learned.map(l=>`<li>${esc(l)}</li>`).join("")}</ul>`:'<div class="empty">nothing yet — the Integrator writes here</div>';
  $("#foot").innerHTML=
    `<span>repo ${esc(S.root)} · ${esc(S.git.branch)} @ ${esc(S.git.head)}</span>`+
    `<span>base ${esc(S.cfg.base||"main")} · claim ${esc(S.cfg.claim||"local-lock")} · integration ${esc(S.cfg.integration||"batch")}</span>`+
    (S.git.last_board?`<span>board: ${esc(S.git.last_board)}</span>`:"")+
    `<span>feat branches: ${S.git.feat_n}</span>`+
    `<span>rules: ${S.rules_n??0}</span>`;
  constellation();
  document.querySelectorAll(".card").forEach(c=>{
    c.addEventListener("click",()=>openTask(c.dataset.id));
    c.addEventListener("keydown",e=>{if(e.key==="Enter")openTask(c.dataset.id)});
  });
  prevM={}; COLS.forEach(c=>(S.columns[c]||[]).forEach(t=>prevM[t.id]=t.mtime));
}

function findTask(id){for(const c of COLS)for(const t of S.columns[c]||[])if(t.id===id)return t;return null}
function md(src){ // tiny, escape-first renderer for the drawer
  const lines=esc(src).split("\n");let out="",inpre=false;
  for(const l of lines){
    if(l.startsWith("```")){out+=inpre?"</pre>":"<pre>";inpre=!inpre;continue}
    if(inpre){out+=l+"\n";continue}
    let s=l.replace(/`([^`]+)`/g,"<code>$1</code>").replace(/\*\*([^*]+)\*\*/g,"<b>$1</b>");
    if(/^#{2,4}\s/.test(s)) out+=`<h4>${s.replace(/^#+\s*/,"")}</h4>`;
    else if(/^- \[x\]/i.test(s)) out+=`<li style="list-style:none"><span class="ck">◆</span>${s.slice(6)}</li>`;
    else if(/^- \[ \]/.test(s)) out+=`<li style="list-style:none"><span class="ck todo">◇</span>${s.slice(6)}</li>`;
    else if(/^\s*-\s+/.test(s)) out+=`<li>${s.replace(/^\s*-\s+/,"")}</li>`;
    else if(s.trim()==="") out+="<div style='height:6px'></div>";
    else out+=`<p>${s}</p>`;
  }
  return out+(inpre?"</pre>":"");
}
function openTask(id){
  const t=findTask(id); if(!t)return;
  $("#dbody").innerHTML=`<span class="id">${esc(t.id)} · ${esc(t.col)}</span><h2>${esc(t.title)}</h2>
    <div class="meta">
      <span class="chip">${t.points}pt</span><span class="chip">wsjf ${t.wsjf}</span>
      <span class="chip">${esc(t.type||"task")}</span>
      ${t.risk==="high"?'<span class="chip risk">RISK: HIGH — human approves merge</span>':""}
      ${t.branch?`<span class="chip">${esc(t.branch)}</span>`:""}
      ${t.contract?`<span class="chip">contract: ${esc(t.contract)}</span>`:""}
      <span class="chip">owns ${t.owned_n} path${t.owned_n===1?"":"s"}</span>
    </div><div class="body">${md(t.body||"(no body)")}</div>`;
  document.body.classList.add("open"); $("#close").focus();
}
$("#veil").addEventListener("click",()=>document.body.classList.remove("open"));
$("#close").addEventListener("click",()=>document.body.classList.remove("open"));
addEventListener("keydown",e=>{if(e.key==="Escape")document.body.classList.remove("open")});
$("#filter").addEventListener("input",e=>{filter=e.target.value.trim().toLowerCase();render()});
$("#bell").addEventListener("click",async()=>{
  if(!("Notification"in window))return;
  if(!notify){ if(Notification.permission!=="granted"&&await Notification.requestPermission()!=="granted")return;
    notify=true; if(!prevCol){prevCol={};COLS.forEach(c=>(S.columns[c]||[]).forEach(t=>prevCol[t.id]=c));} }
  else notify=false;
  $("#bell").textContent=notify?"🔔 notify":"🔕 notify";$("#bell").setAttribute("aria-pressed",String(notify));
});

function tick(){ if(!S)return; S.now++;
  document.querySelectorAll("[data-ts]").forEach(el=>{
    const ts=+el.dataset.ts; if(!ts)return;
    const stale=el.classList.contains("stale");
    el.textContent=(stale?"⚠ ":"")+ago(S.now-ts);
  });
  $("#upd").textContent="live · "+new Date(S.now*1000).toLocaleTimeString();
}
setInterval(tick,1000);

function connect(){
  const es=new EventSource("/events");
  es.addEventListener("state",e=>{
    const next=JSON.parse(e.data);
    if(notify&&prevCol&&"Notification"in window&&Notification.permission==="granted"){
      COLS.forEach(c=>(next.columns[c]||[]).forEach(t=>{
        if(prevCol[t.id]&&prevCol[t.id]!==c) new Notification("✦ POLARIS",{body:`${t.id} → ${c}`});
      }));
    }
    prevCol={};COLS.forEach(c=>(next.columns[c]||[]).forEach(t=>prevCol[t.id]=c));
    S=next;$("#dot").className="dot";render();
  });
  es.addEventListener("ping",()=>{$("#dot").className="dot"});
  es.onerror=()=>{$("#dot").className="dot err";$("#upd").textContent="reconnecting…"};
}
S=BOOT; render(); tick(); connect();
addEventListener("resize",()=>{if(S)constellation()});
</script></body></html>"""

# --------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="POLARIS live board (read-only)")
    ap.add_argument("--root", default=".", help="repo root (default: discover from cwd)")
    ap.add_argument("--port", type=int, default=7373)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()

    root = repo_root(args.root)
    if not os.path.isdir(os.path.join(root, "ops", "board")):
        sys.exit("⛔ no ops/board/ under %s — run `ops/polaris init-board` (or INIT) first" % root)
    if args.host not in ("127.0.0.1", "localhost"):
        print("⚠ binding %s — the board is visible to your network. It is read-only, but board text is exposed." % args.host)

    Handler.root = root
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    srv.daemon_threads = True
    print("✦ POLARIS live board → http://%s:%d   (repo: %s)" % (args.host, args.port, root))
    print("  read-only · Ctrl-C to stop · mutations go through ops/polaris")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")

if __name__ == "__main__":
    main()
