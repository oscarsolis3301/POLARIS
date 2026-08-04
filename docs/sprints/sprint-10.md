# Sprint 10 — Autonomy by default (6.0.0) (2026-08-03–)

## T-048 — "`polaris approve <ID> <scope> -m \"why\"` — the sibling of grant"
points 5 · risk high · landed 0e032ad (2026-08-03) · claimed 2026-08-03
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

## T-074 — "KEYS.tsv — the key registry ships with the kit"
points 2 · risk normal · landed 011c489 (2026-08-03) · claimed 2026-08-03
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
points 3 · risk normal · landed de43297 (2026-08-03) · claimed 2026-08-03
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

## T-079 — "The prose flips with the code — CONDUCTOR, BUILDER, EVOLVE, INIT skeleton"
points 2 · risk normal · landed 8efb81e (2026-08-03) · claimed 2026-08-03
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
