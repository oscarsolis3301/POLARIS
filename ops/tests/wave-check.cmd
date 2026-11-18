# wave-check — a wave's reds show up in that wave (ops/contracts/smooth.md § 3, v1.1). Before a wave
# merges, `seal` runs the tests covering what it changed: the SURFACES rows at every seal, the whole
# `test:` for paths no row covers. A red keeps integrate/<date> open, names the cards and leaves the
# primary on main; a fix card on the same wave seals it.
# The cards are plain [<ID>] commits on the wave branch — the seal reads the wave, not the board, so
# no claim/handoff/land round trips are needed to prove it. The fixture's two test scripts write one
# line per run to $WCLOG, so "how many times did it run" is a line count, never a time.
# HERMETIC: one throwaway repo under mktemp -d, no remote, no session id, HOME, USERPROFILE and
# POLARIS_AWAKE_HOME faked together (the heavy slot lives under the fake HOME). No sha, date or path.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN POLARIS_SEAL_NOCHECK POLARIS_HEAVY_TOKEN POLARIS_HEAVY_DIR
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
export WCLOG="$FIX/runs"; : > "$WCLOG"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src t
  echo good > src/m.sh; echo good > src/u.sh
  printf 'echo rows >> "$WCLOG"\nif grep -q bad src/m.sh; then echo "the m part is bad"; exit 1; fi\n' > t/rows.sh
  printf 'echo whole >> "$WCLOG"\nif grep -q bad src/m.sh src/u.sh; then echo "something is bad"; exit 1; fi\n' > t/whole.sh
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf 'src/m.sh\ttests/m.*\t-\tthe m part\n' > ops/SURFACES.tsv
  git add -A; git commit -qm board
  printf '# SPRINT 1 — wave check  capacity: 20\n' > ops/SPRINT.md
) >/dev/null 2>&1
cd "$R"
D="$(date +%F)"
mask() { tr -d '\r' | sed -e "s,integrate/$D,integrate/<date>,g" -e 's/at [0-9a-f]\{7\}$/at <sha>/'; }
runs() { grep -c "^$1\$" "$WCLOG" || true; }
open() { if git merge-base --is-ancestor "integrate/$D" main 2>/dev/null; then echo merged; else echo open; fi; }
wave() { # wave <ID> <file> <text> — one card's commit on today's wave, cut fresh from main when sealed
  if git rev-parse -q --verify "refs/heads/integrate/$D" >/dev/null && [ "$(open)" = open ]; then
    git checkout -q "integrate/$D"
  else
    git checkout -q -B "integrate/$D" main
  fi
  echo "$3" > "$2"; git commit -qam "feat: $1 changes $2 [$1]"
  git checkout -q main
}
conv() { printf "base: main\nlanding: integrator\n$1" > ops/CONVENTIONS.md; git commit -qam "conventions" >/dev/null; }
seal() { OUT="$(bash "$KIT" seal "$@" 2>&1)"; echo "seal rc=$?"; OUT="$(printf '%s\n' "$OUT" | mask)"; }
show() { printf '%s\n' "$OUT" | grep -E 'wave check|sealed —|^     |^   (cards|fix):' | sed 's/ — integrate\/<date> merged.*//'; }
stamp() { if [ -f .polaris/wave-check ]; then
    awk -F'\t' -v h="$(git rev-parse 'main^2' 2>/dev/null)" '{ p=$3; gsub(/:[0-9]+/, "", p)
      printf "stamp: %s fields · tip %s · last whole green %s · pending %s\n", NF, ($1==h ? "is the wave that merged" : "OTHER"), ($2==0 ? "none" : "recorded"), p }' .polaris/wave-check
  else echo "stamp: none"; fi; }
events() { grep -c "\"ev\":\"$1\"" ops/board/EVENTS.ndjson || true; }

echo '== a. test: unset — the seal says nothing new'
wave T-1 src/m.sh one
seal; show
echo "wave check lines: $(printf '%s\n' "$OUT" | grep -c 'wave check' || true)"
stamp

echo '== b. a mapped test goes red — the wave stays open and names its card'
conv 'test: bash t/whole.sh\ntest_select: bash t/rows.sh {tests}\n'
wave T-2 src/m.sh bad
seal; show
echo "on: $(git rev-parse --abbrev-ref HEAD) · wave: $(open) · rows ran: $(runs rows) · whole ran: $(runs whole)"
echo "wave-red events: $(events wave-red) · board: $(git log -1 --format=%s polaris/board | mask)"
stamp

echo '== c. the fix card lands on the same wave — green, sealed, stamped'
wave T-3 src/m.sh good
seal; show
echo "wave: $(open) · rows ran: $(runs rows) · whole ran: $(runs whole)"
stamp

echo '== d. a re-seal of the same tip skips the check'
wave T-4 src/m.sh fine
git checkout -q main; echo other > src/m.sh; git commit -qam 'chore: main moves under the wave'
seal; printf '%s\n' "$OUT" | grep -E '^⛔ merge conflict' | sed 's/ — .*//'
git reset -q --hard HEAD~1
seal; show
echo "rows ran: $(runs rows)"

echo '== e. an unmapped path runs test: verbatim, once'
wave T-5 src/u.sh newer
seal; show
echo "rows ran: $(runs rows) · whole ran: $(runs whole)"
stamp

echo '== f. inside the window — the rows still run, the whole test: waits'
wave T-6 src/m.sh six; wave T-6 src/u.sh six
seal; show | sed -e 's/last green [0-9]* min ago/last green <m> min ago/' -e 's/after [0-9]* more min/after <k> more min/'
echo "the two numbers add up to the window: $(printf '%s\n' "$OUT" | sed -n 's/.*last green \([0-9]*\) min ago; it runs at the first seal after \([0-9]*\) more min.*/\1 \2/p' | awk '{ print ($1 + $2 == 60) ? "yes" : "no" }')"
echo "rows ran: $(runs rows) · whole ran: $(runs whole)"
stamp

echo '== g. past the window (the stamp moved back an hour) — the whole test: runs, a red names every card since its last green'
awk -F'\t' 'BEGIN { OFS = "\t" } { $2 = $2 - 3660; print }' .polaris/wave-check > .polaris/wave-check.new && mv .polaris/wave-check.new .polaris/wave-check
wave T-7 src/u.sh bad
seal; show
echo "on: $(git rev-parse --abbrev-ref HEAD) · wave: $(open) · whole ran: $(runs whole)"
wave T-8 src/u.sh good
seal; show
echo "whole ran: $(runs whole)"
stamp

echo '== h. wave_check: 0 — the whole test: at every seal'
conv 'test: bash t/whole.sh\ntest_select: bash t/rows.sh {tests}\nwave_check: 0\n'
wave T-9 src/u.sh nine
seal; show
echo "whole ran: $(runs whole)"

echo '== i. wave_check: off — never at a seal, the rows still do'
conv 'test: bash t/whole.sh\ntest_select: bash t/rows.sh {tests}\nwave_check: off\n'
wave T-10 src/u.sh ten; wave T-10 src/m.sh ten
seal; show
echo "rows ran: $(runs rows) · whole ran: $(runs whole)"

echo '== j. seal --no-check — refused on a feat branch and without a why; with both it records the why'
git worktree add -q -b feat/T-99 "$FIX/wt" main >/dev/null 2>&1
( cd "$FIX/wt" && bash "$KIT" seal --no-check -m "why" ) 2>&1 | tr -d '\r'; echo "rc=${PIPESTATUS[0]}"
bash "$KIT" seal --no-check 2>&1 | tr -d '\r' | sed 's/ (usage.*//'; echo "rc=${PIPESTATUS[0]}"
wave T-11 src/m.sh bad
seal --no-check -m "the runner is broken"; show
echo "rows ran: $(runs rows) · skipped events: $(events wave-check-skipped) · its why: $(grep '"ev":"wave-check-skipped"' ops/board/EVENTS.ndjson | sed 's/.*"note":"\([^"]*\)".*/\1/')"
