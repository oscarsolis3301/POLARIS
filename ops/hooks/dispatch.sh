#!/usr/bin/env bash
# POLARIS v7 — the ONE Claude Code hook: every event, every project, one process per tool call.
#
# WHY THIS EXISTS
#   Before 7.0.0 a Bash call in a POLARIS repo started four hook processes (readonly-allow,
#   checkout-guard, presence-guard and the machine-level model-guard), each registered per repo. This
#   file is the single user-level entry (ops/contracts/hook-dispatch.md § 2): it folds those four
#   pure-bash guards in-process as functions (§ 1), `exec`s the rest, stands down outside POLARIS
#   projects and in vendored ones (whose own project hooks still do the work), and hands SessionStart
#   to dispatch-session.sh (§ 6). `--setup` registers it through the shim (§ 3-4); nothing else does.
#
# ===== IT MUST FAIL OPEN. =====
#   Guards fail open, so a bug here would switch every guard off at once — the hook-dispatch golden
#   replays every guard battery through this file. Any internal error ⇒ exit 0 with no output (the
#   EXIT trap below), EXCEPT a model deny already decided, which is printed before anything else runs.
#
# THE VERDICT — one JSON object, the one Claude Code reached from the separate hooks: deny > ask >
#   allow > nothing. A guard's HOUT is printed verbatim; model-guard's pending effort note (its only
#   PreToolUse stdout) rides inside that object as additionalContext — two objects would not parse.
#
# TWO SECURITY PIECES
#   § 4 trust tier: `_ra_hook` (what is auto-APPROVED) comes from $DP_TRUST — the copy only the owner's
#       `--setup` writes — when that file exists, else from this kit. An automatic kit update can change
#       what is denied, never widen what is approved.
#   § 5 genuine launcher: in a machine project a command allowed only because it runs ops/polaris is
#       answered `ask` unless that file is byte-for-byte this kit's ops/launcher.
#
# SPEED — the stand-down path and a machine project's unguarded tools (Read, Grep, …) are builtins
#   only: no `$(`, no backtick, no pipe between the HOT PATH markers (golden hook-budget, PATH emptied).
#
#   dispatch.sh <event>              the hook (stdin = the hook JSON)
#   dispatch.sh --as <guard> [args]  tests only: exactly `<guard>.sh [args]` standalone, through this
#                                    file's sourcing and project test (§ 2 step 6)

DP_RC=0
trap 'exit "$DP_RC"' EXIT                      # fail open: a crash anywhere below still exits 0

# --- where the kit is: the directory this file lives in, two up (§ 2 step 4) -----------------------
DP_SELF="${BASH_SOURCE[0]//\\//}"
DP_KIT=.
case "$DP_SELF" in */*) DP_KIT="${DP_SELF%/*}/../..";; *) DP_KIT=../..;; esac
case "$DP_KIT" in
  /*) ;;
  [A-Za-z]:*) ;;
  *) DP_KIT="$PWD/$DP_KIT";;
esac
DP_HK="$DP_KIT/ops/hooks"
DP_SH="${BASH:-bash}"                          # the running bash by path: an exec needs no PATH lookup
DP_NOTGEN='ops/polaris in this project is not the POLARIS launcher — approve this run yourself'

# _dp_where — the project test, builtins only (§ 2 step 2). DP_KIND = machine | vendored | none,
# DP_ROOT = the project root. CLAUDE_PROJECT_DIR is the harness's word for the project, so its walk
# comes first; then a task-worktree cwd names its primary; then the cwd's own walk (only when the
# harness named no project). ops/lib/ beside ops/polaris = a vendored copy: its own hooks do the rest.
# >>> HOT PATH
# _dp_src <guard> <entry fn> — source one guard's function form; rc 1 when the file or its entry
# function is missing (that guard is then skipped: fail open). readonly-allow comes from the TRUST
# TIER when there is one (§ 4). No `local`: a sourced file's top-level assignments must stay global.
_dp_src() {
  DP_F="$DP_HK/$1.sh"
  if [ "$1" = readonly-allow ]; then
    if [ -n "${DP_TRUST:-}" ]; then
      if [ -f "$DP_TRUST" ]; then DP_F="$DP_TRUST"; fi
    fi
  fi
  if [ ! -f "$DP_F" ]; then return 1; fi
  . "$DP_F"
  declare -F "$2" >/dev/null
}
_dp_up() {
  DP_D="${1//\\//}"
  while [ -n "$DP_D" ]; do
    if [ -f "$DP_D/ops/polaris" ]; then DP_ROOT="$DP_D"; return 0; fi
    case "$DP_D" in */*) DP_D="${DP_D%/*}";; *) return 1;; esac
  done
  return 1
}
_dp_where() {
  DP_KIND=none; DP_ROOT=''
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    _dp_up "$CLAUDE_PROJECT_DIR"
  fi
  if [ -z "$DP_ROOT" ]; then
    DP_D="${PWD//\\//}"
    case "$DP_D" in */.polaris/wt/*) DP_ROOT="${DP_D%%/.polaris/wt/*}";; esac
  fi
  if [ -z "$DP_ROOT" ] && [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
    _dp_up "$PWD"
  fi
  if [ -z "$DP_ROOT" ]; then return 0; fi
  DP_KIND=machine
  if [ -d "$DP_ROOT/ops/lib" ]; then DP_KIND=vendored; fi
  return 0
}

# _dp_raw — print HOUT / HERR / HRC exactly as a standalone guard's face does, and exit.
_dp_raw() {
  printf '%s' "$HOUT"
  if [ -n "$HERR" ]; then printf '%s' "$HERR" >&2; fi
  DP_RC="$HRC"; exit "$HRC"
}
# <<< HOT PATH

# _dp_out <stdout> <stderr> <rc> — the one verdict, with model-guard's note (DP_MO) folded in, and exit.
_dp_out() {
  HOUT="$1"; HERR="$2"; HRC="$3"
  if [ -n "$DP_MO" ]; then
    if [ -z "$HOUT" ]; then HOUT="$DP_MO"
    elif [ "$HOUT" != "$DP_MO" ]; then _dp_join "$HOUT" "$DP_MO"; HOUT="$REPLY"; fi
  fi
  _dp_raw
}

# _dp_join <decision> <note> → REPLY: the note's additionalContext inside the decision's object.
_dp_join() {
  local d="$1" n="$2" c
  REPLY="$d$n"
  case "$n" in *'"additionalContext":"'*) ;; *) return 0;; esac
  case "$d" in '{"hookSpecificOutput":{'*'}}'*) ;; *) return 0;; esac
  case "$d" in *'"additionalContext":'*) return 0;; esac
  c="${n#*\"additionalContext\":\"}"; c="${c%\"\}\}*}"
  REPLY="${d%\}\}*},\"additionalContext\":\"$c\"}}"$'\n'
}

# _dp_take — after a guard ran: an exit-code block or a JSON deny is printed NOW (first deny wins);
# an ask outranks an allow; the best so far waits in DP_V / DP_VO / DP_VE.
_dp_take() {
  if [ "$HRC" != 0 ]; then _dp_out "$HOUT" "$HERR" "$HRC"; fi
  case "$HOUT" in
    *'"permissionDecision":"deny"'*) _dp_out "$HOUT" "$HERR" 0;;
    *'"permissionDecision":"ask"'*) if [ "$DP_V" != ask ]; then DP_V=ask; DP_VO="$HOUT"; DP_VE="$HERR"; fi;;
    *'"permissionDecision":"allow"'*) if [ -z "$DP_V" ]; then DP_V=allow; DP_VO="$HOUT"; DP_VE="$HERR"; fi;;
  esac
  return 0
}

# _dp_same <a> <b> — byte-equal, with builtin reads. A NUL byte in either one ends `read -d ''` early
# (rc 0 instead of EOF's 1), so it counts as different: nothing can hide behind a NUL.
_dp_same() {
  local x='' y='' LC_ALL=C
  [ -f "$1" ] && [ -f "$2" ] || return 1
  if IFS= read -r -d '' x < "$1"; then return 1; fi
  if IFS= read -r -d '' y < "$2"; then return 1; fi
  [ "$x" = "$y" ]
}

# _dp_genuine — rc 0 when every ops/polaris a relative `bash ops/polaris` could reach here is this
# kit's launcher: the project root's, the payload cwd's when it has its own, and the one under every
# `cd`/`pushd` target the command names (§ 5) — `cd sub && bash ops/polaris …` runs sub's copy. A
# target that cannot be resolved without running the shell (`$`, backtick, `~`, a glob, a quote or
# backslash, `-`, a bare `cd`) fails closed. Builtins only.
_dp_genuine() {
  local c='' s='' d='' re
  _dp_same "$DP_ROOT/ops/polaris" "$DP_KIT/ops/launcher" || return 1
  DP_RE='"cwd": *"([^"]*)"'
  [[ $DP_HEAD =~ $DP_RE ]] && c="${BASH_REMATCH[1]}"
  c="${c//\\\\/\\}"; c="${c//\\//}"
  if [ -n "$c" ] && [ -f "$c/ops/polaris" ]; then _dp_same "$c/ops/polaris" "$DP_KIT/ops/launcher" || return 1; fi
  re='"command": *"(.*)'
  [[ $IN =~ $re ]] && s="${BASH_REMATCH[1]}"
  # A bare cd ($HOME's copy) or one followed by a JSON escape (\t, \") fails closed; \n is a break.
  re='(^|[^A-Za-z0-9_./-]|\\[nrt])(cd|pushd)([[:space:]]*$|[[:space:]]*[;&|)"\\])'
  [[ $s =~ $re ]] && return 1
  [ -n "$c" ] || c="$DP_ROOT"
  re='(^|[^A-Za-z0-9_./-]|\\[nrt])(cd|pushd)[[:space:]]+([^;&|()"[:space:]]+)'
  while [[ $s =~ $re ]]; do
    d="${BASH_REMATCH[3]}"; s="${s#*"${BASH_REMATCH[0]}"}"
    case "$d" in *'$'*|*'`'*|'~'*|*'*'*|*'?'*|*'['*|*'"'*|*\'*|*'\'*|-*) return 1;; esac
    case "$d" in /*|[A-Za-z]:/*) c="$d";; *) c="$c/$d";; esac
    if [ -f "$c/ops/polaris" ]; then _dp_same "$c/ops/polaris" "$DP_KIT/ops/launcher" || return 1; fi
  done
  return 0
}

# _dp_bash — PreToolUse Bash | PowerShell | AskUserQuestion in a machine project (§ 2 step 3):
# presence → checkout deny → read-only allow (from the trust tier) → the genuine-launcher check.
_dp_bash() {
  DP_V=''; DP_VO=''; DP_VE=''
  if _dp_src presence-guard _pg_hook; then _pg_hook; _dp_take; fi
  case "$DP_TOOL" in Bash|PowerShell) ;; *) _dp_out "$DP_VO" "$DP_VE" 0;; esac
  if _dp_src checkout-guard _cg_hook; then _cg_hook; _dp_take; fi
  if _dp_src readonly-allow _ra_hook; then
    _ra_hook
    case "$HOUT" in
      *'"permissionDecision":"allow"'*)
        if ! _dp_genuine; then
          # Did the allow need ops/polaris? Ask the parser again with that one door shut. A trust tier
          # without the door's function: any mention of ops/polaris keeps its prompt.
          if declare -F ra_polaris_ok >/dev/null; then
            ra_polaris_ok() { return 1; }
            DP_AO="$HOUT"; _ra_hook
            case "$HOUT" in *'"permissionDecision":"allow"'*) ;; *) HOUT='';; esac
            if [ -n "$HOUT" ]; then HOUT="$DP_AO"; fi
          else
            case "$IN" in *ops/polaris*) HOUT='';; esac
          fi
          if [ -z "$HOUT" ]; then
            printf -v HOUT '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$DP_NOTGEN"
          fi
        fi;;
    esac
    _dp_take
  fi
  _dp_out "$DP_VO" "$DP_VE" 0
}

# _dp_session — SessionStart (§ 6): dispatch-session.sh's `_ds_session <kind> <dir> <model-guard text>`
# (T-346: reads IN, sets HOUT/HERR/HRC, never prints or exits) builds the whole output when the file is
# there. The kind this file already proved is passed on; no project → `auto`, its own builtins test
# (it tells a plain git repo from elsewhere). Absent or broken → model-guard's result alone.
_dp_session() {
  HOUT="$DP_MO"; HERR="$DP_ME"; HRC="$DP_MR"
  if [ -f "$DP_HK/dispatch-session.sh" ] && . "$DP_HK/dispatch-session.sh" && declare -F _ds_session >/dev/null; then
    case "$DP_KIND" in
      machine) _ds_session machine "$DP_ROOT" "$DP_MO";;
      vendored) _ds_session vendored "$DP_ROOT" "$DP_MO";;
      *) _ds_session auto "${CLAUDE_PROJECT_DIR:-$PWD}" "$DP_MO";;
    esac
  fi
  _dp_raw
}

# _dp_as <guard> [args…] — the replay face (§ 2 step 6). model-guard answers in every project, as the
# machine-level hook always did; the others only where the dispatcher would run them.
_dp_as() {
  DP_G="${1:-}"; shift
  case "$DP_G" in
    model-guard)
      if [ "${1:-}" = install ]; then exec "$DP_SH" "$DP_HK/model-guard.sh" "$@"; fi
      IN=''; IFS= read -r -d '' IN 2>/dev/null
      _dp_src model-guard _mg_hook || exit 0
      _mg_hook "$@"; _dp_raw;;
    presence-guard|checkout-guard|readonly-allow) ;;
    ownership-guard|permission-hook|handover-hook)
      _dp_where
      [ "$DP_KIND" = machine ] || exit 0
      exec "$DP_SH" "$DP_HK/$DP_G.sh" "$@";;
    *) exit 0;;
  esac
  _dp_where
  [ "$DP_KIND" = machine ] || exit 0
  IN=''
  case "$DP_G:${1:-}" in
    checkout-guard:--test) ;;
    readonly-allow:--test) ;;
    readonly-allow:--test-ps) ;;
    *) IFS= read -r -d '' IN 2>/dev/null;;
  esac
  case "$DP_G" in presence-guard) DP_FN=_pg_hook;; checkout-guard) DP_FN=_cg_hook;; *) DP_FN=_ra_hook;; esac
  _dp_src "$DP_G" "$DP_FN" || exit 0
  case "$DP_G" in
    presence-guard) _pg_hook "$@";;
    checkout-guard) _cg_hook ${1+"$@"};;
    readonly-allow) _ra_hook ${1+"$@"};;
  esac
  _dp_raw
}

# ===================================================================================================
DP_EV="${1:-}"
if [ "$DP_EV" = --as ]; then shift; _dp_as "$@"; fi

# >>> HOT PATH
# Stop / permission events: no model-guard, no stdin read — the hook gets the harness's bytes as sent.
DP_X=''
case "$DP_EV" in
  Stop) DP_X="handover-hook.sh stop";;
  SubagentStop) DP_X="handover-hook.sh substop";;
  StopFailure) DP_X="handover-hook.sh stopfail";;
  PermissionRequest) DP_X="permission-hook.sh request";;
  PermissionDenied) DP_X="permission-hook.sh denied";;
  PreToolUse) ;;
  PostToolUse) ;;
  SessionStart) ;;
  PreModelSwitch) ;;
  PostModelSwitch) ;;
  UserPromptSubmit) ;;
  *) exit 0;;
esac
if [ -n "$DP_X" ]; then
  _dp_where
  if [ "$DP_KIND" != machine ]; then exit 0; fi
  exec "$DP_SH" "$DP_HK/${DP_X% *}" "${DP_X#* }"
fi

IN=''; IFS= read -r -d '' IN 2>/dev/null
DP_HEAD="$IN"
case "$IN" in *'"tool_input":'*) DP_HEAD="${IN%%\"tool_input\":*}";; esac
DP_TOOL=''
DP_RE='"tool_name": *"([^"]*)"'
if [[ $DP_HEAD =~ $DP_RE ]]; then DP_TOOL="${BASH_REMATCH[1]}"; fi

# --- step 1: the model ban + effort bookkeeping, in every project, on the events it answers ---------
DP_MO=''; DP_ME=''; DP_MR=0; DP_M=1
case "$DP_EV" in
  UserPromptSubmit) DP_M='';;
  PostToolUse) if [ "$DP_TOOL" != Agent ]; then DP_M=''; fi;;
esac
if [ -n "$DP_M" ] && _dp_src model-guard _mg_hook; then
  _mg_hook
  if [ "$HRC" != 0 ]; then _dp_raw; fi          # a model deny is decided: it is printed whatever follows
  DP_MO="$HOUT"; DP_ME="$HERR"; DP_MR="$HRC"
fi

# --- step 2: where are we? -------------------------------------------------------------------------
_dp_where
if [ "$DP_EV" = SessionStart ]; then _dp_session; fi
if [ "$DP_KIND" != machine ]; then
  HOUT="$DP_MO"; HERR="$DP_ME"; HRC="$DP_MR"; _dp_raw
fi
case "$DP_EV:$DP_TOOL" in
  PreToolUse:Bash) ;;
  PreToolUse:PowerShell) ;;
  PreToolUse:AskUserQuestion) ;;
  PreToolUse:Edit) ;;
  PreToolUse:Write) ;;
  PreToolUse:MultiEdit) ;;
  PreToolUse:NotebookEdit) ;;
  PostToolUse:ExitPlanMode) ;;
  UserPromptSubmit:*) ;;
  *) HOUT="$DP_MO"; HERR="$DP_ME"; HRC="$DP_MR"; _dp_raw;;
esac
# <<< HOT PATH

# --- step 3: a machine project ---------------------------------------------------------------------
case "$DP_EV:$DP_TOOL" in
  PreToolUse:Edit|PreToolUse:Write|PreToolUse:MultiEdit|PreToolUse:NotebookEdit)
    # The edit guard keeps its own process. A pending effort note is handed over only on an allow —
    # a refusal's stdout is lost — so then it runs as a child instead of being exec'd.
    if [ -z "$DP_MO" ]; then exec "$DP_SH" "$DP_HK/ownership-guard.sh" <<<"$IN"; fi
    "$DP_SH" "$DP_HK/ownership-guard.sh" <<<"$IN"; DP_R=$?
    if [ "$DP_R" = 0 ]; then printf '%s' "$DP_MO"; fi
    DP_RC="$DP_R"; exit "$DP_R";;
  PreToolUse:*) _dp_bash;;
  PostToolUse:ExitPlanMode)
    DP_V=''; DP_VO=''; DP_VE=''
    if _dp_src presence-guard _pg_hook; then _pg_hook; _dp_out "$HOUT" "$HERR" "$HRC"; fi
    _dp_out '' '' 0;;
  UserPromptSubmit:*)
    # Two hooks printed here, in this order: the run clock, then presence.
    if [ -f "$DP_HK/handover-hook.sh" ]; then "$DP_SH" "$DP_HK/handover-hook.sh" prompt <<<"$IN"; fi
    if _dp_src presence-guard _pg_hook; then _pg_hook; _dp_raw; fi;;
esac
exit 0
