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
    # ---- T-050: the `ask` rule kind + `polaris approve`, end to end (ops/contracts/ask-approval.md).
    # `ask` is the ONE kind that can be lifted, so every containment on it is load-bearing: unheld,
    # `ask` decays into a legal way to dissolve any rule that blocks you — the single motive
    # invariant 11 exists to resist. Two assertions carry that weight alone. (5) a `path` rule is
    # never cleared by an approval, or `ask` becomes a lever on every wall in the repo. (4) a Builder
    # can never approve, its own gate or anyone's — mechanically, by branch, not by exhortation,
    # because an approval mechanism is exactly what a stuck agent rationalizes its way into.
    # Hermetic like the rest of this drill: three rules, two task files and one feat branch, all gone
    # before it returns. `src/wall/` deliberately carries BOTH kinds on the IDENTICAL scope — that
    # collision is the only shape in which (5) means anything.
    printf 'src/ask/\task\t-\taskdrill gated scope\n' >> ops/RULES.tsv
    printf 'src/wall/\task\t-\taskdrill gated wall\n' >> ops/RULES.tsv
    printf 'src/wall/\tpath\t-\taskdrill walled\n' >> ops/RULES.tsv
    printf -- '---\nid: T-ASK\npoints: 1\nwsjf: 4\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/ask/a.txt\n  - src/wall/w.txt\napproved:\nverify: []\n---\n## Notes\n' > ops/board/ready/T-ASK.md
    # (1) an ask rule with no approval denies EXACTLY as path — rc 1 (rules), not 3 (ownership):
    # T-ASK owns the path, so the rule is the only thing that can be refusing it.
    "$SELF" _guard src/ask/a.txt T-ASK >/dev/null 2>&1; [ $? -eq 1 ] || { echo "ASK DENY FAIL (an ask rule with no approval must deny, rc 1)"; exit 1; }
    # (2) the recorded approval clears that same call.
    "$SELF" approve T-ASK src/ask/ -m drill >/dev/null || { echo "ASK APPROVE FAIL (approve from the primary checkout must succeed)"; exit 1; }
    fm_list approved ops/board/ready/T-ASK.md | grep -q '^src/ask/ —' || { echo "ASK APPROVE APPEND FAIL (entry missing from approved:)"; exit 1; }
    "$SELF" _guard src/ask/a.txt T-ASK >/dev/null 2>&1 || { echo "ASK CLEAR FAIL (want rc 0 once the approval is on the task)"; exit 1; }
    # (3) the ID-less entrypoint stays fail-closed: `_rules` carries no task, so it carries no
    # approval — even with the approval that just cleared (2) sitting on the board.
    "$SELF" _rules src/ask/a.txt >/dev/null 2>&1 && { echo "ASK IDLESS FAIL (_rules has no ID and must still deny)"; exit 1; }
    # (5) an approval NEVER clears a `path` rule, even one covering the identical scope.
    "$SELF" approve T-ASK src/wall/ -m drill >/dev/null || { echo "ASK APPROVE WALL FAIL (an ask rule gates this scope, so approve must record it)"; exit 1; }
    "$SELF" _guard src/wall/w.txt T-ASK >/dev/null 2>&1; [ $? -eq 1 ] || { echo "PATH UNCLEARED FAIL (an approval must NOT clear a path rule on the same scope)"; exit 1; }
    # (4) approve refuses on feat/*, names the containment, and moves nothing. The scope is the
    # already-approved src/ask/, so the branch is the ONLY thing standing between this call and a
    # successful self-approval — remove the guard and both halves below go red.
    "$SELF" claim T-ASK >/dev/null
    apre="$(git rev-parse refs/heads/polaris/board)"
    ( cd .polaris/wt/T-ASK && "$SELF" approve T-ASK src/ask/ -m "self-approval" ) >/dev/null 2>"$T/askfeat.err" \
      && { echo "SELF-APPROVE FAIL (approve on feat/* must refuse — a Builder never clears its own gate)"; exit 1; }
    grep -q 'a Builder never approves its own gate' "$T/askfeat.err" || { cat "$T/askfeat.err"; echo "SELF-APPROVE MSG FAIL (the refusal must name the containment)"; exit 1; }
    [ "$(git rev-parse refs/heads/polaris/board)" = "$apre" ] || { echo "SELF-APPROVE MUTATE FAIL (a refusal must not move the board ref)"; exit 1; }
    # (6) the plan gate — the ARC sequence stopped at step 1. T-ASK is active by now, so ready/ holds
    # only the unapproved T-ASK2. The finding disappearing once its approval lands is the half that
    # proves the gate reads the approval, not merely the rule.
    printf -- '---\nid: T-ASK2\npoints: 1\nwsjf: 2\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/ask/b.txt\napproved:\nverify: []\n---\n## Notes\n' > ops/board/ready/T-ASK2.md
    "$SELF" drift > "$T/askdrift.out" 2>&1 || true
    grep -q "READY GATE: T-ASK2 owns 'src/ask/b.txt' under ask scope 'src/ask/'" "$T/askdrift.out" \
      || { cat "$T/askdrift.out"; echo "READY GATE FAIL (an unapproved ask scope in ready/ must be a finding)"; exit 1; }
    ( "$SELF" drift --strict >/dev/null 2>&1 ) && { echo "READY GATE STRICT FAIL (an ask-gated ready task must make --strict rc 1)"; exit 1; }
    "$SELF" approve T-ASK2 src/ask/ -m drill >/dev/null || { echo "READY GATE APPROVE FAIL"; exit 1; }
    "$SELF" drift 2>&1 | grep -q 'READY GATE: T-ASK2 owns' && { echo "READY GATE SETTLED FAIL (a covered scope is a settled question, not a finding)"; exit 1; }
    "$SELF" release T-ASK --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-ASK.md ops/board/ready/T-ASK2.md
    git branch -q -D feat/T-ASK 2>/dev/null || true
    sed -i.bak '/askdrill/d' ops/RULES.tsv && rm -f ops/RULES.tsv.bak
    # ---- end T-050 ask/approve drills ----
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
drill_park() {
    # ---- T-062 park drill (ops/contracts/shared-checkout.md § Executable check) ----
    # A dirty shared checkout is parked, never asked about: park stashes tracked + untracked dirt
    # as polaris/park-<epoch>, unpark reverses it BYTE-identically, and a dirty tree at `land`
    # parks + proceeds + prints the stash name instead of dying. Byte-identity is proven with cmp,
    # never grep/sed — Git Bash strips \r there (T-056), so the untracked fixture carries CR bytes
    # on purpose. autocrlf is pinned OFF for the drill's duration (restored after): on Windows the
    # throwaway repo inherits core.autocrlf=true and `stash pop` re-smudges LF→CRLF — git's own
    # checkout policy, not a park distortion — which would red the cmp for the wrong reason.
    pk_ac="$(git config --local --get core.autocrlf 2>/dev/null || true)"
    git config core.autocrlf false
    printf 'park tracked dirt\n' >> src/a.txt
    printf 'untracked \r\nCR bytes kept\r\n' > src/park-un.bin
    cp src/a.txt "$T/park-a.snap"; cp src/park-un.bin "$T/park-u.snap"
    "$SELF" park -m 'park drill' > "$T/park1.out" 2>&1 || { cat "$T/park1.out"; echo "PARK RC FAIL (a dirty tree must park)"; exit 1; }
    grep -q 'parked as polaris/park-' "$T/park1.out" || { echo "PARK SAY FAIL (park must name the stash)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "PARK CLEAN FAIL (tracked + untracked dirt must leave the tree)"; exit 1; }
    [ -f src/park-un.bin ] && { echo "PARK UNTRACKED FAIL (the untracked file must be stashed away)"; exit 1; }
    "$SELF" unpark > "$T/park2.out" 2>&1 || { cat "$T/park2.out"; echo "UNPARK RC FAIL"; exit 1; }
    cmp -s src/a.txt "$T/park-a.snap" || { echo "UNPARK BYTES FAIL (tracked restore must be byte-identical)"; exit 1; }
    cmp -s src/park-un.bin "$T/park-u.snap" || { echo "UNPARK BYTES FAIL (untracked restore must be byte-identical)"; exit 1; }
    git checkout -q -- src/a.txt; rm -f src/park-un.bin "$T/park-a.snap" "$T/park-u.snap"
    # dirty tree at land → park + caveat + PROCEED (integrate.sh dirty gate → park). Fixture is the
    # hint-drill shape — a review task + its feat branch by hand: `land` makes NO board write and
    # nothing here claims, so there is no lock and no worktree to clean up after.
    printf -- '---\nid: T-PK\ntitle: park lane file\ntype: feature\nscope: src\npoints: 1\nwsjf: 5\nowner: null\nbranch: feat/T-PK\nstatus: review\nfiles_owned:\n  - src/pk.txt\nverify: []\n---\n' > ops/board/review/T-PK.md
    git checkout -q -b feat/T-PK main
    echo pk > src/pk.txt; git add -A; git commit -qm ok
    git checkout -q main
    printf 'park land dirt\n' >> src/a.txt          # TRACKED dirt: land's dirty gate is diff-based
    cp src/a.txt "$T/pk-a.snap"
    pk_d="$(date +%F)"
    "$SELF" land T-PK > "$T/pk.out" 2>&1 || { cat "$T/pk.out"; echo "PARK LAND RC FAIL (a dirty tree must park + proceed, never die)"; exit 1; }
    grep -q 'parked as polaris/park-' "$T/pk.out" || { echo "PARK LAND SAY FAIL (the land must print the stash name)"; exit 1; }
    git log -1 --format=%s | grep -q '\[T-PK\]$' || { echo "PARK LAND PROCEED FAIL (the squash must land after the park)"; exit 1; }
    git diff --quiet && git diff --cached --quiet || { echo "PARK LAND CLEAN FAIL (the dirt belongs in the stash, not the tree)"; exit 1; }
    "$SELF" unpark >/dev/null 2>&1 || { echo "PARK LAND UNPARK FAIL"; exit 1; }
    cmp -s src/a.txt "$T/pk-a.snap" || { echo "PARK LAND BYTES FAIL (the parked dirt must come back byte-identical)"; exit 1; }
    git checkout -q -- src/a.txt; rm -f "$T/pk-a.snap"
    # T-046 hermeticity: land wrote no board state — drop the wave, the branch and the fixture task
    git checkout -q main
    git branch -q -D "integrate/$pk_d" 2>/dev/null || true
    git branch -q -D feat/T-PK 2>/dev/null || true
    rm -f ops/board/review/T-PK.md
    if [ -n "$pk_ac" ]; then git config core.autocrlf "$pk_ac"; else git config --unset core.autocrlf 2>/dev/null || true; fi
}
drill_route() {
    # ---- T-071 route drill (ops/contracts/model-routing.md § Executable check) ----
    # `triage` answers "which lane"; `route` answers "which MODEL", and the CONDUCTOR calls it
    # before EVERY spawn while `fleet` injects its answer into every pane it opens. So line 1 is
    # parsed BLIND — always exactly one of three words — and the note is the other half of the
    # contract: it appears when, and ONLY when, a mapping knob or a task's literal `model:` names a
    # model, because a repo that sets no knobs must behave byte-identically to one with no routing
    # in it at all. That silence is the invariant a knob-shaped feature loses first, so it is
    # asserted here in both directions rather than assumed.
    # HERMETIC (T-046): CONVENTIONS.md is saved and restored byte-exactly, the fixture tasks and the
    # stub PATH bin are removed, and nothing here claims, locks, commits or touches the board branch.
    [ -f ops/CONVENTIONS.md ] && cp ops/CONVENTIONS.md "$T/rt-conv.bak" || rm -f "$T/rt-conv.bak"
    rm -f ops/CONVENTIONS.md
    # 1) the tier_for table, board-free AND knob-free: one bare word on line 1, and nothing else.
    [ "$("$SELF" route --points 5 --risk normal | head -1)" = strong ] || { echo "ROUTE TIER FAIL (>=5 points is strong)"; exit 1; }
    [ "$("$SELF" route --points 3 --risk normal | head -1)" = mid ]    || { echo "ROUTE TIER FAIL (3 points is mid)"; exit 1; }
    [ "$("$SELF" route --points 1 --risk normal | head -1)" = cheap ]  || { echo "ROUTE TIER FAIL (<=1 point is cheap)"; exit 1; }
    [ "$("$SELF" route --points 2 --risk high   | head -1)" = strong ] || { echo "ROUTE TIER FAIL (risk must dominate points)"; exit 1; }
    [ "$("$SELF" route --points x --risk normal | head -1)" = mid ]    || { echo "ROUTE TIER FAIL (non-numeric points is the safe middle, NEVER an error)"; exit 1; }
    [ "$("$SELF" route --points 5 --risk normal | wc -l | tr -d ' ')" = 1 ] || { echo "ROUTE QUIET FAIL (an unset knob must print NOTHING but the tier word)"; exit 1; }
    # 2) the role table, and the only two things route is allowed to refuse. An unknown role is mid
    #    at rc 0 on purpose — routing must never be the reason a piece of work cannot start.
    [ "$("$SELF" route --role PLANNER | head -1)" = strong ] || { echo "ROUTE ROLE FAIL (PLANNER is strong)"; exit 1; }
    [ "$("$SELF" route --role SOLO    | head -1)" = mid ]    || { echo "ROUTE ROLE FAIL (SOLO is mid)"; exit 1; }
    "$SELF" route --role NO-SUCH-ROLE >/dev/null 2>&1 || { echo "ROUTE ROLE FAIL (an unknown role must still rc 0 — routing never blocks work)"; exit 1; }
    [ "$("$SELF" route --role NO-SUCH-ROLE | head -1)" = mid ] || { echo "ROUTE ROLE FAIL (an unknown role falls back to mid)"; exit 1; }
    "$SELF" route >/dev/null 2>&1 && { echo "ROUTE USAGE FAIL (no args must rc 1)"; exit 1; }
    "$SELF" route T-NOPE >/dev/null 2>&1 && { echo "ROUTE ID FAIL (an unknown ID must rc 1)"; exit 1; }
    # 3) the note, via a FIXTURE CONVENTIONS: three-space indent (triage's shape), the knob's value
    #    with its owner comment stripped, and strictly per-tier — model_mid is left unset here, so
    #    mid must stay a bare word while its neighbours note.
    printf 'model_strong: drill-strong-9   # owner comment, stripped by cfg\nmodel_cheap: drill-cheap-2\n' > ops/CONVENTIONS.md
    "$SELF" route --points 5 --risk normal | awk 'NR==2 && $0 == "   model: drill-strong-9" { ok=1 } END { exit !ok }' \
      || { "$SELF" route --points 5 --risk normal; echo "ROUTE NOTE FAIL (want line 2 = three spaces + 'model: <knob value>')"; exit 1; }
    [ "$("$SELF" route --points 1 --risk normal | wc -l | tr -d ' ')" = 2 ] || { echo "ROUTE NOTE FAIL (the cheap knob must note too)"; exit 1; }
    [ "$("$SELF" route --points 3 --risk normal | wc -l | tr -d ' ')" = 1 ] || { echo "ROUTE NOTE FAIL (model_mid is unset — mid must stay a bare word)"; exit 1; }
    # 4) the task override, both shapes. A tier WORD wins outright and the OVERRIDDEN tier's knob is
    #    the one that speaks; any other value is a literal model name, and then line 1 stays the
    #    DERIVED tier (informational) while the note carries the name verbatim, knob or no knob.
    printf -- '---\nid: T-RTW\npoints: 5\nwsjf: 1\nrisk: normal\nmodel: cheap\nstatus: ready\nfiles_owned:\n  - src/rtw.txt\n---\n' > ops/board/ready/T-RTW.md
    printf -- '---\nid: T-RTL\npoints: 5\nwsjf: 1\nrisk: normal\nmodel: drill-literal-7\nstatus: ready\nfiles_owned:\n  - src/rtl.txt\n---\n' > ops/board/ready/T-RTL.md
    [ "$("$SELF" route T-RTW | head -1)" = cheap ] || { echo "ROUTE OVERRIDE FAIL (a tier-word model: must beat the derived tier)"; exit 1; }
    "$SELF" route T-RTW | awk 'NR==2 && $0 == "   model: drill-cheap-2" { ok=1 } END { exit !ok }' \
      || { "$SELF" route T-RTW; echo "ROUTE OVERRIDE FAIL (the overridden tier's knob is the one that notes)"; exit 1; }
    [ "$("$SELF" route T-RTL | head -1)" = strong ] || { echo "ROUTE LITERAL FAIL (line 1 stays the DERIVED tier)"; exit 1; }
    "$SELF" route T-RTL | awk 'NR==2 && $0 == "   model: drill-literal-7" { ok=1 } END { exit !ok }' \
      || { "$SELF" route T-RTL; echo "ROUTE LITERAL FAIL (a literal model: name must reach the note verbatim)"; exit 1; }
    # 5) fleet carries the ready queue's MAX tier: panes claim RACILY, so every pane must be able to
    #    afford the hardest task on the board. T-RTL is 5 points, so strong is the max whatever else
    #    is queued. The launcher needs a runnable tmux + claude or it falls through to "found no
    #    terminal" and this would pass VACUOUSLY — so plant stubs (--dry-run never executes them)
    #    and prepend them. The bin lives under $T, i.e. mktemp's /tmp path, ON PURPOSE: Git Bash
    #    SPLITS a PATH entry at its colon, so a C:/… entry silently becomes two broken ones.
    mkdir -p "$T/rtbin"
    printf '#!/bin/sh\nexit 0\n' > "$T/rtbin/tmux";   chmod +x "$T/rtbin/tmux"
    printf '#!/bin/sh\nexit 0\n' > "$T/rtbin/claude"; chmod +x "$T/rtbin/claude"
    PATH="$T/rtbin:$PATH" "$SELF" fleet 2 --dry-run > "$T/rt-fleet.out" 2>&1 || { cat "$T/rt-fleet.out"; echo "ROUTE FLEET FAIL (fleet --dry-run must rc 0)"; exit 1; }
    grep -q '\[dry-run\]' "$T/rt-fleet.out" || { cat "$T/rt-fleet.out"; echo "ROUTE FLEET FAIL (no launcher preview — the stub CLIs did not take)"; exit 1; }
    grep -q -- '--model drill-strong-9' "$T/rt-fleet.out" || { cat "$T/rt-fleet.out"; echo "ROUTE FLEET FAIL (the pane command must carry the ready queue's max tier)"; exit 1; }
    rm -f ops/CONVENTIONS.md
    PATH="$T/rtbin:$PATH" "$SELF" fleet 2 --dry-run > "$T/rt-fleet2.out" 2>&1 || { cat "$T/rt-fleet2.out"; echo "ROUTE FLEET FAIL (unrouted fleet --dry-run must rc 0)"; exit 1; }
    grep -q -- '--model' "$T/rt-fleet2.out" && { cat "$T/rt-fleet2.out"; echo "ROUTE FLEET FAIL (unset knobs must change NOTHING — no token at all)"; exit 1; }
    # hermetic teardown: the fixture leaves exactly as it was found
    rm -rf "$T/rtbin"; rm -f "$T/rt-fleet.out" "$T/rt-fleet2.out"
    rm -f ops/board/ready/T-RTW.md ops/board/ready/T-RTL.md
    [ -f "$T/rt-conv.bak" ] && cp "$T/rt-conv.bak" ops/CONVENTIONS.md || rm -f ops/CONVENTIONS.md
    rm -f "$T/rt-conv.bak"
}
drill_bg() {
    # ---- T-071 bg drill (ops/contracts/bg-jobs.md § Executable check) ----
    # The harness caps a foreground tool call at 600s, so a suite-length command returns NOTHING and
    # gets re-run; `bg` turns "run detached, collect in bounded chunks" into a command instead of a
    # recipe every session re-invents. Its PUBLIC surface is the EXIT CODE — 0 green · 1 red ·
    # 2 running · 3 unknown — because callers branch on it blind, inside compound commands, with
    # nobody reading the prose. Underneath it sits rc-file-FIRST: a pid check alone may NEVER
    # declare a verdict, since Windows reuses pids. All four codes are exercised below.
    # Fast commands only (echo/false/sleep): a drill never waits on a real suite.
    # HERMETIC (T-046): the whole .polaris/bg registry is removed before returning, so a later
    # `finish` — drill_finish's clean rc 0 included — can never inherit a pending job from here.
    rm -rf .polaris/bg
    # 1) green: run → wait collects rc 0 → status agrees → tail carries the command's own stdout.
    "$SELF" bg run bxok -- echo bx-hello >/dev/null || { echo "BG RUN FAIL (a green job must start rc 0)"; exit 1; }
    "$SELF" bg wait bxok --max 60 > "$T/bx1.out" 2>&1 || { cat "$T/bx1.out"; echo "BG GREEN FAIL (wait must exit 0 on a green job)"; exit 1; }
    "$SELF" bg status bxok >/dev/null 2>&1 || { echo "BG GREEN FAIL (status must exit 0 on a green job)"; exit 1; }
    "$SELF" bg tail bxok | grep -q 'bx-hello' || { echo "BG TAIL FAIL (the job's own stdout must reach the log)"; exit 1; }
    # 2) red is HONEST: the command's failure IS the job's verdict, never swallowed into a green.
    "$SELF" bg run bxred -- false >/dev/null || { echo "BG RUN FAIL (starting a doomed job is still rc 0)"; exit 1; }
    "$SELF" bg wait bxred --max 60 >/dev/null 2>&1 && { echo "BG RED FAIL (wait must exit 1 on a red job)"; exit 1; }
    "$SELF" bg status bxred >/dev/null 2>&1 && { echo "BG RED FAIL (status must exit 1 on a red job)"; exit 1; }
    # 3) running: rc 2, a same-name run REFUSES instead of racing, and --force replaces it.
    "$SELF" bg run bxslow -- sleep 30 >/dev/null || { echo "BG RUN FAIL (the long job must start)"; exit 1; }
    bx_rc=0; "$SELF" bg status bxslow >/dev/null 2>&1 || bx_rc=$?
    [ "$bx_rc" = 2 ] || { echo "BG RUNNING FAIL (a live job must status rc 2, got $bx_rc)"; exit 1; }
    "$SELF" bg run bxslow -- true > "$T/bx2.out" 2>&1 && { cat "$T/bx2.out"; echo "BG DUPLICATE FAIL (a RUNNING same-name job must refuse, not race)"; exit 1; }
    grep -q 'already RUNNING' "$T/bx2.out" || { cat "$T/bx2.out"; echo "BG DUPLICATE MSG FAIL (the refusal must say why and name bg status)"; exit 1; }
    "$SELF" bg run bxslow --force -- echo bx-forced >/dev/null || { echo "BG FORCE FAIL (--force must kill, rotate and start fresh)"; exit 1; }
    "$SELF" bg wait bxslow --max 60 >/dev/null 2>&1 || { echo "BG FORCE FAIL (the forced replacement must run to green)"; exit 1; }
    # 3b) T-104 (bg-jobs.md v2): OWNERSHIP is the job's own `cwd` file. Five sessions each running
    #     `bg run qa` used to rotate one another's LIVE job into .prev, and --force killed by a pid
    #     Windows may since have reused. A live same-name job started from ANOTHER cwd is refused
    #     with AND without --force, and — the part that matters — it survives the refusal untouched.
    "$SELF" bg run bxown -- sleep 30 >/dev/null || { echo "BG RUN FAIL (the ownership fixture job must start)"; exit 1; }
    bx_rc=0; ( cd src && "$SELF" bg run bxown -- true ) > "$T/bx6.out" 2>&1 || bx_rc=$?
    [ "$bx_rc" = 1 ] || { cat "$T/bx6.out"; echo "BG FOREIGN RC FAIL (a live job owned by another cwd must refuse rc 1, got $bx_rc)"; exit 1; }
    grep -q "is RUNNING from another session" "$T/bx6.out" || { cat "$T/bx6.out"; echo "BG FOREIGN MSG FAIL (the refusal must name the owning cwd, not the v1 duplicate line)"; exit 1; }
    bx_rc=0; ( cd src && "$SELF" bg run bxown --force -- true ) > "$T/bx7.out" 2>&1 || bx_rc=$?
    [ "$bx_rc" = 1 ] || { cat "$T/bx7.out"; echo "BG FOREIGN FORCE RC FAIL (--force must NOT lift a foreign refusal, got $bx_rc)"; exit 1; }
    bx_rc=0; "$SELF" bg status bxown >/dev/null 2>&1 || bx_rc=$?
    [ "$bx_rc" = 2 ] || { echo "BG FOREIGN SURVIVE FAIL (the refused-against job must still be RUNNING, got $bx_rc)"; exit 1; }
    [ -d .polaris/bg/bxown.prev ] && { echo "BG FOREIGN ROTATE FAIL (a foreign run must not rotate a live job away)"; exit 1; }
    "$SELF" bg run bxown --force -- echo bx-own-forced >/dev/null || { echo "BG OWN FORCE FAIL (the job's OWN cwd may still --force it)"; exit 1; }
    "$SELF" bg wait bxown --max 60 >/dev/null 2>&1 || { echo "BG OWN FORCE FAIL (the forced replacement must collect green)"; exit 1; }
    # 4) rotation ARCHIVES: one .prev slot per name, holding the run it replaced — never a delete.
    "$SELF" bg run bxok -- echo bx-second >/dev/null || { echo "BG ROTATE FAIL (a finished name must be re-runnable)"; exit 1; }
    [ -d .polaris/bg/bxok.prev ] || { echo "BG ROTATE FAIL (the finished run must archive to <name>.prev)"; exit 1; }
    grep -q 'bx-hello' .polaris/bg/bxok.prev/cmd || { echo "BG ROTATE FAIL (.prev must hold the PREVIOUS run, not the new one)"; exit 1; }
    "$SELF" bg wait bxok --max 60 >/dev/null 2>&1 || { echo "BG ROTATE FAIL (the replacement job must still collect green)"; exit 1; }
    # 5) unknown: no rc file and a DEAD pid is rc 3 — the one case bash cannot solve, only order
    #    around. A REAPED child's pid is dead by construction: no sleeping, no guessed pid number.
    ( exit 0 ) & bx_ghost=$!
    wait "$bx_ghost" 2>/dev/null || true
    mkdir -p .polaris/bg/bxghost
    printf '%s\n' "$bx_ghost" > .polaris/bg/bxghost/pid
    printf 'true\n' > .polaris/bg/bxghost/cmd
    date +%s > .polaris/bg/bxghost/start
    : > .polaris/bg/bxghost/log
    bx_rc=0; "$SELF" bg status bxghost >/dev/null 2>&1 || bx_rc=$?
    [ "$bx_rc" = 3 ] || { echo "BG UNKNOWN FAIL (a dead pid with no rc must be rc 3, got $bx_rc)"; exit 1; }
    # 6) finish's bg guard (bg-jobs.md § finish): a job with no rc is a suite still in flight — or a
    #    crash nobody collected — and either way the run is NOT over. Invariant 4, mechanically.
    "$SELF" finish > "$T/bx3.out" 2>&1 || true
    grep -q 'background job bxghost' "$T/bx3.out" || { cat "$T/bx3.out"; echo "BG FINISH GUARD FAIL (an uncollected job must be a pending item)"; exit 1; }
    grep -q 'bg status bxghost' "$T/bx3.out" || { cat "$T/bx3.out"; echo "BG FINISH GUARD FAIL (a dead-pid unknown must name bg status, not bg wait)"; exit 1; }
    # 7) sweep: a job dir whose start is >24h old is leftover runtime state. BACKDATE it — a drill
    #    that sleeps for a threshold is a drill nobody runs. --fix rotates it; it never deletes.
    printf '%s\n' "$(( $(date +%s) - 90000 ))" > .polaris/bg/bxred/start
    "$SELF" sweep > "$T/bx4.out" 2>&1 || true
    grep -q 'STALE bg job: bxred' "$T/bx4.out" || { cat "$T/bx4.out"; echo "BG SWEEP FAIL (a >24h job must be reported)"; exit 1; }
    "$SELF" sweep --fix > "$T/bx5.out" 2>&1 || true
    [ -d .polaris/bg/bxred.prev ] || { cat "$T/bx5.out"; echo "BG SWEEP FIX FAIL (--fix must rotate the stale job — archive, never delete)"; exit 1; }
    [ -d .polaris/bg/bxred ] && { echo "BG SWEEP FIX FAIL (the stale job must leave the LIVE registry)"; exit 1; }
    # hermetic teardown: no job dirs, no scratch output — the fixture as it was found
    rm -rf .polaris/bg
    rm -f "$T/bx1.out" "$T/bx2.out" "$T/bx3.out" "$T/bx4.out" "$T/bx5.out" "$T/bx6.out" "$T/bx7.out"
}
drill_checkoutguard() {
    # ---- T-089 checkoutguard drill (ops/contracts/shared-checkout.md v2 §6) ----
    # Layer 1 (checkout-guard.sh): a checkout-mutating git line from the PRIMARY denies via
    # hookSpecificOutput JSON on STDOUT — contract v2.1, NOT ownership-guard's exit-2+stderr; the
    # two hooks deny by DIFFERENT mechanisms and BOTH are correct as shipped, so this drill asserts
    # each hook's own shape and never a shared one. Layer 2 (primary_gate): a primary write to
    # tracked source while a task lock is live denies exit 2 + stderr; board surfaces and lock-free
    # repos stay open. Plus the FALLBACK entry every conductor lane actually takes: cwd pinned at
    # the primary, a write + commit via ABSOLUTE paths under .polaris/wt/<ID> is allowed by BOTH
    # hooks and the commit lands on feat/<ID>.
    # Payload paths are GIT-CANONICAL (rev-parse --show-toplevel, C:/… on Windows), never $PWD —
    # ownership-guard norm()s both sides against git's own spelling, and a /tmp-style path here
    # reads as "outside the repo" (the exact fragility that pulled the old wrapper harness).
    ckg_hook="$(dirname "$SELF")/hooks/checkout-guard.sh"
    ckg_og="$(dirname "$SELF")/hooks/ownership-guard.sh"
    ckg_top="$(git rev-parse --show-toplevel)"
    ckg_lk="$(git rev-parse --git-common-dir)/polaris-locks"
    git checkout -q main
    mkdir -p "$T/ckg"
    # (1) the deny SHAPE: primary cwd + `git switch x` → rc 0, hookSpecificOutput JSON on STDOUT
    #     carrying the pinned refusal, and NOTHING on stderr.
    ckg_rc=0
    printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"git switch x"}}' "$ckg_top" \
      | bash "$ckg_hook" > "$T/ckg/1.out" 2> "$T/ckg/1.err" || ckg_rc=$?
    [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/1.out" "$T/ckg/1.err"; echo "CKG DENY RC FAIL (the JSON deny exits 0, never 2)"; exit 1; }
    grep -q '"hookSpecificOutput"' "$T/ckg/1.out" || { cat "$T/ckg/1.out"; echo "CKG DENY SHAPE FAIL (deny must be hookSpecificOutput JSON on STDOUT)"; exit 1; }
    grep -q '"permissionDecision":"deny"' "$T/ckg/1.out" || { cat "$T/ckg/1.out"; echo "CKG DENY DECISION FAIL (the JSON must carry permissionDecision deny)"; exit 1; }
    grep -q 'the primary checkout is shared' "$T/ckg/1.out" || { cat "$T/ckg/1.out"; echo "CKG DENY MSG FAIL (the pinned refusal must ride the JSON)"; exit 1; }
    [ -s "$T/ckg/1.err" ] && { cat "$T/ckg/1.err"; echo "CKG DENY STDERR FAIL (stderr denies are ownership-guard's mechanism, never this hook's)"; exit 1; }
    # (2) the same command with cwd inside .polaris/wt/<ID> → rc 0 and NO output at all
    printf '{"cwd":"%s/.polaris/wt/T-000","tool_name":"Bash","tool_input":{"command":"git switch x"}}' "$ckg_top" \
      | bash "$ckg_hook" > "$T/ckg/2.out" 2>&1 || { echo "CKG WT RC FAIL"; exit 1; }
    [ -s "$T/ckg/2.out" ] && { cat "$T/ckg/2.out"; echo "CKG WT ALLOW FAIL (a task worktree keeps every git form that cannot destroy one)"; exit 1; }
    # (2b) T-104 (shared-checkout.md v2.5 §3): the guard learned the OTHER destroyers. Removing a
    #      worktree, `rm -rf`ing .polaris and killing by name end another session's work from ANY
    #      checkout — there is no cwd where they are the right move — so gate 2's worktree carve-out
    #      does not cover them and gate 4's placement probe is skipped entirely: same JSON deny,
    #      everywhere. Asserted three ways, because two of them are not enough: rc, the JSON shape,
    #      and --test's CLASS word. The class is the load-bearing one — every deny arm falls back to
    #      the generic switch-the-primary message, so "it denied" and even "it denied with SOME
    #      message" both stay true while the class silently drops out of its own arm.
    ckg_rc=0
    printf '{"cwd":"%s/.polaris/wt/T-000","tool_name":"Bash","tool_input":{"command":"git worktree remove .polaris/wt/T-001"}}' "$ckg_top" \
      | bash "$ckg_hook" > "$T/ckg/2b.out" 2> "$T/ckg/2b.err" || ckg_rc=$?
    [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/2b.out" "$T/ckg/2b.err"; echo "CKG WT-REMOVE RC FAIL (the JSON deny exits 0, never 2)"; exit 1; }
    grep -q '"permissionDecision":"deny"' "$T/ckg/2b.out" || { cat "$T/ckg/2b.out"; echo "CKG WT-REMOVE SHAPE FAIL (a removal from a worktree cwd must deny, never ride the carve-out)"; exit 1; }
    grep -q 'a task worktree may be another session' "$T/ckg/2b.out" || { cat "$T/ckg/2b.out"; echo "CKG WT-REMOVE MSG FAIL (the pinned worktree refusal must ride the JSON)"; exit 1; }
    [ -s "$T/ckg/2b.err" ] && { cat "$T/ckg/2b.err"; echo "CKG WT-REMOVE STDERR FAIL (this hook denies on stdout, never stderr)"; exit 1; }
    ckg_rc=0
    printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"rm -rf .polaris"}}' "$ckg_top" \
      | bash "$ckg_hook" > "$T/ckg/2c.out" 2>&1 || ckg_rc=$?
    [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/2c.out"; echo "CKG RM-POLARIS RC FAIL"; exit 1; }
    grep -q '"permissionDecision":"deny"' "$T/ckg/2c.out" || { cat "$T/ckg/2c.out"; echo "CKG RM-POLARIS SHAPE FAIL (rm -rf .polaris takes every session's worktrees, locks and jobs at once)"; exit 1; }
    #      And the message, per class, on the JSON path — because --test prints the class out of
    #      $HIT, so it reads deny:rm-polaris whichever arm of the dispatch actually fired. Only the
    #      text tells you a class fell through to the generic refusal and started telling people to
    #      work in their worktree when what they did was delete everyone's.
    for ckg_c in "git worktree remove .polaris/wt/T-001|a task worktree may be another session" \
                 "rm -rf .polaris|a task worktree may be another session" \
                 "git push origin --delete feat/T-001|never delete origin refs by hand" \
                 "pkill -f uvicorn|never kill by name or kill the whole tree"; do
      ckg_want="${ckg_c#*|}"; ckg_case="${ckg_c%%|*}"
      printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$ckg_top" "$ckg_case" \
        | bash "$ckg_hook" > "$T/ckg/2e.out" 2>&1 || { cat "$T/ckg/2e.out"; echo "CKG MSG RC FAIL ($ckg_case)"; exit 1; }
      grep -q "$ckg_want" "$T/ckg/2e.out" || { cat "$T/ckg/2e.out"; echo "CKG MSG FAIL ($ckg_case must carry its OWN pinned refusal, never another arm's)"; exit 1; }
    done
    for ckg_c in "$ckg_top/.polaris/wt/T-000|git worktree remove .polaris/wt/T-001|deny:worktree-remove" \
                 "$ckg_top|git worktree prune|deny:worktree-prune" \
                 "$ckg_top|rm -rf .polaris|deny:rm-polaris" \
                 "$ckg_top|pkill -f uvicorn|deny:kill-broad" \
                 "$ckg_top|git clean -fdx|deny:clean"; do
      ckg_want="${ckg_c##*|}"; ckg_case="${ckg_c%|*}"
      [ "$(bash "$ckg_hook" --test "$ckg_case" | tr -d ' \r')" = "$ckg_want" ] \
        || { echo "CKG CLASS FAIL ($ckg_case must fire $ckg_want, not another arm's message)"; exit 1; }
    done
    #      The allows are as load-bearing as the denies: a pid-targeted kill is how a session ends
    #      its OWN job, a dry-run clean is how anyone checks what a real one would take, and
    #      node_modules is not .polaris. Deny narrowly, or the guard becomes noise and gets removed.
    for ckg_c in 'kill 1234' 'kill -9 1234' 'taskkill /PID 1234 /F' 'git clean -n' 'rm -rf node_modules'; do
      ckg_rc=0
      printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$ckg_top" "$ckg_c" \
        | bash "$ckg_hook" > "$T/ckg/2d.out" 2>&1 || ckg_rc=$?
      [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/2d.out"; echo "CKG ALLOW RC FAIL ($ckg_c)"; exit 1; }
      [ -s "$T/ckg/2d.out" ] && { cat "$T/ckg/2d.out"; echo "CKG ALLOW FAIL ($ckg_c must pass silently)"; exit 1; }
      [ "$(bash "$ckg_hook" --test "$ckg_top|$ckg_c" | tr -d ' \r')" = allow ] \
        || { echo "CKG ALLOW CLASS FAIL ($ckg_c must reach no parser at all)"; exit 1; }
    done
    # (3) read-only git in the primary passes silently — and `git stash list` / `git stash show`
    #     are the §1 carve-out: the only read-only stash forms, allowed on purpose (denying them
    #     would break the allow/deny disjointness the two-hook design rests on).
    for ckg_c in 'git status' 'git stash list' 'git stash show'; do
      printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$ckg_top" "$ckg_c" \
        | bash "$ckg_hook" > "$T/ckg/3.out" 2>&1 || { echo "CKG READONLY RC FAIL ($ckg_c)"; exit 1; }
      [ -s "$T/ckg/3.out" ] && { cat "$T/ckg/3.out"; echo "CKG READONLY FAIL ($ckg_c must pass silently in the primary)"; exit 1; }
    done
    # (4) primary_gate. Precondition: no live task locks leaked here by a sibling drill — a leak
    #     would flip the no-lock case, so name it honestly instead of failing cryptically.
    for ckg_d in "$ckg_lk"/*/; do
      [ -d "$ckg_d" ] || continue
      case "${ckg_d%/}" in */.int-lease|*/.board-mutex) continue;; esac
      echo "CKG PRECOND FAIL (unexpected live lock $ckg_d — a prior drill leaked)"; exit 1
    done
    # The throwaway repo has no ops/polaris (init-board installs none) and the hook stands down
    # without one — plant a forwarder to "$SELF" so the gate is armed, remove it in teardown.
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$SELF" > ops/polaris
    chmod +x ops/polaris
    mkdir -p "$ckg_lk/T-CKL"
    ckg_rc=0
    printf '{"cwd":"%s","tool_input":{"file_path":"%s/src/a.txt","new_string":"ckg"}}' "$ckg_top" "$ckg_top" \
      | bash "$ckg_og" > /dev/null 2> "$T/ckg/4.err" || ckg_rc=$?
    [ "$ckg_rc" -eq 2 ] || { cat "$T/ckg/4.err"; echo "CKG PRIMARY DENY FAIL (tracked source + live lock + non-feat HEAD must exit 2, got $ckg_rc)"; exit 1; }
    grep -q 'builders never edit the shared primary' "$T/ckg/4.err" || { cat "$T/ckg/4.err"; echo "CKG PRIMARY MSG FAIL (the pinned refusal must reach stderr — THIS hook's mechanism)"; exit 1; }
    ckg_rc=0
    printf '{"cwd":"%s","tool_input":{"file_path":"%s/ops/board/backlog/IDEAS.md","new_string":"ckg"}}' "$ckg_top" "$ckg_top" \
      | bash "$ckg_og" > /dev/null 2> "$T/ckg/5.err" || ckg_rc=$?
    [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/5.err"; echo "CKG BOARD ALLOW FAIL (ops/board/ is a primary-role surface, got rc $ckg_rc)"; exit 1; }
    rm -rf "$ckg_lk/T-CKL"
    ckg_rc=0
    printf '{"cwd":"%s","tool_input":{"file_path":"%s/src/a.txt","new_string":"ckg"}}' "$ckg_top" "$ckg_top" \
      | bash "$ckg_og" > /dev/null 2> "$T/ckg/6.err" || ckg_rc=$?
    [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/6.err"; echo "CKG NOLOCK ALLOW FAIL (no live locks = nobody to collide with = no gate, got rc $ckg_rc)"; exit 1; }
    # (5) the FALLBACK entry (contract v2.6): a REAL claim, then everything via absolute paths from
    #     the pinned primary cwd — allowed by both hooks, and the commit advances feat/<ID>.
    printf -- '---\nid: T-CKF\npoints: 1\nwsjf: 5\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/ckf.txt\nverify: []\n---\n' > ops/board/ready/T-CKF.md
    "$SELF" claim T-CKF >/dev/null
    ckg_wt="$ckg_top/.polaris/wt/T-CKF"
    ckg_rc=0
    printf '{"cwd":"%s","tool_input":{"file_path":"%s/src/ckf.txt","new_string":"ckg"}}' "$ckg_top" "$ckg_wt" \
      | bash "$ckg_og" > /dev/null 2> "$T/ckg/7.err" || ckg_rc=$?
    [ "$ckg_rc" -eq 0 ] || { cat "$T/ckg/7.err"; echo "CKG FALLBACK OG FAIL (an absolute .polaris/wt/<ID> write from the primary rides the allowlist, got rc $ckg_rc)"; exit 1; }
    printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"git -C %s commit -am ok"}}' "$ckg_top" "$ckg_wt" \
      | bash "$ckg_hook" > "$T/ckg/8.out" 2>&1 || { echo "CKG FALLBACK HOOK RC FAIL"; exit 1; }
    [ -s "$T/ckg/8.out" ] && { cat "$T/ckg/8.out"; echo "CKG FALLBACK HOOK FAIL (git commit is not checkout-mutating)"; exit 1; }
    ckg_pre="$(git rev-parse feat/T-CKF)"
    echo ckg > "$ckg_wt/src/ckf.txt"
    git -C "$ckg_wt" add -A
    git -C "$ckg_wt" commit -qm 'ckg: fallback entry'
    [ "$(git rev-parse feat/T-CKF)" != "$ckg_pre" ] || { echo "CKG FALLBACK COMMIT FAIL (the commit must advance feat/T-CKF)"; exit 1; }
    [ "$(git -C "$ckg_wt" rev-parse --abbrev-ref HEAD)" = "feat/T-CKF" ] || { echo "CKG FALLBACK BRANCH FAIL (the worktree HEAD must be feat/T-CKF)"; exit 1; }
    # hermetic teardown: forwarder gone, fixture task gone, branch gone, scratch gone
    "$SELF" release T-CKF --to ready -m drill >/dev/null
    rm -f ops/board/ready/T-CKF.md ops/polaris
    git branch -q -D feat/T-CKF 2>/dev/null || true
    rm -rf "$T/ckg"
}
drill_awake() {
    # ---- T-104 keep-awake drill (ops/contracts/keep-awake.md § drill) ----
    # ONE keep-awake owner per MACHINE: awake while ANY session is still working, gone once they all
    # are, never pressing at a human who is typing. Every one of those words is a race, a registry
    # file or a process lifetime, so prose cannot hold it — but neither can a drill that waits on
    # real clocks. The contract answers that with SEAMS: POLARIS_AWAKE_HOME moves the whole registry
    # into the fixture, POLARIS_AWAKE_PRESSER replaces the key press with `touch` (nothing on this
    # machine is ever pressed by a test), TICK/IDLE/STALE/GRACE shrink minutes into seconds, and
    # POLARIS_AWAKE_SPAWN=inline keeps the daemon inside this process tree so the drill can prove it
    # LEFT. Everything here is rc + file state.
    # CLAUDE_PID is pinned to `-` on the four hook calls: ah_verdict reaps a session whose recorded
    # pid is dead, and inheriting a real harness pid would make the verdict depend on `ps -W` telling
    # the truth about a process this drill does not own. `-` is the documented "no pid" and is the
    # same on every platform.
    aw_hook="$(dirname "$SELF")/hooks/awake-hook.sh"
    aw_home="${POLARIS_AWAKE_HOME:-$T/awake-home}"
    aw_cwd="$(git rev-parse --show-toplevel)"
    aw_wtp='C:\\Users\\x\\.claude\\projects\\p\\drill-sid-1.jsonl'   # JSON-escaped, as a real Windows payload arrives
    rm -rf "$aw_home" "$T/aw"
    mkdir -p "$aw_home/sessions" "$aw_home/repos" "$aw_home/daemon" "$T/aw"
    aw_tp="$T/aw/transcript.jsonl"; : > "$aw_tp"
    export POLARIS_AWAKE_PRESSER="touch $T/aw/pressed"
    export POLARIS_AWAKE_IDLE=3 POLARIS_AWAKE_STALE=5 POLARIS_AWAKE_GRACE=2 POLARIS_AWAKE_SPAWN=inline
    # (1) the four hooks. They run on EVERY turn of every session, so their contract is silence:
    #     UserPromptSubmit stdout is injected into the model's context and rc 2 on Stop means "keep
    #     going". Zero stdout, zero stderr, rc 0 — and `start` never downgrades a session mid-turn.
    export POLARIS_AWAKE_TICK=60                      # a wide freshness window: step 1 wants no daemon
    date +%s > "$aw_home/daemon/beat"
    for aw_sub in start busy idle end; do
      aw_rc=0
      printf '{"session_id":"drill-sid-1","transcript_path":"%s","cwd":"%s","hook_event_name":"x"}' "$aw_wtp" "$aw_cwd" \
        | CLAUDE_PID=- bash "$aw_hook" "$aw_sub" > "$T/aw/h.out" 2> "$T/aw/h.err" || aw_rc=$?
      [ "$aw_rc" -eq 0 ] || { cat "$T/aw/h.err"; echo "AWAKE HOOK RC FAIL ($aw_sub must always exit 0)"; exit 1; }
      [ -s "$T/aw/h.out" ] && { cat "$T/aw/h.out"; echo "AWAKE HOOK STDOUT FAIL ($aw_sub must print NOTHING)"; exit 1; }
      [ -s "$T/aw/h.err" ] && { cat "$T/aw/h.err"; echo "AWAKE HOOK STDERR FAIL ($aw_sub must print NOTHING)"; exit 1; }
      case "$aw_sub" in
        start)
          [ "$(sed -n 1p "$aw_home/sessions/drill-sid-1" | cut -d' ' -f1)" = idle ] || { echo "AWAKE START FAIL (an unknown session is created idle)"; exit 1; }
          [ "$(sed -n 2p "$aw_home/sessions/drill-sid-1" | tr -d '\r')" = 'C:\Users\x\.claude\projects\p\drill-sid-1.jsonl' ] \
            || { echo "AWAKE START PATH FAIL (jstr must decode the escaped backslashes of a Windows transcript path)"; exit 1; }
          [ "$(sed -n 3p "$aw_home/sessions/drill-sid-1" | tr -d '\r')" = '-' ] || { echo "AWAKE START PID FAIL (an absent pid is the dash, never empty)"; exit 1; }
          ;;
        busy)
          [ "$(sed -n 1p "$aw_home/sessions/drill-sid-1" | cut -d' ' -f1)" = busy ] || { echo "AWAKE BUSY FAIL"; exit 1; }
          aw_k="$(printf '%s' "$aw_cwd" | cksum)"; aw_k="${aw_k%% *}"
          [ -f "$aw_home/repos/$aw_k" ] || { echo "AWAKE BUSY REPO FAIL (a busy session registers its primary)"; exit 1; }
          # the whole reason `start` is conditional: a compact or resume fires SessionStart mid-turn
          printf '{"session_id":"drill-sid-1","transcript_path":"%s","cwd":"%s","hook_event_name":"x"}' "$aw_wtp" "$aw_cwd" \
            | CLAUDE_PID=- bash "$aw_hook" start >/dev/null 2>&1 || { echo "AWAKE RESTART RC FAIL"; exit 1; }
          [ "$(sed -n 1p "$aw_home/sessions/drill-sid-1" | cut -d' ' -f1)" = busy ] \
            || { echo "AWAKE NO-DOWNGRADE FAIL (a compact/resume SessionStart must never turn a busy session idle)"; exit 1; }
          ;;
        idle) [ "$(sed -n 1p "$aw_home/sessions/drill-sid-1" | cut -d' ' -f1)" = idle ] || { echo "AWAKE IDLE FAIL"; exit 1; };;
        end)  [ -f "$aw_home/sessions/drill-sid-1" ] && { echo "AWAKE END FAIL (SessionEnd forgets the session outright)"; exit 1; };;
      esac
    done
    # (2) a busy session whose transcript was touched NOW is work in flight: the daemon comes up
    #     inline and presses within a tick. The presser is the stub, so the proof is a file appearing.
    export POLARIS_AWAKE_TICK=1
    rm -f "$aw_home/daemon/beat" "$T/aw/pressed"
    : > "$aw_tp"
    printf '{"session_id":"drill-sid-2","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$aw_tp" "$aw_cwd" \
      | CLAUDE_PID=- bash "$aw_hook" busy >/dev/null 2>&1 || { echo "AWAKE BUSY SPAWN RC FAIL"; exit 1; }
    aw_i=0; while [ "$aw_i" -lt 40 ]; do [ -f "$T/aw/pressed" ] && break; sleep 0.1; aw_i=$((aw_i+1)); done
    [ -f "$T/aw/pressed" ] || { cat "$aw_home/daemon/log" 2>/dev/null; echo "AWAKE PRESS FAIL (a busy session with a live transcript must press within 3s)"; exit 1; }
    [ "$(tr -d ' \r' < "$aw_home/daemon/last-press")" = pressed ] || { echo "AWAKE PRESS WORD FAIL (the presser's ONE word is recorded verbatim)"; exit 1; }
    [ -d "$aw_home/lock" ] || { echo "AWAKE LOCK FAIL (the running daemon holds the mkdir singleton)"; exit 1; }
    # (3) every session idle and stale ⇒ nothing presses, and the daemon LEAVES on its own after
    #     GRACE. A keep-awake that needs stopping by hand is a keep-awake nobody dares to start.
    rm -f "$T/aw/pressed"
    touch -t 200001010000 "$aw_tp"
    printf '{"session_id":"drill-sid-2","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$aw_tp" "$aw_cwd" \
      | CLAUDE_PID=- bash "$aw_hook" idle >/dev/null 2>&1 || { echo "AWAKE IDLE RC FAIL"; exit 1; }
    aw_i=0; while [ "$aw_i" -lt 150 ]; do [ -d "$aw_home/lock" ] || break; sleep 0.1; aw_i=$((aw_i+1)); done
    [ -d "$aw_home/lock" ] && { cat "$aw_home/daemon/log"; echo "AWAKE GRACE FAIL (a quiet machine must let the daemon go, and the lock with it)"; exit 1; }
    [ -f "$T/aw/pressed" ] && { echo "AWAKE QUIET PRESS FAIL (nothing presses once every session is idle)"; exit 1; }
    # (4) the stale-daemon steal: a lock left by a hard-killed daemon must not deadlock the machine
    #     forever. The BEAT decides, never the lock — plant a lock with a backdated beat and a pid
    #     nobody answers, and the next ensure takes over. Exactly one new daemon, and a fresh beat.
    #     Put the session back to work FIRST, under a wide TICK and a fresh beat, so that `busy` —
    #     which ensures a daemon of its own — spawns nothing: this step must have exactly one
    #     spawner, or it measures the setup instead of the steal.
    : > "$aw_tp"
    date +%s > "$aw_home/daemon/beat"
    printf '{"session_id":"drill-sid-2","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$aw_tp" "$aw_cwd" \
      | CLAUDE_PID=- POLARIS_AWAKE_TICK=60 bash "$aw_hook" busy >/dev/null 2>&1 || { echo "AWAKE STEAL BUSY RC FAIL"; exit 1; }
    [ -d "$aw_home/lock" ] && { echo "AWAKE STEAL SETUP FAIL (a fresh beat must cost the busy hook no daemon)"; exit 1; }
    mkdir -p "$aw_home/lock"
    printf '999999\n' > "$aw_home/daemon/pid"
    printf '0\n' > "$aw_home/daemon/beat"; touch -t 200001010000 "$aw_home/daemon/beat"
    aw_n0="$(grep -c 'daemon up' "$aw_home/daemon/log" 2>/dev/null)" || aw_n0=0
    bash "$aw_hook" ensure "$aw_cwd" >/dev/null 2>&1 || { echo "AWAKE ENSURE RC FAIL (ensure is rc 0 always)"; exit 1; }
    aw_b=0
    aw_i=0; while [ "$aw_i" -lt 80 ]; do
      aw_b="$(cat "$aw_home/daemon/beat" 2>/dev/null)" || aw_b=0
      case "$aw_b" in ''|*[!0-9]*) aw_b=0;; esac
      [ "$aw_b" -gt 0 ] && [ $(( $(date +%s) - aw_b )) -lt 30 ] && break
      sleep 0.1; aw_i=$((aw_i+1))
    done
    [ "$aw_b" -gt 0 ] || { cat "$aw_home/daemon/log"; echo "AWAKE STEAL FAIL (a stale lock must be taken over, and the new daemon must beat)"; exit 1; }
    aw_n1="$(grep -c 'daemon up' "$aw_home/daemon/log" 2>/dev/null)" || aw_n1=0
    [ "$aw_n1" -eq "$(( aw_n0 + 1 ))" ] || { cat "$aw_home/daemon/log"; echo "AWAKE STEAL COUNT FAIL (a steal starts ONE daemon, got $(( aw_n1 - aw_n0 )))"; exit 1; }
    # (5) `stop` is the flag, not a kill: the loop reads it, consumes it and leaves within a tick.
    #     Then `disabled` — the opt-out that still keeps the verdicts honest: an ACTIVE tick, and
    #     nothing pressed.
    : > "$aw_home/stop"
    aw_i=0; while [ "$aw_i" -lt 80 ]; do [ -d "$aw_home/lock" ] || break; sleep 0.1; aw_i=$((aw_i+1)); done
    [ -d "$aw_home/lock" ] && { cat "$aw_home/daemon/log"; echo "AWAKE STOP FAIL (the stop flag must end the loop within a tick)"; exit 1; }
    [ -e "$aw_home/stop" ] && { echo "AWAKE STOP FLAG FAIL (the daemon consumes the flag on its way out)"; exit 1; }
    rm -f "$T/aw/pressed"
    : > "$aw_home/disabled"; : > "$aw_tp"
    bash "$aw_hook" --test tick > "$T/aw/tick.out" 2>&1 || { cat "$T/aw/tick.out"; echo "AWAKE TICK RC FAIL"; exit 1; }
    grep -qx 'tick: active disabled' "$T/aw/tick.out" || { cat "$T/aw/tick.out"; echo "AWAKE DISABLED VERDICT FAIL (the opt-out silences the press, never the verdict)"; exit 1; }
    [ "$(tr -d ' \r' < "$aw_home/daemon/last-press")" = disabled ] || { echo "AWAKE DISABLED WORD FAIL"; exit 1; }
    [ -f "$T/aw/pressed" ] && { echo "AWAKE DISABLED PRESS FAIL (a disabled daemon presses NOTHING)"; exit 1; }
    rm -f "$aw_home/disabled"
    # (6) re-entrant ensure: it fires from claim, status, doctor, handoff and bg run, so the second
    #     one has to cost nothing. A fresh beat ⇒ no second daemon, no fork.
    rm -rf "$aw_home/lock"; rm -f "$aw_home/daemon/beat"
    aw_n0="$(grep -c 'daemon up' "$aw_home/daemon/log" 2>/dev/null)" || aw_n0=0
    bash "$aw_hook" ensure "$aw_cwd" >/dev/null 2>&1 || { echo "AWAKE REENTRANT RC FAIL"; exit 1; }
    aw_i=0; while [ "$aw_i" -lt 80 ]; do [ -s "$aw_home/daemon/beat" ] && break; sleep 0.1; aw_i=$((aw_i+1)); done
    [ -s "$aw_home/daemon/beat" ] || { cat "$aw_home/daemon/log"; echo "AWAKE REENTRANT BEAT FAIL (the first ensure must bring a daemon up)"; exit 1; }
    bash "$aw_hook" ensure "$aw_cwd" >/dev/null 2>&1 || { echo "AWAKE REENTRANT RC FAIL (2)"; exit 1; }
    sleep 0.5
    aw_n1="$(grep -c 'daemon up' "$aw_home/daemon/log" 2>/dev/null)" || aw_n1=0
    [ "$aw_n1" -eq "$(( aw_n0 + 1 ))" ] || { cat "$aw_home/daemon/log"; echo "AWAKE REENTRANT FAIL (two ensures, ONE daemon — got $(( aw_n1 - aw_n0 )))"; exit 1; }
    : > "$aw_home/stop"
    aw_i=0; while [ "$aw_i" -lt 80 ]; do [ -d "$aw_home/lock" ] || break; sleep 0.1; aw_i=$((aw_i+1)); done
    [ -d "$aw_home/lock" ] && { echo "AWAKE REENTRANT STOP FAIL"; exit 1; }
    # (7) the bg-job clause. A detached suite is work with nobody at a keyboard and no transcript
    #     moving — the case the machine used to sleep through. Every session idle, and the verdict
    #     is still ACTIVE because a registered repo holds a live job with no rc file.
    rm -f "$T/aw/pressed"
    touch -t 200001010000 "$aw_tp"
    printf '{"session_id":"drill-sid-2","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$aw_tp" "$aw_cwd" \
      | CLAUDE_PID=- bash "$aw_hook" idle >/dev/null 2>&1 || { echo "AWAKE BGJOB IDLE RC FAIL"; exit 1; }
    bash "$aw_hook" --test tick > "$T/aw/t7a.out" 2>&1 || { cat "$T/aw/t7a.out"; echo "AWAKE BGJOB PRE RC FAIL"; exit 1; }
    grep -qx 'tick: quiet no-press' "$T/aw/t7a.out" || { cat "$T/aw/t7a.out"; echo "AWAKE BGJOB PRE FAIL (with no live job the same registry must read quiet)"; exit 1; }
    mkdir -p "$T/aw/repo/.polaris/bg/awjob"
    sleep 30 & aw_job=$!
    printf '%s\n' "$aw_job" > "$T/aw/repo/.polaris/bg/awjob/pid"
    printf 'sleep 30\n' > "$T/aw/repo/.polaris/bg/awjob/cmd"
    date +%s > "$T/aw/repo/.polaris/bg/awjob/start"
    : > "$T/aw/repo/.polaris/bg/awjob/log"
    aw_k="$(printf '%s' "$T/aw/repo" | cksum)"; aw_k="${aw_k%% *}"
    printf '%s\n' "$T/aw/repo" > "$aw_home/repos/$aw_k"
    bash "$aw_hook" --test tick > "$T/aw/t7b.out" 2>&1 || { cat "$T/aw/t7b.out"; echo "AWAKE BGJOB RC FAIL"; exit 1; }
    grep -qx 'tick: active pressed' "$T/aw/t7b.out" || { cat "$T/aw/t7b.out"; echo "AWAKE BGJOB FAIL (a live rc-less job in a registered repo is an ACTIVE machine)"; exit 1; }
    [ -f "$T/aw/pressed" ] || { echo "AWAKE BGJOB PRESS FAIL"; exit 1; }
    kill "$aw_job" >/dev/null 2>&1 || true
    wait "$aw_job" 2>/dev/null || true
    rm -f "$aw_home/repos/$aw_k"
    # (8) install: the ONE subcommand that writes outside the registry, so HOME moves to the fixture
    #     too. Identity is the PATH polaris/awake-hook.sh — an entry running OUR script is replaced
    #     wholesale (a wrong timeout stays correctable), and every other entry is the human's.
    if python -c pass >/dev/null 2>&1 || python3 -c pass >/dev/null 2>&1; then
      mkdir -p "$T/aw/home/.claude"
      printf '%s\n' '{' '  "hooks": {' '    "Stop": [' \
        '      {"hooks": [{"type": "command", "command": "echo foreign-stop"}]},' \
        '      {"hooks": [{"type": "command", "timeout": 99, "command": "\"bash\" \"/old/polaris/awake-hook.sh\" idle 2>/dev/null || true"}]}' \
        '    ]' '  }' '}' > "$T/aw/home/.claude/settings.json"
      aw_sj="$T/aw/home/.claude/settings.json"
      HOME="$T/aw/home" bash "$aw_hook" install > "$T/aw/inst.out" 2>&1 || { cat "$T/aw/inst.out"; echo "AWAKE INSTALL RC FAIL"; exit 1; }
      grep -q 'foreign-stop' "$aw_sj" || { cat "$aw_sj"; echo "AWAKE INSTALL FOREIGN FAIL (someone else's Stop hook is theirs — never rewritten)"; exit 1; }
      grep -q '/old/polaris/awake-hook.sh' "$aw_sj" && { cat "$aw_sj"; echo "AWAKE INSTALL STALE FAIL (an entry running OUR script is replaced wholesale)"; exit 1; }
      [ "$(grep -c 'awake-hook' "$aw_sj")" = 4 ] || { cat "$aw_sj"; echo "AWAKE INSTALL COUNT FAIL (exactly four entries, never a fifth on re-run)"; exit 1; }
      for aw_ev in SessionStart UserPromptSubmit Stop SessionEnd; do
        grep -q "\"$aw_ev\"" "$aw_sj" || { cat "$aw_sj"; echo "AWAKE INSTALL EVENT FAIL ($aw_ev missing)"; exit 1; }
      done
      for aw_sub in start busy idle end; do
        [ "$(grep -c "\" $aw_sub 2>/dev/null" "$aw_sj")" = 1 ] || { cat "$aw_sj"; echo "AWAKE INSTALL SUB FAIL ($aw_sub must appear exactly once)"; exit 1; }
      done
    else
      note "awake drill: no python on this machine — the settings.json merge is skipped (keep-awake.md § install)"
    fi
    # hermetic teardown: no daemon outlives the drill, the seams leave the environment, and the
    # registry goes back to the empty shape the spine's export creates.
    : 2>/dev/null > "$aw_home/stop" || true
    aw_i=0; while [ "$aw_i" -lt 80 ]; do [ -d "$aw_home/lock" ] || break; sleep 0.1; aw_i=$((aw_i+1)); done
    [ -d "$aw_home/lock" ] && { cat "$aw_home/daemon/log"; echo "AWAKE TEARDOWN FAIL (a drill must never leave a daemon running)"; exit 1; }
    unset POLARIS_AWAKE_PRESSER POLARIS_AWAKE_TICK POLARIS_AWAKE_IDLE POLARIS_AWAKE_STALE POLARIS_AWAKE_GRACE POLARIS_AWAKE_SPAWN
    rm -rf "$aw_home" "$T/aw"
    mkdir -p "$aw_home/sessions" "$aw_home/repos" "$aw_home/daemon"
}
