# POLARIS lib/pulse.sh — the away run's three small verbs (ops/contracts/walk-away.md § 2.2-2.3):
# `pulse` (what a timer-woken session runs: reap, then ONE word on line 1), `preflight <slug>` (the
# mechanical "needs you before I start" checks) and `defer` (park a command for the close). Plus
# _run_armed, the kit-wide "is an approved away run armed?" read (§ 1). Read-only except `defer`
# (one line in .polaris/run/deferred.tsv) and `pulse --reenter` (line 3 of the armed file).

_run_armed() { # _run_armed — rc 0 when some <primary>/.polaris/run/*.armed has a line-1 epoch within
  # reentry_hours (default 12) of now, printing the NEWEST such file's path; rc 1 otherwise. Never
  # dies. Builtins until a file exists: the unarmed path (every command, every day) costs no fork.
  local f e newest="" ne=-1 now="" h=12
  for f in "$PRIMARY"/.polaris/run/*.armed; do
    [ -f "$f" ] || continue
    e=""; read -r e 2>/dev/null < "$f" || true; e="${e%$'\r'}"
    case "$e" in ''|*[!0-9]*) continue;; esac
    if [ -z "$now" ]; then
      now="$(date +%s 2>/dev/null)" || now=""; case "$now" in ''|*[!0-9]*) return 1;; esac
      h="$(cfg reentry_hours 12 2>/dev/null)" || h=12; case "$h" in ''|*[!0-9]*) h=12;; esac
    fi
    [ $(( now - e )) -le $(( h * 3600 )) ] || continue
    [ "$e" -ge "$ne" ] && { ne="$e"; newest="$f"; }
  done
  [ -n "$newest" ] || return 1
  printf '%s\n' "$newest"
}

cmd_pulse() { # pulse [--reenter] — reap first (bgwatch_reap: only budgets kill), then line 1 is ONE of
  # ok · act <next line 1> · done · parked, lines 2+ three-space notes, rc 0 always. parked = this
  # session's <sid>.parked (any *.parked without a sid) or the stalled marker; done = armed and next
  # says finish with nothing under it, or no armed file left and this session's finish went green.
  case "${1:-}" in
    '') ;;
    --reenter) _pulse_reenter; return $?;;
    *) die "usage: polaris pulse [--reenter]";;
  esac
  local run="$PRIMARY/.polaris/run" sid="${CLAUDE_CODE_SESSION_ID:-}" rp="" a="" out="" l1 pk="" f
  rp="$(bgwatch_reap 2>/dev/null)" || true
  if [ -n "$sid" ]; then [ -f "$run/$sid.parked" ] && pk="parked: $sid.parked"
  else for f in "$run"/*.parked; do [ -f "$f" ] && { pk="parked: ${f##*/}"; break; }; done; fi
  [ -z "$pk" ] && [ -f "$run/stalled" ] && pk="stalled: $(cut -f2- "$run/stalled" 2>/dev/null | tr -d '\r' | head -1)"
  if [ -n "$pk" ]; then
    printf 'parked\n'; note "$pk"; note "what waits on you: bash ops/polaris finish"
  elif a="$(_run_armed)"; then
    out="$(cmd_next 2>/dev/null)" || true
    l1="${out%%$'\n'*}"
    case "$l1" in
      ''|wait|wait\ *|stop|stop\ *) printf 'ok\n'; note "next: ${l1:-nothing}"; _pulse_quiet;;
      finish) if [ "$out" = "$l1" ]; then printf 'done\n'; note "the run is over — run bash ops/polaris finish, then delete the pulse"
              else printf 'act finish\n'; fi;;
      *) printf 'act %s\n' "$l1";;
    esac
  elif [ -n "$sid" ] && [ -f "$PRIMARY/.polaris/handover/$sid/finished" ]; then
    printf 'done\n'; note "the run finished — delete the pulse"
  else
    printf 'ok\n'; note "not armed — the pulse only acts on an approved away run"
  fi
  [ -z "$rp" ] || printf '%s\n' "$rp" | sed 's/^/   /'
  return 0
}

_pulse_quiet() { # _pulse_quiet — armed and nothing to do: one note when the board has been quiet past
  # stall_minutes (default 20) — the newest of EVENTS.ndjson and the armed epoch. A report, never a kill.
  local m t now
  m="$(cfg stall_minutes 20)"; case "$m" in ''|*[!0-9]*) m=20;; esac
  t="$(stat -c %Y "$EVENTS" 2>/dev/null || stat -f %m "$EVENTS" 2>/dev/null || true)"
  case "$t" in ''|*[!0-9]*) t=0;; esac
  [ -n "${a:-}" ] && { read -r now 2>/dev/null < "$a" || true; now="${now%$'\r'}"; case "$now" in ''|*[!0-9]*) ;; *) [ "$now" -gt "$t" ] && t="$now";; esac; }
  now="$(date +%s)"
  [ "$t" -gt 0 ] && [ $(( now - t )) -ge $(( m * 60 )) ] || return 0
  note "quiet $(bg_age $(( now - t ))) — past stall_minutes ($m): the Stop gate and keep-awake mark a stall"
}

_pulse_reenter() { # pulse --reenter — armed within reentry_hours and reentries < reentry_max (3) → line 3
  # becomes `reentries <n+1>` and ONE reenter line; else `refused: <why>` rc 1, nothing written.
  local a="" e="" s="" r="" n mx
  if ! a="$(_run_armed)"; then
    printf 'refused: not armed — no approved away run within reentry_hours\n'; return 1
  fi
  { read -r e; IFS= read -r s; IFS= read -r r; } 2>/dev/null < "$a" || true
  e="${e%$'\r'}"; s="${s%$'\r'}"; r="${r%$'\r'}"
  n="${r#reentries }"; case "$n" in ''|*[!0-9]*) n=0;; esac
  mx="$(cfg reentry_max 3)"; case "$mx" in ''|*[!0-9]*) mx=3;; esac
  if [ "$n" -ge "$mx" ]; then
    printf 'refused: re-entered %s times — reentry_max is %s\n' "$n" "$mx"; return 1
  fi
  printf '%s\n%s\nreentries %s\n' "$e" "$s" "$(( n + 1 ))" > "$a.tmp.$$" && mv -f "$a.tmp.$$" "$a" \
    || { rm -f "$a.tmp.$$" 2>/dev/null; printf 'refused: could not write %s\n' "${a##*/}"; return 1; }
  printf 'reenter %s — run: bash ops/polaris next and follow line 1\n' "${s:--}"
  return 0
}

_pf_timed() { # _pf_timed <seconds> <cmd…> — run with a hard budget (no `timeout` on stock macOS): rc
  # of the command, or 124 after killing its tree past the budget.
  local s="$1" p i=0 r=0; shift
  ( "$@" ) </dev/null >/dev/null 2>&1 &
  p=$!
  while kill -0 "$p" 2>/dev/null; do
    if [ "$i" -ge $(( s * 5 )) ]; then _bgwatch_kill "$p"; wait "$p" 2>/dev/null || true; return 124; fi
    sleep 0.2; i=$(( i + 1 ))
  done
  wait "$p" || r=$?
  return "$r"
}

cmd_preflight() { # preflight <slug> — read-only: one line per mechanical check, `✅ <what>` or
  # `⛔ needs you: <what> — <the command or click>`; last line `preflight: clear` (rc 0) or
  # `preflight: <n> need you` (rc 1). Checks: origin answers (20 s) · gh signed in (only under
  # publish: pr or when the plan names gh) · every risk: high card and ask scope of the plan with no
  # yes from approve --plan · the measured suite time.
  local slug="${1:-}" need=0 r=0 pf="" files f id rk v sc want have miss n=0 pat rs kind rmsg nl='
'
  case "$slug" in ''|*[!A-Za-z0-9._-]*) die "usage: polaris preflight <slug> — the plan's slug, as its cards' plan: names it";; esac
  if git -C "$PRIMARY" remote get-url origin >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 _pf_timed 20 git -C "$PRIMARY" ls-remote --heads origin || r=$?
    if [ "$r" -eq 0 ]; then printf '✅ origin answers\n'
    elif [ "$r" -eq 124 ]; then printf '⛔ needs you: origin did not answer within 20s — git ls-remote --heads origin (sign in, or check the network)\n'; need=$(( need + 1 ))
    else printf '⛔ needs you: origin refused — git ls-remote --heads origin (sign in, or fix the remote)\n'; need=$(( need + 1 )); fi
  else
    printf '✅ no origin remote — nothing to reach\n'
  fi
  pf="$PRIMARY/plans/$slug.md"
  if [ "$(cfg publish direct)" = pr ] || { [ -f "$pf" ] && grep -qE '(^|[^A-Za-z0-9_./-])gh([^A-Za-z0-9_-]|$)' "$pf" 2>/dev/null; }; then
    if ! command -v gh >/dev/null 2>&1; then printf '⛔ needs you: gh is not installed — install the GitHub CLI, then gh auth login\n'; need=$(( need + 1 ))
    elif _pf_timed 20 gh auth status; then printf '✅ gh is signed in\n'
    else printf '⛔ needs you: gh is not signed in — gh auth login\n'; need=$(( need + 1 )); fi
  fi
  # the plan's cards: ONE grep finds them; the per-card reads below run only for those few files
  files="$(grep -lE "^plan:[[:space:]]*$slug[[:space:]]*(#.*)?$" "$BOARD"/backlog/*.md "$BOARD"/ready/*.md "$BOARD"/active/*.md \
           "$BOARD"/review/*.md "$BOARD"/blocked/*.md 2>/dev/null)" || true
  for f in $files; do
    n=$(( n + 1 )); id="${f##*/}"; id="${id%.md}"; want=""
    rk="$(fm_get risk "$f" 2>/dev/null || true)"
    [ "$rk" = high ] && want="merge"
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      case "$v" in
        schema|dependency|delete) want="$want${nl}need:$v";;
        *) printf '⛔ needs you: %s needs: %s — approve --plan cannot record it; edit the card\n' "$id" "$v"; need=$(( need + 1 ));;
      esac
    done <<EOF
$(fm_list needs "$f" 2>/dev/null || true)
EOF
    while IFS="$POLARIS_TAB" read -r rs kind pat rmsg; do
      [ "$kind" = ask ] || continue
      while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        if owned_match "$pat" "$rs"; then want="$want$nl$rs"; break; fi
      done <<EOF
$(fm_list files_owned "$f" 2>/dev/null || true)
EOF
    done <<EOF
$(rules_lines)
EOF
    have="$nl$(approved_entries "$f")$nl"; miss=""
    while IFS= read -r sc; do
      [ -n "$sc" ] || continue
      case "$have" in *"$nl$sc|$slug$nl"*) ;; *) miss="${miss:+$miss, }$sc";; esac
    done <<EOF
$(printf '%s\n' "$want" | awk 'NF && !seen[$0]++')
EOF
    [ -z "$miss" ] && continue
    printf '⛔ needs you: %s has no yes for %s — bash ops/polaris approve --plan %s -m "why"\n' "$id" "$miss" "$slug"
    need=$(( need + 1 ))
  done
  [ "$need" -eq 0 ] && printf '✅ plan %s: %s card(s) — nothing in it waits on a yes\n' "$slug" "$n"
  v=""; read -r v rk 2>/dev/null < "$PRIMARY/.polaris/last-suite-seconds" || true; v="${v%$'\r'}"
  case "$v" in ''|*[!0-9]*) printf '✅ suite time: unknown — the first wave gate will measure it\n';;
    *) printf '✅ suite time: %s (the last full run)\n' "$(bg_age "$v")";; esac
  if [ "$need" -eq 0 ]; then printf 'preflight: clear\n'; return 0; fi
  printf 'preflight: %s need you\n' "$need"
  return 1
}

cmd_defer() { # defer -m "<why>" -- <cmd…> — park a command for the close: ONE line
  # `<epoch><TAB><why><TAB><cmd>` in .polaris/run/deferred.tsv (TABs and newlines folded to spaces),
  # then `deferred: <cmd> — finish lists it`. No -m or no command → usage, rc 1, nothing written.
  local why="" cmd run="$PRIMARY/.polaris/run"
  while [ $# -gt 0 ]; do
    case "$1" in
      -m) why="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
      --) shift; break;;
      *)  die "usage: polaris defer -m \"why\" -- <cmd…>";;
    esac
  done
  [ -n "$why" ] && [ $# -gt 0 ] || die "usage: polaris defer -m \"why\" -- <cmd…>"
  cmd="$*"; cmd="${cmd//$POLARIS_TAB/ }"; cmd="${cmd//$'\n'/ }"; why="${why//$POLARIS_TAB/ }"; why="${why//$'\n'/ }"
  mkdir -p "$run" || die "defer: could not make $run"
  printf '%s\t%s\t%s\n' "$(date +%s)" "$why" "$cmd" >> "$run/deferred.tsv" || die "defer: could not write $run/deferred.tsv"
  printf 'deferred: %s — finish lists it\n' "$cmd"
}
