# CONTRACT: pipelined-integration            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the conductor's pipelining + stall-hardening wording (CONDUCTOR.md — T-034) from the
integrator's arrival-order recipe (INTEGRATOR.md — T-035): two parallel doc tasks, one pinned
vocabulary, zero merge conflicts. Docs only — no CLI change rides this contract.

## Pinned semantics (both files must describe the SAME protocol)
- **Integrator starts at FIRST handoff, not last.** The conductor spawns the integrator subagent as
  soon as the first lane reports its handoff; the integrator audits and lands tasks
  `as they arrive in review/, in dependency order` (pinned fragment, verbatim in BOTH files) —
  a task whose `depends_on` has not yet arrived waits; everything else lands on arrival.
- `handoff`'s existing all-review notice (`Integrate now`) stays the LAST-LANE signal — pipelining
  changes when integration STARTS, never what seal requires before it runs.
- The wave's suite/seal discipline is unchanged: full suite once per wave (batch) or per land
  (paranoid), then one seal — arrival-order landing reorders work, it drops no check.

## Pinned foreground rule (T-034 — EVERY subagent kickoff template in CONDUCTOR.md gains it)
Verbatim sentence, in each template (planner, builder, integrator, QA scout, EVOLVE):
`Run every command in the FOREGROUND; never wait on background notifications.`
(Rationale, for the doc's own prose: two sprint-4 lanes stalled forever waiting on a
background-notification that never fires for subagents; verify/qa/suite runs get a generous timeout.)

## Pinned recovery paragraph (T-034 — one paragraph in CONDUCTOR.md's snag section)
A lane that goes silent past `stale_hours` is a DEAD lane, not a slow one: first try resuming the
SAME subagent (its context is intact); no response → re-anchor from `bash ops/polaris status` +
`git status` in its worktree, then release-and-respawn per the existing snag path. Pinned fragment
for greps: `resume the same agent` and `re-anchor`.

## Executable check
Doc-only seam — the check is the pinned fragments, grepped by each task's `verify:`:
`as they arrive in review/, in dependency order` (CONDUCTOR.md + INTEGRATOR.md) ·
`in the FOREGROUND` (CONDUCTOR.md, ≥5 occurrences — one per template) ·
`resume the same agent` (CONDUCTOR.md).

## Invariants
- No gate weakens: audit-before-merge, risk:high human approval, green-before-review, seal
  preconditions all read exactly as today.
- Wording added by one task never edits a line the other task owns: T-034 touches ONLY
  kit/ops/roles/CONDUCTOR.md; T-035 touches ONLY its four role files.

## Example
Wave of 3 lanes: lane B hands off first → integrator spawns, audits+lands B; lane A arrives, lands;
lane C (depends_on A) arrives, lands after A; all-review notice fires with C → suite once → seal.
Wall-clock: integration overlaps the slowest lane instead of following it.

## Changelog
- v1 2026-07-20: created for T-034 (CONDUCTOR.md) · T-035 (INTEGRATOR.md and role files)
