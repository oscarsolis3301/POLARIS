# lib/selftest/history.sh — selftest drills: tcm express pr-publish. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_tcm() {
    # task-commit-msg: pure formatter — subject map · Why verbatim · checkbox markers stripped ·
    # comment + ⛔ notes filtered · Files joined
    mkdir -p "$T/fmt"
    printf -- '---\nid: T-X\ntitle: format drill\ntype: bug\nscope: core\nfiles_owned:\n  - src/a.txt\n  - src/b.txt\n---\n## Why\nbecause history should read.\n\n## Acceptance criteria\n- [ ] box one\n- [x] box two\n\n## Notes\n<!-- comment line -->\n- kept note\n- ⛔ dropped note\n' > "$T/fmt/T-X.md"
    "$SELF" task-commit-msg "$T/fmt/T-X.md" > "$T/fmt/out" || { echo "TCM RUN FAIL"; exit 1; }
    head -1 "$T/fmt/out" | grep -q '^fix(core): format drill \[T-X\]$' || { echo "TCM SUBJECT FAIL"; exit 1; }
    grep -q '^because history should read\.$' "$T/fmt/out" || { echo "TCM WHY FAIL"; exit 1; }
    grep -q '^- box one$' "$T/fmt/out" || { echo "TCM CRIT FAIL (marker must strip)"; exit 1; }
    grep -q '^- kept note$' "$T/fmt/out" || { echo "TCM NOTE FAIL"; exit 1; }
    grep -q '⛔' "$T/fmt/out" && { echo "TCM FILTER FAIL (⛔ note must drop)"; exit 1; }
    grep -q '^Files: src/a.txt, src/b.txt$' "$T/fmt/out" || { echo "TCM FILES FAIL"; exit 1; }
    # T-038 commit-type map (clean-history v2.2): the two advertised types test/docs must be
    # REACHABLE (they were falling through to chore); spike/missing stay chore.
    for ctpair in test:test docs:docs spike:chore; do
      ctin="${ctpair%%:*}"; ctout="${ctpair##*:}"
      printf -- '---\nid: T-CT\ntitle: t\ntype: %s\nscope: core\nfiles_owned:\n  - src/a.txt\n---\n' "$ctin" > "$T/fmt/ct.md"
      "$SELF" task-commit-msg "$T/fmt/ct.md" | head -1 | grep -q "^$ctout(core): " || { echo "COMMIT TYPE MAP FAIL (type: $ctin must map to $ctout)"; exit 1; }
    done
    printf -- '---\nid: T-CT\ntitle: t\nscope: core\nfiles_owned:\n  - src/a.txt\n---\n' > "$T/fmt/ct.md"   # no type: → chore
    "$SELF" task-commit-msg "$T/fmt/ct.md" | head -1 | grep -q '^chore(core): ' || { echo "COMMIT TYPE MAP FAIL (missing type must map to chore)"; exit 1; }
}
drill_express() {
    if [ -n "$SELFTEST_ONLY" ] && ! git rev-parse -q --verify refs/tags/sprint/2 >/dev/null 2>&1; then
      # T-033: --only express runs on the bare spine (sprint/1 sealed; no sprint/2, no SPRINT 2).
      # Rebuild the sprint-2 context the pr-publish drill leaves in the full run so express stands
      # alone. Guarded on SELFTEST_ONLY — skipped entirely in the full run (tested path unchanged).
      sed -i.bak -e '/^test:/d' -e '/^lint:/d' -e '/^typecheck:/d' -e '/^build:/d' -e '/^uat:/d' ops/CONVENTIONS.md 2>/dev/null || true; rm -f ops/CONVENTIONS.md.bak
      printf '# SPRINT 2 — express standalone  capacity: 5\n' > ops/SPRINT.md
      git tag -f sprint/2 main >/dev/null
      git add -A; git commit -qm 'express standalone: sprint-2 context' >/dev/null 2>&1 || true
    fi
    # ========= T-031 express-lane + slow-suite drills (ops/contracts/express-lane.md ·
    # ops/contracts/verification-tiering.md) =========
    "$SELF" help | grep -q -- 'land --express' || { echo "USAGE FAIL: land --express missing from help"; exit 1; }
    # qa stamp: gated on ≥1 suite command — no suite keys → NO stamp; test: true → "<seconds> <epoch>"
    rm -f .polaris/last-suite-seconds
    "$SELF" qa >/dev/null 2>&1 || true          # rc is not under test here — only the stamp gate
    [ -f .polaris/last-suite-seconds ] && { echo "QA STAMP GATE FAIL (no suite command ran — no stamp)"; exit 1; }
    printf 'test: true\n' >> ops/CONVENTIONS.md
    "$SELF" qa >/dev/null 2>&1 || true
    grep -qE '^[0-9]+ [0-9]+$' .polaris/last-suite-seconds || { echo "QA STAMP FORMAT FAIL (want one \"<seconds> <epoch>\" line)"; exit 1; }
    git add -A; git commit -qm 'express drill: suite on'
    # a review task + its feat branch, shaped exactly as handoff leaves them (risk: high at birth
    # so the risk refusal drills on the real frontmatter key)
    printf -- '---\nid: T-EX\ntitle: express file\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: high\nowner: null\nbranch: feat/T-EX\nstatus: review\nfiles_owned:\n  - src/ex.txt\nverify:\n  - test -f src/ex.txt\n---\n## Why\nexpress drill.\n\n## Acceptance criteria\n- [ ] lands\n' > ops/board/review/T-EX.md
    git checkout -q -b feat/T-EX main
    echo ex > src/ex.txt; git add -A; git commit -qm ok
    git checkout -q main
    exd="$(date +%F)"
    expre="$(git rev-parse main)"
    # refusal: single-task rule — unknown ID, then a second review occupant, both by name
    "$SELF" land --express T-NOPE > "$T/ex1.out" 2>&1 && { echo "EXPRESS REVIEW FAIL (task not in review/ must refuse)"; exit 1; }
    grep -q 'express lands exactly one task' "$T/ex1.out" || { echo "EXPRESS REVIEW MSG FAIL"; exit 1; }
    printf -- '---\nid: T-EX2\npoints: 1\nwsjf: 1\nstatus: review\nfiles_owned:\n  - src/ex2.txt\n---\n' > ops/board/review/T-EX2.md
    "$SELF" land --express T-EX > "$T/ex2.out" 2>&1 && { echo "EXPRESS SOLO FAIL (a second review task must refuse)"; exit 1; }
    grep -q 'express lands exactly one task' "$T/ex2.out" || { echo "EXPRESS SOLO MSG FAIL"; exit 1; }
    rm -f ops/board/review/T-EX2.md
    # refusal: risk gate
    "$SELF" land --express T-EX > "$T/ex3.out" 2>&1 && { echo "EXPRESS RISK FAIL (risk: high must refuse)"; exit 1; }
    grep -q 'risk: high never rides the express lane' "$T/ex3.out" || { echo "EXPRESS RISK MSG FAIL"; exit 1; }
    set_fm risk normal ops/board/review/T-EX.md
    # refusal: express: off — and an unknown value warns, then fails the same safe way
    printf 'express: off\n' >> ops/CONVENTIONS.md
    "$SELF" land --express T-EX > "$T/ex4.out" 2>&1 && { echo "EXPRESS OFF FAIL"; exit 1; }
    grep -q 'express: off' "$T/ex4.out" || { echo "EXPRESS OFF MSG FAIL"; exit 1; }
    sed -i.bak '/^express:/d' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    printf 'express: bogus\n' >> ops/CONVENTIONS.md
    "$SELF" land --express T-EX > "$T/ex5.out" 2>&1 && { echo "EXPRESS UNKNOWN FAIL (bogus must behave as off)"; exit 1; }
    grep -q "express: 'bogus' unknown" "$T/ex5.out" || { echo "EXPRESS UNKNOWN WARN FAIL (unknown value must warn)"; exit 1; }
    grep -q 'express: off' "$T/ex5.out" || { echo "EXPRESS UNKNOWN MSG FAIL (unknown value must fail as off)"; exit 1; }
    sed -i.bak '/^express:/d' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    # refusal: publish: pr
    printf 'publish: pr\n' >> ops/CONVENTIONS.md
    "$SELF" land --express T-EX > "$T/ex6.out" 2>&1 && { echo "EXPRESS PR FAIL (publish: pr must refuse)"; exit 1; }
    grep -q 'express needs publish: direct' "$T/ex6.out" || { echo "EXPRESS PR MSG FAIL"; exit 1; }
    git checkout -q -- ops/CONVENTIONS.md       # restore publish: direct (default) for everything below
    # all four refusals died BEFORE any mutation — and BEFORE step 0, so no lease is left behind
    # (express-lane v2: refusals precede the integration lease; a doomed express never queues)
    [ "$(git rev-parse main)" = "$expre" ] || { echo "EXPRESS REFUSE MUTATE FAIL (base moved)"; exit 1; }
    git rev-parse -q --verify "refs/heads/integrate/$exd" >/dev/null && { echo "EXPRESS REFUSE MUTATE FAIL (integrate branch created)"; exit 1; }
    [ -f ops/board/review/T-EX.md ] || { echo "EXPRESS REFUSE MUTATE FAIL (task left review/)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "EXPRESS REFUSE DIRTY FAIL (a refusal must leave zero uncommitted state)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/.int-lease" ] && { echo "EXPRESS REFUSE LEASE FAIL (a refusal must not leave the integration lease behind)"; exit 1; }
    # red suite mid-express: land unwinds (integrate back at base), kickback carries the failing tail
    sed -i.bak 's|^test: true$|test: bash -c "echo EXPRESS-BOOM; exit 1"|' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    git add -A; git commit -qm 'express drill: suite red'
    "$SELF" land --express T-EX > "$T/ex7.out" 2>&1 && { echo "EXPRESS RED FAIL (red suite must die)"; exit 1; }
    grep -q 'EXPRESS-BOOM' "$T/ex7.out" || { echo "EXPRESS RED TAIL FAIL (output must carry the failing tail)"; exit 1; }
    [ -f ops/board/active/T-EX.md ] || { echo "EXPRESS RED KICKBACK FAIL (task must bounce to active/)"; exit 1; }
    grep -q 'EXPRESS-BOOM' ops/board/active/T-EX.md || { echo "EXPRESS RED NOTE FAIL (kickback note must carry the tail)"; exit 1; }
    [ "$(git rev-parse "refs/heads/integrate/$exd")" = "$(git rev-parse main)" ] || { echo "EXPRESS RED UNWIND FAIL (the land must reset away)"; exit 1; }
    # T-058 (express-lane v2): step 1 went through wave_on (first pass on a fresh day → create),
    # and the red death released the step-0 integration lease on its way out
    grep -q 'wave: created integrate/' "$T/ex7.out" || { echo "EXPRESS WAVE CREATE FAIL (step 1 must create the wave via wave_on)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/.int-lease" ] && { echo "EXPRESS RED LEASE FAIL (a red express must release the integration lease)"; exit 1; }
    git checkout -q main
    mv ops/board/active/T-EX.md ops/board/review/T-EX.md    # back to review + a green suite for the happy path
    set_fm status review ops/board/review/T-EX.md
    sed -i.bak 's|^test: .*$|test: true|' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    git add -A; git commit -qm 'express drill: suite green'
    # happy path: one pass → done/ with landed: stamp, sprint tag moved to the new seal,
    # integrate/<today> deleted (reused from the red run above), tree clean, qa named at the end
    extagpre="$(git rev-parse refs/tags/sprint/2)"
    "$SELF" land --express T-EX > "$T/ex8.out" 2>&1 || { cat "$T/ex8.out"; echo "EXPRESS HAPPY FAIL"; exit 1; }
    # T-038: land --express shares cmd_land's squash path — the same chatter must stay silenced here
    grep -qi 'Squash commit' "$T/ex8.out" && { echo "LAND NOISE FAIL (express: git 'Squash commit' line leaked)"; exit 1; }
    grep -qi 'stopped before committing' "$T/ex8.out" && { echo "LAND NOISE FAIL (express: git 'stopped before committing' line leaked)"; exit 1; }
    [ -f ops/board/done/T-EX.md ] || { echo "EXPRESS DONE FAIL (task must end in done/)"; exit 1; }
    [ "$(sed -n 's/^landed: //p' ops/board/done/T-EX.md | tr -d ' \r')" = "$(git log --format='%H %s' main | awk '/\[T-EX\]$/ {print $1; exit}')" ] \
      || { echo "EXPRESS STAMP FAIL (done must stamp the landed sha)"; exit 1; }
    [ "$(git rev-parse refs/tags/sprint/2)" != "$extagpre" ] || { echo "EXPRESS TAG FAIL (sprint tag must move to the express seal)"; exit 1; }
    [ "$(git rev-parse refs/tags/sprint/2)" = "$(git rev-parse main)" ] || { echo "EXPRESS TAG FAIL (tag must equal the new base HEAD)"; exit 1; }
    git rev-parse -q --verify "refs/heads/integrate/$exd" >/dev/null && { echo "EXPRESS BRANCH FAIL (integrate/<today> must be deleted)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "EXPRESS CLEAN FAIL (tree must end clean)"; exit 1; }
    grep -q 'polaris finish' "$T/ex8.out" || { echo "EXPRESS FINISH FAIL (final note must name polaris finish)"; exit 1; }
    # T-058 (express-lane v2): the happy pass reused the red run's wave branch via wave_on
    # (ff-reuse — it sat exactly at base), and freed the step-0 lease on the way out
    grep -q 'wave: reusing integrate/' "$T/ex8.out" || { echo "EXPRESS WAVE REUSE FAIL (step 1 must ff-reuse the open wave via wave_on)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/.int-lease" ] && { echo "EXPRESS LEASE RELEASE FAIL (a green express must release the integration lease)"; exit 1; }
}
drill_pr-publish() {
    # T-033 self-provision: --only pr-publish skips the remote and notify drills, but it pushes to
    # origin and its seal fires the notify: hook (ngwait polls the log). Provide both — no-ops in
    # the full run, where the remote/notify drills already set them up.
    ensure_origin
    grep -q '^notify:' ops/CONVENTIONS.md 2>/dev/null || printf 'notify: printf "%%s/%%s/%%s/%%s\\n" "$POLARIS_EV" "$POLARIS_SEVERITY" "$POLARIS_ID" "$POLARIS_NOTE" >> %s\n' "$T/notify.log" >> ops/CONVENTIONS.md
    # ================== T-022 pr-publish drill (ops/contracts/publish-modes.md) ==================
    # publish: pr against a scratch bare origin: handoff keeps feat/* local · seal pushes ONLY
    # integrate/<date> + prints title/bullets/URL fallback + fires notify done, moving NO ref on
    # base (local or remote) and no tag · a simulated host PR merge (--no-ff from a temp clone) ·
    # seal --sync: unmerged wave dies by name, merged wave pulls base, tags, deletes the branch
    # both sides · done green via the rule-1 gate · direct --sync dies · unknown publish: warns.
    "$SELF" help | grep -q -- 'seal --sync' || { echo "USAGE FAIL: seal --sync missing from help"; exit 1; }
    "$SELF" help | grep -q 'publish: pr' || { echo "USAGE FAIL: publish: key missing from help"; exit 1; }
    printf 'publish: pr\n' >> ops/CONVENTIONS.md
    git add -A; git commit -qm 'publish pr'
    git push -q origin main
    printf '# SPRINT 2 — pr sprint  capacity: 5\n' > ops/SPRINT.md
    # URL composition is a pure in-process function — drill it directly, like fm_list above
    [ "$(pr_create_url 'git@bitbucket.org:acme/arc.git' 2026-01-02 main)" = 'https://bitbucket.org/acme/arc/pull-requests/new?source=integrate/2026-01-02&dest=main' ] \
      || { echo "PR URL SSH FAIL"; exit 1; }
    [ "$(pr_create_url 'https://u@bitbucket.org/acme/arc.git' 2026-01-02 main)" = 'https://bitbucket.org/acme/arc/pull-requests/new?source=integrate/2026-01-02&dest=main' ] \
      || { echo "PR URL HTTPS FAIL"; exit 1; }
    [ -z "$(pr_create_url 'git@github.com:acme/arc.git' 2026-01-02 main)" ] || { echo "PR URL FOREIGN FAIL (non-bitbucket must yield nothing)"; exit 1; }
    printf -- '---\nid: T-P\ntitle: pr mode file\ntype: feature\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/p.txt\nverify: []\n---\n' > ops/board/ready/T-P.md
    "$SELF" claim T-P >/dev/null
    ( cd .polaris/wt/T-P && echo p > src/p.txt && git add -A && git commit -qm ok && "$SELF" handoff T-P >/dev/null )
    git ls-remote origin 'refs/heads/feat/*' | grep -q . && { echo "PR HANDOFF FAIL (feat branches must never leave the machine)"; exit 1; }
    git checkout -q -b integrate/2026-01-02
    "$SELF" land T-P >/dev/null || { echo "PR LAND FAIL"; exit 1; }
    basepre="$(git rev-parse main)"; rbasepre="$(git ls-remote origin refs/heads/main | cut -f1)"
    # unmerged wave → --sync dies naming the missing task, and tags nothing
    "$SELF" seal --sync 2026-01-02 > "$T/prsync0.out" 2>&1 && { echo "PR SYNC UNMERGED FAIL (must die before the PR merges)"; exit 1; }
    grep -q 'T-P' "$T/prsync0.out" || { echo "PR SYNC NAME FAIL (die must name the missing task)"; exit 1; }
    git rev-parse -q --verify refs/tags/sprint/2 >/dev/null && { echo "PR SYNC MUTATE FAIL (failed sync must not tag)"; exit 1; }
    : > "$T/notify.log"
    "$SELF" seal 2026-01-02 > "$T/prseal.out" || { cat "$T/prseal.out"; echo "PR SEAL FAIL"; exit 1; }
    git ls-remote --exit-code origin refs/heads/integrate/2026-01-02 >/dev/null || { echo "PR SEAL PUSH FAIL (integrate branch must reach origin)"; exit 1; }
    [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$rbasepre" ] || { echo "PR SEAL REMOTE BASE FAIL (origin base must not move)"; exit 1; }
    [ "$(git rev-parse main)" = "$basepre" ] || { echo "PR SEAL LOCAL FAIL (no local merge in pr mode)"; exit 1; }
    git rev-parse -q --verify refs/tags/sprint/2 >/dev/null && { echo "PR SEAL TAG FAIL (no tag before --sync)"; exit 1; }
    [ -f ops/board/review/T-P.md ] || { echo "PR SEAL BOARD FAIL (tasks stay in review/)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/T-P" ] || { echo "PR SEAL LOCK FAIL (locks stay until done)"; exit 1; }
    grep -q 'open a PR from integrate/2026-01-02 into main on your host' "$T/prseal.out" || { echo "PR SEAL URL FALLBACK FAIL"; exit 1; }
    grep -q 'Sprint 2 — pr sprint' "$T/prseal.out" || { echo "PR SEAL TITLE FAIL (suggested title missing)"; exit 1; }
    grep -q -- '- feat(src): pr mode file \[T-P\]' "$T/prseal.out" || { echo "PR SEAL BULLET FAIL (description bullets missing)"; exit 1; }
    ngwait '^run-done/done//run-done$' || { echo "PR SEAL NOTIFY FAIL (pr seal must fire notify-gate done)"; exit 1; }
    # the human merges the PR — simulated with a --no-ff merge pushed from a temp clone
    git clone -q "$T/origin.git" "$T/prhost" 2>/dev/null
    ( set -e; cd "$T/prhost"; git config user.email t@t; git config user.name t
      git checkout -q main 2>/dev/null || git checkout -q -b main origin/main
      git merge -q --no-ff origin/integrate/2026-01-02 -m 'Merged in integrate/2026-01-02 (pull request #1)'
      git push -q origin main ) || { echo "PR MERGE SIM FAIL"; exit 1; }
    "$SELF" seal --sync 2026-01-02 > "$T/prsync.out" || { cat "$T/prsync.out"; echo "PR SYNC FAIL"; exit 1; }
    [ "$(git rev-parse main)" = "$(git ls-remote origin refs/heads/main | cut -f1)" ] || { echo "PR SYNC PULL FAIL (base must fast-forward to the PR merge)"; exit 1; }
    git rev-parse -q --verify refs/tags/sprint/2 >/dev/null || { echo "PR SYNC TAG FAIL"; exit 1; }
    [ "$(git ls-remote origin refs/tags/sprint/2 | cut -f1)" = "$(git rev-parse refs/tags/sprint/2)" ] || { echo "PR SYNC TAG PUSH FAIL (tag must land on origin)"; exit 1; }
    git rev-parse -q --verify refs/heads/integrate/2026-01-02 >/dev/null 2>&1 && { echo "PR SYNC BRANCH FAIL (local integrate branch must go)"; exit 1; }
    git ls-remote --exit-code origin refs/heads/integrate/2026-01-02 >/dev/null 2>&1 && { echo "PR SYNC REMOTE BRANCH FAIL (origin integrate branch must go)"; exit 1; }
    "$SELF" done T-P >/dev/null || { echo "PR DONE FAIL (rule-1 gate must pass after --sync)"; exit 1; }
    # direct mode: --sync has nothing to do · unknown publish: warns once + behaves direct
    sed -i.bak '/^publish:/d' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    "$SELF" seal --sync 2026-01-02 > "$T/prd.out" 2>&1 && { echo "SYNC DIRECT FAIL (direct mode --sync must die)"; exit 1; }
    grep -q 'nothing to sync' "$T/prd.out" || { echo "SYNC DIRECT MSG FAIL"; exit 1; }
    printf 'publish: bogus\n' >> ops/CONVENTIONS.md
    "$SELF" seal --sync 2026-01-02 > "$T/prb.out" 2>&1 && { echo "PUBLISH UNKNOWN FAIL (bogus must behave direct)"; exit 1; }
    grep -q "publish: 'bogus' unknown" "$T/prb.out" || { echo "PUBLISH WARN FAIL (unknown value must warn)"; exit 1; }
    grep -q 'nothing to sync' "$T/prb.out" || { echo "PUBLISH FALLBACK FAIL (unknown value must behave direct)"; exit 1; }
    sed -i.bak '/^publish:/d' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    git add -A; git commit -qm 'publish drill cleanup'
}
drill_busyint() {
    # ---- T-062 busyint drill (ops/contracts/shared-checkout.md § Executable check) ----
    # ONE shared integration lane, serialized by the lease. Proves: a held lease → the ~30s wait
    # note, then rc 3 with the `queued: ` line · a STALE lease is stolen with a note and the land
    # proceeds · a re-land of a landed ID skips rc 0 · an open non-ff integrate/<date> is ADOPTED
    # and the wave seals ONCE. The lease is exercised through the CLI (`land`/`seal`) only — int_on
    # is never captured in $( ): its EXIT trap self-releases inside a subshell (T-058 trap).
    if [ -f ops/CONVENTIONS.md ]; then cp ops/CONVENTIONS.md "$T/bi-conv.bak"; else rm -f "$T/bi-conv.bak"; fi
    [ -f ops/SPRINT.md ] && cp ops/SPRINT.md "$T/bi-sprint.bak" || rm -f "$T/bi-sprint.bak"
    printf 'integration_wait_minutes: 1\n' >> ops/CONVENTIONS.md   # bounded wait: 60s, not the 10m default
    git add -A; git commit -qm 'busyint drill: wait knob'          # committed: land parks DIRTY trees
    printf '# SPRINT 9 — busyint drill  capacity: 5\n' > ops/SPRINT.md   # moved set: disk-only, ignored on base
    # review task + feat branch by hand (hint-drill shape): no claim, so no lock and no worktree —
    # the lease is the object under test, not the builder lifecycle.
    printf -- '---\nid: T-BI1\ntitle: busy one\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nowner: null\nbranch: feat/T-BI1\nstatus: review\nfiles_owned:\n  - src/bi1.txt\nverify: []\n---\n' > ops/board/review/T-BI1.md
    git checkout -q -b feat/T-BI1 main
    echo bi1 > src/bi1.txt; git add -A; git commit -qm ok
    git checkout -q main
    bi_lk="$(git rev-parse --git-common-dir)/polaris-locks/.int-lease"
    bi_d="$(date +%F)"
    # (a) held lease (fresh epoch, pid 1 — never this process): wait notes, then rc 3 + queued:
    mkdir -p "$bi_lk"; date +%s > "$bi_lk/epoch"; echo other@host > "$bi_lk/who"; echo 1 > "$bi_lk/pid"
    bi_rc=0
    "$SELF" land T-BI1 > "$T/bi1.out" 2>&1 || bi_rc=$?
    [ "$bi_rc" -eq 3 ] || { cat "$T/bi1.out"; echo "BUSYINT QUEUE RC FAIL (a busy lane past the bounded wait must rc 3)"; exit 1; }
    grep -q '^   integration lane busy' "$T/bi1.out" || { cat "$T/bi1.out"; echo "BUSYINT WAIT NOTE FAIL (the ~30s progress note must fire while waiting)"; exit 1; }
    grep -q '^queued: ' "$T/bi1.out" || { echo "BUSYINT QUEUED LINE FAIL (the final line must begin queued:)"; exit 1; }
    git rev-parse -q --verify "refs/heads/integrate/$bi_d" >/dev/null && { echo "BUSYINT QUEUE MUTATE FAIL (a queued land must mutate nothing)"; exit 1; }
    [ -f ops/board/review/T-BI1.md ] || { echo "BUSYINT QUEUE BOARD FAIL (a queued land must move nothing)"; exit 1; }
    # (b) stale lease: epoch aged past integration_stale_minutes (default 45) → stolen with a note,
    # the land proceeds, and the lane is FREED on the way out
    echo $(( $(date +%s) - 3600 )) > "$bi_lk/epoch"
    "$SELF" land T-BI1 > "$T/bi2.out" 2>&1 || { cat "$T/bi2.out"; echo "BUSYINT STEAL RC FAIL (a stale lease must be stolen, not queued)"; exit 1; }
    grep -q 'stealing stale integration lease' "$T/bi2.out" || { echo "BUSYINT STEAL NOTE FAIL (the steal must be named)"; exit 1; }
    git log -1 --format=%s | grep -q '\[T-BI1\]$' || { echo "BUSYINT STEAL LAND FAIL (the land must proceed after the steal)"; exit 1; }
    [ -d "$bi_lk" ] && { echo "BUSYINT LEASE RELEASE FAIL (the lane must be freed after the land)"; exit 1; }
    # (c) re-land of a landed ID: idempotent skip, rc 0, board untouched
    "$SELF" land T-BI1 > "$T/bi3.out" 2>&1 || { cat "$T/bi3.out"; echo "BUSYINT RELAND RC FAIL (an already-landed ID must skip rc 0)"; exit 1; }
    grep -q 'already landed — skipped' "$T/bi3.out" || { echo "BUSYINT RELAND MSG FAIL"; exit 1; }
    [ -f ops/board/review/T-BI1.md ] || { echo "BUSYINT RELAND BOARD FAIL (the skip must move nothing)"; exit 1; }
    # (d) adoption: a second land starts on $BASE, meets the open non-ff wave, ADOPTS it and lands
    # on top; ONE seal then closes both lands (wave_on's third outcome — the by-hand die is dead).
    printf -- '---\nid: T-BI2\ntitle: busy two\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nowner: null\nbranch: feat/T-BI2\nstatus: review\nfiles_owned:\n  - src/bi2.txt\nverify: []\n---\n' > ops/board/review/T-BI2.md
    git checkout -q -b feat/T-BI2 main
    echo bi2 > src/bi2.txt; git add -A; git commit -qm ok
    git checkout -q main
    "$SELF" land T-BI2 > "$T/bi4.out" 2>&1 || { cat "$T/bi4.out"; echo "BUSYINT ADOPT LAND FAIL"; exit 1; }
    grep -q 'wave: adopting' "$T/bi4.out" || { echo "BUSYINT ADOPT FAIL (an open non-ff wave must be ADOPTED, never a die)"; exit 1; }
    "$SELF" seal "$bi_d" > "$T/bi5.out" 2>&1 || { cat "$T/bi5.out"; echo "BUSYINT SEAL FAIL (the adopted wave must seal once)"; exit 1; }
    git log -1 --format=%b main | grep -q '\[T-BI1\]$' || { echo "BUSYINT SEAL BULLET FAIL (the first land missing from the one seal)"; exit 1; }
    git log -1 --format=%b main | grep -q '\[T-BI2\]$' || { echo "BUSYINT SEAL BULLET FAIL (the adopted-wave land missing from the one seal)"; exit 1; }
    "$SELF" done T-BI1 >/dev/null || { echo "BUSYINT DONE FAIL (T-BI1)"; exit 1; }
    "$SELF" done T-BI2 >/dev/null || { echo "BUSYINT DONE FAIL (T-BI2)"; exit 1; }
    # hermetic: CONVENTIONS + SPRINT back byte-exactly; the sealed wave stays, like the spine's own
    if [ -f "$T/bi-conv.bak" ]; then cp "$T/bi-conv.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    [ -f "$T/bi-sprint.bak" ] && cp "$T/bi-sprint.bak" ops/SPRINT.md || rm -f ops/SPRINT.md
    rm -f "$T/bi-conv.bak" "$T/bi-sprint.bak"
    git add -A; git commit -qm 'busyint drill cleanup' >/dev/null 2>&1 || true
}
drill_selfland() {
    # ---- T-089 selfland drill (ops/contracts/shared-checkout.md v2 §5) ----
    # `landing:` unset composes to self — DEFAULT IN CODE, because `update` never rewrites an
    # installed CONVENTIONS.md (the 6.0.0 lesson) — so a handoff CONTINUES into land, and the last
    # lane out seals + finishes the wave. Hard stop no knob softens: risk: high never self-lands.
    # landing: integrator restores the classic notice byte-for-byte.
    # FIXTURES DECLARE risk: EXPLICITLY — self_land fails CLOSED and refuses SILENTLY on a task
    # carrying no risk: frontmatter at all (T-088's recorded decision: unclassified cannot prove it
    # is not stop-and-ask material), so a risk-less fixture here would go green while testing
    # NOTHING. The happy path asserts the landing POSITIVELY (done/, stamp, main, lease) — nothing
    # here passes on the strength of "nothing errored".
    if [ -f ops/CONVENTIONS.md ]; then cp ops/CONVENTIONS.md "$T/sl-conv.bak"; else rm -f "$T/sl-conv.bak"; fi
    [ -f ops/SPRINT.md ] && cp ops/SPRINT.md "$T/sl-sprint.bak" || rm -f "$T/sl-sprint.bak"
    printf '# SPRINT 12 — selfland drill  capacity: 5\n' > ops/SPRINT.md   # moved set: disk-only, ignored on base
    sl_gcd="$(git rev-parse --git-common-dir)"
    # (a) unset knob + risk: normal → the handoff itself lands, seals (last lane out) and finishes:
    #     task in done/ with the landed: stamp, squash on the base branch, lease + lock released.
    printf -- '---\nid: T-SL1\ntitle: self land one\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/sl1.txt\nverify: []\n---\n' > ops/board/ready/T-SL1.md
    "$SELF" claim T-SL1 >/dev/null
    ( cd .polaris/wt/T-SL1 && echo sl1 > src/sl1.txt && git add -A && git commit -qm ok && "$SELF" handoff T-SL1 > "$T/sl1.out" 2>&1 ) || { cat "$T/sl1.out"; echo "SELFLAND HANDOFF RC FAIL"; exit 1; }
    grep -q 'landing: self — continuing into land T-SL1' "$T/sl1.out" || { cat "$T/sl1.out"; echo "SELFLAND NOTE FAIL (the handoff must announce the self-land)"; exit 1; }
    [ -f ops/board/done/T-SL1.md ] || { cat "$T/sl1.out"; echo "SELFLAND DONE FAIL (the task must reach done/ — landed for real, not merely un-errored)"; exit 1; }
    grep -q '^landed: ' ops/board/done/T-SL1.md || { echo "SELFLAND STAMP FAIL (done must stamp the squash SHA)"; exit 1; }
    git log --format=%s main | grep -q '\[T-SL1\]$' || { echo "SELFLAND MAIN FAIL (the squash must be on the base branch)"; exit 1; }
    git rev-parse -q --verify refs/tags/sprint/12 >/dev/null || { echo "SELFLAND SEAL FAIL (the last lane out must seal the wave)"; exit 1; }
    [ -d "$sl_gcd/polaris-locks/.int-lease" ] && { echo "SELFLAND LEASE FAIL (the lease must release after the landing tail)"; exit 1; }
    [ -d "$sl_gcd/polaris-locks/T-SL1" ] && { echo "SELFLAND LOCK FAIL (done must drop the claim lock)"; exit 1; }
    # T-104 (ops/contracts/worktree-liveness.md — own-worktree `done` is designed OUT, not handled):
    # the handoff BEAT its own worktree on the way in, so the `done` at the end of its own tail sees
    # clean + LIVE and LEAVES the directory the session is standing in, branch kept. Nothing in this
    # protocol removes a worktree it cannot prove dead — the cleanup is the NEXT idle sweep, so
    # backdate the beat (the contract's fake-idle form) and prove --fix actually finishes the job.
    grep -q 'worktree LEFT' "$T/sl1.out" || { cat "$T/sl1.out"; echo "SELFLAND WT LEFT FAIL (the landing tail must LEAVE the handoff's own worktree)"; exit 1; }
    [ -d .polaris/wt/T-SL1 ] || { echo "SELFLAND WT GONE FAIL (a self-landing session must never lose the worktree it is standing in)"; exit 1; }
    [ -n "$(git branch --list feat/T-SL1)" ] || { echo "SELFLAND WT BRANCH FAIL (a LEFT worktree keeps feat/T-SL1)"; exit 1; }
    echo 1 2>/dev/null > "$sl_gcd/worktrees/T-SL1/polaris-beat" || true
    "$SELF" sweep --fix > "$T/sl1sw.out" 2>&1 || true
    [ -d .polaris/wt/T-SL1 ] && { cat "$T/sl1sw.out"; echo "SELFLAND SWEEP FAIL (once the beat goes quiet, sweep --fix removes the worktree)"; exit 1; }
    [ -z "$(git branch --list feat/T-SL1)" ] || { cat "$T/sl1sw.out"; echo "SELFLAND SWEEP BRANCH FAIL (a removed worktree on a done task takes feat/T-SL1 with it)"; exit 1; }
    rm -f "$T/sl1sw.out"
    # (b) risk: high → the pinned refusal, the task STAYS in review/, and NOTHING lands
    printf -- '---\nid: T-SL2\ntitle: self land high\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: high\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/sl2.txt\nverify: []\n---\n' > ops/board/ready/T-SL2.md
    "$SELF" claim T-SL2 >/dev/null
    ( cd .polaris/wt/T-SL2 && echo sl2 > src/sl2.txt && git add -A && git commit -qm ok && "$SELF" handoff T-SL2 > "$T/sl2.out" 2>&1 ) || { cat "$T/sl2.out"; echo "SELFLAND HIGH RC FAIL (a refused self-land is still a clean handoff)"; exit 1; }
    grep -q 'risk: high never self-lands — a human must approve the merge; task stays in review/' "$T/sl2.out" || { cat "$T/sl2.out"; echo "SELFLAND HIGH MSG FAIL (the pinned refusal must print ON ONE LINE)"; exit 1; }
    [ -f ops/board/review/T-SL2.md ] || { echo "SELFLAND HIGH BOARD FAIL (the task must stay in review/)"; exit 1; }
    git log --format=%s main | grep -q '\[T-SL2\]$' && { echo "SELFLAND HIGH LAND FAIL (a refused self-land must land NOTHING)"; exit 1; }
    # (c) landing: integrator → byte-for-byte the classic handoff: the integrate notice, no
    #     self-land note, no land. The knob edit is COMMITTED (land parks dirty trees) and undone
    #     in teardown the same way.
    printf 'landing: integrator\n' >> ops/CONVENTIONS.md
    git add -A; git commit -qm 'selfland drill: integrator knob'
    printf -- '---\nid: T-SL3\ntitle: self land classic\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/sl3.txt\nverify: []\n---\n' > ops/board/ready/T-SL3.md
    "$SELF" claim T-SL3 >/dev/null
    ( cd .polaris/wt/T-SL3 && echo sl3 > src/sl3.txt && git add -A && git commit -qm ok && "$SELF" handoff T-SL3 > "$T/sl3.out" 2>&1 ) || { cat "$T/sl3.out"; echo "SELFLAND INTEG RC FAIL"; exit 1; }
    grep -q 'Integrate now' "$T/sl3.out" || { cat "$T/sl3.out"; echo "SELFLAND INTEG NOTICE FAIL (landing: integrator must print the classic notice)"; exit 1; }
    grep -q 'landing: self' "$T/sl3.out" && { cat "$T/sl3.out"; echo "SELFLAND INTEG QUIET FAIL (no self-land note under landing: integrator)"; exit 1; }
    [ -f ops/board/review/T-SL3.md ] || { echo "SELFLAND INTEG BOARD FAIL (the task must stay in review/)"; exit 1; }
    git log --format=%s main | grep -q '\[T-SL3\]$' && { echo "SELFLAND INTEG LAND FAIL (a classic handoff must not land)"; exit 1; }
    # teardown: drain the two review fixtures through the CLASSIC lane — the exact path both
    # refusals point at (in a drill, this process stands in for the human's yes on T-SL2) — then
    # CONVENTIONS + SPRINT back byte-exactly; the sealed wave stays, like the spine's own.
    "$SELF" land T-SL2 >/dev/null 2>&1 || { echo "SELFLAND DRAIN LAND FAIL (T-SL2)"; exit 1; }
    "$SELF" land T-SL3 >/dev/null 2>&1 || { echo "SELFLAND DRAIN LAND FAIL (T-SL3)"; exit 1; }
    "$SELF" seal >/dev/null 2>&1 || { echo "SELFLAND DRAIN SEAL FAIL"; exit 1; }
    "$SELF" done T-SL2 >/dev/null || { echo "SELFLAND DRAIN DONE FAIL (T-SL2)"; exit 1; }
    "$SELF" done T-SL3 >/dev/null || { echo "SELFLAND DRAIN DONE FAIL (T-SL3)"; exit 1; }
    if [ -f "$T/sl-conv.bak" ]; then cp "$T/sl-conv.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    [ -f "$T/sl-sprint.bak" ] && cp "$T/sl-sprint.bak" ops/SPRINT.md || rm -f ops/SPRINT.md
    rm -f "$T/sl-conv.bak" "$T/sl-sprint.bak"
    git add -A; git commit -qm 'selfland drill cleanup' >/dev/null 2>&1 || true
}
drill_wtreap() {
    # ---- T-104 worktree-liveness drill (ops/contracts/worktree-liveness.md § executable check) ----
    # A sibling's seal fan-out once ran `done ARC-428`, which `git worktree remove --force`d a
    # worktree another session was still typing in; everything uncommitted died. The repair is a
    # DECISION TABLE — caller × dirty × live — behind ONE removal primitive, and a table is only real
    # if every row is a test. So this drill walks all of them against the shipped CLI: `done`,
    # `release` from outside its lane, `resume`, and `sweep --fix`.
    # Liveness is the BEAT and nothing else, which is what makes the table drillable: `echo 1 > <beat>`
    # is a session that walked away, a fresh beat is one still typing, and no sleeping is involved.
    # `export CLAUDE_CODE_SESSION_ID=drill-sid` gives the claiming session an identity so the resume
    # gate has two distinct sessions to tell apart — the ONE thing the beat alone cannot decide.
    # The fixture declares `risk:` EXPLICITLY (T-089) and pins `landing: integrator`, because a
    # self-landing handoff would land these tasks before the drill has looked at their worktrees.
    wr_gcd="$(git rev-parse --git-common-dir)"
    wr_top="$(git rev-parse --show-toplevel)"
    mkdir -p "$T/wr"
    if [ -f ops/CONVENTIONS.md ]; then cp ops/CONVENTIONS.md "$T/wr/conv.bak"; else rm -f "$T/wr/conv.bak"; fi
    [ -f ops/SPRINT.md ] && cp ops/SPRINT.md "$T/wr/sprint.bak" || rm -f "$T/wr/sprint.bak"
    printf '# SPRINT 14 — wtreap drill  capacity: 5\n' > ops/SPRINT.md   # moved set: disk-only, ignored on base
    printf 'landing: integrator\n' >> ops/CONVENTIONS.md
    git add -A; git commit -qm 'wtreap drill: integrator knob'
    wr_sid="${CLAUDE_CODE_SESSION_ID:-}"
    export CLAUDE_CODE_SESSION_ID=drill-sid
    # two lanes through the classic path: T-WR1 will be dirty and idle at `done` (archive), T-WR2
    # clean and live (LEFT). One land per task, one seal for the wave — the spine's own recipe.
    printf -- '---\nid: T-WR1\ntitle: reap a dead lane\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/wr1.txt\nverify: []\n---\n' > ops/board/ready/T-WR1.md
    printf -- '---\nid: T-WR2\ntitle: leave a live lane\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/wr2.txt\nverify: []\n---\n' > ops/board/ready/T-WR2.md
    "$SELF" claim T-WR1 >/dev/null
    ( cd .polaris/wt/T-WR1 && echo wr1 > src/wr1.txt && git add -A && git commit -qm ok && "$SELF" handoff T-WR1 >/dev/null ) \
      || { echo "WTREAP HANDOFF FAIL (T-WR1)"; exit 1; }
    "$SELF" claim T-WR2 >/dev/null
    ( cd .polaris/wt/T-WR2 && echo wr2 > src/wr2.txt && git add -A && git commit -qm ok && "$SELF" handoff T-WR2 >/dev/null ) \
      || { echo "WTREAP HANDOFF FAIL (T-WR2)"; exit 1; }
    "$SELF" land T-WR1 > "$T/wr/land1.out" 2>&1 || { cat "$T/wr/land1.out"; echo "WTREAP LAND FAIL (T-WR1)"; exit 1; }
    "$SELF" land T-WR2 > "$T/wr/land2.out" 2>&1 || { cat "$T/wr/land2.out"; echo "WTREAP LAND FAIL (T-WR2)"; exit 1; }
    "$SELF" seal > "$T/wr/seal.out" 2>&1 || { cat "$T/wr/seal.out"; echo "WTREAP SEAL FAIL"; exit 1; }
    # (1) done · dirty + idle ⇒ ARCHIVED, rc 0, the uncommitted bytes intact, feat/T-WR1 deleted.
    #     Untracked counts as dirty by the contract, which is the case that matters: the file that
    #     died in ARC-428 was never added.
    printf 'uncommitted\n' > .polaris/wt/T-WR1/dirt.txt
    echo 1 2>/dev/null > "$wr_gcd/worktrees/T-WR1/polaris-beat" || true
    wr_rc=0; "$SELF" done T-WR1 > "$T/wr/1.out" 2>&1 || wr_rc=$?
    [ "$wr_rc" -eq 0 ] || { cat "$T/wr/1.out"; echo "WTREAP DONE ARCHIVE RC FAIL (an archived worktree is a SUCCESSFUL done, got rc $wr_rc)"; exit 1; }
    grep -q 'worktree archived → .polaris/wt-archive/T-WR1-' "$T/wr/1.out" || { cat "$T/wr/1.out"; echo "WTREAP DONE ARCHIVE LINE FAIL"; exit 1; }
    [ -d .polaris/wt/T-WR1 ] && { echo "WTREAP DONE ARCHIVE MOVE FAIL (the worktree must leave .polaris/wt/)"; exit 1; }
    wr_arc=''; for wr_d in .polaris/wt-archive/T-WR1-*/; do [ -d "$wr_d" ] && wr_arc="$wr_d"; done
    [ -n "$wr_arc" ] || { echo "WTREAP DONE ARCHIVE DIR FAIL (.polaris/wt-archive/T-WR1-<epoch>/ must exist)"; exit 1; }
    [ "$(cat "$wr_arc/dirt.txt" 2>/dev/null)" = uncommitted ] || { echo "WTREAP DONE ARCHIVE BYTES FAIL (the uncommitted file must survive, byte for byte)"; exit 1; }
    [ -e "$wr_arc/.git" ] && { echo "WTREAP DONE ARCHIVE POINTER FAIL (the .git pointer goes — git forgets it, the bytes stay)"; exit 1; }
    [ -z "$(git branch --list feat/T-WR1)" ] || { echo "WTREAP DONE ARCHIVE BRANCH FAIL (done drops the branch after rc 0 or 2)"; exit 1; }
    # (2) done · clean + LIVE ⇒ LEFT, rc 0, branch KEPT with the pinned note. Nothing removes the
    #     directory a session may be standing in, whatever the board says about the task.
    wr_rc=0; "$SELF" done T-WR2 > "$T/wr/2.out" 2>&1 || wr_rc=$?
    [ "$wr_rc" -eq 0 ] || { cat "$T/wr/2.out"; echo "WTREAP DONE LEFT RC FAIL (a LEFT worktree is not a failed done, got rc $wr_rc)"; exit 1; }
    grep -q 'worktree LEFT: .polaris/wt/T-WR2 is live' "$T/wr/2.out" || { cat "$T/wr/2.out"; echo "WTREAP DONE LEFT LINE FAIL"; exit 1; }
    grep -q 'branch feat/T-WR2 kept — checked out in a live worktree; sweep --fix finishes the cleanup once idle' "$T/wr/2.out" \
      || { cat "$T/wr/2.out"; echo "WTREAP DONE LEFT NOTE FAIL (the pinned kept-branch note must print)"; exit 1; }
    [ -d .polaris/wt/T-WR2 ] || { echo "WTREAP DONE LEFT DIR FAIL (a live worktree must still be there)"; exit 1; }
    [ -n "$(git branch --list feat/T-WR2)" ] || { echo "WTREAP DONE LEFT BRANCH FAIL (a LEFT worktree keeps its branch)"; exit 1; }
    # (3) release from OUTSIDE the lane · dirty + LIVE ⇒ DIES before any board write, naming the beat
    #     file so takeover stays explicit; rm the beat ⇒ the same command archives and moves the task.
    printf -- '---\nid: T-WR3\ntitle: refuse a live lane\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/wr3.txt\nverify: []\n---\n' > ops/board/ready/T-WR3.md
    "$SELF" claim T-WR3 >/dev/null
    printf 'uncommitted\n' > .polaris/wt/T-WR3/dirt.txt
    wr_rc=0; "$SELF" release T-WR3 --to ready -m drill > "$T/wr/3.out" 2>&1 || wr_rc=$?
    [ "$wr_rc" -ne 0 ] || { cat "$T/wr/3.out"; echo "WTREAP RELEASE REFUSE RC FAIL (a live dirty worktree must die, rc != 0)"; exit 1; }
    grep -q 'release refused: .polaris/wt/T-WR3 is live' "$T/wr/3.out" || { cat "$T/wr/3.out"; echo "WTREAP RELEASE REFUSE LINE FAIL"; exit 1; }
    grep -q 'worktrees/T-WR3/polaris-beat' "$T/wr/3.out" || { cat "$T/wr/3.out"; echo "WTREAP RELEASE BEAT PATH FAIL (the die must name the beat file — takeover is explicit)"; exit 1; }
    [ -f ops/board/active/T-WR3.md ] || { echo "WTREAP RELEASE BOARD FAIL (the refusal comes BEFORE any board write)"; exit 1; }
    [ -d .polaris/wt/T-WR3 ] || { echo "WTREAP RELEASE WT FAIL (a refused release touches nothing)"; exit 1; }
    rm -f "$wr_gcd/worktrees/T-WR3/polaris-beat"
    wr_rc=0; "$SELF" release T-WR3 --to ready -m drill > "$T/wr/3b.out" 2>&1 || wr_rc=$?
    [ "$wr_rc" -eq 0 ] || { cat "$T/wr/3b.out"; echo "WTREAP RELEASE RC FAIL (with the beat gone the release goes through, got rc $wr_rc)"; exit 1; }
    grep -q 'worktree archived → .polaris/wt-archive/T-WR3-' "$T/wr/3b.out" || { cat "$T/wr/3b.out"; echo "WTREAP RELEASE ARCHIVE FAIL (a dirty worktree is archived, never deleted)"; exit 1; }
    [ -f ops/board/ready/T-WR3.md ] || { echo "WTREAP RELEASE MOVE FAIL (the task must land back in ready/)"; exit 1; }
    [ -d .polaris/wt/T-WR3 ] && { echo "WTREAP RELEASE MOVE WT FAIL (the archived worktree must leave .polaris/wt/)"; exit 1; }
    # (4) resume · the lock's line 4 is the ONLY thing that distinguishes two live sessions. A foreign
    #     sid is refused; the SAME sid (a compacted session re-entering its own task) is admitted.
    printf -- '---\nid: T-WR4\ntitle: guard a live lane\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/wr4.txt\nverify: []\n---\n' > ops/board/ready/T-WR4.md
    "$SELF" claim T-WR4 >/dev/null
    [ "$(sed -n 4p "$wr_gcd/polaris-locks/T-WR4/meta" 2>/dev/null | tr -d ' \r')" = drill-sid ] \
      || { echo "WTREAP LOCK SID FAIL (lock_take must record the claiming session id on meta line 4)"; exit 1; }
    wr_rc=0; CLAUDE_CODE_SESSION_ID=other-sid "$SELF" resume T-WR4 > "$T/wr/4.out" 2>&1 || wr_rc=$?
    [ "$wr_rc" -ne 0 ] || { cat "$T/wr/4.out"; echo "WTREAP RESUME FOREIGN RC FAIL (a live lane held by another session must refuse)"; exit 1; }
    grep -q 'resume refused: .polaris/wt/T-WR4 is live' "$T/wr/4.out" || { cat "$T/wr/4.out"; echo "WTREAP RESUME FOREIGN LINE FAIL"; exit 1; }
    grep -q 'worktrees/T-WR4/polaris-beat' "$T/wr/4.out" || { cat "$T/wr/4.out"; echo "WTREAP RESUME BEAT PATH FAIL"; exit 1; }
    [ "$(sed -n 4p "$wr_gcd/polaris-locks/T-WR4/meta" 2>/dev/null | tr -d ' \r')" = drill-sid ] \
      || { echo "WTREAP RESUME FOREIGN LOCK FAIL (a refused resume must not adopt the lock)"; exit 1; }
    wr_rc=0; "$SELF" resume T-WR4 > "$T/wr/4b.out" 2>&1 || wr_rc=$?
    [ "$wr_rc" -eq 0 ] || { cat "$T/wr/4b.out"; echo "WTREAP RESUME SAME-SID RC FAIL (a session re-entering its OWN live task is allowed, got rc $wr_rc)"; exit 1; }
    grep -q 'resumed T-WR4' "$T/wr/4b.out" || { cat "$T/wr/4b.out"; echo "WTREAP RESUME SAME-SID LINE FAIL"; exit 1; }
    # (5) sweep · reports LIVE and leaves it; backdated + clean ⇒ --fix removes; backdated + dirty ⇒
    #     --fix archives. T-WR2's LEFT worktree from (2) is the dirty half — the exact leftover the
    #     kept-branch note promised sweep would finish.
    "$SELF" sweep > "$T/wr/5.out" 2>&1 || true
    grep -q 'LIVE worktree: .polaris/wt/T-WR4 (beat .*s ago) — left alone' "$T/wr/5.out" \
      || { cat "$T/wr/5.out"; echo "WTREAP SWEEP LIVE FAIL (a live worktree is reported and left alone)"; exit 1; }
    echo 1 2>/dev/null > "$wr_gcd/worktrees/T-WR4/polaris-beat" || true
    printf 'uncommitted\n' > .polaris/wt/T-WR2/dirt.txt
    echo 1 2>/dev/null > "$wr_gcd/worktrees/T-WR2/polaris-beat" || true
    "$SELF" sweep > "$T/wr/6.out" 2>&1 || true
    grep -q 'IDLE worktree: .polaris/wt/T-WR4 (task active, beat .*m ago, clean) — sweep --fix removes it' "$T/wr/6.out" \
      || { cat "$T/wr/6.out"; echo "WTREAP SWEEP IDLE CLEAN FAIL"; exit 1; }
    grep -q 'IDLE worktree: .polaris/wt/T-WR2 (task done, beat .*m ago, dirty) — sweep --fix archives it' "$T/wr/6.out" \
      || { cat "$T/wr/6.out"; echo "WTREAP SWEEP IDLE DIRTY FAIL"; exit 1; }
    [ -d .polaris/wt/T-WR4 ] || { echo "WTREAP SWEEP REPORT-ONLY FAIL (a bare sweep removes nothing)"; exit 1; }
    "$SELF" sweep --fix > "$T/wr/7.out" 2>&1 || true
    [ -d .polaris/wt/T-WR4 ] && { cat "$T/wr/7.out"; echo "WTREAP SWEEP FIX CLEAN FAIL (an idle clean worktree must go)"; exit 1; }
    [ -d .polaris/wt/T-WR2 ] && { cat "$T/wr/7.out"; echo "WTREAP SWEEP FIX DIRTY FAIL (an idle dirty worktree must leave .polaris/wt/)"; exit 1; }
    wr_arc=''; for wr_d in .polaris/wt-archive/T-WR2-*/; do [ -d "$wr_d" ] && wr_arc="$wr_d"; done
    [ -n "$wr_arc" ] || { echo "WTREAP SWEEP FIX ARCHIVE FAIL (the dirty one is archived, never removed)"; exit 1; }
    [ "$(cat "$wr_arc/dirt.txt" 2>/dev/null)" = uncommitted ] || { echo "WTREAP SWEEP FIX BYTES FAIL"; exit 1; }
    [ -n "$(git branch --list feat/T-WR2)" ] || { echo "WTREAP SWEEP FIX ARCHIVE BRANCH FAIL (an ARCHIVED worktree keeps its branch — those commits are still recoverable)"; exit 1; }
    [ -n "$(git branch --list feat/T-WR4)" ] || { echo "WTREAP SWEEP FIX ACTIVE BRANCH FAIL (an active task's branch survives its worktree)"; exit 1; }
    # (6) the v1.1 correction, which is a SILENCE and can only be tested as one: the beat writers put
    #     2>/dev/null BEFORE the > (bash applies redirections left to right), so a hook payload whose
    #     .polaris/wt/<ID> has no $GCD/worktrees/<ID>/ behind it writes nothing and SAYS nothing. The
    #     v1 order made every Bash call from such a cwd print "No such file or directory".
    wr_rc=0
    printf '{"cwd":"%s/.polaris/wt/T-NOPE","tool_name":"Bash","tool_input":{"command":"git status"}}' "$wr_top" \
      | bash "$(dirname "$SELF")/hooks/checkout-guard.sh" > "$T/wr/8.out" 2> "$T/wr/8.err" || wr_rc=$?
    [ "$wr_rc" -eq 0 ] || { cat "$T/wr/8.err"; echo "WTREAP BEAT HOOK RC FAIL (a read-only git form is allowed, rc 0)"; exit 1; }
    [ -s "$T/wr/8.err" ] && { cat "$T/wr/8.err"; echo "WTREAP BEAT STDERR FAIL (a missing worktrees dir must be SILENT — 2>/dev/null comes BEFORE the >)"; exit 1; }
    [ -s "$T/wr/8.out" ] && { cat "$T/wr/8.out"; echo "WTREAP BEAT VERDICT FAIL (the beat touch never changes the verdict)"; exit 1; }
    # teardown: the fixture back as it was found — the two ready fixtures gone, every feat/T-WR*
    # branch gone (a drill's litter, not a human's), the archives it made removed (the contract's
    # "archives are the human's to delete" is about real work; these are three files this drill
    # wrote itself), CONVENTIONS + SPRINT restored byte-exactly and the session id put back.
    "$SELF" release T-WR4 --to ready -m drill >/dev/null 2>&1 || true
    rm -f ops/board/ready/T-WR3.md ops/board/ready/T-WR4.md
    git branch -q -D feat/T-WR2 feat/T-WR3 feat/T-WR4 >/dev/null 2>&1 || true
    rm -rf .polaris/wt-archive
    if [ -f "$T/wr/conv.bak" ]; then cp "$T/wr/conv.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    [ -f "$T/wr/sprint.bak" ] && cp "$T/wr/sprint.bak" ops/SPRINT.md || rm -f ops/SPRINT.md
    rm -rf "$T/wr"
    if [ -n "$wr_sid" ]; then export CLAUDE_CODE_SESSION_ID="$wr_sid"; else unset CLAUDE_CODE_SESSION_ID; fi
    git add -A; git commit -qm 'wtreap drill cleanup' >/dev/null 2>&1 || true
}
