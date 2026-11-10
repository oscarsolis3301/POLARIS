# POLARIS lib/presence.sh — is the owner here, or did they approve the plan and leave?
# Sourced by ops/polaris (the lib loader). ops/contracts/away.md § 2.3–2.4.
# The hook ops/hooks/presence-guard.sh writes the state; this file only reads it (and appends plan
# slugs to an approval already on record). Files, one pair per session, beside model-guard.sh's:
#   $HOME/.claude/polaris/model-state/<sid>.mode      one line: the last permission_mode seen
#   $HOME/.claude/polaris/model-state/<sid>.approved  line 1: approval epoch · lines 2+: plan slugs
# A Bash call has no payload, so <sid> is $CLAUDE_CODE_SESSION_ID and the mode is <sid>.mode.
# away ⇔ <sid> valid AND <sid>.approved exists AND the mode is auto | bypassPermissions | dontAsk.
# Anything else, every unknown included, is here. Builtins only: no fork.

_presence_file() { # sets PRESENCE_F to the state path without extension, or empty when there is none
  PRESENCE_F=""
  case "${CLAUDE_CODE_SESSION_ID:-}" in ''|*[!A-Za-z0-9_-]*) return 0;; esac
  [ -n "${HOME:-}" ] || return 0
  PRESENCE_F="$HOME/.claude/polaris/model-state/$CLAUDE_CODE_SESSION_ID"
}

_presence_state() { # sets PRESENCE (away|here) and PRESENCE_WHY. rc 0 always.
  local m=""
  PRESENCE=here; PRESENCE_WHY="no session id"
  case "${CLAUDE_CODE_SESSION_ID:-}" in ''|*[!A-Za-z0-9_-]*) return 0;; esac
  _presence_file
  if [ -z "$PRESENCE_F" ] || [ ! -f "$PRESENCE_F.approved" ]; then
    PRESENCE_WHY="no plan approved in this session"; return 0
  fi
  { IFS= read -r m < "$PRESENCE_F.mode"; } 2>/dev/null || true   # set -e: a missing file is no mode
  m="${m%$'\r'}"
  case "$m" in
    auto|bypassPermissions|dontAsk)
      PRESENCE=away; PRESENCE_WHY="the plan was approved and this session runs in $m mode";;
    '') PRESENCE_WHY="this session's mode is unknown";;
    *)  PRESENCE_WHY="this session runs in $m mode";;
  esac
  return 0
}

_presence_away() { # rc 0 iff the owner is away
  _presence_state
  [ "$PRESENCE" = away ]
}

_presence_has() { # _presence_has <slug> — rc 0 iff <slug> is on lines 2+ of $PRESENCE_F.approved
  local l="" n=0
  [ -n "${1:-}" ] && [ -n "$PRESENCE_F" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    n=$((n + 1)); [ "$n" -gt 1 ] || continue
    [ "${l%$'\r'}" = "$1" ] && return 0
  done < "$PRESENCE_F.approved"
  return 1
} 2>/dev/null

_presence_bind() { # _presence_bind <slug> — bind a plan slug to the approval on record. rc 0 always.
  _presence_file
  case "${1:-}" in ''|*[!A-Za-z0-9._-]*) return 0;; esac
  [ -n "$PRESENCE_F" ] && [ -f "$PRESENCE_F.approved" ] || return 0
  _presence_has "$1" && return 0
  { printf '%s\n' "$1" >> "$PRESENCE_F.approved"; } 2>/dev/null || true
  return 0
}

_presence_covers() { # _presence_covers <slug> — rc 0 iff away AND <slug> is bound to the approval
  _presence_away || return 1
  _presence_file
  _presence_has "${1:-}"
}

_presence_cmd() { # polaris presence — line 1 away|here, then ONE why: line. Read-only, rc 0 always.
  _presence_state
  printf '%s\n   why: %s\n' "$PRESENCE" "$PRESENCE_WHY"
  return 0
}
