# lease-token — the integration lease follows its holder into child processes, and only the frame
# that took it lets it go (ops/contracts/safe-landing.md § 1, T-222). Before this the lease knew
# only the pid that took it, so land, seal and done each took and dropped it on their own and other
# lanes slipped in between. Pinned, through the CLI only:
#   1. a process carrying the lease's token re-enters a lease another pid holds (rc 0, no wait),
#      and its release leaves the lease standing with the token unchanged
#   2. a process without the token — or with a wrong one — still queues: rc 3 + the `queued: ` line
#   3. the taking frame: a child spawned while it holds the lease (a commit-msg hook running
#      `land`) re-enters, its release is a no-op, and the taker's own release removes the lease
# integration_wait_minutes: 0 in the fixture, so a queue answers at once instead of after minutes.
#
# HERMETIC (the seal-fallback pattern): ONE throwaway repo under mktemp -d, no remote, no session
# id, HOME and USERPROFILE faked together, the CLI run from INSIDE the fixture. Nothing printed
# carries a sha, a path, a date or a user.
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
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nintegration_wait_minutes: 0\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  printf '# SPRINT 1 — lease token  capacity: 5\n' > ops/SPRINT.md
  for id in T-1 T-2; do
    printf -- '---\nid: %s\ntitle: lane %s\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: feat/%s\nstatus: review\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\nverify: []\n---\n' "$id" "$id" "$id" "$id" > "ops/board/review/$id.md"
    git checkout -q -b "feat/$id" main
    echo "$id" > "src/$id.txt"; git add -A; git commit -qm "$id"
    git checkout -q main
  done
) >/dev/null 2>&1
cd "$R"
LK="$(cd "$(git rev-parse --git-common-dir)" && pwd)/polaris-locks/.int-lease"
lease() { if [ -d "$LK" ]; then printf 'lease: standing, token %s\n' "$(tr -d '\r\n' < "$LK/token" 2>/dev/null | sed 's/^1:tok$/unchanged/')"; else echo 'lease: gone'; fi; }

echo '== 1. the token re-enters a lease another pid holds; its release leaves it standing =='
mkdir -p "$LK"; date +%s > "$LK/epoch"; echo other@host > "$LK/who"; echo 1 > "$LK/pid"; echo 1:tok > "$LK/token"
OUT="$(POLARIS_INT_TOKEN=1:tok bash "$KIT" land T-1 2>&1)"; echo "land rc=$?"
echo "waited or queued: $(printf '%s\n' "$OUT" | grep -c 'integration lane busy\|^queued: ' || true)"
echo "T-1 landed: $(git log -1 --format=%s | grep -c '\[T-1\]$' || true)"
lease

echo '== 2. no token, or a wrong one, still queues =='
OUT="$(bash "$KIT" land T-2 2>&1)"; echo "land rc=$?"
printf '%s\n' "$OUT" | grep '^queued: ' | sed 's/ — other@host holds it ([0-9]*m)/ — <holder> holds it/'
OUT="$(POLARIS_INT_TOKEN=1:wrong bash "$KIT" land T-2 2>&1)"; echo "land rc=$?"
echo "queued lines: $(printf '%s\n' "$OUT" | grep -c '^queued: ' || true)"
echo "T-2 still in review: $([ -f ops/board/review/T-2.md ] && echo yes || echo no)"
lease

echo '== 3. the taking frame: a child re-enters, only the taker releases =='
POLARIS_INT_TOKEN=1:tok bash "$KIT" seal "$(date +%F)" >/dev/null 2>&1; echo "seal rc=$?"
rm -rf "$LK"
cat > .git/hooks/commit-msg <<HOOK
#!/usr/bin/env bash
unset GIT_INDEX_FILE
bash "$KIT" land T-1 > "$FIX/child.out" 2>&1; echo "child land rc=\$?" > "$FIX/child.rc"
if [ -d "$LK" ]; then echo 'lease after the child: standing' >> "$FIX/child.rc"; else echo 'lease after the child: gone' >> "$FIX/child.rc"; fi
exit 0
HOOK
chmod +x .git/hooks/commit-msg
OUT="$(bash "$KIT" land T-2 2>&1)"; echo "land rc=$?"
rm -f .git/hooks/commit-msg
cat "$FIX/child.rc" 2>/dev/null || echo 'child: never ran'
echo "child skipped without waiting: $(grep -c '^✅ already landed — skipped' "$FIX/child.out" 2>/dev/null || true) · waited: $(grep -c 'integration lane busy\|^queued: ' "$FIX/child.out" 2>/dev/null || true)"
echo "T-2 landed: $(git log -1 --format=%s | grep -c '\[T-2\]$' || true)"
lease
