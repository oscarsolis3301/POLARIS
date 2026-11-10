# qa-parallel — T-295 (ops/contracts/test-depth.md § v2.4, ops/contracts/away.md § 6): qa's quick
# checks run side by side. At `scoped` test, lint and typecheck start together, then build; at `ui`
# only lint and typecheck run, together, and the test key never starts. `qa_parallel: off` runs them
# one after another, and qa's printed text is the same either way — two reds side by side each keep
# their own block, in today's key order.
#
# HERMETIC: two identical throwaway repos under mktemp -d with the kit INSTALLED in each (one with
# `qa_parallel: off`), every qa run by the fixture's own ops/polaris. HOME, USERPROFILE and
# POLARIS_AWAKE_HOME are faked together. Each key appends `<key> start` / `<key> end` to ONE log with
# a sleep between, and touches `<key>.marker`; the overlap is read from the log's ORDER, never from a
# time. No sha, path or time printed.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT
mkfix() { # mkfix <dir> <extra CONVENTIONS line or -> — a repo with the kit installed and a green baseline
  local R="$1" extra="$2"
  ( set -e
    git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
    cd "$R"
    git config user.email t@t; git config user.name t; git config core.autocrlf false
    mkdir -p web src
    echo 'v1' > web/App.tsx; echo 'v1' > src/lib.dat
    cat > k.sh <<'KEY'
touch "$1.marker"; echo "$1 start" >> keys.log; sleep 2
if [ -f "red.$1" ]; then i=1; while [ "$i" -le 3 ]; do echo "$1 says line $i"; i=$((i + 1)); done; echo "$1 end" >> keys.log; exit 1; fi
echo "$1 end" >> keys.log
KEY
    printf '.polaris/\nkeys.log\n*.marker\nred.*\n' > .gitignore
    git add -A; git commit -qm init
    bash "$KIT_DIR/ops/install.sh" "$R"
    bash ops/polaris init-board
    printf 'test: bash k.sh test\nlint: bash k.sh lint\ntypecheck: bash k.sh typecheck\nbuild: echo BUILD\ntest_select: bash k.sh test {tests}\n' > ops/CONVENTIONS.md
    [ "$extra" = - ] || printf '%s\n' "$extra" >> ops/CONVENTIONS.md
    printf 'src/lib.dat\tsrc/t\t-\tfixture [T-9]\n' > ops/SURFACES.tsv
    git add -A; git commit -qm board
    bash ops/polaris qa
  ) >/dev/null 2>&1
}
overlap() { # overlapped: yes when a second key started before the first one ended
  awk '/ start$/ { o++; if (o > m) m = o } / end$/ { o-- } END { print (m >= 2) ? "yes" : "no" }' keys.log 2>/dev/null
}
run() { # run <label> — one qa in the current fixture, reported as facts; the full text kept in qa.<label>
  rm -f keys.log ./*.marker
  bash ops/polaris qa > "../qa.$1" 2>&1; local rc=$?
  echo "$1: rc=$rc overlapped: $(overlap) ran: $(sed -n 's/ start$//p' keys.log 2>/dev/null | sort | tr '\n' ' ')"
  echo "  test marker: $([ -f test.marker ] && echo created || echo never)"
  echo "  stamp scope: $(cut -d' ' -f3 .polaris/suite-stamp 2>/dev/null)"
  grep -e 'depth:' -e '— green' -e '— RED' -e '^   ui —' -e 'says line' "../qa.$1" | sed 's/^/  /'
}
case_scoped() { ( echo 'v2' > src/lib.dat && git commit -qam 'feat: lib v2' ) >/dev/null 2>&1; run "$1-scoped"; }
case_red() { # lint and typecheck both red side by side: each keeps its OWN block, in today's order
  ( echo 'v3' > src/lib.dat && git commit -qam 'feat: lib v3' ) >/dev/null 2>&1
  touch red.lint red.typecheck; run "$1-red"; rm -f red.lint red.typecheck
  bash ops/polaris qa >/dev/null 2>&1   # green again: the stamp moves to HEAD before the ui case
}
case_ui() {
  printf -- '---\nid: T-1\ntitle: fixture T-1\ntype: feature\npoints: 1\nwsjf: 1\nrisk: normal\nowner: null\nbranch: null\nstatus: active\nfiles_owned:\n  - web/App.tsx\nverify: []\n---\n' > ops/board/active/T-1.md
  ( echo 'v2' > web/App.tsx && git commit -qam 'ui: a tighter header [T-1]' ) >/dev/null 2>&1
  run "$1-ui"
}
mkfix "$FIX/on/repo" -
mkfix "$FIX/off/repo" 'qa_parallel: off'
cd "$FIX/on/repo"; echo "installed: $([ -f ops/polaris ] && echo yes || echo no)"
echo '== qa_parallel on (the default) =='
case_scoped on; case_red on; case_ui on
cd "$FIX/off/repo"
echo '== qa_parallel: off =='
case_scoped off; case_red off; case_ui off
cd "$FIX"
echo '== the printed text is the same in both modes =='
for d in scoped red ui; do
  if cmp -s "on/qa.on-$d" "off/qa.off-$d"; then echo "$d: same"; else echo "$d: DIFFERENT"; diff "on/qa.on-$d" "off/qa.off-$d"; fi
done
