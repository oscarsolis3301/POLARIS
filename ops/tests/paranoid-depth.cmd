# paranoid-depth — T-212 (ops/contracts/one-yes.md §§ 3-4): risk: high no longer forces the suite;
# depth follows the paths. A CSS-only land under integration: paranoid runs no suite; a risk: high
# docs task is none; the DIRTY-tree + ancestor-stamp + test_select-UNSET case still runs the suite
# and writes .polaris/last-suite-seconds. HERMETIC: fixtures under mktemp -d.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
unset CLAUDE_CODE_SESSION_ID
mkfix() { # mkfix <name> → fixture repo, paranoid, green stamp at the board commit
  R="$FIX/$1"
  ( set -e
    git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
    cd "$R"
    git config user.email t@t; git config user.name t; git config core.autocrlf false
    mkdir -p src docs
    echo 'code v1' > src/a.dat
    echo 'doc v1'  > docs/readme.md
    echo 'css v1'  > src/a.css
    git add -A; git commit -qm init
    bash "$KIT" init-board
    printf 'test: true\nlint: true\nintegration: paranoid\n' > ops/CONVENTIONS.md
    git add -A; git commit -qm board
    mkdir -p .polaris; printf '%s %s full\n' "$(git rev-parse HEAD)" "$(date +%s)" > .polaris/suite-stamp
  ) >/dev/null 2>&1
  cd "$R"
}
landed() { # landed <ID> <risk> <file> <content> — one risk-tagged task landed: commit ending [<ID>] + done/ file
  mkdir -p "$(dirname "$3")" ops/board/done
  printf '%s\n' "$4" > "$3"
  git add -A; git commit -qm "feat: $1 [$1]"
  printf -- '---\nid: %s\nrisk: %s\n---\n' "$1" "$2" > "ops/board/done/$1.md"
  git add -A; git commit -qm "board $1" >/dev/null 2>&1 || true
}
qa() { # qa <label> — rc · suite keys that ran · the depth line
  OUT="$(bash "$KIT" qa 2>&1)"; RC=$?
  printf '%s: rc=%s suite-ran=%s\n' "$1" "$RC" "$(printf '%s\n' "$OUT" | grep -cE '(test|lint) — green')"
  printf '%s\n' "$OUT" | sed -n 's/^ *\(depth: .*\)$/  \1/p'
}
secs() { if [ -f .polaris/last-suite-seconds ] && grep -qE '^[0-9]+ [0-9]+$' .polaris/last-suite-seconds; then echo ok; else echo missing; fi; }
echo '== paranoid, CSS-only land: no suite =='
mkfix css; landed T-C normal src/a.css 'css v2'
qa css-only
echo '== paranoid, risk: high docs-only land: no suite =='
mkfix hdocs; landed T-H high docs/readme.md 'doc v2'
qa high-docs
echo '== paranoid, risk: high code land: depth follows the paths (test_select unset => full, said so) =='
mkfix hcode; landed T-K high src/a.dat 'code v2'
qa high-code
echo "last-suite-seconds: $(secs)"
echo '== dirty tree + ancestor stamp + test_select UNSET: the suite still runs, timing written =='
mkfix dirty; landed T-D normal docs/readme.md 'doc v2'
printf 'test: true\n' >> ops/CONVENTIONS.md
qa dirty-unset
echo "last-suite-seconds: $(secs)"
