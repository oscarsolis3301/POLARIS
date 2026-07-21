# Sprint 6 — Many hands (2026-07-21–)

## T-039 — lib-loader + core.sh extraction + install/INIT parity
points 5 · risk normal · landed d958aee (2026-07-21) · claimed 2026-07-21
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
