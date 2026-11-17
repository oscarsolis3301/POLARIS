# The smooth run (kit 6.19.0) — plan slug `smooth`

## The owner's words (2026-11-17)
"install it onto SONOBA once you finish and MONITOR their work/speed/effeciency to fill in gaps and
holes and errors and issues for the following update as well to make it even more effecient, even
less hops, smoother" — and, asked "Build the next update from the 18 gaps now?": "Yes, build it".

## Where the gaps come from
Eighteen lines on `ops/board/backlog/IDEAS.md`, all dated 2026-11-17, added in board commits 37f05b6
(sixteen) and 980ddbd (two). Read them there — they are the scope, with their measured costs. Twelve
are from Sonoba's run on kit 6.17.0 (its board log on GitHub plus its conductor's written answers);
six are from this repo's own 6.18.0/6.18.1 run. Sonoba measured on 6.17.0: 71 points landed in 2.6 h
(27 an hour), build median 28 min, finished → landed 3 min.

## What gets built, in order of measured cost

### A. A card owns its tests before it starts (24 of Sonoba's 27 grants; 25–40 min each)
The builder found the reds 40–50 minutes in, stopped, was granted the test file, re-pinned, re-ran.
- `new` puts on `files_owned`, by itself, the tests `ops/SURFACES.tsv` maps to every path the card
  owns. An overlap with another open card is sequenced by the ready gate exactly as today.
- `new` and `pack` also list the test files that NAME one of the card's owned files (a plain search
  of the project's test roots for each owned file's name and, for a file the card replaces, the
  name it replaces) and are not on the card. `new` prints them as one advisory block; `pack` prints
  them as the first thing a builder reads; `BUILDER.md` says: any listed test you will have to
  touch → return `NEEDS PATH` in the first minute, not after the build.
- No model, no project-specific rule in the kit. A project that wants more declares it in
  `ops/SURFACES.tsv`, which already exists for this.

### B. A wave's reds show up in that wave (Sonoba: two cards landed 5 failing tests unseen)
Under `push: end` nothing runs more than a card's own filters until `finish`. Invariant 4 already
says "the full suite runs once per wave". FIRST establish from the code what the seal runs today
under `landing: self` (kit/ops/lib/integrate.sh around the `depth_for` / `test_select` block, and
whatever seal-on-demand from 6.17.0 skips) and why a project with only `test:` set got nothing.
Then make the invariant true: when a wave seals, the tests covering what the wave changed run once,
under the heavy slot — every SURFACES row the wave's diff touches, or the whole `test:` when no row
covers a changed path. A red there keeps the wave open and names the card(s) whose paths the
failing row covers. It must cost at most one run per wave and nothing per card.

### C. Re-cutting a filed plan is commands, not hand edits (124 hand board edits; 78 cards parked in blocked/)
- `retire <old…> --by <new> -m why` (also `--map <file>` of `old<TAB>new` lines): one board commit;
  each old card leaves the queue with a Notes line naming its successor; every `depends_on` naming
  it is rewritten to the successor (dropped when the dependent IS the successor). Retired cards must
  stop showing as "blocked — needs regroom": pick the smallest mechanism that keeps `blocked/`
  meaningful (a `retired/` folder beside the board's others, read by nothing but `status --all`, is
  the default; say what you chose and what else had to learn about it).
- `new` sorts its drafts by `depends_on` itself (it refused T-1142 because T-1144 came later).
- `new` does not chain a draft to a card that the same call retires (`new --retire <map>` or
  `retire` first in the same commit — your call).
- `amend <ID> --deps +X` / `--deps -X` for a waiting or claimed card, with the why on the record.
- `release --to blocked` (and `--to backlog`) works on an UNCLAIMED ready card, and `release`
  removes the card's `feat/<ID>` branch itself when it holds no commits.

### D. Smaller hops and wrong answers
- `grant` refuses when run from the card's own worktree or on its `feat/<ID>` branch, exactly as
  `amend` and `approve` do. `NEEDS PATH` (6.18.0) is the route. (Seen at Sonoba, and here: a SOLO
  granted itself two test paths on T-311.) SOLO.md says what a lone session does instead.
- `next` never tells a conductor "resume <ID>: your own lock is live" for a card a subagent holds:
  the lock records the worktree, and `next` answers for the caller's own folder.
- `approve --plan <slug>` makes that plan the run's plan, so `drain: plan` stops holding its cards
  as "not this run's".
- `handoff --hold`: stop at review/ (no land, no seal) — for a `risk: high` card waiting on a yes.
- `handoff --no-before` asks for no screenshot at all when the diff touches no `visual:` path.
- `next` and `triage`: a verdict cache naming another commit means "recompute", never "nothing due".
- `update --all` (a typed command) asks the channel itself; `--auto` re-asks when the cached answer
  equals the installed version and is over an hour old. (6.18.1 came out hours after 6.18.0 and two
  projects answered "up to date (6.18.0)" until the cache file was removed by hand.)
- `update --all` treats two registry paths that differ only by drive-letter case as one, skips a
  worktree of a listed project, and drops an entry with no `ops/VERSION`.
- A project that never commits an update itself (`publish: pr`) is no longer frozen by its own
  pending update: the next update recognises the kit's own uncommitted files and goes on top. If
  you cannot tell the kit's own pending files from a person's edits with certainty, park THIS item
  as a `spike` card and carve the rest.
- `tools/proof.sh --await <job>`: a job GitHub cancelled is "cancelled — no answer", not RED, and
  the wait falls back to the push run of the same commit.
- `speed --plan` prices a chain card from its steps (or points), and prints the release checks as
  their own line when the project's history has them (here: two full checks of about 22 min and a
  macOS wait per release). Last plan: priced 24 min, the longer card took 42.
- Release words: `kit/ops/VERSION` 6.19.0, CHANGELOG (measured claims only), PROTOCOL command
  table, MANUAL by-hand recipes for every new verb or flag, help text.

## WON'T touch
`.github/` · any other project's files · `ops/CONVENTIONS.md` values · RULES lines (none convert) ·
no new dependency · nothing deleted from the repo. `renumber` (migration-number shifts) is
project-specific and stays out; leave its idea line where it is.

## DONE looks like
- Fixture proofs, one per section: a card filed with an owned source gets its mapped test on
  `files_owned`, and `pack` lists a test that names its file; a wave whose joined tree fails a
  mapped test does not seal and names the card; `retire` rewires a dependent in one commit and
  `status` no longer lists the retired card as blocked; `grant` refuses from the card's worktree;
  a stale verdict makes `next` recompute; `update --all` sees a same-day release.
- `bash ops/polaris finish` exits 0; release ritual complete (6.19.0 everywhere).
- After the release: job and venzeti updated from here; the Sonoba session told.

## Assumed (owner away per `presence`; each is the recommended option)
- assumed: all eighteen gaps go in ONE release, as the owner decided for plans over the hour.
- assumed: tests named by a card's files are LISTED, not auto-owned — auto-owning a search hit
  could chain cards that have nothing to do with each other; SURFACES-mapped tests are auto-owned.
- assumed: the wave check runs the tests covering what the wave changed, not always the whole
  suite; the whole suite still runs at `finish`.
- assumed: a retired card is kept (moved, with its text), never deleted.
- assumed: `grant` refusing on a builder's own card is right even for SOLO — a lone session hands
  the card back naming the path, as BUILDER.md already says for "alone".

## Hard-won rules for the cards
- Few, large chain cards with `steps:` — this kit's last two 13-point cards took 23 and 42 minutes.
  Disjoint files; exactly one card owns `kit/ops/polaris` (dispatch + help) and exactly one owns
  `ops/tests/api-kit.expected`; `cli-help` is re-pinned after the dogfood, never in a card.
- NO seam between side-by-side cards that only shows on the joined tree: last plan a golden that
  runs the real `heal` went red only after both cards landed. If two cards meet at a file or a
  verdict, name in the contract which goldens run the real thing, and give ONE card the job of
  running them on the joined tree as its last step (it depends on the other), or chain them.
- A card's `verify:` is its own checks (`bash -n`, `check --only <goldens>`, `doctor --fast`):
  never `tools/proof.sh` or the full suite. A self-test drill that takes over ten minutes
  (`autoupdate` takes 16 here) is run by hand in the background by the builder that changes it and
  reported — and any change to the session-start line, the registry walk or `update --auto` MUST
  run that drill before handoff: CI runs it serially and it went red last time.
- New helpers `_`-prefixed; no fixed sleeps in goldens; pipe python output through `tr -d '\r'`.
- Price the plan with `bash ops/polaris speed --plan smooth <drafts>` and return its `projected:`
  line verbatim.
