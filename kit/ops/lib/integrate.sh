# POLARIS lib/integrate.sh — the Integrator machinery sourced by ops/polaris (the lib loader):
# audit/kickback/done, the landed-commit message, land/land --express, seal/seal --sync, history, rollback.

cmd_kickback() { # Integrator: red merge → review→active with the failure note; lock+branch stay
  local id="${1:?usage: polaris kickback <ID> -m \"failure\"}"; shift
  local msg=""; [ "${1:-}" = "-m" ] && msg="$2"
  local tf; tf="$(task_file "$id" review)" || die "$id is not in review/"
  mutex_on
  mv "$BOARD/review/$id.md" "$BOARD/active/$id.md"
  set_fm status active "$BOARD/active/$id.md"
  [ -n "$msg" ] && printf -- '- ⛔ kicked back by Integrator: %s\n' "$msg" >> "$BOARD/active/$id.md"
  evt kickback "$id" "$msg"
  board_commit "chore(board): kickback $id"
  sync_board
  mutex_off; trap - EXIT
  say "$id → active/ (lock, worktree, branch untouched — Builder resumes there)"
}

cmd_audit() { # Integrator: ownership check of a review branch, from anywhere
  local id="${1:?usage: polaris audit <ID>}"
  local tf; tf="$(task_file "$id")" || die "no task file for $id"
  check_ownership "$tf" "feat/$id"
  check_rules "feat/$id"
}

cmd_run_verify() { # Integrator: re-run a task's verify commands in CWD (e.g. on integrate branch)
  local id="${1:?usage: polaris run-verify <ID>}"
  local tf; tf="$(task_file "$id")" || die "no task file for $id"
  run_verify_cmds "$tf"
}

landed_sha() { # landed_sha <ID> [ref] — SHA of the squash commit in <ref> (default $BASE) whose
  # subject ENDS with [<ID>] (what `land` writes). --fixed-strings so the grep is literal; the
  # suffix check below is what keeps [T-1] from ever matching [T-10]. rc 1 = no landed commit.
  # The ref parameter lets `report`/`seal` grep integrate/<date> before a wave reaches base.
  local id="$1" ref="${2:-$BASE}" line sha subj
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sha="${line%% *}"; subj="${line#* }"
    case "$subj" in *"[$id]") printf '%s' "$sha"; return 0;; esac
  done <<EOF
$(git -C "$PRIMARY" log --fixed-strings --grep "[$id]" --format='%H %s' "$ref" 2>/dev/null)
EOF
  return 1
}

cmd_done() { # Integrator only, after the task is landed (squash) or merged (legacy) into BASE
  local id="${1:?usage: polaris done <ID>}"
  local tf; tf="$(task_file "$id" review)" || die "$id is not in review/"
  # merged? A squash landing (polaris land) is NEVER an ancestor of $BASE, so ancestry alone
  # went blind the day land shipped. Rule 1: the landed commit record — subject suffix [<ID>]
  # in $BASE history. Rule 2 (legacy fallback): feat-branch ancestry, so hand --no-ff merges
  # per MANUAL.md keep working. Both fail → not merged.
  local landed; landed="$(landed_sha "$id" || true)"
  if [ -z "$landed" ]; then
    git -C "$PRIMARY" merge-base --is-ancestor "feat/$id" "$BASE" 2>/dev/null \
      || die "$id is not in $BASE — land it (or merge it), then done"
  fi
  local deltas; deltas="$(fm_list map_delta "$tf" 2>/dev/null || true)"   # BEFORE the mv — path vanishes after
  local pts; pts="$(fm_get points "$tf")"
  # A non-empty map_delta lands as ONE separate docs(map) commit on $BASE (quiet-board contract) —
  # the only base commit any board mutation makes. Require the checkout BEFORE mutating anything,
  # so a wrong branch aborts clean; empty delta commits nothing on $BASE.
  if [ -n "$deltas" ]; then
    local br; br="$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ "$br" = "$BASE" ] || die "done: $id carries a map_delta — it lands as a docs(map) commit on $BASE; check out $BASE in the primary first (currently on ${br:-?})"
  fi
  mutex_on
  mv "$BOARD/review/$id.md" "$BOARD/done/$id.md"
  set_fm status done "$BOARD/done/$id.md"
  # stamp the landed commit onto the task — the durable, human-readable record (rollback's fast
  # path; sweep's stray test). Rides this same board commit; legacy merges have no SHA to stamp.
  [ -n "$landed" ] && fm_stamp landed "$landed" "$BOARD/done/$id.md"
  # apply map_delta so MAP.md never rots (Integrator is its only writer → no conflict)
  local d applied=0 first=""
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    if [ $applied -eq 0 ]; then printf '\n' >> "$OPS/MAP.md"; first="$d"; fi
    printf -- '- %s  (%s, %s)\n' "$d" "$id" "$(date +%F)" >> "$OPS/MAP.md"; applied=1
  done <<EOF
$deltas
EOF
  if [ "$applied" -eq 1 ]; then   # MAP.md stays on $BASE — pathspec-limited commit, index.lock retry
    local mi mok=0
    for mi in 1 2 3 4 5; do
      if git -C "$PRIMARY" add -- "$OPS/MAP.md" 2>/dev/null \
         && git -C "$PRIMARY" commit -q -m "docs(map): $id $first" -- "$OPS/MAP.md" 2>/dev/null; then mok=1; break; fi
      sleep 0.3
    done
    [ "$mok" -eq 1 ] || { git -C "$PRIMARY" add -- "$OPS/MAP.md" && git -C "$PRIMARY" commit -q -m "docs(map): $id $first" -- "$OPS/MAP.md"; } \
      || die "docs(map) commit failed for $id (error above)"
  fi
  evt done "$id" "" "$pts"
  board_commit "chore(board): done $id"
  sync_board
  mutex_off; trap - EXIT
  board_changed_touch   # freshness beacon for the brain (ops/contracts/brain.md) — best-effort
  brain_refresh_if_present  # v1.1: done mirrors seal — refresh AFTER the touch so the wave close
                            # (land → seal → run-verify → done) ends fresh; ⚠ note on failure, never a red done
  local wt; wt="$(wt_path "$id")"
  [ -d "$wt" ] && git -C "$PRIMARY" worktree remove --force "$wt" 2>/dev/null || true
  # LOCAL tip before the branch dies — a squash-landed branch is never an ancestor of $BASE,
  # so remote cleanup proves the remote is ours by TIP EQUALITY with this SHA instead.
  local ltip; ltip="$(git -C "$PRIMARY" rev-parse -q --verify "refs/heads/feat/$id" 2>/dev/null || true)"
  git -C "$PRIMARY" branch -q -D "feat/$id" 2>/dev/null || true
  # handoff pushed feat/<ID> to origin; a landed task must not leave a dead branch there —
  # that is how a sprint turns into a wall of stale branches on the host. Delete only when the
  # remote tip == the local tip we just landed from (squash landings), or is provably in $BASE
  # (legacy merges); a diverged tip is left for sweep to flag, never lost.
  local remote_note=""
  if has_remote; then
    local rsha; rsha="$(git -C "$PRIMARY" ls-remote origin "refs/heads/feat/$id" 2>/dev/null | cut -f1)"
    if [ -n "$rsha" ]; then
      if [ -n "$ltip" ] && [ "$rsha" = "$ltip" ]; then
        git -C "$PRIMARY" push -q origin ":refs/heads/feat/$id" 2>/dev/null && remote_note=" (local+remote)" || true
      elif git -C "$PRIMARY" cat-file -e "$rsha" 2>/dev/null \
         && git -C "$PRIMARY" merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
        git -C "$PRIMARY" push -q origin ":refs/heads/feat/$id" 2>/dev/null && remote_note=" (local+remote)" || true
      else
        note "⚠ origin/feat/$id tip is not in $BASE — left in place; inspect: git fetch origin feat/$id && git log $BASE..FETCH_HEAD"
      fi
    fi
  fi
  lock_drop "$id"; [ "$CLAIM_MODE" = "claim-branch" ] && claim_branch_drop "$id"
  say "$id → done/ · lock, worktree, branch$remote_note cleaned$( [ $applied -eq 1 ] && echo ' · map_delta applied')"
}

# ------------------------------------------------- clean history (land · seal)
# The history model: one rich squash commit per task (`land`), one tagged --no-ff summary merge
# per sprint (`seal`). `history` reads it back; `rollback` reverts it. Contract:
# ops/contracts/clean-history.md — applies forward only; existing history is never rewritten.

cmd_task_commit_msg() { # task-commit-msg <task-file> — the task's landed-commit message on stdout.
  # PURE: reads one file, mutates NOTHING. `land` is the consumer — commit quality is authored at
  # grooming time (## Why, scope:, checkboxes, Notes), not improvised at merge time.
  local tf="${1:?usage: polaris task-commit-msg <task-file>}"
  [ -f "$tf" ] || die "no such task file: $tf"
  local id title ttype ctype scope first why crit notes files
  id="$(fm_get id "$tf")"; [ -n "$id" ] || die "no id: in frontmatter — not a task file? $tf"
  title="$(fm_get title "$tf")"
  ttype="$(fm_get type "$tf")"
  case "$ttype" in            # type map per clean-history v2.2; spike/missing/unknown → chore
    feature) ctype=feat;;
    bug)     ctype=fix;;
    test)    ctype=test;;
    docs)    ctype=docs;;
    *)       ctype=chore;;
  esac
  scope="$(fm_get scope "$tf")"
  if [ -z "$scope" ]; then    # fallback: first path component of the first files_owned entry
    first="$(fm_list files_owned "$tf" | head -1)"
    scope="${first%%/*}"
  fi
  # Why body: between the ## Why heading (legacy ## Why this exists accepted — pre-5.12 boards)
  # and the next ## heading, blank edges trimmed. Lands in the commit body VERBATIM.
  why="$(awk '
    /^## Why[ \t\r]*$/ || /^## Why this exists[ \t\r]*$/ { on=1; next }
    on && /^## / { exit }
    on { sub(/\r$/,""); if (!got && $0 ~ /^[ \t]*$/) next; got=1; print }
  ' "$tf")"
  # What changed: the acceptance checkboxes, "- [ ] "/"- [x] " marker stripped
  crit="$(awk '
    /^## Acceptance/ { on=1; next }
    on && /^## / { on=0 }
    on && /^[ \t]*- \[[ xX]\]/ { sub(/\r$/,""); sub(/^[ \t]*- \[[ xX]\][ \t]*/,""); print "- " $0 }
  ' "$tf")"
  # Notes: the Builder discoveries — "- " lines only, comment lines and ⛔ traffic filtered out
  notes="$(awk '
    /^## Notes/ { on=1; next }
    on && /^## / { on=0 }
    on && /^[ \t]*- / {
      sub(/\r$/,"")
      if (index($0, "<!--")) next
      if (index($0, "⛔")) next
      sub(/^[ \t]*/,""); print
    }
  ' "$tf")"
  files="$(fm_list files_owned "$tf" | awk 'NR>1 {printf ", "} {printf "%s", $0} END {printf "\n"}')"
  printf '%s(%s): %s [%s]\n\n' "$ctype" "$scope" "$title" "$id"
  [ -n "$why" ] && printf '%s\n\n' "$why"
  printf 'What changed:\n'
  [ -n "$crit" ] && printf '%s\n' "$crit"
  printf '\n'
  [ -n "$notes" ] && printf 'Notes:\n%s\n\n' "$notes"
  printf 'Files: %s\n' "$files"
}

in_primary() { # land/seal mutate the branch checked out in CWD — only the primary checkout
  # qualifies (in a Builder worktree they would mangle a feat branch). Both sides go through the
  # same `cd && pwd -P`, so macOS /tmp symlinks and Git Bash drive-style paths compare equal.
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ "$(cd "$top" 2>/dev/null && pwd -P)" = "$(cd "$PRIMARY" 2>/dev/null && pwd -P)" ]
}

land_slow_suite_hint() { # T-031 (ops/contracts/verification-tiering.md): after a successful land,
  # ONE advisory note when a paranoid repo's suite has outgrown the per-land re-run rule —
  # INTEGRATOR.md's batch-first guidance, made mechanical. Print-only: silent when the stamp is
  # missing/garbled, integration: is not paranoid, or the suite took ≤120s. NEVER changes the
  # exit status.
  local stamp="$PRIMARY/.polaris/last-suite-seconds" secs
  [ "$(cfg integration batch)" = "paranoid" ] || return 0
  [ -f "$stamp" ] || return 0
  secs="$(awk 'NR==1{print $1+0}' "$stamp" 2>/dev/null || true)"
  case "$secs" in ''|*[!0-9]*) return 0;; esac
  [ "$secs" -gt 120 ] || return 0
  note "⚠ suite last took ${secs}s (>2 min) — paranoid re-runs it per land; consider integration: batch"
  return 0
}

cmd_land() { # land <ID> — Integrator, primary checkout, ON the integrate branch: audit, then
  # squash feat/<ID> into exactly ONE commit whose message comes from the task file. Makes NO
  # board write, NO evt, NO board commit — a red task unwinds with a single
  # `git reset --hard HEAD~1`, nothing uncommitted at stake. The landed record IS the commit
  # (subject suffix [<ID>] + Landed-from trailer); `done` stamps it onto the task later.
  # land --express <ID> routes to the one-pass lane (ops/contracts/express-lane.md).
  if [ "${1:-}" = "--express" ]; then
    shift
    cmd_land_express "${1:?usage: polaris land --express <ID>}"
    return 0
  fi
  local id="${1:?usage: polaris land <ID>}"
  local tf; tf="$(task_file "$id" review)" || die "$id is not in review/ — only handed-off work lands"
  in_primary || die "land mutates the checked-out branch — run it in the primary checkout, never a worktree"
  local br; br="$(git rev-parse --abbrev-ref HEAD)"
  [ "$br" != "$BASE" ] || die "you are on $BASE — create the integration branch first: git checkout -b integrate/$(date +%F)"
  git diff --quiet && git diff --cached --quiet || die "working tree not clean — a conflict must be able to reset --hard safely"
  local tip; tip="$(git rev-parse -q --verify "refs/heads/feat/$id")" || die "no local branch feat/$id"
  # audit BEFORE any merge — ownership + rules on the feat branch, exactly as `polaris audit`
  check_ownership "$tf" "feat/$id"
  check_rules "feat/$id"
  # build the message BEFORE the merge, so no failure path can strand staged state
  local msgf; msgf="$(mktemp)"
  cmd_task_commit_msg "$tf" > "$msgf"
  printf '\nLanded-from: %s\n' "$tip" >> "$msgf"
  # git 2.53 narrates a squash even under -q: "Squash commit -- not updating HEAD" on stdout AND, on a
  # divergent merge, "Automatic merge went well; stopped before committing as requested" on STDERR.
  # Silence BOTH on success; on a real conflict re-emit the captured stderr so the failure still
  # surfaces, then kick back. --express shares this path (one fix, both). (clean-history v2.2)
  local mergeerr
  mergeerr="$(mktemp)"
  if ! git merge --squash -q "feat/$id" >/dev/null 2>"$mergeerr"; then
    cat "$mergeerr" >&2                 # real conflict output stays visible on the failure path
    rm -f "$mergeerr"
    git reset -q --hard                 # restore the integrate HEAD, tree clean
    rm -f "$msgf"
    cmd_kickback "$id" -m "squash conflict — planning bug"
    die "squash conflict — $br restored, $id kicked back to active/"
  fi
  rm -f "$mergeerr"
  if git diff --cached --quiet; then
    git reset -q --hard; rm -f "$msgf"
    die "feat/$id brings no changes over $br — nothing to land (your call: kickback it, or done it by hand)"
  fi
  git commit -q -F "$msgf" || { rm -f "$msgf"; git reset -q --hard; die "commit failed — squash unwound, $br clean"; }
  rm -f "$msgf"
  say "landed $id on $br — $(git log -1 --format=%s)"
  note "goes red on the suite? unwind: git reset --hard HEAD~1   ·   bounce: polaris kickback $id -m \"<why>\""
  land_slow_suite_hint
}

cmd_land_express() { # land --express <ID> — ops/contracts/express-lane.md: the integrator's whole
  # long path for the SINGLE-task case, in one pass: integrate branch → audit+land → ONE full
  # CONVENTIONS suite → seal → run-verify → done → branch cleanup. Express collapses SESSIONS,
  # never checks — every gate of the long path runs exactly as it does there. Four pinned
  # refusals below die BEFORE step 1, mutating nothing; `qa` stays the mandatory finish line.
  local id="$1"
  local tf other f ex
  # refusal: express lands exactly one task — <ID> must be review/'s ONLY occupant
  tf="$(task_file "$id" review)" || die "express lands exactly one task — $id is not in review/; hand it off first"
  other=""
  for f in "$BOARD/review/"*.md; do
    [ -e "$f" ] || continue
    case "$f" in */"$id".md) ;; *) other="$(basename "$f" .md)";; esac
  done
  [ -z "$other" ] || die "express lands exactly one task — review/ also holds $other; run the full integrate/land/seal path"
  # refusal: risk: high never rides the express lane — invariant 9's human gate stays human
  if [ "$(fm_get risk "$tf")" = "high" ]; then
    die "risk: high never rides the express lane — integrate it by hand with the human in the loop"
  fi
  # refusal: the express: knob — auto (default; unset = auto) | off; unknown warns once and
  # fails to the full ceremony (off is the safe side)
  ex="$(cfg express auto)"
  case "$ex" in
    auto) ;;
    off)  die "express: off — CONVENTIONS disables the express lane; run the full ceremony";;
    *)    printf "   ⚠ express: '%s' unknown (auto | off) — behaving as off\n" "$ex" >&2
          die "express: off (an unknown value behaves as off) — run the full ceremony";;
  esac
  # refusal: a pr-mode wave ends at a PR the human merges, never at a one-pass seal
  publish_resolve
  [ "$PUB" = "direct" ] || die "express needs publish: direct — publish: pr waves end at a PR, not a seal"
  # context — the same preconditions land/seal enforce: primary checkout, ON <base>, clean tree
  in_primary || die "express runs in the primary checkout — cd \"$PRIMARY\" first"
  local br; br="$(git rev-parse --abbrev-ref HEAD)"
  [ "$br" = "$BASE" ] || die "express starts ON $BASE — you are on $br"
  git diff --quiet && git diff --cached --quiet || die "working tree not clean — commit or stash first"
  # step 1: create/reuse today's integration branch from $BASE
  local date; date="$(date +%F)"
  if git rev-parse -q --verify "refs/heads/integrate/$date" >/dev/null; then
    git checkout -q "integrate/$date"
    git merge -q --ff-only "$BASE" \
      || { git checkout -q "$BASE"; die "integrate/$date exists and cannot fast-forward to $BASE — finish that wave by hand first"; }
  else
    git checkout -q -b "integrate/$date" "$BASE"
  fi
  # step 2: audit + land — existing cmd_land semantics, unchanged
  cmd_land "$id"
  # step 3: the FULL CONVENTIONS suite, ONCE (same set as qa). Red → unwind the land, kick the
  # task back carrying the failing tail, die — the board never keeps a green it didn't earn.
  local k c out tailtxt
  out="$(mktemp)"
  for k in test lint typecheck build uat; do
    c="$(cfg "$k" "")"
    [ -z "$c" ] && continue
    if ( cd "$PRIMARY" && bash -c "$c" ) >"$out" 2>&1; then
      say "$k — green"
    else
      printf '⛔ %s — RED: %s\n' "$k" "$c" >&2
      tail -15 "$out" | sed 's/^/     /' >&2
      tailtxt="$(tail -3 "$out" | tr '\n' ' ' | cut -c1-200)"
      rm -f "$out"
      git reset -q --hard HEAD~1        # unwind the land — integrate/<date> back at $BASE state
      cmd_kickback "$id" -m "express suite red on $k: $tailtxt"
      die "express: $k red — land unwound on integrate/$date, $id kicked back with the failing tail"
    fi
  done
  rm -f "$out"
  # step 4: seal — existing cmd_seal semantics, unchanged (tag sprint/<n>, pushes when remoted)
  cmd_seal "$date"
  # step 5: prove + close — verify: commands on the sealed base, done (landed: stamp + cleanup),
  # then the wave branch goes (its job is finished; a fresh one is cheap tomorrow)
  cmd_run_verify "$id"
  cmd_done "$id"
  git branch -q -D "integrate/$date" 2>/dev/null || true
  say "express: $id landed · sealed · done — one pass, integrate/$date cleaned"
  note "finish line: bash ops/polaris qa"
}

tag_push_recovery_note() { # tag_push_recovery_note <n> — convergent recovery when a moved-tag CAS
  # push is rejected (clean-history v2.1). The stale LOCAL old-sha lease can NEVER win once origin
  # missed a prior wave's tag move — so lease from origin's ACTUAL current tag instead. ls-remote
  # yields the origin value (empty = tag absent → the empty lease correctly expects "not present").
  local n="$1"
  note "⚠ tag push failed — origin's sprint/$n lags a prior wave; the local lease can't win. Lease from origin and retry:"
  note "   git push --force-with-lease=refs/tags/sprint/$n:\$(git ls-remote origin refs/tags/sprint/$n | cut -f1) origin refs/tags/sprint/$n"
}

cmd_seal() { # seal [<date>] | seal --sync [<date>] — close an integration wave: ONE --no-ff merge
  # of integrate/<date> into $BASE, tagged sprint/<n>. Message = sprint header + a bullet per landed
  # commit — the changelog entry `history` shows forever. sprint/<n> always marks the sprint's
  # LATEST sealed checkpoint (contract v2, multi-wave): the first seal of sprint n creates the tag,
  # a later seal of the same n moves it forward. A merge conflict aborts; a human resolves — never
  # auto-resolved. publish: pr (ops/contracts/publish-modes.md): NO local merge — the wave leaves
  # as ONE pushed integrate branch + a PR-create URL, and `seal --sync` finishes after the human
  # merges the PR (merge-commit strategy, never squash).
  local sync=""
  if [ "${1:-}" = "--sync" ]; then sync=1; shift; fi
  local date="${1:-}"; [ -n "$date" ] || date="$(date +%F)"
  publish_resolve
  if [ -n "$sync" ]; then
    [ "$PUB" = "pr" ] || die "publish: direct seals locally — nothing to sync"
    seal_sync "$date"
    return 0
  fi
  in_primary || die "seal runs in the primary checkout — cd \"$PRIMARY\" first"
  git diff --quiet && git diff --cached --quiet || die "working tree not clean — commit or stash first"
  git rev-parse -q --verify "refs/heads/integrate/$date" >/dev/null \
    || die "no branch integrate/$date — land tasks on it first (a different day's branch? seal <date>)"
  local subjects
  subjects="$(git log --reverse --format=%s "$BASE..integrate/$date" | grep -v '^chore(board):' || true)"
  [ -n "$subjects" ] || die "nothing to seal — $BASE..integrate/$date has only board commits"
  # <n> + <goal> from the ops/SPRINT.md header: "# SPRINT <n> — <goal>" (goal ends at 2+ spaces
  # or capacity:; — or - both accepted)
  local hdr n goal
  hdr="$(sed -n 's/^# SPRINT //p' "$OPS/SPRINT.md" 2>/dev/null | head -1 | tr -d '\r')"
  n="${hdr%%[!0-9]*}"
  [ -n "$n" ] || die "cannot read the sprint number — ops/SPRINT.md needs a '# SPRINT <n> — <goal>' header"
  goal="$(printf '%s' "${hdr#"$n"}" | sed -e 's/^[[:space:]]*//' -e 's/^—[[:space:]]*//' -e 's/^-[[:space:]]*//' \
      -e 's/[[:space:]][[:space:]].*$//' -e 's/[[:space:]]*capacity:.*$//' -e 's/[[:space:]]*$//')"
  # tag gate (contract v2): absent → first wave of sprint n. Present AND an ancestor of $BASE →
  # a previous wave's checkpoint; the tag moves to this wave's merge below. Neither → the number
  # was REUSED on unrelated history — refuse before anything mutates.
  local oldtag
  oldtag="$(git rev-parse -q --verify "refs/tags/sprint/$n" || true)"
  if [ -n "$oldtag" ] && ! git merge-base --is-ancestor "$oldtag" "$BASE" 2>/dev/null; then
    die "sprint/$n exists and is not in $BASE history — reused sprint number; bump the ops/SPRINT.md header"
  fi
  # T-023: the sprint report rides the wave. Commit it on integrate/<date> BEFORE the merge (direct)
  # / the push (pr). $subjects was captured above, so the report never appears in the merge bullets;
  # it is a docs(sprint-N) commit with no [<ID>] suffix (ID resolution ignores it).
  git checkout -q "integrate/$date"
  seal_report_commit "$n" "$date"
  if [ "$PUB" = "pr" ]; then
    # ---------------- publish: pr — the ENTIRE pr fork (one block, one seam) ----------------
    # All preconditions + the tag gate above ran check-only. From here: NO local merge, NO tag,
    # NO $BASE ref change (local or remote) — everything mutating waits for `seal --sync` after
    # the human merges the PR. Tasks stay in review/, locks stay, integrate/<date> stays.
    # (T-023: the wave's sprint-report commit lands HERE, on integrate/$date, before the push.)
    has_remote || die "publish: pr needs an origin remote — nowhere to push integrate/$date"
    git push -q -u origin "integrate/$date" || die "push of integrate/$date failed — check origin access"
    board_changed_touch   # brain freshness (ops/contracts/brain.md): the wave left the machine.
                          # No auto-refresh here — the fold happens at `seal --sync`, not now.
    local prurl
    prurl="$(pr_create_url "$(git -C "$PRIMARY" remote get-url origin 2>/dev/null || true)" "$date" "$BASE")"
    say "wave pushed — ONLY integrate/$date left the machine ($BASE and tags untouched)"
    if [ -n "$prurl" ]; then
      note "open the PR: $prurl"
    else
      note "open a PR from integrate/$date into $BASE on your host"
    fi
    note "suggested title: Sprint $n — $goal"
    note "suggested description:"
    printf '%s\n' "$subjects" | sed 's/^/     - /'
    note "merge with the MERGE COMMIT strategy (never squash — the per-task commits must survive)"
    note "merged? finish the wave: bash ops/polaris seal --sync $date"
    cmd_notify_gate done
    return 0
  fi
  local msg
  msg="Sprint $n — $goal

$(printf '%s\n' "$subjects" | sed 's/^/- /')"
  git checkout -q "$BASE"
  if ! git merge --no-ff -q "integrate/$date" -m "$msg"; then
    git merge --abort 2>/dev/null || true
    die "merge conflict sealing integrate/$date into $BASE — resolve by hand; seal never auto-resolves"
  fi
  local old7="" new7=""
  if [ -n "$oldtag" ]; then
    old7="$(git rev-parse --short "$oldtag")"
    git tag -f "sprint/$n" >/dev/null       # move the checkpoint to this wave's merge
    new7="$(git rev-parse --short "refs/tags/sprint/$n")"
  else
    git tag "sprint/$n"
  fi
  if has_remote; then
    # push $BASE on its own so its result is known: success clears the protected-branch stamp,
    # rejection records it (doctor reads the count). The tag push follows only once base lands.
    if git push -q origin "$BASE" 2>/dev/null; then
      base_push_clear
      if [ -n "$oldtag" ]; then
        # moved tag → compare-and-swap push, leased against the wave we know we're replacing:
        # the ONLY forced ref update POLARIS ever makes.
        git push -q --force-with-lease="refs/tags/sprint/$n:$oldtag" origin "refs/tags/sprint/$n" 2>/dev/null \
          || tag_push_recovery_note "$n"
      else
        git push -q origin "refs/tags/sprint/$n" 2>/dev/null \
          || note "⚠ tag push failed — push by hand: git push origin sprint/$n"
      fi
    else
      base_push_reject
      if [ -n "$oldtag" ]; then
        note "⚠ push failed — push $BASE by hand: git push origin $BASE"
        tag_push_recovery_note "$n"
      else
        note "⚠ push failed — push by hand: git push origin $BASE sprint/$n"
      fi
      note "origin keeps rejecting $BASE? protected branch — set publish: pr in ops/CONVENTIONS.md and seal opens a PR instead"
    fi
  fi
  board_changed_touch   # fold succeeded (ops/contracts/brain.md): beacon first, then the brain
  brain_refresh_if_present  # follows the new base — a refresh failure notes ⚠, never fails the seal
  if [ -n "$oldtag" ]; then
    say "sprint $n re-sealed — integrate/$date merged into $BASE (--no-ff); sprint/$n: $old7 → $new7"
  else
    say "sprint $n sealed — integrate/$date merged into $BASE (--no-ff), tagged sprint/$n"
  fi
}

seal_sync() { # seal --sync <date> — pr mode only: finish the wave AFTER the human merges the PR
  # (ops/contracts/publish-modes.md). Steps: ff-only pull of $BASE · every [<ID>] subject of the
  # wave verified in $BASE (an unmerged OR squash-merged PR dies here, by name — the per-task
  # commits must survive) · sprint/<n> tag create-or-move per clean-history v2 (compare-and-swap
  # push; failure → by-hand note) · integrate/<date> deleted local+remote · per-task next step.
  local date="$1"
  in_primary || die "seal --sync runs in the primary checkout — cd \"$PRIMARY\" first"
  git diff --quiet && git diff --cached --quiet || die "working tree not clean — commit or stash first"
  has_remote || die "seal --sync needs an origin remote — the PR merge lives there"
  git rev-parse -q --verify "refs/heads/integrate/$date" >/dev/null \
    || die "no branch integrate/$date — nothing to sync (a different day's wave? seal --sync <date>)"
  local hdr n goal
  hdr="$(sed -n 's/^# SPRINT //p' "$OPS/SPRINT.md" 2>/dev/null | head -1 | tr -d '\r')"
  n="${hdr%%[!0-9]*}"
  [ -n "$n" ] || die "cannot read the sprint number — ops/SPRINT.md needs a '# SPRINT <n> — <goal>' header"
  # the wave's commits = integrate past its branch point — capture BEFORE the pull moves $BASE
  local mb; mb="$(git merge-base "$BASE" "integrate/$date")"
  # 1. base catches up to the merged PR — ff-only, never rebase, never merge
  git checkout -q "$BASE"
  git pull -q --ff-only origin "$BASE" \
    || die "cannot fast-forward $BASE from origin — resolve by hand (--sync never rebases, never merges)"
  # 2. every task subject of the wave must now be in $BASE history (rule 1: subject suffix [<ID>]).
  #    A squash-merged PR collapsed them into one foreign subject → die naming the missing.
  local subj sid ids="" missing=""
  while IFS= read -r subj; do
    [ -n "$subj" ] || continue
    case "$subj" in
      *\[*\]) sid="${subj##*\[}"; sid="${sid%]}";;
      *) continue;;
    esac
    if landed_sha "$sid" >/dev/null; then ids="$ids $sid"; else missing="$missing $sid"; fi
  done <<EOF
$(git log --no-merges --format=%s "$mb..integrate/$date" | grep -v '^chore(board):' || true)
EOF
  [ -z "$missing" ] || die "not in $BASE:$missing — the PR is unmerged, or was squash-merged (per-task commits must survive; merge with the MERGE COMMIT strategy). $BASE is already fast-forwarded to the PR merge; the sprint/$n tag, integrate/$date and the board are untouched"
  # 3. tag on the new $BASE HEAD — clean-history v2: create, or move an ancestor tag (CAS push)
  local oldtag old7 new7
  oldtag="$(git rev-parse -q --verify "refs/tags/sprint/$n" || true)"
  if [ -n "$oldtag" ] && ! git merge-base --is-ancestor "$oldtag" "$BASE" 2>/dev/null; then
    die "sprint/$n exists and is not in $BASE history — reused sprint number; bump the ops/SPRINT.md header"
  fi
  if [ -n "$oldtag" ]; then
    old7="$(git rev-parse --short "$oldtag")"
    git tag -f "sprint/$n" >/dev/null
    new7="$(git rev-parse --short "refs/tags/sprint/$n")"
    git push -q --force-with-lease="refs/tags/sprint/$n:$oldtag" origin "refs/tags/sprint/$n" 2>/dev/null \
      || tag_push_recovery_note "$n"
    say "sprint $n synced — $BASE fast-forwarded to the PR merge; sprint/$n: $old7 → $new7"
  else
    git tag "sprint/$n"
    git push -q origin "refs/tags/sprint/$n" 2>/dev/null \
      || note "⚠ tag push failed — push by hand: git push origin sprint/$n"
    say "sprint $n synced — $BASE fast-forwarded to the PR merge, tagged sprint/$n"
  fi
  # 4. the wave is folded into $BASE — the integrate branch is done on both sides
  git branch -q -D "integrate/$date" 2>/dev/null || true
  git push -q origin ":refs/heads/integrate/$date" 2>/dev/null \
    || note "⚠ could not delete origin integrate/$date — by hand: git push origin :refs/heads/integrate/$date"
  board_changed_touch   # the fold completed here in pr mode (ops/contracts/brain.md)
  brain_refresh_if_present  # existing brain follows the fast-forwarded base; failure = ⚠ note only
  # 5. the [<ID>]-in-$BASE gate now passes — walk each task out
  if [ -n "$ids" ]; then
    note "next, per task:$ids — bash ops/polaris run-verify <ID> · bash ops/polaris done <ID>"
  else
    note "next: per landed task — bash ops/polaris run-verify <ID> · bash ops/polaris done <ID>"
  fi
}

cmd_history() { # history [--tasks <n>] — read-only changelog view of $BASE: first-parent, board
  # noise hidden. Sealed sprints read as one line each; a never-sealed board degrades to its
  # plain log minus chore(board): — it never dies.
  local n
  if [ "${1:-}" = "--tasks" ]; then
    n="${2:?usage: polaris history --tasks <n>}"
    git -C "$PRIMARY" rev-parse -q --verify "refs/tags/sprint/$n" >/dev/null \
      || die "no tag sprint/$n — only sealed sprints have a task view (polaris history lists them)"
    # multi-wave sprints (contract v2): the tag marks the LATEST wave's merge, so the range
    # starts at the OLDEST first-parent "Sprint <n> — " merge — every wave's tasks show. A
    # single-wave sprint finds its own merge → identical to the old sprint/<n>^1..sprint/<n>.
    local start
    start="$(git -C "$PRIMARY" log --first-parent --format='%H %s' "$BASE" 2>/dev/null \
      | awk -v n="$n" 'BEGIN{p="Sprint " n " — "} index(substr($0,42),p)==1 {sha=$1} END{if (sha) print sha}')"
    [ -n "$start" ] || start="$(git -C "$PRIMARY" rev-parse "refs/tags/sprint/$n")"
    git -C "$PRIMARY" log --no-merges --date=short --format='%h %ad %s' "$start^1..sprint/$n" \
      | grep -Ev '^[0-9a-f]+ [0-9-]+ (chore\(board\):|docs\(sprint-[0-9]+\): report)' || true
    return 0
  fi
  [ -z "${1:-}" ] || die "usage: polaris history [--tasks <n>]"
  git -C "$PRIMARY" log --first-parent --date=short --format='%h %ad %s' "$BASE" 2>/dev/null \
    | grep -Ev '^[0-9a-f]+ [0-9-]+ chore\(board\):' || true
  return 0
}

cmd_rollback() { # rollback <ID | sprint/<n>> — one forward revert commit on $BASE. Never resets,
  # never force-pushes; a conflicted revert aborts with the tree restored.
  local target="${1:?usage: polaris rollback <ID | sprint/<n>>}"
  local br; br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || die "cannot resolve the current branch"
  [ "$br" = "$BASE" ] || die "rollback reverts on $BASE — you are on $br"
  git diff --quiet && git diff --cached --quiet || die "working tree not clean — commit or stash first"
  local sha
  case "$target" in
    sprint/*)
      git rev-parse -q --verify "refs/tags/$target" >/dev/null || die "no tag $target — sealed sprints only"
      if ! git revert --no-edit -m 1 "$target" >/dev/null; then
        git revert --abort 2>/dev/null || true
        die "conflicted revert of $target — aborted, tree restored; resolve by hand"
      fi
      ;;
    *)
      sha=""
      [ -f "$BOARD/done/$target.md" ] && sha="$(fm_get landed "$BOARD/done/$target.md" 2>/dev/null || true)"
      [ -n "$sha" ] || sha="$(landed_sha "$target" || true)"
      [ -n "$sha" ] || die "no landed commit for $target — no landed: stamp in done/ and nothing in $BASE with subject suffix [$target]"
      if ! git revert --no-edit "$sha" >/dev/null; then
        git revert --abort 2>/dev/null || true
        die "conflicted revert of $target ($sha) — aborted, tree restored; resolve by hand"
      fi
      ;;
  esac
  say "reverted $target — one forward commit on $BASE: $(git log -1 --format=%s)"
}
