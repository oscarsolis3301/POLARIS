# POLARIS lib/awake.sh — the CLI face of the machine-wide keep-awake daemon (ops/contracts/keep-awake.md).
# The daemon, its hooks and its registry live OUTSIDE any repo, under ~/.claude/polaris/: ONE owner per
# MACHINE that keeps the box awake while ANY session is still working, and stops once every one is done.
# This module only READS that registry and nudges the hook. It never presses a key, never runs the loop
# itself, and never touches the board. No CONVENTIONS key gates it — a repo key cannot gate machine hooks.

awake_home() { # awake_home — print the registry root (ah_home's resolution, byte for byte), or `-` when
  # this machine is unarmed: no POLARIS_AWAKE_HOME and no installed hook. Callers that must not act on an
  # unarmed machine test for the dash; `status` prints the idle line for it. Never `~` — a hook runs under
  # `env -i`, where $HOME is empty, so every path the registry hands out is absolute or nothing.
  if [ -n "${POLARIS_AWAKE_HOME:-}" ]; then printf '%s\n' "$POLARIS_AWAKE_HOME"; return 0; fi
  case "${OPS_DIR:-}" in */.claude/polaris) printf '%s/awake\n' "$OPS_DIR"; return 0 ;; esac
  if [ -f "${HOME:-}/.claude/polaris/awake-hook.sh" ]; then
    printf '%s/.claude/polaris/awake\n' "$HOME"; return 0
  fi
  printf '%s\n' '-'
}

awake_conf() { # awake_conf <key> <default> — one registry setting, in the contract's precedence: the env
  # POLARIS_AWAKE_<KEY> wins (the drills' seam), then the `<KEY>=<value>` line in <home>/config, then the
  # default. The config file is READ line by line with `case` and NEVER sourced: it is machine state a
  # daemon rewrites, not code, and sourcing it would run whatever a stray line happened to say.
  local k="${1:-}" d="${2:-}" v="" line="" h=""
  case "$k" in ''|*[!A-Z_]*) ;; *) eval "v=\${POLARIS_AWAKE_$k:-}" ;; esac
  if [ -z "$v" ]; then
    h="$(awake_home)"
    if [ "$h" != "-" ] && [ -r "$h/config" ]; then
      while read -r line; do
        case "$line" in "$k"=*) v="${line#*=}" ;; esac
      done < "$h/config"
    fi
  fi
  [ -n "$v" ] || v="$d"
  printf '%s\n' "$v"
}

awake_ensure() { # awake_ensure — keep this machine's daemon alive on behalf of THIS repo. Wired into the
  # hot commands (claim · status · doctor · handoff · bg run), so the common path — a daemon that is
  # already beating — must not fork: every check below is a shell builtin, and the hook is spawned ONLY
  # when the beat is stale. `awake_conf`/`awake_home` are deliberately NOT called here; a command
  # substitution is a subshell, and a subshell is the fork this function exists to avoid (~240ms on
  # Windows, paid on every CLI call). Silent, rc 0, ALWAYS — an unarmed machine and CI are a no-op.
  local h="${POLARIS_AWAKE_HOME:-}" hook="${HOME:-}/.claude/polaris/awake-hook.sh"
  [ -f "$hook" ] || hook="${OPS_DIR:-}/hooks/awake-hook.sh"   # kit-local fallback: an armed-by-env drill
  [ -f "$hook" ] || return 0                                  # unarmed machine (or CI) — nothing to ensure
  [ -n "$h" ] || h="${HOME:-}/.claude/polaris/awake"
  local tick="${POLARIS_AWAKE_TICK:-}" line="" beat="" now=""
  if [ -z "$tick" ] && [ -r "$h/config" ]; then
    while read -r line; do case "$line" in TICK=*) tick="${line#TICK=}" ;; esac; done < "$h/config"
  fi
  case "$tick" in ''|*[!0-9]*) tick=55 ;; esac
  if [ -r "$h/daemon/beat" ]; then
    read -r beat < "$h/daemon/beat" 2>/dev/null || true
    case "$beat" in ''|*[!0-9]*) beat=0 ;; esac
    now="${EPOCHSECONDS:-}"                                   # bash 5 builtin: the fork-free clock
    [ -n "$now" ] || now="$(date +%s 2>/dev/null || echo 0)"  # bash 3.2 (macOS/CI) pays one cheap fork
    if [ "$beat" -gt 0 ] && [ "$(( now - beat ))" -lt "$(( tick * 3 ))" ]; then return 0; fi
  fi
  bash "$hook" ensure "$PRIMARY" </dev/null >/dev/null 2>&1 &
  return 0
}

awake_status_line() { # awake_status_line — ONE line, one of the three shapes keep-awake.md pins. Liveness
  # is the BEAT, not the pid: a daemon whose lock survived a hard kill still has a stale beat, and the next
  # spawner steals from it, so a pid alone would report a corpse as running.
  local h="" p="" beat="" now="" age=0 tick="" n=0 m=0 f="" line=""
  h="$(awake_home)"
  if [ "$h" = "-" ] || [ ! -d "$h" ]; then printf 'awake: idle — not running\n'; return 0; fi
  if [ -e "$h/disabled" ]; then printf 'awake: off (disabled)\n'; return 0; fi
  if [ -r "$h/daemon/pid" ]; then read -r p < "$h/daemon/pid" 2>/dev/null || true; fi
  if [ -r "$h/daemon/beat" ]; then read -r beat < "$h/daemon/beat" 2>/dev/null || true; fi
  case "$p" in ''|*[!0-9]*) p="" ;; esac
  case "$beat" in ''|*[!0-9]*) beat=0 ;; esac
  tick="$(awake_conf TICK 55)"
  case "$tick" in ''|*[!0-9]*) tick=55 ;; esac
  now="${EPOCHSECONDS:-}"
  [ -n "$now" ] || now="$(date +%s 2>/dev/null || echo 0)"
  age=$(( now - beat ))
  [ "$age" -ge 0 ] || age=0
  if [ -z "$p" ] || [ "$beat" -eq 0 ] || [ "$age" -ge "$(( tick * 3 ))" ]; then
    printf 'awake: idle — not running\n'; return 0
  fi
  for f in "$h"/sessions/*; do
    if [ -f "$f" ]; then
      line=""
      read -r line < "$f" 2>/dev/null || true
      case "$line" in busy*) n=$(( n + 1 )) ;; esac
    fi
  done
  for f in "$h"/repos/*; do
    if [ -f "$f" ]; then m=$(( m + 1 )); fi
  done
  printf 'awake: running (pid %s, beat %ss ago, %s busy session(s), %s repo(s))\n' "$p" "$age" "$n" "$m"
}

cmd_awake() { # polaris awake [status|start|stop|disable|enable|install] — the human face of the daemon.
  # `stop` is the polite one: it flags the loop to exit, kills the pid it recorded, drops the singleton
  # lock and writes a 60-minute expiry stamp into `disabled`, so the machine re-arms itself without anyone
  # remembering to. `disable` is the permanent opt-out (an EMPTY flag file — the daemon expires a stamped
  # one, never a bare one) and `enable` lifts it. `install` hands off to the hook, which owns the settings
  # merge. Nothing here writes the board, EVENTS.ndjson, or any lock.
  local sub="${1:-status}" h="" hook="" p="" now=""
  h="$(awake_home)"
  hook="${HOME:-}/.claude/polaris/awake-hook.sh"
  [ -f "$hook" ] || hook="${OPS_DIR:-}/hooks/awake-hook.sh"
  [ "$h" != "-" ] || h="${HOME:-}/.claude/polaris/awake"
  case "$sub" in
    status)
      awake_status_line ;;
    start)
      [ -f "$hook" ] || die "keep-awake is not installed on this machine — bash ops/polaris awake install"
      mkdir -p "$h" 2>/dev/null || true
      rm -f "$h/stop" 2>/dev/null || true
      if [ -s "$h/disabled" ]; then rm -f "$h/disabled" 2>/dev/null || true; fi  # lift a stop's 60-min stamp
      bash "$hook" ensure "$PRIMARY" </dev/null >/dev/null 2>&1 || true
      say "keep-awake armed for this machine"
      note "$(awake_status_line)" ;;
    stop)
      if [ ! -d "$h" ]; then say "keep-awake was not running on this machine"; return 0; fi
      : 2>/dev/null > "$h/stop" || true
      if [ -r "$h/daemon/pid" ]; then read -r p < "$h/daemon/pid" 2>/dev/null || true; fi
      case "$p" in ''|*[!0-9]*) p="" ;; esac
      if [ -n "$p" ]; then kill "$p" 2>/dev/null || true; fi
      rm -rf "$h/lock" 2>/dev/null || true
      now="${EPOCHSECONDS:-}"
      [ -n "$now" ] || now="$(date +%s 2>/dev/null || echo 0)"
      printf '%s\n' "$now" 2>/dev/null > "$h/disabled" || true
      say "keep-awake stopped — off for 60 minutes, then this machine arms itself again" ;;
    disable)
      mkdir -p "$h" 2>/dev/null || true
      : 2>/dev/null > "$h/disabled" || true
      say "keep-awake disabled — nothing presses until: bash ops/polaris awake enable" ;;
    enable)
      rm -f "$h/disabled" 2>/dev/null || true
      say "keep-awake enabled"
      note "$(awake_status_line)" ;;
    install)
      [ -f "$hook" ] || die "no awake-hook.sh on this machine or in this kit — re-run the installer (bash ops/install.sh)"
      exec bash "$hook" install ;;
    *)
      die "unknown: awake $sub — usage: polaris awake [status|start|stop|disable|enable|install]" ;;
  esac
}
