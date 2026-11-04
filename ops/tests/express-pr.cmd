# express-pr — T-229 (ops/contracts/publish-modes.md § v2). `land --express` no longer treats
# `publish: pr` as special: one reviewed task lands, seals and reaches done/ on LOCAL main exactly as
# in direct mode, and NOTHING leaves the machine (origin keeps only the refs it had).
#
# HERMETIC: a throwaway repo + throwaway bare origin under mktemp -d, run from INSIDE the fixture.
# Nothing printed carries a sha, a path, a time or a user.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"; OR="$FIX/origin.git"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\npublish: pr\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# SPRINT 1 - express pr  capacity: 5\n' > ops/SPRINT.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf -- '---\nid: T-1\ntitle: express task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/e.dat\nverify: []\n---\n' > ops/board/ready/T-1.md
  git add -A; git commit -qm board
  git init -q --bare "$OR"; git remote add origin "$OR"; git push -q origin main
) >/dev/null 2>&1
cd "$R"
refs() { git ls-remote origin 2>/dev/null | awk '{print $2}' | grep -v 'polaris/board' | sort; }
BEFORE="$(refs)"; M0="$(git rev-parse main)"
echo "triage: $(bash "$KIT" triage 2>&1 | sed -n 1p)"
bash "$KIT" claim T-1 >/dev/null 2>&1
( set -e; cd .polaris/wt/T-1; echo e > src/e.dat; git add -A; git commit -qm "feat: T-1 express"
  bash "$KIT" handoff T-1 >/dev/null 2>&1 ) || true
echo "in review: $([ -f ops/board/review/T-1.md ] && echo yes || echo no)"
bash "$KIT" land --express T-1 >/dev/null 2>&1; echo "express rc=$?"
echo "done: $([ -f ops/board/done/T-1.md ] && echo yes || echo no)"
echo "local main moved: $([ "$(git rev-parse main)" != "$M0" ] && echo yes || echo no)"
echo "file on main: $(git ls-tree --name-only main src/ | grep -c 'e\.dat')"
echo "sprint tag (local): $(git tag -l 'sprint/*' | wc -l | tr -d ' ')"
echo "origin refs unchanged: $([ "$(refs)" = "$BEFORE" ] && echo yes || echo no)"
echo "origin main unchanged: $([ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$M0" ] && echo yes || echo no)"
