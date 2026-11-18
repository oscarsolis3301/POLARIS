# Sprint 27 — The smooth run: cards own their tests, waves catch their reds, re-cuts by command (6.19.0) (2026-11-17–)

## T-313 — "Filing work right the first time - new owns a card's mapped tests and folder guides, lists what touches its files, sorts its drafts, and retire re-cuts a plan in one command"
points 13 · risk normal · landed 2317bc7 (2026-11-17) · claimed 2026-11-17
files touched: kit/ops/index.py, kit/ops/lib/author.sh, kit/ops/lib/observe.sh, kit/ops/polaris, kit/ops/templates/TASK.md, ops/tests/fm-comments.cmd, ops/tests/fm-comments.expected, ops/tests/new-task.cmd, ops/tests/new-task.expected, ops/tests/retire-board.cmd, ops/tests/retire-board.expected

### Why
Sonoba's run (kit 6.17.0) spent its biggest block of time on one pattern: 24 of its 27 `grant`s in
16 hours were TEST files, and each cost 25–40 minutes — the builder found the reds 40–50 minutes in,
stopped, was granted the file, re-pinned and re-ran. Three more hours of its board added the rest of
the pattern: of 12 new grants, 4 were source files that use the card's own files and 1 was the guide
(`<dir>/CLAUDE.md`) of a folder the card adds a file to. `ops/SURFACES.tsv` already says which tests
cover which source paths, so `new` puts those tests — and the guide of every folder the card changes —
on the card itself (contract § 1.1). It also LISTS, as advice, the tests that mention one of the card's
files and the files that import them (§ 1.2–1.3), so the builder asks for any it must change in its
first minute instead of after the build. `pack` (T-314) prints the same list through the helper this
card writes.

The same run re-cut its plan by hand: 124 hand edits of board files and 78 superseded cards left in
`blocked/`, where they read as "needs regroom" forever. `retire` moves waiting cards to a new
`retired/` folder in ONE board commit, notes their successor on each, and rewires every `depends_on`
that named them (§ 2.1); `new --retire <map>` does the retire first in the same commit, so a re-cut
never chains a new card to one it is about to retire (§ 2.3); `status --all` is the one reader of
`retired/` (§ 2.2). `new` also stops refusing a draft just because the card it waits on came later in
the glob — it sorts its drafts itself.

This card owns `kit/ops/polaris`, so it writes the help text for EVERY new verb and flag of the plan
(§ 9) straight from the contract; PROTOCOL and MANUAL are T-315's.

### Acceptance
- [ ] `new` adds each mapped test glob and each tracked folder guide to the filed card's files_owned and says so on stderr; none of either = byte-identical output
- [ ] `new` prints the advisory block (stderr) with `names` and `uses` lines; nothing to list = nothing printed
- [ ] `find --importers` with ONE path is byte-identical; with several, one index build and prefixed rows
- [ ] two drafts given in the wrong order file in dependency order; a cycle refuses and writes nothing
- [ ] `retire` and `new --retire` match § 2.1 and § 2.3 exactly — refusals, effect, ONE commit subject, printed lines
- [ ] bare `status` byte-identical; `status --all` lists retired cards with their successor
- [ ] help carries every § 9 item

## T-314 — "The builder's commands stop costing round trips - grant refuses from a card's own lane, release parks and cleans up, handoff can hold, the lock knows its folder, next recomputes a stale verdict"
points 12 · risk normal · landed d2f81e1 (2026-11-17) · claimed 2026-11-17
files touched: kit/ops/lib/builder.sh, kit/ops/lib/handover.sh, kit/ops/lib/route.sh, kit/ops/lib/selftest/board.sh, ops/tests/builder-cmds.cmd, ops/tests/builder-cmds.expected, ops/tests/next-own-folder.cmd, ops/tests/next-own-folder.expected

### Why
Seven of the eighteen gaps are small commands that each cost a builder or a conductor a round trip.
A builder could `grant` itself a test that gates its own work (Sonoba, and here: T-311's SOLO granted
itself two test paths) — `amend` and `approve` already refuse from a builder's lane, `grant` now does
too and points at `NEEDS PATH` (contract § 5.1). `release --to blocked` refused an unclaimed ready card
and `release` left a feat branch nobody could delete (§ 5.2). Under `landing: self` a builder told
"hand off, the conductor lands" could not stop at review/ — T-1127 (2 points) sat 3.5 hours between
built and the owner's yes; `handoff --hold` stops there and nothing lands it by itself (§ 5.3).
`approve --plan` for a re-cut plan left `drain: plan` holding its cards as "not this run's" (§ 5.4).
`next` told the conductor "resume T-1130: your own lock is live" because builder subagents share its
session id — the lock now records its worktree and `next` answers for the caller's folder (§ 5.5).
And `next`/`triage` read a verdict about an older commit as "nothing due" — found live in job and
venzeti — so a stale one is now recomputed once (§ 5.6).

`pack` gains its first section — the tests and files that touch the card's own files — through T-313's
`_card_reach`, guarded so it is silent until T-313 lands (§ 1.4). T-317 proves the pair on the joined
tree.

### Acceptance
- [ ] grant from a feat branch or inside .polaris/wt/<ID> refuses with the § 5.1 words and writes nothing
- [ ] release --to blocked of an unclaimed ready card; an empty feat branch is removed and the line says so
- [ ] handoff --hold leaves the card in review/ with held: yes, lands nothing, and next never routes integrate for it
- [ ] approve --plan writes the plan marker when a session id is set
- [ ] next from the primary never says resume for a lock whose line 6 is a worktree; from that worktree it does
- [ ] a stale tune-due on a quiet board makes next and bare triage recompute and answer from the fresh verdict
- [ ] pack's first section appears only when _card_reach exists and lists something; every other pack byte-identical

## T-315 — "A wave's reds show up in that wave - the seal runs the tests covering what the wave changed, amend can rewire depends_on, and the roles, PROTOCOL and MANUAL say how"
points 11 · risk normal · landed f84663f (2026-11-17) · claimed 2026-11-17
files touched: kit/ops/KEYS.tsv, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/lib/integrate.sh, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md, ops/tests/amend-deps.cmd, ops/tests/amend-deps.expected, ops/tests/wave-check.cmd, ops/tests/wave-check.expected

### Why
Sonoba (6.17.0, `landing: self`, `push: end`, only `test:` set): T-1134 and T-1135 each landed green
on their own filters and left 5 red tests on main, found only when someone ran the suite by hand —
a fix card and a grant later. Invariant 4 says "the full suite runs once per wave", but the code
never did that under `landing: self`: contract § 3.0 traces it — the self-landing tail is `land`
(squash + audit) then `seal` (merge + tag + report), and neither runs a test; the suite runs only in
`qa` (so `finish`) and in `land --express`. Seal on demand (6.17.0) made it worse by splitting one
plan into several waves that each sealed untested.

Now the seal itself runs, once, the tests covering what the wave changed — the same selection `qa`
and express already share (`test_select_for`), or the whole `test:` when a changed path has no
SURFACES row — under the heavy slot, before anything merges (§ 3.1). A red keeps the wave open and
names the card(s) whose paths the failing row covers (§ 3.3), so the fix lands on the same wave.
The rows run at every seal; the whole `test:` (for paths no row covers) runs at a seal only once per
`wave_check:` minutes — default 60 — because with seal on demand a chained plan seals at almost every
card, and a whole suite at each (Sonoba: 11 min) would bring back the per-card wait 6.17.0 removed
(445 s → 4 s). A whole-suite red names every card sealed since its last green (contract § 3.1-3.5, v1.1).
Nothing per card. `seal --no-check -m why` is the recorded way past a red
that is not the wave's code (§ 3.4); `finish` still runs the whole suite.

`amend --deps +X/-X` (§ 4) ends hand-edited depends_on (three Sonoba cards). And this card carries the
words of the whole plan except help: the role files (§ 9 — BUILDER's first-minute NEEDS PATH, SOLO's
hand-back instead of grant, CONDUCTOR's hold / re-cut / red-wave steps, INTEGRATOR's wave check,
PLANNER's retire), the PROTOCOL rows and the MANUAL recipes, written from the contract.

### Acceptance
- [ ] a wave whose joined tree fails a mapped test does not seal, names the card, records wave-red, leaves integrate/<date> open and the primary on base
- [ ] a green wave seals with one wave-check line and the stamp; a re-seal of the same tip skips
- [ ] test: unset → nothing printed and the seal byte-identical to 6.18.1
- [ ] an unmapped changed path runs test: verbatim once
- [ ] seal --no-check refuses on feat/* and without -m; with both it records the why
- [ ] amend --deps matches contract § 4 — refusals, effect, one commit
- [ ] the role files, PROTOCOL and MANUAL carry every § 9 item; the only new MANUAL headings are the three named

## T-316 — "Updates that see a same-day release and never freeze, a plan price that counts chain cards and release checks, and a proof that does not call a cancelled job red"
points 12 · risk normal · landed 2e3f0a7 (2026-11-17) · claimed 2026-11-17
files touched: kit/ops/lib/admin.sh, kit/ops/lib/selftest/remote.sh, ops/tests/proof-ci.cmd, ops/tests/proof-ci.expected, ops/tests/speed-plan.cmd, ops/tests/speed-plan.expected, ops/tests/update-pending.cmd, ops/tests/update-pending.expected, ops/tests/update-registry.cmd, ops/tests/update-registry.expected, tools/proof.sh

### Why
Six gaps live in the update path, the price of a plan and this repo's proof tool.
6.18.1 came out hours after 6.18.0 and job and venzeti answered "up to date (6.18.0)" until the cache
file was removed by hand — the channel is asked once a day. A typed `update --all` now asks the
channel itself, and `--auto` re-asks when its cached answer is the installed version and over an hour
old (contract § 6). The machine registry listed one project twice by drive-letter case, listed
worktrees, and five entries held no POLARIS at all; the walk folds, skips and drops them (§ 6).
A `publish: pr` project never commits an update itself, so its own pending update read as "your
uncommitted kit edits" and froze every later update (polaris-testbed sits on 6.17.0 this way): the
update now records exactly what it wrote and left uncommitted, by content hash, and the next update
recognises those files — byte-equality, so a person's edit to a kit file still holds it (§ 6).

`speed --plan` priced two 13-point chain cards as average cards (24 min); they took 23 and 42. A chain
card is now priced from its points, along a weighted critical path, and the release checks — one
whole suite per wave check plus the finish — get their own lines (§ 7). And `tools/proof.sh --await`
printed RED for a macOS job GitHub cancelled after 15 minutes in the queue with no step run; a
cancelled job is now "cancelled — no answer" and the wait falls back to the push run of the same
commit, which under `push: end` exists as soon as `finish` returns (§ 8).

### Acceptance
- [ ] a typed update --all reaches the channel even with a same-day cache; --auto re-asks only per § 6
- [ ] the registry walk removes a case-folded duplicate and a no-VERSION entry, skips a worktree, with the § 6 lines
- [ ] a publish: pr fixture whose only dirt is its recorded pending update is not held; one kit file edited after the record is
- [ ] a 13-point chain card prices at twice a card's build minutes; the release-checks lines appear only with a suite time on record
- [ ] proof.sh: a cancelled job never prints RED; it falls back to the push run, or says no push run yet with rc 3
- [ ] the autoupdate drill green, run by hand, result in Notes
