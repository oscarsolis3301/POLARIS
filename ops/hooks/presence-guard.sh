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
#   walk-away § 1, § 4.1, § 4.4: an approval also ARMS the run — <primary>/.polaris/run/<sid>.armed
#   (epoch · the slugs · `reentries 0`), written only when absent, only where the cwd holds a board,
#   removed when the mode turns to plan; `reentry: desktop` lets a `POLARIS re-entry:` prompt inherit it.
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
PG_P=''

# The primary (walk-away § 1): the payload's cwd when it holds a board — a worktree cwd names its
# primary fork-free. The cwd arrives JSON-escaped (C:\\Users\\…), so \ → / and the doubled / folds.
_pg_primary() {
  local c='' s='//' re='"cwd": *"([^"]*)"'
  [ -n "$PG_P" ] && return 0
  [[ $PG_H =~ $re ]] && c="${BASH_REMATCH[1]}"
  c="${c//\\//}"; c="${c//$s//}"
  case "$c" in */.polaris/wt/*) c="${c%%/.polaris/wt/*}";; esac
  [ -n "$c" ] && [ -d "$c/ops/board" ] && PG_P="$c"
  [ -n "$PG_P" ]
}
_pg_cfg() { # one CONVENTIONS key of the primary: $1 key, $2 default -> REPLY. A fork, off the common path.
  local f="$PG_P/ops/CONVENTIONS.md" v
  REPLY="$2"; [ -f "$f" ] || return 0
  v="$(sed -n "s/^$1:[[:space:]]*\([^#]*\).*\$/\1/p" "$f" 2>/dev/null | head -1)"
  v="${v%"${v##*[![:space:]]}"}"
  [ -n "$v" ] && REPLY="$v"
  return 0
}
_pg_arm() { # <primary>/.polaris/run/<sid>.armed, only when absent: epoch · the approval's slugs · reentries 0
  local a l n=0 sl='' e
  _pg_primary || return 0
  a="$PG_P/.polaris/run/$PG_SID.armed"
  [ -f "$a" ] && return 0
  e="${EPOCHSECONDS:-$(date +%s 2>/dev/null)}"
  case "$e" in ''|*[!0-9]*) return 0;; esac
  if [ -f "$PG_F.approved" ]; then
    { while IFS= read -r l || [ -n "$l" ]; do
        n=$((n + 1)); [ "$n" -ge 2 ] || continue
        l="${l%$'\r'}"; [ -n "$l" ] && sl="${sl:+$sl }$l"
      done < "$PG_F.approved"; } 2>/dev/null
  fi
  [ -d "${a%/*}" ] || mkdir -p "${a%/*}" 2>/dev/null
  { printf '%s\n%s\nreentries 0\n' "$e" "$sl" > "$a"; } 2>/dev/null
  return 0
}
pg_approve() { # line 1 of <sid>.approved, only when absent: an approval on record keeps its epoch + slugs
  if [ ! -f "$PG_F.approved" ]; then
    [ -d "${PG_F%/*}" ] || mkdir -p "${PG_F%/*}" 2>/dev/null
    { printf '%s\n' "${EPOCHSECONDS:-$(date +%s 2>/dev/null)}" > "$PG_F.approved"; } 2>/dev/null
  fi
  _pg_arm                                     # the approval ARMS the run (walk-away § 4.1)
  return 0
}
# Desktop re-entry (walk-away § 4.4, opt-in `reentry: desktop`): a fresh session whose prompt opens
# with the fixed prefix inherits the newest armed run's approval — within reentry_hours, under
# reentry_max. Writes <sid>.approved (now · the armed slugs) and nothing else; any doubt → nothing.
_pg_reenter() {
  local f e best='' be=0 l='' sl='' r='' now h mx
  [ -f "$PG_F.approved" ] && return 0
  _pg_primary || return 0
  _pg_cfg reentry session; [ "$REPLY" = desktop ] || return 0
  for f in "$PG_P"/.polaris/run/*.armed; do
    [ -f "$f" ] || continue
    e=''; { IFS= read -r e < "$f"; } 2>/dev/null; e="${e%$'\r'}"
    case "$e" in ''|*[!0-9]*) continue;; esac
    [ "$e" -gt "$be" ] && { be="$e"; best="$f"; }
  done
  [ -n "$best" ] || return 0
  _pg_cfg reentry_hours 12; h="$REPLY"; case "$h" in ''|*[!0-9]*) h=12;; esac
  _pg_cfg reentry_max 3; mx="$REPLY"; case "$mx" in ''|*[!0-9]*) mx=3;; esac
  now="${EPOCHSECONDS:-$(date +%s 2>/dev/null)}"; case "$now" in ''|*[!0-9]*) return 0;; esac
  [ $((now - be)) -le $((h * 3600)) ] || return 0
  { IFS= read -r l; IFS= read -r sl; IFS= read -r r; } < "$best" 2>/dev/null
  sl="${sl%$'\r'}"; r="${r%$'\r'}"; r="${r#reentries }"
  case "$r" in ''|*[!0-9]*) return 0;; esac
  [ "$r" -lt "$mx" ] || return 0
  [ -d "${PG_F%/*}" ] || mkdir -p "${PG_F%/*}" 2>/dev/null
  { printf '%s\n' "$now" > "$PG_F.approved"; [ -n "$sl" ] && printf '%s\n' $sl >> "$PG_F.approved"; } 2>/dev/null
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
    _pg_primary && [ -f "$PG_P/.polaris/run/$PG_SID.armed" ] && rm -f "$PG_P/.polaris/run/$PG_SID.armed" 2>/dev/null
  elif [ "$PG_WAS" = plan ]; then
    pg_approve
  fi
else
  PG_MODE="$PG_WAS"                          # no permission_mode in this payload → the recorded one
fi
pg_re='"prompt": *"POLARIS re-entry:'
[ "$PG_EV" = UserPromptSubmit ] && [[ $PG_H =~ $pg_re ]] && _pg_reenter

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
