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
HERE="$PWD"   # the caller's folder: `hops <dir>` reads a relative <dir> from here, not from $ROOT
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

# --- `bench.sh hops [--dry-run] <dir>`: five lookups counted in turns (ops/contracts/save-hops.md § 10)
# A better layout score is a promise; fewer turns for a real agent is the saving. This asks five
# fixed "where is X" questions on the practice shop, one fresh headless session each, and prints how
# many turns each answer took. <dir> missing → hops_fixture builds the shop there first; an existing
# <dir> is asked as it is. The conductor runs it once on the shop and once on a copy after a tidy
# pass, and the after total must be lower. A real call spends tokens on five sessions and can take
# 15 minutes, so it is the conductor's step alone, through `bash ops/polaris bg run`. Tests and
# verify: lines use --dry-run only: it prints the questions and the exact command lines, builds
# nothing and runs nothing. To prove the real path without tokens, put a stand-in `claude` first on
# PATH that prints a canned `--output-format json` reply: PATH is the only seam, so what runs is the
# § 10 line itself. stdout is exactly q<n><TAB><num_turns><TAB><first line of the answer> per
# question (a failed or timed-out run: q<n><TAB>-<TAB>error), then total<TAB><sum>. Any failed run
# makes the total `-` and rc 1: a sum with a hole in it compares to nothing. Why it failed → stderr.
if [ "${1:-}" = "hops" ]; then
  shift
  dry=0; dir=""; bad=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1 ;;
      -*) bad="$1" ;;
      *) if [ -z "$dir" ]; then dir="$1"; else bad="$1"; fi ;;
    esac
    shift
  done
  if [ -z "$dir" ] || [ -n "$bad" ]; then
    printf '⛔ usage: bash ops/bench.sh hops [--dry-run] <dir>%s\n' "${bad:+ — not understood: $bad}" >&2
    exit 2
  fi
  case "$dir" in /*|[A-Za-z]:[\\/]*) ;; *) dir="$HERE/$dir" ;; esac
  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    printf '⛔ %s is a file — name a folder, or a missing one to build the practice shop in\n' "$dir" >&2
    exit 2
  fi
  QS=("Where is the checkout cart total computed?" "Which function uploads a profile avatar?"
      "Where does search debounce its input?" "Where is an invoice number formatted?"
      "Which test covers the checkout coupon rule?")
  tab=$'\t'; cr=$'\r'
  if [ "$dry" = 1 ]; then
    echo "hop benchmark, dry run: nothing is built and nothing is asked"
    if [ -d "$dir" ]; then s="there, so a real run asks inside it as it is"; else s="missing, so a real run builds the practice shop there first"; fi
    printf 'folder\t%s\t%s\n' "$dir" "$s"
    n=0; for q in "${QS[@]}"; do n=$((n + 1)); printf 'q%s\t%s\n' "$n" "$q"; done
    echo "a real run asks them inside that folder, one session each, with these commands:"
  else
    # `-c pass` proves a REAL interpreter: the Windows Store python3 stub sits on PATH and only prints an ad.
    PY=""; python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; } || true
    [ -n "$PY" ] || { echo "⛔ the hop benchmark needs python3 (or python) on PATH to read the answers" >&2; exit 1; }
    if [ ! -e "$dir" ]; then
      FX="$ROOT/ops/lib/selftest/hops.sh"
      [ -f "$FX" ] || { printf '⛔ the practice shop builder is missing: %s\n' "$FX" >&2; exit 1; }
      printf 'building the practice shop in %s\n' "$dir" >&2
      bash -c '. "$1" && hops_fixture "$2"' bench "$FX" "$dir" || exit 1
    fi
    T="$(mktemp -d)" || exit 1
    trap 'rm -rf "$T"' EXIT
    printf 'asking %s questions in %s, one fresh session each (up to 3 minutes apiece)\n' "${#QS[@]}" "$dir" >&2
  fi
  n=0; sum=0; rc=0
  for q in "${QS[@]}"; do
    n=$((n + 1))
    # The § 10 command, in ONE place: the dry run prints exactly these words, the real run executes them.
    set -- env -u CLAUDECODE timeout 180 claude -p "$q Answer with path:line only." --output-format json --max-turns 15
    if [ "$dry" = 1 ]; then printf '%s "%s" %s\n' "${*:1:7}" "$8" "${*:9}"; continue; fi
    ( cd "$dir" && exec "$@" ) </dev/null >"$T/out" 2>"$T/err"
    r=$?
    # The reply → "<num_turns><TAB><first answer line>" and rc 0, or "-<TAB><why>" and rc 1. A list of
    # messages (the json shape of other CLI versions) is read by its last "result" entry.
    "$PY" - "$T/out" >"$T/res" 2>/dev/null <<'PY'
import json, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
try:
    raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
except OSError:
    raw = ""
try:
    d = json.loads(raw)
except ValueError:
    d = None
if isinstance(d, list):
    d = ([m for m in d if isinstance(m, dict) and m.get("type") == "result"] or [None])[-1]
if not isinstance(d, dict):
    print("-\t" + ("the reply was not JSON" if raw.strip() else ""))
    sys.exit(1)
t = d.get("num_turns")
lines = str(d.get("result") or "").strip().splitlines()
a = lines[0].replace("\t", " ").strip() if lines else ""
if type(t) is int and not d.get("is_error") and d.get("subtype", "success") == "success":
    print("%d\t%s" % (t, a or "-"))
    sys.exit(0)
n = " (after %d turn%s)" % (t, "" if t == 1 else "s") if type(t) is int else ""
print("-\t%s%s" % (a or d.get("subtype") or "no answer", n))
sys.exit(1)
PY
    p=$?
    res=""; IFS= read -r res <"$T/res"; res="${res%"$cr"}"
    if [ "$r" = 0 ] && [ "$p" = 0 ]; then
      printf 'q%s\t%s\n' "$n" "$res"
      sum=$((sum + ${res%%"$tab"*}))
    else
      printf 'q%s\t-\terror\n' "$n"
      rc=1
      why=""; [ "$p" = 0 ] || why="${res#*"$tab"}"
      [ "$r" = 124 ] && why="no answer within 180 s"
      [ -n "$why" ] || { IFS= read -r why <"$T/err"; why="${why%"$cr"}"; }
      printf 'q%s did not answer, exit %s: %s\n' "$n" "$r" "${why:-no reply}" >&2
    fi
  done
  [ "$dry" = 1 ] && exit 0
  if [ "$rc" = 0 ]; then printf 'total\t%s\n' "$sum"; else printf 'total\t-\n'; fi
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
