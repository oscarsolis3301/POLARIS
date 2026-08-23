# POLARIS lib/builder.sh — the Builder lifecycle sourced by ops/polaris (the lib loader): claim/
# verify/handoff/release, the grant files_owned amendment, and resume.

cmd_claim() {
  local id="${1:-}" f
  local explicit=1; [ -z "$id" ] && explicit=0
  # Candidate list: an explicit ID is the only candidate; auto-pick is EVERY ready task, sorted
  # by wsjf desc. We then take the first candidate we can lock. That fan-out is what makes N
  # parallel `claim` (no ID) — e.g. a fleet of Builder panes — land on N DISTINCT tasks instead
  # of all grabbing the top one and N-1 dying on its lock.
  local candidates
  if [ "$explicit" = 1 ]; then
    candidates="$id"
  else
    # NO `case` inside this $(...): bash 3.2 (macOS /bin/bash) cannot parse a case pattern's `)`
    # terminator inside command substitution — it reads it as the closing `)` of the `$(`. sort -rn
    # already coerces a blank/non-numeric wsjf to 0, so the ordering is identical without a sanitiser.
    candidates="$( { for f in "$BOARD/ready/"*.md; do
        [ -e "$f" ] || break
        printf '%s\t%s\n' "$(fm_get wsjf "$f")" "$(basename "$f" .md)"
      done; } | sort -rn | cut -f2- )"
    [ -n "$candidates" ] || die "ready/ is empty — nothing to claim"
  fi

  local got="" cand
  local ov_id="" ov_cpat="" ov_apat="" ov_col="" ov_msg=""
  local af aid apat cpat
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    # T-059 (ops/contracts/shared-checkout.md): branch-ID hygiene BEFORE any lock — a bad ID used
    # to become a bad ref name deep inside worktree add. Explicit → die; auto-pick → id_ok already
    # printed its one ⛔ line, move on to the next candidate.
    id_ok "$cand" || { [ "$explicit" = 1 ] && die "claim refused — invalid task ID (fix the ID and re-run)"; continue; }
    f="$(task_file "$cand" ready)" || { [ "$explicit" = 1 ] && die "$cand is not in ready/ (state: $(task_col "$cand" || echo unknown))"; continue; }
    if [ "$CLAIM_MODE" = "claim-branch" ]; then
      has_remote || die "claim: claim-branch requires an origin remote"
      if claim_branch_take "$cand"; then lock_take "$cand" || true
      elif [ "$explicit" = 1 ]; then die "taken — $cand claimed on another machine; try: polaris claim"
      else continue
      fi
    else
      if lock_take "$cand"; then :
      elif [ "$explicit" = 1 ]; then die "taken — $cand is locked by another session; try: polaris claim"
      else continue
      fi
    fi
    FAIL_LOCK_ID="$cand"; trap on_die EXIT   # we hold the lock from here — any die below must release it
    # T-059 claim-time disjointness gate, widened to ready ∪ active by T-086 (shared-checkout § v2.3):
    # the locked candidate's files_owned vs EVERY task in ready/ AND active/, both directions via
    # pat_overlap (observe.sh). Two planners racing can put overlapping tasks in ready/, and the
    # ready-gate never re-checks against already-claimed work — without this the overlap surfaces
    # two builds later as an integrator squash conflict. Clean board → zero output, zero extra git
    # work: the scan is frontmatter reads and (since T-086) fork-free pattern matching.
    #
    # The scan runs INSIDE the board mutex, and the placement IS the gate. Where it used to sit —
    # after lock_take, before the mutex — two sessions claiming two overlapping tasks could each
    # scan a board that showed neither of them in active/ yet, both pass, and both mv: the mutex was
    # taken after the decision it exists to protect. Held from here through the ready→active mv
    # below, decision and move are one atomic step. mutex_on is NOT re-entrant, so there is exactly
    # ONE acquisition per candidate and every exit from this iteration releases it — blocked/ below,
    # die (on_die runs mutex_off), or the claim after the loop.
    mutex_on
    ov_id=""; ov_cpat=""; ov_apat=""; ov_col=""
    # active/ FIRST, deliberately: when a candidate collides with both columns the active one is the
    # live conflict — someone is building it right now — and reporting it keeps T-059's message for
    # every board that already had one. ready/ is the addition, not the new precedence.
    for af in "$BOARD/active/"*.md "$BOARD/ready/"*.md; do
      [ -e "$af" ] || continue          # `continue`, not `break`: an empty column must not stop the other
      aid="$(basename "$af" .md)"
      [ "$aid" = "$cand" ] && continue  # the candidate is still in ready/ — it never overlaps itself
      case "$af" in "$BOARD/ready/"*) ov_col=ready;; *) ov_col=active;; esac
      while IFS= read -r cpat; do
        [ -z "$cpat" ] && continue
        while IFS= read -r apat; do
          [ -z "$apat" ] && continue
          if [ -z "$ov_id" ] && pat_overlap "$cpat" "$apat"; then
            ov_id="$aid"; ov_cpat="$cpat"; ov_apat="$apat"
          fi
        done <<EOF_APAT
$(fm_list files_owned "$af")
EOF_APAT
      done <<EOF_CPAT
$(fm_list files_owned "$f")
EOF_CPAT
      [ -n "$ov_id" ] && break
    done
    if [ -n "$ov_id" ]; then
      # Both phrasings are spelled out here as literals, not composed from $ov_col, so they stay
      # greppable in the source: `overlaps active` (T-059) and `overlaps ready` (T-086) are pinned
      # in the contract and grepped by verify: and the readyoverlap drill. Output is byte-identical
      # to T-059's for the active case.
      if [ "$ov_col" = ready ]; then ov_msg="overlaps ready $ov_id"; else ov_msg="overlaps active $ov_id"; fi
      # explicit ID → refuse, naming the task and both patterns (on_die releases lock AND mutex).
      [ "$explicit" = 1 ] && die "claim refused: $cand files_owned '$ov_cpat' $ov_msg '$ov_apat' — re-groom or wait for $ov_id"
      # auto-pick → park the bad pairing in blocked/ with the remedy ON THE RECORD (ONE board
      # commit), release its lock, and keep claiming — the next candidate gets its own gate pass.
      note "⛔ $cand files_owned '$ov_cpat' $ov_msg '$ov_apat' → blocked/ — claiming the next candidate"
      mv "$BOARD/ready/$cand.md" "$BOARD/blocked/$cand.md"
      set_fm status blocked "$BOARD/blocked/$cand.md"
      printf -- "- ⛔ ownership overlap: files_owned '%s' %s '%s' — re-groom or wait for %s\n" \
        "$ov_cpat" "$ov_msg" "$ov_apat" "$ov_id" >> "$BOARD/blocked/$cand.md"
      evt blocked "$cand" "ownership overlap with $ov_id"
      board_commit "chore(board): block $cand (ownership overlap)"
      sync_board
      mutex_off
      lock_drop "$cand"; [ "$CLAIM_MODE" = "claim-branch" ] && claim_branch_drop "$cand"
      FAIL_LOCK_ID=""; trap - EXIT
      continue
    fi
    got="$cand"; break   # mutex still HELD — released after the ready→active mv below
  done <<EOF
$candidates
EOF
  [ -n "$got" ] || die "every ready task is currently claimed — nothing free to take"
  id="$got"
  FAIL_LOCK_ID="$id"; trap on_die EXIT

  local pts; pts="$(fm_get points "$BOARD/ready/$id.md")"
  # NO mutex_on here: the disjointness gate above took it and still holds it, so the scan that
  # cleared this candidate and the move that acts on it cannot be split by another session.
  mv "$BOARD/ready/$id.md" "$BOARD/active/$id.md"   # plain mv: board paths are untracked on base
  who; set_fm owner "$WHO" "$BOARD/active/$id.md"
  set_fm branch "feat/$id" "$BOARD/active/$id.md"
  set_fm status active "$BOARD/active/$id.md"
  evt claim "$id" "" "$pts"
  board_commit "chore(board): claim $id"
  sync_board
  mutex_off; FAIL_LOCK_ID=""; trap - EXIT

  local wt; wt="$(wt_path "$id")"
  # T-059: wt_add (lib/workspace.sh) replaces the inline retry loop — one shared primitive with
  # cmd_resume. index.lock-only retries, ONE stray-feat repair, and any other failure re-emits
  # git's REAL stderr instead of the old blanket "git index busy" guess.
  wt_add "$id"
  say "claimed $id → cd \"$wt\""
  # bootstrap: a fresh worktree is a bare checkout — node_modules/.venv/target are gitignored and
  # absent, so a real repo's `verify:`/full suite fails until deps are installed, in a dir the Builder
  # doesn't own. Run the configured install here so the green-gate can actually pass. Opt-in: no key,
  # no-op (unchanged behavior). Failure is a note, not a die — the Builder can install by hand.
  local bootstrap; bootstrap="$(cfg bootstrap "")"
  if [ -n "$bootstrap" ]; then
    note "bootstrap: installing deps in the worktree ($bootstrap)…"
    ( cd "$wt" && bash -c "$bootstrap" ) \
      && note "bootstrap ok — deps ready" \
      || note "⚠ bootstrap failed — install deps in the worktree before verify (cmd: $bootstrap)"
  fi
  # primary-anchored on purpose (ops/contracts/quiet-board.md): the moved set is ignored on base,
  # so the Builder's worktree contains NO ops/board — a repo-relative task path would point at
  # nothing. Contract paths stay repo-relative: contracts live on base, present in every worktree.
  note "read: task file at \"$BOARD/active/$id.md\" + its contract + context_files. Build only inside files_owned."
  note "when green: polaris handoff   ·   to abort: polaris release $id --to ready"
  # T-087 (shared-checkout v2 §4): claim CLOSES with an instruction, not an observation — a printed
  # `cd` is prose a session can skip, and a session that skips it works in the shared primary.
  # TWO callers, two entries, both pinned: a top-level session (the human's parallel-chat workflow,
  # and every fleet pane) enters with EnterWorktree and gets no prompt; a conductor-spawned subagent
  # has its cwd PINNED at launch and EnterWorktree REFUSES there — it only accepts paths under
  # .claude/worktrees/ — so absolute paths under the worktree are that caller's PRIMARY instruction.
  # Each line stays ON ONE LINE, never hard-wrapped: verify: greps them, here and in the role files.
  note "now enter the worktree — every command until handoff runs there"
  note "top-level session: EnterWorktree({path: \".polaris/wt/<ID>\"}) · pinned-cwd subagent or any other CLI: run everything via absolute paths under .polaris/wt/<ID> (or cd there — the shell's cwd persists between calls)"
}

cmd_verify() {
  local id="${1:-}"; [ -n "$id" ] || id="$(current_task_id)" || die "not on a feat/<ID> branch — pass the ID"
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/"
  check_ownership "$tf" HEAD
  check_rules HEAD "$id"           # ID threaded: an `ask` rule cleared by <ID>'s approved: list
  run_verify_cmds "$tf"
}

cmd_handoff() {
  local id="${1:-}"; [ -n "$id" ] || id="$(current_task_id)" || die "not on a feat/<ID> branch — pass the ID"
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/"
  git diff --quiet && git diff --cached --quiet || die "uncommitted changes — commit on feat/$id first"
  check_ownership "$tf" "feat/$id"
  check_rules "feat/$id" "$id"     # ID threaded: an `ask` rule cleared by <ID>'s approved: list
  run_verify_cmds "$tf"
  map_delta_hint "$tf" "feat/$id"
  # publish: pr — feat branches never leave the machine; seal pushes ONE integrate branch instead
  # (ops/contracts/publish-modes.md). Everything else stays byte-identical to direct mode.
  publish_resolve
  # T-059 (ops/contracts/shared-checkout.md): the push was ONE unguarded attempt, so one network
  # hiccup stranded a FINISHED task in active/ with its lock held. Now 3 attempts 0.5s apart, ONE
  # stray_feat_repair between attempts when a ref literally named `feat` shadows the push, and a
  # persistent failure DEGRADES below instead of dying — direct-mode landing merges the LOCAL
  # branch, so the work is safe either way.
  local pushed=1
  local perr ptry repaired
  if [ "$PUB" != "pr" ] && has_remote; then
    pushed=0
    perr="$(mktemp)"
    ptry=1
    repaired=0
    while :; do
      if git push -q -u origin "feat/$id" 2>"$perr"; then pushed=1; break; fi
      [ "$ptry" -ge 3 ] && break
      if [ "$repaired" -eq 0 ]; then
        if grep -q "refs/heads/feat'" "$perr" 2>/dev/null \
           || [ -n "$(git -C "$PRIMARY" ls-remote --heads origin feat 2>/dev/null | head -1)" ]; then
          repaired=1
          stray_feat_repair
        fi
      fi
      ptry=$((ptry+1))
      sleep 0.5
    done
    if [ "$pushed" -eq 0 ]; then cat "$perr" >&2; fi
    rm -f "$perr"
  fi
  mutex_on
  mv "$BOARD/active/$id.md" "$BOARD/review/$id.md"
  set_fm status review "$BOARD/review/$id.md"
  if [ "$pushed" -eq 0 ]; then
    # a finished task is NEVER stranded by the network: the contract's ⚠ Note + push-fail event
    # ride the same board commit, and land merges the local branch.
    printf -- '- ⚠ push failed at handoff — feat/%s is local-only; land merges the local branch\n' "$id" >> "$BOARD/review/$id.md"
    evt push-fail "$id" "feat/$id local-only after 3 push attempts"
  fi
  evt handoff "$id"
  # Last lane landed? Count inside the mutex (post-mv, pre-commit) so the all-review event
  # rides this same board commit. Without this notice, a fleet of one-task pane sessions
  # ends and the board sits in review/ silently — nobody integrates.
  local nact nrdy notice=""
  nact="$(ls "$BOARD/active" 2>/dev/null | grep -c '\.md$' || true)"
  nrdy="$(ls "$BOARD/ready" 2>/dev/null | grep -c '\.md$' || true)"
  if [ "${nact:-0}" -eq 0 ] && [ "${nrdy:-0}" -eq 0 ]; then
    evt all-review "$id" "last lane landed — board is all review"
    notice="integrate"
  elif [ "${nact:-0}" -eq 0 ]; then
    notice="queue"
  fi
  board_commit "chore(board): handoff $id"
  sync_board
  mutex_off; trap - EXIT
  say "$id → review/. Lock stays until the Integrator lands it. Session may close."
  [ "$pushed" -eq 0 ] && note "⚠ push failed ×3 — feat/$id is local-only; the board moved anyway and land merges the local branch"
  case "$notice" in
    integrate) say "all lanes done — nothing left building. Integrate now: \"You are the INTEGRATOR. Land everything in ops/board/review/.\"";;
    queue)     note "$nrdy ready task(s) still queued — say start (or: bash ops/polaris fleet $nrdy --launch) to build them";;
  esac
  # T-088 (shared-checkout v2 §5): under landing: self the handoff CONTINUES into the landing —
  # the last statement on purpose, so its rc (0, or 3 for a queued lane) is the handoff's rc.
  self_land "$id" "$notice"
}

self_land() { # self_land <ID> <notice> — T-088 (ops/contracts/shared-checkout.md v2 §5): under
  # `landing: self` — the DEFAULT IN CODE, because `update` never rewrites an installed
  # CONVENTIONS.md (the 6.0.0 lesson), so unset must compose to the new behavior — a handoff
  # continues into `land <ID>` in this same session. The integration lease already provides
  # wait-your-turn (int_on: atomic lease, 2s poll, stale steal, `queued: ` + rc 3 past the
  # bounded wait) and land/seal/done run as child invocations from the PRIMARY (`land` refuses
  # worktrees), so every one of their gates, parks and rc semantics applies UNCHANGED. Runs
  # AFTER handoff's mutex_off: the lease is OUTERMOST (contract § Lock ordering) and is never
  # taken while the board mutex is held. Self-landing runs NO full suite — `land` is
  # squash + audit; the suite stays per-wave (integration: batch economics unchanged).
  #
  # HARD STOPS no knob softens, gated on the task's OWN frontmatter (no new classifiers):
  # risk: high, and any recorded ask-rule approval on the task (approved: entries mark
  # STOP-AND-ASK surfaces a human had to clear — their merge stays a human-lane decision).
  # FAIL-CLOSED on a task with NO risk: frontmatter at all: an unclassified task cannot prove
  # it is not stop-and-ask material, so it keeps today's integrator path silently — which also
  # keeps every pre-6.1 fixture (none carry risk:) byte-identical. On EVERY refusal or skip,
  # behavior before this call is byte-for-byte today's handoff.
  local id="$1" notice="${2:-}"
  local lk; lk="$(cfg landing self)"
  [ "$lk" = "self" ] || return 0     # landing: integrator (or any other value) → classic handoff
  local tf="$BOARD/review/$id.md"
  [ -f "$tf" ] || return 0
  local rk; rk="$(fm_get risk "$tf" 2>/dev/null || true)"
  local ap; ap="$(fm_list approved "$tf" 2>/dev/null || true)"
  if [ "$rk" = "high" ] || [ -n "$ap" ]; then
    say "risk: high never self-lands — a human must approve the merge; task stays in review/"
    return 0
  fi
  [ -n "$rk" ] || return 0           # no risk: frontmatter → unclassified → integrator path
  note "landing: self — continuing into land $id (the lease is the integration lane: this waits its turn)"
  local lrc=0
  ( cd "$PRIMARY" && "$SELF" land "$id" ) || lrc=$?
  if [ "$lrc" -eq 3 ]; then
    return 3                         # int_on printed the final `queued: ` line — nothing after it
  fi
  if [ "$lrc" -ne 0 ]; then
    note "⚠ self-land failed (rc $lrc) — the work is safe on feat/$id and $id stays in review/ for the integration lane"
    return 0
  fi
  if [ "$notice" != "integrate" ]; then
    note "$id landed on the wave — mid-wave lands never seal; the last lane out seals"
    return 0
  fi
  # last lane out seals the wave, then finishes every LANDED review task (a refused risk: high
  # task has no landed commit and stays in review/ for the human lane).
  local src=0
  ( cd "$PRIMARY" && "$SELF" seal ) || src=$?
  if [ "$src" -ne 0 ]; then
    note "⚠ wave not sealed (rc $src) — $id is landed and safe; close the wave with: bash ops/polaris seal"
    return 0
  fi
  local f tid
  for f in "$BOARD/review/"*.md; do
    [ -f "$f" ] || continue
    tid="$(fm_get id "$f" 2>/dev/null || true)"
    [ -n "$tid" ] || continue
    landed_sha "$tid" >/dev/null 2>&1 || continue
    ( cd "$PRIMARY" && "$SELF" done "$tid" ) \
      || note "⚠ done $tid failed — finish it by hand: bash ops/polaris done $tid"
  done
  return 0
}

cmd_release() { # release <ID> [--to ready|blocked] [-m "note"]
  local id="${1:?usage: polaris release <ID> [--to ready|blocked] [-m note]}"; shift
  local to="ready" msg=""
  while [ $# -gt 0 ]; do case "$1" in
    --to) to="$2"; shift 2;; -m) msg="$2"; shift 2;; *) die "unknown flag $1";;
  esac; done
  [ "$to" = "ready" ] || [ "$to" = "blocked" ] || die "--to must be ready or blocked"
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/"
  mutex_on
  mv "$BOARD/active/$id.md" "$BOARD/$to/$id.md"
  set_fm owner null "$BOARD/$to/$id.md"; set_fm status "$to" "$BOARD/$to/$id.md"
  who
  [ -n "$msg" ] && printf -- '- ⛔ released by %s: %s\n' "$WHO" "$msg" >> "$BOARD/$to/$id.md"
  # v2: --to blocked is its own board event ("blocked", severity gate at the hook) — a recipe can
  # now tell "the run waits on you" from an FYI. --to ready keeps ev "release". Note text unchanged.
  local ev="release"; [ "$to" = "blocked" ] && ev="blocked"
  evt "$ev" "$id" "→ $to: $msg"
  board_commit "chore(board): release $id → $to"
  sync_board
  mutex_off; trap - EXIT
  local wt; wt="$(wt_path "$id")"
  [ -d "$wt" ] && git -C "$PRIMARY" worktree remove --force "$wt" 2>/dev/null || true
  lock_drop "$id"; [ "$CLAIM_MODE" = "claim-branch" ] && claim_branch_drop "$id"
  say "$id → $to/ · lock released · worktree removed (branch feat/$id kept)"
}

fm_append_item() { # fm_append_item <field> <item> <taskfile> — THE append-only front-matter list
  # writer, shared by grant (files_owned) and approve (approved) so the 25 lines of awk exist ONCE
  # (ops/contracts/ask-approval.md § 3). Keeps the list's shape: block list gets a new "  - <item>" ·
  # "[a, b]" flow list gets ", <item>" before the ] · "[]" is filled · an inline scalar becomes a
  # two-item flow list (the item itself passes through verbatim). Append-only by construction:
  # existing entries are never removed or rewritten. rc 1 + file untouched when the named field is
  # missing or malformed — it NEVER invents a field. POSIX awk, bash 3.2.
  local fld="$1" p="$2" tf="$3" tmp="$3.tmp.$$"
  awk -v k="$fld" -v p="$p" '
    inblock && /^[ \t]*-[ \t]/ { print; ind=$0; sub(/-.*$/,"",ind); next }
    inblock { if (ind=="") ind="  "; print ind "- " p; inblock=0; done=1 }
    /^---[\r]?$/ { fs++; print; next }
    fs==1 && !done && !inblock && index($0, k":")==1 {
      t=substr($0, length(k)+2)
      sub(/^[ \t]*/,"",t); sub(/[ \t]#.*$/,"",t); sub(/[ \t\r]*$/,"",t)
      if (t == "") { print; inblock=1; next }             # block list opens on the next lines
      if (t ~ /^\[/) {                                    # inline flow list, incl. []
        i=index($0, "]"); if (i == 0) { print; next }     # no ] → malformed → refuse via !done
        if (t ~ /^\[[ \t]*\]$/) ins=p; else ins=", " p
        print substr($0, 1, i-1) ins substr($0, i)
      } else {
        print k": [" t ", " p "]"                         # inline scalar → flow list, entry kept
      }
      done=1; next
    }
    { print }
    END {
      if (inblock) { if (ind=="") ind="  "; print ind "- " p; done=1 }
      if (!done) exit 3
    }' "$tf" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$tf"
}

grant_append_owned() { # grant_append_owned <path> <taskfile> — the files_owned specialization of
  # fm_append_item, kept under its public name (and signature) so cmd_grant and the grant drill are
  # byte-for-byte what they were before the writer was generalized for T-048.
  fm_append_item files_owned "$1" "$2"
}

cmd_grant() { # grant <ID> <path> -m "why" — the SANCTIONED files_owned amendment (ops/contracts/grant.md).
  # Adds one path to a CLAIMED task's ownership, with the why on the record. Disjointness (the ONE
  # IDEA) survives mechanically: any overlap with ANOTHER ready/active task's files_owned — checked
  # with the same pattern semantics as verify (exact · dir/ prefix · glob), in BOTH directions via
  # pat_overlap — refuses outright, and a refusal mutates NOTHING: no partial write, no commit.
  # RULES.tsv still binds inside granted paths: granting a danger zone does not make it writable
  # (the guard and verify check RULES independently of ownership).
  local id="${1:-}" path="${2:-}" msg=""
  local u='usage: polaris grant <ID> <path> -m "why"'
  [ -n "$id" ] && [ -n "$path" ] || die "$u"
  shift 2
  while [ $# -gt 0 ]; do case "$1" in
    -m) msg="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
    *)  die "unknown flag $1 — $u";;
  esac; done
  [ -n "$msg" ] || die "grant needs -m \"why\" — the reason goes on the task's record ($u)"
  local tf; tf="$(task_file "$id" active)" \
    || die "$id is not in active/ (state: $(task_col "$id" || echo unknown)) — grant amends CLAIMED work only; anything else is a Planner edit"
  # the refusal gate: every files_owned entry of every OTHER task in ready/ ∪ active/ (the claimable set)
  local col f oid pat
  for col in ready active; do
    for f in "$BOARD/$col/"*.md; do
      [ -e "$f" ] || break
      oid="$(basename "$f" .md)"; [ "$oid" = "$id" ] && continue
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        pat_overlap "$path" "$pat" \
          && die "grant refused: '$path' overlaps $oid ($col/) files_owned '$pat' — ownership stays disjoint; chain the tasks (depends_on) or hand back"
      done <<EOF
$(fm_list files_owned "$f")
EOF
    done
  done
  mutex_on
  grant_append_owned "$path" "$tf" \
    || die "grant refused: $tf has no usable files_owned list — planning bug, nothing written"
  printf -- '- grant: %s — %s\n' "$path" "$msg" >> "$tf"
  evt grant "$id" "$path"
  board_commit "chore(board): grant $id $path"
  sync_board
  mutex_off; trap - EXIT
  say "granted: $path → $id files_owned (append-only; why recorded on the task)"
  note "RULES.tsv still binds inside granted paths · prove it when done: polaris verify"
}

cmd_approve() { # approve <ID> <scope> -m "why" — the sibling of grant (ops/contracts/ask-approval.md).
  # Records a HUMAN's yes to an `ask` rule on ONE task's approved: list. It records a decision, it
  # never infers one: no ask rule gating <scope> → refuse and SAY so (approving something ungated is
  # a no-op, never a silent write) · any feat/* branch → refuse (a Builder approving itself must be
  # mechanically impossible, not merely discouraged) · every refusal mutates NOTHING. The approval is
  # per-task and per-scope and expires with the task; `path` and `content` rules consult it never.
  local id="${1:-}" scope="${2:-}" msg=""
  local u='usage: polaris approve <ID> <scope> -m "why"'
  [ -n "$id" ] && [ -n "$scope" ] || die "$u"
  shift 2
  while [ $# -gt 0 ]; do case "$1" in
    -m) msg="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
    *)  die "unknown flag $1 — $u";;
  esac; done
  [ -n "$msg" ] || die "approve needs -m \"why\" — the human's reason goes on the task's record ($u)"
  # the load-bearing containment: an approval mechanism is exactly what a stuck agent rationalizes
  # its way into, so the refusal is mechanical — feat/* is where Builders live, and no session on a
  # feat branch can record an approval, its own or anyone else's.
  local br; br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*)
    die "approve refused on $br — a Builder never approves its own gate. Hand back instead: the human records their yes from the primary checkout (ops/contracts/ask-approval.md § 3)";;
  esac
  # any board column, deliberately wider than grant's active/-only: the ask belongs at the PLAN
  # gate, so the approval usually lands while the task still sits in backlog/ or ready/.
  local tf; tf="$(task_file "$id")" || die "$id is not on the board — check: ops/polaris board-fm"
  ask_rule_matches "$scope" \
    || die "approve refused: no ask-kind rule in ops/RULES.tsv gates '$scope' — approving something ungated is a no-op, nothing written"
  who
  local entry; entry="$scope — $WHO, $(date +%F): $msg"
  mutex_on
  fm_append_item approved "$entry" "$tf" \
    || die "approve refused: $tf has no approved: front-matter field — add the empty field from ops/templates/TASK.md first; nothing written"
  printf -- '- approve: %s — %s\n' "$scope" "$msg" >> "$tf"
  evt approve "$id" "$scope"
  board_commit "chore(board): approve $id $scope"
  sync_board
  mutex_off; trap - EXIT
  say "approved: $scope → $id approved: (a recorded human decision — per-task, per-scope, expires with the task)"
  note "verify/handoff will name this approval when it clears the rule, so the Integrator sees the exception"
}

# ------------------------------------------------------------------ pack (5.21.0)
# THE 1-HOP CONTEXT. `ops/contracts/context-pack.md`.
#
# Until now "read the brain first, run `find` before Grep, match the house style, check the
# contract" was PROSE in five role files and every conductor kickoff. Prose is something a model
# can skip, and skipping it is invisible until the diff comes back in the wrong style against an
# interface nobody read. Worse, an agent that DOES follow it spends 6-15 round trips assembling
# facts the CLI could have handed it in one — each round trip a tool call, a result, and a re-read
# of everything above it in the transcript.
#
# `pack` is the same seven things as ONE call. It reads; it never writes, never touches git refs,
# never mutates the board. Every section degrades to a one-line note rather than dying, because a
# missing brain or an unindexed repo must still produce a usable pack.

pack_section() { printf '\n=== %s ===\n' "$1"; }

pack_brain_grep() { # pack_brain_grep <file> <pattern> — brain lines mentioning an owned path.
  # The brain already distills gotchas and co-change; the only new thing here is RELEVANCE — a
  # Builder needs the two lines about ITS files, not all 60.
  local bf="$PRIMARY/.polaris/brain/$1" pat="$2"
  [ -f "$bf" ] && [ -n "$pat" ] || return 0
  grep -E "$pat" "$bf" 2>/dev/null | head -8 || true
}

cmd_pack() { # pack <ID> — the whole context for one task, in ONE call. Read-only.
  local id="${1:-}" f owned ctx contract pts risk title dirs d p pat any
  [ -n "$id" ] || id="$(current_task_id 2>/dev/null || true)"
  [ -n "$id" ] || die "usage: polaris pack <ID>   (or run it inside a feat/<ID> worktree)"
  f="$(task_file "$id" 2>/dev/null || true)"
  [ -n "$f" ] && [ -f "$f" ] || die "no task $id on the board — check: ops/polaris board-fm"

  title="$(fm_get title "$f")"; pts="$(fm_get points "$f")"; risk="$(fm_get risk "$f")"
  owned="$(fm_list files_owned "$f" 2>/dev/null | grep . || true)"
  ctx="$(fm_list context_files "$f" 2>/dev/null | grep . || true)"
  contract="$(fm_get contract "$f" 2>/dev/null || true)"
  # tier: route's line 1 for this task (ops/contracts/model-routing.md) — a model: frontmatter
  # tier word wins; a literal model name keeps the derived tier (informational), exactly as route.
  local pov ptier
  pov="$(fm_get model "$f" 2>/dev/null || true)"
  case "$pov" in
    strong|mid|cheap) ptier="$pov";;
    *) ptier="$(tier_for "$pts" "$risk")";;
  esac

  printf 'PACK %s — %s\n' "$id" "$title"
  printf 'points %s · risk %s · column %s · tier %s\n' "${pts:-?}" "${risk:-normal}" "$(task_col "$id" 2>/dev/null || echo '?')" "$ptier"
  printf 'This is your whole context. You should not need to go hunting for more.\n'

  # 1. the task itself — Why becomes the commit body, acceptance boxes are the definition of done.
  pack_section "THE TASK  ($f)"
  awk '/^## Why/{on=1} on&&/^## /&&!/^## Why/&&!seen{seen=1} on{print}' "$f" 2>/dev/null \
    | awk 'NR<=60' | grep . || printf '(no ## Why section — ask before coding)\n'

  # 2. the contract, VERBATIM. Invariant 3: never invent an interface.
  pack_section "THE CONTRACT"
  if [ -n "$contract" ] && [ -f "$PRIMARY/$contract" ]; then
    printf '# %s\n' "$contract"; awk 'NR<=120' "$PRIMARY/$contract"
  elif [ -n "$contract" ]; then
    printf '⛔ contract %s is NAMED but MISSING — Invariant 3: park this in blocked/, never guess\n' "$contract"
  else
    printf '(none — a change this size usually has no seam. Do not invent one.)\n'
  fi

  # 3. house style, DETECTED. The point: match what the repo already does without re-inferring it.
  pack_section "HOUSE STYLE — match this, it is what the repo already does"
  if [ -f "$PRIMARY/.polaris/brain/prefs.md" ]; then
    grep -E '^\|' "$PRIMARY/.polaris/brain/prefs.md" 2>/dev/null | head -8 || true
  else
    printf '(no brain yet — run: ops/polaris brain)\n'
  fi

  # 4. what you may touch, and what you may only read. Invariant 1 is the whole job.
  pack_section "FILES YOU OWN — edit ONLY these"
  printf '%s\n' "${owned:-(none declared — that is a bug in the task, stop and ask)}"
  if [ -n "$ctx" ]; then
    printf '\nread-only context:\n%s\n' "$ctx"
  fi

  # 5. the neighbourhood + 6. the public surface you must not break. Both already exist as
  # generated artifacts; pack's only contribution is asking for exactly the owned paths.
  pack_section "WHERE THIS LIVES"
  dirs="$(printf '%s\n' "$owned" | sed -n 's|/[^/]*$||p' | sort -u | grep . || true)"
  any=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -f "$PRIMARY/.polaris/brain/code-map.md" ]; then
      awk -v d="## $d/" '$0==d{on=1;print;next} on&&/^## /{exit} on{print}' \
        "$PRIMARY/.polaris/brain/code-map.md" 2>/dev/null | grep . && any=1
    fi
  done <<EOF
$dirs
EOF
  [ -n "$any" ] || printf '(no code-map entry — run: ops/polaris brain)\n'

  pack_section "PUBLIC SURFACE — do not break these signatures"
  any=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # `find --api` is the same index `check --scaffold` locks goldens from, so what prints here is
    # exactly what a shape regression would flag later.
    "$SELF" find --api "$p" 2>/dev/null | head -25 | grep . && any=1
  done <<EOF
$owned
EOF
  [ -n "$any" ] || printf '(nothing indexed for these paths — new files, or run: ops/polaris brain)\n'

  # 7. the lessons that already cost someone tokens, filtered to THIS task's files.
  pat="$(printf '%s\n' "$owned" | sed -e 's/[].[^$*\\/]/\\&/g' | grep . | tr '\n' '|' | sed 's/|$//')"
  if [ -n "$pat" ]; then
    pack_section "KNOWN TRAPS IN THESE FILES"
    { pack_brain_grep learned.md "$pat"; pack_brain_grep gotchas.md "$pat"; } | grep . \
      || printf '(none recorded for these paths)\n'
  fi

  # 8. what will actually be run against you. Knowing this up front is what stops a Builder
  # writing a verify: it cannot pass, or hand-checking something the list already proves.
  pack_section "WHAT PROVES IT — polaris verify runs exactly this"
  fm_list verify "$f" 2>/dev/null | grep . || printf '(no verify: list — add one, narrow, each under ~10s)\n'
  printf '\nthen the fast tier: %s\n' "$(cfg test_fast "$(cfg test '(no test: configured)')")"

  printf '\n--- end of pack. Anything beyond this needs a one-line reason in the task Notes. ---\n'
  return 0
}

cmd_resume() { # resume [ID] — re-enter an already-claimed active task without re-claiming it: after a
  # Builder crash, a kickback, or simply a fresh session. sweep only FLAGS stale locks; this is the
  # action that takes one over — recreates the worktree if it vanished, refreshes the lock's age+owner.
  local id="${1:-}"
  [ -n "$id" ] || id="$(current_task_id)" || die "usage: polaris resume <ID> (or run inside a feat/<ID> worktree)"
  board_materialize || true   # fresh clone: rebuild ops/board/ from polaris/board BEFORE the lookup
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/ — only a claimed task can be resumed; for a fresh one: polaris claim"
  who; mkdir -p "$LOCKS/$id"; { date +%s; echo "$WHO"; echo "$id"; } > "$LOCKS/$id/meta"   # adopt + refresh the lock
  local wt; wt="$(wt_path "$id")"
  if [ ! -d "$wt" ]; then
    note "worktree was gone — recreating it from feat/$id"
    wt_add "$id"   # T-059: same primitive as claim — honest stderr, index.lock-only retries
  fi
  say "resumed $id → cd \"$wt\""
  note "task file: \"$BOARD/active/$id.md\" (primary-anchored — worktrees do not contain ops/board)"
  if grep -q '⛔' "$tf" 2>/dev/null; then note "last note on this task (why it is back in active/):"; grep '⛔' "$tf" | tail -1 | sed 's/^[[:space:]]*/     /'; fi
  note "when green: polaris handoff   ·   to abort: polaris release $id --to ready"
}
