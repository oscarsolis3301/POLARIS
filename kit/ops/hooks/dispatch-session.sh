#!/usr/bin/env bash
# POLARIS v7 — the session context: what a SessionStart puts in front of the model
# (ops/contracts/hook-dispatch.md § 6, ops/contracts/shared-kit.md § 9).
#
# WHY THIS EXISTS
#   A joined project carries no protocol block in its CLAUDE.md — only a three-line pointer — so
#   the protocol has to arrive another way. The one user-level dispatcher sources this file and
#   calls `_ds_session` on every SessionStart (startup | resume | clear | compact):
#     machine project → ONE JSON object whose additionalContext is, in order:
#       (a) `bash "<kit>/ops/polaris" router` — the trimmed kit/CLAUDE.md, ≤ 8,000 bytes
#       (b) `voice: <value> (<repo|machine|default>) — <rule>`
#       (c) adhd on → one header line and the five "facts" lines of the vendored i-have-adhd skill, verbatim
#       (d) startup → the model guard's SessionStart text, then update-hook.sh's output;
#           compact | resume → handover-hook.sh anchor's text
#       (a)-(c) stay ≤ 9,000 bytes (golden session-context); the hook limit is 10,000 characters.
#     a git repo without POLARIS → the ONE zero-touch line (or nothing), zero forks
#     vendored, or anywhere else → nothing (the repo's own project hooks do the rest)
#
# THE INTERFACE (function form, the same as the four guards — hook-dispatch.md § 1)
#   _ds_session [<kind>] [<dir>] [<model-guard text>]
#     kind  machine · plain · vendored · auto (default: decided here with builtins, § 2 step 2)
#     dir   machine: the project root · plain: where the walk for `.git` starts
#           (default: the payload's cwd, else CLAUDE_PROJECT_DIR, else $PWD)
#   Reads the hook JSON from IN. Never prints, never exits, never reads stdin; sets HOUT (stdout
#   bytes) · HERR · HRC (always 0: a session hook never fails the session). Safe under `set -u`.
#   Names: `_ds_` functions, `DS_` globals; shared on purpose: IN, HOUT, HERR, HRC, REPLY.
#
# THE KEYS
#   voice / adhd: the repo's ops/CONVENTIONS.md line, else this computer's preferences file
#   (POLARIS_PREFS overrides its path; set-but-empty = that layer off), else the default. A value
#   that is not one of the key's choices reads as unset. auto_setup / owners: the preferences file
#   only (machine keys, shared-kit § 9). All read with `read` builtins.

# <kit>/ops: this file lives in <kit>/ops/hooks/ — the versioned store copy the shim chose.
DS_OPS="${BASH_SOURCE[0]%/*}"
case "$DS_OPS" in "${BASH_SOURCE[0]}") DS_OPS=..;; hooks) DS_OPS=.;; */hooks) DS_OPS="${DS_OPS%/hooks}";; *) DS_OPS="$DS_OPS/..";; esac
DS_STD='everyday words, no git or test vocabulary; ✅ lines while working, 🎉 only after finish exits 0'

# _ds_val <raw> → REPLY: a config value — CR, leading blanks, a ` # comment` and trailing blanks
# gone; a value that is only a comment reads empty (core.sh cfg's semantics).
_ds_val() {
  local s="${1%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  case "$s" in '#'*) s='';; esac
  s="${s%%[[:space:]]#*}"
  s="${s%"${s##*[![:space:]]}"}"
  REPLY="$s"
}

# _ds_key <file> <key> → REPLY: the first `<key>:` line's value; rc 1 when absent or blank.
_ds_key() {
  local line
  REPLY=''
  [ -n "$1" ] && [ -f "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$2:"*) _ds_val "${line#"$2:"}"; [ -n "$REPLY" ]; return;; esac
  done < "$1"
  return 1
}

_ds_prefs() { REPLY="${POLARIS_PREFS-${POLARIS_HOME:-${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/polaris}/preferences}"; }

# _ds_layer <root> <key> <choices…> → DS_V (value) and DS_L (repo | machine | default; empty = default)
_ds_layer() {
  local root="$1" key="$2" m c; shift 2
  DS_V=''; DS_L=''
  _ds_prefs; m="$REPLY"
  for c in repo machine; do
    if [ "$c" = repo ]; then _ds_key "$root/ops/CONVENTIONS.md" "$key" || continue
    else _ds_key "$m" "$key" || continue; fi
    case " $* " in *" $REPLY "*) DS_V="$REPLY"; DS_L="$c"; return 0;; esac
  done
}

# _ds_json <text> → REPLY: <text> as the inside of a JSON string.
_ds_json() {
  local LC_ALL=C s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  s="${s//[$'\001'-$'\010'$'\013'$'\014'$'\016'-$'\037']/}"
  REPLY="$s"
}

# _ds_in <key> → REPLY: a string field of the payload (backslashes folded to /, for cwd).
_ds_in() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  REPLY=''
  [[ ${IN:-} =~ $re ]] || return 1
  REPLY="${BASH_REMATCH[1]}"; REPLY="${REPLY//\\\\/\\}"; REPLY="${REPLY//\\//}"
  [ -n "$REPLY" ]
}

# _ds_where <dir> → DS_KIND (machine | vendored | plain | none) and DS_ROOT, builtins only.
_ds_where() {
  local d="$1"
  DS_KIND=none; DS_ROOT=''
  case "$d" in */.polaris/wt/*) d="${d%%/.polaris/wt/*}"; DS_KIND=machine; DS_ROOT="$d"
    [ -d "$d/ops/lib" ] && DS_KIND=vendored; return 0;; esac
  while [ -n "$d" ]; do
    if [ -f "$d/ops/polaris" ]; then
      DS_ROOT="$d"; if [ -d "$d/ops/lib" ]; then DS_KIND=vendored; else DS_KIND=machine; fi; return 0
    fi
    [ "${d%/*}" = "$d" ] && break
    d="${d%/*}"
  done
  DS_KIND=plain
}

# _ds_zero <dir> → HOUT: the zero-touch line (shared-kit § 9), or nothing. Zero forks.
_ds_zero() {
  local d="$1" g='' mode owners own url line sec='' origin=0 upstream=0 o
  while [ -n "$d" ]; do
    if [ -e "$d/.git" ]; then g="$d"; break; fi
    [ "${d%/*}" = "$d" ] && break
    d="${d%/*}"
  done
  [ -n "$g" ] && [ -d "$g/.git" ] || return 0        # no repo, or a linked worktree (.git is a file)
  [ -e "$g/ops/polaris" ] && return 0
  if [ -f "$g/.git/polaris-setup" ]; then
    IFS= read -r line < "$g/.git/polaris-setup" 2>/dev/null
    _ds_val "${line:-}"; [ "$REPLY" = never ] && return 0
  fi
  _ds_prefs; mode=ask
  _ds_key "$REPLY" auto_setup && case "$REPLY" in ask|auto|off) mode="$REPLY";; esac
  [ "$mode" = off ] && return 0
  if [ "$mode" = auto ]; then
    url=''
    if [ -f "$g/.git/config" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        _ds_val "$line"; line="$REPLY"
        case "$line" in
          '[remote "origin"]') sec=origin; origin=1;;
          '[remote "upstream"]') sec=upstream; upstream=1;;
          '['*) sec='';;
          url*=*) [ "$sec" = origin ] && { url="${line#*=}"; url="${url#"${url%%[![:space:]]*}"}"; };;
        esac
      done < "$g/.git/config"
    fi
    [ "$upstream" = 1 ] && mode=ask
    [ -d "$g/ops" ] && mode=ask
    if [ "$mode" = auto ] && [ "$origin" = 1 ]; then
      url="${url%/}"; url="${url%.git}"; url="${url%/*}"; url="${url##*[/:]}"
      _ds_prefs; owners=''; _ds_key "$REPLY" owners && owners="$REPLY"
      own=0; o="$owners,"
      while [ -n "$o" ]; do
        line="${o%%,*}"; o="${o#*,}"
        line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
        [ -n "$url" ] && [ "$line" = "$url" ] && own=1
      done
      [ "$own" = 1 ] || mode=ask
    fi
  fi
  if [ "$mode" = auto ]; then
    HOUT="POLARIS is not set up in this project. Before the first change the owner asks for, run bash \"$DS_OPS/polaris\" join, then bash ops/polaris role INIT (entered from a work request)."$'\n'
  else
    HOUT="POLARIS is not set up in this project. If the owner's request changes it, ask once (here · all my projects · not here); here → bash \"$DS_OPS/polaris\" join · all → also bash ops/polaris prefs --set auto_setup=auto · not here → write never to .git/polaris-setup."$'\n'
  fi
}

# _ds_context <root> → REPLY: blocks (a)-(c), each ending in a newline.
_ds_context() {
  local root="$1" t r v line on=0 n=0 skill
  t="$( cd "$root" 2>/dev/null && bash "$DS_OPS/polaris" router 2>/dev/null )"
  [ -n "$t" ] && t="$t"$'\n'
  _ds_layer "$root" voice standard technical
  v="${DS_V:-standard}"
  r="$DS_STD"; [ "$v" = technical ] && r='terse and dense'
  t="$t"$'\n'"voice: $v (${DS_L:-default}) — $r"$'\n'
  _ds_layer "$root" adhd on off
  if [ "$DS_V" = on ]; then
    t="$t"'adhd: on — shape every reply for a reader with ADHD (the /i-have-adhd skill has the rules). The five facts:'$'\n'
    skill="$DS_OPS/../.claude/skills/i-have-adhd/SKILL.md"
    if [ -f "$skill" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [ "$on" = 0 ]; then [ "$line" = 'Five facts drive every rule below:' ] && on=1; continue; fi
        case "$line" in '') [ "$n" -gt 0 ] && break; continue;; [1-5]'. '*) t="$t$line"$'\n'; n=$((n+1));; *) break;; esac
      done < "$skill"
    fi
  fi
  REPLY="$t"
}

_ds_session() {
  local kind="${1:-auto}" dir="${2:-}" mg="${3:-}" src='' t x
  HOUT=''; HERR=''; HRC=0
  if [ -z "$dir" ]; then
    if _ds_in cwd; then dir="$REPLY"
    elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then dir="${CLAUDE_PROJECT_DIR//\\//}"
    else dir="$PWD"; fi
  fi
  if [ "$kind" = auto ]; then _ds_where "$dir"; kind="$DS_KIND"; [ -n "$DS_ROOT" ] && dir="$DS_ROOT"; fi
  case "$kind" in
    plain|none) _ds_zero "$dir"; return 0;;
    machine) ;;
    *) return 0;;
  esac
  _ds_in source && src="$REPLY"
  _ds_context "$dir"; t="$REPLY"
  case "$src" in
    startup|'')
      [ -n "$mg" ] && t="$t$mg"$'\n'
      x="$( cd "$dir" 2>/dev/null && bash "$DS_OPS/hooks/update-hook.sh" <<<"${IN:-}" 2>/dev/null )"
      [ -n "$x" ] && t="$t$x"$'\n';;
    compact|resume)
      x="$( cd "$dir" 2>/dev/null && bash "$DS_OPS/hooks/handover-hook.sh" anchor <<<"${IN:-}" 2>/dev/null )"
      [ -n "$x" ] && t="$t$x"$'\n';;
  esac
  _ds_json "$t"
  HOUT="{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$REPLY\"}}"$'\n'
  return 0
}

# --- standalone face: executed, not sourced → print HOUT, exit 0 (tests; hook-dispatch.md § 1) ---
case "${BASH_SOURCE[0]}" in "$0") IN=''; IFS= read -r -d '' IN 2>/dev/null; _ds_session "$@"; printf '%s' "$HOUT"; [ -z "$HERR" ] || printf '%s' "$HERR" >&2; exit "$HRC";; esac
