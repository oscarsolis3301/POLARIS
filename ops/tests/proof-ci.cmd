# proof-ci — one command proves a commit (ops/contracts/minutes.md § 2.5, T-272).
#
# tools/proof.sh is run for real against a throwaway repo with a bare `origin`, so the push of the
# proof/<sha12> branch and the deletion of an older proof/* branch are real git operations. `gh` is a
# stub first on PATH that reads its answers from files (one line per call, the last line repeats), and
# PROOF_GOLDENS is a stub runner, so this golden never recurses into the real goldens and never talks to
# GitHub. Polls are 0 s. The commit id prints as <s7> / <sha12>, the stub's run ids are fixed.
TOOL="$(pwd)/tools/proof.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export STUB="$FIX/stub" PROOF_POLL=0 PROOF_FIND_POLL=0
mkdir -p "$FIX/bin" "$STUB"
cat > "$FIX/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$STUB/calls"
pop() { f="$STUB/$1"; [ -f "$f" ] || return 0; head -n 1 "$f"
  if [ "$(wc -l < "$f" | tr -d ' ')" -gt 1 ]; then tail -n +2 "$f" > "$f.n"; mv "$f.n" "$f"; fi; }
case "$1 $2" in
  "auth status") exit "$(cat "$STUB/auth_rc" 2>/dev/null || echo 0)";;
  "run list") pop list;;
  "workflow run") exit 0;;
  "run view")
    case "$*" in
      *--log-failed*) cat "$STUB/log";;
      *select*) pop "job-$(printf '%s' "$7" | sed -n 's/.*name=="\([^"]*\)".*/\1/p')";;
      *) cat "$STUB/report";;
    esac;;
esac
GH
chmod +x "$FIX/bin/gh"
# the goldens stub: one golden per call, red when its name is listed in $STUB/red
printf '%s\n' 'grep -qx "$1" "$STUB/red" 2>/dev/null && { echo "golden $1 output: it differs"; exit 1; }; exit 0' > "$FIX/golden.sh"
export PATH="$FIX/bin:$PATH" PROOF_GOLDENS="bash $FIX/golden.sh"
R="$FIX/repo"
( set -e
  git init -q --bare "$FIX/origin.git"
  git init -q "$R"; cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p ops/tests; echo 'echo a' > ops/tests/a.cmd; echo 'echo b' > ops/tests/b.cmd
  git add -A; git commit -qm init
  git remote add origin "$FIX/origin.git"
  git push -q origin HEAD:refs/heads/main
  git push -q origin HEAD:refs/heads/proof/000000000000
) >/dev/null 2>&1
cd "$R"
SHA="$(git rev-parse HEAD)"
M() { sed "s#$SHA#<sha>#g; s#${SHA:0:12}#<sha12>#g; s#${SHA:0:7}#<s7>#g"; }
P() { ( bash "$TOOL" "$@" 2>&1; echo "rc=$?" ) | M; }
fresh() { rm -rf "$STUB"; mkdir -p "$STUB"; }
heads() { git ls-remote --heads origin 'proof/*' | sed 's#^[0-9a-f]*[[:space:]]*refs/heads/##' | M | tr '\n' ' '; echo; }

echo '== 1. a run for this commit already exists: reused, goldens green, linux green after one poll =='
fresh; echo 111 > "$STUB/list"; printf 'in_progress \ncompleted success\n' > "$STUB/job-ubuntu-latest"
P
echo "ci-proof: $(M < .polaris/ci-proof)"
echo "dispatches: $(grep -c '^workflow run' "$STUB/calls")"
echo "polls of run 111: $(grep -c "^run view 111 " "$STUB/calls")"

echo '== 2. no run yet: older proof/* deleted, proof/<sha12> pushed, CI dispatched, the id found on a later poll =='
fresh; printf '\n\n222\n' > "$STUB/list"; echo 'completed success' > "$STUB/job-ubuntu-latest"
echo "proof branches before: $(heads)"
P
echo "proof branches after: $(heads)"
grep '^workflow run' "$STUB/calls" | M
echo "ci-proof: $(M < .polaris/ci-proof)"

echo '== 3. the linux job is red: rc 1, the last 40 lines of the failed log =='
fresh; echo 333 > "$STUB/list"; echo 'completed failure' > "$STUB/job-ubuntu-latest"
i=1; while [ $i -le 50 ]; do echo "log $i"; i=$((i + 1)); done > "$STUB/log"
out="$(P)"
printf '%s\n' "$out" | grep -v '^log '
echo "log lines printed: $(printf '%s\n' "$out" | grep -c '^log ') — from $(printf '%s\n' "$out" | grep '^log ' | head -n 1) to $(printf '%s\n' "$out" | grep '^log ' | tail -n 1)"

echo '== 4. a golden is red: rc 1, its name and its output =='
fresh; echo 444 > "$STUB/list"; echo 'completed success' > "$STUB/job-ubuntu-latest"; echo b > "$STUB/red"
P

echo '== 5. --await macos-latest on the recorded run: green, then red =='
fresh; printf 'queued \ncompleted success\n' > "$STUB/job-macos-latest"
P --await macos-latest
grep -c '^run view 444 ' "$STUB/calls" | sed 's/^/polls of run 444: /'
fresh; echo 'completed failure' > "$STUB/job-macos-latest"
P --await macos-latest

echo '== 6. --report: one line per job of the recorded run =='
fresh; printf '%s\n' 'ubuntu-latest: completed success' 'macos-latest: completed failure' 'windows-latest: in_progress ' 'one version, everywhere: completed failure' > "$STUB/report"
P --report

echo '== 7. no gh: the self-test runs here instead, and nothing is recorded =='
fresh; rm -f .polaris/ci-proof
PROOF_GH="$FIX/bin/no-such-gh" PROOF_SELFTEST='echo self-test ran' P
[ -f .polaris/ci-proof ] && echo 'ci-proof written: yes' || echo 'ci-proof written: no'
echo '-- gh not signed in, and the self-test red --'
fresh; echo 1 > "$STUB/auth_rc"
PROOF_SELFTEST='echo self-test broke; exit 1' P
[ -f .polaris/ci-proof ] && echo 'ci-proof written: yes' || echo 'ci-proof written: no'

echo '== 8. --await with no recorded run =='
P --await macos-latest
