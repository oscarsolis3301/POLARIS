# bg-budget — every detached job has a budget and a watchdog (ops/contracts/walk-away.md § 2.1). The
# owner came back after three hours to a job that hung and a builder polling `bg wait` forever; the
# budget is what ends that. Pinned, through the CLI only:
#   a. the budget a job is given: --budget verbatim · 3 × the longest green .prev/.archive run ·
#      the name's class · 3 × last-suite-seconds · the 300 s floor · + the heavy wait for a kit command
#   b. a --budget 2 job whose shell spawns sleeping grandchildren: killed, retried ONCE, every process
#      of both attempts gone (checked by pid AND command marker), overrun + rc 124, exit 4
#   c. a command that itself exits 124 is an ordinary red, never a timeout
#
# HERMETIC: one throwaway repo under mktemp -d, HOME and USERPROFILE faked, the awake home and the
# heavy folder inside the fixture. No sha, no time, no pid, no absolute path is printed.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN POLARIS_HEAVY_TOKEN POLARIS_HEAVY_WAIT
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'cd /; rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home" POLARIS_HEAVY_DIR="$FIX/heavy"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
BG="$R/.polaris/bg"
# budget <label> <name> <bg run args…> — start a job, print the budget it was given, collect it
budget() {
  l="$1"; shift
  bash "$KIT" bg run "$@" >/dev/null 2>&1
  printf '%s: %s\n' "$l" "$(tr -d '\r\n' < "$BG/$1/budget")"
  bash "$KIT" bg wait "$1" --max 30 >/dev/null 2>&1 || true
}
past() { # past <dir> <rc> <seconds> — a finished run of that length, written by hand
  mkdir -p "$1"; printf '%s\n' "$2" > "$1/rc"; printf '1000\n' > "$1/start"; printf '%s\n' "$(( 1000 + $3 ))" > "$1/end"
  printf 'true\n' > "$1/cmd"; : > "$1/log"
}

echo '== a. the budget =='
budget 'given' given --budget 7 -- true
past "$BG/fromprev.prev" 0 200
mkdir -p "$BG/.archive"; past "$BG/.archive/fromprev-1700000000" 0 250; past "$BG/.archive/fromprev-1700000001" 1 9000
past "$BG/.archive/fromprev-other-1700000002" 0 9000
budget 'from the longest green run (3 x 250)' fromprev -- true
past "$BG/short.prev" 0 20
budget 'a short green run gets the floor' short -- true
budget 'class lint' lint -- true
budget 'no history, no measured suite' qa -- true
printf '400 1700000000\n' > "$R/.polaris/last-suite-seconds"
budget 'class test, 3 x last-suite-seconds' test -- true
budget 'any other name, 3 x last-suite-seconds' other -- true
printf '50 1700000000\n' > "$R/.polaris/last-suite-seconds"
budget 'a short measured suite gets the floor' proof -- true
POLARIS_HEAVY_WAIT=100 budget 'a kit command adds the heavy wait' kitcmd -- true ops/polaris version
budget 'given is verbatim, kit command or not' kitgiven --budget 3 -- true ops/polaris version

echo '== b. a hang: killed, retried once, nothing left behind =='
# The shell records every grandchild it starts, both attempts; afterwards none of those pids may
# still be a sleep. Pid AND marker: Windows reuses pids, so a pid alone could name a stranger.
printf 'sleep 300 & echo $! >> "%s/kids"\nsleep 301 & echo $! >> "%s/kids"\nwait\n' "$FIX" "$FIX" > "$FIX/hang.sh"
bash "$KIT" bg run hang --budget 2 -- sh "$FIX/hang.sh" >/dev/null 2>&1
out="$(bash "$KIT" bg wait hang --max 60 2>&1)"; echo "wait rc=$?"
printf '%s\n' "$out" | sed -e "s#$FIX#<fix>#g" -e 's#[^ ]*/\.polaris/bg/#<reg>/#g'
echo "grandchildren started: $(grep -c . "$FIX/kids")"
left=0; for k in $(cat "$FIX/kids"); do ps -ef 2>/dev/null | awk -v p="$k" '$2 == p && /sleep/ { f = 1 } END { exit !f }' && left=$((left + 1)); done
echo "grandchildren alive: $left"
grep '^bg: budget' "$BG/hang/log"
printf 'attempt: %s\n' "$(tr -d '\r\n' < "$BG/hang/attempt")"
printf 'overrun: %s\n' "$(tr '\t' ' ' < "$BG/hang/overrun" | tr -d '\r\n')"
printf 'rc: %s\n' "$(tr -d '\r\n' < "$BG/hang/rc")"
bash "$KIT" bg status hang >/dev/null 2>&1; echo "status rc=$?"

echo '== c. a command that exits 124 by itself is an ordinary red =='
bash "$KIT" bg run e124 -- sh -c 'exit 124' >/dev/null 2>&1
bash "$KIT" bg wait e124 --max 30 2>&1 | sed -e 's/ in [0-9][0-9]*[smh]/ in <dur>/' -e 's#[^ ]*/\.polaris/bg/#<reg>/#g' | tail -1
echo "overrun file: $([ -f "$BG/e124/overrun" ] && echo yes || echo no)"

echo '== d. reap: a live watchdog owns its job; past the budget with the watchdog gone, reap kills it =='
# The job's start is backdated by hand (no clock wait): 100 s old against a budget of 90 — past it,
# but inside the 15 s a live watchdog is given, so the first reap leaves it alone.
printf 'sleep 300 & echo $! >> "%s/kids2"\nwait\n' "$FIX" > "$FIX/rp.sh"
bash "$KIT" bg run rp -- sh "$FIX/rp.sh" >/dev/null 2>&1
i=0; until [ -s "$FIX/kids2" ] || [ "$i" -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
printf '90\n' > "$BG/rp/budget"; printf '%s\n' "$(( $(date +%s) - 100 ))" > "$BG/rp/start"
printf 'reap with a live watchdog: %s\n' "$(bash "$KIT" bg reap 2>&1 | grep -c . || true)"
W="$(tr -d '\r\n' < "$BG/rp/wpid")"; kill "$W" 2>/dev/null
i=0; while kill -0 "$W" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
( cd "$R/src" && printf 'reap from another folder: %s\n' "$(bash "$KIT" bg reap 2>&1 | grep -c . || true)" )
bash "$KIT" bg reap 2>&1
bash "$KIT" bg wait rp --max 30 >/dev/null 2>&1; echo "wait rc=$?"
printf 'overrun: %s\n' "$(tr '\t' ' ' < "$BG/rp/overrun" | tr -d '\r\n')"
left=0; for k in $(cat "$FIX/kids2"); do ps -ef 2>/dev/null | awk -v p="$k" '$2 == p && /sleep/ { f = 1 } END { exit !f }' && left=$((left + 1)); done
echo "grandchildren alive: $left"
