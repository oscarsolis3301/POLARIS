# POLARIS lib/bgwatch.sh — job budgets for lib/bg.sh (ops/contracts/walk-away.md § 2.1): every
# detached job gets a budget and ONE watchdog beside its runner; past the budget the watchdog kills
# the command's whole process tree, retries once (bg_retries), then writes <dir>/overrun + rc 124 and
# `bg wait` answers exit 4. Only budgets kill — pulse, keep-awake and the Stop gate reap through
# bgwatch_reap, never by name and never across cwds. Loaded right after bg.sh.

bgwatch_budget() { # bgwatch_budget <name> [<cmd…>] — the job's budget in whole seconds. 3 × the longest
  # GREEN run of that name (its .prev slot and .archive/<name>-<epoch>/), else the name's class —
  # lint/typecheck/build 900, anything else 3 × .polaris/last-suite-seconds (field 1) when present,
  # else 1800. Floor 300; + POLARIS_HEAVY_WAIT (1800) when the command is a kit command (it can queue
  # for the heavy slot). `bg run --budget <s>` never reaches here: it is written verbatim.
  local name="${1:-}" root="$PRIMARY/.polaris/bg" b=0 d r s e x l=""
  [ $# -gt 0 ] && shift
  for d in "$root/$name.prev" "$root/.archive/$name-"*; do
    [ -f "$d/rc" ] || continue
    x="${d##*/}"; case "$x" in "$name.prev") ;; *) x="${x#"$name"-}"; case "$x" in ''|*[!0-9]*) continue;; esac;; esac
    r=""; s=""; e=""
    read -r r 2>/dev/null < "$d/rc" || true; [ "${r%$'\r'}" = 0 ] || continue
    read -r s 2>/dev/null < "$d/start" || true; read -r e 2>/dev/null < "$d/end" || true
    s="${s%$'\r'}"; e="${e%$'\r'}"
    case "$s$e" in ''|*[!0-9]*) continue;; esac
    [ $(( e - s )) -gt "$b" ] && b=$(( e - s ))
  done
  if [ "$b" -gt 0 ]; then b=$(( b * 3 ))
  else
    read -r l x 2>/dev/null < "$PRIMARY/.polaris/last-suite-seconds" || true
    case "$name" in
      lint|typecheck|build) b=900;;
      *) case "$l" in ''|*[!0-9]*) b=1800;; *) b=$(( l * 3 ));; esac;;
    esac
  fi
  [ "$b" -lt 300 ] && b=300
  x="${POLARIS_HEAVY_WAIT:-1800}"; case "$x" in ''|*[!0-9]*) x=1800;; esac
  case " $* " in *ops/polaris*) b=$(( b + x ));; esac
  printf '%s\n' "$b"
}

_bgwatch_launch() { # _bgwatch_launch <dir> <cmd…> — THE runner (bg_run's first attempt, the watchdog's
  # retry). pid semantics from birth: spawn, the caller writes the pid, nothing in between. The runner
  # writes end THEN rc, rc LAST — its existence means "finished" — unless the watchdog is killing it
  # (<dir>/killing): a killed attempt never writes a verdict. set +e inside: the subshell inherits
  # set -e and must survive the command failing. POSIX: the job gets its OWN process group (set -m)
  # so a budget kill reaches every grandchild; Git Bash kills the tree by winpid instead.
  local dir="$1" cwd=""; shift
  IFS= read -r cwd 2>/dev/null < "$dir/cwd" || true; cwd="${cwd%$'\r'}"
  case "${OSTYPE:-}" in msys*|cygwin*) ;; *) set -m 2>/dev/null || true;; esac
  (
    set +e
    rc=127
    if cd "$cwd" 2>/dev/null; then
      "$@"
      rc=$?
    else
      echo "bg: cannot cd to $cwd"
    fi
    [ -f "$dir/killing" ] && exit 0
    date +%s > "$dir/end"
    printf '%s\n' "$rc" > "$dir/rc"
  ) </dev/null >>"$dir/log" 2>&1 &
  _BGW_PID=$!
  set +m 2>/dev/null || true
  return 0
}

_bgwatch_tree() { # _bgwatch_tree <pid> — the pid and every descendant, parents first, from ONE ps
  # listing (PID = $2, PPID = $3 on Git Bash, Linux and macOS alike). Taken BEFORE any kill: once a
  # parent dies its children are re-parented and the link is gone.
  ps -ef 2>/dev/null | awk -v r="$1" 'NR > 1 { pp[$2] = $3; o[++n] = $2 }
    END { t[r] = 1; print r; ch = 1
      while (ch) { ch = 0; for (i = 1; i <= n; i++) { p = o[i]; if (!(p in t) && (pp[p] in t)) { t[p] = 1; print p; ch = 1 } } } }'
}

_bgwatch_kill() { # _bgwatch_kill <pid> — kill the runner's whole process tree. Git Bash: each pid's
  # /proc/<pid>/winpid → taskkill //T //F (the Windows tree), then kill -9 the MSYS pids. POSIX: TERM
  # the process group and every descendant, up to 5 s for them to go, then KILL. Never fatal.
  local root="${1:-}" t p w i=0 left
  case "$root" in ''|*[!0-9]*) return 0;; esac
  t="$(_bgwatch_tree "$root")" || true
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      for p in $t; do
        w=""; read -r w 2>/dev/null < "/proc/$p/winpid" || true
        case "$w" in ''|*[!0-9]*) ;; *) taskkill //PID "$w" //T //F >/dev/null 2>&1 || true;; esac
      done
      for p in $t; do kill -9 "$p" 2>/dev/null || true; done;;
    *)
      kill -TERM -"$root" 2>/dev/null || true
      for p in $t; do kill -TERM "$p" 2>/dev/null || true; done
      command -v pkill >/dev/null 2>&1 && { for p in $t; do pkill -TERM -P "$p" 2>/dev/null || true; done; }
      while [ "$i" -lt 25 ]; do
        left=""; for p in $t; do kill -0 "$p" 2>/dev/null && left=1; done
        [ -n "$left" ] || break
        sleep 0.2; i=$(( i + 1 ))
      done
      kill -KILL -"$root" 2>/dev/null || true
      for p in $t; do kill -KILL "$p" 2>/dev/null || true; done;;
  esac
  return 0
}

_bgwatch_over() { # _bgwatch_over <dir> <budget> <attempts> — the timed-out verdict: overrun, end, rc 124
  printf '%s\t%s\n' "$2" "$3" > "$1/overrun"
  date +%s > "$1/end"
  printf '124\n' > "$1/rc"
}

_bgwatch_loop() { # _bgwatch_loop <dir> <nonce> <cmd…> — the watchdog body. Polls rc every 5 s (every
  # second under a budget below 10 s — the drills' size); exits the moment rc exists, or when <dir>/watch
  # no longer names its nonce (a --force rerun or a reap took the folder over). Past the budget: kill
  # the tree, log it, retry while attempts ≤ bg_retries, else the overrun verdict. cwd is / so it never
  # holds a folder open (Windows cannot delete a folder a live process stands in).
  set +e
  local dir="$1" nonce="$2" b="" a=1 r t0="" now pid="" w poll=5
  shift 2
  cd / 2>/dev/null || true
  read -r b < "$dir/budget" 2>/dev/null; b="${b%$'\r'}"; case "$b" in ''|*[!0-9]*) b=1800;; esac
  read -r pid < "$dir/pid" 2>/dev/null; pid="${pid%$'\r'}"
  read -r t0 < "$dir/start" 2>/dev/null; t0="${t0%$'\r'}"; case "$t0" in ''|*[!0-9]*) t0="$(date +%s)";; esac
  r="$(cfg bg_retries 1)"; case "$r" in ''|*[!0-9]*) r=1;; esac
  [ "$b" -lt 10 ] && poll=1
  while :; do
    [ -f "$dir/rc" ] && return 0
    w=""; read -r w < "$dir/watch" 2>/dev/null; [ "${w%$'\r'}" = "$nonce" ] || return 0
    now="$(date +%s)"
    if [ $(( now - t0 )) -ge "$b" ]; then
      : > "$dir/killing"
      if [ -f "$dir/rc" ]; then rm -f "$dir/killing"; return 0; fi
      _bgwatch_kill "$pid"
      printf 'bg: budget %ss passed — killed the process tree (attempt %s)\n' "$b" "$a" >> "$dir/log"
      if [ "$a" -gt "$r" ]; then _bgwatch_over "$dir" "$b" "$a"; rm -f "$dir/killing"; return 0; fi
      a=$(( a + 1 )); printf '%s\n' "$a" > "$dir/attempt"
      t0="$(date +%s)"; printf '%s\n' "$t0" > "$dir/astart"
      _bgwatch_launch "$dir" "$@"; pid="$_BGW_PID"
      printf '%s\n' "$pid" > "$dir/pid"
      rm -f "$dir/killing"
    fi
    sleep "$poll"
  done
}

bgwatch_start() { # bgwatch_start <dir> [<cmd…>] — launch ONE detached watchdog for the job in <dir>
  # (its runner already started, pid and budget already written). The command rides along so a retry
  # re-runs exactly what bg_run ran. Writes watch (the nonce), attempt (1) and wpid.
  local dir="${1:-}" nonce
  [ $# -gt 0 ] && shift
  [ -d "$dir" ] || return 0
  nonce="$$.$RANDOM.$RANDOM"
  printf '%s\n' "$nonce" > "$dir/watch"
  printf '1\n' > "$dir/attempt"
  ( _bgwatch_loop "$dir" "$nonce" "$@" ) </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$dir/wpid"
  return 0
}

_bgwatch_gone() { # _bgwatch_gone <dir> <pid> — rc 0 only when the job is truly dead with no verdict:
  # no rc, the pid not alive, no kill in flight, and the pid file still names <pid> (a retry that has
  # just relaunched is running, not crashed). bg_wait and bg_status ask this instead of bg_alive alone.
  local p=""
  [ -f "$1/rc" ] && return 1
  bg_alive "$2" && return 1
  [ -f "$1/killing" ] && return 1
  read -r p 2>/dev/null < "$1/pid" || true
  [ "${p%$'\r'}" = "$2" ]
}

_bgwatch_said() { # _bgwatch_said <name> <dir> — rc 0 + the ONE timed-out line when <dir>/overrun
  # exists (the exit-4 verdict); rc 1 and silent otherwise.
  local b="" a="" c=""
  [ -f "$2/overrun" ] || return 1
  IFS="$POLARIS_TAB" read -r b a 2>/dev/null < "$2/overrun" || true
  IFS= read -r c 2>/dev/null < "$2/cmd" || true
  printf '⛔ %s timed out — killed after %ss, %s attempts · log: %s/log · park it: bash ops/polaris defer -m "%s hung" -- %s\n' \
    "$1" "${b:-?}" "${a%$'\r'}" "$2" "$1" "${c%$'\r'}"
  return 0
}

_bgwatch_join() { # _bgwatch_join <file> — a --steps file's command lines (non-blank, non-#) joined
  # with " && ": the job's cmd record, re-runnable as one line. No line → rc 1.
  [ -f "${1:-}" ] || { printf '⛔ bg run: --steps file not found: %s\n' "${1:-<none>}" >&2; return 1; }
  awk '{ sub(/\r$/, ""); l = $0; sub(/^[ \t]+/, "", l) } l == "" || l ~ /^#/ { next }
    { o = o (n++ ? " && " : "") l } END { if (!n) exit 1; print o }' "$1" \
    || { printf '⛔ bg run: --steps file has no command line: %s\n' "$1" >&2; return 1; }
}

_bgwatch_steps() { # _bgwatch_steps <file> — the --steps job body: each command line in order, ONE job,
  # stopping at the first red; that line's rc is the job's rc and the log names the line.
  local l i=0 r
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"; l="${l#"${l%%[! 	]*}"}"
    case "$l" in ''|'#'*) continue;; esac
    i=$(( i + 1 ))
    printf 'bg: step %s — %s\n' "$i" "$l"
    bash -c "$l" </dev/null; r=$?
    if [ "$r" -ne 0 ]; then printf 'bg: step %s red (rc %s) — %s\n' "$i" "$r" "$l"; return "$r"; fi
  done < "$1"
  return 0
}

bgwatch_reap() { # bgwatch_reap [<name>] — `bg reap`: for every rc-less job of THIS cwd whose runner is
  # still alive and whose attempt is past its budget, do the watchdog's kill + overrun write — when the
  # watchdog is dead, or overdue by 15 s (stuck: a slept laptop). A live watchdog inside its budget owns
  # the job. One `reaped: <name>` line per job; nothing to reap → silent, rc 0. A crashed job (dead
  # runner) has nothing to kill: it stays rc 3, and `next` names it crashed:.
  local root="$PRIMARY/.polaris/bg" d n c me b s a p wp now=""
  me="${PWD//\\//}"
  for d in "$root"/*/; do
    case "$d" in *.prev/) continue;; esac
    [ -e "$d" ] || break
    d="${d%/}"; n="${d##*/}"
    [ -z "${1:-}" ] || [ "$n" = "$1" ] || continue
    [ -f "$d/rc" ] && continue
    p=""; read -r p 2>/dev/null < "$d/pid" || true; p="${p%$'\r'}"
    bg_alive "$p" || continue
    c=""; IFS= read -r c 2>/dev/null < "$d/cwd" || true; c="${c%$'\r'}"; c="${c//\\//}"
    _bgwatch_same "$c" "$me" || continue
    b=""; read -r b 2>/dev/null < "$d/budget" || true; b="${b%$'\r'}"
    case "$b" in ''|*[!0-9]*) c=""; IFS= read -r c 2>/dev/null < "$d/cmd" || true; b="$(bgwatch_budget "$n" "${c%$'\r'}")";; esac
    s=""; read -r s 2>/dev/null < "$d/astart" || read -r s 2>/dev/null < "$d/start" || true; s="${s%$'\r'}"
    case "$s" in ''|*[!0-9]*) continue;; esac
    a=""; read -r a 2>/dev/null < "$d/attempt" || true; a="${a%$'\r'}"; case "$a" in ''|*[!0-9]*) a=1;; esac
    [ -n "$now" ] || now="$(date +%s)"
    [ $(( now - s )) -gt "$b" ] || continue
    wp=""; read -r wp 2>/dev/null < "$d/wpid" || true; wp="${wp%$'\r'}"
    if bg_alive "$wp" && [ $(( now - s )) -le $(( b + 15 )) ]; then continue; fi
    printf 'reaped\n' > "$d/watch"
    : > "$d/killing"
    _bgwatch_kill "$p"
    printf 'bg: budget %ss passed — killed the process tree (attempt %s)\n' "$b" "$a" >> "$d/log"
    _bgwatch_over "$d" "$b" "$a"
    rm -f "$d/killing"
    printf 'reaped: %s\n' "$n"
  done
  return 0
}

_bgwatch_same() { # _bgwatch_same <path> <path> — the same folder? `\` already folded to `/`; a leading
  # /<letter>/ reads as <letter>:/, and the compare ignores case (Windows spells one folder both ways).
  local x="$1" y="$2" m=0 k=1
  case "$x" in /[A-Za-z]/*) x="${x:1:1}:/${x:3}";; esac
  case "$y" in /[A-Za-z]/*) y="${y:1:1}:/${y:3}";; esac
  shopt -q nocasematch && m=1; shopt -s nocasematch
  case "$x" in "$y") k=0;; esac
  [ "$m" -eq 1 ] || shopt -u nocasematch
  return "$k"
}
