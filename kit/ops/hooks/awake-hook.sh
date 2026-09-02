#!/usr/bin/env bash
# POLARIS v6 — machine-level keep-awake: the four Claude Code hooks AND the daemon that presses.
#
# WHY  The machine sleeps mid-run. ONE keep-awake owner per MACHINE — never one per session — awake
#   while ANY session is still working, silent once they are all done, never interrupting a human who
#   is typing, and still alive on the LOCK screen: synthetic keys never reach the secure desktop,
#   which is exactly when the box is about to sleep. So the lever is SetThreadExecutionState
#   (ES_SYSTEM_REQUIRED) — works locked, holds nothing — and the F-key is only its visible half.
# SILENCE  `start busy idle end` are hooks. UserPromptSubmit stdout is injected into the model's
#   context and rc 2 on Stop means "keep going": they print NOTHING and exit 0 whatever happens.
# NAMES  ops/contracts/keep-awake.md pins every path, default, function and printed word — CLI face
#   ops/lib/awake.sh, and `--test <sub>` prints one pinned line for the golden and the drill.
set -u

REPLY=''                                       # jstr's out-parameter
AH_SELF="$0"
case "$AH_SELF" in /*|[A-Za-z]:[/\\]*) ;; *) AH_SELF="$PWD/$AH_SELF";; esac
AH_WIN=0; AH_MAC=0                             # $OSTYPE is bash's own — msys · cygwin · darwin* · linux-gnu
case "${OSTYPE:-}" in msys*|cygwin*|win*) AH_WIN=1;; darwin*) AH_MAC=1;; esac
AH_SUB=''; AH_TEST=0; AH_SID=''; AH_TP=''; AH_CWD=''; AH_REPO='-'; AH_IN=''; AH_L=''; AH_V=''
AH_PID="${CLAUDE_PID:-}"; case "$AH_PID" in ''|*[!0-9]*) AH_PID='-';; esac
AH_PS=''; AH_PWSH=''; AH_PS1=''                # the ONE `ps -W` snapshot · powershell.exe · the .ps1
AH_VERDICT=quiet; AH_WORD=no-press; AH_ACTIVE=0; AH_BUSY=0; AH_REPOS=0; AH_FAILS=0

# Extract a complete JSON string value for "$1" from "$2" into REPLY. Returns 1 on ANY irregularity
# — a missing key, an escape we do not decode, or a closing quote not followed by , or } .
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
# ---------------------------------------------------------------- registry primitives
ah_home() { # the root: env → beside an installed copy under .claude/polaris/ → $HOME.
  local d="${AH_SELF%/*}"; d="${d//\\//}"
  [ -z "${POLARIS_AWAKE_HOME:-}" ] || { printf '%s\n' "$POLARIS_AWAKE_HOME"; return 0; }
  case "$d" in */.claude/polaris) printf '%s/awake\n' "$d"; return 0;; esac
  printf '%s/.claude/polaris/awake\n' "${HOME:-.}"
}
ah_log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$AWAKE/daemon/log" 2>/dev/null || true; }
ah_now() { date +%s; }
ah_mtime() { # epoch mtime of "$1", or 0 — GNU stat, then BSD stat, then give up quietly.
  local m=''
  [ -e "${1:-}" ] && { m="$(stat -c %Y "$1" 2>/dev/null)" || m="$(stat -f %m "$1" 2>/dev/null)" || m=''; }
  case "$m" in ''|*[!0-9]*) m=0;; esac; printf '%s\n' "$m"
}
ah_alive() { case "${1:-}" in ''|-|*[!0-9]*) return 1;; esac; kill -0 "$1" 2>/dev/null; }
ah_win_alive() { # the same question against the ONE `ps -W` snapshot; no snapshot → plain kill -0.
  [ -n "$AH_PS" ] || { ah_alive "${1:-}"; return; }
  case "${1:-}" in ''|-|*[!0-9]*) return 1;; esac
  case " $AH_PS " in *" $1 "*) return 0;; esac
  return 1
}
ah_repo_of() { # the PRIMARY checkout behind a session's cwd — a worktree path answers fork-free.
  local c="${1:-}" p=''
  c="${c//\\//}"
  case "$c" in *"/.polaris/wt/"*) printf '%s\n' "${c%/.polaris/wt/*}"; return 0;; esac
  [ -d "$c" ] && p="$(cd "$c" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
  printf '%s\n' "${p:--}"
}
ah_register_repo() { # repos/<cksum of the path> ← the path. Idempotent, silent, best effort.
  local p="${1:-}" k
  [ -n "$p" ] && [ "$p" != '-' ] || return 0
  k="$(printf '%s' "$p" | cksum)"; k="${k%% *}"; case "$k" in ''|*[!0-9]*) return 0;; esac
  printf '%s\n' "$p" > "$AWAKE/repos/$k" 2>/dev/null || true
}
# ---------------------------------------------------------------- the four hooks
ah_hook_start() { # create as idle ONLY when absent: a compact/resume start must never downgrade a
  local f="$AWAKE/sessions/$AH_SID" st=idle how=created l1=''   # session that is mid-turn.
  if [ -f "$f" ]; then
    read -r l1 < "$f" || true
    st="${l1%% *}"; how=kept
    case "$st" in busy|idle) ;; *) st=idle; l1="idle $(ah_now)";; esac
    printf '%s\n%s\n%s\n%s\n' "$l1" "$AH_TP" "$AH_PID" "$AH_REPO" > "$f"
  else
    printf '%s %s\n%s\n%s\n%s\n' idle "$(ah_now)" "$AH_TP" "$AH_PID" "$AH_REPO" > "$f"
  fi
  [ "$AH_TEST" = 1 ] && printf 'start: %s %s (%s)\n' "$AH_SID" "$st" "$how"; return 0
}
ah_hook_busy() { # UserPromptSubmit: this session is working. Registers its repo, ensures a daemon.
  printf '%s %s\n%s\n%s\n%s\n' busy "$(ah_now)" "$AH_TP" "$AH_PID" "$AH_REPO" > "$AWAKE/sessions/$AH_SID"
  ah_register_repo "$AH_REPO"
  [ "$AH_TEST" = 1 ] && { printf 'busy: %s busy\n' "$AH_SID"; return 0; }
  ah_spawn; return 0
}
ah_hook_idle() { # Stop: this session went quiet. The DAEMON decides whether the machine has.
  printf '%s %s\n%s\n%s\n%s\n' idle "$(ah_now)" "$AH_TP" "$AH_PID" "$AH_REPO" > "$AWAKE/sessions/$AH_SID"
  [ "$AH_TEST" = 1 ] && printf 'idle: %s idle\n' "$AH_SID"; return 0
}
ah_hook_end() { # SessionEnd: forget the session outright.
  rm -f "$AWAKE/sessions/$AH_SID"
  [ "$AH_TEST" = 1 ] && printf 'end: %s removed\n' "$AH_SID"; return 0
}
# ---------------------------------------------------------------- daemon lifecycle
ah_spawn() { # ensure ONE daemon: fresh beat → nothing to do; stale lock → steal it; else detach.
  # WMI Win32_Process.Create is the only real detach on Windows — the child belongs to WmiPrvSE, so
  # it sits OUTSIDE every caller's Job Object (a Bash-tool child is inside one), has no console and
  # survives the terminal. Start-Process falls back on the SAME fork (a second costs ~680 ms);
  # inline is the last resort, and is logged because it dies with us. `bash -l` is LOAD-BEARING:
  # a WMI child inherits the bare Windows environment, so without it PATH has no /usr/bin and the
  # daemon dies on its first `mkdir`. POSIX $AH_SELF, never `cygpath -w` — bash cannot open C:\…
  local now beat b cmd out
  now="$(ah_now)"; beat="$(ah_mtime "$AWAKE/daemon/beat")"
  [ "$beat" -gt 0 ] && [ $(( now - beat )) -lt $(( AH_TICK * 3 )) ] && return 0
  rm -rf "$AWAKE/lock" 2>/dev/null || true     # a beat this stale means the holder is gone
  if [ "${POLARIS_AWAKE_SPAWN:-}" = inline ]; then ( ah_daemon & ) ; return 0; fi
  if [ "$AH_WIN" != 1 ]; then nohup bash "$AH_SELF" daemon >/dev/null 2>&1 & disown 2>/dev/null; return 0; fi
  if [ -n "$AH_PWSH" ]; then
    b="$(cygpath -w "$(command -v bash)" 2>/dev/null)" || b=''; [ -n "$b" ] || b=bash
    cmd="\"$b\" -l \"$AH_SELF\" daemon"
    out="$(POLARIS_AWAKE_CMD="$cmd" POLARIS_AWAKE_EXE="$b" POLARIS_AWAKE_ARGS="-l \"$AH_SELF\" daemon" \
      "$AH_PWSH" -NoProfile -NonInteractive -Command '$i=0; try{ $r=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$env:POLARIS_AWAKE_CMD} -ErrorAction Stop; $i=$r.ProcessId }catch{ $i=0 }; if(-not $i){ try{ $i=(Start-Process -FilePath $env:POLARIS_AWAKE_EXE -ArgumentList $env:POLARIS_AWAKE_ARGS -WindowStyle Hidden -PassThru -ErrorAction Stop).Id }catch{ $i=0 } }; $i' 2>/dev/null | tr -dc '0-9')" || out=''
    if [ -n "$out" ] && [ "$out" != 0 ]; then printf '%s\n' "$out" > "$AWAKE/daemon/winpid"; return 0; fi
  fi
  ah_log 'spawn: WMI and Start-Process both failed — daemon runs INLINE and dies with this shell'
  ( ah_daemon & ); return 0
}
ah_press() { # run the presser ONCE; its one word lands in daemon/last-press and in AH_WORD.
  local w='' rc=0
  if [ -e "$AWAKE/disabled" ]; then AH_WORD=disabled; printf 'disabled\n' > "$AWAKE/daemon/last-press"; return 0; fi
  if [ -n "${POLARIS_AWAKE_PRESSER:-}" ]; then  # the drill seam: replaces the presser wholesale
    w="$(eval "$POLARIS_AWAKE_PRESSER" 2>/dev/null)" || rc=1
  elif [ "$AH_MAC" = 1 ]; then w=pressed
    if [ "$AH_DISPLAY" = 1 ]; then caffeinate -u -t 75 >/dev/null 2>&1 & else caffeinate -i -t 75 >/dev/null 2>&1 & fi
  elif [ "$AH_WIN" = 1 ] && [ -n "$AH_PWSH" ] && [ -n "$AH_PS1" ]; then
    w="$("$AH_PWSH" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$AH_PS1" \
      -Key "$AH_KEY" -Display "$AH_DISPLAY" -InputIdle "$AH_INPUT_IDLE" 2>/dev/null)" || rc=1
  elif [ "$AH_WIN" = 1 ]; then rc=1
  elif xdotool key "$AH_KEY" >/dev/null 2>&1; then w=pressed
  elif xdg-screensaver reset >/dev/null 2>&1; then w=state-only
  else rc=1
  fi
  w="${w//$'\r'/}"; w="${w##*$'\n'}"; w="${w%% *}"
  if [ "$rc" != 0 ]; then   # GPO, Constrained Language Mode, AV, no powershell: a machine fact, not
    AH_FAILS=$(( AH_FAILS + 1 )); w=failed   # an event. Loud once, then quiet, and NEVER fatal.
    [ $(( AH_FAILS % 100 )) = 1 ] && ah_log "presser failed (${AH_FAILS}x) — GPO, Constrained Language Mode or AV?"
  fi
  [ -n "$w" ] || w=pressed                     # a presser that prints nothing still pressed
  AH_WORD="$w"; printf '%s\n' "$w" > "$AWAKE/daemon/last-press"; return 0
}
ah_verdict() { # ONE pass over the registry → AH_VERDICT active|quiet, plus the counts for `status`.
  # A session's real beat is its transcript's mtime OR the newest <sid>/subagents/*.jsonl: the
  # top-level transcript goes stale for the whole length of a subagent run, which is exactly when
  # the machine must stay up. Dead-pid and day-old files are reaped here — nothing else cleans the
  # registry — and a detached bg suite is work with nobody at a keyboard.
  local now f sid l1 st stamp tp pid d j m p beat
  now="$(ah_now)"; AH_PS=''; AH_ACTIVE=0; AH_BUSY=0; AH_REPOS=0
  [ "$AH_WIN" = 1 ] && AH_PS="$(ps -W 2>/dev/null | awk 'NR>1 { printf "%s %s ", $1, $4 }')"
  for f in "$AWAKE"/sessions/*; do
    [ -f "$f" ] || continue
    sid="${f##*/}"; l1=''; tp=''; pid=''
    { read -r l1; read -r tp; read -r pid; } < "$f" || true
    st="${l1%% *}"; stamp="${l1#* }"; case "$stamp" in ''|*[!0-9]*) stamp=0;; esac
    if [ -n "$pid" ] && [ "$pid" != '-' ] && ! ah_win_alive "$pid"; then rm -f "$f"; continue; fi
    [ $(( now - $(ah_mtime "$f") )) -gt 86400 ] && { rm -f "$f"; continue; }
    beat="$(ah_mtime "$tp")"
    for j in "${tp%/*}/$sid/subagents"/*.jsonl; do
      [ -f "$j" ] && m="$(ah_mtime "$j")" && [ "$m" -gt "$beat" ] && beat="$m"
    done
    case "$st" in
      busy) AH_BUSY=$(( AH_BUSY + 1 )); [ $(( now - beat )) -lt "$AH_STALE" ] && AH_ACTIVE=$(( AH_ACTIVE + 1 ));;
      idle) [ "$beat" -gt "$stamp" ] && [ $(( now - beat )) -lt "$AH_IDLE" ] && AH_ACTIVE=$(( AH_ACTIVE + 1 ));;
    esac
  done
  for f in "$AWAKE"/repos/*; do
    [ -f "$f" ] || continue
    p=''; read -r p < "$f" || true
    if [ -z "$p" ] || [ ! -d "$p" ]; then rm -f "$f"; continue; fi
    AH_REPOS=$(( AH_REPOS + 1 ))
    [ "$AH_ACTIVE" -gt 0 ] && continue
    for d in "$p"/.polaris/bg/*/; do
      { [ -f "${d}rc" ] || [ ! -f "${d}pid" ]; } && continue
      pid=''; read -r pid < "${d}pid" || true
      ah_win_alive "$pid" && AH_ACTIVE=$(( AH_ACTIVE + 1 ))
    done
  done
  [ "$AH_ACTIVE" -gt 0 ] && AH_VERDICT=active || AH_VERDICT=quiet
  return 0
}
ah_tick() { # one verdict + at most one press. `awake stop` leaves an EXPIRING disabled; it lapses here.
  local d="$AWAKE/disabled"
  [ -s "$d" ] && [ $(( $(ah_now) - $(ah_mtime "$d") )) -ge 3600 ] && rm -f "$d"
  AH_WORD=no-press; ah_verdict
  [ "$AH_VERDICT" = active ] && ah_press
  return 0
}
ah_daemon() { # the loop. `mkdir lock` is the singleton: a loser just leaves, and says nothing.
  local now quiet_since
  mkdir "$AWAKE/lock" 2>/dev/null || return 0
  trap 'rm -rf "$AWAKE/lock"; exit 0' TERM INT
  printf '%s\n' "$$" > "$AWAKE/daemon/pid"
  ah_log "daemon up (pid $$ · tick ${AH_TICK}s · grace ${AH_GRACE}s · key ${AH_KEY})"
  quiet_since="$(ah_now)"
  while : ; do
    ah_tick
    now="$(ah_now)"; printf '%s\n' "$now" > "$AWAKE/daemon/beat"
    [ "$AH_VERDICT" = active ] && quiet_since="$now"
    [ -e "$AWAKE/stop" ] && { rm -f "$AWAKE/stop"; ah_log 'daemon: stop — leaving'; break; }
    [ $(( now - quiet_since )) -ge "$AH_GRACE" ] && { ah_log "daemon: quiet ${AH_GRACE}s — leaving"; break; }
    sleep "$AH_TICK" & wait $!                 # backgrounded so a signal lands within a second
  done
  rm -rf "$AWAKE/lock"; return 0
}
ah_install() { # merge the four machine hooks into ~/.claude/settings.json BY SCRIPT IDENTITY.
  # Identity is the PATH `polaris/awake-hook.sh`, never a basename: an entry running our script is
  # ours and is replaced wholesale (a wrong timeout can then always be CORRECTED); every other one
  # is the human's, left as found. ABSOLUTE paths only — `env -i` empties $HOME.
  local sj="${HOME:-.}/.claude/settings.json" b py=''
  b="$(command -v bash 2>/dev/null)" || b=bash
  python -c pass >/dev/null 2>&1 && py=python || { python3 -c pass >/dev/null 2>&1 && py=python3; } || true
  [ -n "$py" ] || { printf 'awake: no python — add the four hooks to %s by hand (keep-awake.md)\n' "$sj"; return 0; }
  mkdir -p "${sj%/*}" 2>/dev/null || true
  "$py" - "$sj" "$b" "${HOME:-.}/.claude/polaris/awake-hook.sh" <<'PYEOF'
import json, os, re, sys
p, sh, hk = sys.argv[1], sys.argv[2], sys.argv[3]
EV = (("SessionStart", "start", 5), ("UserPromptSubmit", "busy", 10), ("Stop", "idle", 5), ("SessionEnd", "end", 5))
ents = [(ev, {"hooks": [{"type": "command", "timeout": t,
        "command": '"%s" "%s" %s 2>/dev/null || true' % (sh, hk, sub)}]}) for ev, sub, t in EV]
ours = re.compile(r"polaris/awake-hook\.sh")
mine = lambda e: isinstance(e, dict) and any(isinstance(h, dict) and ours.search(
    str(h.get("command", "")).replace("\\", "/")) for h in (e.get("hooks") or []))
def bail(why):                                 # fails OPEN: print the four, rewrite nothing
    print("awake: %s %s — add these four by hand:" % (p, why))
    for ev, e in ents: print("  %s: %s" % (ev, json.dumps(e)))
    raise SystemExit(0)
try: d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
except (OSError, ValueError) as exc: bail("is unreadable (%s)" % exc)
if not isinstance(d, dict): bail("is not a JSON object")
hooks = d.setdefault("hooks", {})
if not isinstance(hooks, dict): bail('has a non-object "hooks"')
n = 0
for ev, ent in ents:
    have = hooks.setdefault(ev, [])
    if not isinstance(have, list): continue
    at = [i for i, e in enumerate(have) if mine(e)]
    if not at: have.append(ent); n += 1
    elif have[at[0]] != ent: have[at[0]] = ent; n += 1
try:                                           # tmp + os.replace: never a truncated settings.json
    open(p + ".polaris-tmp", "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
    os.replace(p + ".polaris-tmp", p)
except OSError as exc: bail("could not be written (%s)" % exc)
print("awake: %d of 4 hook entries written to %s" % (n, p))
PYEOF
  return 0
}
# ---------------------------------------------------------------- entry
AWAKE="$(ah_home)"
mkdir -p "$AWAKE/sessions" "$AWAKE/repos" "$AWAKE/daemon" 2>/dev/null || true
AH_KEY=F15; AH_TICK=55; AH_STALE=2700; AH_IDLE=900; AH_GRACE=300; AH_DISPLAY=1; AH_INPUT_IDLE=60
if [ -f "$AWAKE/config" ]; then                # config is DATA: matched by `case`, NEVER sourced
  while IFS='=' read -r AH_L AH_V || [ -n "$AH_L" ]; do
    case "$AH_L" in KEY|TICK|STALE|IDLE|GRACE|DISPLAY|INPUT_IDLE) eval "AH_$AH_L=\$AH_V";; esac
  done < "$AWAKE/config"
fi
for AH_L in KEY TICK STALE IDLE GRACE DISPLAY INPUT_IDLE; do   # env POLARIS_AWAKE_<KEY> wins
  eval "AH_V=\${POLARIS_AWAKE_$AH_L:-}"
  [ -n "$AH_V" ] && eval "AH_$AH_L=\$AH_V"
done
case "$AH_TICK$AH_STALE$AH_IDLE$AH_GRACE$AH_DISPLAY$AH_INPUT_IDLE" in   # one bad value, one reset
  ''|*[!0-9]*) AH_TICK=55; AH_STALE=2700; AH_IDLE=900; AH_GRACE=300; AH_DISPLAY=1; AH_INPUT_IDLE=60;;
esac
[ "$AH_TICK" -ge 1 ] || AH_TICK=55             # TICK=0 would spin the daemon at 100% CPU
AH_SUB="${1:-}"; case "$AH_SUB" in --test) AH_TEST=1; shift; AH_SUB="${1:-}";; esac
if [ "$AH_WIN" = 1 ]; then case "$AH_SUB" in   # resolve the Windows tools ONCE, and only if needed
  busy|ensure|daemon|tick)
    AH_PWSH="$(cygpath "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null)/System32/WindowsPowerShell/v1.0/powershell.exe"
    [ -x "$AH_PWSH" ] || { AH_PWSH="$(command -v powershell 2>/dev/null)" || AH_PWSH=''; }
    case "$AH_SUB" in daemon|tick) AH_PS1="$(cygpath -w "${AH_SELF%/*}/awake-press.ps1" 2>/dev/null)" || AH_PS1='';; esac;;
esac; fi
case "$AH_SUB" in
  start|busy|idle|end)
    # THE SILENT PATH. --test keeps stdout so a golden can read one pinned line; nothing else does.
    if [ "$AH_TEST" = 0 ]; then exec >/dev/null 2>>"$AWAKE/daemon/hook.log"; set +e; trap 'exit 0' EXIT; fi
    AH_IN="$(cat 2>/dev/null)" || AH_IN=''
    jstr session_id "$AH_IN" && AH_SID="$REPLY"
    case "$AH_SID" in ''|*[!A-Za-z0-9._-]*) exit 0;; esac   # absent, or unusable as a filename
    jstr transcript_path "$AH_IN" && AH_TP="$REPLY"
    jstr cwd "$AH_IN" && AH_CWD="$REPLY"
    case "$AH_SUB" in start|busy|idle) AH_REPO="$(ah_repo_of "$AH_CWD")";; esac
    ah_hook_"$AH_SUB"                          # one of the four this same case just matched
    exit 0;;
  ensure) shift
    if [ "$AH_TEST" = 0 ]; then exec >/dev/null 2>>"$AWAKE/daemon/hook.log"; set +e; trap 'exit 0' EXIT; fi
    ah_register_repo "${1:-}"; ah_spawn; exit 0;;
  daemon)  ah_daemon; exit 0;;
  tick)    ah_tick; [ "$AH_TEST" = 1 ] && printf 'tick: %s %s\n' "$AH_VERDICT" "$AH_WORD"; exit 0;;
  install) ah_install; exit 0;;
  *)       printf 'usage: awake-hook.sh [--test] start|busy|idle|end|ensure|daemon|tick|install\n' >&2; exit 0;;
esac
