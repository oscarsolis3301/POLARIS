# flow-solo — `begin` and `wrap` (ops/contracts/minutes.md § 9.5): one call in, one call out.
# HERMETIC: a throwaway repo under mktemp -d with HOME and USERPROFILE faked together, `landing:
# integrator`, the CLI run from INSIDE it. Pinned: a 1-point draft goes `begin` → an edit in the
# worktree `pack` names → `wrap`, and ends in done/ with finish's rc 0; a 5-point draft makes `begin`
# exit 3 with its one line and the task stays in ready/. Nothing printed carries a sha, path or time.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# SPRINT 1 — flow\n' > ops/SPRINT.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  D=.polaris/drafts; mkdir -p "$D"
  dr() { printf -- '---\ntitle: %s\nplan: p\npoints: %s\nrisk: normal\nfiles_owned:\n  - %s\ndepends_on: []\ncontract: ops/contracts/fix.md\nverify: []\n---\n## Why\nfixture\n' "$@"; }
  dr 'a small change' 1 src/a.txt > "$D/a.md"
  dr 'a bigger change' 5 src/b.txt > "$D/b.md"
) >/dev/null 2>&1
cd "$R"
out="$(bash "$KIT" begin .polaris/drafts/a.md 2>&1)"; echo "begin rc=$?"
echo "pack printed: $(printf '%s\n' "$out" | grep -c '^PACK T-001')"
echo "active: $([ -f ops/board/active/T-001.md ] && echo yes || echo no)"
( cd .polaris/wt/T-001 && echo a > src/a.txt && git add -A && git commit -qm "a small change" ) >/dev/null 2>&1
out="$(cd .polaris/wt/T-001 && bash "$KIT" wrap 2>&1)"; echo "wrap rc=$?"
echo "finish ran: $(printf '%s\n' "$out" | grep -c '^✅ finish: run complete')"
echo "done: $([ -f ops/board/done/T-001.md ] && echo yes || echo no)"
echo "file on main: $(git ls-tree --name-only main src/ | grep -c 'a\.txt')"
out="$(bash "$KIT" begin .polaris/drafts/b.md 2>&1)"; echo "begin rc=$?"
printf '%s\n' "$out" | grep '^begin:'
echo "ready: $([ -f ops/board/ready/T-002.md ] && echo yes || echo no)"
echo "active: $([ -f ops/board/active/T-002.md ] && echo yes || echo no)"
