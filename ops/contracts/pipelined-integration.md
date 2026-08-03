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

## v2 — one integration lane, many sessions (2026-08-03, plan n-chats-one-repo)

Mechanics in `ops/contracts/shared-checkout.md` (the authority); this section pins what the
ROLE DOCS say about them (T-063) and what the CLI guarantees underneath (T-058):
- Integration is a SINGLE shared lane serialized by the lease. Because `files_owned` are
  disjoint, ANY integrator may land ANY review task — the lane holder lands everything in
  review/, in dependency order (v1's arrival-order recipe unchanged).
- A second integrator is NOT an error: it waits (bounded, with progress notes), steals only a
  STALE lease, and past the wait exits **rc 3** with one `queued: ` line. Pinned doc sentence
  (ONE LINE, never hard-wrapped): `integration lane busy → wait; rc 3 with a queued: line means
  report queued and retry at the next wave boundary` — CONDUCTOR.md polls at wave boundaries;
  a subagent integrator reports queued and ends its turn instead of spinning.
- Idempotent re-lands make overlap harmless: an already-landed task skips (`already landed —
  skipped`, rc 0); a nothing-new seal is rc 0. Two integrators can never die on each other's
  completed work.
- An open integrate/<date> left by a crashed or paused session is ADOPTED by the next lane
  holder (`wave_on`), never a reason to stop and ask.
- Per-run integrate branches were CONSIDERED and REJECTED: $BASE is checked out in the primary
  (git forbids a second checkout), so integrators cannot truly parallelize; a queue on one lane
  is simpler than N branches racing to merge into one checkout.

## Changelog
- v2 2026-08-03: single lane + lease semantics for docs (T-063) over the T-058 CLI; rc 3
  queued line pinned; idempotent re-lands + wave adoption pinned.
- v1 2026-07-20: created for T-034 (CONDUCTOR.md) · T-035 (INTEGRATOR.md and role files)
