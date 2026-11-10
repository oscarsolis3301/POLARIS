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

## v1.1 (2026-11-09) — pointers and riders
Planner groom for Phase 3 of plans/minutes.md (owner-approved). v1 above is unchanged and still binds;
this section only re-points it at today's code, corrects how § 8's race golden is driven, and adds four
riders. Line numbers are as of main 32e15e7; builders re-find them with `ops/polaris find <symbol>`.

### A. § 8 land-race, corrected (T-221)
- Driver: NOT separate land / seal / done processes. Four tasks T-1..T-4 (risk: normal, disjoint
  files_owned, one trivial verify line each) are claimed one by one, each gets one commit in its
  worktree, then all four `handoff` calls start together in the background under `landing: self`.
  That is self_land's real tail (the reported failure), so the .cmd never changes when T-223 fixes it.
  Fixture as self-land-finish.cmd, plus a `# SPRINT 1 — race` header, test_select unset and an ancestor
  suite stamp. Budget about 3 minutes.
- Output, exactly: one line per task `<ID> <column> OK|LOST` (OK = main's file byte-equals the feat
  tip's, the tip recorded before any done can delete the branch), then `waves: <n>`, then
  `leftover-unsealed: <n>`. No sha, path, time or user.
- What `.expected` pins at each step: the GREEN output (`T-1 done OK`..`T-4 done OK`, `waves: 1`,
  `leftover-unsealed: 0`) from the day T-221 lands. Actual output on main: RED after T-221 and after
  T-222; GREEN from T-223 on (the lease alone must make it green; § 5's re-land is the net), and it stays
  in T-224's and T-225's verify lists. Nobody edits land-race.expected after T-221. No full proof runs
  between T-221 and T-223; if one does, land-race is the one expected red and is never weakened.

### B. File moves and pointers
- § 1: `int_on` kit/ops/lib/workspace.sh:213, `int_off` :276, `wave_on` :286; `on_die` core.sh:597.
- § 2: `self_land` builder.sh:375. Since v1 (T-259) it reads the sprint header and returns 0 BEFORE
  landing; the lease is taken after that check, so a header-less sprint still takes nothing.
- § 3: `cmd_done` integrate.sh:198; the "would DEADLOCK" comment is near :323; the board move, docs(map)
  commit and `board_commit` sit inside `mutex_on` (about :278-:361); the verify stamp is removed at :362
  (T-284). The § 5 check and re-land run before the board move, so the stamp goes only when the task
  does. `cmd_land` :518 (land_had :540; skip gate 1 :543 "already landed — skipped ($id is in $BASE
  history)"; gate 2 :567 "already landed — skipped ($id is on $br)"; its conflict unwind :589 is a bare
  `git reset -q --hard`, already exact, and stays). The two `HEAD~1` unwinds are in `cmd_land_express`
  :730 and :787 (ex_had :644); the printed hint :608 may keep naming HEAD~1. `cmd_seal` :894 (seal_had
  :915, release :1043; T-259's one-open-wave fallback and return-to-base on a refused seal stay).
  `landed_sha` :183.
- § 7: `cmd_finish` is now kit/ops/lib/qa.sh:272 (T-273 split observe.sh: `cmd_qa` qa.sh:4,
  `cmd_drift` drift.sh, `cmd_check` check.sh, `cmd_route` / `cmd_triage` route.sh). The gate runs in
  PHASE A, before qa and before finish clears merged wave branches and idle finished worktrees (T-282),
  so every branch it needs still exists.
- New public names: `int_mine` (T-222), `landed_content_ok` (T-224); each owner regenerates
  ops/tests/api-kit.expected.

### C. Ownership changes since v1
- T-222 also owns builder.sh, selftest/board.sh and the plan-marker golden (rider a), so T-223 stays at
  5 points. T-225 owns qa.sh instead of observe.sh, plus the finish-qa-red golden (rider c).
- T-226 adds kit/ops/roles/BUILDER.md (rider d). T-221 and T-226 share no file and run together; the
  chain T-222 → T-223 → T-224 → T-225 runs one lane at a time and each task lands itself at handoff,
  so chain tasks may share files.

### D. Rider a — the session plan marker (T-222, builder.sh `cmd_claim`, today :179)
- At claim, with a session id: no marker → write the task's plan (today). Marker names plan A, the
  claimed task is plan B, and no task with `plan: A` is in active/ or review/ (the task being claimed
  excluded) → overwrite with B. A still has a task there → keep A. Same plan → untouched. Claim prints
  nothing new.
- Golden ops/tests/plan-marker.cmd pins one line each, `marker: <plan>`, after: (1) the first claim of
  an alpha task → `marker: alpha`; (2) a claim of a beta task while an alpha task is still active →
  `marker: alpha`; (3) the alpha tasks moved to done/, a claim of another beta task → `marker: beta`.

### E. Rider b — healed after a kickback (T-224, landed-content case e)
- Case: T-x is landed and sealed (its [T-x] squash is on main), then kicked back, given one more commit
  on feat/T-x that changes one owned file, and returned to review/. `land T-x` still skips by gate 1
  (unchanged). `done T-x` then prints `⚠ T-x did not fully arrive — re-landing`, makes exactly ONE
  extra commit on main through a wave (subject ends `[T-x]`, body line `re-land: 1 path(s) did not
  arrive`), and ends with main's file byte-equal to the feat tip, the task in done/, and the branch
  deleted only after the match. The golden prints those facts as counts and yes/no, no shas.
- No `land --drop` verb: done is the healer.

### F. Rider c — finish names the red qa key (T-225, qa.sh)
- qa's red block for a suite key (full or scoped, `⛔ <k> — RED: <cmd>`) prints `tail -20` of that
  key's output (today 15), each line indented 5 spaces; doctor's red block prints `tail -20` (today 5).
  The drift block is unchanged.
- finish, when qa is red, prints instead of today's `tail -6`:
  `⛔ pending: qa is red on <base> — <k1>[, <k2>…]` (the keys in qa's order, read from qa's
  `⛔ <key> — ` header lines), then each red key's whole block from qa's output, verbatim, every line
  indented 5 more spaces. A green qa prints what it prints today.
- Golden ops/tests/finish-qa-red.cmd: a fixture whose `test:` prints `line 1`..`line 30` and exits 1;
  finish exits non-zero; pinned: the pending line naming `test`, the red header, `line 11`..`line 30`,
  and no `line 10`.

### G. Tests that pin each changed verb (the chain's verify lists)
Every chain task lands itself, so its verify list is its whole gate; drills are judged by CI through
`PROOF_GOLDENS=true bash tools/proof.sh`, run once before handoff (Notes, never verify).
- handoff and the self-land tail: self-land-finish, guide-stale, pack-visual, shots-gallery,
  verify-stamp, seal-fallback, pr-one-link, express-pr (T-223).
- land / land --express: express-pr, plan-approval-gates (T-223). seal: seal-fallback, express-pr
  (T-223, T-224, T-225). done: where-done, verify-stamp, shots-gallery (T-223, T-224). finish:
  self-land-finish, finish-blocked, drain-default, pr-one-link (T-225). Lease messages: unchanged,
  pinned by the busyint drill (CI) and self-land-finish (T-222).
- No golden or drill pins qa's `— RED` block or finish's red-qa lines today (grepped), so rider c moves
  nothing already pinned.

### H. Rider d — prose (T-226)
`bg wait … --max 300` → `--max 120` in BUILDER.md, the builder kickoff in CONDUCTOR.md, SOLO.md and
PROTOCOL.md § LANES ("half the cap" goes); CONDUCTOR.md and INTEGRATOR.md say a task lands itself at
handoff from this release and an integrator is spawned only for what refused to; BUILDER.md says a task
that changed kit/ops/lib/ runs the CI proof once before handoff. After T-221 + T-226 land, the conductor
deletes `landing: integrator` from ops/CONVENTIONS.md before the chain starts.

### I. Rider e — waiting for the board never kills the command (T-222, core.sh `mutex_on`, today :619)
Found by T-221's golden on today's code, five runs of five. While a command waits for the board,
`mutex_on` reads the holder's start time with `e="$(cat "$MUTEX/epoch" 2>/dev/null)"`. The CLI runs under
`set -eu`, so when the holder lets go between the `[ -f "$MUTEX/epoch" ]` test and the `cat`, the `cat`
fails and the whole command dies there: rc 1, no message. A `handoff` that dies this way leaves its task
in `active/` with its lock held, so no lane is ever the last one out and nobody seals.
- The read never fails the command: `e="$(cat "$MUTEX/epoch" 2>/dev/null || true)"`. An empty value
  already falls back to "now" on the same line (age 0 → keep waiting), which is the right answer for a
  board that was just released. Nothing else in `mutex_on` changes; no output changes.
- T-222 reads the rest of the wait loop (and `mutex_off`, `int_on`'s wait) for the same shape — a bare
  `x="$(cmd)"` on a file another process may remove — and gives each the same guard. It reports what it
  found; it changes no behaviour beyond not dying.
- Check: with this rider and nothing else, T-221's `land-race` no longer leaves a task in `active/`.
  It is still RED by design until T-223 (one lane seals early, a later lane's land is left unsealed:
  `waves: 2`, `leftover-unsealed: 1`). T-222 runs `ops/tests/land-race.cmd` twice by hand through
  `bg run` and reports the two outputs; it is never in T-222's verify list.

### J. § 7 corrected — what "missing" means at finish (T-225; conductor, 2026-11-10)
Asked by T-225's builder before writing a line, with evidence: tasks that build on each other share
files (v1.1 § C), so a later task rightly changes a path an earlier one landed. Compared against main's
tip, `feat/T-222` differs today on builder.sh, core.sh and api-kit.expected, and `feat/T-223` on
integrate.sh — nothing is missing, yet § 7 as written would make `finish` refuse this very run.
- **At `finish` only**, a path of a done task counts as missing when main's blob differs from the feat
  tip's AND no commit on main AFTER the task's own landed commit (subject ending `[<ID>]`, the newest
  one — a re-land counts) touched that path with a subject ending in another task's `[<other ID>]`.
- A done task with NO landed commit in main's history counts every differing path (that is the
  reported failure: done on the board, never on main).
- Cost: nothing on the healthy path; one `git log` per task that already differs.
- `seal` (§ 6) and `done` (§ 5) are unchanged: they run right after the landing, when nothing else can
  have touched the paths, so the plain comparison against main is exact there.
- The gate's one line and exit are as § 7 pins them. Golden `finish-qa-red` is unaffected; golden
  `landed-seal` gains nothing from this; a case for the rule goes where T-225 tests the finish gate:
  task A landed, task B later changed the same file → finish passes; task C done with no landed
  commit → finish refuses and names C and its paths.

## Changelog
- v1 2026-10-28: created for tasks of plan `safe-landing`.
- v1.1 2026-11-09: pointers re-derived after T-259, T-273, T-277, T-282, T-284; section 8 driver corrected; riders a-d (Phase 3 groom).
- v1.2 2026-11-09 (conductor): rider e — the wait for the board mutex no longer kills the command when the holder releases mid-read (found by T-221; folded into T-222, which owns core.sh).
- v1.3 2026-11-10 (conductor): § J — at finish a path is missing only when no later landed task commit touched it; a done task with no landed commit counts every differing path (asked by T-225's builder, with the false alarms it measured on this run).
