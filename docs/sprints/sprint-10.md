# Sprint 10 — Autonomy by default (6.0.0) (2026-08-03–)

## T-048 — "`polaris approve <ID> <scope> -m \"why\"` — the sibling of grant"
points 5 · risk high · landed 0e032ad (2026-08-03) · claimed 2026-08-03 → done 2026-08-03
files touched: kit/ops/lib/builder.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
An `ask` rule is only half a mechanism without a sanctioned way to record the human's yes. This is
that way, and it is deliberately the twin of `grant`: same shape, same refusal discipline, same
single board commit. **They stay distinct commands** — `grant` widens ownership, `approve` clears a
policy gate, and only `approve` needs a human.

The generalization matters as much as the command: `grant_append_owned` becomes a field-name-taking
append-only front-matter writer that both callers share, rather than a second near-copy of 25 lines
of awk drifting away from the first.

The `feat/*` refusal is the load-bearing containment. An approval mechanism is exactly what a stuck
agent rationalizes its way into, so a Builder approving itself must be *mechanically impossible*, not
merely discouraged. Read `ops/contracts/ask-approval.md` § 3.

### Acceptance
- [ ] `grant_append_owned` generalized to take a field name; `grant` calls it with `files_owned` and
- [ ] the generalized writer refuses (rc non-zero, file untouched) when the named field is absent —
- [ ] `cmd_approve` exists in `kit/ops/lib/builder.sh`, modelled on `cmd_grant`: same option parsing,
- [ ] refuses, board untouched, when `<ID>` is not on the board
- [ ] refuses, board untouched, when `-m "why"` is missing or empty
- [ ] refuses and SAYS SO when `<scope>` matches no `ask`-kind rule (approving something ungated is a
- [ ] refuses when `git rev-parse --abbrev-ref HEAD` is `feat/*`
- [ ] every refusal mutates nothing: no partial write, no board commit, no event, clean tree
- [ ] success appends `<scope> — <who>, <date>: <why>` to the task's `approved:` list, one
- [ ] `approve` dispatched in `kit/ops/polaris` and documented in `help` in the `grant` house style
- [ ] `bash ops/polaris check --only cli-help-parity` and `--only triage-lane` stay green (the latter
- [ ] `check_rules` threaded with the task ID at its builder.sh call sites (`cmd_verify`,
- [ ] W1 api-kit owner (key-registry.md § 5): ops/tests/api-kit.expected gains `cmd_approve` and

## T-049 — "Move the ask to the plan gate — ready gate, triage three-way, rules health"
points 5 · risk normal · landed 92ab95f (2026-08-04) · claimed 2026-08-04
files touched: kit/ops/lib/observe.sh, ops/tests/api-kit.expected, ops/tests/triage-lane.cmd, ops/tests/triage-lane.expected

### Why
This is the half that actually fixes the ARC failure. T-047 makes an approval *possible*; this makes
the board *ask for it before a Builder is ever spawned*.

The ARC sequence was: ready gate never consults RULES → task promoted to `ready/` with nothing
objecting → `triage` prints `full` → Builder claims it → dies on its first write. Break it at step 1
and the rest never happens. A task that needs a human's yes belongs in `blocked/` with a note, not in
`ready/` waiting to burn a Builder's whole context discovering it cannot write.

Read `ops/contracts/ask-approval.md` § 5 — the three triage cases and the finding text are exact.

### Acceptance
- [ ] `cmd_rules` accepts `ask` as a valid kind in its health check (alongside `path|content`), and
- [ ] `cmd_drift` step 2 gains a check: a `ready/` task whose `files_owned` intersects an `ask` scope
- [ ] that finding makes `drift --strict` exit 1
- [ ] a `ready/` task WITH a covering approval produces no finding
- [ ] `cmd_triage` distinguishes three cases instead of one: `path` scope → `full` +
- [ ] `triage` line 1 is still exactly one bare word (`solo`/`express`/`full`); every reason stays on
- [ ] `bash ops/polaris check --only triage-lane` green — the golden asserts line-1 shape, the

## T-074 — "KEYS.tsv — the key registry ships with the kit"
points 2 · risk normal · landed 011c489 (2026-08-03) · claimed 2026-08-03 → done 2026-08-03
files touched: kit/ops/KEYS.tsv, kit/ops/install.sh, ops/RULES.tsv, ops/tests/rules-health.expected

### Why
`update` refreshes kit code and never rewrites CONVENTIONS.md — correct, and exactly why every
capability gated on a NEW key ships dormant: nothing in the system compares an installed repo's
config against the kit's feature set (polaris-testbed is missing 19 keys on byte-identical kit
code). This file is the single source of truth both fixes read: doctor's one-line drift report
(T-076) and `polaris adopt` (T-077). One TAB-separated row per key: key · version introduced ·
effective default · what the repo loses while it is absent.

### Acceptance
- [x] `kit/ops/KEYS.tsv` exists with exactly the 37 rows named in key-registry.md § 1 (the
- [x] the `default` column records the EFFECTIVE 6.0 value — for the three autonomy knobs that is
- [x] `KEYS.tsv` added to `KIT_CODE` at kit/ops/install.sh:76 — one token; both install paths
- [x] `ops/RULES.tsv` gains a `path` rule guarding `ops/KEYS.tsv` as an installed copy, matching
- [x] `ops/tests/rules-health.expected` updated for the new rule count (14 → 15) — this task
- [x] surface-frozen (key-registry.md § 5): no new top-level fn, no new markdown heading under

## T-075 — "Flip the autonomy defaults — unset composes trusted; doctor always says so"
points 3 · risk normal · landed de43297 (2026-08-03) · claimed 2026-08-03 → done 2026-08-03
files touched: kit/ops/lib/observe.sh

### Why
The hands-free machinery shipped in 5.13.0 and stayed OFF in exactly the repos that never learned
it existed — unset knobs composed to confirm/ask/confirm, and doctor printed the composition ONLY
when a knob was already set (observe.sh:265), so the repos most needing the message were guaranteed
not to get it. This is the heart of 6.0.0: invert the three fallbacks in kit CODE so `update`
delivers autonomy through the mechanism it already refreshes, and delete the silence. Nothing here
writes into anyone's CONVENTIONS.md, and no hard gate softens.

### Acceptance
- [ ] the three `if [ -z … ]` fallbacks (observe.sh:273/277/281) invert: unset resolves to
- [ ] precedence unchanged: an explicit individual knob beats `autonomy:` in BOTH directions —
- [ ] fail-safe unknowns per v2: unknown `autonomy:` → warn once, behave as `standard`; unknown
- [ ] the `if [ -n "$a$pg$bq$ea$dr$ds" ]` guard at observe.sh:265 is deleted — the composition
- [ ] the `drain:` note keeps its own `[ -n "$dr$ds" ]` condition (drain is never composed and
- [ ] the stale comment block at observe.sh:258-261 ("Silence = every default = today's
- [ ] surface-frozen (key-registry.md § 5): no new top-level fn — the flip lives inside

## T-076 — "Doctor reports config drift — one line naming the keys an install is missing"
points 3 · risk normal · landed b923cf2 (2026-08-04) · claimed 2026-08-04 → done 2026-08-04
files touched: kit/ops/lib/observe.sh, ops/tests/keys-drift.cmd, ops/tests/keys-drift.expected

### Why
The only drift detector of this class is the CLAUDE.md `[kit X.Y.Z]` stamp (observe.sh:427-443),
added after a repo sat three weeks stale while doctor called it healthy — and that lesson was
applied to exactly one file. This applies it to the config surface: after the CONVENTIONS presence
check (:251), read `ops/KEYS.tsv` and report absent keys as ONE line in the stamp check's tone.
One line, not a warning storm; a commented stub counts as present, which is how `adopt` (T-077)
silences the line without changing behavior.

### Acceptance
- [ ] `$OPS/KEYS.tsv` missing → say nothing (pre-6.0 installed copy)
- [ ] presence test per key-registry.md § 2: line-start `key:` OR a `# key:` stub both count as
- [ ] absent keys → exactly the pinned one-liner (first six absent keys in KEYS.tsv order,
- [ ] zero absent keys → no output from this check at all
- [ ] no kit version number in the line (derived-surface golden trap)
- [ ] golden pair `ops/tests/keys-drift.{cmd,expected}` — HERMETIC (fixture repo + fixture
- [ ] surface-frozen (key-registry.md § 5): implemented inline in cmd_doctor, no new top-level fn

## T-077 — "`polaris adopt` — commented stubs for every missing key, plus the 6.0 update banner"
points 5 · risk normal · landed bd647d3 (2026-08-04) · claimed 2026-08-04 → done 2026-08-04
files touched: kit/ops/lib/admin.sh, kit/ops/polaris, ops/tests/adopt-stub.cmd, ops/tests/adopt-stub.expected, ops/tests/api-kit.expected

### Why
Doctor's drift line (T-076) tells you keys are missing; this is the hand that fixes it — the
discovery mechanism, deliberately NOT how autonomy arrives. `adopt` appends commented stubs
carrying each key's default and one-line rationale from KEYS.tsv, so uncommenting a line is the
whole gesture of enabling a feature. And the same release must be LOUD at the moment it lands:
`update`'s `refreshed here:`/`untouched:` pair (admin.sh:403-404) gains the two pinned BREAKING
lines naming the one-line revert, exactly when a repo crosses to 6.0 with no knob set.

### Acceptance
- [ ] `cmd_adopt` in kit/ops/lib/admin.sh per key-registry.md § 3: appends stubs to the END of
- [ ] never edits an existing line, never uncomments, never reorders, never writes a live value;
- [ ] idempotent: second run appends nothing, file byte-identical, prints
- [ ] no KEYS.tsv → die naming `ops/polaris update`; no CONVENTIONS.md → die pointing at INIT
- [ ] dispatched in kit/ops/polaris beside `update`/`upgrade` (:311-315) and documented in
- [ ] `cmd_update` prints the two pinned banner lines from hands-free-knobs.md v2 § Pinned
- [ ] golden pair `ops/tests/adopt-stub.{cmd,expected}` — HERMETIC (fixture repo + fixture
- [ ] W2 api-kit owner (key-registry.md § 5): ops/tests/api-kit.expected gains `cmd_adopt` AND

## T-078 — "settings.json hook merge keys on script PATH and updates POLARIS-owned fields"
points 3 · risk normal · landed 473b5e7 (2026-08-04) · claimed 2026-08-04 → done 2026-08-04
files touched: kit/ops/install.sh, kit/ops/selftest-install.sh

### Why
The merge at install.sh:267-297 keys on hook script BASENAME and `continue`s when present, so an
existing entry is never re-examined and a shipped field change can never arrive. Real cost,
measured: polaris-testbed is pinned at ownership-guard.sh `timeout: 10` while the kit ships 20,
against a guard core.sh measures at ~8s per write — parked on the fail-open margin permanently,
which means the ownership gate silently drops exactly when the machine is slow. Fix the identity
(script PATH under `ops/hooks/`, not basename), replace POLARIS-owned entries wholesale, and touch
nothing the user added.

### Acceptance
- [ ] POLARIS-owned entry := any hooks entry whose `hooks[].command` contains the path segment
- [ ] a target entry running the same `ops/hooks/<script>` as a kit entry is REPLACED wholesale
- [ ] user-added hook entries (no `ops/hooks/` in any command) are byte-untouched, whatever
- [ ] idempotent — a second install changes nothing; the report line names updated entries as
- [ ] `drill_hookmerge` in kit/ops/selftest-install.sh (fn name pinned in key-registry.md § 5-6;
- [ ] `drill_live_board` green UNCHANGED — the preserve guarantee (board_snapshot,

## T-079 — "The prose flips with the code — CONDUCTOR, BUILDER, EVOLVE, INIT skeleton"
points 2 · risk normal · landed 8efb81e (2026-08-03) · claimed 2026-08-03 → done 2026-08-03
files touched: kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/EVOLVE.md, kit/ops/roles/INIT.md

### Why
The three gate knobs are ENFORCED by role-file prose — the conductor computes effective plan_gate
from CONDUCTOR.md:111-119, builders read BUILDER.md:36, EVOLVE reads EVOLVE.md:16. So this task is
not documentation trailing the code: for the roles, it IS the behavior change. Each surface gets
the byte-exact pinned sentence from hands-free-knobs.md v2 § Pinned strings, so the prose and
observe.sh state the same default and can never drift apart in this release.

### Acceptance
- [ ] CONDUCTOR.md:111-113 — the effective-plan_gate sentence replaced with the v2 pinned
- [ ] BUILDER.md:36 — opening clause replaced with the v2 pinned clause (`default-safe` is the
- [ ] EVOLVE.md:16 — the parenthetical replaced with the v2 pinned parenthetical
- [ ] INIT.md:120-134 — the four commented autonomy-stanza lines state the 6.0 facts: unset =
- [ ] no markdown heading added, removed, or renamed in any of the four files (api-kit records

## T-082 — "Radically plain `standard` voice — new row, re-cut rules, Pre-send check, plain examples, plain-voice golden"
points 3 · risk normal · landed 3f33f42 (2026-08-04) · claimed 2026-08-04 → done 2026-08-04
files touched: kit/.claude/output-styles/polaris.md, kit/ops/PROTOCOL.md, ops/tests/plain-voice.cmd, ops/tests/plain-voice.expected

### Why
With `voice: standard` ("plain, friendly English") the owner's summaries come back short but dense
and technical — a real close read "Wave 1 is sealed as sprint/10, the tree is clean, and waves 2–5
sit on the board with their dependencies satisfied", every noun jargon. Root causes are in the texts
themselves: the `standard` row bans only POLARIS jargon and its "unless you explain it in the same
breath" escape hatch licenses jargon; the 7 rules optimize volume, not simplicity; and the style's
own worked examples — the model's imitation target — say "Full suite is green on `main`". This task
replaces the words in BOTH copies (they are one artifact under contract invariant 6) and gives
invariant 6 its first mechanical pin. Every replacement text is byte-exact in
`ops/contracts/output-style.md` § v2 — write those bytes, do not compose your own.

### Acceptance
- [ ] `standard` row in `kit/ops/PROTOCOL.md` § VOICE (currently line 235) replaced with the § v2
- [ ] zero occurrences of "in the same breath" in either file — the escape hatch is dead
- [ ] the 7 rules re-cut per § v2, byte-identical in both files, still EXACTLY 7 lines matching
- [ ] Pre-send check per § v2 added IDENTICALLY to both files: bold-led paragraph + dash bullets,
- [ ] both worked examples under the existing `## What a close reads like` heading replaced with
- [ ] `voice: technical` untouched — row and behavior
- [ ] new golden `ops/tests/plain-voice.cmd` + `.expected` with the SEVEN assertions specified in
- [ ] sabotage-proven: reintroduce one jargon word into an example and one drifted rule line →
- [ ] `output-style-installed` and `adhd-skill-installed` goldens still green (pinned literals

## T-083 — "Role prose speaks the plain voice — conductor close, solo report, builder progress line, INIT picker, CLAUDE.md clause"
points 2 · risk normal · landed 952d80b (2026-08-04) · claimed 2026-08-04 → done 2026-08-04
files touched: kit/CLAUDE.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INIT.md, kit/ops/roles/SOLO.md

### Why
T-082 rewrites what `voice: standard` means; this task makes the role files ASK for it at the spots
where a human actually reads agent prose. Each edit is a small in-line wording change — zero new or
renamed `##`/`###` headings anywhere (ops/tests/api-kit.expected pins every kit heading and this
task does not own it). The register itself lives in ops/contracts/output-style.md § v2 — these
edits point at it, they never restate it.

### Acceptance
- [ ] CONDUCTOR.md step 8 (≈lines 249-251) first sentence becomes: In `voice:`, **≤8 lines**
- [ ] CONDUCTOR.md relay example (≈line 146) becomes: `"✅ 2 of 5 done — the new navigation is in,
- [ ] SOLO.md report line (≈lines 62-63) becomes: what changed, how you know it works, what you
- [ ] BUILDER.md `✅` progress line (≈line 26) gains: the words follow the repo's `voice:`; in
- [ ] INIT.md voice-picker (≈line 46) standard option becomes: `**Plain English** — friendly,
- [ ] kit/CLAUDE.md § PROGRESS FORMAT sentence becomes: Keep the shape; the words inside follow
- [ ] pinned literals survive in kit/CLAUDE.md: `🎉 Complete!` and `subagent never ends a run`
