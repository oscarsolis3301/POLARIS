# SPRINT 1 — Finish the self-hosting split          capacity: 10   dates: 2026-07-14–

The refactor landed: `kit/` is the product, `ops/` is a real POLARIS installation running this board,
and CI proves the two never leak into each other. But the kit still *describes* the old world — the
role files, MANUAL, PROMPTS, README and the install skill all say `ops/` where they now mean
`kit/ops/` — and a Builder who changes `install.sh` has no drill to run against it.

This sprint makes the kit tell the truth about itself, and gives it a test for the one path CI
exercises but a Builder cannot.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-15 | 8 (T-001, T-002) | 9 (T-003..T-006) |

## Learned (Integrator appends ≤3 bullets per integration; Planner reads first)
- The write-guard binds every `feat/*` branch to a board task. Bootstrap work that is NOT a task must
  not use that prefix, or the guard blocks every write. (Cost: one rename, mid-refactor.)
- A `case` statement inside `$(...)` command substitution is a HARD PARSE error on bash 3.2 (macOS
  `/bin/bash`): it reads the case pattern's `)` as the `$(`'s close. Keep `case` out of command
  substitution; only the 3-OS CI's `/bin/bash 3.2` leg catches it. (Cost: 4 CI round-trips to pinpoint.)
- Editing `kit/` files off-board collided with a task parked in `review/` that owned the same file
  (T-002 owned `kit/ops/polaris`). Off-board edits break the disjoint-ownership guarantee like a bad
  plan does — route product changes through tasks, or expect a merge conflict with parked work.
