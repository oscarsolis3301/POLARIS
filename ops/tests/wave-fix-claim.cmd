# wave-fix-claim — a fix card for a red wave is cut from the wave (ops/contracts/safe-landing.md v2).
#
# One fixture, the integrator lane driven by hand (landing: integrator):
#   a. T-1 lands on the open wave, changing f and g
#   b. T-2 owns f (a path the wave changed) → claim cuts feat/T-2 from the wave tip and records it in
#      branch.feat/T-2.polaris-cut; verify is green with a diff of exactly the fix (cut from $BASE it
#      would also carry g, which T-2 does not own); land squashes clean onto the wave
#   c. T-3 owns h (no wave path) → cut from $BASE, no config key
#   d. T-4 owns g → cut from the wave, key recorded; release drops the key with the branch
# HERMETIC: one throwaway repo under mktemp -d, no remote, no session id, HOME, USERPROFILE and
# POLARIS_AWAKE_HOME faked together, POLARIS_PREFS empty, the CLI run from INSIDE it. No sha, date or path.
unset CLAUDE_CODE_SESSION_ID CLAUDECODE POLARIS_INT_TOKEN POLARIS_SEAL_NOCHECK
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home" CLAUDE_CONFIG_DIR="$FIX/home/.claude" POLARIS_PREFS=
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
task() { # task <ID> <file>... — a ready task owning the files
  local id="$1"; shift
  { printf -- '---\nid: %s\ntitle: lane %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n' "$id" "$id"
    for f in "$@"; do printf '  - %s\n' "$f"; done
    printf 'verify:\n  - grep -q . %s\n---\n## Why\nlane %s.\n' "$1" "$id"; } > "ops/board/ready/$id.md"
}
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  for f in f g h; do echo x > "$f"; done
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf '# SPRINT 1 — wave fix  capacity: 20\n' > ops/SPRINT.md
  task T-1 f g; task T-3 h
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
yn() { if "$@"; then echo yes; else echo no; fi; }
cutkey() { git config --get "branch.feat/$1.polaris-cut" 2>/dev/null || echo "(none)"; }
wave() { git for-each-ref --format='%(refname:short)' 'refs/heads/integrate/' | head -1; }

echo '== a. T-1 lands on the open wave =='
bash "$KIT" claim T-1 >/dev/null 2>&1
( cd .polaris/wt/T-1 && echo y > f && echo y > g && git commit -qam "feat: T-1 the edit" && bash "$KIT" handoff T-1 ) >/dev/null 2>&1
bash "$KIT" land T-1 >/dev/null 2>&1; echo "land rc=$?"
W="$(wave)"; TIP="$(git rev-parse "$W")"
echo "T-1 cut key: $(cutkey T-1)"

echo '== b. T-2 owns f, a path the wave changed =='
task T-2 f   # authored now: the ready gate refuses two ready cards sharing f
OUT="$(bash "$KIT" claim T-2 2>&1)"; echo "claim rc=$?"
printf '%s\n' "$OUT" | tr -d '\r' | grep -c 'starts from the open wave' | sed 's/^/cut note: /'
echo "cut from the wave tip: $(yn [ "$(git rev-parse feat/T-2)" = "$TIP" ])"
echo "key = wave tip: $(yn [ "$(cutkey T-2)" = "$TIP" ])"
( cd .polaris/wt/T-2 && printf 'y\nz\n' > f && git commit -qam "feat: T-2 the fix" )
echo "diff from the cut: $(git diff --name-only "$(cutkey T-2)...feat/T-2" | tr '\n' ' ')"
echo "diff from main: $(git diff --name-only "main...feat/T-2" | tr '\n' ' ')"
( cd .polaris/wt/T-2 && bash "$KIT" verify T-2 >/dev/null 2>&1 ); echo "verify rc=$?"
( cd .polaris/wt/T-2 && bash "$KIT" handoff T-2 >/dev/null 2>&1 ); echo "handoff rc=$?"
OUT="$(bash "$KIT" land T-2 2>&1)"; echo "land rc=$?"
printf '%s\n' "$OUT" | tr -d '\r' | grep -c 'squash conflict' | sed 's/^/squash conflicts: /'
echo "wave has the fix: $(yn [ "$(git show "$W:f" | tr -d '\r' | tr '\n' ' ')" = "y z " ])"
echo "wave keeps T-1's g: $(yn [ "$(git show "$W:g" | tr -d '\r')" = y ])"

echo '== c. T-3 owns h, no wave path =='
bash "$KIT" claim T-3 >/dev/null 2>&1; echo "claim rc=$?"
echo "cut from main: $(yn [ "$(git rev-parse feat/T-3)" = "$(git rev-parse main)" ])"
echo "T-3 cut key: $(cutkey T-3)"

echo '== d. T-4 owns g: cut from the wave, release drops the key =='
task T-4 g
bash "$KIT" claim T-4 >/dev/null 2>&1; echo "claim rc=$?"
echo "key recorded: $(yn [ "$(cutkey T-4)" != "(none)" ])"
bash "$KIT" release T-4 --to ready -m "fixture" >/dev/null 2>&1; echo "release rc=$?"
echo "branch gone: $(yn [ -z "$(git branch --list feat/T-4)" ])"
echo "T-4 cut key: $(cutkey T-4)"
