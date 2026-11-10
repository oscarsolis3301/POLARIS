#!/usr/bin/env bash
# tools/fnmove.sh — prove a move-only refactor moved functions and changed none of them
# (ops/contracts/minutes.md § 3.3). This repo's own tool: it never ships in the kit.
#
#   bash tools/fnmove.sh <rev>:<path>... -- <path>...
#
# The left side is read with `git show`, the right side from disk. A function is a column-0 line
# matching ^[A-Za-z_][A-Za-z0-9_]*\(\) *\{ ; its body runs from that line through the first later
# column-0 line that is exactly `}` — or is that line alone when it ends in `; }` (a one-liner).
# Comments above a function are not part of it. One awk per side emits name<TAB>body (newlines as
# the two characters \n), both lists are sorted, then compared as multisets.
# bash 3.2-safe: no arrays, no `case` inside $(...), no ${v,,}.
usage() { echo "usage: bash tools/fnmove.sh <rev>:<path>... -- <path>..."; exit 2; }

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT

# Left side: every <rev>:<path> before `--`, one file each, read by git.
i=0
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  i=$((i+1))
  git show "$1" > "$tmp/l.$i" 2>/dev/null || { echo "fnmove: cannot read $1"; exit 2; }
  shift
done
[ "${1:-}" = "--" ] || usage
shift
[ "$i" -gt 0 ] && [ $# -gt 0 ] || usage
for p in "$@"; do [ -f "$p" ] || { echo "fnmove: no such file $p"; exit 2; }; done

# shellcheck disable=SC2016
prog='
FNR == 1 { infn = 0 }
infn { body = body "\\n" $0; if ($0 == "}") { print name "\t" body; infn = 0 }; next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {
  name = $0; sub(/\(.*/, "", name)
  if ($0 ~ /; *\} *$/) { print name "\t" $0; next }
  infn = 1; body = $0; next
}'
LC_ALL=C awk "$prog" "$tmp"/l.* | LC_ALL=C sort > "$tmp/left"
LC_ALL=C awk "$prog" "$@" | LC_ALL=C sort > "$tmp/right"

if cmp -s "$tmp/left" "$tmp/right"; then
  n="$(wc -l < "$tmp/left" | tr -d ' ')"
  h="$(git hash-object "$tmp/left" | cut -c1-7)"
  echo "fnmove: $n functions, same names and bodies (list $h)"
  exit 0
fi
echo "fnmove: DIFFERS"
{ LC_ALL=C comm -23 "$tmp/left" "$tmp/right" | cut -f1 | sed 's/^/- /'
  LC_ALL=C comm -13 "$tmp/left" "$tmp/right" | cut -f1 | sed 's/^/+ /'
} | LC_ALL=C sort
exit 1
