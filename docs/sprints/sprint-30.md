# Sprint 30 — One kit for the whole machine (6.22.0 + 7.0.0) (2026-11-24–)

## T-341 — "A fix card for a red wave is cut from the wave, and the admin groundwork for a shared kit - claim cuts a card from the open wave when it owns a path the wave changed, update --all keeps joined projects, adopt and heal read kit data through one lookup"
points 8 · risk normal · landed 0fb3d05c (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/lib/admin.sh, kit/ops/lib/builder.sh, kit/ops/lib/core.sh, kit/ops/lib/ownership.sh, kit/ops/lib/selftest/remote.sh, kit/ops/lib/workspace.sh, ops/tests/adopt-stub.cmd, ops/tests/heal-design.cmd, ops/tests/update-registry.cmd, ops/tests/update-registry.expected, ops/tests/wave-fix-claim.cmd, ops/tests/wave-fix-claim.expected

### Why
Two things this release needs before anything else, both in files no other first-wave card touches.

(1) The wave cut. Last run, a card written to fix a red wave could not change code that existed only
on that open wave: claim always cut `feat/<ID>` from the base branch, so the squash conflicted, and a
branch cut from `integrate/<date>` failed verify's ownership diff, which compares against the base.
`_wave_cut <ID>` decides where a card starts: from the open wave's tip when the card owns a path the
wave already changed, else from the base as today. `wt_add` records the cut in git config and every
diff that judges a card's OWN change uses it. With no recorded cut, every command is byte-identical
(safe-landing.md v2). It lands in wave 1 so any later red wave of this plan can be fixed on the wave.

(2) Admin groundwork for the shared kit (shared-kit.md): `update --all` stops deleting the registry
entry of a joined project (it has no `ops/VERSION`, only a launcher); the settings sweep `uninstall`
does becomes a shared private helper that `migrate` will reuse; and `adopt`/`heal` read their kit data
(`KEYS.tsv`, `templates/DESIGN.md`) through `kit_file`, the decision last run left open: in a state-only
repo that data is always the kit's, so "no registry" only means an incomplete vendored kit, and the two
goldens keep testing that case by running a vendored copy of the CLI in their fixture.

### Acceptance
- [ ] wave-fix-claim: every case in safe-landing v2's golden bullet (cut from the wave tip + config recorded · verify diff = only the fix · land squashes clean · a card owning no wave path cuts from $BASE with no key · release drops the key)
- [ ] No recorded cut: landed-seal, landed-content, land-race, seal-fallback byte-identical
- [ ] update-registry: + one case, a launcher-only entry prints `<p>: machine kit — moves with the machine update` and stays; every other line unchanged
- [ ] adopt-stub and heal-design print byte-identical output; only their .cmd fixtures change
- [ ] _settings_sweep is a move: cmd_uninstall's behaviour and output unchanged (drill_adopt / uninstall paths green)
- [ ] api-kit unchanged (both new functions are private)

## T-342 — "Landing words under landing self, and one bg wait length for subagents - next says wait while lanes still build and land their own work, and the bg wait budget a subagent uses is measured once and written the same everywhere"
points 4 · risk normal · landed 7341e7c9 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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
points 10 · risk high · landed b16c5163 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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
points 10 · risk normal · landed 299bc6a9 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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

## T-345 — "One hook process per tool call - the dispatcher folds the model ban, presence, checkout and read-only guards, runs the other hooks itself, stands down outside joined projects, asks when ops/polaris is not the real launcher, and the shim and trust tier setup will install"
points 8 · risk high · landed bc73c3a3 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/hooks/dispatch.sh, kit/ops/hooks/shim.sh, ops/tests/hook-budget.cmd, ops/tests/hook-budget.expected, ops/tests/hook-dispatch.cmd, ops/tests/hook-dispatch.expected

### Why
This is the fold card, the riskiest of the plan: guards fail open, so a dispatcher bug would switch
off every guard at once. `dispatch.sh <event>` reads the hook input once and, in order, runs the
model ban (every project, as the machine-level model guard does today), decides with builtins whether
it stands in a joined project (a vendored project's own hooks keep doing the work, so it stands
down there), then runs presence, the checkout deny and the read-only allow as functions in this one
process and prints the single verdict Claude Code would have reached from the four separate hooks
(hook-dispatch.md § 2). The edit guard, the hand-over hook and the permission hook are `exec`ed.

Two security pieces ride along. The read-only allow comes from a TRUST TIER copy that only the owner's
`--setup` writes (§ 4), so an automatic kit update can change what is denied but never widen what is
auto-approved. And in a joined project a command that runs `ops/polaris` is answered `ask` unless that
file is byte-for-byte the real launcher (§ 5), so a cloned repo cannot ride the pre-approved
`bash ops/polaris` rule. `shim.sh` is the small file `--setup` will copy to `$POLARIS_HOME/hook`.

The equivalence golden replays every existing guard battery through the dispatcher and must match
them exactly — it is on this card on purpose. Nothing registers the dispatcher yet (T-350, 7.0.0).

### Acceptance
- [ ] hook-dispatch (a): readonly-allow, checkout-guard-denies, presence-guard, model-guard-v2, ownership-primary, permission-hook, handover-stop each replayed via `dispatch.sh --as <guard>` in a joined fixture prints `<battery>: identical`
- [ ] hook-dispatch (b) merge matrix, (c) stand-down in vendored and non-POLARIS dirs, (d) no duplicate function — every case per hook-dispatch.md § 7
- [ ] hook-budget: same verdicts with PATH emptied for the § 7 cases; no `$(`, backtick or pipe on the shim and dispatcher stand-down path
- [ ] Genuine-launcher: a joined fixture whose ops/polaris differs from kit/ops/launcher by one byte → `ask` with the pinned reason; identical → today's allow
- [ ] SessionStart: dispatch.sh sources kit/ops/hooks/dispatch-session.sh when present (T-346 writes it) and is silent otherwise
- [ ] api-kit unchanged (all new functions are `_dp_*`)

## T-346 — "The protocol arrives at session start - the router fits under the hook limit, a joined project gets the router, its voice and the ADHD lines at session start, a plain git project gets the one zero-touch line, and the conductor's role file pages under the harness limit"
points 10 · risk normal · landed 4f63aba9 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/CLAUDE.md, kit/ops/PROTOCOL.md, kit/ops/hooks/dispatch-session.sh, kit/ops/roles/CONDUCTOR.md, ops/tests/api-kit.expected, ops/tests/doc-server.cmd, ops/tests/doc-server.expected, ops/tests/session-context.cmd, ops/tests/session-context.expected

### Why
In a joined project there is no managed protocol block in CLAUDE.md — only a three-line pointer — so the
protocol has to arrive another way: the dispatcher's SessionStart injects it (hook-dispatch.md § 6).
The hook output limit is 10,000 characters and today's protocol (kit/CLAUDE.md) is about 11,600, so it
is trimmed to at most 8,000 bytes. It is one text for both layouts — vendored projects get the shorter
block at their next update, and every session everywhere pays fewer tokens. Every heading, invariant
number and table row stays; long explanations move into PROTOCOL.md sections the router names with
`bash ops/polaris doc PROTOCOL "<section>"`.

`dispatch-session.sh` builds the context: the router, then a one-line voice rule (the repo's value,
else this computer's, else standard), then the five ADHD facts when adhd is on — under 9,000 bytes in
all. In a git project without POLARIS it prints only the zero-touch line (shared-kit.md § 9).

Riding along because the pager is the same problem: `role CONDUCTOR --page 2` is about 32 KB, over the
harness's inline limit, because its Protocol section alone is bigger than a page. One new `##` heading
at a step boundary splits it; that heading is this wave's one api-kit change, so this card owns api-kit.

### Acceptance
- [ ] router ≤ 8,000 bytes; every kit/CLAUDE.md heading byte-identical (api-kit shows no heading change for kit/CLAUDE.md); each moved explanation reachable by the doc PROTOCOL section the router names
- [ ] session-context: every case of hook-dispatch.md § 7's session-context bullet; total ≤ 9,000 bytes printed as `≤ 9000: yes`
- [ ] Every page of role CONDUCTOR ≤ 28,000 bytes before its footer; `## Protocol` unchanged; one new heading
- [ ] doc-server: the new cases; every earlier case byte-identical
- [ ] drift: no doc-overflow finding from the moved text

## T-347 — "The machine update - in a joined project update fetches the next kit, checks its sha256, unpacks it beside the old one and switches every project when none is busy, with no commit anywhere; each project catches up at its next command"
points 13 · risk normal · landed ca79f6cd (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/hooks/update-hook.sh, kit/ops/lib/admin.sh, kit/ops/lib/store.sh, kit/ops/polaris, ops/tests/machine-update.cmd, ops/tests/machine-update.expected

### Why
Today every project updates itself: `update` downloads a tarball, runs the installer into the repo and
commits the result. With one kit per computer an update is a MACHINE operation instead
(shared-kit.md §§ 3, 5; auto-update.md v6): fetch the release zip the channel names, refuse it unless
its sha256 matches the channel's `zip_sha256:`, unpack it beside the running version, and switch
`current` once no registered joined project has work in flight — else stage it in `kit/next` and say
which project is busy. Nothing is committed, parked or installed into any repo.

Each joined project then catches up lazily: the first command after a switch notices its
`.polaris/kit-seen` is behind and runs `upgrade` + `heal` quietly (board folders, configuration), so a
kit change never needs a commit in your projects. Machine mode is recognised with zero forks by the
variable the launcher sets; a vendored install takes none of these branches, so every vendored
command is byte-identical (startup-budget unchanged).

This card is wave 2's only owner of kit/ops/polaris and admin.sh. join and migrate come in 7.0.0
(T-349), so in 6.22.0 the machine path is reached only from test fixtures.

### Acceptance
- [ ] machine-update: every case of auto-update.md v6's golden bullet (two joined fixture projects move with one update and no commit or dirty path · kit-seen written once each · busy → kit/next, later --auto flips · tampered zip refused · no zip_sha256 refused · prune keeps current + previous)
- [ ] Vendored: update-registry, update-pending, update-waiting, update-arms, install-update, startup-budget byte-identical
- [ ] The lazy upgrade never runs for find|show|hops|help|role|doc|router|prefs|version and never in a vendored install
- [ ] __quiet is hidden (not in usage); cli-help-parity re-pinned here only if it must be, with the reason
- [ ] api-kit unchanged (no new public function)

## T-348 — "Release 6.22.0, proven on the joined tree - the store, launcher, dispatcher, session context and machine update all dormant behind detection, every vendored golden unchanged, version 6.22.0 and its changelog"
points 3 · risk normal · landed 79704cca (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: CHANGELOG.md, kit/ops/VERSION, ops/tests/kit-mode.cmd, ops/tests/kit-mode.expected

### Why
The first of the plan's two releases. Everything wave 1 and wave 2 built — the wave cut, the landing
words, the guard functions, the store and launcher, the dispatcher, the session context and the
machine update — sits on main together for the first time here, so this card runs the shared goldens
once on the joined tree and adds the one end-to-end case no single card could: a joined fixture
project whose SessionStart goes through the dispatcher and comes back with the router, and whose
`bash ops/polaris version` runs through the launcher.

Nothing in 6.22.0 writes a launcher into any project and nothing registers the dispatcher, so for
every existing install this is an ordinary minor release. The CHANGELOG says only what was measured.
Tag, push, dogfood and the cli-help re-pin are the conductor's release ritual, not this card's.

### Acceptance
- [ ] kit-mode: + dispatcher SessionStart in a joined fixture (context present, ≤ 9,000 bytes) and a launcher-run `version`; earlier cases byte-identical
- [ ] Every golden in verify green on the joined tree; api-kit strict-equal to the indexed tree
- [ ] CHANGELOG 6.22.0: each claim has its number and where it was measured

## T-349 — "join and migrate - a git project joins the machine kit with only a launcher and its state, and a vendored project converts in one commit that git revert undoes byte for byte"
points 13 · risk normal · landed b17b116f (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/lib/join.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/join-migrate.cmd, ops/tests/join-migrate.expected, ops/tests/startup-budget.cmd, ops/tests/startup-budget.expected

### Why
The switch to machine mode starts here (7.0.0). `join` sets a git project up against this computer's
kit: it writes only the launcher, the attribute and ignore lines the installer adds today, the
commit-message hook, the machine registry entry and a three-line version-free pointer in CLAUDE.md —
no `.claude/` folder, no settings, no kit code, no commit (shared-kit.md § 6). It prints
`installed · fresh` so the agent runs INIT next, exactly as after today's quiet install.

`migrate` converts an existing vendored project in ONE commit: kit files out, launcher in, POLARIS's
own hook entries and output style swept out of the project's `.claude/settings.json` with the same
helper `uninstall` uses (permission rules are left alone), the managed block replaced by the pointer
(§ 7). It refuses on a busy board, in the POLARIS repo (its `ops/` is the update channel), and when this
computer's kit is older than the project's. `git revert` of that commit restores the vendored project
byte for byte — the golden proves it. The owner's yield of repo preferences to the machine file is
printed as their step, never done for them.

No project of the owner's is migrated by this work; only test fixtures are.

### Acceptance
- [ ] join-migrate: join in a fresh fixture writes exactly the § 6 set and nothing under .claude/; every `bash ops/polaris version|status|role BUILDER|doc PROTOCOL` works through the launcher; each refusal prints its pinned line and writes nothing
- [ ] join-migrate: migrate of a vendored fixture is one commit with the § 7 content; `git revert` → `git diff <before> HEAD` empty; each refusal pinned
- [ ] Last line of join is `installed · fresh` (or `installed · live-board`), ≤ 2 lines above it, no INIT kickoff phrase
- [ ] api-kit: + cmd_join, cmd_migrate only; startup-budget unchanged for every other verb
- [ ] join never runs install.sh and never writes a settings file

## T-350 — "Only the owner's setup writes Claude Code settings - python polaris-v5.zip --setup stores the kit, installs the shim and trust tier and registers the one dispatcher, and every agent-run install, update or guard install writes no permission, mode or hook"
points 10 · risk high · landed 1d37882d (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/bootstrap.py, kit/ops/hooks/model-guard.sh, kit/ops/lib/admin.sh, kit/ops/lib/awake.sh, kit/ops/lib/prefs.sh, kit/ops/selftest-install.sh, ops/tests/machine-armed.cmd, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected, ops/tests/perm-tools.cmd, ops/tests/prefs-cli.cmd, ops/tests/prefs-cli.expected, ops/tests/update-arms.cmd, ops/tests/update-arms.expected

### Why
The owner's decision for 7.0.0: only the setup command they run themselves writes Claude Code's
permission rules, auto mode or hooks. Today four agent-run paths do it silently (the installer, the
update's machine refresh, the guard installer, an INIT instruction). This card adds the one owner path
and closes the agent ones (shared-kit.md §§ 10-11, install-parity.md v2).

`python polaris-v5.zip --setup` does what `--claude-skill` does today and also stores the kit, installs
the shim and the trust tier the dispatcher reads its read-only approvals from, and registers the one
dispatcher per event in place of the machine-level model guard it folds. It refuses when run by an
agent (`CLAUDECODE` set). Under `CLAUDECODE`, every install acts as `--no-permissions` and prints one
line asking the owner to run `--setup`; `model-guard.sh install` and `polaris awake install` refuse the
same way; and the update's permission block is deleted outright. A human (and CI, which never sets
`CLAUDECODE`) sees today's behaviour, which keeps ci.yml's settings checks green without touching
`.github/`. `prefs --seed` also fills `owners:`, which zero-touch uses to decide whose projects set
themselves up without asking.

### Acceptance
- [ ] selftest-install.sh: every install-parity v2 assert (--setup refused under CLAUDECODE=1 with settings byte-identical · --setup in a fake home → current, hook, trust copy, one dispatcher entry per event, folded model-guard entries gone, keep-awake kept, second run byte-identical · a plain install under CLAUDECODE=1 leaves ~/.claude/settings.json byte-identical)
- [ ] model-guard-v2: + `install` under CLAUDECODE=1 refused with the needs-you line; every earlier case byte-identical
- [ ] prefs-cli: + --seed fills owners: when unset, leaves it when set
- [ ] Without CLAUDECODE every bootstrap path is byte-identical to 6.22 (ci.yml 250-295, 339, 497 unaffected)
- [ ] refresh_machine_kit writes nothing to settings.json in any mode; update-arms re-pinned only for that

## T-351 — "A project sets itself up from a work request - INIT skips what a joined project's request already answers and authors the request as the first task, INIT no longer writes permission rules, and the two zero-touch keys join the registry"
points 5 · risk normal · landed 3f4a4b75 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/KEYS.tsv, kit/ops/lib/core.sh, kit/ops/roles/INIT.md, ops/tests/cfg-layers.cmd, ops/tests/cfg-layers.expected, ops/tests/keys-drift.cmd, ops/tests/keys-drift.expected

### Why
With zero-touch, the owner's first request in a project without POLARIS can set the project up
(shared-kit.md § 9): the session-start line tells the agent to `join`, then run INIT "entered from a
work request". INIT then has less to ask: when this computer's preferences answer every question,
interaction 1 is skipped; the request itself is the goal, so the goal question is skipped too; the
safety questions stay; and the request becomes the first task, routed by `triage` (first-run.md v3).
No new heading — bold lead-ins only — so the api-kit golden does not move.

INIT also stops telling the agent to add a `shot:` command to `.claude/settings.json`
`permissions.allow` — the owner's rule is that no agent writes permission rules (shared-kit § 11).

`auto_setup` (ask | auto | off) and `owners` live only in the machine preferences file; they join
KEYS.tsv with scope `machine` and the allowlist in core.sh, so `prefs` shows them and the registry
golden ties stay honest.

### Acceptance
- [ ] INIT.md: the § 0 lead-in and its four rules per first-run v3; the shot: allow paragraph gone; no heading added or changed (api-kit unchanged)
- [ ] KEYS.tsv: auto_setup (default ask) and owners (default empty), scope machine; core.sh allowlist +2 in the same order; cfg-layers allowlist tie green
- [ ] keys-drift re-pinned for exactly the two rows (read by the dispatcher, not cfg — say so in the expected's reason if the golden carries one)
- [ ] interview and doc-refs unchanged

## T-352 — "Release 7.0.0, one kit for the whole machine - nothing an agent runs grants itself a permission, a joined project works end to end, the install skill joins on a machine with a kit, version 7.0.0 and its changelog"
points 8 · risk normal · landed 6630207f (2026-11-24) · claimed 2026-11-24
files touched: CHANGELOG.md, kit/.claude/skills/polaris-install/SKILL.md, kit/ops/VERSION, kit/ops/hooks/awake-hook.sh, kit/ops/hooks/dispatch.sh, kit/ops/lib/observe.sh, kit/ops/lib/selftest/policy.sh, kit/ops/lib/selftest/remote.sh, kit/ops/lib/selftest/spine.sh, ops/tests/api-kit.expected, ops/tests/awake-hook.cmd, ops/tests/awake-hook.expected, ops/tests/hook-dispatch.cmd, ops/tests/hook-dispatch.expected, ops/tests/kit-mode.cmd, ops/tests/kit-mode.expected, ops/tests/no-self-grant.cmd, ops/tests/no-self-grant.expected

### Why
The second release and the plan's DONE line. Everything is on main; this card proves it on the
joined tree. `no-self-grant` runs every agent-run path with `CLAUDECODE=1` against a fake home and
proves none of them changes a settings file (shared-kit.md § 11) — the owner's condition for this
release. `drill_sharedkit` walks the whole life of a joined project in a fake home — join, a command
through the launcher, the dispatcher's session start, one update moving two projects with no commit,
migrate, and the revert — inside `doctor --selftest`, so it runs on Linux, macOS bash 3.2 and Windows CI
without touching `.github/`.

The install skill learns the new first rung: on a machine with a kit, "install POLARIS" in a project
means `join`, then INIT; the zip install stays for machines without one and for CI. Migrating one of the
owner's projects happens only when the owner names it. 7.0.0 is a MAJOR, so installs on other machines
ask before moving. Tag, push, dogfood, cli-help and the owner's `--setup` click are the conductor's
release ritual and close.

### Acceptance
- [ ] no-self-grant: every path in step 2 → `byte-identical` per file; the same run WITHOUT CLAUDECODE for the bootstrap install still merges (proves the golden can see a write)
- [ ] drill_sharedkit green locally (doctor --selftest --only sharedkit via bg run) and named in spine.sh
- [ ] kit-mode: + the joined-testbed cases; earlier cases byte-identical
- [ ] SKILL.md: ## Join, ## Migrate, rung 1 = join; skill-budget/skill-install re-pinned only if they move; api-kit + exactly those two headings
- [ ] CHANGELOG 7.0.0: MAJOR notice, each claim measured

## T-353 — The 6.22 wave seals — session context prints LF on Windows, heal-model-line's fixture is ready for kit_file
points 2 · risk normal · landed eaa404e2 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/hooks/dispatch-session.sh, ops/tests/heal-model-line.cmd, ops/tests/session-context.cmd, ops/tests/session-context.expected

### Why
The 2026-11-24 one-kit wave (T-341..T-346 landed on integrate/2026-11-24) did not seal. Its wave
check (`tools/proof.sh`, run on this Windows machine) is red on:
1. session-context (T-346): identical words, but some output lines end CR+LF where the expected file
   has LF (first difference at byte 193). Find where the CR comes from — most likely python- or
   Windows-native output inside kit/ops/hooks/dispatch-session.sh or the .cmd's own python — and make
   the PRODUCT emit LF on every OS (a hook's stdout is read by the harness; CRs in injected context are
   a real defect, not only a golden one). Do not hide it by stripping CRs only in the golden unless the
   CR is produced by the golden's own harness code.
2. heal-model-line: since T-341 `heal` finds templates/DESIGN.md through kit_file, so this fixture now
   also installs ops/DESIGN.md and prints one extra `healed: ops/DESIGN.md …` line. Keep the expected
   output byte-identical by making the fixture behave as its intent says: give it a ready ops/DESIGN.md
   (as it does with .polaris/brain/), or run a vendored copy of the CLI as heal-design now does.
This card's files exist only on the open wave, so it must be cut from the wave (T-341's `_wave_cut`).
- amend: deps -T-346 — fix card for the open wave's red check; it lands on the same wave (T-341's wave cut), so it cannot wait for T-346 to reach done
- CR source: the golden's own python print (text-mode stdout on Windows); product hardened anyway — _ds_session strips CR from router/tail text (a CRLF checkout's kit/CLAUDE.md leaked escaped \r into additionalContext); the 'facts: identical' line was missing from the expected because the CRs had broken that cmp

## T-354 — perm-tools asserts the update path writes no permission rules (admin.sh union block gone)
points 1 · risk normal · landed 7389b605 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: ops/tests/perm-tools.cmd, ops/tests/perm-tools.expected

### Why
The 6.22.0 final qa (7f99ba4) is red only on perm-tools: it counts the permission "union block" in
kit/ops/lib/admin.sh (refresh_machine_kit) and expects 1, but T-347 deleted that block on purpose —
plans/one-kit.md and shared-kit.md: "refresh_machine_kit's permission block is DELETED in both modes"
(an agent-run update must never write permission rules). Turn the admin.sh half of that line into the
new invariant: the update path holds NO permission union (`admin.sh 0`), and say so in the .cmd's
comment. bootstrap.py's union (the owner-run installer) stays asserted as 1. Every other expected line
byte-identical.
- amend: deps -T-350 — 6.22.0 must ship before 7.0.0's T-350; T-350 was moved back to backlog and now follows this card
