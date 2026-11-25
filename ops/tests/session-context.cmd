# session-context — what SessionStart puts in front of the model (ops/contracts/hook-dispatch.md § 6,
# § 7; ops/contracts/shared-kit.md § 9): in a joined (machine) project ONE JSON object whose
# additionalContext is the router, the voice line (repo → machine → default) and, adhd on, the five
# facts quoted from the vendored skill, then the startup / compact / resume tail; the router
# ≤ 8,000 bytes and (a)-(c) ≤ 9,000; in a git repo without POLARIS the one zero-touch line for
# ask / auto (no origin, an owned origin) and nothing for off / never / a linked worktree / no repo,
# an `upstream` remote, a foreign origin or an existing ops/ folder downgrading auto to ask; and the
# zero-touch path runs with PATH emptied (no fork); vendored → nothing.
# HERMETIC: a fixture KIT (the real polaris, core.sh, docs.sh, CLAUDE.md, the i-have-adhd skill and
# dispatch-session.sh beside STUB update/handover hooks) and fixture repos under mktemp -d; fake
# HOME and CLAUDE_CONFIG_DIR, CLAUDECODE unset, POLARIS_PREFS set per case (empty = machine layer off).
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
unset CLAUDECODE CLAUDE_PROJECT_DIR
export HOME="$F/home" CLAUDE_CONFIG_DIR="$F/home/.claude" PYTHONIOENCODING=utf-8 POLARIS_PREFS=
mkdir -p "$CLAUDE_CONFIG_DIR"
W="$(pwd)"
KR="$F/kit"; K="$KR/ops"
mkdir -p "$K/lib" "$K/hooks" "$KR/.claude/skills/i-have-adhd"
cp kit/ops/polaris "$K/polaris"
cp kit/ops/lib/core.sh kit/ops/lib/docs.sh "$K/lib/"
tr -d '\r' < kit/CLAUDE.md > "$KR/CLAUDE.md"
cp kit/.claude/skills/i-have-adhd/SKILL.md "$KR/.claude/skills/i-have-adhd/SKILL.md"
cp kit/ops/hooks/dispatch-session.sh "$K/hooks/dispatch-session.sh"
printf '#!/usr/bin/env bash\necho "UPDATE-STUB (startup)"\n' > "$K/hooks/update-hook.sh"
printf '#!/usr/bin/env bash\necho "ANCHOR-STUB ($1)"\n' > "$K/hooks/handover-hook.sh"
DS="$K/hooks/dispatch-session.sh"
mkrepo() { ( git init -q "$1" && cd "$1" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i ) >/dev/null 2>&1; }
# machine project: a launcher at ops/polaris, no ops/lib
M="$F/machine"; mkrepo "$M"; mkdir -p "$M/ops"; printf '#!/usr/bin/env bash\n# launcher fixture\n' > "$M/ops/polaris"
PF="$F/prefs"
# run <source> <cwd> [args…] — the standalone face, payload on stdin; stdout to $F/raw
run() { local s="$1" c="$2"; shift 2
  printf '{"session_id":"s1","source":"%s","cwd":"%s","hook_event_name":"SessionStart"}' "$s" "$c" | bash "$DS" "$@" > "$F/raw" 2>"$F/err"; echo "rc=$?"; }
# ctx — the raw stdout must be ONE JSON object; its additionalContext lands in $F/ctx
ctx() { python -c '
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
o = json.loads(raw)
h = o["hookSpecificOutput"]
assert list(o) == ["hookSpecificOutput"] and raw.endswith("}\n") and raw.count("\n") == 1, "not one object"
open(sys.argv[2], "w", encoding="utf-8", newline="").write(h["additionalContext"])
print("one JSON object · event " + h["hookEventName"])' "$F/raw" "$F/ctx"; }
# after — the lines after the router block
after() { python -c '
import sys
c = open(sys.argv[1], encoding="utf-8").read(); r = open(sys.argv[2], encoding="utf-8").read().rstrip("\n")
print("router block first: " + ("yes" if c.startswith(r + "\n") else "NO"))
sys.stdout.write(c[len(r) + 1:])' "$F/ctx" "$F/router"; }
( cd "$M" && bash "$K/polaris" router ) > "$F/router"

echo '== 1. the router fits =='
r=$(wc -c < "$F/router" | tr -d ' ')
[ "$r" -le 8000 ] && echo "router ≤ 8000: yes" || echo "router ≤ 8000: NO ($r)"
cmp -s "$F/router" "$KR/CLAUDE.md" && echo 'router = kit/CLAUDE.md, byte-identical'

echo '== 2. machine project, default voice, adhd off (source clear) =='
run clear "$M"; ctx; after

echo '== 3. voice from the repo · from the machine · a blank repo line falls through =='
printf 'voice: technical\n' > "$M/ops/CONVENTIONS.md"
run clear "$M"; ctx; after | tail -n +2
printf 'voice: standard\n' > "$PF"
POLARIS_PREFS="$PF" run clear "$M" >/dev/null; ctx >/dev/null; after | tail -n +2
printf 'voice:   # none\n' > "$M/ops/CONVENTIONS.md"; printf 'voice: technical\n' > "$PF"
POLARIS_PREFS="$PF" run clear "$M" >/dev/null; ctx >/dev/null; after | tail -n +2
printf 'voice: pirate\n' > "$M/ops/CONVENTIONS.md"
run clear "$M" >/dev/null; ctx >/dev/null; after | tail -n +2

echo '== 4. adhd on — the five facts, verbatim from the skill =='
printf 'voice: standard\nadhd: on\n' > "$M/ops/CONVENTIONS.md"
run clear "$M" >/dev/null; ctx >/dev/null; after | tail -n +2
after | tail -n 5 > "$F/facts"
tr -d '\r' < "$KR/.claude/skills/i-have-adhd/SKILL.md" | grep -E '^[1-5]\. ' | head -5 | cmp -s - "$F/facts" && echo 'facts: identical to the skill'
t=$(python -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read().encode("utf-8")))' "$F/ctx")
[ "$t" -le 9000 ] && echo "≤ 9000: yes" || echo "≤ 9000: NO ($t)"
rm -f "$M/ops/CONVENTIONS.md"; printf 'adhd: on\n' > "$PF"
echo "adhd from the machine: $(POLARIS_PREFS="$PF" run clear "$M" >/dev/null; ctx >/dev/null; after | grep -c '^adhd: on')"
printf 'adhd: off\n' > "$M/ops/CONVENTIONS.md"
echo "repo off over machine on: $(POLARIS_PREFS="$PF" run clear "$M" >/dev/null; ctx >/dev/null; after | grep -c '^adhd: on')"
rm -f "$M/ops/CONVENTIONS.md"
echo "machine layer off, no repo line: $(POLARIS_PREFS= run clear "$M" >/dev/null; ctx >/dev/null; after | grep -c '^adhd: on')"

echo '== 5. the tail: startup · compact · resume =='
run startup "$M" machine "$M" "MG-TEXT (model guard)"; ctx >/dev/null; after | tail -n +3
run startup "$M"; ctx >/dev/null; after | tail -n +3
run compact "$M"; ctx >/dev/null; after | tail -n +3
run resume "$M"; ctx >/dev/null; after | tail -n +3

echo '== 6. where: a worktree cwd · vendored · vendored worktree =='
run clear "$M/.polaris/wt/T-1"; ctx; after | tail -n +2
V="$F/vendored"; mkrepo "$V"; mkdir -p "$V/ops/lib"; cp "$K/polaris" "$V/ops/polaris"
run startup "$V"; echo "bytes: $(wc -c < "$F/raw" | tr -d ' ')"
run startup "$V/.polaris/wt/T-1"; echo "bytes: $(wc -c < "$F/raw" | tr -d ' ')"
run startup "$V" vendored "$V"; echo "bytes: $(wc -c < "$F/raw" | tr -d ' ')"

echo '== 7. zero-touch: a git repo without POLARIS =='
P="$F/plain"; mkrepo "$P"; mkdir -p "$P/src/deep"
z() { run startup "$@" >/dev/null; [ -s "$F/raw" ] && sed "s#$F#<F>#g" "$F/raw" || echo '(nothing)'; }
echo '-- ask (machine layer off), from a subfolder'; z "$P/src/deep"
echo '-- ask, auto_setup unknown';      printf 'auto_setup: maybe\n' > "$PF"; POLARIS_PREFS="$PF" z "$P"
echo '-- auto, no origin';               printf 'auto_setup: auto\n' > "$PF"; POLARIS_PREFS="$PF" z "$P"
git -C "$P" remote add origin https://github.com/acme/thing.git
echo '-- auto, origin owner not in owners → ask'; POLARIS_PREFS="$PF" z "$P"
printf 'auto_setup: auto\nowners: me, acme\n' > "$PF"
echo '-- auto, origin owner in owners';  POLARIS_PREFS="$PF" z "$P"
git -C "$P" remote set-url origin git@github.com:acme/thing.git
echo '-- auto, ssh origin owner in owners'; POLARIS_PREFS="$PF" z "$P"
git -C "$P" remote add upstream https://github.com/other/thing.git
echo '-- auto, an upstream remote → ask'; POLARIS_PREFS="$PF" z "$P"
git -C "$P" remote remove upstream; mkdir "$P/ops"
echo '-- auto, an ops/ folder → ask';    POLARIS_PREFS="$PF" z "$P"
rmdir "$P/ops"
echo '-- off';                           printf 'auto_setup: off\n' > "$PF"; POLARIS_PREFS="$PF" z "$P"
echo '-- never in .git/polaris-setup';   printf 'never\n' > "$P/.git/polaris-setup"; z "$P"
rm -f "$P/.git/polaris-setup"
git -C "$P" worktree add -q "$F/linked" >/dev/null 2>&1
echo '-- a linked worktree (.git is a file)'; z "$F/linked"
echo '-- not a git repo';                mkdir -p "$F/nogit/x"; z "$F/nogit/x"
echo '-- the same ask line with PATH emptied (no fork)'
mkdir -p "$F/nopath"
printf '{"source":"startup","cwd":"%s"}' "$P" | PATH="$F/nopath" "$BASH" "$DS" 2>&1 | sed "s#$F#<F>#g"
