# POLARIS lib/qa.sh — the closing checks, sourced by ops/polaris (the lib loader): qa and finish.
# Moved out of observe.sh unchanged (ops/contracts/minutes.md § 3).

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
  # speed.md § 4: red is EVERYTHING; sred_any = a suite key went red; hred = a red that is neither a
  # suite key nor CRUFT-class. The stamp needs sred_any=0 AND hred=0 — the rc still reads red alone.
  local sred_any=0 hred=0
  # test-depth.md § 4: depth_skip=1 ⇒ the whole suite loop never runs (none|look). ddepth/dwhy carry
  # whatever depth_for actually answered (any of the four words), empty when the gate never ran
  # (--force, --full, or an unbounded change set) — decision_log below fires only when non-empty.
  local depth_skip=0 ddepth="" dwhy="" dtf="" dcsf="" dline dbaseline dcur dsubj dsid df qf qplan qtaskid qpf dsecs
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
  # test-depth.md § 4: decide ONCE whether this change needs the suite at all, before the per-key
  # loop below. --force/--full and an unbounded change set (no proven baseline) never consult
  # depth_for — they mean "run everything", exactly as before. Bounded ⇒ depth_for's verdict:
  # none/look skip the WHOLE loop (no test/lint/typecheck/build/uat); scoped/full fall through to
  # the loop UNCHANGED — its own test_select scoping just below is a separate, finer decision about
  # the `test` key alone, and stays byte-identical to 6.8.0 either way. A dirty tree never consults
  # the gate either: depth_for sees only COMMITTED diffs, and the whole point of `dirty` up top is
  # that an uncommitted edit (a CONVENTIONS.md config change included) might be exactly what the
  # next suite run needs to see — qa's own stated philosophy ("any uncommitted change... re-runs
  # everything"), so the gate defers to it instead of reading a stale, HEAD-only "nothing changed".
  if [ "$force" -eq 0 ] && [ "$full" -eq 0 ] && [ -z "$dirty" ]; then
    dcsf="$(mktemp)"
    if surface_change_set > "$dcsf"; then
      # task files: every `[<ID>]` subject since the baseline (SURFACE_BASELINE, else $BASE on a
      # branch), plus feat/<ID> when HEAD is on one — the same scan cmd_depth uses for its no-ID
      # case, resolved with task_file in any column; missing files ignored.
      dbaseline="${SURFACE_BASELINE:-}"
      dcur="$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      [ -n "$dbaseline" ] || { [ "$dcur" = "$BASE" ] || dbaseline="$BASE"; }
      dtf=""
      if [ -n "$dbaseline" ]; then
        while IFS= read -r dsubj; do
          [ -z "$dsubj" ] && continue
          case "$dsubj" in *'['*']') dsid="${dsubj##*[}"; dsid="${dsid%]}";; *) dsid="";; esac
          [ -n "$dsid" ] || continue
          df="$(task_file "$dsid" 2>/dev/null)" || continue
          case " $dtf " in *" $df "*) ;; *) dtf="${dtf:+$dtf }$df";; esac
        done <<EOF
$(git -C "$PRIMARY" log --format=%s "$dbaseline..HEAD" 2>/dev/null)
EOF
      fi
      case "$dcur" in
        feat/*) df="$(task_file "${dcur#feat/}" 2>/dev/null)" || df=""
                if [ -n "$df" ]; then case " $dtf " in *" $df "*) ;; *) dtf="${dtf:+$dtf }$df";; esac; fi ;;
      esac
      dline="$(depth_for $dtf < "$dcsf")"
      ddepth="${dline%%$POLARIS_TAB*}"; dwhy="${dline#*$POLARIS_TAB}"
    fi
  fi
  if [ "$ddepth" = none ] || [ "$ddepth" = look ]; then
    note "depth: $ddepth — $dwhy"
    scope="$ddepth"; depth_skip=1
  else
  [ -z "$ddepth" ] || depth_line_say "$ddepth" "$dwhy"
  for k in test lint typecheck build uat; do
    c="$(cfg "$k" "")"
    [ -z "$c" ] && continue
    # change-sized.md § 5: at scoped depth the slow live tier is deferred, said once
    if [ "$k" = uat ] && [ "$ddepth" = scoped ]; then uat_deferred_say; continue; fi
    # test — change-scoped selection (test-surfaces.md § 6), and ONLY when test_select: is set:
    # which of the ops/SURFACES.tsv commands can this change break? The decision itself lives in
    # core.sh (surface_change_set + surface_select_cmd) and is shared with `land --express`, so the
    # two lanes cannot disagree. Unset ⇒ this block is never entered and the loop is 6.3, byte for
    # byte. Selection is all-or-nothing: one changed path without a row ⇒ the whole suite (D3).
    sel=""
    if [ "$k" = test ] && [ "$full" -eq 0 ] && [ -z "$dirty" ] && { [ -n "$(cfg test_select "")" ] || [ "$(cfg test_related "")" != "-" ]; }; then
      csf="$(mktemp)"
      if surface_change_set $fflag > "$csf"; then
        if [ ! -s "$csf" ] && [ -z "$(cfg test_select "")" ]; then
          # a carry is a test_select feature: unset runs test: verbatim, exactly as 6.8.0 (T-209)
          :
        elif [ ! -s "$csf" ]; then
          # BOUNDED and EMPTY: only board files moved since an ancestor stamp — the batch-wave
          # finish case — so the baseline's verdict carries to HEAD: the whole loop is skipped and
          # HEAD is re-stamped below with the scope that was actually proven.
          if [ "${SURFACE_BOUND:-}" = run ]; then
            scope=none; carry=1
            note "nothing this run changed needs a suite"
            rm -f "$csf"; break
          fi
          bsha="${SURFACE_BASELINE:-$head}"; scope="${SURFACE_BASELINE_SCOPE:-full}"; carry=1
          say "suite already green at $(printf '%.7s' "$bsha") — only board files changed since; skipped, proven $scope (qa --force re-runs it)"
          rm -f "$csf"; break
        fi
        np="$(grep -c . "$csf" || true)"
        if sel="$(test_select_for "$csf")"; then
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
          # test_select unset: the related attempt alone failed — stay as quiet as before it existed
          if [ -n "$(cfg test_select "")" ]; then note "test — running the whole suite: $why"; fi
        fi
      else
        [ -z "$(cfg test_select "")" ] || note "test — running the whole suite: no proven baseline on $BASE (no stamp, --force, or a stamp that is not an ancestor)"
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
        tail -20 "$out" | sed 's/^/     /'
        red=1; sred=1; sred_any=1; break
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
      tail -20 "$out" | sed 's/^/     /'
      red=1; sred_any=1
    fi
  done
  fi
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
  [ "$ran" -eq 0 ] && [ "$skip" -eq 0 ] && [ "$carry" -eq 0 ] && [ "$depth_skip" -eq 0 ] && note "no test/lint/typecheck/build/uat in CONVENTIONS.md — only board + env checked"
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
    # speed.md § 4: a finding whose text starts CRUFT (a leftover branch) is still red, but it says
    # nothing about the code the suite just proved, so it alone never withholds the stamp. Any other
    # finding is a hard red, and so is a red drift that printed no finding at all (it died on
    # something we cannot classify). MAP Deltas and LEARNED are advisory since minutes.md § 7.
    if ! grep -q '^⚠' "$out" || grep '^⚠' "$out" | grep -qv '^⚠ \[[0-9]*\] CRUFT'; then hred=1; fi
  fi
  # minutes.md § 7: the doc-overflow notes (MAP deltas, LEARNED bullets) are advice — drift never
  # counts them, so they can never red qa or withhold the stamp; qa only passes them on.
  grep -E '^   advisory: (MAP|LEARNED): ' "$out" || true
  if ( cmd_doctor ) >"$out" 2>&1; then
    say "doctor — env OK"
  else
    printf '⛔ doctor — RED:\n'
    tail -20 "$out" | sed 's/^/     /'
    red=1; hred=1
  fi
  rm -f "$out"
  # Stamp only a suite we actually RAN and that was fully green. Never stamp a skipped run (it
  # would just re-write the same sha) and never stamp a dirty tree — the stamp claims "this commit
  # is proven", and an uncommitted edit means the thing proven is not the thing on disk.
  # The stamp is decided BEFORE the red verdict (speed.md § 4): every suite key green and the only
  # other reds CRUFT-class ⇒ stamp, and qa STILL exits 1 below — so the next qa at this HEAD clears
  # the branches without paying the suite again. Any other red withholds it, exactly as before.
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
  if { [ "$ran" -ge 1 ] || [ "$carry" -eq 1 ] || [ "$depth_skip" -eq 1 ]; } && [ "$head" != "none" ] && [ "$sred_any" -eq 0 ] && [ "$hred" -eq 0 ]; then
    if [ "$head2" = "$head" ] && [ -z "$dirty" ] && [ -z "$dirty2" ]; then
      mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
      printf '%s %s %s\n' "$head" "$(date +%s)" "$scope" > "$PRIMARY/.polaris/suite-stamp" 2>/dev/null || true
      [ "$red" -eq 0 ] || note "suite stamp kept at $(printf '%.7s' "$head") — the only reds are leftover branches (CRUFT), so the next qa here skips the suite"
    else
      note "⚠ HEAD moved or the tree is not clean — stamp withheld, so the next qa re-runs the suite"
    fi
  fi
  # decision log (test-depth.md § 5): ONE row per qa that actually reached a depth verdict —
  # AFTER the run, so secs/rc are real; never when the gate didn't run (skip/force/full/unbounded).
  if [ -n "$ddepth" ]; then
    if [ -n "$dtf" ]; then
      qf="${dtf%% *}"
      qplan="$(fm_get plan "$qf" 2>/dev/null)"
      qtaskid="$(fm_get id "$qf" 2>/dev/null)"; [ -n "$qtaskid" ] || qtaskid="$(basename "$qf" .md)"
    else
      qplan=""; qtaskid=""
    fi
    if [ -z "$qplan" ]; then
      qpf="$(next_dir)/plan"
      [ -f "$qpf" ] && qplan="$(tr -d ' \r\n' < "$qpf" 2>/dev/null)"
    fi
    dsecs=$(( $(date +%s) - t0 ))
    set -f   # word-split the paths below on IFS, never glob-expand one that happens to contain * or ?
    decision_log test_depth "$qplan" "$qtaskid" "$ddepth" "$dwhy" "$dsecs" "$red" $([ -s "$dcsf" ] && head -20 "$dcsf")
    set +f
  fi
  [ -z "$dcsf" ] || rm -f "$dcsf"
  [ "$red" -eq 0 ] || die "qa: red — fix the ⛔ lines above before calling the work done"
  say "qa: all green"
}

_fin_landed_gate() { # PRIVATE to cmd_finish (safe-landing.md § 7, as corrected by v1.3 § J): every
  # task in done/ this run — plan: equal to the session's plan record, or all of done/ without one —
  # whose feat/<ID> still exists must have its files on $BASE. A task whose branch is gone is rc 2 to
  # landed_content_ok, nothing to prove, so the candidates are ONE for-each-ref, never a scan of
  # done/. A differing path is MISSING only when no commit on $BASE after the task's newest landed
  # [<ID>] commit touched it under another task's [<other ID>] (chain tasks share files, § C); no
  # landed commit on $BASE at all → every differing path is missing. One `⛔` line per task, counted
  # as pending in the caller's PEND, so qa and the cleanup below never run while one is red.
  local ref id seen=" " tf fplan="" fpf bad rc landed miss nl oifs
  nl='
'
  fpf="$(next_dir)/plan"
  [ -f "$fpf" ] && fplan="$(tr -d ' \r\n' < "$fpf" 2>/dev/null)"
  for ref in $(git -C "$PRIMARY" for-each-ref --format='%(refname)' refs/heads/feat/ refs/remotes/origin/feat/ 2>/dev/null); do
    id="${ref##*/feat/}"
    case "$seen" in *" $id "*) continue;; esac
    seen="$seen$id "
    tf="$BOARD/done/$id.md"
    [ -f "$tf" ] || continue
    if [ -n "$fplan" ] && [ "$(fm_get plan "$tf" 2>/dev/null)" != "$fplan" ]; then continue; fi
    rc=0; bad="$(landed_content_ok "$id")" || rc=$?
    [ "$rc" -eq 1 ] || continue
    landed="$(landed_sha "$id" || true)"
    miss="$bad"
    if [ -n "$landed" ]; then
      oifs="$IFS"; IFS="$nl"; set -f
      # shellcheck disable=SC2086 # one path per line, split on newlines only, globbing off
      set -- $bad
      IFS="$oifs"; set +f
      # ONE log over the differing paths: a path touched later by another task's commit was changed
      # on purpose after this one landed — superseded, not lost
      miss="$( { git -C "$PRIMARY" --literal-pathspecs -c core.quotepath=off log --format='%x01%s' --name-only "$landed..$BASE" -- "$@" 2>/dev/null
                 printf '\002\n%s\n' "$bad"; } | awk -v me="[$id]" '
        $0 == "\002" { p = 1; next }
        p == 1 { if ($0 != "" && !($0 in sup)) print; next }
        substr($0, 1, 1) == "\001" { s = substr($0, 2); o = 0
                  if (match(s, /\[[^][]*\]$/) && substr(s, RSTART) != me) o = 1; next }
        $0 != "" && o { sup[$0] = 1 }')"
    fi
    [ -n "$miss" ] || continue
    PEND=$((PEND+1))
    printf '⛔ %s is done but its files are not on %s: %s\n' "$id" "$BASE" \
      "$(printf '%s\n' "$miss" | awk 'NR <= 5 { printf "%s%s", (NR > 1 ? " " : ""), $0 } END { if (NR > 5) printf " +%d more", NR - 5 }')"
  done
  return 0
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
  local fin_t0 fin_plan fin_pf
  fin_t0="$(date +%s)"
  [ "${1:-}" = "--force" ] && force=1
  fin_pending() { PEND=$((PEND+1)); printf '⛔ pending: %s\n' "$1"; }
  fin_caveat()  { CAV=$((CAV+1));  CAVS="$CAVS$1
"; }
  fin_count() { ls "$BOARD/$1" 2>/dev/null | grep -c '\.md$' || true; }
  fin_ids() { # ≤5 ids from a board column, comma-joined, "… +N more" beyond that (PROTOCOL.md § VOICE)
    local d="$1" g i=0 o=""
    for g in "$BOARD/$d/"*.md; do [ -e "$g" ] || break
      i=$((i+1)); g="${g##*/}"; [ "$i" -le 5 ] && o="${o:+$o, }${g%.md}"
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
  _fin_landed_gate
  # drain: (ops/contracts/hands-free-knobs.md) decides whether a queued task blocks the close. Under
  # `plan` one "go" authorizes THE PLAN, not the board, so ready/ is legitimately non-empty at the
  # end — gating on it there would make the default run un-finishable. Under queue/backlog it gates.
  rd=$(fin_count ready); dr="$(cfg drain "")"; dr="${dr:-plan}"
  if [ "$rd" -gt 0 ]; then
    case "$dr" in
      plan) fin_caveat "$rd queued in ready/ under drain: plan — say so; \`start\` picks them up";;
      queue|backlog) fin_pending "$rd queued in ready/ and drain: $dr — drain them, or set drain: plan in ops/CONVENTIONS.md";;
      *) note "⚠ unknown drain: '$dr' — treating it as plan (plan | queue | backlog)"
         fin_caveat "$rd queued in ready/ under drain: plan — say so; \`start\` picks them up";;
    esac
  fi
  # An unmerged integrate/<date> is a whole wave that never reached <base> — the single most
  # expensive thing to mistake for done. Merged-but-undeleted is just cruft, and finish clears it
  # itself (minutes.md § 11.2): `branch -d` refuses an unmerged branch (and one checked out
  # anywhere), so it can never lose work. Only a refused delete leaves the old caveat.
  while IFS= read -r ib; do
    [ -n "$ib" ] || continue
    if git -C "$PRIMARY" merge-base --is-ancestor "$ib" "$BASE" 2>/dev/null; then
      if git -C "$PRIMARY" branch -q -d "$ib" >/dev/null 2>&1; then note "cleaned: $ib (merged)"
      else fin_caveat "$ib is merged but the branch is still here — git branch -d $ib"; fi
    else
      n=$(git -C "$PRIMARY" rev-list --count "$BASE..$ib" 2>/dev/null || echo 0)
      publish_resolve
      if [ "$PUB" = "pr" ]; then fin_caveat "$ib is a pushed v1 branch not in $BASE — seal --sync once its PR is merged"
      else fin_pending "$ib is not in $BASE — $n commit(s) unsealed (bash ops/polaris seal ${ib#integrate/})"; fi
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
  if [ -d "$LOCKS/.int-lease" ] && ! int_mine; then
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
    n="${lk%/}"; n="${n##*/}"; [ "$n" = ".board-mutex" ] && continue
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
    bgn="${bgd%/}"; bgn="${bgn##*/}"
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
  # save-hops.md § 2.4: and every parked ID carries its WHY, so the close can tell the owner what
  # each one needs without a `why <ID>` per task — the note of that ID's NEWEST "ev":"blocked"
  # event (highest ts; a tie goes to the later line, because EVENTS.ndjson is union-merged and line
  # order is not time order), JSON escapes undone, whitespace collapsed, cut at 80 characters with
  # `…`; no event, or an empty note → `no reason recorded`. ONE awk pass over the file. Characters
  # are counted by hand under LC_ALL=C: awk's own length() is bytes in some awks and characters in
  # others, and a cut inside a UTF-8 sequence prints garbage. Still fin_ids's list shape — at most
  # five, then "… +N more" (PROTOCOL.md § VOICE).
  local blid="" blw
  bl=$(fin_count blocked)
  if [ "$bl" -gt 0 ]; then
    for f in "$BOARD/blocked/"*.md; do [ -e "$f" ] || break; f="${f##*/}"; blid="$blid ${f%.md}"; done
    blw="$(LC_ALL=C awk -v ids="$blid" -v evf="$EVENTS" '
      function jv(s, k,   p, i, c, o) {        # string field k of the JSON line s, escapes undone
        p = index(s, "\"" k "\":\""); if (p == 0) return ""
        s = substr(s, p + length(k) + 4); o = ""
        for (i = 1; i <= length(s); i++) {
          c = substr(s, i, 1)
          if (c == "\"") break
          if (c == "\\") { c = substr(s, ++i, 1); if (c == "t" || c == "n" || c == "r") c = " " }
          o = o c
        }
        return o
      }
      BEGIN {
        n = split(ids, I, " "); for (k = 1; k <= n; k++) want[I[k]] = 1
        while ((getline ln < evf) > 0) {
          if (index(ln, "\"ev\":\"blocked\"") == 0) continue
          id = jv(ln, "id"); if (!(id in want)) continue
          t = 0; if (match(ln, /"ts":[0-9]+/)) t = substr(ln, RSTART + 5, RLENGTH - 5) + 0
          if ((id in at) && t < at[id]) continue
          at[id] = t; why[id] = jv(ln, "note")
        }
        for (k = 1; k <= n && k <= 5; k++) {
          w = why[I[k]]; gsub(/[ \t]+/, " ", w); sub(/^ /, "", w); sub(/ $/, "", w)
          if (w == "") w = "no reason recorded"
          c = 0
          for (i = 1; i <= length(w); i++) {    # a UTF-8 character starts at any non-continuation byte
            b = substr(w, i, 1)
            if ((b < "\200" || b >= "\300") && ++c > 80) { w = substr(w, 1, i - 1) "…"; break }
          }
          o = o (k > 1 ? " · " : "") I[k] " (" w ")"
        }
        if (n > 5) o = o " … +" (n - 5) " more"
        printf "%s", o
      }')"
    fin_caveat "$bl blocked — $blw (name what is parked, and why, in your close)"
  fi
  # A self-landed lane leaves its own worktree and branch behind by design (it cannot remove the
  # ground it stands on), and any later command run from inside it beats it fresh again. Once
  # nothing is building and nothing waits to land (PEND still 0 here), a CLEAN worktree of a done
  # task is a finished lane: its beat goes quiet and the same lossless pass qa makes (cruft_clear)
  # takes it — the branch only once proven landed, never a worktree holding anything uncommitted,
  # never one the caller stands in — so it never shows up below as a sweep for somebody to run
  # by hand (minutes.md § 7). Anything it leaves keeps today's caveat.
  if [ "$PEND" -eq 0 ]; then
    for f in "$PRIMARY"/.polaris/wt/*/; do
      [ -e "$f" ] || break
      n="${f%/}"; n="${n##*/}"
      if [ -f "$BOARD/done/$n.md" ] && [ -d "$GCD/worktrees/$n" ] && [ -z "$(git -C "$f" status --porcelain 2>/dev/null | head -1)" ]; then
        printf '1\n' 2>/dev/null > "$GCD/worktrees/$n/polaris-beat" || true
      fi
    done
    cruft_clear
  fi
  for f in "$PRIMARY"/.polaris/wt/*/; do
    [ -e "$f" ] || break
    n="${f%/}"; n="${n##*/}"
    { task_file "$n" active >/dev/null || task_file "$n" review >/dev/null; } && continue
    if [ -f "$BOARD/done/$n.md" ] && _wt_stood_in "$n"; then   # minutes.md § 14: it clears from elsewhere
      fin_caveat "worktree .polaris/wt/$n is where this command ran from — the next finish from the project folder clears it"
    else
      fin_caveat "worktree .polaris/wt/$n has no active task — bash ops/polaris sweep --fix"
    fi
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
  publish_resolve
  if [ "$PUB" != "pr" ] && has_remote && git -C "$PRIMARY" show-ref -q --verify "refs/remotes/origin/$BASE" 2>/dev/null; then
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
      # safe-landing.md v1.1 § F: name the red key(s), in qa's order, from qa's `⛔ <key> — ` header
      # lines, then each red key's whole block verbatim (the header and its 5-space-indented lines),
      # indented 5 more. ONE awk pass. No header at all (qa died before any) → today's tail -6.
      w="$(awk '/^⛔ [^ ]+ — / { k = $2; o = o (o == "" ? "" : ", ") k }
                END { printf "%s", o }' "$out")"
      if [ -n "$w" ]; then
        fin_pending "qa is red on $BASE — $w"
        awk '/^⛔ [^ ]+ — / { b = 1; print "     " $0; next }
             b && /^     / { print "     " $0; next }
             { b = 0 }' "$out"
      else
        fin_pending "qa is red on $BASE"
        tail -6 "$out" | sed 's/^/     /'
      fi
    fi
    rm -f "$out"
  fi

  # decision log (test-depth.md § 5): one `finish` row, win or lose, AFTER the checks above so
  # secs/rc are real. plan: the recorded session plan only — finish is about the whole run, never
  # one task. Best-effort, never gates (decision_log swallows its own failures).
  fin_plan=""; fin_pf="$(next_dir)/plan"
  [ -f "$fin_pf" ] && fin_plan="$(tr -d ' \r\n' < "$fin_pf" 2>/dev/null)"
  if [ "$PEND" -gt 0 ]; then
    decision_log finish "$fin_plan" "" "" "" "$(( $(date +%s) - fin_t0 ))" 1
    [ "$PEND" -eq 1 ] && { w="thing"; it="it"; } || { w="things"; it="them"; }
    die "finish: not done — $PEND $w pending; fix $it and run finish again"
  fi
  decision_log finish "$fin_plan" "" "" "" "$(( $(date +%s) - fin_t0 ))" 0

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

  # publish: pr (publish-modes.md v2 § ship branch): local $BASE ran ahead of origin by design.
  # Fast-forward it to origin ship/<date> (an open ship/* is reused, so the same PR updates) and
  # print the ONE link. Nothing here ever pushes $BASE itself.
  local shp="" shurl shahead
  if [ "$PUB" = "pr" ] && has_remote; then
    shp="$(git -C "$PRIMARY" ls-remote --heads origin 'refs/heads/ship/*' 2>/dev/null | awk '{print $2}' | sed 's#^refs/heads/##' | sort | head -1)"
    shahead=1
    if [ -z "$shp" ]; then
      git -C "$PRIMARY" show-ref -q --verify "refs/remotes/origin/$BASE" 2>/dev/null \
        && shahead=$(git -C "$PRIMARY" rev-list --count "origin/$BASE..$BASE" 2>/dev/null || echo 0)
      shp="ship/$(date +%F)"
    fi
    if [ "$shahead" -gt 0 ]; then
      git -C "$PRIMARY" push -q origin "refs/heads/$BASE:refs/heads/$shp" >/dev/null 2>&1 \
        || die "finish: could not fast-forward origin $shp (diverged? it must only ever grow) — nothing else was touched"
      mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
      printf '%s\n' "$shp" > "$PRIMARY/.polaris/ship" 2>/dev/null || true
      shurl="$(pr_create_url "$(git -C "$PRIMARY" remote get-url origin 2>/dev/null)" "$(date +%F)" "$BASE" "$shp")"
      if [ -n "$shurl" ]; then say "ship: open this one link, merge it with a MERGE COMMIT (never squash):"; printf '%s\n' "$shurl"
      else say "ship: open a PR from $shp into $BASE on your host (merge commit, never squash)"; fi
    fi
  fi

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
