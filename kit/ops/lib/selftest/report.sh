# lib/selftest/report.sh — selftest drills: report metrics brief hint. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_report() {
    # ==================== T-023 sprint-report drill (ops/contracts/sprint-report.md) ====================
    # seal committed the wave's report on integrate → it rode the --no-ff merge into base as a
    # docs(sprint-N) commit (no [<ID>] suffix, off the first-parent chain), and the file carries the
    # task's ID/title/acceptance/landed sha. Then cmd_report re-renders it, board read-only.
    git log --format=%s sprint/1 | grep -qx 'docs(sprint-1): report' || { echo "SEAL REPORT COMMIT FAIL (docs(sprint-N) must ride the wave)"; exit 1; }
    git log --first-parent --format=%s main | grep -q 'docs(sprint-1)' && { echo "SEAL REPORT FIRSTPARENT FAIL (report must not be a base first-parent commit)"; exit 1; }
    [ -f docs/sprints/sprint-1.md ] || { echo "SEAL REPORT FILE FAIL (report must ride into base)"; exit 1; }
    grep -q '^## T-1 — land a file$' docs/sprints/sprint-1.md || { echo "REPORT SECTION FAIL (ID + title)"; exit 1; }
    grep -q 'the file lands' docs/sprints/sprint-1.md || { echo "REPORT ACCEPTANCE FAIL (acceptance line verbatim)"; exit 1; }
    grep -q 'the sprint report has a story' docs/sprints/sprint-1.md || { echo "REPORT WHY FAIL (Why body verbatim)"; exit 1; }
    t1short="$(git log --format='%h %s' main | awk '/\[T-1\]$/ {print $1; exit}')"   # the land commit (subject ENDS [T-1]), not the seal merge whose body cites it
    grep -q "landed $t1short" docs/sprints/sprint-1.md || { echo "REPORT SHA FAIL (landed short sha)"; exit 1; }
    # cmd_report: explicit + board read-only. Rewrites the file WHOLE, prints the path, commits NOTHING.
    mainpre_r="$(git rev-parse main)"; boardpre_r="$(git rev-parse refs/heads/polaris/board)"
    "$SELF" report --sprint 1 > "$T/rep.out" || { echo "REPORT RUN FAIL"; exit 1; }
    grep -q 'sprint-1.md' "$T/rep.out" || { echo "REPORT PATH FAIL (must print the path)"; exit 1; }
    "$SELF" report > "$T/rep2.out" || { echo "REPORT CURRENT FAIL (no flag = current sprint)"; exit 1; }
    grep -q 'sprint-1.md' "$T/rep2.out" || { echo "REPORT CURRENT PATH FAIL"; exit 1; }
    "$SELF" report --all > "$T/rep3.out" || { echo "REPORT ALL FAIL"; exit 1; }
    grep -q 'sprint-1.md' "$T/rep3.out" || { echo "REPORT ALL PATH FAIL"; exit 1; }
    [ "$(git rev-parse main)" = "$mainpre_r" ] || { echo "REPORT COMMIT FAIL (report must not commit on base)"; exit 1; }
    [ "$(git rev-parse refs/heads/polaris/board)" = "$boardpre_r" ] || { echo "REPORT BOARD FAIL (report must not touch the board)"; exit 1; }
    git diff --quiet -- docs/sprints/sprint-1.md || { echo "REPORT IDEMPOTENT FAIL (cmd_report must match the sealed render)"; exit 1; }
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
