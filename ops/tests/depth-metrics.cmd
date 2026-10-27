# depth-metrics — T-199 (ops/contracts/test-depth.md § 6): `polaris metrics` gains two lines,
# appended LAST — suite minutes skipped this sprint (by depth) and the per-run build / land /
# suite / finish split — read from .polaris/decisions.ndjson (T-198) and EVENTS.ndjson, sprint-scoped
# by SPRINT.md line 1's `dates:`. With no log both lines still print (n/a, -).
#
# HERMETIC: a throwaway fixture repo under mktemp -d, run from INSIDE it — polaris anchors to the
# fixture's own primary — so no live telemetry, board or decisions log can ever red this golden, and
# running this twice from ANY state is byte-identical. The sprint cutoff epoch is derived with the
# SAME `date -d` / `date -j` fallback the implementation uses, so the fixture's row timestamps are
# always correctly placed on either side of the cutoff, on any machine's timezone.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  echo x > a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"

echo '== 1. no decisions.ndjson, no EVENTS.ndjson — both lines still print (n/a, -) =='
bash "$KIT" metrics 2>&1 | tail -3

# A sprint cutoff, and its epoch computed the SAME way cmd_metrics computes it, so every seeded row
# below lands unambiguously on one side of the line regardless of the host's timezone.
SDATE=2026-01-10
EPOCH="$(date -d "$SDATE" +%s 2>/dev/null || date -j -f %Y-%m-%d "$SDATE" +%s)"
mkdir -p ops .polaris
printf '# SPRINT 1 — test   dates: %s\n' "$SDATE" > ops/SPRINT.md

# EVENTS.ndjson: one in-sprint task (claim→handoff 600s, handoff→done 300s) and one PRE-sprint task
# (claim→handoff 9000s, handoff→done 1000s) that must be excluded by the sprint cutoff.
A=$((EPOCH+100)); B=$((A+600)); C=$((B+300))
P=$((EPOCH-10000)); Q=$((P+9000)); S=$((Q+1000))
{
  printf '{"ts":%s,"ev":"claim","id":"T-A","who":"t","note":""}\n' "$A"
  printf '{"ts":%s,"ev":"handoff","id":"T-A","who":"t","note":""}\n' "$B"
  printf '{"ts":%s,"ev":"done","id":"T-A","who":"t","note":""}\n' "$C"
  printf '{"ts":%s,"ev":"claim","id":"T-P","who":"t","note":""}\n' "$P"
  printf '{"ts":%s,"ev":"handoff","id":"T-P","who":"t","note":""}\n' "$Q"
  printf '{"ts":%s,"ev":"done","id":"T-P","who":"t","note":""}\n' "$S"
} > ops/board/EVENTS.ndjson

# decisions.ndjson: two FULL rows (1200s, 1800s ⇒ median 1500s), one row at each of none/look/scoped,
# two finish rows, all in-sprint — plus one PRE-sprint full row that must be excluded.
{
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"test_depth","depth":"full","why":"w","paths":[],"secs":1200,"rc":0}\n' "$((EPOCH+50))"
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"test_depth","depth":"full","why":"w","paths":[],"secs":1800,"rc":0}\n' "$((EPOCH+60))"
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"test_depth","depth":"none","why":"w","paths":[],"secs":5,"rc":0}\n' "$((EPOCH+70))"
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"test_depth","depth":"look","why":"w","paths":[],"secs":200,"rc":0}\n' "$((EPOCH+80))"
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"test_depth","depth":"scoped","why":"w","paths":[],"secs":400,"rc":0}\n' "$((EPOCH+90))"
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"finish","secs":30,"rc":0}\n' "$((EPOCH+95))"
  printf '{"ts":%s,"plan":"","task":"T-A","kind":"finish","secs":50,"rc":0}\n' "$((EPOCH+96))"
  printf '{"ts":%s,"plan":"","task":"T-P","kind":"test_depth","depth":"full","why":"w","paths":[],"secs":999999,"rc":0}\n' "$((EPOCH-100))"
} > .polaris/decisions.ndjson

echo '== 2. seeded decisions.ndjson + EVENTS.ndjson, sprint-scoped =='
bash "$KIT" metrics 2>&1 | tail -3

echo '== 3. existing metrics output above the new lines is unchanged — same run, full output =='
bash "$KIT" metrics 2>&1
