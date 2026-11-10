# brain-once — a landing refreshes the brain once (ops/contracts/away.md § 7).
# HERMETIC: a throwaway repo under mktemp -d with the kit INSTALLED in it and a brain folder, so every
# command runs the fixture's own ops/polaris. HOME, USERPROFILE and POLARIS_AWAKE_HOME are faked
# together. POLARIS_BRAIN_TRACE counts the refreshes that actually run. Pinned: a self-landing handoff
# (land, seal and done under one lease) refreshes ONCE and leaves no .polaris/brain-due; with
# `landing: integrator`, a standalone seal still refreshes once, and so does a plain done after it,
# again with no marker left. No sha, path or time printed.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT POLARIS_INT_TOKEN POLARIS_BRAIN_TRACE
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
  for n in a b; do
    printf -- '---\ntitle: change %s\nplan: p\npoints: 1\nrisk: normal\nfiles_owned:\n  - src/%s.txt\ndepends_on: []\ncontract: ops/contracts/fix.md\nverify: []\n---\n## Why\nfixture\n' "$n" "$n" > "$D/$n.md"
  done
) >/dev/null 2>&1
cd "$R"
TR="$FIX/trace"
count() { if [ -f "$TR" ]; then grep -c '^refresh$' "$TR"; else echo 0; fi; }
echo "installed: $([ -f ops/polaris ] && echo yes || echo no)"
echo "== self-landing handoff: land, seal and done under one lease"
bash ops/polaris begin .polaris/drafts/a.md >/dev/null 2>&1; echo "begin rc=$?"
( cd .polaris/wt/T-001 && echo a > src/a.txt && git add -A && git commit -qm "change a" ) >/dev/null 2>&1
: > "$TR"
( cd .polaris/wt/T-001 && POLARIS_BRAIN_TRACE="$TR" bash ops/polaris handoff ) >/dev/null 2>&1; echo "handoff rc=$?"
echo "done: $([ -f ops/board/done/T-001.md ] && echo yes || echo no)"
echo "refreshes: $(count)"
echo "marker: $([ -f .polaris/brain-due ] && echo left || echo none)"
echo "== landing: integrator — a standalone seal, then a plain done"
printf 'test: true\nlanding: integrator\n' > ops/CONVENTIONS.md
git add -A >/dev/null 2>&1; git commit -qm "integrator lane" >/dev/null 2>&1
bash ops/polaris begin .polaris/drafts/b.md >/dev/null 2>&1; echo "begin rc=$?"
( cd .polaris/wt/T-002 && echo b > src/b.txt && git add -A && git commit -qm "change b" ) >/dev/null 2>&1
( cd .polaris/wt/T-002 && bash ops/polaris handoff ) >/dev/null 2>&1; echo "handoff rc=$?"
echo "in review: $([ -f ops/board/review/T-002.md ] && echo yes || echo no)"
bash ops/polaris land T-002 >/dev/null 2>&1; echo "land rc=$?"
: > "$TR"
POLARIS_BRAIN_TRACE="$TR" bash ops/polaris seal >/dev/null 2>&1; echo "seal rc=$?"
echo "seal refreshes: $(count)"
: > "$TR"
POLARIS_BRAIN_TRACE="$TR" bash ops/polaris done T-002 >/dev/null 2>&1; echo "done rc=$?"
echo "done: $([ -f ops/board/done/T-002.md ] && echo yes || echo no)"
echo "done refreshes: $(count)"
echo "marker: $([ -f .polaris/brain-due ] && echo left || echo none)"
