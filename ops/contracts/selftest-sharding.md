# CONTRACT: selftest-sharding            (v1 — 2026-07-21)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Lets the ~7-minute drill suite run as N parallel shards, OPT-IN only — serial stays the default,
byte-identical to today, and CI stays serial. Task: T-040 (extends `--only` from
ops/contracts/verification-tiering.md).

## Interface
```
doctor --selftest [--only <patterns>] [--parallel <N>]
```
- `--only <patterns>` — EXTENDED, additively: a comma-separated list of case-glob patterns.
  A label is selected when it matches ANY pattern. A single pattern (no comma) behaves exactly
  as today, including the pre-spine `unknown drill label` death when nothing matches. A list
  where any element matches no label ALSO dies with the existing `unknown drill label` wording.
- `--parallel <N>` — requires `--selftest`. N must be an integer ≥ 2, else:
  `⛔ --parallel needs an integer >= 2` (rc 1). When N exceeds the selected-label count k,
  clamp to k and print `   --parallel clamped to <k> (only <k> labels selected)`.
- No `--parallel` = the serial path, UNTOUCHED — byte-identical output, same exit codes.

## Shard semantics
1. Resolve the selected label set (after `--only` filtering) in `SELFTEST_LABELS` canonical order.
2. Partition round-robin: label i goes to shard `i mod N`. Deterministic — same inputs, same shards.
3. Each shard is a CHILD RE-INVOCATION: `"$SELF" doctor --selftest --only <comma-list-of-its-labels>`,
   backgrounded, stdout+stderr to its own log file under ONE parent mktemp dir. Isolation is total:
   every child builds its own throwaway repo (existing `--only` behavior), no shared state.
4. Parent `wait`s for all shards, then prints per shard, in shard order:
   green → `✅ shard <i>/<N> green — <labels>`
   red   → the shard's log replayed verbatim, then `⛔ shard <i>/<N> RED — <labels>`
5. Verdict: all green → final line `✅ selftest passed — <N> shards` rc 0; any red → rc 1.
   The green final line MUST contain `selftest passed` — the log-and-poll recipe greps for it.
6. Each shard pays a full spine (setup ~1 min): sharding trades CPU for wall-clock. Document, don't
   optimize, this sprint.

## Executable check
Owned by T-040; listed in T-042's `verify:` (the seam stays honest across later extractions):
`bash kit/ops/polaris doctor --selftest --parallel 2 --only 'fmlist,grant'`
→ 2 shards, one label each, both green, final line `✅ selftest passed — 2 shards`, rc 0.

## Invariants
- **Hermeticity (v1.1).** Every labeled drill leaves the shared fixture repo exactly as it found
  it — board columns, RULES.tsv, CONVENTIONS values, refs, locks — or provisions and removes its
  own scratch state. No drill may depend on state another label created OR cleaned up. Definition:
  every single label greens in isolation, every comma-list greens in any order, every partition
  greens — `--only`/`--parallel` results are partition-invariant.
- Serial (`--parallel` absent) output byte-identical to pre-split for every input.
- CI invocations stay serial until a full green week — flipping CI is a HUMAN decision, not this sprint.
- bash 3.2 only: background jobs + `wait`, no `wait -n`, no mapfile, no `case` inside `$(...)`.
- The parent cleans up its mktemp dir on exit (trap), including on red.

## Doc phrase — pinned for T-041 (cite verbatim, no paraphrase)
"Opt-in: `doctor --selftest --parallel <N>` runs the labeled drills in N parallel shards; serial
stays the default and CI stays serial."

## Example
`doctor --selftest --parallel 3` → 18 labels round-robin into 3 shards of 6 → 3 children run
concurrently (~3 min wall) → `✅ shard 1/3 green — fmlist brain grant …` ×3 →
`✅ selftest passed — 3 shards`.

## Changelog
- v1 2026-07-21: created for T-040, T-041, T-042 (plan: many-hands)
- v1.1 2026-07-21: hermeticity clause added for T-046 — drills must be state-neutral in the shared
  fixture. Evidence (wave-3 integrator): the `rules` drill leaves a contract-less ready task that
  only an intervening `drift` drill masks → shard 3 red under `--parallel 3`; serial reproducer
  `--only rules,qa` on pre-T-042 main.
