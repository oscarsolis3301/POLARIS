#!/usr/bin/env bash
# POLARIS — dashboard smoke drill. The `test:` for kit/ops/dashboard.py (previously untested —
# see ops/MAP.md "Unverified": CI never launches it, so a silent break shipped to every user who
# ran `polaris dash`).
#
#     bash kit/ops/selftest-dashboard.sh
#
# Starts dashboard.py on a throwaway loopback port (an OS-assigned ephemeral port — NEVER 7373, a
# live `polaris dash` must be untouched), waits for it to come up, drills GET / and GET /state
# per ops/contracts/dashboard-http.md, then kills the server on every exit path (trap). Read-only:
# dashboard.py is human-maintained code (ops/CONVENTIONS.md write routing) — never edited here.
#
# One line per drill; exit 0 only if every drill passed. Needs bash >= 3.2, git, python (3.8+
# stdlib only — no curl/wget). No network beyond the local loopback server this script starts.
set -u

say() { printf '%s\n' "$*"; }
die() { printf '⛔ %s\n' "$*" >&2; exit 1; }

# --- where am I --------------------------------------------------------------------
KIT="$(cd "$(dirname "$0")/.." && pwd)"        # <repo>/kit
REPO="$(cd "$KIT/.." && pwd)"                  # <repo>
DASH="$KIT/ops/dashboard.py"
[ -f "$DASH" ] || die "not found: $DASH"
[ -d "$REPO/ops/board" ] || die "no $REPO/ops/board — dashboard.py refuses to serve without a live board"

# `-c pass` proves a REAL interpreter (the Windows Store python3 stub passes `command -v` but
# only prints an ad when actually run).
PY=""
python3 -c pass >/dev/null 2>&1 && PY=python3
[ -n "$PY" ] || { python -c pass >/dev/null 2>&1 && PY=python; }
[ -n "$PY" ] || die "no working python — dashboard.py needs one"

HOST=127.0.0.1

# --- scratch + leave-no-trace --------------------------------------------------------
WORK="$(mktemp -d)" || die "mktemp failed"
LOG="$WORK/server.log"
PID=""

cleanup() {
  # No orphan process on ANY exit path, including a failed assertion mid-drill.
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    i=0
    while [ "$i" -lt 20 ] && kill -0 "$PID" 2>/dev/null; do
      sleep 0.1 2>/dev/null || sleep 1
      i=$((i + 1))
    done
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

git -C "$REPO" status --porcelain > "$WORK/repo-before" 2>/dev/null

FAIL=0
drill() { # $1 = name, $2 = function — one line per drill, full trace only on failure
  if ( set -e; "$2" ) > "$WORK/$1.log" 2>&1; then
    say "✅ drill $1"
  else
    say "⛔ drill $1 FAILED —"
    sed 's/^/   /' "$WORK/$1.log"
    FAIL=1
  fi
}

# --- port pick: an OS-assigned free loopback port, never the live-dashboard default ------------
PORT="$("$PY" - <<'PYEOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PYEOF
)"
case "$PORT" in
  ''|*[!0-9]*) die "could not pick a free port" ;;
esac
[ "$PORT" = 7373 ] && die "picked 7373 — refusing to touch the live dashboard port"

# --- start: launch the server and wait for it to accept connections ---------------------------
# Not run through drill() — it must set $PID in THIS shell (drill()'s subshell would lose it),
# and cleanup() needs that PID to guarantee no orphan on any later failure.
"$PY" "$DASH" --root "$REPO" --host "$HOST" --port "$PORT" > "$LOG" 2>&1 &
PID=$!

ready=0
if "$PY" - "$HOST" "$PORT" <<'PYEOF'
import sys, time, urllib.request
host, port = sys.argv[1], sys.argv[2]
url = "http://%s:%s/" % (host, port)
deadline = time.time() + 5
while time.time() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=1) as r:
            sys.exit(0 if r.status == 200 else 1)
    except Exception:
        time.sleep(0.15)
sys.exit(1)
PYEOF
then
  ready=1
fi
if [ "$ready" = 1 ] && kill -0 "$PID" 2>/dev/null; then
  say "✅ drill start"
else
  say "⛔ drill start FAILED —"
  sed 's/^/   /' "$LOG" 2>/dev/null
  say "⛔ dashboard smoke drill FAILED — server never became ready, skipping remaining drills"
  exit 1
fi

# --- get-root: GET / -> 200 ---------------------------------------------------------
drill_get_root() {
  "$PY" - "$HOST" "$PORT" <<'PYEOF'
import sys, urllib.request
host, port = sys.argv[1], sys.argv[2]
with urllib.request.urlopen("http://%s:%s/" % (host, port), timeout=3) as r:
    assert r.status == 200, "GET / -> %s" % r.status
    body = r.read()
    assert len(body) > 0, "GET / returned an empty body"
PYEOF
}
drill get-root drill_get_root

# --- get-state: GET /state -> 200 JSON, columns has exactly the 6 contract keys --------------
drill_get_state() {
  "$PY" - "$HOST" "$PORT" <<'PYEOF'
import sys, json, urllib.request
host, port = sys.argv[1], sys.argv[2]
with urllib.request.urlopen("http://%s:%s/state" % (host, port), timeout=3) as r:
    assert r.status == 200, "GET /state -> %s" % r.status
    ctype = r.headers.get("Content-Type", "")
    assert "json" in ctype, "Content-Type %r has no json" % ctype
    body = r.read()
data = json.loads(body)
assert isinstance(data, dict), "body is not a JSON object"
cols = data.get("columns")
assert isinstance(cols, dict), "columns is not a JSON object"
expect = {"backlog", "ready", "active", "review", "blocked", "done"}
got = set(cols.keys())
assert got == expect, "columns keys %s != %s" % (sorted(got), sorted(expect))
for k, v in cols.items():
    assert isinstance(v, list), "columns[%r] is not an array" % k
PYEOF
}
drill get-state drill_get_state

# --- stop: kill the server now (cleanup() would also catch it, but the repo-clean check below
# wants it gone first, and this proves the trap path terminates a live server cleanly). ----------
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null
  i=0
  while [ "$i" -lt 20 ] && kill -0 "$PID" 2>/dev/null; do
    sleep 0.1 2>/dev/null || sleep 1
    i=$((i + 1))
  done
fi
if kill -0 "$PID" 2>/dev/null; then
  say "⛔ drill stop FAILED — server still alive after SIGTERM + 2s"
  FAIL=1
else
  say "✅ drill stop"
fi

# --- repo-clean: dashboard.py is read-only by design; the repo must be byte-identical ----------
drill_repo_clean() {
  git -C "$REPO" status --porcelain > "$WORK/repo-after" 2>/dev/null
  cmp "$WORK/repo-before" "$WORK/repo-after"
}
drill repo-clean drill_repo_clean

if [ "$FAIL" = 1 ]; then
  say "⛔ dashboard smoke drill FAILED"
  exit 1
fi
say "✅ dashboard smoke drill green — all drills passed"
