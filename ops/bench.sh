#!/usr/bin/env bash
# POLARIS v5 — startup + lookup benchmark.  bash ops/bench.sh [--json]
#
# WHY THIS EXISTS
#   Every performance claim in this kit used to be a comment written from memory, and several of
#   them were wrong by 5x when finally measured (2026-07-25: `find` was documented at 0.70s and ran
#   at 1.1-2.0s; `hostname` was documented at 0.07s and cost 0.52s). A number nobody can reproduce
#   is a number nobody should trust. Run this before and after any change to the startup path and
#   paste the delta — that is the whole contract.
#
# WHAT IT MEASURES
#   The fixed tax: what every command pays before it does any work. Not the test suite (that is
#   `qa`, and it is measured by .polaris/last-suite-seconds).
#
# HOW TO READ IT
#   MIN, not mean. These are wall-clock timings on a machine that is also running an editor, a
#   shell and possibly parallel builders; the mean measures your background load, the minimum
#   measures the code. Runs are cheap, so it takes the best of N.
set -u

RUNS="${POLARIS_BENCH_RUNS:-5}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
P="ops/polaris"
[ -x "$P" ] || P="bash ops/polaris"

ms() { # ms <label> <command...> — best-of-$RUNS wall clock, in milliseconds
  local label="$1"; shift
  local i s e d min=99999999
  for i in $(seq 1 "$RUNS"); do
    s=$(date +%s%N)
    "$@" >/dev/null 2>&1
    e=$(date +%s%N)
    d=$(( (e - s) / 1000000 ))
    [ "$d" -lt "$min" ] && min="$d"
  done
  printf '%-28s %6sms\n' "$label" "$min"
}

echo "POLARIS bench — $(sed -n 's/^version: *//p' ops/VERSION 2>/dev/null | head -1) · best of $RUNS · $(git rev-parse --short HEAD 2>/dev/null)"
echo "repo: $(git ls-files 2>/dev/null | wc -l | tr -d ' ') tracked files"
echo

# --- the OTHER axis: bytes, not milliseconds -----------------------------------------------
# Wall clock is only half the cost of running agents, and it was the half this file measured. The
# other half is what every context PAYS TO EXIST: the router, the role file, and — much larger than
# either — the name+description of every skill/agent/command definition installed under ~/.claude,
# injected whether or not anything invokes them. A conductor run pays that 6-8 times.
# `bench.sh --context` prints it so a claim about token savings can be reproduced, not asserted.
if [ "${1:-}" = "--context" ]; then
  echo "-- what every context pays before any work (bytes → ~tokens at 4 B/token) --"
  ctx_b() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }
  R="$(ctx_b CLAUDE.md)"; K="$(ctx_b kit/CLAUDE.md)"
  [ "$K" -gt 0 ] && R="$K"
  printf '  %-34s %8s B  %7s tok\n' "CLAUDE.md (every subagent too)" "$R" "$((R / 4))"
  for f in ops/roles/*.md; do
    [ -f "$f" ] || continue
    b="$(ctx_b "$f")"
    printf '  %-34s %8s B  %7s tok\n' "  $(basename "$f")" "$b" "$((b / 4))"
  done
  echo
  echo "-- installed definitions (the passenger) --"
  bash ops/polaris slim 2>/dev/null | sed -n '/MACHINERY/,/total paid/p' | sed 's/^/  /'
  echo
  echo "  Recover the machinery rows:  bash ops/polaris slim --apply   (reversible: --restore)"
  exit 0
fi

echo "-- the fixed tax (paid by every command) --"
ms "help (no env, no modules)"  bash ops/polaris help
ms "board-fm"                   bash ops/polaris board-fm
ms "rules"                      bash ops/polaris rules
ms "metrics"                    bash ops/polaris metrics
ms "_guard (per Edit/Write)"    bash ops/polaris _guard ops/MAP.md -

echo
echo "-- lookup (the 1-hop 'where is X') --"
ms "find <symbol>"              bash ops/polaris find cmd_verify
ms "find -t <text>"             bash ops/polaris find -t files_owned
ms "find --api"                 bash ops/polaris find --api 'ops/*'

echo
echo "-- baseline: what the shell itself costs here --"
ms "bash -c true"               bash -c true
ms "git rev-parse"              git rev-parse --git-common-dir
ms "grep -rn (whole repo)"      grep -rn cmd_verify --include=*.sh .

echo
echo "-- zero-LLM acceptance --"
# ONE run: `check` is seconds, not milliseconds, and it is deterministic — repeating it five times
# measures nothing new and turns a 20s bench into a 2min one.
RUNS=1 ms "check (all goldens)"  bash ops/polaris check

echo
echo "Suite timings are NOT here — they are stamped by qa into .polaris/last-suite-seconds:"
if [ -f .polaris/last-suite-seconds ]; then
  echo "  last qa: $(cut -d' ' -f1 < .polaris/last-suite-seconds)s"
else
  echo "  last qa: never run"
fi
