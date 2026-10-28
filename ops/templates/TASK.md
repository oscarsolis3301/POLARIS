---
id: XXX-000
title:
type: feature            # feature | bug | chore | spike
scope:                   # optional; conventional-commit scope for type(scope): title — Planner sets it
screen:                  # optional; the human name of the surface this task changes, e.g.
                         # Homepage / Universal Search Bar — becomes the shot folder
epic:                    # optional grouping; epics are never claimed, only leaves
# plan:                  # optional; conductor-run slug for backlog drain, e.g. hands-free-core —
                          # Planner sets it on every task of a run; see contract hands-free-knobs
                          # — required (not optional) on every task authored for a specific request,
                          # including backlog/, so a run can tell its own work from a leftover
points:                  # 1,2,3,5 claimable · 8,13 MUST be split
value:                   # WSJF inputs, Fibonacci 1-13
time_criticality:
risk_opportunity:
wsjf:                    # (value + time_criticality + risk_opportunity) / points
risk: normal             # high = auth/payments/schema/prod-config → human approves before merge
test_depth:              # optional; raise-only — the only value that does anything is `full`,
                         # which forces the wave gate to run the whole suite for this task even
                         # when depth_for would otherwise pick none/look/scoped. Any other value is
                         # ignored. `test_depth: full` is the way to force everything, including the
                         # live uat tier a scoped run defers. See ops/contracts/test-depth.md
model:                   # optional; strong|mid|cheap tier word, or a literal model name — overrides
                         # the tier `polaris route` derives for this task. ops/contracts/model-routing.md
status: backlog          # mirrors the folder; folder is the source of truth
owner: null              # set by `polaris claim`
branch: null             # set by `polaris claim`: feat/<ID>
files_owned:             # ONLY paths this task may create/edit — disjoint vs all ready+active.
  -                      # exact path · `dir/` prefix · glob like src/api/util_*.py (* crosses /)
needs:                   # optional list: schema | dependency | delete, the STOP-AND-ASK items this task
                         # will do; `approve --plan` covers each the approved plan named (need:<v>)
approved:                # optional; human-granted exceptions to `ask` rules. `polaris approve`
                         # writes these — a Planner never hand-edits them. Empty = no approvals.
  -                      # <scope> — <who>, <date>: <why>
context_files:           # read-only patterns to imitate (2–5 paths). Builders read nothing else.
  -
depends_on: []           # task is not ready until all of these are in done/
contract:                # ops/contracts/<name>.md — MUST exist before ready/
verify:                  # shell commands, repo root, each <~10s; `polaris verify` runs them,
  -                      # Integrator re-runs post-merge. No bare " #" inside a command — quote it.
map_delta:               # optional, one line per structural change; `polaris done` appends to MAP.md
surface:                 # optional; rows `polaris done` appends to ops/SURFACES.tsv (the ONLY writer)
  -                      # <surface-glob> tests: <tests-glob> [cmd: <complete command | ->] [note: <plain English>]
---
## Why
<!-- junior-dev-grade: plain enough a junior dev could land this unsupervised — what changes and why. Becomes the commit body verbatim at land. -->

## Acceptance criteria (binary — each becomes a test; put the runnable ones in verify:)
- [ ]
- [ ]

## Notes
<!-- Builders append one-line discoveries here; Integrator pastes failures here (path:line only). -->
