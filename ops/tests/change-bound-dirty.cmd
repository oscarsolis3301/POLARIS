# change-bound-dirty — T-208 (ops/contracts/change-sized.md fix wave 1): the run-landed fallback is
# taken ONLY on a clean tree; uncommitted edits make the set unbounded, so qa re-runs the suite.
# HERMETIC: fixtures under mktemp -d, run from inside; CONVENTIONS sets test_select so the carry
# branch is reachable.
# live board, CONVENTIONS or decisions.ndjson can red this golden; byte-identical from any state.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
unset CLAUDE_CODE_SESSION_ID
mkfix() { # mkfix <name> → a fixture repo at $FIX/<name>, board initialised, test: true lint: true
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
    printf 'test: true\nlint: true\ntest_select: true {tests}\n' > ops/CONVENTIONS.md
    git add -A; git commit -qm board
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
  OUT="$(bash "$KIT" qa 2>&1)"; RC=$?
  if [ -f .polaris/suite-stamp ]; then read -r _ _ STSC < .polaris/suite-stamp; else STSC=none; fi
  printf '%s: rc=%s scope=%s suite-ran=%s\n' "$1" "$RC" "${STSC:-none}" \
    "$(printf '%s\n' "$OUT" | grep -cE '(test|lint|typecheck|build|uat) — green')"
  printf '%s\n' "$OUT" | sed -n 's/^ *\(depth: .*\)$/  \1/p'
}
# 1) plan + landed docs-only task + an uncommitted edit => dirty => unbounded => suite runs (a dirty tree withholds the stamp, so scope stays none)
mkfix dirty; plan p1
landed T-9 p1 docs/readme.md 'doc v2'
printf 'test: true\n' >> ops/CONVENTIONS.md
qa dirty-docs
# 2) the same landed docs-only plan on a CLEAN tree ⇒ none, no suite
mkfix clean; plan p1
landed T-9 p1 docs/readme.md 'doc v2'
qa clean-docs
# 3) plan + landed code task + dirty tree ⇒ the suite runs
mkfix dirtycode; plan p1
landed T-9 p1 src/a.dat 'code v2'
printf 'test: true\n' >> ops/CONVENTIONS.md
qa dirty-code
