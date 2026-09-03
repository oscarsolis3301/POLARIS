# POLARIS lib/handover.sh — `polaris next` sourced by ops/polaris (the lib loader): the seven-verb
# router read off the board, `--do` promotes backlog under the board lock, `--brief` re-anchors a
# compacted chat (ops/contracts/role-handover.md). A session ends with its task (Invariant 5), so
# every next role used to need a human kickoff; `next` names the next context's role from disk.
# Read-only by contract; `--do` alone writes, and only the board. bash 3.2: no mapfile, no assoc
# arrays, no `case` inside `$(...)`. Exactly EIGHT fns, no more — api-kit pins every name.

next_dir() { # next_dir — this session's state dir: $PRIMARY/.polaris/handover/<sid>/ (gitignored,
  # per checkout, never the board). Never created here — evt() and the hooks write it, `next` reads.
  # No sid (a plain shell, CI) ⇒ `-`, which matches no lock.
  printf '%s/.polaris/handover/%s' "$PRIMARY" "${CLAUDE_CODE_SESSION_ID:--}"
}

next_landable() { # next_landable — row 1's predicate, ONE pass over review/ and the lease.
  # NX_REV_OK = landable IDs (risk ≠ high AND approved: empty) · NX_REV_HUMAN = the rest, whose
  # merge only a human may license · NX_LEASE = absent | mine | stale | live, on int_on's OWN steal
  # predicate (worktree-liveness.md § steals). rc 0 iff something is landable AND the lane is open —
  # under BOTH landing modes, since a self-land tail that queued leaves its task for nobody.
  local f id rk ap lease now e hp sm dead
  NX_REV_OK=""; NX_REV_HUMAN=""; NX_LEASE=absent; NX_LEASE_WHO=""; NX_LEASE_M=0
  for f in "$BOARD/review/"*.md; do [ -e "$f" ] || break
    id="$(basename "$f" .md)"
    rk="$(fm_get risk "$f" 2>/dev/null || true)"; ap="$(fm_list approved "$f" 2>/dev/null || true)"
    if [ "$rk" = "high" ] || [ -n "$ap" ]; then NX_REV_HUMAN="${NX_REV_HUMAN:+$NX_REV_HUMAN }$id"
    else NX_REV_OK="${NX_REV_OK:+$NX_REV_OK }$id"; fi
  done
  lease="$LOCKS/.int-lease"
  if [ -d "$lease" ]; then
    who; now="$(date +%s)"
    e="$(cat "$lease/epoch" 2>/dev/null | tr -d ' \r\n')"; case "$e" in ''|*[!0-9]*) e="$now";; esac
    NX_LEASE_M=$(( (now - e) / 60 ))
    NX_LEASE_WHO="$(cat "$lease/who" 2>/dev/null | tr -d '\r\n')"; NX_LEASE_WHO="${NX_LEASE_WHO:-unknown}"
    hp="$(cat "$lease/pid" 2>/dev/null | tr -d ' \r\n')"
    sm="$(cfg integration_stale_minutes 45)"; case "$sm" in ''|*[!0-9]*) sm=45;; esac
    NX_LEASE=live
    if [ "$hp" = "$$" ] || [ "$NX_LEASE_WHO" = "$WHO" ]; then NX_LEASE=mine
    elif [ $(( now - e )) -gt $(( sm * 60 )) ]; then
      dead=0
      case "$hp" in ''|*[!0-9]*) dead=1;;
        *) case "${OSTYPE:-}" in
             msys*|cygwin*) ps -W 2>/dev/null | awk -v p="$hp" '$1==p{f=1} END{exit !f}' || dead=1;;
             *) kill -0 "$hp" 2>/dev/null || dead=1;;
           esac;;
      esac
      { [ "$dead" -eq 1 ] || [ $(( now - e )) -gt $(( 2 * sm * 60 )) ]; } && NX_LEASE=stale
    fi
  fi
  [ -n "$NX_REV_OK" ] || return 1
  case "$NX_LEASE" in absent|mine|stale) return 0;; esac
  return 1
}

next_claimable() { # next_claimable — row 3's predicate: the top-wsjf ready task (ties by ID) that is
  # unlocked, not in this session's `avoid` list and not foreign. Foreign = drain: plan AND the
  # task's plan: set AND ≠ the plan this session first claimed under (<dir>/plan; no file ⇒ nothing
  # is foreign). NX_BUILD + NX_BUILD_NOTE · NX_FOREIGN (finish names them) · NX_READY_N.
  local d f id w pl drain myplan="" have="" cands="" title pts
  d="$(next_dir)"; drain="$(cfg drain plan)"
  [ -f "$d/plan" ] && { have=1; myplan="$(tr -d ' \r\n' < "$d/plan")"; }
  NX_BUILD=""; NX_BUILD_NOTE=""; NX_FOREIGN=""; NX_READY_N=0
  for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
    id="$(basename "$f" .md)"; NX_READY_N=$(( NX_READY_N + 1 ))
    [ -d "$LOCKS/$id" ] && continue
    grep -qx "$id" "$d/avoid" 2>/dev/null && continue
    pl="$(fm_get plan "$f" 2>/dev/null || true)"
    if [ "$drain" = "plan" ] && [ -n "$pl" ] && [ -n "$have" ] && [ "$pl" != "$myplan" ]; then
      NX_FOREIGN="${NX_FOREIGN:+$NX_FOREIGN }$id"; continue
    fi
    w="$(fm_get wsjf "$f")"; case "$w" in ''|*[!0-9.]*) w=0;; esac
    cands="$cands$w$POLARIS_TAB$id
"
  done
  [ -n "$cands" ] || return 1
  NX_BUILD="$(printf '%s' "$cands" | sort -t "$POLARIS_TAB" -k1,1rn -k2,2 | sed -n 1p | cut -f2)"
  f="$BOARD/ready/$NX_BUILD.md"
  title="$(fm_get title "$f")"; title="${title#\"}"; title="${title%\"}"
  pts="$(fm_get points "$f")"; w="$(fm_get wsjf "$f")"
  NX_BUILD_NOTE="$title (${pts:-?} pts, wsjf ${w:-0})"
  return 0
}

next_promote() { # next_promote [--do] — row 4's scan, and `--do`'s worker. Every backlog/ task (wsjf
  # desc; files without frontmatter such as IDEAS.md skipped) is held to the FULL ready gate, drift's
  # checks reused: every depends_on in done/ · contract file exists · points ∉ {8, 13, ''} · no
  # unapproved `ask` scope (rules_gate) · files_owned disjoint from ready/ ∪ active/ BOTH directions
  # (pat_overlap — claim's loop, builder.sh) INCLUDING tasks accepted earlier in this pass. Scan
  # fills NX_ELIGIBLE and writes nothing; `--do` re-checks INSIDE the mutex, moves each passer
  # (mv + set_fm + evt promote), lands ONE board_commit + sync_board, and returns NX_PROMOTED.
  local mode="${1:-}" f id w cands="" acc="" pts v d ok g gid cpat apat over deps others
  NX_ELIGIBLE=""; NX_PROMOTED=""; NX_HELD=""
  for f in "$BOARD/backlog/"*.md; do [ -e "$f" ] || break
    [ "$(sed -n 1p "$f" | tr -d '\r')" = "---" ] || continue
    w="$(fm_get wsjf "$f")"; case "$w" in ''|*[!0-9.]*) w=0;; esac
    cands="$cands$w$POLARIS_TAB$(basename "$f" .md)
"
  done
  [ -n "$cands" ] || return 1
  [ "$mode" = "--do" ] && mutex_on
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    f="$BOARD/backlog/$id.md"; [ -f "$f" ] || continue
    ok=1
    v="$(fm_get contract "$f")"; { [ -z "$v" ] || [ ! -f "$PRIMARY/$v" ]; } && ok=0
    pts="$(fm_get points "$f")"; case "$pts" in ''|8|13) ok=0;; esac
    deps=""
    while IFS= read -r d; do [ -z "$d" ] && continue
      deps="${deps:+$deps, }$d"; task_file "$d" done >/dev/null || ok=0
    done <<EOF_DEP
$(dep_ids "$f")
EOF_DEP
    [ "$ok" -eq 1 ] || continue
    others="$(for g in "$BOARD/active/"*.md "$BOARD/ready/"*.md; do [ -e "$g" ] && printf '%s\n' "$g"; done; printf '%s' "$acc")"
    over=""
    while IFS= read -r cpat; do [ -z "$cpat" ] && continue
      if [ -z "$over" ] && rules_gate "$cpat" "$id" && [ "$RULES_GATE" = "ask" ]; then
        over="held: $id — ask scope $RULES_GATE_SCOPE needs a human's yes"
      fi
      while IFS= read -r g; do [ -e "$g" ] || continue
        gid="$(basename "$g" .md)"; [ "$gid" = "$id" ] && continue
        while IFS= read -r apat; do [ -z "$apat" ] && continue
          if [ -z "$over" ] && pat_overlap "$cpat" "$apat"; then over="held: $id — overlaps $gid on '$cpat'"; fi
        done <<EOF_APAT
$(fm_list files_owned "$g")
EOF_APAT
      done <<EOF_OTH
$others
EOF_OTH
    done <<EOF_CPAT
$(fm_list files_owned "$f")
EOF_CPAT
    [ -n "$over" ] && { NX_HELD="$NX_HELD   $over
"; continue; }
    NX_ELIGIBLE="${NX_ELIGIBLE:+$NX_ELIGIBLE }$id"
    if [ "$mode" = "--do" ]; then
      mv "$f" "$BOARD/ready/$id.md"; set_fm status ready "$BOARD/ready/$id.md"
      evt promote "$id" "deps done: ${deps:-none}" "$pts"; f="$BOARD/ready/$id.md"
    fi
    acc="$acc$f
"
  done <<EOF_CAND
$(printf '%s' "$cands" | sort -t "$POLARIS_TAB" -k1,1rn -k2,2 | cut -f2)
EOF_CAND
  if [ "$mode" = "--do" ]; then
    NX_PROMOTED="$NX_ELIGIBLE"
    # ONE commit for the pass; the moved set carries EVENTS.ndjson, so every `evt promote` rides it.
    [ -n "$NX_PROMOTED" ] && { board_commit "chore(board): promote $NX_PROMOTED"; sync_board; }
    mutex_off; trap - EXIT
  fi
  [ -n "$NX_ELIGIBLE" ]
}

next_budget() { # next_budget <N> — row 2's predicate, asked ONLY when a build or a promote would
  # otherwise fire: hops ≥ run_max_tasks (cap ≠ 0), or minutes since max(started, prompted-at) ≥
  # run_max_minutes (cap ≠ 0). NX_CAP names the cap that hit; NX_BUDGET_NOTE is the CONDUCTOR's
  # verbatim budget line, N = ready + eligible backlog. Caps default as ops/KEYS.tsv does.
  local d hops mt mm now s p base
  d="$(next_dir)"; NX_CAP=""; NX_BUDGET_NOTE=""
  mt="$(cfg run_max_tasks 12)"; case "$mt" in ''|*[!0-9]*) mt=12;; esac
  mm="$(cfg run_max_minutes 90)"; case "$mm" in ''|*[!0-9]*) mm=90;; esac
  hops="$(cat "$d/hops" 2>/dev/null | tr -d ' \r\n')"; case "$hops" in ''|*[!0-9]*) hops=0;; esac
  [ "$mt" -ne 0 ] && [ "$hops" -ge "$mt" ] && NX_CAP=run_max_tasks
  if [ -z "$NX_CAP" ] && [ "$mm" -ne 0 ]; then
    now="$(date +%s)"; base=0
    for p in started prompted-at; do
      s="$(cat "$d/$p" 2>/dev/null | tr -d ' \r\n')"; case "$s" in ''|*[!0-9]*) continue;; esac
      [ "$s" -gt "$base" ] && base="$s"
    done
    [ "$base" -gt 0 ] && [ $(( (now - base) / 60 )) -ge "$mm" ] && NX_CAP=run_max_minutes
  fi
  [ -n "$NX_CAP" ] || return 1
  NX_BUDGET_NOTE="budget: $NX_CAP reached — ${1:-0} tasks left on the board; say start to continue"
  return 0
}

next_route() { # next_route — the decision table (role-handover.md), first match wins, one read of
  # the board: line 1 = `<verb>[ <ID>]`, every other line a three-space note (the `triage` shape).
  # Writes nothing. `wait` is NEVER emitted with nothing in flight; `stop` fires only where a build
  # or promote would otherwise have, so a budget stops work rather than inventing it.
  local d sid lk id f n can=0 pro=0 mine="" active="" blocked="" bgs="" p own cwds
  d="$(next_dir)"; sid="${CLAUDE_CODE_SESSION_ID:--}"
  # 0 — my own live lock on an active task: never a second task mid-task
  if [ "$sid" != "-" ]; then
    for lk in "$LOCKS"/*/; do [ -e "$lk" ] || break
      lk="${lk%/}"; id="$(basename "$lk")"
      [ "$(sed -n 4p "$lk/meta" 2>/dev/null | tr -d '\r')" = "$sid" ] || continue
      mine="${mine:+$mine }$id"
      if task_file "$id" active >/dev/null; then printf 'resume %s\n' "$id"
        note "mid-task: your own lock is live — finish or release before anything else"; return 0; fi
    done
  fi
  # 1 — landable review/ work and an open lane (absent · stale · mine), under both landing modes
  if next_landable; then
    printf 'integrate\n'; note "review/: $NX_REV_OK"
    [ -n "$NX_REV_HUMAN" ] && note "risk: high, human approves: $NX_REV_HUMAN"
    return 0
  fi
  # rows 3 and 4 run BEFORE row 2: a budget stops only what would otherwise start, and its note
  # counts what is left, so both predicates must have answered before the cap is consulted.
  next_claimable && can=1
  next_promote && pro=1
  n="$(printf '%s' "$NX_ELIGIBLE" | wc -w | tr -d ' ')"
  if [ "$can" -eq 1 ] || [ "$pro" -eq 1 ]; then
    if next_budget $(( NX_READY_N + n )); then printf 'stop\n'; note "$NX_BUDGET_NOTE"; return 0; fi
  fi
  if [ "$can" -eq 1 ]; then printf 'build %s\n' "$NX_BUILD"; note "$NX_BUILD_NOTE"; return 0; fi
  if [ "$pro" -eq 1 ]; then printf 'promote\n'
    note "eligible: $NX_ELIGIBLE — bash ops/polaris next --do promotes them under the board lock"; return 0; fi
  # 5 — wait, only with work genuinely in flight: others' lanes · a live foreign lease · an OWN live
  # bg job (ownership = the job's cwd, never its pid — bg-jobs.md v2) · review/ only a human lands.
  for f in "$BOARD/active/"*.md; do [ -e "$f" ] || break; active="${active:+$active }$(basename "$f" .md)"; done
  cwds="$(printf '%s\n%s\n' "$PRIMARY" "$PWD"; for id in $mine; do wt_path "$id"; printf '\n'; done)"
  cwds="$(printf '%s' "$cwds" | tr 'A-Z\\' 'a-z/')"
  for f in "$PRIMARY"/.polaris/bg/*/; do [ -e "$f" ] || break
    f="${f%/}"; n="$(basename "$f")"
    case "$n" in *.prev) continue;; esac
    [ -f "$f/rc" ] && continue
    bg_alive "$(cat "$f/pid" 2>/dev/null | tr -d ' \r\n')" || continue
    p="$(cat "$f/cwd" 2>/dev/null | tr -d ' \r\n' | tr 'A-Z\\' 'a-z/')"; own=0
    [ -n "$p" ] && printf '%s' "$cwds" | grep -qxF "$p" && own=1
    [ "$own" -eq 1 ] && bgs="${bgs:+$bgs }$n"
  done
  if [ -n "$active" ] || [ "$NX_LEASE" = live ] || [ -n "$bgs" ] || [ -n "$NX_REV_HUMAN" ]; then
    printf 'wait\n'
    [ -n "$active" ] && note "active: $active"
    [ "$NX_LEASE" = live ] && note "lease: $NX_LEASE_WHO (${NX_LEASE_M}m)"
    for n in $bgs; do note "bg: $n running"; done
    [ -n "$NX_REV_HUMAN" ] && note "review/ awaits a human: $NX_REV_HUMAN"
    return 0
  fi
  # 6 — otherwise the run's board is done; name what is parked, each only when non-empty
  printf 'finish\n'
  [ -n "$NX_FOREIGN" ] && note "foreign queued (drain: plan): $NX_FOREIGN"
  for f in "$BOARD/blocked/"*.md; do [ -e "$f" ] || break; blocked="${blocked:+$blocked }$(basename "$f" .md)"; done
  [ -n "$blocked" ] && note "blocked/: $blocked"
  [ -n "$NX_REV_HUMAN" ] && note "risk: high awaiting approval: $NX_REV_HUMAN"
  return 0
}

next_brief() { # next_brief — `--brief`: ≤8 lines, no `|` anywhere, markers verbatim, so a compacted
  # chat re-anchors from disk: role (my live lock on an active task ⇒ BUILDER · lease mine ⇒
  # INTEGRATOR · else none) · task and worktree (only with a lock, and only when the dir exists) ·
  # up to three of MY last events, newest first · line 1 of `next` · the role file it implies (omitted at `role: none`).
  local sid lk id="" col="" role=none wt n line1 rfile now ts ev eid line
  sid="${CLAUDE_CODE_SESSION_ID:--}"
  if [ "$sid" != "-" ]; then
    for lk in "$LOCKS"/*/; do [ -e "$lk" ] || break
      lk="${lk%/}"
      [ "$(sed -n 4p "$lk/meta" 2>/dev/null | tr -d '\r')" = "$sid" ] || continue
      id="$(basename "$lk")"; col="$(task_col "$id" 2>/dev/null || true)"; break
    done
  fi
  [ -n "$id" ] && [ "$col" = active ] && role=BUILDER
  if [ "$role" = none ]; then next_landable >/dev/null 2>&1 || true; [ "$NX_LEASE" = mine ] && role=INTEGRATOR; fi
  printf 'role: %s\n' "$role"
  [ -n "$id" ] && printf 'task: %s (%s, yours)\n' "$id" "${col:-unknown}"
  if [ -n "$id" ] && [ -d "$(wt_path "$id")" ]; then
    wt="$(wt_path "$id")"; n="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    printf 'worktree: .polaris/wt/%s — %s uncommitted\n' "$id" "${n:-0}"
  fi
  who; now="$(date +%s)"
  while IFS= read -r line; do [ -n "$line" ] || continue
    ts="$(printf '%s' "$line" | sed -n 's/.*"ts":\([0-9]*\).*/\1/p')"
    ev="$(printf '%s' "$line" | sed -n 's/.*"ev":"\([^"]*\)".*/\1/p')"
    eid="$(printf '%s' "$line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
    printf 'last: %s %s %sm ago\n' "$ev" "$eid" "$(( (now - ${ts:-$now}) / 60 ))"
  done <<EOF_EV
$(grep -F "\"who\":\"$WHO\"" "$EVENTS" 2>/dev/null | tail -3 | sed '1!G;h;$!d')
EOF_EV
  line1="$(next_route | sed -n 1p)"
  printf 'next: %s\n' "$line1"
  case "${line1%% *}" in
    resume|build)      rfile=BUILDER;;
    integrate|promote) rfile=INTEGRATOR;;
    *)                 rfile="$role";;
  esac
  [ "$rfile" = none ] || printf 'read ops/roles/%s.md if this context lost it\n' "$rfile"
  return 0
}

cmd_next() { # next [--do|--brief] — dispatch. Bare: the route, read-only. --do: promote under the
  # board lock, then the FRESH route on line 1 (a verb under every flag, so a caller never parses),
  # the promote notes (`promoted:` · `held:` · `nothing to promote`), and `drift` as the audit any
  # board mutation earns — findings printed, rc still 0. --brief: the anchor. Bad flag = the ONLY rc 1.
  local promoted held
  case "${1:-}" in
    '')      next_route;;
    --brief) next_brief;;
    --do)
      next_promote --do || true
      promoted="$NX_PROMOTED"; held="$NX_HELD"
      next_route
      if [ -n "$promoted" ]; then note "promoted: $promoted"; else note "nothing to promote"; fi
      [ -n "$held" ] && printf '%s' "$held"
      [ -n "$promoted" ] && ( cmd_drift ) 2>&1 | sed 's/^/   /'
      ;;
    *) die "usage: polaris next [--do|--brief]";;
  esac
  return 0
}
