# SPRINT 10 — Autonomy by default (6.0.0)          capacity: 36   dates: 2026-08-03–

`update` refreshes kit code and never rewrites CONVENTIONS.md — correct, and exactly why every
capability gated on a NEW key ships dormant: the 5.13 autonomy knobs sat OFF here for two sprints
and are still off in polaris-testbed (19 keys missing on byte-identical kit code), doctor printed
the composition ONLY when a knob was already set, and cfg() cannot tell missing from empty. 6.0.0
flips the DEFAULTS IN KIT CODE (hands-free-knobs v2): unset composes auto / default-safe /
auto-reversible, `autonomy: standard` is the one-line revert, doctor always prints the effective
plan — plus the discovery loop (KEYS.tsv registry → doctor's one-line drift report → `polaris
adopt` commented stubs), the settings.json hook-merge repair (path identity, field updates —
testbed is parked at guard timeout 10 vs the kit's 20, on the fail-open margin), and the parked
`ask`-rule remainder (T-048/T-049/T-050) rides along at last. Hard gates move NOWHERE: risk:high
approval, STOP-AND-ASK, RULES.tsv, ready gate, contract-before-code, green-before-review; drain
is never composed. BREAKING major: T-081 carries the changelog + the human-only ritual (VERSION ·
tag · dogfood · testbed E2E). Serial chains, not parallel splits, on every hotspot:
observe.sh T-075→T-076→T-049 · kit/ops/polaris T-048→T-077 · install.sh T-074→T-078. api-kit is
the ONLY moving shared golden — ONE owner per wave (T-048 → T-077 → T-049 → T-080), cross-lane fn
names pinned in key-registry.md § 5, everything else surface-frozen (the sprint-9 prescription,
0 kickbacks across 3 waves). New goldens keys-drift + adopt-stub are hermetic fixtures, no
version numbers. Board mechanics run installed 5.24.0; prove new behavior via `bash
kit/ops/polaris …` (27-label tell). plan: autonomy-by-default → T-074..T-081 + T-048/T-049/T-050
(36 pts). W1 ready: T-074 · T-075 · T-048 (risk: high — get the merge yes early, a high-risk
root stalled 13 pts for 128.9h once) · T-079.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-08-03 | 12 (T-074 2pts, T-075 3pts, T-079 2pts, T-048 5pts, wave 1, sealed sprint/10 2145137) | 24 · T-076 + T-077 + T-078 promoted to `ready/` (deps T-074/T-075/T-048 all done; ownership mutually disjoint — observe.sh+keys-drift pair · admin+entry+adopt-stub pair+api-kit golden · install.sh+selftest-install.sh), so wave 2 runs THREE parallel lanes · T-049/T-050/T-080/T-081 correctly held in `backlog/` (deps unmet) · cycle p50 0.7h n=74 · kickbacks 0 this wave (2 lifetime, 3%) · build avg 0.3h / integrate avg 3.1h · gate: full SERIAL suite green on integrate (backgrounded, SELFTEST-PASS across all 27 labels incl. `doctor knob composition` · `grant append+refusals` · `rules` · `route`) · T-048 merged on the human's relayed in-conversation approval (risk: high, named alongside T-081; no other high task covered) · § 5 PINNED-PAIR DEADLOCK surfaced and resolved mid-wave: T-048, sole `api-kit.expected` owner, could not hand off while T-074/T-079's already-landed surface had redded the golden — integrator recorded the landed surface on integrate/2026-08-03 (derived from live output, cross-checked byte-identical against the owner's copy stripped of its two unlanded fns, diff reviewed line-by-line; commit 7afb5c2), post-T-048 the golden gained exactly `cmd_approve` + `fm_append_item` · `drill_live_board` byte-identical to pre-wave main at every land (the install-never-touches-board proof stands) · drift: MAP 21 delta lines to fold (EVOLVE target) · Learned: 2 new bullets + 1 clause folded into the derived-surface bullet |

# SPRINT 9 — Route and background          capacity: 23   dates: 2026-08-03–

Model choice is manual prose and long commands die at the harness's cap: PROTOCOL's routing rule is
advisory (no code reads it, no `model:` field exists, conductor spawns and fleet panes pass
nothing), and the suite — MEASURED 805s serial, 169-330s sharded, `qa` 1225s — times out against
the 600s foreground ceiling, returns NOTHING, and gets re-run; two subagents did exactly that last
sprint. This sprint makes both mechanical. F1: `tier_for(points,risk)` + `model_for_tier` in
core.sh, `polaris route` (line 1 = bare tier word; `   model:` note only when a CONVENTIONS knob
maps it), knobs model_strong/mid/cheap (THIS repo pins fable/opus/sonnet — owner decision
2026-08-02, never haiku), CONDUCTOR route-per-spawn, fleet `--model` injection incl. the wt.exe
pane tokens (max tier over ready — panes claim racily), pack `· tier`, TASK.md `model:` override.
F2: `kit/ops/lib/bg.sh` — dir-per-job `$PRIMARY/.polaris/bg/<name>/`, rc-file-first verdicts then
`kill -0` (pid semantics from birth — the T-064 lesson), run/status/tail/wait (`--max` 300 default:
chunked under the cap), `.prev` rotation, `sweep --fix` >24h, `finish` pends on running jobs;
readonly-allow arms `route` + `bg status/tail/wait`; PROTOCOL § LONG COMMANDS finally writes the
recipe and the five duplicated CONDUCTOR blockquotes collapse to one canonical pointer. api-kit is
the ONLY moving shared golden: ONE owner per wave (T-065 → T-070 → T-071), the wave-1 heading swap
cross-pinned in the contract, every other wave-1 lane surface-frozen (Learned-log rule, 3 prior
instances). New goldens route-tier + bg-lifecycle are hermetic by construction (fixture repos, flag
forms — the T-062 pattern). Release: 5.24.0 lands ONCE at program end, AFTER this sprint —
VERSION + CHANGELOG + tag + published release + dogfood as one ritual (cli-help goldens regenerate
at dogfood); the plan's R-8 release task is deliberately NOT on this board, same reason sprint 8
dropped I-8: `pack.py --dogfood` installs the PUBLISHED release only, and a landed VERSION bump
without its tag reds the one-version-everywhere gate. Both waves still run installed 5.23.0 board
mechanics (route/bg/park exist in kit only — prove new behavior via `bash kit/ops/polaris …`).
Contracts: model-routing · bg-jobs (+ module-layout v4). plan: routing-and-bg → T-065..T-072
(22 pts; scope grew +1 mid-sprint: T-072 filed from T-067's gate-integrity finding — `check
--update/--scaffold` were hook-auto-approved inside compounds, bg-jobs v1.1; T-071 groomed to also
own kit/ops/PROTOCOL.md for the two § THE TOOL rows, explicit depends_on T-066 per the
golden-coupling rule; +T-073 filed from T-071's builder — finish's bg guard pended forever on
rc-less `.prev` archives, bg-jobs v1.2).
W1 T-065 ∥ T-066 ∥ T-067 ∥ T-068 ∥ T-069 (5 disjoint lanes) → W2 T-070 → W3 T-071 ∥ T-072 ∥ T-073.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-08-03 | 13 (T-065 5pts, T-066 2pts, T-067 2pts, T-068 2pts, T-069 2pts, wave 1, sealed sprint/9 dff3657) | 9 · T-070 + T-072 promoted to `ready/` (deps T-065/T-067 now done; ownership disjoint — bg+entry+observe+the api-kit golden vs. the readonly-allow hook + its two goldens), so W2 runs TWO lanes where the plan wrote one: T-072's only dep was T-067, so pulling it forward from W3 is legal · T-071 (3pts) correctly held behind T-070 — it shares `ops/tests/api-kit.expected` · T-048 + T-049 (sprint-7 leftovers, deps met since T-047) also correctly HELD in `backlog/`, and this one is not obvious: their deps ARE satisfied, but they overlap T-070 on `kit/ops/polaris` and `kit/ops/lib/observe.sh` respectively, so promoting on deps alone would have broken W2's disjointness · cycle p50 0.6h n=66 · kickbacks 0 this wave (2 total, 3%) · build avg 0.3h / integrate avg 3.5h · gate: suite green sharded 351s (3 shards, 25 drills) + build green + uat 12/12 · the api-kit one-owner-per-wave prescription earned its first proof — T-065's golden and T-066's byte-pinned heading swap proved together at the wave gate with five lanes on that surface and zero kickbacks · one stray commit caught pre-seal: the Planner's `docs(contract): bg-jobs v1.1 (T-072)` committed onto the checked-out integrate branch and rode the seal into main — correct destination, logged as an entanglement hazard · doctor's zip-STALE line is known HEAD-comparison noise, rebuilt by `build:` · Learned now 6 bullets (2 of 3 findings folded into existing bullets rather than appended; EVOLVE may prune) |
| 2026-08-03 | 19 (+T-070 5pts, +T-072 1pt, wave 2, re-sealed sprint/9 dff3657→8d16b08) | 3 · T-071 (3pts) promoted to `ready/` — its last dep (T-070) landed here, and with `ready/`+`active/` empty the disjointness test is trivial; note for whoever re-grooms T-050 that it shares `kit/ops/lib/selftest/policy.sh` with T-071, harmless only because T-050's own deps (T-048/T-049) are unmet and the ready gate compares against `ready/`+`active/` alone · cycle p50 0.6h n=68 · kickbacks 0 · build avg 0.3h / integrate avg 3.4h · gate: suite green sharded 359s (3 shards) + build green + uat 12/12, green on the FIRST pass — this was the run proving T-072's hardened `check --update/--scaffold` hook and T-070's regenerated `api-kit` golden agree · zero stray commits on the integrate branch this wave, checked deliberately per W1's lesson · NO new Learned bullets: wave 2 reproduced wave 1's pattern exactly and the one-owner-per-wave golden rule held a second time (T-070 sole owner of `api-kit.expected` across a 2-lane wave), which is confirmation, not a new lesson |
| 2026-08-03 | 23 (+T-071 3pts, +T-073 1pt, wave 3, re-sealed sprint/9 8d16b08→fe0aac4) — SPRINT COMPLETE | 0 — all 9 tasks of plan `routing-and-bg` landed; scope grew +1 mid-sprint (22→23) with T-073, the 1-pt rider filed from T-071's finding · cycle p50 0.6h n=70 · kickbacks 0 across the whole sprint (2 lifetime, 3%) · build avg 0.3h / integrate avg 3.3h · FINAL GATE: kit-anchored sharded suite green 378s across all 27 labels — `route` and `bg` running for the first time — + build green + uat 14/14 including both new hermetic goldens `route-tier` and `bg-lifecycle` · a SECOND stray base-bound commit was captured and logged (`docs(contract): bg-jobs v1.2 (T-073)`, same mechanism as wave 1's v1.1), caught by the pre-seal log read both times · Learned: 1 new bullet (the 1-pt-rider pattern), 3 clauses folded into existing bullets (the 27-vs-21 kit-vs-installed label diff, the recurrence plus my own tag force-push near-miss, one-owner-per-wave's three-wave confirmation), and the fully-shipped EOL bullet compacted — log stands at 7 bullets, EVOLVE to prune · RELEASE NEXT: 5.24.0 is unbuilt — `ops/` still runs installed 5.23.0 while `kit/` carries 5.24.0-unreleased behavior (`route`/`bg` exist in kit only), so `doctor` reports the zip STALE until `pack.py` runs as part of the release ritual |

# SPRINT 8 — N chats, one repo          capacity: 29   dates: 2026-08-03–

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
Contract: shared-checkout. plan: n-chats-one-repo → T-057..T-064 (29 pts).
W1 T-057 ∥ T-061 → W2 T-058 ∥ T-059 ∥ T-060 → W3 T-062 ∥ T-063 ∥ T-064.
Scope grew +2 pts mid-sprint (27→29): T-064 filed from the integrator's audit of T-058 — the board
mutex was removable by ANY process exit (unguarded mutex_off + never-disarmed on_die trap, armed
lease-long since T-057); pid-guard it like the lease (shared-checkout v1.1).

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-08-03 | 7 (T-057 5pts, T-061 2pts, wave 1, sealed sprint/8 2f14623) | 22 · T-058 + T-059 + T-060 promoted to `ready/` (T-057 done unblocks all three; ownership disjoint: integrate+history · builder+board+remote · observe+admin+policy) · T-062 correctly held in `backlog/` — it overlaps all three on the selftest shards · cycle p50 0.7h n=55 · kickbacks 0 · suite green sharded + build green + uat 12/12 · MEASURED: `doctor --selftest --parallel 3` = 169s vs 805s serial for all 21 drills, which puts the whole wave gate under the harness's 600s tool cap for the first time |
| 2026-08-03 | 20 (+T-058 5pts, +T-059 5pts, +T-060 3pts, wave 2, re-sealed sprint/8 2f14623→722ad1d) | 9 · T-062 + T-063 promoted to `ready/` beside the planner's T-064 · scope grew +2 pts mid-sprint (27→29): T-064 filed from my audit of T-058 — unguarded `mutex_off` + a never-disarmed `on_die` trap, armed lease-long since T-057 · cycle p50 0.7h n=58 · kickbacks 0 · suite green sharded 202s + build green · uat 11/12: `triage-lane` RED and NOT the sprint's — it asserts `polaris triage` against the LIVE board, and the planner filing T-064 mid-wave flipped line 1 `full`→`solo`; reproduced identically on bare `main` with zero sprint code, so role §3's flake clause applies — sealed, logged, not kicked back |
| 2026-08-03 | 29 (+T-062 5pts, +T-063 2pts, +T-064 2pts, wave 3, re-sealed sprint/8 722ad1d→fe32671) | 0 — sprint complete, all 8 tasks of plan n-chats-one-repo landed · cycle p50 0.7h n=61 · kickbacks 1 (3%), mine and procedural: T-063 added a PROTOCOL heading that `api-kit.expected` records, but T-062 owns that golden, so the two parallel lanes were coupled through a file neither could reconcile alone — bisect (T-064 green → +T-063 red → +T-062 red, same single line) named T-063 the offender while only T-062 could legally fix it, so T-062 took the bounce · `check --update` is "a human/Builder decision, never automatic" per its own help, so the integrator routed it to the owning Builder instead of self-approving · build avg 0.3h / integrate avg 3.7h · final gate: suite green sharded 330s across 25 drills (4 new labels) + build green + uat 12/12 |

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
- EOL PINS: CLOSED, WITH ONE DEFERRED DIFF STILL OWED (compacted at the sprint-9 close — the bug is
  fully shipped, only the consequence is still live). `ops/tests/*.{expected,cmd}` (T-056) and
  `docs/sprints/*.md` (T-069) are now all pinned `eol=lf`. Before that, `core.autocrlf=true`
  re-materialized goldens CRLF on any git touch and `check` byte-diffed all 480 lines as "differ" — a
  golden green at wave start and red right after the land, reproduced on bare `main` with ZERO task
  code, which is what proved it was the repo's flake and not the task's. The rule outlived the bug and
  now lives in role §3: BASE-CHECK EVERY uat RED BEFORE YOU BELIEVE IT. Still owed: sprint-9's report
  was a NEW file so it normalized silently, but the five PRE-EXISTING reports stay unnormalized until
  something next touches them — expect exactly one whole-file diff per report, once each, and fold it
  into whatever commit touches it rather than reading it as damage.
- A GOLDEN THAT RECORDS A *DERIVED* SURFACE SILENTLY COUPLES EVERY TASK THAT FEEDS IT — three
  instances now, so treat it as structural, not bad luck. Sprint 7: T-047 added fns to `ownership.sh`
  without owning `ops/tests/api-kit.expected`. Sprint 8: T-063 (docs) added ONE PROTOCOL heading —
  `api-kit` records headings too, not just fns — while T-062 (tests) owned the golden; `files_owned`
  were disjoint, the ready gate was satisfied, and the two lanes were still coupled through a file
  neither could reconcile alone. Bisect named T-063 the offender (T-064 green → +T-063 red → +T-062
  red, same single line) while only T-062 could legally fix it, so the bounce went to T-062 — the
  mechanical offender and the legal fixer are NOT always the same task. The live-board variant is the
  same shape: `triage-lane` pins `triage`'s output against the real board, so the Planner filing T-064
  mid-wave turned it red with zero code changed (T-062 made it hermetic). PLANNER: either the golden's
  owner owns every file feeding it, or surface-touching tasks get an explicit `depends_on` chain
  instead of parallel lanes — the ready gate compares paths and CANNOT see this. INTEGRATOR: never
  `check --update` yourself; its own help says "a human/Builder decision, never automatic".
  THE PRESCRIPTION NOW HAS ITS FIRST POSITIVE RESULT (sprint 9 W1). Five parallel lanes touched the
  `api-kit` surface and it cost zero kickbacks, because the plan did all three things at once: ONE
  owner for the golden per wave (T-065), the cross-lane edit — T-066's PROTOCOL heading swap, the
  exact shape that bounced T-063 — pinned BYTE-EXACT in the contract so the golden's owner could
  write the matching line without seeing T-066's diff, and every other lane surface-frozen. Worth
  knowing for nerve: this makes `api-kit` legitimately RED mid-wave whenever only one of the pair has
  landed. That is the design working, not a defect — which is why the wave gate is the run that
  counts, and why an integrator landing pipelined must NOT gate on the golden task-by-task.
  IT HELD ALL THREE WAVES (T-065 → T-070 → T-071 as sole `api-kit.expected` owner, one per wave,
  exactly as the sprint plan carved it), across 5 lanes then 2 then 2, for ZERO kickbacks and a
  first-pass-green gate every time. Three sprints of this defect, one sprint of the prescription, no
  recurrences: the rule is now earned, not theoretical. Keep carving it this way.
  SPRINT 10 W1 FOUND THE PRESCRIPTION'S OWN DEADLOCK: `handoff` re-runs `verify:`, the golden's sole
  owner (T-048) pinned `check --only api-kit` in its verify list, and the golden was legitimately red
  from OTHER lanes' landings (T-074's 37 key rows, T-079's INIT heading tail) — so the one lane
  allowed to reconcile the golden was the one lane that could not hand off. Under one-owner-per-wave
  the owner handing off LAST is the norm, so this is structural, not bad luck. The resolution that
  keeps every gate: the INTEGRATOR records the landed surface mid-wave on the integrate branch —
  derive from the live `.cmd` output, cross-check against the owner's copy stripped of its unlanded
  lines (two independent derivations must agree), review the commit diff line-by-line, never
  `check --update` on faith — and the owner's handoff retries green. After the owner lands, the
  golden must gain exactly its own lines on top; anything else is a finding. EVOLVE: write this into
  key-registry § 5 — the pinned-pair design assumed the owner could hand off red, and it cannot.
- A `risk: high` task at the ROOT of the dependency tree stalls the whole board, not just itself.
  T-047 was audited and verified for days while T-048/T-049/T-050 (13 of 28 pts) sat behind it and
  `ready/` was empty — it waited 128.9h at the gate, which alone moved integrate avg 1.5h→3.9h. The
  approval is cheap at the plan gate and expensive here, exactly as the `ask` mechanism this sprint
  ships argues for its own scopes. Get the yes before the wave, not at the merge.
- THE SUITE SHARDS, AND THAT CHANGES THE INTEGRATOR'S RHYTHM. `doctor --selftest --parallel 3`
  (hermetic since T-046) ran the FULL drill set in 169s / 202s / 330s across sprint 8's three wave
  gates — versus 805s serial — with all 21→25 drills covered, not a subset. That is the first time
  the whole wave gate fits under the harness's 600s tool cap, so a wave gate is now a plain
  foreground call instead of the log-to-a-file-and-poll recipe CONVENTIONS still describes. Measure
  before assuming: the serial 805s figure is what drove three sprints of background-and-poll
  ceremony. EVOLVE: `test:` is a candidate to carry `--parallel 3` outright.
  ANCHOR THE SUITE AT `kit/`, NOT AT THE INSTALLED COPY — and here is the exact cost of getting it
  wrong, measured at the sprint-9 close: the kit driver registers 27 drill labels, the installed
  `ops/` driver registers 21, and the six it cannot see are `bg`, `route`, `busyint`, `claimguard`,
  `park`, `pushdegrade`. For sprint 9 that gap was precisely the sprint — `route` and `bg` ARE the
  work — so `bash ops/polaris doctor --selftest` would have gone green while proving none of it. This
  is THE SPLIT's installed-LAGS-source paragraph showing up as a silent false green rather than an
  error, which is the dangerous shape. `CONVENTIONS.md test:` already anchors the correct form
  (`bash kit/ops/polaris …`) and `handoff` re-ran it per task, so no gate was actually weakened this
  sprint; the tell that you are on the right driver is the label list itself — kit-only labels like
  `park`/`pushdegrade` appear in the shard lines, and after T-071 the count reads 27, not 21.
- EVERY LOCK NEEDS AN OWNER CHECK, AND RECOVERY-BY-AGE MUST STAY OWNER-BLIND. Found auditing T-058,
  fixed by T-064: the integration lease was pid-guarded but the board mutex was not — `mutex_off` was
  an unconditional `rm -rf`, and `on_die` never disarmed, so ANY process exit deleted whatever mutex
  existed, including one another session legitimately held. T-057 widened the window from one board
  mutation to a whole landing pass by arming the trap lease-long. The tell was the ASYMMETRY between
  two locks in the same codebase — worth grepping for whenever one lock learns something the others
  did not. The fix's second half matters as much: `mutex_on`'s staleness steal stays deliberately
  pid-blind, because pid-guarding recovery would make a crashed holder's lock immortal.
- A BASE-BOUND COMMIT LANDS ON WHATEVER THE SHARED CHECKOUT HAS OUT — AND DURING A WAVE THAT IS THE
  INTEGRATE BRANCH. Sprint 9 W1: while I held `integrate/2026-08-03`, the Planner authored
  `docs(contract): bg-jobs v1.1 (T-072)` and it committed onto MY branch, then rode my `--no-ff` seal
  into `main`. Content-wise a non-event — `ops/contracts/**` and `ops/MAP.md` are explicitly NOT in
  the board's moved set (`ops/MANUAL.md`:57), so base is exactly where it belonged, and it touched no
  file any task owned. The hazard is ENTANGLEMENT, not correctness: an unrelated contract is now
  inside a sprint's seal merge, so `rollback sprint/<n>` would revert it too. Structural, not a
  one-off — board writes are protected by living on their own ref, contracts and MAP have no such
  protection, and the Planner grooms the next wave during precisely the window the integrate branch
  is checked out. INTEGRATOR: `git log <base>..integrate/<date>` before sealing and read every commit
  you did not land — a subject without a `[<ID>]` suffix is the tell, and it is invisible after the
  merge. Cheap fix if it recurs: groom onto `<base>` from a second worktree, or seal sooner.
  IT RECURRED IN THE SAME SPRINT, so treat it as certain rather than possible: wave 3 captured
  `docs(contract): bg-jobs v1.2 (T-073)` exactly as wave 1 captured v1.1. Twice in one sprint, both
  times the Planner authoring the NEXT task's contract during the landing window — which is not bad
  luck, it is the two roles' schedules overlapping by design. The pre-seal log read caught both; make
  it a reflex, not a reaction.
  SAME FAMILY, MY OWN NEAR-MISS: DO NOT TOUCH TAGS BY HAND. Closing wave 2 I ran
  `git push origin --tags --force`, which is on the STOP-AND-ASK list and which I should have asked
  about first. It was a harmless no-op only because `seal` had already moved `sprint/9` via its own
  compare-and-swap, and I verified all seven sprint tags still pointed where they belonged. The
  lesson is that there was never a reason to reach for it: `seal` OWNS the tag in both publish modes,
  so an integrator pushing tags manually is already off the sanctioned path, and `--force` on a ref
  namespace holding every sprint's history is the one place a no-op and a catastrophe look identical
  until you check.
- A BUILDER DEEP IN ONE FILE IS THE CHEAPEST DEFECT DETECTOR YOU HAVE — GIVE THE FINDING A 1-PT RIDER
  INSTEAD OF A BACKLOG LINE. Twice in sprint 9 a Builder surfaced a real defect in code it did not
  own and could not legally touch: T-067 found `check --update/--scaffold` silently hook-approved
  inside compounds (→ T-072, 1pt, `fix(hooks)`), and T-071 found `cmd_finish`'s bg guard counting
  `.prev` archives as live jobs, which makes a run permanently un-finishable (→ T-073, 1pt,
  `fix(cli)`). Both were filed mid-sprint, both owned a single disjoint file, both landed in the wave
  already in flight, and both cost one point. The pattern that makes this safe is the SIZE and the
  DISJOINTNESS, not the urgency: a one-file rider clears the ready gate against whatever is already
  in `ready/`+`active/` without re-planning the wave, so the finding gets fixed while the context is
  hot instead of aging in `IDEAS.md` until nobody remembers the repro. PLANNER: treat "Builder found
  a defect outside its ownership" as a first-class task source, and point it at 1 unless it is
  genuinely bigger. INTEGRATOR: a rider arriving after you have already landed its wave is not a
  reason to seal early — hold the gate, take the rider, gate once over both.
- A RAW SHELL BACKGROUND JOB IS OWNED BY NOBODY THE MOMENT A SUBAGENT'S TURN ENDS. Sprint 10 W1: the
  integrator (conductor-entered, so a subagent) launched the 805s suite through the harness's
  background shell and ended its turn expecting a completion notification — but a subagent between
  turns receives none, so the job ran orphaned with nothing watching it, and a crash would have been
  indistinguishable from still-running. It survived because the conductor independently armed a watch
  on process exit covering both outcomes. `bg run` + chunked `bg wait` exists for exactly this — the
  verdict lives in an rc file ANY session can collect later — so a long command in a subagent goes
  through the bg machinery or stays foreground with an explicit timeout; a bare background shell is
  only safe in a session that will still be alive to reap it.
- PLANNER: NEVER YAML-QUOTE A `verify:` LINE. frontmatter-lists v1 keeps quotes BY DESIGN, so a
  double-quoted entry reaches bash as ONE quoted word and can never run — T-074 shipped with two
  unrunnable assertions (the awk TSV checks) and the Builder had to fix its own task file mid-flight,
  the only sanctioned self-edit there is. `fm_list` strips only a trailing ` #comment`; plain
  unquoted lines are always right, and no quoting is ever needed.
