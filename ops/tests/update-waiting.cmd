# update-waiting: `update --auto` stops being silent once an update has waited a day (ops/contracts/
# tune.md § 5, § 6). When it skips — work in flight (step 5) or edits inside the kit's own files
# (step 6) — it records when the update to <latest> first waited in .polaris/update-waiting
# (`<epoch><TAB><latest>`, rewritten only when absent or naming another version). Under a day:
# today's behaviour, byte for byte (`skipped: <why>` under --say, silence without). From 24 h on:
# ONE line in both modes, naming what holds it and the step that frees it — the § 5 table, first
# reason that applies. It still never applies under work in flight.
#
# HERMETIC: a throwaway repo under mktemp -d with its own board, a fake HOME/USERPROFILE, and a
# channel cache dated TODAY naming a newer minor version, so update_latest never reaches the network.
# The kit's own version moves with every release, so it prints here as <cur>. Epochs are set
# relative to now, whole days plus a margin, so no line depends on the clock's second.
KIT="$(pwd)/kit/ops/polaris"; KVER="$(pwd)/kit/ops/VERSION"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT
CUR="$(sed -n 's/^version: *//p' kit/ops/VERSION | tr -d ' \r')"
LATEST="${CUR%%.*}.999.0"
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src ops/lib; echo x > src/a.txt; printf '# the kit, as installed\n' > ops/polaris
  cp "$KVER" ops/VERSION
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$FIX/repo"
L="$(git rev-parse --git-common-dir)/polaris-locks"
mkdir -p .polaris
printf 'checked: %s\nlatest: %s\n' "$(date +%Y-%m-%d)" "$LATEST" > .polaris/update-cache
NOW="$(date +%s)"
W=.polaris/update-waiting
U() { # U <label> — one --auto with --say, one without; versions shown as <cur> / <latest>
  a="$(bash "$KIT" update --auto --say 2>&1)"; b="$(bash "$KIT" update --auto 2>&1)"
  printf '%s\n   --say: %s\n   bare:  %s\n' "$1" "${a:-(silent)}" "${b:-(silent)}" | sed "s/$CUR/<cur>/g; s/$LATEST/<latest>/g"
}
OLD() { printf '%s\t%s\n' "$(( NOW - ${1} * 86400 - 600 ))" "${2:-$LATEST}" > "$W"; }   # OLD <days> [version]

echo '--- 1. a card building, first seen now: under a day, today'"'"'s skip — and the first wait is recorded'
printf -- '---\nid: T-A1\npoints: 1\nstatus: active\n---\n' > ops/board/active/T-A1.md
U 'active, fresh'
awk -F'\t' -v n="$NOW" -v l="$LATEST" '{ print "update-waiting: " (($1 >= n - 5 && $1 <= n + 60) ? "now" : "WRONG") " · " ($2 == l ? "<latest>" : "WRONG") " · fields " NF }' "$W"

echo '--- 2. the same wait, over a day old: the one line, in both modes'
OLD 2; U 'active, 2 days'

echo '--- 3. a wait recorded for another version starts over: under a day again'
OLD 5 6.0.1; U 'active, another version'
awk -F'\t' -v l="$LATEST" '{ print "update-waiting now names: " ($2 == l ? "<latest>" : $2) }' "$W"
rm -f ops/board/active/T-A1.md

echo '--- 4. the rest of the table, each alone, each waiting 3 days'
printf -- '---\nid: T-V1\npoints: 1\nstatus: review\n---\n' > ops/board/review/T-V1.md
printf -- '---\nid: T-V2\npoints: 1\nstatus: review\n---\n' > ops/board/review/T-V2.md
printf '{"ts":%s,"ev":"handoff","id":"T-V1","who":"a@b"}\n{"ts":%s,"ev":"handoff","id":"T-V2","who":"a@b"}\n' \
  "$(( NOW - 4 * 86400 - 600 ))" "$(( NOW - 1 * 86400 ))" >> ops/board/EVENTS.ndjson
OLD 3; U 'review'
rm -f ops/board/review/T-V*.md
mkdir -p "$L/T-K1"; OLD 3; U 'lock'; rm -rf "$L/T-K1"
mkdir -p "$L/.int-lease"; OLD 3; U 'lease'; rm -rf "$L/.int-lease"
mkdir -p .polaris/bg/fixture-job; echo "$$" > .polaris/bg/fixture-job/pid
OLD 3; U 'bg job'; rm -rf .polaris/bg/fixture-job
printf '# an edit inside the kit\n' >> ops/polaris
OLD 3; U 'kit dirt'
