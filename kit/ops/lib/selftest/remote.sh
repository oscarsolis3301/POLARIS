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
    # ---- T-059 handoff push resilience (ops/contracts/shared-checkout.md) ----
    # (1) a stray ref literally named `feat` on origin D/F-blocks EVERY feat/<ID> push: handoff must
    # repair it BETWEEN attempts (archive as stray/feat-<sha7>, never delete) and land the push.
    printf -- '---\nid: T-PU\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/pu.txt\nverify: []\n---\n' > ops/board/ready/T-PU.md
    git push -q origin main:refs/heads/feat
    straysha="$(git rev-parse main)"
    "$SELF" claim T-PU >/dev/null
    ( cd .polaris/wt/T-PU && echo pu > src/pu.txt && git add -A && git commit -qm ok && "$SELF" handoff T-PU > "$T/pu.out" 2>&1 ) \
      || { echo "HANDOFF REPAIR RC FAIL (a stray feat ref must not sink the handoff)"; exit 1; }
    git ls-remote --exit-code origin refs/heads/feat/T-PU >/dev/null || { echo "HANDOFF REPAIR PUSH FAIL (the repaired push must land)"; exit 1; }
    git ls-remote origin refs/heads/feat | grep -q . && { echo "HANDOFF REPAIR STRAY FAIL (origin's stray feat must be archived away)"; exit 1; }
    git ls-remote --exit-code origin "refs/heads/stray/feat-$(printf '%.7s' "$straysha")" >/dev/null \
      || { echo "HANDOFF REPAIR ARCHIVE FAIL (the stray must be RENAMED to stray/feat-<sha7>, never deleted)"; exit 1; }
    grep -q 'push failed' "$T/pu.out" && { echo "HANDOFF REPAIR DEGRADE FAIL (a repaired push must not report failure)"; exit 1; }
    git merge -q --no-ff feat/T-PU -m merge
    "$SELF" done T-PU >/dev/null
    git push -q origin ":refs/heads/stray/feat-$(printf '%.7s' "$straysha")"   # bare origin for later drills
    # (2) a push that keeps failing DEGRADES: 3 attempts, then the board move PROCEEDS with the
    # contract's ⚠ Note + a push-fail event — a finished task is never stranded in active/ again.
    # (refs/heads/feat/T-PF/x on origin D/F-blocks pushing feat/T-PF while polaris/board still syncs.)
    printf -- '---\nid: T-PF\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/pf.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-PF.md
    git push -q origin main:refs/heads/feat/T-PF/x
    "$SELF" claim T-PF >/dev/null
    ( cd .polaris/wt/T-PF && echo pf > src/pf.txt && git add -A && git commit -qm ok && "$SELF" handoff T-PF > "$T/pf.out" 2>&1 ) \
      || { echo "HANDOFF DEGRADE RC FAIL (a failing push must not strand the task in active/)"; exit 1; }
    [ -f ops/board/review/T-PF.md ] || { echo "HANDOFF DEGRADE MOVE FAIL (the board move must proceed)"; exit 1; }
    grep -qxF -- '- ⚠ push failed at handoff — feat/T-PF is local-only; land merges the local branch' ops/board/review/T-PF.md \
      || { echo "HANDOFF DEGRADE NOTE FAIL (the contract Note must append to the task)"; exit 1; }
    grep -q '"ev":"push-fail","id":"T-PF"' ops/board/EVENTS.ndjson || { echo "HANDOFF DEGRADE EVENT FAIL (evt push-fail must emit)"; exit 1; }
    grep -q 'local-only' "$T/pf.out" || { echo "HANDOFF DEGRADE SAY FAIL (the degrade must say so)"; exit 1; }
    git ls-remote origin refs/heads/feat/T-PF | grep -q . && { echo "HANDOFF DEGRADE PUSH FAIL (feat/T-PF must stay local-only)"; exit 1; }
    git push -q origin ":refs/heads/feat/T-PF/x"
    git merge -q --no-ff feat/T-PF -m merge
    "$SELF" done T-PF >/dev/null
    # ---- end T-059 handoff push resilience ----
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
    # v6.0 THE FLIP (hands-free-knobs.md § v2), the release's whole claim and the one thing prose
    # cannot hold: an UNSET knob now composes the autonomous defaults, and `autonomy: standard` is
    # the one-line opt-out that restores 5.13's confirm/ask/confirm exactly.
    : > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/doc-def.out" 2>&1 || { echo "DOCTOR DEFAULT RC FAIL"; exit 1; }
    grep -q 'plan_gate=auto · builder_questions=default-safe · evolve_apply=auto-reversible' "$T/doc-def.out" \
      || { echo "KNOB DEFAULT FAIL (an empty CONVENTIONS must compose the 6.0 autonomous defaults)"; exit 1; }
    printf 'autonomy: standard\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/doc-std.out" 2>&1 || { echo "DOCTOR STANDARD RC FAIL"; exit 1; }
    grep -q 'plan_gate=confirm · builder_questions=ask · evolve_apply=confirm' "$T/doc-std.out" \
      || { echo "KNOB STANDARD FAIL (autonomy: standard must restore confirm/ask/confirm)"; exit 1; }
    # precedence's OTHER direction: an explicit knob beats `autonomy: standard` too, and standard
    # still fills the rest (the first assertion above proves explicit beating `trusted`)
    printf 'autonomy: standard\nplan_gate: auto\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/doc-mix.out" 2>&1 || { echo "DOCTOR MIX RC FAIL"; exit 1; }
    grep -q 'plan_gate=auto · builder_questions=ask · evolve_apply=confirm' "$T/doc-mix.out" \
      || { echo "KNOB PRECEDENCE FAIL (an explicit knob must beat autonomy: standard, both directions)"; exit 1; }
    # A TYPO MUST NEVER GRANT AUTONOMY. An unknown value on an individual knob falls back to that
    # knob's STANDARD value — even under `autonomy: trusted`, where both the dial AND the 6.0
    # default would otherwise say auto. Mistakes degrade toward asking the human, never toward
    # acting without them (v2 fails SAFE, deliberately diverging from v1's fail-to-default).
    printf 'autonomy: trusted\nplan_gate: bogus\nbuilder_questions: bogus\nevolve_apply: bogus\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/doc-typo.out" 2>&1 || { echo "DOCTOR TYPO RC FAIL"; exit 1; }
    grep -q 'plan_gate=confirm · builder_questions=ask · evolve_apply=confirm' "$T/doc-typo.out" \
      || { echo "KNOB TYPO FAIL (an unknown knob value must fail SAFE to standard, never grant autonomy)"; exit 1; }
    grep -q "plan_gate: 'bogus' unknown" "$T/doc-typo.out" || { echo "KNOB TYPO WARN FAIL (the safe fallback must say so)"; exit 1; }
    grep -q "builder_questions: 'bogus' unknown" "$T/doc-typo.out" || { echo "KNOB TYPO WARN FAIL (builder_questions)"; exit 1; }
    grep -q "evolve_apply: 'bogus' unknown" "$T/doc-typo.out" || { echo "KNOB TYPO WARN FAIL (evolve_apply)"; exit 1; }
    # ...and a typo in the DIAL itself degrades the same way: standard, never the autonomous default
    printf 'autonomy: trustd\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/doc-dial.out" 2>&1 || { echo "DOCTOR DIAL RC FAIL"; exit 1; }
    grep -q 'plan_gate=confirm · builder_questions=ask · evolve_apply=confirm' "$T/doc-dial.out" \
      || { echo "KNOB DIAL TYPO FAIL (an unknown autonomy: value must behave as standard)"; exit 1; }
    grep -q "autonomy: 'trustd' unknown" "$T/doc-dial.out" || { echo "KNOB DIAL WARN FAIL"; exit 1; }
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
drill_adopt() {
    # ============ T-080 adopt stub-writer drill (ops/contracts/key-registry.md § 3) ============
    # `update` refreshes kit code and NEVER rewrites CONVENTIONS.md — that is what makes updating
    # safe — so every key-gated capability ships dormant and adopt is the discovery half. Its whole
    # promise is that discovery can never become activation: it appends COMMENTED stubs and nothing
    # else. Drilled against the REAL shipped registry (kit/ops/KEYS.tsv), never a fixture — a
    # stub-writer proven only on invented keys says nothing about the file that actually ships.
    adst="$(git status --porcelain)"
    [ -f ops/CONVENTIONS.md ] && cp ops/CONVENTIONS.md "$T/ad-conv.bak" || rm -f "$T/ad-conv.bak"
    [ -f "$OPS_DIR/KEYS.tsv" ] || { echo "ADOPT REGISTRY MISSING (kit/ops/KEYS.tsv must ship)"; exit 1; }
    # the two refusals, first: no registry → die naming the remedy · no CONVENTIONS.md (INIT never
    # ran) → die, and NEVER create the file it was asked to extend
    rm -f ops/KEYS.tsv
    printf 'voice: plain\n' > ops/CONVENTIONS.md
    "$SELF" adopt > "$T/ad-nokeys.out" 2>&1 && { echo "ADOPT REGISTRY RC FAIL (no KEYS.tsv must die)"; exit 1; }
    grep -q 'polaris update' "$T/ad-nokeys.out" || { echo "ADOPT REGISTRY REMEDY FAIL (the refusal must name the remedy)"; exit 1; }
    cp "$OPS_DIR/KEYS.tsv" ops/KEYS.tsv
    rm -f ops/CONVENTIONS.md
    "$SELF" adopt > "$T/ad-noconv.out" 2>&1 && { echo "ADOPT CONV RC FAIL (no CONVENTIONS.md must die)"; exit 1; }
    [ -f ops/CONVENTIONS.md ] && { echo "ADOPT CREATE FAIL (adopt must never create CONVENTIONS.md)"; exit 1; }
    grep -q 'INIT' "$T/ad-noconv.out" || { echo "ADOPT CONV REMEDY FAIL (the refusal must point at INIT)"; exit 1; }
    # a live value AND an existing stub, both pre-set: both must survive exactly as found — the stub
    # is what says "known and deliberately unset", so re-stubbing it would itself be an edit
    printf 'voice: plain\ndrain: plan\n# builder_questions: ask   # deliberately unset\n' > ops/CONVENTIONS.md
    cp ops/CONVENTIONS.md "$T/ad-pre.md"
    adbytes="$(wc -c < "$T/ad-pre.md" | tr -d ' ')"
    "$SELF" adopt > "$T/ad1.out" 2>&1 || { cat "$T/ad1.out"; echo "ADOPT RUN RC FAIL"; exit 1; }
    # APPEND-ONLY, proven in bytes: everything that was there is still there, unchanged and in order
    head -c "$adbytes" ops/CONVENTIONS.md > "$T/ad-head"
    cmp -s "$T/ad-pre.md" "$T/ad-head" || { echo "ADOPT APPEND-ONLY FAIL (adopt must never edit, reorder or uncomment an existing line)"; exit 1; }
    # ...and nothing appended is LIVE: every added line is a comment (the blank separator aside)
    tail -c "+$((adbytes+1))" ops/CONVENTIONS.md | grep -v '^#' | grep -q . \
      && { echo "ADOPT LIVE VALUE FAIL (every appended line must be a comment — adopt never activates a key)"; exit 1; }
    grep -qxF '# --- known keys not set here (polaris adopt; uncomment a line to enable it) ---' ops/CONVENTIONS.md \
      || { echo "ADOPT MARKER FAIL (the first append writes the marker)"; exit 1; }
    # the stub carries the key's default and absent-cost out of the REGISTRY — read back from
    # KEYS.tsv so this asserts the shipped data itself, not a hand-copy of it that can drift
    adline="$(awk -F'\t' '$1=="plan_gate"{printf "# %s: %s   # %s (since %s)\n",$1,$3,$4,$2}' ops/KEYS.tsv)"
    [ -n "$adline" ] || { echo "ADOPT REGISTRY ROW FAIL (plan_gate must have a KEYS.tsv row)"; exit 1; }
    grep -qxF "$adline" ops/CONVENTIONS.md || { echo "ADOPT STUB SHAPE FAIL (the stub must carry the registry's default + absent-cost)"; exit 1; }
    grep -q '^plan_gate:' ops/CONVENTIONS.md && { echo "ADOPT UNCOMMENT FAIL (a stubbed key must never become a live value)"; exit 1; }
    grep -qx 'drain: plan' ops/CONVENTIONS.md || { echo "ADOPT LIVE SURVIVE FAIL (a pre-set live value must survive untouched)"; exit 1; }
    [ "$(grep -c '^# builder_questions:' ops/CONVENTIONS.md)" = "1" ] || { echo "ADOPT RESTUB FAIL (an existing stub counts as present)"; exit 1; }
    grep -q 'nothing changed behavior' "$T/ad1.out" || { echo "ADOPT SAY FAIL (the run must say it changed no behavior)"; exit 1; }
    # second run: rc 0, byte-identical file, and the no-op line names the whole registry
    cp ops/CONVENTIONS.md "$T/ad-1.md"
    "$SELF" adopt > "$T/ad2.out" 2>&1 || { cat "$T/ad2.out"; echo "ADOPT RERUN RC FAIL"; exit 1; }
    cmp -s "$T/ad-1.md" ops/CONVENTIONS.md || { echo "ADOPT IDEMPOTENT FAIL (a second run must leave CONVENTIONS.md byte-identical)"; exit 1; }
    grep -q "nothing to adopt — all $(grep -c '^[a-z]' ops/KEYS.tsv) known keys present or stubbed" "$T/ad2.out" \
      || { echo "ADOPT NOOP LINE FAIL (the no-op must count every registry row)"; exit 1; }
    # a GROWN registry appends under the marker that is already there — never a second marker
    printf 'zz_drill_key\t9.9.9\tnope\tnothing at all\n' >> ops/KEYS.tsv
    "$SELF" adopt > "$T/ad3.out" 2>&1 || { cat "$T/ad3.out"; echo "ADOPT GROWN RC FAIL"; exit 1; }
    grep -qxF '# zz_drill_key: nope   # nothing at all (since 9.9.9)' ops/CONVENTIONS.md \
      || { echo "ADOPT GROWN STUB FAIL (a new registry row must stub on the next run)"; exit 1; }
    [ "$(grep -cF '# --- known keys not set here' ops/CONVENTIONS.md)" = "1" ] \
      || { echo "ADOPT MARKER ONCE FAIL (a grown registry must append under the existing marker)"; exit 1; }
    # hermetic (T-046): every fixture file leaves with the drill
    rm -f ops/KEYS.tsv
    if [ -f "$T/ad-conv.bak" ]; then cp "$T/ad-conv.bak" ops/CONVENTIONS.md; else rm -f ops/CONVENTIONS.md; fi
    [ "$(git status --porcelain)" = "$adst" ] || { echo "ADOPT HERMETIC FAIL (the drill must leave the tree exactly as it found it)"; exit 1; }
}
drill_pushdegrade() {
    # ---- T-062 pushdegrade drill (ops/contracts/shared-checkout.md § Executable check) ----
    # handoff push resilience, end to end: (1) a planted ref literally named `feat` on the scratch
    # origin D/F-blocks every feat/<ID> push → handoff retries, repairs BETWEEN attempts (archive
    # as stray/feat-<sha7>, NEVER delete) and the push lands clean. (2) push forced dead — an
    # unrepairable D/F blocker with no stray `feat` to fix — → the board move STILL happens, with
    # the contract's ⚠ Note on the task + the push-fail event: a finished task is never stranded
    # in active/ by the network.
    ensure_origin
    printf -- '---\nid: T-PD\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/pd.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-PD.md
    git push -q origin main:refs/heads/feat
    pd_sha="$(git rev-parse main)"
    "$SELF" claim T-PD >/dev/null
    ( cd .polaris/wt/T-PD && echo pd > src/pd.txt && git add -A && git commit -qm ok && "$SELF" handoff T-PD > "$T/pd1.out" 2>&1 ) \
      || { echo "PUSHDEGRADE REPAIR RC FAIL (a stray feat ref must not sink the handoff)"; exit 1; }
    git ls-remote --exit-code origin refs/heads/feat/T-PD >/dev/null || { echo "PUSHDEGRADE REPAIR PUSH FAIL (the repaired push must land)"; exit 1; }
    git ls-remote origin refs/heads/feat | grep -q . && { echo "PUSHDEGRADE REPAIR STRAY FAIL (origin's stray feat must be archived away)"; exit 1; }
    git ls-remote --exit-code origin "refs/heads/stray/feat-$(printf '%.7s' "$pd_sha")" >/dev/null \
      || { echo "PUSHDEGRADE REPAIR ARCHIVE FAIL (the stray must be RENAMED stray/feat-<sha7>, never deleted)"; exit 1; }
    grep -q 'push failed' "$T/pd1.out" && { echo "PUSHDEGRADE REPAIR DEGRADE FAIL (a repaired push must not report failure)"; exit 1; }
    git merge -q --no-ff feat/T-PD -m merge
    "$SELF" done T-PD >/dev/null
    git push -q origin ":refs/heads/stray/feat-$(printf '%.7s' "$pd_sha")"   # bare origin for later drills
    # (2) push forced dead: refs/heads/feat/T-PD2/x D/F-blocks feat/T-PD2 and no stray `feat`
    # exists to repair — 3 attempts, then the DEGRADE: board moves, Note + event land, branch local
    printf -- '---\nid: T-PD2\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/pd2.txt\nverify: []\n---\n## Notes\n' > ops/board/ready/T-PD2.md
    git push -q origin main:refs/heads/feat/T-PD2/x
    "$SELF" claim T-PD2 >/dev/null
    ( cd .polaris/wt/T-PD2 && echo pd2 > src/pd2.txt && git add -A && git commit -qm ok && "$SELF" handoff T-PD2 > "$T/pd2.out" 2>&1 ) \
      || { echo "PUSHDEGRADE DEAD RC FAIL (a dead push must degrade, never strand the task in active/)"; exit 1; }
    [ -f ops/board/review/T-PD2.md ] || { echo "PUSHDEGRADE DEAD MOVE FAIL (the board move must proceed)"; exit 1; }
    grep -qxF -- '- ⚠ push failed at handoff — feat/T-PD2 is local-only; land merges the local branch' ops/board/review/T-PD2.md \
      || { echo "PUSHDEGRADE DEAD NOTE FAIL (the contract Note must append to the task)"; exit 1; }
    grep -q '"ev":"push-fail","id":"T-PD2"' ops/board/EVENTS.ndjson || { echo "PUSHDEGRADE DEAD EVENT FAIL (evt push-fail must emit)"; exit 1; }
    grep -q 'local-only' "$T/pd2.out" || { echo "PUSHDEGRADE DEAD SAY FAIL (the degrade must say so)"; exit 1; }
    git ls-remote origin refs/heads/feat/T-PD2 | grep -q . && { echo "PUSHDEGRADE DEAD PUSH FAIL (feat/T-PD2 must stay local-only)"; exit 1; }
    git push -q origin ":refs/heads/feat/T-PD2/x"
    git merge -q --no-ff feat/T-PD2 -m merge
    "$SELF" done T-PD2 >/dev/null
}
