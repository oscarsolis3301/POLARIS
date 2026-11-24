# heavy-slot — one heavy job at a time on this machine (ops/contracts/hour.md § 3, T-300). Every
# verify list runs inside a machine-wide heavy slot: an atomic folder under POLARIS_HEAVY_DIR, the
# integration lease's mechanism. It never refuses work. Pinned, through the CLI only (`run-verify`):
#   a. two verify runs started together never overlap, and the one that waited said so
#   b. a slot held by a live process → the waiting note, then the run once it frees
#   c. a slot whose process is gone → the stale-slot note at once, then the run
#   d. heavy_slots: 0 → no slot folder is ever made
#   e. a child carrying the holder's token re-enters without waiting and leaves the slot standing
#   f. POLARIS_HEAVY_WAIT=2 and a live holder → the running-without note, rc 0, holder untouched
#
# HERMETIC: one throwaway repo under mktemp -d, HOME and USERPROFILE faked together, the slot
# folder in that same scratch dir, POLARIS_HEAVY_TOKEN unset first (the builder's own verify holds
# the real slot; inheriting its token would make every case re-enter). Nothing printed carries a
# sha, a path, a time or a user.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN POLARIS_HEAVY_TOKEN POLARIS_HEAVY_WAIT
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
HP=""
trap '[ -n "$HP" ] && kill "$HP" 2>/dev/null; rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
export POLARIS_HEAVY_DIR="$FIX/heavy"
HD="$POLARIS_HEAVY_DIR"
R="$FIX/repo"
cat > "$FIX/job.sh" <<'JOB'
echo "start $1" >> "$2"
# case a only (the gate file exists): hold the slot until the other run has said it waits — an
# event, not a clock, so a slow start under a loaded machine cannot slip past the holder
d="$(dirname "$2")"; i=0
if [ -f "$d/gate" ]; then
  until cat "$d/a1" "$d/a2" 2>/dev/null | grep -q 'heavy: waiting' || [ "$i" -ge 90 ]; do sleep 1; i=$((i+1)); done
fi
sleep 1; echo "end $1" >> "$2"
JOB
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  for id in T-1 T-2; do
    printf -- '---\nid: %s\ntitle: lane %s\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: feat/%s\nstatus: review\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\nverify:\n  - bash "%s" %s "%s"\n---\n' "$id" "$id" "$id" "$id" "$FIX/job.sh" "$id" "$FIX/log" > "ops/board/review/$id.md"
  done
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
heavy() { grep -o 'heavy: .*' "$1" || true; }
hold() { # hold <who> <pid> — a fixture holder in slot-1
  mkdir -p "$HD/slot-1"; date +%s > "$HD/slot-1/epoch"; echo "$1" > "$HD/slot-1/who"; echo "$2" > "$HD/slot-1/pid"
  echo qa > "$HD/slot-1/why"; echo /elsewhere/proj > "$HD/slot-1/repo"; echo 1:tok > "$HD/slot-1/token"
}
slot() { if [ -d "$HD/slot-1" ]; then printf 'slot: standing, token %s\n' "$(tr -d '\r\n' < "$HD/slot-1/token" | sed 's/^1:tok$/unchanged/')"; else echo 'slot: free'; fi; }
ran() { echo "ran: $(awk '/^end /{n++} END{print n+0}' "$FIX/log" 2>/dev/null || echo 0)"; rm -f "$FIX/log"; }

echo '== a. two verify runs started together never overlap =='
touch "$FIX/gate"
bash "$KIT" run-verify T-1 > "$FIX/a1" 2>&1 & P1=$!
bash "$KIT" run-verify T-2 > "$FIX/a2" 2>&1 & P2=$!
wait "$P1"; echo "first rc=$?"; wait "$P2"; echo "second rc=$?"
rm -f "$FIX/gate"
awk '{split($0, w, " "); a[NR]=w[1]; t[NR]=w[2]} END{print "overlap: " ((NR==4 && a[1]=="start" && a[2]=="end" && t[1]==t[2] && a[3]=="start" && a[4]=="end" && t[3]==t[4]) ? "no" : "YES")}' "$FIX/log"
echo "the one that waited said so: $(cat "$FIX/a1" "$FIX/a2" | grep -c 'heavy: waiting for .* — one heavy job at a time on this machine' || true)"
ran; slot

echo '== b. a live holder: the waiting note, then the run once it frees =='
sleep 60 & HP=$!
hold other@host "$HP"
( i=0; until grep -q 'heavy: waiting' "$FIX/b" 2>/dev/null || [ "$i" -ge 90 ]; do sleep 1; i=$((i+1)); done; rm -rf "$HD/slot-1" ) &
bash "$KIT" run-verify T-1 > "$FIX/b" 2>&1; echo "rc=$?"
heavy "$FIX/b" | sed 's/, [0-9]*m, /, <m>m, /'
ran; slot

echo '== c. a holder whose process is gone: the stale-slot note at once =='
( exit 0 ) & DP=$!; wait "$DP"
hold gone@host "$DP"
bash "$KIT" run-verify T-1 > "$FIX/c" 2>&1; echo "rc=$?"
heavy "$FIX/c"
ran; slot

echo '== d. heavy_slots: 0 — no slot folder is ever made =='
printf 'base: main\nheavy_slots: 0\n' > ops/CONVENTIONS.md
POLARIS_HEAVY_DIR="$FIX/heavy-off" bash "$KIT" run-verify T-1 > "$FIX/d" 2>&1; echo "rc=$?"
heavy "$FIX/d"
echo "slot folder made: $([ -e "$FIX/heavy-off" ] && echo yes || echo no)"
printf 'base: main\n' > ops/CONVENTIONS.md
ran

echo '== e. a child with the holder token re-enters without waiting =='
hold other@host "$HP"
POLARIS_HEAVY_TOKEN=1:tok bash "$KIT" run-verify T-1 > "$FIX/e" 2>&1; echo "rc=$?"
echo "heavy notes: $(heavy "$FIX/e" | grep -c . || true)"
ran; slot

echo '== f. POLARIS_HEAVY_WAIT=2 and a live holder: run without the slot =='
POLARIS_HEAVY_WAIT=2 bash "$KIT" run-verify T-1 > "$FIX/f" 2>&1; echo "rc=$?"
heavy "$FIX/f" | sed 's/, [0-9]*m, /, <m>m, /'
ran; slot

echo '== g. an ARMED run and a live holder: queued once, runs at once without the slot (walk-away § 2.4) =='
# No POLARIS_HEAVY_WAIT here: unarmed, this case would wait the full 30 minutes. The armed file is
# written by hand (T-319's presence-guard writes it for real); its epoch is now, within reentry_hours.
kill "$HP" 2>/dev/null; sleep 120 & HP=$!
hold other@host "$HP"
mkdir -p "$R/.polaris/run"; printf '%s\nfix\nreentries 0\n' "$(date +%s)" > "$R/.polaris/run/hs.armed"
S=$SECONDS
bash "$KIT" run-verify T-1 > "$FIX/g" 2>&1; echo "rc=$?"
grep -o 'queued: heavy slot busy.*' "$FIX/g" | sed 's/, [0-9]*m, /, <m>m, /'
echo "waiting notes: $(heavy "$FIX/g" | grep -c . || true) · waited past a minute: $([ $((SECONDS - S)) -ge 60 ] && echo yes || echo no)"
rm -f "$R/.polaris/run/hs.armed"
ran; slot
