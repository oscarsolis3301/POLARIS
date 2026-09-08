# Sprint 13 — Feel fast, stay fast (6.3.0) (2026-09-08–)

## T-122 — "A test tier that is actually seconds — doctor --fast runs the kit's logic in-process"
points 5 · risk normal · landed 1767e5f (2026-09-08) · claimed 2026-09-08
files touched: kit/ops/PROTOCOL.md, kit/ops/lib/observe.sh, kit/ops/lib/selftest/fast.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/cli-help.expected

### Why
Every change here waits on a test tier that is minutes long, because even the "fast" tier
(`test_fast:`, 320s) is four full drills, and each drill spawns the CLI dozens of times at ~57ms per
git fork on Windows. Nothing in the kit can be proven in seconds today. This task adds a NEW tier
beside the drills — not instead of them — that sources nothing extra and calls the kit's pure
functions in-process: `semver_gt`, `fm_get`/`fm_list`, `cfg`, `owned_match`, `id_ok`,
`cmd_task_commit_msg`, `jesc`, `rules_lines`, `awake_conf`, `bg_age`. Zero `polaris` re-invocations,
no scratch git repo, one `mktemp`. It runs as `bash ops/polaris doctor --fast` and must finish in
under 15 seconds on this machine (target 5). The existing 2,739 lines of drills are NOT touched: they
are slow because they test the real entry point, and CI is where that cost belongs.

This task is also the wave's single owner of the two derived goldens (`cli-help`, `api-kit`), so it
writes the help line for `update [--auto|--all]` and the api-kit rows for T-123's and T-124's new
functions from the names pinned in the contracts — never from their diffs.

### Acceptance
- [ ] `kit/ops/lib/selftest/fast.sh` exists with exactly three top-level fns: `selftest_fast` · `ft_assert` · `ft_section` (ops/contracts/fast-tier.md § Shared types); every section in the contract's minimum table is present and green
- [ ] `bash kit/ops/polaris doctor --fast` ends with `✅ fast tier passed — <n> checks in <s>s`, rc 0; a deliberately broken assertion (sabotage in a throwaway copy) prints `⛔ FAST <SECTION> FAIL (...)`, the run CONTINUES, rc 1 — record the sabotage in Notes
- [ ] measured wall time on this machine recorded in Notes AND as a new ROW in `kit/ops/PROTOCOL.md` § LONG COMMANDS's table (`| \`doctor --fast\` — the in-process tier | <s>s | yes |`); no new heading anywhere under kit/
- [ ] `kit/ops/polaris`: `selftest/fast` appended to the default `_mods` list only (never the `_match|_rules|_guard` list); help's doctor line reads `doctor [--selftest [--only <patterns>] [--parallel <N>] | --fast]` plus the pinned one-line explanation; help's update line reads `update [--auto|--all] [--repo-only]` with the contract's wording (ops/contracts/auto-update.md)
- [ ] `cmd_doctor`: `--fast` after the env check; `--fast` with any extra arg dies `⛔ doctor --fast takes no options` rc 1; plain `doctor`, `--selftest`, `--only`, `--parallel` byte-identical
- [ ] `ops/tests/cli-help.expected` refreshed BY CONTENT DIFF (`bash kit/ops/polaris help | diff - ops/tests/cli-help.expected` empty); `ops/tests/api-kit.expected` carries the W1 union pinned in ops/contracts/key-registry.md § 8 — your three fns, `suite_stamp_carry`, the five admin.sh fns, KEYS row `auto_update` — sorted in place; an unexpected hunk is a STOP, not a refresh
- [ ] `ops/tests/startup-budget` unchanged and green (no cfg fork added to the entry's globals block); `bash kit/ops/polaris check --only startup-budget,cli-help-parity` green after landing (integrator re-proves — goldens are primary-anchored and pass vacuously in a worktree)
- [ ] bash 3.2 clean: no `case` inside `$(...)`, no `mapfile`; `bash -n` on the module

## T-123 — "The express lane remembers its own green suite, so finish stops paying it twice"
points 3 · risk normal · landed 116d828 (2026-09-08) · claimed 2026-09-08
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/selftest/history.sh

### Why
`land --express` runs the whole test suite (13+ minutes here) and then throws the result away: it
never writes `.polaris/suite-stamp`, the little file `qa` uses to know "this exact commit was
already proven green". Only `qa` writes that file. So on the `landing: integrator` path a task pays
the full suite at express AND again at `finish` — the same tests over the same tree, ~20 wasted
minutes per task. The fix is one small function, `suite_stamp_carry`, called at the very end of
express: if the tree is clean and the only thing that changed since the tested commit is the sprint
report (and the MAP line `done` appends), stamp the current HEAD exactly the way `qa` would have.
If anything else moved, withhold the stamp and say so — `finish` then re-runs the suite, which is
cheap next to blessing something untested. `qa` itself is not touched. Express also records how long
the suite took (`.polaris/last-suite-seconds`) so the slow-suite hint works after an express land too.

### Acceptance
- [ ] `suite_stamp_carry <tested-sha>` exists in integrate.sh with exactly the semantics of ops/contracts/verification-tiering.md § v2 (clean tree · ancestor · diff restricted to `$(cfg reports docs/sprints/)` + `ops/MAP.md` · same `"<sha> <epoch>"` shape · withheld line otherwise · never changes express's rc); called ONCE, after `cmd_done` and the integrate-branch delete, before the closing `say`
- [ ] `<tested-sha>` is captured right after step 3's last green on integrate/<date>; `.polaris/last-suite-seconds` written as `"<seconds> <epoch>"` when ≥ 1 suite command ran
- [ ] `drill_express` (history.sh) gains the assertions pinned in the contract: stamp line 1 == `git rev-parse main` after the happy path · `qa` prints `suite already green` · a new commit on main makes `qa` run the suite again — asserting file content + rc, never message presence alone; the drill stays hermetic (leaves the fixture as it found it)
- [ ] sabotage evidence in Notes: with the carry call removed in a throwaway copy, the new assertion goes RED at the stamp check
- [ ] `bash kit/ops/polaris doctor --selftest --only express` green (acceptance, not verify: — foreground with a 600000 ms timeout, or `bg run` + chunked `bg wait`)
- [ ] no new top-level fn beyond `suite_stamp_carry` (T-122 writes its api-kit row); no heading changes

## T-124 — "Repos update themselves — update --auto applies when the board is quiet, --all walks the machine"
points 5 · risk normal · landed 3d3dab8 (2026-09-08) · claimed 2026-09-08
files touched: kit/ops/KEYS.tsv, kit/ops/lib/admin.sh, kit/ops/polaris

### Why
Three of the four POLARIS repos on this machine were months stale, and the fixes for their own
slowness had shipped here long before. The daily check (`update_check_maybe`) already knows a newer
kit exists — it just prints a notice nobody acts on. This task makes the check ACT, safely: a new
`update --auto` form that applies a minor or patch update when the board is quiet (nothing in
ready/active/review, no task lock, no integration lease, no running background job), stays silent
otherwise, never stashes anyone's work, and for a MAJOR version prints one line asking instead of
applying. It is meant to be called by a session-start hook (T-125), never by the everyday commands,
which keep today's notice byte-for-byte. The off switch is a CONVENTIONS key `auto_update: off`,
defaulting ON in code — `update` never writes a repo's own config, so a default that only works when
written would be dormant everywhere. Two more things ride along because they share the same code:
`update --all` walks the machine registry and updates every quiet repo in one command, and the
explicit `update` stops dying on a dirty tree when the dirt is the human's app files rather than kit
files (the venzeti report: app-only dirt, "commit or stash first"). Only overlapping dirt gets parked.

### Acceptance
- [ ] `cmd_update` parses flags from `"$@"`: `--auto` · `--say` · `--all` · `--repo-only` in any combination the contract allows; unknown → today's die; the re-exec-from-a-copy guard stays FIRST for every form except the self-hosting `--auto` exit (step 1), which must be silent rc 0 before any copy is made
- [ ] `update --auto` follows ops/contracts/auto-update.md § algorithm step by step: silent rc 0 on self-hosting / `auto_update: off` / nothing newer / busy board / kit-path dirt; the pinned MAJOR line; apply with stdout+stderr in `.polaris/update.log`; the pinned `✅ POLARIS updated` and `⚠ auto-update … failed` lines; `--say` turns each silent exit into `skipped: <reason>`
- [ ] `update_latest` shares `.polaris/update-cache` and the daily throttle with `update_check_maybe` (refactor the cache/network part into it; the notice path stays byte-identical on `claim status doctor dash version`)
- [ ] `board_quiescent` reads only `$BOARD` · `$LOCKS` · `$PRIMARY/.polaris/bg`, rc 0/1, sets `QUIET_WHY` with the pinned shapes; bg jobs judged rc-file-FIRST via `bg_alive`; a dirty tree is NOT a reason
- [ ] `update_dirt_overlaps_kit` reads porcelain on stdin, rc 0 on any path in the pinned kit footprint (renames test the NEW path); explicit `update`: no overlap → proceeds with the `outside the kit's paths — left alone` note and NO stash; overlap → `park` as today; park refused → today's die verbatim
- [ ] `cmd_update_all`: registry from `awake_home`; the pinned per-repo lines (`gone` · `self-hosting — skipped` · the child's `--auto --say` output prefixed `<path>: ` · `up to date`); never deletes a registry entry; rc 0 always; `--repo-only` passed through
- [ ] `kit/ops/KEYS.tsv` gains exactly the pinned `auto_update` row, in the header's spirit (default = effective value when absent); `doctor` on this repo now names `auto_update` among the absent keys (this repo does NOT adopt it — it is self-hosting and never auto-updates anyway)
- [ ] surface-frozen beyond the five pinned fns (T-122 writes their api-kit rows and the KEYS row's line); no `help` edit (T-122 owns the entry); no new heading
- [ ] a manual proof in Notes: in a throwaway clone of `Desktop\polaris-testbed` (or a scratch installed repo) with `ops/VERSION` pinned low and a `file://` channel + tarball per the contract's drill recipe, `update --auto --say --repo-only` applies on a quiet board and skips with `active: 1` when a task file sits in active/ — the T-126 drill automates this; you prove it first
