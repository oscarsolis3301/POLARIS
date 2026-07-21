# lib/selftest/spine.sh — selftest spine: drill_on/ngwait/ensure_origin + selftest(), the throwaway-
# repo mechanics chain; labeled drill bodies live in the sibling group files (drill_<label>).
drill_on() { # T-033/T-040: is labeled drill $1 selected by the current --only patterns? Reads
  # selftest()'s local SELFTEST_ONLY (dynamic scope): empty = full run = every drill on; else a
  # comma-separated case-glob list (ops/contracts/selftest-sharding.md) — selected when $1 matches
  # ANY element; a single element behaves exactly like the pre-split single pattern.
  # Plain case, NEVER inside $(...) — bash 3.2 mis-parses `case` in command substitution.
  if [ -z "${SELFTEST_ONLY:-}" ]; then return 0; fi
  local _dp _dr
  _dr="${SELFTEST_ONLY},"
  while [ -n "$_dr" ]; do
    _dp="${_dr%%,*}"; _dr="${_dr#*,}"
    [ -n "$_dp" ] || continue
    case "$1" in $_dp) return 0;; esac
  done
  return 1
}

ngwait() { # T-033: poll (bounded, ≤2s) for line $1 in the selftest's backgrounded notify.log.
  # File-scope (reads selftest's $T via dynamic scope) so any drill using it — notify AND
  # pr-publish — stands alone under --only, not just when the notify drill defined it inline.
  local i=0; while [ "$i" -lt 20 ]; do grep -q "$1" "$T/notify.log" 2>/dev/null && return 0; sleep 0.1; i=$((i+1)); done; return 1
}

ensure_origin() { # T-033: self-provision the scratch bare origin that the remote/syncrace/pr-publish
  # drills share, so each stands alone under --only. No-op once any of them has created it; in the
  # full run the remote drill makes it first and the rest are no-ops (byte-identical outcome).
  git remote get-url origin >/dev/null 2>&1 && return 0
  git init -q --bare "$T/origin.git"
  git remote add origin "$T/origin.git"
  git push -qu origin main >/dev/null 2>&1 || true
  git rev-parse -q --verify refs/heads/polaris/board >/dev/null 2>&1 \
    && git push -q origin refs/heads/polaris/board >/dev/null 2>&1 || true   # syncrace clones origin/polaris/board
  return 0
}

selftest() { # end-to-end mechanics drill in a throwaway repo — run once per new machine.
  # $1 (optional): --only patterns, comma-separated. Empty = full run, byte-identical to the
  #    pre-5.15 selftest; a single pattern = the pre-split --only, byte-identical.
  # $2 (optional): --parallel shard count N (integer >= 2, validated by cmd_doctor) — round-robin
  #    the selected labels into N child re-invocations (ops/contracts/selftest-sharding.md).
  local SELFTEST_ONLY="${1:-}"
  local SELFTEST_PAR="${2:-}"
  # Every label a drill_on gate below uses, in run order — the contract's minimum set. An --only
  # element matching NONE of these dies HERE, before the throwaway repo is even created.
  local SELFTEST_LABELS='fmlist tcm report metrics brain rules drift hardening qa remote syncrace notify grant upgrade pr-publish express hint brief'
  local st_total=0 st_hit=0 st_lbl
  local st_sel="" st_pat st_rest st_pat_hit
  for st_lbl in $SELFTEST_LABELS; do st_total=$((st_total+1)); done
  if [ -n "$SELFTEST_ONLY" ]; then
    st_rest="$SELFTEST_ONLY,"
    while [ -n "$st_rest" ]; do
      st_pat="${st_rest%%,*}"; st_rest="${st_rest#*,}"
      [ -n "$st_pat" ] || continue
      st_pat_hit=0
      for st_lbl in $SELFTEST_LABELS; do
        case "$st_lbl" in $st_pat) st_pat_hit=$((st_pat_hit+1));; esac
      done
      [ "$st_pat_hit" -gt 0 ] || die "unknown drill label '$st_pat' — valid labels: $SELFTEST_LABELS"
    done
  fi
  for st_lbl in $SELFTEST_LABELS; do
    drill_on "$st_lbl" || continue
    st_sel="$st_sel$st_lbl "
    st_hit=$((st_hit+1))
  done
  # --parallel (ops/contracts/selftest-sharding.md): partition the selected labels round-robin into
  # N child re-invocations — own logs, own throwaway repos, total isolation. Each shard pays a full
  # spine (~1 min setup): sharding trades CPU for wall-clock. Serial (no --parallel) is untouched.
  if [ -n "$SELFTEST_PAR" ]; then
    local st_n=0 st_i st_j st_list st_pids st_pid st_shlbl st_red=0
    for st_lbl in $st_sel; do st_n=$((st_n+1)); done
    if [ "$SELFTEST_PAR" -gt "$st_n" ]; then
      note "--parallel clamped to $st_n (only $st_n labels selected)"
      SELFTEST_PAR="$st_n"
    fi
    SELFTEST_PTMP="$(mktemp -d)"   # NOT local: the EXIT trap must still see it after selftest returns
    trap 'rm -rf "$SELFTEST_PTMP"' EXIT
    st_pids=""
    st_j=0
    while [ "$st_j" -lt "$SELFTEST_PAR" ]; do
      st_list=""
      st_i=0
      for st_lbl in $st_sel; do
        [ $((st_i % SELFTEST_PAR)) -eq "$st_j" ] && st_list="$st_list,$st_lbl"
        st_i=$((st_i+1))
      done
      st_list="${st_list#,}"
      st_j=$((st_j+1))
      printf '%s\n' "$st_list" > "$SELFTEST_PTMP/shard.$st_j.labels"
      "$SELF" doctor --selftest --only "$st_list" > "$SELFTEST_PTMP/shard.$st_j.log" 2>&1 &
      st_pids="$st_pids $!"
    done
    st_j=0
    for st_pid in $st_pids; do   # wait for ALL shards first; report below, in shard order
      st_j=$((st_j+1))
      if wait "$st_pid"; then echo 0 > "$SELFTEST_PTMP/shard.$st_j.rc"; else echo 1 > "$SELFTEST_PTMP/shard.$st_j.rc"; fi
    done
    st_j=0
    while [ "$st_j" -lt "$SELFTEST_PAR" ]; do
      st_j=$((st_j+1))
      st_shlbl="$(tr ',' ' ' < "$SELFTEST_PTMP/shard.$st_j.labels")"
      if [ "$(cat "$SELFTEST_PTMP/shard.$st_j.rc")" = "0" ]; then
        say "shard $st_j/$SELFTEST_PAR green — $st_shlbl"
      else
        cat "$SELFTEST_PTMP/shard.$st_j.log"
        printf '⛔ shard %s/%s RED — %s\n' "$st_j" "$SELFTEST_PAR" "$st_shlbl"
        st_red=$((st_red+1))
      fi
    done
    [ "$st_red" -eq 0 ] || exit 1
    say "selftest passed — $SELFTEST_PAR shards"
    return 0
  fi
  local T; T="$(mktemp -d)"
  note "selftest in $T${SELFTEST_ONLY:+  (subset: $SELFTEST_ONLY)}"
  ( set -e; cd "$T"
    git init -q -b main repo 2>/dev/null || { git init -q repo; git -C repo symbolic-ref HEAD refs/heads/main; }
    cd repo; git config user.email t@t; git config user.name t
    mkdir -p src; echo x > src/a.txt
    git add -A; git commit -qm init
    "$SELF" init-board >/dev/null
    git add -A; git commit -qm board
    # board files land AFTER init-board: gitignored on base, disk-only — quiet-board contract
    printf -- '---\nid: T-1\ntitle: land a file\ntype: feature\npoints: 1\nwsjf: 9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/a.txt\nverify:\n  - test -f src/a.txt\n---\n## Why\nthe file must land so the sprint report has a story to tell.\n\n## Acceptance criteria\n- [ ] the file lands\n' > ops/board/ready/T-1.md
    # race: 8 parallel claims, exactly one may win
    local i wins=0
    for i in 1 2 3 4 5 6 7 8; do ( "$SELF" claim T-1 >/dev/null 2>&1 && echo WIN ) & done > "$T/race" 2>&1
    wait; wins=$(grep -c WIN "$T/race" || true)
    [ "$wins" -eq 1 ] || { echo "RACE FAIL: $wins winners"; exit 1; }
    cd .polaris/wt/T-1; echo y >> src/a.txt; git commit -qam ok
    "$SELF" verify T-1 >/dev/null || { echo "VERIFY FAIL (should pass)"; exit 1; }
    echo z > src/illegal.txt; git add -A; git commit -qm bad
    "$SELF" verify T-1 >/dev/null 2>&1 && { echo "OWNERSHIP FAIL (should reject)"; exit 1; }
    git reset -q --hard HEAD~1
    "$SELF" handoff T-1 > "$T/ho.out"
    grep -q 'Integrate now' "$T/ho.out" || { echo "HANDOFF NOTICE FAIL (last lane must print the integrate hint)"; exit 1; }
    cd "$T/repo"
    if drill_on fmlist; then
    drill_fmlist
    fi   # drill_on fmlist
    # ====================== v5.12 clean-history drills =======================
    # land (squash → ONE rich commit) → seal (tagged summary merge) → history →
    # done (rule-1 gate + landed: stamp) → rollback (task + sprint reverts).
    for c in task-commit-msg land seal history rollback; do
      "$SELF" help | grep -q "$c" || { echo "USAGE FAIL: $c missing from help"; exit 1; }
    done
    if drill_on tcm; then
    drill_tcm
    fi   # drill_on tcm
    # land: one commit, contract subject + Landed-from trailer, clean tree after
    printf '# SPRINT 1 — selftest sprint  capacity: 5\n' > ops/SPRINT.md   # moved set: disk-only, ignored on base
    git checkout -q -b integrate/2026-01-01
    "$SELF" land T-1 > "$T/land.out" 2>&1 || { cat "$T/land.out"; echo "LAND FAIL"; exit 1; }
    # T-038 land noise (clean-history v2.2): git 2.53's squash chatter must not reach land output
    grep -qi 'Squash commit' "$T/land.out" && { echo "LAND NOISE FAIL (git 'Squash commit' line leaked)"; exit 1; }
    grep -qi 'stopped before committing' "$T/land.out" && { echo "LAND NOISE FAIL (git 'stopped before committing' line leaked)"; exit 1; }
    git log -1 --format=%s | grep -q '^feat(src): land a file \[T-1\]$' || { echo "LAND SUBJECT FAIL"; exit 1; }
    [ "$(git log -1 --format=%B | sed -n 's/^Landed-from: //p' | tr -d ' \r')" = "$(git rev-parse feat/T-1)" ] \
      || { echo "LAND TRAILER FAIL"; exit 1; }
    git diff --quiet && git diff --cached --quiet || { echo "LAND DIRTY FAIL (must leave zero uncommitted state)"; exit 1; }
    # seal: one --no-ff merge on main, per-task bullet body, lightweight sprint tag
    "$SELF" seal 2026-01-01 >/dev/null || { echo "SEAL FAIL"; exit 1; }
    git rev-parse -q --verify refs/tags/sprint/1 >/dev/null || { echo "SEAL TAG FAIL"; exit 1; }
    git log -1 --format=%s | grep -q '^Sprint 1 — selftest sprint$' || { echo "SEAL SUBJECT FAIL"; exit 1; }
    git log -1 --format=%b | grep -q '^- feat(src): land a file \[T-1\]$' || { echo "SEAL BULLET FAIL"; exit 1; }
    if drill_on report; then
    drill_report
    fi   # drill_on report
    # ==================== end T-023 sprint-report drill ====================
    # history: sprint line visible, board noise filtered; --tasks drills into the squash commit
    "$SELF" history > "$T/hist.out"
    grep -q 'Sprint 1 — selftest sprint' "$T/hist.out" || { echo "HISTORY FAIL (sprint merge missing)"; exit 1; }
    grep -q 'chore(board)' "$T/hist.out" && { echo "HISTORY FILTER FAIL (board noise must hide)"; exit 1; }
    "$SELF" history --tasks 1 > "$T/htasks.out"
    grep -q 'land a file \[T-1\]' "$T/htasks.out" || { echo "HISTORY TASKS FAIL"; exit 1; }
    grep -q 'docs(sprint-' "$T/htasks.out" && { echo "HISTORY TASKS REPORT FILTER FAIL (docs(sprint-N): report must not appear in the task view)"; exit 1; }
    # done on a squash landing: rule-1 gate accepts (feat/T-1 is NOT an ancestor of main) + landed: stamp
    "$SELF" done T-1 >/dev/null
    [ "$(sed -n 's/^landed: //p' ops/board/done/T-1.md | tr -d ' \r')" = "$(git log --format='%H %s' main | awk '/\[T-1\]$/ {print $1; exit}')" ] \
      || { echo "LANDED STAMP FAIL (done must stamp the squash SHA)"; exit 1; }   # the land commit (subject ENDS [T-1]); the wave's report commit now tips integrate
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/T-1" ] && { echo "LOCK CLEANUP FAIL"; exit 1; }
    # ---- T-029 Rule-2-blind attribution drill (ops/contracts/sprint-report.md v1.2) ----
    # T-1 is now a sealed, done, tag-ancestor task. Strip the [T-1] bullet from the seal merge
    # body (keep the 'Sprint 1 — …' subject) so Rule 1 goes blind, then report --all must STILL
    # attribute T-1 to sprint 1 via Rule 2 (tag ancestry) — never (unsealed). This is RED against
    # the pre-fix resolve_sprint_ids, whose combined `local` read tag/prev from cmd_report's own
    # n (""), so `rev-parse refs/tags/sprint/` failed and Rule 2 silently no-op'd. Save/restore so
    # the rollback drills below see byte-identical git state.
    r2save="$(git rev-parse main)"
    git commit -q --amend -m 'Sprint 1 — selftest sprint'   # drop the [T-1] bullet, keep the subject
    git tag -f sprint/1 HEAD >/dev/null                      # tag follows the amended merge
    git log -1 --format=%b HEAD | grep -q '\[T-1\]' && { echo "RULE2 SETUP FAIL (merge body must be [ID]-blind)"; exit 1; }
    "$SELF" report --all >/dev/null || { echo "REPORT RULE2 RUN FAIL"; exit 1; }
    grep -q '^## T-1 — land a file$' docs/sprints/sprint-1.md || { echo "REPORT RULE2 ATTR FAIL (task must render under its sprint)"; exit 1; }
    grep -q '^## (unsealed)$' docs/sprints/sprint-1.md && { echo "REPORT RULE2 UNSEALED FAIL (a tag-ancestor done task must never fall to (unsealed))"; exit 1; }
    git tag -f sprint/1 "$r2save" >/dev/null                 # restore tag → wave-1 merge
    git reset -q --hard "$r2save"                            # restore main + the sealed sprint-1.md render
    # ---- end T-029 Rule-2-blind attribution drill ----
    # rollback: task revert applies, then (state reset between) the sprint revert applies too
    "$SELF" rollback T-1 >/dev/null || { echo "ROLLBACK TASK FAIL"; exit 1; }
    [ "$(cat src/a.txt)" = "x" ] || { echo "ROLLBACK CONTENT FAIL (the y line must go)"; exit 1; }
    git reset -q --hard HEAD~1        # drop the task revert so the sprint revert sees the same diff
    "$SELF" rollback sprint/1 >/dev/null || { echo "ROLLBACK SPRINT FAIL"; exit 1; }
    [ "$(cat src/a.txt)" = "x" ] || { echo "ROLLBACK SPRINT CONTENT FAIL"; exit 1; }
    git reset -q --hard HEAD~1        # back to the sealed state for the drills below
    # ==================== end v5.12 clean-history drills =====================
    if drill_on brain; then
    drill_brain
    fi   # drill_on brain
    # ==================== end T-030 brain drills ====================
    if drill_on metrics; then
    drill_metrics
    fi   # drill_on metrics
    # ================ v5.13 second-seal drill (clean-history v2) =================
    # A sprint's SECOND integration wave: wave 2 lands on the same integrate branch (caught up
    # to base first), seal runs again → same --no-ff merge, tag sprint/1 MOVES to the new merge
    # (old → new logged), history --tasks 1 spans both waves, and the wave-2 task passes done
    # via the rule-1 gate its seal just made true. (State here: main parked ON the sealed merge.)
    w1tag="$(git rev-parse refs/tags/sprint/1)"
    printf -- '---\nid: T-W\ntitle: wave two file\ntype: feature\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nmap_delta: wave two exists\nfiles_owned:\n  - src/w.txt\nverify: []\n---\n' > ops/board/ready/T-W.md
    "$SELF" claim T-W >/dev/null
    ( cd .polaris/wt/T-W && echo w > src/w.txt && git add -A && git commit -qm ok && "$SELF" handoff T-W >/dev/null )
    git checkout -q integrate/2026-01-01
    git merge -q --ff-only main || { echo "SECOND-SEAL FF FAIL (integrate must catch up to base)"; exit 1; }
    "$SELF" land T-W >/dev/null || { echo "SECOND-SEAL LAND FAIL (wave-2 land on the same integrate branch)"; exit 1; }
    # reused sprint number: tag exists but is NOT an ancestor of base → die BEFORE the merge,
    # nothing mutated (a dangling parentless commit stands in for foreign history)
    mainpre="$(git rev-parse main)"
    git tag -f sprint/1 "$(git commit-tree -m dangling "HEAD^{tree}" </dev/null)" >/dev/null
    "$SELF" seal 2026-01-01 > "$T/seal-reuse.out" 2>&1 && { echo "REUSED SPRINT FAIL (non-ancestor tag must die)"; exit 1; }
    grep -q 'reused sprint number' "$T/seal-reuse.out" || { echo "REUSED SPRINT MSG FAIL (die must name the reuse)"; exit 1; }
    [ "$(git rev-parse main)" = "$mainpre" ] || { echo "REUSED SPRINT MUTATE FAIL (failed gate must mutate nothing)"; exit 1; }
    git tag -f sprint/1 "$w1tag" >/dev/null
    if drill_on brain; then bstamp1="$(cat .polaris/brain/.stamp)"; fi   # T-030: pre-seal stamp — seal auto-refreshes it (brain-gated: seal itself is spine)
    "$SELF" seal 2026-01-01 > "$T/seal2.out" || { echo "SECOND-SEAL FAIL (re-seal of the same sprint must pass)"; exit 1; }
    w2tag="$(git rev-parse refs/tags/sprint/1)"
    [ "$w2tag" != "$w1tag" ] || { echo "TAG MOVE FAIL (sprint/1 must leave the wave-1 merge)"; exit 1; }
    [ "$w2tag" = "$(git rev-parse main)" ] || { echo "TAG MOVE FAIL (sprint/1 must equal the new base HEAD)"; exit 1; }
    grep -q "sprint/1: $(git rev-parse --short "$w1tag") → $(git rev-parse --short "$w2tag")" "$T/seal2.out" \
      || { echo "TAG MOVE LOG FAIL (re-seal must name the old → new move)"; exit 1; }
    # T-030 seal auto-refresh: the fold touched board-changed, then refreshed the existing brain —
    # the stamp follows the new base sha and doctor must NOT read the board as stale.
    [ -f .polaris/board-changed ] || { echo "SEAL TOUCH FAIL (seal must touch board-changed)"; exit 1; }
    if drill_on brain; then
    [ "$(cat .polaris/brain/.stamp)" != "$bstamp1" ] || { echo "SEAL BRAIN REFRESH FAIL (seal must auto-refresh an existing brain)"; exit 1; }
    "$SELF" doctor 2>/dev/null | grep -q 'brain is stale' && { echo "SEAL BRAIN STALE FAIL (auto-refresh must leave .stamp newer than board-changed)"; exit 1; }
    fi   # drill_on brain
    "$SELF" history --tasks 1 > "$T/hist2.out"
    grep -q 'land a file \[T-1\]' "$T/hist2.out" || { echo "HISTORY WAVES FAIL (wave-1 task missing from --tasks)"; exit 1; }
    grep -q 'wave two file \[T-W\]' "$T/hist2.out" || { echo "HISTORY WAVES FAIL (wave-2 task missing from --tasks)"; exit 1; }
    "$SELF" run-verify T-W >/dev/null 2>&1 || { echo "SECOND-SEAL RUN-VERIFY FAIL (verify: [] must pass)"; exit 1; }
    "$SELF" done T-W >/dev/null || { echo "SECOND-SEAL DONE FAIL (wave-2 done must pass once its seal lands)"; exit 1; }
    if drill_on brain; then
    # T-038 (brain v1.1): the documented wave close land → seal → run-verify → done ends FRESH —
    # done auto-refreshes AFTER its board-changed touch (mirroring seal), so doctor must not warn.
    "$SELF" doctor 2>/dev/null | grep -q 'brain is stale' && { echo "DONE BRAIN STALE FAIL (done must auto-refresh; wave close must end fresh)"; exit 1; }
    fi   # drill_on brain
    if drill_on brain; then
    # T-030 seal-refresh-failure note: a BROKEN brain (.stamp is a directory, so the rebuild's
    # stamp write fails) must cost the wave nothing — seal rc 0, one ⚠ note, board state normal.
    # Brain-gated: the whole T-Z wave exists only to prove this brain behavior (quiet-board below
    # references T-1/T-W only, never T-Z, so skipping it leaves the spine self-consistent).
    printf -- '---\nid: T-Z\ntitle: wave three file\ntype: feature\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/z.txt\nverify: []\n---\n' > ops/board/ready/T-Z.md
    "$SELF" claim T-Z >/dev/null
    ( cd .polaris/wt/T-Z && echo z > src/z.txt && git add -A && git commit -qm ok && "$SELF" handoff T-Z >/dev/null )
    git checkout -q integrate/2026-01-01
    git merge -q --ff-only main || { echo "THIRD-SEAL FF FAIL (integrate must catch up to base)"; exit 1; }
    "$SELF" land T-Z >/dev/null || { echo "THIRD-SEAL LAND FAIL"; exit 1; }
    rm -f .polaris/brain/.stamp; mkdir .polaris/brain/.stamp
    "$SELF" seal 2026-01-01 > "$T/seal3.out" || { cat "$T/seal3.out"; echo "SEAL REFRESH-FAIL RC FAIL (a failed brain refresh must never fail the seal)"; exit 1; }
    grep -q 'brain refresh failed' "$T/seal3.out" || { echo "SEAL REFRESH NOTE FAIL (the failure must print its ⚠ note)"; exit 1; }
    "$SELF" done T-Z >/dev/null || { echo "THIRD-SEAL DONE FAIL"; exit 1; }
    rm -rf .polaris/brain    # brain leaves the drill here — later doctors must run silent again
    fi   # drill_on brain (T-Z seal-refresh-failure wave)
    # ================== end v5.13 second-seal drill ==============================
    # ================== T-020 quiet-board drill (ops/contracts/quiet-board.md) ==================
    # The whole flow above (claim → handoff → land → seal → done, two waves) ran with the moved set
    # ignored on base: its chore(board) commits live on refs/heads/polaris/board, base first-parent
    # gained ZERO chore(board) commits, and T-W's map_delta landed as exactly ONE docs(map) commit.
    git rev-parse -q --verify refs/heads/polaris/board >/dev/null || { echo "QUIET REF FAIL (polaris/board must exist)"; exit 1; }
    for s in 'claim T-1' 'handoff T-1' 'done T-1' 'claim T-W' 'handoff T-W' 'done T-W'; do
      git log --format=%s refs/heads/polaris/board | grep -qx "chore(board): $s" || { echo "QUIET LOG FAIL (chore(board): $s missing on polaris/board)"; exit 1; }
    done
    [ "$(git rev-list --max-parents=0 refs/heads/polaris/board | wc -l | tr -d ' ')" = "1" ] || { echo "QUIET ORPHAN FAIL (exactly one parentless root)"; exit 1; }
    git log --first-parent --format=%s main | grep -q '^chore(board):' && { echo "QUIET BASE FAIL (base first-parent must gain ZERO chore(board) commits)"; exit 1; }
    [ "$(git log --format=%s main | grep -c '^docs(map):')" = "1" ] || { echo "QUIET MAP COUNT FAIL (non-empty map_delta = exactly ONE docs(map) commit on base)"; exit 1; }
    git log --format=%s main | grep -qx 'docs(map): T-W wave two exists' || { echo "QUIET MAP SUBJECT FAIL"; exit 1; }
    grep -q 'wave two exists' ops/MAP.md || { echo "QUIET MAP APPLY FAIL (delta line must append to ops/MAP.md)"; exit 1; }
    git ls-tree -r --name-only refs/heads/polaris/board | grep -v '^ops/board/' | grep -v '^ops/SPRINT\.md$' | grep -q . \
      && { echo "QUIET TREE FAIL (branch tree = ONLY ops/board/** + ops/SPRINT.md)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "QUIET CLEAN FAIL (board mutations must never dirty base status)"; exit 1; }
    # ================== end T-020 quiet-board drill ==================
    if drill_on rules; then
    drill_rules
    fi   # drill_on rules
    if drill_on drift; then
    drill_drift
    fi   # drill_on drift
    if drill_on hardening; then
    drill_hardening
    fi   # drill_on hardening
    if drill_on qa; then
    drill_qa
    fi   # drill_on qa
    # --- v5.11: no AI fingerprints — commit-msg hook strips provider attribution, keeps the message
    local hooksrc; hooksrc="$(dirname "$SELF")/hooks/commit-msg"
    if [ -f "$hooksrc" ]; then
      cp "$hooksrc" "$(git rev-parse --git-common-dir)/hooks/commit-msg"
      chmod +x "$(git rev-parse --git-common-dir)/hooks/commit-msg" 2>/dev/null || true
      echo drill > src/a.txt; git add -A
      git commit -qm 'feat: clean product

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
🤖 Generated with [Claude Code](https://claude.com/claude-code)'
      git log -1 --format=%B | grep -qiE 'co-authored-by|generated with' && { echo "ATTRIBUTION STRIP FAIL"; exit 1; }
      git log -1 --format=%B | grep -q 'feat: clean product' || { echo "ATTRIBUTION KEEP FAIL (subject must survive)"; exit 1; }
    fi
    if drill_on remote; then
    drill_remote
    fi   # drill_on remote
    if drill_on syncrace; then
    drill_syncrace
    fi   # drill_on syncrace
    if drill_on notify; then
    drill_notify
    fi   # drill_on notify
    if drill_on grant; then
    drill_grant
    fi   # drill_on grant
    # ================== T-006 staleness drills (ops/contracts/self-hosting.md) ==================
    # Fake `unzip`/`curl` on PATH make this deterministic and portable (no real network, no zip
    # binary needed — Git Bash ships none — matching the fixture style already used for notify-gate).
    mkdir -p "$T/bin"
    printf '#!/bin/sh\necho "commit: bbbbbbb"\n' > "$T/bin/unzip"; chmod +x "$T/bin/unzip"
    # 1) stale-zip check must gate on kit/ops/pack.py, not the dead pre-split ops/pack.py: with the
    #    tell absent, a present (fake-stale) zip must stay silent.
    : > polaris-v5.zip
    PATH="$T/bin:$PATH" "$SELF" doctor 2>/dev/null | grep -q 'polaris-v5.zip is STALE' \
      && { echo "STALEZIP GATE FAIL (no kit/ops/pack.py — must stay quiet)"; exit 1; }
    # 2) tell present → warns, naming the correct rebuild command
    mkdir -p kit/ops; : > kit/ops/pack.py
    PATH="$T/bin:$PATH" "$SELF" doctor 2>/dev/null > "$T/stale.out"
    grep -q 'polaris-v5.zip is STALE' "$T/stale.out" || { echo "STALEZIP FIRE FAIL (kit/ops/pack.py present + stale zip must warn)"; exit 1; }
    grep -q 'rebuild: python kit/ops/pack.py' "$T/stale.out" || { echo "STALEZIP HINT FAIL (rebuild hint must name kit/ops/pack.py)"; exit 1; }
    rm -f polaris-v5.zip kit/ops/pack.py; rmdir kit/ops kit 2>/dev/null || true
    # 3) version-cache tell: explicit `version` must query the channel fresh even when a passive
    #    command already spent today's once-a-day throttle (5.6.0 bug 2 — release-day false "up to
    #    date"). A fake curl stands in for the channel.
    printf '#!/bin/sh\necho "version: 8.8.8"\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"
    printf 'version: 1.0.0\nchannel: http://example.invalid/channel\n' > ops/VERSION
    mkdir -p .polaris
    printf 'checked: %s\nlatest: 1.0.0\n' "$(date +%Y-%m-%d)" > .polaris/update-cache
    PATH="$T/bin:$PATH" "$SELF" doctor >/dev/null 2>&1
    grep -q '^latest: 1.0.0$' .polaris/update-cache || { echo "THROTTLE FAIL (passive command must keep today's cached value)"; exit 1; }
    PATH="$T/bin:$PATH" "$SELF" version > "$T/ver.out" 2>&1
    grep -q '8.8.8' "$T/ver.out" || { echo "VERSION FRESH FAIL (explicit version must bypass the once-a-day throttle)"; exit 1; }
    grep -q '^latest: 8.8.8$' .polaris/update-cache || { echo "VERSION CACHE FAIL (fresh check must update the cache)"; exit 1; }
    rm -rf ops/VERSION .polaris/update-cache
    # ================== end T-006 staleness drills ==================
    if drill_on upgrade; then
    drill_upgrade
    fi   # drill_on upgrade
    # ================== end T-021 upgrade-migration drill ==================
    if drill_on pr-publish; then
    drill_pr-publish
    fi   # drill_on pr-publish
    # ================== end T-022 pr-publish drill ==================
    if drill_on express; then
    drill_express
    fi   # drill_on express
    if drill_on hint; then
    drill_hint
    fi   # drill_on hint
    # ========= end T-031 express-lane + slow-suite drills =========
    if drill_on brief; then
    drill_brief
    fi   # drill_on brief
    # ========= T-033 --only self-drills (ops/contracts/verification-tiering.md) — full run ONLY:
    # a subset run must never re-spawn selftest (infinite recursion), so gate on empty SELFTEST_ONLY.
    # nonsense pattern dies pre-spine (rc 1); --only fmlist runs spine + the fmlist drill and prints
    # the distinct subset pass line.
    if [ -z "$SELFTEST_ONLY" ]; then
      "$SELF" doctor --selftest --only 'no-such-drill-xyz' >/dev/null 2>&1 && { echo "ONLY UNKNOWN FAIL (nonsense pattern must die rc 1, pre-spine)"; exit 1; }
      "$SELF" doctor --selftest --only fmlist > "$T/only.out" 2>&1 || { cat "$T/only.out"; echo "ONLY SUBSET FAIL (--only fmlist must pass)"; exit 1; }
      grep -q 'selftest passed (subset: fmlist' "$T/only.out" || { echo "ONLY SUBSET LINE FAIL (distinct subset pass line missing)"; exit 1; }
    fi
    echo SELFTEST-PASS
  ) || { rm -rf "$T"; die "selftest FAILED — do not trust this environment until fixed"; }
  rm -rf "$T"
  if [ -n "$SELFTEST_ONLY" ]; then
    say "selftest passed (subset: $SELFTEST_ONLY — $st_hit of $st_total labeled drills; spine always runs)"
    return 0
  fi
  say "selftest passed: race(8→1) · ownership accept/reject · verify cmds · handoff+all-review notice · fm_list scalar/[]/flow/block+messy/depends_on · task-commit-msg format · land squash+trailer · seal merge+tag · history filter · done-on-squash+landed stamp · rollback task+sprint · second-seal tag-move+wave-spanning history+wave-2 done · quiet board (chores→polaris/board · zero base chores · orphan root · docs(map) once · tree=moved set · clean status) · EVENTS union sync race · legacy --no-ff done · done cleanup · events+metrics(+pts buckets) · _match · rules path/content/diff · drift overlap+strict · rename-reject · claim fan-out · glob-overlap · audit reject · why · dep-cycle · qa green/red · attribution strip · remote branch cleanup+sweep · notify-gate silence/env/severity · blocked event+why · severity info/gate · doctor knob composition · grant append+refusals(column/-m/overlap both ways) · upgrade-migration (orphan seed · untrack+ignore · ONE base commit · no-op re-run · quiet after) · primary-anchored claim/resume paths · fresh-clone materialization (doctor+resume) · uninstall board-branch delete local+origin · pr-publish (feat stays local · seal pushes ONLY integrate + title/bullets/URL + notify done, no ref moved · --sync subject gate/tag/branch cleanup both sides · done via rule 1 · direct --sync dies · unknown publish warns) · sprint report (seal commits docs(sprint-N) riding the wave · cmd_report --sprint/current/--all renders + prints, board read-only + idempotent) · brain (7-file build gitignored · INDEX routes all 5 · board digest names the landed task · stale warn → refresh clears · seal auto-refresh · refresh failure = note, never a red seal) · express (help form · qa suite stamp gated+formatted · 4 refusals pre-mutation: solo-review/risk-high/off+unknown/publish-pr · red suite unwind+kickback tail · happy path: done+landed stamp · tag moved · integrate deleted · clean tree · qa finish line) · slow-suite hint (paranoid+180s fires naming integration: batch · batch silent) · status --brief (one paragraph · Last landed:/Next up: markers · header sprint clause · active ids · no table pipe · plain status unchanged) · metrics In-plain-English summary (first line above the table · silent on empty EVENTS)"
}
