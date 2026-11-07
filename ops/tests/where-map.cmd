# where-map: `polaris where` — the ≤15-line root map, read off ops/MAP.md and the folder guides and kept
# between two markers in the repo-root CLAUDE.md (ops/contracts/save-hops.md § 0.2, § 3.3, § 3.4). It is
# a PROJECTION, never a second source, so what is pinned here is the projection rule and the write
# discipline around it: items in their fixed order (Entry points → Modules → Deltas → guided folders, the
# first occurrence of a path wins), the 90-character cut, the overflow line, placement below the POLARIS
# END line, a second write that changes nothing, and a strip that gives back the exact file. CLAUDE.md is
# the owner's file, so no byte outside the markers may ever move — LF or CRLF. guide_purpose, the pinned
# reader, and brain_code_map are called directly, the libs sourced the way the CLI sources them.
# v2 (§ 12.3, § 14): a guide's purpose loses its own `<dir>/ — ` lead (once, only when text follows), so
# no reader prints the folder twice; a MAP row whose path is no longer TRACKED is no item; and drift
# prints one MAP STALE advisory per such row off that very parse — never a finding. Every other row the
# fixture's maps name is a real tracked file, so the older cases still test placement and the 13 cap.
#
# HERMETIC (the keys-drift pattern): one throwaway repo with its own tiny MAP.md, guides and CLAUDE.md —
# never this repo's, which change every sprint. One fixture, many states: ~0.7s of CLI start-up per call.
KIT="$(pwd)/kit/ops/polaris"
LIB="$(pwd)/kit/ops/lib"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p ops bin lib src/api src/ui src/components docs tools web
  printf 'base: main\n' > ops/CONVENTIONS.md
  for f in bin/run lib/new.sh src/main.ts src/cli.ts src/api/routes.ts src/ui/view.ts tools/gen.sh web/index.html \
           src/components/button.ts src/components/card.ts; do printf 'x\n' > "$f"; done
  # Case 7's fifteen entry points are real files too: a row whose path is not tracked is no item (§ 14.2).
  for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do printf 'x\n' > "f$i.sh"; done
  printf '# Docs — how-tos\n' > docs/README.md
  printf '# API readme — the guide speaks first\n' > src/api/README.md
  # A guide: the marker, its heading, a body — and the owner's own line below the block, never read.
  printf '<!-- polaris:guide -->\n# src/api/ — the HTTP handlers\n**Entry files:** `routes.ts`\n<!-- /polaris:guide -->\nMy own note, outside the block.\n' > src/api/CLAUDE.md
  # A folder CLAUDE.md that was there first gets the block APPENDED: the purpose is the first non-blank
  # line inside the block, leading #s and spaces removed.
  printf '# ui notes\n\n<!-- polaris:guide -->\n\n## src/ui/ — the screens\n<!-- /polaris:guide -->\n' > src/ui/CLAUDE.md
  # A CLAUDE.md without the marker is no guide.
  printf '# tools — no marker, so not a guide\n' > tools/CLAUDE.md
  cat > ops/MAP.md <<'EOF'
# MAP — fixture shop

## Stack
Bash and a little TypeScript.

## Entry points
| Path | What it is |
|---|---|
| `bin/run` | the launcher — starts everything |
| `bin/old-run` | a launcher this repo never had |
| src/main.ts | boots the app — reads the config, opens the store, mounts every view, then greets our café — the rest is cut |
src/cli.ts — the command-line entry, written in INIT's list form
<path — what it is>

## Modules
| Path | Purpose | Notes |
|---|---|---|
| src/api/ |  | a guided folder with no purpose of its own takes the guide's |
| docs/ | how-tos and decisions | |
| src/components/ | the widgets | every file in it has since moved to src/ui/ |
| bin/run | a second row for the launcher — the first occurrence wins | |

## Danger zones — agents NEVER edit these
- `vendor/` — third-party code, never a map item

## Deltas

- src/components/ — new: the widgets, before they moved  (T-0, 2026-10-31)

- lib/new.sh — new: the helper the first task added  (T-1, 2026-11-01)

- "quoted.sh: a delta that does not start with a path"  (T-2, 2026-11-02)

- docs/ — a later delta for a path already listed  (T-3, 2026-11-03)

## Unverified
- nothing yet
- tools/gen.sh — a delta done appended below a later heading still counts  (T-4, 2026-11-04)
EOF
  printf '<!-- POLARIS:BEGIN — managed block [kit fixture] -->\n# POLARIS fixture protocol\n<!-- POLARIS:END -->\n\n<!-- POLARIS:EFFICIENCY -->\n## Your own rules\nKeep it kind.\n' > CLAUDE.md
  git add -A; git commit -qm fixture
  # The widgets move into src/ui/: src/components/ holds no tracked file any more — only a leftover
  # nobody committed, so the folder is still on disk and still gone from the map.
  git mv src/components/button.ts src/ui/button.ts; git mv src/components/card.ts src/ui/card.ts
  git commit -qm 'the widgets move into src/ui/'
  printf 'cache\n' > src/components/.cache
  # An UNTRACKED guide is no guide (§ 0.1: a guide is a tracked file).
  mkdir -p scratch
  printf '<!-- polaris:guide -->\n# scratch/ — never committed\n<!-- /polaris:guide -->\n' > scratch/CLAUDE.md
) >/dev/null 2>&1
W() { ( cd "$R" && bash "$KIT" where "$@" ); printf 'rc=%s\n' "$?"; }
GP() { ( cd "$R"; PRIMARY="$R"; . "$LIB/core.sh"; . "$LIB/knowledge.sh"; guide_purpose "$1" ); printf 'rc=%s\n' "$?"; }
# GQ: guide_purpose bracketed, so a purpose that ends in a blank shows it (a golden holds no trailing blank).
GQ() { o="$( cd "$R"; PRIMARY="$R"; . "$LIB/core.sh"; . "$LIB/knowledge.sh"; guide_purpose "$1" )"; printf '[%s] rc=%s\n' "$o" "$?"; }
same() { if cmp -s "$R/CLAUDE.md" "$1"; then printf '%s: identical\n' "$2"; else printf '%s: DIFFERS\n' "$2"; fi; }

# 1. Preview: the block, markers included, rc 0, nothing written. Entry points (a backticked cell, the
#    cut at 90 characters with a multibyte one on the edge, INIT's list form; the unfilled placeholder
#    skipped) → Modules (an empty purpose on a guided folder takes the guide's; the repeat of bin/run
#    dropped) → Deltas (the trailer dropped; a quoted line and a repeat skipped; a Delta below a later
#    heading still counts) → the guided folder MAP.md never names. Danger zones, the untracked guide and
#    the CLAUDE.md with no marker are not items. Nor are two rows whose paths are not tracked (§ 14.2):
#    bin/old-run never existed, and src/components/ is still on disk but every file in it moved away.
#    A guide's own `src/api/ — ` lead is gone from its purpose (§ 12.3): the folder is never said twice.
W

# 1b. drift reads that SAME parse: one advisory per row the map just dropped, MAP order, once each
#     (src/components/ is listed twice), the path as MAP writes it. Never a finding: ONE --strict run
#     shows it all — the advisories print, the verdict stays "board clean" and the rc stays 0. No guide
#     here cites a missing path, so there is no GUIDE STALE line.
( cd "$R" && bash "$KIT" drift --strict 2>/dev/null ); printf 'strict-rc=%s\n' "$?"

# 2. The first --write lands directly below the POLARIS END line, after ONE blank line, and counts its items.
cp "$R/CLAUDE.md" "$FIX/before.md"
W --write
cat "$R/CLAUDE.md"

# 3. A second --write over an unchanged map says so and leaves the file alone.
cp "$R/CLAUDE.md" "$FIX/first.md"
W --write
same "$FIX/first.md" 'second write'

# 4. The map follows MAP.md: `done` appends a Delta, and the next --write replaces the block where it sits.
#    (web/ holds a tracked file, as a landed task's new folder does.)
printf -- '- web/ — the new front end  (T-5, 2026-11-05)\n' >> "$R/ops/MAP.md"
W --write
grep -n -e '^<!-- polaris:where -->$' -e 'web/' -e '^<!-- /polaris:where -->$' "$R/CLAUDE.md"

# 5. --strip takes the block, its markers and the ONE blank line above it: the owner's file, byte for byte.
W --strip
same "$FIX/before.md" 'after strip'

# 6. No block: --strip is silent, rc 0 (uninstall calls it blind).
W --strip

# 7. More than 13 items: the 13th line becomes the overflow line, so the body stays at 15 lines.
#    (f01.sh…f15.sh are tracked files: the cap counts the items that survive, and all of these do.)
{ printf '## Entry points\n'; for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do printf -- '- f%s.sh — file %s\n' "$i" "$i"; done; } > "$R/ops/MAP.md"
P="$( cd "$R" && bash "$KIT" where )"
printf '%s\n' "$P" | awk 'END { print NR " lines" }'
printf '%s\n' "$P" | tail -n 3

# 8. No managed block at all: the map goes to the end of the file after one blank line; strip gives it back.
printf '# Just my rules\n\nBe kind.\n' > "$R/CLAUDE.md"
cp "$R/CLAUDE.md" "$FIX/plain.md"
W --write
sed -n '1,6p' "$R/CLAUDE.md"
W --strip
same "$FIX/plain.md" 'after strip'

# 9. A CRLF CLAUDE.md (a Windows checkout): the block is written in CRLF too, a second write is
#    unchanged, and strip gives back every byte. Only counts are printed — a golden holds no CR.
printf '<!-- POLARIS:BEGIN — fixture -->\r\n# protocol\r\n<!-- POLARIS:END -->\r\n\r\n# Mine\r\n' > "$R/CLAUDE.md"
cp "$R/CLAUDE.md" "$FIX/crlf.md"
W --write
# (tr, not awk: on Git Bash awk drops the CR before it can be counted.)
printf 'CRLF: %s CRs over %s lines\n' "$(tr -cd '\r' < "$R/CLAUDE.md" | wc -c | tr -d ' ')" "$(wc -l < "$R/CLAUDE.md" | tr -d ' ')"
W --write
W --strip
same "$FIX/crlf.md" 'after strip'

# 10. No CLAUDE.md: --write says so and fails; --strip stays silent.
rm -f "$R/CLAUDE.md"
W --write
W --strip

# 11. guide_purpose: a guide's purpose line, its own `<dir>/ — ` lead dropped, rc 0 — and rc 1 with
#     nothing printed for no marker, an untracked file, the root and a folder with no CLAUDE.md at all.
GP src/api
GP src/ui
GP tools
GP scratch
GP .
GP docs

# 12. The brain's code map takes a folder's purpose from its guide first, then from its README heading.
#     brain_code_map is called directly: a whole `brain` build costs ~9s here for nothing this golden asks.
( cd "$R"; PRIMARY="$R"; OPS="$R/ops"; . "$LIB/core.sh"; . "$LIB/knowledge.sh"; brain_code_map ) 2>/dev/null \
  | awk '/^## / { d = $2 } /^- purpose: / { print d " " substr($0, 3) }'

# 13. The lead goes ONCE, byte-exact, and only when something non-blank follows it — a guide headed with
#     its folder alone, or with nothing after the dash, keeps its line as is — and only the guide's OWN
#     folder is a lead: naming another folder is the guide's own words (§ 12.3). Four tracked guides,
#     added last so no case above sees them.
( cd "$R" && mkdir -p g/bare g/twice g/blank g/other \
  && printf '<!-- polaris:guide -->\n# g/bare/\n<!-- /polaris:guide -->\n' > g/bare/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n# g/twice/ — g/twice/ — said twice\n<!-- /polaris:guide -->\n' > g/twice/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n## g/blank/ —  \nThe body.\n<!-- /polaris:guide -->\n' > g/blank/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n# src/api/ — not this folder\n<!-- /polaris:guide -->\n' > g/other/CLAUDE.md \
  && git add g && git commit -qm 'four more guides' ) >/dev/null 2>&1
GQ g/bare
GQ g/twice
GQ g/blank
GQ g/other
