# Sprint 6 — Many hands (2026-07-21–)

## T-039 — lib-loader + core.sh extraction + install/INIT parity
points 5 · risk normal · landed d958aee (2026-07-21) · claimed 2026-07-21 → done 2026-07-21
files touched: kit/ops/install.sh, kit/ops/lib/core.sh, kit/ops/polaris, kit/ops/roles/INIT.md, kit/ops/selftest-install.sh

### Why
kit/ops/polaris is 3,826 lines in one file — every CLI sprint serializes on it and the review
surface is the whole script. This task opens the seam the rest of the sprint walks through: create
kit/ops/lib/, move the 33 core functions (die/say/cfg/fm_*/locks/mutex/board_commit/evt/sync/…)
verbatim into lib/core.sh, and put the pinned loader (module-layout contract, byte-for-byte —
list holds only `core` at this stage) into the entry script between `POLARIS_V=5` and the git
guard. Relocation only: no body changes, no behavior changes, serial output byte-identical.
Because ops/lib/ is a NEW installed directory, the same commit must teach the installer about it
(install-parity contract): `lib` added to BOTH named dir loops in kit/ops/install.sh (a miss ships
a CLI that dies at the loader), selftest-install gains the fresh-install and live-board-repair
asserts for ops/lib/core.sh, and kit/ops/roles/INIT.md's write-routing skeleton row "kit code +
invariants" gains ops/lib/ so new repos guard the installed copy from day one. The two installer
tripwires (quiet-install line count ≤2 above the epilogue; never print the INIT kickoff phrase)
must survive untouched — the dir loops print nothing, keep it that way.

### Acceptance
- [x] kit/ops/lib/core.sh holds exactly the 33 functions the module-layout contract assigns it, bodies verbatim, original relative order
- [x] entry script: loader block matches the contract byte-for-byte (list = `core` only), placed after POLARIS_V, before the git guard; top-level assignments MUTEX/FAIL_LOCK_ID/PUB/PUBLISH_WARNED/BOARD_REF moved into the globals block in original relative order
- [x] deleting kit/ops/lib/core.sh makes `bash kit/ops/polaris help` refuse with the pinned remedy message, rc 1 (restore after)
- [x] install.sh: both dir loops say `roles templates hooks ci lib`; KIT_CODE, chmod, output lines all unchanged
- [x] selftest-install: drill_fresh asserts ops/lib/core.sh installed; drill_live_board corrupts ops/lib/core.sh and asserts repair; all drills green
- [x] full `bash kit/ops/polaris doctor --selftest` green (handoff gate `test:`) — byte-identical referee

## T-040 — selftest extraction into lib/selftest/ + opt-in --parallel sharding
points 5 · risk normal · landed 7ff906f (2026-07-21) · claimed 2026-07-21 → done 2026-07-21
files touched: kit/ops/lib/selftest/board.sh, kit/ops/lib/selftest/brain.sh, kit/ops/lib/selftest/history.sh, kit/ops/lib/selftest/policy.sh, kit/ops/lib/selftest/remote.sh, kit/ops/lib/selftest/report.sh, kit/ops/lib/selftest/spine.sh, kit/ops/polaris

### Why
The ~890-line selftest embedded in kit/ops/polaris is why the full suite (~7 min) outgrew the
600s harness cap and killed healthy lanes on timeout mechanics (sprint 5). Move it out and make
it shardable: drill_on/ngwait/ensure_origin plus the selftest() spine go verbatim to
kit/ops/lib/selftest/spine.sh; each labeled drill block becomes a `drill_<label>` function in its
group file (board/history/report/brain/policy/remote per the module-layout contract), called from
the spine at the exact same point behind the same drill_on gate — bodies verbatim, NO new `local`
lines (spine state reaches drills by dynamic scoping; a stray local shadows it, e.g. bstamp1).
Then the selftest-sharding contract's opt-in surface: `--only` gains comma-separated patterns
(single pattern byte-identical to today), and `--parallel <N>` partitions selected labels
round-robin into N child re-invocations (`"$SELF" doctor --selftest --only <list>`, own logs, own
throwaway repos), waits, replays red logs, and greens with `✅ selftest passed — <N> shards`.
Serial stays the default and byte-identical; CI stays serial. Update the entry's loader list
(+ the 7 selftest/ names) and usage()'s doctor line. Sharding lands EARLY so waves 3–6 iterate fast.

### Acceptance
- [ ] lib/selftest/ = spine.sh + board.sh + history.sh + report.sh + brain.sh + policy.sh + remote.sh, labels grouped exactly per module-layout contract
- [ ] plain `doctor --selftest` and every single-pattern `--only` run byte-identical to pre-split (spot-diff one of each against the pre-task script)
- [ ] `--parallel 2 --only 'fmlist,grant'` → two shards, both green, final line `✅ selftest passed — 2 shards`, rc 0
- [ ] `--parallel 1` refuses with the pinned message; N > selected labels clamps with the pinned note line
- [ ] a forced-red shard (nonexistent tool in one drill, locally) replays its log verbatim and exits rc 1 — then revert
- [ ] full `bash kit/ops/polaris doctor --selftest` green (handoff gate `test:`)

## T-041 — docs — modular layout in MANUAL, kit CLAUDE.md STATE tree + THE TOOL note
points 2 · risk normal · landed 47d1b00 (2026-07-21) · claimed 2026-07-21 → done 2026-07-21
files touched: kit/CLAUDE.md, kit/ops/MANUAL.md

### Why
After the split, a user who opens ops/ meets a lib/ directory no document mentions, and a broken
lib/ prints a remedy no manual explains. Three contract-sourced edits, wording pinned so this task
runs parallel to the CLI chain with zero conflicts: (1) kit/ops/MANUAL.md gains a short "The
modular CLI" section — ops/polaris is the entry (globals + lib-loader + dispatch), function bodies
live in ops/lib/*.sh sourced in fixed order at startup, a missing module refuses with the
re-run-installer/update remedy, recipes below are unchanged — plus the pinned sharding phrase from
the selftest-sharding contract, verbatim: "Opt-in: `doctor --selftest --parallel <N>` runs the
labeled drills in N parallel shards; serial stays the default and CI stays serial." (2) kit/CLAUDE.md
STATE tree gains the `lib/` line under ops/ with the module list, and THE TOOL section gains one
note that the CLI is `globals + lib-loader + dispatch` sourcing ops/lib/. (3) map_delta records the
new module directory in this repo's MAP at done. Describe only what the contracts pin — the CLI
chain is still landing; cite no line numbers, paste no code.

### Acceptance
- [ ] MANUAL "The modular CLI" section present: entry + lib/ + fixed source order + missing-module remedy + recipes-unchanged, and the pinned --parallel phrase verbatim
- [ ] kit/CLAUDE.md STATE tree lists `lib/` under ops/ with the 7 module names + selftest/; THE TOOL notes the entry shape
- [ ] no wording beyond the two contracts; no line numbers, no code blocks copied from the CLI
- [ ] map_delta line present in frontmatter (lands in MAP via `polaris done`)

## T-042 — extract lib/ownership.sh + lib/builder.sh
points 3 · risk normal · landed f8f0fc8 (2026-07-21) · claimed 2026-07-21 → done 2026-07-21
files touched: kit/ops/lib/builder.sh, kit/ops/lib/ownership.sh, kit/ops/polaris

### Why
Third link of the entry-file chain. Move the ownership/verification machinery (owned_match,
check_ownership, run_verify_cmds, map_delta_hint, rule_scan_path, rule_scan_content_file,
check_rules, plus the guard entrypoints cmd_match and cmd_rules_check) verbatim into
kit/ops/lib/ownership.sh, and the builder lifecycle (cmd_claim, cmd_verify, cmd_handoff,
cmd_release, grant_append_owned, cmd_grant, cmd_resume) verbatim into kit/ops/lib/builder.sh —
exactly the function-to-module table in the module-layout contract, original relative order,
bodies untouched. Extend the entry's loader list with `ownership builder` at their final
positions. The write-guard hook calls `ops/polaris _match/_rules` as a subprocess, so the guard
path needs no change — but it now crosses the loader, which the --only subset plus the full suite
prove. Zero behavior change; serial output byte-identical.

### Acceptance
- [ ] ownership.sh holds exactly the contract's 9 functions; builder.sh exactly its 7; nothing else moved
- [ ] loader list reads `core ownership builder selftest/…` (final relative order, per contract growth schedule)
- [ ] the sharding seam check (`--parallel 2 --only 'fmlist,grant'`) still greens post-extraction
- [ ] full `bash kit/ops/polaris doctor --selftest` green (handoff gate `test:`)

## T-043 — extract lib/integrate.sh
points 3 · risk normal · landed 42f1caa (2026-07-21) · claimed 2026-07-21 → done 2026-07-21
files touched: kit/ops/lib/integrate.sh, kit/ops/polaris

### Why
Fourth link of the chain, and the scariest relocation: the integrator machinery (cmd_kickback,
cmd_audit, cmd_run_verify, landed_sha, cmd_done, cmd_task_commit_msg, in_primary,
land_slow_suite_hint, cmd_land, cmd_land_express, tag_push_recovery_note, cmd_seal, seal_sync,
cmd_history, cmd_rollback — the contract's 15) moves verbatim into kit/ops/lib/integrate.sh.
These functions rewrite history on land/seal/rollback, so the referee matters most here: the
spine drills claim→handoff→land→seal end-to-end, tcm covers the generated commit message
(including the git-for-Windows two-stream squash chatter, clean-history v2.3), express covers
the one-pass lane. Extend the loader list with `integrate` at its final position. Original
relative order, bodies untouched, zero behavior change — every land/seal/history output
byte-identical.

### Acceptance
- [ ] integrate.sh holds exactly the contract's 15 functions; nothing else moved
- [ ] loader list reads `core ownership builder integrate selftest/…` (contract growth schedule)
- [ ] full `bash kit/ops/polaris doctor --selftest` green (handoff gate `test:`)

## T-044 — extract lib/knowledge.sh + lib/observe.sh
points 3 · risk normal · landed ebc614a (2026-07-21) · claimed 2026-07-21
files touched: kit/ops/lib/knowledge.sh, kit/ops/lib/observe.sh, kit/ops/polaris

### Why
Fifth link of the chain, two modules in one pass because they share no seam risk: the knowledge
generators (report_* and sprint_* helpers, ts_date, event_ts, resolve_sprint_ids, render_*,
report_dirty_hint, report_one, cmd_report, seal_report_commit, board_changed_touch,
brain_refresh_if_present, the six brain_* writers, cmd_brain — the contract's 26) move verbatim
into kit/ops/lib/knowledge.sh, and the read-only observers (cmd_notify_gate, status_brief,
cmd_status, cmd_sweep, cmd_doctor, pat_overlap, dep_ids, dep_reaches, cmd_drift, cmd_rules,
cmd_qa, cmd_metrics, cmd_why, cmd_dash, find_claude, find_claude_windows, cmd_fleet — the
contract's 17) into kit/ops/lib/observe.sh. cmd_doctor keeps calling selftest() across modules —
free at runtime, everything is sourced before dispatch. seal (integrate.sh, landed last wave)
keeps calling seal_report_commit/brain_refresh_if_present/board_changed_touch the same way.
Extend the loader list with `knowledge observe` at their final positions. Original relative
order, bodies untouched, zero behavior change.

### Acceptance
- [ ] knowledge.sh holds exactly the contract's 26 functions; observe.sh exactly its 17; nothing else moved
- [ ] loader list reads `core ownership builder integrate knowledge observe selftest/…` (contract growth schedule)
- [ ] `report`/`brain`/`status --brief` outputs spot-diffed byte-identical against the pre-task script
- [ ] full `bash kit/ops/polaris doctor --selftest` green (handoff gate `test:`)

## T-046 — hermetic selftest drills — kill the order-coupling between labels
points 3 · risk normal · landed 1f8c56b (2026-07-21) · claimed 2026-07-21 → done 2026-07-21
files touched: kit/ops/lib/selftest/policy.sh

### Why
The drills are order-coupled: each labeled drill mutates the ONE fixture repo the spine builds
and assumes the labels before it ran. Wave-3 evidence: the `rules` drill leaves a contract-less
ready task in the fixture; when the `drift` drill runs in between it happens to clean/mask it,
but partition the labels differently and `qa`'s `drift --strict` meets the leftover and reds —
`--parallel 3` shard 3 red, serial reproducer `--only rules,qa` red on pre-T-042 main. So
`--only` subsets and `--parallel` shards can silently red OR silently mask depending on the
partition, which makes the sharding contract's partition-invariance a lie. Fix per
selftest-sharding v1.1 (Hermeticity): audit all 18 labeled drills; each must leave the shared
fixture exactly as it found it — board columns, RULES.tsv, CONVENTIONS values, refs, locks —
or provision and remove its own scratch state, and no drill may depend on state another label
created or cleaned. Fix lives ONLY in kit/ops/lib/selftest/ (drill bodies + spine helpers if a
shared snapshot/restore helper earns its keep); the entry script, product commands, and drill
ASSERTIONS stay untouched — this restores test independence, it does not change what is tested.

### Acceptance
- [ ] isolation sweep: every one of the 18 labels greens alone — `--only <label>` for each of: fmlist tcm report metrics brain rules drift hardening qa remote syncrace notify grant upgrade pr-publish express hint brief
- [ ] reproducer dead: `--only 'rules,qa'` green
- [ ] `--parallel 3` (full set) green on 3 CONSECUTIVE runs
- [ ] diff touches kit/ops/lib/selftest/ only; no drill assertion weakened or removed
- [ ] full serial `bash kit/ops/polaris doctor --selftest` green (handoff gate `test:`)
