# Sprint 30 — One kit for the whole machine (6.22.0 + 7.0.0) (2026-11-24–)

## T-342 — "Landing words under landing self, and one bg wait length for subagents - next says wait while lanes still build and land their own work, and the bg wait budget a subagent uses is measured once and written the same everywhere"
points 4 · risk normal · landed 7341e7c9 (2026-11-24) · claimed 2026-11-24
files touched: kit/.claude/agents/polaris-runner.md, kit/ops/PROTOCOL.md, kit/ops/hooks/handover-hook.sh, kit/ops/lib/handover.sh, kit/ops/roles/SOLO.md, ops/tests/handover-route.cmd, ops/tests/handover-route.expected, ops/tests/handover-stop.cmd, ops/tests/handover-stop.expected, ops/tests/runner-path.cmd, ops/tests/runner-path.expected

### Why
Two small fixes from last run's notes, bundled because each is one or two points and they share no
file with the rest of wave 1.

(1) Under `landing: self` each building lane lands its own card, yet `next` (and the Stop hook that
reads it) told a conductor "You are the INTEGRATOR — land …" as soon as anything sat in review/,
while other lanes were still building. Row 1a (role-handover.md v6) answers `wait` in exactly that
case; once no lane is live, row 1 fires as before, so a queued self-land tail is never stranded.

(2) The walk-away contract says a subagent collects a job with `bg wait --max 240`; BUILDER.md says 120
because "a subagent's foreground call is moved to the background at about 180 s" — never measured.
Measure it once from this card's own subagent context (walk-away.md v2 addendum gives the recipe and
both outcomes), then make every place say the same number. Do not add new headings: api-kit is not
yours this wave.

### Acceptance
- [ ] handover-route: row 1a case (landing self, a live active lane, landable review/ → `wait` + the two note lines) and its landing integrator twin (line 1 `integrate`)
- [ ] handover-stop: the Stop hook on that state allows (allow:wait), never block:integrate; every other case byte-identical
- [ ] The measured cut-off (returned inline / moved at ~N s) is written in Notes; every `bg wait … --max` for a subagent names one value (verify line 3)
- [ ] No new kit heading; api-kit unchanged

## T-343 — "The four pure-bash guards also run as functions - model ban, presence, checkout and read-only guards keep their standalone behaviour byte for byte and become sourceable, with unique names, for the one dispatcher"
points 10 · risk high · landed b16c5163 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/hooks/checkout-guard.sh, kit/ops/hooks/model-guard.sh, kit/ops/hooks/presence-guard.sh, kit/ops/hooks/readonly-allow.sh, ops/tests/api-kit.expected, ops/tests/checkout-guard-denies.cmd, ops/tests/checkout-guard-denies.expected, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected, ops/tests/presence-guard.cmd, ops/tests/presence-guard.expected, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected

### Why
7.0.0 replaces the four hook processes a Bash call starts today with one dispatcher that runs the guards
in-process (hook-dispatch.md). That needs each guard callable as a function without changing what it
does as a standalone hook — every project on 6.x keeps running these exact scripts, and guards fail
open, so a behaviour slip here silently disables a guard everywhere.

So: each script's top-level logic moves into one entry function that reads the hook JSON from `IN`
and leaves its stdout, stderr and exit code in `HOUT`, `HERR`, `HRC`; the last lines of the file run
it and print exactly what the script prints today when the file is executed rather than sourced. When
all four are sourced into one shell no name may collide, so checkout-guard's and readonly-allow's
unprefixed helpers (`jstr`, `deny`, `scan`, …) get `cg_`/`ra_` prefixes — the one api-kit change, and
this card is wave 1's only api-kit owner. One card owns all four because the test globs `new` attaches
to three of them would chain two guard cards anyway.

Each of the four batteries gains one case that sources the script and calls its entry function,
proving the function path prints the same as the standalone one (the SURFACES gate also requires the
mapped batteries to move with their scripts).

### Acceptance
- [ ] Every pre-existing case of model-guard-v2, presence-guard, presence-installed, checkout-guard-denies, readonly-allow, guard-denies, away-run, runner-path, perm-tools byte-identical
- [ ] Each of the four batteries gains a sourced-function case whose output equals the standalone case beside it
- [ ] Sourcing the four into one `set -u` shell defines _mg_hook _pg_hook _cg_hook _ra_hook and no duplicate function (verify lines 3-4)
- [ ] Each entry function never prints, never exits, never reads stdin, and restores any shell option it changes
- [ ] api-kit: exactly the renamed rows change (old names out, cg_*/ra_* in); nothing else

## T-344 — "The store and the launcher - a versioned kit folder per computer with a current pointer, a fifteen-line project launcher that finds it with no extra processes, a pinned bootstrap for CI, and the release zip's sha256 stamped into the update channel"
points 10 · risk normal · landed 299bc6a9 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/launcher, kit/ops/lib/store.sh, kit/ops/pack.py, ops/tests/dogfood-bytes.cmd, ops/tests/dogfood-bytes.expected, ops/tests/store-launcher.cmd, ops/tests/store-launcher.expected

### Why
The shared kit lives once per computer under `$POLARIS_HOME/kit/<version>/` — the release zip unpacked
verbatim — with a one-line `current` file naming the version every joined project runs
(shared-kit.md § 1). This card builds that store as private functions in a new `store.sh` (nothing
loads it yet; T-347 wires it in wave 2), and the launcher: the small `ops/polaris` a joined project
keeps instead of the kit (§ 2). The launcher reads `current` with a shell builtin, checks it is a
plain version, and sources that version's CLI, so `bash ops/polaris …` costs no extra process. On a
machine without POLARIS it prints one line telling the person how to install it; in CI it fetches the
version pinned in the project's `ops/KIT` and checks its sha256, so the shipped audit workflow keeps
working.

Nothing checks a downloaded kit today. `pack.py --dogfood` installs the published release here, so it
knows the published zip's bytes: it now writes their sha256 into root `ops/VERSION` (the channel every
updater reads), and the machine update refuses a zip that does not match (§ 4). No repo gets a
launcher in this release — `join` is 7.0.0 — so nothing a 6.x user runs changes.

### Acceptance
- [ ] store-launcher: every case listed in step 4, with fake HOME/CLAUDE_CONFIG_DIR, fixture zips built in the golden (python zipfile), no network
- [ ] The launcher's normal path has no `$(`, backtick or pipe, and works with PATH emptied
- [ ] dogfood-bytes unchanged in output, or re-pinned here with the zip_sha256 line explained
- [ ] api-kit unchanged (store.sh functions are private; kit/ops/launcher defines none)
- [ ] kit/ops/launcher is ≤ 60 lines and its two first lines are the contract's
