# SPRINT 8 — N chats, one repo          capacity: 27   dates: 2026-08-03–

Two chats on this repo today meet each other as errors: the second is told "another agent is
working", a stray ref literally named `feat` turns worktree-add failures into git folklore, a dirty
primary kills six commands without naming whose dirt it is, and one failed push strands a finished
task in `active/` with its lock held. This sprint makes the shared checkout a self-explaining place.
One new `workspace.sh` module (id_ok · wt_add · stray_feat_repair · park/unpark · int_on/int_off ·
wave_on), integration as a SINGLE lane serialized by a lease — a busy lane means a bounded wait,
then rc 3 with one `queued:` line, never a question — dirty trees parked into named stashes instead
of dying, handoff pushes that degrade to a caveat instead of stranding the board, claim gaining an
ID sanity check plus a disjointness gate against `active/`, re-lands that skip idempotently, and the
sprint-report writer committing its own file. Docs teach the second-chat decision table; four new
drills (park · claimguard · busyint · pushdegrade) prove all of it.
Release: 5.24.0 lands ONCE at the end of the two-sprint program (isolation, then routing + bg jobs)
per the approved plan — sprint 7's "release 5.24.0 at the close" is superseded, and the `ask`-rule
remainder (T-048/T-049/T-050, re-parked to backlog) rides a later release. No mid-program dogfood:
`pack.py --dogfood` installs the PUBLISHED release only, so both sprints run on installed 5.23.0
board mechanics (the installed-CLI-lags-source rule already covers this) and the dogfood folds into
the combined release step.
Contract: shared-checkout. plan: n-chats-one-repo → T-057..T-063 (27 pts).
W1 T-057 ∥ T-061 → W2 T-058 ∥ T-059 ∥ T-060 → W3 T-062 ∥ T-063.

## Burndown
| date | done pts | remaining |
|---|---|---|

# SPRINT 7 — The recorded yes          capacity: 28   dates: 2026-07-28–

`ops/RULES.tsv` has two kinds and both mean NEVER, so a rule whose message says "human decision,
stop-and-ask" is enforced as a wall. Field evidence (repo ARC): a human approved a schema change at
the plan gate, the ready gate never consulted RULES, the task reached `ready/`, triage said `full`,
and the Builder died on its first write with the decision already made. 5.24.0 adds a third kind
`ask` — the same denial as `path`, lifted only by a human's recorded approval on the task — plus
`polaris approve <ID> <scope> -m "why"`, an `approved:` task field, and the check that matters most:
the ready gate now refuses to promote a task that needs a yes it has not got. `path` and `content`
are untouched; converting a rule between `path` and `ask` is itself a human decision.
Contract: ask-approval. plan: ask-rule-kind → T-047..T-055 (28 pts).
W1 T-047 · T-051 · T-052 · T-053 · T-054 (5 disjoint lanes) → W2 T-048 ∥ T-049 (+T-055 drained)
→ W3 T-050 (drills). Release 5.24.0 at the close.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-28 | 8 (T-051, T-052, T-053, T-054, wave 1, sealed sprint/7 ba6d47d) | 20 (T-047 5pts HELD at the `risk: high` human gate · T-055 in review · T-048, T-049, T-050 behind T-047) · cycle p50 0.7h n=50 · kickbacks 0 · build avg 0.3h / integrate avg 1.5h · pipelined arrival-order landing, 4 lands, 0 squash conflicts · suite green on integrate (batch: full suite once, backgrounded ~13min + foreground log-poll) · uat 12/12 goldens green |
| 2026-07-28 | 10 (+T-055, wave 2, re-sealed sprint/7 tag ba6d47d→72415a5) | 18 · T-047 (5pts) audit clean + its whole `verify:` list green incl. the `newcmds` drill, unmerged and awaiting the human's literal approval · T-048, T-049, T-050 (13pts) all `depends_on` T-047, so `ready/` is EMPTY and no lane can start · cycle p50 0.7h n=51 · kickbacks 0 · build avg 0.3h / integrate avg 1.5h · suite green on integrate + uat 12/12 |
| 2026-08-03 | 16 (+T-047 5pts, +T-056 1pt, wave 3, re-sealed sprint/7 tag 72415a5→427c333) | 13 · T-048 + T-049 promoted to `ready/` (T-047 done unblocks both; ownership disjoint) · T-050 (3pts) still behind T-048+T-049 · scope grew +1pt mid-wave — T-056 filed to pin golden EOLs (28→29 pts) · cycle p50 0.7h n=53 · kickbacks 1 (2%), the sprint's first and mine: T-047 bounced so `ops/tests/api-kit.expected` got a sanctioned owner — procedural, not a defect · build avg 0.3h / integrate avg 1.5h→3.9h (T-047 sat 128.9h at the `risk: high` human gate; gate wait, not build effort, moved this) · suite green ×2 on integrate + build green + uat 12/12 after the EOL fix · Learned pruned 11→5 |

# SPRINT 6 — Many hands          capacity: 23   dates: 2026-07-21–

One file, eight modules: kit/ops/polaris (3,826 lines) becomes a <500-line entry (globals +
lib-loader + dispatch) sourcing kit/ops/lib/*.sh — core · ownership · builder · integrate ·
knowledge · observe · admin + selftest/ groups. ZERO behavior change: verbatim relocation, serial
output byte-identical, full suite the referee after every extraction; opt-in
`doctor --selftest --parallel <N>` sharding (serial default, CI serial). install.sh dir loops gain
`lib` in BOTH paths; INIT skeleton gains the ops/lib/ write-routing row; installer tripwires
untouched. Contracts: module-layout · selftest-sharding · install-parity.
plan: many-hands → T-039..T-045 (23 pts). kit/ops/polaris chain
T-039 → T-040 → T-042 → T-043 → T-044 → T-045; docs T-041 parallel from W2 (contract-pinned).
Release 5.16.0.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-21 | 5 (T-039, wave 1, sealed sprint/6) | 18 (T-040, T-041 ready · T-042..T-045 backlog) · cycle p50 0.5h n=39 · kickbacks 0 · build avg 0.3h / integrate avg 1.8h · suite green on integrate (batch: full suite once + pack) |
| 2026-07-21 | 12 (+T-040, T-041, wave 2, re-sealed sprint/6 tag 01d250d→13a92e1) | 11 (T-042 ready · T-043..T-045 backlog) · cycle p50 0.6h n=41 · kickbacks 0 · build avg 0.3h / integrate avg 1.7h · suite green on integrate (batch: full suite once + pack) · --parallel sharding live (run-verify used 2 shards) |
| 2026-07-21 | 15 (+T-042, wave 3, re-sealed sprint/6 tag 13a92e1→41607ed) | 8 (T-043 ready · T-044, T-045 backlog) · cycle p50 0.6h n=42 · kickbacks 0 · build avg 0.3h / integrate avg 1.7h · sharded gate (--parallel 3) RED on pre-existing drill coupling (T-040 seam, red on base, no kickback) → wave gated on SERIAL suite green (backgrounded ~12min, log-polled) + pack green |
| 2026-07-21 | 18 (+T-043, wave 4, re-sealed sprint/6 tag 41607ed→1ab1ddc) | 5 (T-044 ready · T-045 backlog) · T-046 (hermetic-drills fix, +3) in review · cycle p50 0.6h n=43 · kickbacks 0 · build avg 0.3h / integrate avg 1.7h · wave gated on SERIAL suite green (backgrounded ~12min, foreground log-poll) + pack green |
| 2026-07-21 | 21 (+T-046, wave 5, hermetic-drills fix, re-sealed sprint/6 tag 1ab1ddc→5c509a6) | 5 (T-044 building · T-045 backlog) · cycle p50 0.6h n=44 · kickbacks 0 · build avg 0.3h / integrate avg 1.7h · wave gated on SERIAL suite green + pack green · T-046 run-verify --parallel 3 green (sharding now hermetic — subsequent gates may shard) |
| 2026-07-21 | 24 (+T-044, wave 6, re-sealed sprint/6 tag 5c509a6→f1c96b5) | 2 (T-045 building — final chain link) · cycle p50 0.6h n=45 · kickbacks 0 · build avg 0.3h / integrate avg 1.6h · wave gated on --parallel 3 (3 shards green, hermetic post-T-046) + pack green |
| 2026-07-21 | 26 (+T-045, wave 7, re-sealed sprint/6 tag f1c96b5→df0df1d) — SPRINT COMPLETE | 0 · module split done: entry kit/ops/polaris 3,826→163 lines (<500) · grand total 4017 in band [3750,4120] · every module ≤1200 (max observe.sh 673) · cycle p50 0.6h n=46 · kickbacks 0 · build avg 0.3h / integrate avg 1.6h · wave gated on --parallel 3 green + pack green · qa green on main |

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
QA fix wave (2026-07-20, scout on the sprint-5 kit pre-release): T-038 (cli+manual, 3 pts) — brain
commands.md truncation · post-done staleness · land squash noise · commit type map test/docs ·
MANUAL 7-vs-6 count (brain v1.1 · clean-history v2.2).

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-07-20 | 15 (T-030, T-034..T-037, wave 1, sealed sprint/5) | 10 (T-031 ready · T-032, T-033 backlog) · cycle p50 0.5h n=34 · kickbacks 0 · build avg 0.2h / integrate avg 2.0h · suite green on integrate |
| 2026-07-20 | 20 (+T-031, wave 2, re-sealed sprint/5 tag 03d6919→82bfe37) | 5 (T-032 ready · T-033 backlog) · cycle p50 0.5h n=35 · kickbacks 0 · build avg 0.2h / integrate avg 1.9h · suite green on integrate |
| 2026-07-20 | 22 (+T-032, wave 3, re-sealed sprint/5 tag 82bfe37→b5cbcc7) | 3 (T-033 ready) · cycle p50 0.5h n=36 · kickbacks 0 · build avg 0.2h / integrate avg 1.9h · suite green on integrate · suite ~7min (drill growth) |
| 2026-07-20 | 25 (+T-033, wave 4, re-sealed sprint/5 tag b5cbcc7→30903df) — SPRINT COMPLETE | 0 · cycle p50 0.5h n=37 · kickbacks 0 · build avg 0.3h / integrate avg 1.9h · suite green on integrate |
| 2026-07-20 | 28 (+T-038, wave 5, QA fix wave, re-sealed sprint/5 tag 30903df→2bdc0fe) | 0 · cycle p50 0.5h n=38 · kickbacks 0 · build avg 0.3h / integrate avg 1.8h · suite green on integrate |

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
- GOLDENS NEED AN EOL PIN. `ops/tests/*.expected` and `*.cmd` fell through `.gitattributes`' `* text=auto`,
  so with `core.autocrlf=true` git materializes them CRLF the moment it rewrites them — and `check`
  byte-diffs LF stdout against the file, so all 480 lines "differ". A golden is therefore green only
  until git next touches its working copy: `api-kit` was green at wave start and red right after the
  land. Re-checking it out on bare `main` (`rm` + `git checkout --`) reproduced the red with ZERO task
  code, which is what proved it was the repo's flake and not the task's. BASE-CHECK EVERY uat RED
  before you believe it — role §3's flake clause paid for itself here; the golden's content was
  byte-exact, ordering included. T-056 pins both globs `eol=lf`; the `.cmd` half matters most, since
  `check` runs those through `bash -c`, so CRLF there breaks execution, not merely comparison.
- A TASK THAT CHANGES THE PUBLIC API SURFACE MUST OWN THE GOLDEN THAT RECORDS IT. T-047 added three
  contract-named fns to `ownership.sh` but did not own `ops/tests/api-kit.expected`, and its `verify:`
  ran only `check --only startup-budget` — so its narrow gate passed while the wave-level `uat:` failed
  on a file the Builder could not legally edit. Cost: a kickback, a `grant`, and a second land.
  Planner: hand any surface-changing task the recording golden up front. T-048 (`polaris approve`,
  owns `kit/ops/polaris` + `builder.sh`) adds fns too and will hit this again if carved as-is.
- A `risk: high` task at the ROOT of the dependency tree stalls the whole board, not just itself.
  T-047 was audited and verified for days while T-048/T-049/T-050 (13 of 28 pts) sat behind it and
  `ready/` was empty — it waited 128.9h at the gate, which alone moved integrate avg 1.5h→3.9h. The
  approval is cheap at the plan gate and expensive here, exactly as the `ask` mechanism this sprint
  ships argues for its own scopes. Get the yes before the wave, not at the merge.
- T-055 documents `ask`-guarded `solo` routing in PROTOCOL.md § LANES that T-049 has not shipped yet
  (deliberate — the Planner's carve says so). Until T-049 lands, that line and MANUAL's by-hand `ask`
  recipe describe behavior the CLI does not have. T-047 is merged now, so T-049 is unblocked and in
  `ready/` — ship it before this gap outlives the sprint.
- Contract-pinned phrases across parallel doc lanes held again (T-053/T-054/T-055 wrote the same
  strings into 9 files from 3 lanes, 0 conflicts) — but they are only as good as their line breaks.
  SOLO.md hard-wrapped the pinned one-liner mid-phrase ("lifted\nonly by a human"), so
  `grep -q 'lifted only by a human'` fails on that one file while the other eight pass. Planner: the
  contract's Pinned phrasing section must say ON ONE LINE, NEVER HARD-WRAPPED, and the grep belongs
  in `verify:` for EVERY file the task touches, not just one.
