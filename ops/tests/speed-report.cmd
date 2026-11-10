# speed-report — T-215 (ops/contracts/one-yes.md § 6): `polaris speed` classifies the last commits with
# the same function `depth --commit` uses, prints the counts line + last full run time, then one advice
# line per slowing setting. Read-only (repo byte-identical after). cmd_update's tail is checked statically
# (it cannot run hermetically): the speed report there must be guarded by `|| true`.
# Landing time (ops/contracts/minutes.md § 5.3): a fixture EVENTS log with known times gives two
# medians — build (last claim → last handoff) and built → done (that handoff → done) — printed right
# after the counts line; tasks missing a claim, a handoff or a done do not count; only the last 20 by
# done time do, whatever order the log is in.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it.
KIT="$(pwd)/kit/ops/polaris"
# The content cases below test WHAT the report says, not how fast it says it; the budget has its own
# cases (budget-zero, slow-within-budget) that set POLARIS_SPEED_BUDGET themselves. A generous default
# keeps a slow machine (one git call ~20s on Windows under load) from turning content into "stopped early".
export POLARIS_SPEED_BUDGET=600
ADMIN="$(pwd)/kit/ops/lib/admin.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p web/src lib docs
  echo 'v1' > web/src/App.tsx; echo 'v1' > web/src/app.css; echo 'v1' > lib/core.dat; echo 'v1' > docs/readme.md
  printf '.polaris/\n' > .gitignore
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\nlint: echo LINT\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
  echo 'v2' > lib/core.dat;       git commit -qam 'feat: core v2'
  echo 'v2' > docs/readme.md;     git commit -qam 'docs: readme v2'
  echo 'v2' > web/src/app.css;    git commit -qam 'style: css v2'
) >/dev/null 2>&1
cd "$R"
snap() { { git status --porcelain; git rev-parse HEAD; find . -path ./.git -prune -o -type f -print | sort | xargs cksum 2>/dev/null; } | cksum; }
mkdir -p .polaris
BEFORE="$(snap)"
echo "plain:"; bash "$KIT" speed 2>&1; echo "  rc=$?"
[ "$BEFORE" = "$(snap)" ] && echo "read-only: repo byte-identical after" || echo "read-only: REPO CHANGED"
EV=ops/board/EVENTS.ndjson
[ -f "$EV" ] && cp "$EV" "$FIX/events.bak"
# A: 10 min build, 20 min wait · B: claimed twice, the LAST claim counts: 30 / 5 · C: handed off twice,
# the LAST handoff before done counts: 2.5 → 3 / 0.5 → 1 · D: never done · E: no claim. Not in time order.
{
  printf '{"ts":7400,"ev":"done","id":"T-B","who":"t","note":"","pts":1}\n'
  printf '{"ts":1000,"ev":"claim","id":"T-A","who":"t","note":"","pts":1}\n'
  printf '{"ts":1600,"ev":"handoff","id":"T-A","who":"t","note":"","pts":1}\n'
  printf '{"ts":2800,"ev":"done","id":"T-A","who":"t","note":"","pts":1}\n'
  printf '{"ts":5000,"ev":"claim","id":"T-B","who":"t","note":"","pts":1}\n'
  printf '{"ts":5300,"ev":"claim","id":"T-B","who":"t","note":"","pts":1}\n'
  printf '{"ts":7100,"ev":"handoff","id":"T-B","who":"t","note":"","pts":1}\n'
  printf '{"ts":9000,"ev":"claim","id":"T-C","who":"t","note":"","pts":1}\n'
  printf '{"ts":9090,"ev":"handoff","id":"T-C","who":"t","note":"","pts":1}\n'
  printf '{"ts":9150,"ev":"handoff","id":"T-C","who":"t","note":"","pts":1}\n'
  printf '{"ts":9180,"ev":"done","id":"T-C","who":"t","note":"","pts":1}\n'
  printf '{"ts":9500,"ev":"claim","id":"T-D","who":"t","note":"","pts":1}\n'
  printf '{"ts":9600,"ev":"handoff","id":"T-D","who":"t","note":"","pts":1}\n'
  printf '{"ts":9700,"ev":"handoff","id":"T-E","who":"t","note":"","pts":1}\n'
  printf '{"ts":9800,"ev":"done","id":"T-E","who":"t","note":"","pts":1}\n'
} > "$EV"
echo "landing:"; bash "$KIT" speed 2>&1 | sed 's/^Of your last [0-9]* changes: .*/COUNTS/'
# 21 finished tasks: the 20 newest are ten 1-minute builds and ten 9-minute ones (median 1); the oldest,
# written LAST, is a 9-minute build that would tip the median to 9 if it were counted.
awk 'BEGIN { for (i = 2; i <= 21; i++) { c = i * 10000; b = (i <= 11 ? 60 : 540)
               printf "{\"ts\":%d,\"ev\":\"claim\",\"id\":\"T-%d\"}\n{\"ts\":%d,\"ev\":\"handoff\",\"id\":\"T-%d\"}\n{\"ts\":%d,\"ev\":\"done\",\"id\":\"T-%d\"}\n", c, i, c + b, i, c + b + 120, i }
             printf "{\"ts\":100,\"ev\":\"claim\",\"id\":\"T-1\"}\n{\"ts\":640,\"ev\":\"handoff\",\"id\":\"T-1\"}\n{\"ts\":760,\"ev\":\"done\",\"id\":\"T-1\"}\n" }' > "$EV"
echo "last-20:"; bash "$KIT" speed 2>&1 | grep -e '^build:' -e '^built'
printf '{"ts":100,"ev":"claim","id":"T-1"}\n{"ts":200,"ev":"handoff","id":"T-1"}\n' > "$EV"
echo "none-finished-lines: $(bash "$KIT" speed 2>&1 | grep -c -e '^build:' -e '^built')"
if [ -f "$FIX/events.bak" ]; then cp "$FIX/events.bak" "$EV"; else rm -f "$EV"; fi
echo "45 1" > .polaris/last-suite-seconds
echo "last-run-45s:"; bash "$KIT" speed 2>&1 | grep -c 'Your last full run took 45s\.'
echo "300 1" > .polaris/last-suite-seconds
printf 'drain: queue\nautonomy: standard\nplan_gate: confirm\nintegration: paranoid\n' >> ops/CONVENTIONS.md
echo "slow-settings:"; bash "$KIT" speed 2>&1 | sed 's/^Of your last [0-9]* changes: [0-9]* would skip the test run, [0-9]* run only related tests, [0-9]* run everything\./COUNTS/'
printf 'drain: queue\n' > /dev/null
echo "300 1" > .polaris/last-suite-seconds
sed -i 's/^integration: paranoid/integration: paranoid/' ops/CONVENTIONS.md
echo "90 1" > .polaris/last-suite-seconds
echo "paranoid-fast-suite-advice-lines: $(bash "$KIT" speed 2>&1 | grep -c 'integration: batch')"
grep -c '^drain: queue$' ops/CONVENTIONS.md | sed 's/^/config-untouched-drain: /'
cd "$FIX"; mkdir empty; cd empty; git init -q . 2>/dev/null
echo "no-history:"; bash "$KIT" speed 2>&1 | sed -n 1p
cd "$R"
echo "budget-zero:"
POLARIS_SPEED_BUDGET=0 bash "$KIT" speed 2>&1 | grep -c 'stopped early at the time limit'
echo "budget-zero-rc: $(POLARIS_SPEED_BUDGET=0 bash "$KIT" speed >/dev/null 2>&1; echo $?)"
# fake slow decision: 30 commits that each need cmd_depth, an env-injected sleep per expensive call
SLOW="$FIX/slow"
( set -e
  git init -q -b main "$SLOW" 2>/dev/null || { git init -q "$SLOW"; git -C "$SLOW" symbolic-ref HEAD refs/heads/main; }
  cd "$SLOW"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  printf '.polaris/\n' > .gitignore; echo v0 > lib.dat; git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
  for i in $(seq 1 30); do echo "v$i" > lib.dat; git commit -qam "c$i"; done
) >/dev/null 2>&1
cd "$SLOW"; mkdir -p .polaris
# measured ABOVE the command's own startup (a zero-budget run): a slow machine pays ~20s just to
# start, and that is not what this case proves. Unbounded, 30 commits x 2s add >=60s of sleep alone,
# so a 30s ceiling still separates "the budget stopped it" from "it ran to the end" on any machine.
T0=$SECONDS
POLARIS_SPEED_BUDGET=0 POLARIS_SPEED_TEST_SLEEP=2 bash "$KIT" speed >/dev/null 2>&1
BASE=$((SECONDS - T0))
T0=$SECONDS
OUT="$(POLARIS_SPEED_BUDGET=3 POLARIS_SPEED_TEST_SLEEP=2 bash "$KIT" speed 2>&1)"
EL=$((SECONDS - T0 - BASE))
echo "slow-within-budget+2s: $([ "$EL" -le 30 ] && echo yes || echo "no ${EL}s")"
printf '%s\n' "$OUT" | sed 's/^Of your last [0-9]* changes/Of your last N changes/; s/[0-9][0-9]* not checked/M not checked/; s/[0-9][0-9]* run everything/C run everything/'
cd "$R"
echo "update-guarded:"
grep -c 'cmd_speed; } || true' "$ADMIN"
grep -c 'cmd_speed' "$ADMIN" | sed 's/^/speed-fn-and-call-refs>=2: /' | awk '{print ($2>=2?"yes":"no")}'
bash -n "$ADMIN" && echo "admin.sh parses"
