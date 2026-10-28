# depth-uat — T-204 (ops/contracts/change-sized.md § 5): at scoped depth qa skips the slow `uat` key
# and says so in one pinned line; every run that reached a depth verdict prints ONE depth line, and
# at full it names the forcing cause plus the last measured full-suite time (the parenthetical is
# omitted when .polaris/last-suite-seconds is absent or not a number).
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it, so no live board
# or CONVENTIONS can red this golden. The "test runner" is a fake node_modules/.bin/vitest that
# only echoes its argv; `uat:` appends to a file so "uat not run" is a fact, not a guess.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p web/src web/node_modules/.bin lib
  printf '{"name":"web","scripts":{"test":"vitest run"}}\n' > web/package.json
  printf '#!/bin/sh\necho "FAKE-VITEST $*"\n' > web/node_modules/.bin/vitest
  chmod +x web/node_modules/.bin/vitest
  echo 'v1' > web/src/App.tsx
  echo 'v1' > lib/core.dat
  printf 'node_modules/\n.polaris/\nuat.log\n' > .gitignore
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\nuat: echo ran >> uat.log\ntest_select: echo RUN {tests}\n' > ops/CONVENTIONS.md
  printf 'web/src/App.tsx\tweb/t\t-\tfixture [T-4]\n' > ops/SURFACES.tsv
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
qa() { # qa <label> — ONE qa run reported as facts: the depth line, the uat deferral line, how many
  # times uat has actually run so far.
  OUT="$(bash "$KIT" qa 2>&1)"
  echo "$1:"
  printf '%s\n' "$OUT" | sed -n -e 's/^ *\(depth: .*\)$/  \1/p' -e 's/^ *\(uat — deferred.*\)$/  \1/p'
  echo "  uat-runs=$(grep -c ran uat.log 2>/dev/null || echo 0)"
}
# 1) unbounded first run: no baseline, the whole suite incl. uat runs — the green stamp the rest build on.
qa baseline
# 2) a component change in a package with an installed runner → scoped: uat deferred, never run.
echo 'v2' > web/src/App.tsx; git commit -qam 'feat: app v2'
qa scoped
# 3) a change outside any package → full: the line names the path and the last measured time.
echo '125 1' > .polaris/last-suite-seconds
echo 'v2' > lib/core.dat; git commit -qam 'feat: core v2'
qa full-timed
# 4) same shape, last-suite-seconds absent → no parenthetical.
rm -f .polaris/last-suite-seconds
echo 'v3' > lib/core.dat; git commit -qam 'feat: core v3'
qa full-untimed
# 5) a seconds figure under a minute renders as <n>s.
echo '42 1' > .polaris/last-suite-seconds
echo 'v4' > lib/core.dat; git commit -qam 'feat: core v4'
qa full-seconds
