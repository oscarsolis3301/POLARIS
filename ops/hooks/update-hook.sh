#!/usr/bin/env bash
# POLARIS v6 — Claude Code SessionStart hook (matcher `startup`): the repo updates ITSELF when quiet.
#
# WHY THIS EXISTS
#   Installed POLARIS repos went stale for months while the fixes for their own slow landing tail
#   sat published (measured 2026-09-08: 6.0.0 / 5.23.0 / unversioned). `update --auto` (lib/admin.sh)
#   applies a minor/patch update only when the board is quiet and the kit's own paths are clean;
#   this hook is the one thing that CALLS it. A fresh session by definition sits between tasks, so
#   `startup` is the moment — `compact|resume` stays the handover anchor's (handover-hook.sh).
#   Its stdout is passed through untouched: SessionStart stdout enters the model's context, and the
#   single `✅ POLARIS updated …` line is exactly what a session must read before it acts on a role
#   file that just changed. stderr goes to <primary>/.polaris/update.log. Exit 0 ALWAYS — a hook
#   must never fail the session. Lives under ops/hooks/ so install.sh's settings merge adds it and
#   uninstall's sweep removes it with no special case. `--test` prints the pinned line, runs nothing.
#
# THE CHEAP CHECK FIRST (6.6.x, T-176 — plans/audit-0924.md hooks-8)
#   The CLI starts twice (the update re-exec) just to learn it already asked the channel today:
#   ~1 s here, 2-3 s in an installed repo, on EVERY new chat. So before it starts, in plain bash
#   with no child process (`read` builtins, `printf '%(…)T'` for today): the kit's own repo
#   (kit/ops/pack.py) stops, and so does a cache that was `checked:` today with a `latest:` no
#   newer than ops/VERSION's `version:` — exactly the cases where `update --auto` would print
#   nothing. Anything unreadable or odd falls through to the CLI, as before. The check sits BEFORE
#   the `--test` print, so `--test` proves it: silent when the check stops, `would run` otherwise.
set -u
TESTMODE=0
REPLY=''
# Verbatim checkout-guard.sh's jstr: "$1" from the JSON "$2" into REPLY, rc 1 on ANY irregularity.
jstr() {
  local key="$1" s="$2" rest ch out='' i=0 len after
  rest="${s#*\"$key\"}"
  [ "$rest" = "$s" ] && return 1
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = ":" ] || return 1
  rest="${rest:1}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = '"' ] || return 1
  rest="${rest:1}"
  len=${#rest}
  while [ "$i" -lt "$len" ]; do
    ch="${rest:i:1}"
    if [ "$ch" = '\' ]; then
      i=$((i + 1)); ch="${rest:i:1}"
      case "$ch" in
        n)        out="$out
";;
        t)        out="$out	";;
        r)        ;;                      # a bare CR changes nothing we parse
        '"'|'\'|/) out="$out$ch";;
        *)        return 1;;              # \u, \b, \f — refuse to guess
      esac
      i=$((i + 1)); continue
    fi
    if [ "$ch" = '"' ]; then
      after="${rest:i+1}"
      after="${after#"${after%%[![:space:]]*}"}"
      case "${after:0:1}" in
        ','|'}') REPLY="$out"; return 0;;
        *)       return 1;;
      esac
    fi
    out="$out$ch"; i=$((i + 1))
  done
  return 1
}
# handover-hook.sh's hh_primary, same resolution: a primary is where the board is.
uh_primary() {
  local c="${1:-}"
  c="${c//\\//}"                             # Claude Code hands us a Windows cwd
  case "$c" in */.polaris/wt/*) REPLY="${c%%/.polaris/wt/*}"; return 0;; esac
  [ -n "$c" ] && [ -d "$c/ops/board" ] && { REPLY="$c"; return 0; }
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && { REPLY="${CLAUDE_PROJECT_DIR//\\//}"; return 0; }
  REPLY="$(git -C "${c:-.}" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$REPLY" ]
}
# The whole hook: resolve the primary, refuse nothing, run the engine, let its one line through.
uh_main() {
  local in='' cwd='' p line today='' checked='' latest='' cur='' a b i x y
  IFS= read -r -d '' in || true                # the whole payload, no `cat` process
  jstr cwd "$in" && cwd="$REPLY"
  uh_primary "$cwd" || exit 0
  p="$REPLY"
  [ -f "$p/ops/polaris" ] || exit 0
  [ -f "$p/kit/ops/pack.py" ] && exit 0        # self-hosting: this repo never self-updates
  # Today in LOCAL time, as the cache writes it (`date +%Y-%m-%d`). bash < 4.2 has no %(…)T: one
  # `date` there is still far cheaper than two CLI starts.
  printf -v today '%(%Y-%m-%d)T' -1 2>/dev/null || today="$(date +%Y-%m-%d 2>/dev/null)" || today=''
  if [ -f "$p/.polaris/update-cache" ] && [ -f "$p/ops/VERSION" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line//[[:space:]]/}"
      case "$line" in
        checked:*) [ -n "$checked" ] || checked="${line#checked:}";;
        latest:*)  [ -n "$latest" ]  || latest="${line#latest:}";;
      esac
    done < "$p/.polaris/update-cache"
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in version:*) line="${line#version:}"; line="${line%%#*}"; cur="${line//[[:space:]]/}"; break;; esac
    done < "$p/ops/VERSION"
    # Checked today → the CLI would answer from this same cache (update_latest's throttle), and it
    # acts only when latest > version. So: no latest, or latest <= version, is a guaranteed no-op.
    # Semver field by field in base 10 (a string compare puts 6.9.0 above 6.10.0); both sides must
    # be plain digits-and-dots, or we fall through to the CLI and let it judge.
    case "$today" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) today='';; esac
    if [ -n "$today" ] && [ "$checked" = "$today" ]; then
      case "$cur" in ''|*[!0-9.]*|.*|*.|*..*) cur='';; esac
      case "$latest" in *[!0-9.]*|.*|*.|*..*) cur='';; esac
      if [ -n "$cur" ]; then
        [ -z "$latest" ] && exit 0
        a="$latest." b="$cur."
        for i in 1 2 3; do
          x="${a%%.*}"; a="${a#*.}"; y="${b%%.*}"; b="${b#*.}"
          [ $((10#${x:-0})) -gt $((10#${y:-0})) ] && break      # newer → the CLI has work
          [ $((10#${x:-0})) -lt $((10#${y:-0})) ] && exit 0
          [ "$i" = 3 ] && exit 0                                # equal
        done
      fi
    fi
  fi
  [ "$TESTMODE" = 1 ] && { printf 'update-hook: would run %s/ops/polaris update --auto\n' "$p"; exit 0; }
  mkdir -p "$p/.polaris" 2>/dev/null || true
  ( cd "$p" && bash ops/polaris update --auto 2>>"$p/.polaris/update.log" ) || true
  exit 0
}
[ "${1:-}" = "--test" ] && TESTMODE=1
uh_main
exit 0
