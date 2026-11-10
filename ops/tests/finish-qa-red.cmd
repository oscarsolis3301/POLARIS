# finish-qa-red — a red finish names the qa check that failed and shows its last 20 lines
# (ops/contracts/safe-landing.md v1.1 § F). It used to say only "qa is red" and show the last six
# lines of qa's whole report, which were doctor's and drift's, never the test that failed.
# The fixture's test: prints `line 1`..`line 30` and fails; finish must exit non-zero, name `test`
# on the pending line, show qa's red header and lines 11-30 of the test's output, and nothing before
# line 11. HERMETIC: a throwaway repo under mktemp -d, no session id, HOME, USERPROFILE and
# POLARIS_AWAKE_HOME faked together, the CLI run from INSIDE it. No sha, date or path.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  printf 'i=1; while [ $i -le 30 ]; do echo "line $i"; i=$((i+1)); done; exit 1\n' > t.sh
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\ntest: bash t.sh\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
OUT="$(bash "$KIT" finish 2>&1)"; echo "finish rc=$?"
printf '%s\n' "$OUT" | tr -d '\r' | grep '^⛔ pending: qa is red'
printf '%s\n' "$OUT" | tr -d '\r' | grep -E '^ +(⛔ test — RED: |line [0-9]+$)'
echo "line 10 shown: $(printf '%s\n' "$OUT" | tr -d '\r' | grep -c 'line 10$' || true)"
