# CONTRACT: quiet-board            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates board-state history (chore(board) churn) from product history: board mutations commit to
a dedicated ref, `<base>` first-parent stays clean.

## Interface
```
ref:        refs/heads/polaris/board          # fixed name, every repo
moved set:  ops/board/**  +  ops/SPRINT.md    # exactly these, at their on-disk paths
stays on <base>: ops/MAP.md · ops/contracts/ · ops/CONVENTIONS.md · ops/RULES.tsv · installed kit files
```
- The branch's tree contains ONLY the moved set, files at the same relative paths as on disk.
  First commit is parentless (orphan); every mutation appends one commit; subjects unchanged
  (`chore(board): claim <ID>` etc.).
- `board_commit <msg>`: commits moved-set changes ONLY, to polaris/board, via a SECONDARY index —
  `GIT_INDEX_FILE=<tmp>` + `git read-tree <prev-tip|empty>` + `git update-index --add` per path +
  `write-tree` + `commit-tree [-p <prev-tip>]` + `update-ref`. Runs in `$PRIMARY`. NEVER a second
  worktree, NEVER `git checkout`/branch switch; working tree and primary index untouched.
  Contention retry loop kept. (`update-index` bypasses gitignore — required, the set is ignored on base.)
- `sync_board`: pushes `polaris/board` (never `$BASE`). On rejection: fetch origin/polaris/board →
  union-append any EVENTS.ndjson lines present remotely but missing locally into the on-disk file →
  re-commit local state with parent = fetched tip → retry (bounded, 5). Other board files: local wins
  (same-machine writers are mutex-serialized).
- map_delta at `done`: no longer rides board_commit. `cmd_done` commits ops/MAP.md on `<base>` as
  `docs(map): <ID> <first delta line>` ONLY when the delta is non-empty. No other board mutation
  commits anything on `<base>`.
- Board file state transitions use plain `mv`, never `git mv` (the set is untracked on base).
- `init-board` (fresh install): appends `.gitignore` entries `ops/board/` + `ops/SPRINT.md`;
  board files written to disk; the branch is created by the first board_commit.
- Migration (`upgrade`, idempotent, runs when polaris/board is absent AND the moved set is tracked
  on base): (1) orphan-commit the current moved-set state to polaris/board · (2) `git rm -r --cached`
  the moved set on base · (3) append the .gitignore entries · (4) ONE final base commit
  `chore(board): board moves to polaris/board`. Re-run = no-op. History is never rewritten.
- Materialization (fresh clone): `doctor` and `resume`, when `ops/board/` is missing on disk and
  polaris/board exists (local, else origin — local ref created from origin's), write the moved set's
  files from the ref into the working tree via plumbing (read-tree into a secondary index +
  checkout-index, or per-file `git show`) — never a branch switch. Says what it materialized.
- `uninstall`: deletes refs/heads/polaris/board and, with a remote, pushes the deletion; the branch
  is named in the pre-confirm summary.
- `claim`/`resume` output: the task-file path printed for the Builder is PRIMARY-ANCHORED (absolute,
  under `$PRIMARY`) — builder worktrees do not contain ops/board. Contract paths stay repo-relative
  (contracts remain on base, present in every worktree).

## Invariants
- After migration (or on any fresh install), no NEW `<base>` first-parent commit ever has a
  `chore(board):` subject — the migration commit itself is the last.
- status/claim/verify/drift/dash/metrics keep reading the on-disk files; read behavior unchanged.
- `seal`'s clean-tree gate stays satisfiable: moved-set churn is committed by board_commit or
  ignored on base — it never dirties `<base>`'s status.
- EVENTS union semantics survive sync: no line is ever lost to a push race.
- bash >= 3.2 (NO `case` inside `$(...)`), POSIX awk, no new dependencies.

## Executable check
Selftest drills inside kit/ops/polaris: `quiet-board` (T-020) and the upgrade-migration drill
(T-021); both run via `bash kit/ops/polaris doctor --selftest`, listed in dependent tasks' verify.

## Example
`claim T-9` → lock + ready→active mv on disk → one commit `chore(board): claim T-9` on
polaris/board → push polaris/board. `git log --first-parent <base>` shows nothing new.
`done T-9` (task has a map_delta) → `chore(board): done T-9` on polaris/board + one
`docs(map): T-9 …` commit on `<base>`.

## Changelog
- v1 2026-07-20: created for T-020, T-021 (consumed by T-022..T-026)
