# `pack` carries the folder guides (ops/contracts/save-hops.md § 0.1 + § 3.2) because nothing else
# reliably does: Claude Code loads a folder's CLAUDE.md only when a session READS a file there, so a
# builder that only CREATES files never sees one, and other agents never load one at all. The walk
# is the whole feature — start at each owned pattern's folder, climb to (never into) the root, the
# first tracked CLAUDE.md holding the marker wins, ≤ 3 guides, ≤ 25 lines each — and none of it is
# reachable from this repo: POLARIS's own source carries no guide. Without a fixture it is code that
# only OTHER people's repos run. The same golden pins § 3.2's other half: a cold repo's first pack
# builds the missing brain, quietly, BEFORE the HOUSE STYLE section reads it.
#
# HERMETIC by construction (the pack-visual / keys-drift pattern): ONE throwaway repo under mktemp -d
# with its own board, tasks and guides, the CLI run from INSIDE it so polaris anchors to the fixture
# as PRIMARY. Nothing here reads the live board or the live brain. Only the sections this task owns
# are sliced out of pack; everything else pack says about a fixture is noise this golden must not own.
# RUNTIME ~21s (measured, Windows/Git Bash): three real packs at ~3s each, the first one paying a real
# brain build (~10s of the total) — the cost § 3.2 moves from a builder's extra hop into its first pack.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src/app/feature src/hooks lib web tools extra docs plain
  echo x > src/app/feature/x.ts; echo h > src/hooks/use.ts; echo u > lib/util.sh; echo w > web/a.html
  echo z > tools/z.txt; echo w > extra/w.txt; echo d > docs/x.md; echo y > plain/y.txt; echo r > README.md
  # The ROOT carries the marker too, and must never be read as a guide: the walk stops below it.
  printf '<!-- polaris:guide -->\n# the root — never a folder guide\n<!-- /polaris:guide -->\n' > CLAUDE.md
  # The guide two folders above src/app/feature/, wrapped in a human's own text on both sides — text
  # outside the markers is the human's, never read. The blank line inside the block is body, kept.
  printf '# notes a human wrote, above the block\n\n<!-- polaris:guide -->\n# src/ — the shop'"'"'s application code\n\nFeatures import each other through `@/…`, never by climbing with ../\n<!-- /polaris:guide -->\n\nMore of the human'"'"'s text, below the block.\n' > src/CLAUDE.md
  # A CLAUDE.md WITHOUT the marker is not a guide: the climb goes straight past it.
  printf '# app notes — a plain CLAUDE.md, no guide marker\n' > src/app/CLAUDE.md
  # No end marker: the block runs to EOF, and a reader prints its first 25 lines, never all 30.
  { printf '<!-- polaris:guide -->\n# lib/ — shell helpers every feature shares\n'
    i=2; while [ "$i" -le 30 ]; do printf -- '- rule %s\n' "$i"; i=$((i + 1)); done; } > lib/CLAUDE.md
  printf '<!-- polaris:guide -->\n# web/ — the pages a customer sees\n<!-- /polaris:guide -->\n' > web/CLAUDE.md
  # CRLF, the way a Windows checkout with core.autocrlf writes it: the markers still match, and no
  # carriage return reaches the pack.
  printf '<!-- polaris:guide -->\r\n# tools/ — build scripts, saved with CRLF line ends\r\n<!-- /polaris:guide -->\r\n' > tools/CLAUDE.md
  printf '<!-- polaris:guide -->\n# extra/ — a fourth guide, one past the cap\n<!-- /polaris:guide -->\n' > extra/CLAUDE.md
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  # Written AFTER the commits: a guide is a TRACKED <dir>/CLAUDE.md, so this one does not count.
  printf '<!-- polaris:guide -->\n# docs/ — UNTRACKED, so never a guide\n<!-- /polaris:guide -->\n' > docs/CLAUDE.md
  # T <ID> <title> <owned patterns, one per line>. backlog/, not ready/: pack finds a task in any
  # column, and these three are never claimed.
  T() { printf -- '---\nid: %s\ntitle: %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\ncontract: ops/contracts/fix.md\nfiles_owned:\n%sverify: []\n---\n## Why\nfixture\n' \
        "$1" "$2" "$(printf '%s\n' "$3" | sed 's/^/  - /')
" > "ops/board/backlog/$1.md"; }
  T T-501 'the climb' 'src/app/feature/x.ts
src/app/feature/*.ts
src/hooks/use.ts
README.md'
  T T-502 'patterns and caps' 'lib/ut*.sh
web/
docs/x.md
tools/z.txt
extra/w.txt'
  T T-503 'no guide anywhere' 'plain/y.txt
docs/x.md'
) >/dev/null 2>&1
R="$FIX/repo"; OUT="$FIX/out"
P() { ( cd "$R" && bash "$KIT" pack "$1" 2>/dev/null ) > "$OUT"; }
# ONE section of the saved pack: from its own header to the next `=== `. The blank line that leads
# the NEXT header is held and dropped; a blank line INSIDE a section is printed, because a guide's
# own blank lines are part of its body. awk, not grep/sed — CR-sensitive matching bites on Windows.
SEC() { awk -v s="=== $1" '
  on && /^=== / { exit }
  on { if (held) print ""; held = ($0 == ""); if (!held) print }
  index($0, s) == 1 { on = 1 }' "$OUT"; }
# The section header printed just before FOLDER GUIDES — the placement the contract pins.
PREV() { awk '/^=== FOLDER GUIDES/ { print "follows: " p; exit }
  /^=== / { p = $0; sub(/^=== /, "", p); sub(/ ===$/, "", p) }' "$OUT"; }
COUNT() { awk '/^=== FOLDER GUIDES/ { n++ } END { print "FOLDER GUIDES sections: " n + 0 }' "$OUT"; }
BRAIN() { [ -d "$R/.polaris/brain" ] && echo yes || echo no; }

echo '== 1. a cold repo: the first pack builds the missing brain, quietly, before HOUSE STYLE reads it =='
# Before § 3.2 this pack printed `(no brain yet — run: ops/polaris brain)` and handed a cold builder
# one more hop. Now HOUSE STYLE opens on the detected table — which proves the build ran BEFORE the
# section, not after it — and not one line of the build's own chatter reaches the pack.
printf 'brain before the first pack: %s\n' "$(BRAIN)"
P T-501
printf 'brain after it: %s\n' "$(BRAIN)"
SEC 'HOUSE STYLE' | head -1
printf 'lines of brain-build chatter in the pack: %s\n' "$(awk '/brain built/ { n++ } END { print n + 0 }' "$OUT")"

echo '== 2. a guide two folders up is found; a CLAUDE.md without the marker is climbed past =='
# Three owned patterns, ONE guide: a file and a glob in src/app/feature/ and a file in a sibling
# folder all climb to src/, and it prints once. README.md sits at the root, whose CLAUDE.md carries
# the marker and still never counts. The human's text around the block stays out.
PREV
SEC 'FOLDER GUIDES'

echo '== 3. a brain that already exists is never rebuilt by pack =='
# "Once" means missing → build; present → leave it. Refreshing is done's and seal's job, and a pack
# that rebuilt every time would charge every builder a full brain build per call.
rm -f "$R/.polaris/brain/learned.md"
P T-502
printf 'learned.md after the next pack: %s\n' "$( [ -f "$R/.polaris/brain/learned.md" ] && echo rebuilt || echo 'still gone — left as it was' )"

echo '== 4. globs, dir/ patterns, an untracked guide, the 25-line and 3-guide caps, CRLF =='
# lib/ut*.sh keeps only its literal prefix `lib/ut`, then its folder: lib/. web/ is that dir. docs/ has
# a marker but is untracked, so it is no guide and takes no slot. tools/ is CRLF. extra/ is the fourth
# guide and the cap of three cuts it — owned order decides which three, never the alphabet.
SEC 'FOLDER GUIDES'

echo '== 5. no guide anywhere above an owned path: no section at all — not even its header =='
# plain/ has no CLAUDE.md, docs/'s is untracked, and the root is never climbed into: the section is
# OMITTED, which is what keeps every guide-less repo's pack (and pack-visual's golden) byte-identical.
# The brain is swapped for a plain FILE first, so the build below cannot create its folder — assert 6.
rm -rf "$R/.polaris/brain"; : > "$R/.polaris/brain"
P T-503
COUNT

echo '== 6. a brain build that fails changes nothing: the old no-brain line still prints =='
SEC 'HOUSE STYLE'
rm -f "$R/.polaris/brain"
