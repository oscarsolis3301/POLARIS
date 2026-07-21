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
    # all four refusals died BEFORE any mutation
    [ "$(git rev-parse main)" = "$expre" ] || { echo "EXPRESS REFUSE MUTATE FAIL (base moved)"; exit 1; }
    git rev-parse -q --verify "refs/heads/integrate/$exd" >/dev/null && { echo "EXPRESS REFUSE MUTATE FAIL (integrate branch created)"; exit 1; }
    [ -f ops/board/review/T-EX.md ] || { echo "EXPRESS REFUSE MUTATE FAIL (task left review/)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "EXPRESS REFUSE DIRTY FAIL (a refusal must leave zero uncommitted state)"; exit 1; }
    # red suite mid-express: land unwinds (integrate back at base), kickback carries the failing tail
    sed -i.bak 's|^test: true$|test: bash -c "echo EXPRESS-BOOM; exit 1"|' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    git add -A; git commit -qm 'express drill: suite red'
    "$SELF" land --express T-EX > "$T/ex7.out" 2>&1 && { echo "EXPRESS RED FAIL (red suite must die)"; exit 1; }
    grep -q 'EXPRESS-BOOM' "$T/ex7.out" || { echo "EXPRESS RED TAIL FAIL (output must carry the failing tail)"; exit 1; }
    [ -f ops/board/active/T-EX.md ] || { echo "EXPRESS RED KICKBACK FAIL (task must bounce to active/)"; exit 1; }
    grep -q 'EXPRESS-BOOM' ops/board/active/T-EX.md || { echo "EXPRESS RED NOTE FAIL (kickback note must carry the tail)"; exit 1; }
    [ "$(git rev-parse "refs/heads/integrate/$exd")" = "$(git rev-parse main)" ] || { echo "EXPRESS RED UNWIND FAIL (the land must reset away)"; exit 1; }
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
    { grep -q 'finish line' "$T/ex8.out" && grep -q 'qa' "$T/ex8.out"; } || { echo "EXPRESS FINISH FAIL (final note must name qa)"; exit 1; }
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
