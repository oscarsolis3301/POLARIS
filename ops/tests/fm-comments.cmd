# A value or a list item that is ONLY a comment reads as empty, the way YAML means it
# (ops/contracts/frontmatter-lists.md v1.1, T-269). fm_get and fm_list used to trim the leading
# blanks first and only then look for " #", so TASK.md's own guidance (`files_owned:   # ONLY paths …`,
# `  -   # exact path …`, `contract:   # ops/contracts/<name>.md …`) came back as an owned path, a
# contract and a verify line. Run against kit/ops/lib/core.sh itself, on throwaway files. Pinned:
#   1. fm_get: a comment-only value is empty, after spaces or a tab; `value  # a note` keeps `value`
#   2. fm_list: a comment-only scalar and comment-only items drop, `- # x` and `-   # x` alike; every
#      real item stays: block items, a flow list, a scalar, each with its trailing comment stripped
#   3. a `#` that does not start the value reads exactly as in v1: a " #" still begins a comment there
#      (`Fix #12` reads `Fix`, as it always has), and a `#` inside a word stays (`Fix#12`,
#      `src/issue#12.txt`)
#   4. a CRLF copy of the same file reads the same, line for line
#   5. the real TASK.md, copied untouched: no files_owned, surface, verify, approved or context_files
#      items, and an empty contract
# Every reader call is a fork, so a list is joined by parameter expansion, not a pipe through tr.
. kit/ops/lib/core.sh
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
printf -- '---\nid: T-C\nnote:   # a note\ntabnote:\t# a tab note\nvalue: value  # a note\ntitle: Fix #12\ntight: Fix#12\nowns:   # a note on the key\n  - src/a.txt\n  -   # a note between items\n  - # a tight note\n  - src/b.txt  # a trailing comment\n  - src/issue#12.txt\n  - src/c.txt\nnotes_only:\n  -   # a note\n  - # a tight note\nflow: [a, b]  # a trailing comment\nempty: []   # nothing yet\n---\n## Notes\nowns: not frontmatter\n' > "$F/c.md"
awk '{ printf "%s\r\n", $0 }' "$F/c.md" > "$F/crlf.md"
cp kit/ops/templates/TASK.md "$F/TASK.md"
NL='
'
g() { printf 'fm_get %s: [%s]\n' "$1" "$(fm_get "$1" "$2")"; }
l() { local x; x="$(fm_list "$1" "$2")"; printf 'fm_list %s: [%s]\n' "$1" "${x//$NL/|}"; }
probe() { # probe <file> — sections 1 to 3 over one fixture
  echo "== 1. fm_get"
  g note "$1"; g tabnote "$1"; g value "$1"
  echo "== 2. fm_list"
  l note "$1"; l notes_only "$1"; l owns "$1"; l flow "$1"; l value "$1"; l empty "$1"
  echo "== 3. a # that does not start the value"
  g title "$1"; g tight "$1"
}
probe "$F/c.md" > "$F/lf.out"
probe "$F/crlf.md" > "$F/crlf.out"
cat "$F/lf.out"
echo "== 4. CRLF"
cmp -s "$F/lf.out" "$F/crlf.out" && echo "the CRLF copy reads the same: yes" || echo "the CRLF copy reads the same: NO"
echo "== 5. the real TASK.md, untouched"
for k in files_owned surface verify approved context_files; do l "$k" "$F/TASK.md"; done
g contract "$F/TASK.md"
