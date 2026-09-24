# POLARIS lib/observe.sh — read-only observers sourced by ops/polaris (the lib loader): notify-gate,
# status/--brief, sweep, doctor, drift, rules, qa, finish, metrics, why, dash, and fleet.

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
  local done_c active_c review_c ready_c ids f parts lead line2 newest ntitle top nextup n
  done_c=$(ls "$BOARD/done" 2>/dev/null | grep -c '\.md$' || true)
  active_c=$(ls "$BOARD/active" 2>/dev/null | grep -c '\.md$' || true)
  review_c=$(ls "$BOARD/review" 2>/dev/null | grep -c '\.md$' || true)
  ready_c=$(ls "$BOARD/ready" 2>/dev/null | grep -c '\.md$' || true)
  ids=""
  for f in "$BOARD/active/"*.md; do [ -e "$f" ] || break
    ids="${ids:+$ids, }$(basename "$f" .md)"
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
    id="$(basename "$f" .md)"; age="$(lock_age "$id")"
    printf '  %s · %s · lock age %ss%s\n' "$id" "$(fm_get owner "$f")" "${age:-?}" \
      "$( [ -n "${age:-}" ] && [ "$age" -gt $((STALE_H*3600)) ] && echo " ⚠ STALE — polaris resume $id to take over, or release")"
  done
  echo 'ready (top by wsjf):'
  { for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
      printf '%s\t%s · %spts · wsjf %s\n' "$(fm_get wsjf "$f")" "$(basename "$f" .md)" \
        "$(fm_get points "$f")" "$(fm_get wsjf "$f")"
    done; } | sort -rn | cut -f2- | head -5
  # blocked tasks are owned by no role until drained — surface them WITH the reason so they stop
  # being invisible (Integrator regrooms or escalates them; see INTEGRATOR.md).
  local bf bid any=0
  for bf in "$BOARD/blocked/"*.md; do [ -e "$bf" ] || break
    [ "$any" -eq 0 ] && echo 'blocked (needs regroom/escalation):'
    any=1; bid="$(basename "$bf" .md)"
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
      id="$(basename "$f" .md)"
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
      note "drain: ${dr:-queue} · drain_slices: ${ds:-2} (autonomy never composes drain)"
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


pat_overlap() { # heuristic: can patterns A and B claim a common path?
  # Proves: identical · exact⊂glob · exact⊂dir/ · dir/⊂dir/ · glob∩glob with nested literal dirs.
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  # match_one (lib/ownership.sh), NOT `printf | owned_match`: with exactly one pattern the pipeline
  # reduced to precisely this call, and a pipeline is a fork PER DIRECTION — two per comparison. The
  # sweep above is O(tasks x patterns squared): measured over 600 comparisons (a 5-lane board's full
  # sweep), 18.4s of forking became 0.053s of `case`. cmd_drift runs that sweep, cmd_qa runs drift
  # --strict and cmd_finish runs cmd_qa — the fork tax was on every finish. Semantics are identical:
  # owned_match skips empty patterns, and both-empty already returned above.
  match_one "$a" "$b" && return 0   # pattern B matches A taken as a literal path
  match_one "$b" "$a" && return 0   # pattern A matches B taken as a literal path
  case "$a" in */) case "$b" in "$a"*) return 0;; esac;; esac
  case "$b" in */) case "$a" in "$b"*) return 0;; esac;; esac
  # glob ∩ glob: exact intersection is undecidable, but the collision that bites in practice is
  # two globs whose literal directory prefixes nest (src/api/* vs src/*/handler.js → both can
  # match src/api/handler.js). Flag conservatively — a false "verify this" beats a missed clash.
  case "$a" in *"*"*) case "$b" in *"*"*)
    local la lb
    la="${a%%\**}"; la="${la%/*}"   # dir prefix up to the segment before the first glob
    lb="${b%%\**}"; lb="${lb%/*}"
    [ "$la" = "$lb" ] && return 0
    case "$lb/" in "$la"/*) return 0;; esac
    case "$la/" in "$lb"/*) return 0;; esac
  ;; esac;; esac
  return 1
}

rules_gate() { # rules_gate <owned-pattern> <ID|-> — does RULES gate this owned pattern, and WHY?
  # rc 0 = gated, with RULES_GATE (path|ask) and RULES_GATE_SCOPE naming the rule; rc 1 = clear.
  # cmd_triage and cmd_drift need the KIND behind a deny — rule_scan_path's rc deliberately carries
  # only yes/no and its contract is unchanged (ask-approval.md § 4) — so the classification lives
  # here, beside its two plan-gate callers. Matching is pat_overlap, BOTH directions: files_owned
  # entries and rule scopes are both patterns, so a task owning src/db/ intersects a scope
  # src/db/schema.py even though scope-matches-path alone would miss it. `path` dominates `ask`:
  # a pattern under both gets the wall's answer, because no approval can lift a `path` rule.
  # An `ask` scope covered by <ID>'s approved: list does not gate — the question is settled
  # (ask-approval.md § 5). `content` rules never gate planning: they judge diffs, not ownership.
  local p="$1" id="${2:--}" scope kind pat msg ask_scope=""
  RULES_GATE=""; RULES_GATE_SCOPE=""
  # Read the memo in THIS shell: `$(rules_lines)` filled it inside a subshell and threw it away, so
  # every call re-ran tr|grep|grep — each owned pattern of each ready task paid it, in drift and triage.
  rules_lines >/dev/null
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    case "$kind" in path|ask) ;; *) continue;; esac
    pat_overlap "$p" "$scope" || continue
    if [ "$kind" = "path" ]; then RULES_GATE=path; RULES_GATE_SCOPE="$scope"; return 0; fi
    [ -n "$ask_scope" ] && continue
    ask_approval_covers "$p" "$id" || ask_scope="$scope"
  done <<EOF
$_RULES_CACHE
EOF
  [ -n "$ask_scope" ] && { RULES_GATE=ask; RULES_GATE_SCOPE="$ask_scope"; return 0; }
  return 1
}

dep_ids() { # dep_ids <taskfile> — depends_on entries as clean ids, handling BOTH block lists
  # ("- T-002") and the inline form ("[T-002, T-003]"). The sed bracket-expression strips [ ] and ,
  # portably — BSD tr (macOS) mishandles a bare '[]' set, so `tr -d '[]'` is NOT portable here.
  fm_list depends_on "$1" 2>/dev/null | sed 's/[][,]/ /g' | tr ' ' '\n' | grep -v '^[[:space:]]*$' || true
}
dep_reaches() { # dep_reaches <cur-id> <target-id> <visited> — 0 if target is reachable from cur via
  # depends_on. A task that reaches ITSELF sits in a cycle and can never satisfy the ready gate.
  local cur="$1" target="$2" visited="$3" f d
  f="$(task_file "$cur")" || return 1
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    [ "$d" = "$target" ] && return 0
    case " $visited " in *" $d "*) continue;; esac
    dep_reaches "$d" "$target" "$visited $d" && return 0
  done <<EOF
$(dep_ids "$f")
EOF
  return 1
}

cmd_drift() { # mechanical hygiene audit — the invariants, machine-checked. --strict: rc 1 on findings
  local strict="${1:-}" n=0 f g id id2 v d p s t hk hn hs hr
  finding() { n=$((n+1)); printf '⚠ [%d] %s\n' "$n" "$1"; }
  # Warm both per-process memos in THIS shell: their readers call them as $(…), a subshell that
  # fills the memo and discards it, so every rules/surfaces read below paid three forks again.
  rules_lines >/dev/null; surfaces_lines >/dev/null
  # 1) THE invariant: files_owned disjoint across ready ∪ active (heuristic, see pat_overlap)
  local claimable="" nready=0; set --
  for d in ready active; do
    for f in "$BOARD/$d/"*.md; do [ -e "$f" ] || break; claimable="$claimable$f
"; set -- "$@" "$f"; done
    if [ "$d" = ready ]; then nready=$#; fi
  done
  # ONE frontmatter pass over ready ∪ active — the only columns § 1 and § 2 read (speed.md § 3).
  # Every key is read exactly as its reader reads it: contract/points/title as fm_get (first match),
  # files_owned/surface as fm_list, depends_on as dep_ids — tagged <pos><TAB><key><TAB><value>,
  # <pos> being the file's 0-based place in $claimable (ready first, then active, glob order).
  # The per-key, per-pair awk starts this replaces were most of what drift still cost once § 7
  # became one pass. Kept in fcon/fpts/fttl (scalars) and fown/fsrf/fdep (newline lists).
  local nl='
' fx fk fv fmx fcon fpts fttl fown fsrf fdep
  if [ $# -gt 0 ]; then
    fmx="$(awk '
  function out(x, k, s) { printf "%d\t%s\t%s\n", x, k, s }
  function item(x, k, s,   n, j, p) {
    if (k != "depends_on") { out(x, k, s); return }
    gsub(/\[/, " ", s); gsub(/\]/, " ", s); gsub(/,/, " ", s)
    n = split(s, p, "[ ]")
    for (j = 1; j <= n; j++) if (p[j] !~ /^[[:space:]]*$/) out(x, k, p[j])
  }
  function emit(x, k, s,   n, j, p, it) {
    if (s == "") return
    if (s ~ /^\[.*\]$/) {
      s = substr(s, 2, length(s) - 2); n = split(s, p, ",")
      for (j = 1; j <= n; j++) {
        it = p[j]; sub(/^[ \t]*/, "", it); sub(/[ \t]*$/, "", it)
        if (it != "") item(x, k, it)
      }
      return
    }
    item(x, k, s)
  }
  BEGIN {
    ns = split("contract points title", sk, " "); nk = split("files_owned surface depends_on", lk, " ")
    for (i = 1; i < ARGC; i++) {
      path = ARGV[i]; x = i - 1; fs = 0; on = ""
      while ((getline line < path) > 0) {
        if (line ~ /^---[\r]?$/) { if (++fs > 1) break; continue }
        if (fs != 1) continue
        for (j = 1; j <= ns; j++) if (!((x, sk[j]) in got) && index(line, sk[j] ":") == 1) {
          s = substr(line, length(sk[j]) + 2)
          sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          out(x, sk[j], s); got[x, sk[j]] = 1
        }
        hit = 0
        for (j = 1; j <= nk; j++) if (index(line, lk[j] ":") == 1) {
          on = lk[j]; hit = 1; s = substr(line, length(on) + 2)
          sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          emit(x, on, s)
        }
        if (hit) continue
        if (on != "" && line ~ /^[ \t]*-[ \t]/) {
          s = line; sub(/^[ \t]*-[ \t]+/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          if (s != "") item(x, on, s)
          continue
        }
        if (on != "" && line ~ /^[A-Za-z_]/) on = ""
      }
      close(path)
    }
    exit
  }' "$@" 2>/dev/null || true)"
    while IFS= read -r v; do [ -z "$v" ] && continue
      fx="${v%%$POLARIS_TAB*}"; v="${v#*$POLARIS_TAB}"; fk="${v%%$POLARIS_TAB*}"; fv="${v#*$POLARIS_TAB}"
      case "$fk" in
        contract) fcon[$fx]="$fv";;
        points) fpts[$fx]="$fv";;
        title) fttl[$fx]="$fv";;
        files_owned) fown[$fx]="${fown[$fx]:-}$fv$nl";;
        surface) fsrf[$fx]="${fsrf[$fx]:-}$fv$nl";;
        depends_on) fdep[$fx]="${fdep[$fx]:-}$fv$nl";;
      esac
    done <<EOF
$fmx
EOF
  fi
  # The pairwise walk: each task's list comes from the pass above and is kept in oid[]/opat[], so
  # the walk itself forks nothing — pat_overlap is pure `case`. Same pairs, same order, same lines.
  local pa pb fo j k=0 oid opat
  while IFS= read -r f; do [ -z "$f" ] && continue
    id="${f##*/}"; id="${id%.md}"
    fo="${fown[$k]:-}"
    j=0
    while [ "$j" -lt "$k" ]; do
      id2="${oid[$j]}"
      while IFS= read -r pa; do [ -z "$pa" ] && continue
        while IFS= read -r pb; do [ -z "$pb" ] && continue
          if pat_overlap "$pa" "$pb"; then
            finding "OWNERSHIP OVERLAP: $id ∩ $id2 on '$pa' / '$pb' — chain them (depends_on), never parallel"
          fi
        done <<EOF2
${opat[$j]}
EOF2
      done <<EOF1
$fo
EOF1
      j=$((j+1))
    done
    oid[$k]="$id"; opat[$k]="$fo"; k=$((k+1))
  done <<EOF
$claimable
EOF
  # 2) ready-gate: contract exists · deps all done · ≤5 points — the ready files are positions
  # 0..nready-1 of the same list, so every key below comes from the one pass above.
  k=0
  for f in "$@"; do
    [ "$k" -lt "$nready" ] || break
    id="${f##*/}"; id="${id%.md}"
    v="${fcon[$k]:-}"
    # NAMED but MISSING only — an unset contract is legal (handover.sh next_promote, builder.sh pack).
    [ -n "$v" ] && [ ! -f "$PRIMARY/$v" ] && finding "READY GATE: $id contract missing ($v) — blocked/, not ready/"
    while IFS= read -r d; do [ -z "$d" ] && continue
      task_file "$d" done >/dev/null || finding "READY GATE: $id depends_on $d which is NOT in done/"
    done <<EOF
${fdep[$k]:-}
EOF
    v="${fpts[$k]:-}"; case "$v" in 8|13) finding "READY GATE: $id is ${v}pts — must be split before ready/";; esac
    # ask gate (ask-approval.md § 5): a ready task owning anything under an `ask` scope with no
    # covering approved: entry would spawn a Builder only to die on its first write — the ARC
    # sequence, stopped here at step 1. The asking belongs at the plan gate, where a human is
    # present and it is cheap. A covered scope is a settled question and no finding at all.
    while IFS= read -r p; do [ -z "$p" ] && continue
      if rules_gate "$p" "$id" && [ "$RULES_GATE" = "ask" ]; then
        finding "READY GATE: $id owns '$p' under ask scope '$RULES_GATE_SCOPE' with no covering approved: entry — get the human's yes (polaris approve $id $RULES_GATE_SCOPE -m \"why\") or blocked/, not ready/"
      fi
    done <<EOF
${fown[$k]:-}
EOF
    # surface: items (test-surfaces.md § 3, § 7): `done` writes each one as an ops/SURFACES.tsv row
    # and merely skips a malformed one with a ⚠ — so the typo is caught HERE, at the plan gate, and
    # never discovered at done. A tests glob covering its own surface is the one row shape the
    # whole map cannot survive (D6), so it is refused before any builder claims the task.
    v="${fttl[$k]:-}"
    while IFS= read -r p; do [ -z "$p" ] && continue
      if d="$(surface_row_from_item "$p" "$id" "$v")"; then
        s="${d%%$POLARIS_TAB*}"; t="${d#*$POLARIS_TAB}"; t="${t%%$POLARIS_TAB*}"
        match_one "$s" "$t" && finding "READY GATE: $id surface: '$p' — tests glob covers its own surface — fix the item before a builder claims it"
      else
        finding "READY GATE: $id surface: '$p' — $d — fix the item before a builder claims it"
      fi
    done <<EOF
${fsrf[$k]:-}
EOF
    k=$((k+1))
  done
  # 3) cruft: a done task's feat branch survived — THREE classes, not one (ops/contracts/
  # worktree-liveness.md § v2). Under `landing: self` a lane leaves its OWN branch behind by design
  # (v1.2: never remove the ground you are standing on), so the flat "the branch exists" finding
  # fired on every self-landed wave — after `qa` had already paid the suite, which withheld the
  # stamp and made the next `finish` pay it all over again for a nit clearable in a second. A
  # branch is a finding only once nobody is standing in its worktree, and DELETABLE only with proof
  # its tip is already in $BASE. ONE ref read, and the loop walks the BRANCHES, never done/ (speed.md
  # § 3): a handful of refs instead of every task ever finished, with zero process starts per step.
  # A branch whose name matches NO task in any column is an ADVISORY, never a finding: it may hold
  # unmerged work, so nothing may clear it, and a new red class would red `qa` in every install that
  # carries a legacy stray the moment it updates. It is printed so the stray is seen — nothing more.
  local crefs; crefs="$(git -C "$PRIMARY" for-each-ref --format='%(refname)' 'refs/heads/feat/*' 2>/dev/null || true)"
  for f in $crefs; do
    id="${f#refs/heads/feat/}"
    if [ -f "$BOARD/done/$id.md" ]; then
      if ! feat_tip_landed "$id"; then
        finding "CRUFT diverged: feat/$id carries commits not in $BASE — inspect: git log $BASE..feat/$id (never auto-deleted)"
      elif [ -d "$GCD/worktrees/$id" ] && beat_live "$id"; then
        : # waiting — the lane that landed it is still inside its own worktree; `sweep` lists the LIVE worktree and drift says nothing
      else
        finding "CRUFT: feat/$id still exists though $id is done — bash ops/polaris qa or sweep --fix clears it"
      fi
    elif ! task_file "$id" >/dev/null; then
      note "advisory: orphan branch feat/$id — no task in any column (may hold unmerged work; never auto-cleared)"
    fi
  done
  # 4) stale forward refs: TODO(T-…) pointing at tasks already done
  local refs; refs="$(grep -RIn 'TODO([A-Za-z][A-Za-z0-9._-]*-[0-9A-Za-z]' "$BOARD" "$OPS/contracts" "$OPS/SPRINT.md" "$OPS/MAP.md" 2>/dev/null || true)"
  while IFS= read -r v; do [ -z "$v" ] && continue
    id="$(printf '%s' "$v" | sed -n 's/.*TODO(\([A-Za-z][A-Za-z0-9._-]*-[0-9A-Za-z][0-9A-Za-z]*\)).*/\1/p')"
    [ -n "$id" ] && task_file "$id" done >/dev/null \
      && finding "STALE REF: $(printf '%s' "$v" | cut -d: -f1,2) — $id is done; update the text"
  done <<EOF
$refs
EOF
  # 5) doc overflow: MAP Deltas tail + Learned log
  v="$(grep -Ec ' \([A-Za-z0-9._-]+, [0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$OPS/MAP.md" 2>/dev/null || true)"
  [ "${v:-0}" -gt 20 ] && finding "MAP: $v delta lines — fold them into the sections (EVOLVE target)"
  v="$(awk '/^##[ \t]*Learned/{on=1;next} on&&/^## /{exit} on&&/^[ \t]*[-*]/{c++} END{print c+0}' "$OPS/SPRINT.md" 2>/dev/null || true)"
  [ "${v:-0}" -gt 8 ] && finding "LEARNED: $v bullets — prune to ≤5 carry-overs (EVOLVE target)"
  # 6) telemetry safety
  [ -f "$EVENTS" ] && ! grep -q 'EVENTS\.ndjson merge=union' "$PRIMARY/.gitattributes" 2>/dev/null \
    && finding "TELEMETRY: EVENTS.ndjson without union-merge gitattribute — run: ops/polaris upgrade"
  # 7) dependency graph across ALL columns: deps that exist nowhere + cycles (a ring never promotes).
  # ONE inline awk pass over every column (speed.md § 3). The per-task walk it replaces re-read the
  # whole board once per dependency, done/ included, and was ~94% of drift's wall time. Same verdicts
  # in the same order: files in backlog ready active review blocked done order, glob order inside a
  # column · a dependency is read exactly as dep_ids reads it (fm_list's block and flow shapes, then
  # split on [ ] , and space) · an id resolves to the file task_file would pick (active first, done
  # last) · a task is a DEP CYCLE iff it can reach itself. Files are read with getline, so one that
  # another lane moves mid-pass reads as empty instead of killing the pass.
  local col2 idf dout
  set --
  for col2 in backlog ready active review blocked done; do
    for idf in "$BOARD/$col2/"*.md; do [ -e "$idf" ] || break; set -- "$@" "$idf"; done
  done
  if [ $# -gt 0 ]; then
    dout="$(awk '
  function add(i, s,   n, k, p) {
    gsub(/\[/, " ", s); gsub(/\]/, " ", s); gsub(/,/, " ", s)
    n = split(s, p, "[ ]")
    for (k = 1; k <= n; k++) if (p[k] !~ /^[[:space:]]*$/) { nd[i]++; dep[i, nd[i]] = p[k] }
  }
  function emit(i, s,   n, k, p, item) {
    if (s == "") return
    if (s ~ /^\[.*\]$/) {
      s = substr(s, 2, length(s) - 2); n = split(s, p, ",")
      for (k = 1; k <= n; k++) {
        item = p[k]; sub(/^[ \t]*/, "", item); sub(/[ \t]*$/, "", item)
        if (item != "") add(i, item)
      }
      return
    }
    add(i, s)
  }
  function reaches(s,   q, h, t, u, b, k) {
    stamp++; h = 1; t = 0; b = best[s]
    for (k = 1; k <= nd[b]; k++) q[++t] = dep[b, k]
    while (h <= t) {
      u = q[h++]
      if (u == s) return 1
      if (!(u in best) || vis[u] == stamp) continue
      vis[u] = stamp; b = best[u]
      for (k = 1; k <= nd[b]; k++) q[++t] = dep[b, k]
    }
    return 0
  }
  BEGIN {
    split("active ready review blocked backlog done", c, " ")
    for (k = 1; k <= 6; k++) rank[c[k]] = k
    nf = ARGC - 1
    for (i = 1; i <= nf; i++) {
      path = ARGV[i]; n = split(path, seg, "/")
      id = seg[n]; sub(/\.md$/, "", id); fid[i] = id
      r = (n > 1 && (seg[n-1] in rank)) ? rank[seg[n-1]] : 9
      if (!(id in best) || r < brank[id]) { best[id] = i; brank[id] = r }
      fs = 0; on = 0
      while ((getline line < path) > 0) {
        if (line ~ /^---[\r]?$/) { if (++fs > 1) break; continue }
        if (fs != 1) continue
        if (index(line, "depends_on:") == 1) {
          on = 1; s = substr(line, 12)
          sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          emit(i, s); continue
        }
        if (on && line ~ /^[ \t]*-[ \t]/) {
          s = line; sub(/^[ \t]*-[ \t]+/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          if (s != "") add(i, s)
          continue
        }
        if (on && line ~ /^[A-Za-z_]/) on = 0
      }
      close(path)
    }
    for (i = 1; i <= nf; i++) {
      for (k = 1; k <= nd[i]; k++)
        if (!(dep[i, k] in best)) printf "DEP MISSING: %s depends_on %s — no task by that id in any column\n", fid[i], dep[i, k]
      if (!(fid[i] in cyc)) cyc[fid[i]] = reaches(fid[i])
      if (cyc[fid[i]]) printf "DEP CYCLE: %s sits in a depends_on ring — it can never satisfy the ready gate; break the cycle\n", fid[i]
    }
    exit
  }' "$@" 2>/dev/null || true)"
    while IFS= read -r v; do if [ -n "$v" ]; then finding "$v"; fi; done <<EOF
$dout
EOF
  fi
  # 8) surfaces (test-surfaces.md § 7): a row that would make change-scoped selection lie — the E
  # lines of surfaces_health. Its warnings (a glob in a rename window, an unarmed guard) never red
  # a wave gate; `ops/polaris surfaces` shows them.
  while IFS="$POLARIS_TAB" read -r hk hn hs hr; do
    [ "$hk" = E ] || continue
    finding "SURFACES: row $hn '$hs' — $hr (ops/polaris surfaces)"
  done <<EOF
$(surfaces_health || true)
EOF
  if [ "$n" -eq 0 ]; then say "drift: board clean (overlap · ready gate · cruft · stale refs · doc overflow · telemetry · deps)"
  else printf '%d finding(s).\n' "$n"; [ "$strict" = "--strict" ] && exit 1; fi
  return 0
}

cmd_rules() { # list + health-check ops/RULES.tsv
  if ! rules_lines | grep -q .; then note "no rules yet — ops/RULES.tsv (INIT seeds danger zones; EVOLVE proposes more)"; return 0; fi
  local scope kind pat msg n=0 bad=0
  printf '%-28s %-8s %-24s %s\n' 'SCOPE' 'KIND' 'PATTERN' 'MESSAGE'
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    n=$((n+1)); printf '%-28s %-8s %-24s %s\n' "$scope" "$kind" "${pat:--}" "$msg"
    # `ask` is a first-class kind (ask-approval.md § 1): pattern column `-`, exactly as for path —
    # no ERE is demanded for either. Only `content` carries a pattern that must compile.
    case "$kind" in path|content|ask) :;; *) bad=1; printf '   ⛔ bad kind (want path|content|ask)\n';; esac
    [ -z "$scope" ] && { bad=1; printf '   ⛔ empty scope\n'; }
    if [ "$kind" = "content" ]; then
      { [ -z "$pat" ] || [ "$pat" = "-" ]; } && { bad=1; printf '   ⛔ content rule needs an ERE pattern\n'; }
      local rc=0; grep -E -e "${pat:-x}" /dev/null >/dev/null 2>&1 || rc=$?
      [ "$rc" -eq 2 ] && { bad=1; printf '   ⛔ pattern does not compile (grep -E)\n'; }
    fi
  done <<EOF
$(rules_lines)
EOF
  [ "$bad" -eq 0 ] && say "$n rule(s), all healthy" || die "rules health check failed — fix ops/RULES.tsv"
}

surfaces_health() { # surfaces_health — ops/SURFACES.tsv health as DATA, one line per problem:
  # E|W<TAB><row#>|0<TAB><surface>|-<TAB><reason>; rc = the number of E lines (0 = healthy). Row
  # numbers are 1-based over surfaces_lines, row 0 = repo-level. cmd_surfaces renders these; drift
  # turns the E lines into findings and never the W lines — a glob in a rename window must not red
  # every wave gate (test-surfaces.md § 7). Selection fails UNSAFE (D6): a wrong tests glob skips
  # coverage while reporting green, so the one row shape that would make the whole map lie — a
  # tests glob covering its own surface, the tests pattern applied as a files_owned matcher to the
  # surface taken as a path — is an E; a glob matching nothing or far too much is a W. No rows ⇒
  # prints nothing, rc 0, no fork. ONE `git ls-files` fork, then match_one per file (builtins).
  local lines row n=0 e=0 surface tests cmd rest tracked f cs ct tpl
  lines="$(surfaces_lines)"
  [ -n "$lines" ] || return 0
  tracked="$(git -C "$PRIMARY" ls-files 2>/dev/null || true)"
  tpl="$(cfg test_select "")"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    n=$((n + 1))
    surface="${row%%$POLARIS_TAB*}"
    rest=""; case "$row" in *"$POLARIS_TAB"*) rest="${row#*$POLARIS_TAB}";; esac
    tests="${rest%%$POLARIS_TAB*}"
    cmd=""; case "$rest" in *"$POLARIS_TAB"*) cmd="${rest#*$POLARIS_TAB}"; cmd="${cmd%%$POLARIS_TAB*}";; esac
    if [ -z "$surface" ] || [ -z "$tests" ]; then
      e=$((e + 1)); printf 'E\t%s\t%s\t%s\n' "$n" "${surface:--}" "fewer than 2 columns"; continue
    fi
    if match_one "$surface" "$tests"; then
      e=$((e + 1)); printf 'E\t%s\t%s\t%s\n' "$n" "$surface" "tests glob covers its own surface"
    fi
    cs=0; ct=0
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      match_one "$f" "$surface" && cs=$((cs + 1))
      match_one "$f" "$tests" && ct=$((ct + 1))
    done <<EOF
$tracked
EOF
    [ "$cs" -eq 0 ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "surface matches 0 tracked files"
    [ "$cs" -gt 200 ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "surface matches $cs tracked files (>200 — too broad to select anything)"
    [ "$ct" -eq 0 ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "tests matches 0 tracked files"
    [ "$cmd" = "-" ] && [ -z "$tpl" ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "cmd is - but test_select: is unset"
  done <<EOF
$lines
EOF
  # Repo-level: the file is meant to be written only by `done`. Without a RULES `path` rule over
  # it, a row anyone could delete when it blocked them guards nothing (D2).
  if rules_gate ops/SURFACES.tsv - && [ "$RULES_GATE" = "path" ]; then :; else
    printf 'W\t0\t-\t%s\n' "ops/SURFACES.tsv is not RULES-guarded — arm a path rule so only done writes it"
  fi
  return "$e"
}

cmd_surfaces() { # surfaces [--scaffold [--apply]] — list + health-check ops/SURFACES.tsv (test-surfaces.md
  # § 7); rc 1 iff any ⛔. Mirrors cmd_rules: the table, each row's problems indented beneath it,
  # the repo-level warnings after the table, then ONE tail line carrying the counts.
  # --scaffold (v2 § 14) PROPOSES rows from the stack's own layout — the engine in surfaces.sh
  # decides, this renders: the runner it found, the rows it would write, every pairing it skipped
  # and why — and writes nothing, ever. --scaffold --apply writes exactly those rows (tagged
  # [scaffold]) and sets test_select: where the repo never set it, on $BASE only, and commits
  # nothing: the diff is the review. D6 is the rule here — an unmapped surface runs the whole suite
  # (safe); a MIS-mapped one skips real coverage while reporting green, and in a repo nobody is
  # watching nobody would notice — so the ambiguous pairings are said aloud as skips, never guessed.
  # The `git ls-files` below is the caller's ONE fork, handed to the engine as a file, never a pipe.
  local u="usage: polaris surfaces [--scaffold [--apply]]" mode=""
  if [ $# -gt 0 ]; then
    [ "$1" = --scaffold ] || die "$u"
    case "$#:${2:-}" in 1:) mode=scaffold;; 2:--apply) mode=apply;; *) die "$u";; esac
  fi
  if [ -n "$mode" ]; then
    local ls prop kind what why cmd rest n=0 s=0 rc=0
    if [ "$mode" = apply ]; then
      # feat/* is where Builders live, and a Builder never writes a row (D1: a row buys R1's savings
      # and arms R2 against you). From a task, rows are surface: items and `done` writes them.
      what="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      case "$what" in feat/*) die "surfaces --scaffold --apply runs on $BASE only — from a task, rows are surface: items (polaris done writes them)";; esac
      [ -f "$CONV" ] || die "no ops/CONVENTIONS.md — run INIT first; the scaffold sets test_select: in it"
    fi
    ls="$(mktemp)"; prop="$(mktemp)"
    git -C "$PRIMARY" ls-files > "$ls" 2>/dev/null || true
    if [ -f "$SURFACES" ]; then surfaces_proposal "$ls" "$SURFACES" > "$prop"; else surfaces_proposal "$ls" > "$prop"; fi
    rm -f "$ls"
    while IFS="$POLARIS_TAB" read -r kind what why cmd rest; do
      case "$kind" in
        NORUNNER) note "$what. Map rows by hand: a task's surface: items (ops/roles/PLANNER.md step 5b)"; rm -f "$prop"; return 0;;
        RUNNER)   note "runner: $what — test_select: $why"; printf '%-28s %-28s %s\n' SURFACE TESTS CMD;;
        ROW)      n=$((n + 1)); printf '%-28s %-28s %s\n' "$what" "$why" "$cmd";;
        SKIP)     s=$((s + 1)); printf '   ⚠ skipped: %s — %s\n' "$what" "$why";;
      esac
    done < "$prop"
    if [ "$n" -eq 0 ]; then
      if [ "$s" -ge 1 ]; then note "nothing to propose — $s pairing(s) skipped, listed above"
      else note "nothing to propose — no pairing the layout makes unambiguous (map rows by hand: surface: items)"; fi
      rm -f "$prop"; return 0
    fi
    if [ "$mode" = scaffold ]; then
      say "$n row(s) proposed · $s skipped — write them: ops/polaris surfaces --scaffold --apply"
      rm -f "$prop"; return 0
    fi
    surfaces_apply "$prop" || rc=$?
    rm -f "$prop"
    return "$rc"
  fi
  if ! surfaces_lines | grep -q .; then
    note "no surfaces yet — ops/SURFACES.tsv (init-board seeds the header; rows arrive from a task's surface: list when done lands it — never by hand)"
    return 0
  fi
  local health surface tests cmd msg n=0 e=0 w=0 kind rn surf reason
  health="$(surfaces_health || true)"   # the verdict is in the lines; the rc is recounted below
  printf '%-28s %-28s %-32s %s\n' 'SURFACE' 'TESTS' 'CMD' 'NOTE'
  while IFS="$POLARIS_TAB" read -r surface tests cmd msg; do
    [ -n "$surface$tests$cmd$msg" ] || continue
    n=$((n + 1)); printf '%-28s %-28s %-32s %s\n' "$surface" "${tests:--}" "${cmd:--}" "$msg"
    while IFS="$POLARIS_TAB" read -r kind rn surf reason; do
      [ "$rn" = "$n" ] || continue
      case "$kind" in E) printf '   ⛔ %s\n' "$reason";; W) printf '   ⚠ %s\n' "$reason";; esac
    done <<EOF2
$health
EOF2
  done <<EOF
$(surfaces_lines)
EOF
  while IFS="$POLARIS_TAB" read -r kind rn surf reason; do
    case "$kind" in E) e=$((e + 1));; W) w=$((w + 1));; *) continue;; esac
    [ "$rn" = 0 ] && printf '   ⚠ %s\n' "$reason"
  done <<EOF
$health
EOF
  [ "$e" -eq 0 ] || die "$n surface row(s), $e unhealthy"
  [ "$w" -eq 0 ] || { say "$n surface row(s), all healthy · $w warning(s)"; return 0; }
  say "$n surface row(s), all healthy"
}

surfaces_apply() { # surfaces_apply <proposal-file> — the SECOND sanctioned writer of ops/SURFACES.tsv
  # (test-surfaces.md v2 § 14 · § 16; the first is `done`). Seeds the header when the file is
  # absent, appends every ROW of the proposal as `<surface><TAB><tests><TAB><cmd><TAB><note> [scaffold]`
  # by shell redirect — the RULES path guard sees Edit/Write tools and feat-branch diffs, never
  # this, and still denies every hand edit — then test_select: in CONVENTIONS.md, ONLY where the
  # repo never set it: a LIVE line (any value, even empty) is the human's and is kept; a
  # `# test_select:` stub (adopt's "known and deliberately unset") is replaced in place; neither ⇒
  # the line is appended at the end after one blank line. Temp file + mv, LF kept, never sed -i.
  # Says exactly what it wrote and commits nothing: rows a human never sees written are rows nobody
  # checks, and D6 makes an unchecked row the one thing this file must not hold. rc 0.
  local prop="${1:-}" kind surface tests cmd rest tpl="" n=0 ts="" tmp line
  surfaces_seed
  while IFS="$POLARIS_TAB" read -r kind surface tests cmd rest; do
    case "$kind" in
      RUNNER) tpl="$tests";;
      ROW)    printf '%s\n' "$surface$POLARIS_TAB$tests$POLARIS_TAB$cmd$POLARIS_TAB$rest [scaffold]" >> "$SURFACES"
              n=$((n + 1));;
    esac
  done < "$prop"
  if grep -q '^test_select:' "$CONV" 2>/dev/null; then
    ts="kept (already set here)"
  else
    line="test_select: $tpl   # set by surfaces --scaffold --apply: {tests} = the changed rows' tests globs; delete this line to run the whole test: suite on every change"
    tmp="$(mktemp)"
    if grep -qE '^#[[:space:]]*test_select:' "$CONV" 2>/dev/null; then
      awk -v rep="$line" 'BEGIN { hit = 0 } !hit && /^#[ \t]*test_select:/ { print rep; hit = 1; next } { print }' "$CONV" > "$tmp"
    else
      { cat "$CONV"; printf '\n%s\n' "$line"; } > "$tmp"
    fi
    mv "$tmp" "$CONV"
    ts=set
  fi
  say "$n row(s) written to ops/SURFACES.tsv · test_select: $ts"
  note "review, then commit ops/SURFACES.tsv ops/CONVENTIONS.md — nothing was committed for you"
  return 0
}

scaffold_try() { # scaffold_try <name> <cmd-body> — write the pair, but ONLY if it is worth locking.
  # Four refusals, each one a golden that would have been worse than no golden at all:
  #   exists  — never clobber a reviewed pair; --update is the deliberate way to redo one
  #   flappy  — output or rc differed across two back-to-back runs (timestamps, ordering, paths)
  #   empty   — an empty golden asserts nothing and goes green forever
  #   dead    — rc 127/126: the command isn't installed here, so the lock would be fiction
  #   huge    — rc 4 to the CALLER, which may then lock a coarser view of the same thing.
  #             Measured on a 3,000-file repo: one `--api src/*` golden is 75,001 lines / 2.9 MB.
  #             A golden nobody can read in a diff is a golden nobody maintains.
  # $3 = max lines (default 2000). Explicit argument, NOT a `VAR=x scaffold_try` prefix: the prefix
  # form silently failed to reach the function across a line-continued call, capping a 3,000-line
  # fallback at 2,000 and swallowing the whole scaffold.
  local name="$1" body="$2" cap="${3:-2000}" dir="$OPS/tests" a b arc brc lines
  [ -f "$dir/$name.cmd" ] && { SC_SKIP=$((SC_SKIP+1)); return 0; }
  if a="$( cd "$PRIMARY" && bash -c "$body" 2>/dev/null )"; then arc=0; else arc=$?; fi
  if b="$( cd "$PRIMARY" && bash -c "$body" 2>/dev/null )"; then brc=0; else brc=$?; fi
  { [ "$arc" -eq 127 ] || [ "$arc" -eq 126 ]; } && { SC_DEAD=$((SC_DEAD+1)); return 0; }
  { [ "$a" = "$b" ] && [ "$arc" = "$brc" ]; } || { SC_FLAP=$((SC_FLAP+1)); return 0; }
  [ -n "$a" ] || { SC_EMPTY=$((SC_EMPTY+1)); return 0; }
  lines="$(printf '%s\n' "$a" | wc -l)"
  [ "$lines" -gt "$cap" ] && { SC_HUGE=$((SC_HUGE+1)); return 4; }
  # Already asserted by an existing golden under another name? Two goldens with byte-identical
  # output test one thing twice and double the cost of every real change. Seen for real: a
  # generated `board-fm-cols` that duplicated the hand-written `board-fm-shape` exactly.
  local e
  for e in "$dir"/*.expected; do
    [ -e "$e" ] || break
    if printf '%s\n' "$a" | diff -q - "$e" >/dev/null 2>&1; then
      SC_DUP=$((SC_DUP+1)); note "skipped $name — same output as $(basename "$e" .expected)"; return 0
    fi
  done
  printf '%s\n' "$body" > "$dir/$name.cmd"
  printf '%s\n' "$a"    > "$dir/$name.expected"
  [ "$arc" != "0" ] && printf '%s\n' "$arc" > "$dir/$name.rc"
  SC_MADE=$((SC_MADE+1)); say "golden: $name"
  return 0
}

scaffold_dirs() { # top-level directories carrying a real public surface, newline-separated.
  # Derived from the INDEX, so it needs no config and works on a repo it has never seen.
  # The exclusions are all one idea: NEVER lock a tree whose whole job is to change without us.
  #   vendored/built  node_modules vendor dist build out target coverage — someone else's code
  #   ops · kit/ops   POLARIS's own INSTALLED copy. Locking it reds on every `polaris update`,
  #                   which is the workflow, not a regression — the golden would assert the
  #                   opposite of what is supposed to happen. (prefs.md excludes it for the
  #                   same reason.) Seen for real: a 571-line api-ops golden on this repo.
  #   docs            `seal` writes a sprint report here every wave — reds by construction.
  #   .github         CI config, human-owned and RULES-guarded; an agent cannot fix a red here.
  #   archive         dead code kept on purpose.
  "$SELF" find --api '*' 2>/dev/null \
    | awk -F'\t' '{ i=index($1,"/"); if (i>1) print substr($1,1,i-1) }' \
    | sort | uniq -c | sort -rn \
    | awk '$1 >= 5 {print $2}' \
    | grep -Ev '^(node_modules|vendor|dist|build|out|target|\.git|\.github|archive|coverage|ops|docs)$' || true
}

# ------------------------------------------------------------------ harness (5.21.0)
# ops/contracts/app-harness.md — the BEHAVIOUR tier above `check --scaffold --app`.
#
# `--scaffold --app` locks an app's SHAPE by reading files: routes declared, deps declared, env
# names referenced. It never runs anything, so it cannot tell you the app still BOOTS.
# `harness` writes the one script that does — generated once, run forever for a subprocess and
# zero tokens. It is the mechanical answer to the most expensive habit in this protocol: a model
# re-checking every route, import and entry point by hand, every wave.
#
# Three sweeps, chosen because each is (a) generatable without knowing the app and (b) catches a
# class of failure that otherwise reaches a human:
#   IMPORT  every module imports cleanly            — syntax errors, bad/circular imports, missing deps
#   ROUTE   every discovered route answers non-5xx  — the app boots and its surface responds
#   ENTRY   every console entry runs --help         — the thing users actually type still starts
# Plus a BASELINE: the route and module inventory captured on the first green run, so a route or
# module that DISAPPEARS is a failure too. That is the "expected output" half — a regression lock,
# reviewed once by a human, then free.
#
# Honesty rules baked into the generated file: a sweep that cannot find what it needs SKIPS with a
# printed reason. It never invents an app object, never guesses a factory's arguments, and never
# passes by asserting nothing. A harness that goes green because it tested nothing is worse than
# no harness, because it also removes the human's suspicion.

harness_testdir() { # where this repo already puts tests — never impose tests/ on a repo with a
  # convention. brain/prefs.md detects this by counting; fall back to the commonest layout.
  local d
  for d in tests test spec __tests__; do
    [ -d "$PRIMARY/$d" ] && { printf '%s' "$d"; return 0; }
  done
  printf 'tests'
}

harness_stack() { # python | node | none — from tracked files, never from a guess
  local ls; ls="$(git -C "$PRIMARY" ls-files 2>/dev/null)"
  case "$ls" in *pyproject.toml*|*requirements.txt*|*setup.py*) printf 'python'; return 0;; esac
  case "$ls" in *package.json*) printf 'node'; return 0;; esac
  printf '%s\n' "$ls" | grep -q '\.py$'  && { printf 'python'; return 0; }
  printf '%s\n' "$ls" | grep -qE '\.[cm]?js$' && { printf 'node'; return 0; }
  printf 'none'
}

harness_write_python() { # emit the pytest harness. Quoted heredoc: nothing here is expanded by the
  # shell, so the generated file is exactly what is written below.
  cat <<'PYEOF'
"""POLARIS app harness — GENERATED by `ops/polaris harness`. Regenerate, do not hand-edit.

Three sweeps and a baseline. Every one of them is mechanical: this file exists so that proving
"the app still works" costs a subprocess instead of an agent walking the app by hand every wave.

    pytest tests/test_polaris_harness.py -q

A sweep that cannot find what it needs SKIPS and says why. It never passes by asserting nothing.
Accept a legitimate change with:  ops/polaris harness --refresh
"""
import importlib, json, os, pathlib, pkgutil, subprocess, sys
import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = ROOT / ".polaris" / "harness-baseline.json"
SKIP_DIRS = {".git", ".polaris", "node_modules", "venv", ".venv", "env", "build", "dist",
             "__pycache__", "ops", "kit", "archive", ".tox", "site-packages", "migrations"}

sys.path.insert(0, str(ROOT))


def _baseline():
    if BASELINE.exists():
        try:
            return json.loads(BASELINE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def _modules():
    """Every importable module path in the repo, as dotted names."""
    out = []
    for p in sorted(ROOT.rglob("*.py")):
        rel = p.relative_to(ROOT)
        if any(part in SKIP_DIRS or part.startswith(".") for part in rel.parts[:-1]):
            continue
        if rel.name.startswith((".", "test_", "conftest")) or rel.name.endswith("_test.py"):
            continue
        parts = list(rel.parts[:-1]) + [rel.stem]
        if parts[-1] == "__init__":
            parts = parts[:-1]
        if parts:
            out.append(".".join(parts))
    return sorted(set(out))


def _find_app():
    """Locate a WSGI/ASGI application without guessing at constructor arguments.

    Only zero-argument factories are called. A factory that needs a config object is one we
    cannot supply correctly, and calling it with invented arguments would either crash (a false
    red) or build an app unlike the real one (a false green). Both are worse than a skip.
    """
    import inspect
    candidates = ("app", "application", "api", "server")
    for modname in _modules():
        if not any(k in modname.lower() for k in ("app", "main", "server", "api", "wsgi", "asgi")):
            continue
        try:
            mod = importlib.import_module(modname)
        except Exception:
            continue
        for attr in candidates:
            obj = getattr(mod, attr, None)
            if obj is not None and (hasattr(obj, "url_map") or hasattr(obj, "routes")):
                return obj, f"{modname}.{attr}"
        for fname in ("create_app", "make_app", "get_app"):
            f = getattr(mod, fname, None)
            if not callable(f):
                continue
            try:
                if inspect.signature(f).parameters:
                    continue           # needs config we do not have — skip, never invent
                obj = f()
            except Exception:
                continue
            if hasattr(obj, "url_map") or hasattr(obj, "routes"):
                return obj, f"{modname}.{fname}()"
    return None, None


def _routes(app):
    """(rule, methods) for Flask/Werkzeug or FastAPI/Starlette. GET/HEAD only downstream."""
    out = []
    if hasattr(app, "url_map"):
        for r in app.url_map.iter_rules():
            if r.endpoint == "static":
                continue
            out.append((str(r.rule), sorted(r.methods - {"HEAD", "OPTIONS"})))
    elif hasattr(app, "routes"):
        for r in app.routes:
            path = getattr(r, "path", None)
            if path:
                out.append((str(path), sorted(getattr(r, "methods", ["GET"]) or ["GET"])))
    return sorted(out)


def _client(app):
    if hasattr(app, "test_client"):
        return app.test_client(), "flask"
    try:
        from fastapi.testclient import TestClient
        return TestClient(app), "starlette"
    except Exception:
        try:
            from starlette.testclient import TestClient
            return TestClient(app), "starlette"
        except Exception:
            return None, None


# ---------------------------------------------------------------- SWEEP 1: imports
@pytest.mark.parametrize("modname", _modules() or ["<none>"])
def test_module_imports(modname):
    """Catches syntax errors, bad imports and circular imports across the whole app at once."""
    if modname == "<none>":
        pytest.skip("no importable modules found under the repo root")
    try:
        importlib.import_module(modname)
    except Exception as exc:
        pytest.fail(f"{modname} does not import: {type(exc).__name__}: {exc}")


# ---------------------------------------------------------------- SWEEP 2: routes
def test_every_route_answers():
    """Every GET route returns < 500. A 4xx is a valid answer; a 5xx is the app falling over."""
    app, where = _find_app()
    if app is None:
        pytest.skip("no zero-argument app factory or app object found — routes not swept")
    client, kind = _client(app)
    if client is None:
        pytest.skip(f"found {where} but no usable test client (install flask or fastapi extras)")

    broken = []
    for rule, methods in _routes(app):
        if "GET" not in methods or "<" in rule or "{" in rule:
            continue          # parameterised routes need fixtures we cannot invent
        try:
            resp = client.get(rule)
            code = getattr(resp, "status_code", 0)
            if code >= 500:
                broken.append(f"{rule} -> {code}")
        except Exception as exc:
            broken.append(f"{rule} -> raised {type(exc).__name__}: {exc}")
    assert not broken, "routes returning 5xx or raising:\n  " + "\n  ".join(broken)


# ---------------------------------------------------------------- SWEEP 3: entry points
def test_entry_points_start():
    """Whatever a user actually types must still start. --help only: never runs the real thing."""
    entries = []
    pp = ROOT / "pyproject.toml"
    if pp.exists():
        txt = pp.read_text(encoding="utf-8", errors="replace")
        in_scripts = False
        for line in txt.splitlines():
            s = line.strip()
            if s.startswith("["):
                in_scripts = "scripts" in s
                continue
            if in_scripts and "=" in s and not s.startswith("#"):
                entries.append(s.split("=")[0].strip().strip('"').strip("'"))
    if not entries:
        pytest.skip("no console entry points declared in pyproject.toml")

    env = dict(os.environ, POLARIS_HARNESS="1")
    broken = []
    for e in entries:
        try:
            r = subprocess.run([e, "--help"], capture_output=True, timeout=30, cwd=ROOT, env=env)
            if r.returncode != 0 and b"Traceback" in (r.stderr or b""):
                broken.append(f"{e} --help crashed: {(r.stderr or b'').decode(errors='replace')[:200]}")
        except FileNotFoundError:
            pass          # not installed in this environment; that is not an app defect
        except subprocess.TimeoutExpired:
            broken.append(f"{e} --help hung for 30s")
    assert not broken, "entry points failing:\n  " + "\n  ".join(broken)


# ---------------------------------------------------------------- BASELINE: nothing vanished
def test_nothing_disappeared():
    """A route or module that VANISHES is a regression the sweeps above cannot see: they only
    check what exists now. This is the recorded-expectations half — `harness --refresh` accepts
    a deliberate removal, which makes accepting one a visible, reviewable act."""
    base = _baseline()
    if not base:
        pytest.skip("no baseline yet — run: ops/polaris harness --refresh")
    now_mods = set(_modules())
    gone = sorted(set(base.get("modules", [])) - now_mods)
    app, _ = _find_app()
    detail = [f"module gone: {m}" for m in gone]
    if app is not None:
        now_routes = {r for r, _m in _routes(app)}
        detail += [f"route gone: {r}" for r in sorted(set(base.get("routes", [])) - now_routes)]
    assert not detail, ("the app lost surface it used to have:\n  " + "\n  ".join(detail)
                        + "\n\nDeliberate? accept it: ops/polaris harness --refresh")
PYEOF
}

harness_write_node() { # emit the node:test harness — same three sweeps, same honesty rules.
  cat <<'JSEOF'
// POLARIS app harness — GENERATED by `ops/polaris harness`. Regenerate, do not hand-edit.
//
// Three sweeps and a baseline, all mechanical. This file exists so that proving "the app still
// works" costs a subprocess instead of an agent clicking through it every wave.
//
//     node --test <thisfile>
//
// A sweep that cannot find what it needs SKIPS and says why — it never passes by asserting nothing.
// Accept a legitimate change with:  ops/polaris harness --refresh
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const BASELINE = path.join(ROOT, '.polaris', 'harness-baseline.json');
const SKIP = new Set(['node_modules', '.git', '.polaris', 'dist', 'build', 'out', 'coverage',
                      'ops', 'kit', 'archive', '__tests__', 'tests', 'test']);

function sources(dir = ROOT, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.') || SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) sources(p, acc);
    else if (/\.(js|cjs|mjs)$/.test(e.name) && !/\.(test|spec)\./.test(e.name)) acc.push(p);
  }
  return acc;
}

function baseline() {
  try { return JSON.parse(fs.readFileSync(BASELINE, 'utf8')); } catch { return null; }
}

// ------------------------------------------------------------ SWEEP 1: every module loads
test('every module loads', () => {
  const broken = [];
  for (const f of sources()) {
    try { require(f); }
    catch (err) {
      // A module that legitimately refuses to load without config is not a syntax error.
      if (err && (err.code === 'ERR_REQUIRE_ESM' || err.code === 'MODULE_NOT_FOUND')) continue;
      broken.push(`${path.relative(ROOT, f)}: ${err && err.message}`);
    }
  }
  assert.deepStrictEqual(broken, [], `modules that do not load:\n  ${broken.join('\n  ')}`);
});

// ------------------------------------------------------------ SWEEP 2: package scripts exist
test('declared npm scripts still exist', () => {
  const pj = path.join(ROOT, 'package.json');
  if (!fs.existsSync(pj)) return;                       // nothing declared, nothing to lose
  const base = baseline();
  if (!base || !base.scripts) { console.log('  skip: no baseline — ops/polaris harness --refresh'); return; }
  const now = Object.keys(JSON.parse(fs.readFileSync(pj, 'utf8')).scripts || {});
  const gone = base.scripts.filter((s) => !now.includes(s));
  assert.deepStrictEqual(gone, [], `npm scripts removed: ${gone.join(', ')}`);
});

// ------------------------------------------------------------ SWEEP 3: the CLI still starts
test('bin entries run --help without crashing', () => {
  const pj = path.join(ROOT, 'package.json');
  if (!fs.existsSync(pj)) return;
  const bin = JSON.parse(fs.readFileSync(pj, 'utf8')).bin || {};
  const entries = typeof bin === 'string' ? [bin] : Object.values(bin);
  if (!entries.length) { console.log('  skip: no bin entries declared'); return; }
  const broken = [];
  for (const e of entries) {
    const p = path.join(ROOT, e);
    if (!fs.existsSync(p)) { broken.push(`${e}: declared in package.json but missing on disk`); continue; }
    try { execFileSync(process.execPath, [p, '--help'], { timeout: 30000, stdio: 'pipe', cwd: ROOT }); }
    catch (err) {
      if (err.status !== 0 && /Error|Exception/.test(String(err.stderr || ''))) {
        broken.push(`${e} --help crashed: ${String(err.stderr).slice(0, 200)}`);
      }
    }
  }
  assert.deepStrictEqual(broken, [], `entry points failing:\n  ${broken.join('\n  ')}`);
});

// ------------------------------------------------------------ BASELINE: nothing vanished
test('nothing disappeared', () => {
  const base = baseline();
  if (!base) { console.log('  skip: no baseline — ops/polaris harness --refresh'); return; }
  const now = sources().map((f) => path.relative(ROOT, f).split(path.sep).join('/'));
  const gone = (base.modules || []).filter((m) => !now.includes(m));
  assert.deepStrictEqual(gone, [],
    `the app lost files it used to have:\n  ${gone.join('\n  ')}\n\nDeliberate? ops/polaris harness --refresh`);
});
JSEOF
}

harness_baseline() { # capture the inventory the "nothing disappeared" test diffs against.
  # Written by the CLI, not by the harness itself: a suite that rewrites its own expectations on
  # every run cannot fail, and that is the failure mode this whole tier exists to avoid.
  local stack="$1" out="$PRIMARY/.polaris/harness-baseline.json" rel="${2:-}" py=""
  mkdir -p "$PRIMARY/.polaris"
  if [ "$stack" = python ]; then
    # Ask the GENERATED harness for the inventory rather than re-deriving it here. Two copies of
    # "what counts as a module" drift, and the day they disagree the baseline test either fires on
    # nothing or fires forever. This also fills `routes`, which a pure file-listing cannot know —
    # routes only exist once the app is imported. No python (or an app that will not import) →
    # fall through to the module list alone, so the baseline degrades instead of failing.
    python3 -c pass >/dev/null 2>&1 && py=python3 || { python -c pass >/dev/null 2>&1 && py=python; }
    if [ -n "$py" ] && [ -n "$rel" ] && [ -f "$PRIMARY/$rel" ]; then
      ( cd "$PRIMARY" && "$py" - "$rel" <<'PY' > "$out" 2>/dev/null
import importlib.util, json, sys, pathlib
spec = importlib.util.spec_from_file_location("_ph", pathlib.Path(sys.argv[1]).resolve())
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
    mods = mod._modules()
    app, _ = mod._find_app()
    routes = sorted({r for r, _m in mod._routes(app)}) if app is not None else []
except Exception:
    raise SystemExit(1)
json.dump({"modules": mods, "routes": routes}, sys.stdout, indent=2)
PY
      ) && [ -s "$out" ] && { printf '%s' "$out"; return 0; }
    fi
    git -C "$PRIMARY" ls-files '*.py' 2>/dev/null | awk '
      BEGIN { print "{\n  \"modules\": [" }
      { gsub(/\.py$/,""); gsub(/\//,"."); sub(/\.__init__$/,"")
        if ($0 ~ /^(ops|kit|archive|tests?|test)\./ || $0 ~ /(^|\.)test_/) next
        printf "%s    \"%s\"", (n++ ? ",\n" : ""), $0 }
      END { print "\n  ],\n  \"routes\": []\n}" }' > "$out"
  else
    # package.json is parsed by NODE, not by awk. The awk version keyed on `"scripts":` starting a
    # line and `}` ending one, so it silently produced an empty list for the extremely common
    # single-line form `"scripts": { "start": "...", "build": "..." },` — and an empty baseline
    # asserts nothing while looking exactly like a passing one. Never hand-roll a JSON parser for a
    # file the runtime you are already targeting can read correctly.
    local scripts="[]"
    if [ -f "$PRIMARY/package.json" ] && command -v node >/dev/null 2>&1; then
      scripts="$(node -e 'try{const p=require(process.argv[1]);process.stdout.write(JSON.stringify(Object.keys(p.scripts||{})))}catch(e){process.stdout.write("[]")}' \
                 "$PRIMARY/package.json" 2>/dev/null)" || scripts="[]"
      [ -n "$scripts" ] || scripts="[]"
    fi
    { printf '{\n  "modules": [\n'
      git -C "$PRIMARY" ls-files '*.js' '*.cjs' '*.mjs' 2>/dev/null \
        | grep -Ev '^(node_modules|ops|kit|archive|dist|build|coverage)/' \
        | grep -Ev '\.(test|spec)\.' \
        | awk '{ printf "%s    \"%s\"", (n++ ? ",\n" : ""), $0 } END{ print "" }'
      printf '  ],\n  "scripts": %s\n}\n' "$scripts"
    } > "$out"
  fi
  printf '%s' "$out"
}

cmd_harness() { # harness [--refresh] — generate ONE runnable suite for the HOST app.
  local refresh=0 stack td file rel base
  case "${1:-}" in
    '') ;;
    --refresh) refresh=1;;
    *) die "usage: polaris harness [--refresh]";;
  esac

  stack="$(harness_stack)"
  [ "$stack" = none ] && die "cannot tell what this app is built with (no pyproject/requirements/package.json, no .py or .js).
   For a CLI or a shell tool, the right tier is golden output: ops/polaris check --scaffold --app"

  td="$(harness_testdir)"
  mkdir -p "$PRIMARY/$td" || die "cannot create $td/"
  if [ "$stack" = python ]; then rel="$td/test_polaris_harness.py"; else rel="$td/polaris-harness.test.js"; fi
  file="$PRIMARY/$rel"

  if [ -f "$file" ] && [ "$refresh" -eq 0 ]; then
    note "$rel already exists — left as is (it may have been edited on purpose)"
    note "re-generate it and re-capture expectations with: ops/polaris harness --refresh"
  else
    if [ "$stack" = python ]; then harness_write_python > "$file"; else harness_write_node > "$file"; fi
    say "wrote $rel  ($stack)"
  fi

  base="$(harness_baseline "$stack" "$rel")"
  say "captured baseline: .polaris/harness-baseline.json"

  # The point of the whole tier, said once where someone will read it.
  printf '\n'
  note "This suite is MECHANICAL: it costs a subprocess and zero tokens, every run, forever."
  note "Run it:"
  if [ "$stack" = python ]; then
    note "  pytest $rel -q"
    note "Wire it into qa (ops/CONVENTIONS.md), so it rides the gate that already exists:"
    note "  uat: pytest $rel -q"
  else
    note "  node --test $rel"
    note "Wire it into qa (ops/CONVENTIONS.md), so it rides the gate that already exists:"
    note "  uat: node --test $rel"
  fi
  note ""
  note "A sweep that cannot find what it needs SKIPS and says why — read the skips once. Anything"
  note "it skips is a place a golden pair still earns its keep: ops/polaris check --scaffold --app"
  return 0
}

cmd_scaffold() { # check --scaffold [--cmd "<shell>"] — GENERATE goldens from observed behavior.
  # These are REGRESSION LOCKS, not correctness proofs: they assert "this still does what it did
  # the day we looked", which is exactly the class of check that never needed a model. A human or
  # Builder reviews them once; from then on every run costs a subprocess instead of a subagent.
  #
  # Auto-generated sources are limited to ones that are provably READ-ONLY — the index and this
  # CLI's own reporting commands. Scaffold does NOT go hunting for executables in bin/ to run with
  # --help: on a real app that is how you start a server or mutate a database during a test-writing
  # pass. Behavioural goldens for an app's own commands are opt-in, one at a time, via --cmd.
  local extra="" app=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cmd) extra="${2:?--cmd needs a shell command}"; shift 2;;
      --app) app=1; shift;;
      *) die "usage: polaris check --scaffold [--app] [--cmd \"<shell command>\"]";;
    esac
  done
  local dir="$OPS/tests" d slug
  mkdir -p "$dir"
  SC_MADE=0; SC_SKIP=0; SC_FLAP=0; SC_EMPTY=0; SC_DEAD=0; SC_HUGE=0; SC_DUP=0
  if [ "$app" -eq 1 ]; then
    # --app: lock the HOST application's shape, not POLARIS's. The default scaffold locks the code
    # index and this CLI; a user's repo also has a manifest, routes, migrations and a config
    # surface, and those are where "someone changed something nobody meant to change" actually
    # shows up. Each golden below is pure TEXT EXTRACTION over tracked files — nothing here runs
    # the app, imports its modules, opens a port or touches a database, for the same reason the
    # default scaffold refuses to go hunting for executables to run with --help.
    #
    # These answer the ask directly: instead of an agent re-reading routes and re-checking deps
    # every wave, `polaris check` re-proves all of it for the price of a subprocess.
    if [ -f "$PRIMARY/package.json" ]; then
      # Parsed by node, not by a sed line-range: `/"scripts"/,/}/` runs past the closing brace on
      # any compact package.json and swallows the next block whole (observed: the scripts golden
      # captured `express` and `zod`). node only READS the manifest here — no install, no script
      # run. A repo with a package.json and no node is rare, and when it happens scaffold_try
      # simply records the candidate as dead and skips it, which is the honest outcome.
      # Invariant 8 says no new dependencies without asking; app-deps-npm is that rule as a diff.
      scaffold_try "app-deps-npm" \
        "node -e \"p=require('./package.json');console.log(Object.keys(p.dependencies||{}).sort().join('\\n'))\"" || true
      # Script NAMES only — never their bodies, and never running them.
      scaffold_try "app-scripts-npm" \
        "node -e \"p=require('./package.json');console.log(Object.keys(p.scripts||{}).sort().join('\\n'))\"" || true
    fi
    if [ -f "$PRIMARY/requirements.txt" ]; then
      scaffold_try "app-deps-python" \
        "grep -oE '^[A-Za-z0-9_.-]+' requirements.txt | sort -u" || true
    fi
    if [ -f "$PRIMARY/pyproject.toml" ]; then
      scaffold_try "app-deps-pyproject" \
        "sed -n '/^\\[project\\]/,/^\\[/p;/dependencies *= *\\[/,/\\]/p' pyproject.toml | grep -oE '\"[A-Za-z0-9_.-]+' | tr -d '\"' | sort -u" || true
    fi
    # HTTP surface. One line per registered route across the common frameworks — a deleted,
    # renamed or newly exposed endpoint reds. Deliberately matches the DECLARATION text, so it
    # needs no server and no framework knowledge at run time.
    scaffold_try "app-routes" \
      "git ls-files | grep -E '\\.(py|js|jsx|mjs|ts|tsx|go|rb|php|java|kt|cs)\$' | tr '\\n' '\\0' | xargs -0 grep -hoE '(@(app|router|bp|blueprint)\\.(route|get|post|put|patch|delete)|(app|router|r|mux)\\.(Get|Post|Put|Patch|Delete|get|post|put|patch|delete))\\([^,)]+' 2>/dev/null | sed 's/[[:space:]]*\$//' | sort -u" || true
    # Schema surface: the migration set, by name. A migration appearing or vanishing is exactly the
    # STOP-AND-ASK class of change, and this makes it mechanically visible.
    scaffold_try "app-migrations" \
      "git ls-files | grep -Ei '(^|/)(migrations?|alembic/versions|db/migrate)/' | sort" || true
    # Config surface: env var NAMES referenced in source. NAMES ONLY — no values are read, printed
    # or stored, so this can never put a secret in a golden (Invariant 10).
    scaffold_try "app-env-names" \
      "git ls-files | grep -E '\\.(py|js|jsx|mjs|ts|tsx|go|rb|php|java|kt|cs|sh)\$' | tr '\\n' '\\0' | xargs -0 grep -hoE '(process\\.env\\.[A-Z0-9_]+|os\\.environ\\[[^]]+\\]|os\\.getenv\\([^,)]+|ENV\\[[^]]+\\])' 2>/dev/null | grep -oE '[A-Z][A-Z0-9_]{2,}' | sort -u" || true
  elif [ -n "$extra" ]; then
    scaffold_try "cmd-$(printf '%s' "$extra" | tr -cs 'a-zA-Z0-9' '-' | sed 's/^-*//;s/-*$//' | cut -c1-40)" "$extra"
  else
    # 1. public API surface — one golden per top-level source dir. The generic lock: a renamed,
    #    deleted or relocated public symbol reds instantly, on any repo, in any language we index.
    #    Too big to be readable (rc 4) → fall back to one line per FILE with its symbol count. That
    #    still reds on a deleted file, a new file, or symbols appearing/vanishing from one; it gives
    #    up only same-file renames. A bounded lock that survives is worth more than a 2.9 MB one
    #    that gets deleted the first time someone opens the diff.
    for d in $(scaffold_dirs); do
      slug="$(printf '%s' "$d" | tr -cs 'a-zA-Z0-9' '-')"
      # An `if` (not a || chain): scaffold_try's rc 4 is a routing signal, and as the last command
      # of an OR-list a second rc 4 would trip `set -e` and abort the whole scaffold silently.
      if scaffold_try "api-$slug" "bash ops/polaris find --api '$d/*'"; then :; elif [ $? -eq 4 ]; then
        # One line per FILE with its symbol count — bounded by file count, not symbol count, so it
        # holds where the full surface cannot. Its own higher cap: past ~5k files in ONE top-level
        # directory, per-directory locking is the wrong tool and saying nothing beats saying 1.7 MB.
        scaffold_try "api-$slug-counts" \
          "bash ops/polaris find --api '$d/*' | awk -F'\\t' '{c[\$1]++} END{for(p in c) print p\"\\t\"c[p]}' | sort" \
          5000 || true
      fi
    done
    # 2. this CLI's own contract surfaces — read-only reporting commands whose SHAPE agents parse.
    scaffold_try "cli-help"      "bash ops/polaris help"
    scaffold_try "board-fm-cols" "bash ops/polaris board-fm | head -1"
    scaffold_try "rules-health"  "bash ops/polaris rules | tail -1"
  fi
  printf '\n'
  say "scaffold: $SC_MADE written · $SC_SKIP already existed · $SC_FLAP non-deterministic · $SC_EMPTY empty · $SC_DEAD command missing · $SC_DUP duplicate · $SC_HUGE too large (locked coarser instead)"
  [ "$SC_MADE" -eq 0 ] && { note "nothing new to lock"; return 0; }
  note "REVIEW THESE before committing: $dir — a golden records what the code DOES, not what it SHOULD do."
  note "A wrong behaviour captured here becomes a wrong behaviour defended forever. Then: polaris check"
  return 0
}

cmd_check() { # check [--only <glob>] [--update] [--scaffold] — golden-output acceptance tests, ZERO LLM.
  # ops/tests/<name>.cmd       one or more shell lines, run from the repo root
  # ops/tests/<name>.expected  the golden stdout  (stderr is NOT captured — it is noisy and
  #                            makes goldens flap; assert on stdout, or redirect inside the .cmd)
  # ops/tests/<name>.rc        optional expected exit code, default 0
  # Run it, diff it, done. This is what replaces an agent re-checking every widget/route by hand
  # on every wave: the Builder writes the pair ONCE while it already has the context, and every
  # run afterwards costs a subprocess instead of a subagent.
  # --update rewrites goldens from actual output — ALWAYS a human/Builder decision, never automatic,
  # because a golden that regenerates itself asserts nothing.
  # --scaffold GENERATES the pairs instead of running them; it is a different verb behind one noun
  # on purpose ("the goldens" are one concept), and it must be the first flag so a mistyped
  # `--scaffold --update` can never be read as a request to overwrite every reviewed golden.
  [ "${1:-}" = "--scaffold" ] && { shift; cmd_scaffold "$@"; return $?; }
  local only="*" upd=0 named=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --only) only="${2:?--only needs a glob}"; named=1; shift 2;;
      --update) upd=1; shift;;
      *) die "usage: polaris check [--only <glob>] [--update] | check --scaffold [--app] [--cmd \"<shell>\"]";;
    esac
  done
  # WHICH tree (speed.md § 3): run from inside a builder's worktree, check tests THAT worktree —
  # its ops/tests, run from its root. Anchored to the primary it proved the base instead, and a
  # golden that exists only on the branch printed "no goldens matched" and passed having run
  # nothing. The case test is the entry point's own beat test; anywhere else, unchanged.
  local root="$PRIMARY" wt
  case "$PWD" in */.polaris/wt/*) wt="${PWD##*/.polaris/wt/}"; wt="${wt%%/*}"
    [ -n "$wt" ] && [ -d "$PRIMARY/.polaris/wt/$wt" ] && root="$PRIMARY/.polaris/wt/$wt";; esac
  local dir="$root/ops/tests" f name exp rcf want got grc red=0 n=0
  [ -d "$dir" ] || { note "no ops/tests/ yet — add <name>.cmd + <name>.expected (polaris check --update writes the golden)"; return 0; }
  for f in "$dir"/*.cmd; do
    [ -e "$f" ] || break
    name="${f##*/}"; name="${name%.cmd}"
    case "$name" in $only) ;; *) continue;; esac
    n=$((n+1)); exp="$dir/$name.expected"; rcf="$dir/$name.rc"
    got="$( cd "$root" && bash -c "$(cat "$f")" 2>/dev/null )"; grc=$?
    want=0; [ -f "$rcf" ] && want="$(tr -d ' \r\n' < "$rcf")"
    if [ "$upd" -eq 1 ]; then printf '%s\n' "$got" > "$exp"; say "updated golden: $name"; continue; fi
    if [ ! -f "$exp" ]; then printf '⛔ %s — no golden yet (polaris check --only %s --update)\n' "$name" "$name"; red=1; continue; fi
    if [ "$grc" != "$want" ]; then printf '⛔ %s — exit %s, expected %s\n' "$name" "$grc" "$want"; red=1; continue; fi
    if printf '%s\n' "$got" | diff -q - "$exp" >/dev/null 2>&1; then say "$name"
    else
      printf '⛔ %s — output differs:\n' "$name"
      printf '%s\n' "$got" | diff -u "$exp" - 2>/dev/null | sed -n '3,12p' | sed 's/^/     /'
      red=1
    fi
  done
  # A NAMED check that runs nothing is red: `--only <typo>` used to pass, proving nothing. A bare
  # check over an empty ops/tests/ stays rc 0 — there is simply nothing yet.
  [ "$n" -eq 0 ] && { note "no goldens matched '$only'"; [ "$named" -eq 1 ] && return 1; return 0; }
  [ "$red" -eq 0 ] || die "check: $n golden(s) run, at least one red"
  say "check: $n golden(s), all green"
}

cmd_triage() { # triage — print the LANE this board's work belongs in: solo | express | full.
  # The six conditions below were prose in CONDUCTOR.md, which meant a model re-derived them from
  # the board every run — reading task files, weighing points, re-reading CONVENTIONS — and paid
  # tokens to reach an answer the CLI already had. It is data, so it is a command.
  # Line 1 is the lane and nothing else, so a caller can branch on it without parsing.
  #   solo    one context does plan+build+integrate. No subagents at all.
  #   express conductor + ONE builder + ONE integrator, landing through `land --express`.
  #   full    the ordinary loop: planner, N builders, integrator, wave gate.
  local n=0 id="" f base pts risk owned p why="" lane=full k sum big
  for f in "$BOARD"/ready/*.md "$BOARD"/active/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"; [ "$base" = "IDEAS.md" ] && continue
    n=$((n + 1)); id="${base%.md}"
  done

  if [ "$n" -eq 0 ]; then
    printf 'full\n'; note "nothing claimable — the board is empty, so a Planner runs first"; return 0
  fi
  if [ "$n" -gt 1 ]; then
    # Several tasks price CONTEXTS, not tasks (test-surfaces.md § 8). A `full` wave for n tasks
    # opens n+3 cold starts — conductor, planner, n builders, integrator — of ~7,300 tokens EACH
    # before any work happens, while four 1-point tasks landed one after another in ONE solo
    # context pay for one. So small-and-few work stays solo, worked one task at a time, and the
    # note states the arithmetic it used so the lane is auditable rather than felt. Rules, in
    # order: a lane already building · any task failing its own gate (first offender, the
    # single-task wording) · the express/publish knobs · the solo budget (≤4 tasks, ≤3 pts each,
    # ≤6 pts in all) · otherwise full.
    k=0
    for f in "$BOARD"/active/*.md; do
      [ -e "$f" ] || continue
      [ "$(basename "$f")" = "IDEAS.md" ] && continue
      k=$((k + 1))
    done
    if [ "$k" -gt 0 ]; then
      printf 'full\n'; note "$k task(s) already active — another lane is building; parallel lanes are the point"; return 0
    fi
    sum=0; big=0
    for f in "$BOARD"/ready/*.md; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"; [ "$base" = "IDEAS.md" ] && continue
      id="${base%.md}"
      pts="$(fm_get points "$f")"; pts="${pts:-99}"
      risk="$(fm_get risk "$f")"; risk="${risk:-normal}"
      [ "$risk" = "normal" ] || why="risk: $risk (only a human may approve a merge)"
      case "$pts" in ''|*[!0-9]*) [ -z "$why" ] && why="points '$pts' is not a plain number";; esac
      if [ -z "$why" ]; then
        owned="$(fm_list files_owned "$f")"
        while IFS= read -r p; do
          [ -z "$p" ] && continue
          if rules_gate "$p" "$id"; then
            if [ "$RULES_GATE" = "path" ]; then why="owns '$p' under RULES path scope '$RULES_GATE_SCOPE' — cannot be built as specified"
            else why="owns '$p' under ask scope '$RULES_GATE_SCOPE' — get the human's yes before starting (polaris approve $id $RULES_GATE_SCOPE -m \"why\")"
            fi
            break
          fi
        done <<EOF
$owned
EOF
      fi
      if [ -n "$why" ]; then printf 'full\n'; note "$id: $why"; return 0; fi
      sum=$((sum + pts)); [ "$pts" -gt "$big" ] && big="$pts"
    done
    if [ "$(cfg express auto)" = "off" ]; then printf 'full\n'; note "express: off in CONVENTIONS.md"; return 0; fi
    if [ "$(cfg publish direct)" != "direct" ]; then printf 'full\n'; note "publish: pr — the wave needs a human merge"; return 0; fi
    if [ "$big" -le 3 ] && [ "$n" -le 4 ] && [ "$sum" -le 6 ]; then
      printf 'solo\n'
      note "$n tasks · $sum pts ≤ 6 — one context (~7,300 tokens cold start) beats a full wave's $((n + 3)) contexts (~$(( (n + 3) * 7300 )) tokens); work them one at a time: claim → build → land --express → next"
    else
      printf 'full\n'
      note "$n claimable tasks · $sum pts — over the solo budget (4 tasks / 6 pts / 3 pts each); parallel lanes are the point"
    fi
    return 0
  fi

  f="$(task_file "$id")" || { printf 'full\n'; note "cannot read task $id"; return 0; }
  pts="$(fm_get points "$f")"; pts="${pts:-99}"
  risk="$(fm_get risk "$f")"; risk="${risk:-normal}"

  [ "$risk" = "normal" ] || why="risk: $risk (only a human may approve a merge)"
  case "$pts" in ''|*[!0-9]*) [ -z "$why" ] && why="points '$pts' is not a plain number";; esac
  [ -z "$why" ] && [ "$(cfg express auto)" = "off" ] && why="express: off in CONVENTIONS.md"
  [ -z "$why" ] && [ "$(cfg publish direct)" != "direct" ] && why="publish: pr — the wave needs a human merge"
  # STOP-AND-ASK, mechanically — three cases, not one (ask-approval.md § 5):
  #   `path` scope       → full: the rule is a wall, no approval can lift it
  #   `ask`, no approval → full: get the human's yes at the plan gate, where asking is cheap
  #   `ask`, approved    → the question is settled — fall through to ordinary points routing
  if [ -z "$why" ]; then
    owned="$(fm_list files_owned "$f")"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if rules_gate "$p" "$id"; then
        if [ "$RULES_GATE" = "path" ]; then why="owns '$p' under RULES path scope '$RULES_GATE_SCOPE' — cannot be built as specified"
        else why="owns '$p' under ask scope '$RULES_GATE_SCOPE' — get the human's yes before starting (polaris approve $id $RULES_GATE_SCOPE -m \"why\")"
        fi
        break
      fi
    done <<EOF
$owned
EOF
  fi

  if [ -n "$why" ]; then
    printf 'full\n'; note "$id: $why"; return 0
  fi
  # SOLO threshold 2 → 3 (2026-07-26, assistant, owner-authorized in the 5.21.0 token-efficiency
  # plan). WHY: the gates were never the expense, the CONTEXTS were — a 3-point task in `express`
  # opens a conductor, a builder and an integrator, three cold starts of ~7,300 tokens of injected
  # skill definitions plus CLAUDE.md and a role file EACH, to land work one context finishes
  # comfortably. Nothing about the checks changes: SOLO still runs verify, the task's verify: list,
  # the full suite once at `land --express`, and qa. Points measure scope and merge risk, and this
  # repo's own calibration records that they do NOT predict wall clock (5pt p50 = 2pt p50 = 0.5h,
  # n=8, 0 kickbacks) — so a 3-pointer is not a longer job, it is a slightly wider one, and width
  # is exactly what a single context handles well. Revert to 2 if solo tasks start kicking back.
  if [ "$pts" -le 3 ]; then lane=solo; else lane=express; fi
  printf '%s\n' "$lane"
  note "$id: $pts point(s), risk normal, express on, publish direct"
  [ "$lane" = express ] && note "over 3 points — worth a fresh builder context, but still ONE task and ONE suite run"
  return 0
}

cmd_route() { # route [<ID>] [--role <ROLE>] [--points <N>] [--risk <R>] — which model TIER runs a
  # piece of work (ops/contracts/model-routing.md). triage answers "which lane"; this answers
  # "which model", with the same shape: line 1 is ALWAYS exactly one bare word — strong | mid |
  # cheap — so callers branch on it blind, and a `   model: <name>` note follows ONLY when the
  # winning tier's CONVENTIONS knob (model_strong/mid/cheap) is set, or the task pins a literal
  # model: name in frontmatter. Precedence: explicit --points/--risk (pure, board-free) → --role →
  # <ID>. Routing never blocks work — malformed points and unknown roles fall back to mid, rc 0;
  # only no-args and an unknown ID are errors. Read-only by contract: touches no lock, writes no
  # board file, fires no hook.
  local id="" role="" pts="" rsk="" pts_set="" rsk_set=""
  local tier="" mdl="" ov="" f="" rnote="" rdeny="" rraw=""
  local u="usage: polaris route <ID> | --role <ROLE> | --points <N> [--risk <R>]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --role)   role="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
      --points) pts_set=1; pts="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
      --risk)   rsk_set=1; rsk="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
      -*)       die "$u";;
      *)        if [ -z "$id" ]; then id="$1"; else die "$u"; fi; shift;;
    esac
  done
  if [ -n "$pts_set$rsk_set" ]; then
    # pure mode: board-free. A missing half defaults (--risk normal; --points empty → mid inside
    # tier_for), so a conductor can ask about work that has no task file yet.
    tier="$(tier_for "$pts" "${rsk:-normal}")"
  elif [ -n "$role" ] && [ "$role" != "BUILDER" ]; then
    case "$role" in
      INIT|PLANNER|INTEGRATOR|EVOLVE|CONDUCTOR) tier=strong;;
      SOLO|scout) tier=mid;;
      *) tier=mid; rnote="unknown role '$role' — mid (routing never blocks work)";;
    esac
  elif [ "$role" = "BUILDER" ] && [ -z "$id" ]; then
    tier=mid; rnote="BUILDER routes per task — bash ops/polaris route <ID>"
  elif [ -n "$id" ]; then
    f="$(task_file "$id" 2>/dev/null || true)"
    [ -n "$f" ] && [ -f "$f" ] || die "route: no task $id on the board — check: ops/polaris board-fm"
    tier="$(tier_for "$(fm_get points "$f")" "$(fm_get risk "$f")")"
    ov="$(fm_get model "$f" 2>/dev/null || true)"
    case "$ov" in
      strong|mid|cheap) tier="$ov";;                # tier-word override: that tier wins outright
      "") :;;
      *) mdl="$ov";;                                # literal model name — line 1 stays the derived
    esac                                            # tier (informational); the note carries it
  else
    die "$u"
  fi
  printf '%s\n' "$tier"
  # FORBIDDEN models are NEVER named (core.sh model_denied — owner, 2026-09-15: Fable and Haiku, in
  # any repo, on any machine). Two sources, both refused here: a task's literal `model:` is checked
  # directly, and a CONVENTIONS model_* value was already refused inside model_for_tier, which hands
  # the name back via MODEL_DENIED. Either way the `model:` note is WITHHELD — which is not a new
  # code path: the contract's existing rule is absent ⇒ the caller omits the spawn's model param and
  # the platform default runs. Line 1 is untouched, so every caller still branches on the bare tier.
  if model_denied "$mdl"; then rdeny="$mdl"; mdl=""; fi
  if [ -z "$mdl" ]; then
    mdl="$(model_for_tier "$tier")"
    # Nothing came back — either the knob is unset (ordinary) or it named a forbidden model and
    # model_for_tier withheld it. Those must read differently to a human, so re-read the raw key to
    # tell them apart. model_for_tier's MODEL_DENIED cannot be used here: it runs in a command
    # substitution, so the assignment happens in a SUBSHELL and never reaches this scope.
    if [ -z "$mdl" ]; then
      rraw="$(cfg "model_$tier" "")"
      model_denied "$rraw" && rdeny="$rraw"
    fi
  fi
  [ -n "$mdl" ] && note "model: $mdl"
  [ -n "$rdeny" ] && note "model REFUSED: '$rdeny' is forbidden (owner, 2026-09-15) — this spawn names no model and inherits the session's"
  [ -n "$rnote" ] && note "$rnote"
  return 0
}

cmd_qa() { # qa [--force] [--full] — ONE answer to "is everything okay?": the full CONVENTIONS suite
  # (test/lint/typecheck/build, uat if set), then drift --strict, then doctor's env check. Runs EVERY
  # check even after a red — one pass paints the whole picture — and exits 1 if anything was
  # red. The Conductor runs it after integration (a subagent's "green" is never taken on
  # faith), the Integrator runs it before reporting, CI and humans run it whenever.
  # --force ignores the suite stamp (no skip, and on $BASE no baseline either ⇒ the whole suite);
  # --full runs test: verbatim even where test_select: would have scoped it (test-surfaces.md § 6).
  local red=0 ran=0 k c out skip=0 force=0 full=0 a
  local t0 t1 head stamped dirty
  local scope=full carry=0 sel="" csf="" np=0 m=0 why="" p sc bsha c2 sred=0 fflag=""
  for a in "$@"; do
    case "$a" in --force) force=1;; --full) full=1;; esac
  done
  [ "$force" -eq 1 ] && fflag="--force"   # a 0/1 counter, so ${force:+…} would always be true

  # SUITE STAMP. A green suite is a fact about a COMMIT, not about a moment: if HEAD has not moved
  # and the tree is clean, re-running it cannot learn anything new. Measured here: test: 805s and
  # the whole qa loop 1225s — and the old flow paid it TWICE per change, because the integrator
  # ran the full suite inside `land --express` and then the conductor ran `qa` as its finish line
  # over the identical tree. That duplicate was the single largest block of wall-clock in a run.
  # Deliberately conservative: any uncommitted change, any HEAD move, or --force re-runs everything.
  # drift and doctor below are seconds and always run, so the board is still audited every time.
  head="$(git -C "$PRIMARY" rev-parse HEAD 2>/dev/null || echo none)"
  dirty="$(git -C "$PRIMARY" status --porcelain 2>/dev/null | head -1)"
  if [ "$force" -eq 0 ] && [ -z "$dirty" ] && [ -f "$PRIMARY/.polaris/suite-stamp" ]; then
    stamped="$(cut -d' ' -f1 < "$PRIMARY/.polaris/suite-stamp" 2>/dev/null || true)"
    [ -n "$stamped" ] && [ "$stamped" = "$head" ] && skip=1
  fi

  t0="$(date +%s)"
  out="$(mktemp)"
  if [ "$skip" -eq 1 ]; then
    sc="$(suite_stamp_scope "$PRIMARY/.polaris/suite-stamp" || true)"
    say "suite already green at $(printf '%.7s' "$head") — skipped, proven ${sc:-full} (qa --force re-runs it)"
  else
  for k in test lint typecheck build uat; do
    c="$(cfg "$k" "")"
    [ -z "$c" ] && continue
    # test — change-scoped selection (test-surfaces.md § 6), and ONLY when test_select: is set:
    # which of the ops/SURFACES.tsv commands can this change break? The decision itself lives in
    # core.sh (surface_change_set + surface_select_cmd) and is shared with `land --express`, so the
    # two lanes cannot disagree. Unset ⇒ this block is never entered and the loop is 6.3, byte for
    # byte. Selection is all-or-nothing: one changed path without a row ⇒ the whole suite (D3).
    sel=""
    if [ "$k" = test ] && [ "$full" -eq 0 ] && [ -n "$(cfg test_select "")" ]; then
      csf="$(mktemp)"
      if surface_change_set $fflag > "$csf"; then
        if [ ! -s "$csf" ]; then
          # BOUNDED and EMPTY: only board files moved since an ancestor stamp — the batch-wave
          # finish case — so the baseline's verdict carries to HEAD: the whole loop is skipped and
          # HEAD is re-stamped below with the scope that was actually proven.
          bsha="${SURFACE_BASELINE:-$head}"; scope="${SURFACE_BASELINE_SCOPE:-full}"; carry=1
          say "suite already green at $(printf '%.7s' "$bsha") — only board files changed since; skipped, proven $scope (qa --force re-runs it)"
          rm -f "$csf"; break
        fi
        np="$(grep -c . "$csf" || true)"
        if sel="$(surface_select_cmd "$csf")"; then
          m="$(printf '%s\n' "$sel" | grep -c . || true)"
          note "test — scoped to $m command(s): $np changed path(s) all mapped (qa --full runs test: verbatim)"
        else
          why="$sel"; sel=""
          case "$why" in
            'unmapped: '*) p="${why#unmapped: }"
                           case "$p" in
                             *' (+'*) why="${p%% (+*} has no ops/SURFACES.tsv row (+${p##* (+}";;
                             *)       why="$p has no ops/SURFACES.tsv row";;
                           esac;;
            'no rows')     why="ops/SURFACES.tsv has no rows";;
          esac
          note "test — running the whole suite: $why"
        fi
      else
        note "test — running the whole suite: no proven baseline on $BASE (no stamp, --force, or a stamp that is not an ancestor)"
      fi
      rm -f "$csf"
    fi
    ran=$((ran+1))
    if [ -n "$sel" ]; then
      # scoped: each selected command in order, from the repo root in $PRIMARY; the first red stops
      # — today's red shape exactly, naming the command that failed rather than test: itself.
      scope=scoped; sred=0
      while IFS= read -r c2; do
        [ -z "$c2" ] && continue
        if ( cd "$PRIMARY" && bash -c "$c2" ) >"$out" 2>&1; then continue; fi
        printf '⛔ %s — RED: %s\n' "$k" "$c2"
        tail -15 "$out" | sed 's/^/     /'
        red=1; sred=1; break
      done <<EOF
$sel
EOF
      [ "$sred" -eq 0 ] && say "$k — green (scoped: $m command(s))"
      continue
    fi
    if ( cd "$PRIMARY" && bash -c "$c" ) >"$out" 2>&1; then
      say "$k — green"
    else
      printf '⛔ %s — RED: %s\n' "$k" "$c"
      tail -15 "$out" | sed 's/^/     /'
      red=1
    fi
  done
  fi
  # T-031 (ops/contracts/verification-tiering.md): stamp how long the suite took — one line,
  # "<seconds> <epoch>", written only when ≥1 suite command actually ran. `land` reads it for
  # the slow-suite hint; purely advisory, never a gate, best-effort write.
  if [ "$ran" -ge 1 ]; then
    t1="$(date +%s)"
    mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
    printf '%s %s\n' "$((t1 - t0))" "$t1" > "$PRIMARY/.polaris/last-suite-seconds" 2>/dev/null || true
    # ACTIVATION NUDGE (test-surfaces.md v2 § 15): the moment a repo has just paid for the whole
    # suite — a minute or more, test: ran, nothing was scoped — and a map would have let it pay
    # less. Gated like doctor's line: a runner the scaffold can scope AND no rows, so a repo the
    # scaffold cannot help (this one) never hears it, and a mapped repo never hears it again.
    if [ "$scope" = full ] && [ -n "$(cfg test "")" ] && [ $((t1 - t0)) -ge 60 ] && ! surfaces_lines | grep -q .; then
      csf="$(mktemp)"
      git -C "$PRIMARY" ls-files > "$csf" 2>/dev/null || true
      surfaces_runner "$csf" >/dev/null 2>&1 \
        && note "test — ran the whole suite ($((t1 - t0))s). A surface map runs only what a change can break: ops/polaris surfaces --scaffold"
      rm -f "$csf"
    fi
  fi
  [ "$ran" -eq 0 ] && [ "$skip" -eq 0 ] && [ "$carry" -eq 0 ] && note "no test/lint/typecheck/build/uat in CONVENTIONS.md — only board + env checked"
  # CRUFT (ops/contracts/worktree-liveness.md § v2): clear the provably-landed leftovers BEFORE
  # drift looks at them. This is qa's only mutation besides the stamp, and it is exactly the subset
  # of `sweep --fix` that is lossless by construction — a branch goes only when its commits are
  # already in $BASE under another sha, and never while a lane is still standing in its worktree.
  # The ORDER is the whole point: reported instead of cleared, it reds a run that has just paid for
  # a green suite, withholds the stamp, and hands the next `finish` the full ~12 minutes again for
  # a nit. `finish` inherits this through cmd_qa.
  cruft_clear
  [ "${CRUFT_CLEARED:-0}" -gt 0 ] && say "cruft — cleared $CRUFT_CLEARED branch(es)"
  # drift --strict exits the script on findings, so both sub-checks run in subshells.
  if ( cmd_drift --strict ) >"$out" 2>&1; then
    say "drift — board clean"
  else
    printf '⛔ drift — board hygiene findings:\n'
    grep '^⚠' "$out" | sed 's/^/     /' || true
    red=1
  fi
  if ( cmd_doctor ) >"$out" 2>&1; then
    say "doctor — env OK"
  else
    printf '⛔ doctor — RED:\n'
    tail -5 "$out" | sed 's/^/     /'
    red=1
  fi
  rm -f "$out"
  [ "$red" -eq 0 ] || die "qa: red — fix the ⛔ lines above before calling the work done"
  # Stamp only a suite we actually RAN and that was fully green. Never stamp a skipped run (it
  # would just re-write the same sha) and never stamp a dirty tree — the stamp claims "this commit
  # is proven", and an uncommitted edit means the thing proven is not the thing on disk.
  # The AFTER reads are the parallel-wave half of that same claim: a sibling lane lands while the
  # suite is halfway through, HEAD moves under it, and a stamp keyed on the BEFORE sha would green
  # a later `finish` on code nobody has ever tested. So HEAD must be where it started AND the tree
  # must still be clean when the suite ends. Anything else withholds the stamp and says so — the
  # next qa simply runs the suite again, which is cheap next to blessing an untested commit.
  local head2 dirty2
  head2="$(git -C "$PRIMARY" rev-parse HEAD 2>/dev/null || echo none)"
  dirty2="$(git -C "$PRIMARY" status --porcelain 2>/dev/null | head -1)"
  # Stamp v3 (test-surfaces.md § 6): ONE line `<sha> <epoch> <scope>` — scoped iff the test key
  # ran a selection, full otherwise; a carried verdict re-stamps HEAD with the baseline's own scope.
  # Readers go through suite_stamp_scope (a 2-field pre-6.4 stamp reads as full).
  if { [ "$ran" -ge 1 ] || [ "$carry" -eq 1 ]; } && [ "$head" != "none" ]; then
    if [ "$head2" = "$head" ] && [ -z "$dirty" ] && [ -z "$dirty2" ]; then
      mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
      printf '%s %s %s\n' "$head" "$(date +%s)" "$scope" > "$PRIMARY/.polaris/suite-stamp" 2>/dev/null || true
    else
      note "⚠ HEAD moved or the tree is not clean — stamp withheld, so the next qa re-runs the suite"
    fi
  fi
  say "qa: all green"
}

cmd_finish() { # finish [--force] — is the RUN over? (ops/contracts/run-finish.md). The mechanical
  # half of CONDUCTOR.md's "the run is over ONLY when" list, in ONE call: nothing building, nothing
  # waiting to land, ready/ drained per drain:, no unmerged integrate/<date>, no orphan lock, clean
  # tree on <base>, qa green. It knows NOTHING about EVOLVE's proposals or the close report — those
  # are the role's, and they come FIRST.
  #   rc 0 → the run is COMPLETE. This is the ONLY thing that licenses the `# 🎉 Complete!` H1 in an
  #          agent's reply (a command can never print it: terminals do not render markdown, which is
  #          exactly why the signal lives in the REPLY and the verdict lives here). The notify: done
  #          hook fires too, exactly ONCE per finished state — .polaris/finish-stamp, keyed on the
  #          base tip sha, so it self-clears the moment the next run lands a commit.
  #   rc 1 → something is pending, each named on its own `⛔ pending:` line. No H1, no confetti.
  # `caveat:` lines are NEVER gates. They are things the closing message MUST mention — blocked
  # tasks, work parked under drain: plan, cruft — because rc 0 means "the run is over", never
  # "nothing was left behind".
  # The verdict is recomputed on EVERY invocation; only the hook is memoised. That split is what
  # lets an agent re-run finish freely while chasing pendings without muting the signal.
  local force="" PEND=0 CAV=0 CAVS="" br dr n out w it stamp key fired bl rd ib lk f line sc ssha
  local lho lag lsm
  [ "${1:-}" = "--force" ] && force=1
  fin_pending() { PEND=$((PEND+1)); printf '⛔ pending: %s\n' "$1"; }
  fin_caveat()  { CAV=$((CAV+1));  CAVS="$CAVS$1
"; }
  fin_count() { ls "$BOARD/$1" 2>/dev/null | grep -c '\.md$' || true; }
  fin_ids() { # ≤5 ids from a board column, comma-joined, "… +N more" beyond that (PROTOCOL.md § VOICE)
    local d="$1" g i=0 o=""
    for g in "$BOARD/$d/"*.md; do [ -e "$g" ] || break
      i=$((i+1)); [ "$i" -le 5 ] && o="${o:+$o, }$(basename "$g" .md)"
    done
    [ "$i" -gt 5 ] && o="$o … +$((i-5)) more"
    printf '%s' "$o"
  }

  # PHASE 0 — the mechanical half of "a Builder never celebrates". A conductor-spawned builder lives
  # in .polaris/wt/<ID>, so it can never reach rc 0 no matter what its context talked it into.
  in_primary || die "finish runs in the primary checkout — cd \"$PRIMARY\" first (a worktree can never end the run)"

  # PHASE A — board + git. Free, and every finding is accumulated: one pass paints the whole picture,
  # the same reason cmd_qa and cmd_drift never short-circuit on the first red.
  br="$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  [ "$br" = "$BASE" ] || fin_pending "on branch $br, not $BASE — a run ends on the base branch (git switch $BASE)"
  # Same porcelain read cmd_qa's suite stamp uses, deliberately: if the two disagreed on "clean",
  # finish could bless a tree for which qa silently re-ran the whole suite.
  # The remedy now names the third option. On a SHARED checkout the dirt is often not even this
  # session's, so "commit or discard" asks one chat to make a call about another's work — exactly
  # the git question ops/contracts/shared-checkout.md exists to stop asking. park is reversible.
  [ -z "$(git -C "$PRIMARY" status --porcelain 2>/dev/null | head -1)" ] \
    || fin_pending "uncommitted changes in the working tree — commit or discard them before calling the work done, or park it: bash ops/polaris park"
  n=$(fin_count active); [ "$n" -eq 0 ] || fin_pending "$n building — $(fin_ids active)"
  n=$(fin_count review); [ "$n" -eq 0 ] || fin_pending "$n waiting to land — $(fin_ids review) (audit + land + seal them)"
  # drain: (ops/contracts/hands-free-knobs.md) decides whether a queued task blocks the close. Under
  # `plan` one "go" authorizes THE PLAN, not the board, so ready/ is legitimately non-empty at the
  # end — gating on it there would make the default run un-finishable. Under queue/backlog it gates.
  rd=$(fin_count ready); dr="$(cfg drain "")"; dr="${dr:-queue}"
  if [ "$rd" -gt 0 ]; then
    case "$dr" in
      plan) fin_caveat "$rd queued in ready/ under drain: plan — say so; \`start\` picks them up";;
      queue|backlog) fin_pending "$rd queued in ready/ and drain: $dr — drain them, or set drain: plan in ops/CONVENTIONS.md";;
      *) note "⚠ unknown drain: '$dr' — treating it as queue (plan | queue | backlog)"
         fin_pending "$rd queued in ready/ — drain them, or set drain: plan in ops/CONVENTIONS.md";;
    esac
  fi
  # An unmerged integrate/<date> is a whole wave that never reached <base> — the single most
  # expensive thing to mistake for done. Merged-but-undeleted is just cruft: a caveat.
  while IFS= read -r ib; do
    [ -n "$ib" ] || continue
    if git -C "$PRIMARY" merge-base --is-ancestor "$ib" "$BASE" 2>/dev/null; then
      fin_caveat "$ib is merged but the branch is still here — git branch -d $ib"
    else
      n=$(git -C "$PRIMARY" rev-list --count "$BASE..$ib" 2>/dev/null || echo 0)
      fin_pending "$ib is not in $BASE — $n commit(s) unsealed (bash ops/polaris seal ${ib#integrate/})"
    fi
  done <<EOF
$(git -C "$PRIMARY" for-each-ref --format='%(refname:short)' 'refs/heads/integrate/*' 2>/dev/null)
EOF
  # The integration lease (ops/contracts/shared-checkout.md). A land in flight leaves the board
  # looking quiet — the task is out of review/ and not yet in done/ — so nothing else on this list
  # can see it, and a run declared over here would be declared over mid-landing. OURS never gates:
  # a finish nested inside our own landing pass is not a conflict. Past integration_stale_minutes
  # the holder is abandoned by definition and the next `int_on` steals it automatically, so that is
  # a caveat — gating on a crashed session would make the run un-finishable for 45 minutes.
  if [ -d "$LOCKS/.int-lease" ] && [ "$(cat "$LOCKS/.int-lease/pid" 2>/dev/null | tr -d ' \r\n')" != "$$" ]; then
    lho="$(cat "$LOCKS/.int-lease/who" 2>/dev/null | tr -d '\r\n')"; lho="${lho:-unknown}"
    lag="$(cat "$LOCKS/.int-lease/epoch" 2>/dev/null | tr -d ' \r\n')"
    case "$lag" in ''|*[!0-9]*) lag="$(date +%s)";; esac
    lag=$(( ( $(date +%s) - lag ) / 60 ))
    lsm="$(cfg integration_stale_minutes 45)"
    case "$lsm" in ''|*[!0-9]*) lsm=45;; esac
    if [ "$lag" -ge "$lsm" ]; then
      fin_caveat "the integration lease is stale — $lho has held it ${lag}m (> ${lsm}m) — the next land steals it automatically"
    else
      fin_pending "$lho holds the integration lease (${lag}m) — a session is landing; wait for it, then run finish again"
    fi
  fi
  for lk in "$LOCKS"/*/; do
    [ -e "$lk" ] || break
    n="$(basename "$lk")"; [ "$n" = ".board-mutex" ] && continue
    if ! task_file "$n" active >/dev/null && ! task_file "$n" review >/dev/null; then
      fin_pending "orphan lock $n (age $(( $(lock_age "$n") / 3600 ))h) — bash ops/polaris sweep --fix"
    fi
  done
  [ -d "$MUTEX" ] && fin_pending "a board operation still holds the mutex — wait for it, or bash ops/polaris sweep --fix if it is stale"
  # Background jobs (ops/contracts/bg-jobs.md § finish): a job dir with NO rc file is a suite still
  # in flight — or a crash nobody collected — and either way the run is not over. rc-file-FIRST,
  # then the pid, never the reverse (Windows pid reuse). This reads the registry layout ONLY: the
  # bg module may not even be installed yet, and no .polaris/bg/ dir means silence. `.prev` dirs are
  # rotation ARCHIVES (bg-jobs.md § v1.2), never live jobs — skipped here exactly like bg_status/sweep.
  local bgd bgn bgp
  for bgd in "$PRIMARY"/.polaris/bg/*/; do
    [ -e "$bgd" ] || break
    bgn="$(basename "$bgd")"
    case "$bgn" in *.prev) continue;; esac
    [ -f "$bgd/rc" ] && continue
    bgp="$(cat "$bgd/pid" 2>/dev/null | tr -d ' \r\n')"
    if [ -n "$bgp" ] && kill -0 "$bgp" 2>/dev/null; then
      fin_pending "background job $bgn still running — collect it: bash ops/polaris bg wait $bgn"
    else
      fin_pending "background job $bgn crashed? no verdict recorded — check it: bash ops/polaris bg status $bgn"
    fi
  done
  # blocked/ is NEVER a gate. CONDUCTOR.md licenses blocked "with a reason the human has been told",
  # and whether they were told is not mechanically knowable — gating here would either make runs
  # un-finishable or force finish to write board state. So: a caveat the close MUST carry.
  bl=$(fin_count blocked)
  [ "$bl" -eq 0 ] || fin_caveat "$bl blocked — $(fin_ids blocked) (name what is parked, and why, in your close)"
  for f in "$PRIMARY"/.polaris/wt/*/; do
    [ -e "$f" ] || break
    n="$(basename "$f")"
    task_file "$n" active >/dev/null || task_file "$n" review >/dev/null \
      || fin_caveat "worktree .polaris/wt/$n has no active task — bash ops/polaris sweep --fix"
  done
  # Parked dirt is NEVER a gate. park exists precisely so a shared checkout never has to ask a git
  # question, so gating on its own remedy would close the loop on itself — but a stash somebody
  # forgot is exactly what rc 0 must still MENTION, on the same rule blocked/ follows: the run is
  # over, and something was left behind. One caveat per park, newest first.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    fin_caveat "parked work is still stashed: $line — bash ops/polaris unpark restores the newest"
  done <<EOF
$(git -C "$PRIMARY" stash list --format='%gd %gs' 2>/dev/null | grep 'polaris/park-' || true)
EOF
  # Local ref read only — NEVER a fetch. A missing or stale origin ref is silence, not a caveat
  # about nothing.
  if has_remote && git -C "$PRIMARY" show-ref -q --verify "refs/remotes/origin/$BASE" 2>/dev/null; then
    n=$(git -C "$PRIMARY" rev-list --count "origin/$BASE..$BASE" 2>/dev/null || echo 0)
    [ "$n" -eq 0 ] || fin_caveat "$n commit(s) on $BASE not pushed to origin — git push origin $BASE"
  fi

  # PHASE B — qa, and only once the board is quiet: a suite run while a lane is still building
  # proves nothing about the finished state. finish RUNS it rather than requiring it, because
  # "requiring" means trusting an agent's memory that it ran — the exact class of claim this command
  # exists to replace. Nearly free when HEAD has not moved: cmd_qa's suite stamp skips the suite and
  # drift/doctor are seconds. cmd_qa dies on red, so it goes in a subshell exactly as cmd_qa itself
  # does for drift and doctor.
  if [ "$PEND" -eq 0 ]; then
    note "checking the suite on $BASE (quiet unless red; skipped when already green at this commit)"
    out="$(mktemp)"
    if ( cmd_qa ${force:+--force} ) >"$out" 2>&1; then
      # Say what was proven (test-surfaces.md § 6): the stamp's scope — full, or scoped to the
      # commands the changed surfaces map to. A scoped green is accepted, never rejected: refusing
      # it would put the full suite back on the one lane a one-line change takes.
      if sc="$(suite_stamp_scope)"; then
        ssha="$(cut -d' ' -f1 < "$PRIMARY/.polaris/suite-stamp" 2>/dev/null || true)"
        say "qa green on $BASE — proven $sc at $(printf '%.7s' "$ssha")"
      else
        say "qa green on $BASE"
      fi
    else
      fin_pending "qa is red on $BASE"
      tail -6 "$out" | sed 's/^/     /'
    fi
    rm -f "$out"
  fi

  if [ "$PEND" -gt 0 ]; then
    [ "$PEND" -eq 1 ] && { w="thing"; it="it"; } || { w="things"; it="them"; }
    die "finish: not done — $PEND $w pending; fix $it and run finish again"
  fi

  # From here down the verdict is rc 0 — the die above is the only exit. The Stop hook reads this
  # marker to know a session has already ended its RUN (ops/contracts/role-handover.md, the
  # `allow:finished` rung), so a finished session is never hopped into another role and made to
  # start work after its own close. Best-effort and sid-only: without a session id there is no
  # session to hop, and nothing to write. Redirection AFTER 2>/dev/null on purpose — bash opens
  # left to right, and a missing dir would otherwise talk on the way past (worktree-liveness v1.1).
  local hsd
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    hsd="$PRIMARY/.polaris/handover/$CLAUDE_CODE_SESSION_ID"
    mkdir -p "$hsd" 2>/dev/null || true
    date +%s 2>/dev/null > "$hsd/finished" || true
  fi

  say "board clear — $(fin_count done) done · $bl blocked · $rd queued · nothing building · nothing waiting to land"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    note "caveat: $line"
  done <<EOF
$CAVS
EOF

  # FIRE-ONCE, keyed on the base tip sha. notify-gate is observe-only by contract (it may not touch
  # the board), so the board carries no record that the signal fired and cannot be made to — a stamp
  # is the only permitted memory. Keying on HEAD makes it self-clearing: the next run lands a commit,
  # the stamp goes stale, the signal fires again. No expiry, no --reset, no session id to plumb.
  # Best-effort writes throughout, exactly as .polaris/suite-stamp — finish can never fail the close.
  stamp="$PRIMARY/.polaris/finish-stamp"
  key="$(git -C "$PRIMARY" rev-parse HEAD 2>/dev/null || echo none)"
  fired=""
  [ -f "$stamp" ] && fired="$(cut -d' ' -f1 < "$stamp" 2>/dev/null || true)"
  if [ "$key" != none ] && [ "$fired" = "$key" ]; then
    say "finish: run complete — done signal already fired"
  else
    cmd_notify_gate done
    mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
    printf '%s %s\n' "$key" "$(date +%s)" > "$stamp" 2>/dev/null || true
    say "finish: run complete — done signal fired"
  fi
}

cmd_metrics() { # cycle time + throughput + kickbacks from EVENTS.ndjson — pure awk
  [ -s "$EVENTS" ] || { note "no telemetry yet (EVENTS.ndjson empty) — runs accumulate it"; return 0; }
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
    [ "$(basename "$tf")" = "IDEAS.md" ] && continue
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
