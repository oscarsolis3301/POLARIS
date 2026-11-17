# The hour program (6.17.0) — why Sonoba quoted 60–70 hours, and what closes the gap

## Context

A Sonoba session on the remote Mac (`venzeti@StudioX1`) planned a stakeholder round and said it
needs "60–70 hours of builder time, two at a time". The owner's bar: release the same day, an hour
at most.

I could not read that chat (Remote Control sessions are listed here, their transcripts are not
readable from this machine). I read Sonoba's board from GitHub instead (`oscarsolis3301/sonoba`,
branch `polaris/board`, pushed minutes earlier): 5,126 timed events, 841 finished cards. Every
number below is measured from that log, or from the same log in Pool and Polaris. Three read-only
traces of `kit/` then tied each number to the code that causes it; I re-read the cited lines.

**The estimate is honest. The process is slow, and it is slow by design in two places POLARIS has
never measured.**

### What the log says

| Sonoba, last 300 cards | Value |
|---|---|
| The round as planned (`stakeholder-1116`) | **72 cards, 271 points**, mostly chained |
| Build time of one card, built alone | **29 min** |
| Same card with 2 / 3–4 / 5–7 / 8+ builders beside it | 44 / 81 / 97 / 119 min |
| A 1-point card vs a 5-point card | 99 vs 103 min — size does not matter |
| After handoff, until landed | 83 min (46 waiting on the slowest sibling, 19 for the landing check) |
| After a wave lands, until the next card starts | 14 min |
| Backup pushes that failed three times in a row | 138 |

72 cards × about 55 min ≈ 66 hours. That is the quote.

| Same kit elsewhere | Build per card | Request → all landed |
|---|---|---|
| **Pool** (6.16.1, 3-second suite, no push check) | 4–8 min at any lane count | 25 cards / 96 points in **2.6 h** |
| **Polaris** (6.16.1) | 21 min | 8 cards / 20 points in 2.4 h |
| **Sonoba** (6.15.0, 14-minute suite on every push) | 29–119 min | 15 cards / 47 points in **21.5 h** |

So: **time = cards on the critical path × cost per card.** POLARIS pushes both up, in every
project. A fast suite (Pool) hides it; a slow one (Sonoba) multiplies it.

### The gaps

| # | Gap | Evidence |
|---|---|---|
| 1 | **Check time is invisible.** A "hop" is a lookup; the protocol says checks "cost zero LLM tokens" and that it "collapses SESSIONS, never CHECKS". Nothing forecasts a plan, and the run caps skip plan work, so a 66-hour plan is approved exactly like a 20-minute one. | `kit/ops/PROTOCOL.md:93-100,192` · `lib/handover.sh:265` · `lib/admin.sh:438-478` (two medians, read by no rule) |
| 2 | **Card count only goes up.** `new` refuses anything over 5 points, and chains every draft that shares a file. No way for one builder to carry a chain. A 1-point "What's New" note is its own card, waiting on 32 others. | `lib/author.sh:73`, `:107-109`, `:142-147` · `roles/PLANNER.md:20,71-73,96` |
| 3 | **Each chain link costs a whole wave.** B starts only when A is merged to base; only the last lane out merges, and only when `ready/` and `active/` are empty. Sonoba's `ready/` always holds 8 cards from other plans, so no lane ever qualifies. | `lib/builder.sh:489-493`, `:555-558` · `lib/handover.sh:142-149` |
| 4 | **Every card pushes a backup nobody uses.** Handoff pushes `feat/<ID>`, 3 tries, unlocked; landing merges the local branch (the code says so) and `done` deletes the copy. On Sonoba each push runs the full 14-minute check. Seal then pushes base and tag separately: two more. | `lib/builder.sh:335-371` · `lib/integrate.sh:504`, `:1130-1138` |
| 5 | **Nothing stops several heavy checks at once.** Lanes = min(ready, 5), blind to load. Only the board and the landing are locked; verify lines, pushes and `qa` are not. | `roles/CONDUCTOR.md:194` · `lib/workspace.sh:225-298` |
| 6 | **Builders are told to run the whole suite per card.** Invariant 4 says "Test commands from CONVENTIONS green"; BUILDER.md and SOLO.md say the opposite. | `kit/CLAUDE.md` Invariant 4 · `roles/BUILDER.md:52` |
| 7 | **The board got heavy** (estimates, not timed). `next` forks ~3,100 processes over 220 backlog cards after every board event; `seal` walks all 841 done cards. | `lib/handover.sh:102-153` · `lib/knowledge.sh:56-82` |
| 8 | **Every card starts cold** (inferred, not timed): a fresh worktree per card, no warm build. | `lib/workspace.sh:40-45` |

## What changes — kit 6.17.0, plan slug `hour`

Ordered by measured payoff. Contract: `ops/contracts/hour.md`.

**A. Stop paying for checks nobody asked for** (gaps 4, 5, 6)
1. **Code is pushed once, at the very end of a run** (owner, 2026-11-16). New key `push:` —
   `end` is the default on one computer (`claim: local-lock`); `wave` keeps today's behaviour and
   stays the default for `claim: claim-branch`, where another machine needs the code sooner.
   Under `end`: handoff pushes no `feat/<ID>` and `done` deletes none; seal merges and tags
   locally, exactly as `publish: pr` already does; `finish` makes the one push.
   — `lib/builder.sh:335-371`, `lib/integrate.sh:501-507`, `:1125-1143`, `lib/qa.sh:653-674`
2. That one push carries base and tags together (`git push --atomic`): one check, not two or
   three. `wave` mode gets the same single push per seal. `status` and `finish` say how many
   commits are not on origin yet. — `lib/qa.sh`, `lib/integrate.sh`, `lib/observe.sh`
3. One heavy job at a time per machine: a `heavy` slot (same mechanism as the landing lease,
   `int_on`/`int_off`, kept under `~/.claude/polaris/` so it spans worktrees and projects) around
   `verify:` runs, `qa`, the express suite and the push. Key `heavy_slots:` (default 1).
   — `lib/workspace.sh`, `lib/ownership.sh:56-84`, `lib/qa.sh`, `ops/KEYS.tsv`
4. Lane count from the log: `speed` prints build time by lanes in use; the conductor takes the
   count with the best cards per hour instead of a flat 5. — `lib/admin.sh` (`cmd_speed`), `roles/CONDUCTOR.md:194`
5. Invariant 4 reworded: the card's own checks per card, the full suite once per wave.
   — `kit/CLAUDE.md`, `roles/BUILDER.md`

**B. Fewer, bigger cards — and a price on every plan** (gaps 1, 2)
1. `speed --plan <slug>`: cards, waves on the critical path, lanes × this project's own medians →
   projected hours. The planner's "estimated time" line comes from this command only.
   — `lib/admin.sh`, `roles/PLANNER.md:89`
2. `target_minutes:` (default 60). A plan that projects past it is re-cut once to drop cards
   (chains merged, riders folded). Then it runs as ONE release, and the projected hours are shown
   before approval (owner, 2026-11-16: run it all, show the time — no slices, nothing refused).
   — `lib/author.sh`, `ops/KEYS.tsv`, `roles/PLANNER.md`, `roles/CONDUCTOR.md`
3. A chain is one card: up to 13 points when the card lists `steps:` (each step ≤ 5 points, own
   check, own commit). Riders (notes, version bumps, string additions) are a step of the card that
   causes them. Owner-only "record" cards leave the builder queue and go to the close.
   — `lib/author.sh:73`, `lib/handover.sh:136-139`, `lib/drift.sh:207`, `lib/route.sh`, `roles/PLANNER.md`, Invariant 2

**C. A chain does not wait for the wave** (gap 3)
1. "Last lane out" counts only cards this run can claim. — `lib/builder.sh:555-558`
2. After a land, if a card of this plan waits only on what just landed, seal now and promote it in
   the same step. With A1 a seal no longer pushes, so this costs seconds.
   — `lib/builder.sh:489-545`, `lib/handover.sh`

**D. A lighter board** (gap 7)
1. `next`'s backlog scan and seal's done scan become one `awk` pass each.
   — `lib/handover.sh:102-153`, `lib/knowledge.sh:56-82`

**E. Say it out loud** (gap 1)
1. PROTOCOL § LANES gains the missing half: checks cost no tokens, they cost minutes; the unit to
   save is a card. Every close quotes the `speed` line. — `kit/ops/PROTOCOL.md`

**Later, after measuring 6.17.0** (not in this plan): warm worktrees (gap 8, a `warm:` key), and
`derived:` paths so generated files stop forcing chains.

Reuse, not new machinery: the landing lease (`int_on`), the `speed` awk pass, the `git` stand-in
drill pattern from T-285, `plan_covers` for the plan filter, `tools/proof.sh` for the gate.

## What this buys — projections, to be measured

| | Today | After 6.17.0 |
|---|---|---|
| Sonoba, the same 271-point round | 72 cards, ~66 builder-hours, ~33 h on the clock | ~20 cards, **about 5 h**, one release, one full check at the end |
| Sonoba, one card | 29–119 min | ~15–20 min (no push check per card, no overlap) |
| Pool, 96 points | 2.6 h | about 1–1.5 h |
| One feature (≤ 40 points), fast suite | 1–2.5 h | inside the hour |

One hour for all 271 points is not reachable on one Mac with a 14-minute check: the model still has
to write about fifteen migrations and five screens. Same day is.

The price of pushing at the end: until a run finishes, its code is on that machine's disk only (the
board still syncs as it goes), and a red check at the end covers the whole run — the fix wave
handles it, as today.

## Sonoba today — no kit release needed

After approval I send this note to the Remote Control session "App feature review and stakeholder
requests" (owner, 2026-11-16: send it):
- Finish the 3 cards in flight; hold the other 69.
- `autolaunch_max: 2` in `ops/CONVENTIONS.md` (measured: 44 min per card at 2 lanes, 97 at 6).
- `tools/githooks/pre-push`: skip the gate when a push carries only `feat/*` refs; `main` and tags
  stay gated in full. Owner's yes required — it is the gate.
- Shut down booted simulators before each seal (its own lesson, 2026-11-11).
- After 6.17.0: `update`, then re-cut `stakeholder-1116` under the new rules.

## Proof

- **Drills** (`kit/ops/lib/selftest/`): under `push: end`, handoff, seal and done leave origin's
  refs unchanged and `finish` makes exactly one push (a `git` stand-in counts); `push: wave` makes
  one push per seal; two `run-verify` calls never overlap; a wave seals with
  another plan's cards in `ready/`; a chain's next card is promoted without waiting on another
  lane; `new` takes 13 points with `steps:` and refuses it without; `speed --plan` matches a
  fixture log; an over-budget plan prints the re-cut line.
- **Gate:** `bash ops/polaris finish` → `tools/proof.sh` (CI Linux serial + goldens), then
  `tools/proof.sh --await macos-latest` before the tag.
- **Live, before and after:** in `Desktop\polaris-testbed`, a 60-second pre-push check and a
  6-card plan with a 3-link chain. Count check runs and time request → landed on 6.16.1 and 6.17.0.
- **Release everywhere:** `ops/VERSION`, CHANGELOG, tag `v6.17.0`, published zip, dogfood,
  `update --all`.
- **Sonoba, after its update:** `bash ops/polaris speed` — target: build ≤ 20 min per card at 2
  lanes, no `push-fail` events, the round re-cut to about 20 cards.

## Owner decisions, 2026-11-16 (named here so the run does not stop)

- Chain cards: yes — up to 13 points with `steps:`. Invariant 2 changes in `kit/CLAUDE.md`.
- Over the hour: run it all as one release, show the projected time before approval.
- Pushes: once, at the very end of a run (`push: end`, the new default on one computer).
- Sonoba: send the hold-and-tune note after approval.
- Also changed by this plan: Invariant 4 (which checks run per card); new keys `push`,
  `target_minutes`, `heavy_slots`.
- Nothing is deleted; `.github/` is not touched.
