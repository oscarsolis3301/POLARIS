# lib/selftest/policy.sh — selftest drills: rules drift hardening qa. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_rules() {
    # --- v5: RULES engine — path deny beats ownership; content deny on payload and on diff
    printf 'src/a.txt\tpath\t-\tfrozen for the drill\n' >> ops/RULES.tsv
    "$SELF" _rules src/a.txt 2>/dev/null && { echo "RULES PATH FAIL (should deny)"; exit 1; }
    "$SELF" rules >/dev/null || { echo "RULES HEALTH FAIL"; exit 1; }
    sed -i.bak '/frozen for the drill/d' ops/RULES.tsv && rm -f ops/RULES.tsv.bak
    printf 'src/\tcontent\tDO_NOT_SHIP\tblocked marker\n' >> ops/RULES.tsv
    echo ok > /tmp/pay.$$; "$SELF" _rules src/a.txt /tmp/pay.$$ || { echo "RULES CONTENT FAIL (clean should pass)"; exit 1; }
    echo DO_NOT_SHIP > /tmp/pay.$$
    "$SELF" _rules src/a.txt /tmp/pay.$$ 2>/dev/null && { echo "RULES CONTENT FAIL (should deny)"; exit 1; }
    rm -f /tmp/pay.$$
    # diff-level: a fresh task committing the marker must fail verify on rules, pass after revert
    printf -- '---\nid: T-2\npoints: 2\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n' > ops/board/ready/T-2.md
    git add -A; git commit -qm t2
    "$SELF" claim T-2 >/dev/null
    ( cd .polaris/wt/T-2 && echo "x DO_NOT_SHIP x" > src/b.txt && git add -A && git commit -qm bad
      "$SELF" verify T-2 >/dev/null 2>&1 && { echo "RULES DIFF FAIL (should deny)"; exit 1; }
      git reset -q --hard HEAD~1 && echo clean > src/b.txt && git add -A && git commit -qm ok
      "$SELF" verify T-2 >/dev/null || { echo "RULES DIFF FAIL (clean should pass)"; exit 1; } ) || exit 1
    "$SELF" release T-2 --to ready -m drill >/dev/null
    # T-046 hermeticity: leave the fixture exactly as found — remove T-2 (contract-less ready task)
    # and the DO_NOT_SHIP rule this drill added, so a later label sharing the shard (qa's
    # drift --strict) meets a clean board + pristine RULES.tsv regardless of partition.
    rm -f ops/board/ready/T-2.md
    sed -i.bak '/DO_NOT_SHIP/d' ops/RULES.tsv && rm -f ops/RULES.tsv.bak
    git add -A; git commit -qm 'rules drill cleanup' >/dev/null 2>&1 || true
}
drill_drift() {
    # --- v5: drift — seeded overlap must be found; --strict must go red, then green
    # Self-provision T-2: the rules drill (T-046) now removes its own T-2, and --only drift skips
    # rules entirely — so drift always seeds its own contract-less ready task here, independent of
    # any other label. Removed again below, so drift too leaves the fixture as it found it.
    [ -f ops/board/ready/T-2.md ] || printf -- '---\nid: T-2\npoints: 2\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n' > ops/board/ready/T-2.md
    printf -- '---\nid: T-3\npoints: 1\nwsjf: 1\nstatus: ready\nfiles_owned:\n  - src/b.txt\n---\n' > ops/board/ready/T-3.md
    "$SELF" drift | grep -q 'OWNERSHIP OVERLAP: T-3 ∩ T-2' || { echo "DRIFT OVERLAP FAIL"; exit 1; }
    ( "$SELF" drift --strict >/dev/null 2>&1 ) && { echo "DRIFT STRICT FAIL (should rc 1)"; exit 1; }
    rm ops/board/ready/T-3.md ops/board/ready/T-2.md; sed -i.bak '/DO_NOT_SHIP/d' ops/RULES.tsv && rm -f ops/RULES.tsv.bak
    git add -A; git commit -qm cleanup || true   # T-033: --only drift has no rules-drill RULES.tsv change to commit
    "$SELF" drift >/dev/null || { echo "DRIFT CLEAN FAIL"; exit 1; }
}
drill_hardening() {
    # ============================ v5.8 hardening drills ============================
    # rename must NOT smuggle a non-owned deletion past the gate (--no-renames)
    mkdir -p pkg; echo keep > pkg/keep.txt; echo out > outside.txt
    printf -- '---\nid: T-4\npoints: 1\nwsjf: 3\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - pkg/\nverify: []\n---\n' > ops/board/ready/T-4.md
    git add -A; git commit -qm t4
    "$SELF" claim T-4 >/dev/null
    ( cd .polaris/wt/T-4 && git mv outside.txt pkg/moved.txt && git commit -qm 'smuggle rename'
      if "$SELF" verify T-4 >/dev/null 2>&1; then echo "RENAME OWNERSHIP FAIL (deletion of outside.txt must reject)"; exit 1; fi ) || exit 1
    "$SELF" release T-4 --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-4.md outside.txt pkg/keep.txt; rmdir pkg 2>/dev/null || true
    git add -A; git commit -qm cleanup4
    # auto-pick claim fans out PAST a locked top task to the next ready one (this + atomic locks =
    # N parallel no-ID claims land on N distinct tasks). Deterministic: pre-take the top, then no-ID.
    printf -- '---\nid: T-5\npoints: 1\nwsjf: 9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/f5.txt\nverify: []\n---\n' > ops/board/ready/T-5.md
    printf -- '---\nid: T-6\npoints: 1\nwsjf: 8\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/f6.txt\nverify: []\n---\n' > ops/board/ready/T-6.md
    "$SELF" claim T-5 >/dev/null                         # session A takes the top wsjf task
    "$SELF" claim >/dev/null                             # session B, no ID: takes the next available task
    [ -f ops/board/active/T-6.md ] || { echo "FANOUT FAIL — no-ID claim did not take the next task"; exit 1; }
    "$SELF" release T-5 --to ready -m drill >/dev/null; "$SELF" release T-6 --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-5.md ops/board/ready/T-6.md
    # drift must catch nested-glob overlap (previously declared 'undecidable')
    printf -- '---\nid: T-7\npoints: 1\nwsjf: 2\nstatus: ready\nfiles_owned:\n  - src/api/*\n---\n' > ops/board/ready/T-7.md
    printf -- '---\nid: T-8\npoints: 1\nwsjf: 2\nstatus: ready\nfiles_owned:\n  - src/*/handler.js\n---\n' > ops/board/ready/T-8.md
    "$SELF" drift | grep -q 'OWNERSHIP OVERLAP: T-8 ∩ T-7' || { echo "GLOB OVERLAP FAIL (nested globs must flag)"; exit 1; }
    rm -f ops/board/ready/T-7.md ops/board/ready/T-8.md
    # `audit` (the logic polaris-audit.yml wraps) must reject an out-of-scope feat branch, from anywhere
    printf -- '---\nid: T-9\npoints: 1\nwsjf: 1\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/f9.txt\nverify: []\n---\n' > ops/board/ready/T-9.md
    "$SELF" claim T-9 >/dev/null
    ( cd .polaris/wt/T-9 && echo x > src/f9.txt && echo y > src/nope.txt && git add -A && git commit -qm 'in+out of scope' )
    "$SELF" audit T-9 >/dev/null 2>&1 && { echo "AUDIT FAIL (out-of-scope feat branch must reject)"; exit 1; }
    "$SELF" release T-9 --to ready -m drill >/dev/null
    "$SELF" why T-9 | grep -q 'release' || { echo "WHY FAIL (release note not surfaced)"; exit 1; }
    rm -f ops/board/ready/T-9.md
    # drift catches a depends_on cycle (a ring never satisfies the ready gate)
    printf -- '---\nid: T-A\npoints: 1\nwsjf: 1\nstatus: backlog\ndepends_on:\n  - T-B\n---\n' > ops/board/backlog/T-A.md
    printf -- '---\nid: T-B\npoints: 1\nwsjf: 1\nstatus: backlog\ndepends_on:\n  - T-A\n---\n' > ops/board/backlog/T-B.md
    "$SELF" drift | grep -q 'DEP CYCLE' || { echo "DEP CYCLE FAIL"; exit 1; }
    rm -f ops/board/backlog/T-A.md ops/board/backlog/T-B.md
    # (The write-time guard hook wrapper is validated manually, not here: driving it needs python and
    #  git-canonical paths, which made it fragile across the CI matrix. The guard's allow/block logic is
    #  still covered by the _match/_rules drills above; only the JSON-wrapper harness was pulled.)
    # --- self-hosting: this throwaway repo is NOT self-hosting, so doctor must stay quiet...
    "$SELF" doctor 2>/dev/null | grep -q 'self-hosting' && { echo "SELFHOST MISFIRE FAIL"; exit 1; }
    # ...and once kit/ops/pack.py exists, update refuses and doctor reports the skew.
    mkdir -p kit/ops; : > kit/ops/pack.py
    printf 'version: 9.9.9\n' > kit/ops/VERSION
    printf 'version: 1.0.0\n' > ops/VERSION
    "$SELF" update >/dev/null 2>&1 && { echo "SELFHOST UPDATE FAIL (should refuse)"; exit 1; }
    "$SELF" doctor 2>/dev/null | grep -q 'NOT been dogfooded' || { echo "SELFHOST SKEW FAIL"; exit 1; }
    printf 'version: 9.9.9\n' > ops/VERSION
    "$SELF" doctor 2>/dev/null | grep -q 'runs the POLARIS it ships' || { echo "SELFHOST SYNC FAIL"; exit 1; }
    rm -rf kit ops/VERSION
    # --- shared checkout: doctor validates the two integration knobs (ops/contracts/shared-checkout.md).
    # They are minutes on a path where a typo is SILENT — it changes how long a session waits for the
    # lane, or how old a lease must be before it is stolen. Unset must stay quiet, on the same rule
    # drill_claudemd's fourth case exists to hold: a warning that also fires when nothing is wrong is
    # a warning people learn to scroll past. Each bad value gets exactly one ⚠ line, and 0 is bad —
    # it means "never wait" and "steal any lease on sight", which nobody types on purpose.
    "$SELF" doctor 2>/dev/null | grep -q 'integration_wait_minutes' && { echo "KNOB SILENCE FAIL (an unset knob must say nothing)"; exit 1; }
    printf 'integration_wait_minutes: soon\nintegration_stale_minutes: 45\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/knob1.out" 2>&1 || true
    grep -q 'integration_wait_minutes' "$T/knob1.out" || { cat "$T/knob1.out"; echo "KNOB WAIT FAIL (a non-numeric wait must warn)"; exit 1; }
    grep -q 'integration_stale_minutes' "$T/knob1.out" && { cat "$T/knob1.out"; echo "KNOB STALE MISFIRE FAIL (a valid value must stay silent)"; exit 1; }
    printf 'integration_wait_minutes: 10\nintegration_stale_minutes: 0\n' > ops/CONVENTIONS.md
    "$SELF" doctor > "$T/knob2.out" 2>&1 || true
    grep -q 'integration_stale_minutes' "$T/knob2.out" || { cat "$T/knob2.out"; echo "KNOB STALE FAIL (0 is not a positive number of minutes)"; exit 1; }
    grep -q 'integration_wait_minutes' "$T/knob2.out" && { cat "$T/knob2.out"; echo "KNOB WAIT MISFIRE FAIL (a valid value must stay silent)"; exit 1; }
    rm -f ops/CONVENTIONS.md
}
drill_qa() {
    # --- v5.10: qa — one command, the whole picture. Green suite → rc 0 with per-check lines;
    # a red test: must flip the exit code and name the check.
    printf 'test: true\n' > ops/CONVENTIONS.md
    "$SELF" qa > "$T/qa.out" || { cat "$T/qa.out"; echo "QA GREEN FAIL (healthy repo must rc 0)"; exit 1; }
    grep -q 'test — green' "$T/qa.out" || { echo "QA LINE FAIL (per-check line missing)"; exit 1; }
    printf 'test: false\n' > ops/CONVENTIONS.md
    "$SELF" qa >/dev/null 2>&1 && { echo "QA RED FAIL (red suite must rc 1)"; exit 1; }
    rm -f ops/CONVENTIONS.md
}
drill_finish() {
    # --- v5.22: finish — the run-over gate (ops/contracts/run-finish.md). Proves: listed in help ·
    # a pending item is NAMED, rc 1, and does NOT stamp or fire (a pending run must never claim it
    # signalled) · drain: queue gates on ready/ while drain: plan demotes the SAME board to a caveat ·
    # a worktree invocation refuses, which is the mechanical half of "a BUILDER never celebrates" ·
    # a clean board is rc 0 with the frozen verdict token and a well-formed stamp · the done hook
    # fires EXACTLY ONCE per finished state and a re-run stays rc 0 with the stamp unmoved.
    # HERMETIC (ops/contracts/selftest-sharding.md): every artifact is removed before returning —
    # CONVENTIONS.md absent and the tree clean, exactly as drill_qa leaves them, plus no finish-stamp
    # and no notify.log (drill_notify greps the same file and would false-pass on our lines).
    "$SELF" help | grep -q '^  finish' || { echo "USAGE FAIL: finish missing from help"; exit 1; }
    # The fixture is COMMITTED: finish gates on a clean tree (same porcelain read cmd_qa's suite
    # stamp uses), so an untracked CONVENTIONS.md would itself be the pending item. `test: true`
    # gives qa a real green suite command; the notify: hook makes "fired once" OBSERVED, not assumed.
    printf 'test: true\n' > ops/CONVENTIONS.md
    printf 'notify: printf "%%s/%%s/%%s/%%s\\n" "$POLARIS_EV" "$POLARIS_SEVERITY" "$POLARIS_ID" "$POLARIS_NOTE" >> %s\n' "$T/notify.log" >> ops/CONVENTIONS.md
    # A real contract file: the queued fixture below is the first ready/ task in the spine that
    # coexists with a qa run, so it must satisfy the ready gate or drift reds for the wrong reason.
    mkdir -p ops/contracts; printf '# drill contract\n' > ops/contracts/fin.md
    git add -A; git commit -qm 'drill: finish fixture'
    : > "$T/notify.log"; rm -f .polaris/finish-stamp
    # 1) a task waiting to land → rc 1, named by ID, no stamp, no hook
    printf -- '---\nid: T-FIN\npoints: 1\nwsjf: 1\nstatus: review\nfiles_owned:\n  - src/fin.txt\n---\n' > ops/board/review/T-FIN.md
    "$SELF" finish > "$T/fin1.out" 2>&1 && { cat "$T/fin1.out"; echo "FINISH PENDING FAIL (a review/ task must rc 1)"; exit 1; }
    grep -q 'pending: 1 waiting to land' "$T/fin1.out" || { cat "$T/fin1.out"; echo "FINISH PENDING MSG FAIL (must name WHAT is pending)"; exit 1; }
    grep -q 'T-FIN' "$T/fin1.out" || { echo "FINISH PENDING ID FAIL (must name the task)"; exit 1; }
    grep -q 'finish: not done' "$T/fin1.out" || { echo "FINISH PENDING VERDICT FAIL (frozen token missing)"; exit 1; }
    [ -f .polaris/finish-stamp ] && { echo "FINISH PENDING STAMP FAIL (a pending run must not stamp)"; exit 1; }
    grep -q 'run-done' "$T/notify.log" 2>/dev/null && { echo "FINISH PENDING HOOK FAIL (a pending run must not fire done)"; exit 1; }
    rm -f ops/board/review/T-FIN.md
    # 2) drain: — the default (queue) gates on a queued task; drain: plan demotes the SAME board to
    #    a caveat, because one "go" there authorizes the plan and not the board.
    printf -- '---\nid: T-FQ\npoints: 1\nwsjf: 1\nstatus: ready\ncontract: ops/contracts/fin.md\nfiles_owned:\n  - src/fq.txt\n---\n' > ops/board/ready/T-FQ.md
    "$SELF" finish > "$T/fin2.out" 2>&1 && { cat "$T/fin2.out"; echo "FINISH DRAIN FAIL (a queued task under drain: queue must rc 1)"; exit 1; }
    grep -q 'pending: 1 queued' "$T/fin2.out" || { cat "$T/fin2.out"; echo "FINISH DRAIN MSG FAIL"; exit 1; }
    printf 'drain: plan\n' >> ops/CONVENTIONS.md; git add -A; git commit -qm 'drill: drain plan'
    "$SELF" finish > "$T/fin3.out" 2>&1 || { cat "$T/fin3.out"; echo "FINISH DRAIN-PLAN FAIL (drain: plan must not gate on ready/)"; exit 1; }
    grep -q 'caveat: 1 queued' "$T/fin3.out" || { cat "$T/fin3.out"; echo "FINISH DRAIN-PLAN CAVEAT FAIL (parked work must still be REPORTED)"; exit 1; }
    rm -f ops/board/ready/T-FQ.md
    grep -v '^drain:' ops/CONVENTIONS.md > "$T/conv.tmp" && mv "$T/conv.tmp" ops/CONVENTIONS.md
    git add -A; git commit -qm 'drill: drain default'
    # 3) a subagent can NEVER celebrate: finish refuses outside the primary checkout, whatever its
    #    context talked it into. This is the one part of the H1 ban that is mechanically testable.
    printf -- '---\nid: T-FW\npoints: 1\nwsjf: 1\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/fw.txt\nverify: []\n---\n' > ops/board/ready/T-FW.md
    "$SELF" claim T-FW >/dev/null
    ( cd .polaris/wt/T-FW && "$SELF" finish > "$T/fin4.out" 2>&1 ) && { cat "$T/fin4.out"; echo "FINISH WORKTREE FAIL (a worktree invocation must rc 1)"; exit 1; }
    grep -q 'primary checkout' "$T/fin4.out" || { cat "$T/fin4.out"; echo "FINISH WORKTREE MSG FAIL (must name the refusal)"; exit 1; }
    "$SELF" release T-FW --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-FW.md; git branch -D feat/T-FW >/dev/null 2>&1 || true
    # 4) a clean board → rc 0, the frozen verdict token, a well-formed stamp, and the hook line
    rm -f .polaris/finish-stamp; : > "$T/notify.log"
    "$SELF" finish > "$T/fin5.out" 2>&1 || { cat "$T/fin5.out"; echo "FINISH GREEN FAIL (a clean board must rc 0)"; exit 1; }
    grep -q 'finish: run complete' "$T/fin5.out" || { cat "$T/fin5.out"; echo "FINISH GREEN VERDICT FAIL (frozen token missing)"; exit 1; }
    grep -q 'done signal fired' "$T/fin5.out" || { cat "$T/fin5.out"; echo "FINISH FIRE FAIL (the first finish must say it fired)"; exit 1; }
    grep -qE '^[0-9a-f]{7,} [0-9]+$' .polaris/finish-stamp || { echo "FINISH STAMP FORMAT FAIL (want one '<sha> <epoch>' line)"; exit 1; }
    ngwait '^run-done/done//run-done$' || { echo "FINISH HOOK FAIL (notify: must see run-done/done)"; exit 1; }
    # 5) FIRE-ONCE: same finished state → still rc 0, no second hook line, stamp unmoved
    fnpre="$(cat .polaris/finish-stamp)"
    "$SELF" finish > "$T/fin6.out" 2>&1 || { cat "$T/fin6.out"; echo "FINISH REFIRE RC FAIL (a re-run must stay rc 0)"; exit 1; }
    grep -q 'already fired' "$T/fin6.out" || { cat "$T/fin6.out"; echo "FINISH REFIRE MSG FAIL"; exit 1; }
    sleep 0.5
    [ "$(grep -c 'run-done/done' "$T/notify.log")" = "1" ] || { echo "FINISH REFIRE HOOK FAIL (done must fire EXACTLY once per finished state)"; exit 1; }
    [ "$(cat .polaris/finish-stamp)" = "$fnpre" ] || { echo "FINISH REFIRE STAMP FAIL (the stamp must not move)"; exit 1; }
    # 6) SHARED CHECKOUT (ops/contracts/shared-checkout.md) — what a SECOND chat must be able to see.
    #    A dirty tree still gates, but the pending line now names park as the third option, because
    #    on a shared checkout "commit or discard" asks one chat to rule on another's work. A lease
    #    held elsewhere is a NEW gate: a land in flight leaves the board looking quiet, so without it
    #    a run could be declared over mid-landing. Parked dirt is a CAVEAT and never a gate — rc 0
    #    means "the run is over", never "nothing was left behind" — and a lease past the stale knob
    #    is a caveat too, or one crashed integrator makes the run un-finishable for 45 minutes.
    echo dirt > src/fin-dirt.txt
    "$SELF" finish > "$T/fin7.out" 2>&1 && { cat "$T/fin7.out"; echo "FINISH DIRTY FAIL (a dirty tree must rc 1)"; exit 1; }
    grep -q 'ops/polaris park' "$T/fin7.out" || { cat "$T/fin7.out"; echo "FINISH DIRTY REMEDY FAIL (the dirty-tree pending must name park)"; exit 1; }
    "$SELF" park -m 'finish drill' >/dev/null || { echo "FINISH PARK FAIL (park must take a dirty tree)"; exit 1; }
    "$SELF" finish > "$T/fin8.out" 2>&1 || { cat "$T/fin8.out"; echo "FINISH PARK GATE FAIL (a parked stash must never gate)"; exit 1; }
    grep -q 'caveat: parked work is still stashed' "$T/fin8.out" || { cat "$T/fin8.out"; echo "FINISH PARK CAVEAT FAIL (a forgotten stash must still be REPORTED)"; exit 1; }
    "$SELF" status | grep -q '^parked: ' || { echo "STATUS PARK FAIL (status must list the parked stash)"; exit 1; }
    "$SELF" unpark >/dev/null || { echo "FINISH UNPARK FAIL (unpark must restore the stash)"; exit 1; }
    rm -f src/fin-dirt.txt
    # a lease held by ANOTHER session gates and names holder + age (pid 1 is never this process)
    finlk="$(git rev-parse --git-common-dir)/polaris-locks/.int-lease"
    mkdir -p "$finlk"; date +%s > "$finlk/epoch"; echo other@host > "$finlk/who"; echo 1 > "$finlk/pid"
    "$SELF" finish > "$T/fin9.out" 2>&1 && { cat "$T/fin9.out"; echo "FINISH LEASE FAIL (a held integration lease must rc 1)"; exit 1; }
    grep -q 'other@host holds the integration lease' "$T/fin9.out" || { cat "$T/fin9.out"; echo "FINISH LEASE MSG FAIL (must name the holder)"; exit 1; }
    "$SELF" status | grep -q '^integration lane: held by other@host' || { echo "STATUS LEASE FAIL (status must name the holder)"; exit 1; }
    echo $(( $(date +%s) - 3600 )) > "$finlk/epoch"     # older than the 45m default → abandoned
    "$SELF" finish > "$T/finA.out" 2>&1 || { cat "$T/finA.out"; echo "FINISH STALE LEASE FAIL (a stale lease must not gate)"; exit 1; }
    grep -q 'caveat: the integration lease is stale' "$T/finA.out" || { cat "$T/finA.out"; echo "FINISH STALE LEASE CAVEAT FAIL"; exit 1; }
    rm -rf "$finlk"
    # neither present → status says nothing about either: the quiet repo stays byte-identical
    "$SELF" status > "$T/finB.out" 2>&1
    grep -qE '^(integration lane|parked): ' "$T/finB.out" && { cat "$T/finB.out"; echo "STATUS QUIET FAIL (a quiet repo must stay silent about both)"; exit 1; }
    # hermetic: back to drill_qa's exit state — CONVENTIONS.md absent, tree clean, no stamp, no log
    rm -f ops/CONVENTIONS.md ops/contracts/fin.md .polaris/finish-stamp "$T/notify.log"
    rmdir ops/contracts 2>/dev/null || true
    git add -A; git commit -qm 'drill: finish teardown'
}
drill_claudemd() {
    # --- v5.23: does the protocol every session READS match the kit this repo claims to run?
    # A repo was found on 5.22.0 injecting a CLAUDE.md three weeks old, and every command — doctor
    # included — called it healthy, because nothing compared the two. install.sh now stamps
    # `[kit X.Y.Z]` into the BEGIN marker; these four cases are the whole detection surface.
    # The FOURTH is the one that keeps the check useful: a warning that also fires when everything
    # is fine is a warning people learn to scroll past.
    # HERMETIC: ops/VERSION and CLAUDE.md are saved and restored byte-exactly.
    [ -f ops/VERSION ] && cp ops/VERSION "$T/cmv-VERSION.bak" || rm -f "$T/cmv-VERSION.bak"
    [ -f CLAUDE.md ] && cp CLAUDE.md "$T/cmv-CLAUDE.bak" || rm -f "$T/cmv-CLAUDE.bak"
    printf 'version: 9.9.9\n' > ops/VERSION
    # 1) stamped, but NOT the version this kit runs → the mismatch must be named with both numbers
    printf '<!-- POLARIS:BEGIN — managed block [kit 1.0.0] -->\nx\n<!-- POLARIS:END -->\n' > CLAUDE.md
    "$SELF" doctor > "$T/cm1.out" 2>&1 || true
    grep -q 'block is 1.0.0' "$T/cm1.out" || { cat "$T/cm1.out"; echo "CLAUDEMD MISMATCH FAIL (must name the block version)"; exit 1; }
    grep -q '9.9.9' "$T/cm1.out" || { echo "CLAUDEMD MISMATCH FAIL (must name the kit version too)"; exit 1; }
    # 2) markers but no stamp → a pre-5.23.0 block, possibly many releases behind
    printf '<!-- POLARIS:BEGIN — managed block -->\nx\n<!-- POLARIS:END -->\n' > CLAUDE.md
    "$SELF" doctor > "$T/cm2.out" 2>&1 || true
    grep -q 'predates version stamping' "$T/cm2.out" || { cat "$T/cm2.out"; echo "CLAUDEMD UNSTAMPED FAIL"; exit 1; }
    # 3) POLARIS text with NO markers at all — the frozen-at-install-time case, the actual bug
    printf '# POLARIS v5 — Parallel Sprint Protocol\n\nold\n' > CLAUDE.md
    "$SELF" doctor > "$T/cm3.out" 2>&1 || true
    grep -q 'NO managed markers' "$T/cm3.out" || { cat "$T/cm3.out"; echo "CLAUDEMD UNMARKED FAIL"; exit 1; }
    grep -q 'ops/polaris update' "$T/cm3.out" || { echo "CLAUDEMD UNMARKED FAIL (must name the fix)"; exit 1; }
    # 4) stamp MATCHES → doctor must say nothing about CLAUDE.md at all
    printf '<!-- POLARIS:BEGIN — managed block [kit 9.9.9] -->\nx\n<!-- POLARIS:END -->\n' > CLAUDE.md
    "$SELF" doctor > "$T/cm4.out" 2>&1 || true
    grep -q 'CLAUDE.md' "$T/cm4.out" && { cat "$T/cm4.out"; echo "CLAUDEMD FALSE ALARM (a current block must be silent)"; exit 1; }
    # hermetic restore
    [ -f "$T/cmv-VERSION.bak" ] && cp "$T/cmv-VERSION.bak" ops/VERSION || rm -f ops/VERSION
    [ -f "$T/cmv-CLAUDE.bak" ] && cp "$T/cmv-CLAUDE.bak" CLAUDE.md || rm -f CLAUDE.md
    rm -f "$T/cmv-VERSION.bak" "$T/cmv-CLAUDE.bak"
}
