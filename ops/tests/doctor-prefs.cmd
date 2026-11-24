# doctor-prefs — `doctor` names this computer's preferences file, and only when one is in play
# (ops/contracts/machine-prefs.md § 9, T-339). The line sits directly after the autonomy composition
# line, exactly once; with no machine file doctor says byte-for-byte what it said before.
#   1. the layer off (POLARIS_PREFS= — every golden's default) and a POLARIS_PREFS path with no file:
#      no provenance line, and doctor's whole output equals the layer-off run
#   2. a fixture machine file (POLARIS_PREFS=<path>): the § 9 line once, right after the autonomy line,
#      and every OTHER line identical to the layer-off run
#   3. POLARIS_PREFS unset: the default path, $POLARIS_HOME/preferences — under the fake HOME, and
#      under CLAUDE_CONFIG_DIR when that is set
# HERMETIC: a throwaway repo under mktemp -d and a fake HOME, so the owner's real
# ~/.claude/polaris/preferences is never read. The fixture file sets a machine key to its own default,
# so nothing else doctor composes can move between the runs.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID POLARIS_ROOT CLAUDE_CONFIG_DIR
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  echo x > a.txt; git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'voice: standard\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
printf '# machine fixture\nrun_max_tasks: 12\n' > "$FIX/prefs"
# doctor's output with the fixture's paths folded to names, so the golden never pins a temp dir
D() { ( cd "$R" && bash "$KIT" doctor 2>/dev/null ) | sed -e "s#$FIX#<FIX>#g"; }
L() { grep -c 'machine preferences:' "$1" | tr -d ' '; }
POLARIS_PREFS= D > /dev/null                      # warm-up: doctor self-heals the commit-msg hook once

echo '== 1. no machine file =='
POLARIS_PREFS= D > "$FIX/off"
echo "  layer off: provenance lines $(L "$FIX/off")"
grep '^   autonomy:' "$FIX/off"
POLARIS_PREFS="$FIX/none" D > "$FIX/none.out"
echo "  path with no file: provenance lines $(L "$FIX/none.out")"
cmp -s "$FIX/off" "$FIX/none.out" && echo "  doctor unchanged" || { echo "  doctor CHANGED"; diff "$FIX/off" "$FIX/none.out"; }

echo '== 2. a machine file =='
POLARIS_PREFS="$FIX/prefs" D > "$FIX/on"
echo "  provenance lines $(L "$FIX/on")"
grep -A1 '^   autonomy:' "$FIX/on"
grep -v 'machine preferences:' "$FIX/on" > "$FIX/on.rest"
cmp -s "$FIX/off" "$FIX/on.rest" && echo "  every other line unchanged" || { echo "  OTHER LINES CHANGED"; diff "$FIX/off" "$FIX/on.rest"; }

echo '== 3. POLARIS_PREFS unset: the default path =='
mkdir -p "$HOME/.claude/polaris"; cp "$FIX/prefs" "$HOME/.claude/polaris/preferences"
( unset POLARIS_PREFS; D ) | grep 'machine preferences:'
mkdir -p "$FIX/cfgdir/polaris"; cp "$FIX/prefs" "$FIX/cfgdir/polaris/preferences"
( unset POLARIS_PREFS; export CLAUDE_CONFIG_DIR="$FIX/cfgdir"; D ) | grep 'machine preferences:'
