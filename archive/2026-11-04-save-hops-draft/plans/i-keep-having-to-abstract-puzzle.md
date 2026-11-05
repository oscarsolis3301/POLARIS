# Save hops: POLARIS 6.12.0

## Context

**The problem.** You paste the same "reorganize this project so you need fewer lookups" prompt into
every project. You want POLARIS to do it on its own: an update should trigger a layout review, and
the review should restructure the repo. "Save hops, keep going to the end, spend few tokens" should
be POLARIS's core principle.

**What already exists (reuse it, don't rebuild it).** POLARIS can already help an agent find its
way around a repo as the repo stands today:
- `.polaris/brain/` gives a 4-hop guarantee (`kit/ops/lib/knowledge.sh`, `brain_code_map` / `brain_index`).
- `find`, `show`, `--importers` and `--imports` come from `kit/ops/index.py`. The import graph is the
  same one the Planner uses to prove that task file sets don't overlap.
- `pack`, `ops/MAP.md` and `harness` (import, route and entry sweeps).
- `board_quiescent` (`kit/ops/lib/admin.sh:654`).
- The marker-guarded CLAUDE.md refresh on update (`kit/ops/install.sh:205`).
- `approve --plan` (one yes covers the whole plan) and `builder_questions: default-safe`.

**What's missing.**
- Nothing measures the repo's own layout or fixes it.
- Nothing puts a "read this first" guide where the agent actually lands.
- The conductor still asks the human in the middle of a run (`CONDUCTOR.md` step 5: "ask the human
  right away").

**Your decisions.**
- Each folder gets its own guide as a **per-folder `CLAUDE.md`**. Claude loads it automatically,
  so it costs zero lookups.
- **A quiet auto-update only flags the pass.** It runs at your next `start`. A typed `update` runs
  it right away.
- **Never stop mid-run.** Every question is asked before work starts, and you are assumed to be away
  after that.

## The principle, written into `kit/CLAUDE.md`

This goes in a new section near the top, kept to 8 lines or fewer, because the file is injected
into every context:

> ## THE CORE PRINCIPLE — save hops, ask first, then finish
> Every file read, search and tool call is a hop, and every hop is the owner's money.
> - **Fewest hops to the answer:** `pack` → `.polaris/brain/INDEX.md` → the folder's own CLAUDE.md
>   (loads itself) → `find`/`show` → Grep last.
> - **A layout that makes you jump is a bug.** `polaris hops` measures it; the `tidy` lane fixes it.
> - **Ask first, then finish.** Every question the run could need goes in ONE round before work
>   starts. After the go, assume the human has walked away. An open question becomes either a safe
>   default (noted) or a parked item. Everything else runs to the end, and the final report lists
>   what is waiting on them.

The STOP-AND-ASK block gets one rewording: "ask before the run, never during — the plan names it, or
it parks."

## What ships

The Planner turns these into board tasks with disjoint `files_owned`.

### 1. `polaris hops`: the layout audit
New file `kit/ops/hops.py`, dispatched through the existing python shim in `kit/ops/lib/search.sh`
the same way `find` is. It is read-only and uses no LLM. With no python it exits rc 3 and degrades
gracefully, the same way `find` does.

**The score is mean distinct folders per change.** The data is the last 300 non-merge changes on
`<base>`:
- Skip bulk commits that touch more than 40 files, and commits that only touch the board or `ops/`.
- Rename detection (`-M`) maps old paths onto today's layout. Because of that, the same history
  scores both "before" and "after".

**Findings, shown on one screen of 40 lines or fewer:**
- **MAP:** each top-level folder with its file count, a one-line purpose, and whether it has a guide.
- **SCATTER:** clusters of files that change together across 3 or more folders. These are the
  "features you had to jump around for". Each one gets a suggested home.
- **MERGE:** tiny files (40 lines or fewer) that are almost always changed together.
- **SPLIT:** big files (600 lines or more) whose changes pull in 4 or more unrelated folders.
- **GUIDES:** major folders with no `CLAUDE.md`, and guides that cite paths that no longer exist.
- **FIXED, never proposed for a move:**
  - Framework-routed folders: `app/`, `pages/`, `routes/`, `migrations/`, `public/`, `static/`,
    `.github/`, `ops/`, `.claude/`, and generated or vendored dirs from MAP.
  - `RULES.tsv` path and ask rows.
  - `SURFACES.tsv` rows. A file covered by one may move only within that row's glob.
  - `ops/LAYOUT.tsv` keep rows.
  - Unity `Assets/` files may move only together with their `.meta` file.

**Flags:**
- `--score <moves.tsv>`: before/after score, plus a per-cluster line such as "change checkout:
  4 folders → 1".
- `--owned <moves.tsv>`: the files the pass will touch, meaning sources, destinations and
  importers (from index.db).
- `--due`: rc 0 with one line when the estimated saving is at least 15% or 3 or more guides are
  missing. Otherwise rc 1 and silent.
- `--tsv`: machine-readable output.

**New contract:** `ops/contracts/save-hops.md`.

### 2. `ops/LAYOUT.tsv`: the layout record
Columns are `path<TAB>verdict<TAB>why`, where the verdict is `keep`, `moved`, `merged` or `split`.
- It is owner state like `RULES.tsv`. The tidy pass creates it, and install and update never
  overwrite it.
- A `keep` row stops `hops` from proposing that path again. This covers framework conventions,
  "tried it, it broke X", and "unsure, left for you".

### 3. Folder guides
New template `kit/ops/templates/FOLDER-CLAUDE.md`, 25 lines or fewer:
- the purpose line
- entry points
- "to do X, read Y first"
- what to leave alone
- "update this when you move files here"

`brain_code_map` (`knowledge.sh`) takes a folder's purpose from the first line of its guide when one
exists.

The root map goes into the repo's own `CLAUDE.md`, below the POLARIS END marker, inside a
`polaris:where` marker pair: 15 lines or fewer covering the top-level map and the first file to
read for each common task. Later passes refresh only what is between the markers, so your own
writing is never touched.

### 4. The `tidy` lane: new role file `kit/ops/roles/TIDY.md` (≤90 lines)
This turns your pasted prompt into a procedure, with your answers applied. It runs in one context,
with no subagents, on a quiet board.
1. **Questions first.** If anything really needs the human (a framework-looking folder, a merge
   that removes a file), ask ONE round now, while they are still there. With nobody there, use the
   safe default: skip the move and add a `keep` row marked "unsure — left for you".
2. **`polaris hops`.** Print the map in chat. This is shown, not waited on.
3. **The proposal.** Write the moves, merges, splits and guides to `.polaris/hops-plan.tsv`, then
   run `hops --score` to show the predicted before and after. The run waits for a yes only under
   `autonomy: standard`, which is the existing knob.
4. **Author and claim one board task.** Its `files_owned` is `hops --owned`, its `plan:` slug is
   `hops-<version>`, and it is sized to 5 points or fewer. Findings that don't fit wait for the next
   pass. A file discovered later is added with `polaris grant`.
5. **Steps of 5 files or fewer where possible.** Each step is:
   - `git mv`, carrying `.meta` sidecars along;
   - fix references with `find --importers` / `find -t <old path>`, with no logic changes;
   - run the smallest check (harness import sweep, build, or the moved files' tests);
   - commit.

   A red step is reverted, gets a `keep` row ("broke X"), and the run continues. It never stops.
6. **Write the guides and the root `polaris:where` section.** Then run the full suite once, run
   `hops` again for the actual after-score, update `LAYOUT.tsv`, land the change, and run `finish`.
7. **Report:** a before/after table, which tasks now take fewer lookups (from the per-cluster
   lines), and what was left for the human.

### 5. Routing: when the pass runs
- **`triage`** (`kit/ops/lib/observe.sh`) prints a 4th lane word, `tidy`, but only when all of
  these hold:
  - no IDs were named, so a work request is never hijacked;
  - the board is quiet (`board_quiescent`);
  - `hops --due`;
  - `hops:` is not `off`.

  Ready work always goes first. `kit/CLAUDE.md` gains a `tidy` row in the lane table.
- **An explicit `update`** (`admin.sh` epilogue) runs `hops --due`. If the pass is due and the board
  is quiet, it prints a final `▶ NEXT — save hops: … read ops/roles/TIDY.md and run it now` line.
  If the board is busy, it prints "runs at your next start" instead.
- **`update --auto`** keeps its one pinned line and adds the suffix
  `· layout pass due — runs at your next start`. The contract `auto-update.md` is amended to match.
- **The off switch:** a new `KEYS.tsv` row, `hops: on|off`. It defaults to on in code, and update
  never writes it.

### 6. Never stop mid-run
- **`CONDUCTOR.md` step 1:** "everything the run could need, ask here, in one round".
- **`CONDUCTOR.md` step 5:** when a builder returns a QUESTION:
  - the question goes into the task's Notes;
  - run `release --to blocked`, then `notify-gate question`;
  - the other lanes keep running;
  - under `autonomy: standard`, the conductor still asks right away, as it does today.
- **`SOLO.md` STOP-AND-ASK line:** something found mid-run parks the piece and the run finishes the
  rest.
- **`hands-free-knobs.md` v3:** documents the question handling above.
- **`finish`** (`observe.sh`) ends with a `waiting on you:` block: each task parked this run, with
  its one-line reason. Add this only if `finish` doesn't already print it.
- **`PROTOCOL.md`:** a new `## SAVE HOPS` section with the hop ladder, ask-first-then-finish, and
  the tidy lane. The TOKEN DISCIPLINE opener points to it.

### 7. Tests
- **New selftest shard** `kit/ops/lib/selftest/hops.sh`. It builds a throwaway repo with a scripted
  history and checks:
  - scatter is detected;
  - keep, RULES and SURFACES paths are never proposed;
  - `--score` drops after the projected moves;
  - `--due` returns the right exit code;
  - `triage` prints `tidy` only on a quiet board with nothing named;
  - the update epilogue line appears.
- **Goldens to refresh:** `cli-help`, `cli-help-parity`, `api-kit`, and the PROTOCOL headings golden.
- **Fast checks:** `bash ops/polaris check`.
- **The sharded suite** runs in the background and is followed through its log, because it is
  longer than the 600-second tool limit.

### 8. Release 6.12.0
The release goes to all four places: `ops/VERSION`, `CHANGELOG`, the git tag, and the published
release. Then `python kit/ops/pack.py --dogfood` and confirm with `polaris version`.

## Verification (end to end)
1. **The suite and goldens are green.** Run the selftest serially once before tagging, since a
   sharded green is not a CI green.
2. **Run `hops` on the POLARIS repo itself.** Its findings (for example, `observe.sh` at 3,173 lines
   is a likely SPLIT) go in one IDEAS.md line as the next sprint's input. This repo is not
   restructured in this run.
3. **Proving ground** `Desktop\polaris-testbed`:
   - `update` prints the save-hops line;
   - `start` makes `triage` print `tidy`;
   - the TIDY pass runs to the end with nobody answering;
   - the before/after score is printed, the folder `CLAUDE.md` guides exist, and the suite is green.

## How it runs after you approve
- This chat becomes the CONDUCTOR (per `CLAUDE.md`). Everything has been asked already, so nothing
  waits on you.
- Commits and pushes are covered by the approval.
- Commit messages are plain and friendly, with no AI attribution.
- Your standing preference is saved to memory: ask everything up front, then never stop mid-run,
  because you may be away.
