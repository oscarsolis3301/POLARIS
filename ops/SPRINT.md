# SPRINT 30 — One kit for the whole machine (6.22.0 + 7.0.0)          capacity: 110   dates: 2026-11-24–

Owner ask of 2026-11-24 (plans/one-kit.md, approved): one POLARIS installation for ALL projects on
the computer, one shared kit, "hop less if possible and run commands for us". The kit lives once
under ~/.claude/polaris/kit/<ver>/, a project keeps only its state and a launcher, one dispatcher
hook replaces four per tool call, the protocol arrives at session start, one update moves every
project with no commit, and only the owner's --setup writes Claude Code settings. Plan `one-kit`,
contracts shared-kit v1 · hook-dispatch v1 · auto-update v6 · install-parity v2 · first-run v3 ·
module-layout v12 · doc-server v2 · safe-landing v2 · role-handover v6 · walk-away v2 addendum.
TWO releases under one slug (speed: projected about 3.6 h, 4.4 h with release checks; walk-away
measured 5.5x its projection): 6.22.0 = everything dormant behind detection, 7.0.0 = the switch.

12 tasks / 102 pts, FIVE waves. W1 side by side (32): T-341 (wave cut + admin groundwork) · T-342
(landing words, one bg wait length) · T-343 (four guards as functions, high, W1 api-kit) · T-344
(store + launcher + zip_sha256). W2 (31): T-345 (dispatcher + shim, high) · T-346 (session context,
router ≤ 8,000 bytes, CONDUCTOR pages, W2 api-kit) · T-347 (machine update, sole kit/ops/polaris +
admin.sh owner). R1: T-348 (6.22.0 joined tree). Then finish + release ritual. W3 (28): T-349 (join +
migrate) · T-350 (--setup, no agent-run settings writes, high) · T-351 (INIT from a work request,
two machine keys). R2: T-352 (no-self-grant, drill_sharedkit, install skill, 7.0.0). Then finish,
ritual, the owner's --setup click.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-24 | 24 | 78 |
| 2026-11-24 | 28 | 52 |
| 2026-11-24 | 13 | 39 |
| 2026-11-24 | 3 | 36 |
| 2026-11-24 | 1 | 36 |

# SPRINT 29 — Your preferences, once, for every project (6.21.0)          capacity: 100   dates: 2026-11-24–

Owner ask of 2026-11-24 (plans/prefs.md, approved): one POLARIS installation for all projects on the
computer, using the same preferences. A machine preferences file sits under every repo's own
CONVENTIONS lines, `polaris prefs` shows and sets it, a new project asks nothing the file answers,
and the CLI finds its own code and serves its own documents (groundwork for the shared kit, 7.0.0).
Plan `prefs`, contracts machine-prefs v1 · doc-server v1 · first-run v2 · key-registry § 10 ·
hands-free-knobs v4 · module-layout v11 · safe-landing v1.4. Capacity 100: one release, as approved.

8 tasks / 59 pts, THREE waves. Wave 1 side by side (29 pts): T-333 (cfg machine layer + harness
isolation, KEYS scope column, kit_file/prefs_put/POLARIS_HOME, landed_content_ok § K; wave-1 owner of
api-kit + KEYS.tsv) · T-334 (all hooks) · T-335 (kit prose to command form + INIT.md) · T-336 (CLI
printed strings). Wave 2 (26 pts): T-337 (sole owner of kit/ops/polaris: prefs, role, doc, router,
kit/CLAUDE.md; wave-2 api-kit) · T-338 (interview --init/--remember, admin + installer) · T-339
(doctor line, lib readers). Wave 3: T-340 (kit-mode + doc-refs on the joined tree, every shared
golden, VERSION 6.21.0, CHANGELOG). After it: finish, release ritual, dogfood, re-pin cli-help.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-24 | 29 | 30 |
| 2026-11-24 | 26 | 4 |
| 2026-11-24 | 4 | 0 |

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
| 2026-11-24 | 1 | 5 |

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
