# CONTRACT: clean history            (v1 — 2026-07-18)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
The seam between the git-history model (one rich squash commit per task, one tagged summary merge per
sprint) and everything that reads or writes it: the CLI commands (T-007), the Integrator recipe
(T-008), the task-authoring surface (T-009), and the docs (T-010). Ships in 5.12.0; applies forward
only — existing history is never rewritten.

## Interface — CLI (all in kit/ops/polaris; dispatch + usage entries required)
Command names are hyphenated per house style (`run-verify`, `init-board`); the plan's
`task_commit_msg` is therefore CLI name `task-commit-msg`.

```
polaris task-commit-msg <task-file>
  Pure helper: prints the task's commit message to stdout, mutates NOTHING. Exact output:

    <type>(<scope>): <title> [<ID>]
    <blank>
    <Why body>                       # omit block (and its blank line) when empty
    <blank>
    What changed:
    - <acceptance criterion>         # one per checkbox line, "- [ ] "/"- [x] " marker stripped
    <blank>
    Notes:                           # omit block when no qualifying lines
    - <builder note>
    <blank>
    Files: <files_owned, comma-space joined, one line>

  type:  feature→feat · bug→fix · chore→chore · spike→chore · missing→chore
  scope: `scope:` frontmatter if non-empty, else the first path component of the first
         files_owned entry (kit/ops/polaris → kit). Planners SET scope:; derivation is fallback.
  Why body: text between the `## Why` heading (accept legacy `## Why this exists` too) and the
         next `## ` heading, trimmed. Criteria: checkbox lines within the section whose heading
         starts `## Acceptance`. Notes: `- ` lines under `## Notes`, excluding HTML-comment
         lines and lines containing ⛔.

polaris land <ID>
  Integrator, inside the PRIMARY checkout, on the integrate branch.
  preconditions (else exit non-zero, nothing mutated):
    - <ID> is in review/ · current branch is NOT $BASE (die: create integrate/<date> first)
  steps:
    1. audit <ID>  (ownership + rules on feat/<ID> — unchanged, runs before any merge)
    2. git merge --squash feat/<ID>
       - conflict → git reset --hard (restore integrate HEAD) → kickback <ID> -m "squash
         conflict — planning bug" → exit non-zero
       - empty diff → git reset --hard → die (Integrator decides; no auto-kickback)
    3. ONE commit: message = task-commit-msg output + trailing blank line +
       `Landed-from: <feat/<ID> tip SHA>` trailer.
  land makes NO board write, NO evt, NO board commit — the board files stay clean so that
  `git reset --hard HEAD~1` (red task on integrate) unwinds a land completely, one commit,
  nothing uncommitted to lose. The landed record lives in the commit itself (subject `[<ID>]`
  + Landed-from trailer); `done` stamps it onto the task file later.
  Re-land after a kickback simply repeats the above.

polaris seal [<date>]
  Integrator, PRIMARY checkout. Default <date> = today (integrate/<date> must exist).
  preconditions: working tree clean · integrate/<date> exists · base..integrate has ≥1
    non-`chore(board):` commit (else die "nothing to seal") · tag sprint/<n> does not exist
    (else die "bump the SPRINT.md header").
  steps: git checkout $BASE → git merge --no-ff integrate/<date> -m <msg> → tag (lightweight)
    sprint/<n> on the merge → if a remote exists, push $BASE and the tag.
  Merge conflict → git merge --abort → die (human resolves; never auto-resolve).
  <msg>:  Sprint <n> — <goal>
          <blank>
          - <subject of each non-chore(board) commit in base..integrate, oldest first>
  <n> and <goal> parse from the ops/SPRINT.md header line `# SPRINT <n> — <goal>` (goal ends at
  2+ spaces or `capacity:`; accept `—` or `-`).

polaris history [--tasks <n>]
  Read-only. Default: git log --first-parent $BASE, `chore(board):`-subject commits filtered
  out, one line per commit (%h %ad %s, short date). Reads as a changelog; degrades gracefully
  on never-sealed boards.
  --tasks <n>: the per-task commits inside sprint <n>: git log --no-merges
  sprint/<n>^1..sprint/<n>, same chore(board) filter.

polaris rollback <ID | sprint/<n>>
  preconditions: working tree clean · current branch is $BASE (else die).
  <ID>:        locate the squash commit (landed: frontmatter in done/<ID>.md, else search $BASE
               history for subject suffix `[<ID>]`) → git revert --no-edit <sha>.
  sprint/<n>:  git revert --no-edit -m 1 <tag>.
  Conflicted revert → git revert --abort → die. Never resets, never force-pushes.
```

## Gate replacement — squash breaks feat-branch ancestry; these rules replace it
A squash-landed task's feat/<ID> is NEVER an ancestor of $BASE. Everywhere the code asks "is this
task merged?" the test becomes, in order:
1. **landed check**: a commit with subject suffix `[<ID>]` exists in $BASE history
   (`git log --fixed-strings --grep "[<ID>]"`, then confirm the subject truly ends with `[<ID>]` —
   fixed-string, so [T-1] never matches [T-10]);
2. **legacy fallback**: today's `merge-base --is-ancestor feat/<ID> $BASE` (keeps hand `--no-ff`
   merges per MANUAL.md working).
Both fail → not merged.

Applied at:
- `done` merge gate (kit/ops/polaris:543-544): accept via rule 1 or 2; new die message names both
  paths ("land it (or merge it), then done").
- `done` additionally stamps `landed: <squash SHA>` frontmatter on the task as it moves review→done
  (rides done's existing board commit — the durable, human-readable record; rollback's fast path).
- `done` remote cleanup (kit/ops/polaris:573-574): delete origin feat/<ID> iff the remote tip SHA ==
  the LOCAL feat/<ID> tip at done time (local branch still exists there), else legacy
  ancestor-of-$BASE check, else warn exactly as today. Never delete a diverged tip.
- `sweep` merged-stray detection: for a done/ task (local branch gone), the remote tip is a
  deletable stray iff it == the `Landed-from:` trailer value of the task's squash commit (located
  via rule 1 / `landed:` frontmatter), else legacy ancestor check, else "diverged" warning.
- `doctor --selftest`: the hand-merge drills (`git merge --no-ff feat/T-1` ~:743 and the T-C remote
  drill ~:865) move to land→seal→done; ONE drill keeps the legacy `--no-ff` + `done` path green to
  prove rule 2 survives.

## Shared types / schema — task template fields (T-009 owns the template + role files)
```
scope:                   # NEW, optional frontmatter: conventional-commit scope; Planner sets it
## Why                   # NEW body section, after frontmatter, before ## Acceptance criteria:
                         # junior-dev-grade what/why — becomes the commit body VERBATIM at land
```
task-commit-msg accepts legacy `## Why this exists` so pre-5.12 boards keep working.
PLANNER.md: author `## Why` + `scope:` per task at grooming time — commit quality is planned in.
BUILDER.md: Notes lines are the "how" that lands in the commit body — one line per real discovery,
no chatter (⛔ lines and comments are filtered out).

## Integrator recipe (T-008 owns kit/ops/roles/INTEGRATOR.md; replaces the --no-ff-per-task recipe)
audit+`land` per task in dependency order on integrate/<date> (paranoid: full suite after every
land; batch: once after all) → full suite ONCE green on the combined tree → red = bisect by
`git reset --hard` + re-land halves, offender = `reset --hard HEAD~1` + kickback (one commit per
task, no topology) → `seal` → per task `run-verify` + `done` on $BASE → `qa`. Flake rule, human
gate on risk:high, sweep/promote/Learned duties unchanged.

## Docs surface (T-010): kit/CLAUDE.md THE TOOL table gains `land · seal · history · rollback`
(+ the one-line history model); kit/ops/MANUAL.md gains fallback recipes for land (squash + a
hand-written message in the format above) and seal; kit/ops/roles/INIT.md notes the history model
+ recommends a clean-log alias (`git log --first-parent` sans chore(board)); CHANGELOG.md 5.12.0.

## Executable check
`doctor --selftest` gains the squash-model drills (land = one commit w/ subject format + trailer ·
seal = one merge + sprint tag · history filters chore(board) · done accepts a squash landing and
stamps landed: · legacy --no-ff still accepted · revert of task and sprint apply) — owned by
T-007, listed in T-007's `verify:`. T-008/9/10 pin their names against this file via grep-based
`verify:` lines.

## Invariants
- land/seal/rollback NEVER touch $BASE except seal's single --no-ff merge and rollback's revert;
  no force-push anywhere; a conflicted anything aborts and reports — never auto-resolves.
- land leaves zero uncommitted state behind on any path (success, conflict, empty, red-unwind).
- `chore(board):` commits keep landing exactly as today — history/seal FILTER them, never suppress.
- Board mutations stay inside existing commands (kickback/done); land/seal add no new board-commit
  call sites beyond done's `landed:` stamp.
- bash 3.2 + POSIX awk only; no new dependencies; Windows/Git Bash safe.

## Example
```
$ bash ops/polaris task-commit-msg ops/board/review/T-042.md
feat(api): rate-limit the reset endpoint [T-042]

Unthrottled password resets let one IP hammer SMTP; support asked twice.

What changed:
- POST /auth/reset returns 429 with retry_after after 5 hits/min/IP
- selftest gains a limiter drill

Notes:
- limiter reuses the token-bucket in api/util_bucket.py

Files: src/api/reset.py, src/api/util_bucket.py
```

## v2 — multi-wave seal (2026-07-18, owner T-017)
Motivation: Sprint 3 wave 1 proved v1 conflates sprint with integration wave — `seal` dies once
tag sprint/<n> exists, and `done` needs the landed [<ID>] commit reachable in $BASE, which only a
seal merge provides; a sprint with >1 wave could neither seal nor done after wave 1 (SPRINT.md
Learned + EVENTS.ndjson). v1 stands except as amended below. Tag semantics: `sprint/<n>` ALWAYS
marks the sprint's latest sealed checkpoint — end of sprint = final checkpoint. The sprint number
truth stays the ops/SPRINT.md header; a new sprint = the human bumps the header, exactly as today.

`seal [<date>]` — amended:
- tag precondition REPLACED: refs/tags/sprint/<n> absent, OR it points to an ancestor of $BASE (a
  previous wave's checkpoint) → proceed. Neither → die "sprint/<n> exists and is not in $BASE
  history — reused sprint number; bump the ops/SPRINT.md header". Checked BEFORE the merge;
  nothing mutated on failure. All other v1 preconditions unchanged.
- every wave seals with the same --no-ff merge + message format (bullets are naturally the new
  wave's commits — $BASE..integrate excludes prior waves).
- FIRST seal of sprint n: create tag sprint/<n> (v1, unchanged).
- LATER seal of the same n: after the merge, MOVE the tag — `git tag -f sprint/<n>` on the new
  merge; output names the move (`sprint/<n>: <old7> → <new7>`).
- push: $BASE as v1. A moved tag pushes compare-and-swap:
  `git push --force-with-lease=refs/tags/sprint/<n>:<old-sha> origin refs/tags/sprint/<n>`
  — the only forced ref update POLARIS ever makes, and it is leased. Failure → v1's warn-note.

`history --tasks <n>` — amended: range starts at the OLDEST first-parent merge of $BASE whose
subject starts `Sprint <n> — `: `<oldest>^1..sprint/<n>`, --no-merges, chore(board) filter as v1.
A single-wave sprint produces byte-identical output to v1.

`done` / `land` / `task-commit-msg` — UNCHANGED. Wave-2+ `done` works because that wave's seal
makes its [<ID>] commits reachable in $BASE (rule 1 of the v1 gate replacement).

`rollback sprint/<n>` — code UNCHANGED: reverts the tag's merge = the LATEST wave, one atomic
revert (matches checkpoint semantics). Earlier waves revert by SHA (`git revert --no-edit -m 1
<sha>`); MANUAL.md documents it. Revert-all-waves was REJECTED: a mid-chain revert conflict would
strand a half-reverted sprint, and rollback never resets.

Executable check: `doctor --selftest` gains a `second-seal` drill (wave-2 land on the same
integrate branch → re-seal green → tag moved → `--tasks` spans both waves → wave-2 `done` passes)
— owned by T-017, listed in T-017's `verify:`.

## Changelog
- v1 2026-07-18: created for T-007, T-008, T-009, T-010 (Phase 1, 5.12.0).
- v2 2026-07-18: multi-wave seal for T-017 (5.13.0) — tag moves per wave; history --tasks spans waves; evidence: Sprint 3 wave 1.
