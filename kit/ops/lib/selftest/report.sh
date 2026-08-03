# lib/selftest/report.sh — selftest drills: report metrics brief hint. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_report() {
    # ==================== T-023 sprint-report drill (ops/contracts/sprint-report.md) ====================
    # seal committed the wave's report on integrate → it rode the --no-ff merge into base as a
    # docs(sprint-N) commit (no [<ID>] suffix, off the first-parent chain), and the file carries the
    # task's ID/title/acceptance/landed sha. Then cmd_report re-renders it, board read-only.
    git log --format=%s sprint/1 | grep -qx 'docs(sprint-1): report' || { echo "SEAL REPORT COMMIT FAIL (docs(sprint-N) must ride the wave)"; exit 1; }
    git log --first-parent --format=%s main | grep -qx 'docs(sprint-1): report' && { echo "SEAL REPORT FIRSTPARENT FAIL (the seal's report must not be a base first-parent commit)"; exit 1; }   # exact subject: v2's `report refresh` IS a first-parent commit on base, by design
    [ -f docs/sprints/sprint-1.md ] || { echo "SEAL REPORT FILE FAIL (report must ride into base)"; exit 1; }
    grep -q '^## T-1 — land a file$' docs/sprints/sprint-1.md || { echo "REPORT SECTION FAIL (ID + title)"; exit 1; }
    grep -q 'the file lands' docs/sprints/sprint-1.md || { echo "REPORT ACCEPTANCE FAIL (acceptance line verbatim)"; exit 1; }
    grep -q 'the sprint report has a story' docs/sprints/sprint-1.md || { echo "REPORT WHY FAIL (Why body verbatim)"; exit 1; }
    t1short="$(git log --format='%h %s' main | awk '/\[T-1\]$/ {print $1; exit}')"   # the land commit (subject ENDS [T-1]), not the seal merge whose body cites it
    grep -q "landed $t1short" docs/sprints/sprint-1.md || { echo "REPORT SHA FAIL (landed short sha)"; exit 1; }
    # cmd_report: explicit + board read-only. Rewrites the file WHOLE, prints the path.
    mainpre_r="$(git rev-parse main)"; boardpre_r="$(git rev-parse refs/heads/polaris/board)"
    "$SELF" report --sprint 1 > "$T/rep.out" || { echo "REPORT RUN FAIL"; exit 1; }
    grep -q 'sprint-1.md' "$T/rep.out" || { echo "REPORT PATH FAIL (must print the path)"; exit 1; }
    "$SELF" report > "$T/rep2.out" || { echo "REPORT CURRENT FAIL (no flag = current sprint)"; exit 1; }
    grep -q 'sprint-1.md' "$T/rep2.out" || { echo "REPORT CURRENT PATH FAIL"; exit 1; }
    "$SELF" report --all > "$T/rep3.out" || { echo "REPORT ALL FAIL"; exit 1; }
    grep -q 'sprint-1.md' "$T/rep3.out" || { echo "REPORT ALL PATH FAIL"; exit 1; }
    [ "$(git rev-parse main)" = "$mainpre_r" ] || { echo "REPORT COMMIT FAIL (a re-render that matches HEAD must commit nothing)"; exit 1; }
    [ "$(git rev-parse refs/heads/polaris/board)" = "$boardpre_r" ] || { echo "REPORT BOARD FAIL (report must not touch the board)"; exit 1; }
    git diff --quiet -- docs/sprints/sprint-1.md || { echo "REPORT IDEMPOTENT FAIL (cmd_report must match the sealed render)"; exit 1; }
    # ---------- v2 (T-061): the writer commits its own file when it is the ONLY dirt ----------
    # Fixture: commit a deliberately STALE sprint-1.md so the next render legitimately differs from
    # HEAD — the same shape as the post-`done` re-render that used to leave the tree dirty and kill
    # the NEXT land/seal with "working tree not clean". Everything here is unwound at the end.
    v2pre_r="$(git rev-parse main)"
    printf 'stale\n' > docs/sprints/sprint-1.md
    git commit -q -m 'report drill: stale report' -- docs/sprints/sprint-1.md
    # (a) MIXED dirt → commit NOTHING, print v1.1's hint verbatim, leave the foreign path alone
    echo foreign >> src/a.txt
    mixedpre_r="$(git rev-parse main)"
    "$SELF" report --sprint 1 > "$T/rep4.out" || { echo "REPORT MIXED RUN FAIL"; exit 1; }
    [ "$(git rev-parse main)" = "$mixedpre_r" ] || { echo "REPORT MIXED COMMIT FAIL (a foreign dirty path vetoes the self-commit)"; exit 1; }
    grep -q 'differs from HEAD' "$T/rep4.out" || { echo "REPORT MIXED HINT FAIL (v1.1 hint must still print)"; exit 1; }
    grep -q 'report commits nothing' "$T/rep4.out" || { echo "REPORT MIXED HINT TEXT FAIL (v1.1 hint text is verbatim)"; exit 1; }
    grep -q 'docs(sprint-1): report refresh' "$T/rep4.out" || { echo "REPORT MIXED HINT REMEDY FAIL (hint names the commit remedy)"; exit 1; }
    grep -q 'git checkout -- docs/sprints/sprint-1.md' "$T/rep4.out" || { echo "REPORT MIXED HINT DISCARD FAIL (hint names the discard remedy)"; exit 1; }
    tail -1 src/a.txt | grep -qx foreign || { echo "REPORT MIXED FOREIGN FAIL (the foreign dirty path must be untouched)"; exit 1; }
    # (b) ONLY dirt → self-commit with the pinned subject, tree clean after, no contradictory hint
    git checkout -- src/a.txt
    "$SELF" report --sprint 1 > "$T/rep5.out" || { echo "REPORT ONLYDIRT RUN FAIL"; exit 1; }
    git log -1 --format=%s | grep -qx 'docs(sprint-1): report refresh' || { echo "REPORT SELFCOMMIT FAIL (only-dirt must commit with the pinned subject)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "REPORT SELFCOMMIT CLEAN FAIL (the tree must come back clean)"; exit 1; }
    grep -q 'committed' "$T/rep5.out" && grep -q 'docs(sprint-1): report refresh' "$T/rep5.out" || { echo "REPORT SELFCOMMIT SAY FAIL (it must say what it committed)"; exit 1; }
    grep -q 'report commits nothing' "$T/rep5.out" && { echo "REPORT SELFCOMMIT HINT LEAK FAIL (a committed report must not also print the hint)"; exit 1; }
    grep -q '^## T-1 — land a file$' docs/sprints/sprint-1.md || { echo "REPORT SELFCOMMIT CONTENT FAIL (the committed file is the real render)"; exit 1; }
    # (c) --all → ONE commit, its own subject
    printf 'stale\n' > docs/sprints/sprint-1.md
    git commit -q -m 'report drill: stale report (all)' -- docs/sprints/sprint-1.md
    allpre_r="$(git rev-parse main)"
    "$SELF" report --all > "$T/rep6.out" || { echo "REPORT ALL SELFCOMMIT RUN FAIL"; exit 1; }
    git log -1 --format=%s | grep -qx 'docs(sprint): report refresh --all' || { echo "REPORT ALL SUBJECT FAIL (--all has its own pinned subject)"; exit 1; }
    [ "$(git rev-list --count "$allpre_r"..main)" = "1" ] || { echo "REPORT ALL ONE COMMIT FAIL (--all commits once)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "REPORT ALL CLEAN FAIL"; exit 1; }
    # (d) off-$BASE → byte-identical to v1: writes, hints, never commits
    git checkout -q -b integrate/report-drill
    printf 'stale\n' > docs/sprints/sprint-1.md
    git commit -q -m 'report drill: stale report (off-base)' -- docs/sprints/sprint-1.md
    offpre_r="$(git rev-parse HEAD)"
    "$SELF" report --sprint 1 > "$T/rep7.out" || { echo "REPORT OFFBASE RUN FAIL"; exit 1; }
    [ "$(git rev-parse HEAD)" = "$offpre_r" ] || { echo "REPORT OFFBASE COMMIT FAIL (off-base must never commit)"; exit 1; }
    grep -q 'report commits nothing' "$T/rep7.out" || { echo "REPORT OFFBASE HINT FAIL (off-base keeps the v1.1 hint)"; exit 1; }
    git checkout -q -- docs/sprints/sprint-1.md
    git checkout -q main; git branch -q -D integrate/report-drill
    git reset -q --hard "$v2pre_r"     # unwind the whole v2 fixture: later drills inherit the sealed main
}
drill_metrics() {
    for ev in claim handoff all-review done; do
      grep -q "\"ev\":\"$ev\",\"id\":\"T-1\"" ops/board/EVENTS.ndjson || { echo "EVENTS FAIL: $ev missing"; exit 1; }
    done
    "$SELF" metrics | grep -q 'done total: 1' || { echo "METRICS FAIL"; exit 1; }
    "$SELF" _match src/a.txt T-1 || { echo "_MATCH FAIL (should allow)"; exit 1; }
    "$SELF" _match src/other.txt T-1 && { echo "_MATCH FAIL (should reject)"; exit 1; }
    # --- v5: points telemetry + per-point calibration
    grep -q '"ev":"claim","id":"T-1".*"pts":1' ops/board/EVENTS.ndjson || { echo "PTS EVT FAIL"; exit 1; }
    "$SELF" metrics | grep -q '1pt p50' || { echo "PTS BUCKET FAIL"; exit 1; }
}
drill_brief() {
    # ========= T-032 status --brief + metrics summary drills (ops/contracts/status-brief.md) =========
    # --brief: ONE plain-English paragraph, grep-stable markers, NO table pipe, sprint clause from the
    # header, active IDs listed · plain `status` keeps its table + gains no brief markers · metrics
    # opens with an In-plain-English line above the untouched table · EVENTS empty → note, no summary.
    "$SELF" help | grep -q -- '--brief' || { echo "USAGE FAIL: --brief missing from help"; exit 1; }
    printf '# SPRINT 7 — the brief lane  capacity: 5\n' > ops/SPRINT.md
    printf -- '---\nid: T-BR1\ntitle: newest landed thing\ntype: feature\npoints: 1\nwsjf: 3\nstatus: done\nfiles_owned:\n  - src/br1.txt\n---\n' > ops/board/done/T-BR1.md
    printf -- '---\nid: T-BR2\ntitle: top queued thing\ntype: feature\npoints: 2\nwsjf: 9\nstatus: ready\nfiles_owned:\n  - src/br2.txt\n---\n' > ops/board/ready/T-BR2.md
    printf -- '---\nid: T-BR3\ntitle: in progress thing\ntype: feature\npoints: 1\nwsjf: 2\nstatus: active\nfiles_owned:\n  - src/br3.txt\n---\n' > ops/board/active/T-BR3.md
    "$SELF" status --brief > "$T/brief.out" || { echo "BRIEF RUN FAIL"; exit 1; }
    grep -q 'Last landed:' "$T/brief.out" || { echo "BRIEF MARKER FAIL (Last landed: missing)"; exit 1; }
    grep -q 'Next up:' "$T/brief.out" || { echo "BRIEF MARKER FAIL (Next up: missing)"; exit 1; }
    grep -q '|' "$T/brief.out" && { echo "BRIEF PIPE FAIL (a one-paragraph digest carries no table pipe)"; exit 1; }
    grep -q 'Sprint 7 (the brief lane):' "$T/brief.out" || { echo "BRIEF SPRINT CLAUSE FAIL (header-sourced sprint/goal)"; exit 1; }
    grep -q 'building (T-BR3)' "$T/brief.out" || { echo "BRIEF ACTIVE IDS FAIL (active ids must ride the building clause)"; exit 1; }
    grep -q 'Last landed: newest landed thing' "$T/brief.out" || { echo "BRIEF LAST-LANDED FAIL (newest done title)"; exit 1; }
    grep -q 'Next up: top queued thing' "$T/brief.out" || { echo "BRIEF NEXT-UP FAIL (top-wsjf ready title)"; exit 1; }
    grep -q 'POLARIS board' "$T/brief.out" && { echo "BRIEF NO-TABLE FAIL (brief must not print the status table header)"; exit 1; }
    # plain `status` unchanged: keeps its table header, gains NONE of the brief markers
    "$SELF" status > "$T/plain.out" || { echo "PLAIN STATUS FAIL"; exit 1; }
    grep -q 'POLARIS board' "$T/plain.out" || { echo "PLAIN HEADER FAIL (plain status must keep its table header)"; exit 1; }
    grep -q 'Last landed:' "$T/plain.out" && { echo "PLAIN BRIEF LEAK FAIL (plain status must not gain brief markers)"; exit 1; }
    # metrics: In-plain-English summary as the FIRST line, existing table still below it
    "$SELF" metrics > "$T/mt.out" || { echo "METRICS RUN FAIL"; exit 1; }
    head -1 "$T/mt.out" | grep -q '^In plain English:' || { echo "METRICS SUMMARY FIRST-LINE FAIL"; exit 1; }
    head -1 "$T/mt.out" | grep -q 'tasks done' || { echo "METRICS SUMMARY CONTENT FAIL"; exit 1; }
    grep -q '^done total:' "$T/mt.out" || { echo "METRICS TABLE FAIL (existing table must stay below the summary)"; exit 1; }
    # EVENTS empty → the no-telemetry note, and NO summary line
    mv ops/board/EVENTS.ndjson "$T/ev.save"; : > ops/board/EVENTS.ndjson
    "$SELF" metrics > "$T/mt-empty.out" 2>&1 || { echo "METRICS EMPTY RC FAIL"; exit 1; }
    grep -q 'no telemetry yet' "$T/mt-empty.out" || { echo "METRICS EMPTY NOTE FAIL"; exit 1; }
    grep -q 'In plain English:' "$T/mt-empty.out" && { echo "METRICS EMPTY SUMMARY FAIL (empty EVENTS must print no summary)"; exit 1; }
    mv "$T/ev.save" ops/board/EVENTS.ndjson
    rm -f ops/board/done/T-BR1.md ops/board/ready/T-BR2.md ops/board/active/T-BR3.md
    # ========= end T-032 status --brief + metrics summary drills =========
}
drill_hint() {
    # slow-suite hint: fake stamp 180s + integration: paranoid → land prints it; batch → silent
    printf -- '---\nid: T-EY\ntitle: hint file\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nowner: null\nbranch: feat/T-EY\nstatus: review\nfiles_owned:\n  - src/ey.txt\nverify: []\n---\n' > ops/board/review/T-EY.md
    git checkout -q -b feat/T-EY main
    echo ey > src/ey.txt; git add -A; git commit -qm ok
    git checkout -q main
    printf 'integration: paranoid\n' >> ops/CONVENTIONS.md
    git add -A; git commit -qm 'hint drill: paranoid'
    printf '180 1700000000\n' > .polaris/last-suite-seconds
    git checkout -q -b integrate/2026-01-03
    "$SELF" land T-EY > "$T/hint1.out" || { echo "HINT LAND FAIL"; exit 1; }
    grep -q 'suite last took 180s' "$T/hint1.out" || { echo "HINT FIRE FAIL (paranoid + 180s stamp must print the note)"; exit 1; }
    grep -q 'integration: batch' "$T/hint1.out" || { echo "HINT GUIDE FAIL (the note must name integration: batch)"; exit 1; }
    git reset -q --hard HEAD~1                  # unwind the land so the silent case re-lands the same task
    sed -i.bak 's/^integration: paranoid$/integration: batch/' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    git add -A; git commit -qm 'hint drill: batch'
    "$SELF" land T-EY > "$T/hint2.out" || { echo "HINT SILENT LAND FAIL"; exit 1; }
    grep -q 'suite last took' "$T/hint2.out" && { echo "HINT SILENT FAIL (integration: batch must not print the note)"; exit 1; }
    # cleanup: nothing sealed here — drop the drill refs, restore the pre-drill CONVENTIONS
    git checkout -q main
    git branch -q -D integrate/2026-01-03
    git branch -q -D feat/T-EY
    rm -f ops/board/review/T-EY.md .polaris/last-suite-seconds
    sed -i.bak -e '/^integration:/d' -e '/^test: true$/d' ops/CONVENTIONS.md && rm -f ops/CONVENTIONS.md.bak
    git add -A; git commit -qm 'express drill cleanup'
}
