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
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    f="$(task_file "$cand" ready)" || { [ "$explicit" = 1 ] && die "$cand is not in ready/ (state: $(task_col "$cand" || echo unknown))"; continue; }
    if [ "$CLAIM_MODE" = "claim-branch" ]; then
      has_remote || die "claim: claim-branch requires an origin remote"
      if claim_branch_take "$cand"; then lock_take "$cand" || true; got="$cand"; break
      elif [ "$explicit" = 1 ]; then die "taken — $cand claimed on another machine; try: polaris claim"
      fi
    else
      if lock_take "$cand"; then got="$cand"; break
      elif [ "$explicit" = 1 ]; then die "taken — $cand is locked by another session; try: polaris claim"
      fi
    fi
  done <<EOF
$candidates
EOF
  [ -n "$got" ] || die "every ready task is currently claimed — nothing free to take"
  id="$got"
  FAIL_LOCK_ID="$id"; trap on_die EXIT

  local pts; pts="$(fm_get points "$BOARD/ready/$id.md")"
  mutex_on
  mv "$BOARD/ready/$id.md" "$BOARD/active/$id.md"   # plain mv: board paths are untracked on base
  set_fm owner "$WHO" "$BOARD/active/$id.md"
  set_fm branch "feat/$id" "$BOARD/active/$id.md"
  set_fm status active "$BOARD/active/$id.md"
  evt claim "$id" "" "$pts"
  board_commit "chore(board): claim $id"
  sync_board
  mutex_off; FAIL_LOCK_ID=""; trap - EXIT

  local wt; wt="$(wt_path "$id")"
  mkdir -p "$PRIMARY/.polaris/wt"
  # worktree add runs OUTSIDE the board mutex (it is slow, and each task's tree is distinct), so two
  # near-simultaneous claims — exactly what a fleet's panes are — can collide on git's index.lock.
  # Each adds a different worktree, so a brief retry is safe and keeps the fan-out promise real.
  local wi
  for wi in 1 2 3 4 5 6 7; do
    if git -C "$PRIMARY" show-ref --verify -q "refs/heads/feat/$id"; then
      git -C "$PRIMARY" worktree add -q "$wt" "feat/$id" 2>/dev/null && break
    else
      git -C "$PRIMARY" worktree add -q "$wt" -b "feat/$id" "$BASE" 2>/dev/null && break
    fi
    [ "$wi" -ge 7 ] && die "worktree add failed for $id (git index busy after retries) — retry: polaris claim $id"
    sleep 0.3
  done
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
}

cmd_verify() {
  local id="${1:-}"; [ -n "$id" ] || id="$(current_task_id)" || die "not on a feat/<ID> branch — pass the ID"
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/"
  check_ownership "$tf" HEAD
  check_rules HEAD
  run_verify_cmds "$tf"
}

cmd_handoff() {
  local id="${1:-}"; [ -n "$id" ] || id="$(current_task_id)" || die "not on a feat/<ID> branch — pass the ID"
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/"
  git diff --quiet && git diff --cached --quiet || die "uncommitted changes — commit on feat/$id first"
  check_ownership "$tf" "feat/$id"
  check_rules "feat/$id"
  run_verify_cmds "$tf"
  map_delta_hint "$tf" "feat/$id"
  # publish: pr — feat branches never leave the machine; seal pushes ONE integrate branch instead
  # (ops/contracts/publish-modes.md). Everything else stays byte-identical to direct mode.
  publish_resolve
  if [ "$PUB" != "pr" ] && has_remote; then
    git push -q -u origin "feat/$id"
  fi
  mutex_on
  mv "$BOARD/active/$id.md" "$BOARD/review/$id.md"
  set_fm status review "$BOARD/review/$id.md"
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
  case "$notice" in
    integrate) say "all lanes done — nothing left building. Integrate now: \"You are the INTEGRATOR. Land everything in ops/board/review/.\"";;
    queue)     note "$nrdy ready task(s) still queued — say start (or: bash ops/polaris fleet $nrdy --launch) to build them";;
  esac
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

grant_append_owned() { # grant_append_owned <path> <taskfile> — append ONE files_owned entry, keeping
  # the list's shape: block list gets a new "  - <path>" item · "[a, b]" flow list gets ", <path>"
  # before the ] · "[]" is filled · an inline scalar becomes a two-item flow list (the entry itself
  # passes through verbatim). Append-only by construction: existing entries are never removed or
  # rewritten. rc 1 + file untouched when files_owned is missing or malformed. POSIX awk, bash 3.2.
  local p="$1" tf="$2" tmp="$2.tmp.$$"
  awk -v p="$p" '
    inblock && /^[ \t]*-[ \t]/ { print; ind=$0; sub(/-.*$/,"",ind); next }
    inblock { if (ind=="") ind="  "; print ind "- " p; inblock=0; done=1 }
    /^---[\r]?$/ { fs++; print; next }
    fs==1 && !done && !inblock && index($0, "files_owned:")==1 {
      t=substr($0, 13)
      sub(/^[ \t]*/,"",t); sub(/[ \t]#.*$/,"",t); sub(/[ \t\r]*$/,"",t)
      if (t == "") { print; inblock=1; next }             # block list opens on the next lines
      if (t ~ /^\[/) {                                    # inline flow list, incl. []
        i=index($0, "]"); if (i == 0) { print; next }     # no ] → malformed → refuse via !done
        if (t ~ /^\[[ \t]*\]$/) ins=p; else ins=", " p
        print substr($0, 1, i-1) ins substr($0, i)
      } else {
        print "files_owned: [" t ", " p "]"               # inline scalar → flow list, entry kept
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

cmd_resume() { # resume [ID] — re-enter an already-claimed active task without re-claiming it: after a
  # Builder crash, a kickback, or simply a fresh session. sweep only FLAGS stale locks; this is the
  # action that takes one over — recreates the worktree if it vanished, refreshes the lock's age+owner.
  local id="${1:-}"
  [ -n "$id" ] || id="$(current_task_id)" || die "usage: polaris resume <ID> (or run inside a feat/<ID> worktree)"
  board_materialize || true   # fresh clone: rebuild ops/board/ from polaris/board BEFORE the lookup
  local tf; tf="$(task_file "$id" active)" || die "$id is not in active/ — only a claimed task can be resumed; for a fresh one: polaris claim"
  mkdir -p "$LOCKS/$id"; { date +%s; echo "$WHO"; echo "$id"; } > "$LOCKS/$id/meta"   # adopt + refresh the lock
  local wt; wt="$(wt_path "$id")"
  if [ ! -d "$wt" ]; then
    note "worktree was gone — recreating it from feat/$id"
    mkdir -p "$PRIMARY/.polaris/wt"
    git -C "$PRIMARY" worktree add -q "$wt" "feat/$id" 2>/dev/null \
      || git -C "$PRIMARY" worktree add -q "$wt" -b "feat/$id" "$BASE" 2>/dev/null \
      || die "could not recreate the worktree for $id"
  fi
  say "resumed $id → cd \"$wt\""
  note "task file: \"$BOARD/active/$id.md\" (primary-anchored — worktrees do not contain ops/board)"
  if grep -q '⛔' "$tf" 2>/dev/null; then note "last note on this task (why it is back in active/):"; grep '⛔' "$tf" | tail -1 | sed 's/^[[:space:]]*/     /'; fi
  note "when green: polaris handoff   ·   to abort: polaris release $id --to ready"
}
