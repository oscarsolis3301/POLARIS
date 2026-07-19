# ROADMAP
Human-authored, ordered list of outcomes for this product — not a task list. Agents read it to
pick the next objective when a kickoff carries no objective and `ready/` is empty; they never
write to it or check off a line. Edit it yourself, anytime, in whatever order matters to you.

Seeded 2026-07-18 by the repo owner from the vetted hands-free analysis (deferred proposals
P4–P13; details in the analysis plan and CHANGELOG 5.13.0 context).

## Outcomes (top to bottom = priority)
- [ ] `polaris next [--exec]` — the board names its own next move so a thin outer loop can drive it (exec runs only idempotent re-checks, never promote/merge)
- [ ] Telemetry-driven conductor — `metrics --json`; conductor acts on stalls, age-floored orphan cleanup, chronic-bounce (kb≥2) escalation at wave boundaries
- [ ] `polaris promote [ID]` — mechanical backlog→ready for Planner-pre-authorized (`promotable: true`) tasks whose deps just cleared
- [ ] Durable self-heal budget — wave ledger in telemetry + tunable `fix_waves` / `builder_retries` / `heal_budget` knobs (defaults = today's caps)
- [ ] Implement `flaky:` — bounded qa retry gated strictly on the human-curated allowlist; unlisted retry-passers stay red
- [ ] `polaris drain-review [--land]` — batch the mechanical integrate seam; `--land` = run the Integrator recipe non-interactively, full suite on the combined tree
- [ ] Per-run intelligence — persist run summaries (waves, parks, degradation) via the CLI; metrics recommends `stale_hours`/`capacity` from evidence
- [ ] Deep backlog grooming — epic decomposition + top-K IDEAS refinement into contract-backed backlog; provisional contracts re-validated at promotion
- [ ] Scheduled re-entry — `polaris drain` entrypoint + cron recipe with the strict unattended contract (park-and-escalate at every human gate, fail-closed blocked revival)
