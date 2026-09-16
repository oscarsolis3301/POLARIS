# lib/selftest/board.sh — selftest drills: fmlist grant. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_fmlist() {
    # ========================= fm_list parsing drills =========================
    # inline scalar · "[]" · populated "[a, b]" flow list · block list — plus edge
    # stripping (comment/\r/whitespace, empty items). fm_list is a shell function
    # defined in this same process, so it's called directly (no "$SELF" needed).
    # ops/contracts/frontmatter-lists.md
    printf -- '---\r\nid: T-L\r\nscalar: v\r\nempty: []\r\nflow: [a, b, c]  # comment\r\nmessy: [a,, b ,c,]\r\nblock:\r\n  - x\r\n  - y  # comment\r\ndepends_on: [T-A, T-B]\r\n---\r\n' > "$T/fmlist.md"
    [ "$(fm_list scalar "$T/fmlist.md")" = "v" ] || { echo "FM_LIST SCALAR FAIL"; exit 1; }
    [ -z "$(fm_list empty "$T/fmlist.md")" ] || { echo "FM_LIST EMPTY FAIL ([] must yield nothing)"; exit 1; }
    [ "$(fm_list flow "$T/fmlist.md" | tr '\n' ',')" = "a,b,c," ] || { echo "FM_LIST FLOW FAIL (populated inline list must split)"; exit 1; }
    [ "$(fm_list messy "$T/fmlist.md" | tr '\n' ',')" = "a,b,c," ] || { echo "FM_LIST MESSY FAIL (empty items from ,, and trailing , must drop)"; exit 1; }
    [ "$(fm_list block "$T/fmlist.md" | tr '\n' ',')" = "x,y," ] || { echo "FM_LIST BLOCK FAIL (block list must stay byte-identical)"; exit 1; }
    [ "$(fm_list depends_on "$T/fmlist.md" | wc -l | tr -d ' ')" = "2" ] || { echo "FM_LIST DEPENDS_ON COUNT FAIL (inline flow list must yield 2 items, not 1)"; exit 1; }
    [ "$(fm_list depends_on "$T/fmlist.md" | tr '\n' ',')" = "T-A,T-B," ] || { echo "FM_LIST DEPENDS_ON VALUES FAIL"; exit 1; }
}
drill_newcmds() {
    # board-fm · check · _guard — the 2026-07-25 token/wall-clock commands.
    # HERMETIC (ops/contracts/selftest-sharding.md v1.1): every artifact created here is removed
    # before returning, so any --only/--parallel subset containing this drill stays honest.
    "$SELF" board-fm > "$T/bfm.out" 2>&1 || { echo "BOARD-FM RC FAIL"; exit 1; }
    head -1 "$T/bfm.out" | grep -q '^col	id	pts' || { echo "BOARD-FM HEADER FAIL (agents parse this header)"; exit 1; }
    "$SELF" board-fm nosuchcolumn >/dev/null 2>&1 && { echo "BOARD-FM BADCOL FAIL (must reject)"; exit 1; }
    printf '# not a task\n' > ops/board/backlog/IDEAS.md
    "$SELF" board-fm backlog | grep -q 'IDEAS' && { echo "BOARD-FM IDEAS FAIL (frontmatter-less files must be skipped)"; exit 1; }
    # _guard: 0 clean · 1 rules deny · 3 not owned. One call replaces _rules + _match.
    # Seed our OWN rule (drill_rules pattern) — the throwaway repo's RULES.tsv is whatever
    # init-board wrote, NOT this repo's, so asserting on ops/polaris would be a false premise.
    "$SELF" _guard src/newcmds-ok.txt - >/dev/null 2>&1 || { echo "GUARD CLEAN FAIL (want rc 0)"; exit 1; }
    printf 'src/newcmds-deny.txt\tpath\t-\tnewcmds drill\n' >> ops/RULES.tsv
    "$SELF" _guard src/newcmds-deny.txt - >/dev/null 2>&1; [ $? -eq 1 ] || { echo "GUARD RULES FAIL (want rc 1)"; exit 1; }
    sed -i.bak '/newcmds drill/d' ops/RULES.tsv && rm -f ops/RULES.tsv.bak
    "$SELF" _guard src/newcmds-ok.txt T-NOPE >/dev/null 2>&1; [ $? -eq 3 ] || { echo "GUARD OWN FAIL (want rc 3)"; exit 1; }
    # RULES.tsv is agent-maintainable (CLAUDE.md invariant 11, owner decision 2026-07-25): writes
    # to it are NOT specially gated. Assert that, so a future guard change cannot silently re-lock
    # policy maintenance without this drill going red and forcing the decision back into the open.
    { cat ops/RULES.tsv; printf 'src/ao-new.txt\tpath\t-\tdrill\n'; } > "$T/ao.add"
    "$SELF" _guard ops/RULES.tsv - "$T/ao.add" >/dev/null 2>&1 || { echo "RULES ADD FAIL (adding a rule must be allowed)"; exit 1; }
    grep -v 'installed copy' ops/RULES.tsv > "$T/ao.del" 2>/dev/null || cp ops/RULES.tsv "$T/ao.del"
    "$SELF" _guard ops/RULES.tsv - "$T/ao.del" >/dev/null 2>&1 || { echo "RULES EDIT FAIL (editing rules must be allowed)"; exit 1; }
    rm -f "$T/ao.add" "$T/ao.del"
    # check: missing golden is RED (never silently green) · matching is green · differing is red
    mkdir -p ops/tests
    printf 'echo hello\n' > ops/tests/st.cmd
    "$SELF" check --only st >/dev/null 2>&1 && { echo "CHECK NOGOLDEN FAIL (missing golden must be red)"; exit 1; }
    "$SELF" check --only st --update >/dev/null 2>&1 || { echo "CHECK UPDATE FAIL"; exit 1; }
    grep -q '^hello$' ops/tests/st.expected || { echo "CHECK GOLDEN CONTENT FAIL"; exit 1; }
    "$SELF" check --only st >/dev/null 2>&1 || { echo "CHECK GREEN FAIL"; exit 1; }
    printf 'goodbye\n' > ops/tests/st.expected
    "$SELF" check --only st >/dev/null 2>&1 && { echo "CHECK RED FAIL (a differing golden must be red)"; exit 1; }
    printf 'echo hi\n' > ops/tests/st.cmd; printf 'hi\n' > ops/tests/st.expected; printf '3\n' > ops/tests/st.rc
    "$SELF" check --only st >/dev/null 2>&1 && { echo "CHECK RC FAIL (wrong exit code must be red)"; exit 1; }
    rm -rf ops/tests                                  # hermetic: leave the fixture as found
    rm -f ops/board/backlog/IDEAS.md
}
drill_grant() {
    # ================== T-005 grant drills (ops/contracts/grant.md) ==================
    # sanctioned files_owned amendment: refusals (wrong column · missing -m · overlap, each
    # mutating NOTHING) then one success = append + Notes line + event + ONE board commit.
    "$SELF" help | grep -q 'grant' || { echo "USAGE FAIL: grant missing from help"; exit 1; }
    printf -- '---\nid: T-G\npoints: 1\nwsjf: 6\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/g.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-G.md
    printf -- '---\nid: T-H\npoints: 1\nwsjf: 1\nstatus: ready\nfiles_owned:\n  - src/h/\n---\n' > ops/board/ready/T-H.md
    "$SELF" claim T-G > "$T/tg.out" 2>&1
    grep -q 'overlap' "$T/tg.out" && { echo "CLAIM CLEAN NOISE FAIL (the disjointness gate must be silent on a clean claim)"; exit 1; }
    "$SELF" grant T-H src/free.txt -m why >/dev/null 2>&1 && { echo "GRANT COLUMN FAIL (ready task must refuse — grant is for active/ only)"; exit 1; }
    "$SELF" grant T-G src/free.txt >/dev/null 2>&1 && { echo "GRANT -M FAIL (missing -m must refuse)"; exit 1; }
    gpre="$(git rev-parse refs/heads/polaris/board)"
    "$SELF" grant T-G src/h/inner.txt -m why >/dev/null 2>&1 && { echo "GRANT OVERLAP FAIL (path under another task's dir/ must refuse)"; exit 1; }
    "$SELF" grant T-G src/ -m why >/dev/null 2>&1 && { echo "GRANT OVERLAP FAIL (dir/ swallowing another task's entry must refuse — both directions)"; exit 1; }
    [ "$(git rev-parse refs/heads/polaris/board)" = "$gpre" ] || { echo "GRANT REFUSE MUTATE FAIL (a refusal must not commit)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "GRANT REFUSE DIRTY FAIL (a refusal must leave zero uncommitted state)"; exit 1; }
    "$SELF" grant T-G src/free.txt -m "discovered during wiring" >/dev/null || { echo "GRANT FAIL (free path must succeed)"; exit 1; }
    fm_list files_owned ops/board/active/T-G.md | grep -qx 'src/free.txt' || { echo "GRANT APPEND FAIL (path missing from files_owned)"; exit 1; }
    fm_list files_owned ops/board/active/T-G.md | grep -qx 'src/g.txt' || { echo "GRANT PRESERVE FAIL (existing entries must survive)"; exit 1; }
    grep -q '^- grant: src/free.txt — discovered during wiring$' ops/board/active/T-G.md || { echo "GRANT NOTE FAIL (Notes line missing)"; exit 1; }
    grep -q '"ev":"grant","id":"T-G".*"note":"src/free.txt"' ops/board/EVENTS.ndjson || { echo "GRANT EVENT FAIL"; exit 1; }
    git log -1 --format=%s refs/heads/polaris/board | grep -q '^chore(board): grant T-G src/free.txt$' || { echo "GRANT COMMIT FAIL (one board commit on polaris/board, contract subject)"; exit 1; }
    ( cd .polaris/wt/T-G && echo f > src/free.txt && git add -A && git commit -qm ok \
      && "$SELF" verify T-G >/dev/null ) || { echo "GRANT VERIFY FAIL (granted path must pass ownership)"; exit 1; }
    # ---- T-059 claim hardening (ops/contracts/shared-checkout.md): id_ok pre-lock + the claim-time
    # disjointness gate, drilled here where a claimed task (T-G, active) already owns src/g.txt.
    "$SELF" claim 'bad..id' >/dev/null 2>"$T/badid.err" && { echo "CLAIM BADID FAIL (invalid ID must die)"; exit 1; }
    grep -q 'invalid task ID' "$T/badid.err" || { echo "CLAIM BADID MSG FAIL (id_ok must name the bad ID)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/bad..id" ] && { echo "CLAIM BADID LOCK FAIL (id_ok must run BEFORE lock_take)"; exit 1; }
    gvpre="$(git rev-parse refs/heads/polaris/board)"
    printf -- '---\nid: T-OV\npoints: 1\nwsjf: 9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/\nverify: []\n---\n## Notes\n' > ops/board/ready/T-OV.md
    "$SELF" claim T-OV >/dev/null 2>"$T/ov.err" && { echo "CLAIM GATE EXPLICIT FAIL (overlap with active T-G must refuse)"; exit 1; }
    grep -q "T-OV files_owned 'src/' overlaps active T-G 'src/g.txt'" "$T/ov.err" || { echo "CLAIM GATE NAME FAIL (die must name the task and both patterns)"; exit 1; }
    [ -f ops/board/ready/T-OV.md ] || { echo "CLAIM GATE EXPLICIT MUTATE FAIL (an explicit refusal must move nothing)"; exit 1; }
    [ "$(git rev-parse refs/heads/polaris/board)" = "$gvpre" ] || { echo "CLAIM GATE EXPLICIT COMMIT FAIL (an explicit refusal must not commit)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/T-OV" ] && { echo "CLAIM GATE EXPLICIT LOCK FAIL (the refused claim must release its lock)"; exit 1; }
    "$SELF" claim > "$T/ovauto.out" 2>&1 || { echo "CLAIM GATE AUTO RC FAIL (auto-pick must block the overlap and claim the next candidate)"; exit 1; }
    [ -f ops/board/blocked/T-OV.md ] || { echo "CLAIM GATE BLOCK FAIL (the overlapping candidate must auto-block)"; exit 1; }
    grep -q 're-groom or wait for T-G' ops/board/blocked/T-OV.md || { echo "CLAIM GATE NOTE FAIL (the ⛔ note must name the remedy)"; exit 1; }
    git log --format=%s refs/heads/polaris/board | grep -qx 'chore(board): block T-OV (ownership overlap)' || { echo "CLAIM GATE COMMIT FAIL (ONE board commit, contract subject)"; exit 1; }
    grep -q '"ev":"blocked","id":"T-OV"' ops/board/EVENTS.ndjson || { echo "CLAIM GATE EVENT FAIL (the auto-block must emit ev blocked)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/T-OV" ] && { echo "CLAIM GATE AUTOLOCK FAIL (the blocked candidate's lock must release)"; exit 1; }
    [ -f ops/board/active/T-H.md ] || { echo "CLAIM GATE NEXT FAIL (claim must take the next candidate)"; exit 1; }
    "$SELF" release T-H --to ready -m drill >/dev/null
    rm -f ops/board/blocked/T-OV.md
    # wt_add honesty: a junk dir at the worktree path is NOT an index.lock race — claim must die
    # re-emitting git's real stderr (never the old blanket "git index busy"), and resume must
    # recreate the worktree through the same wt_add primitive once the junk is gone.
    mkdir -p .polaris/wt/T-H && : > .polaris/wt/T-H/junk
    "$SELF" claim T-H >/dev/null 2>"$T/wterr.err" && { echo "WT HONEST RC FAIL (worktree add into a junk dir must die)"; exit 1; }
    grep -q 'git index busy' "$T/wterr.err" && { echo "WT HONEST MSG FAIL (the blanket index-busy guess must be gone)"; exit 1; }
    grep -q 'already exists' "$T/wterr.err" || { echo "WT HONEST STDERR FAIL (git's real error must re-emit verbatim)"; exit 1; }
    rm -rf .polaris/wt/T-H
    "$SELF" resume T-H >/dev/null 2>&1 || { echo "WT RESUME FAIL (resume must recreate the worktree via wt_add)"; exit 1; }
    [ -d .polaris/wt/T-H ] || { echo "WT RESUME DIR FAIL (recreated worktree missing)"; exit 1; }
    "$SELF" release T-H --to ready -m drill >/dev/null
    # ---- end T-059 claim hardening ----
    # ================== T-157 amend drills (ops/contracts/grant.md v2) ==================
    # grant's sibling: grant widens a claimed task's OWNERSHIP, amend corrects its ACCEPTANCE LIST.
    # The two refusals are the product, not the guard rails — a Builder must not be able to relax its
    # own gate (approve's rule, mechanical not advisory), and an amendment must not be able to
    # install the wave suite that run_verify_cmds already refuses. Both mutate NOTHING.
    "$SELF" help | grep -q '^  amend ' || { echo "USAGE FAIL: amend missing from help"; exit 1; }
    printf -- '---\nid: T-AM\ntitle: amend me\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: active\nfiles_owned:\n  - src/am.txt\nverify:\n  - test -f one\n  - test -f two\n  - test -f three\n---\n## Notes\n' > ops/board/active/T-AM.md
    ampre="$(git rev-parse refs/heads/polaris/board)"; amsum="$(git hash-object ops/board/active/T-AM.md)"
    # (1) feat/* — the containment. T-G is claimed, so .polaris/wt/T-G is a real feat/* worktree.
    ( cd .polaris/wt/T-G && "$SELF" amend T-AM --verify 1 -m why -- true ) > "$T/am1.out" 2>&1 \
      && { echo "AMEND FEAT FAIL (a feat/* branch must refuse — a Builder never rewrites its own gate)"; exit 1; }
    grep -q 'a Builder never rewrites its own gate' "$T/am1.out" || { cat "$T/am1.out"; echo "AMEND FEAT MSG FAIL (the contract pins this refusal text verbatim)"; exit 1; }
    # (2) out of range, naming the length so the caller can see what it may pick
    "$SELF" amend T-AM --verify 9 -m why -- true > "$T/am2.out" 2>&1 \
      && { echo "AMEND RANGE FAIL (a line past the end must refuse)"; exit 1; }
    grep -q 'verify has 3 line(s), no line 9' "$T/am2.out" || { cat "$T/am2.out"; echo "AMEND RANGE MSG FAIL (the refusal must name the length and the line asked for)"; exit 1; }
    # (3) a bare full-suite command — run_verify_cmds' own predicate, reused. Prepended so cfg's
    #     first-match-wins picks it whatever the fixture's CONVENTIONS already says.
    if [ -f ops/CONVENTIONS.md ]; then cp ops/CONVENTIONS.md "$T/am-conv.bak"; else rm -f "$T/am-conv.bak"; fi
    { printf 'test: bash ops/tests/all.sh\n'; cat "$T/am-conv.bak" 2>/dev/null || true; } > ops/CONVENTIONS.md
    "$SELF" amend T-AM --verify 1 -m why -- bash ops/tests/all.sh > "$T/am3.out" 2>&1 \
      && { echo "AMEND SUITE FAIL (a bare full-suite command must refuse — an amendment that could install one is a hole in a gate that already exists)"; exit 1; }
    grep -q 'that is the wave gate, never a verify: line' "$T/am3.out" || { cat "$T/am3.out"; echo "AMEND SUITE MSG FAIL"; exit 1; }
    if [ -f "$T/am-conv.bak" ]; then cp "$T/am-conv.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    rm -f "$T/am-conv.bak"
    [ "$(git rev-parse refs/heads/polaris/board)" = "$ampre" ] || { echo "AMEND REFUSE COMMIT FAIL (a refusal must not commit)"; exit 1; }
    [ "$(git hash-object ops/board/active/T-AM.md)" = "$amsum" ] || { echo "AMEND REFUSE MUTATE FAIL (a refusal must leave the task byte-identical)"; exit 1; }
    # (4) replace line 2: old-1 / new / old-3, the Notes line, the event, ONE board commit
    amn="$(git rev-list --count refs/heads/polaris/board)"
    "$SELF" amend T-AM --verify 2 -m "the sibling lands first" -- test -f TWO >/dev/null \
      || { echo "AMEND REPLACE FAIL (the sanctioned edit must succeed from the primary)"; exit 1; }
    [ "$(fm_list verify ops/board/active/T-AM.md | tr '\n' '|')" = "test -f one|test -f TWO|test -f three|" ] \
      || { fm_list verify ops/board/active/T-AM.md; echo "AMEND REPLACE LIST FAIL (order kept: old-1 / new / old-3)"; exit 1; }
    grep -q '^- amend: verify\[2\] "test -f two" → "test -f TWO" — the sibling lands first$' ops/board/active/T-AM.md \
      || { echo "AMEND NOTE FAIL (the Notes line is what tells an amendment apart from a lane lowering its own bar)"; exit 1; }
    grep -q '"ev":"amend","id":"T-AM".*"note":"verify\[2\]"' ops/board/EVENTS.ndjson || { echo "AMEND EVENT FAIL"; exit 1; }
    git log -1 --format=%s refs/heads/polaris/board | grep -qx 'chore(board): amend T-AM verify' || { echo "AMEND COMMIT FAIL (contract subject)"; exit 1; }
    [ "$(git rev-list --count refs/heads/polaris/board)" = "$(( amn + 1 ))" ] || { echo "AMEND COMMIT COUNT FAIL (ONE board commit)"; exit 1; }
    # (5) --drop leaves two lines · (6) --add appends one
    "$SELF" amend T-AM --verify 1 --drop -m "unsatisfiable until the sibling lands" >/dev/null || { echo "AMEND DROP FAIL"; exit 1; }
    [ "$(fm_list verify ops/board/active/T-AM.md | tr '\n' '|')" = "test -f TWO|test -f three|" ] \
      || { fm_list verify ops/board/active/T-AM.md; echo "AMEND DROP LIST FAIL (two lines, order kept)"; exit 1; }
    grep -q '^- amend: verify\[1\] "test -f one" → dropped — unsatisfiable until the sibling lands$' ops/board/active/T-AM.md || { echo "AMEND DROP NOTE FAIL"; exit 1; }
    "$SELF" amend T-AM --verify --add -m "the narrow check it actually needs" -- test -f four >/dev/null || { echo "AMEND ADD FAIL"; exit 1; }
    [ "$(fm_list verify ops/board/active/T-AM.md | tr '\n' '|')" = "test -f TWO|test -f three|test -f four|" ] \
      || { fm_list verify ops/board/active/T-AM.md; echo "AMEND ADD LIST FAIL (appended last, order kept)"; exit 1; }
    grep -q '^- amend: verify\[+\] "test -f four" — the narrow check it actually needs$' ops/board/active/T-AM.md || { echo "AMEND ADD NOTE FAIL"; exit 1; }
    grep -qx '  - test -f four' ops/board/active/T-AM.md || { echo "AMEND INDENT FAIL (the block list's own indentation must survive)"; exit 1; }
    rm -f ops/board/active/T-AM.md      # gone from disk before anything downstream can claim or count it; the next board commit drops it from the ref
    # ================== T-153/T-155 learned drills (ops/contracts/sprint-report.md v3) ==========
    # The Learned log died at sprint 11 because its only writer was the Integrator, and a lane
    # standing in a feat/* worktree never hand-edits a board file. `learned` is the pen — from any
    # lane, any branch. These assertions live HERE and not in T-153's own drill for one mechanical
    # reason: a drill cannot call a command its own worktree cannot dispatch, and the dispatch line
    # landed with T-155.
    "$SELF" help | grep -q '^  learned ' || { echo "USAGE FAIL: learned missing from help"; exit 1; }
    if [ -f ops/SPRINT.md ]; then cp ops/SPRINT.md "$T/ln-sprint.bak"; else rm -f "$T/ln-sprint.bak"; fi
    printf '%s\n' '# SPRINT 1 — learned drill  capacity: 5' '' '## Learned' '- 2026-01-01 · the first lesson' '' '## Burndown' '| date | done pts | remaining |' > ops/SPRINT.md
    lnn="$(git rev-list --count refs/heads/polaris/board)"
    ( cd .polaris/wt/T-G && "$SELF" learned -m "a lane can write the Learned log" >/dev/null ) \
      || { echo "LEARNED FAIL (it must work from inside a feat/* worktree — that is the whole point of the command)"; exit 1; }
    [ "$(sed -n '/^## Learned/,/^## Burndown/p' ops/SPRINT.md | sed -n '3p' | tr -d '\r')" = "- $(date +%F) · a lane can write the Learned log" ] \
      || { sed -n '/^## Learned/,/^## Burndown/p' ops/SPRINT.md; echo "LEARNED BULLET FAIL (the bullet is the section's LAST bullet — under the existing one, above the next heading)"; exit 1; }
    [ "$(grep -c '^## ' ops/SPRINT.md)" = "2" ] || { cat ops/SPRINT.md; echo "LEARNED SECTION FAIL (the existing section is used, never a second one)"; exit 1; }
    [ "$(tail -1 ops/SPRINT.md | tr -d '\r')" = "| date | done pts | remaining |" ] || { cat ops/SPRINT.md; echo "LEARNED TAIL FAIL (everything after the section must stay where it was)"; exit 1; }
    grep -q '"ev":"learned","id":"".*"note":"a lane can write the Learned log"' ops/board/EVENTS.ndjson || { echo "LEARNED EVENT FAIL"; exit 1; }
    git log -1 --format=%s refs/heads/polaris/board | grep -qx 'chore(board): learned' || { echo "LEARNED COMMIT FAIL (the contract pins this board-commit subject)"; exit 1; }
    [ "$(git rev-list --count refs/heads/polaris/board)" = "$(( lnn + 1 ))" ] || { echo "LEARNED COMMIT COUNT FAIL (ONE board commit)"; exit 1; }
    "$SELF" learned >/dev/null 2>&1 && { echo "LEARNED -M FAIL (an empty -m must refuse — a lesson nobody wrote is not a lesson)"; exit 1; }
    if [ -f "$T/ln-sprint.bak" ]; then cp "$T/ln-sprint.bak" ops/SPRINT.md; else rm -f ops/SPRINT.md; fi
    rm -f "$T/ln-sprint.bak"
    # ================== end T-157 amend + learned drills ==================
    "$SELF" release T-G --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-G.md ops/board/ready/T-H.md
    # ================== end T-005 grant drills ==================
}
drill_claimguard() {
    # ---- T-062 claimguard drill (ops/contracts/shared-checkout.md § Executable check) ----
    # claim's three isolation gates, end to end: (1) an invalid ID dies via id_ok BEFORE lock_take,
    # (2) a planted ref literally named `feat` — local AND scratch origin — is ARCHIVED as
    # stray/feat-<sha7> and the claim then succeeds, (3) two overlapping ready tasks → auto-pick
    # blocks the second in blocked/ with the remedy note and claims the next candidate.
    "$SELF" claim 'cg..bad' >/dev/null 2>"$T/cg1.err" && { echo "CLAIMGUARD BADID FAIL (invalid ID must die)"; exit 1; }
    grep -q 'invalid task ID' "$T/cg1.err" || { echo "CLAIMGUARD BADID MSG FAIL (id_ok must name the refusal)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/cg..bad" ] && { echo "CLAIMGUARD BADID LOCK FAIL (id_ok must run BEFORE lock_take)"; exit 1; }
    # (2) in a NESTED throwaway repo: the main fixture's lingering feat/<ID> branches make a ref
    # literally named `feat` un-plantable there (git's ref D/F rule) — and the nested repo dies
    # whole at the end, locks, worktrees and refs with it (T-046 hermeticity by construction).
    git init -q -b main "$T/cgrepo" 2>/dev/null || { git init -q "$T/cgrepo"; git -C "$T/cgrepo" symbolic-ref HEAD refs/heads/main; }
    ( set -e; cd "$T/cgrepo"; git config user.email t@t; git config user.name t
      mkdir -p src; echo x > src/cg.txt
      git add -A; git commit -qm init
      "$SELF" init-board >/dev/null
      git add -A; git commit -qm board
      git init -q --bare "$T/cg-origin.git"
      git remote add origin "$T/cg-origin.git"
      git push -qu origin main >/dev/null 2>&1
      git branch feat main
      git push -q origin main:refs/heads/feat
      cg_sha="$(git rev-parse refs/heads/feat)"
      cg_7="$(git rev-parse --short=7 refs/heads/feat)"
      printf -- '---\nid: T-CG\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/cg.txt\nverify: []\n---\n' > ops/board/ready/T-CG.md
      "$SELF" claim T-CG > "$T/cg2.out" 2>&1 || { cat "$T/cg2.out"; echo "CLAIMGUARD STRAY CLAIM FAIL (a stray feat ref must be repaired, never fatal)"; exit 1; }
      [ -f ops/board/active/T-CG.md ] || { echo "CLAIMGUARD STRAY MOVE FAIL (the claim must complete)"; exit 1; }
      [ -d .polaris/wt/T-CG ] || { echo "CLAIMGUARD STRAY WT FAIL (the worktree must exist)"; exit 1; }
      git show-ref --verify -q refs/heads/feat && { echo "CLAIMGUARD STRAY LOCAL FAIL (local feat must be renamed away)"; exit 1; }
      [ "$(git rev-parse "refs/heads/stray/feat-$cg_7")" = "$cg_sha" ] || { echo "CLAIMGUARD STRAY ARCHIVE FAIL (local feat must be ARCHIVED as stray/feat-<sha7>)"; exit 1; }
      git ls-remote origin refs/heads/feat | grep -q . && { echo "CLAIMGUARD STRAY ORIGIN FAIL (origin's feat must be archived away)"; exit 1; }
      [ "$(git ls-remote origin "refs/heads/stray/feat-$(printf '%.7s' "$cg_sha")" | cut -f1)" = "$cg_sha" ] || { echo "CLAIMGUARD STRAY ORIGIN ARCHIVE FAIL (origin's feat must be RENAMED, never deleted)"; exit 1; }
    ) || exit 1
    rm -rf "$T/cgrepo" "$T/cg-origin.git"
    # (3) overlap auto-block, in the main fixture: A active, B overlaps A (top wsjf), C is free —
    # auto-pick must block B with the remedy ON THE RECORD and claim C in the same pass.
    printf -- '---\nid: T-CGA\npoints: 1\nwsjf: 9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/cga.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-CGA.md
    "$SELF" claim T-CGA >/dev/null
    printf -- '---\nid: T-CGB\npoints: 1\nwsjf: 8\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/cga.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-CGB.md
    printf -- '---\nid: T-CGC\npoints: 1\nwsjf: 1\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/cgc.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-CGC.md
    "$SELF" claim > "$T/cg3.out" 2>&1 || { cat "$T/cg3.out"; echo "CLAIMGUARD OVERLAP RC FAIL (auto-pick must block the overlap and claim the next)"; exit 1; }
    [ -f ops/board/blocked/T-CGB.md ] || { echo "CLAIMGUARD OVERLAP BLOCK FAIL (the overlapping candidate must auto-move to blocked/)"; exit 1; }
    grep -q 're-groom or wait for T-CGA' ops/board/blocked/T-CGB.md || { echo "CLAIMGUARD OVERLAP NOTE FAIL (the ⛔ note must carry the remedy)"; exit 1; }
    git log --format=%s refs/heads/polaris/board | grep -qx 'chore(board): block T-CGB (ownership overlap)' || { echo "CLAIMGUARD OVERLAP COMMIT FAIL (ONE board commit, contract subject)"; exit 1; }
    grep -q '"ev":"blocked","id":"T-CGB"' ops/board/EVENTS.ndjson || { echo "CLAIMGUARD OVERLAP EVENT FAIL (the auto-block must emit ev blocked)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/T-CGB" ] && { echo "CLAIMGUARD OVERLAP LOCK FAIL (the blocked candidate's lock must release)"; exit 1; }
    [ -f ops/board/active/T-CGC.md ] || { echo "CLAIMGUARD OVERLAP NEXT FAIL (claim must take the next candidate)"; exit 1; }
    "$SELF" release T-CGC --to ready -m drill >/dev/null
    "$SELF" release T-CGA --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-CGA.md ops/board/ready/T-CGC.md ops/board/blocked/T-CGB.md
    git branch -q -D feat/T-CGA feat/T-CGC 2>/dev/null || true
}
drill_readyoverlap() {
    # ---- T-089 readyoverlap drill (ops/contracts/shared-checkout.md v2 §3) ----
    # The claim gate sweeps ready ∪ active: two READY tasks sharing a file are caught at claim
    # time — an explicit claim dies naming `overlaps ready`, auto-pick parks the colliding
    # candidate in blocked/ with the remedy on the record and claims the next free one in the same
    # pass — and `drift` REPORTS the overlap always, while only --strict turns it into a failing
    # exit (plain drift stays rc 0: an audit, not a gate).
    printf -- '---\nid: T-ROA\npoints: 1\nwsjf: 9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/roa.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-ROA.md
    printf -- '---\nid: T-ROB\npoints: 1\nwsjf: 8\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/roa.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-ROB.md
    printf -- '---\nid: T-ROC\npoints: 1\nwsjf: 1\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/roc.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-ROC.md
    # (1) drift: plain run reports but exits 0; --strict fails. Subshells on purpose — --strict
    #     exits the script on findings (spine precedent, observe.sh:1515).
    ( "$SELF" drift > "$T/ro1.out" 2>&1 ) || { cat "$T/ro1.out"; echo "READYOVERLAP DRIFT RC FAIL (plain drift must exit 0 on findings)"; exit 1; }
    grep -q 'OWNERSHIP OVERLAP' "$T/ro1.out" || { cat "$T/ro1.out"; echo "READYOVERLAP DRIFT FIND FAIL (the ready∩ready overlap must be reported)"; exit 1; }
    ( "$SELF" drift --strict > "$T/ro2.out" 2>&1 ) && { echo "READYOVERLAP STRICT RC FAIL (--strict must exit nonzero on an overlap)"; exit 1; }
    grep -q 'OWNERSHIP OVERLAP' "$T/ro2.out" || { cat "$T/ro2.out"; echo "READYOVERLAP STRICT FIND FAIL (the failing exit must still name the finding)"; exit 1; }
    # (2) explicit claim of the second dies `overlaps ready`, board untouched, lock released
    "$SELF" claim T-ROB > "$T/ro3.out" 2>&1 && { echo "READYOVERLAP EXPLICIT RC FAIL (an explicit overlap claim must die)"; exit 1; }
    grep -q 'overlaps ready T-ROA' "$T/ro3.out" || { cat "$T/ro3.out"; echo "READYOVERLAP EXPLICIT MSG FAIL (the die must carry the pinned overlaps ready fragment + the task)"; exit 1; }
    [ -f ops/board/ready/T-ROB.md ] || { echo "READYOVERLAP EXPLICIT BOARD FAIL (a refused claim must move nothing)"; exit 1; }
    [ -d "$(git rev-parse --git-common-dir)/polaris-locks/T-ROB" ] && { echo "READYOVERLAP EXPLICIT LOCK FAIL (the refused claim's lock must release)"; exit 1; }
    # (3) auto-pick: the top-wsjf candidate collides with ready T-ROB → parked in blocked/ with the
    #     ready-variant note + remedy, ONE board commit — and the SAME pass claims the freed second
    #     task (wsjf order holds: T-ROC stays ready).
    "$SELF" claim > "$T/ro4.out" 2>&1 || { cat "$T/ro4.out"; echo "READYOVERLAP AUTO RC FAIL (auto-pick must park the collider and keep claiming)"; exit 1; }
    [ -f ops/board/blocked/T-ROA.md ] || { echo "READYOVERLAP AUTO BLOCK FAIL (the colliding candidate must park in blocked/)"; exit 1; }
    grep -q 'overlaps ready' ops/board/blocked/T-ROA.md || { echo "READYOVERLAP AUTO VARIANT FAIL (the note must carry the ready variant, not overlaps active)"; exit 1; }
    grep -q 're-groom or wait for T-ROB' ops/board/blocked/T-ROA.md || { echo "READYOVERLAP AUTO REMEDY FAIL (the ⛔ note must carry the remedy)"; exit 1; }
    git log --format=%s refs/heads/polaris/board | grep -qx 'chore(board): block T-ROA (ownership overlap)' || { echo "READYOVERLAP AUTO COMMIT FAIL (ONE board commit, contract subject)"; exit 1; }
    [ -f ops/board/active/T-ROB.md ] || { echo "READYOVERLAP AUTO NEXT FAIL (the pass must claim the freed second task)"; exit 1; }
    [ -f ops/board/ready/T-ROC.md ] || { echo "READYOVERLAP AUTO ORDER FAIL (wsjf order must hold — T-ROC stays ready)"; exit 1; }
    # hermetic teardown
    "$SELF" release T-ROB --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-ROB.md ops/board/ready/T-ROC.md ops/board/blocked/T-ROA.md
    git branch -q -D feat/T-ROB 2>/dev/null || true
}
drill_handover() {
    # ---- T-111 handover drill (ops/contracts/role-handover.md § Executable check) ----
    # `polaris next` is the router every role follows at its boundary AND the Stop hook's oracle, so
    # a wrong line 1 misroutes a whole session and a rung that blocks where it should allow traps a
    # chat in a loop only the human can break. This walks the contract's assertion list IN ORDER on
    # the spine's own repo, judging rc and FILE STATE — never the presence of a message.
    # Contract v1.1 governs two of them: human-gated review work routes to `wait` (row 6's approval
    # note is unreachable dead source and gets no case), and `--brief` is asserted only under a live
    # lock, where the role is real and the pointer line is not in question. Contract v2 adds (8b):
    # the promote pass honours `drain: plan`, and says out loud what it refused.
    # NO helper functions here: `find --api` extracts nested fns too, and this drill ships exactly
    # one name. The hook reaches the router through POLARIS_HANDOVER_CLI rather than a forwarder
    # planted at ops/polaris, because `finish` below gates on a clean `git status` and ops/ is
    # tracked in this fixture — a planted CLI would be untracked dirt failing the step it serves.
    [ -z "$(git status --porcelain)" ] || { git status --porcelain; echo "HANDOVER PRECONDITION FAIL (the tree is dirty on entry — an upstream drill leaked; this drill proves it changes nothing, which needs a clean start)"; exit 1; }
    ho_n="$( { ls ops/board/active; ls ops/board/review; } 2>/dev/null | grep -c '\.md$' || true )"
    [ "$ho_n" = "0" ] || { "$SELF" board-fm; echo "HANDOVER PRECONDITION FAIL (active/ or review/ still holds work — this drill needs a drained board to read the router honestly)"; exit 1; }
    ho_sid0="${CLAUDE_CODE_SESSION_ID:-}"
    export CLAUDE_CODE_SESSION_ID=drill-sid
    ho_gcd="$(git rev-parse --git-common-dir)"
    ho_dir=".polaris/handover/drill-sid"
    ho_hook="$OPS_DIR/hooks/handover-hook.sh"
    ho_tr="$T/ho-tr/session.jsonl"
    mkdir -p "$T/ho-tr"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}\n' > "$ho_tr"
    ho_json="{\"session_id\":\"drill-sid\",\"transcript_path\":\"$ho_tr\",\"cwd\":\"$PWD\",\"stop_hook_active\":false,\"hook_event_name\":\"Stop\"}"
    ho_jsont="{\"session_id\":\"drill-sid\",\"transcript_path\":\"$ho_tr\",\"cwd\":\"$PWD\",\"stop_hook_active\":true,\"hook_event_name\":\"Stop\"}"
    if [ -f ops/SPRINT.md ]; then cp ops/SPRINT.md "$T/ho-sprint.bak"; else rm -f "$T/ho-sprint.bak"; fi
    printf '# SPRINT 14 — handover drill  capacity: 5\n' > ops/SPRINT.md   # moved set: disk-only, ignored on base
    # (11) and (15)/(16) below OVERWRITE ops/CONVENTIONS.md to drive the knobs, so record here
    # whether it was there at all when we arrived — the same entry snapshot busyint, selfland and
    # wtreap take. SPRINT.md is gitignored and only has to come back for the drills after us;
    # CONVENTIONS.md is TRACKED from drill_express onward (that drill commits it), so the teardown's
    # old unconditional `rm -f` left the full run a tracked file short and the hermetic assertion at
    # the bottom — correctly — fired on it. Absent at entry (any --only partition that skips
    # express) means absent at exit: no snapshot file, and the restore removes it.
    if [ -f ops/CONVENTIONS.md ]; then cp ops/CONVENTIONS.md "$T/ho-conv.bak"; else rm -f "$T/ho-conv.bak"; fi
    # (1) the router is documented. cli-docs-parity counts it too; here it is the precondition for
    #     every role's boundary instruction actually being runnable.
    "$SELF" help | grep -q '^  next ' || { echo "HANDOVER HELP FAIL (next missing from help — every role file tells the session to run it)"; exit 1; }
    # (2) row 3: the only ready task, and the SHAPE — line 1 is the whole decision, everything under
    #     it is a three-space note, so a caller branches on line 1 without parsing.
    printf -- '---\nid: T-HO1\ntitle: hand over one\ntype: feature\nscope: src\npoints: 1\nwsjf: 7\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/ho1.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-HO1.md
    "$SELF" next > "$T/ho1.out" 2>&1 || { cat "$T/ho1.out"; echo "HANDOVER NEXT RC FAIL (the router must exit 0 on every board state)"; exit 1; }
    [ "$(sed -n 1p "$T/ho1.out")" = "build T-HO1" ] || { cat "$T/ho1.out"; echo "HANDOVER BUILD FAIL (row 3 must name the only claimable ready task)"; exit 1; }
    [ "$(sed -n '2,$p' "$T/ho1.out" | grep -cv '^   ')" = "0" ] || { cat "$T/ho1.out"; echo "HANDOVER SHAPE FAIL (every line under line 1 must be a three-space note)"; exit 1; }
    # (3) claim records the session state `next` and the hooks read back, and row 0 outranks it all.
    "$SELF" claim T-HO1 >/dev/null || { echo "HANDOVER CLAIM FAIL"; exit 1; }
    [ "$(tr -d ' \r\n' < "$ho_dir/task")" = "T-HO1" ] || { echo "HANDOVER TASK STATE FAIL (claim must record the task in .polaris/handover/<sid>/task)"; exit 1; }
    tr -d '\r' < "$ho_dir/last-event" | grep -qE '^[0-9]+ claim T-HO1$' || { cat "$ho_dir/last-event"; echo "HANDOVER LAST-EVENT FAIL (evt must stamp <ts> <kind> <id>)"; exit 1; }
    [ "$("$SELF" next | sed -n 1p)" = "resume T-HO1" ] || { echo "HANDOVER RESUME FAIL (row 0: my own live lock outranks every other row)"; exit 1; }
    # (4) --brief re-anchors a compacted chat: under a live lock the role is real, so role/task/next
    #     are all present. No pipe anywhere — the anchor is prose, and a table would break it.
    "$SELF" next --brief > "$T/hob.out" 2>&1 || { cat "$T/hob.out"; echo "HANDOVER BRIEF RC FAIL"; exit 1; }
    [ "$(grep -c . "$T/hob.out")" -le 8 ] || { cat "$T/hob.out"; echo "HANDOVER BRIEF LEN FAIL (--brief must stay within 8 lines)"; exit 1; }
    grep -q '^role: ' "$T/hob.out" || { cat "$T/hob.out"; echo "HANDOVER BRIEF ROLE FAIL"; exit 1; }
    grep -q '^task: T-HO1 ' "$T/hob.out" || { cat "$T/hob.out"; echo "HANDOVER BRIEF TASK FAIL (a live lock must name the task)"; exit 1; }
    grep -q '^next: ' "$T/hob.out" || { cat "$T/hob.out"; echo "HANDOVER BRIEF NEXT FAIL"; exit 1; }
    grep -q '|' "$T/hob.out" && { cat "$T/hob.out"; echo "HANDOVER BRIEF PIPE FAIL (no pipe anywhere in the anchor)"; exit 1; }
    # (5) a self-landing handoff is a COMPLETION: the done event licenses exactly one hop, and the
    #     hook hands the session the next role rather than letting the chat end mid-run.
    ( cd .polaris/wt/T-HO1 && echo ho1 > src/ho1.txt && git add -A && git commit -qm ok && "$SELF" handoff T-HO1 > "$T/ho2.out" 2>&1 ) || { cat "$T/ho2.out"; echo "HANDOVER HANDOFF RC FAIL"; exit 1; }
    [ -f ops/board/done/T-HO1.md ] || { cat "$T/ho2.out"; echo "HANDOVER SELFLAND FAIL (landing: self must carry the task to done/)"; exit 1; }
    tr -d '\r' < "$ho_dir/last-event" | grep -qE '^[0-9]+ done T-HO1$' || { cat "$ho_dir/last-event"; echo "HANDOVER DONE EVENT FAIL (the landing tail must leave a done event as last-event)"; exit 1; }
    [ "$("$SELF" next | sed -n 1p)" = "finish" ] || { "$SELF" next; echo "HANDOVER FINISH ROUTE FAIL (a drained board is the run's end)"; exit 1; }
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "block:finish" ] || { echo "HANDOVER HOOK FINISH FAIL (got '$ho_out')"; exit 1; }
    [ "$(tr -d ' \r\n' < "$ho_dir/hops")" = "1" ] || { echo "HANDOVER HOPS FAIL (a block must record the hop it spent)"; exit 1; }
    # (6) `finish` rc 0 stamps the run closed, and the ladder allows from then on — the one thing
    #     that stops a finished run being hopped back to life by its own last event.
    #     `finish` runs the suite, and drift counts a feat/<ID> branch whose task is already done as
    #     CRUFT, which reds it. Two sources of that here: a self-land BEATS its worktree seconds
    #     before `done` asks to remove it, so wt_remove refuses a live lane and the branch stays
    #     checked out; and under `--only handover` the history drills that sweep the spine's own
    #     done branches never ran. A drill honest in only one partition is not honest, so reap
    #     exactly what drift names — every DONE task's worktree, dead by definition — by clearing
    #     the beat the way wt_remove's own note prescribes and running the tidy command the product
    #     ships for it. The branch loop is the belt: a done task whose worktree is already gone.
    for ho_f in ops/board/done/*.md; do [ -e "$ho_f" ] || break
      rm -f "$ho_gcd/worktrees/$(basename "$ho_f" .md)/polaris-beat"
    done
    "$SELF" sweep --fix >/dev/null 2>&1 || true
    for ho_f in ops/board/done/*.md; do [ -e "$ho_f" ] || break
      git branch -q -D "feat/$(basename "$ho_f" .md)" 2>/dev/null || true
    done
    "$SELF" finish > "$T/ho3.out" 2>&1 || { cat "$T/ho3.out"; echo "HANDOVER FINISH RC FAIL (the board must be finishable after the self-land)"; exit 1; }
    [ -f "$ho_dir/finished" ] || { echo "HANDOVER FINISHED STAMP FAIL (finish rc 0 must stamp the state dir)"; exit 1; }
    #     the consumed rung sits ABOVE this one and the block at (5) already spent this event, so
    #     clear the hop bookkeeping to read the rung under test; the event file is backdated so
    #     "finished is newer than the event" is a stated ordering, not a same-second clock race.
    rm -f "$ho_dir/hopped-event"
    touch -t 202001010000 "$ho_dir/last-event"
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "allow:finished" ] || { echo "HANDOVER HOOK FINISHED FAIL (got '$ho_out')"; exit 1; }
    # (7) row 4 + `--do`: the ready gate decides, the board lock serializes, and the promote is
    #     asserted from the BOARD — the file moved, the event landed, the commit carries the
    #     contract's subject. The contract file appears only NOW: it is untracked, and `finish`
    #     above gates on a clean tree.
    printf '# fixture contract\n' > ops/contracts/ho.md
    printf -- '---\nid: T-HO2\ntitle: hand over two\ntype: feature\nscope: src\npoints: 1\nwsjf: 6\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\ncontract: ops/contracts/ho.md\ndepends_on: [T-HO1]\nfiles_owned:\n  - src/ho2.txt\nverify: []\n---\n## Notes\n' > ops/board/backlog/T-HO2.md
    [ "$("$SELF" next | sed -n 1p)" = "promote" ] || { "$SELF" next; echo "HANDOVER PROMOTE ROUTE FAIL (a backlog task whose dep is done must offer the promote)"; exit 1; }
    "$SELF" next --do > "$T/ho4.out" 2>&1 || { cat "$T/ho4.out"; echo "HANDOVER DO RC FAIL"; exit 1; }
    [ -f ops/board/ready/T-HO2.md ] || { cat "$T/ho4.out"; echo "HANDOVER DO MOVE FAIL (--do must move the task into ready/)"; exit 1; }
    grep -q '"ev":"promote","id":"T-HO2"' ops/board/EVENTS.ndjson || { echo "HANDOVER DO EVENT FAIL (the promote must be on the record)"; exit 1; }
    git log -1 --format=%s refs/heads/polaris/board | grep -qx 'chore(board): promote T-HO2' || { git log -1 --format=%s refs/heads/polaris/board; echo "HANDOVER DO COMMIT FAIL (ONE board commit, contract subject)"; exit 1; }
    "$SELF" next --do > "$T/ho5.out" 2>&1 || { cat "$T/ho5.out"; echo "HANDOVER DO2 RC FAIL (a promoter with nothing to do is still rc 0)"; exit 1; }
    grep -qx '   nothing to promote' "$T/ho5.out" || { cat "$T/ho5.out"; echo "HANDOVER DO2 NOTE FAIL (an idempotent --do must say so)"; exit 1; }
    # (8) disjointness at the gate: a candidate overlapping a ready task is HELD with the reason,
    #     never promoted — this is what keeps parallel builders from ever meeting on a file.
    #     T-HO3 carries NO contract on purpose: an unset contract is legal (most small tasks have
    #     no seam), so the candidate must reach the overlap check and be HELD by name — not dropped
    #     silently by the gate, absent from the eligible list and the held list both.
    printf -- '---\nid: T-HO3\ntitle: hand over three\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\ncontract:\nfiles_owned:\n  - src/ho2.txt\nverify: []\n---\n## Notes\n' > ops/board/backlog/T-HO3.md
    "$SELF" next --do > "$T/ho6.out" 2>&1 || { cat "$T/ho6.out"; echo "HANDOVER HELD RC FAIL"; exit 1; }
    grep -q "held: T-HO3 — overlaps T-HO2 on 'src/ho2.txt'" "$T/ho6.out" || { cat "$T/ho6.out"; echo "HANDOVER HELD NOTE FAIL (the hold must name the task, the collider and the pattern)"; exit 1; }
    [ -f ops/board/backlog/T-HO3.md ] || { echo "HANDOVER HELD BOARD FAIL (a held candidate must stay in backlog/)"; exit 1; }
    # (8b) contract v2: `drain: plan` authorises ONE plan per run, so the promote pass must refuse a
    #      candidate carrying a different slug — and SAY SO. One "go" is the human approving the plan
    #      in front of them, not the whole board, and a board holding two plans is where a silent
    #      adoption becomes a whole sprint of foreign work. P comes from the session `plan` file (the
    #      shape `claim` stamps) with a ready task carrying the same slug beside it. Judged from the
    #      BOARD — `ls ready/`, the promote event count, the commit count, rc — with one exception:
    #      the held line itself, which IS the feature. A candidate that vanishes from both the
    #      eligible and the held list reads as a bug in the ready gate, so the reason is the product.
    #      Then the same board under `drain: queue` promotes the very task just refused, which is
    #      what proves the hold was the knob and not an accident of the gate.
    if [ -f ops/CONVENTIONS.md ]; then cp ops/CONVENTIONS.md "$T/ho-conv2.bak"; else rm -f "$T/ho-conv2.bak"; fi
    if [ -f "$ho_dir/plan" ]; then cp "$ho_dir/plan" "$T/ho-plan.bak"; else rm -f "$T/ho-plan.bak"; fi
    { printf 'drain: plan\n'; cat "$T/ho-conv2.bak" 2>/dev/null || true; } > ops/CONVENTIONS.md
    printf 'alpha\n' > "$ho_dir/plan"
    ho_ev0="$(grep -c '"ev":"promote"' ops/board/EVENTS.ndjson || true)"
    ho_cm0="$(git rev-list --count refs/heads/polaris/board)"
    printf -- '---\nid: T-HOA\ntitle: alpha in flight\ntype: feature\nscope: src\npoints: 1\nwsjf: 9\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nplan: alpha\ncontract: ops/contracts/ho.md\nfiles_owned:\n  - src/hoa.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-HOA.md
    printf -- '---\nid: T-HOB\ntitle: alpha dependent\ntype: feature\nscope: src\npoints: 1\nwsjf: 9\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\nplan: alpha\ncontract: ops/contracts/ho.md\ndepends_on: [T-HO1]\nfiles_owned:\n  - src/hob.txt\nverify: []\n---\n## Notes\n' > ops/board/backlog/T-HOB.md
    printf -- '---\nid: T-HOC\ntitle: beta dependent\ntype: feature\nscope: src\npoints: 1\nwsjf: 8\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\nplan: beta\ncontract: ops/contracts/ho.md\ndepends_on: [T-HO1]\nfiles_owned:\n  - src/hoc.txt\nverify: []\n---\n## Notes\n' > ops/board/backlog/T-HOC.md
    printf -- '---\nid: T-HOD\ntitle: unplanned rider\ntype: feature\nscope: src\npoints: 1\nwsjf: 7\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\nplan:\ncontract: ops/contracts/ho.md\ndepends_on: [T-HO1]\nfiles_owned:\n  - src/hod.txt\nverify: []\n---\n## Notes\n' > ops/board/backlog/T-HOD.md
    "$SELF" next --do > "$T/ho12.out" 2>&1 || { cat "$T/ho12.out"; echo "HANDOVER PLAN RC FAIL (a plan-filtered promote is still rc 0)"; exit 1; }
    [ "$(ls ops/board/ready | grep -c '^T-HO[BCD]\.md$')" = "2" ] || { ls ops/board/ready; cat "$T/ho12.out"; echo "HANDOVER PLAN READY FAIL (only this run's plan and the unplanned rider may reach ready/)"; exit 1; }
    [ -f ops/board/ready/T-HOB.md ] || { cat "$T/ho12.out"; echo "HANDOVER PLAN OWN FAIL (this run's own plan must still promote)"; exit 1; }
    [ -f ops/board/ready/T-HOD.md ] || { cat "$T/ho12.out"; echo "HANDOVER PLAN RIDER FAIL (a candidate with no plan: is never foreign — riders must still flow)"; exit 1; }
    [ -f ops/board/backlog/T-HOC.md ] || { cat "$T/ho12.out"; echo "HANDOVER PLAN FOREIGN FAIL (a foreign plan's task must stay in backlog/)"; exit 1; }
    grep -q "held: T-HOC — plan beta is not this run's (alpha) — drain: plan" "$T/ho12.out" || { cat "$T/ho12.out"; echo "HANDOVER PLAN HELD FAIL (the hold must name the task, its plan and this run's — a silent drop is the bug)"; exit 1; }
    [ "$(grep -c '"ev":"promote"' ops/board/EVENTS.ndjson)" = "$(( ho_ev0 + 2 ))" ] || { echo "HANDOVER PLAN EVENT FAIL (exactly the two promotes belong on the record)"; exit 1; }
    [ "$(git rev-list --count refs/heads/polaris/board)" = "$(( ho_cm0 + 1 ))" ] || { echo "HANDOVER PLAN COMMIT FAIL (a promote pass is ONE board commit, however many tasks move)"; exit 1; }
    git log -1 --format=%s refs/heads/polaris/board | grep -qx 'chore(board): promote T-HOB T-HOD' || { git log -1 --format=%s refs/heads/polaris/board; echo "HANDOVER PLAN SUBJECT FAIL (the one commit names exactly what moved, wsjf order)"; exit 1; }
    { printf 'drain: queue\n'; cat "$T/ho-conv2.bak" 2>/dev/null || true; } > ops/CONVENTIONS.md
    "$SELF" next --do > "$T/ho13.out" 2>&1 || { cat "$T/ho13.out"; echo "HANDOVER QUEUE RC FAIL"; exit 1; }
    [ "$(ls ops/board/ready | grep -c '^T-HO[BCD]\.md$')" = "3" ] || { ls ops/board/ready; cat "$T/ho13.out"; echo "HANDOVER QUEUE FAIL (drain: queue filters no plan at all — the hold was the knob)"; exit 1; }
    [ "$(grep -c '"ev":"promote"' ops/board/EVENTS.ndjson)" = "$(( ho_ev0 + 3 ))" ] || { echo "HANDOVER QUEUE EVENT FAIL (the task held a moment ago must now be on the record)"; exit 1; }
    grep -q "is not this run's" "$T/ho13.out" && { cat "$T/ho13.out"; echo "HANDOVER QUEUE HELD FAIL (drain: queue must hold nothing on plan)"; exit 1; }
    rm -f ops/board/ready/T-HOA.md ops/board/ready/T-HOB.md ops/board/ready/T-HOC.md ops/board/ready/T-HOD.md
    if [ -f "$T/ho-conv2.bak" ]; then cp "$T/ho-conv2.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    if [ -f "$T/ho-plan.bak" ]; then cp "$T/ho-plan.bak" "$ho_dir/plan"; else rm -f "$ho_dir/plan"; fi
    rm -f "$T/ho-conv2.bak" "$T/ho-plan.bak"
    # (9) ONE EVENT, ONE HOP — by string equality, so a second stop on the same completion allows.
    printf '%s done T-HO1\n' "$(date +%s)" > "$ho_dir/last-event"
    rm -f "$ho_dir/hopped-event"
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "block:build" ] || { echo "HANDOVER HOOK BUILD FAIL (got '$ho_out')"; exit 1; }
    [ "$(tr -d ' \r\n' < "$ho_dir/hops")" = "2" ] || { echo "HANDOVER HOPS2 FAIL (the second block must spend the second hop)"; exit 1; }
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "allow:consumed" ] || { echo "HANDOVER HOOK CONSUMED FAIL (got '$ho_out')"; exit 1; }
    # (10) the avoid list stops the ping-pong: a task this session just put down is never the task
    #      the router hands it straight back.
    "$SELF" claim T-HO2 >/dev/null || { echo "HANDOVER RECLAIM FAIL"; exit 1; }
    "$SELF" release T-HO2 --to ready -m drill >/dev/null || { echo "HANDOVER RELEASE FAIL"; exit 1; }
    grep -qx 'T-HO2' "$ho_dir/avoid" || { cat "$ho_dir/avoid" 2>/dev/null; echo "HANDOVER AVOID FAIL (a release must add the ID to this session's avoid list)"; exit 1; }
    [ "$("$SELF" next | sed -n 1p)" != "build T-HO2" ] || { echo "HANDOVER AVOID ROUTE FAIL (an avoided task must not be handed straight back)"; exit 1; }
    # (11) row 2: the budget stops only what would otherwise start, and the hook allows at the cap —
    #      a run ends where the human set it, never because a hook refused to let go.
    printf 'handover: auto\nrun_max_tasks: 3\n' > ops/CONVENTIONS.md
    printf -- '---\nid: T-HO4\ntitle: hand over four\ntype: feature\nscope: src\npoints: 1\nwsjf: 4\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/ho.md\nfiles_owned:\n  - src/ho4.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-HO4.md
    printf '3\n' > "$ho_dir/hops"
    "$SELF" next > "$T/ho7.out" 2>&1 || { cat "$T/ho7.out"; echo "HANDOVER STOP RC FAIL"; exit 1; }
    [ "$(sed -n 1p "$T/ho7.out")" = "stop" ] || { cat "$T/ho7.out"; echo "HANDOVER STOP FAIL (row 2 must pre-empt the build it would otherwise have named)"; exit 1; }
    grep -q '^   budget: run_max_tasks reached — ' "$T/ho7.out" || { cat "$T/ho7.out"; echo "HANDOVER STOP NOTE FAIL (the note must name the cap KEY, never a number of its own)"; exit 1; }
    printf '%s done T-HO1\n' "$(date +%s)" > "$ho_dir/last-event"; rm -f "$ho_dir/hopped-event"
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "allow:cap" ] || { echo "HANDOVER HOOK CAP FAIL (got '$ho_out')"; exit 1; }
    # (12) row 5: someone else's lane is work in flight, so the answer is wait — not a second claim.
    mv ops/board/ready/T-HO4.md ops/board/active/T-HO4.md
    mkdir -p "$ho_gcd/polaris-locks/T-HO4"
    printf '%s\nsomeone\nT-HO4\nother-sid\n-\n' "$(date +%s)" > "$ho_gcd/polaris-locks/T-HO4/meta"
    rm -f "$ho_dir/hops"
    "$SELF" next > "$T/ho8.out" 2>&1 || { cat "$T/ho8.out"; echo "HANDOVER WAIT RC FAIL"; exit 1; }
    [ "$(sed -n 1p "$T/ho8.out")" = "wait" ] || { cat "$T/ho8.out"; echo "HANDOVER WAIT FAIL (a foreign lock on an active task is work in flight)"; exit 1; }
    grep -qx '   active: T-HO4' "$T/ho8.out" || { cat "$T/ho8.out"; echo "HANDOVER WAIT NOTE FAIL"; exit 1; }
    # (13) the lease IS the integrator: live and foreign closes the lane, stealably stale reopens it.
    printf -- '---\nid: T-HO5\ntitle: hand over five\ntype: feature\nscope: src\npoints: 1\nwsjf: 3\nrisk: normal\nowner: null\nbranch: null\nstatus: review\ncontract: ops/contracts/ho.md\nfiles_owned:\n  - src/ho5.txt\nverify: []\n---\n## Notes\n' > ops/board/review/T-HO5.md
    mkdir -p "$ho_gcd/polaris-locks/.int-lease"
    printf 'other-agent\n' > "$ho_gcd/polaris-locks/.int-lease/who"
    printf '99999\n' > "$ho_gcd/polaris-locks/.int-lease/pid"
    printf '%s\n' "$(date +%s)" > "$ho_gcd/polaris-locks/.int-lease/epoch"
    "$SELF" next > "$T/ho9.out" 2>&1 || { cat "$T/ho9.out"; echo "HANDOVER LEASE RC FAIL"; exit 1; }
    [ "$(sed -n 1p "$T/ho9.out")" = "wait" ] || { cat "$T/ho9.out"; echo "HANDOVER LEASE LIVE FAIL (a live foreign lease closes the lane)"; exit 1; }
    grep -q '^   lease: other-agent ' "$T/ho9.out" || { cat "$T/ho9.out"; echo "HANDOVER LEASE NOTE FAIL (the wait must name who holds it)"; exit 1; }
    printf '%s\n' "$(( $(date +%s) - 9000 ))" > "$ho_gcd/polaris-locks/.int-lease/epoch"
    "$SELF" next > "$T/ho10.out" 2>&1 || { cat "$T/ho10.out"; echo "HANDOVER LEASE STALE RC FAIL"; exit 1; }
    [ "$(sed -n 1p "$T/ho10.out")" = "integrate" ] || { cat "$T/ho10.out"; echo "HANDOVER LEASE STALE FAIL (a stealable lease reopens the lane)"; exit 1; }
    grep -qx '   review/: T-HO5' "$T/ho10.out" || { cat "$T/ho10.out"; echo "HANDOVER INTEGRATE NOTE FAIL"; exit 1; }
    rm -rf "$ho_gcd/polaris-locks/.int-lease"
    # (14) contract v1.1: human-gated review work ALONE is `wait` with the human named — NEVER
    #      `finish`. A task waiting on a human is in flight, with the human; row 6's approval note
    #      is unreachable dead source and gets no case at all.
    rm -f ops/board/review/T-HO5.md ops/board/active/T-HO4.md
    rm -rf "$ho_gcd/polaris-locks/T-HO4"
    printf -- '---\nid: T-HO6\ntitle: hand over six\ntype: feature\nscope: src\npoints: 1\nwsjf: 2\nrisk: high\nowner: null\nbranch: null\nstatus: review\ncontract: ops/contracts/ho.md\nfiles_owned:\n  - src/ho6.txt\nverify: []\n---\n## Notes\n' > ops/board/review/T-HO6.md
    "$SELF" next > "$T/ho11.out" 2>&1 || { cat "$T/ho11.out"; echo "HANDOVER HUMAN RC FAIL"; exit 1; }
    [ "$(sed -n 1p "$T/ho11.out")" = "wait" ] || { cat "$T/ho11.out"; echo "HANDOVER HUMAN-GATED FAIL (role-handover.md v1.1: human-gated review alone is wait, never finish)"; exit 1; }
    grep -qx '   review/ awaits a human: T-HO6' "$T/ho11.out" || { cat "$T/ho11.out"; echo "HANDOVER HUMAN NOTE FAIL"; exit 1; }
    # (15) `handover: off` allows before any fork — the knob is the whole opt-out, and it is read
    #      from CONVENTIONS with sed, never by paying for a CLI startup on the allow path.
    printf 'handover: off\nrun_max_tasks: 3\n' > ops/CONVENTIONS.md
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "allow:off" ] || { echo "HANDOVER HOOK OFF FAIL (got '$ho_out')"; exit 1; }
    # (16) the harness's own consecutive-block cap outranks ours: stop_hook_active means let go.
    printf 'handover: auto\nrun_max_tasks: 0\n' > ops/CONVENTIONS.md
    ho_out="$(printf '%s' "$ho_jsont" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "allow:harness-cap" ] || { echo "HANDOVER HOOK HARNESS FAIL (got '$ho_out')"; exit 1; }
    # (17) a subagent's completion lands in the PARENT's state dir, so a conductor whose builders
    #      just handed off must never be hopped into BUILDER itself. The event file is backdated so
    #      the freshness comparison is decided by a stated ordering, not by a clock race.
    rm -f "$ho_dir/finished"
    touch -t 202001010000 "$ho_dir/last-event"
    mkdir -p "$T/ho-tr/drill-sid/subagents"
    printf '{}\n' > "$T/ho-tr/drill-sid/subagents/x.jsonl"
    ho_out="$(printf '%s' "$ho_json" | POLARIS_HANDOVER_CLI="$SELF" bash "$ho_hook" --test stop)"
    [ "$ho_out" = "allow:subagent" ] || { echo "HANDOVER HOOK SUBAGENT FAIL (got '$ho_out')"; exit 1; }
    # hermetic teardown: the board drained, the ONE file this drill created (ops/contracts/ho.md)
    # gone, CONVENTIONS + SPRINT put back the way we found them — restored, never deleted: whether
    # CONVENTIONS.md is tracked here depends on which drills ran before us, and only the entry
    # snapshot knows — the session state removed, the sid handed back to whatever runs next, and the
    # tree byte-identical to the way we found it.
    rm -f ops/board/review/T-HO6.md ops/board/ready/T-HO2.md ops/board/backlog/T-HO3.md ops/board/done/T-HO1.md
    rm -rf "$ho_gcd/polaris-locks/T-HO2" "$ho_gcd/polaris-locks/T-HO4" "$ho_gcd/polaris-locks/.int-lease"
    rm -rf "$ho_dir" "$T/ho-tr"
    rm -f .polaris/finish-stamp ops/contracts/ho.md
    git branch -q -D feat/T-HO2 2>/dev/null || true
    # CONVENTIONS.md: put back what HEAD holds, not the byte copy. The neighbours that save/restore
    # this file by `cp` all COMMIT afterwards, which is what makes their trees clean; this drill must
    # not commit anything — proving it changes nothing is the whole point — so it restores through
    # git instead, which is the one form that leaves `git status` with nothing to say. The entry
    # backup is still the record of whether the file existed at all when we arrived (any --only
    # partition that never tracked it) and the fallback if HEAD no longer carries it.
    if [ -f "$T/ho-conv.bak" ]; then git checkout -q HEAD -- ops/CONVENTIONS.md 2>/dev/null || cp "$T/ho-conv.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    if [ -f "$T/ho-sprint.bak" ]; then cp "$T/ho-sprint.bak" ops/SPRINT.md; else rm -f ops/SPRINT.md; fi
    rm -f "$T/ho-conv.bak" "$T/ho-sprint.bak"
    if [ -n "$ho_sid0" ]; then export CLAUDE_CODE_SESSION_ID="$ho_sid0"; else unset CLAUDE_CODE_SESSION_ID; fi
    [ -z "$(git status --porcelain)" ] || { git status --porcelain; echo "HANDOVER HERMETIC FAIL (the drill must leave the tree exactly as it found it)"; exit 1; }
}
