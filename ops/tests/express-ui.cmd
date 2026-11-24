# express-ui — walk-away § 6 (T-324). `land --express` honours depth `ui`: a change of ui file types
# only runs lint and typecheck — test, build and uat are skipped and said ONCE (_ui_skip_say, the line
# qa prints), and with no before/after look set up the "lint and typecheck are the whole check" line
# prints once per repo (.polaris/look-offered): the second ui land says only the skip line.
#
# HERMETIC: a throwaway repo under mktemp -d, no remote, landing: integrator (the by-hand express
# lane), run from INSIDE the fixture. Every suite key appends its own name to .polaris/ran, so which
# keys ran is a fact, not a guess. A green qa first gives the bounded change set depth needs.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_HEAVY_DIR="$FIX/heavy"
mkdir -p "$HOME"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  { for k in test lint typecheck build uat; do printf '%s: echo %s >> .polaris/ran\n' "$k" "$k"; done
    printf 'landing: integrator\n'; } > ops/CONVENTIONS.md
  printf '# SPRINT 1 - express ui  capacity: 5\n' > ops/SPRINT.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  for i in 1 2; do
    printf -- '---\nid: T-%s\ntitle: ui task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/c%s.tsx\nverify: []\n---\n' "$i" "$i" > ops/board/ready/T-$i.md
  done
  git add -A; git commit -qm board
  mkdir -p .polaris
  bash "$KIT" qa
) >/dev/null 2>&1
cd "$R"
land() { # land <n> — claim, change one .tsx, hand off, land --express; report the facts
  rm -f .polaris/ran
  bash "$KIT" claim "T-$1" >/dev/null 2>&1
  ( set -e; cd ".polaris/wt/T-$1"; echo "<b/>" > "src/c$1.tsx"; git add -A; git commit -qm "feat: T-$1 ui"
    bash "$KIT" handoff "T-$1" >/dev/null 2>&1 ) || true
  OUT="$(bash "$KIT" land --express "T-$1" 2>&1)"; echo "express rc=$?"
  printf '%s\n' "$OUT" | grep -E '^   (depth: |ui — )|^✅ (test|lint|typecheck|build|uat) — '
  echo "skip line: $(printf '%s\n' "$OUT" | grep -c 'ui — test, build and uat skipped')"
  echo "ran: $(tr '\n' ' ' < .polaris/ran 2>/dev/null)"
  echo "done: $([ -f "ops/board/done/T-$1.md" ] && echo yes || echo no)"
}
echo "== 1. the first ui land: lint + typecheck only, both ui lines =="
land 1
echo "== 2. the second: lint + typecheck only, the look line already said =="
land 2
echo "look-offered: $([ -f .polaris/look-offered ] && echo yes || echo no)"
