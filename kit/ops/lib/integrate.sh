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
  check_rules "feat/$id" "$id"     # ID threaded: an `ask` rule cleared by <ID>'s approved: list
  # ops/contracts/visual-check.md: NAME the Builder's captures so the Integrator opens them before
  # landing — a green suite shipped a broken page once. Read-only, one line each; no shots ⇒ nothing.
  local shot
  for shot in "$PRIMARY/.polaris/shots/$id"-*.png; do
    [ -e "$shot" ] || continue
    note "capture: $shot"
  done
}

cmd_run_verify() { # Integrator: re-run a task's verify commands in CWD (e.g. on integrate branch)
  local id="${1:?usage: polaris run-verify <ID>}"
  local tf; tf="$(task_file "$id")" || die "no task file for $id"
  run_verify_cmds "$tf"
}

amend_verify() { # amend_verify <taskfile> <n|add> <newline|-> — the PURE verify: list surgery behind
  # cmd_amend, and the only writer that touches an EXISTING front-matter item (fm_append_item only
  # appends). Block-list shape — the "  - <cmd>" lines the TASK template and the Planner emit — with
  # the item's own indentation kept and every other byte of the file untouched, because the express
  # drill diffs task files. <n> is 1-based: `add` appends through fm_append_item (which keeps
  # whatever shape the list already has), `-` as <newline> drops the line, anything else replaces it
  # verbatim. rc 1 and the file byte-identical when <n> is out of range, or verify: is absent or not
  # a block list — no board side-effects at all, which is what lets the fast tier prove it on a
  # fixture file. ENVIRON, not -v: -v backslash-processes its value and a verify command is full of
  # backslashes. POSIX awk, bash 3.2, no awk functions (`find --api` indexes a nested
  # `function x() {` as a symbol of the file).
  local tf="$1" n="$2" new="$3" tmp="$1.tmp.$$"
  if [ "$n" = add ]; then fm_append_item verify "$new" "$tf" || return 1; return 0; fi
  POLARIS_AMEND_NEW="$new" awk -v n="$n" '
    BEGIN { new = ENVIRON["POLARIS_AMEND_NEW"] }
    /^---[\r]?$/ { fs++; print; next }
    fs==1 && !on && !done && index($0, "verify:")==1 {
      t=substr($0, 8)                                   # length("verify")+2 — fm_list stripping, exactly
      sub(/^[ \t]*/,"",t); sub(/[ \t]#.*$/,"",t); sub(/[ \t\r]*$/,"",t)
      print
      if (t == "") on=1                                 # the block list opens on the next lines
      next
    }
    on && /^[ \t]*-[ \t]/ {
      i++
      if (i != n) { print; next }
      done=1
      if (new == "-") next                              # drop: the line simply does not come out
      ind=$0; sub(/-.*$/,"",ind); print ind "- " new    # replace, the item indentation kept
      next
    }
    on && /^[A-Za-z_]/ { on=0 }
    { print }
    END { if (!done) exit 3 }
  ' "$tf" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$tf"
}

cmd_amend() { # amend <ID> --verify <n> -m "why" -- <cmd…> — the SANCTIONED verify: amendment
  # (ops/contracts/grant.md v2), and grant's sibling: grant widens a claimed task's OWNERSHIP, amend
  # corrects its ACCEPTANCE LIST. Four times across two sprints (T-122, T-125, T-136, T-139) a
  # cross-lane golden owner was handed a verify line unsatisfiable BY CONSTRUCTION — its branch is
  # based on <base>, so a row its contract REQUIRES it to write can only read as a diff hunk until
  # the sibling lands — and each one cost a round trip to a human or a conductor hand-editing a
  # board file. A calibration note fixes the NEXT wave's carves and can do nothing for work already
  # planned; a command can.
  # It lives in the INTEGRATOR's module because the two refusals are the point, not guard rails:
  #   - any feat/* branch refuses, exactly as approve does and for the same reason. A Builder
  #     EXECUTING a recorded decision is legitimate; a Builder CHOOSING one is not, and that
  #     distinction has to be structural rather than conventional. It is also what keeps an
  #     amendment legible AS an amendment — who decided, and why — instead of reading like a lane
  #     quietly lowering its own bar.
  #   - a bare full-suite command refuses, through run_verify_cmds' own predicate (_norm_cmd against
  #     CONVENTIONS test:/build:). An amendment that could install one would be a hole in a gate
  #     that already exists.
  # Every refusal mutates NOTHING — no partial write, no commit (grant's rule) — and a success is
  # ONE board commit. --verify is the only field in v2; the flag is there so a later one can join
  # without a new command.
  local id="${1:-}" n="" msg="" newcmd="" drop=0 add=0 tok="" old="" len nc st sb br tf
  local u='usage: polaris amend <ID> --verify <n> -m "why" -- <cmd…>  |  amend <ID> --verify <n> --drop -m "why"  |  amend <ID> --verify --add -m "why" -- <cmd…>'
  [ -n "$id" ] || die "$u"
  shift
  while [ $# -gt 0 ]; do case "$1" in
    --verify) case "${2:-}" in ''|-*) ;; *) n="$2"; shift;; esac; shift;;   # --verify --add carries no <n>
    --drop)   drop=1; shift;;
    --add)    add=1; shift;;
    -m)       msg="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
    --)       shift; newcmd="$*"; break;;
    *)        die "unknown flag $1 — $u";;
  esac; done
  # FIRST, before anything reads the board: the containment IS the command. A Builder standing in
  # its own worktree must hit this and nothing else, whatever else is wrong with the invocation.
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*)
    die "amend refused on $br — a Builder never rewrites its own gate; run it from the primary checkout";;
  esac
  [ -n "$msg" ] || die "amend needs -m \"why\" — the reason the acceptance list changed goes on the task's record ($u)"
  if [ "$drop" -eq 1 ] && [ "$add" -eq 1 ]; then die "amend: --drop and --add are opposites — pick one ($u)"; fi
  if [ "$add" -eq 1 ]; then
    [ -z "$n" ]      || die "amend --add appends; it takes no line number ($u)"
    [ -n "$newcmd" ] || die "amend --add needs the command after -- ($u)"
    n=add; tok='+'
  elif [ "$drop" -eq 1 ]; then
    [ -n "$n" ]      || die "amend --drop needs the line: --verify <n> --drop ($u)"
    newcmd='-'; tok="$n"
  else
    [ -n "$n" ]      || die "$u"
    [ -n "$newcmd" ] || die "amend replaces verify line $n with the command after -- ($u)"
    tok="$n"
  fi
  case "$n" in add) ;; ''|*[!0-9]*) die "amend: <n> is the 1-based verify: line, got '$n' ($u)";; esac
  tf="$(task_file "$id" active)" || tf="$(task_file "$id" review)" \
    || die "$id is not in active/ or review/ (state: $(task_col "$id" || echo unknown)) — amend corrects a CLAIMED task's acceptance list; anything else is a Planner edit"
  len="$(fm_list verify "$tf" | awk 'END{print NR+0}')"
  if [ "$n" != add ]; then
    { [ "$n" -ge 1 ] && [ "$n" -le "$len" ]; } || die "amend: verify has $len line(s), no line $n"
  fi
  # run_verify_cmds' predicate, reused rather than restated: verify: runs 2-3x per task ON TOP of
  # the wave gate, so the suite belongs in exactly one of those places and it is not this one.
  if [ "$newcmd" != '-' ]; then
    nc="$(_norm_cmd "$newcmd")"
    st="$(_norm_cmd "$(cfg test "")")"
    sb="$(_norm_cmd "$(cfg build "")")"
    if { [ -n "$st" ] && [ "$nc" = "$st" ]; } || { [ -n "$sb" ] && [ "$nc" = "$sb" ]; }; then
      die "amend refused: that is the wave gate, never a verify: line — \"$newcmd\" is CONVENTIONS test:/build:, which the wave already pays once and verify:/handoff/run-verify would pay three times over. Nothing written."
    fi
  fi
  [ "$n" = add ] || old="$(fm_list verify "$tf" | sed -n "${n}p")"
  mutex_on
  amend_verify "$tf" "$n" "$newcmd" \
    || die "amend refused: $id has no verify: block list (\"  - <cmd>\" lines) to amend — nothing written"
  if [ "$n" = add ]; then
    printf -- '- amend: verify[%s] "%s" — %s\n' "$tok" "$newcmd" "$msg" >> "$tf"
  elif [ "$newcmd" = '-' ]; then
    printf -- '- amend: verify[%s] "%s" → dropped — %s\n' "$tok" "$old" "$msg" >> "$tf"
  else
    printf -- '- amend: verify[%s] "%s" → "%s" — %s\n' "$tok" "$old" "$newcmd" "$msg" >> "$tf"
  fi
  evt amend "$id" "verify[$tok]"
  board_commit "chore(board): amend $id verify"
  sync_board
  mutex_off; trap - EXIT
  if [ "$n" = add ]; then        say "amended: $id verify[+] \"$newcmd\" (appended)"
  elif [ "$newcmd" = '-' ]; then say "amended: $id verify[$tok] dropped — was \"$old\""
  else                           say "amended: $id verify[$tok] → \"$newcmd\" (was \"$old\")"
  fi
  note "the why is on the task's record, so this reads as an amendment and not as a lane lowering its own bar · re-prove: polaris verify $id"
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
  # T-137 (ops/contracts/test-surfaces.md § 9): `done` is the ONE writer of ops/SURFACES.tsv, and
  # the task's `surface:` items are the ONE channel into it. Parsed HERE, BEFORE the mv — the
  # review/ path vanishes after it, exactly as map_delta's does. Writing the map from the
  # single-threaded integrator lane is what keeps ops/SURFACES.tsv off every task's files_owned,
  # so invariant 2 never has to reason about a file every task would otherwise share.
  # A bad item is a ⚠ and nothing more — NEVER a die: a coverage row must not be the thing that
  # blocks a landing, and drift already flags the same item while the task sits in ready/.
  local sitems; sitems="$(fm_list surface "$tf" 2>/dev/null || true)"
  local sitem srow rows="" sfirst="" ssurf stests spairs="" stitle="" snl
  snl='
'
  if [ -n "$sitems" ]; then
    stitle="$(fm_get title "$tf" 2>/dev/null || true)"
    while IFS= read -r srow; do                       # the pairs already mapped — the dup test
      [ -z "$srow" ] && continue
      ssurf="${srow%%$POLARIS_TAB*}"; stests="${srow#*$POLARIS_TAB}"; stests="${stests%%$POLARIS_TAB*}"
      spairs="$spairs$ssurf$POLARIS_TAB$stests$snl"
    done <<EOF
$(surfaces_lines)
EOF
    while IFS= read -r sitem; do
      [ -z "$sitem" ] && continue
      if ! srow="$(surface_row_from_item "$sitem" "$id" "$stitle")"; then
        note "⚠ surface row skipped: $sitem — $srow"; continue      # rc 1 puts the reason on stdout
      fi
      ssurf="${srow%%$POLARIS_TAB*}"; stests="${srow#*$POLARIS_TAB}"; stests="${stests%%$POLARIS_TAB*}"
      if match_one "$ssurf" "$stests"; then           # § 7's health check, applied before the write
        note "⚠ surface row skipped: $sitem — tests glob covers its own surface"; continue
      fi
      case "$snl$spairs" in
        *"$snl$ssurf$POLARIS_TAB$stests$snl"*)
          note "⚠ surface row skipped: $sitem — already mapped to $stests"; continue;;
      esac
      spairs="$spairs$ssurf$POLARIS_TAB$stests$snl"
      [ -n "$rows" ] || sfirst="$ssurf"
      rows="$rows$srow$snl"
    done <<EOF
$sitems
EOF
  fi
  # A non-empty map_delta lands as ONE separate docs(map) commit on $BASE (quiet-board contract) —
  # the only base commit any board mutation makes. Require the checkout BEFORE mutating anything,
  # so a wrong branch aborts clean; empty delta commits nothing on $BASE. Surface rows ride the
  # SAME commit and so need the same checkout — the die names whichever of the two you carry.
  if [ -n "$deltas" ] || [ -n "$rows" ]; then
    local br; br="$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$br" != "$BASE" ]; then
      # no rows ⇒ the 6.3 line, byte for byte; rows ⇒ the die names them, because "map_delta"
      # alone would send the human looking for a map entry the task does not have.
      [ -n "$rows" ] || die "done: $id carries a map_delta — it lands as a docs(map) commit on $BASE; check out $BASE in the primary first (currently on ${br:-?})"
      local carries="surface rows"; [ -z "$deltas" ] || carries="a map_delta + surface rows"
      die "done: $id carries $carries — they land as ONE docs commit on $BASE; check out $BASE in the primary first (currently on ${br:-?})"
    fi
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
  # T-137 (§ 9): the rows go down beside the map delta — seed the header first (a header-only file
  # is still zero rows everywhere), then append. Plain redirects, so neither the write-time guard
  # (Edit/Write tools) nor check_rules (feat-branch diffs) ever sees this; the RULES `path` rule on
  # ops/SURFACES.tsv guards every OTHER writer, which is the whole point of the guard.
  local sapplied=0 srn=0
  if [ -n "$rows" ]; then
    surfaces_seed
    while IFS= read -r srow; do
      [ -z "$srow" ] && continue
      printf '%s\n' "$srow" >> "$SURFACES"; sapplied=1; srn=$((srn+1))
    done <<EOF
$rows
EOF
    _SURFACES_CACHED=""            # a batch close calls done per task — the next dup test re-reads
  fi
  # ONE base commit for both (quiet-board contract). The pathspec goes through the positional
  # params so a path with a space still arrives as one argument; cmd_done is finished with "$@"
  # by here — $1 became $id at the top.
  if [ "$applied" -eq 1 ] || [ "$sapplied" -eq 1 ]; then   # stays on $BASE — pathspec-limited commit, index.lock retry
    local mi mok=0 msubj mkind="docs(map)"
    if [ "$applied" -eq 1 ]; then
      msubj="docs(map): $id $first"; set -- "$OPS/MAP.md"
      if [ "$sapplied" -eq 1 ]; then set -- "$@" "$SURFACES"; fi
    else
      mkind="docs(surfaces)"; msubj="docs(surfaces): $id $sfirst"; set -- "$SURFACES"
    fi
    for mi in 1 2 3 4 5; do
      if git -C "$PRIMARY" add -- "$@" 2>/dev/null \
         && git -C "$PRIMARY" commit -q -m "$msubj" -- "$@" 2>/dev/null; then mok=1; break; fi
      sleep 0.3
    done
    [ "$mok" -eq 1 ] || { git -C "$PRIMARY" add -- "$@" && git -C "$PRIMARY" commit -q -m "$msubj" -- "$@"; } \
      || die "$mkind commit failed for $id (error above)"
  fi
  evt done "$id" "" "$pts"
  board_commit "chore(board): done $id"
  sync_board
  mutex_off; trap - EXIT
  board_changed_touch   # freshness beacon for the brain (ops/contracts/brain.md) — best-effort
  brain_refresh_if_present  # v1.1: done mirrors seal — refresh AFTER the touch so the wave close
                            # (land → seal → run-verify → done) ends fresh; ⚠ note on failure, never a red done
  # THE removal goes through wt_remove (ops/contracts/worktree-liveness.md, the `done` row) — this
  # is the line that killed ARC-428 back when it forced the removal. clean+idle ⇒ removed,
  # rc 0 · dirty+idle ⇒ archived to .polaris/wt-archive/<ID>-<epoch>, rc 2 · LIVE ⇒ LEFT, rc 1,
  # whatever the dirt: a session is typing in there and nothing of ours is worth its work.
  local wtrc=0
  wt_remove "$id" done || wtrc=$?
  # LOCAL tip before the branch dies — a squash-landed branch is never an ancestor of $BASE,
  # so remote cleanup proves the remote is ours by TIP EQUALITY with this SHA instead.
  local ltip; ltip="$(git -C "$PRIMARY" rev-parse -q --verify "refs/heads/feat/$id" 2>/dev/null || true)"
  # the local branch dies ONLY after a removal (rc 0) or an archive (rc 2). A LEFT worktree keeps
  # it: git cannot delete a checked-out branch anyway, and the builder standing in it may still
  # need it. sweep --fix finishes both once the beat goes quiet.
  if [ "$wtrc" -eq 1 ]; then
    note "branch feat/$id kept — checked out in a live worktree; sweep --fix finishes the cleanup once idle"
  else
    git -C "$PRIMARY" branch -q -D "feat/$id" 2>/dev/null || true
  fi
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
        # Two lines, never `&&` — a human pastes this, and PowerShell has no chain operators.
        note "⚠ origin/feat/$id tip is not in $BASE — left in place. Inspect with these two lines:"
        note "  git fetch origin feat/$id"
        note "  git log $BASE..FETCH_HEAD"
      fi
    fi
  fi
  lock_drop "$id"; [ "$CLAIM_MODE" = "claim-branch" ] && claim_branch_drop "$id"
  # the closing line tells the truth about the two outcomes — under landing: self a builder's own
  # worktree is live by definition, so "cleaned" would be a lie on the commonest path of all.
  local swept="lock, worktree, branch$remote_note cleaned"
  [ "$wtrc" -eq 1 ] && swept="lock cleaned · live worktree + branch feat/$id left for sweep --fix" || true
  say "$id → done/ · $swept$( [ $applied -eq 1 ] && echo ' · map_delta applied')$( [ $sapplied -eq 1 ] && echo " · $srn surface row(s) written")"
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

suite_stamp_carry() { # suite_stamp_carry <tested-sha> <scope> — T-123 (verification-tiering.md
  # § v2): express runs the suite at step 3 and used to throw the verdict away, so the next
  # `finish` re-ran the identical suite over the identical tree — measured at ~20 wasted minutes per
  # task. This carries the verdict forward: it writes .polaris/suite-stamp in exactly the shape
  # cmd_qa writes and reads ("<HEAD-sha> <epoch> <scope>", T-137 / test-surfaces.md § 6 D5), and
  # ONLY when the carry is provably honest — tree clean · <tested-sha> an ancestor of HEAD ·
  # nothing changed since it outside the reports dir, ops/MAP.md and ops/SURFACES.tsv (the three
  # things seal and done write AFTER the suite ran). Anything else withholds the stamp and says so:
  # finish then re-runs the suite, which is cheap next to blessing a commit nobody tested.
  # <scope> is `full` | `scoped` — WHAT the suite proved, not merely that it was green. An EMPTY
  # scope withholds too: a caller with a tested sha but nothing to say about its breadth would
  # otherwise write a 2-field stamp, which every reader charitably reads as `full`. Fail closed —
  # the field is being ADDED here, no existing conservatism is being relaxed.
  # NEVER changes the caller's exit status.
  local tested="${1:-}" scope="${2:-}" head dirty rel changed extra
  [ -n "$tested" ] || return 0
  head="$(git -C "$PRIMARY" rev-parse HEAD 2>/dev/null || echo none)"
  [ "$head" = "none" ] && return 0
  dirty="$(git -C "$PRIMARY" status --porcelain 2>/dev/null | head -1)"
  rel="$(cfg reports docs/sprints)"; rel="${rel%/}"; [ -n "$rel" ] || rel="docs/sprints"
  if [ -n "$scope" ] && [ -z "$dirty" ] && git -C "$PRIMARY" merge-base --is-ancestor "$tested" "$head" 2>/dev/null; then
    changed="$(git -C "$PRIMARY" diff --name-only "$tested" "$head" 2>/dev/null || true)"
    extra="$(printf '%s\n' "$changed" | grep -v '^[[:space:]]*$' | grep -v "^$rel/" | grep -vx 'ops/MAP.md' | grep -vx 'ops/SURFACES.tsv' || true)"
    if [ -z "$extra" ]; then
      mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
      printf '%s %s %s\n' "$head" "$(date +%s)" "$scope" > "$PRIMARY/.polaris/suite-stamp" 2>/dev/null || true
      return 0
    fi
  fi
  note "⚠ suite stamp withheld — HEAD gained more than the sprint report since the suite ran; finish will re-run it"
  return 0
}

cmd_land() { # land <ID> — Integrator, primary checkout, ON the integrate branch: audit, then
  # squash feat/<ID> into exactly ONE commit whose message comes from the task file. Makes NO
  # board write, NO evt, NO board commit — a red task unwinds with a single
  # `git reset --hard HEAD~1`, nothing uncommitted at stake. The landed record IS the commit
  # (subject suffix [<ID>] + Landed-from trailer); `done` stamps it onto the task later.
  # land --express <ID> routes to the one-pass lane (ops/contracts/express-lane.md).
  # shared-checkout v1 (T-058): the body runs under the integration lease — ONE shared lane,
  # int_on first (a busy lane past the bounded wait → its `queued: ` line + rc 3, nothing
  # mutated), released on every exit. A dirty tree parks instead of dying; on $BASE wave_on
  # creates/ff-reuses/adopts today's integrate/<date>; a re-land of an already-landed ID skips
  # with rc 0 — two integrators never die on each other's completed work.
  if [ "${1:-}" = "--express" ]; then
    shift
    cmd_land_express "${1:?usage: polaris land --express <ID>}" || return $?
    return 0
  fi
  local id="${1:?usage: polaris land <ID>}"
  in_primary || die "land mutates the checked-out branch — run it in the primary checkout, never a worktree"
  # lease is OUTERMOST (shared-checkout lock ordering). Nested calls (express) re-enter rc 0;
  # only the frame that took it releases on success paths — a die releases regardless, because
  # the process is over either way. STATEMENT-LEVEL call, never $( ): the EXIT trap it arms
  # would self-release inside a subshell.
  local land_had="${INT_HELD:-}"
  int_on "land $id" || return $?
  # idempotence gate 1: already in $BASE (a sealed earlier wave — the task may even be done/) →
  # skip BEFORE the review/ gate can die on another integrator's completed work. Nothing mutated.
  if landed_sha "$id" >/dev/null; then
    [ -n "$land_had" ] || int_off
    say "already landed — skipped ($id is in $BASE history)"
    return 0
  fi
  local tf; tf="$(task_file "$id" review)" || { int_off; die "$id is not in review/ — only handed-off work lands"; }
  local tip; tip="$(git rev-parse -q --verify "refs/heads/feat/$id")" || { int_off; die "no local branch feat/$id"; }
  # dirty tree → park + caveat + proceed (BEFORE wave_on — the checkout needs the dirt gone);
  # park refused → the old die verbatim, tree untouched.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    if park "land $id"; then
      note "⚠ parked your dirt — bash ops/polaris unpark returns it"
    else
      int_off
      die "working tree not clean — a conflict must be able to reset --hard safely"
    fi
  fi
  local br; br="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$br" = "$BASE" ]; then
    wave_on      # create · ff-reuse · adopt today's integrate/<date> — replaces the on-$BASE die
    br="$(git rev-parse --abbrev-ref HEAD)"
  fi
  # idempotence gate 2: already on THIS wave branch (an adopted wave, or a re-run mid-wave) →
  # skip; the earlier landing pass already did the work.
  if landed_sha "$id" HEAD >/dev/null; then
    [ -n "$land_had" ] || int_off
    say "already landed — skipped ($id is on $br)"
    return 0
  fi
  # audit BEFORE any merge — ownership + rules on the feat branch, exactly as `polaris audit`
  check_ownership "$tf" "feat/$id"
  check_rules "feat/$id" "$id"     # ID threaded: an `ask` rule cleared by <ID>'s approved: list
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
    int_off      # kickback's `trap - EXIT` disarmed the on_die net — release the lease by hand
    die "squash conflict — $br restored, $id kicked back to active/"
  fi
  rm -f "$mergeerr"
  if git diff --cached --quiet; then
    git reset -q --hard; rm -f "$msgf"
    int_off
    die "feat/$id brings no changes over $br — nothing to land (your call: kickback it, or done it by hand)"
  fi
  git commit -q -F "$msgf" || { rm -f "$msgf"; git reset -q --hard; int_off; die "commit failed — squash unwound, $br clean"; }
  rm -f "$msgf"
  # re-stamp the lease after the land (worktree-liveness.md § steals): a drain of many tasks, or a
  # slow suite around this one, must never let an ALIVE integrator look abandoned to the steal.
  [ -n "${INT_HELD:-}" ] && date +%s > "$LOCKS/.int-lease/epoch" 2>/dev/null || true
  [ -n "$land_had" ] || int_off        # our lane work is done; a nested (express) hold stays held
  say "landed $id on $br — $(git log -1 --format=%s)"
  note "goes red on the suite? unwind: git reset --hard HEAD~1   ·   bounce: polaris kickback $id -m \"<why>\""
  land_slow_suite_hint
}

cmd_land_express() { # land --express <ID> — ops/contracts/express-lane.md: the integrator's whole
  # long path for the SINGLE-task case, in one pass: integrate branch → audit+land → ONE full
  # CONVENTIONS suite → seal → run-verify → done → branch cleanup. Express collapses SESSIONS,
  # never checks — every gate of the long path runs exactly as it does there. Four pinned
  # refusals below die BEFORE step 1, mutating nothing; `finish` stays the mandatory finish line.
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
  # context — the same preconditions land/seal enforce: primary checkout, ON <base>
  in_primary || die "express runs in the primary checkout — cd \"$PRIMARY\" first"
  local br; br="$(git rev-parse --abbrev-ref HEAD)"
  [ "$br" = "$BASE" ] || die "express starts ON $BASE — you are on $br"
  # step 0 (express-lane v2, shared-checkout): the integration lease. The four refusals above
  # stay BEFORE it on purpose — a doomed express must refuse instantly, never queue on a busy
  # lane. Busy past the bounded wait → int_on's `queued: ` line + rc 3, nothing mutated.
  local ex_had="${INT_HELD:-}"
  int_on "land --express $id" || return $?
  # dirty tree → park + caveat + proceed; park refused → v1's die verbatim, tree untouched
  if ! git diff --quiet || ! git diff --cached --quiet; then
    if park "land --express $id"; then
      note "⚠ parked your dirt — bash ops/polaris unpark returns it"
    else
      int_off
      die "working tree not clean — commit or stash first"
    fi
  fi
  # step 1 (express-lane v2): today's wave via wave_on — create from $BASE · ff-reuse · ADOPT an
  # open non-ff wave. The v1 "finish that wave by hand first" die is deleted.
  local date; date="$(date +%F)"
  wave_on
  # step 2: audit + land — existing cmd_land semantics, unchanged (re-enters the lease, rc 0;
  # an already-landed <ID> skips there and express continues to the still-pending steps)
  cmd_land "$id"
  # step 3: the CONVENTIONS suite, ONCE (same set as qa). Red → unwind the land, kick the
  # task back carrying the failing tail, die — the board never keeps a green it didn't earn.
  # T-137 (ops/contracts/test-surfaces.md § 6): the `test` iteration — and ONLY it — asks the same
  # two core.sh functions cmd_qa asks, so a scoped `qa` and an express land can never disagree
  # about what was proven. The two loops stay SEPARATE on purpose — express re-stamps the lease
  # per command and unwinds the land on red, which qa does neither of; it is the SELECTION that is
  # shared, never the loop. `test_select:` unset (every repo until it maps a surface) ⇒ this block
  # is inert and express is byte-identical to 6.3. Express never takes --full — it takes no flags
  # at all; `qa --full` afterwards is the escape hatch.
  local k c out tailtxt
  local ex_ran=0 ex_t0 ex_t1 ex_tested="" ex_scope="" ex_cmds ex_paths ex_why ex_p ex_m=0 ex_n ex_selected
  ex_t0="$(date +%s)"
  out="$(mktemp)"
  ex_paths="$(mktemp)"
  for k in test lint typecheck build uat; do
    c="$(cfg "$k" "")"
    [ -z "$c" ] && continue
    ex_cmds="$c"; ex_selected=0
    if [ "$k" = "test" ] && [ -n "$(cfg test_select "")" ]; then
      if surface_change_set > "$ex_paths"; then
        if ex_why="$(surface_select_cmd "$ex_paths")"; then
          ex_cmds="$ex_why"; ex_m=0; ex_n=0; ex_selected=1
          while IFS= read -r ex_p; do if [ -n "$ex_p" ]; then ex_m=$((ex_m+1)); fi; done <<EOF
$ex_cmds
EOF
          while IFS= read -r ex_p; do if [ -n "$ex_p" ]; then ex_n=$((ex_n+1)); fi; done < "$ex_paths"
          note "test — scoped to $ex_m command(s): $ex_n changed path(s) all mapped (qa --full runs test: verbatim)"
        else
          # the reason comes back in surface_select_cmd's vocabulary — say it in the human's
          case "$ex_why" in
            'no rows')     ex_why='ops/SURFACES.tsv has no rows';;
            'unmapped: '*) ex_why="${ex_why#unmapped: }"; ex_p="${ex_why%% *}"
                           ex_why="$ex_p has no ops/SURFACES.tsv row${ex_why#"$ex_p"}";;
          esac
          note "test — running the whole suite: $ex_why"
        fi
      else
        note "test — running the whole suite: no proven baseline on $BASE (no stamp, --force, or a stamp that is not an ancestor)"
      fi
    fi
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      ex_ran=$((ex_ran+1))
      if ( cd "$PRIMARY" && bash -c "$c" ) >"$out" 2>&1; then
        # the suite is the longest thing the lane ever does — re-stamp after EACH command so a
        # 13-minute test run stays visibly alive to the pid-aware steal (worktree-liveness.md)
        [ -n "${INT_HELD:-}" ] && date +%s > "$LOCKS/.int-lease/epoch" 2>/dev/null || true
      else
        printf '⛔ %s — RED: %s\n' "$k" "$c" >&2
        tail -15 "$out" | sed 's/^/     /' >&2
        tailtxt="$(tail -3 "$out" | tr '\n' ' ' | cut -c1-200)"
        rm -f "$out" "$ex_paths"
        git reset -q --hard HEAD~1        # unwind the land — integrate/<date> back at $BASE state
        cmd_kickback "$id" -m "express suite red on $k: $tailtxt"
        int_off    # kickback's `trap - EXIT` disarmed the on_die net — release the lease by hand
        die "express: $k red — land unwound on integrate/$date, $id kicked back with the failing tail"
      fi
    done <<EOF
$ex_cmds
EOF
    if [ "$ex_selected" -eq 1 ]; then
      ex_scope=scoped                  # only a `test` key that RAN a selection makes the stamp scoped
      say "test — green (scoped: $ex_m command(s))"
    else
      say "$k — green"
    fi
  done
  rm -f "$out" "$ex_paths"
  # T-123 (verification-tiering v2): the commit the suite just proved — captured HERE, on
  # integrate/<date>, right after the last green, before seal/done move anything. Plus the
  # suite duration, same "<seconds> <epoch>" line qa writes, so the slow-suite hint works after
  # an express land too. Both best-effort; neither can fail the lane.
  if [ "$ex_ran" -ge 1 ]; then
    ex_tested="$(git rev-parse HEAD 2>/dev/null || true)"   # nothing ran ⇒ nothing proven ⇒ no carry
    # T-137 (§ 6, stamp v3): WHAT it proved, not just that it was green. `full` for every path but
    # one — selection off, no baseline, an unmapped path, or no `test:` key at all.
    [ -n "$ex_scope" ] || ex_scope=full
    ex_t1="$(date +%s)"
    mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
    printf '%s %s\n' "$((ex_t1 - ex_t0))" "$ex_t1" > "$PRIMARY/.polaris/last-suite-seconds" 2>/dev/null || true
  fi
  # step 4: seal — existing cmd_seal semantics, unchanged (tag sprint/<n>, pushes when remoted)
  cmd_seal "$date"
  # step 5: prove + close — verify: commands on the sealed base, done (landed: stamp + cleanup),
  # then the wave branch goes (its job is finished; a fresh one is cheap tomorrow)
  cmd_run_verify "$id"
  cmd_done "$id"
  git branch -q -D "integrate/$date" 2>/dev/null || true
  [ -n "$ex_had" ] || int_off          # the lane's work is over — free it before the closing notes
  # T-123: carry step 3's verdict to `finish` — the LAST thing express does before its closing say
  suite_stamp_carry "$ex_tested" "$ex_scope"
  say "express: $id landed · sealed · done — one pass, integrate/$date cleaned"
  note "finish line: bash ops/polaris finish — it runs qa for you, proves the RUN is over, and signals done"
}

tag_push_recovery_note() { # tag_push_recovery_note <n> — convergent recovery when a moved-tag CAS
  # push is rejected (clean-history v2.1). The stale LOCAL old-sha lease can NEVER win once origin
  # missed a prior wave's tag move — so lease from origin's ACTUAL current tag instead. ls-remote
  # yields the origin value (empty = tag absent → the empty lease correctly expects "not present").
  local n="$1"
  note "⚠ tag push failed — origin's sprint/$n lags a prior wave; the local lease can't win. Lease from origin and retry:"
  note "   git push --force-with-lease=refs/tags/sprint/$n:\$(git ls-remote origin refs/tags/sprint/$n | cut -f1) origin refs/tags/sprint/$n"
}

seal_burndown_row() { # seal_burndown_row <n> <date> <ids> — sprint-report.md v3 (T-153): the wave's
  # burndown row, written by the seal that already holds its numbers. Three sprints of empty tables
  # were the tell: the Integrator was the only writer of ops/SPRINT.md, and that pen went silent the
  # day integration became a command nobody sits behind. The seal is the one step every lane passes
  # through, so the row lives here. <ids> = the wave's task IDs (the [<ID>] suffixes of the sealed
  # subjects), whitespace-separated; at seal time their files still sit in review/ (done/ is the
  # fallback for a re-seal). done_pts = Σ their points. remaining = Σ points over backlog ∪ ready ∪
  # active ∪ review MINUS the wave (no numeric points: ⇒ 0; IDEAS.md has no frontmatter and is
  # skipped). The row goes in as the LAST row of the TOP sprint's ## Burndown table, the table
  # created at the end of the top section when the Planner wrote none, then ONE board commit
  # (`chore(board): burndown <date>`) + sync — BEFORE done's commit, so the drills that pin the
  # board ref's last subject as `chore(board): done <ID>` stay true. Best-effort end to end: every
  # failure is a ⚠ note and rc 0 — a seal never fails on its own bookkeeping. Counts are the half a
  # command CAN write honestly; the closing nudge is for the half it cannot: the lesson.
  local n="$1" date="$2" ids id tf f b col wave="" rest="" wave_ids="" done_pts remaining row sf tmp ok=1
  ids=" $(printf '%s' "${3:-}" | tr '\n\t' '  ') "
  for id in $ids; do
    tf="$(task_file "$id" review)" || tf="$(task_file "$id" done)" || continue
    wave="$wave$(fm_get points "$tf")
"
    wave_ids="$wave_ids${wave_ids:+ }$id"
  done
  for col in backlog ready active review; do
    for f in "$BOARD/$col/"*.md; do
      [ -f "$f" ] || continue
      b="${f##*/}"; b="${b%.md}"
      [ "$b" = IDEAS ] && continue
      case "$ids" in *" $b "*) continue;; esac
      rest="$rest$(fm_get points "$f")
"
    done
  done
  done_pts="$(printf '%s' "$wave" | awk '{ s += $1 + 0 } END { printf "%s", s + 0 }')"
  remaining="$(printf '%s' "$rest" | awk '{ s += $1 + 0 } END { printf "%s", s + 0 }')"
  row="| $date | $done_pts | $remaining |"
  # The rewrite, one awk pass: the top section runs from the first '# SPRINT ' header to the next.
  # Its first ## Burndown opens a table = the contiguous '|' lines under it; the row is appended
  # after the last of them. No table ⇒ created where the section ends (before the next header,
  # else at EOF) as a blank line + heading + header row + separator + the row. Blank lines inside
  # the top section are held (pend) and re-emitted AFTER whatever the boundary inserts, so the
  # new table sits between the section's text and the blank line that already preceded the next
  # header — the shape the hand-written sprints have. Every other byte passes through untouched.
  # (Plain rules, no awk functions: `find --api` would index `function x() {` as a nested fn.)
  sf="$OPS/SPRINT.md"; tmp="$(mktemp)"
  mutex_on
  if [ -f "$sf" ] && POLARIS_ROW="$row" awk '
      BEGIN { row = ENVIRON["POLARIS_ROW"]; body = "| date | done pts | remaining |\n|---|---|---|\n" row; tbl = "\n## Burndown\n" body }
      /^# SPRINT / { if (top && !done) { out = (intab && rows) ? row : (intab ? body : tbl); print out; done = 1 }
                     intab = 0; top = (seen ? 0 : 1); seen = 1; while (pend) { print ""; pend-- }; print; next }
      !top { print; next }
      !done && !intab && /^## Burndown/ { while (pend) { print ""; pend-- }; print; intab = 1; rows = 0; next }
      intab && /^\|/ { while (pend) { print ""; pend-- }; print; rows++; next }
      /^[ \t\r]*$/ { if (intab && rows) { print row; done = 1; intab = 0 }; pend++; next }
      { if (intab) { out = rows ? row : body; print out; done = 1; intab = 0 }; while (pend) { print ""; pend-- }; print; next }
      END { if (!done) { out = (intab && rows) ? row : (intab ? body : tbl); print out }; while (pend) { print ""; pend-- } }
    ' "$sf" > "$tmp"; then
    cat "$tmp" > "$sf"
    # commit + sync in subshells: both `die` on a stuck ref or a rejected push, and a die in the
    # seal's own shell would fail the seal. A subshell inherits no EXIT trap, so nothing here can
    # release the lease or the mutex the seal is holding (the T-058 trap is int_on/mutex_on INSIDE
    # a subshell, never a plain command in one).
    if ( board_commit "chore(board): burndown $date" ); then
      ( sync_board ) || note "⚠ board push failed — the next board mutation carries the burndown row with it"
    else
      ok=0
    fi
  else
    ok=0
  fi
  rm -f "$tmp"
  mutex_off
  if [ "$ok" -eq 1 ]; then
    say "burndown: $date · sprint $n · $done_pts pts landed (${wave_ids:-no task IDs}) · $remaining pts still on the board — ops/SPRINT.md"
  else
    note "⚠ burndown row not recorded — add it by hand to ops/SPRINT.md § Burndown (sprint $n): $row"
  fi
  note 'learned anything? bash ops/polaris learned -m "…" — ≤3 per wave; EVOLVE reads them'
  return 0
}

cmd_seal() { # seal [<date>] | seal --sync [<date>] — close an integration wave: ONE --no-ff merge
  # of integrate/<date> into $BASE, tagged sprint/<n>. Message = sprint header + a bullet per landed
  # commit — the changelog entry `history` shows forever. sprint/<n> always marks the sprint's
  # LATEST sealed checkpoint (contract v2, multi-wave): the first seal of sprint n creates the tag,
  # a later seal of the same n moves it forward. A merge conflict aborts; a human resolves — never
  # auto-resolved. publish: pr (ops/contracts/publish-modes.md): NO local merge — the wave leaves
  # as ONE pushed integrate branch + a PR-create URL, and `seal --sync` finishes after the human
  # merges the PR (merge-commit strategy, never squash).
  # shared-checkout v1 (T-058): the sealing pass runs under the integration lease (int_on first,
  # statement-level; busy lane → `queued: ` + rc 3), a dirty tree parks instead of dying, and a
  # wave with only board noise closes idempotently — `nothing new to seal`, rc 0.
  local sync=""
  if [ "${1:-}" = "--sync" ]; then sync=1; shift; fi
  local date="${1:-}"; [ -n "$date" ] || date="$(date +%F)"
  publish_resolve
  if [ -n "$sync" ]; then
    [ "$PUB" = "pr" ] || die "publish: direct seals locally — nothing to sync"
    seal_sync "$date" || return $?
    return 0
  fi
  in_primary || die "seal runs in the primary checkout — cd \"$PRIMARY\" first"
  local seal_had="${INT_HELD:-}"
  int_on "seal $date" || return $?
  # dirty tree → park + caveat + proceed; park refused → the old die verbatim, tree untouched
  if ! git diff --quiet || ! git diff --cached --quiet; then
    if park "seal $date"; then
      note "⚠ parked your dirt — bash ops/polaris unpark returns it"
    else
      int_off
      die "working tree not clean — commit or stash first"
    fi
  fi
  git rev-parse -q --verify "refs/heads/integrate/$date" >/dev/null \
    || { int_off; die "no branch integrate/$date — land tasks on it first (a different day's branch? seal <date>)"; }
  local subjects
  subjects="$(git log --reverse --format=%s "$BASE..integrate/$date" | grep -v '^chore(board):' || true)"
  # idempotent close (shared-checkout): an already-sealed or board-noise-only wave costs nothing —
  # a second integrator's seal after the first one finished is rc 0, board untouched.
  if [ -z "$subjects" ]; then
    [ -n "$seal_had" ] || int_off
    say "nothing new to seal — $BASE..integrate/$date has only board commits"
    return 0
  fi
  # <n> + <goal> from the ops/SPRINT.md header: "# SPRINT <n> — <goal>" (goal ends at 2+ spaces
  # or capacity:; — or - both accepted)
  local hdr n goal
  hdr="$(sed -n 's/^# SPRINT //p' "$OPS/SPRINT.md" 2>/dev/null | head -1 | tr -d '\r')"
  n="${hdr%%[!0-9]*}"
  [ -n "$n" ] || { int_off; die "cannot read the sprint number — ops/SPRINT.md needs a '# SPRINT <n> — <goal>' header"; }
  goal="$(printf '%s' "${hdr#"$n"}" | sed -e 's/^[[:space:]]*//' -e 's/^—[[:space:]]*//' -e 's/^-[[:space:]]*//' \
      -e 's/[[:space:]][[:space:]].*$//' -e 's/[[:space:]]*capacity:.*$//' -e 's/[[:space:]]*$//')"
  # tag gate (contract v2): absent → first wave of sprint n. Present AND an ancestor of $BASE →
  # a previous wave's checkpoint; the tag moves to this wave's merge below. Neither → the number
  # was REUSED on unrelated history — refuse before anything mutates.
  local oldtag
  oldtag="$(git rev-parse -q --verify "refs/tags/sprint/$n" || true)"
  if [ -n "$oldtag" ] && ! git merge-base --is-ancestor "$oldtag" "$BASE" 2>/dev/null; then
    int_off
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
    has_remote || { int_off; die "publish: pr needs an origin remote — nowhere to push integrate/$date"; }
    git push -q -u origin "integrate/$date" || { int_off; die "push of integrate/$date failed — check origin access"; }
    board_changed_touch   # brain freshness (ops/contracts/brain.md): the wave left the machine.
                          # No auto-refresh here — the fold happens at `seal --sync`, not now.
    [ -n "$seal_had" ] || int_off   # lane work done — release BEFORE the notify hook, which may
                                    # block on a human gate; the lane must not wait with it
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
    int_off
    die "merge conflict sealing integrate/$date into $BASE — resolve by hand; seal never auto-resolves"
  fi
  # T-153 (sprint-report.md v3): the wave's burndown row, right after the merge — the sealed
  # subjects name the wave and the board holds the rest, so the numbers need no one to remember
  # them. $subjects was captured before the report commit, so the [<ID>] suffixes are the tasks
  # and nothing else. Best-effort inside: a ⚠ at worst, never a failed seal.
  seal_burndown_row "$n" "$date" "$(printf '%s\n' "$subjects" | sed -n 's/.*\[\([^][]*\)\]$/\1/p' | tr '\n' ' ')"
  # the merge is behind us and the pushes below are the network-slow stretch — re-stamp so the
  # lease reads fresh across them (worktree-liveness.md § steals)
  [ -n "${INT_HELD:-}" ] && date +%s > "$LOCKS/.int-lease/epoch" 2>/dev/null || true
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
  [ -n "$seal_had" ] || int_off   # last mutation of the sealing pass is behind us — free the lane
  if [ -n "$oldtag" ]; then
    say "sprint $n re-sealed — integrate/$date merged into $BASE (--no-ff); sprint/$n: $old7 → $new7"
  else
    say "sprint $n sealed — integrate/$date merged into $BASE (--no-ff), tagged sprint/$n"
  fi
  # A wave is not a run: a sprint may seal several times (INTEGRATOR.md § 4). So this POINTS at the
  # run-level verdict rather than calling it — an auto-called finish would print `⛔ pending:` inside
  # two successful seals out of three, and would put the whole suite between the merge and the push.
  note "wave sealed. run over? bash ops/polaris finish"
}

seal_sync() { # seal --sync <date> — pr mode only: finish the wave AFTER the human merges the PR
  # (ops/contracts/publish-modes.md). Steps: ff-only pull of $BASE · every [<ID>] subject of the
  # wave verified in $BASE (an unmerged OR squash-merged PR dies here, by name — the per-task
  # commits must survive) · sprint/<n> tag create-or-move per clean-history v2 (compare-and-swap
  # push; failure → by-hand note) · integrate/<date> deleted local+remote · per-task next step.
  # shared-checkout v1 (T-058): the sync leg is lane work too — int_on first (statement-level;
  # rc 3 `queued: ` propagates), dirty tree parks + proceeds, released on every exit.
  local date="$1"
  in_primary || die "seal --sync runs in the primary checkout — cd \"$PRIMARY\" first"
  local ss_had="${INT_HELD:-}"
  int_on "seal --sync $date" || return $?
  # dirty tree → park + caveat + proceed; park refused → the old die verbatim, tree untouched
  if ! git diff --quiet || ! git diff --cached --quiet; then
    if park "seal --sync $date"; then
      note "⚠ parked your dirt — bash ops/polaris unpark returns it"
    else
      int_off
      die "working tree not clean — commit or stash first"
    fi
  fi
  has_remote || { int_off; die "seal --sync needs an origin remote — the PR merge lives there"; }
  git rev-parse -q --verify "refs/heads/integrate/$date" >/dev/null \
    || { int_off; die "no branch integrate/$date — nothing to sync (a different day's wave? seal --sync <date>)"; }
  local hdr n goal
  hdr="$(sed -n 's/^# SPRINT //p' "$OPS/SPRINT.md" 2>/dev/null | head -1 | tr -d '\r')"
  n="${hdr%%[!0-9]*}"
  [ -n "$n" ] || { int_off; die "cannot read the sprint number — ops/SPRINT.md needs a '# SPRINT <n> — <goal>' header"; }
  # the wave's commits = integrate past its branch point — capture BEFORE the pull moves $BASE
  local mb; mb="$(git merge-base "$BASE" "integrate/$date")"
  # 1. base catches up to the merged PR — ff-only, never rebase, never merge
  git checkout -q "$BASE"
  git pull -q --ff-only origin "$BASE" \
    || { int_off; die "cannot fast-forward $BASE from origin — resolve by hand (--sync never rebases, never merges)"; }
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
  [ -z "$missing" ] || { int_off; die "not in $BASE:$missing — the PR is unmerged, or was squash-merged (per-task commits must survive; merge with the MERGE COMMIT strategy). $BASE is already fast-forwarded to the PR merge; the sprint/$n tag, integrate/$date and the board are untouched"; }
  # T-153 (sprint-report.md v3): every task of the wave is proven in $BASE — the pr-mode moment
  # that matches direct mode's "right after the merge". Same row, same board commit, best-effort.
  seal_burndown_row "$n" "$date" "$ids"
  # 3. tag on the new $BASE HEAD — clean-history v2: create, or move an ancestor tag (CAS push)
  local oldtag old7 new7
  oldtag="$(git rev-parse -q --verify "refs/tags/sprint/$n" || true)"
  if [ -n "$oldtag" ] && ! git merge-base --is-ancestor "$oldtag" "$BASE" 2>/dev/null; then
    int_off
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
  [ -n "$ss_had" ] || int_off   # fold complete — free the lane before the per-task next steps
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
  # shared-checkout v1 (T-058): reverting $BASE is lane work — int_on first (statement-level;
  # rc 3 `queued: ` propagates), dirty tree parks + proceeds, released on every exit.
  local target="${1:?usage: polaris rollback <ID | sprint/<n>>}"
  local br; br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || die "cannot resolve the current branch"
  [ "$br" = "$BASE" ] || die "rollback reverts on $BASE — you are on $br"
  local rb_had="${INT_HELD:-}"
  int_on "rollback $target" || return $?
  # dirty tree → park + caveat + proceed; park refused → the old die verbatim, tree untouched
  if ! git diff --quiet || ! git diff --cached --quiet; then
    if park "rollback $target"; then
      note "⚠ parked your dirt — bash ops/polaris unpark returns it"
    else
      int_off
      die "working tree not clean — commit or stash first"
    fi
  fi
  local sha
  case "$target" in
    sprint/*)
      git rev-parse -q --verify "refs/tags/$target" >/dev/null || { int_off; die "no tag $target — sealed sprints only"; }
      if ! git revert --no-edit -m 1 "$target" >/dev/null; then
        git revert --abort 2>/dev/null || true
        int_off
        die "conflicted revert of $target — aborted, tree restored; resolve by hand"
      fi
      ;;
    *)
      sha=""
      [ -f "$BOARD/done/$target.md" ] && sha="$(fm_get landed "$BOARD/done/$target.md" 2>/dev/null || true)"
      [ -n "$sha" ] || sha="$(landed_sha "$target" || true)"
      [ -n "$sha" ] || { int_off; die "no landed commit for $target — no landed: stamp in done/ and nothing in $BASE with subject suffix [$target]"; }
      if ! git revert --no-edit "$sha" >/dev/null; then
        git revert --abort 2>/dev/null || true
        int_off
        die "conflicted revert of $target ($sha) — aborted, tree restored; resolve by hand"
      fi
      ;;
  esac
  [ -n "$rb_had" ] || int_off
  say "reverted $target — one forward commit on $BASE: $(git log -1 --format=%s)"
}
