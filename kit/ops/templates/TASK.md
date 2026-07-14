---
id: XXX-000
title:
type: feature            # feature | bug | chore | spike
epic:                    # optional grouping; epics are never claimed, only leaves
points:                  # 1,2,3,5 claimable · 8,13 MUST be split
value:                   # WSJF inputs, Fibonacci 1-13
time_criticality:
risk_opportunity:
wsjf:                    # (value + time_criticality + risk_opportunity) / points
risk: normal             # high = auth/payments/schema/prod-config → human approves before merge
status: backlog          # mirrors the folder; folder is the source of truth
owner: null              # set by `polaris claim`
branch: null             # set by `polaris claim`: feat/<ID>
files_owned:             # ONLY paths this task may create/edit — disjoint vs all ready+active.
  -                      # exact path · `dir/` prefix · glob like src/api/util_*.py (* crosses /)
context_files:           # read-only patterns to imitate (2–5 paths). Builders read nothing else.
  -
depends_on: []           # task is not ready until all of these are in done/
contract:                # ops/contracts/<name>.md — MUST exist before ready/
verify:                  # shell commands, repo root, each <~10s; `polaris verify` runs them,
  -                      # Integrator re-runs post-merge. No bare " #" inside a command — quote it.
map_delta:               # optional, one line per structural change; `polaris done` appends to MAP.md
---
## Acceptance criteria (binary — each becomes a test; put the runnable ones in verify:)
- [ ]
- [ ]

## Notes
<!-- Builders append one-line discoveries here; Integrator pastes failures here (path:line only). -->
