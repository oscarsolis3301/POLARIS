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

## Changelog
- v1 2026-07-20: created for T-023 (seal hook), consumed by T-025, T-026
- v1.1 2026-07-20 (QA fix wave, T-027): report stays board-read-only and never commits — UNCHANGED. Added: after writing a file, if it differs from HEAD (`git diff --quiet -- <file>`), report prints next steps naming both remedies verbatim — commit as `docs(sprint-<n>): report refresh`, or discard with `git checkout -- <file>`. Rationale: a post-`done` re-render adds done-dates the sealed render lacked; the silently dirty file makes the NEXT land/seal die "working tree not clean" with no visible cause.
