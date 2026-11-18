# pack-named-tests — the one code seam between the smooth run's side-by-side cards, run for real
# (ops/contracts/smooth.md § 10, T-317): `new` (T-313) owns a card's mapped test and its folder guide
# and lists what touches the card's files; `pack` (T-314) calls the same `_card_reach` and prints that
# list FIRST. Neither card could prove the pair in its own worktree; this golden runs both on the
# joined tree.
# The fixture: a draft owning src/alpha.py (tracked) and src/beta.sh (a file the card ADDS — git does
# not track it yet), a tracked src/CLAUDE.md, a SURFACES row mapping src/beta.sh to tests/beta.*,
# tests/test_alpha.py that names alpha (and says CLAUDE.md, which must never become a "names" line —
# § 1.2 v1.2) and src/gamma.py that imports alpha (an edge the index's `find --importers` resolves;
# kit/ops/index.py is copied into the fixture and kept out of git, as new-task does).
# Pinned: 1. new's ID line, its two "owns … too" lines and its advisory block, both on stderr (2>&1);
# 2. the board file gained exactly tests/beta.* and src/CLAUDE.md; 3. pack's FILES THAT TOUCH YOURS
# section holds the same two paths, and it is the first section of the pack.
# HERMETIC: one throwaway repo under mktemp -d, HOME, USERPROFILE and POLARIS_AWAKE_HOME faked, no
# session id, the CLI run from INSIDE the fixture. No sha, time or absolute path is printed.
unset CLAUDE_CODE_SESSION_ID
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src tests
  printf 'def run():\n    return 1\n' > src/alpha.py
  printf 'import alpha\n\nalpha.run()\n' > src/gamma.py
  printf '# the folder notes live in src/CLAUDE.md\nfrom src import alpha\n' > tests/test_alpha.py
  printf '<!-- polaris:guide -->\n# src/ — the code\n<!-- /polaris:guide -->\n' > src/CLAUDE.md
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf 'src/beta.sh\ttests/beta.*\t-\tthe beta script\n' >> ops/SURFACES.tsv
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  cp "${KIT%/*}/index.py" ops/index.py; echo ops/index.py >> .git/info/exclude   # the index the uses kind asks
  mkdir -p .polaris/drafts
  printf -- '---\ntitle: alpha and a new beta\nplan: p\npoints: 1\nrisk: normal\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/alpha.py\n  - src/beta.sh\ndepends_on: []\nverify:\n  - true\n---\n## Why\nfixture\n' > .polaris/drafts/a.md
) >/dev/null 2>&1
cd "$R"
echo '== 1. new: the mapped test and the guide join the card, the rest is listed'
bash "$KIT" new .polaris/drafts/a.md 2>&1 | tr -d '\r'
echo '== 2. the board file gained exactly those two'
f="$(ls ops/board/*/T-*.md | head -1)"
sed -n '/^files_owned:/,/^depends_on:/p' "$f" | sed '1d;$d' | tr -d '\r'
echo '== 3. pack prints the same two paths, before any other section'
id="${f##*/}"; id="${id%.md}"
bash "$KIT" pack "$id" 2>/dev/null | tr -d '\r' > "$FIX/pack"
awk '/^FILES THAT TOUCH YOURS/ { on = 1; print; next } on && /^   / { print; next } on { exit }' "$FIX/pack"
awk '/^FILES THAT TOUCH YOURS/ { print "it comes before: " (seen ? "a section — WRONG" : "every === section"); exit } /^=== / { seen = 1 }' "$FIX/pack"
