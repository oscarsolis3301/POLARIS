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
drill_grant() {
    # ================== T-005 grant drills (ops/contracts/grant.md) ==================
    # sanctioned files_owned amendment: refusals (wrong column · missing -m · overlap, each
    # mutating NOTHING) then one success = append + Notes line + event + ONE board commit.
    "$SELF" help | grep -q 'grant' || { echo "USAGE FAIL: grant missing from help"; exit 1; }
    printf -- '---\nid: T-G\npoints: 1\nwsjf: 6\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/g.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-G.md
    printf -- '---\nid: T-H\npoints: 1\nwsjf: 1\nstatus: ready\nfiles_owned:\n  - src/h/\n---\n' > ops/board/ready/T-H.md
    "$SELF" claim T-G >/dev/null
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
    "$SELF" release T-G --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-G.md ops/board/ready/T-H.md
    # ================== end T-005 grant drills ==================
}
