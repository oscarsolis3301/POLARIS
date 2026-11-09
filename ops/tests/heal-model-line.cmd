# heal migrates ONE line of a repo's own CLAUDE.md (ops/contracts/speed.md § 2b, owner 2026-11-09).
# Older kits appended "- **Never name a model.** Fable and Haiku are forbidden outright; every spawn
# inherits the session." to every project's efficiency section, so every agent in every project was
# still told Fable is off limits after the owner made it theirs to pick again. heal now rewrites that
# EXACT line to the new wording — the first copy only, its line ending kept, every other byte of the
# file untouched. A line its owner has edited is theirs and stays; a file without the line is never
# written at all; and a second heal changes nothing. "Written" is read off the file's mtime, so "not
# written" means not even rewritten with the same bytes.
#
# HERMETIC (the heal-design pattern): a throwaway repo, and HOME and USERPROFILE point into this
# run's mktemp -d, so the real ~/.claude can never be read or written. A ready-made .polaris/brain/
# keeps heal from building a knowledge base this golden does not own; the marker in every fixture
# keeps it from appending a section. ONE fixture repo, seven heals (~1.2 s of CLI startup each).
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home"
mkdir -p "$HOME"
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
R="$FIX/repo"
printf 'base: main\nvoice: standard\n' > "$R/ops/CONVENTIONS.md"
mkdir -p "$R/.polaris/brain"
OLD='- **Never name a model.** Fable and Haiku are forbidden outright; every spawn inherits the session.'
NEW='- **Never name a model.** Every spawn inherits the session; Haiku is blocked, and Fable runs only when the owner picks it.'
# doc <eol> <model line> — the owner's prose, then the section an older kit appended around <model
# line>, every line ended by <eol>.
doc() {
  local e="$1" l
  for l in '# Fixture project' '' 'Our own words — heal never rewrites a byte of them.' '' \
           '<!-- POLARIS:EFFICIENCY -->' '## Token efficiency — the first property' '' \
           '- **Prefer ONE context over three.** Twenty-five subagents in a day is a failure, not diligence.' \
           "$2" '- **Ask early** rather than burning tokens guessing.' '' \
           'Added by `polaris heal`. Edit freely — it is appended once and never rewritten.'; do
    printf '%s%s' "$l" "$e"
  done
}
# H — heal once: everything it says but its closing line, note()'s indent stripped (an error leaking
# onto either stream shows up here too), then its rc.
H() {
  ( cd "$R" && bash "$KIT" heal ) > "$FIX/heal.out" 2>&1; printf '  heal rc: %s\n' "$?"
  sed -n 's/^   //; /^✅ heal: configuration checked$/d; p' "$FIX/heal.out"
}
touch -t 200101010000 "$FIX/ref"
old() { touch -t 200001010000 "$R/CLAUDE.md"; }
W() { if [ "$R/CLAUDE.md" -nt "$FIX/ref" ]; then echo "  file: written"; else echo "  file: not written"; fi; }
C() { if cmp -s "$R/CLAUDE.md" "$FIX/want"; then echo "  bytes: $1"; else echo "  bytes: DIFFER — expected $1"; fi; }

echo '== 1. the line an older kit appended (LF): rewritten, every other byte kept =='
doc $'\n' "$OLD" > "$R/CLAUDE.md"; doc $'\n' "$NEW" > "$FIX/want"; old
H; W; C 'the old file with only that line changed'
grep -n 'Never name a model' "$R/CLAUDE.md"

echo '== 2. a second heal is a no-op: no note, and the file is not even rewritten =='
old; H; W; C 'unchanged since the first heal'

echo '== 3. the same file with CRLF line ends: the new line keeps its CRLF =='
doc $'\r\n' "$OLD" > "$R/CLAUDE.md"; doc $'\r\n' "$NEW" > "$FIX/want"; old
H; W; C 'the CRLF file with only that line changed'

echo '== 4. a line its owner has edited is theirs: left exactly as found =='
doc $'\n' "$OLD We mean it." > "$R/CLAUDE.md"; cp "$R/CLAUDE.md" "$FIX/want"; old
H; W; C 'as its owner left it'

echo '== 5. a file without the line (the section a newer kit appends) is never written =='
doc $'\n' '- **Never name a model** — every spawn inherits the session.' > "$R/CLAUDE.md"; cp "$R/CLAUDE.md" "$FIX/want"; old
H; W; C 'as found'

echo '== 6. one line per heal at most, and a last line with no line end still has none after =='
{ doc $'\n' "$OLD"; printf '%s' "$OLD"; } > "$R/CLAUDE.md"
{ doc $'\n' "$NEW"; printf '%s' "$OLD"; } > "$FIX/want"; old
H; W; C 'the first copy changed, the second kept'
{ doc $'\n' "$NEW"; printf '%s' "$NEW"; } > "$FIX/want"
H; C 'the second copy changed too, still with no line end'

echo '== nothing left behind =='
printf '  temp files beside CLAUDE.md: %s\n' "$(ls -a "$R" | grep -c 'heal-tmp')"
printf '  files under the fake home: %s\n' "$(find "$HOME" -type f | wc -l | tr -d ' ')"
