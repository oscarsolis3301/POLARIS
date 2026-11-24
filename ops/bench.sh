#!/usr/bin/env bash
# POLARIS v5 — startup + lookup benchmark.  bash ops/bench.sh [--json | --context | --flow | guards | hops]
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

# --- `bench.sh --flow [--list] [--profile] [--runs <n>]`: a small change, begin → wrap, per phase ----
# (ops/contracts/walk-away.md § 7). Before anyone builds a faster lane for one-point changes, this
# says where the seconds of the ordinary one go. HERMETIC: a mktemp -d repo with HOME/USERPROFILE,
# POLARIS_AWAKE_HOME and POLARIS_HEAVY_DIR inside it, `test: true`, `lint: true`, `typecheck: true`.
# Each run builds a fresh repo and takes two 1-point cards — a look card (one .css file) and a ui card
# (one .html file) — through the commands `begin` and `wrap` run, one CLI call per phase, so every
# phase has its own wall clock. The edit itself is not timed. Pass `self` is the default landing:
# handoff carries the landing tail, split at its `continuing into land` line (land = land+seal+done).
# Pass `integrator` runs land, seal and done as the integrator does, one call each. A phase's number
# is its best of <n> runs (default 3) of the two cards' mean; `flow:` is the best run's mean
# begin+wrap for one card. stdout is `pass<TAB><name>`, then one `phase<TAB>seconds` line per phase,
# then `flow: begin+wrap <s>s (best of <n>)`, per pass. The per-card totals go to stderr. --list
# prints the pass and phase names and runs nothing (the verify proof). --profile then runs one more
# cycle with `PS4='+ $EPOCHREALTIME <file>:<line> '` xtrace on the slowest phase and prints its 15
# costliest lines. Measure only when `bash ops/polaris bg status` shows no heavy job.
_flow_phases() { # _flow_phases <pass> — the phase names of one pass, space-separated
  case "$1" in
    self) echo "new triage claim pack handoff land next finish" ;;
    *)    echo "new triage claim pack handoff land seal done next finish" ;;
  esac
}

_flow_now() { # _flow_now — wall clock in seconds with a fraction; bash 3.2 falls back to date
  if [ -n "${EPOCHREALTIME:-}" ]; then printf '%s\n' "${EPOCHREALTIME/,/.}"; return 0; fi
  local n; n="$(date +%s%N)"
  case "$n" in *N) date +%s ;; *) printf '%s.%s\n' "${n%?????????}" "${n#"${n%?????????}"}" ;; esac
}

_flow_rec() { # _flow_rec <phase> <t0> <t1> — one row into the current card's timing file
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$_FLOW_TSV"
}

_flow_run() { # _flow_run <phase> <dir> <cmd…> — one timed CLI call; output → the log; rc is the call's
  local ph="$1" dir="$2" t0 t1 rc=0; shift 2
  printf '== %s: %s\n' "$ph" "$*" >>"$_FLOW_LOG"
  t0="$(_flow_now)"
  if [ "$ph" = "${_FLOW_TRACE:-}" ]; then
    _flow_traced "$dir" "$@" || rc=$?
  else
    ( cd "$dir" && "$@" ) >>"$_FLOW_LOG" 2>&1 </dev/null || rc=$?
  fi
  t1="$(_flow_now)"
  _flow_rec "$ph" "$t0" "$t1"
  return "$rc"
}

_flow_traced() { # _flow_traced <dir> <cmd…> — the call under xtrace, every child bash too, into $_FLOW_XT
  ( cd "$1" || exit 1; shift
    exec 9>"$_FLOW_XT"
    export BASH_XTRACEFD=9 PS4='+ $EPOCHREALTIME ${BASH_SOURCE##*/}:$LINENO '
    set -x; export SHELLOPTS
    "$@" ) >>"$_FLOW_LOG" 2>&1 </dev/null
}

_flow_repo() { # _flow_repo <dir> <landing> — the throwaway repo, board and two drafts
  local R="$1"
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R" || return 1
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$_FLOW_KIT" init-board
  { printf 'test: true\nlint: true\ntypecheck: true\n'
    [ "$2" = integrator ] && printf 'landing: integrator\n'; } > ops/CONVENTIONS.md
  printf '# SPRINT 1 — flow\n' > ops/SPRINT.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  mkdir -p .polaris/drafts
  _flow_draft 'a look change' src/a.css > .polaris/drafts/look.md
  _flow_draft 'a ui change' src/b.html > .polaris/drafts/ui.md
}

_flow_draft() { # _flow_draft <title> <path> — a 1-point, risk: normal draft owning one file
  printf -- '---\ntitle: %s\nplan: flow\npoints: 1\nrisk: normal\nfiles_owned:\n  - %s\ndepends_on: []\ncontract: ops/contracts/fix.md\nverify: []\n---\n## Why\nbench\n' "$1" "$2"
}

_flow_card() { # _flow_card <repo> <pass> <card> — one card begin → wrap, a phase per call; rc 1 + why
  local R="$1" pass="$2" card="$3" id lane t0 tm t1 line nx path
  case "$card" in look) path=src/a.css ;; *) path=src/b.html ;; esac
  _flow_run new "$R" bash "$_FLOW_KIT" new ".polaris/drafts/$card.md" || { echo "new failed"; return 1; }
  id="$(sed -n '/^== new:/{n;p;}' "$_FLOW_LOG" | tail -1)"; id="${id%%[ $'\t']*}"
  case "$id" in T-[0-9]*) ;; *) echo "new printed no task id"; return 1 ;; esac
  t0="$(_flow_now)"; lane="$(cd "$R" && bash "$_FLOW_KIT" triage "$id" 2>>"$_FLOW_LOG" | sed -n 1p)"; t1="$(_flow_now)"
  _flow_rec triage "$t0" "$t1"
  [ "$lane" = solo ] || { echo "triage said '$lane', not solo"; return 1; }
  _flow_run claim "$R" bash "$_FLOW_KIT" claim "$id" || { echo "claim failed"; return 1; }
  _flow_run pack "$R" bash "$_FLOW_KIT" pack "$id" || { echo "pack failed"; return 1; }
  ( cd "$R/.polaris/wt/$id" && echo "$card" > "$path" && git add -A && git commit -qm "$card" ) >>"$_FLOW_LOG" 2>&1 \
    || { echo "the edit did not commit"; return 1; }
  if [ "$pass" = self ]; then
    if [ "${_FLOW_TRACE:-}" = handoff ] || [ "${_FLOW_TRACE:-}" = land ]; then
      # one call holds both: trace it whole (the profile then covers the landing tail too)
      _FLOW_TRACE=handoff _flow_run handoff "$R/.polaris/wt/$id" bash "$_FLOW_KIT" handoff
      line="$(awk -F'\t' '$1=="handoff"{print $3}' "$_FLOW_TSV")"; _flow_rec land "$line" "$line"
    else
      # the landing tail runs inside handoff: one call, split at the line that starts it
      t0="$(_flow_now)"; tm=""
      while IFS= read -r line; do
        printf '%s\n' "$line" >>"$_FLOW_LOG"
        case "$line" in *"continuing into land"*) [ -n "$tm" ] || tm="$(_flow_now)" ;; esac
      done < <(cd "$R/.polaris/wt/$id" && bash "$_FLOW_KIT" handoff 2>&1 </dev/null)
      t1="$(_flow_now)"; [ -n "$tm" ] || tm="$t1"
      _flow_rec handoff "$t0" "$tm"; _flow_rec land "$tm" "$t1"
    fi
  else
    _flow_run handoff "$R/.polaris/wt/$id" bash "$_FLOW_KIT" handoff || { echo "handoff failed"; return 1; }
    _flow_run land "$R" bash "$_FLOW_KIT" land "$id" || { echo "land failed"; return 1; }
    _flow_run seal "$R" bash "$_FLOW_KIT" seal || { echo "seal failed"; return 1; }
    _flow_run done "$R" bash "$_FLOW_KIT" done "$id" || { echo "done failed"; return 1; }
  fi
  [ -f "$R/ops/board/done/$id.md" ] || { echo "$id did not reach done/"; return 1; }
  t0="$(_flow_now)"; nx="$(cd "$R" && bash "$_FLOW_KIT" next 2>>"$_FLOW_LOG" | sed -n 1p)"; t1="$(_flow_now)"
  _flow_rec next "$t0" "$t1"
  printf '== next said: %s\n' "$nx" >>"$_FLOW_LOG"
  # wrap runs finish only when next says finish; a phase that did not run counts 0
  if [ "$nx" = finish ]; then
    _flow_run finish "$R" bash "$_FLOW_KIT" finish || { echo "finish failed"; return 1; }
  else
    t0="$(_flow_now)"; _flow_rec finish "$t0" "$t0"
  fi
}

_flow_cycle() { # _flow_cycle <pass> <run> — a fresh repo, both cards; timings under $_FLOW_W/<pass>.<run>.<card>
  local pass="$1" r="$2" R="$_FLOW_W/$1.$2/repo" card why
  mkdir -p "$_FLOW_W/$1.$2/home"
  ( export HOME="$_FLOW_W/$1.$2/home" USERPROFILE="$_FLOW_W/$1.$2/home"
    _flow_repo "$R" "$pass" ) >>"$_FLOW_W/$1.$2.log" 2>&1 || { echo "⛔ flow: the fixture repo did not build — $_FLOW_W/$1.$2.log" >&2; return 1; }
  for card in look ui; do
    _FLOW_TSV="$_FLOW_W/$pass.$r.$card"; _FLOW_LOG="$_FLOW_W/$pass.$r.log"; : >"$_FLOW_TSV"
    why="$(export HOME="$_FLOW_W/$1.$2/home" USERPROFILE="$_FLOW_W/$1.$2/home"; _flow_card "$R" "$pass" "$card")" || {
      printf '⛔ flow: %s pass, run %s, %s card: %s\n' "$pass" "$r" "$card" "$why" >&2
      tail -15 "$_FLOW_LOG" >&2; return 1; }
    # the traced profile cycle takes one card — the trace is the point, not the second number
    [ -z "${_FLOW_TRACE:-}" ] || break
  done
}

_flow_main() { # _flow_main [--list] [--profile] [--runs <n>] [--pass self|integrator]
  local list=0 prof=0 runs=3 passes="self integrator" pass r slow
  while [ $# -gt 0 ]; do
    case "$1" in
      --list) list=1 ;;
      --profile) prof=1 ;;
      --runs) runs="${2:-}"; shift ;;
      --pass) passes="${2:-}"; shift ;;
      *) printf '⛔ usage: bash ops/bench.sh --flow [--list] [--profile] [--runs <n>] [--pass self|integrator] — not understood: %s\n' "$1" >&2; return 2 ;;
    esac
    shift
  done
  case "$runs" in ''|*[!0-9]*|0) echo "⛔ --runs takes a whole number above 0" >&2; return 2 ;; esac
  case "$passes" in "self integrator"|self|integrator) ;; *) echo "⛔ --pass is self or integrator" >&2; return 2 ;; esac
  if [ "$list" = 1 ]; then
    for pass in $passes; do
      printf 'pass\t%s\n' "$pass"
      for r in $(_flow_phases "$pass"); do printf '%s\n' "$r"; done
    done
    return 0
  fi
  _FLOW_KIT="$ROOT/ops/polaris"
  _FLOW_W="$(mktemp -d)" || return 1
  trap 'rm -rf "$_FLOW_W"' EXIT
  export POLARIS_AWAKE_HOME="$_FLOW_W/awake" POLARIS_HEAVY_DIR="$_FLOW_W/heavy"
  unset CLAUDE_PROJECT_DIR CLAUDE_PID
  for pass in $passes; do
    for r in $(seq 1 "$runs"); do _flow_cycle "$pass" "$r" || return 1; done
    printf 'pass\t%s\n' "$pass"
    # per run: each phase's mean over the two cards; a phase prints its best run, flow the best total
    slow="$(for r in $(seq 1 "$runs"); do
        awk -F'\t' -v r="$r" '{ s[$1] += $3 - $2 } END { for (p in s) printf "%s\t%s\t%.3f\n", r, p, s[p] / 2 }' \
          "$_FLOW_W/$pass.$r.look" "$_FLOW_W/$pass.$r.ui"
      done | awk -F'\t' -v order="$(_flow_phases "$pass")" -v runs="$runs" '
        { k = $2; if (!(k in best) || $3 < best[k]) best[k] = $3; tot[$1] += $3 }
        END {
          n = split(order, o, " ")
          for (i = 1; i <= n; i++) { printf "%s\t%.2f\n", o[i], best[o[i]]; if (best[o[i]] > m) { m = best[o[i]]; sp = o[i] } }
          b = -1; for (r in tot) if (b < 0 || tot[r] < b) b = tot[r]
          printf "flow: begin+wrap %.2fs (best of %d)\n", b, runs
          printf "slowest\t%s\n", sp
        }')"
    printf '%s\n' "$slow" | grep -v '^slowest'
    for r in $(seq 1 "$runs"); do
      awk -F'\t' -v r="$r" -v pass="$pass" 'FNR == 1 { c = FILENAME; sub(/.*\./, "", c) } { s[c] += $3 - $2 }
        END { printf "flow %s run %s: look %.2fs · ui %.2fs\n", pass, r, s["look"], s["ui"] }' \
        "$_FLOW_W/$pass.$r.look" "$_FLOW_W/$pass.$r.ui" >&2
    done
    if [ "$prof" = 1 ]; then
      _FLOW_TRACE="$(printf '%s\n' "$slow" | sed -n 's/^slowest\t//p')"
      _FLOW_XT="$_FLOW_W/$pass.trace"
      _flow_cycle "$pass" profile || { _FLOW_TRACE=""; return 1; }
      printf 'profile\t%s\t%s (one traced look card; seconds until the next traced line, summed per line)\n' "$pass" "$_FLOW_TRACE"
      [ -s "$_FLOW_XT" ] || { echo "⛔ flow: no trace was written for $_FLOW_TRACE" >&2; _FLOW_TRACE=""; return 1; }
      awk '$1 ~ /^\++$/ && $2 ~ /^[0-9]+[.][0-9]+$/ {
          if (pl != "") { d[pl] += $2 - pt; if (!(pl in c)) c[pl] = pc }
          pt = $2; pl = $3; pc = ""; for (i = 4; i <= NF && length(pc) < 70; i++) pc = pc (pc == "" ? "" : " ") $i }
        END { for (k in d) printf "%.3f\t%s\t%s\n", d[k], k, c[k] }' "$_FLOW_XT" | sort -t"$(printf '\t')" -k1,1 -rn | head -15
      _FLOW_TRACE=""
    fi
  done
}

if [ "${1:-}" = "--flow" ]; then
  shift
  _flow_main "$@"
  exit $?
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
