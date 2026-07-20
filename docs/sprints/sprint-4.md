# Sprint 4 — One PR, clean graph (2026-07-20–)

## T-005 — polaris grant — a sanctioned way to amend files_owned
points 3 · risk normal · landed 1b171bc (2026-07-18) · claimed 2026-07-18 → done 2026-07-18
files touched: kit/ops/MANUAL.md, kit/ops/polaris

### Why
Field report, 5.6.0, gap 5: invariant 6 says board mutations go through the CLI, but no command can
amend a claimed task's `files_owned` — so the first external repo had to hand-edit the board to finish
a task. `grant` closes the gap while preserving disjointness mechanically (refuse on any overlap with
ready/active ownership).

### Acceptance
- [ ] `polaris grant <ID> <path> -m "why"` implements ops/contracts/grant.md exactly: append to files_owned + Notes line + EVENTS event + one board commit.
- [ ] Refusals (non-zero, board untouched): task not in active/ · missing/empty -m · path overlaps any OTHER ready/active task's files_owned, using the same pattern semantics as `verify` (exact · dir/ prefix · glob).
- [ ] `doctor --selftest` gains a grant drill: one success, one overlap refusal, one missing -m refusal.
- [ ] `kit/ops/MANUAL.md` gains the manual fallback recipe mirroring the command.
- [ ] `polaris` usage/help text lists grant.
- [ ] Bash 3.2 compatible, no new dependencies.

## T-006 — Staleness checks that actually fire — the zip warning and the version cache
points 2 · risk normal · landed 7c9f097 (2026-07-18) · claimed 2026-07-18 → done 2026-07-18
files touched: kit/ops/polaris

### Why
Two staleness checks lie quietly:
1. doctor's stale-zip warning (kit/ops/polaris:532) gates on `$OPS/pack.py` — a pre-split path that no
   longer exists, so the warning README promises can never fire. The last shipped zip rotted exactly
   this way. Gate on the self-hosting tell (`kit/ops/pack.py`, per contract) and fix the rebuild hint
   (`python kit/ops/pack.py`).
2. Field report, 5.6.0, bug 2: explicit `version` (kit/ops/polaris:848) answers from the once-a-day
   update cache and told a user "up to date" while 3 releases behind on release day.

### Acceptance
- [x] Stale-zip check detects the kit source tree exactly per ops/contracts/self-hosting.md (`kit/ops/pack.py`); with a stale `polaris-v5.zip` present it warns, naming `python kit/ops/pack.py` as the rebuild.
- [x] Explicit `version` and `update` always query the channel fresh (keep the 5s timeout; unreachable → fall back to cached value with a note, exactly as graceful as today). Only the passive end-of-command nag keeps the once-a-day throttle.
- [x] Ordinary (non-self-hosting) repos see no new output from doctor.
- [x] `doctor --selftest` stays green; Bash 3.2 compatible; no new dependencies (the existing `command -v unzip` guard pattern stays — Git Bash ships no unzip).

## T-013 — notify v2 in the CLI — POLARIS_SEVERITY, blocked event, notify-gate shim, knob awareness, drills
points 3 · risk normal · landed f440bba (2026-07-18) · claimed 2026-07-18 → done 2026-07-18
files touched: kit/ops/polaris

### Why
The notify: hook fires identically for every board event, so a recipe cannot tell "FYI" from "the
run is blocked on you" — and nothing pings at the exact moments POLARIS waits on a human. This
implements notify v2 from ops/contracts/hands-free-knobs.md: severity in the env contract, a
distinct blocked event, a notify-gate shim the conductor calls at human gates, doctor awareness of
the new autonomy knobs, and selftest drills proving all of it. The shim observes the run; it may
never write the board.

### Acceptance
- [ ] evt() exports POLARIS_SEVERITY per contract (blocked → gate, every other event → info) alongside the v1 vars.
- [ ] `release --to blocked` emits ev "blocked"; `--to ready` keeps ev "release"; `why` reads both names.
- [ ] `notify-gate <kind> [ID]` matches the contract table exactly: env per kind, silent rc 0 when notify: is unset, background/output-discarded/failure-ignored like evt(), NEVER calls evt()/appends EVENTS/takes the mutex/touches the board/commits; unknown or missing kind is a usage error (rc≠0).
- [ ] doctor prints the effective autonomy composition (contract precedence: explicit knob > autonomy:trusted > default) when any of autonomy/plan_gate/builder_questions/evolve_apply/drain/drain_slices is set, and warns on unknown values (which behave as defaults).
- [ ] usage lists notify-gate.
- [ ] selftest gains the contract's drills: no-notify silence · env/severity lines via a temp-file logger for plan/risk/question/done kinds · EVENTS line count + work tree unchanged by the shim · ev "blocked" on release-to-blocked with SEVERITY=gate · SEVERITY=info on an ordinary event.
- [ ] Bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies; existing selftest stays green.

## T-017 — seal per integration wave — sprint tag moves forward, history spans waves
points 3 · risk normal · landed bea57bb (2026-07-18) · claimed 2026-07-18 → done 2026-07-18
files touched: kit/ops/MANUAL.md, kit/ops/polaris, kit/ops/roles/INTEGRATOR.md

### Why
The first real land/seal run (Sprint 3, wave 1) proved the tool conflates "sprint" with
"integration wave": `seal` hard-dies once refs/tags/sprint/<n> exists, and under the squash model
`done` requires the landed [<ID>] commit reachable in base — which only a seal merge provides. Net
effect: a sprint with more than one integration wave can neither seal nor done after wave 1; this
sprint hit it live (wave 1 sealed sprint/3, waves 2+ blocked). Fix per clean-history.md v2: every
wave's seal performs the --no-ff merge; the first seal of sprint n creates tag sprint/<n>; a later
seal of the same n moves the tag forward (git tag -f, pushed compare-and-swap with
--force-with-lease on the tag ref, move clearly logged) so the tag always marks the sprint's
latest sealed checkpoint — end of sprint = final checkpoint. `history --tasks <n>` learns to span
all of the sprint's wave merges instead of assuming one. `done`, `land`, `rollback` code stays
untouched.

### Acceptance
- [x] First seal of sprint n behaves byte-identically to today (merge, message format, lightweight tag created, plain push).
- [x] Later seal of the same n: --no-ff merge as always, then `git tag -f sprint/<n>` onto the new merge; output names the move (old → new short SHAs).
- [x] Tag precondition replaced per contract v2: tag absent OR an ancestor of $BASE → proceed; neither → die naming a reused sprint number (bump the ops/SPRINT.md header). Checked before the merge; nothing mutated on failure.
- [x] Moved tag pushes compare-and-swap: `git push --force-with-lease=refs/tags/sprint/<n>:<old-sha> origin refs/tags/sprint/<n>`; $BASE pushes as today; push-failure note kept.
- [x] `history --tasks <n>` range starts at the OLDEST first-parent merge of $BASE whose subject starts `Sprint <n> — `: `<oldest>^1..sprint/<n>`, --no-merges, chore(board) filter unchanged; single-wave output identical to today.
- [x] `cmd_done`, `cmd_land`, `cmd_task_commit_msg`, `cmd_rollback` are NOT modified (wave-2 done passes via the existing rule-1 gate once its seal lands).
- [x] kit/ops/roles/INTEGRATOR.md § Seal and kit/ops/MANUAL.md § Seal state the wave semantics: seal per wave, tag follows the latest wave, earlier waves revert by SHA (`git revert -m 1 <sha>`).
- [x] selftest gains a `second-seal` drill: wave-2 land on the same integrate branch → seal again green → tag moved (differs from the wave-1 SHA, equals the new base HEAD) → `history --tasks` lists both waves' task commits → the wave-2 task passes `done`.
- [x] Bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies; all existing drills stay green.

## T-018 — kit/CLAUDE.md THE TOOL table catch-up — grant + notify-gate rows, seal/history/rollback v2 wording
points 1 · risk normal · landed 66dc04a (2026-07-18) · claimed 2026-07-18 → done 2026-07-18
files touched: kit/CLAUDE.md

### Why
Sprint 3 shipped grant (T-005) and notify-gate (T-013) and taught seal/history/rollback multi-wave
semantics (T-017, clean-history.md v2), but kit/CLAUDE.md's THE TOOL table — the first thing every
agent reads — still describes Sprint 2's CLI. An agent briefed by the table does not know grant or
notify-gate exist, believes a sprint seals exactly once, and reads `rollback sprint/<n>` as "the
sprint" instead of its latest sealed wave. Bring the table in line with `bash kit/ops/polaris help`:
add a `grant` row and a `notify-gate` row; amend `seal` (a later seal MOVES the sprint tag — the
sprint's latest sealed checkpoint), `history` (`--tasks` spans all a sprint's waves — also in the
one-line history-model sentence below the table), and `rollback` (sprint/<n> reverts the latest
sealed wave). Wording comes from the owning contracts, never invented. The table stays CURATED
(no rows for init-board/resume/task-commit-msg/why/uninstall — admin plumbing); add one clause to
the table intro naming `ops/polaris help` as the full list so the omission reads as intent
(ops/contracts/cli-docs-parity.md).

### Acceptance
- [ ] `grant` row present: append one path to a CLAIMED task's files_owned; refuses any overlap with another ready/active task
- [ ] `notify-gate` row present: fires the notify: hook at a human gate, kinds plan · risk <ID> · question <ID> · done [ID]; observe-only, never writes the board
- [ ] `seal` row says a later seal MOVES the sprint tag — the sprint's latest sealed checkpoint
- [ ] `history` row AND the one-line history-model sentence say `--tasks` spans all a sprint's waves
- [ ] `rollback` row says sprint/<n> reverts the latest sealed wave
- [ ] Table intro gains one clause pointing at `ops/polaris help` as the full command list; NO rows added for init-board/resume/task-commit-msg/why/uninstall
- [ ] Row style matches the existing table (terse, one line per command); diff touches kit/CLAUDE.md only

## T-019 — usage() banner says "POLARIS v4 board CLI" — drop the number so it cannot rot again
points 1 · risk normal · landed 5e3ca23 (2026-07-18) · claimed 2026-07-18 → done 2026-07-18
files touched: kit/ops/polaris

### Why
The first line every `help`/usage caller sees still reads "polaris — POLARIS v4 board CLI"
(kit/ops/polaris:2263, inside usage()'s heredoc) while the whole kit is v5 — the string was
hand-carried through the v4→v5 rewrite and rotted. Decision (ops/contracts/cli-docs-parity.md):
do NOT bump it to v5 — DELETE the number, making the line "polaris — POLARIS board CLI (run from
anywhere inside the repo)". Version truth lives in ops/VERSION and is surfaced by `polaris version`;
a hardcoded number in a banner is a second home for the same fact and will lie again at v6. The
file-header comment at kit/ops/polaris:2 ("POLARIS v5 — board CLI") is accurate and OUT of scope.
One-line string change inside a quoted heredoc — no logic, no case statements, nothing bash-3.2
can trip on.

### Acceptance
- [ ] usage() banner reads "polaris — POLARIS board CLI (run from anywhere inside the repo)" — no version number
- [ ] No "POLARIS v<digit> board CLI" string anywhere in kit/ops/polaris (the :2 header comment "v5 — board CLI" is allowed and untouched)
- [ ] `bash kit/ops/polaris help` still renders and exits 0
- [ ] Diff touches kit/ops/polaris only, and only the one heredoc line

## T-020 — quiet board core — board_commit/sync_board target refs/heads/polaris/board
points 5 · risk normal · landed f4d4013 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
Every claim/handoff/done/release/grant/kickback today commits `chore(board): …` on the base branch
(~3 chores per task), and `sync_board` pushes base after each one — so a hosted repo's history
drowns in board noise, and on a protected main every push fails and the whole board stops syncing.
This is the prerequisite for PR-based publishing: board mutations move to a dedicated ref,
`refs/heads/polaris/board`, committed via secondary-index git plumbing (files stay at their on-disk
paths; no second worktree, no branch switching), and base first-parent stays clean product history.
Everything is specified in ops/contracts/quiet-board.md — implement it, do not redesign it.

### Acceptance
- [x] board_commit commits ONLY the moved set (ops/board/** + ops/SPRINT.md) to refs/heads/polaris/board via GIT_INDEX_FILE plumbing per contract: no second worktree, no checkout; working tree and primary index untouched; commit subjects unchanged; contention retry kept.
- [x] sync_board pushes polaris/board (never $BASE), bounded retry; on rejection it union-appends missing remote EVENTS.ndjson lines, re-parents on the fetched tip, retries — per contract.
- [x] init-board appends .gitignore entries `ops/board/` + `ops/SPRINT.md`; the branch is created (orphan) by the first board_commit.
- [x] All board-file state transitions use plain `mv` — no `git mv` on board paths remains (claim, handoff, release, kickback, done).
- [x] done: non-empty map_delta becomes ONE separate `docs(map): <ID> <first delta line>` commit on $BASE; empty map_delta commits nothing on $BASE; no other board mutation commits on $BASE.
- [x] Existing selftest drills that assert chore(board) commits on the scratch base (grant drill exact-subject check, seal subjects, history filter fixtures — drill region ~:1149-1550) are re-targeted to polaris/board and stay green.
- [x] New drill `quiet-board`: scratch repo → claim → handoff → land → seal → done → polaris/board log carries the chore(board) commits · base first-parent gains ZERO chore(board) commits · a fixture map_delta yields exactly one docs(map) commit on base.
- [x] seal's clean-tree gate stays satisfiable throughout the drill flow (moved set ignored on base, never dirty).
- [x] Bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies; full selftest green.

## T-021 — quiet board lifecycle — upgrade migration, fresh-clone materialization, uninstall, primary-anchored paths
points 5 · risk normal · landed 4464ef3 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
T-020 re-targets board commits for NEW installs; this task makes the change survive the real
world: existing 5.13 boards must migrate (once, idempotently), a fresh clone must be able to
rebuild ops/board/ + SPRINT.md from origin/polaris/board, uninstall must take the branch with it,
and a Builder — whose worktree no longer contains ops/board — must be told the task file's real
(primary-anchored) path by claim/resume. All semantics are pinned in ops/contracts/quiet-board.md.

### Acceptance
- [ ] cmd_upgrade gains the idempotent 5.13→5.14 migration per contract: seed polaris/board (orphan) from the current moved-set state · `git rm -r --cached` the set on base · append the .gitignore entries · ONE final base commit `chore(board): board moves to polaris/board`. Re-run = no-op; no history rewritten; runs only when polaris/board is absent AND the set is tracked.
- [ ] doctor: ops/board/ missing on disk + polaris/board present (local, else origin — local ref created from origin's) → materializes the moved set into the working tree per contract (plumbing, no branch switch) and says what it did.
- [ ] resume performs the same materialization before task lookup, so a fresh clone can resume an active task.
- [ ] uninstall deletes refs/heads/polaris/board (and pushes the deletion when a remote exists); the branch is named in the pre-confirm summary.
- [ ] claim and resume print the task file as a primary-anchored absolute path (under $PRIMARY); the "read:" hint names that location; contract paths stay repo-relative.
- [ ] New drill (upgrade-migration): scratch 5.13-shaped repo (moved set tracked on base, chore(board) history present) → upgrade → branch exists with the board tree · set untracked + ignored on base · exactly ONE new base commit · re-run upgrade = no-op; then claim → handoff → done on a fixture task stays green and base first-parent gains no chore(board) after the migration commit.
- [ ] Bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies; full selftest green.

## T-022 — publish pr mode — local feat branches, one integrate push, PR URL, seal --sync
points 5 · risk normal · landed c4e9eef (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
On a Bitbucket repo with a protected main, POLARIS today pushes every feat branch and tries to
push main directly — the pushes fail, remote main goes stale, and the branch list fills with
"create pull request" nags. This adds the `publish: direct | pr` CONVENTIONS key
(ops/contracts/publish-modes.md): in pr mode feat branches never leave the machine, seal pushes
exactly one integrate branch and prints a ready-made PR-create URL, and `seal --sync` completes
the wave after the human merges the PR (verify subjects, tag, delete the branch). Direct mode is
byte-identical to today except a rejected base push now suggests pr mode.

### Acceptance
- [ ] `publish:` read via cfg per contract: default direct, absent → direct, unknown → warn once + behave direct; never cached.
- [ ] pr: handoff skips the feat/<ID> push; everything else byte-identical (verify, board move, notices).
- [ ] pr: seal per contract — preconditions + clean-history v2 tag gate checked BEFORE anything mutates; NO local merge, NO tag, NO base ref change (local or remote); pushes ONLY integrate/<date>; prints the PR URL (Bitbucket composition, graceful non-Bitbucket fallback) + suggested title `Sprint <n> — <goal>` + the per-task bullet description; fires `notify-gate done`.
- [ ] seal --sync per contract, steps 1-5: clean tree + ff-only pull · every `[<ID>]` subject of the wave verified in base or die naming the missing · sprint/<n> tag create/move per clean-history v2 with compare-and-swap push and by-hand fallback note · integrate/<date> deleted local+remote · next-step note (run-verify/done per task). In direct mode --sync dies with the contract's message.
- [ ] direct: seal's rejected base-push note gains the one-line `publish: pr` suggestion (stamp file + doctor warning are T-024, not here).
- [ ] usage/help lists `seal --sync` and the publish: key.
- [ ] New drill `pr-publish`: scratch bare origin + publish: pr → claim→handoff (ls-remote shows NO feat/*) → land → seal (ls-remote shows integrate/<date>; origin base unmoved; no local merge happened) → simulate the PR merge (--no-ff merge of integrate into base pushed to the bare origin from a temp clone) → seal --sync green (tag on origin, integrate branch gone both sides) → done <ID> green.
- [ ] All existing direct-mode drills stay green (default unchanged); bash 3.2 compatible (NO `case` inside `$(...)`), POSIX awk, no new dependencies.

## T-023 — sprint reports — polaris report + seal auto-commits docs(sprint-N) on the wave
points 3 · risk normal · landed fb9e0e2 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
Task files hold the whole story of a sprint — why, acceptance criteria, ownership, landed sha —
but they live in ops/board/done/ where management never looks. `polaris report` renders a
per-sprint markdown file (default docs/sprints/sprint-<n>.md) from the board + git history, and
seal generates/refreshes it for the wave being sealed and commits it on the integrate branch, so
the report rides the same merge/PR into base with zero extra steps. Past sprints render too
(--sprint n / --all) — that back-fills repos whose history predates this feature. Format and ID
resolution are pinned in ops/contracts/sprint-report.md.

### Acceptance
- [ ] `polaris report [--sprint <n> | --all]` per contract: no flag = current sprint from the top SPRINT.md header; writes <reports>/sprint-<n>.md whole (idempotent), prints the path(s); never commits; board read-only.
- [ ] `reports:` CONVENTIONS key honored, default docs/sprints/.
- [ ] Renderer seam per contract: explicit sprint number + task-ID list + ref-to-grep parameter; cmd_report resolves IDs (layered rules 1-3, degrade-not-die); cmd_seal calls the renderer directly with the wave's subjects (ref = integrate/<date>).
- [ ] Per-task section per contract: ID, title, points, risk, landed short sha + date, claimed→done dates from EVENTS, files touched via diff-tree (fallback files_owned), `## Why` body verbatim, acceptance checkboxes verbatim; missing data omits the field, never dies; no generation timestamp.
- [ ] seal (both publish modes) generates/refreshes the report and commits `docs(sprint-N): report` on integrate/<date> BEFORE the merge (direct) / the push (pr); the commit carries no [<ID>] suffix.
- [ ] usage lists report.
- [ ] New drill `report`: fixture task with Why + acceptance + landed sha → report file contains the ID, the title, an acceptance line, and the landed sha; the seal path asserts a `docs(sprint-` commit rides the wave.
- [ ] Bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies; full selftest green.

## T-024 — remote hygiene — sweep flags merged integrate branches, doctor warns on rejected base pushes
points 2 · risk normal · landed 842a3d6 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
Two small leaks remain after pr-mode lands: a pushed integrate/* branch whose wave already merged
can linger on origin forever (nothing owned deleting it before seal --sync existed, and direct-mode
repos push integrate branches too), and a repo on `publish: direct` against a protected main fails
its base push at every seal with only a by-hand note — nothing ever tells the human the durable
fix. sweep learns an integrate-branch stray pass; seal stamps rejected base pushes and doctor
reads the stamp to recommend `publish: pr`. Both per ops/contracts/publish-modes.md.

### Acceptance
- [ ] sweep: for each remote integrate/* branch, tip an ancestor of $BASE (wave merged) → flagged as stray, deleted by --fix; tip not in $BASE → flagged, NEVER auto-deleted; wording matches sweep's existing stray/diverged style.
- [ ] seal (direct): a rejected $BASE push stamps $PRIMARY/.polaris/base-push-rejected (date + incremented count); a successful base push deletes the stamp.
- [ ] doctor: stamp count >= 2 → warns per the contract's message, recommending publish: pr; no stamp or count < 2 → silent.
- [ ] Selftest extended minimally: an integrate-stray assertion inside an existing bare-origin drill (merged → flagged + --fix deletes; diverged → flagged, kept); all existing drills stay green.
- [ ] Bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies.

## T-025 — protocol docs — CLAUDE.md invariant 6 + MANUAL recipes for the quiet board and pr publishing
points 3 · risk normal · landed 14f4218 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/CLAUDE.md, kit/ops/MANUAL.md

### Why
The protocol file and the manual still describe the old world: invariant 6 says board mutations
"commit on the base branch", and every MANUAL fallback recipe (claim, handoff, grant, done, seal,
EVENTS) writes chore(board) commits on base. Once the 5.14 CLI targets polaris/board and grows
publish: pr / report / seal --sync, an agent following these docs would corrupt the very histories
the release cleans up. MANUAL must mirror the CLI byte-for-byte in behavior; both files are
rewritten strictly from the three contracts — no invented behavior.

### Acceptance
- [ ] kit/CLAUDE.md invariant 6 reworded per quiet-board: board mutations go through ops/polaris and commit on refs/heads/polaris/board; code commits on feat/<ID>; never mix. Same terseness, same numbering.
- [ ] kit/CLAUDE.md tool table: seal row covers pr mode + seal --sync; a report row exists; sweep row mentions merged integrate/* strays; no stale "commits on base" claim anywhere in the file.
- [ ] MANUAL claim/handoff/grant/done/kickback recipes re-target board commits to polaris/board via the contract's secondary-index plumbing recipe (one shared "board commit by hand" block referenced by each, incl. the EVENTS union note); plan-commit recipe: moved set → polaris/board, contracts/MAP stay on base.
- [ ] MANUAL seal section documents both publish modes: direct (today's fold + tag) and pr (report commit → push integrate only → PR URL → human merges with MERGE COMMIT strategy → seal --sync steps 1-5 by hand); done's map_delta recipe becomes the separate docs(map) base commit.
- [ ] MANUAL gains fresh-clone materialization and 5.13→5.14 migration recipes (the by-hand equivalents of doctor/upgrade per quiet-board).
- [ ] Every recipe states only what the contracts state — zero behavior invented beyond ops/contracts/{quiet-board,publish-modes,sprint-report}.md.

## T-026 — role docs — INTEGRATOR publish modes, BUILDER primary-anchored paths, INIT publish key, PLANNER plan commit
points 2 · risk normal · landed 8427ed9 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/roles/BUILDER.md, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md

### Why
Four role files still teach the pre-5.14 world. The Integrator needs the two publish modes spelled
out (direct = today; pr = seal → one PR → human merges with the merge-commit strategy →
seal --sync → run-verify/done). The Builder must learn its worktree no longer contains ops/board —
the task file lives in the primary checkout at the path claim prints. INIT must derive/ask the
publish: key (Bitbucket origin → suggest pr) and mention reports:, and its clean-log alias section
predates a base with no board chores. The Planner's plan-commit step must route the moved set to
polaris/board. All strictly from the contracts — no invented behavior.

### Acceptance
- [ ] INTEGRATOR.md step 4 documents both publish modes per publish-modes.md, including the merge-commit-strategy warning and the seal --sync handshake; its board-commit wording (burndown/Learned commit) targets polaris/board; the sprint-report auto-commit is mentioned so the Integrator expects the docs(sprint-N) commit on the wave.
- [ ] BUILDER.md: states the task file lives in the PRIMARY checkout (worktrees have no ops/board), tells the Builder to use the path claim/resume prints, and keeps contract paths repo-relative; no other behavior change.
- [ ] INIT.md: the CONVENTIONS skeleton/interview covers `publish:` (origin matches bitbucket.org → suggest pr, else default direct) and names the `reports:` key + default; the clean-log alias passage reflects a base without new chore(board) commits post-5.14.
- [ ] PLANNER.md step 13: the plan commit routes board files (+ SPRINT.md) to polaris/board per MANUAL's by-hand recipe; contracts stay on base; wording change only, no protocol change.
- [ ] Zero behavior invented beyond ops/contracts/{quiet-board,publish-modes,sprint-report}.md.

## T-027 — qa fixes — report dirty-file hint · convergent tag-push recovery · history --tasks filters report commits · --sync die wording
points 3 · risk normal · landed e2136f6 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
A read-only QA pass over the landed 5.14 kit confirmed four defects in kit/ops/polaris, all small,
none blocking core flows but each able to strand or mislead a user:
1. `report` run after `done` re-renders docs/sprints/sprint-<n>.md with done-dates the sealed
   render lacked, leaving the file modified+uncommitted on base — the NEXT land/seal then dies
   "working tree not clean" with no hint why. report must stay board-read-only and never commit
   (contract), so the minimal fix is: after writing, if the file differs from HEAD, print exactly
   what to do (commit as `docs(sprint-<n>): report refresh`, or discard via `git checkout -- <file>`).
   See sprint-report.md v1.1.
2. The three tag-push failure notes (~:1085, ~:1093, ~:1153) print a recovery command that reuses
   the stale LOCAL lease (`--force-with-lease=refs/tags/sprint/$n:$oldtag`). When the failure cause
   is that a PREVIOUS wave's tag move never reached origin, that lease can never succeed. Print a
   recovery that converges: lease from origin's actual tag (`git ls-remote origin
   refs/tags/sprint/<n>`) or a fetch-then-retry recipe. See clean-history.md v2.1.
3. `history --tasks <n>` — documented as the task-commits view — includes the per-wave
   `docs(sprint-N): report` commits. Filter them like chore(board):. Cosmetic. clean-history.md v2.1.
4. The pr-mode `seal --sync` squash-merge die (~:1141) says "nothing mutated", but step 1's
   --ff-only pull has already moved local base. Correct the wording per publish-modes.md v1.1:
   keep naming the missing IDs, state base is "already fast-forwarded" (pinned phrase) and that
   tag, integrate branch and board are untouched. (The matching MANUAL claim is T-028's, not yours.)

### Acceptance
- [ ] After rendering each file (report_one AND the --all loop), when the written file differs from HEAD (`git diff --quiet -- <file>`) report prints a next-step note naming BOTH remedies verbatim: commit as `docs(sprint-<n>): report refresh` · discard with `git checkout -- <file>`. report still never commits and never writes the board.
- [ ] No tag-push failure note prints the stale local lease: the literal `sprint/$n:$oldtag origin` recovery text is gone from all three notes; each printed recovery converges per clean-history v2.1 (ls-remote lease or fetch-then-retry). The actual CAS push commands themselves are unchanged.
- [ ] `history --tasks <n>` output contains no `docs(sprint-` line; plain `history` behavior unchanged.
- [ ] The --sync missing-subject die names the missing IDs, contains "already fast-forwarded", claims nothing false — the "nothing mutated" clause is gone from that die (the direct-seal reused-sprint drill comment at ~:1759 describes a gate that truly mutates nothing and stays).
- [ ] Existing drills only, extended where a fix is otherwise unverifiable: the `history --tasks 1` drill assertions also prove no `docs(sprint-` line appears. Full selftest green.
- [ ] bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies.

## T-028 — docs parity — INTEGRATOR board-commit mechanism · mode-aware handoff wording · MANUAL --sync die claim
points 2 · risk normal · landed 2885aa6 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/CLAUDE.md, kit/ops/MANUAL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/INTEGRATOR.md

### Why
The same QA pass confirmed three places where kit prose drifted from what the CLI actually does —
each one strands or misleads the agent reading it:
1. kit/ops/roles/INTEGRATOR.md ~:94 tells the Integrator to commit burndown+Learned on the
   polaris/board ref but names no mechanism (no CLI command makes a standalone board commit), so
   the wave's last SPRINT.md edit sits untracked and unsynced. Point it at the by-hand
   board-commit recipe in `ops/MANUAL.md` — exactly the pointer kit/ops/roles/PLANNER.md:31
   already carries (that line is your pattern to copy).
2. kit/ops/roles/BUILDER.md ~:31 and kit/CLAUDE.md ~:36 describe handoff unconditionally as
   "pushes feat/<ID>"; under `publish: pr` it deliberately does NOT push (the branch stays local;
   seal pushes only integrate/<date> — see publish-modes). Make both mode-aware in one line each.
3. kit/ops/MANUAL.md ~:182 (--sync step 2) repeats the false "mutate nothing" claim — step 1 has
   already fast-forwarded local base by then. Align with publish-modes v1.1: die names the missing
   IDs, base is "already fast-forwarded" (pinned phrase), tag/branch/board untouched. The CLI-side
   wording is T-027's; this contract-pinned phrase is what keeps the two tasks in lockstep.

### Acceptance
- [ ] INTEGRATOR.md § Close the loop routes its chore(board) commit "via the by-hand board-commit recipe in `ops/MANUAL.md`" — same wording shape as kit/ops/roles/PLANNER.md:31.
- [ ] BUILDER.md handoff comment (~:31) is mode-aware: pushes feat/<ID> under `publish: direct`; under `publish: pr` the branch stays local and seal pushes only integrate/<date>.
- [ ] kit/CLAUDE.md handoff table row carries the same mode-awareness on its one line; the table stays curated (no new rows).
- [ ] MANUAL.md --sync step 2: "mutate nothing" gone; states the missing IDs are named and base is "already fast-forwarded" with tag/branch/board untouched (publish-modes v1.1). The task-commit-msg "mutates nothing" line (~:115) is accurate and untouched.
- [ ] Wording-only diff — no recipe steps added or removed anywhere; selftest green.

## T-029 — report --all sealed-task attribution — split resolve_sprint_ids local declaration + Rule-2 drill
points 2 · risk normal · landed f2bbe3a (2026-07-20) · claimed 2026-07-20
files touched: kit/ops/polaris

### Why
Testbed verification of the published 5.14.0 found `report --all` rendering sealed tasks under
`## (unsealed)`. Root cause is a bash gotcha in `resolve_sprint_ids` (kit/ops/polaris ~:1292): on a
`local` line, EVERY word is expanded BEFORE `local` performs any assignment, so in
`local n="$1" tag="refs/tags/sprint/$n" prev="refs/tags/sprint/$((n-1))"` the `$n` inside `tag` and
`prev` reads the CALLER's `n`, not the just-assigned `$1`. Two callers (`report_one`,
`seal_report_commit`) happen to hold their own `n` equal to `$1`, so they work by coincidence.
`cmd_report --all` loops with `m` while its own `n` is "" — bash -x trace showed
`local n=1 tag=refs/tags/sprint/ prev=refs/tags/sprint/-1` — so the tag verify fails and Rule 2
(tag-ancestry attribution) silently no-ops. Any sealed task not named by a Rule-1 `[ID]` merge-body
bullet (e.g. a host-merged PR whose message the human wrote) falls to `## (unsealed)`.

Fix: split the declaration — `local n="$1"` on its own line FIRST, then a second `local` line
deriving `tag`/`prev` from it. Semantics per sprint-report v1.2: Rule 2 must resolve the tags from
the function's own argument regardless of caller state.

Drill: the existing selftest fixture seals directly, so its merge body carries `- … [T-1]` and
Rule 1 masks the Rule-2 failure — the current assertions stay green on the buggy code. Extend the
T-023 sprint-report drill (kit/ops/polaris ~:1717) with a Rule-1-blind scenario: neutralize the
`[ID]` bullets (e.g. amend the seal merge body away keeping the `Sprint 1 — …` subject, or add a
sealed done task absent from the body — your call, keep later drills green), run `report --all`,
and assert the task renders under the sprint heading, not `(unsealed)`. That assertion must be RED
against the unfixed function — it is the regression guard that would have caught this.

### Acceptance
- [ ] `resolve_sprint_ids` assigns `n` via its own `local n="$1"` statement before any line that expands `$n`; the combined `local n="$1" tag="refs/tags/sprint/$n" …` declaration is gone. Output for the `report_one` / `seal_report_commit` call paths is byte-identical to today.
- [ ] Extended sprint-report drill: with the sealed sprint's Rule-1 `[ID]` bullets neutralized, `report --all` writes the fixture task under its `# Sprint <n>` file (`^## T-1 — `) and that file contains NO `## (unsealed)` section. The assertion fails when run against the unfixed `resolve_sprint_ids`.
- [ ] All existing sprint-report drill assertions stay green (seal-time render, plain `report`, `--sprint`, path printing, board-read-only, idempotence), and every drill after the extension point still passes.
- [ ] bash 3.2 compatible (NO `case` inside `$(...)` — hard parse error, see SPRINT Learned), POSIX awk, no new dependencies.
