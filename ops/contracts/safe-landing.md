# CONTRACT: safe-landing — nothing lands twice, nothing gets lost   (v1 — 2026-10-28)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
One lease covers a self-landing lane's whole tail (land → seal → done), and `done` proves a task's
files really are on main — re-landing them itself if not — before it moves the task or deletes its branch.

## Why (the reported failure)
Four lanes self-landed within two minutes. Each of land / seal / done ran as a separate process that
took and dropped the integration lease, so another lane slipped into every gap; `done` committed to the
shared checkout with no lease; land failure paths used a bare `git reset --hard HEAD~1`; and nothing
compared main's files with the feat tip before `done` deleted the branch. Result: tasks in `done/`,
code absent from main.

## 1. Lease token (workspace.sh: int_on / int_off)
- `int_on` writes `$LOCKS/.int-lease/{epoch,who,pid,why}` as today PLUS `token` = `<holder-pid>:<nonce>`
  (nonce = epoch-seconds + `$RANDOM`, generated once at take time) and exports `POLARIS_INT_TOKEN=<token>`.
- Re-entry (rc 0, no wait, nothing rewritten) when EITHER the lease `pid` file equals `$$` (today's rule)
  OR `POLARIS_INT_TOKEN` is set and equals the lease's `token` file. A child process of the holder
  therefore inherits the lease; any other session has no token and queues exactly as today
  (poll 2s, stale steal, `queued: ` + rc 3 — messages unchanged).
- A re-entering frame sets `INT_HELD` only as "I may rely on the lease" but records `INT_TOOK=0`; the
  taking frame records `INT_TOOK=1`. `int_off` removes the lease directory ONLY when `INT_TOOK=1`
  (the frame that created it) and the lease `token` still matches; a re-entering frame's `int_off` is a
  silent no-op. A stale/unset/mismatched token never grants entry.
- on_die (core.sh) releases the lease only for a taking frame. Stale-steal rules unchanged.
- Lock ordering unchanged and stated once more: lease OUTERMOST, board mutex inside; never `int_on`
  while holding the board mutex.

## 2. self_land tail (builder.sh)
`self_land` (after handoff's `mutex_off`) takes the lease ONCE (`int_on "self-land <ID>"`; rc 3 →
return 3 with the `queued: ` line last, as today) and holds it through the whole tail, releasing in
its own frame on every exit path. Inside the lease:
1. `land <ID>` (child; re-enters via token). Failure rules unchanged (rc≠0 → note, task stays in review/).
2. Re-read "am I the last lane out" FROM THE BOARD, inside the lease: `active/` and `ready/` both empty
   (the same two counts handoff used). The handoff-time `notice` is advisory output only and never
   decides the seal.
3. Last lane out → `seal` (child), then fan out `done` over every landed review task, own ID last
   (unchanged ordering/Guard 1 rules from worktree-liveness v1.3). Not last → the mid-wave note, as today.
All outputs, rcs and the "risk: high never self-lands" refusals stay byte-for-byte as today.

## 3. cmd_done under the lease (integrate.sh)
`cmd_done` takes the (re-entrant) lease before its base commit (map / surface / screen rows), the
worktree removal and the branch deletion, and releases it only if it took it. The old "would deadlock"
comment is replaced by a pointer to § 1. Standalone `done` (no token) queues for the lane like `land`
does; rc 3 prints the `queued: ` line and stops with nothing touched.
Land failure paths (the conflict/audit unwinds in `cmd_land`, `cmd_land_express`) record
`pre="$(git rev-parse HEAD)"` BEFORE the squash and unwind with `git reset -q --hard "$pre"`, never
`HEAD~1`. The user-facing recovery hint text may keep naming `HEAD~1`.

## 4. landed_content_ok (core.sh)
`landed_content_ok <ID> [<ref>]` — pure check, no writes, no lease needed (callers hold it).
- `ref` defaults to `$BASE`; `seal` passes the wave branch before it merges.
- Let `mb = git merge-base <ref> feat/<ID>` falling back to the task's recorded base; paths =
  `git diff --name-only <mb> feat/<ID>` (with `--no-renames`, so a rename is a delete + an add).
- For every path: feat tip blob == `<ref>`'s blob (`git rev-parse <ref>:<p>` vs `feat/<ID>:<p>`); a path
  absent at the feat tip must be absent at `<ref>`. Executable-bit/mode differences count as mismatch.
- stdout: the mismatching paths, one per line (empty when ok). rc 0 = every path arrived, rc 1 =
  at least one mismatch, rc 2 = cannot check (no `feat/<ID>`, branch already gone) — callers treat rc 2
  as "nothing to prove": proceed silently exactly as today (so replays and already-cleaned tasks behave).
- The branch is `feat/<ID>`; check the local ref first, else `origin/feat/<ID>`.
- A task with an empty diff (a docs-only or no-op task) is rc 0.

## 5. done: check, re-land, re-check (integrate.sh)
Inside the lease, BEFORE the board moves the task to `done/` and before any branch/worktree deletion:
1. `landed_content_ok <ID>`; rc 0 or 2 → proceed unchanged. Normal path prints NOTHING extra and makes
   NO extra commit.
2. Mismatch → print `⚠ <ID> did not fully arrive — re-landing`, then `relanding <ID>` once:
   a wave via `wave_on` on a fresh integrate branch from `$BASE`; for each mismatching path, restore
   the feat tip's blob (or `git rm` for a deletion); ONE commit with subject
   `<scope-subject-of-the-task> [<ID>]` carrying the body line `re-land: <n> path(s) did not arrive`
   (subject ends `[<ID>]` so `landed_sha` still finds it, the original squash stays in history); then
   `seal` through the same machinery (`cmd_seal` in-process, lease re-entered). Dirty-tree, ancestor-stamp
   and `test_select`-unset behavior of land/seal are untouched: the re-land runs NO suite.
3. Re-check. rc 0 → continue as normal (branch deleted only now). Second mismatch → print exactly ONE
   line `⛔ <ID> still missing from main: <p1> <p2> … — branch feat/<ID> kept` (first 5 paths, then `+N more`),
   exit 1, task NOT moved, branch NOT deleted.

## 6. seal check (integrate.sh)
After `cmd_seal` merges the wave, for each task whose `[<ID>]` landed commit it merged, run
`landed_content_ok <ID>`; a mismatch prints `⚠ <ID> did not fully arrive — re-landing` and invokes the §5
re-land for that ID (in the same lease), then continues. All-green prints nothing new.

## 7. finish gate (observe.sh)
`finish` gains one gate: for every task in `done/` whose `plan:` matches this run (all of `done/` finished
this run when the run has no plan record), `landed_content_ok <ID>` must be rc 0 or 2. Any rc 1 → finish
prints ONE line `⛔ <ID> is done but its files are not on main: <paths>` and exits non-zero. No mismatch → no new output.

## 8. Executable checks
- `ops/tests/land-race.cmd` / `.expected` (task owner: first of the chain). HERMETIC: `mktemp -d` fixture,
  CLI run from inside it. 4–6 review-state tasks with DISJOINT `files_owned`, each with its own `feat/<ID>`
  tip (plumbing commit-tree or tiny commits) and risk: normal. Fire each lane's tail concurrently
  (`( bash "$KIT" land <ID> … )` in the background × N, started together, using the same lease-token path
  `self_land` uses once B ships; before B the golden drives today's separate land → seal → done
  processes per lane). After every job exits assert and print only facts: for each done task `OK <ID>` or
  `LOST <ID> <path>` (byte-compare `git show main:<p>` vs `git show feat/<ID>:<p>`); `waves: <n>` open-or-sealed
  integrate branches (expect 1); `leftover-unsealed: <n>` (expect 0). Expected output has zero shas/paths/times.
  Must be RED on code before B and C; green after. If it cannot be made red the builder reports the exact
  interleavings tried and ships it as a (green) regression guard — never faked.
- `ops/tests/landed-content.cmd` / `.expected` (task owner: C): (a) clobbered file on main → `done` re-lands,
  ends green, branch kept until content matches; (b) deliberately unfixable (mismatch re-appears after re-land,
  e.g. a hook/ rule that rejects the path) → one `⛔` line naming task + files, branch kept, task not in `done/`;
  (c) normal path → no extra commit (commit count equal) and `done` output unchanged;
  (d) dirty tree + ancestor stamp + `test_select` UNSET in the fixture: the same flows behave as before.
- `ops/tests/api-kit.expected` regenerated by the task that adds/moves a function.

## Invariants
- No lane ever loses a landing; `done` never writes before the lease; a re-entering frame never releases.
- No new config key, no new dependency, no RULES.tsv change, nothing touches `.github/`.
- Quiet when healthy: the normal path's stdout/stderr and commit graph are byte-identical to 6.10.1.

## Changelog
- v1 2026-10-28: created for tasks of plan `safe-landing`.
