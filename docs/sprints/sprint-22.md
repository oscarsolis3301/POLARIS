# Sprint 22 — The speed release (6.14.0) (2026-11-09–)

## T-273 — "observe.sh becomes five modules, move-only, with a machine proof that nothing changed"
points 5 · risk normal · landed eb5f239 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/check.sh, kit/ops/lib/drift.sh, kit/ops/lib/observe.sh, kit/ops/lib/qa.sh, kit/ops/lib/route.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/lib-census.cmd, ops/tests/lib-census.expected, ops/tests/triage-lane.cmd, tools/fnmove.sh

### Why
observe.sh is 3,267 lines, and four of this sprint's tasks need to change it. If they all owned that one file they would have to run one after another, which is the slowness this sprint exists to remove. This task cuts it into five files by moving functions, and changes nothing else: drift.sh (board hygiene), check.sh (the goldens), route.sh (triage, route and depth), qa.sh (qa and finish), and observe.sh keeps the rest. Because "nothing else changed" is the whole promise, it is proven by a small tool, tools/fnmove.sh, that lists every function as its name and body before and after and checks the two lists are the same. ops/contracts/minutes.md section 3 has the exact lists, the loader line and the tool's output.

### Acceptance
- [ ] the five files hold exactly the functions minutes.md § 3.1 lists, bodies byte for byte, each with its leading comment
- [ ] the loader line in kit/ops/polaris is § 3.2 literally; the guard path stays `core ownership`; the entry gains no line
- [ ] `tools/fnmove.sh` behaves as § 3.3 and prints the equal line for this move
- [ ] golden `lib-census` (§ 3.4) is new and green; api-kit rows change file only, same count; triage-lane greps route.sh
- [ ] every verify line is green

## T-274 — "The knowledge base rebuilds in one pass and never shows a half-written file"
points 3 · risk normal · landed 6e3a148 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/knowledge.sh, ops/tests/brain-codemap.cmd, ops/tests/brain-codemap.expected

### Why
Every seal rebuilds the knowledge base, and its code map walks each folder with a dozen small commands, so it costs 20 seconds even in a 124-file project and over two minutes here. This task rebuilds the map from one file listing, one search and one awk, printing the same lines in a pinned order, and writes every brain file to a temporary name before moving it into place so nobody ever reads half a file. ops/contracts/minutes.md section 4 has the line shapes, the ordering rules and the golden.

### Acceptance
- [ ] `brain_code_map` follows minutes.md § 4.1: one ls-files, one grep, one awk; same line shapes; the pinned order
- [ ] every brain file is written atomically (§ 4.2)
- [ ] golden `brain-codemap` (§ 4.3) is new and green; the `brain` drill stays green
- [ ] timed by hand: under 3 s on the practice shop and under 10 s here, both numbers noted below

## T-275 — "One update covers the PC: it commits itself, starts the other projects, and speed shows landing time"
points 5 · risk normal · landed 9c15e91 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/admin.sh, kit/ops/lib/selftest/remote.sh, ops/tests/heal-design.expected, ops/tests/heal-model-line.cmd, ops/tests/heal-model-line.expected, ops/tests/speed-report.cmd, ops/tests/speed-report.expected

### Why
Updates leave files uncommitted (one project had 64), and other projects on this PC sit on old versions because nobody remembers to update them. After this task an update commits exactly the files it changed, with a plain subject, but only when that is safe (on the main line, nothing half-done, nothing staged, not a pull-request project) and it never pushes. A typed update then starts updating the other projects on this PC in the background and says where the log is. `speed` also learns two numbers: how long tasks take to build, and how long they wait to land. ops/contracts/minutes.md section 5 pins every line.

### Acceptance
- [ ] self-commit as minutes.md § 5.1: the four conditions, exactly the changed paths, that subject, never a push, the two notes
- [ ] fan-out as § 5.2: only a typed `update`, detached, the one line, `--auto` never fans out, `POLARIS_UPDATE_NO_FANOUT` seam
- [ ] `speed` prints the two median lines of § 5.3 from one awk
- [ ] the `autoupdate` drill gains the § 5.4 cases and stays green; speed-report re-pinned; install-update green; no new CONVENTIONS key
- [ ] heal turns each of the three old model lines into the one new line of minutes.md § 11.1, appends that line in a first heal, and the heal-model-line golden is re-pinned

## T-276 — "The goldens run side by side, with the same output as one at a time"
points 3 · risk normal · landed 95a3676 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/check.sh, ops/tests/check-parallel.cmd, ops/tests/check-parallel.expected, tools/proof.sh

### Why
All 68 goldens take 1,478 seconds one after another; run twelve at a time they take 406 seconds with every one green. This task builds that into `check` itself: it uses the machine's cores (at most twelve), deals the slowest goldens out first, prints results in the usual order with the usual lines, and re-runs alone any golden that only fails beside others, saying so. tools/proof.sh then calls `check` once instead of its own loop. ops/contracts/minutes.md section 6 pins the rules, the one new line and the golden. The help text is written by T-279.

### Acceptance
- [ ] `check --jobs` and its defaults as minutes.md § 6; `--update`, one job or one golden keep today's loop byte for byte
- [ ] longest-first dealing from .polaris/check-times by one awk; no `wait -n`, no arrays
- [ ] the alone re-run and its note line, byte-exact
- [ ] golden `check-parallel` is new and green; tools/proof.sh step 3 is one `check` call and proof-ci stays green
- [ ] only `_private` names are added; kit/ops/polaris and api-kit are untouched

## T-277 — "The end of a run never stalls on housekeeping or proves the same thing twice"
points 5 · risk normal · landed 30945b7 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/builder.sh, kit/ops/lib/drift.sh, kit/ops/lib/integrate.sh, kit/ops/lib/qa.sh, kit/ops/lib/selftest/policy.sh, kit/ops/roles/INTEGRATOR.md, ops/tests/qa-stamp.cmd, ops/tests/qa-stamp.expected, ops/tests/self-land-finish.cmd, ops/tests/self-land-finish.expected

### Why
Both of the last sprints ended red on "the lessons list is too long" and needed a hand fix, and every task runs its checks two or three times: at verify, again at handoff, and again after landing, on the very same code. This task makes the two housekeeping findings advice that never turns anything red, lets handoff and run-verify skip re-running checks that were already proven on the same code (and say so), proves that a lane which lands itself ends with a green finish and no clean-up, and updates the integrator's instructions to match how waves now run. It also carries T-278's one drill line, because it owns that file this wave. ops/contracts/minutes.md section 7 pins every line.

### Acceptance
- [ ] the two doc-overflow findings print as the § 7 advisory lines and never turn drift --strict, qa or finish red, nor withhold the suite stamp
- [ ] verify writes .polaris/verify-stamp/<ID>; handoff and run-verify skip with the two pinned lines exactly when § 7 says
- [ ] golden `self-land-finish` is new and green; qa-stamp re-pinned; finish-blocked and drift-deps green
- [ ] policy.sh's route check expects 3 lines as § 7 pins
- [ ] INTEGRATOR.md: no typed `git checkout -b`, `bg wait --max 120`, the wave gate is the verify lines with the full proof in the background; no heading text changed
- [ ] finish deletes a merged wave branch itself and prints the cleaned line of minutes.md § 11.2; the old caveat prints only when the delete fails

## T-278 — "Helpers are sized by the kit: route names the model and effort for every spawn"
points 5 · risk normal · landed 9c88158 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/KEYS.tsv, kit/ops/PROTOCOL.md, kit/ops/lib/route.sh, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/EVOLVE.md, kit/ops/roles/PLANNER.md, ops/tests/keys-drift.cmd, ops/tests/keys-drift.expected, ops/tests/route-tier.cmd, ops/tests/route-tier.expected

### Why
Every helper in the last sprint ran on the biggest model at maximum effort because it inherited the chat's settings: a one-line version bump cost 73,000 output tokens and 8 minutes. The owner decided helpers are sized to the task. After this task `route` always follows its tier word with the model and effort a spawn should use (small work Sonnet at low effort, normal work Opus at medium, big or risky work Opus at high), never above the chat's own effort, never Fable or Haiku, and any project can override or drop each. The conductor passes both to every spawn, retries a kicked-back task one level higher, and skips the lessons pass when there is nothing to learn. ops/contracts/minutes.md section 8 pins every rule. The help text is written by T-279; the drill line by T-277.

### Acceptance
- [ ] `route` prints the model and effort notes per minutes.md § 8: defaults in code, the overrides, `inherit`, the clamp, the ban untouched
- [ ] KEYS.tsv gains the three effort rows and the model rows show their defaults; route-tier and keys-drift re-pinned and green
- [ ] CONDUCTOR.md, PLANNER.md, EVOLVE.md and PROTOCOL.md say what § 8 says; plain-voice and interview stay green; no heading text changed
- [ ] only `_private` names are added; kit/ops/polaris, core.sh and selftest/policy.sh are untouched

## T-279 — "One call in, one call out: begin and wrap for a small change"
points 3 · risk normal · landed 8bc8814 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/flow.sh, kit/ops/polaris, kit/ops/roles/BUILDER.md, kit/ops/roles/SOLO.md, kit/ops/roles/TIDY.md, ops/tests/api-kit.expected, ops/tests/cli-help-parity.cmd, ops/tests/cli-help-parity.expected, ops/tests/flow-solo.cmd, ops/tests/flow-solo.expected

### Why
One small change costs about ten separate commands today, 98 seconds of pure command time before any thinking. This task adds two commands that run the existing ones in order: `begin <draft>` files the task, checks it is a one-person job, claims it and prints its context; `wrap` hands it off, lands it when that is the setup, asks what is next and runs the closing check when that is the answer. No gate changes. The SOLO and BUILDER guides use them. This task also owns the help text for T-276's `--jobs` and T-278's two route notes, written byte for byte from ops/contracts/minutes.md section 9.4.

### Acceptance
- [ ] `begin` and `wrap` behave as minutes.md § 9.1–9.2, calling only existing commands; the non-solo case exits 3 with the pinned line
- [ ] the loader gains `flow` after `author`; the dispatch arms and every help line of § 9.4 are byte-exact; the entry stays under 500 lines
- [ ] SOLO.md uses begin and wrap; BUILDER.md drops the separate verify before handoff
- [ ] api-kit gains the begin/wrap rows; cli-help-parity expects 14; golden `flow-solo` is new and green
- [ ] TIDY.md carries the three wording fixes of minutes.md § 11.3 and stays within 90 lines and its four headings

## T-280 — "Release 6.14.0 - the speed release: version and changelog (LAST)"
points 1 · risk normal · landed 54258f4 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
Change version: in kit/ops/VERSION to 6.14.0 and leave every other line of that multi-line keyed file exactly as is. Add a '## 6.14.0 — 2026-11-09' entry at the top of CHANGELOG.md in the same plain-language style, with no task IDs, saying what ops/contracts/minutes.md section 10 lists. Tag, publish, dogfood and update --all are the conductor's steps, not this task.

### Acceptance
- [ ] every verify line passes (VERSION is multi-line: use grep, never test "$(cat kit/ops/VERSION)" = ..., the T-217 trap)

## T-281 — "The route drill expects the sized notes everywhere: tier, then model, then effort"
points 2 · risk normal · landed 5905a24 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/selftest/policy.sh

### Why
Since this release `route` always prints three lines: the tier word, then the model, then the effort (minutes.md § 8). The route drill was updated for that in its first section only. Its later sections still count lines the old way, so the drill fails on the combined code: it expects two lines where a tier's model is set in the project's settings and one bare word where it is not, and both are now three. The drill is what CI runs on three systems, so it must say what the command really does.

### Acceptance
- [ ] every assertion in the route drill (`drill_route` in kit/ops/lib/selftest/policy.sh, sections 3 onward) matches what `route` prints under minutes.md § 8: line 1 the bare tier, line 2 `   model: <name>`, line 3 `   effort: <level>`, with a project's `model_<tier>` value on line 2 when it is set and the built-in default when it is not
- [ ] the comments beside those assertions say the same thing (no "mid must stay a bare word")
- [ ] `bash kit/ops/polaris doctor --selftest --only route` passes, run once by hand through `bg run` (not in verify: it takes 2–4 minutes)
- [ ] nothing outside the route drill changes

## T-282 — "A skipped check rests on a real proof: the stamp names the commit and the check list it proved"
points 3 · risk normal · landed a80a748 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/builder.sh, kit/ops/lib/integrate.sh, ops/tests/self-land-finish.cmd, ops/tests/self-land-finish.expected, ops/tests/verify-stamp.cmd, ops/tests/verify-stamp.expected

### Why
This release let a landing skip a task's checks when the landed code was identical to what the builder had. Identical code proves nothing by itself: it does not say a green check ever ran on it, and it does not say the list of checks is still the one that ran. CI caught it: one drill edits a task's check list to a failing line and expects the landing to refuse, and the landing sailed through. The stamp a green check leaves behind now records both the commit it proved and a fingerprint of the check list, and nothing is skipped unless both still match.

### Acceptance
- [ ] the stamp is one line, `<sha> <crc>-<bytes>`, exactly as ops/contracts/minutes.md § 12 pins it
- [ ] handoff skips the checks only when the stamp's commit is HEAD, the list fingerprint matches the task file now, and the worktree is clean
- [ ] run-verify skips only when the trees match, nothing is modified, a stamp names the task branch's tip, and the list fingerprint matches; with no stamp, an old one-field stamp or a changed list, the checks run
- [ ] `done` removes the stamp; `amend` still does
- [ ] golden `verify-stamp` is new and covers the seven cases of § 12; `self-land-finish` is re-pinned for the two-field stamp; api-kit does not move (private names only)
- [ ] `bash kit/ops/polaris doctor --selftest --only express` passes, run once by hand through `bg run` (not in verify: it takes 2-4 minutes)

## T-283 — "The update drill checks that nothing was pushed by comparing before and after, so it passes in any drill order"
points 1 · risk normal · landed b169382 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/selftest/remote.sh

### Why
The update drill's new "it commits, and never pushes" case proved "never pushed" by requiring that no remote-tracking ref exists at all. That holds only when the drill runs alone. CI runs every drill one after another in one practice repo, earlier drills leave such refs behind, and the case failed there on Linux and macOS (`AUTOUPDATE (7) PUSH FAIL (no remote ref may appear)`) while passing here. The check now records the remote refs before the update and requires them unchanged after it, which is what "never pushed" means in any order.

### Acceptance
- [ ] case (7) of `drill_autoupdate` records `git for-each-ref refs/remotes` before the update and fails only if that listing differs afterwards; its message says a remote ref moved or appeared
- [ ] any other assertion in `drill_autoupdate` that assumes no earlier drill ran (no remotes, no stashes, no other branches, an empty registry) is made order-proof the same way; none is weakened
- [ ] run one after another in ONE process (no `--parallel`): `bash kit/ops/polaris doctor --selftest --only remote,syncrace,pr-publish,autoupdate,selfland,wtreap,hops` passes; before the fix that same command fails at case (7)
- [ ] nothing outside `drill_autoupdate` changes

## T-284 — "A task with no checks is never called proven: handoff says acceptance is manual, as it always did"
points 2 · risk normal · landed 449e62f (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/builder.sh, ops/tests/verify-stamp.cmd, ops/tests/verify-stamp.expected

### Why
This release lets a handoff skip a task's checks when a stamp shows they already passed on the same commit. For a task that has no checks at all, the handoff started printing "verify: proven at … — not re-run" where it used to say that acceptance is manual. Nothing was proven, so the line is false, and three acceptance checks that pin the handoff's output failed. A task with no checks now behaves exactly as it did before this release.

### Acceptance
- [ ] with an empty verify list, `verify`, `handoff` and `run-verify` print the manual-acceptance line as before, write no stamp (and remove an old one), and never print a "not re-run" line (ops/contracts/minutes.md § 12, v2.4)
- [ ] the goldens `guide-stale`, `pack-visual` and `shots-gallery` pass with their .expected files UNCHANGED
- [ ] golden `verify-stamp` gains case (8) for the empty list; its other cases and `self-land-finish` stay green
- [ ] api-kit does not move (private names only)

## T-285 — "An update commits itself every time: it lists the files first, then stages them, and says why if it cannot"
points 3 · risk normal · landed 50df2aa (2026-11-09) · claimed 2026-11-09
files touched: kit/ops/lib/admin.sh, kit/ops/lib/selftest/remote.sh

### Why
After an update, POLARIS commits the files it changed so the project is left clean (minutes.md § 5.1). On macOS that commit did not happen in three CI runs out of three, and the update gave no reason. The cause is in how the files are staged: one pipeline runs `git status`, a filter and `git add` at the same moment, and the two git commands both want the same lock. When `status` gets there first, `add` gives up before reading anything. The safe fallback kicked in each time (nothing committed, nothing lost), but 6.14.0 cannot be released while macOS is red, and the same collision can happen on any machine. Contract: minutes.md § 13.

### Acceptance
- [ ] the staging in `cmd_update` (kit/ops/lib/admin.sh, the block headed "THE SELF-COMMIT") computes the list of paths first, into a variable, and only then runs `git add --pathspec-from-file=-` with it; the status + awk that builds the list is unchanged
- [ ] an empty list still means no `add`, no commit and no extra line
- [ ] when the `add` or the `commit` fails and git's message names `index.lock`, it waits 1 second and tries again, 3 tries in all; any other failure is not retried
- [ ] when it still cannot stage or commit, the index is left empty, today's note prints, and one more note gives the reason in the exact shapes of minutes.md § 13 ("Never silent")
- [ ] `update --auto` still prints exactly one line in every case
- [ ] in `drill_autoupdate` (kit/ops/lib/selftest/remote.sh), each case that expects the update to commit first checks that HEAD is exactly one new commit on top of where the case started, with the pinned subject, and fails with `AUTOUPDATE (<n>) COMMIT FAIL (…)` when it is not: at least (5), (5b), (7), (9), and (1) if its fixture meets every condition of § 5.1
- [ ] two new drill cases, (10) and (10b), as minutes.md § 13 "Executable checks" describes, using a `git` stand-in on PATH
- [ ] `bash kit/ops/polaris doctor --selftest --only autoupdate` passes here, run once by hand through `bg run`
- [ ] the drill is green on CI's Linux run AND its macOS run of this task's own commit: `PROOF_GOLDENS=true bash tools/proof.sh`, then `bash tools/proof.sh --await macos-latest`, each run once by hand through `bg run` (never in verify)

## T-286 — "wrap ends green when it is typed from the task's own folder, and says the leftover folder clears itself"
points 3 · risk normal · landed d90a23f (2026-11-09) · claimed 2026-11-09
files touched: kit/ops/lib/drift.sh, kit/ops/lib/qa.sh, kit/ops/lib/workspace.sh, ops/tests/wrap-own-folder.cmd, ops/tests/wrap-own-folder.expected

### Why
`wrap` is the one command that finishes a small change: it hands the work off, lands it, and runs `finish`. The role files tell every agent to type it from the task's own folder. Typed that way it always ends red: the folder cannot be removed while the command is running out of it, its branch stays with it, and the board check then calls that branch a leftover (`CRUFT: feat/<ID> still exists though <ID> is done`), so `finish` exits 1. The work itself is fine (landed, sealed, done). Found by installing 6.14.0 into a brand-new project and running one change start to finish. Contract: minutes.md § 14.

### Acceptance
- [ ] one private helper `_wt_stood_in <ID>` in kit/ops/lib/workspace.sh holds the two tests of `wt_remove`'s first guard (the running script inside that worktree, or the current directory inside it), moved without change; `wt_remove` uses it and prints exactly what it prints today in every case
- [ ] `drift`'s leftover-branch check (kit/ops/lib/drift.sh, the block commented "3) cruft") treats a done task's worktree that the running command stands in like a live beat: no finding
- [ ] `finish` (kit/ops/lib/qa.sh, the loop that prints `worktree .polaris/wt/<n> has no active task …`) prints the § 14 caveat instead for such a worktree, and today's line for every other one
- [ ] new golden `wrap-own-folder`, exactly as minutes.md § 14 describes: the kit installed inside the fixture, default landing, `wrap` typed from inside the worktree ends rc 0 with finish complete; then a `finish` from the project folder removes the folder and the branch
- [ ] the golden fails on today's code (run it once before the fix and report what it printed) and passes after
- [ ] `flow-solo`, `self-land-finish`, `finish-blocked` and `drift-deps` still match without being re-pinned
- [ ] CI's Linux run of the full self-test is green on this task's own commit: `PROOF_GOLDENS=true bash tools/proof.sh`, once, by hand, through `bg run` (never in verify)
