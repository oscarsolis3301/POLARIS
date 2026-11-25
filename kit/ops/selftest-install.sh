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
#   heal-pure   a pre-marker CLAUDE.md (whole file ours, no user text) is WRAPPED, refreshed and
#               stamped `[kit X.Y.Z]`, with a byte-exact backup at .polaris/CLAUDE.md.pre-heal
#   heal-unmarked  same, but the user's own file sat below a `---` separator — it and the separator
#               come out byte-identical, below the END marker
#   heal-refuses   POLARIS text present but NOT at line 1 → the boundary is unknowable, so the file
#               is left BYTE-IDENTICAL and the refusal is stated. All three also assert the quiet
#               line budget locally, because .github/ is RULES-guarded and CI's counted install
#               never reaches the heal branch
#   no-leaks    the installed target carries no board artifacts and still reports "INIT has not run"
#   old-client  install by running <repo>/ops/install.sh — the path `polaris update` walks
#               (the branch tarball's root ops/ IS our installation) — same no-leak + marker checks
#   live-board  install twice over one target: second run says `live-board`, refreshes kit code,
#               leaves board/CONVENTIONS/MAP/SPRINT/RULES byte-identical — then, with `adhd: on`
#               in the target's CONVENTIONS, a third install flips the COPIED i-have-adhd skill to
#               `disable-model-invocation: false` and leaves the kit's own copy opt-in
#   hookmerge   settings.json holding a STALE POLARIS hook entry (ownership-guard at timeout 10)
#               plus two hooks the human added — one of them sharing our basename — is merged:
#               our entry is replaced with the kit's shipped fields, theirs come out untouched,
#               and a second install changes not one byte
#   setup       `--setup` (install-parity v2): refused under CLAUDECODE=1 with settings.json
#               byte-identical; in a fake home it stores the kit as `current`, copies the shim and
#               the trust tier, registers one dispatcher entry per event, folds the old model-guard
#               entries, keeps keep-awake's and the human's, and a second run changes not one byte
#   agent-install  a plain install under CLAUDECODE=1 leaves ~/.claude/settings.json byte-identical
#               and says `⛔ needs you` once; `polaris awake install` refuses the same way
#   uninstall   `polaris uninstall --yes` removes ops/, the managed block and the guard hook,
#               keeps the user's own CLAUDE.md content and hooks
#   repo-clean  this repo is left byte-identical (everything ran in mktemp dirs)
#
# One line per drill; exit 0 only if every drill passed. Needs bash >= 3.2, git, python.
# No network: the only outward call anywhere in the path (doctor's update notice) fails open.
set -u
# The owner's machine file never reaches a drill (machine-prefs.md § 5, same as check.sh's
# goldens): set and empty, so an `adhd: on` at home cannot red the adhd case.
export POLARIS_PREFS=

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

assert_stamped() { # $1 = target — the [kit X.Y.Z] stamp in the BEGIN marker.
  # How `doctor` tells a current block from one frozen years ago; without it a repo can report 5.23
  # while injecting a protocol three weeks older, which is the bug this release closes.
  # Deliberately NOT in assert_one_marker_pair: the old-client drill installs via the repo's ROOT
  # ops/install.sh, which is the PREVIOUS release until `pack.py --dogfood` runs. Asserting a new
  # behavior there would make every install.sh change unreleasable — old-client's job is to prove an
  # OLD client still works, so it may only assert what is true of both.
  grep -qE '<!-- POLARIS:BEGIN .*\[kit [0-9]+\.[0-9]+\.[0-9]+\] -->' "$1/CLAUDE.md" \
    || { say "BEGIN marker carries no [kit X.Y.Z] stamp — doctor cannot detect a stale block"; return 1; }
}

assert_quiet_budget() { # $1 = an install log — the LOCAL stand-in for ci.yml's tripwire.
  # CI counts non-blank lines above the `▶ NEXT` epilogue and allows at most 2. .github/ is
  # RULES-guarded so we cannot add a case there; CI's own counted install happens to land on the
  # prepend branch, so nothing upstream would catch the day a heal starts printing. This does.
  n=$(sed '/^▶ NEXT/,$d' "$1" | grep -c . || true)
  [ "$n" -le 2 ] || { say "quiet install printed $n lines before the epilogue (expected <= 2)"; return 1; }
}

heal_target() { # $1 = dir, $2 = shape: pure | sep | notop — a repo whose CLAUDE.md predates markers
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email drill@example.com
  git -C "$1" config user.name drill
  # A faithful pre-marker block: starts at line 1 with the H1 the old installer wrote.
  printf '# POLARIS v5 — Parallel Sprint Protocol\n\nOLD_PROTOCOL_MARKER\n\n## PROGRESS FORMAT\nold text\n' > "$WORK/old-proto.md"
  case "$2" in
    pure)  cp "$WORK/old-proto.md" "$1/CLAUDE.md";;
    sep)   { cat "$WORK/old-proto.md"; printf '\n---\n\n'; printf 'THEIR_RULE: do not break the build.\n'; } > "$1/CLAUDE.md";;
    notop) { printf '# Their Project\n\nTHEIR_RULE: keep this.\n\n'; cat "$WORK/old-proto.md"; } > "$1/CLAUDE.md";;
  esac
  cp "$1/CLAUDE.md" "$WORK/$(basename "$1").pre"
  echo 'print(1)' > "$1/app.py"
  git -C "$1" add -A
  git -C "$1" commit -qm pristine
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
  [ -f "$T_FRESH/ops/lib/core.sh" ]
  assert_one_marker_pair "$T_FRESH"
  assert_stamped "$T_FRESH"
  grep -q THEIR_HOOK "$T_FRESH/.claude/settings.json"
  grep -q ownership-guard "$T_FRESH/.claude/settings.json"
  ( cd "$T_FRESH" && "$PY" -c "import json; json.load(open('.claude/settings.json'))" )
  # Output style (ops/contracts/output-style.md). new_target ships its own settings.json, so this
  # exercises the MERGE path — the one that can silently regress — not the wholesale copy.
  [ -f "$T_FRESH/.claude/output-styles/polaris.md" ]
  grep -q '^name: POLARIS$' "$T_FRESH/.claude/output-styles/polaris.md"
  # Invariant 1: without this flag the style EXCLUDES Claude Code's built-in coding instructions.
  grep -q '^keep-coding-instructions: true$' "$T_FRESH/.claude/output-styles/polaris.md"
  ( cd "$T_FRESH" && "$PY" -c "import json,sys; sys.exit(0 if json.load(open('.claude/settings.json')).get('outputStyle')=='polaris' else 1)" )
}

drill_heal_pure() {
  # The shape found in the wild: a pre-marker install, whole file ours, no user content. It must be
  # wrapped, refreshed and stamped — and backed up byte-exactly before anything is rewritten.
  heal_target "$WORK/healpure" pure
  ( cd "$WORK/healpure" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/healpure.out"
  cat "$WORK/healpure.out"
  assert_quiet_budget "$WORK/healpure.out"
  b=$(grep -cF 'POLARIS:BEGIN' "$WORK/healpure/CLAUDE.md" || true)
  e=$(grep -cF 'POLARIS:END' "$WORK/healpure/CLAUDE.md" || true)
  [ "$b" = 1 ] && [ "$e" = 1 ]
  grep -qE '\[kit [0-9]+\.[0-9]+\.[0-9]+\]' "$WORK/healpure/CLAUDE.md"
  grep -q 'ROLE DISPATCH' "$WORK/healpure/CLAUDE.md"          # the FRESH protocol landed
  ! grep -q OLD_PROTOCOL_MARKER "$WORK/healpure/CLAUDE.md"    # the stale one is gone
  cmp "$WORK/healpure/.polaris/CLAUDE.md.pre-heal" "$WORK/healpure.pre"
  grep -q 'WRAPPED in markers' "$WORK/healpure/.polaris/install.log"
  grep -q 'No separator was present' "$WORK/healpure/.polaris/install.log"
}

drill_heal_unmarked() {
  # Same heal, but the old installer had appended the user's own file below a `---` separator.
  # Their content and the separator must come out byte-identical, below the END marker.
  heal_target "$WORK/healsep" sep
  ( cd "$WORK/healsep" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/healsep.out"
  cat "$WORK/healsep.out"
  assert_quiet_budget "$WORK/healsep.out"
  assert_one_marker_pair "$WORK/healsep"                      # markers, protocol, THEIR_RULE
  assert_stamped "$WORK/healsep"
  ! grep -q OLD_PROTOCOL_MARKER "$WORK/healsep/CLAUDE.md"
  grep -c '^---$' "$WORK/healsep/CLAUDE.md" | grep -qx 1      # their separator survived
  awk '/POLARIS:END/{f=1} f&&/THEIR_RULE/{found=1} END{exit !found}' "$WORK/healsep/CLAUDE.md"
  cmp "$WORK/healsep/.polaris/CLAUDE.md.pre-heal" "$WORK/healsep.pre"
}

drill_heal_refuses() {
  # The safety rail. POLARIS text present but NOT at line 1 → a human moved or merged it, the
  # boundary is unknowable, and a heal that rewrites what it cannot delimit is how rules get lost.
  # The file must come out BYTE-IDENTICAL and the refusal must be stated.
  heal_target "$WORK/healno" notop
  ( cd "$WORK/healno" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/healno.out"
  cat "$WORK/healno.out"
  assert_quiet_budget "$WORK/healno.out"
  cmp "$WORK/healno/CLAUDE.md" "$WORK/healno.pre"
  ! grep -qF 'POLARIS:BEGIN' "$WORK/healno/CLAUDE.md"
  [ ! -f "$WORK/healno/.polaris/CLAUDE.md.pre-heal" ]         # nothing rewritten → nothing backed up
  grep -q 'NOT healed' "$WORK/healno/.polaris/install.log"
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
  # Corrupt kit code files: the second install must repair them (proof the refresh happened —
  # ops/lib/core.sh rides the live-board dir loop, the loader dies without it).
  printf 'corrupted\n' > "$T_LIVE/ops/MANUAL.md"
  printf 'corrupted\n' > "$T_LIVE/ops/lib/core.sh"
  ( cd "$T_LIVE" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/live2.out"
  cat "$WORK/live2.out"
  grep -q 'installed · live-board' "$WORK/live2.out"
  # A live board must NOT get the run-INIT epilogue — INIT never re-runs over a live board.
  ! grep -q 'read ops/roles/INIT.md' "$WORK/live2.out"
  ! grep -qx 'corrupted' "$T_LIVE/ops/MANUAL.md"
  ! grep -qx 'corrupted' "$T_LIVE/ops/lib/core.sh"
  board_snapshot "$T_LIVE" > "$WORK/board-after"
  cmp "$WORK/board-before" "$WORK/board-after"
  # adhd — the repo preference, re-applied on EVERY copy (ops/contracts/first-run.md § 2).
  # The vendored skill is opt-in by its own frontmatter and is copied verbatim, so a repo that
  # answered `adhd: on` once would have the flag silently re-armed by every update: the line still
  # sits in CONVENTIONS.md and simply stops working. Both directions, because only the pair proves
  # it — a copy that always writes `false` is just as wrong, and would load the skill into every
  # session of every repo that never asked for it.
  A_SKILL="$T_LIVE/.claude/skills/i-have-adhd/SKILL.md"
  grep -q '^disable-model-invocation: true$' "$A_SKILL"
  printf 'adhd: on
' >> "$T_LIVE/ops/CONVENTIONS.md"
  ( cd "$T_LIVE" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/live3.out"
  grep -q '^disable-model-invocation: false$' "$A_SKILL"
  grep -q '^disable-model-invocation: true$' "$KIT/.claude/skills/i-have-adhd/SKILL.md"
}

drill_hookmerge() {
  # The half of the settings.json merge that was silently broken for three releases: it keyed on
  # hook script BASENAME and skipped every entry it already saw, so a POLARIS entry, once written,
  # could never be CORRECTED. Measured in polaris-testbed — pinned at ownership-guard.sh
  # `timeout: 10` against a guard ops/lib/core.sh clocks at ~8s per write, i.e. parked on the
  # fail-open margin where the ownership gate quietly stops applying, with no update able to
  # rescue it. Identity is the script PATH under ops/hooks/ now, so this drill has to prove BOTH
  # halves in one run: OUR entry is refreshed to the shipped fields, THEIRS is never touched.
  new_target "$WORK/hookmerge"
  # A stale POLARIS entry (wrong matcher AND wrong timeout) between two hooks the human added.
  # The last one runs `tools/ownership-guard.sh` — our basename, their script: under the old
  # matcher its mere presence suppressed our own entry, which is why basename identity had to go.
  cat > "$WORK/hookmerge/.claude/settings.json" <<'JSONEOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "echo THEIR_HOOK" }]
      },
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/ops/hooks/ownership-guard.sh\"",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "bash tools/ownership-guard.sh", "timeout": 1 }]
      }
    ]
  }
}
JSONEOF
  cp "$WORK/hookmerge/.claude/settings.json" "$WORK/hookmerge.pre"
  ( cd "$WORK/hookmerge" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/hookmerge1.out"
  cat "$WORK/hookmerge1.out"
  grep -q 'installed · fresh' "$WORK/hookmerge1.out"
  # Path as argv, never inline — Git Bash converts argv paths for native python (see zip-purity).
  "$PY" - "$WORK/hookmerge/.claude/settings.json" "$KIT/.claude/settings.json" "$WORK/hookmerge.pre" <<'PYEOF'
import json, sys
merged = json.load(open(sys.argv[1], encoding="utf-8"))
kit    = json.load(open(sys.argv[2], encoding="utf-8"))
pre    = json.load(open(sys.argv[3], encoding="utf-8"))
got, want = merged["hooks"]["PreToolUse"], kit["hooks"]["PreToolUse"]
canon = lambda e: json.dumps(e, sort_keys=True)
ours  = lambda es: [e for e in es if "ops/hooks/" in json.dumps(e)]
mine  = lambda es: [e for e in es if "ops/hooks/" not in json.dumps(e)]

# 1. every kit entry is present EXACTLY as shipped — matcher, timeout and command together
for w in want:
    if canon(w) not in [canon(e) for e in got]:
        sys.exit("kit entry did not land verbatim: " + canon(w))
# 2. replaced IN PLACE, never duplicated: one POLARIS entry per kit entry, and the stale one
#    kept its slot (index 1) rather than being appended behind the user's hooks
if len(ours(got)) != len(want):
    sys.exit("expected %d POLARIS entries, found %d: %s" % (len(want), len(ours(got)), got))
if "ops/hooks/ownership-guard.sh" not in json.dumps(got[1]):
    sys.exit("the refreshed entry lost its list position: " + canon(got[1]))
# 3. the user's hooks are untouched, in order — including the one sharing our basename
if [canon(e) for e in mine(pre["hooks"]["PreToolUse"])] != [canon(e) for e in mine(got)]:
    sys.exit("user hooks were modified: %s" % json.dumps(mine(got)))
PYEOF
  # The repair is REPORTED, not silent — a fix no one can see is how the old bug survived.
  grep -q 'updated ops/hooks/ownership-guard.sh' "$WORK/hookmerge/.polaris/install.log"
  grep -q 'added ops/hooks/readonly-allow.sh' "$WORK/hookmerge/.polaris/install.log"
  cp "$WORK/hookmerge/.claude/settings.json" "$WORK/hookmerge.after1"
  # 4. idempotent: a second install changes not one byte, and claims no update it did not make.
  ( cd "$WORK/hookmerge" && "$PY" "$ZIP" --no-machine-setup ) > "$WORK/hookmerge2.out"
  cmp "$WORK/hookmerge.after1" "$WORK/hookmerge/.claude/settings.json"
  ! grep -q 'updated ops/hooks/' "$WORK/hookmerge/.polaris/install.log"
}

_fake_home() { # _fake_home <dir> <cmd…> — run <cmd> with every home seam inside <dir>, never the real ~/.claude
  local h="$1"; shift
  env HOME="$h" USERPROFILE="$h" CLAUDE_CONFIG_DIR="$h/.claude" POLARIS_AWAKE_HOME="$h/.claude/polaris/awake" \
    PYTHONIOENCODING=utf-8 "$@"
}

_drill_setup() {
  # install-parity v2 / shared-kit.md § 10: --setup is the ONE writer of Claude Code's own settings,
  # and only the owner runs it. The fake machine is one an older kit armed: the user-level model
  # guard registered (the dispatcher folds it), keep-awake registered, and one hook of the human's.
  H="$WORK/setuphome"; C="$H/.claude"; PH="$C/polaris"
  mkdir -p "$PH"
  cat > "$C/settings.json" <<JSONEOF
{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "timeout": 5, "command": "\"/bin/bash\" \"$PH/model-guard.sh\""}]},
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo MY_OWN_HOOK"}]}],
 "SessionStart": [{"hooks": [{"type": "command", "timeout": 5, "command": "\"/bin/bash\" \"$PH/model-guard.sh\""}]},
  {"hooks": [{"type": "command", "timeout": 5, "command": "\"/bin/bash\" \"$PH/awake-hook.sh\" start 2>/dev/null || true"}]}]}}
JSONEOF
  cp "$C/settings.json" "$WORK/setup.pre"
  # 1. run by an agent: refused, rc 2, nothing written anywhere
  rc=0; _fake_home "$H" CLAUDECODE=1 "$PY" "$ZIP" --setup > "$WORK/setup0.out" 2>&1 || rc=$?
  cat "$WORK/setup0.out"
  [ "$rc" = 2 ]
  grep -q -- "--setup changes Claude Code's own settings — run it in your own terminal, not through an agent" "$WORK/setup0.out"
  cmp "$WORK/setup.pre" "$C/settings.json"
  # one test per line: set -e skips a failure anywhere but last in an && list, and after a `!`
  [ ! -e "$PH/kit" ]
  [ ! -e "$PH/hook" ]
  [ ! -e "$PH/trust" ]
  # 2. the owner: the store, the shim, the trust tier, the registration
  _fake_home "$H" CLAUDECODE= "$PY" "$ZIP" --setup > "$WORK/setup1.out" 2>&1
  cat "$WORK/setup1.out"
  v="$(sed -n 's/^version: *//p' "$KIT/ops/VERSION" | tr -d '\r')"
  [ "$(tr -d '\r' < "$PH/kit/current")" = "$v" ]
  [ -f "$PH/kit/$v/.stored" ]
  [ -f "$PH/kit/$v/ops/polaris" ]
  [ -f "$PH/kit/$v/polaris-v5.zip" ]
  cmp "$PH/hook" "$KIT/ops/hooks/shim.sh"
  cmp "$PH/trust/readonly-allow.sh" "$KIT/ops/hooks/readonly-allow.sh"
  "$PY" - "$C/settings.json" <<'PYEOF'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
hooks = d["hooks"]
cmds = lambda e: [str(h.get("command", "")).replace("\\", "/") for h in e.get("hooks", [])]
EVENTS = ("PreToolUse PostToolUse SessionStart PreModelSwitch PostModelSwitch UserPromptSubmit Stop "
          "SubagentStop StopFailure PermissionRequest PermissionDenied").split()
for ev in EVENTS:
    ours = [e for e in hooks.get(ev, []) if any(re.search(r'polaris/hook" %s$' % ev, c) for c in cmds(e))]
    if len(ours) != 1:
        sys.exit("%s: %d dispatcher entries, want 1" % (ev, len(ours)))
if hooks["PreToolUse"][0].get("matcher") != "*" or "polaris/hook" not in cmds(hooks["PreToolUse"][0])[0]:
    sys.exit("PreToolUse: the dispatcher is not first with matcher *")
left = [c for es in hooks.values() for e in es for c in cmds(e) if "polaris/model-guard.sh" in c]
if left:
    sys.exit("a folded model-guard entry survived: %s" % left)
for ev in ("SessionStart", "UserPromptSubmit", "Stop", "SessionEnd"):
    n = sum(1 for e in hooks.get(ev, []) for c in cmds(e) if "polaris/awake-hook.sh" in c)
    if n != 1:
        sys.exit("%s: %d keep-awake entries, want 1" % (ev, n))
if not any("MY_OWN_HOOK" in c for e in hooks["PreToolUse"] for c in cmds(e)):
    sys.exit("the human's own hook was lost")
if "Bash(bash ops/polaris:*)" not in d.get("permissions", {}).get("allow", []):
    sys.exit("the --claude-skill half of --setup did not run (no permission rules)")
PYEOF
  cp "$C/settings.json" "$WORK/setup.after1"
  ( cd "$C" && find . -type f | sort | xargs cksum ) > "$WORK/setup.tree1"
  # 3. a second run, and one from the stored zip itself: not one byte changes
  _fake_home "$H" CLAUDECODE= "$PY" "$ZIP" --setup > "$WORK/setup2.out" 2>&1
  _fake_home "$H" CLAUDECODE= "$PY" "$PH/kit/$v/polaris-v5.zip" --setup > "$WORK/setup3.out" 2>&1
  cmp "$WORK/setup.after1" "$C/settings.json"
  ( cd "$C" && find . -type f | sort | xargs cksum ) | cmp "$WORK/setup.tree1" -
}

_drill_agent_install() {
  # shared-kit.md § 11: an install an agent runs writes no permission, mode or hook — it arms the
  # rest of the machine, says `⛔ needs you` ONCE, and the routing marker still lands.
  new_target "$WORK/agentinst"
  H="$WORK/agenthome"; mkdir -p "$H/.claude"
  printf '{"permissions":{"allow":[]}}\n' > "$H/.claude/settings.json"
  cp "$H/.claude/settings.json" "$WORK/agent.pre"
  ( cd "$WORK/agentinst" && _fake_home "$H" CLAUDECODE=1 "$PY" "$ZIP" ) > "$WORK/agent1.out" 2>&1
  cat "$WORK/agent1.out"
  grep -q 'installed · fresh' "$WORK/agent1.out"
  [ "$(grep -c '⛔ needs you: python .* --setup in your own terminal (permissions and hooks are yours to grant)' "$WORK/agent1.out")" = 1 ]
  if grep -q 'permissions.allow' "$WORK/agent1.out"; then exit 1; fi   # no rule block handed to the agent
  cmp "$WORK/agent.pre" "$H/.claude/settings.json"
  [ -f "$H/.claude/skills/polaris-install/polaris-v5.zip" ]   # the rest of the arm still happened
  # the keep-awake registration refuses the same way, from the installed project
  rc=0; ( cd "$WORK/agentinst" && _fake_home "$H" CLAUDECODE=1 bash ops/polaris awake install ) > "$WORK/agent2.out" 2>&1 || rc=$?
  cat "$WORK/agent2.out"
  [ "$rc" = 2 ]
  grep -q '⛔ needs you:' "$WORK/agent2.out"
  cmp "$WORK/agent.pre" "$H/.claude/settings.json"
}

drill_uninstall() {
  [ -f "$T_FRESH/ops/polaris" ]      # depends on drill fresh
  ( cd "$T_FRESH" && bash ops/polaris uninstall --yes ) > "$WORK/uninstall.out"
  [ ! -d "$T_FRESH/ops" ]
  grep -q THEIR_RULE "$T_FRESH/CLAUDE.md"
  ! grep -qF 'POLARIS:BEGIN' "$T_FRESH/CLAUDE.md"
  grep -q THEIR_HOOK "$T_FRESH/.claude/settings.json"
  ! grep -q ownership-guard "$T_FRESH/.claude/settings.json"
  # Our style and our key go; a style the human chose is theirs and must survive (invariant 4).
  [ ! -f "$T_FRESH/.claude/output-styles/polaris.md" ]
  ! grep -q '"outputStyle"' "$T_FRESH/.claude/settings.json"
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
# The heal drills build their OWN targets, so they must not run between fresh and the drills that
# depend on $T_FRESH (no-leaks, uninstall). Placed here they are independent of every other drill.
drill heal-pure     drill_heal_pure
drill heal-unmarked drill_heal_unmarked
drill heal-refuses  drill_heal_refuses
drill no-leaks    drill_no_leaks
drill old-client  drill_old_client
drill live-board  drill_live_board
# Builds its own target, like the heal drills — independent of every other drill.
drill hookmerge   drill_hookmerge
# Both build their own fake home and target — independent of every other drill.
drill setup         _drill_setup
drill agent-install _drill_agent_install
drill uninstall   drill_uninstall
drill repo-clean  drill_repo_clean

if [ "$FAIL" = 1 ]; then
  say "⛔ install drill FAILED — do not push install.sh/pack.py/bootstrap.py changes"
  exit 1
fi
say "✅ install drill green — all drills passed"
