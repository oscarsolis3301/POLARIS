# SPRINT 28 — Walk away: approve, leave, come back to finished work (6.20.0)          capacity: 100   dates: 2026-11-24–

Owner ask of 2026-11-24 (plans/walk-away.md, approved): after a plan is approved in auto mode POLARIS
runs every command itself, nothing waits on the owner, a hung job is killed and parked instead of
stalling for hours, the expensive model never sits waiting (a Haiku runner is allowed for that one
job), and small look/text/UI changes are checked in proportion with fewer hops.
Plan `walk-away`, contract `ops/contracts/walk-away.md` v1. Capacity 100: the whole plan is one release, as approved.

10 tasks / 90 pts, THREE waves. Wave 1 side by side (57 pts): T-318 (job budgets + watchdog, pulse,
preflight, defer, stall lines, the loader, all help; sole owner of kit/ops/polaris, KEYS.tsv and
api-kit for wave 1) · T-319 (armed run, Stop gate, permission hooks, keep-awake — risk: high) · T-320
(Haiku runner + its one guard exception — risk: high) · T-321 (depth in the core, route --role RUNNER)
· T-322 (spike: timing BEFORE section D) · T-328 (fewer CLI starts, pack forecast; re-filed from
T-323). Wave 2: T-324 (finish: parked, run: line, express ui) · T-325 (words, heal, speed; api-kit
for wave 2) · T-326 (quiet-lane tail, only if its trigger is met). Wave 3: T-327 (joined-tree drills
away-run + runner-path, every shared golden, api-kit, VERSION 6.20.0, CHANGELOG). After it: finish,
release ritual, dogfood, re-pin cli-help.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-24 | 60 | 33 |
| 2026-11-24 | 8 | 85 |
| 2026-11-24 | 2 | 91 |
| 2026-11-24 | 8 | 59 |
| 2026-11-24 | 2 | 34 |
| 2026-11-24 | 25 | 8 |
| 2026-11-24 | 3 | 5 |

# SPRINT 27 — The smooth run: cards own their tests, waves catch their reds, re-cuts by command (6.19.0)          capacity: 50   dates: 2026-11-17–

Owner ask of 2026-11-17 (plans/smooth.md, approved; owner away): build the next update from the
eighteen gap lines of 2026-11-17 (Sonoba's run on 6.17.0 + this repo's 6.18.0/6.18.1 run), plus the
coordinator's addition from Sonoba's latest grants (folder guides auto-owned, importing files listed).
Plan `smooth`, contract `ops/contracts/smooth.md` v1. Capacity raised to 50: one release, as decided.

5 tasks / 50 pts, TWO waves. Wave 1 side by side: T-313 (new owns mapped tests + guides, lists what
touches a card's files, sorts drafts, retire + new --retire + status --all, help; sole owner of
kit/ops/polaris) · T-314 (grant/release/handoff --hold/approve --plan/lock folder/next+triage stale
verdict/pack's first section) · T-315 (the wave check in seal, amend --deps, roles + PROTOCOL + MANUAL)
· T-316 (update channel/registry/pending update, speed --plan pricing, proof.sh cancelled). Wave 2:
T-317 (joined-tree goldens, api-kit re-pin — its sole owner — VERSION 6.19.0, CHANGELOG). After it:
dogfood, re-pin cli-help, release ritual.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-17 | 48 | 3 |
| 2026-11-17 | 3 | 0 |

# SPRINT 26 — The tune-up: every install ends faster than it started (6.18.0)          capacity: 30   dates: 2026-11-17–

Owner ask of 2026-11-17 (plans/tune.md, approved; owner away): apply the three lessons of plan hour,
and make every update and every install end in a tune-up that restructures what slows a project.
Plan `tune`, contract `ops/contracts/tune.md` v1.

2 tasks / 26 pts, ONE wave, side by side: T-308 (the commands: tune, fold, note, NEEDS PATH, the words,
version 6.18.0 + changelog; sole owner of kit/ops/polaris and api-kit.expected) and T-309 (the hop:
next/triage take the tune-up with cards waiting, the hold rule keeps the layout pass off waiting cards'
files, update/install/heal/done/seal name and refresh it, find --api skips nested helpers, TIDY/INIT/
CLAUDE words). After both land: dogfood, then re-pin cli-help and api-kit (the seven nested rows leave).

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-17 | 26 | 0 |
| 2026-11-17 | 1 | 0 |
| 2026-11-17 | 3 | 0 |
| 2026-11-17 | 2 | 0 |

# SPRINT 25 — The hour: push once, one heavy job, fewer cards, a price on every plan (6.17.0)          capacity: 30   dates: 2026-11-16–

Owner ask of 2026-11-16 (plans/hour.md, approved in plan mode): Sonoba quoted 60–70 hours for one
stakeholder round; the bar is the same day, an hour at most. Measured cause: time = cards on the
critical path × cost per card, and POLARIS pushes both up. Plan `hour`, contract `ops/contracts/hour.md` v1.

6 tasks / 26 pts. Wave 1, side by side: T-300 (the heavy slot + the three new keys), T-301 (handoff
stops pushing under push: end, last lane out counts only this run, seal on demand, pack steps, one-pass
seal scan), T-302 (speed by lanes + speed --plan), T-303 (chain cards with steps: + next in one pass).
Wave 2: T-304 (seal/done/finish/status under push: end, one atomic push; after T-300 and T-301) and
T-305 (the words + version 6.17.0 + changelog; after T-300..T-303). Every task lands itself at handoff;
each verify list is its whole gate, and CI's Linux serial self-test runs once per task before handoff.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-16 | 18 | 8 |
| 2026-11-16 | 8 | 0 |
| 2026-11-17 | 2 | 0 |
| 2026-11-17 | 1 | 0 |

## Learned
- 2026-11-17 · speed --plan priced two 13-point chain cards as average cards (24 min); they took 23 and 42 min — price a chain card by its steps, not as one card (plan tune)
- 2026-11-17 · two side-by-side cards met at a shared verdict file and one golden that runs the real heal went red only after both landed — a wave with a seam file needs one golden run on the joined tree before the seal (plan tune, T-310)
- 2026-11-24 · new auto-adds a SURFACES tests glob (ops/tests/<x>.*) to a card; two cards each holding one are chained by pat_overlap's glob-vs-glob heuristic even when disjoint — a false overlap cost walk-away a wave until T-323 was re-filed as T-328 without author.sh (plan tune)
