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
  # One line per park, newest first. `git stash list` is the source of truth, not a guess: the human
  # can act on the printed stash@{N} directly if unpark's newest-first order is not what they want.
  local pk
  while IFS= read -r pk; do
    [ -n "$pk" ] || continue
    printf 'parked: %s — bash ops/polaris unpark restores the newest\n' "$pk"
  done <<EOF
$(git -C "$PRIMARY" stash list --format='%gd %gs' 2>/dev/null | grep 'polaris/park-' || true)
EOF
}

cmd_board_fm() { # board-fm [<col>…] — ONE tab line per task: the frontmatter a Planner actually
  # carves against, and nothing else. Default = the LIVE columns; `done/` is history and is opt-in
  # (on a mature board it is ~98% of the bytes and answers no planning question). Replaces the
  # PLANNER's "read ops/board/** frontmatter", which has no command behind it today — so the agent
  # reads whole task files and pays for the prose body, which dwarfs the frontmatter ~4:1.
  # Non-task files (backlog/IDEAS.md) carry no frontmatter and are skipped.
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

cmd_sweep() { # report orphans + stale locks + >24h bg jobs + remote strays; --fix removes true
  # orphans, rotates finished/crashed stale jobs, and deletes merged strays
  local fix="${1:-}" d id found=0
  for d in "$LOCKS"/*/; do
    [ -e "$d" ] || break
    id="$(basename "$d")"; [ "$id" = ".board-mutex" ] && continue
    if ! task_file "$id" active >/dev/null && ! task_file "$id" review >/dev/null; then
      found=1; printf '⚠ ORPHAN lock: %s (age %sh, no active/review task)\n' "$id" "$(( $(lock_age "$id") / 3600 ))"
      [ "$fix" = "--fix" ] && { lock_drop "$id"; note "removed"; }
    elif task_file "$id" active >/dev/null && [ "$(lock_age "$id")" -gt $((STALE_H*3600)) ]; then
      found=1; printf '⚠ STALE lock: %s (%ss > %sh) — take it over: polaris resume %s · or hand back: polaris release %s --to ready\n' \
        "$id" "$(lock_age "$id")" "$STALE_H" "$id" "$id"
    fi
  done
  # background jobs (ops/contracts/bg-jobs.md): a non-.prev job dir whose start is >24h old is
  # leftover runtime state. Always reported; --fix rotates it to <name>.prev (archive, never
  # delete) — but NEVER a still-running job: rotating a live job's dir out from under its runner
  # is destruction, not hygiene. `.prev` archives are never swept (ONE slot per name, no chains).
  local bgd bgn bgs bga bgp
  for bgd in "$PRIMARY/.polaris/bg"/*/; do
    [ -e "$bgd" ] || break
    bgn="$(basename "$bgd")"
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
  # remote hygiene: a landed task should have taken its feat/<ID> branch with it (done does this
  # since 5.11). This pass catches strays from before — or from any path that skipped `done`.
  # Only branches whose task is in done/ are touched; active/review branches are live work.
  if has_remote; then
    local rline rsha rref rid lsha lf
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
        found=1; printf '⚠ REMOTE diverged: feat/%s — task done but the remote tip is NOT in %s. Inspect: git fetch origin feat/%s && git log %s..FETCH_HEAD (never auto-deleted)\n' \
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
      if git -C "$PRIMARY" cat-file -e "$rsha" 2>/dev/null \
         && git -C "$PRIMARY" merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
        found=1; printf '⚠ REMOTE stray: %s — wave merged into %s, branch still on origin\n' "$rid" "$BASE"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/$rid" && note "deleted"; }
      else
        found=1; printf '⚠ REMOTE diverged: %s — tip is NOT in %s. Inspect: git fetch origin %s && git log %s..FETCH_HEAD (never auto-deleted)\n' \
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
  say "doctor: OK"
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
  printf '%s\n' "$b" | owned_match "$a" && return 0   # pattern B matches A taken as a literal path
  printf '%s\n' "$a" | owned_match "$b" && return 0   # pattern A matches B taken as a literal path
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
  local strict="${1:-}" n=0 f g id id2 v d
  finding() { n=$((n+1)); printf '⚠ [%d] %s\n' "$n" "$1"; }
  # 1) THE invariant: files_owned disjoint across ready ∪ active (heuristic, see pat_overlap)
  local claimable=""; for d in ready active; do
    for f in "$BOARD/$d/"*.md; do [ -e "$f" ] || break; claimable="$claimable$f
"; done; done
  local seen=""
  while IFS= read -r f; do [ -z "$f" ] && continue
    while IFS= read -r g; do [ -z "$g" ] && continue
      id="$(basename "$f" .md)"; id2="$(basename "$g" .md)"
      local pa pb
      while IFS= read -r pa; do [ -z "$pa" ] && continue
        while IFS= read -r pb; do [ -z "$pb" ] && continue
          if pat_overlap "$pa" "$pb"; then
            finding "OWNERSHIP OVERLAP: $id ∩ $id2 on '$pa' / '$pb' — chain them (depends_on), never parallel"
          fi
        done <<EOF2
$(fm_list files_owned "$g")
EOF2
      done <<EOF1
$(fm_list files_owned "$f")
EOF1
    done <<EOF0
$seen
EOF0
    seen="$seen$f
"
  done <<EOF
$claimable
EOF
  # 2) ready-gate: contract exists · deps all done · ≤5 points
  for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
    id="$(basename "$f" .md)"
    v="$(fm_get contract "$f")"
    { [ -z "$v" ] || [ ! -f "$PRIMARY/$v" ]; } && finding "READY GATE: $id contract missing (${v:-unset}) — blocked/, not ready/"
    while IFS= read -r d; do [ -z "$d" ] && continue
      task_file "$d" done >/dev/null || finding "READY GATE: $id depends_on $d which is NOT in done/"
    done <<EOF
$(dep_ids "$f")
EOF
    v="$(fm_get points "$f")"; case "$v" in 8|13) finding "READY GATE: $id is ${v}pts — must be split before ready/";; esac
  done
  # 3) cruft: done tasks whose feat branch survived
  for f in "$BOARD/done/"*.md; do [ -e "$f" ] || break
    id="$(basename "$f" .md)"
    git -C "$PRIMARY" show-ref --verify -q "refs/heads/feat/$id" \
      && finding "CRUFT: feat/$id still exists though $id is done — git branch -D feat/$id"
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
  # 7) dependency graph across ALL columns: deps that exist nowhere + cycles (a ring never promotes)
  local col2 idf d2
  for col2 in backlog ready active review blocked done; do
    for idf in "$BOARD/$col2/"*.md; do [ -e "$idf" ] || break
      id="$(basename "$idf" .md)"
      while IFS= read -r d2; do [ -z "$d2" ] && continue
        task_file "$d2" >/dev/null || finding "DEP MISSING: $id depends_on $d2 — no task by that id in any column"
      done <<EOF
$(dep_ids "$idf")
EOF
      dep_reaches "$id" "$id" "" && finding "DEP CYCLE: $id sits in a depends_on ring — it can never satisfy the ready gate; break the cycle"
    done
  done
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
    case "$kind" in path|content) :;; *) bad=1; printf '   ⛔ bad kind (want path|content)\n';; esac
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
  local only="*" upd=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --only) only="${2:?--only needs a glob}"; shift 2;;
      --update) upd=1; shift;;
      *) die "usage: polaris check [--only <glob>] [--update] | check --scaffold [--app] [--cmd \"<shell>\"]";;
    esac
  done
  local dir="$OPS/tests" f name exp rcf want got grc red=0 n=0
  [ -d "$dir" ] || { note "no ops/tests/ yet — add <name>.cmd + <name>.expected (polaris check --update writes the golden)"; return 0; }
  for f in "$dir"/*.cmd; do
    [ -e "$f" ] || break
    name="$(basename "$f" .cmd)"
    case "$name" in $only) ;; *) continue;; esac
    n=$((n+1)); exp="$dir/$name.expected"; rcf="$dir/$name.rc"
    got="$( cd "$PRIMARY" && bash -c "$(cat "$f")" 2>/dev/null )"; grc=$?
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
  [ "$n" -eq 0 ] && { note "no goldens matched '$only'"; return 0; }
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
  local n=0 id="" f base pts risk owned p why="" lane=full
  for f in "$BOARD"/ready/*.md "$BOARD"/active/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"; [ "$base" = "IDEAS.md" ] && continue
    n=$((n + 1)); id="${base%.md}"
  done

  if [ "$n" -eq 0 ]; then
    printf 'full\n'; note "nothing claimable — the board is empty, so a Planner runs first"; return 0
  fi
  if [ "$n" -gt 1 ]; then
    printf 'full\n'; note "$n claimable tasks — parallel lanes are the point; solo/express land exactly one"; return 0
  fi

  f="$(task_file "$id")" || { printf 'full\n'; note "cannot read task $id"; return 0; }
  pts="$(fm_get points "$f")"; pts="${pts:-99}"
  risk="$(fm_get risk "$f")"; risk="${risk:-normal}"

  [ "$risk" = "normal" ] || why="risk: $risk (only a human may approve a merge)"
  case "$pts" in ''|*[!0-9]*) [ -z "$why" ] && why="points '$pts' is not a plain number";; esac
  [ -z "$why" ] && [ "$(cfg express on)" = "off" ] && why="express: off in CONVENTIONS.md"
  [ -z "$why" ] && [ "$(cfg publish direct)" != "direct" ] && why="publish: pr — the wave needs a human merge"
  # STOP-AND-ASK, mechanically: a RULES path rule over anything the task owns means this task
  # cannot be a quiet one-context run, whatever its size.
  if [ -z "$why" ]; then
    owned="$(fm_list files_owned "$f")"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if rule_scan_path "$p" 2>/dev/null; then :; else why="owns a RULES-guarded path ($p)"; break; fi
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
  local tier="" mdl="" ov="" f="" rnote=""
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
  [ -n "$mdl" ] || mdl="$(model_for_tier "$tier")"
  [ -n "$mdl" ] && note "model: $mdl"
  [ -n "$rnote" ] && note "$rnote"
  return 0
}

cmd_qa() { # qa — ONE answer to "is everything okay?": the full CONVENTIONS suite (test/lint/
  # typecheck/build, uat if set), then drift --strict, then doctor's env check. Runs EVERY
  # check even after a red — one pass paints the whole picture — and exits 1 if anything was
  # red. The Conductor runs it after integration (a subagent's "green" is never taken on
  # faith), the Integrator runs it before reporting, CI and humans run it whenever.
  local red=0 ran=0 k c out skip=0 force=0
  local t0 t1 head stamped dirty
  [ "${1:-}" = "--force" ] && force=1

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
    say "suite already green at $(printf '%.7s' "$head") — skipped (qa --force re-runs it)"
  else
  for k in test lint typecheck build uat; do
    c="$(cfg "$k" "")"
    [ -z "$c" ] && continue
    ran=$((ran+1))
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
  fi
  [ "$ran" -eq 0 ] && [ "$skip" -eq 0 ] && note "no test/lint/typecheck/build/uat in CONVENTIONS.md — only board + env checked"
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
  if [ "$ran" -ge 1 ] && [ "$head" != "none" ] && [ -z "$dirty" ]; then
    mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
    printf '%s %s\n' "$head" "$(date +%s)" > "$PRIMARY/.polaris/suite-stamp" 2>/dev/null || true
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
  local force="" PEND=0 CAV=0 CAVS="" br dr n out w it stamp key fired bl rd ib lk f line
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
      say "qa green on $BASE"
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
  local msg="You are a BUILDER. Claim the top ready task and complete it end to end. Stop at the review handoff.$loop"
  note "kickoff (paste into $n parallel sessions of ANY agent CLI — in Claude Code, \"start\" alone does it):"
  printf '   %s\n' "$msg"

  # Print-only unless the caller asked to open sessions (--launch) or preview that (--dry-run).
  # We NEVER spawn windows a caller didn't ask for — the Planner passes --launch per autolaunch:.
  if [ -z "$launch" ] && [ -z "$dry" ]; then
    note "(add --launch to open $n Builder sessions automatically, or open $n terminals and paste the line above)"
    return 0
  fi

  # Cap auto-launched sessions — screen + cost discipline. The printed kickoff above stays uncapped.
  local cap launch_n; cap="$(cfg autolaunch_max 3)"; case "$cap" in ''|*[!0-9]*) cap=3;; esac
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
