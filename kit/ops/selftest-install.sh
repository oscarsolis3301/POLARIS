#!/usr/bin/env bash
# POLARIS — local install drill. The `test:` for any install.sh / pack.py / bootstrap.py change.
#
#     bash kit/ops/selftest-install.sh
#
# Runs the same drills CI runs (.github/workflows/ci.yml), on this machine, before you push:
#   pack        build polaris-v5.zip with kit/ops/pack.py (no `zip` binary needed)
#   zip-purity  the zip carries the PRODUCT, never our board (CONVENTIONS/MAP/SPRINT/RULES/board)
#   fresh       zip install into a repo with its own CLAUDE.md + PreToolUse hook — both survive,
#               the guard is merged, CLAUDE.md ends with exactly one BEGIN/END marker pair
#   no-leaks    the installed target carries no board artifacts and still reports "INIT has not run"
#   old-client  install by running <repo>/ops/install.sh — the path `polaris update` walks
#               (the branch tarball's root ops/ IS our installation) — same no-leak + marker checks
#   live-board  install twice over one target: second run says `live-board`, refreshes kit code,
#               leaves board/CONVENTIONS/MAP/SPRINT/RULES byte-identical
#   uninstall   `polaris uninstall --yes` removes ops/, the managed block and the guard hook,
#               keeps the user's own CLAUDE.md content and hooks
#   repo-clean  this repo is left byte-identical (everything ran in mktemp dirs)
#
# One line per drill; exit 0 only if every drill passed. Needs bash >= 3.2, git, python.
# No network: the only outward call anywhere in the path (doctor's update notice) fails open.
set -u

say()  { printf '%s\n' "$*"; }
die()  { printf '⛔ %s\n' "$*" >&2; exit 1; }

# --- where am I ------------------------------------------------------------------
# The pack.py tell (ops/contracts/self-hosting.md): pack.py exists in a kit SOURCE tree and
# nowhere else. Never test ops/board/ or ops/CONVENTIONS.md — those answer a different question.
KIT="$(cd "$(dirname "$0")/.." && pwd)"        # <repo>/kit
REPO="$(cd "$KIT/.." && pwd)"                  # <repo> — self-hosts an instance at ops/
[ -f "$KIT/ops/pack.py" ] || die "not a kit source tree (no $KIT/ops/pack.py) — run me from the POLARIS repo"
[ -f "$REPO/ops/install.sh" ] || die "no $REPO/ops/install.sh — the old-client drill needs the installed instance"

# `-c pass` proves a REAL interpreter (the Windows Store python3 stub passes command -v).
PY=""
python3 -c pass >/dev/null 2>&1 && PY=python3
[ -n "$PY" ] || { python -c pass >/dev/null 2>&1 && PY=python; }
[ -n "$PY" ] || die "no working python — pack.py and the zipapp install need one"
command -v git >/dev/null 2>&1 || die "no git on PATH"

# --- scratch + leave-no-trace ----------------------------------------------------
WORK="$(mktemp -d)" || die "mktemp failed"
ZIP="$REPO/polaris-v5.zip"
PACKED=0
cleanup() {
  # Restore the repo exactly as found: drop the zip WE packed, put back any pre-existing one.
  # Never rm -rf anything we did not mktemp — this runs on the maintainer's machine.
  [ "$PACKED" = 1 ] && rm -f "$ZIP"
  [ -f "$WORK/saved-polaris-v5.zip" ] && mv "$WORK/saved-polaris-v5.zip" "$ZIP"
  rm -rf "$WORK"
}
trap cleanup EXIT
[ -f "$ZIP" ] && mv "$ZIP" "$WORK/saved-polaris-v5.zip"

git -C "$REPO" status --porcelain > "$WORK/repo-before" 2>/dev/null

T_FRESH="$WORK/fresh"
T_OLD="$WORK/oldclient"
T_LIVE="$WORK/liveboard"

# --- helpers -----------------------------------------------------------------------
new_target() { # $1 = dir — a temp project with its own CLAUDE.md and its own PreToolUse hook
  mkdir -p "$1/src" "$1/.claude"
  git -C "$1" init -q
  git -C "$1" config user.email drill@example.com
  git -C "$1" config user.name drill
  printf '# Their Project\n\nTHEIR_RULE: do not break the build.\n' > "$1/CLAUDE.md"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo THEIR_HOOK"}]}]}}\n' > "$1/.claude/settings.json"
  echo 'print(1)' > "$1/src/app.py"
  git -C "$1" add -A
  git -C "$1" commit -qm pristine
}

assert_no_leaks() { # $1 = target — our board must never land in a stranger's repo
  for f in CONVENTIONS.md MAP.md SPRINT.md RULES.tsv; do
    [ ! -f "$1/ops/$f" ] || { say "LEAK: ops/$f"; return 1; }
  done
  [ ! -d "$1/ops/board" ] || { say "LEAK: ops/board/"; return 1; }
}

assert_one_marker_pair() { # $1 = target — a nested pair means uninstall cannot delimit the block
  b=$(grep -cF 'POLARIS:BEGIN' "$1/CLAUDE.md" || true)
  e=$(grep -cF 'POLARIS:END' "$1/CLAUDE.md" || true)
  [ "$b" = 1 ] && [ "$e" = 1 ] || { say "CLAUDE.md has $b BEGIN / $e END markers"; return 1; }
  grep -q 'ROLE DISPATCH' "$1/CLAUDE.md" || { say "managed block carries no protocol"; return 1; }
  grep -q THEIR_RULE "$1/CLAUDE.md" || { say "install ate the user's CLAUDE.md"; return 1; }
}

FAIL=0
drill() { # $1 = name, $2 = function — one line per drill, full trace only on failure
  if ( set -ex; "$2" ) > "$WORK/$1.log" 2>&1; then
    say "✅ drill $1"
  else
    say "⛔ drill $1 FAILED —"
    sed 's/^/   /' "$WORK/$1.log"
    FAIL=1
  fi
}

# --- drills --------------------------------------------------------------------------
drill_pack() {
  # --allow-dirty: this runs mid-change by design — that is the whole point of a local drill.
  "$PY" "$KIT/ops/pack.py" --allow-dirty
  [ -f "$ZIP" ]
}

drill_zip_purity() {
  # Lifted from CI "The zip carries the PRODUCT, never our board". Path as argv, never inline —
  # Git Bash converts argv paths for native python; strings inside code it does not.
  "$PY" - "$ZIP" <<'PYEOF'
import sys, zipfile
FORBIDDEN = ("CONVENTIONS.md", "MAP.md", "SPRINT.md", "RULES.tsv")
names = zipfile.ZipFile(sys.argv[1]).namelist()
bad = [n for n in names
       if n.rsplit("/", 1)[-1] in FORBIDDEN
       or "/board/" in n
       or n.startswith("polaris-v5/.github/")]
for n in sorted(bad):
    print(f"LEAK in zip: {n}")
sys.exit(1 if bad else 0)
PYEOF
}

drill_fresh() {
  new_target "$T_FRESH"
  # --no-machine-setup: nothing outside the target repo, so ~/.claude stays untouched.
  ( cd "$T_FRESH" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/fresh.out"
  cat "$WORK/fresh.out"
  grep -q 'installed · fresh' "$WORK/fresh.out"
  # First-contact routing: fresh output MUST carry the agent epilogue (a machine's first-ever
  # install has no skill loaded — the epilogue is the only thing that chains into INIT).
  grep -q 'read ops/roles/INIT.md' "$WORK/fresh.out"
  [ -f "$T_FRESH/ops/polaris" ]
  assert_one_marker_pair "$T_FRESH"
  grep -q THEIR_HOOK "$T_FRESH/.claude/settings.json"
  grep -q ownership-guard "$T_FRESH/.claude/settings.json"
  ( cd "$T_FRESH" && "$PY" -c "import json; json.load(open('.claude/settings.json'))" )
}

drill_no_leaks() {
  [ -f "$T_FRESH/ops/polaris" ]      # depends on drill fresh
  assert_no_leaks "$T_FRESH"
  # Capture, THEN grep — `doctor | grep -q` dies of SIGPIPE under pipefail (see ci.yml).
  ( cd "$T_FRESH" && bash ops/polaris doctor ) > "$WORK/doctor.out"
  grep -q 'INIT has not run' "$WORK/doctor.out"
}

drill_old_client() {
  # `polaris update` installs from the branch tarball's ROOT ops/ — which in this repo is our
  # live installation. Simulate that client exactly: install from <repo>/ops/install.sh.
  new_target "$T_OLD"
  bash "$REPO/ops/install.sh" --quiet "$T_OLD" > "$WORK/oldclient.out"
  cat "$WORK/oldclient.out"
  grep -q 'installed · fresh' "$WORK/oldclient.out"
  [ -f "$T_OLD/ops/polaris" ]
  assert_no_leaks "$T_OLD"
  assert_one_marker_pair "$T_OLD"
}

board_snapshot() { # $1 = target, stdout = checksums of everything an update must not touch
  ( cd "$1" && cksum ops/CONVENTIONS.md ops/MAP.md ops/SPRINT.md ops/RULES.tsv \
    && find ops/board -type f | sort | xargs cksum )
}

drill_live_board() {
  new_target "$T_LIVE"
  ( cd "$T_LIVE" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/live1.out"
  grep -q 'installed · fresh' "$WORK/live1.out"
  ( cd "$T_LIVE" && bash ops/polaris init-board ) >/dev/null
  # A live board = INIT has run = CONVENTIONS.md exists. Seed it plus the other INIT artifacts
  # with sentinel content the refresh must not touch.
  printf '# CONVENTIONS\nbase: main\nvoice: technical\ntest: echo hi\n' > "$T_LIVE/ops/CONVENTIONS.md"
  printf '# MAP — SENTINEL\n'    > "$T_LIVE/ops/MAP.md"
  printf '# SPRINT — SENTINEL\n' > "$T_LIVE/ops/SPRINT.md"
  printf 'sentinel\trule\n'      > "$T_LIVE/ops/RULES.tsv"
  board_snapshot "$T_LIVE" > "$WORK/board-before"
  # Corrupt a kit code file: the second install must repair it (proof the refresh happened).
  printf 'corrupted\n' > "$T_LIVE/ops/MANUAL.md"
  ( cd "$T_LIVE" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/live2.out"
  cat "$WORK/live2.out"
  grep -q 'installed · live-board' "$WORK/live2.out"
  # A live board must NOT get the run-INIT epilogue — INIT never re-runs over a live board.
  ! grep -q 'read ops/roles/INIT.md' "$WORK/live2.out"
  ! grep -qx 'corrupted' "$T_LIVE/ops/MANUAL.md"
  board_snapshot "$T_LIVE" > "$WORK/board-after"
  cmp "$WORK/board-before" "$WORK/board-after"
}

drill_uninstall() {
  [ -f "$T_FRESH/ops/polaris" ]      # depends on drill fresh
  ( cd "$T_FRESH" && bash ops/polaris uninstall --yes ) > "$WORK/uninstall.out"
  [ ! -d "$T_FRESH/ops" ]
  grep -q THEIR_RULE "$T_FRESH/CLAUDE.md"
  ! grep -qF 'POLARIS:BEGIN' "$T_FRESH/CLAUDE.md"
  grep -q THEIR_HOOK "$T_FRESH/.claude/settings.json"
  ! grep -q ownership-guard "$T_FRESH/.claude/settings.json"
}

drill_repo_clean() {
  git -C "$REPO" status --porcelain > "$WORK/repo-after" 2>/dev/null
  cmp "$WORK/repo-before" "$WORK/repo-after"
}

# --- run ---------------------------------------------------------------------------
PACKED=1
drill pack        drill_pack
if [ "$FAIL" = 1 ]; then say "⛔ cannot pack the kit — nothing else can run"; exit 1; fi
drill zip-purity  drill_zip_purity
drill fresh       drill_fresh
drill no-leaks    drill_no_leaks
drill old-client  drill_old_client
drill live-board  drill_live_board
drill uninstall   drill_uninstall
drill repo-clean  drill_repo_clean

if [ "$FAIL" = 1 ]; then
  say "⛔ install drill FAILED — do not push install.sh/pack.py/bootstrap.py changes"
  exit 1
fi
say "✅ install drill green — all drills passed"
