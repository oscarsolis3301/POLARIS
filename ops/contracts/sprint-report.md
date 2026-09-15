# CONTRACT: sprint-report            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the board's machine state from the management-readable per-sprint record generated from it.

## Interface
```
CONVENTIONS key:  reports: <dir>            # default docs/sprints/
file:             <reports>/sprint-<n>.md   # regenerated WHOLE each run (idempotent; later waves overwrite)

polaris report [--sprint <n> | --all]       # no flag = current sprint (top `# SPRINT <n>` header
                                            # of ops/SPRINT.md). Writes the file(s), prints the
                                            # path(s). Never commits; board is read-only to it.
```
- Internal seam: a renderer function taking `<n>` + an explicit task-ID list (+ a ref to grep for
  landed shas, default `$BASE`). `cmd_report` resolves IDs then calls it; `cmd_seal` calls it
  directly with the wave's known subjects (ref = integrate/<date>) — seal never guesses membership.
- ID resolution (`cmd_report`), layered, degrade-gracefully: (1) `[T-…]` bullets of `<base>`
  first-parent merges whose subject starts `Sprint <n> — `; (2) plus any done/ task whose `landed:`
  sha is an ancestor of tag sprint/<n> (and not of sprint/<n-1> when that tag exists); (3) `--all`:
  one file per `# SPRINT <n>` header in ops/SPRINT.md; done/ tasks attributable to no sealed sprint
  are grouped into the newest sprint's file under an `(unsealed)` marker. Missing data (no tag, no
  landed sha, no EVENTS line) → omit the field, never die.

## Shared types / schema — per-sprint file content
```
# Sprint <n> — <goal>            (dates from the SPRINT.md header, when present)
## <ID> — <title>                (one section per task, ID order)
  points · risk · landed <short-sha> (<date>) · claimed <date> → done <date>
  files touched: git diff-tree --no-commit-id --name-only -r <landed>   (fallback: files_owned)
  ### Why           — the task's `## Why` body, verbatim
  ### Acceptance    — the task's acceptance checkboxes, verbatim
```
Sources: task frontmatter via fm_get/fm_list/task_file (done/ — and review/ at seal time, those
land this wave) · `[<ID>]` subject grep on the given ref (landed sha) · EVENTS.ndjson (first claim
ts, last done ts). NO generation timestamp inside the file — byte-stable given the same inputs.

## seal hook (both publish modes)
After seal's preconditions pass: generate/refresh the current sprint's report from the wave's
subjects, commit it on integrate/<date> as `docs(sprint-N): report` — BEFORE the merge (direct) /
the push (pr). The report commit carries no `[<ID>]` suffix (it is not a task commit; ID
resolution ignores it).

## Invariants
- Report path lives OUTSIDE ops/ (default docs/sprints/) — it ships as product history and rides
  the wave into `<base>`.
- `report` mutates nothing but the report file(s); `--sprint` for a past sprint works on any repo
  with a surviving done/ + history (back-fill).
- bash >= 3.2 (NO `case` inside `$(...)`), POSIX awk, no new dependencies.

## Executable check
Selftest drill `report` (T-023): fixture done task → file contains ID, title, an acceptance line,
landed sha; the seal drill asserts the `docs(sprint-N):` commit rides the wave. Runs via
`bash kit/ops/polaris doctor --selftest`.

## Example
`polaris report --sprint 3` → `docs/sprints/sprint-3.md` with one `## T-013 — notify v2 …` section
carrying points 3, landed f440bba, its Why paragraph and its checkbox list, verbatim.

## v2 — the writer commits its own file when it is the only dirt (2026-08-03, T-061)

v1.1 documented the failure (a silently dirty report file makes the NEXT land/seal die "working
tree not clean" with no visible cause) and named remedies; v2 kills it at source. After writing,
`cmd_report` SELF-COMMITS its file(s) when ALL hold:
- running in the primary checkout, current branch == `$BASE`;
- `git status --porcelain` shows NOTHING but the report file(s) this invocation just wrote.
Commit subjects: `docs(sprint-<n>): report refresh` (single sprint) · `docs(sprint): report
refresh --all` (--all). It says what it committed. ANY other dirty path present → commit NOTHING
and print v1.1's two-remedy hint verbatim (unchanged). Never commits in a worktree, off-$BASE,
or at seal time (seal's own `docs(sprint-N): report` commit on integrate/<date> is UNCHANGED).
The `report` drill (selftest/report.sh, owned by T-061) gains both assertions: only-dirt →
commit exists with the pinned subject + clean tree; mixed-dirt → no commit + hint printed.

## Changelog
- v2 2026-08-03: report self-commits when its file(s) are the only dirty paths on $BASE in the
  primary; mixed dirt keeps v1.1's hint; seal-time behavior untouched (T-061, plan n-chats-one-repo).
- v1 2026-07-20: created for T-023 (seal hook), consumed by T-025, T-026
- v1.1 2026-07-20 (QA fix wave, T-027): report stays board-read-only and never commits — UNCHANGED. Added: after writing a file, if it differs from HEAD (`git diff --quiet -- <file>`), report prints next steps naming both remedies verbatim — commit as `docs(sprint-<n>): report refresh`, or discard with `git checkout -- <file>`. Rationale: a post-`done` re-render adds done-dates the sealed render lacked; the silently dirty file makes the NEXT land/seal die "working tree not clean" with no visible cause.
- v1.2 2026-07-20 (patch 5.14.1, T-029): ID-resolution semantics UNCHANGED; made binding: Rule 2 resolves `sprint/<n>` / `sprint/<n-1>` from the resolver's own `<n>` argument regardless of caller state (bash expands every word of a `local` line BEFORE assigning — split the declaration). Executable check extended: the drill proves Rule-2-ONLY attribution — `report --all` on a sealed sprint whose merge body carries no `[ID]` bullets still attributes the task under its sprint heading, never `(unsealed)`.

## v3 — `seal` writes the burndown row; `polaris learned` writes the Learned bullet (2026-09-14, plan sprint-c, 6.5.0 — T-153 code · T-155 entry · T-158 prose)

**Why.** `ops/SPRINT.md`'s burndown tables for sprints 12, 13 and 14 are empty and the Learned log has
no bullet newer than sprint 11 W4, while CONVENTIONS write-routing still names the Integrator as
the only writer — whose pen went silent when integration became a command (`landing: self`,
`land --express`, `next`). EVOLVE's "repeated Learned themes" input is dry. Decision: the seal
writes the row it already has the numbers for, and any lane records a lesson with one command; the
per-sprint report (`docs/sprints/`) stays the narrative of record, SPRINT.md carries the numbers.

### `seal_burndown_row <n> <date> <ids>` (integrate.sh, T-153; called by `cmd_seal` in direct mode right
after the merge, and by `seal_sync` in pr mode after the `[<ID>]` verification)
- `done_pts` = Σ `points` of the wave's task IDs (the `[<ID>]` suffixes of the sealed subjects; the
  files still sit in `review/` at seal time — read them there, `done/` as fallback).
- `remaining` = Σ `points` over `backlog/` ∪ `ready/` ∪ `active/` ∪ `review/` EXCLUDING the wave's IDs
  (files without a numeric `points:` count 0; `IDEAS.md` has no frontmatter and is skipped).
- Appends `| <date> | <done_pts> | <remaining> |` as the LAST row of the CURRENT sprint's `## Burndown`
  table — the first `## Burndown` after the TOP `# SPRINT` header, after its `|---|---|---|` line and
  any existing rows. No such table in the top section ⇒ create it at the END of the top section
  (before the next `# SPRINT ` line, else at EOF) as `\n## Burndown\n| date | done pts | remaining |\n|---|---|---|\n` + the row.
- Then `board_commit "chore(board): burndown <date>"` + `sync_board` (SPRINT.md is in the moved set; the
  secondary index makes this safe from the `<base>` checkout seal is on). Best-effort: a failure here
  is a `⚠` note, never a failed seal.
- `seal` then prints ONE nudge: `   learned anything? bash ops/polaris learned -m "…" — ≤3 per wave; EVOLVE reads them`.

### `cmd_learned` (knowledge.sh, T-153)
```
polaris learned -m "<bullet>"     # append ONE bullet to ops/SPRINT.md § Learned, from any lane, any branch
```
Appends `- <YYYY-MM-DD> · <bullet>` as the LAST bullet of the `## Learned` section (created at EOF when
absent), `evt learned "" "<first 60 chars>"`, `board_commit "chore(board): learned"`, `sync_board`.
Refuses an empty `-m` (`die "learned needs -m \"<one lesson>\""`), a bullet over 400 chars
(`die "learned: keep it to one lesson (≤ 400 chars) — the detail belongs in the task's Notes"`), and a
TAB. Prints `✅ learned: <bullet>`. Dispatch (T-155, verbatim, under `report)`): `learned)    shift; cmd_learned "$@";;`.
Usage entry (T-155, verbatim, under the `report` entry):
```
  learned -m "<bullet>"          append ONE lesson to ops/SPRINT.md § Learned (any lane, any branch;
                                 board commit) — the Planner reads it first, EVOLVE prunes it to ≤5
```

### Executable check — `drill_express` (history.sh, T-153; no new fn)
After the express land's seal: `ops/SPRINT.md` holds a `## Burndown` table whose last row is
`| <today> | <pts> | <remaining> |` with the fixture's numbers, and `git log -1 --format=%s refs/heads/polaris/board`
reads `chore(board): done <ID>` (the burndown commit precedes done's). The `learned` half lives in
`drill_grant` (board.sh, T-157 — it needs T-155's dispatch line, which T-153's worktree lacks): `learned -m "x"` from
inside a `feat/*` worktree: the bullet is the section's last line, the event exists, the board
commit's subject is pinned. Asserts bytes + rc.

### Prose (T-158) + this repo's config (Planner, on `<base>`, now)
INTEGRATOR.md § 6: "seal already wrote the burndown row; a lesson is `bash ops/polaris learned -m "…"`
(≤3 per wave) — never a hand edit of SPRINT.md". CONVENTIONS write-routing row: burndown row → `seal` ·
Learned bullet → `polaris learned` (any lane) · EVOLVE prunes. INIT.md's skeleton row: the same.

### Changelog
- v3 2026-09-14: `seal_burndown_row` · `cmd_learned` · `learned` usage/dispatch (T-153 · T-155 · T-158, plan sprint-c).
