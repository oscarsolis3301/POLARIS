# The tune-up (kit 6.18.0) — plan slug `tune`

## The owner's words (2026-11-17)
1. "Apply all three" — the three fixes from the lessons pass of plan `hour`. Exact diffs:
   `evolve-hour-report.md` beside this file (copy what a card needs into the contract or the card).
2. "Existing installs already of POLARIS that are UPDATING POLARIS should restructure, add, modify
   their installs completely to improve speed and effeciency."
3. "Even new, greenfield, existing installations, they should all have full and complete
   optimization along with improving the overall output speed by decreasing amount of hops,
   restructuring the project if necessary, etc."

## Measured today on this machine — what an update leaves behind
Read from each registered project (`~/.claude/polaris/awake/repos/*`), 2026-11-17:

| Project | Kit | What the update did not do |
|---|---|---|
| job | 6.17.0 | layout pass due ("52 folders of 5+"), never run · `integration: paranoid` · 13 open cards cut under the old size rule |
| venzeti | 6.17.0 | layout pass due ("~29% fewer folders"), never run · `integration: paranoid` · 11 open cards |
| Pool | 6.16.1 | never updated: 4 cards sit in review · layout pass due ("35 folders of 5+"), never run · 28 backlog cards |
| pip | 6.10.0 | never updated since 6.10.0: 7 cards sit in review · `autolaunch_max: 6` · 31 open cards |
| The Director | 6.7.1 | never updated: uncommitted edits inside the kit's own files · 13 open cards |
| polaris-testbed | 6.17.0 | the update itself is uncommitted (30 files, `publish: pr`) |

No project but this one has an `ops/LAYOUT.tsv`: the layout pass has never run anywhere else.

Why, in the kit (verify each before you carve):
- An update can end in exactly ONE next step, the layout pass (`update_hops_hint`,
  `kit/ops/lib/admin.sh:979`). Under `--auto` and `--all` it is a suffix on a line no agent acts on.
  The pass itself starts only at the end of a run or on an empty board (`ops/roles/TIDY.md` § Entry,
  `kit/ops/lib/handover.sh:388-402`); a project with cards always waiting may never reach either.
- Nothing after an update looks at speed. No step compares a project's settings with its own
  `speed` numbers, and nothing touches cards filed under the old 5-point rule: Sonoba's 72-card plan
  needed a hand-written note before anyone re-cut it.
- `update --auto` leaves silently when the board is busy (`cmd_update_auto`: "every early exit is a
  silent rc 0"). Cards parked in review for weeks keep an install frozen with no word to anyone.

## What gets built

### A. The three fixes (one card, about 5 points)
1. `index.py find --api` skips INDENTED shell definitions (nested helpers, awk functions inside
   quoted programs). Seven rows leave `ops/tests/api-kit.expected` — but that golden runs the
   INSTALLED `ops/index.py`, so those seven leave at the post-dogfood re-pin (release ritual), not in
   the card. Add a selfcheck fixture.
2. `CONDUCTOR.md` § 5 and `BUILDER.md`: a builder short exactly one unowned path returns
   `NEEDS PATH <path> — <why>` still claimed; the conductor runs `grant` and resumes the same builder.
3. `note <ID> -m "<line>"`: one Notes line on a CLAIMED card, in its own board commit; `BUILDER.md`
   and `SOLO.md` point at it for `assumed:` lines.

### B. `tune` — one report of what still slows THIS project
Read-only, no model, seconds. Prints a line only for what applies; each line is the finding plus the
one step that fixes it. Exit 0 = nothing to do, 1 = findings. It writes a small verdict cache
(`.polaris/tune-due`, same idea and shape as `.polaris/hops-due`) so `next`, `triage`, the
session-start line and `update` read the verdict for free and never recompute it.

Findings (each from data the project already has):
- `cards:` — per plan with open cards (ready + backlog): how many cards, the projected time
  (`speed --plan`), and how many sit in chains that fold into one chain card under the 6.17.0 rule
  (≤ 13 points, each step ≤ 5). Fix: `fold` (C).
- `layout:` — the layout pass is due (`.polaris/hops-due`). Fix: the pass in `TIDY.md`.
- `lanes:` — an explicit `autolaunch_max:` above the lane count `speed` measured as best here.
- `landing:` — `integration: paranoid` (the whole suite on every card) with the measured landing
  time it costs across the open cards; names `batch`.
- `checks:` — no `test_fast:` while the suite's measured time is over a few minutes.
- `behind:` — the installed kit is older than the channel's, and WHY the update has not happened
  (the first reason `board_quiescent` / `update_dirt_overlaps_kit` gives, with the age of the oldest
  card in review).
- `context:` — unused definitions under `~/.claude` over a threshold (`slim`'s own number).
Settings findings (`lanes`, `landing`, `checks`, `context`) are REPORTED, never applied: `tune` and
everything it triggers never edit `ops/CONVENTIONS.md`, `ops/RULES.tsv` or `~/.claude`. They go to
the owner as numbered proposals in the close, exactly like EVOLVE's ("reply approve <n>").

### C. `fold <ID> <ID>…` — a chain of waiting cards becomes ONE chain card, mechanically
No model. Refuses unless every card is open (ready/backlog, unclaimed), in the same plan, forms one
linear chain (each waits only on the one before it, or they share files and nothing else waits
between them), adds up to ≤ 13 points with each ≤ 5, and nothing in the group is `risk: high` unless
all are. The first card survives and becomes the chain card: `steps:` = one line per folded card
(its points and title), `points:` = the sum (a value the size rule accepts), `files_owned` and
`verify:` = the unions, `depends_on` = the union minus the folded IDs, the body keeps every folded
card's Why and Acceptance under a step heading. Every other card that waited on a folded ID now
waits on the survivor. The folded card files leave the board in the SAME single board commit
(`chore(board): fold <IDs> → <ID>`): nothing is lost (the text lives in the survivor, the originals
in board history) and one `git revert` of that commit on the board branch undoes it. A refusal
writes nothing. `tune`'s `cards:` line prints the exact `fold` commands.

### D. Every update and every install ends in the tune-up — and the next agent runs it
- A typed `update`: the last line names the tune-up (it replaces the layout-only line; layout is one
  of its findings): the agent reading it runs it now, in that chat.
- `update --auto` (session start) and `update --all`: the one line per project carries the count
  (`· tune-up due (3)`).
- `update --auto` stops being silent when an install is behind and blocked for more than a day: one
  line saying the version gap, what it is waiting on, and the step that frees it. It still never
  forces an update under cards that are building or waiting to land.
- `next` / `triage` send a session to the tune-up when the verdict says due and nothing is building
  or waiting to land — cards merely WAITING in ready/backlog must not hold it off (prove on a
  fixture board with waiting cards whether today's `tidy` hop fires; fix it if it does not). Once
  per session, as `tidy` is today. Keep the lane word `tidy` and `ops/roles/TIDY.md`; the role
  grows a first step: run `tune`, apply every `fold` it prints, then the layout pass, then return
  the settings findings as numbered proposals. `CLAUDE.md`'s lane row says what the lane now is.
- First install on an existing project and INIT on a new one end the same way: `tune`, then the
  pass. (A never-configured repo: the INIT epilogue still wins; INIT's last step is the tune-up.)
- Release words: `kit/ops/VERSION` 6.18.0, CHANGELOG entry (measured claims only), PROTOCOL command
  table, MANUAL (by-hand recipe for `note`, `fold`), help text.

## WON'T touch
`.github/` · any other project's files · `ops/CONVENTIONS.md` values of this or any repo · RULES
lines (none convert) · the hook guard · no new dependency · nothing is deleted from the repo (dead
files move to `archive/`).

## DONE looks like
- On a fixture project with a waiting 3-card chain, a due layout verdict and `integration:
  paranoid`: `tune` prints the three lines and exits 1; `fold` turns the chain into one card and
  `tune`'s `cards:` line goes away; a typed `update` ends by naming the tune-up; `next` hops to it
  with cards still waiting.
- The three fixes behave as the lessons report's diffs say.
- `bash ops/polaris finish` exits 0; release ritual complete (6.18.0 everywhere).
- After the release: `tune` run read-only in job, venzeti and polaris-testbed; its lines go in the
  close. No pass is run inside the owner's other projects from this chat.

## Assumed (owner away per `presence`; each is the recommended option)
- assumed: the tune-up never changes a project's own settings — it reports them as numbered
  proposals (EVOLVE.md already lists `integration` and `autolaunch_max` as never auto-applied).
- assumed: `fold` is applied by the tune-up pass without a question — it is lossless, board-only and
  one revert undoes it; it never touches a claimed card or one waiting to land.
- assumed: an update never runs under cards that are building or waiting to land; the install says
  so out loud instead of forcing it.
- assumed: the lane keeps its word, `tidy`; no new lane, no new role file.
- assumed: one release, 6.18.0, carries the three fixes and the tune-up.

## Hard-won rules for the cards (from plan `hour`)
- A card's `verify:` is its own checks only (`bash -n`, `check --only <golden>`,
  `doctor --selftest --only <label>`): never `tools/proof.sh`, never the full suite (Invariant 4).
- `ops/tests/api-kit.expected` moves on every new public name (a `cmd_*`, a KEYS row, a heading in a
  kit `.md`). Exactly one card per wave owns it, and it is named in the contract. `cli-help` is
  re-pinned after the dogfood, never in a card.
- Prefer few, larger cards: this kit's own numbers say a card costs about 36 minutes whatever its
  size. A chain is ONE chain card with `steps:`. Riders (version, changelog, help) are steps.
- Price the plan with `bash ops/polaris speed --plan tune <drafts>` before filing and return the
  `projected:` line verbatim.
