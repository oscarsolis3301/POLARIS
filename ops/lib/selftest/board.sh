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
