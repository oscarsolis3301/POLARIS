# CONTRACT: express-lane            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the express CLI (`land --express` — T-031) from the conductor triage that invokes it
(CONDUCTOR.md — T-034) and the by-hand recipe (MANUAL — T-037): a single small task stops paying the
full pipeline.

## Interface — CONVENTIONS key
```
express: auto               # auto (default; unset = auto) | off (full ceremony always)
# unknown value → warn once, behave as OFF (fail to the full ceremony — the safe side)
```

## Interface — CLI (T-031, in kit/ops/polaris)
```
polaris land --express <ID>   # primary checkout, ON <base>, clean tree. One pass:
  1 create/reuse integrate/<today> from <base>
  2 audit + land <ID>                                  (existing cmd_land semantics, unchanged)
  3 run the FULL CONVENTIONS suite ONCE (test/lint/typecheck/build, uat if set — same set as qa)
      red → git reset --hard HEAD~1 · kickback <ID> with the failing tail · die
  4 seal <today>                                       (existing cmd_seal semantics, unchanged)
  5 run-verify <ID> · done <ID> · delete integrate/<today>
  exit 0 green; final note names `ops/polaris qa` as the still-mandatory finish line
```
REFUSALS — die BEFORE step 1, message must contain the quoted fragment (drill greps):
- review/ holds any task other than <ID>, or <ID> not in review/ → `express lands exactly one task`
- task frontmatter `risk: high` → `risk: high never rides the express lane`
- CONVENTIONS `express: off` (or unknown value) → `express: off`
- CONVENTIONS `publish: pr` → `express needs publish: direct`

## Conductor triage (T-034, CONDUCTOR.md — pinned semantics)
After the planner's report, take the express path ONLY when ALL hold:
plan created exactly ONE task · ≤2 points · `risk: normal` · nothing on the STOP-AND-ASK list touched ·
`express:` ≠ off · `publish:` = direct. Then: one builder subagent → ONE integrator subagent told to
use `land --express <ID>` → conductor still runs `bash ops/polaris qa` itself. Skip the QA scout and
EVOLVE (≤1 task = no signal; the EVOLVE skip rule already exists). Plan-gate disclosure line, verbatim:
`small change — taking the express lane`. Any triage condition failing → the standard full loop, silently.

## Executable check (rides the kit selftest — T-031 adds)
Drills in `selftest()`: happy path (one review task → `land --express` leaves it in done/ with a
`landed:` stamp, sprint tag exists/moved, integrate branch deleted, tree clean) + all four refusals
(each grepped by its pinned fragment). Run: `bash kit/ops/polaris doctor --selftest`.

## Invariants
- Express NEVER weakens a gate: audit, RULES, full suite, seal preconditions, `done`'s landed-record
  gate and the final `qa` all run exactly as in the long path. It only collapses SESSIONS, not checks.
- `land <ID>` without `--express` is byte-identical to today.
- Bash >= 3.2; no `case` inside `$(...)`; split `local` declarations (one var per line when one
  references another).

## Example
```
$ ops/polaris land --express T-042
✅ landed T-042 on integrate/2026-07-20 — feat(api): rename save button [T-042]
✅ suite green (42s)
✅ sealed sprint/6 · T-042 → done/
finish line: bash ops/polaris qa
```

## Changelog
- v1 2026-07-20: created for T-031 (CLI) · T-034 (conductor triage) · T-037 (MANUAL recipe)
