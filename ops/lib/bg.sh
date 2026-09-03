# POLARIS lib/bg.sh — background job runner sourced by ops/polaris (the lib loader): detach a
# suite-length command past the harness's 600s tool cap, collect it in bounded chunks (ops/contracts/bg-jobs.md).

bg_resolve() { # bg_resolve <name> — validate the name grammar (bg-jobs.md: [A-Za-z0-9._-]+) and
  # echo the job's registry dir. ALWAYS under the PRIMARY checkout — one registry every session
  # and worktree sees. Existence is the CALLER's question: run creates, status/tail/wait require.
  local n="${1:-}"
  case "$n" in ''|*[!A-Za-z0-9._-]*) die "bad job name '${n:-<empty>}' — allowed: A-Z a-z 0-9 . _ -";; esac
  printf '%s/.polaris/bg/%s' "$PRIMARY" "$n"
}

bg_alive() { # bg_alive <pid> — is the pid a live process (kill -0)? NEVER a verdict by itself:
  # Windows reuses pids, so every caller checks the rc file FIRST — this only splits "running"
  # from "unknown" AFTER the rc file said nothing. Empty/garbage pid → not alive.
  local p="${1:-}"
  case "$p" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$p" 2>/dev/null
}

bg_age() { # bg_age <seconds> — humanize a second count for one-line reports: 42s · 7m · 3h.
  local s="${1:-0}"
  case "$s" in ''|*[!0-9]*) s=0;; esac
  if [ "$s" -ge 3600 ]; then printf '%sh' "$(( s / 3600 ))"
  elif [ "$s" -ge 60 ]; then printf '%sm' "$(( s / 60 ))"
  else printf '%ss' "$s"; fi
}

bg_rotate() { # bg_rotate <name> — archive a job dir to its ONE .prev slot (bg-jobs.md v2:
  # rotation NEVER deletes). The .prev an earlier run left behind is moved aside into
  # .archive/<name>-<epoch> — a dot-dir, so every `*/` reader (bg status, sweep, the finish guard)
  # keeps ignoring it for free, and `sweep --fix` prunes it by age. No dir → silent rc 0. Windows
  # can hold the dir open while a runner still writes its log — die honestly.
  local root="$PRIMARY/.polaris/bg"
  local n="${1:-}"
  [ -d "$root/$n" ] || return 0
  if [ -d "$root/$n.prev" ]; then
    mkdir -p "$root/.archive"
    mv "$root/$n.prev" "$root/.archive/$n-$(date +%s)" 2>/dev/null || true
  fi
  mv "$root/$n" "$root/$n.prev" 2>/dev/null \
    || die "could not rotate '$n' to $n.prev — still running? bash ops/polaris bg status $n"
}

bg_run() { # bg run <name> [--force] [-- <cmd…>] — start a detached job (bg-jobs.md). A bare
  # SUITE-KEY name runs that CONVENTIONS value in the CALLER's cwd (a builder proves its own
  # worktree); `qa` ALWAYS runs in the PRIMARY, so its green stamps .polaris/suite-stamp and a
  # later `finish` rides the existing fast path — zero new code, that is the point. `--` runs an
  # arbitrary command under that name. The launch is the notify_fire idiom — a plain `( … ) &`
  # subshell, no nohup/setsid: MSYS children survive the parent tool call ending, and stdin is
  # /dev/null so nothing ever waits on a tty. Lock-free by design: no board, no events, no lock.
  local name="${1:-}"
  [ $# -gt 0 ] && shift
  local dir
  dir="$(bg_resolve "$name")"
  case "$name" in *.prev) die "'$name' — .prev is the rotation-slot suffix (bg-jobs.md), not a job name";; esac
  local force=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1; shift;;
      --)      shift; break;;
      *)       die "bg run: unexpected '$1' — usage: bg run <name> [--force] [-- <cmd…>]";;
    esac
  done
  local cwd="$PWD"
  local cmdline=""
  if [ $# -gt 0 ]; then
    cmdline="$*"
  else
    local val=""
    case "$name" in
      qa)  cwd="$PRIMARY"; cmdline="bash $SELF qa"; set -- bash "$SELF" qa;;
      test|test_fast|lint|typecheck|build|uat)
           val="$(cfg "$name" "")"
           [ -n "$val" ] || die "CONVENTIONS '${name}:' is empty — nothing to run (set it, or: bg run $name -- <cmd…>)"
           cmdline="$val"; set -- bash -c "$val";;
      *)   die "'$name' is not a suite key (test test_fast lint typecheck build uat · qa) — arbitrary commands: bg run $name -- <cmd…>";;
    esac
  fi
  local pid=""
  if [ -d "$dir" ]; then
    pid="$(cat "$dir/pid" 2>/dev/null | tr -d ' \r\n')"
    if [ ! -f "$dir/rc" ] && bg_alive "$pid"; then
      # OWNERSHIP = the job's cwd, never its pid (bg-jobs.md v2). Five sessions on one machine share
      # ONE registry, so a live same-name job started elsewhere belongs to somebody else: refuse it
      # WITH or WITHOUT --force, because --force kills a pid Windows may already have handed on.
      # Compare normalized (\ → /, case-folded) — the same dir reaches us spelled both ways. `qa`
      # records $PRIMARY on every session, so two `bg run qa` are same-cwd and hit the v1 refusal.
      local owner=""
      owner="$(cat "$dir/cwd" 2>/dev/null | tr -d ' \r\n')"
      if [ -n "$owner" ] \
         && [ "$(printf '%s' "$owner" | tr 'A-Z\\' 'a-z/')" != "$(printf '%s' "$cwd" | tr 'A-Z\\' 'a-z/')" ]; then
        die "job '$name' is RUNNING from another session (cwd $owner) — pick a distinct name (bg run $name-<ID>); --force never kills a foreign live job"
      fi
      [ -n "$force" ] || die "job '$name' is already RUNNING (pid $pid) — bash ops/polaris bg status $name · rerun anyway: bg run $name --force"
      # best-effort kill: the direct children first (ps: PID=$2 PPID=$3 on Git Bash), then the
      # runner — grandchildren may survive; the rotate below dies honestly if they hold the log.
      local kids=""
      kids="$(ps -ef 2>/dev/null | awk -v p="$pid" '$3 == p { print $2 }')" || true
      local k
      for k in $kids; do kill "$k" 2>/dev/null || true; done
      kill "$pid" 2>/dev/null || true
      local w=0
      while bg_alive "$pid" && [ "$w" -lt 20 ]; do sleep 0.2; w=$(( w + 1 )); done
      note "killed running '$name' (pid $pid) — --force"
    fi
    bg_rotate "$name"   # finished, crashed or just killed: the old run archives to <name>.prev
  fi
  mkdir -p "$dir"
  date +%s > "$dir/start"
  printf '%s\n' "$cmdline" > "$dir/cmd"
  printf '%s\n' "$cwd" > "$dir/cwd"
  printf '%s\n' "${CLAUDE_CODE_SESSION_ID:--}" > "$dir/sid"   # informational only — cwd is the ownership key (it also works in CI, where no sid exists)
  : > "$dir/log"
  # pid semantics from birth (the T-064 lesson): spawn, write the pid, nothing in between. The
  # runner writes end THEN rc — rc is written LAST, and its EXISTENCE means "finished". set +e
  # inside: the subshell inherits set -e and must survive the command failing to record its rc.
  (
    set +e
    rc=127
    if cd "$cwd" 2>/dev/null; then
      "$@"
      rc=$?
    else
      echo "bg: cannot cd to $cwd"
    fi
    date +%s > "$dir/end"
    printf '%s\n' "$rc" > "$dir/rc"
  ) </dev/null >>"$dir/log" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$dir/pid"
  say "bg: '$name' started (pid $pid) — log: $dir/log · collect: bash ops/polaris bg wait $name"
}

bg_status() { # bg status [<name>] — rc-file-FIRST, then the pid, NEVER the reverse (bg-jobs.md):
  # rc exists → the job's verdict (content 0 → rc 0 green · else rc 1 red); no rc + pid alive →
  # rc 2 running; no rc + pid dead → rc 3 unknown (crashed — or a Windows pid was reused; bash
  # cannot tell which, only order around it, which is what rc-file-first does). Bare form: one
  # line per job dir (name · verdict · age); `.prev` dirs are rotation ARCHIVES, not live jobs —
  # addressable by explicit name, skipped in the listing and by sweep.
  local root="$PRIMARY/.polaris/bg"
  local now
  now="$(date +%s)"
  local name="${1:-}"
  if [ -z "$name" ]; then
    local d n v s r any=""
    for d in "$root"/*/; do
      [ -e "$d" ] || break
      n="$(basename "$d")"
      case "$n" in *.prev) continue;; esac
      any=1
      if [ -f "$d/rc" ]; then
        r="$(tr -d ' \r\n' < "$d/rc")"
        v="red"; [ "$r" = "0" ] && v="green"
      elif bg_alive "$(cat "$d/pid" 2>/dev/null | tr -d ' \r\n')"; then v="running"
      else v="unknown"; fi
      s="$(cat "$d/start" 2>/dev/null | tr -d ' \r\n')"
      case "$s" in ''|*[!0-9]*) s="$now";; esac
      printf '%s\t%s\t%s\n' "$n" "$v" "$(bg_age $(( now - s )))"
    done
    [ -n "$any" ] || printf 'no background jobs\n'
    return 0
  fi
  local d
  d="$(bg_resolve "$name")"
  [ -d "$d" ] || die "no background job '$name' — bash ops/polaris bg status lists them"
  local p
  p="$(cat "$d/pid" 2>/dev/null | tr -d ' \r\n')"
  if [ -f "$d/rc" ]; then
    local r
    r="$(tr -d ' \r\n' < "$d/rc")"
    local s
    local e
    s="$(cat "$d/start" 2>/dev/null | tr -d ' \r\n')"
    e="$(cat "$d/end" 2>/dev/null | tr -d ' \r\n')"
    case "$s" in ''|*[!0-9]*) s="";; esac
    case "$e" in ''|*[!0-9]*) e="";; esac
    local dur="?"
    [ -n "$s" ] && [ -n "$e" ] && dur="$(bg_age $(( e - s )))"
    if [ "$r" = "0" ]; then
      say "'$name' green — rc 0 in $dur · log: $d/log"
      return 0
    fi
    printf '⛔ %s red — rc %s in %s · tail: bash ops/polaris bg tail %s\n' "$name" "$r" "$dur" "$name"
    return 1
  fi
  if bg_alive "$p"; then
    local s2
    s2="$(cat "$d/start" 2>/dev/null | tr -d ' \r\n')"
    case "$s2" in ''|*[!0-9]*) s2="$now";; esac
    printf '%s running — pid %s · %s · collect: bash ops/polaris bg wait %s\n' "$name" "$p" "$(bg_age $(( now - s2 )))" "$name"
    return 2
  fi
  printf '%s unknown — no rc and pid %s is dead: crashed, or a Windows pid was reused · log: %s/log\n' "$name" "${p:-?}" "$d"
  return 3
}

bg_tail() { # bg tail <name> [-n N] — last N (default 20) log lines, read-only: bounded collection
  # for chunk-polling agents (never the whole log — a suite log runs long).
  local name="${1:-}"
  [ $# -gt 0 ] && shift
  local n=20
  if [ "${1:-}" = "-n" ]; then
    n="${2:-}"
    case "$n" in ''|*[!0-9]*) die "bg tail: -n takes a number, got '${n:-}'";; esac
  fi
  local d
  d="$(bg_resolve "$name")"
  [ -d "$d" ] || die "no background job '$name' — bash ops/polaris bg status lists them"
  tail -n "$n" "$d/log" 2>/dev/null || true
}

bg_wait() { # bg wait <name> [--max <s>] — poll ~2s until the rc file exists; --max default 300,
  # deliberately HALF the harness's 600s tool cap so agents collect in bounded, resumable chunks.
  # Finished → last log lines + verdict, exit 0 green / 1 red (the verdict, never the raw job rc:
  # a job that exited 2 must stay distinguishable from "still running"). Expired → ONE resumable
  # line, exit 2, NEVER a question. Dead pid with no rc mid-wait → the unknown story, exit 3.
  local name="${1:-}"
  [ $# -gt 0 ] && shift
  local max=300
  if [ "${1:-}" = "--max" ]; then
    max="${2:-}"
    case "$max" in ''|*[!0-9]*) die "bg wait: --max takes seconds, got '${max:-}'";; esac
  fi
  local d
  d="$(bg_resolve "$name")"
  [ -d "$d" ] || die "no background job '$name' — bash ops/polaris bg status lists them"
  local waited=0
  local told=0
  local p=""
  while :; do
    if [ -f "$d/rc" ]; then
      local r
      r="$(tr -d ' \r\n' < "$d/rc")"
      local s
      local e
      s="$(cat "$d/start" 2>/dev/null | tr -d ' \r\n')"
      e="$(cat "$d/end" 2>/dev/null | tr -d ' \r\n')"
      case "$s" in ''|*[!0-9]*) s="";; esac
      case "$e" in ''|*[!0-9]*) e="";; esac
      local dur="?"
      [ -n "$s" ] && [ -n "$e" ] && dur="$(bg_age $(( e - s )))"
      bg_tail "$name"
      if [ "$r" = "0" ]; then
        say "'$name' green — rc 0 in $dur"
        return 0
      fi
      printf '⛔ %s red — rc %s in %s · full log: %s/log\n' "$name" "$r" "$dur" "$d"
      return 1
    fi
    p="$(cat "$d/pid" 2>/dev/null | tr -d ' \r\n')"
    if ! bg_alive "$p" && [ ! -f "$d/rc" ]; then
      # the runner writes rc BEFORE exiting, so the [ ! -f ] re-check above closes the race —
      # a dead pid still without rc is a crash, or Windows reused the pid (rc-file-first honesty).
      printf '%s unknown — no rc and pid %s is dead: crashed, or a Windows pid was reused · log: %s/log\n' "$name" "${p:-?}" "$d"
      return 3
    fi
    if [ "$waited" -ge "$max" ]; then
      printf 'still running — bash ops/polaris bg wait %s\n' "$name"
      return 2
    fi
    sleep 2
    waited=$(( waited + 2 ))
    if [ $(( waited - told )) -ge 30 ]; then
      note "waiting on '$name' — ${waited}s (pid ${p:-?})"
      told="$waited"
    fi
  done
}

cmd_bg() { # polaris bg <run|status|tail|wait> … — dispatch (bg-jobs.md). Workspace machinery,
  # like park: NEVER writes the board, EVENTS.ndjson, or any lock; the registry is per-job-dir,
  # so two jobs of DIFFERENT names cannot interact by construction.
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    run)    bg_run "$@";;
    status) bg_status "${1:-}";;
    tail)   bg_tail "$@";;
    wait)   bg_wait "$@";;
    *)      die "usage: polaris bg run <name> [--force] [-- <cmd…>] · bg status [<name>] · bg tail <name> [-n N] · bg wait <name> [--max <s>]";;
  esac
}
