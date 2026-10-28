# depth-commit — T-205 (ops/contracts/change-sized.md § 6): `polaris depth --commit <sha>` says, with
# nothing run, how much testing a commit needed, why, and the exact commands qa would run (and the uat
# it would skip). Pinned here: the verdict matches what a real qa decides for the same change, the
# command is read-only (the repo is byte-identical after), a bad sha is rc 2, and --commit <sha>
# together with an <ID> is a usage error.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it. The "test runner" is
# a fake node_modules/.bin/vitest that only echoes its argv.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p web/src web/node_modules/.bin lib docs
  printf '{"name":"web","scripts":{"test":"vitest run"}}\n' > web/package.json
  printf '#!/bin/sh\necho "FAKE-VITEST $*"\n' > web/node_modules/.bin/vitest
  chmod +x web/node_modules/.bin/vitest
  echo 'v1' > web/src/App.tsx
  echo 'v1' > web/src/app.css
  echo 'v1' > lib/core.dat
  echo 'v1' > docs/readme.md
  printf 'node_modules/\n.polaris/\n' > .gitignore
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\nlint: echo LINT\nuat: echo UAT\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
  echo 'v2' > web/src/App.tsx;    git commit -qam 'feat: app v2'
  echo 'v2' > lib/core.dat;       git commit -qam 'feat: core v2'
  echo 'v2' > docs/readme.md;     git commit -qam 'docs: readme v2'
  echo 'v2' > web/src/app.css;    git commit -qam 'style: css v2'
) >/dev/null 2>&1
cd "$R"
snap() { { git status --porcelain; git rev-parse HEAD; find . -path ./.git -prune -o -type f -print | sort | xargs cksum 2>/dev/null; } | cksum; }
show() { # show <label> <sha>
  echo "$1:"; bash "$KIT" depth --commit "$2" 2>&1; echo "  rc=$?"
}
APP="$(git rev-parse HEAD~3)"; CORE="$(git rev-parse HEAD~2)"; DOC="$(git rev-parse HEAD~1)"; CSS="$(git rev-parse HEAD)"
ROOT="$(git rev-list --max-parents=0 HEAD)"
BEFORE="$(snap)"
show scoped "$APP"
show full "$CORE"
show none "$DOC"
show look "$CSS"
echo "root:"; bash "$KIT" depth --commit "$ROOT" 2>&1 | sed -n 1p
show bad-sha deadbeef
echo "id-and-commit:"; bash "$KIT" depth T-1 --commit "$APP" 2>&1 | sed -n 1p; echo "  rc=${PIPESTATUS[0]}"
[ "$BEFORE" = "$(snap)" ] && echo "read-only: repo byte-identical after" || echo "read-only: REPO CHANGED"
# the same decision qa makes for the same change: qa at a fresh checkout of each commit
for pair in scoped:"$APP" full:"$CORE"; do
  lbl="${pair%%:*}"; sha="${pair#*:}"
  git checkout -q -B main "$sha~1" 2>/dev/null
  mkdir -p .polaris; echo "$(git rev-parse HEAD) 1 full" > .polaris/suite-stamp
  git checkout -q -B main "$sha" 2>/dev/null
  echo "qa-agrees-$lbl: $(bash "$KIT" qa 2>&1 | awk '/depth: /{print $2; exit}') / $(bash "$KIT" depth --commit "$sha" 2>&1 | sed -n 1p)"
done
