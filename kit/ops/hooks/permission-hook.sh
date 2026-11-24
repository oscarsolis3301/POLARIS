#!/usr/bin/env bash
# POLARIS v6 — Claude Code permission hooks: an armed away run never sits on a permission prompt.
#
# WHY THIS EXISTS
#   In the three-hour failure (plans/walk-away.md) a permission dialog waited for a person who had
#   approved the plan and left. While the run is ARMED (<primary>/.polaris/run/*.armed, walk-away § 1)
#   and the owner is away, a prompt that would open is DENIED instead, with the one command that
#   parks the step for the owner (`defer`), so the model finishes the rest. Unarmed, or with the
#   owner here, this hook prints nothing and the dialog opens exactly as before.
#   It NEVER allows anything on the user's behalf — the one invariant this file exists under.
#
# THE CONTRACT — ops/contracts/walk-away.md § 4.3. Registered twice by .claude/settings.json:
#   permission-hook.sh request   PermissionRequest — armed + away → deny with the park line
#   permission-hook.sh denied    PermissionDenied  — armed → append <primary>/.polaris/run/denied.tsv
#                                (epoch<TAB>tool<TAB>first 160 chars of the command or path)
#   Payloads (code.claude.com/docs/en/hooks, verified 2026-11-24): PermissionRequest carries
#   tool_name + tool_input + permission_mode, and denies through hookSpecificOutput.decision
#   {"behavior":"deny","message":…}; PermissionDenied (auto-mode classifier denials) carries
#   tool_name, tool_input, tool_use_id and reason, and its output is ignored but for `retry`.
#   away ⇔ the session's <sid>.approved exists and its mode is auto | bypassPermissions | dontAsk —
#   presence-guard.sh's state, read the same way handover-hook.sh's _hh_away reads it.
#
# FAIL-OPEN, AND FAST
#   Any parse miss, unset HOME, bad <sid>, no board, no armed file ⇒ no output, exit 0 — the
#   harness then shows its dialog as it always did. Builtins on the common path (one glob that
#   matches nothing); a fork only on an armed run (sed for one CONVENTIONS key, date).
#
#   --test as $1: print ONE word instead (deny:away · allow:here · denied:recorded · denied:not-armed)
#   after the SAME state writes.

export LC_ALL=C
PH_TEST=''; PH_SUB="${1:-}"
[ "$PH_SUB" = --test ] && { PH_TEST=1; PH_SUB="${2:-}"; }
PH_SAY='The owner approved the plan and left. Do not ask. Take the recommended option and write it down as an assumed: line; if there is no safe default, park that one piece and finish the rest.'
PH_NO=allow:here; [ "$PH_SUB" = denied ] && PH_NO=denied:not-armed

_ph_end() { # _ph_end <word> — the test word under --test, otherwise nothing; always exit 0
  [ -n "$PH_TEST" ] && printf '%s\n' "$1"
  exit 0
}
case "$PH_SUB" in request|denied) ;; *) _ph_end "$PH_NO";; esac

# --- read the hook JSON (builtin; no fork) -----------------------------------
IN=''
IFS= read -r -d '' IN 2>/dev/null
[ -n "$IN" ] || _ph_end "$PH_NO"
PH_H="$IN"; PH_TI=''
case "$IN" in *'"tool_input":'*) PH_H="${IN%%\"tool_input\":*}"; PH_TI="${IN#*\"tool_input\":}";; esac
PH_SID=''; PH_TOOL=''; PH_MODE=''; PH_CWD=''; PH_P=''
ph_re='"session_id": *"([^"]*)"';      [[ $PH_H =~ $ph_re ]] && PH_SID="${BASH_REMATCH[1]}"
ph_re='"tool_name": *"([^"]*)"';       [[ $PH_H =~ $ph_re ]] && PH_TOOL="${BASH_REMATCH[1]}"
ph_re='"permission_mode": *"([^"]*)"'; [[ $PH_H =~ $ph_re ]] && PH_MODE="${BASH_REMATCH[1]}"
ph_re='"cwd": *"([^"]*)"';             [[ $PH_H =~ $ph_re ]] && PH_CWD="${BASH_REMATCH[1]}"
case "$PH_SID" in ''|*[!A-Za-z0-9_-]*) _ph_end "$PH_NO";; esac
case "$PH_TOOL" in *[!A-Za-z0-9_.:-]*) PH_TOOL=tool;; '') PH_TOOL=tool;; esac
case "$PH_MODE" in *[!A-Za-z]*) PH_MODE='';; esac

# The primary: the cwd when it holds a board; a worktree cwd names its primary. JSON-escaped on
# Windows (C:\\Users\\…), so \ → / and the doubled / folds — presence-guard.sh's _pg_primary.
_ph_primary() {
  local c="$PH_CWD" s='//'
  c="${c//\\//}"; c="${c//$s//}"
  case "$c" in */.polaris/wt/*) c="${c%%/.polaris/wt/*}";; esac
  [ -n "$c" ] && [ -d "$c/ops/board" ] && PH_P="$c"
  [ -n "$PH_P" ]
}
_ph_cfg() { # one CONVENTIONS key: $1 key, $2 default -> REPLY (a fork — armed runs only)
  local f="$PH_P/ops/CONVENTIONS.md" v
  REPLY="$2"; [ -f "$f" ] || return 0
  v="$(sed -n "s/^$1:[[:space:]]*\([^#]*\).*\$/\1/p" "$f" 2>/dev/null | head -1)"
  v="${v%"${v##*[![:space:]]}"}"
  [ -n "$v" ] && REPLY="$v"
  return 0
}
_ph_armed() { # rc 0 = some <primary>/.polaris/run/*.armed within reentry_hours (default 12)
  local f e be=0 h now
  for f in "$PH_P"/.polaris/run/*.armed; do
    [ -f "$f" ] || continue
    e=''; { IFS= read -r e < "$f"; } 2>/dev/null; e="${e%$'\r'}"
    case "$e" in ''|*[!0-9]*) continue;; esac
    [ "$e" -gt "$be" ] && be="$e"
  done
  [ "$be" -gt 0 ] || return 1
  _ph_cfg reentry_hours 12; h="$REPLY"; case "$h" in ''|*[!0-9]*) h=12;; esac
  now="${EPOCHSECONDS:-$(date +%s 2>/dev/null)}"; case "$now" in ''|*[!0-9]*) return 1;; esac
  [ $((now - be)) -le $((h * 3600)) ]
}
_ph_away() { # the owner left: an approval on record and an away mode (payload, else <sid>.mode)
  local d m="$PH_MODE"
  [ -n "${HOME:-}" ] || return 1
  d="$HOME/.claude/polaris/model-state"
  [ -f "$d/$PH_SID.approved" ] || return 1
  [ -n "$m" ] || { { IFS= read -r m < "$d/$PH_SID.mode"; } 2>/dev/null; m="${m%$'\r'}"; }
  case "$m" in auto|bypassPermissions|dontAsk) return 0;; esac
  return 1
}
# What the tool would have done, as its RAW JSON string (escapes intact, so it splices straight back
# into JSON and never holds a real TAB or newline): the command, else the path, else the tool name.
_ph_target() {
  local k re
  REPLY="$PH_TOOL"
  for k in command file_path notebook_path path url; do
    re="\"$k\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
    [[ $PH_TI =~ $re ]] && { REPLY="${BASH_REMATCH[1]}"; return 0; }
  done
  return 0
}

_ph_primary || _ph_end "$PH_NO"
_ph_armed || _ph_end "$PH_NO"

if [ "$PH_SUB" = denied ]; then             # armed: one line per denial; never prints
  _ph_target
  [ -d "$PH_P/.polaris/run" ] || mkdir -p "$PH_P/.polaris/run" 2>/dev/null
  { printf '%s\t%s\t%s\n' "${EPOCHSECONDS:-$(date +%s 2>/dev/null)}" "$PH_TOOL" "${REPLY:0:160}" \
      >> "$PH_P/.polaris/run/denied.tsv"; } 2>/dev/null
  _ph_end denied:recorded
fi

_ph_away || _ph_end allow:here               # armed, owner here: the dialog opens as always
_ph_target
[ -n "$PH_TEST" ] && _ph_end deny:away
printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"%s This needs a person: park it — bash ops/polaris defer -m \\"%s needed approval\\" -- %s"}}}\n' \
  "$PH_SAY" "$PH_TOOL" "$REPLY" 2>/dev/null
exit 0
