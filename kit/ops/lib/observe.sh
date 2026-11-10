# POLARIS lib/observe.sh — read-only observers sourced by ops/polaris (the lib loader): notify-gate,
# status/--brief, sweep, doctor, metrics, why, dash, and fleet. drift.sh, check.sh, route.sh and qa.sh
# were cut from this file (ops/contracts/minutes.md § 3).

cmd_notify_gate() { # notify-gate <kind> [ID] — fire the notify: hook at a HUMAN GATE, and do
  # nothing else. Conductor calls it when the run starts waiting on a person; it is ADDITIVE to
  # the in-conversation gate, never a substitute. Kinds (ops/contracts/hands-free-knobs.md):
  #   plan          EV=waiting  NOTE=plan-gate         SEVERITY=gate   (no ID)
  #   risk <ID>     EV=waiting  NOTE=risk-approval     SEVERITY=gate
  #   question <ID> EV=waiting  NOTE=builder-question  SEVERITY=gate
  #   done [ID]     EV=run-done NOTE=run-done          SEVERITY=done
  # Observe-only by contract: NEVER calls evt(), appends EVENTS.ndjson, takes the board mutex,
  # moves/edits a board file, or commits. No notify: configured → rc 0, silent.
  local kind="${1:-}" id="${2:-}" ev nt sev
  local u="usage: polaris notify-gate <plan | risk <ID> | question <ID> | done [ID]>"
  case "$kind" in
    plan)     ev="waiting"; nt="plan-gate"; sev="gate"; id="";;
    risk)     [ -n "$id" ] || die "$u"; ev="waiting"; nt="risk-approval"; sev="gate";;
    question) [ -n "$id" ] || die "$u"; ev="waiting"; nt="builder-question"; sev="gate";;
    done)     ev="run-done"; nt="run-done"; sev="done";;
    *)        die "$u";;
  esac
  notify_fire "$ev" "$id" "$nt" "$sev"
}

status_brief() { # `status --brief` — ONE plain-English paragraph, no table (ops/contracts/status-brief.md).
  # voice: standard, no jargon. Grep-stable markers, written VERBATIM: "Last landed:" and "Next up:".
  local done_c active_c review_c ready_c ids f b parts lead line2 newest ntitle top nextup n
  done_c=$(ls "$BOARD/done" 2>/dev/null | grep -c '\.md$' || true)
  active_c=$(ls "$BOARD/active" 2>/dev/null | grep -c '\.md$' || true)
  review_c=$(ls "$BOARD/review" 2>/dev/null | grep -c '\.md$' || true)
  ready_c=$(ls "$BOARD/ready" 2>/dev/null | grep -c '\.md$' || true)
  ids=""
  for f in "$BOARD/active/"*.md; do [ -e "$f" ] || break
    b="${f##*/}"; ids="${ids:+$ids, }${b%.md}"
  done
  # each ·-joined sub-clause is DROPPED when its count is 0 (nothing to say), never zero-padded
  parts=""
  [ "$done_c"   -gt 0 ] && parts="${parts:+$parts · }$done_c done"
  [ "$active_c" -gt 0 ] && parts="${parts:+$parts · }$active_c building${ids:+ ($ids)}"
  [ "$review_c" -gt 0 ] && parts="${parts:+$parts · }$review_c waiting to land"
  [ "$ready_c"  -gt 0 ] && parts="${parts:+$parts · }$ready_c queued"
  [ -n "$parts" ] || parts="Nothing building"
  n="$(sprint_hdr_num)"
  if [ -n "$n" ]; then lead="Sprint $n ($(sprint_goal "$n")):"; else lead="No sprint header —"; fi
  printf '%s %s.\n' "$lead" "$parts"
  # line two: newest done (highest-mtime file) + top-wsjf ready; each dropped when there is none
  line2=""
  newest="$(ls -t "$BOARD/done/"*.md 2>/dev/null | head -1)"
  if [ -n "$newest" ]; then
    ntitle="$(fm_get title "$newest")"
    line2="Last landed: ${ntitle:-$(basename "$newest" .md)}."
  fi
  top="$( { for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
      printf '%s\t%s\n' "$(fm_get wsjf "$f")" "$f"
    done; } | sort -rn | head -1 | cut -f2- )"
  if [ -n "$top" ]; then
    nextup="$(fm_get title "$top")"
    line2="${line2:+$line2 }Next up: ${nextup:-$(basename "$top" .md)}."
  fi
  [ -n "$line2" ] && printf '%s\n' "$line2"
  return 0
}

cmd_status() {
  board_pull   # T-148: under claim: claim-branch, origin's board first — the other machine's moves are the truth (first-run.md § 5)
  [ "${1:-}" = "--brief" ] && { status_brief; return; }
  local col n
  printf 'POLARIS board — base: %s · claim: %s\n' "$BASE" "$CLAIM_MODE"
  for col in backlog ready active review blocked done; do
    n=$(ls "$BOARD/$col" 2>/dev/null | grep -c '\.md$' || true)
    printf '  %-8s %s\n' "$col" "$n"
  done
  echo 'active:'
  local f id age
  for f in "$BOARD/active/"*.md; do
    [ -e "$f" ] || { echo '  (none)'; break; }
    id="${f##*/}"; id="${id%.md}"; age="$(lock_age "$id")"
    printf '  %s · %s · lock age %ss%s\n' "$id" "$(fm_get owner "$f")" "${age:-?}" \
      "$( [ -n "${age:-}" ] && [ "$age" -gt $((STALE_H*3600)) ] && echo " ⚠ STALE — polaris resume $id to take over, or release")"
  done
  echo 'ready (top by wsjf):'
  { for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
      id="${f##*/}"; id="${id%.md}"
      printf '%s\t%s · %spts · wsjf %s\n' "$(fm_get wsjf "$f")" "$id" \
        "$(fm_get points "$f")" "$(fm_get wsjf "$f")"
    done; } | sort -rn | cut -f2- | head -5
  # blocked tasks are owned by no role until drained — surface them WITH the reason so they stop
  # being invisible (Integrator regrooms or escalates them; see INTEGRATOR.md).
  local bf bid any=0
  for bf in "$BOARD/blocked/"*.md; do [ -e "$bf" ] || break
    [ "$any" -eq 0 ] && echo 'blocked (needs regroom/escalation):'
    any=1; bid="${bf##*/}"; bid="${bid%.md}"
    printf '  %s · %s\n' "$bid" "$(grep '⛔' "$bf" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*-*[[:space:]]*//' | grep . || echo 'no reason recorded — open the task')"
  done
  # SHARED CHECKOUT (ops/contracts/shared-checkout.md). A second chat's FIRST read is `status`, and
  # two things that change what it may do were invisible here: someone is mid-landing (the board
  # looks quiet while a land is in flight), and someone's uncommitted work is stashed rather than
  # gone. Both print ONLY when they exist — on a quiet repo this output is byte-identical to before,
  # which is the whole reason they are appended rather than folded into the table above.
  local lse lho lag
  lse="$LOCKS/.int-lease"
  if [ -d "$lse" ]; then
    lag="$(cat "$lse/epoch" 2>/dev/null | tr -d ' \r\n' || true)"
    case "$lag" in ''|*[!0-9]*) lag="$(date +%s)";; esac
    lho="$(cat "$lse/who" 2>/dev/null | tr -d '\r\n' || true)"
    printf 'integration lane: held by %s · %sm — a session is landing; wait for it, never steal\n' \
      "${lho:-unknown}" "$(( ( $(date +%s) - lag ) / 60 ))"
  fi
  # One line per park, newest first (ops/contracts/worktree-liveness.md § park): name · age · why.
  # The epoch is IN the stash name, so the age costs no extra git call, and the `why` a caller gave
  # `park` is what says whose interruption this was — a bare stash ref told a second chat nothing
  # about whether the dirt was minutes old or three days stale. The summary line above the list
  # keeps the remedy attached and stays the greppable "something is parked here" marker.
  # `git stash list` remains the source of truth: the human can act on stash@{N} directly.
  local pk pks pnm pwhy pep pn=0
  pks="$(git -C "$PRIMARY" stash list --format='%gs' 2>/dev/null | grep 'polaris/park-' || true)"
  [ -n "$pks" ] && pn="$(printf '%s\n' "$pks" | grep -c .)"
  if [ "$pn" -gt 0 ]; then
    printf 'parked: %s stash(es) — bash ops/polaris unpark restores the newest\n' "$pn"
    while IFS= read -r pk; do
      [ -n "$pk" ] || continue
      pnm="polaris/park-${pk#*polaris/park-}"
      case "$pnm" in *' — '*) pwhy="${pnm#* — }"; pnm="${pnm%% — *}";; *) pwhy="no reason recorded";; esac
      pep="${pnm#polaris/park-}"; pep="${pep%%-*}"
      case "$pep" in ''|*[!0-9]*) pep="$(date +%s)";; esac
      printf 'park: %s · %sm · %s\n' "$pnm" "$(( ( $(date +%s) - pep ) / 60 ))" "$pwhy"
    done <<EOF
$pks
EOF
  fi
}

cmd_board_fm() { # board-fm [<col>…] — ONE tab line per task: the frontmatter a Planner actually
  # carves against, and nothing else. Default = the LIVE columns; `done/` is history and is opt-in
  # (on a mature board it is ~98% of the bytes and answers no planning question). Replaces the
  # PLANNER's "read ops/board/** frontmatter", which has no command behind it today — so the agent
  # reads whole task files and pays for the prose body, which dwarfs the frontmatter ~4:1.
  # Non-task files (backlog/IDEAS.md) carry no frontmatter and are skipped.
  board_pull   # T-148: the board another machine moved, before a single row is read (first-run.md § 5)
  local cols="$*" col f id
  [ -n "$cols" ] || cols="ready active backlog blocked"
  for col in $cols; do
    [ -d "$BOARD/$col" ] || die "no such column: $col (backlog ready active review done blocked)"
  done
  printf 'col\tid\tpts\twsjf\trisk\tdeps\towns\tcontract\ttitle\n'
  for col in $cols; do
    for f in "$BOARD/$col/"*.md; do
      [ -e "$f" ] || break
      head -1 "$f" | tr -d '\r' | grep -q '^---$' || continue
      id="${f##*/}"; id="${id%.md}"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$col" "$id" \
        "$(fm_get points "$f")" "$(fm_get wsjf "$f")" "$(fm_get risk "$f")" \
        "$(fm_list depends_on "$f" | tr '\n' ',' | sed 's/,$//')" \
        "$(fm_list files_owned "$f" | tr '\n' ',' | sed 's/,$//')" \
        "$(fm_get contract "$f")" "$(fm_get title "$f")"
    done
  done
}

feat_tip_landed() { # feat_tip_landed <ID> — rc 0 iff a local feat/<ID> exists AND its tip is PROVEN
  # landed (ops/contracts/worktree-liveness.md § v2). Two proofs, in the order they actually happen:
  # TIP EQUALITY with the `Landed-from:` trailer of the task's landed squash commit — what `land`
  # writes, and the only proof that works for a squash, which is never an ancestor of $BASE — then
  # plain ancestry, the legacy proof for hand merges. Anything else is rc 1: a tip that moved past
  # the landing carries commits nobody has merged, and "the task is in done/" is evidence about the
  # TASK, never about the branch. That distinction is the whole gate — getting it wrong in the
  # permissive direction deletes work. Prints nothing; sets $FEAT_LANDED_SHA to the commit that
  # proved it (the rules_gate/$RULES_GATE shape) for callers that name the sha in a note.
  local id="$1" tip lsha lf
  FEAT_LANDED_SHA=""
  tip="$(git -C "$PRIMARY" rev-parse -q --verify "refs/heads/feat/$id" 2>/dev/null || true)"
  [ -n "$tip" ] || return 1
  lsha="$(fm_get landed "$BOARD/done/$id.md" 2>/dev/null || true)"
  [ -n "$lsha" ] || lsha="$(landed_sha "$id" 2>/dev/null || true)"
  if [ -n "$lsha" ]; then
    lf="$(git -C "$PRIMARY" log -1 --format=%B "$lsha" 2>/dev/null | sed -n 's/^Landed-from: *//p' | head -1 | tr -d ' \r' || true)"
    if [ -n "$lf" ] && [ "$lf" = "$tip" ]; then FEAT_LANDED_SHA="$lsha"; return 0; fi
  fi
  if git -C "$PRIMARY" merge-base --is-ancestor "$tip" "$BASE" 2>/dev/null; then
    FEAT_LANDED_SHA="$tip"; return 0
  fi
  return 1
}

cruft_clear() { # cruft_clear — delete every local feat/<ID> whose task is done AND whose tip
  # feat_tip_landed can PROVE landed, unless a lane is still standing in its worktree. Under
  # `landing: self` a lane leaves its own branch behind BY DESIGN (v1.2: never remove the ground you
  # are standing on), so that branch is not a finding, it is a lane mid-step — and reporting it as
  # cruft is what reddened `qa` after the suite, withheld the stamp, and made the next `finish`
  # re-run ~12 minutes of tests for a nit clearable in a second. So: the beat decides who is still
  # there, feat_tip_landed decides what is safe to delete, and this is the ONE mutation `qa` makes
  # besides the stamp — lossless by construction, because a branch only goes when its commits are
  # already in $BASE under another sha. Everything it skips, `drift` still reports.
  # rc 0 always; silent when nothing was cleared. Sets $CRUFT_CLEARED to the count.
  local r id rc refs
  CRUFT_CLEARED=0
  # ONE ref read for the whole pass, and the loop walks the BRANCHES — a handful — never done/,
  # which holds every task ever finished: that walk paid a `basename` fork per done task on every
  # qa while any feat/* existed at all (speed.md § 3). Refnames never hold whitespace or glob
  # characters (git check-ref-format), so the unquoted word split is exact.
  refs="$(git -C "$PRIMARY" for-each-ref --format='%(refname)' 'refs/heads/feat/*' 2>/dev/null || true)"
  [ -n "$refs" ] || return 0
  for r in $refs; do
    id="${r#refs/heads/feat/}"
    [ -f "$BOARD/done/$id.md" ] || continue
    feat_tip_landed "$id" || continue
    if [ -d "$GCD/worktrees/$id" ]; then
      if beat_live "$id"; then continue; fi            # a lane is still standing in it — not cruft yet
      rc=0; wt_remove "$id" sweep || rc=$?
      if [ "$rc" -eq 1 ]; then continue; fi            # LEFT — the branch it holds stays with it
    fi
    git -C "$PRIMARY" branch -D "feat/$id" >/dev/null 2>&1 || continue
    CRUFT_CLEARED=$((CRUFT_CLEARED+1))
    note "cleared: feat/$id (landed ${FEAT_LANDED_SHA:0:7})"
  done
  return 0
}

cmd_sweep() { # report orphans + stale locks + idle worktrees + >24h bg jobs/archives + remote
  # strays; --fix removes true orphans, reaps idle worktrees through wt_remove, rotates
  # finished/crashed stale jobs, prunes day-old runtime archives, and deletes merged strays
  local fix="${1:-}" d id found=0
  local la lpid lalive psl="" psgot=0
  for d in "$LOCKS"/*/; do
    [ -e "$d" ] || break
    id="${d%/}"; id="${id##*/}"; [ "$id" = ".board-mutex" ] && continue
    la="$(lock_age "$id")"
    if ! task_file "$id" active >/dev/null && ! task_file "$id" review >/dev/null; then
      found=1
      # A claim is not atomic end to end: the lock lands before the task file moves into active/,
      # so a lock younger than the mutex's own steal window is a claim IN FLIGHT, not an orphan.
      # Dropping it there hands the same task to a second session. Reported, so nothing is hidden —
      # never dropped, `--fix` included (ops/contracts/worktree-liveness.md § orphan-lock drop).
      if [ "$la" -lt 120 ]; then
        printf '⚠ ORPHAN lock: %s (age %ss — younger than 120s, left alone: a claim may be mid-flight)\n' "$id" "$la"
      else
        printf '⚠ ORPHAN lock: %s (age %sh, no active/review task)\n' "$id" "$(( la / 3600 ))"
        [ "$fix" = "--fix" ] && { lock_drop "$id"; note "removed"; }
      fi
    elif task_file "$id" active >/dev/null && [ "$la" -gt $((STALE_H*3600)) ]; then
      # Lock age says when the task was CLAIMED; it never said whether anyone is still working.
      # The beat says that, and meta line 5 says whether the session that took the lock is even on
      # the machine any more. A stale lock behind a live session is patience; a stale lock behind a
      # dead one is yours to take — and until now both printed the identical line.
      lpid="$(sed -n 5p "$d/meta" 2>/dev/null | tr -d ' \r')"
      lalive="session gone"
      case "$lpid" in
        ''|-|*[!0-9]*) : ;;
        *) # ONE `ps -W` for the whole sweep, and only once a stale lock actually names a pid: on
           # Windows an MSYS pid is invisible to `kill -0` across runtimes, so the PID column of a
           # ps listing is the only honest answer — and it costs ~0.4s, which is fine once per
           # sweep, absurd once per lock, and pure waste on the sweeps that find nothing stale.
           if [ "$psgot" -eq 0 ]; then
             psgot=1
             case "${OSTYPE:-}" in msys*|cygwin*) psl="$(ps -W 2>/dev/null || true)";; esac
           fi
           if [ -n "$psl" ]; then
             if printf '%s\n' "$psl" | awk -v p="$lpid" '$1==p{f=1} END{exit !f}'; then lalive="session alive"; fi
           elif kill -0 "$lpid" 2>/dev/null; then
             lalive="session alive"
           fi;;
      esac
      found=1; printf '⚠ STALE lock: %s (%ss > %sh) — take it over: polaris resume %s · or hand back: polaris release %s --to ready · last activity %sm ago · %s\n' \
        "$id" "$la" "$STALE_H" "$id" "$id" "$(( $(beat_age "$id") / 60 ))" "$lalive"
    fi
  done
  # WORKTREE PASS (ops/contracts/worktree-liveness.md § sweep lines). git's own registry is the
  # source of truth: a bare directory under .polaris/wt/ that git no longer knows about is not a
  # worktree, and `worktree list --porcelain` is the one read that never guesses. Liveness is the
  # BEAT and nothing else — a LIVE worktree is reported and LEFT, `--fix` included, because no
  # session may remove a worktree it cannot prove dead (a seal fan-out once did, and everything
  # uncommitted inside it died). An IDLE one goes through wt_remove, the ONE removal primitive,
  # which removes it clean and ARCHIVES it dirty. This pass is what finally makes `finish`'s
  # worktree caveat and `uninstall`'s "run sweep --fix" remedy TRUE.
  local wl wid wcol wage wrc
  while IFS= read -r wl; do
    case "$wl" in 'worktree '*) wl="${wl#worktree }";; *) continue;; esac
    wl="${wl%$'\r'}"; wl="${wl//\\//}"
    case "$wl" in */.polaris/wt/*) wid="${wl##*/.polaris/wt/}"; wid="${wid%%/*}";; *) continue;; esac
    [ -n "$wid" ] || continue
    wcol="$(task_col "$wid" 2>/dev/null || true)"; wcol="${wcol:-none}"
    wage="$(beat_age "$wid")"
    found=1
    if beat_live "$wid"; then
      note "LIVE worktree: .polaris/wt/$wid (beat ${wage}s ago) — left alone"
      continue
    fi
    if [ -n "$(git -C "$wl" status --porcelain 2>/dev/null)" ]; then
      printf '⚠ IDLE worktree: .polaris/wt/%s (task %s, beat %sm ago, dirty) — sweep --fix archives it\n' "$wid" "$wcol" "$(( wage / 60 ))"
    else
      printf '⚠ IDLE worktree: .polaris/wt/%s (task %s, beat %sm ago, clean) — sweep --fix removes it\n' "$wid" "$wcol" "$(( wage / 60 ))"
    fi
    if [ "$fix" = "--fix" ]; then
      wrc=0; wt_remove "$wid" sweep || wrc=$?
      # The local branch goes only with a worktree that actually LEFT (rc 0), and only for a task
      # the board already calls done — an active or review branch is live work whatever state its
      # worktree is in, and an archived one still has its commits to recover.
      if [ "$wrc" -eq 0 ] && [ -f "$BOARD/done/$wid.md" ]; then
        # ...and only with PROOF its tip is already in $BASE (worktree-liveness.md § v2): "done" is
        # a fact about the TASK, and a branch can still carry commits nobody ever merged.
        if feat_tip_landed "$wid"; then
          git -C "$PRIMARY" branch -D "feat/$wid" >/dev/null 2>&1 && note "branch feat/$wid deleted" || true
        else
          printf '⚠ feat/%s kept — tip not proven landed\n' "$wid"
        fi
      fi
    fi
  done <<EOF
$(git -C "$PRIMARY" worktree list --porcelain 2>/dev/null)
EOF
  # CRUFT BRANCHES (ops/contracts/worktree-liveness.md § v2). The pass above reaps WORKTREES; this
  # one reaps the branches a self-landing lane leaves behind once it has stepped out of its own
  # worktree — and only those whose tip feat_tip_landed can prove is already in $BASE. A diverged
  # tip is `drift`'s to report and nobody's to delete. `--fix` calls the same cruft_clear `qa`
  # calls, so there is exactly ONE implementation of "safe to delete" in the kit.
  # Walks the feat/* refs, never done/ (speed.md § 3) — the same shape as cruft_clear.
  local crefs cf cfid
  crefs="$(git -C "$PRIMARY" for-each-ref --format='%(refname)' 'refs/heads/feat/*' 2>/dev/null || true)"
  for cf in $crefs; do
    cfid="${cf#refs/heads/feat/}"
    [ -f "$BOARD/done/$cfid.md" ] || continue
    feat_tip_landed "$cfid" || continue
    if [ -d "$GCD/worktrees/$cfid" ] && beat_live "$cfid"; then continue; fi
    found=1
    printf '⚠ CRUFT: feat/%s — task done, tip proven landed, no live worktree — sweep --fix clears it\n' "$cfid"
  done
  [ "$fix" = "--fix" ] && cruft_clear
  # background jobs (ops/contracts/bg-jobs.md): a non-.prev job dir whose start is >24h old is
  # leftover runtime state. Always reported; --fix rotates it to <name>.prev (archive, never
  # delete) — but NEVER a still-running job: rotating a live job's dir out from under its runner
  # is destruction, not hygiene. `.prev` archives are never swept (ONE slot per name, no chains).
  local bgd bgn bgs bga bgp
  for bgd in "$PRIMARY/.polaris/bg"/*/; do
    [ -e "$bgd" ] || break
    bgn="${bgd%/}"; bgn="${bgn##*/}"
    case "$bgn" in *.prev) continue;; esac
    bgs="$(cat "$bgd/start" 2>/dev/null | tr -d ' \r\n')"
    case "$bgs" in ''|*[!0-9]*) bgs=0;; esac
    bga=$(( $(date +%s) - bgs ))
    [ "$bga" -gt 86400 ] || continue
    bgp="$(cat "$bgd/pid" 2>/dev/null | tr -d ' \r\n')"
    if [ ! -f "$bgd/rc" ] && bg_alive "$bgp"; then
      found=1; printf '⚠ STALE bg job: %s (%sh, pid %s still alive) — collect: bash ops/polaris bg wait %s (a live job is never auto-rotated)\n' \
        "$bgn" "$(( bga / 3600 ))" "$bgp" "$bgn"
    else
      found=1; printf '⚠ STALE bg job: %s (%sh old, finished or crashed) — bash ops/polaris sweep --fix rotates it to %s.prev\n' \
        "$bgn" "$(( bga / 3600 ))" "$bgn"
      [ "$fix" = "--fix" ] && { bg_rotate "$bgn"; note "rotated to $bgn.prev"; }
    fi
  done
  # RUNTIME ARCHIVES (ops/contracts/bg-jobs.md § v2 · ops/contracts/role-handover.md § state dir).
  # Rotation now ARCHIVES a finished job instead of deleting it, and every session that hops roles
  # leaves a handover state dir behind — both deliberate, both unbounded without a reaper. A day is
  # long enough that a human can still read yesterday's evidence and short enough that neither
  # grows forever. Reported first so a `--fix` is never a surprise. `.polaris/wt-archive/` is NOT
  # here on purpose: it holds uncommitted WORK, and only its owner deletes that.
  local ad an at now hd hn hf ht
  now="$(date +%s)"
  for ad in "$PRIMARY/.polaris/bg/.archive"/*/; do
    [ -e "$ad" ] || break
    an="${ad%/}"; an="${an##*/}"
    at="$(stat -c %Y "${ad%/}" 2>/dev/null || stat -f %m "${ad%/}" 2>/dev/null || echo 0)"
    case "$at" in ''|*[!0-9]*) at=0;; esac
    [ $(( now - at )) -gt 86400 ] || continue
    found=1; printf '⚠ STALE bg archive: .polaris/bg/.archive/%s (%sh old) — bash ops/polaris sweep --fix prunes it\n' "$an" "$(( ( now - at ) / 3600 ))"
    [ "$fix" = "--fix" ] && { rm -rf "$ad"; note "pruned"; }
  done
  for hd in "$PRIMARY/.polaris/handover"/*/; do
    [ -e "$hd" ] || break
    hn="${hd%/}"; hn="${hn##*/}"
    # NEWEST file, not the directory's own mtime: a state dir is written into for the whole life of
    # its session, and on some filesystems the dir mtime stops moving once the names stop changing.
    ht=0
    for hf in "$hd"*; do
      [ -e "$hf" ] || break
      at="$(stat -c %Y "$hf" 2>/dev/null || stat -f %m "$hf" 2>/dev/null || echo 0)"
      case "$at" in ''|*[!0-9]*) at=0;; esac
      [ "$at" -gt "$ht" ] && ht="$at"
    done
    [ $(( now - ht )) -gt 86400 ] || continue
    found=1; printf '⚠ STALE handover state: .polaris/handover/%s (%sh since its newest file) — bash ops/polaris sweep --fix prunes it\n' "$hn" "$(( ( now - ht ) / 3600 ))"
    [ "$fix" = "--fix" ] && { rm -rf "$hd"; note "pruned"; }
  done
  # remote hygiene: a landed task should have taken its feat/<ID> branch with it (done does this
  # since 5.11). This pass catches strays from before — or from any path that skipped `done`.
  # Only branches whose task is in done/ are touched; active/review branches are live work.
  if has_remote; then
    local rline rsha rref rid lsha lf itoday
    itoday="integrate/$(date +%F)"
    while IFS= read -r rline; do
      [ -n "$rline" ] || continue
      rsha="${rline%%$'\t'*}"; rref="${rline#*$'\t'}"
      case "$rref" in refs/heads/feat/*) rid="${rref#refs/heads/feat/}";; *) continue;; esac
      [ -f "$BOARD/done/$rid.md" ] || continue
      # deletable iff the remote tip is provably what we landed. Squash landings (polaris land)
      # are never ancestors of $BASE, so the proof is TIP EQUALITY with the squash commit's
      # Landed-from trailer; the ancestor check stays as the legacy proof for hand merges.
      lsha="$(fm_get landed "$BOARD/done/$rid.md" 2>/dev/null || true)"
      [ -n "$lsha" ] || lsha="$(landed_sha "$rid" || true)"
      lf=""
      [ -n "$lsha" ] && lf="$(git -C "$PRIMARY" log -1 --format=%B "$lsha" 2>/dev/null | sed -n 's/^Landed-from: *//p' | head -1 | tr -d ' \r' || true)"
      if [ -n "$lf" ] && [ "$rsha" = "$lf" ]; then
        found=1; printf '⚠ REMOTE stray: feat/%s — task done (landed %.7s), branch still on origin\n' "$rid" "$lsha"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/feat/$rid" && note "deleted"; }
      elif git -C "$PRIMARY" cat-file -e "$rsha" 2>/dev/null \
         && git -C "$PRIMARY" merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
        found=1; printf '⚠ REMOTE stray: feat/%s — task done, branch fully merged, still on origin\n' "$rid"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/feat/$rid" && note "deleted"; }
      else
        # Two lines, never `&&` — a human pastes this, and PowerShell has no chain operators.
        found=1; printf '⚠ REMOTE diverged: feat/%s — task done but the remote tip is NOT in %s (never auto-deleted). Inspect:\n     git fetch origin feat/%s\n     git log %s..FETCH_HEAD\n' \
          "$rid" "$BASE" "$rid" "$BASE"
      fi
    done <<EOF
$(git -C "$PRIMARY" ls-remote origin 'refs/heads/feat/*' 2>/dev/null)
EOF
    # integrate/<date> branches on origin: a wave whose merge is already in $BASE (tip an ancestor
    # of $BASE) is a stray — seal --sync deletes it in pr mode, but direct-mode seals never owned
    # the push and a skipped --sync leaves it forever. Merged → stray (--fix deletes); tip not in
    # $BASE → diverged, flagged but NEVER auto-deleted. Same style as the feat/* pass above.
    while IFS= read -r rline; do
      [ -n "$rline" ] || continue
      rsha="${rline%%$'\t'*}"; rref="${rline#*$'\t'}"
      case "$rref" in refs/heads/integrate/*) rid="${rref#refs/heads/}";; *) continue;; esac
      # TODAY's wave is never swept (ops/contracts/worktree-liveness.md § sweep lines). Under a
      # pipelined landing the branch is merged into $BASE after every task and reused for the next,
      # so "merged" proves only that the LAST land arrived — deleting it there pulls the branch out
      # from under an integrator that is still mid-wave.
      [ "$rid" = "$itoday" ] && continue
      if git -C "$PRIMARY" cat-file -e "$rsha" 2>/dev/null \
         && git -C "$PRIMARY" merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
        found=1; printf '⚠ REMOTE stray: %s — wave merged into %s, branch still on origin\n' "$rid" "$BASE"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/$rid" && note "deleted"; }
      else
        # Two lines, never `&&` — a human pastes this, and PowerShell has no chain operators.
        found=1; printf '⚠ REMOTE diverged: %s — tip is NOT in %s (never auto-deleted). Inspect:\n     git fetch origin %s\n     git log %s..FETCH_HEAD\n' \
          "$rid" "$BASE" "$rid" "$BASE"
      fi
    done <<EOF
$(git -C "$PRIMARY" ls-remote origin 'refs/heads/integrate/*' 2>/dev/null)
EOF
  fi
  if [ $found -eq 0 ]; then say "no orphan or stale locks, no remote strays"; fi
}

cmd_doctor() {
  local gv; gv="$(git --version | sed 's/[^0-9.]*\([0-9][0-9.]*\).*/\1/')"
  say "git $gv · primary: $PRIMARY · locks: $LOCKS"
  awk -v v="$gv" 'BEGIN{split(v,a,"."); exit !(a[1]>2 || (a[1]==2 && a[2]>=5))}' \
    || die "git >= 2.5 required for worktrees"
  # `park` is `git stash push --include-untracked -m <name>`, and `stash push` landed in git 2.13
  # (the old `stash save` cannot take untracked files AND a name). Below that the shared checkout's
  # "a dirty tree is parked, never asked about" promise silently degrades to the old dirty-tree die.
  # A warn, not a die: everything else in POLARIS still works on 2.5.
  awk -v v="$gv" 'BEGIN{split(v,a,"."); exit !(a[1]>2 || (a[1]==2 && a[2]>=13))}' \
    || note "⚠ git $gv predates 2.13 — 'git stash push' is missing, so park/unpark cannot run and a dirty shared checkout falls back to a die. Upgrade git."
  git -C "$PRIMARY" show-ref --verify -q "refs/heads/$BASE" || note "⚠ base branch '$BASE' not found — set base: in CONVENTIONS.md"
  board_materialize || true   # fresh clone: ops/board/ missing + polaris/board present → rebuild it
  # CONVENTIONS.md is written by INIT and by nothing else — its absence is THE test for
  # "INIT never ran here". install.sh, CLAUDE.md's role dispatch and INIT.md all use this
  # same file for that question. Never ops/board/: an older installer shipped it empty.
  if [ -f "$CONV" ]; then
    # `update` never rewrites CONVENTIONS.md, so a pre-5.2 board has no voice: line — print the
    # effective value either way, or the knob is undiscoverable for exactly the repos that want it.
    note "voice: $(cfg voice standard) — how agents talk to you (standard | technical; set in CONVENTIONS.md)"
  else
    note "⚠ ops/CONVENTIONS.md missing — INIT has not run in this repo. Say: \"You are INIT.\" (no new session needed)"
  fi
  # CONFIG DRIFT (ops/contracts/key-registry.md § 2). `update` refreshes kit code and deliberately
  # never rewrites CONVENTIONS.md — that is what makes updating safe — but nothing compared an
  # installed config against the kit's feature set, so every capability gated on a NEW key shipped
  # DORMANT and no line ever said so. Measured: a repo running byte-identical 5.24.0 code against a
  # CONVENTIONS.md missing 19 keys, called healthy by every command. This is the CLAUDE.md `[kit
  # X.Y.Z]` stamp lesson (:429 below) applied to the config surface, and it keeps that check's tone:
  # ONE line naming the count and the remedy, never a warning storm.
  # A commented `# key:` stub counts as PRESENT — "known here and deliberately unset" — which is how
  # `polaris adopt` silences this line without changing one behavior. Silent when `ops/KEYS.tsv` is
  # absent (a pre-6.0 installed copy; the next update ships it) and when CONVENTIONS.md is absent
  # (INIT never ran — the line above already says the one useful thing, and "lacks 37 of 37" on top
  # of it is the storm this check exists to avoid).
  # NEVER name a kit version in the line: it is goldened, and a version number reds it every release.
  if [ -f "$OPS/KEYS.tsv" ] && [ -f "$CONV" ]; then
    local drift
    drift="$(awk '
      FNR==NR {                                  # pass 1: CONVENTIONS.md → every key known HERE
        s=$0; sub(/\r$/,"",s)
        if (substr(s,1,1)=="#") sub(/^#[ \t]*/,"",s)  # a `# key:` stub reads exactly like a live key
        i=index(s,":"); if (i>1) present[substr(s,1,i-1)]=1
        next
      }
      { s=$0; sub(/\r$/,"",s)                    # pass 2: the registry, IN ORDER — the line names
        if (s ~ /^#/ || s ~ /^[ \t]*$/) next     # the first six absent keys as KEYS.tsv lists them
        k=s; sub(/\t.*$/,"",k); if (k=="") next
        m++
        if (!(k in present)) { n++; if (n<=6) list = (n==1 ? k : list " · " k) }
      }
      END { if (n>0) printf "⚠ CONVENTIONS.md lacks %d of %d known keys (%s%s) — see what each unlocks: ops/polaris adopt\n", n, m, list, (n>6 ? " +" (n-6) " more" : "") }
    ' "$CONV" "$OPS/KEYS.tsv")"
    [ -n "$drift" ] && note "$drift"
  fi
  # ACTIVATION NUDGE (ops/contracts/test-surfaces.md v2 § 15). 6.4.0 shipped change-scoped
  # selection to every installed repo and, by design, changed nothing: an empty ops/SURFACES.tsv
  # runs the whole suite on every change, exactly as before, and no line said so. This is the ONE
  # doctor line that does — gated on a runner the scaffold can actually scope (surfaces_runner over
  # the tracked list; THIS repo, bash + drills, answers NORUNNER and stays silent) AND on a map with
  # no rows, so a repo the scaffold cannot help is never nagged and a repo that mapped its surfaces
  # never hears it again. The cheap tests run first; the ls-files fork only when they all pass.
  if [ -f "$CONV" ] && [ -n "$(cfg test "")" ] && ! surfaces_lines | grep -q .; then
    local sls; sls="$(mktemp)"
    git -C "$PRIMARY" ls-files > "$sls" 2>/dev/null || true
    surfaces_runner "$sls" >/dev/null 2>&1 \
      && note "surfaces: none mapped — every change runs the whole test: suite; propose a map: ops/polaris surfaces --scaffold"
    rm -f "$sls"
  fi
  # The preferences a repo cannot derive (ops/contracts/first-run.md § 2): the same line `update`
  # prints, rendered from interview_pending's answer. Guarded by `command -v` because the interview
  # (admin.sh) and this line land in the same wave — before the wave gate the fn may not exist yet.
  if [ -f "$CONV" ] && command -v interview_pending >/dev/null 2>&1; then
    local ipend
    ipend="$(interview_pending)" && note "preferences never set here: $ipend — one round of questions: ops/polaris interview"
  fi
  # THE BAR, STILL BLANK (ops/contracts/visual-check.md § v3.16). `heal` installs `ops/DESIGN.md`
  # into every repo, but `heal` cannot interview — so the one section that names THIS product is
  # still the template's empty slot, and this line is the only thing that ever says so.
  # ALL THREE, or silence: the file is here · the sentinel is still in it · the repo has a `visual:`
  # surface at all. A repo with no screens has no screen to hold to a bar and must never be nagged
  # about one — absent-by-default, and the same anti-warning-storm discipline as the config-drift and
  # surfaces-activation lines above. NO new CONVENTIONS key: `visual:` already answers "does this
  # repo have screens", and a second knob for the same question is exactly the drift to avoid.
  # NEVER name a kit version in the line — doctor's output is goldened, and a version reds it every
  # release. The remedy is in the owner's terms, never a file-format instruction.
  if [ -f "$OPS/DESIGN.md" ] && [ -n "$(cfg visual "")" ] \
     && grep -qF '_(unfilled' "$OPS/DESIGN.md" 2>/dev/null; then
    note "ops/DESIGN.md is installed but nobody has said what THIS product should look like — write one sentence there, in your own words, on the look and feel you want; every screen gets held to it"
  fi
  # v6.0 autonomy knobs (ops/contracts/hands-free-knobs.md § v2). The 5.13 knobs shipped OFF and
  # stayed off in exactly the repos that never learned they existed, so 6.0 INVERTS the fallbacks
  # here, in kit code — the one mechanism `update` already refreshes in every installed repo — and
  # writes into nobody's CONVENTIONS.md. Unset now composes the trusted values; `autonomy: standard`
  # is the one-line opt-out restoring confirm/ask/confirm, and `autonomy: trusted` stays legal and
  # equals the default. Precedence itself is unchanged: explicit knob > autonomy > default, in both
  # directions. Unknown values fail SAFE — each behaves as that knob's STANDARD value, NOT as the
  # now-autonomous default, because a typo must never grant autonomy. The composition prints
  # whenever CONVENTIONS.md exists: printing it only when a knob was already set guaranteed that the
  # repos most needing the message were the ones certain never to see it. `autonomy` composes only
  # the three gate knobs — never drain, which keeps its own silence-when-unset.
  if [ -f "$CONV" ]; then
    local a pg bq ea dr ds std=0
    a="$(cfg autonomy "")"; pg="$(cfg plan_gate "")"; bq="$(cfg builder_questions "")"
    ea="$(cfg evolve_apply "")"; dr="$(cfg drain "")"; ds="$(cfg drain_slices "")"
    if [ "$a" = "standard" ]; then std=1
    elif [ -n "$a" ] && [ "$a" != "trusted" ]; then
      note "⚠ autonomy: '$a' unknown (standard | trusted) — behaving as standard"; a="standard"; std=1
    fi
    if [ -n "$pg" ] && [ "$pg" != "confirm" ] && [ "$pg" != "auto" ]; then
      note "⚠ plan_gate: '$pg' unknown (confirm | auto) — behaving as confirm"; pg="confirm"
    fi
    if [ -z "$pg" ]; then if [ "$std" -eq 1 ]; then pg="confirm"; else pg="auto"; fi; fi
    if [ -n "$bq" ] && [ "$bq" != "ask" ] && [ "$bq" != "default-safe" ]; then
      note "⚠ builder_questions: '$bq' unknown (ask | default-safe) — behaving as ask"; bq="ask"
    fi
    if [ -z "$bq" ]; then if [ "$std" -eq 1 ]; then bq="ask"; else bq="default-safe"; fi; fi
    if [ -n "$ea" ] && [ "$ea" != "confirm" ] && [ "$ea" != "auto-reversible" ]; then
      note "⚠ evolve_apply: '$ea' unknown (confirm | auto-reversible) — behaving as confirm"; ea="confirm"
    fi
    if [ -z "$ea" ]; then if [ "$std" -eq 1 ]; then ea="confirm"; else ea="auto-reversible"; fi; fi
    note "autonomy: ${a:-default} → plan_gate=$pg · builder_questions=$bq · evolve_apply=$ea (explicit > autonomy > default · opt out: autonomy: standard)"
    if [ -n "$dr$ds" ]; then
      if [ -n "$dr" ] && [ "$dr" != "queue" ] && [ "$dr" != "plan" ] && [ "$dr" != "backlog" ]; then
        note "⚠ drain: '$dr' unknown (queue | plan | backlog) — behaving as the default"; dr=""
      fi
      case "$ds" in *[!0-9]*) note "⚠ drain_slices: '$ds' not a number — behaving as 2"; ds="";; esac
      note "drain: ${dr:-plan} · drain_slices: ${ds:-2} (autonomy never composes drain)"
    fi
  fi
  # The two shared-checkout knobs (ops/contracts/shared-checkout.md). They are NOT composed by
  # autonomy: — they are minutes, and a typo in either changes how long a session waits for the
  # integration lane or how old a lease must be before it is STOLEN, on a path where the wrong
  # answer is silent. int_on fails closed to the default, so the ⚠ names what will actually happen
  # rather than what was asked for. Unset = default = silence: a warning that fires when nothing is
  # wrong is a warning people learn to scroll past.
  local iwm ism
  iwm="$(cfg integration_wait_minutes "")"
  ism="$(cfg integration_stale_minutes "")"
  if [ -n "$iwm" ]; then
    case "$iwm" in
      *[!0-9]*) note "⚠ integration_wait_minutes: '$iwm' is not a whole number of minutes — the integration lane will use the default (10)";;
      0)        note "⚠ integration_wait_minutes: 0 — the lane will never wait; a busy lane returns 'queued:' on the first look";;
    esac
  fi
  if [ -n "$ism" ]; then
    case "$ism" in
      *[!0-9]*) note "⚠ integration_stale_minutes: '$ism' is not a whole number of minutes — the integration lane will use the default (45)";;
      0)        note "⚠ integration_stale_minutes: 0 — every held lease counts as abandoned and is stolen on sight; two sessions can then land at once";;
    esac
  fi
  mkdir -p "$LOCKS" && [ -w "$LOCKS" ] || die "lock dir not writable: $LOCKS"
  case "$(git -C "$PRIMARY" remote get-url origin 2>/dev/null)" in .*|../*) note "⚠ origin is a RELATIVE path — breaks in worktrees; use an absolute URL";; esac
  case "$CLAIM_MODE" in local-lock|claim-branch) :;; *) die "claim: must be local-lock or claim-branch";; esac
  [ "$CLAIM_MODE" = "claim-branch" ] && ! has_remote && note "⚠ claim-branch set but no origin remote"
  # base-push-rejected stamp (ops/contracts/publish-modes.md): a direct-mode seal that keeps hitting
  # a protected $BASE records each rejection; >=2 → recommend publish: pr. No stamp / <2 → silent.
  local bprc=0
  [ -f "$PRIMARY/.polaris/base-push-rejected" ] && bprc="$(awk 'NR==1{print $2+0}' "$PRIMARY/.polaris/base-push-rejected" 2>/dev/null)"
  [ "${bprc:-0}" -ge 2 ] && note "⚠ origin keeps rejecting pushes to $BASE — protected branch? set publish: pr in ops/CONVENTIONS.md"
  [ -f "$EVENTS" ] && ! grep -q 'EVENTS\.ndjson merge=union' "$PRIMARY/.gitattributes" 2>/dev/null \
    && note "⚠ EVENTS.ndjson exists without its union-merge gitattribute — run: ops/polaris upgrade"
  # `ver` exits 0 with empty output when a key is absent, so || can't catch it — grep can.
  # The kit repo's own VERSION is unstamped on purpose: pack.py stamps the emitted copy.
  [ -f "$VER" ] && note "POLARIS v$(ver version) ($(ver commit | grep . || echo unstamped))"
  # Self-hosting repo only (kit/ops/pack.py is the tell — ops/contracts/self-hosting.md): the one
  # skew that matters here is kit/ops/VERSION ahead of ops/VERSION — a release built but never
  # run, while the channel keeps serving the old kit. CI catches it daily; this shows the human.
  if [ -f "$PRIMARY/kit/ops/pack.py" ]; then
    local kv iv
    kv="$(ver version "$PRIMARY/kit/ops/VERSION" 2>/dev/null || true)"
    iv="$(ver version 2>/dev/null || true)"
    if [ -n "$kv" ] && [ "$kv" = "$iv" ]; then
      say "self-hosting: kit $kv = installed $iv — this repo runs the POLARIS it ships"
    else
      note "⚠ self-hosting: kit/ops/VERSION is ${kv:-missing} but ops/ runs ${iv:-unknown} — that release has NOT been dogfooded. Run: python kit/ops/pack.py --dogfood"
    fi
  fi
  # Self-hosting repo only (kit/ops/pack.py is the tell — ops/contracts/self-hosting.md): the
  # shipped zip going stale is exactly how the last one rotted. Was gated on $OPS/pack.py
  # (ops/pack.py) — a pre-split path that no longer exists post kit/ split, so this warning could
  # never fire. Gate on the same tell every other self-hosting check uses.
  if [ -f "$PRIMARY/kit/ops/pack.py" ] && [ -f "$PRIMARY/polaris-v5.zip" ] && command -v unzip >/dev/null 2>&1; then
    local zsha head
    zsha="$(unzip -p "$PRIMARY/polaris-v5.zip" polaris-v5/ops/VERSION 2>/dev/null | sed -n 's/^commit: *//p' | head -1 || true)"
    head="$(git -C "$PRIMARY" rev-parse --short HEAD 2>/dev/null || true)"
    [ -n "$zsha" ] && [ "$zsha" != "$head" ] \
      && note "⚠ polaris-v5.zip is STALE (built at $zsha, HEAD is $head) — rebuild: python kit/ops/pack.py"
  fi
  # commit-msg hook: the no-AI-fingerprints guarantee (ops/hooks/commit-msg). Self-heal here
  # because clones never carry .git/hooks — without this, every fresh clone silently loses it.
  if [ -f "$OPS/hooks/commit-msg" ]; then
    if [ -n "$(git -C "$PRIMARY" config --get core.hooksPath 2>/dev/null || true)" ]; then
      note "⚠ core.hooksPath is set — wire ops/hooks/commit-msg into your hooks dir by hand (it strips AI attribution from commits)"
    else
      local hk="$GCD/hooks/commit-msg"
      if [ ! -f "$hk" ]; then
        mkdir -p "$GCD/hooks"; cp "$OPS/hooks/commit-msg" "$hk"; chmod +x "$hk" 2>/dev/null || true
        say "commit-msg hook installed — AI attribution is stripped from every commit"
      elif grep -q 'POLARIS commit-msg' "$hk" 2>/dev/null; then
        cp "$OPS/hooks/commit-msg" "$hk"; chmod +x "$hk" 2>/dev/null || true
      else
        note "⚠ a non-POLARIS commit-msg hook is installed — chain ops/hooks/commit-msg into it by hand"
      fi
    fi
  fi
  # brain freshness (ops/contracts/brain.md): board-changed newer than the brain's stamp → the
  # digest lies. No brain dir → the feature was never opted into → stay silent.
  # Brain freshness (ops/contracts/brain.md). Two changes over the warn-only version:
  #   1. It checks the CODE too. The old test compared only .polaris/board-changed against the
  #      stamp, so a brain could be four releases behind with a clean board and doctor said nothing
  #      — which is exactly the state this repo was found in on 2026-07-25 (stamp df0df1d, HEAD
  #      9daab03), while every role file instructs agents to read that brain FIRST.
  #   2. It REFRESHES instead of advising. A warning an agent has to act on is a warning an agent
  #      pays tokens to act on, and a stale brain is worse than no brain: it answers confidently
  #      and wrongly. `--refresh` skips code-map when the code is unchanged, so the warm cost is small.
  if [ -d "$PRIMARY/.polaris/brain" ]; then
    local bstale=0 bsha bhead
    [ "$PRIMARY/.polaris/board-changed" -nt "$PRIMARY/.polaris/brain/.stamp" ] && bstale=1
    bsha="$(cut -d' ' -f2 < "$PRIMARY/.polaris/brain/.stamp" 2>/dev/null | tr -d ' \r\n' || true)"
    bhead="$(git -C "$PRIMARY" rev-parse --short "$BASE" 2>/dev/null || true)"
    [ -n "$bsha" ] && [ -n "$bhead" ] && [ "$bsha" != "$bhead" ] && bstale=1
    if [ "$bstale" = 1 ]; then
      if ( cmd_brain --refresh ) >/dev/null 2>&1; then
        say "brain was stale — refreshed (was ${bsha:-?}, now ${bhead:-?})"
      else
        note "⚠ brain is stale and could not be refreshed — run: ops/polaris brain --refresh"
      fi
    fi
  fi
  # Read-only auto-approver (ops/hooks/readonly-allow.sh). Without it every grep/sed/git-log an
  # agent runs through Bash stops and asks a human — which is what made plan mode expensive. It is
  # plumbing spread over three files, so it can be half-installed and look fine; check all three.
  local rah="$OPS/hooks/readonly-allow.sh" psj="$PRIMARY/.claude/settings.json"
  if [ ! -f "$rah" ]; then
    note "⚠ ops/hooks/readonly-allow.sh is missing — reads through Bash will prompt. Re-run: bash ops/install.sh"
  elif [ ! -f "$psj" ]; then
    note "⚠ .claude/settings.json is missing — the read-only auto-approver is not wired. Re-run: bash ops/install.sh"
  elif ! grep -q 'readonly-allow.sh' "$psj" 2>/dev/null; then
    note "⚠ .claude/settings.json does not wire readonly-allow.sh — reads through Bash will prompt. Re-run: bash ops/install.sh"
  fi
  # Auto mode lives in the USER's settings, not the repo's, so a new machine starts prompting again
  # even in a repo that is wired correctly. `ops/polaris update` arms it (admin.sh::refresh_machine_kit).
  if [ -f "$HOME/.claude/settings.json" ] \
     && ! grep -q '"useAutoModeDuringPlan"' "$HOME/.claude/settings.json" 2>/dev/null; then
    note "⚠ ~/.claude/settings.json has no auto-mode keys — plan mode will prompt. Arm this machine: ops/polaris update"
  fi
  # The output style is what binds the MAIN conversation's voice and its closing 🎉 — the layer
  # CLAUDE.md cannot supply. Three ways to be half-installed, and all three look identical from the
  # inside: the session simply has no discipline and nobody can tell why.
  local osf="$PRIMARY/.claude/output-styles/polaris.md" osl="$PRIMARY/.claude/settings.local.json"
  if [ ! -f "$osf" ]; then
    note "⚠ .claude/output-styles/polaris.md is missing — this session's output discipline is not installed. Re-run: bash ops/install.sh ."
  elif ! grep -q 'keep-coding-instructions: *true' "$osf" 2>/dev/null; then
    note "⚠ .claude/output-styles/polaris.md lost 'keep-coding-instructions: true' — a style without it EXCLUDES Claude Code's built-in coding instructions. Re-run: bash ops/install.sh ."
  elif [ -f "$osl" ] && grep -q '"outputStyle"' "$osl" 2>/dev/null \
       && ! grep -q '"outputStyle"[[:space:]]*:[[:space:]]*"polaris"' "$osl" 2>/dev/null; then
    note "⚠ .claude/settings.local.json selects a different outputStyle — it OUTRANKS settings.json, so POLARIS's is not active here. That is yours to choose; remove the key to get it back."
  elif [ -f "$psj" ] && ! grep -q '"outputStyle"' "$psj" 2>/dev/null; then
    note "⚠ .claude/settings.json does not select the POLARIS output style — re-run: bash ops/install.sh ."
  fi
  # Does the protocol every session READS match the kit this repo claims to run? Nothing compared
  # those two until 5.23.0, so a repo could sit on 5.22.0 while injecting a CLAUDE.md three weeks
  # old — and every command, doctor included, called it healthy. install.sh stamps `[kit X.Y.Z]`
  # into the BEGIN marker so the block states its own provenance; one grep closes the gap.
  # Unstamped + a 5.23.0-or-later kit is conclusive, not a guess: 5.23.0+ always stamps.
  local cmf="$PRIMARY/CLAUDE.md" cmv iv
  iv="$(ver version 2>/dev/null || true)"
  if [ ! -f "$cmf" ] || ! grep -qF '<!-- POLARIS:BEGIN' "$cmf" 2>/dev/null; then
    if [ -f "$cmf" ] && grep -qF "POLARIS v5 — Parallel Sprint Protocol" "$cmf" 2>/dev/null; then
      note "⚠ CLAUDE.md carries POLARIS with NO managed markers — frozen at install time while this kit reports ${iv:-unknown}."
      note "  Every session here is reading that stale protocol. Heal it in place: ops/polaris update"
    elif [ -f "$OPS/CONVENTIONS.md" ]; then
      note "⚠ CLAUDE.md has no managed POLARIS block — sessions here get no protocol at all. Re-run: bash ops/install.sh ."
    fi
  else
    cmv="$(sed -n 's/.*\[kit \([0-9][0-9.]*\)\].*/\1/p' "$cmf" | head -1)"
    if [ -z "$cmv" ]; then
      note "⚠ the managed CLAUDE.md block predates version stamping (pre-5.23.0) while this kit is ${iv:-unknown} — it may be several releases behind. Refresh it: ops/polaris update"
    elif [ -n "$iv" ] && [ "$cmv" != "$iv" ]; then
      note "⚠ ops/VERSION says $iv but the managed CLAUDE.md block is $cmv — the protocol injected into every session is NOT the kit you are running. Fix: ops/polaris update"
    fi
  fi
  # KEEP-AWAKE (ops/contracts/keep-awake.md § installers and doctor). The daemon is MACHINE-level —
  # its hooks live in ~/.claude/settings.json and its registry beside them — so a repo can be
  # perfectly healthy while the box still sleeps mid-run, and nothing said so. Two states are worth
  # a line: never armed, and armed but switched off. Both are silent otherwise, and the whole check
  # is gated on ~/.claude existing so CI and a bare shell never see a word about it.
  if [ -d "$HOME/.claude" ]; then
    local awn awh
    awn="$(grep -o 'polaris/awake-hook\.sh' "$HOME/.claude/settings.json" 2>/dev/null | grep -c . || true)"
    case "$awn" in ''|*[!0-9]*) awn=0;; esac
    awh="${POLARIS_AWAKE_HOME:-$HOME/.claude/polaris/awake}"
    if [ "$awn" -lt 4 ]; then
      note "⚠ keep-awake not armed on this machine — ops/polaris awake install"
    elif [ -e "$awh/disabled" ]; then
      note "⚠ keep-awake is DISABLED (ops/polaris awake enable)"
    fi
  fi
  # THE SKILLS SHELF (ops/contracts/self-skills.md § 7). Both lines are the module's OWN verdicts,
  # never a second opinion computed here: `skill_budget` is rc 1 exactly when the tier-1 shelf is
  # over 1,600 B, and `skill_prune` is rc 1 exactly when a demotion or an archive is due. Their
  # stdout is captured, not printed — doctor says the one useful sentence, `ops/polaris skill` says
  # the rest. Silent otherwise, and a repo that never ran `skill propose` has no POLARIS-written
  # skills at all, so it never hears a word and doctor's goldens stay byte-identical. `command -v`
  # because an older installed lib/ predates skills.sh and a health check must never die of a
  # module it was shipped without.
  if command -v skill_budget >/dev/null 2>&1; then
    local skb skp skn
    if ! skb="$(skill_budget 2>/dev/null)"; then
      skb="$(printf '%s\n' "$skb" | grep '^⛔' || true)"
      [ -z "$skb" ] || note "$skb"
    fi
    if ! skp="$(skill_prune 2>/dev/null)"; then
      skn="$(printf '%s\n' "$skp" | grep -cE '^(demote|archive) ' || true)"
      note "⚠ $skn skill(s) due for eviction — ops/polaris skill prune"
    fi
  fi
  say "doctor: OK"
  # --fast (ops/contracts/fast-tier.md): the in-process tier — selftest_fast in lib/selftest/fast.sh,
  # read as $1 exactly like --selftest below. It combines with NOTHING: an extra arg is a die, not a
  # silent ignore, because "--fast --only x" is someone expecting a drill subset this tier cannot run.
  if [ "${1:-}" = "--fast" ]; then
    [ $# -eq 1 ] || die "doctor --fast takes no options"
    if selftest_fast; then return 0; else return 1; fi
  fi
  # --selftest [--only <patterns>] [--parallel <N>] (ops/contracts/verification-tiering.md +
  # ops/contracts/selftest-sharding.md): --only runs the always-on spine + just the labeled drills
  # matching ANY comma-separated shell glob; --parallel shards the selected labels into N child
  # re-invocations. First occurrence of each flag wins; other trailing args stay ignored, exactly
  # as the pre-split parser (which never read past $3) ignored them.
  if [ "${1:-}" = "--selftest" ]; then
    local _only="" _par="" _a
    shift
    case "${1:-}" in
      ""|--only|--only=*|--parallel|--parallel=*) : ;;
      *) die "doctor --selftest: unknown option '$1' (only --only <pattern>)";;
    esac
    while [ $# -gt 0 ]; do
      _a="$1"; shift
      case "$_a" in
        --only)   if [ -z "$_only" ]; then _only="${1:-}"; [ -n "$_only" ] || die "doctor --selftest --only needs a pattern"; shift; fi;;
        --only=*) if [ -z "$_only" ]; then _only="${_a#--only=}"; [ -n "$_only" ] || die "doctor --selftest --only needs a pattern"; fi;;
        --parallel)   if [ -z "$_par" ]; then _par="${1:-}"; case "$_par" in ''|*[!0-9]*) die "--parallel needs an integer >= 2";; esac; [ "$_par" -ge 2 ] || die "--parallel needs an integer >= 2"; shift; fi;;
        --parallel=*) if [ -z "$_par" ]; then _par="${_a#--parallel=}"; case "$_par" in ''|*[!0-9]*) die "--parallel needs an integer >= 2";; esac; [ "$_par" -ge 2 ] || die "--parallel needs an integer >= 2"; fi;;
        *) : ;;
      esac
    done
    selftest "$_only" "$_par"
  fi
}

cmd_metrics() { # cycle time + throughput + kickbacks from EVENTS.ndjson — pure awk
  if [ ! -s "$EVENTS" ]; then
    note "no telemetry yet (EVENTS.ndjson empty) — runs accumulate it"
    metrics_depth_lines
    return 0
  fi
  awk -v now="$(date +%s)" '
    function get(k,   m){ m=""; if (match($0, "\""k"\":\"[^\"]*\"")) { m=substr($0,RSTART,RLENGTH); sub("\""k"\":\"","",m); sub("\"$","",m) } return m }
    function num(k,   m){ m=""; if (match($0, "\""k"\":[0-9]+"))     { m=substr($0,RSTART,RLENGTH); sub("\""k"\":","",m) } return m+0 }
    { ts=num("ts"); ev=get("ev"); id=get("id")
      if (ev=="claim"    && !(id in claimed)) { claimed[id]=ts; if (match($0,/"pts":[0-9.]+/)) { m=substr($0,RSTART+6,RLENGTH-6); cpts[id]=m+0 } }
      if (ev=="handoff" && !(id in ho)) ho[id]=ts
      if (ev=="kickback") { kb[id]++; kbt++ ; if (now-ts<7*86400) kb7++ }
      if (ev=="done")    { done[id]=ts; dn++; if (now-ts<7*86400) dn7++ }
    }
    END{
      n=0; for (id in done) if (id in claimed) { c[n++]=done[id]-claimed[id] }
      # insertion sort (tiny n) for p50
      for(i=1;i<n;i++){v=c[i];j=i-1;while(j>=0&&c[j]>v){c[j+1]=c[j];j--}c[j+1]=v}
      # T-032 plain-English summary FIRST, above the byte-identical table — same numbers it computes
      bsum=0; bcnt=0; for (id in ho) if (id in claimed) { bsum+=ho[id]-claimed[id]; bcnt++ }
      isum=0; icnt=0; for (id in done) if (id in ho) { isum+=done[id]-ho[id]; icnt++ }
      p50h = (n>0) ? c[int((n-1)/2)]/3600 : 0
      printf "In plain English: %d tasks done, a typical task takes %.1fh door to door; building averages %.1fh, landing %.1fh; %d bounced.\n", dn+0, p50h, (bcnt?bsum/bcnt/3600:0), (icnt?isum/icnt/3600:0), kbt+0
      printf "done total: %d   done 7d: %d   kickbacks total: %d (7d: %d)\n", dn+0, dn7+0, kbt+0, kb7+0
      if (n>0) { s=0; for(i=0;i<n;i++) s+=c[i]
        printf "cycle claim→done  avg: %.1fh   p50: %.1fh   n=%d\n", s/n/3600, c[int((n-1)/2)]/3600, n }
      # v5 calibration: cycle p50 per point bucket (only for claims that logged pts)
      for (id in done) if (id in claimed && id in cpts) { b=cpts[id]; bc[b, nb[b]++]=done[id]-claimed[id] }
      line=""
      for (b=1; b<=13; b++) if (nb[b]>0) {
        for(i=1;i<nb[b];i++){v=bc[b,i];j=i-1;while(j>=0&&bc[b,j]>v){bc[b,j+1]=bc[b,j];j--}bc[b,j+1]=v}
        line=line sprintf("%s%gpt p50 %.1fh n=%d", (line==""?"":"  ·  "), b, bc[b,int((nb[b]-1)/2)]/3600, nb[b])
      }
      if (line!="") printf "by points (Planner: point UP any bucket whose p50 dwarfs its size)\n  %s\n", line
      if (kbt+0>0 && dn+0>0) printf "kickback rate: %.0f%%  (Planner: read this before pointing)\n", 100*kbt/dn
      # v5.8: where does cycle time go? build (claim→handoff) vs integration wait (handoff→done).
      bs=0; bn=0; for (id in ho) if (id in claimed) { bs+=ho[id]-claimed[id]; bn++ }
      is=0; iN=0; for (id in done) if (id in ho) { is+=done[id]-ho[id]; iN++ }
      if (bn>0 || iN>0) printf "split  build(claim→handoff) avg: %.1fh n=%d   ·   integrate(handoff→done) avg: %.1fh n=%d\n", (bn?bs/bn/3600:0), bn, (iN?is/iN/3600:0), iN
      # oldest task still awaiting integration (handoff logged, no done yet) — is the Integrator behind?
      oldest=0; oid=""; for (id in ho) if (!(id in done)) { dd=now-ho[id]; if (dd>oldest){oldest=dd; oid=id} }
      if (oid!="") printf "oldest awaiting integration: %s waiting %.1fh — run the Integrator if this keeps climbing\n", oid, oldest/3600
    }' "$EVENTS"
  printf 'WIP now: %s active · %s review\n' \
    "$(ls "$BOARD/active" 2>/dev/null | grep -c '\.md$' || true)" \
    "$(ls "$BOARD/review" 2>/dev/null | grep -c '\.md$' || true)"
  metrics_depth_lines
}

metrics_depth_lines() { # test-depth.md § 6 — two lines, appended LAST: suite minutes skipped this
  # sprint (by depth) and the per-run build/land/suite/finish split, read from
  # .polaris/decisions.ndjson (T-198) + EVENTS.ndjson, sprint-scoped by SPRINT.md line 1's `dates:`.
  # No log → both lines still print (n/a, -). Pure read, never fails the caller.
  local sdate sepoch dec skip_line build_m land_m suite_m finish_m out
  sdate="$(sed -n '1p' "$OPS/SPRINT.md" 2>/dev/null | sed -n 's/.*dates:[[:space:]]*\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p')"
  sepoch=0
  if [ -n "$sdate" ]; then
    sepoch="$(date -d "$sdate" +%s 2>/dev/null || date -j -f %Y-%m-%d "$sdate" +%s 2>/dev/null || echo 0)"
    case "$sepoch" in ''|*[!0-9]*) sepoch=0;; esac
  fi
  dec="$PRIMARY/.polaris/decisions.ndjson"
  if [ -s "$dec" ]; then
    skip_line="$(awk -v epoch="$sepoch" '
      function get(k,   m){ m=""; if (match($0, "\""k"\":\"[^\"]*\"")) { m=substr($0,RSTART,RLENGTH); sub("\""k"\":\"","",m); sub("\"$","",m) } return m }
      function num(k,   m){ m=""; if (match($0, "\""k"\":[0-9]+"))     { m=substr($0,RSTART,RLENGTH); sub("\""k"\":","",m) } return m+0 }
      BEGIN{ nf=0; nd=0 }
      { ts=num("ts"); if (ts<epoch) next
        if (get("kind")!="test_depth") next
        d=get("depth"); s=num("secs")
        if (d=="full") { fs[nf]=s; nf++ } else { cnt[d]++; d2[nd]=s; nd++ }
      }
      END{
        if (nf>0) {
          for(i=1;i<nf;i++){v=fs[i];j=i-1;while(j>=0&&fs[j]>v){fs[j+1]=fs[j];j--}fs[j+1]=v}
          med=fs[int((nf-1)/2)]; skip=0
          for(i=0;i<nd;i++){ df=med-d2[i]; if (df>0) skip+=df }
          printf "suite skipped this sprint: %.1f min (none %d · look %d · scoped %d)\n", skip/60, cnt["none"]+0, cnt["look"]+0, cnt["scoped"]+0
        } else {
          printf "suite skipped this sprint: n/a (no full suite timed yet)\n"
        }
      }
    ' "$dec" 2>/dev/null)"
    out="$(awk -v epoch="$sepoch" '
      function get(k,   m){ m=""; if (match($0, "\""k"\":\"[^\"]*\"")) { m=substr($0,RSTART,RLENGTH); sub("\""k"\":\"","",m); sub("\"$","",m) } return m }
      function num(k,   m){ m=""; if (match($0, "\""k"\":[0-9]+"))     { m=substr($0,RSTART,RLENGTH); sub("\""k"\":","",m) } return m+0 }
      { ts=num("ts"); if (ts<epoch) next
        kind=get("kind"); s=num("secs")
        if (kind=="test_depth") { ssum+=s; sn++ }
        else if (kind=="finish") { fsum+=s; fn++ }
      }
      END{ printf "%s %s\n", (sn? sprintf("%.1f", ssum/sn/60) : "-"), (fn? sprintf("%.1f", fsum/fn/60) : "-") }
    ' "$dec" 2>/dev/null)"
    set -- $out; suite_m="${1:--}"; finish_m="${2:--}"
  else
    skip_line="suite skipped this sprint: n/a (no full suite timed yet)"
    suite_m="-"; finish_m="-"
  fi
  if [ -s "$EVENTS" ]; then
    out="$(awk -v epoch="$sepoch" '
      function get(k,   m){ m=""; if (match($0, "\""k"\":\"[^\"]*\"")) { m=substr($0,RSTART,RLENGTH); sub("\""k"\":\"","",m); sub("\"$","",m) } return m }
      function num(k,   m){ m=""; if (match($0, "\""k"\":[0-9]+"))     { m=substr($0,RSTART,RLENGTH); sub("\""k"\":","",m) } return m+0 }
      { ts=num("ts"); ev=get("ev"); id=get("id")
        if (ev=="claim"   && !(id in claimed)) claimed[id]=ts
        if (ev=="handoff" && !(id in ho))       ho[id]=ts
        if (ev=="done"    && !(id in done))     done[id]=ts
      }
      END{
        bs=0; bn=0; for (id in ho)   if (id in claimed && claimed[id]>=epoch) { bs+=ho[id]-claimed[id]; bn++ }
        is=0; iN=0; for (id in done) if (id in ho      && ho[id]>=epoch)      { is+=done[id]-ho[id]; iN++ }
        printf "%s %s\n", (bn? sprintf("%.1f", bs/bn/60) : "-"), (iN? sprintf("%.1f", is/iN/60) : "-")
      }
    ' "$EVENTS" 2>/dev/null)"
    set -- $out; build_m="${1:--}"; land_m="${2:--}"
  else
    build_m="-"; land_m="-"
  fi
  printf '%s\n' "$skip_line"
  printf 'per run: build %sm · land %sm · suite %sm · finish %sm\n' "$build_m" "$land_m" "$suite_m" "$finish_m"
}

cmd_why() { # why <ID> — the reasons a task bounced or blocked, from telemetry + its own body. The
  # reasons are captured (evt kickback/release, ⛔ lines appended to the task) but no trusted tool
  # surfaced them — you had to hand-open the task or the untested dashboard. This is that tool.
  local id="${1:?usage: polaris why <ID>}" tf out
  tf="$(task_file "$id")" || die "no task file for $id"
  note "why $id — $(fm_get status "$tf" | grep . || echo '?'), currently in $(task_col "$id")/"
  out=""
  if [ -s "$EVENTS" ]; then
    out="$(awk -v id="$id" -v now="$(date +%s)" '
      function g(k,  m){ m=""; if (match($0,"\""k"\":\"[^\"]*\"")){m=substr($0,RSTART,RLENGTH);sub("\""k"\":\"","",m);sub("\"$","",m)} return m }
      function n(k,  m){ m=0; if (match($0,"\""k"\":[0-9]+")){m=substr($0,RSTART,RLENGTH);sub("\""k"\":","",m)} return m+0 }
      { e=g("ev"); if (g("id")==id && (e=="kickback"||e=="release"||e=="blocked")) {
          nt=g("note"); printf "  %5dh ago  %-8s %s\n", int((now-n("ts"))/3600), e, (nt==""?"(no note)":nt) } }
    ' "$EVENTS")"
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  if grep -q '⛔' "$tf" 2>/dev/null; then note "notes on the task file:"; grep '⛔' "$tf" | sed 's/^[[:space:]]*/     /'; fi
  { [ -z "$out" ] && ! grep -q '⛔' "$tf" 2>/dev/null; } && say "$id has a clean record — no kickbacks or releases logged"
  return 0
}

cmd_dash() { # launch the read-only live board (single-file stdlib server)
  local PY=""
  # `-c pass` proves a REAL interpreter — `command -v` alone is fooled by the
  # Windows Store python3 alias stub, which sits on PATH but only prints an ad.
  python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; } || true
  [ -n "$PY" ] || die "dashboard needs python3 (or python) on PATH — everything else in POLARIS runs without it"
  exec "$PY" "$OPS/dashboard.py" --root "$PRIMARY" "$@"
}

find_claude() { # resolve the Claude Code CLI the way it will actually be invoked. On Windows `claude`
  # is usually a .cmd/.exe shim that Git Bash's `command -v claude` misses — so the 5.7.0 "builders
  # beside you" launch silently no-op'd. Probe the shims too. Prints the runnable name, or nothing.
  local c
  for c in claude claude.cmd claude.exe; do
    command -v "$c" >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }
  done
  return 1
}
find_claude_windows() { # pane command wt.exe can actually launch. wt hands its trailing args to
  # Windows CreateProcess, which CANNOT run the extension-less bash shim that `command -v claude`
  # finds first under Git Bash — every 5.8.0 pane died with 0x80070002 "file not found" before a
  # session even started. So resolve a REAL claude.exe/.cmd and print its FULL Windows path (8.3
  # short form, so "C:\Program Files"-style spaces never break wt's arg re-joining); if only the
  # bash shim exists, wrap it in bash.exe -lc. Prints TAB-separated pane tokens, or nothing.
  # $1 (optional): a model name — rides along as `--model <name>` (ops/contracts/model-routing.md);
  # empty → the token list is byte-identical to an unrouted launch.
  local m="${1:-}" c p b
  for c in claude.exe claude.cmd; do
    p="$(command -v "$c" 2>/dev/null)" && [ -n "$p" ] || continue
    if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -ws "$p" 2>/dev/null || cygpath -w "$p" 2>/dev/null || printf '%s' "$p")"; fi
    if [ -n "$m" ]; then printf '%s\t--model\t%s\tstart' "$p" "$m"; else printf '%s\tstart' "$p"; fi
    return 0
  done
  if command -v claude >/dev/null 2>&1 && b="$(command -v bash 2>/dev/null)" && [ -n "$b" ]; then
    if command -v cygpath >/dev/null 2>&1; then b="$(cygpath -ws "$b" 2>/dev/null || cygpath -w "$b" 2>/dev/null || printf '%s' "$b")"; fi
    if [ -n "$m" ]; then printf '%s\t-lc\tclaude --model %s start' "$b" "$m"; else printf '%s\t-lc\tclaude start' "$b"; fi
    return 0
  fi
  return 1
}
cmd_fleet() { # fleet <N> [--loop] [--launch] [--dry-run] — print N Builder kickoffs; --launch opens them
  local n="" loop="" launch="" dry="" i
  while [ $# -gt 0 ]; do
    case "$1" in
      --loop)    loop=" Run in loop mode.";;
      --launch)  launch=1;;
      --dry-run) dry=1;;
      -*)        die "fleet: unknown flag $1";;
      *)         if [ -z "$n" ]; then n="$1"; else die "fleet: unexpected arg '$1'"; fi;;
    esac
    shift
  done
  [ -n "$n" ] || die "usage: polaris fleet <N> [--loop] [--launch] [--dry-run]"
  case "$n" in *[!0-9]*) die "fleet: N must be a number";; esac
  [ "$n" -ge 1 ] || die "fleet: N must be >= 1"

  # The long form on purpose: this printed line is pasted into ANY agent CLI, including ones with no
  # POLARIS skill to route a bare `start`. In Claude Code, `start` alone does the same thing.
  # T-087 (shared-checkout v2 §4): fleet panes are TOP-LEVEL sessions, so the kickoff carries the
  # EnterWorktree entry line — claim only prints a cd, and prose a session can skip is how five
  # sessions ended up sharing the primary. The absolute-paths form rides along because this same
  # line is pasted into CLIs that have no such tool. NOTE the quoting: `msg` must stay free of
  # double quotes — the tmux branch below embeds it as "$claude_cmd$mtok \"$msg\"" and sh would
  # then read `.polaris/wt/<ID>` unquoted, where `<` is a redirection. Single quotes are safe here.
  # The handoff is a BOUNDARY, not an ending (ops/contracts/role-handover.md): the board itself
  # names the next step, so the pane asks it instead of going quiet with work still queued. The
  # before/after + --saw sentence rides along because a fleet pane never sees the conductor's template.
  local msg="You are a BUILDER. Claim the top ready task and complete it end to end, then enter its worktree — every command until handoff runs there: EnterWorktree({path: '.polaris/wt/<ID>'}), or run everything via absolute paths under .polaris/wt/<ID>, then bash ops/polaris next and follow it. Touching a visual: path? run the shot: line pack printed BEFORE and AFTER your edit, READ both pngs, and hand off with --saw '<what the after shot shows, and how it measures against ops/DESIGN.md>'.$loop"
  note "kickoff (paste into $n parallel sessions of ANY agent CLI — in Claude Code, \"start\" alone does it):"
  printf '   %s\n' "$msg"

  # Print-only unless the caller asked to open sessions (--launch) or preview that (--dry-run).
  # We NEVER spawn windows a caller didn't ask for — the Planner passes --launch per autolaunch:.
  if [ -z "$launch" ] && [ -z "$dry" ]; then
    note "(add --launch to open $n Builder sessions automatically, or open $n terminals and paste the line above)"
    return 0
  fi

  # Cap auto-launched sessions — screen + cost discipline. The printed kickoff above stays uncapped.
  local cap launch_n; cap="$(cfg autolaunch_max 5)"; case "$cap" in ''|*[!0-9]*) cap=5;; esac   # T-088: 3 → 5, re-sized for 5 lanes
  launch_n="$n"; [ "$launch_n" -gt "$cap" ] && launch_n="$cap"

  # Model routing (ops/contracts/model-routing.md § Consumers): panes claim RACILY — any pane may
  # end up holding any ready task — so every launched session rides the MAX tier over ready/
  # (strong > mid > cheap; a task's model: frontmatter counts when it names a tier). The max tier's
  # knob unset → no token, and the launch command stays byte-identical to an unrouted fleet.
  local ftier="" fmodel="" mtok="" tf tov tt
  for tf in "$BOARD/ready/"*.md; do
    [ -e "$tf" ] || break
    [ "${tf##*/}" = "IDEAS.md" ] && continue
    tov="$(fm_get model "$tf" 2>/dev/null || true)"
    case "$tov" in
      strong|mid|cheap) tt="$tov";;
      *) tt="$(tier_for "$(fm_get points "$tf")" "$(fm_get risk "$tf")")";;
    esac
    case "$tt" in
      strong) ftier="strong";;
      mid)    [ "$ftier" = "strong" ] || ftier="mid";;
      cheap)  [ -n "$ftier" ] || ftier="cheap";;
    esac
  done
  [ -n "$ftier" ] && fmodel="$(model_for_tier "$ftier")"
  [ -n "$fmodel" ] && mtok=" --model $fmodel"

  local claude_cmd; claude_cmd="$(find_claude || true)"
  local wt_pane=""
  command -v wt.exe >/dev/null 2>&1 && wt_pane="$(find_claude_windows "$fmodel" || true)"
  if command -v tmux >/dev/null 2>&1 && [ -n "$claude_cmd" ]; then
    if [ -n "$dry" ]; then
      note "[dry-run] tmux: $launch_n windows, each running: $claude_cmd$mtok \"$msg\""
    else
      tmux has-session -t polaris 2>/dev/null || tmux new-session -d -s polaris -c "$PRIMARY"
      for i in $(seq 1 "$launch_n"); do tmux new-window -t polaris -c "$PRIMARY" "$claude_cmd$mtok \"$msg\""; done
      say "fleet of $launch_n launched in tmux — attach: tmux attach -t polaris · watch: ops/polaris dash"
    fi
  elif [ -n "$wt_pane" ]; then
    # Windows Terminal: ONE new window with launch_n VERTICAL split panes (side by side), each running
    # `<claude> start` in the repo. The pane command comes from find_claude_windows — a full .exe/.cmd
    # Windows path CreateProcess can start (a bare `claude` resolves to the npm bash shim in Git Bash,
    # which killed every pane with 0x80070002). The repo's polaris skill routes `start` → BUILDER,
    # whose `claim` (no ID) SKIPS locked tasks and takes the next — so launch_n panes land on
    # launch_n distinct tasks, and a pane whose top pick was taken doesn't die.
    # `\;` reaches wt as a LITERAL subcommand separator, never a bash statement separator.
    [ -n "$loop" ] && note "(loop mode isn't applied to Windows Terminal panes — each does one task; say start again for more)"
    local dir="$PRIMARY" pane=()
    command -v cygpath >/dev/null 2>&1 && dir="$(cygpath -w "$PRIMARY" 2>/dev/null || printf '%s' "$PRIMARY")"
    IFS=$'\t' read -r -a pane <<<"$wt_pane"
    local w=( wt.exe -w new new-tab -d "$dir" "${pane[@]}" )
    for i in $(seq 2 "$launch_n"); do w+=( \; split-pane -V -d "$dir" "${pane[@]}" ); done
    if [ -n "$dry" ]; then
      note "[dry-run] would run:"; printf '  '; printf ' %q' "${w[@]}"; printf '\n'
    else
      "${w[@]}" >/dev/null 2>&1 &
      say "fleet of $launch_n launched in Windows Terminal (side-by-side panes) — watch: ops/polaris dash"
    fi
  else
    # Say WHY nothing opened, so a silent no-op never masquerades as "windows opened".
    if { command -v tmux >/dev/null 2>&1 || command -v wt.exe >/dev/null 2>&1; }; then
      note "found a terminal but no launchable 'claude' CLI (need claude, claude.cmd, or claude.exe on PATH). Install/repair the Claude CLI, or open $n terminals and paste the line above."
    else
      note "(auto-launch needs tmux+claude or Windows Terminal+claude on PATH — open $n terminals and paste the line above)"
    fi
    return 0
  fi
  [ "$n" -gt "$launch_n" ] && note "opened $launch_n of $n (cap autolaunch_max=$cap) — the rest stay claimable; say start in another session"
  return 0
}
