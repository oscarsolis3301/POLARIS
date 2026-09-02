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
set -u
TESTMODE=0
REPLY=''
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
# — this is a hot path, and a hook that is slow is a hook that is not there.
hh_cfg() {
  local f="$2/ops/CONVENTIONS.md" v
  REPLY="${3:-}"; [ -f "$f" ] || return 0
  v="$(sed -n "s/^$1:[[:space:]]*\([^#]*\).*\$/\1/p" "$f" 2>/dev/null | head -1)"
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
  case "$t" in *'\n⛔'*|*'"text":"⛔'*|*'?"}'*|*'?\n"}'*) return 0;; esac
  return 1
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
  local p dir ev hop cap hops n out l1 n2 verb id ids hi job
  hh_primary "$CWD" || hh_emit allow:no-state ''
  p="$REPLY"; dir="$p/.polaris/handover/$SID"
  [ -n "$SID" ] && [ -f "$dir/last-event" ] || hh_emit allow:no-state ''
  hh_state "$dir" last-event; ev="$REPLY"
  hh_cfg handover "$p" auto; [ "$REPLY" = off ] && hh_emit allow:off ''
  hh_state "$dir" hopped-event; hop="$REPLY"
  hh_licensed "$ev" "$hop" || case $? in 1) hh_emit allow:no-event '';; 2) hh_emit allow:consumed '';; esac
  [ -f "$dir/finished" ] && [ "$dir/finished" -nt "$dir/last-event" ] && hh_emit allow:finished ''
  [ "$SHA" = true ] && hh_emit allow:harness-cap ''
  hh_cfg run_max_tasks "$p" 0; cap="${REPLY:-0}"
  hh_state "$dir" hops; hops="${REPLY:-0}"
  case "$hops:$cap" in *[!0-9:]*) hops=0; cap=0;; esac
  [ "$cap" != 0 ] && [ "$hops" -ge "$cap" ] && hh_emit allow:cap ''
  hh_subagent "$TP" "$SID" "$dir/last-event" && hh_emit allow:subagent ''
  hh_question "$TP" && hh_emit allow:question ''
  hh_bg_live "$p" "$CWD" && { job="$REPLY"                   # consumes nothing: the tail resumes
    hh_emit block:collect "Your landing tail $job is still running: bash ops/polaris bg wait $job --max 300 (repeat while rc 2), then bash ops/polaris next."; }
  if [ -n "${POLARIS_HANDOVER_NEXT:-}" ]; then out="$POLARIS_HANDOVER_NEXT"
  else out="$(cd "$p" 2>/dev/null && bash "${POLARIS_HANDOVER_CLI:-$p/ops/polaris}" next 2>/dev/null)"; fi
  l1="$(printf '%s\n' "$out" | head -1)"; l1="${l1%$'\r'}"
  verb="${l1%% *}"; id="${l1#* }"; [ "$id" = "$l1" ] && id=''
  case "$verb" in wait|stop|resume) hh_emit "allow:$verb" '';; build|integrate|promote|finish) ;;
    *) hh_emit allow:no-verb '';; esac
  n=$((hops + 1)); printf '%s\n' "$n" > "$dir/hops"          # the writes land BEFORE the emit, so
  printf '%s\n' "$ev" > "$dir/hopped-event"                  # one event still buys one hop on a crash
  case "$verb" in
    build)  n2="$(printf '%s\n' "$out" | sed -n 2p)"; n2="${n2#   }"; n2="${n2%, wsjf *}"
            [ -n "$n2" ] && n2=" — ${n2})"
            hh_emit block:build "You are a BUILDER (hop $n of $cap). The board hands you $id$n2. Leave the finished worktree first (ExitWorktree, or cd \"$p\"), then: bash ops/polaris claim $id — taken? bash ops/polaris claim takes the next. Read ops/roles/BUILDER.md if this context no longer has it; at your handoff run bash ops/polaris next and follow it.";;
    integrate) ids="$(printf '%s\n' "$out" | sed -n 's/^   review\/: //p')"
            hi="$(printf '%s\n' "$out" | sed -n 's/^   risk: high, human approves: //p')"
            [ -n "$hi" ] && hi=" $hi are risk: high — the human approves those, never you."
            hh_emit block:integrate "You are the INTEGRATOR (hop $n). From the primary checkout land what waits in ops/board/review/ — $ids: bash ops/polaris land <ID> per task, then seal, run-verify + done each.$hi Read ops/roles/INTEGRATOR.md if this context no longer has it; then bash ops/polaris next.";;
    promote) ids="$(printf '%s\n' "$out" | sed -n 's/^   eligible: \(.*\) — bash.*$/\1/p')"
            hh_emit block:promote "Backlog work is unblocked ($ids). From the primary: bash ops/polaris next --do — it promotes what passes the ready gate under the board lock — then follow its line 1.";;
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
esac
exit 0
