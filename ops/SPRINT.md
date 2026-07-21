# SPRINT 5 — The fast lane          capacity: 25   dates: 2026-07-20–

Requests take hours; telemetry says where: cold-start context re-derivation (~1.6M tokens/day),
full ceremony for 2-point asks, integration waiting on the slowest lane, repeated full suites.
5.15.0 ships the fixes with every gate intact: `brain [--refresh]` (generated .polaris/brain/
knowledge base, ≤4-hop, seal-refreshed, doctor-warned), express lane (`express: auto` +
`land --express`), pipelined integration + foreground/recovery hardening (docs),
`--selftest --only` + slow-suite hint, `status --brief` + metrics summary.
Contracts: brain · express-lane · verification-tiering · status-brief · pipelined-integration.
plan: fast-lane → T-030..T-037 (25 pts). kit/ops/polaris chain T-030 → T-031 → T-032 → T-033;
doc tasks T-034..T-037 parallel (contract-pinned wording). Release 5.15.0.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-20 | 15 (T-030, T-034..T-037, wave 1, sealed sprint/5) | 10 (T-031 ready · T-032, T-033 backlog) · cycle p50 0.5h n=34 · kickbacks 0 · build avg 0.2h / integrate avg 2.0h · suite green on integrate |
| 2026-07-20 | 20 (+T-031, wave 2, re-sealed sprint/5 tag 03d6919→82bfe37) | 5 (T-032 ready · T-033 backlog) · cycle p50 0.5h n=35 · kickbacks 0 · build avg 0.2h / integrate avg 1.9h · suite green on integrate |
| 2026-07-20 | 22 (+T-032, wave 3, re-sealed sprint/5 tag 82bfe37→b5cbcc7) | 3 (T-033 ready) · cycle p50 0.5h n=36 · kickbacks 0 · build avg 0.2h / integrate avg 1.9h · suite green on integrate · suite ~7min (drill growth) |
| 2026-07-20 | 25 (+T-033, wave 4, re-sealed sprint/5 tag b5cbcc7→30903df) — SPRINT COMPLETE | 0 · cycle p50 0.5h n=37 · kickbacks 0 · build avg 0.3h / integrate avg 1.9h · suite green on integrate |

# SPRINT 4 — One PR, clean graph          capacity: 25   dates: 2026-07-20–

Bitbucket-grade publishing: board chores leave base for refs/heads/polaris/board (quiet board),
`publish: direct|pr` ships one host PR per wave with a `seal --sync` handshake, `polaris report`
renders docs/sprints/sprint-<n>.md and seal commits it on each wave, sweep/doctor learn remote
hygiene. Contracts: quiet-board · publish-modes · sprint-report.
plan: one-pr-clean-graph → T-020..T-026 (25 pts). kit/ops/polaris chain
T-020 → T-021 → T-022 → T-023 → T-024; doc tasks T-025, T-026 parallel (contract-sourced).
Release 5.14.0.
QA fix wave (2026-07-20, scout on the landed 5.14 kit): T-027 (cli, 3 pts) + T-028 (docs, 2 pts),
parallel, contract-pinned wording (sprint-report v1.1 · clean-history v2.1 · publish-modes v1.1).
Patch wave 5.14.1 (2026-07-20, testbed verify of published 5.14.0): T-029 (cli, 2 pts) —
resolve_sprint_ids expands caller's `n` on its `local` line, silently skipping Rule-2 tag
attribution in `report --all`; sealed tasks fell to `(unsealed)` (sprint-report v1.2).

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-20 | 10 (T-020, T-025, T-026, wave 1, sealed sprint/4) | 15 (T-021 ready · T-022..T-024 backlog) · cycle p50 0.5h n=22 · kickbacks 0 · build avg 0.2h / integrate avg 2.9h · qa green on main |
| 2026-07-20 | 15 (+T-021, wave 2, re-sealed sprint/4 tag 69e3628→c239aa3) | 10 (T-022 ready · T-023, T-024 backlog) · cycle p50 0.5h n=23 · kickbacks 0 · build avg 0.2h / integrate avg 2.8h · qa green on main |
| 2026-07-20 | 20 (+T-022, wave 3, re-sealed sprint/4 tag c239aa3→be299c9) | 5 (T-023 ready · T-024 backlog) · cycle p50 0.5h n=24 · kickbacks 0 · build avg 0.2h / integrate avg 2.7h · qa green on main |
| 2026-07-20 | 23 (+T-023, wave 4, re-sealed sprint/4 tag be299c9→1cdfdc2) | 2 (T-024 ready) · cycle p50 0.5h n=25 · kickbacks 0 · build avg 0.2h / integrate avg 2.6h · qa green on main · Learned pruned 9→5 |
| 2026-07-20 | 25 (+T-024, wave 5, re-sealed sprint/4 tag 1cdfdc2→9426ce6) — SPRINT COMPLETE | 0 · cycle p50 0.5h n=26 · kickbacks 0 · build avg 0.2h / integrate avg 2.5h · qa green on main |
| 2026-07-20 | 30 (+T-027, T-028, wave 6, QA fix wave, re-sealed sprint/4 tag 9426ce6→7f7a9d6) | 0 · cycle p50 0.5h n=28 · kickbacks 0 · build avg 0.2h / integrate avg 2.3h · qa green on main |
| 2026-07-20 | 32 (+T-029, wave 7, patch wave, re-sealed sprint/4 tag 7f7a9d6→47ca6ea) | 0 · cycle p50 0.5h n=29 · kickbacks 0 · build avg 0.2h / integrate avg 2.3h · qa green on main |

# SPRINT 3 — Hands-free core          capacity: 13   dates: 2026-07-18–

The loop runs hands-off once a human starts it: an autonomy dial (plan_gate · builder_questions ·
evolve_apply, composed by autonomy:), a bounded backlog drain (drain: backlog + drain_slices), a
human-authored ops/ROADMAP.md as the standing objective, and notify severity + gate pings. Every
knob unset = today's behavior; every hard gate stays. Contract: ops/contracts/hands-free-knobs.md.
plan: hands-free-core → T-012..T-016 (13 pts). Sprint-2 carryover rides the same run:
kit/ops/polaris chain T-004 → T-013 → T-005 → T-006. Release 5.13.0.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-18 | 12 (T-004, T-012, T-014..T-016, wave 1, sealed sprint/3) | 8 (T-013 ready · T-005, T-006 backlog) · cycle p50 0.5h n=13 · kickbacks 0 · build avg 0.1h / integrate avg 4.8h |
| 2026-07-18 | 15 (+T-013, wave 2, folded via MANUAL fallback, no tag) | 8 (T-017 ready · T-005, T-006 backlog) · cycle p50 0.5h n=14 · kickbacks 0 · build avg 0.1h / integrate avg 4.5h |
| 2026-07-18 | 18 (+T-017, wave 3, folded via MANUAL fallback, no tag) | 5 (T-005 ready · T-006 backlog) · cycle p50 0.5h n=15 · kickbacks 0 · build avg 0.1h / integrate avg 4.2h |
| 2026-07-18 | 21 (+T-005, wave 4, folded via MANUAL fallback, no tag) | 2 (T-006 ready) · cycle p50 0.4h n=16 · kickbacks 0 · build avg 0.1h / integrate avg 3.9h |
| 2026-07-18 | 23 (+T-006, wave 5, folded via MANUAL fallback, no tag) — SPRINT COMPLETE | 0 · cycle p50 0.5h n=17 · kickbacks 0 · build avg 0.1h / integrate avg 3.7h · qa green on main |
| 2026-07-18 | 25 (+T-018, T-019, wave 6, fix wave, folded via MANUAL fallback, no tag) | 0 · cycle p50 0.4h n=19 · kickbacks 0 · build avg 0.1h / integrate avg 3.3h · drift: LEARNED 9>5 (EVOLVE to prune) |

# SPRINT 2 — Clean history          capacity: 13   dates: 2026-07-18–

Every task one rich commit, every sprint one sealed merge. The model shipped in kit source
(T-007..T-010, CHANGELOG 5.12.0-unreleased): `land` squashes a feat branch into ONE generated
commit, `seal` closes a sprint as ONE tagged merge, `history`/`rollback` read and revert it.
Capacity 13 = points landed last wave (13 pts, 0 kickbacks). Queue: the T-004→T-005→T-006 chain
on kit/ops/polaris (fm_list · grant · staleness), unblocked now T-007's rework of that file landed.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-18 | 1 (T-011, fix wave) | 7 (T-004..T-006) · cycle p50 0.5h · kickbacks 0 |

# SPRINT 1 — Finish the self-hosting split          capacity: 10   dates: 2026-07-14–2026-07-18

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
| 2026-07-18 | 13 (T-003, T-007..T-010) | 7 (T-004..T-006) · cycle p50 0.5h · kickbacks 0 |

## Learned (Integrator appends ≤3 bullets per integration; Planner reads first)
- A `case` statement inside `$(...)` command substitution is a HARD PARSE error on bash 3.2 (macOS
  `/bin/bash`): it reads the case pattern's `)` as the `$(`'s close. Keep `case` out of command
  substitution; only the 3-OS CI's `/bin/bash 3.2` leg catches it. (Cost: 4 CI round-trips to pinpoint.)
- Since T-006, doctor's stale-zip warning fires on every post-fold run in THIS repo (the zip embeds
  its pack commit; any merge moves HEAD past it). Warning only — doctor/qa stay green; the rebuild
  belongs to the release ritual, not integration. Don't read it as a red.
- 5.14 lag: T-020 quiet-board, T-022 pr-mode and T-023 sprint reports live in KIT SOURCE only until
  the 5.14 dogfood — the installed 5.13 board still writes chore(board) on base, stays
  publish: direct, and seal does NOT auto-commit docs(sprint-N). Their drills ride the kit selftest,
  so `test:` already exercises them pre-dogfood.
- backlog→ready promotion has no CLI command in 5.13 — done by hand (git mv + status frontmatter +
  chore(board) commit), per MANUAL's board-mutation pattern.
- bash expands EVERY word of a `local` line BEFORE assigning, so `local n="$1" tag=".../$n"` reads
  the CALLER's `n` (T-029: `report --all` sent sealed tasks to `(unsealed)`; two callers masked it by
  holding the same `n`). Split `local` decls, and drills must cover the fallback path (Rule-1-blind),
  not just the fixture's happy path — testbed verify of the PUBLISHED release is what caught it.
- Pipelined arrival-order landing (sprint 5 w1–2, 6 tasks): 0 kickbacks, 0 squash conflicts,
  integrate avg 2.3h→1.9h. The disjoint carve holds under batch mode with per-arrival lands;
  spawn the integrator at first handoff, run the suite once per wave. Batch-mode data point (w3):
  the full suite is ~7 min on this machine (was ~3) — drill count grows with every CLI task;
  T-033's `--only` subset is the relief valve, batch stays the right mode.
- Rescue lane (sprint 5 w4): a stalled lane's draft was CORRECT — timeout mechanics were the
  failure, not the work (harness caps kill long suites mid-run; background notifications don't
  reliably reach subagents). Kickoffs MUST carry explicit timeout numbers; long commands log to a
  file and the session polls that file for the PASS/FAIL line instead of waiting on notifications.
