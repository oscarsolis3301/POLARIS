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
- The write-guard binds every `feat/*` branch to a board task. Bootstrap work that is NOT a task must
  not use that prefix, or the guard blocks every write. (Cost: one rename, mid-refactor.)
- A `case` statement inside `$(...)` command substitution is a HARD PARSE error on bash 3.2 (macOS
  `/bin/bash`): it reads the case pattern's `)` as the `$(`'s close. Keep `case` out of command
  substitution; only the 3-OS CI's `/bin/bash 3.2` leg catches it. (Cost: 4 CI round-trips to pinpoint.)
- Editing `kit/` files off-board collided with a task parked in `review/` that owned the same file
  (T-002 owned `kit/ops/polaris`). Off-board edits break the disjoint-ownership guarantee like a bad
  plan does — route product changes through tasks, or expect a merge conflict with parked work.
- Kit source now has land/seal/history/rollback, but the INSTALLED ops/polaris is 5.11 until a
  release + `pack.py --dogfood` — the next integration on THIS board is still classic --no-ff;
  do not follow the new kit/ops/roles/INTEGRATOR.md recipe here before the dogfood lands.
- integrate(handoff→done) avg 8.4h vs build avg 0.1h — review parking dominates cycle time; run the
  Integrator as soon as a wave finishes handing off.
- First land/seal run (5 tasks, paranoid): green per land, 0 conflicts. But `seal` tags sprint/<n>
  ONCE and `done` needs the landed [ID] commit reachable in base — a mid-sprint wave 2 can neither
  seal (tag exists) nor done. Sprint 3's next wave is blocked on a human call: bump the SPRINT
  header number per wave, or teach seal multi-wave (kit change).
- Installed ops/polaris runs pre-T-004 fm_list until 5.13.0 dogfoods: inline `[a, b]` lists on the
  board parse as ONE literal item everywhere except depends_on (dep_ids special-cases it). Keep
  board frontmatter lists block-shaped until the dogfood lands.
- Wave 2 correction: only `seal` is wave-blocked (tag exists), NOT `done` — MANUAL's fold recipe
  (plain `--no-ff` merge into base, no tag) puts the [ID] commit in base and `done` passes.
  Wave 3 (T-017) needs the same fallback; T-017's fixed seal owns tag semantics from 5.13.0.
