# wrap-own-folder — `wrap` typed from the task's own folder ends green (ops/contracts/minutes.md § 14).
# HERMETIC: a throwaway repo under mktemp -d with the kit INSTALLED in it, so every command runs the
# fixture's own ops/polaris and never a path outside it (flow-solo runs the kit by an absolute path
# from outside, which is why it never saw this); default landing (no `landing:` line). HOME,
# USERPROFILE and POLARIS_AWAKE_HOME are faked together. Pinned: `begin` a 1-point draft → one commit
# in the worktree → `wrap` from inside that worktree ends rc 0 with finish complete, the task done, its
# file on main, finish's "where this command ran from" caveat once and no ⛔ line; then a `finish`
# from the project folder ends rc 0 and clears the folder and its branch. No sha, path or time printed.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT_DIR/ops/install.sh" "$R"
  bash ops/polaris init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  printf '# SPRINT 1 — x\n' > ops/SPRINT.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  mkdir -p .polaris/brain
  git add -A; git commit -qm board
  D=.polaris/drafts; mkdir -p "$D"
  printf -- '---\ntitle: a small change\nplan: p\npoints: 1\nrisk: normal\nfiles_owned:\n  - src/a.txt\ndepends_on: []\ncontract: ops/contracts/fix.md\nverify: []\n---\n## Why\nfixture\n' > "$D/a.md"
) >/dev/null 2>&1
cd "$R"
echo "installed: $([ -f ops/polaris ] && echo yes || echo no)"
bash ops/polaris begin .polaris/drafts/a.md >/dev/null 2>&1; echo "begin rc=$?"
( cd .polaris/wt/T-001 && echo a > src/a.txt && git add -A && git commit -qm "a small change" ) >/dev/null 2>&1
out="$(cd .polaris/wt/T-001 && bash ops/polaris wrap 2>&1)"; echo "wrap rc=$?"
echo "finish ran: $(printf '%s\n' "$out" | grep -c '^✅ finish: run complete')"
echo "done: $([ -f ops/board/done/T-001.md ] && echo yes || echo no)"
echo "file on main: $(git ls-tree --name-only main src/ | grep -c 'a\.txt')"
echo "caveat: $(printf '%s\n' "$out" | grep -c 'worktree \.polaris/wt/T-001 is where this command ran from — the next finish from the project folder clears it')"
echo "stop lines: $(printf '%s\n' "$out" | grep -c '^⛔')"
printf '%s\n' "$out" | grep -e '^⛔' -e 'CRUFT:' | sed 's/^/  /'
out="$(bash ops/polaris finish 2>&1)"; echo "finish rc=$?"
echo "folder: $([ -d .polaris/wt/T-001 ] && echo still there || echo gone)"
echo "branch: $(git show-ref -q --verify refs/heads/feat/T-001 && echo still there || echo gone)"
echo "caveat about it: $(printf '%s\n' "$out" | grep -c -e 'worktree .polaris/wt/T-001 has no active task' -e 'worktree .polaris/wt/T-001 is where')"
