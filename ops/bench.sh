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

ms() { # ms <label> <command...> — best-of-$RUNS wall clock, in milliseconds; stdin from $BENCH_IN if set
  local label="$1"; shift
  local i s e d min=99999999
  for i in $(seq 1 "$RUNS"); do
    s=$(date +%s%N)
    if [ -n "${BENCH_IN:-}" ]; then "$@" <"$BENCH_IN" >/dev/null 2>&1; else "$@" >/dev/null 2>&1; fi
    e=$(date +%s%N)
    d=$(( (e - s) / 1000000 ))
    [ "$d" -lt "$min" ] && min="$d"
  done
  printf '%-28s %6sms\n' "$label" "$min"
}

# --- `bench.sh guards`: the per-call hooks against their budgets (ops/contracts/speed.md § 1) -----
# A PreToolUse hook runs before EVERY tool call, and a hook that overruns its timeout FAILS OPEN — so
# a slow guard is a guard that is not there (model-guard timed out 6 times in one fan-out and let
# every one of those calls through). Budgets are relative to the machine's floor, `bash -c true`:
# Windows pays ~10x Linux just to start bash, and a budget is for the hook's own work, not for that.
# Each hook gets its common-path input on stdin (ms reads it from $BENCH_IN) and is timed from the
# primary checkout, so the numbers are what a real session pays.
# HERMETIC: HOME is a mktemp -d, so model-guard's state file is a fixture and the real
# ~/.claude/polaris/model-state is never touched; POLARIS_AWAKE_HOME sits inside it, so awake-hook
# never reaches the real registry, and `start` is the subcommand that never spawns the daemon.
# stdout is exactly the TAB-separated lines below and nothing else; rc 1 iff one of them says OVER.
if [ "${1:-}" = "guards" ]; then
  HK=ops/hooks; [ -d kit/ops/hooks ] && HK=kit/ops/hooks   # the kit repo times its own source
  HK="$(cd "$HK" 2>/dev/null && pwd)" || exit 1
  PRIM="$(git rev-parse --show-toplevel 2>/dev/null)"; PRIM="${PRIM%%/.polaris/wt/*}"
  FIX="$(mktemp -d)" || exit 1
  trap 'rm -rf "$FIX"' EXIT
  export HOME="$FIX" POLARIS_AWAKE_HOME="$FIX/awake"
  unset CLAUDE_PROJECT_DIR CLAUDE_PID
  mkdir -p "$FIX/.claude/polaris/model-state" "$FIX/repo/ops/board" "$FIX/repo/.polaris/wt/T-000"
  # Any id the ban does not deny reads as allowed — so the fixture names no model at all.
  printf 'bench-allowed\n' > "$FIX/.claude/polaris/model-state/bench"
  : > "$FIX/t.jsonl"
  J='{"session_id":"bench","transcript_path":"'"$FIX/t.jsonl"'","hook_event_name":'
  printf '%s' "$J"'"PreToolUse","cwd":"'"$FIX"'","tool_name":"Read","tool_input":{"file_path":"'"$FIX/x.txt"'"}}' > "$FIX/mg.json"
  printf '%s' "$J"'"PreToolUse","cwd":"'"$PRIM"'","tool_name":"Edit","tool_input":{"file_path":"'"$PRIM/docs/bench-probe.md"'","old_string":"a","new_string":"b"}}' > "$FIX/og.json"
  printf '%s' "$J"'"PreToolUse","cwd":"'"$PRIM"'","tool_name":"Bash","tool_input":{"command":"git status"}}' > "$FIX/sh.json"
  printf '%s' "$J"'"SessionStart","cwd":"'"$FIX/repo/.polaris/wt/T-000"'","source":"startup"}' > "$FIX/aw.json"
  printf '%s' "$J"'"Stop","cwd":"'"$FIX/repo"'","stop_hook_active":false}' > "$FIX/hh.json"
  FL="$(ms floor bash -c true)"; FL="${FL%ms}"; FL="${FL##* }"
  printf 'floor\t%s\n' "$FL"
  rc=0
  # name | budget over the floor (- = timed, no budget yet) | hook | input | subcommand
  for row in "model-guard|300|model-guard.sh|mg.json|" "ownership-guard|600|ownership-guard.sh|og.json|" \
             "checkout-guard|150|checkout-guard.sh|sh.json|" "readonly-allow|150|readonly-allow.sh|sh.json|" \
             "awake-hook|-|awake-hook.sh|aw.json|start" "handover-hook|-|handover-hook.sh|hh.json|stop"; do
    IFS='|' read -r n b h j a <<EOF
$row
EOF
    t="$(cd "${PRIM:-.}" 2>/dev/null; BENCH_IN="$FIX/$j" ms "$n" bash "$HK/$h" $a)"; t="${t%ms}"; t="${t##* }"
    if [ "$b" = - ]; then
      printf '%s\t%s\t-\t-\n' "$n" "$t"
    else
      b=$((FL + b)); v=ok
      [ "$t" -gt "$b" ] && { v=OVER; rc=1; }
      printf '%s\t%s\t%s\t%s\n' "$n" "$t" "$b" "$v"
    fi
  done
  exit "$rc"
fi

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
