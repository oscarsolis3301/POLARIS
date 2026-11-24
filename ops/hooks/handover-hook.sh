#!/usr/bin/env bash
# POLARIS v6 — Claude Code handover hooks: the Stop backstop, the compaction anchor, the prompt clock.
#
# WHY THIS EXISTS
#   Invariant 5 ends a context with its task, so every next role used to need a human kickoff. The
#   loop itself lives in the ROLE PROSE — every role runs `bash ops/polaris next` at its boundary and
#   follows line 1 — because the harness caps consecutive Stop blocks, so a hook-driven loop is
#   structurally short. This file is only the backstop for what prose cannot cover: `stop` hands a
#   model that completed a task and stopped anyway its next role, `anchor` re-reads the board into a
#   compacted or resumed context, `prompt` stamps the clock the run-minutes budget measures from.
#   It NEVER mutates the board: `promote` blocks with "run next --do" and the model promotes in its
#   own turn, because a 30 s mutex wait inside a 30 s hook would strand the mutex. It prints on
#   stdout ONLY a block's JSON (stdout not starting with `{` is read as plain text and the decision
#   is silently dropped) or, under `--test`, its one pinned word.
#
# THE LADDER — cheapest first, and the first rung is free. Ordinary Q&A never wrote a board event, so
#   it exits at `allow:no-state` on pure builtins: no fork, no interpreter, no `ops/polaris` (~2.2 s
#   of startup). Every later rung is paid only by a context that just completed something. ONE event
#   licenses exactly ONE hop, by string equality of `last-event` and `hopped-event` — never a
#   timestamp comparison. `--test [stop|anchor|prompt]` prints the rung word instead of the output
#   layer and performs the SAME state writes, so `hops` is assertable after a `--test` block.
#   POLARIS_HANDOVER_NEXT="<line 1>" replaces the `next` call and POLARIS_HANDOVER_CLI replaces
#   <primary>/ops/polaris — the INSTALLED CLI has no `next` until 6.2.0 is dogfooded.
#
# BUILD-TIME VERIFICATIONS (2026-09-02, code.claude.com/docs/en/hooks + this machine; all four hold,
#   so no rung fails open — quoted wording in the handoff Notes): 1 the input field is
#   `stop_hook_active`, and the harness overrides a Stop hook after eight consecutive blocks · 2 Stop
#   uses a TOP-LEVEL `decision: block` field, so the pinned JSON ships as designed · 3 the
#   <transcript dir>/<sid>/subagents/*.jsonl mtimes advance live, and `-newer` against the last-event
#   FILE is the portable comparison against the event's ts · 4 assistant lines carry
#   {"type":"text","text":"..."} with the stop mark stored as raw UTF-8. `prompt` is builtins-only
#   but for one `date +%s`: bash 3.2 has no epoch builtin and next_budget needs the file non-empty.
#
# THE ARMED RUN (ops/contracts/walk-away.md § 4.2, 6.20.0): with <primary>/.polaris/run/<sid>.armed
#   on disk and the owner away, `stop` gains a FIRST rung (_hh_run) and `substop` (SubagentStop) /
#   `stopfail` (StopFailure) answer. No armed file → every rung below is byte-for-byte 6.19.0's.
#   Verified 2026-11-24 against code.claude.com/docs/en/hooks: Stop and SubagentStop carry
#   `background_tasks` + `session_crons` (a cron's `prompt` key); StopFailure carries `error`.
set -u
TESTMODE=0
REPLY=''
HH_SAY='The owner approved the plan and left. Do not ask. Take the recommended option and write it down as an assumed: line; if there is no safe default, park that one piece and finish the rest.'
# Value of "$1" from the JSON "$2" into REPLY. checkout-guard.sh's jstr — rc 1 on ANY irregularity —
# plus one arm it does not need: a bare literal, `stop_hook_active` being a boolean.
hh_jstr() {
  local key="$1" s="$2" rest ch out='' i=0 len after
  rest="${s#*\"$key\"}"; [ "$rest" = "$s" ] && return 1
  rest="${rest#"${rest%%[![:space:]]*}"}"; [ "${rest:0:1}" = ":" ] || return 1
  rest="${rest:1}"; rest="${rest#"${rest%%[![:space:]]*}"}"
  if [ "${rest:0:1}" != '"' ]; then          # true/false/null/number — cut at , or } , then rtrim
    out="${rest%%,*}"; out="${out%%\}*}"; out="${out%"${out##*[![:space:]]}"}"
    case "$out" in ''|*[!A-Za-z0-9.+-]*) return 1;; esac
    REPLY="$out"; return 0
  fi
  rest="${rest:1}"; len=${#rest}
  while [ "$i" -lt "$len" ]; do
    ch="${rest:i:1}"
    if [ "$ch" = '\' ]; then
      i=$((i + 1)); ch="${rest:i:1}"
      case "$ch" in '"'|'\'|/) out="$out$ch";; *) return 1;; esac  # any other escape: never guess
      i=$((i + 1)); continue
    fi
    if [ "$ch" = '"' ]; then
      after="${rest:i+1}"; after="${after#"${after%%[![:space:]]*}"}"
      case "${after:0:1}" in ','|'}') REPLY="$out"; return 0;; *) return 1;; esac
    fi
    out="$out$ch"; i=$((i + 1))
  done
  return 1
}
# A primary is where the board is — which is what lets a mktemp fixture dir BE one for a golden or a
# verify probe. $2 = nofork forbids the git arm, so the UserPromptSubmit path stays free.
hh_primary() {
  local c="${1:-}"
  c="${c//\\//}"                             # Claude Code hands us a Windows cwd
  case "$c" in */.polaris/wt/*) REPLY="${c%%/.polaris/wt/*}"; return 0;; esac
  [ -n "$c" ] && [ -d "$c/ops/board" ] && { REPLY="$c"; return 0; }
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && { REPLY="${CLAUDE_PROJECT_DIR//\\//}"; return 0; }
  [ "${2:-}" = nofork ] && return 1
  REPLY="$(git -C "${c:-.}" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$REPLY" ]
}
# One CONVENTIONS key: $1 key, $2 primary, $3 default -> REPLY. `sed`, never `ops/polaris` (~2.2 s)
# — this is a hot path, and a hook that is slow is a hook that is not there. A blank or missing repo
# line falls back to this computer's preferences (machine-prefs § 4; POLARIS_PREFS= turns it off);
# no machine file costs one builtin test, no process.
hh_cfg() {
  local f="$2/ops/CONVENTIONS.md" m="${POLARIS_PREFS-${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/polaris/preferences}" v
  REPLY="${3:-}"
  if [ -f "$f" ]; then
    v="$(sed -n "s/^$1:[[:space:]]*\([^#]*\).*\$/\1/p" "$f" 2>/dev/null | head -1)"
    v="${v%"${v##*[![:space:]]}"}"
    [ -n "$v" ] && { REPLY="$v"; return 0; }
  fi
  [ -n "$m" ] && [ -f "$m" ] || return 0
  v="$(sed -n "s/^$1:[[:space:]]*\([^#[:space:]][^#]*\).*\$/\1/p" "$m" 2>/dev/null | head -1)"
  v="${v%"${v##*[![:space:]]}"}"
  [ -n "$v" ] && REPLY="$v"
  return 0
}
# One state file: $1 dir, $2 name -> REPLY (first line, CR stripped); rc 1 when absent. No fork.
hh_state() {
  REPLY=''; [ -f "$1/$2" ] || return 1
  IFS= read -r REPLY < "$1/$2" 2>/dev/null || REPLY=''
  REPLY="${REPLY%$'\r'}"; return 0
}
# Does this event license a hop? $1 last-event, $2 hopped-event.
# rc 0 = yes · 1 = not a completion · 2 = already consumed.
hh_licensed() {
  local kind="${1#* }"; kind="${kind%% *}"
  case "$kind" in handoff|done|all-review) ;; *) return 1;; esac
  [ -n "$1" ] && [ "$1" = "$2" ] && return 2
  return 0
}
# Was a subagent working? $1 transcript_path, $2 sid, $3 last-event file. Subagent completions land
# in the PARENT's state dir, so without this rung a conductor whose builders just handed off would
# be hopped into BUILDER.
hh_subagent() {
  local d
  [ -n "$1" ] || return 1
  d="${1%/*}/$2/subagents"
  if [ -d "$d" ] && [ -f "$3" ]; then
    [ -n "$(find "$d" -name '*.jsonl' -newer "$3" 2>/dev/null | head -1)" ] && return 0
  fi
  [ -f "$1" ] || return 1
  tail -200 "$1" 2>/dev/null | grep -qE '"name":"(Task|Agent)"'
}
# Did it stop to ask? $1 transcript_path. The last assistant text block opens a line with the stop
# mark, or ends with a question mark. Text is JSON-escaped, so a line break inside it is the two
# chars \n and the block closes with "} — both shapes verified on a live transcript.
hh_question() {
  local t
  [ -n "$1" ] && [ -f "$1" ] || return 1
  t="$(tail -400 "$1" 2>/dev/null | grep '"type":"assistant"' | grep '{"type":"text"' | tail -1)"
  [ -n "$t" ] || return 1
  REPLY=stop                                  # the stop mark: a real stop, never bounced
  case "$t" in *'\n⛔'*|*'"text":"⛔'*) return 0;; esac
  REPLY=q                                     # a closing question: bounced once while work is left
  case "$t" in *'?"}'*|*'?\n"}'*) return 0;; esac
  return 1
}
# Plan work? $1 primary, $2 state dir, $3.. task IDs -> 0 only when the session has a recorded plan
# and EVERY id's task carries that plan slug (T-230: caps count only work outside the plan).
hh_inplan() {
  local p="$1" d="$2" mp='' id f pl c
  shift 2
  [ -f "$d/plan" ] && mp="$(tr -d ' \r\n' < "$d/plan" 2>/dev/null)"
  [ -n "$mp" ] && [ "$#" -gt 0 ] || return 1
  for id in "$@"; do
    f=''
    for c in active ready review backlog blocked; do [ -f "$p/ops/board/$c/$id.md" ] && { f="$p/ops/board/$c/$id.md"; break; }; done
    [ -n "$f" ] || return 1
    pl="$(sed -n 's/^plan:[[:space:]]*//p' "$f" 2>/dev/null | head -1)"; pl="$(printf '%s' "$pl" | tr -d ' \r"')"
    [ "$pl" = "$mp" ] || return 1
  done
  return 0
}
# Is our landing tail still up? $1 primary, $2 cwd -> REPLY = an OWN ship-<ID> job with no rc yet.
hh_bg_live() {
  local d n c
  for d in "$1"/.polaris/bg/ship-*/; do
    [ -d "$d" ] || continue
    n="${d%/}"; n="${n##*/}"
    case "$n" in *.prev) continue;; esac
    [ -e "$d/rc" ] && continue
    c=''; [ -f "$d/cwd" ] && { IFS= read -r c < "$d/cwd" 2>/dev/null || c=''; }
    c="${c%$'\r'}"; c="${c//\\//}"
    [ "$c" = "$1" ] || [ "$c" = "$2" ] || continue
    REPLY="$n"; return 0
  done
  return 1
}
# Has the owner left? (ops/contracts/away.md § 2.3) rc 0 = away: a valid session id, an approval on
# record in <state dir>/<sid>.approved, and an away mode — the Stop payload's permission_mode, else line
# 1 of <sid>.mode. Anything unknown or unreadable is "here" (rc 1). Builtins and one small read.
_hh_away() {
  local d m=''
  case "$SID" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
  [ -n "${CLAUDE_CONFIG_DIR:-${HOME:-}}" ] || return 1
  d="${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/polaris/model-state"
  [ -f "$d/$SID.approved" ] || return 1
  hh_jstr permission_mode "$IN" && m="$REPLY"
  [ -n "$m" ] || { hh_state "$d" "$SID.mode" || return 1; m="$REPLY"; }
  case "$m" in auto|bypassPermissions|dontAsk) return 0;; esac
  return 1
}
# Is the run armed? (walk-away § 1) $1 primary -> REPLY = the newest <primary>/.polaris/run/*.armed
# whose epoch is within reentry_hours (default 12). rc 1 = not armed — and no file is the free path:
# one glob that matches nothing, no fork. Anything unparseable is "not armed" (today's behaviour).
_hh_armed() {
  local f e best='' be=0 h now
  for f in "$1"/.polaris/run/*.armed; do
    [ -f "$f" ] || continue
    e=''; { IFS= read -r e < "$f"; } 2>/dev/null; e="${e%$'\r'}"
    case "$e" in ''|*[!0-9]*) continue;; esac
    [ "$e" -gt "$be" ] && { be="$e"; best="$f"; }
  done
  [ -n "$best" ] || return 1
  hh_cfg reentry_hours "$1" 12; h="$REPLY"; case "$h" in ''|*[!0-9]*) h=12;; esac
  now="${EPOCHSECONDS:-$(date +%s 2>/dev/null)}"; case "$now" in ''|*[!0-9]*) return 1;; esac
  [ $((now - be)) -le $((h * 3600)) ] || return 1
  REPLY="$best"; return 0
}
# THE ARMED RUNG (walk-away § 4.2), first in hh_stop. $1 primary, $2 state dir. Returns only to hand
# the stop to today's ladder: not armed, not away, `away_gate: off`, parked, finished, or a `next` that
# printed nothing. Otherwise it decides: a background task or a real wait lets go; work left blocks;
# the THIRD identical block (same last-event + line 1) lets go as stalled, marks it and notifies.
# Payload fields (code.claude.com/docs/en/hooks, Stop input): `background_tasks` and `session_crons`
# are arrays, "present when the task registry is reachable and empty when nothing is in flight" —
# absent reads as empty, never as "allow".
_hh_run() {
  local p="$1" d="$2" a out l1 verb ev='' pv='' pl='' pn=0 n=1 now re cr why
  _hh_armed "$p" || return 0
  a="$REPLY"
  _hh_away || return 0
  hh_cfg away_gate "$p" on; [ "$REPLY" = off ] && return 0
  [ -f "$p/.polaris/run/$SID.parked" ] && return 0
  [ -f "$d/finished" ] && [ "$d/finished" -nt "$a" ] && return 0
  re='"background_tasks"[[:space:]]*:[[:space:]]*\[[[:space:]]*([^[:space:]])'
  [[ $IN =~ $re ]] && [ "${BASH_REMATCH[1]}" != ']' ] && hh_emit allow:bg ''
  if [ -n "${POLARIS_HANDOVER_NEXT:-}" ]; then out="$POLARIS_HANDOVER_NEXT"
  else out="$(cd "$p" 2>/dev/null && bash "${POLARIS_HANDOVER_CLI:-$p/ops/polaris}" next 2>/dev/null)"; fi
  l1="${out%%$'\n'*}"; l1="${l1%$'\r'}"
  [ -n "$l1" ] || return 0
  case "${l1%% *}" in wait|stop) hh_emit allow:wait '';; esac
  hh_state "$d" last-event && ev="$REPLY"
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null
  if [ -f "$d/run-blocks" ]; then              # <event>TAB<l1>TAB<n>; the event may be empty, so no IFS split
    hh_state "$d" run-blocks; pv="${REPLY%%$'\t'*}"; pl="${REPLY#*$'\t'}"; pn="${pl#*$'\t'}"; pl="${pl%%$'\t'*}"
    case "$pn" in ''|*[!0-9]*) pn=0;; esac
    [ "$pv" = "$ev" ] && [ "$pl" = "$l1" ] && n=$((pn + 1))
  fi
  printf '%s\t%s\t%s\n' "$ev" "$l1" "$n" > "$d/run-blocks" 2>/dev/null
  if [ "$n" -ge 3 ]; then
    if [ "$n" = 3 ]; then
      now="${EPOCHSECONDS:-$(date +%s 2>/dev/null)}"
      printf '%s\t%s\n' "$now" "the Stop gate blocked 3 times on: next says $l1" > "$p/.polaris/run/stalled" 2>/dev/null
      ( cd "$p" 2>/dev/null && bash "${POLARIS_HANDOVER_CLI:-$p/ops/polaris}" notify-gate stall ) </dev/null >/dev/null 2>&1 &
    fi
    hh_emit allow:stalled ''
  fi
  why="$HH_SAY Work left — next says $l1; do it."
  re='"session_crons"[[:space:]]*:[[:space:]]*(\[.*)'
  if [[ $IN =~ $re ]]; then
    cr="${BASH_REMATCH[1]}"; cr="${cr%%\"background_tasks\"*}"
    case "$cr" in *'ops/polaris pulse'*) ;; *)
      hh_cfg pulse_minutes "$p" 30
      why="$why Arm the pulse: CronCreate every $REPLY min, prompt \"bash ops/polaris pulse, then follow line 1\".";;
    esac
  fi
  hh_emit block:run "$why"
}
# SubagentStop (walk-away § 4.2), armed only: an own rc-less, live job whose cwd is under the
# subagent's cwd keeps it from ending with the job still running. Otherwise silent.
_hh_substop() {
  local p d n c sc pid
  hh_primary "$CWD" || hh_emit substop:none ''
  p="$REPLY"
  _hh_armed "$p" || hh_emit substop:none ''
  sc="${CWD//\\//}"; sc="${sc%/}"
  [ -n "$sc" ] || hh_emit substop:none ''
  for d in "$p"/.polaris/bg/*/; do
    [ -d "$d" ] || continue
    n="${d%/}"; n="${n##*/}"
    case "$n" in *.prev) continue;; esac
    [ -e "$d/rc" ] && continue
    pid=''; [ -f "$d/pid" ] && { IFS= read -r pid < "$d/pid" 2>/dev/null || pid=''; }
    pid="${pid%$'\r'}"; case "$pid" in ''|*[!0-9]*) ;; *) kill -0 "$pid" 2>/dev/null || continue;; esac
    c=''; [ -f "$d/cwd" ] && { IFS= read -r c < "$d/cwd" 2>/dev/null || c=''; }
    c="${c%$'\r'}"; c="${c//\\//}"
    [ -n "$c" ] || continue
    case "$c/" in "$sc"/*) ;; *) continue;; esac
    hh_emit substop:collect "Your job $n is still running: bash ops/polaris bg wait $n --max 240 (repeat while rc 2)."
  done
  hh_emit substop:none ''
}
# StopFailure (walk-away § 4.2), armed only: the API error the turn died on, appended to
# <primary>/.polaris/run/stopfail.tsv. The harness ignores this hook's output; it never blocks.
_hh_stopfail() {
  local p e='' now
  hh_primary "$CWD" || hh_emit stopfail:none ''
  p="$REPLY"
  _hh_armed "$p" || hh_emit stopfail:none ''
  hh_jstr error "$IN" && e="$REPLY"
  case "$e" in ''|*[!A-Za-z0-9_]*) e=unknown;; esac
  now="${EPOCHSECONDS:-$(date +%s 2>/dev/null)}"
  [ -d "$p/.polaris/run" ] || mkdir -p "$p/.polaris/run" 2>/dev/null
  printf '%s\t%s\n' "$now" "$e" >> "$p/.polaris/run/stopfail.tsv" 2>/dev/null
  hh_emit stopfail:recorded ''
}
# THE one emitter: $1 = the --test word, $2 = the reason ('' means allow). Never returns.
hh_emit() {
  local r="${2:-}"
  [ "$TESTMODE" = 1 ] && { printf '%s\n' "$1"; exit 0; }
  [ -n "$r" ] || exit 0                      # allow = no output at all, exit 0
  r="${r//\\/\\\\}"; r="${r//\"/\\\"}"       # a board title may carry either; JSON may not
  printf '{"decision":"block","reason":"%s"}\n' "$r"
  exit 0
}
# The gate ladder, in the pinned order.
hh_stop() {
  local p dir ev hop cap hops n out l1 n2 verb id ids hi job q=0 capped=0 plan=0 away=0
  hh_primary "$CWD" || hh_emit allow:no-state ''
  p="$REPLY"; dir="$p/.polaris/handover/$SID"
  _hh_run "$p" "$dir"                        # the armed FIRST rung; returns only to today's ladder
  [ -n "$SID" ] && [ -f "$dir/last-event" ] || hh_emit allow:no-state ''
  hh_state "$dir" last-event; ev="$REPLY"
  hh_cfg handover "$p" auto; [ "$REPLY" = off ] && hh_emit allow:off ''
  hh_state "$dir" hopped-event; hop="$REPLY"
  hh_licensed "$ev" "$hop" || case $? in 1) hh_emit allow:no-event '';; 2) hh_emit allow:consumed '';; esac
  [ -f "$dir/finished" ] && [ "$dir/finished" -nt "$dir/last-event" ] && hh_emit allow:finished ''
  # away + a closing question is bounced on EVERY stop (away.md § 3): the harness's own cap is the backstop
  [ "$SHA" = true ] && { _hh_away && hh_question "$TP" && [ "$REPLY" = q ] && away=1 || hh_emit allow:harness-cap ''; }
  hh_cfg run_max_tasks "$p" 0; cap="${REPLY:-0}"
  hh_state "$dir" hops; hops="${REPLY:-0}"
  case "$hops:$cap" in *[!0-9:]*) hops=0; cap=0;; esac
  # a recorded plan defers the cap to the verb below. Recorded = a slug, read the way hh_inplan and
  # next_inplan read it: claim writes a bare newline for a task with no plan:, and `-s` called that a plan
  [ "$cap" != 0 ] && [ "$hops" -ge "$cap" ] && { hh_state "$dir" plan; [ -n "${REPLY//[[:space:]]/}" ] && capped=1 || hh_emit allow:cap ""; }
  hh_subagent "$TP" "$SID" "$dir/last-event" && hh_emit allow:subagent ''
  hh_question "$TP" && { [ "$REPLY" = stop ] && hh_emit allow:question ""; q=1; }
  hh_bg_live "$p" "$CWD" && { job="$REPLY"                   # consumes nothing: the tail resumes
    hh_emit block:collect "Your landing tail $job is still running: bash ops/polaris bg wait $job --max 300 (repeat while rc 2), then bash ops/polaris next."; }
  if [ -n "${POLARIS_HANDOVER_NEXT:-}" ]; then out="$POLARIS_HANDOVER_NEXT"
  else out="$(cd "$p" 2>/dev/null && bash "${POLARIS_HANDOVER_CLI:-$p/ops/polaris}" next 2>/dev/null)"; fi
  l1="$(printf '%s\n' "$out" | head -1)"; l1="${l1%$'\r'}"
  verb="${l1%% *}"; id="${l1#* }"; [ "$id" = "$l1" ] && id=''
  case "$verb" in wait|stop|resume) [ "$q" = 1 ] && hh_emit allow:question ''; hh_emit "allow:$verb" '';;
    build|integrate|promote|tidy|finish) ;;
    *) [ "$q" = 1 ] && hh_emit allow:question ''; hh_emit allow:no-verb '';; esac
  # plan work (T-230): tasks of the session's recorded plan are not counted against the run caps.
  # The layout pass is free the same way (save-hops.md § 2.2): a run cap never skips what the owner asked for.
  case "$verb" in
    build)   hh_inplan "$p" "$dir" $id && plan=1;;
    integrate) ids="$(printf '%s\n' "$out" | sed -n 's/^   review\/: //p')"; hh_inplan "$p" "$dir" $ids && plan=1;;
    promote) ids="$(printf '%s\n' "$out" | sed -n 's/^   eligible: \(.*\) — bash.*$/\1/p')"; hh_inplan "$p" "$dir" $ids && plan=1;;
    tidy)    plan=1;;
  esac
  [ "$capped" = 1 ] && [ "$plan" = 0 ] && hh_emit allow:cap ''
  if [ "$q" = 1 ]; then
    case "$verb" in finish|tidy) hh_emit allow:question '';; esac   # the run's end: a question there is the close
    [ "$away" = 1 ] || { _hh_away && away=1; }
    [ "$away" = 1 ] && hh_emit block:away "The owner approved the plan and left. Do not ask. Take the recommended option and write it down as an assumed: line; if there is no safe default, park that one piece and finish the rest. Work left - next says $l1; do it."
    hh_emit block:question "Work left - next says $l1. The plan approval covers it; do it. A real product/approval question? ask again and you will be let through."
  fi
  n=$((hops + 1)); [ "$plan" = 1 ] && n="$hops"; printf '%s\n' "$n" > "$dir/hops"   # plan hops are free; the writes land BEFORE the emit, so
  printf '%s\n' "$ev" > "$dir/hopped-event"                  # one event still buys one hop on a crash
  case "$verb" in
    build)  n2="$(printf '%s\n' "$out" | sed -n 2p)"; n2="${n2#   }"; n2="${n2%, wsjf *}"
            [ -n "$n2" ] && n2=" — ${n2})"
            hh_emit block:build "You are a BUILDER (hop $n of $cap). The board hands you $id$n2. Leave the finished worktree first (ExitWorktree, or cd \"$p\"), then: bash ops/polaris claim $id — taken? bash ops/polaris claim takes the next. Run bash ops/polaris role BUILDER if this context no longer has it; at your handoff run bash ops/polaris next and follow it.";;
    integrate) ids="$(printf '%s\n' "$out" | sed -n 's/^   review\/: //p')"
            hi="$(printf '%s\n' "$out" | sed -n 's/^   risk: high, human approves: //p')"
            [ -n "$hi" ] && hi=" $hi are risk: high — the human approves those, never you."
            hh_emit block:integrate "You are the INTEGRATOR (hop $n). From the primary checkout land what waits in ops/board/review/ — $ids: bash ops/polaris land <ID> per task, then seal, run-verify + done each.$hi Run bash ops/polaris role INTEGRATOR if this context no longer has it; then bash ops/polaris next.";;
    promote) ids="$(printf '%s\n' "$out" | sed -n 's/^   eligible: \(.*\) — bash.*$/\1/p')"
            hh_emit block:promote "Backlog work is unblocked ($ids). From the primary: bash ops/polaris next --do — it promotes what passes the ready gate under the board lock — then follow its line 1.";;
    tidy)   hh_emit block:tidy "The layout pass is due. You are TIDY (hop $n): run bash ops/polaris role TIDY and follow it now — one context, no subagents, it lands one task. Then bash ops/polaris next.";;
    finish) hh_emit block:finish "This run's board is done. From the primary: bash ops/polaris finish — its exit code decides your close (0 opens with # 🎉 Complete!; otherwise no H1, name the one pending thing).";;
  esac
}
# Re-entry after a compaction. SessionStart stdout IS added to the model's context, which is the
# point: a context that lost everything reads the board instead of guessing.
hh_anchor() {
  local p
  hh_primary "$CWD" || exit 0
  p="$REPLY"
  [ -n "$SID" ] && [ -d "$p/.polaris/handover/$SID" ] || { [ "$TESTMODE" = 1 ] && printf 'anchor: no-state\n'; exit 0; }
  [ "$TESTMODE" = 1 ] && { printf 'anchor: brief\n'; exit 0; }
  ( cd "$p" 2>/dev/null && bash "${POLARIS_HANDOVER_CLI:-$p/ops/polaris}" next --brief 2>/dev/null ); exit 0
}
# The run clock. UserPromptSubmit stdout enters the model's context, so this one prints NOTHING. A
# human prompt is what resets the run-minutes budget: the run is alive again because a person said so.
hh_prompt() {
  local p dir
  hh_primary "$CWD" nofork || exit 0
  p="$REPLY"; dir="$p/.polaris/handover/$SID"
  [ -n "$SID" ] && [ -d "$dir" ] || exit 0
  date +%s > "$dir/prompted-at" 2>/dev/null || true
  [ "$TESTMODE" = 1 ] && printf 'prompt: prompted-at written\n'
  exit 0
}
if [ "${1:-}" = "--test" ]; then TESTMODE=1; SUB="${2:-stop}"; else SUB="${1:-stop}"; fi
IN="$(cat)"
SID=''; hh_jstr session_id       "$IN" && SID="$REPLY"
TP='';  hh_jstr transcript_path  "$IN" && TP="$REPLY"
CWD=''; hh_jstr cwd              "$IN" && CWD="$REPLY"
SHA=''; hh_jstr stop_hook_active "$IN" && SHA="$REPLY"
case "$SUB" in
  stop)   hh_stop;;
  anchor) hh_anchor;;
  prompt) hh_prompt;;
  substop)  _hh_substop;;
  stopfail) _hh_stopfail;;
esac
exit 0
