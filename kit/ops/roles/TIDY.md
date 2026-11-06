# ROLE: TIDY — the layout pass: proven moves, folder guides, one context
You make this repo cheaper to work in: fewer folders opened per change, a guide in each busy folder.
You move only what `hops --proof` shows changed nothing but paths, and the pass lands as ONE task.
Nobody is watching: what you cannot prove or decide becomes a keep row in `ops/LAYOUT.tsv` and a
line in your report — never a question mid-pass, never a stop. A merge (one file folds into another
and disappears) needs the human's yes from before the run; a proven move is not a delete.

## Entry — who sends you here
- **`next` or the Stop hook, at the end of a run** — a board-proven hop: use only the answers the
  run already has.
- **`triage` on an empty board** — you are the whole run: ask `bash ops/polaris hops --questions`
  once, NOW, before any work. That is the run's one round; after it the owner is away.
- **A conductor's TIDY subagent** — its kickoff carries the up-front answers; ask nothing. Your
  report is your close: never `next` or `finish`. Subagents share the conductor's session, so the
  run's one tidy hop is spent and the conductor's own `next` and `finish` take it from there.
- **The explicit `update` epilogue** — `▶ NEXT — save hops: read ops/roles/TIDY.md and run it now`.

One context, no subagents. `hops: off` in `ops/CONVENTIONS.md` → stop: one line saying so, nothing
else. Long command? `ops/PROTOCOL.md` § LONG COMMANDS; never end a turn with a job still running.

## The pass
0. **The update first.** `ops/VERSION` changed but uncommitted in the primary checkout = an update is
   pending: commit the kit's files FIRST, as their own change on `<base>`, named from
   `git diff ops/VERSION`: `chore(polaris): POLARIS <old> → <new>` — `ops/` minus the repo's own
   records (board, contracts, tests, CONVENTIONS, MAP, SPRINT, RULES, LAYOUT, ROADMAP), plus
   `CLAUDE.md`, `.gitignore`, `.gitattributes` and the kit's `.claude/` pieces; never anyone's other
   work. Work in flight elsewhere (dirty files, unmerged branches, an open PR) `hops` leaves out by
   itself; `git fetch --quiet` first when an `origin` exists.
1. **Questions — only answers the run already has.** A merge needs a yes; a `keep` answer is a keep
   row `framework convention`. Anything unanswered gets the safe default: skip the item, keep row
   `unsure — left for you`.
2. **`bash ops/polaris hops`** — print the map in chat; shown, never waited on. Its line 1 is the
   before-score.
3. **The proposal.** The `MOVE` rows of `bash ops/polaris hops --tsv`, in order, become
   `.polaris/hops-plan.tsv` rows `move<TAB><from><TAB><to>` — at most 25 moved files and 8 guides
   (picked after the moves, step 8) per pass; the rest wait for the next one. An approved merge adds
   `merge<TAB><from><TAB><into>`. Files only, never a `.meta` (it travels with its asset). Then
   `bash ops/polaris hops --score .polaris/hops-plan.tsv`. Wait for a yes only under
   `autonomy: standard`, and only where you can ask.
4. **The proving check.** On the untouched tree: the first of `typecheck:` → `build:` → `test:`
   (`ops/CONVENTIONS.md`) that is set and green. None, in a python or node repo →
   `bash ops/polaris harness`, and the run line it prints is the check. No green check at all → no
   moves, guides only, and ONE `ops/board/backlog/IDEAS.md` line: `set test: or typecheck: to unlock moves`
   (most Unity repos end here).
5. **One task**, authored exactly as SOLO.md step 1, minus its `triage` confirm (this lane is
   chosen): `files_owned` = what `bash ops/polaris hops --owned .polaris/hops-plan.tsv` prints + each
   guide step 8 may write (`<dir>/CLAUDE.md`, every `to` folder too) + `CLAUDE.md` + `ops/LAYOUT.tsv` ·
   `plan: hops-<version>` (`version:` in `ops/VERSION`) · ≤ 5 points · `risk: normal` · `verify:` =
   `bash ops/polaris hops --proof .polaris/hops-plan.tsv` + the proving check · `needs: [delete]`
   ONLY for an approved merge — then, before the claim, record the human's up-front yes:
   `bash ops/polaris approve --plan hops-<version> -m "<their answer, quoted>"`. Claim; work in the
   worktree (SOLO.md step 2b). Set the proposal aside as `.polaris/hops-proposal.tsv`: from here the
   plan file holds only the rows of the steps made so far. Both live in the primary's `.polaris/` —
   edit them there, by full path, even from the worktree.
6. **Steps of ≤ 5 files**, in proposal order. Each: add its rows to the plan file · `git mv` (+ each
   `.meta`) · fix every importer `bash ops/polaris find --importers <from>` lists (aliases too) and
   the path tails in configs and docs · `bash ops/polaris hops --proof .polaris/hops-plan.tsv` · the
   proving check · commit. A red step: `git reset --hard HEAD` inside the worktree, a keep row with
   the reason, noted for step 8 (`proof failed: <reason>` · `broke <check>: <first line>`), drop its
   rows from the plan file, continue. A step passes 5 files only when the proposal listed it.
7. **`bash ops/polaris hops --remap .polaris/hops-plan.tsv`** — the harness baseline follows the
   moves, so a module that truly vanished still fails. Never `harness --refresh`.
8. **Guides, map, record, suite, land.**
   - Guides: the first 8 `GUIDES` rows of `POLARIS_ROOT=<task worktree> bash ops/polaris hops --tsv`,
     new folders too. Each: `POLARIS_ROOT=<task worktree> bash ops/polaris hops --facts <dir>`, then
     `ops/templates/FOLDER-CLAUDE.md` filled from those facts alone, never by exploring — stable
     knowledge in plain Markdown, no POLARIS command, no file inventories or symbols (the code map
     keeps those). A folder `CLAUDE.md` without the `<!-- polaris:guide -->` line gets the block
     appended after one blank line; the human's text is never rewritten.
   - `git add` the guides, THEN `bash ops/polaris where --write` (it lists tracked guides only).
   - `ops/LAYOUT.tsv`: a new file's first line is exactly
     `# path<TAB>verdict<TAB>why — the layout record; polaris hops never proposes a keep row`; then
     `<old path><TAB>moved<TAB>→ <new path> · hops-<version>` per move (`merged` for a merge) and
     `<path><TAB>keep<TAB><why>` per noted keep row — in-flight paths get none. Commit.
   - The full suite once, when `test:` is set: `bash ops/polaris bg run test`, then
     `bash ops/polaris bg wait test` until the rc is not 2. Red → `git revert --no-edit` the move
     commits, their rows become keep rows `broke test: <first line>` (guides citing them follow), and
     run it again.
   - `bash ops/polaris hops` again for the after-score — with `--score .polaris/hops-plan.tsv`, since
     bare `hops` reads the primary checkout, which has not moved yet.
   - Land exactly as SOLO.md steps 4–6. Top-level: `bash ops/polaris next`, and follow it.

## Report
In the repo's `voice:` — outcomes, not tooling. Conductor-entered, this is your whole result.
- **Before → after**, a small table: folders per change (step 2's line 1 → the after-score) and
  guides (`<g>/<G>` → with yours added); then what moved, each `from → to`.
- **These tasks now take fewer lookups** — the final `--score`'s `change <name>: <k> folders → <k2>`
  lines, one per feature.
- **Left for you** — every keep row `unsure — left for you`, each merge not made, and the IDEAS line
  if you wrote it. None of it stopped the pass; each is one answer for the next run's round.
