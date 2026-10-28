# speed-report — T-215 (ops/contracts/one-yes.md § 6): `polaris speed` classifies the last commits with
# the same function `depth --commit` uses, prints the counts line + last full run time, then one advice
# line per slowing setting. Read-only (repo byte-identical after). cmd_update's tail is checked statically
# (it cannot run hermetically): the speed report there must be guarded by `|| true`.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it.
KIT="$(pwd)/kit/ops/polaris"
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
T0=$SECONDS
OUT="$(POLARIS_SPEED_BUDGET=3 POLARIS_SPEED_TEST_SLEEP=2 bash "$KIT" speed 2>&1)"
EL=$((SECONDS - T0))
echo "slow-within-budget+2s: $([ "$EL" -le 8 ] && echo yes || echo "no ${EL}s")"
printf '%s\n' "$OUT" | sed 's/^Of your last [0-9]* changes/Of your last N changes/; s/[0-9][0-9]* not checked/M not checked/; s/[0-9][0-9]* run everything/C run everything/'
cd "$R"
echo "update-guarded:"
grep -c 'cmd_speed; } || true' "$ADMIN"
grep -c 'cmd_speed' "$ADMIN" | sed 's/^/speed-fn-and-call-refs>=2: /' | awk '{print ($2>=2?"yes":"no")}'
bash -n "$ADMIN" && echo "admin.sh parses"
