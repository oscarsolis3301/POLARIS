# lib/selftest/remote.sh — selftest drills: remote syncrace notify upgrade. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_remote() {
    # --- v5.11: remote hygiene — done deletes the pushed feat branch; sweep --fix removes strays
    # (T-C is deliberately merged --no-ff, NOT landed: it is the ONE legacy drill proving the
    #  gate's rule-2 fallback — hand merges per MANUAL.md still pass done + remote cleanup.)
    ensure_origin   # T-033: scratch bare origin (self-provisions under --only remote; spine no longer)
    printf -- '---\nid: T-C\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/c.txt\nverify: []\n---\n' > ops/board/ready/T-C.md
    "$SELF" claim T-C >/dev/null
    ( cd .polaris/wt/T-C && echo c > src/c.txt && git add -A && git commit -qm ok && "$SELF" handoff T-C >/dev/null )
    git ls-remote --exit-code origin refs/heads/feat/T-C >/dev/null || { echo "REMOTE PUSH FAIL (handoff must push feat branch)"; exit 1; }
    git merge -q --no-ff feat/T-C -m merge
    "$SELF" done T-C >/dev/null
    git ls-remote --exit-code origin refs/heads/feat/T-C >/dev/null 2>&1 && { echo "REMOTE CLEANUP FAIL (done must delete the origin branch)"; exit 1; }
    git push -q origin main:refs/heads/feat/T-C     # resurrect a merged stray, as a pre-5.11 board would have left it
    "$SELF" sweep | grep -q 'REMOTE stray: feat/T-C' || { echo "SWEEP STRAY FAIL"; exit 1; }
    "$SELF" sweep --fix >/dev/null
    git ls-remote --exit-code origin refs/heads/feat/T-C >/dev/null 2>&1 && { echo "SWEEP FIX FAIL (merged stray must be deleted)"; exit 1; }
    # --- v5.13 T-024: sweep flags a MERGED integrate/* branch as a stray (--fix deletes it) but
    # KEEPS a diverged one (tip not in $BASE). Same bare origin as the feat/* drill above.
    git push -q origin main:refs/heads/integrate/2030-01-01                                  # merged wave: tip is in main
    idvg="$(git commit-tree "$(git rev-parse 'main^{tree}')" -p main -m 'diverged wave')"    # a child of main → tip NOT in main
    git push -q origin "$idvg:refs/heads/integrate/2030-02-02"
    "$SELF" sweep > "$T/isweep.out"
    grep -q 'REMOTE stray: integrate/2030-01-01' "$T/isweep.out" || { echo "SWEEP INTEGRATE STRAY FAIL (merged wave must flag)"; exit 1; }
    grep -q 'REMOTE diverged: integrate/2030-02-02' "$T/isweep.out" || { echo "SWEEP INTEGRATE DIVERGED FAIL (unmerged wave must flag)"; exit 1; }
    "$SELF" sweep --fix >/dev/null
    git ls-remote --exit-code origin refs/heads/integrate/2030-01-01 >/dev/null 2>&1 && { echo "SWEEP INTEGRATE FIX FAIL (merged wave must be deleted)"; exit 1; }
    git ls-remote --exit-code origin refs/heads/integrate/2030-02-02 >/dev/null || { echo "SWEEP INTEGRATE KEEP FAIL (diverged wave must be kept)"; exit 1; }
    git push -q origin :refs/heads/integrate/2030-02-02    # clean up so later drills see a bare origin
}
drill_syncrace() {
    ensure_origin   # T-033: --only syncrace skips the remote drill above — self-provision origin (+ polaris/board)
    # ============ T-020 quiet-board sync race (EVENTS union — ops/contracts/quiet-board.md) ============
    # origin/polaris/board moves AHEAD with a foreign machine's EVENTS line; the next local
    # mutation's push is rejected → sync_board must union the line into the on-disk file,
    # re-parent on the fetched tip, and land the push — no line lost to the race.
    git clone -q "$T/origin.git" "$T/peer" 2>/dev/null   # bare origin's HEAD names no branch — harmless
    ( cd "$T/peer" && git config user.email p@p && git config user.name p
      ptip="$(git rev-parse origin/polaris/board)"
      git cat-file -p "$ptip:ops/board/EVENTS.ndjson" > "$T/peer.ev"
      printf '{"ts":1,"ev":"claim","id":"T-PEER","who":"peer","note":""}\n' >> "$T/peer.ev"
      pblob="$(git hash-object -w "$T/peer.ev" 2>/dev/null)"
      GIT_INDEX_FILE="$T/peer.idx" git read-tree "$ptip"
      GIT_INDEX_FILE="$T/peer.idx" git update-index --add --cacheinfo "100644,$pblob,ops/board/EVENTS.ndjson"
      ptree="$(GIT_INDEX_FILE="$T/peer.idx" git write-tree)"
      pnew="$(git commit-tree "$ptree" -p "$ptip" -m 'chore(board): peer claim')"
      git push -q origin "$pnew:refs/heads/polaris/board" ) || { echo "SYNC RACE SETUP FAIL"; exit 1; }
    printf -- '---\nid: T-Q\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/q.txt\nverify: []\n---\n' > ops/board/ready/T-Q.md
    "$SELF" claim T-Q >/dev/null || { echo "SYNC RACE CLAIM FAIL (rejected push must recover via union + re-parent)"; exit 1; }
    grep -q '"id":"T-PEER"' ops/board/EVENTS.ndjson || { echo "SYNC UNION FAIL (remote-only EVENTS line must append locally)"; exit 1; }
    [ "$(git ls-remote origin refs/heads/polaris/board | cut -f1)" = "$(git rev-parse refs/heads/polaris/board)" ] \
      || { echo "SYNC PUSH FAIL (local polaris/board must land on origin)"; exit 1; }
    git log -1 --format=%s refs/heads/polaris/board | grep -qx 'chore(board): claim T-Q' || { echo "SYNC SUBJECT FAIL (re-parented commit must keep its subject)"; exit 1; }
    "$SELF" release T-Q --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-Q.md
    # ============ end T-020 quiet-board sync race ============
}
drill_notify() {
    # ================== v5.13 notify v2 drills (hands-free-knobs) ==================
    # shim listed in help · no notify: configured → rc 0 and SILENT · unknown/missing kind (and a
    # missing required ID) → usage error, rc≠0
    "$SELF" help | grep -q 'notify-gate' || { echo "USAGE FAIL: notify-gate missing from help"; exit 1; }
    "$SELF" notify-gate plan > "$T/ng.out" 2>&1 || { echo "NOTIFY-GATE RC FAIL (no hook must rc 0)"; exit 1; }
    [ -s "$T/ng.out" ] && { echo "NOTIFY-GATE SILENCE FAIL (no hook must print nothing)"; exit 1; }
    "$SELF" notify-gate bogus >/dev/null 2>&1 && { echo "NOTIFY-GATE KIND FAIL (unknown kind must rc!=0)"; exit 1; }
    "$SELF" notify-gate >/dev/null 2>&1 && { echo "NOTIFY-GATE KIND FAIL (missing kind must rc!=0)"; exit 1; }
    "$SELF" notify-gate risk >/dev/null 2>&1 && { echo "NOTIFY-GATE ID FAIL (risk without ID must rc!=0)"; exit 1; }
    # a notify: hook that logs its env as EV/SEVERITY/ID/NOTE lines. The shim BACKGROUNDS the
    # hook, so every assertion polls for its line (bounded, ≤2s) — never races it.
    printf 'notify: printf "%%s/%%s/%%s/%%s\\n" "$POLARIS_EV" "$POLARIS_SEVERITY" "$POLARIS_ID" "$POLARIS_NOTE" >> %s\n' "$T/notify.log" > ops/CONVENTIONS.md
    git add -A; git commit -qm notify-hook
    evn="$(wc -l < ops/board/EVENTS.ndjson)"
    "$SELF" notify-gate plan
    "$SELF" notify-gate risk T-42
    "$SELF" notify-gate question T-43
    "$SELF" notify-gate done
    ngwait '^waiting/gate//plan-gate$' || { echo "NOTIFY-GATE PLAN FAIL (waiting/gate env line missing)"; exit 1; }
    ngwait '^waiting/gate/T-42/risk-approval$' || { echo "NOTIFY-GATE RISK FAIL (waiting/gate/<ID> env line missing)"; exit 1; }
    ngwait '^waiting/gate/T-43/builder-question$' || { echo "NOTIFY-GATE QUESTION FAIL"; exit 1; }
    ngwait '^run-done/done//run-done$' || { echo "NOTIFY-GATE DONE FAIL (run-done/done env line missing)"; exit 1; }
    [ "$(wc -l < ops/board/EVENTS.ndjson)" = "$evn" ] || { echo "NOTIFY-GATE EVENTS FAIL (shim must never append EVENTS.ndjson)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "NOTIFY-GATE CLEAN FAIL (shim must never touch the work tree)"; exit 1; }
    # blocked is a distinct board event: --to blocked → ev "blocked" + SEVERITY=gate at the hook ·
    # an ordinary event (claim) carries SEVERITY=info · --to ready keeps ev "release" · `why`
    # surfaces blocked lines as bounce history
    printf -- '---\nid: T-D\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/d.txt\nverify: []\n---\n' > ops/board/ready/T-D.md
    "$SELF" claim T-D >/dev/null
    ngwait '^claim/info/T-D/' || { echo "SEVERITY INFO FAIL (ordinary event must export SEVERITY=info)"; exit 1; }
    "$SELF" release T-D --to blocked -m stuck >/dev/null
    grep -q '"ev":"blocked","id":"T-D"' ops/board/EVENTS.ndjson || { echo "BLOCKED EVENT FAIL (--to blocked must emit ev blocked)"; exit 1; }
    ngwait '^blocked/gate/T-D/' || { echo "SEVERITY GATE FAIL (blocked must export SEVERITY=gate)"; exit 1; }
    "$SELF" why T-D | grep -q 'ago  blocked' || { echo "WHY BLOCKED FAIL (why must surface blocked telemetry lines)"; exit 1; }
    printf -- '---\nid: T-E\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/e.txt\nverify: []\n---\n' > ops/board/ready/T-E.md
    "$SELF" claim T-E >/dev/null
    "$SELF" release T-E --to ready -m drill >/dev/null
    grep -q '"ev":"release","id":"T-E"' ops/board/EVENTS.ndjson || { echo "RELEASE EVENT FAIL (--to ready must keep ev release)"; exit 1; }
    grep -q '"ev":"blocked","id":"T-E"' ops/board/EVENTS.ndjson && { echo "RELEASE EVENT FAIL (--to ready must not emit blocked)"; exit 1; }
    rm -f ops/board/blocked/T-D.md ops/board/ready/T-E.md
    # doctor knob awareness: explicit knob beats autonomy: trusted, trusted fills the unset
    # knobs, unknown values warn and behave as the default
    printf 'autonomy: trusted\nplan_gate: confirm\ndrain: bogus\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/doc.out" 2>&1 || { echo "DOCTOR KNOB RC FAIL"; exit 1; }
    grep -q 'plan_gate=confirm' "$T/doc.out" || { echo "KNOB PRECEDENCE FAIL (explicit knob must beat autonomy: trusted)"; exit 1; }
    grep -q 'builder_questions=default-safe' "$T/doc.out" || { echo "KNOB TRUSTED FAIL (autonomy: trusted must fill unset knobs)"; exit 1; }
    grep -q "drain: 'bogus' unknown" "$T/doc.out" || { echo "KNOB WARN FAIL (unknown value must warn + behave as default)"; exit 1; }
    git checkout -q -- ops/CONVENTIONS.md
}
drill_upgrade() {
    # ================== T-021 upgrade-migration drill (ops/contracts/quiet-board.md) ==================
    # A 5.13-shaped repo: moved set TRACKED on base, chore(board) history on base, no polaris/board.
    # upgrade must migrate ONCE (orphan seed → untrack → ignore → ONE base commit), re-run as a
    # no-op, and the board must run QUIET afterwards. Then: claim/resume print PRIMARY-anchored
    # task paths · a fresh clone materializes the board via doctor and via resume · uninstall
    # deletes the board-history branch locally and on origin.
    git init -q -b main "$T/mig" 2>/dev/null || { git init -q "$T/mig"; git -C "$T/mig" symbolic-ref HEAD refs/heads/main; }
    ( set -e; cd "$T/mig"; git config user.email t@t; git config user.name t
      mkdir -p src ops/board/ready ops/board/active ops/board/review ops/board/done ops/board/blocked ops/board/backlog
      echo x > src/m0.txt
      : > ops/board/EVENTS.ndjson
      printf '# SPRINT 0 — migration drill  capacity: 1\n' > ops/SPRINT.md
      printf -- '---\nid: T-M\ntitle: migrated task\ntype: feature\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/m.txt\nverify: []\n---\n' > ops/board/ready/T-M.md
      git add -A; git commit -qm init
      echo bump >> ops/SPRINT.md; git add -A; git commit -qm 'chore(board): claim T-OLD'   # 5.13-shaped: tracked set, chore history on base
      pre="$(git rev-list --count main)"
      "$SELF" upgrade > "$T/mig-up.out" 2>&1 || { cat "$T/mig-up.out"; echo "MIGRATION RUN FAIL"; exit 1; }
      git rev-parse -q --verify refs/heads/polaris/board >/dev/null || { echo "MIGRATION REF FAIL (upgrade must seed polaris/board)"; exit 1; }
      git ls-tree -r --name-only refs/heads/polaris/board | grep -qx 'ops/board/ready/T-M.md' || { echo "MIGRATION SEED FAIL (current board state must ride the orphan seed)"; exit 1; }
      git ls-tree -r --name-only refs/heads/polaris/board | grep -v '^ops/board/' | grep -v '^ops/SPRINT\.md$' | grep -q . && { echo "MIGRATION TREE FAIL (seed tree = ONLY the moved set)"; exit 1; }
      [ "$(git rev-list --max-parents=0 refs/heads/polaris/board | wc -l | tr -d ' ')" = "1" ] || { echo "MIGRATION ORPHAN FAIL"; exit 1; }
      [ -z "$(git ls-files -- ops/board ops/SPRINT.md)" ] || { echo "MIGRATION UNTRACK FAIL (the set must leave the base index)"; exit 1; }
      git check-ignore -q ops/SPRINT.md && git check-ignore -q ops/board/ready/T-M.md || { echo "MIGRATION IGNORE FAIL"; exit 1; }
      [ "$(git rev-list --count main)" = "$((pre+1))" ] || { echo "MIGRATION COMMIT COUNT FAIL (exactly ONE new base commit)"; exit 1; }
      git log -1 --format=%s main | grep -qx 'chore(board): board moves to polaris/board' || { echo "MIGRATION SUBJECT FAIL"; exit 1; }
      mig="$(git rev-parse main)"; mtip="$(git rev-parse refs/heads/polaris/board)"
      "$SELF" upgrade > "$T/mig-up2.out" 2>&1 || { cat "$T/mig-up2.out"; echo "MIGRATION RERUN FAIL"; exit 1; }
      [ "$(git rev-parse main)" = "$mig" ] || { echo "MIGRATION IDEMPOTENT FAIL (re-run must add no base commit)"; exit 1; }
      [ "$(git rev-parse refs/heads/polaris/board)" = "$mtip" ] || { echo "MIGRATION IDEMPOTENT FAIL (re-run must not move the ref)"; exit 1; }
      # claim/resume on the migrated board: green, and the printed task path is PRIMARY-anchored
      # (the worktree contains no ops/board). mp = PRIMARY exactly as the script computes it.
      mp="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
      "$SELF" claim T-M > "$T/mig-claim.out" || { echo "MIGRATED CLAIM FAIL"; exit 1; }
      grep -qF "task file at \"$mp/ops/board/active/T-M.md\"" "$T/mig-claim.out" || { echo "CLAIM PATH FAIL (read: hint must name the primary-anchored task file)"; exit 1; }
      "$SELF" resume T-M > "$T/mig-resume.out" || { echo "MIGRATED RESUME FAIL"; exit 1; }
      grep -qF "task file: \"$mp/ops/board/active/T-M.md\"" "$T/mig-resume.out" || { echo "RESUME PATH FAIL (resume must print the primary-anchored task file)"; exit 1; }
      # fresh clones: doctor materializes the board from origin's ref (creating the local ref);
      # resume does the same BEFORE its task lookup — an active task survives the machine hop.
      git clone -q . "$T/mig2" 2>/dev/null
      ( set -e; cd "$T/mig2"; git config user.email t@t; git config user.name t
        [ ! -d ops/board ] || { echo "CLONE SHAPE FAIL (moved set must be absent from a fresh clone)"; exit 1; }
        "$SELF" doctor > "$T/mig-doc.out" 2>&1 || { cat "$T/mig-doc.out"; echo "DOCTOR MATERIALIZE RC FAIL"; exit 1; }
        grep -q 'materialized ops/board/' "$T/mig-doc.out" || { echo "DOCTOR MATERIALIZE SAY FAIL (doctor must say what it did)"; exit 1; }
        [ -f ops/board/active/T-M.md ] && [ -f ops/SPRINT.md ] || { echo "DOCTOR MATERIALIZE FAIL (moved set must land on disk)"; exit 1; }
        git rev-parse -q --verify refs/heads/polaris/board >/dev/null || { echo "DOCTOR REF FAIL (local ref must be created from origin's)"; exit 1; } ) || exit 1
      git clone -q . "$T/mig3" 2>/dev/null
      ( set -e; cd "$T/mig3"; git config user.email t@t; git config user.name t
        "$SELF" resume T-M >/dev/null 2>&1 || { echo "RESUME MATERIALIZE FAIL (fresh clone must resume an active task)"; exit 1; }
        [ -f ops/board/active/T-M.md ] || { echo "RESUME MATERIALIZE DISK FAIL"; exit 1; } ) || exit 1
      # quiet after migration: handoff → legacy merge → done; base first-parent gains ZERO
      # chore(board) commits after the migration commit (the migration commit is the LAST)
      ( set -e; cd .polaris/wt/T-M; echo m > src/m.txt; git add -A; git commit -qm ok
        "$SELF" handoff T-M >/dev/null ) || exit 1
      git merge -q --no-ff feat/T-M -m merge
      "$SELF" done T-M >/dev/null || { echo "MIGRATED DONE FAIL"; exit 1; }
      git log --first-parent --format=%s "$mig..main" | grep -q '^chore(board):' && { echo "MIGRATED QUIET FAIL (no chore(board) on base after the migration commit)"; exit 1; }
      # uninstall: names the branch pre-confirm, deletes it locally AND on origin
      git init -q --bare "$T/mig-origin.git"
      git remote add origin "$T/mig-origin.git"
      git push -q origin main refs/heads/polaris/board
      "$SELF" uninstall > "$T/mig-un.out" 2>&1 && { echo "UNINSTALL CONFIRM FAIL (no --yes must refuse)"; exit 1; }
      grep -q 'polaris/board' "$T/mig-un.out" || { echo "UNINSTALL SUMMARY FAIL (pre-confirm must name the board-history branch)"; exit 1; }
      "$SELF" uninstall --yes > "$T/mig-un2.out" 2>&1 || { cat "$T/mig-un2.out"; echo "UNINSTALL RUN FAIL"; exit 1; }
      git rev-parse -q --verify refs/heads/polaris/board >/dev/null && { echo "UNINSTALL LOCAL REF FAIL (the branch must be deleted)"; exit 1; }
      git ls-remote "$T/mig-origin.git" refs/heads/polaris/board | grep -q . && { echo "UNINSTALL REMOTE REF FAIL (the deletion must push)"; exit 1; }
      : ) || exit 1
}
