# Sprint 13 — Feel fast, stay fast (6.3.0) (2026-09-08–)

## T-122 — "A test tier that is actually seconds — doctor --fast runs the kit's logic in-process"
points 5 · risk normal · landed 1767e5f (2026-09-08) · claimed 2026-09-08 → done 2026-09-08
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
points 3 · risk normal · landed 116d828 (2026-09-08) · claimed 2026-09-08 → done 2026-09-08
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
points 5 · risk normal · landed 3d3dab8 (2026-09-08) · claimed 2026-09-08 → done 2026-09-08
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

## T-125 — "Every session start checks for a newer kit, and every install registers its repo"
points 5 · risk normal · landed 489df55 (2026-09-08) · claimed 2026-09-08
files touched: kit/.claude/settings.json, kit/ops/hooks/update-hook.sh, kit/ops/install.sh, ops/tests/api-kit.expected

### Why
T-124 taught `update --auto` to apply a safe update when the board is quiet. Nothing calls it yet.
This task wires the trigger: a SessionStart hook (matcher `startup` — a fresh session, which by
definition sits between tasks; `compact|resume` stays the handover hook's) that runs
`ops/polaris update --auto` and passes its single line, if any, into the model's context so the
session knows the protocol under it just changed. The hook lives under `ops/hooks/` on purpose: that
path is the identity install.sh's settings merge and `uninstall`'s sweep both key on, so it arrives
on the next update and leaves on uninstall without a special case. The second half fixes the
registry `update --all` walks: `~/.claude/polaris/awake/repos/` is written only when a session goes
busy, so it held 3 of the 5 POLARIS repos on this machine. install.sh now writes the entry at install
and update time with the same cksum-of-path formula the awake hook and uninstall use.

### Acceptance
- [ ] `kit/ops/hooks/update-hook.sh` per ops/contracts/auto-update.md § SessionStart hook: fns exactly `jstr` · `uh_primary` · `uh_main`; ≤ 90 lines; `set -u`; exit 0 ALWAYS; silent when cwd resolves to no primary or the primary has no `ops/polaris`; live path runs `bash ops/polaris update --auto` from the primary with stdout passed through and stderr appended to `.polaris/update.log`; `--test` prints the pinned line and runs nothing
- [ ] `kit/.claude/settings.json`: a second `SessionStart` entry with the pinned matcher/command/timeout; the existing `compact|resume` entry byte-identical; `python -c "import json;json.load(open('kit/.claude/settings.json'))"` passes
- [ ] `kit/ops/install.sh`: the new hook in the `chmod +x` list; the registry write once, after the hooks copy, on BOTH install paths (fresh + live board), skipped silently when `$HOME/.claude` is absent and `POLARIS_AWAKE_HOME` unset; best-effort `|| true`, no output — the installer's quiet-line count above the epilogue must not change (`bash kit/ops/selftest-install.sh` green)
- [ ] the merge-repair drill still passes: on a settings.json that already has a POLARIS SessionStart entry, install.sh ADDS the startup entry and keeps every foreign hook (`bash kit/ops/selftest-install.sh`; the `awake` and `handover` drills and goldens `handover-stop`, `handover-route`, `awake-hook` unchanged)
- [ ] `ops/tests/api-kit.expected` (W2 owner, key-registry § 8): adds your three hook fns and T-126's `drill_autoupdate` — the union written up front from the pinned names, content-diffed, an unexpected hunk is a STOP
- [ ] proof in Notes: a real `SessionStart` payload piped to the LIVE hook (no `--test`) from a scratch installed repo whose channel points at a `file://` VERSION one patch ahead (the T-126 drill recipe) prints the `✅ POLARIS updated` line and nothing else; the same repo with a task in active/ prints nothing
- [ ] `bash kit/ops/polaris doctor --selftest --parallel 3` green (acceptance, via `bg run` + chunked `bg wait`)

## T-126 — "Prove auto-update the way the kit proves everything — a drill, plus the gates in the fast tier"
points 5 · risk normal · landed adcfa1c (2026-09-08) · claimed 2026-09-08
files touched: kit/ops/lib/selftest/fast.sh, kit/ops/lib/selftest/remote.sh, kit/ops/lib/selftest/spine.sh

### Why
An update that applies itself is exactly the kind of thing that must be proven by a test, not by a
promise: the gates that keep it from firing mid-task (`board_quiescent`) and from stepping on
someone's edits (`update_dirt_overlaps_kit`) are pure functions, so they go into the new in-process
tier (T-122) where they are checked in seconds on every change. The end-to-end behavior — a real
`update --auto` against a `file://` channel and tarball, applying on a quiet board, refusing on a
busy one, obeying `auto_update: off`, asking on a major bump, the explicit `update` no longer dying
on app-only dirt, and `update --all` walking a registry — is a labeled drill in the selftest,
sharded and run in CI on three OSes like every other mechanic. Nothing here touches admin.sh: the
drill tests what T-124 shipped, and a red is a finding, never a weakened assertion.

### Acceptance
- [ ] `selftest_fast` (fast.sh) gains sections `quiescent` and `dirt` with every case pinned in ops/contracts/auto-update.md § Executable check, INSIDE the existing fn — the module keeps exactly three top-level fns; the whole tier still under 15s on this machine (record the new number in Notes)
- [ ] `drill_autoupdate` (remote.sh) implements the contract's six numbered assertions, `--repo-only` on every apply, rc AND file state asserted (`ops/VERSION` value, `.polaris/update.log`, `git stash list`), never message presence alone; hermetic — `ops/VERSION`, CONVENTIONS and `src/a.txt` restored, no stash left, the fixture registry under the drill's own `POLARIS_AWAKE_HOME` temp dir
- [ ] spine.sh: `autoupdate` appended to `SELFTEST_LABELS` after `handover`; its `drill_on` gate placed after the handover drill's; the full-run pass line gains an `autoupdate (…)` clause; `--only autoupdate` stands alone on the bare spine
- [ ] `bash kit/ops/polaris doctor --selftest --only autoupdate` green, and `--parallel 3` green with the new label (acceptance: 600000 ms timeouts or `bg run` + chunked `bg wait`); a `--parallel 2 --only 'autoupdate,fmlist'` run green proves partition-invariance
- [ ] sabotage evidence in Notes: with `board_quiescent` forced to rc 0 in a throwaway kit copy, assertion (2) goes RED at the `ops/VERSION` check; with the dirt overlap forced, the fast `dirt` section reds
- [ ] surface-frozen: no new top-level fn beyond `drill_autoupdate` (T-125 writes its api-kit row); no heading

## T-127 — "Seconds on every change, minutes at the wave gate, the full drill only in CI — measured and written down"
points 3 · risk normal · landed c6667b1 (2026-09-08) · claimed 2026-09-08
files touched: kit/ops/PROTOCOL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/SOLO.md, ops/CONVENTIONS.md

### Why
The suite is measured at 13–20 minutes and it sits on the critical path three times per change:
the builder's "fast" tier (320s of real drills), the wave gate, and `finish`. The pieces to fix
that now exist — a seconds-long in-process tier (T-122), the express lane keeping its own suite
stamp (T-123), and `--parallel 3` measured at 169s vs 805s serial — and this task turns them into
the repo's actual gates and writes the numbers down where the next agent reads them. `test_fast:`
becomes `doctor --fast` (seconds, every change). `test:` becomes the sharded suite (the wave gate
and `finish`). CI keeps running the full serial drill on three OSes, so no coverage is lost. The role
prose stops telling SOLO and BUILDER to fall back to the full `test:` when a repo sets no
`test_fast:` — that fallback is why a one-line change paid the whole suite twice — and says instead
that `finish`/the wave gate pays it once, stamp-aware. PROTOCOL's long-command table and its
`update` row learn the new reality (auto-update, `update --all`). One more measurement the plan
asked for: the suite under WSL, where a git fork costs ~5ms instead of 57ms. This machine has no WSL
distribution installed (`wsl -l` → none), so record exactly that with the Git Bash baseline and the
command to re-measure — installing a distribution is the human's call, not this task's.

### Acceptance
- [ ] `ops/CONVENTIONS.md`: `test:` = `bash kit/ops/polaris doctor --selftest --parallel 3`; `test_fast:` = `bash kit/ops/polaris doctor --fast`; the comment block under them rewritten with THREE measurements taken in this task on this machine, in the file's existing style (date, command, seconds): the fast tier · `--parallel 3` (all labels incl. any new ones) · the full serial suite is NOT re-measured (805s / 1225s stand, cite them); plus a `WSL:` line recording either the measured sharded time under WSL or "no distribution installed on <date> (`wsl.exe -l`); git fork measured <n>ms/call under Git Bash; re-measure with: wsl bash kit/ops/polaris doctor --selftest --parallel 3"
- [ ] `kit/ops/roles/SOLO.md` step 4 and `kit/ops/roles/BUILDER.md` § 3: run `test_fast:` when set; when unset, NO fallback to `test:` — say that the wave gate / `finish` pays `test:` once and that `finish` skips it when `.polaris/suite-stamp` already names HEAD (an express land writes it since 6.3.0); mention `bash ops/polaris doctor --fast` as the kit's own seconds-long check; heading count in both files unchanged; SOLO step 7's parenthetical updated to match (an express land now leaves a stamp)
- [ ] `kit/ops/PROTOCOL.md`: § LONG COMMANDS table rows updated with the numbers you measured (`test_fast:` row now names `doctor --fast`; the `--parallel 3` row's count and seconds current); § THE TOOL `version / update` row per ops/contracts/auto-update.md's pinned wording; no new heading
- [ ] `bash kit/ops/polaris check` green after landing (integrator re-proves; `cli-help` is untouched here)
- [ ] a `Planner calibration` line is NOT added — this is a config change, not a pointing lesson

## T-129 — "keep-awake daemon spawns without a visible console window"
points 1 · risk normal · landed b46fdf3 (2026-09-08) · claimed 2026-09-08
files touched: kit/ops/hooks/awake-hook.sh

### Why
Every keep-awake daemon on Windows is started through WMI so it outlives the session that started it. WMI creates it with a brand-new console, and on Windows 11 a new console is a Windows Terminal window. So every daemon start opened a visible terminal titled `bash.exe` on top of whatever the human was doing — and because the CLI's `ensure` fires from claim, status, doctor and `bg run`, and the self-test drills fire it too, a busy afternoon stacked dozens of those windows over the editor. This makes the daemon start with its console hidden (the same console its presser then inherits, so the presser never opens one either), and gives the presser its own hidden-window flag for the inline fallback where the daemon runs inside a hook process. macOS and Linux paths are untouched; the presser still prints exactly one word.

### Acceptance
- [ ] `ah_spawn`'s WMI `Win32_Process.Create` passes a `Win32_ProcessStartup` with `ShowWindow = 0` (SW_HIDE): the spawned daemon owns NO visible window (EnumWindows finds none for its ProcessId while it is alive)
- [ ] the presser invocation carries `-WindowStyle Hidden`; `ah_press` still captures exactly one word (golden `awake-hook` unchanged)
- [ ] `--test` twins, macOS/Linux branches and the Start-Process fallback are byte-for-byte as before
