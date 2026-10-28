# change-bound — T-202 (ops/contracts/change-sized.md § 1): with NO usable suite stamp, a bounded
# verdict comes from the files THIS run landed (the session plan's done/ tasks, via landed_sha):
# CSS-only → look, docs-only → none, no plan recorded → full (today), stamp present → the stamp path.
#
# HERMETIC: each case builds a throwaway fixture repo under mktemp -d and runs from INSIDE it, so no
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
    printf 'test: true\nlint: true\n' > ops/CONVENTIONS.md
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
# 1) no stamp + one landed CSS-only plan task ⇒ look, no suite key runs
mkfix css; plan p1
landed T-9 p1 style.css 'body{color:red}'
qa css-only
# 2) no stamp + one landed docs-only plan task ⇒ none
mkfix docs; plan p1
landed T-9 p1 docs/readme.md 'doc v2'
qa docs-only
# 3) no plan recorded ⇒ unbounded, the whole suite, exactly as before
mkfix noplan
landed T-9 p1 style.css 'body{color:red}'
qa no-plan
# 4) plan recorded but a code file landed ⇒ bounded, depth_for decides (not look/none): suite runs
mkfix code; plan p1
landed T-9 p1 src/a.dat 'code v2'
qa code-landed
# 5) a stamp present ⇒ the stamp path, unchanged: baseline runs everything, then docs-only ⇒ none
mkfix stamp
qa baseline
echo 'doc v2' > docs/readme.md; git commit -qam 'docs: v2'
qa stamp-docs
