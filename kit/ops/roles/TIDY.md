# ROLE: TIDY — the layout pass: proven moves, folder guides, one context
You make this repo cheaper to work in: fewer folders opened per change, a guide in each busy folder.
You move only what `hops --proof` shows changed nothing but paths, and the pass lands as ONE task.
Nobody is watching: what you cannot prove or decide becomes a keep row in `ops/LAYOUT.tsv` and a line
in your report — never a question mid-pass, never a stop. A merge (one file folds into another and
disappears) needs the human's yes from before the run; a proven move is not a delete.

## Entry — who sends you here
- **`next` or the Stop hook, at the end of a run** — a board-proven hop: only the run's own answers.
- **`triage` on an empty board** — you are the whole run: ask `bash ops/polaris hops --questions`
  once, NOW, before any work. That is the run's one round; after it the owner is away.
- **A conductor's TIDY subagent** — its kickoff carries the up-front answers; ask nothing. Your
  report is your close — never `next` or `finish`: the conductor's own run takes it from there.
- **The explicit `update` epilogue** — `▶ NEXT — save hops: read ops/roles/TIDY.md and run it now`.

One context, no subagents. `hops: off` in `ops/CONVENTIONS.md` → stop: one line saying so, nothing
else. Long command? `ops/PROTOCOL.md` § LONG COMMANDS; never end a turn with a job still running.

## The pass
0. **The update first.** `ops/VERSION` changed but uncommitted in the primary checkout = an update is
   pending, and it already ran `upgrade` — never run that again. Commit the kit's files FIRST, as
   their own change on `<base>`: `chore(polaris): POLARIS <old> → <new>` from `git diff ops/VERSION`
   — `ops/` minus the repo's own records (board, contracts, `ops/tests/`, CONVENTIONS, MAP, SPRINT,
   RULES, LAYOUT, ROADMAP), plus `CLAUDE.md`, `.gitignore`, `.gitattributes` and the kit's `.claude/`
   pieces — never anyone's other work. Work in flight elsewhere (dirty files, unmerged branches, an
   open PR) `hops` leaves out on its own; `git fetch --quiet` first when there is an origin.
1. **Questions — only answers the run already has.** None yet (`next`, the Stop hook, a kickoff
   saying `none`)? Run `bash ops/polaris hops --questions` read-only: all it prints is unanswered. A
   merge needs a yes; a `keep` answer is a keep row `framework convention`; anything unanswered gets
   the safe default — skip the item, keep row `unsure — left for you`.
2. **`bash ops/polaris hops`** — print the map in chat, never waited on; line 1 is the before-score.
3. **The proposal.** `bash ops/polaris hops --propose > .polaris/hops-proposal.tsv`: whole features,
   ≤ 25 files, and one that would pass 25 waits whole for the next pass; an approved merge adds a row
   `merge<TAB><from><TAB><into>`. Then `bash ops/polaris hops --score .polaris/hops-proposal.tsv`;
   wait for a yes only under `autonomy: standard`, and only where you can ask.
4. **The proving check.** On the untouched tree: the first of `typecheck:` → `build:` → `test:`
   (`ops/CONVENTIONS.md`) that is set and green. None, in a python or node repo →
   `bash ops/polaris harness`, and the run line it prints is the check. No green check at all → no
   moves: empty the proposal (guides only) and write ONE `ops/board/backlog/IDEAS.md` line,
   `set test: or typecheck: to unlock moves` (most Unity repos end here).
5. **One task, filed by one command.** Draft it from `ops/templates/TASK.md` outside the board, in
   `.polaris/drafts/hops-<version>.md` (`version:` in `ops/VERSION`), as SOLO.md step 1 minus its
   `triage` confirm; file it with `bash ops/polaris new <draft.md>`, never a board file by hand.
   `plan: hops-<version>` · ≤ 5 points · `risk: normal` · `files_owned:` = the lines
   `bash ops/polaris hops --owned .polaris/hops-proposal.tsv` prints, exactly · `verify:` =
   `bash ops/polaris hops --proof .polaris/hops-plan.tsv`, plus the proving check ONLY when it is
   `typecheck:` or the harness line (`verify` refuses a bare `test:` or `build:`; step 8's suite
   proves those) · `map_delta:` one `<dir>/ — <what it holds>` per folder the moves create ·
   `needs: [delete]` ONLY for an approved merge, its yes recorded before the claim:
   `bash ops/polaris approve --plan hops-<version> -m "<their answer, quoted>"`. Claim the ID `new`
   printed (`backlog`: open work holds some of those files — stop, and report it), then work in the
   worktree, as the current directory (SOLO.md step 2b).
6. **Steps of ≤ 5 plan rows**, in proposal order; importer and mention edits ride along, uncounted.
   Each: add its rows to `<primary>/.polaris/hops-plan.tsv` (empty it before the first step) · BEFORE
   the `git mv`, the files to fix, each where it is now:
   `POLARIS_ROOT=<task worktree> bash ops/polaris hops --owned <primary>/.polaris/hops-plan.tsv`
   (never `find`'s importer lookup: it reads the primary's index) · `git mv` (+ each `.meta`) · fix
   the imports (aliases too) and path tails in each listed file that exists ·
   `bash ops/polaris hops --proof .polaris/hops-plan.tsv` · the proving check · commit. A red step:
   `git reset --hard HEAD` in the worktree, a keep row with the reason, noted for step 8
   (`proof failed: <reason>` · `broke <check>: <first line>`), its rows out of the plan file; go on.
7. **`bash ops/polaris hops --remap .polaris/hops-plan.tsv`** — the harness baseline follows the
   moves (never `harness --refresh`: a vanished module still fails); rc 1 `nothing to remap`: fine.
8. **Guides, map, record, suite, land.**
   - Guides: exactly the `<dir>/CLAUDE.md` paths in `files_owned`, bar a folder a red step left
     empty. Each: `POLARIS_ROOT=<task worktree> bash ops/polaris hops --facts <dir>`, then
     `ops/templates/FOLDER-CLAUDE.md` filled from those facts alone, never by exploring (its **Leave
     alone:** from the `leave alone:` line; `-` → drop it): stable knowledge, plain Markdown, no
     POLARIS command, no file inventories or symbols. A folder `CLAUDE.md` without the
     `<!-- polaris:guide -->` line gets the block appended after one blank line, its text untouched.
   - `git add` the guides, THEN `bash ops/polaris where --write` (it lists tracked guides only).
   - `ops/LAYOUT.tsv`: a new file's first line is exactly
     `# path<TAB>verdict<TAB>why — the layout record; polaris hops never proposes a keep row`; then
     `<old path><TAB>moved<TAB>→ <new path> · hops-<version>` per move (`merged` for a merge) and
     `<path><TAB>keep<TAB><why>` per noted keep row — in-flight paths get none. Commit.
   - The full suite once, when `test:` is set: `bash ops/polaris bg run test` FROM the task worktree,
     then `bash ops/polaris bg wait test` until the rc is not 2. Red → `git revert --no-edit` the
     move commits, their rows become keep rows `broke test: <first line>` (guides citing them
     follow); run it again.
   - The after-score: line 1 of `POLARIS_ROOT=<task worktree> bash ops/polaris hops`.
   - Land exactly as SOLO.md steps 4–6. Top-level: `bash ops/polaris next`, and follow it.

## Report
In the repo's `voice:` — outcomes, not tooling. Conductor-entered, this is your whole result.
- **Before → after**, a small table: folders per change (step 2's line 1 → the after-score) and
  guides (`<g>/<G>` → with yours added); then what moved, each `from → to`.
- **These tasks now take fewer lookups** — step 3's `change <name>: <k> folders → <k2>` lines, one
  per feature moved (one a red step cut short: say so).
- **Left for you** — every keep row `unsure — left for you`, each merge not made, and the IDEAS line
  if you wrote it. None of it stopped the pass; each is one answer for the next run's round.
