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
points 3 · risk normal · landed f8f0fc8 (2026-07-21) · claimed 2026-07-21
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
