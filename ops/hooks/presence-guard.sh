#!/usr/bin/env bash
# POLARIS v6 — Claude Code hook: is the owner here, or did they approve the plan and leave?
#
# WHY THIS EXISTS
#   The owner's rule (plans/away.md): once a plan is approved and the chat runs in a hands-off mode,
#   they have left, and nothing may wait on them. Before this hook nothing knew which of the two
#   states a session was in, and the question tool was never intercepted, so a run could stop on
#   "approve this?" and sit idle for half an hour. This hook remembers the session's mode and whether
#   a plan was approved, and refuses AskUserQuestion while the owner is away, with a sentence telling
#   the model what to do instead. `bash ops/polaris presence` reads the same two files.
#
# THE CONTRACT — ops/contracts/away.md § 0–2
#   Registered three times by .claude/settings.json: PreToolUse (AskUserQuestion|Bash|PowerShell),
#   PostToolUse (ExitPlanMode) and UserPromptSubmit. State lives beside model-guard.sh's:
#     $HOME/.claude/polaris/model-state/<sid>.mode      the last permission_mode seen (written on change)
#     $HOME/.claude/polaris/model-state/<sid>.approved  line 1: epoch of the approval · lines 2+: slugs
#   away ⇔ <sid> valid AND <sid>.approved exists AND the mode is auto | bypassPermissions | dontAsk.
#   Every other case is here, and here means no output at all.
#
# FAIL-OPEN, AND FAST
#   Any parse miss, unset HOME, bad <sid> or unreadable file ⇒ no output, exit 0. Never non-zero,
#   never stderr. Builtins and one small read on the common path; a fork only on a state change
#   (mkdir -p on a first write, date on an approval write where bash has no EPOCHSECONDS, rm when a
#   new plan is being drafted).
#
#   --test as $1: print ONE word instead (deny:away · allow:here · allow:not-question · allow:error)
#   after the SAME state writes.

export LC_ALL=C
PG_TEST=''; [ "${1:-}" = --test ] && PG_TEST=1
PG_SAY='The owner approved the plan and left. Do not ask. Take the recommended option and write it down as an assumed: line; if there is no safe default, park that one piece and finish the rest.'

pg_end() { # pg_end <word> — the test word under --test, otherwise nothing; always exit 0
  [ -n "$PG_TEST" ] && printf '%s\n' "$1"
  exit 0
}

# --- read the hook JSON (builtin; no fork) -----------------------------------
IN=''
IFS= read -r -d '' IN 2>/dev/null
[ -n "$IN" ] || pg_end allow:error

# --- the top-level fields, from the HEAD of the payload (model-guard.sh's cut) -
PG_H="$IN"
case "$IN" in *'"tool_input":'*) PG_H="${IN%%\"tool_input\":*}";; esac
PG_EV=''; PG_SID=''; PG_TOOL=''; PG_MODE=''
pg_re='"hook_event_name": *"([^"]*)"'; [[ $PG_H =~ $pg_re ]] && PG_EV="${BASH_REMATCH[1]}"
pg_re='"session_id": *"([^"]*)"';      [[ $PG_H =~ $pg_re ]] && PG_SID="${BASH_REMATCH[1]}"
pg_re='"tool_name": *"([^"]*)"';       [[ $PG_H =~ $pg_re ]] && PG_TOOL="${BASH_REMATCH[1]}"
pg_re='"permission_mode": *"([^"]*)"'; [[ $PG_H =~ $pg_re ]] && PG_MODE="${BASH_REMATCH[1]}"
[ -n "$PG_EV" ] || pg_end allow:error
# <session_id> names a file, so it must be a plain name: `/`, `\` or `..` in it → no state at all.
case "$PG_SID" in ''|*[!A-Za-z0-9_-]*) pg_end allow:error;; esac
[ -n "${HOME:-}" ] || pg_end allow:error
case "$PG_MODE" in *[!A-Za-z]*) PG_MODE='';; esac
PG_F="$HOME/.claude/polaris/model-state/$PG_SID"

pg_approve() { # line 1 of <sid>.approved, only when absent: an approval on record keeps its epoch + slugs
  [ -f "$PG_F.approved" ] && return 0
  [ -d "${PG_F%/*}" ] || mkdir -p "${PG_F%/*}" 2>/dev/null
  { printf '%s\n' "${EPOCHSECONDS:-$(date +%s 2>/dev/null)}" > "$PG_F.approved"; } 2>/dev/null
  return 0
}

# --- 1. record the mode; plan → other is an approval, plan itself drops the old one ---
PG_WAS=''
{ IFS= read -r PG_WAS < "$PG_F.mode"; } 2>/dev/null
PG_WAS="${PG_WAS%$'\r'}"
if [ -n "$PG_MODE" ]; then
  if [ "$PG_MODE" != "$PG_WAS" ]; then
    [ -d "${PG_F%/*}" ] || mkdir -p "${PG_F%/*}" 2>/dev/null
    { printf '%s\n' "$PG_MODE" > "$PG_F.mode"; } 2>/dev/null
  fi
  if [ "$PG_MODE" = plan ]; then
    [ -f "$PG_F.approved" ] && rm -f "$PG_F.approved" 2>/dev/null
  elif [ "$PG_WAS" = plan ]; then
    pg_approve
  fi
else
  PG_MODE="$PG_WAS"                          # no permission_mode in this payload → the recorded one
fi

# --- 2. ExitPlanMode went through: that is the approval ----------------------
if [ "$PG_EV" = PostToolUse ] && [ "$PG_TOOL" = ExitPlanMode ]; then
  pg_approve
  pg_end allow:not-question
fi

# --- 3. the question tool, while the owner is away: refuse it, say what to do instead ---
if [ "$PG_EV" = PreToolUse ] && [ "$PG_TOOL" = AskUserQuestion ]; then
  case "$PG_MODE" in
    auto|bypassPermissions|dontAsk)
      if [ -f "$PG_F.approved" ]; then
        [ -n "$PG_TEST" ] && pg_end deny:away
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$PG_SAY" 2>/dev/null
        exit 0
      fi;;
  esac
  pg_end allow:here
fi

# --- 4. everything else: no opinion ------------------------------------------
pg_end allow:not-question
