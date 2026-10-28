# qa-carry-dirty — T-209 (ops/contracts/change-sized.md fix wave 2): a stamp-baseline carry needs a
# CLEAN tree and a set test_select:; test_select unset runs test: verbatim (6.8.0).
# HERMETIC: fixtures under mktemp -d, run from inside.
# live board, CONVENTIONS or decisions.ndjson can red this golden; byte-identical from any state.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
unset CLAUDE_CODE_SESSION_ID
mkfix() { # mkfix <name> <select|none> → fixture repo, board initialised, green stamp at the board commit
  R="$FIX/$1"
  ( set -e
    git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
    cd "$R"
    git config user.email t@t; git config user.name t; git config core.autocrlf false
    mkdir -p src docs
    echo 'code v1' > src/a.dat
    echo 'doc v1'  > docs/readme.md
    git add -A; git commit -qm init
    bash "$KIT" init-board
    printf 'test: true
lint: true
' > ops/CONVENTIONS.md
    [ "$2" = select ] && printf 'test_select: true {tests}
' >> ops/CONVENTIONS.md
    git add -A; git commit -qm board
    mkdir -p .polaris; printf '%s %s full
' "$(git rev-parse HEAD)" "$(date +%s)" > .polaris/suite-stamp
  ) >/dev/null 2>&1
  cd "$R"
}
landed() { # landed <ID> <plan> <file> <content> — land one plan task: a commit ending [<ID>] + its done/ file
  mkdir -p "$(dirname "$3")" ops/board/done
  printf '%s\n' "$4" > "$3"
  git add -A; git commit -qm "feat: $1 [$1]"
  printf -- '---\nid: %s\nplan: %s\n---\n' "$1" "$2" > "ops/board/done/$1.md"
  git add -A; git commit -qm "board $1" >/dev/null 2>&1 || true
}
plan() { mkdir -p ".polaris/handover/-"; printf '%s\n' "$1" > ".polaris/handover/-/plan"; }
qa() { # qa <label> — rc · stamp scope · suite keys that ran · the depth/nothing lines
  OUT="$(bash "$KIT" qa 2>&1)"; RC=$?; [ -n "$DBG" ] && printf "%s
" "$OUT" >&2
  if [ -f .polaris/suite-stamp ]; then read -r _ _ STSC < .polaris/suite-stamp; else STSC=none; fi
  printf '%s: rc=%s scope=%s suite-ran=%s\n' "$1" "$RC" "${STSC:-none}" \
    "$(printf '%s\n' "$OUT" | grep -cE '(test|lint|typecheck|build|uat) — green')"
  printf '%s\n' "$OUT" | sed -n 's/^ *\(depth: .*\)$/  \1/p'
}
docsonly() { mkdir -p docs; echo 'doc v2' > docs/readme.md; git add -A; git commit -qm 'docs [T-1]' >/dev/null 2>&1; }
secs() { if [ -f .polaris/last-suite-seconds ] && grep -qE '^[0-9]+ [0-9]+$' .polaris/last-suite-seconds; then echo ok; else echo missing; fi; }
# 1) test_select UNSET, dirty tree, board/docs-only commits since the stamp => suite runs, timing written
mkfix dirty none; docsonly
printf 'test: true
' >> ops/CONVENTIONS.md
qa dirty-unset; echo "last-suite-seconds: $(secs)"
# 2) test_select UNSET, CLEAN tree => the suite still runs (6.8.0)
mkfix clean none; docsonly
qa clean-unset; echo "last-suite-seconds: $(secs)"
# 3) test_select SET, CLEAN tree, same history => still carries
mkfix carry select; docsonly
qa clean-set; echo "last-suite-seconds: $(secs)"
