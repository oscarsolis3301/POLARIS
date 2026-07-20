# CONTRACT: verification-tiering            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates targeted re-checking (`doctor --selftest --only` — T-033; slow-suite hint in `land` +
duration stamp in `qa` — T-031) from the full gates, which stay untouched: check what changed often,
prove everything once.

## Interface — `doctor --selftest --only <pattern>` (T-033)
```
polaris doctor --selftest                    # unchanged: every drill, byte-identical semantics,
                                             # pass line still starts `selftest passed`
polaris doctor --selftest --only <pattern>   # SPINE + only labeled drills whose label matches
                                             # <pattern> (one shell glob, case-glob match)
```
- **Spine** (always runs — it builds the throwaway repo's state): bootstrap + the core mechanics
  chain (race → ownership/verify → handoff → land → seal → history → done → rollback → second seal →
  quiet-board assertions). The spine is not skippable and has no label.
- **Labeled drills**: every self-contained section AFTER/AROUND the spine gets a label via a tiny
  `drill_on <label>` helper (plain `case`/pattern match — NEVER inside `$(...)`). Minimum label set
  (implementer may add more, never fewer): `fmlist` `tcm` `report` `rules` `drift` `metrics` `qa`
  `notify` `grant` `upgrade` `pr-publish` `brain` `express` `brief` `hint`.
- Pattern matching NOTHING in the label list → die BEFORE the spine, listing the valid labels
  (message contains `unknown drill label`). Fail loud — a no-op subset must never look green.
- Subset pass line is DISTINCT: starts `selftest passed (subset:` and names the pattern + counts —
  a subset run can never be mistaken for the full gate.

## Interface — suite-duration stamp + slow-suite hint (T-031)
```
.polaris/last-suite-seconds     # one line: "<seconds> <epoch>" — written by qa after its
                                # test/lint/typecheck/build/uat loop, only when ≥1 command ran
```
- `land <ID>` (both forms), after a successful land: if CONVENTIONS `integration:` = `paranoid` AND
  the stamp exists AND seconds > 120 → print ONE note containing `suite last took` and
  `integration: batch` (the batch-first guidance, made mechanical). Silent when: no stamp · `batch` ·
  ≤120s. Never changes exit status.

## Executable check (rides the kit selftest)
- T-033 drills: `--only` with a nonsense pattern → rc 1 + `unknown drill label` (cheap, pre-spine);
  `--only fmlist` → rc 0 + pass line starts `selftest passed (subset:`.
- T-031 drills: fake stamp `180 <epoch>` + `integration: paranoid` → land output matches
  `suite last took`; `integration: batch` same stamp → no such line.
Run: `bash kit/ops/polaris doctor --selftest`.

## Invariants
- Full-suite semantics untouched: no drill deleted, no assertion weakened, plain `--selftest`
  behavior identical. `qa` remains the unchanged, full, final gate in every flow.
- Bash >= 3.2; no `case` inside `$(...)`.

## Example
```
$ ops/polaris doctor --selftest --only 'express'
…
selftest passed (subset: express — 1 of 15 labeled drills; spine always runs)
$ ops/polaris land T-042        # paranoid repo, suite stamp 178s
✅ landed T-042 …
⚠ suite last took 178s (>2 min) — paranoid re-runs it per land; consider integration: batch
```

## Changelog
- v1 2026-07-20: created for T-031 (stamp + hint) · T-033 (--only)
