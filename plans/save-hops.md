# Save hops: POLARIS 6.12.0 — reviewed plan

## Context

**What you asked for.** You keep pasting one prompt into every project: "reorganize this so you
need fewer lookups". You want POLARIS to do it by itself. An update should trigger a layout review,
and the review should fix the layout. "Save hops, keep going to the end, spend few tokens" becomes
the core principle, for brand-new repos and for repos that already run POLARIS.

**What the review found.** The draft (`plans/i-keep-having-to-abstract-puzzle.md`) points the
right way, but checked against the kit's code it would not reliably deliver. There are four reasons:
1. **Its shortcut chain starts with pieces most repos never get.** The brain is opt-in, and nothing
   ever builds it. Folder guides load only when a file is *Read*, but builders start from `pack`,
   which is a shell command.
2. **Its trigger rarely fires for how you work.** It runs on a bare `start` with an empty board.
   You usually describe the work instead.
3. **Moving files safely needs more than the current import finder.** The finder misses `@/`
   aliases, Python `src/` layouts, and paths written in configs and docs. It also collides with the
   "ask before deleting any file" rule, the uncommitted update, and the harness baseline.
4. **Two shipping holes.** A new top-level `ops/hops.py` would never reach installed repos. And the
   proving ground repo is too small to exercise any of it.

**What "guarantee" means here.** No plan can promise that every move succeeds. This one makes
failure *safe*: a move that cannot be proven is skipped and recorded, never shipped broken. It also
makes the saving *measured*: a before/after score, plus a real lookup count from a benchmark.

**Your decisions.**
- Folder guides are per-folder `CLAUDE.md` files, and the root map goes into the repo's own
  `CLAUDE.md`.
- A quiet auto-update only flags the pass. A typed `update` offers it right away.
- **New: the flagged pass runs at the end of your next run.** It lands after your request and before
  the chat wraps up. A bare `start` on an empty board also runs it.
- Never stop mid-run. Every question is asked before work starts; after that you are assumed away.
- **New: proven moves don't ask.** A check proves the move changed nothing except imports and path
  mentions. Merging two files, where one disappears, still needs your yes up front.

## Gaps found → where each is fixed

**Both kinds of repo**
| # | Gap (evidence) | Fix |
|---|---|---|
| G1 | The brain is opt-in, and nothing in install, INIT, update or the hooks ever builds it. `brain_refresh_if_present` refreshes only one that already exists (`kit/ops/lib/knowledge.sh:297`, `ops/contracts/brain.md:50`). Without it, `pack` prints "(no brain yet — run: ops/polaris brain)" (`kit/ops/lib/builder.sh:786,810`). | §3 |
| G2 | Guides never reach builders. On-read loading was measured for `.claude/rules` (`plans/self-skills.md:119-120`). The kit already learned that "a lane that only CREATES files never sees it" (`builder.sh:845-849`). Builders start in `pack`/`show` (shell), as pinned-cwd subagents under `.polaris/wt/<ID>`, where loading has never been measured. | §0, §3 |
| G3 | The trigger misses described work. `triage <ID>` never routes to tidy, a bare `start` is rare, and `update --auto` is the usual update path. | §6 |
| G4 | `find --importers` misses most real imports. `resolve_import` (`kit/ops/index.py:351`) has no tsconfig/jsconfig `paths`/`baseUrl`, no Python `src/` root, and no Java or Go source roots. Paths in package.json, Dockerfile, CI and docs are not edges at all. (This also weakens the Planner's no-overlap proof today.) | §1 |
| G5 | "No logic changes while moving" is a promise, not a check. | §1 `--proof` |
| G6 | Moves collide with STOP-AND-ASK "Deleting any file": a move deletes the old path. `plan_covers` (`kit/ops/lib/ownership.sh:205`) gates `needs: [delete]`. | §5, §8 |
| G7 | Many repos have no `test:`/`build:`/`typecheck:`, so nothing would catch a broken move. | §5 step 4 |
| G8 | The harness baseline goes red on every move by design ("a module that DISAPPEARS is a failure", `kit/ops/lib/observe.sh:1428`). A blind `--refresh` would hide a real loss. | §5 step 7 |
| G9 | Public surface is not FIXED: package `main`/`exports`/`bin`, pyproject packages and entry points, Go/Java package paths, a library's top modules, and Unity `Resources/`, `StreamingAssets/`, `Editor/`, `Plugins/`, `.asmdef` boundaries. | §1 |
| G10 | The score can be gamed. "Folders per change" is minimized by one giant folder. | §1 guardrail |
| G11 | History alone is empty for young repos and for squashed imports (one big first commit is skipped as >40 files). | §1 import-graph signal |
| G12 | Guides go stale, or become a lock magnet. A guide that lists files must be owned by every task that adds a file, and parallel tasks collide. | §4 |
| G13 | "One fact, one home" (`kit/ops/roles/INIT.md:226`). A hand-written root map duplicates `MAP.md`, and an extra base commit breaks the quiet-board rule. | §3 `where` |
| G14 | Mid-run asks remain. CONDUCTOR step 6 asks "approve <ID>?" (`CONDUCTOR.md:237`). `next` prints `wait` while review/ holds only human-landable work (`kit/ops/lib/handover.sh:291`). | §7 |
| G15 | `finish` lists blocked IDs (`observe.sh:2759`) but not why each is blocked. | §7 |
| G16 | The pass's own token cost has no bound: writing guides could read the whole repo. | §1 `--facts`, §5 caps |
| G17 | It can loop: if every proposal is reverted, `--due` must not stay true. | §1 `--due` |
| G18 | Nested `CLAUDE.md` auto-loads only in Claude Code. | §3 (pack carries guides for any model), §4 (plain text) |

**Repos that already run POLARIS**
| # | Gap (evidence) | Fix |
|---|---|---|
| E1 | A new `kit/ops/hops.py` never ships. `install.sh` copies only `KIT_CODE` plus roles/templates/hooks/ci/lib (`kit/ops/install.sh:76,87`). | §1: lives in `index.py` |
| E2 | An update leaves the tree uncommitted: "nothing was committed for you" (`kit/ops/lib/admin.sh:619`), and `--auto` runs the same path. A tidy worktree cut from base lacks the new kit, and `land` would set the dirt aside. | §5 step 0 |
| E3 | Real repos already have human-written folder `CLAUDE.md`/`README.md`. | §4 marker block |
| E4 | Work in flight outside the board. `board_quiescent` ignores dirt (owner decision) and can't see unmerged branches or an open ship PR. | §5 step 0 |
| E5 | The old heal block ("Token efficiency — the first property", `admin.sh:863-891`) is appended once and never rewritten, so it would duplicate the new principle. | §8 |
| E6 | `doctor` will name the new `hops` key as absent everywhere, and KEYS.tsv order decides which six it names. | §6: append after `gallery` |
| E7 | Lane tables and the triage golden know only three words (`ops/tests/triage-lane.cmd`: `^(solo\|express\|full)$`). | §6, §9 |
| E8 | `ops/LAYOUT.tsv` would count as kit dirt and get set aside by update (`update_dirt_overlaps_kit`, `admin.sh:684-702`). | §2 |
| E9 | The proving ground can't exercise any of this: `Desktop\polaris-testbed` is 6.0.0 with 6 source files and 26 commits, so `--due` stays silent. | Verification |

**Brand-new repos**
| # | Gap (evidence) | Fix |
|---|---|---|
| N1 | Nothing tells the first Planner where new code goes. `PLANNER.md` step 3 only says "vertical slices inside ONE module". | §9 |
| N2 | INIT builds no brain and no root map. Greenfield `MAP.md` is "written from the interview" (`INIT.md:12`). | §9 |
| N3 | `hops` on an empty repo must be silent and cheap. | §1 `--due` |

## What ships

The Planner carves these into tasks with disjoint `files_owned`. Suggested waves: W0 §0 · W1 §1–§2 ·
W2 §3–§9 · W3 tests and release.

### 0. Probe first (W0, 1 pt): measure the premise, don't assume it
Reuse the T-150 recipe (`ops/contracts/self-skills.md:258`): headless `claude -p` runs in a
throwaway repo with `src/probe/CLAUDE.md` holding a token. Record a `probe:` line in
`ops/contracts/save-hops.md` for each case:
- fires on Read
- fires on Edit
- fires on create-only (Write)
- fires for an Agent-tool subagent
- fires on an absolute path under `.polaris/wt/<ID>/` from a primary-cwd session
- does NOT fire on Bash `cat`

Also record whether reading under `.polaris/wt/<ID>/` loads that worktree's root CLAUDE.md a
second time. If it does, that is an existing token cost: one IDEAS line, not this sprint.

The design does not depend on the results, because `pack` prints guides either way. The results
only decide what `CLAUDE.md` claims.

### 1. `polaris hops`: built inside `kit/ops/index.py`, not a new file
Fixes E1. `index.py` already ships, already sits behind the engine cache and the Windows-stub
defeat (`kit/ops/lib/search.sh:17-40`), and is already RULES-guarded as an installed copy. Dispatch
is `hops` added beside `find|show` in `index_fast` and the `kit/ops/polaris` fast path. It is
read-only, uses no LLM, and exits rc 3 (degrade quietly) with no python.

**Signals**
- **Co-change.** The last 300 non-merge changes on `<base>`. Skip commits over 40 files and
  board/`ops/`-only commits. `-M` maps old paths onto today's layout.
- **Static coupling** from the import graph (G11). This works with zero history.

**Score**
- Mean distinct folders per change, reported beside guide coverage.
- **Guardrail (G10):** never propose a move that grows a folder past 30 files. A folder over 40
  files is itself a SPLIT finding.

**Findings, on one screen of 40 lines or fewer**
- **MAP:** each folder's file count, purpose, and whether it has a guide.
- **SCATTER:** a cluster spanning 3 or more folders, with a suggested home.
- **MERGE:** files of 40 lines or fewer that change together.
- **SPLIT:** files of 600 lines or more whose changes pull in 4 or more unrelated folders.
- **GUIDES:** folders missing a guide.
- **STALE:** guides citing paths that no longer exist.

**FIXED (never proposed)**
- the draft's list (framework-routed folders, `ops/`, `.claude/`, `.github/`, RULES rows, SURFACES
  globs, keep rows, Unity `.meta` pairing)
- `generated:` globs, the `gallery:` dir, and the `VENDOR` patterns (`index.py:114`)
- **G9 public surface:** anything reachable from a published package's entry points (package.json
  not `private` with `main`/`exports`/`bin`; pyproject `[project]` packages and entry points);
  Go/Java package dirs; Unity `Resources/`, `StreamingAssets/`, `Editor/`, `Plugins/`, and moves
  across an `.asmdef`

**Resolver upgrade (G4).** Read tsconfig/jsconfig `compilerOptions.paths` and `baseUrl`, and try
Python `src/` roots. Path mentions in non-code files are found by searching the path *tail* (no
extension, no source root). Add selfcheck cases for each (`index.py:215`). This also makes
`--importers` sound for the Planner.

**Flags**
- `--score <moves.tsv>` — before/after, plus per-cluster lines such as "change checkout: 4 folders → 1".
- `--owned <moves.tsv>` — sources, destinations, importers, and files with path mentions.
- `--facts <dir>` (G16) — about 15 lines a guide is written from: top symbols, likely entry files
  (fan-in), co-change partners, tests. The agent writes guides from facts and never explores.
- `--questions` — at most 3 pick-one questions (merges, framework-looking folders) for the run's
  one up-front round.
- `--due` (G17, N3)
  - rc 0 with one line when the estimated saving is at least 15%, or when 3 or more folders with
    5 or more files have no guide; rc 1 and silent otherwise.
  - The saving is computed only after FIXED and keep rows are filtered out.
  - Silent within 30 changes of the last `hops-*` pass, and silent under 20 tracked files.
  - The verdict is cached in `.polaris/hops-due`, keyed on the base sha. `done`, `seal` and
    `update` write it; `next` and `triage` only read it, because `next` runs on the anchor
    hook's 10 s clock.
- `--proof <moves.tsv>` (G5, G6) — every changed line must be one of two kinds:
  - an import whose target resolves to the moved counterpart of its old target;
  - a line identical to the old one once old→new paths are substituted.

  Every deletion must belong to a planned move or merge. Anything else is red. A Java/Go `package`
  line change therefore fails, which is correct.
- `--tsv` — machine-readable output.

New contract: `ops/contracts/save-hops.md` (executable check = the drill in §10).

### 2. `ops/LAYOUT.tsv`: the layout record
- Columns: `path<TAB>verdict<TAB>why`, with verdicts `keep`, `moved`, `merged` or `split`.
- It is owner state: install and update never write it.
- Add it to the state exceptions in `update_dirt_overlaps_kit` (`admin.sh:695`), and to update's
  "untouched:" line (E8).
- `keep` covers framework conventions, "proof failed", "broke X", and "unsure — left for you".
- In-flight paths get no row; they are just retried next pass.

### 3. The shortcut chain, made real where agents actually start
- **Brain on by default (G1).** `heal` builds it when it is absent. `heal` already runs on every
  update (`admin.sh:589`), and INIT runs it too (§9). `pack` builds it once if it is still missing,
  instead of telling the agent to.
- **`pack` prints a FOLDER GUIDES section (G2, G18).** It shows the nearest guide block for each
  owned path's folder: at most 3 guides, 25 lines each. When there are none, the section is left
  out entirely, so the `pack-visual` golden stays byte-identical, the same pattern as SKILLS and
  SURFACES (`builder.sh:845-905`).
- **`brain_code_map`** takes a folder's purpose from the guide's first line, then from the README
  heading (`knowledge.sh:349`).
- **`polaris where [--write]` (G13).** It generates the ≤15-line root map, between
  `<!-- polaris:where -->` markers below the POLARIS END marker, from `MAP.md`'s Modules and Entry
  points plus each guide's purpose line. It is a projection, never a second source.
  - `done` refreshes it inside the one `docs(map)` commit it already makes for a `map_delta`
    (`kit/ops/lib/integrate.sh:242`), so there are zero new base commits.
  - TIDY and INIT write it the first time.
  - Uninstall strips it like the heal block.

### 4. Folder guides
New template `kit/ops/templates/FOLDER-CLAUDE.md`, 25 lines or fewer:
- the purpose line
- entry files
- "to do X, read Y first" for 2–4 common tasks
- what to leave alone
- this folder's conventions

**Stable knowledge only (G12).** Facts that change often (file lists, symbols) stay in the
generated code map, so adding a file never requires editing a guide.
- **Format (E3, G18):** plain Markdown, no POLARIS commands, so a guide still works after
  uninstall and for any agent or person. The content sits inside a
  `<!-- polaris:guide -->` block. An existing unmarked `CLAUDE.md` gets the block appended and is
  never rewritten.
- **Staleness:** `drift` reports `GUIDE STALE: <guide> cites <path> (missing)`, which the Planner
  reads first. `verify` prints a warning (it never blocks) when a task removes a cited path without
  owning the guide, the same way `map_delta_hint` does (`ownership.sh:85`).

### 5. The tidy lane: `kit/ops/roles/TIDY.md` (≤90 lines)
It runs in one context with no subagents. In a conductor run it is one subagent, spawned the way
SOLO is.

0. **Preconditions (E2, E4).**
   - Pending changes in the kit's paths from an update → commit them first as their own change,
     "POLARIS <old> → <new>".
   - Collect in-flight paths: dirty files, files touched by any local or remote branch with
     commits not in base, and files in an open ship PR. These are excluded this pass.
1. **Questions.** The run's one round already carried `hops --questions` (§7). No answers → safe
   defaults: skip the item, and add a keep row "unsure — left for you". Merges are skipped unless
   they got a yes.
2. **`hops`.** Print the map in chat. It is shown, not waited on.
3. **The proposal** goes to `.polaris/hops-plan.tsv`, then `hops --score`.
   - Caps: at most 25 moved files and 8 guides per pass; the rest wait for the next pass.
   - The run waits for a yes only under `autonomy: standard`.
4. **The proving check (G7).** Use the first green of `typecheck:` → `build:` → `test:`.
   - python/node with none of these: generate the harness import sweep (`polaris harness`, an
     existing feature) and use it.
   - No green check at all: no moves, guides only, plus one IDEAS line: "set test: or typecheck:
     to unlock moves". This is the outcome for most Unity repos.
5. **Author and claim one task.**
   - `files_owned` = `hops --owned`, plus the guides, `CLAUDE.md` and `ops/LAYOUT.tsv`.
   - `plan: hops-<version>`, sized at 5 points or fewer.
   - `verify:` = `hops --proof .polaris/hops-plan.tsv` plus the proving check.
   - `needs: [delete]` only when a merge was approved (G6). Proven moves are not deletes.
6. **Steps of 5 files or fewer.** Each step is:
   - `git mv`, with `.meta` sidecars;
   - fix the references: importers including aliases, plus path tails in configs and docs;
   - `hops --proof` for the step;
   - the proving check;
   - commit.

   A red step is reverted, gets a keep row with the reason, and the run continues. A step may go
   over 5 files only if the proposal listed it.
7. **Remap the harness baseline through the moves (G8)**, so a genuinely lost module still fails.
   Never use a blind `--refresh`.
8. **Finish the pass.**
   - Write the guides from `hops --facts`, then run `where --write` and update `LAYOUT.tsv`.
   - Run the full suite once.
   - Run `hops` again for the actual after-score.
   - Land through the normal path, then run `next`.
9. **Report:**
   - a before/after table;
   - "these tasks now take fewer lookups" (the per-cluster lines);
   - what was left for you.

### 6. Routing: when the pass runs
- **`next`, the end of every run (G3, your answer).** In `next_route` (`handover.sh:299`), before
  row 6 prints `finish`, print `tidy` when all of these hold:
  - the board is quiet;
  - the `.polaris/hops-due` verdict is due;
  - `hops:` is not `off`;
  - this session has not already run a pass.

  This hop happens at a boundary the board proves, so Invariant 5 holds and the hop is logged.
  After the pass lands, `next` → `finish`.
- **`triage`** (no IDs named, empty board, quiet, due) prints `tidy` at the empty-board branch
  (`observe.sh:2053`). Ready work always goes first.
- **Explicit `update`:** the epilogue ends with
  `▶ NEXT — save hops: read ops/roles/TIDY.md and run it now`, or "runs when your next piece of
  work wraps up" when the board is busy. There is never a second `▶ NEXT`; the never-set-up INIT
  epilogue wins.
- **`update --auto`:** keeps its one pinned line, plus the suffix `· layout pass due — runs when
  your next piece of work wraps up`. Amend `auto-update.md` to match.
- **The switch:** a `hops: on|off` row in `kit/ops/KEYS.tsv`, appended after `gallery` (E6). It
  defaults to on in code, and update never writes it.
- **Kept in step (E7):** the lane tables in `kit/CLAUDE.md`, `CONDUCTOR.md` step 2.5 and
  `SOLO.md`, plus the triage golden.

### 7. Ask first, then finish (never stop mid-run)
- **`CONDUCTOR.md` step 1:** one round with everything the run could need. Include
  `hops --questions` when the pass is due.
- **Step 5, a builder QUESTION:**
  - the question goes into the task's Notes;
  - `release --to blocked`, then `notify-gate question`;
  - the other lanes keep running.
- **Step 6, risk: high not covered by the plan (G14):** `notify-gate risk`; the task stays in
  review/ and goes to the close. Invariant 9 is unchanged.
- **Both steps, under `autonomy: standard`:** ask right away, as today.
- **`next`:** when the only thing in flight is `NX_REV_HUMAN`, print `finish`, not `wait`.
- **CONDUCTOR and SOLO:** when `finish` names only human-gated work, the run is over for you.
  Close with `⛔ waiting on you: approve <ID>`, with no 🎉 and no looping.
- **`SOLO.md` STOP-AND-ASK line:** anything found mid-run parks that piece; finish the rest.
- **`finish`:** extend the existing blocked caveat with each task's one-line reason, read from its
  blocked event (G15). No new block.
- **Docs:** `hands-free-knobs.md` v3 records the above. `PROTOCOL.md` gets `## SAVE HOPS` (the
  ladder, ask-first, the tidy lane), and the TOKEN DISCIPLINE opener points to it.

### 8. The principle, in `kit/CLAUDE.md` (the managed block reaches every repo on each update)
A new section near the top, 8 lines or fewer:
- **Fewest hops:** builders start with `pack`. Everyone else starts with the root map, which is
  already in context → `.polaris/brain/INDEX.md` → the folder's guide → `find`/`show` → Grep last.
- **A layout that makes you jump is a bug.** `hops` measures it, and the tidy lane fixes it.
- **Ask first, then finish.** One round before work starts. After that, safe defaults or a parked
  item, and the close lists what is waiting on the human.

Other edits:
- **STOP-AND-ASK:** "Deleting any file (a move proven by `hops --proof` is not a delete; a merge
  is)", and "ask before the run, never during — the plan names it, or it parks".
- **Lane table:** add a `tidy` row.
- **Heal text for new installs (E5):** trimmed to point at this section. Existing heal blocks
  belong to their owners and stay untouched.

### 9. Brand-new repos: tidy from day one
- **`INIT.md` step 3:**
  - run `polaris brain`;
  - `MAP.md` gets a `## Layout` line: "new code lives with its feature — UI, logic and tests in
    one folder — unless the framework routes by folder";
  - run `where --write`.
- **`PLANNER.md` step 3:** the same layout rule.
- **`PLANNER.md` step 5:** the task that creates a folder also owns that folder's guide. It is a
  new file, so there is no overlap. Set `map_delta` as today.
- **Result:** a brand-new repo never needs a big pass, and `--due` stays silent.

### 10. Tests
- **`index.py` selfcheck:** alias, `src/`-root and path-tail resolution (`ops/tests/index-selfcheck`).
- **A new drill, label `hops`**, under `kit/ops/lib/selftest/`. It uses a scripted fixture repo:
  a type-sorted layout, about 120 commits of feature work, `@/` aliases, and a test command. It
  checks:
  - scatter is detected;
  - FIXED, keep, RULES, SURFACES and public paths are never proposed;
  - `--score` drops after the projected moves;
  - `--due`: the exit code, keep filtering and the cooldown;
  - `--proof` passes a pure move and fails both a logic edit and a Java `package` change;
  - `triage` prints `tidy` only when the board is quiet and nothing is named;
  - `next` prints `tidy` once, before `finish`;
  - the update epilogue line and the `--auto` suffix;
  - `pack` shows FOLDER GUIDES when a guide exists and leaves the section out otherwise;
  - `heal` builds a missing brain;
  - the `where` refresh rides the single `docs(map)` commit (spine's QUIET MAP COUNT stays 1).
- **Goldens:** `cli-help`, `cli-help-parity`, `api-kit`, `triage-lane` (a new tidy case),
  PROTOCOL headings, `keys-drift`. New user-facing lines must pass `plain-voice`.
- **How tests run:**
  - `bash ops/polaris check` for fast checks.
  - The sharded suite runs in the background and is followed through its log (past the 600 s cap).
  - One serial run before tagging, because a sharded green is not a CI green.

### 11. Release 6.12.0
The release goes to all four places: `ops/VERSION`, `CHANGELOG`, the tag, and the published
release. Then `python kit/ops/pack.py --dogfood` and confirm with `polaris version`.

## Verification (end to end)
1. **The suite and goldens are green.** One serial selftest passes before the tag.
2. **The §0 probe lines** are recorded in `ops/contracts/save-hops.md`.
3. **Fixture run, for existing installs.** Use the drill's fixture repo, installed at 6.11.0:
   - `update` → 6.12.0;
   - make a small described change; after it lands, `next` says `tidy`;
   - TIDY commits the update, then runs to the end with nobody answering;
   - check: `--proof` and the proving check are green, guides, the root map and `LAYOUT.tsv`
     exist, the before/after score is printed, and the suite is green.
4. **Hop benchmark, the real measurement (run once, because it spends real tokens).**
   - Ask 5 fixed lookup questions ("where is the cart total computed? answer path:line") with
     `claude -p --output-format json` on the fixture, before and after the pass.
   - Record `num_turns` for each; the after numbers must be lower.
   - Keep it to 10 headless runs or fewer.
5. **Brand-new repo.** In an empty repo, run install → INIT → the first plan, then check:
   - the brain and the root map exist;
   - `MAP.md` has the layout line;
   - the first folder-creating task owns its guide;
   - `hops --due` is silent.
6. **`Desktop\polaris-testbed`, at 6.0.0.**
   - `update` reaches 6.12.0, and the brain gets built.
   - `doctor` names the `hops` key.
   - Nothing moves; the repo is too small, so silence is expected.
7. **`hops` on the POLARIS repo itself.** Its findings (for example `observe.sh` at 3,173 lines as a
   SPLIT) go into one IDEAS line. This repo is not restructured in this run.

## How it runs after you approve
- This chat becomes the CONDUCTOR, with both of your answers recorded. Nothing waits on you.
- This reviewed plan replaces the draft in `plans/`, and the draft moves to `archive/`.
- Commits and pushes are covered by the approval. Messages are plain and friendly, with no AI
  attribution.
- Your standing preference is saved to memory: ask everything up front, then never stop mid-run,
  because you may be away.

## Measurements
T-233 ran § 9 of `ops/contracts/save-hops.md` on 2026-11-05, on this machine: Claude Code 2.1.251,
Windows 11, from a builder subagent inside the Claude desktop app. The throwaway repo was built
exactly as § 9 says and committed before the first session: `.gitignore` (`.polaris/`) · `CLAUDE.md`
(`SH0-ROOT-LOADED`) · `src/probe/CLAUDE.md` (`SH0-GUIDE-FIRED`) · `src/probe/hello.txt` (`hello`);
then `git worktree add .polaris/wt/T-1 -b feat/T-1`, with that branch's root `CLAUDE.md` changed to
`SH0-WTROOT-LOADED` and its `src/probe/CLAUDE.md` to `SH0-WTGUIDE-FIRED`, committed. Nothing under
`~/.claude/` mentions `SH0-`. Each session: `env -u CLAUDECODE timeout 90 claude -p '<prompt>'
--max-turns <n> --output-format text [--allowedTools <tools>] </dev/null`, cwd = the repo's primary.

No session reached the model. All seven stopped at sign-in after 5-6 s with `Failed to
authenticate: OAuth session expired and could not be refreshed` (rc 1), so every answer is an
honest unknown:

probe: guide-fires-on-read: unknown
probe: guide-fires-on-edit: unknown
probe: guide-fires-on-write-new: unknown
probe: guide-fires-in-subagent: unknown
probe: guide-fires-via-worktree-abspath: unknown
probe: guide-silent-on-bash-cat: unknown
probe: worktree-root-claudemd-reloads: unknown

Why, and how to get real answers: the network was fine (`api.anthropic.com` answered 405), and A
failed the same way when re-run with all 34 `CLAUDE*` variables the desktop app hands its children
unset as well. So the recipe is not the problem: the command-line tool's own sign-in has lapsed (its
saved sign-in file was last written 2026-10-13). Sign it in again (`claude` in a terminal, then
`/login`) and the same seven commands answer these lines. Until then `bash ops/bench.sh hops` (§ 10
of the contract) fails the same way, because it starts sessions the same way. One more snag for a
re-run: the checkout guard refuses `git worktree add` in any main checkout, a throwaway one
included, so the repo setup has to run from a script.

Seen directly, and NOT a probe value (this builder's own context: an Agent-tool subagent whose cwd
is this repo's primary, working by absolute paths under `.polaris/wt/T-233/`): its first Read of a
file under that worktree pulled in the worktree's root `CLAUDE.md` in full (about 11 KB), a second
copy of the root file it had already been given at start, while its earlier Bash `grep`/`sed` reads
of the same worktree's files pulled in nothing. That is the effect `worktree-root-claudemd-reloads`
asks about, plus silence for Bash reads; only a re-run of the seven sessions may record either.

Raw replies, verbatim stdout. stderr was the same two `Permission allow rule (…settings.json) … has
a wildcard` warnings (A-D) or empty (E-G and A′). `<TAIL>` = `Then reply with every token in your
context that starts with SH0-, one per line, or NONE.` `<repo>` = the throwaway repo's absolute path.

```
A  rc 1 · 5 s · --max-turns 1 · no --allowedTools
   prompt: Do not read any file and do not use any tool. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

B  rc 1 · 6 s · --max-turns 6 --allowedTools Read
   prompt: Use the Read tool on src/probe/hello.txt and read nothing else. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

C  rc 1 · 5 s · --max-turns 6 --allowedTools Read,Edit
   prompt: Use the Edit tool to append the line "probe" to src/probe/hello.txt, and read no other file. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

D  rc 1 · 6 s · --max-turns 6 --allowedTools Write
   prompt: Use the Write tool to create the NEW file src/probe/new.txt containing the line "new", without reading any file first. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

E  rc 1 · 5 s · --max-turns 6 --allowedTools Agent,Task,Read
   prompt: Do not read any file yourself. Use the Agent tool to start one subagent with exactly this prompt: "Use the Read tool on src/probe/hello.txt and read nothing else. <TAIL>" When it returns, print the line SUBAGENT REPLY: followed by its reply verbatim. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

F  rc 1 · 6 s · --max-turns 6 --allowedTools Read · cwd = the primary
   prompt: Use the Read tool on the absolute path <repo>\.polaris\wt\T-1\src\probe\hello.txt and read nothing else. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

G  rc 1 · 6 s · --max-turns 6 --allowedTools Bash
   prompt: Use the Bash tool to run exactly `cat src/probe/hello.txt` and nothing else; do not use the Read tool. <TAIL>
Failed to authenticate: OAuth session expired and could not be refreshed

A′ (A's exact command, every CLAUDE* variable unset: the check above)   rc 1 · 6 s
Failed to authenticate: OAuth session expired and could not be refreshed
```
