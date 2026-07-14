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

## Learned (Integrator appends ≤3 bullets per integration; Planner reads first)
- The write-guard binds every `feat/*` branch to a board task. Bootstrap work that is NOT a task must
  not use that prefix, or the guard blocks every write. (Cost: one rename, mid-refactor.)
