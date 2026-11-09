# Sprint 21 — The tidy pass, hardened (6.13.0) (2026-11-06–)

## T-258 — "hops sees a tidy pass's own work: its own branch, finished tasks' branches and its land commit stop skewing the report"
points 5 · risk normal · landed 042b826 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/index.py, ops/tests/hops-map.expected, ops/tests/hops-pass.cmd, ops/tests/hops-pass.expected

### Why
The first real tidy pass worked, but `polaris hops` misread the pass's own work in three ways. Run
from the task's worktree, it treated the task's own branch and its own uncommitted moves as somebody
else's work in progress, so every moved file was frozen: no folder guides were offered for the new
folders, and the after-score was wrong (it said 2.37 → 1.31 when the truth was 2.80 → 1.34). After the
task finished, its kept branch kept those files frozen on main too, until it was swept. And the pass's
own landed commit, which moves 31 files at once, was counted as one ordinary change, so it tied every
feature together through one shared file and the leftover search files were never proposed again.

This task fixes all three inside index.py. A worktree on `feat/<ID>` never counts its own changes or
its own branch as in flight; a task already finished on the board never counts either; in a task
worktree the history is read from HEAD; and the task's own commits, plus any commit that records a
layout pass in `ops/LAYOUT.tsv`, only follow renames and never count as a change. It also drops the
folder name a guide's heading repeats (`src/billing/ — invoices` → `invoices`), so the report stops
saying the name twice. A new golden, `hops-pass`, walks a pass on a worktree from start to land.

### Acceptance
- [ ] In flight follows save-hops.md § 12.1: a root on `feat/<ID>` skips its own `git status` and its own branch; every `feat/<ID>` whose task is in done/ on the board ref is skipped, local and remote; excluded refs are dropped before the log, never as one --exclude per task
- [ ] History follows § 12.2: HEAD in a task worktree; commits in `<base>..HEAD` and commits touching ops/LAYOUT.tsv map renames but are never a kept change; every other § 1.3 rule unchanged
- [ ] The purpose line follows § 12.3 (prefix `<dir>/ — ` dropped once, only when text follows) — the same rule T-261 builds into guide_purpose
- [ ] New golden hops-pass: in a fixture with a task worktree holding committed moves, `POLARIS_ROOT=<wt>` `--tsv` shows GUIDES rows for the new folders and no moved file frozen; line 1 of bare `hops` there equals line 1 on main after the squash land; after that land (one commit with LAYOUT.tsv rows, the board ref listing the task in done/, its branch kept) `--tsv` on main still prints MOVE rows for the cluster left behind
- [ ] hops-map, hops-moves and hops-due are green, re-pinned only where § 12.1–§ 12.3 change what they print (say which line moved and why in Notes)
- [ ] No new public name in index.py (every new def/constant starts with `_`): its api-kit rows are unchanged

## T-259 — "A wave that crosses midnight still closes, and a refused close leaves nobody stranded on the wave"
points 3 · risk normal · landed 4009585 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/lib/builder.sh, kit/ops/lib/integrate.sh, ops/tests/seal-fallback.cmd, ops/tests/seal-fallback.expected

### Why
Closing a wave of work can go wrong in three small ways that each leave a mess behind. A wave that
starts before midnight and lands its last task after it can no longer be closed without typing its
date, because the closing step looks only for a wave started today — and the self-landing path never
types a date. When closing refuses early (the sprint file has no `# SPRINT <n> — <goal>` line, or the
sprint number was already used), the main checkout is left sitting on the wave instead of going back
to the main line. And a task that lands itself with no sprint line in place gets landed onto a wave
that can then never close, which is exactly how the first live tidy pass got stranded.

So: closing with no date now uses the one open wave when none was started today (and says so); the
two early refusals put the checkout back on the main line before they stop; and a task about to land
itself first checks the sprint line, and when it is missing it stays in review with one line saying
what to add and what to run next, instead of landing onto a wave that cannot close.

### Acceptance
- [ ] save-hops.md § 15.1: no date + no `integrate/<today>` + exactly one open wave → that wave is sealed after the pinned note line; none → today's die unchanged; two or more → the pinned die naming them, dates ascending; `seal <date>` and `seal --sync` unchanged
- [ ] § 15.2: the unreadable-number and reused-number refusals switch the primary back to `<base>` when it sits on `integrate/<date>`, then die with today's text byte-for-byte
- [ ] § 15.3: self_land checks the sprint number before every land; none → no land, the task stays in review/, handoff rc 0, the pinned ⚠ line exactly once
- [ ] New golden seal-fallback covers the five cases of § 15.4
- [ ] The spine's SECOND-SEAL path still passes (`bash kit/ops/polaris doctor --selftest --only selfland`, run once by hand — the spine rides every --only run); api rows of both files unchanged (no new public fn)

## T-260 — "The first update from an older POLARIS offers the layout pass, and an update never rewrites settings it did not change"
points 3 · risk normal · landed 8a53e05 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/install.sh, kit/ops/lib/admin.sh, ops/tests/install-update.cmd, ops/tests/install-update.expected

### Why
Two things went wrong when the practice shop and the test repo were updated. First, the update that
brings a repo onto the new layout tooling is run by the OLD updater, which knows nothing about the
layout pass — so the one line that says "the layout pass is due, here is how to run it" never
appeared on that first jump. Second, the update rewrote `.claude/settings.json` even when nothing in
it changed, and on Windows it turned every line ending into CRLF: 312 lines of noise in a diff the
owner is asked to review.

This task fixes both at the installer. The settings file is left untouched when merging changes
nothing, and keeps its own line endings when something does change. The new updater tells the
installer it will print the layout line itself; when an older updater runs the new installer on a
set-up repo and the pass is due, the installer prints that line itself, once. Any updater already
runs `upgrade`, so the installer stops telling it to; a zip install still gets that hint.

### Acceptance
- [ ] save-hops.md § 16.1: both settings.json writers skip the write when the merged object equals the original, and otherwise keep the original's CRLF or LF
- [ ] § 16.2: cmd_update passes `POLARIS_UPDATE_HINTS=1` to install.sh (that one line; nothing else reads the marker)
- [ ] § 16.3: the three `live board: finish it with…` notes print only when POLARIS_SHA is unset — a zip install keeps them (ci.yml greps `polaris upgrade` in .polaris/install.log on that path)
- [ ] § 16.4: the save-hops line prints once, last, after the routing line, exactly when all five conditions hold; the two pinned strings; never on a fresh install
- [ ] New golden install-update covers every case of § 16.6, hermetic (HOME, USERPROFILE and POLARIS_AWAKE_HOME inside its temp dir)
- [ ] `doctor --fast` stays green (its update_hops_hint and update_dirt cases unchanged); api rows of both files unchanged (no new public fn)

## T-261 — "Folder guides and the root map stay true: no doubled folder names, no folders that are gone, and drift names the stale map rows"
points 3 · risk normal · landed 54c5a7b (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/lib/knowledge.sh, kit/ops/lib/observe.sh, ops/tests/where-map.cmd, ops/tests/where-map.expected

### Why
The short "where things live" map at the top of a project's CLAUDE.md, and the knowledge base POLARIS
reads first, both quote each folder guide's one-line purpose. The guide template starts that line
with the folder's own name, so every reader printed it twice: `src/billing/ — src/billing/ — invoices`.
And the map kept listing folders that no longer exist — after the first tidy pass moved everything
out of `src/components/`, the map still sent agents there, because the project map it is built from
never forgets a row.

This task drops the repeated folder name when a guide's purpose line starts with it, makes the map
skip any row whose path is no longer tracked, and has `drift` print one gentle advisory per stale row
of the project map (`MAP STALE: ops/MAP.md lists <path> (missing)`), so the next EVOLVE pass can
retire it. Agents never edit the project map themselves; the advisory never stops a run.

### Acceptance
- [ ] save-hops.md § 12.3 / § 14.1: guide_purpose drops a leading `<dir>/ — ` once, only when text follows — the same rule T-258 builds into index.py
- [ ] § 14.2: `where` keeps an item only when its path is a tracked file or a folder holding a tracked file, read from ONE `git ls-files` into a temp file (never an environment variable); the 13-item cap counts survivors
- [ ] § 14.3: drift prints `advisory: MAP STALE: ops/MAP.md lists <path> (missing)` once per dropped MAP item, MAP order, right after the GUIDE STALE lines; never counted, never red; where and drift share ONE parse (a private helper — no new public fn, no copied awk)
- [ ] § 14.5: where-map re-pinned with every listed case; where-done green (re-pinned only if its delta path is not a tracked file there); guide-stale unchanged
- [ ] api rows of knowledge.sh and observe.sh unchanged

## T-262 — "polaris new: file tasks in one command, with IDs, checks and the ready gate (review counted), in one board commit"
points 5 · risk normal · landed 8ef0291 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/lib/author.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/cli-help-parity.cmd, ops/tests/cli-help-parity.expected, ops/tests/new-task.cmd, ops/tests/new-task.expected

### Why
Every lane that files a task today writes the board files and the board commit by hand: SOLO's first
step, the tidy pass's step 5, and the Planner. Each agent re-derives the recipe, picks an ID by eye,
and checks the ready rules in its head — and in sprint 20's last wave, five tasks that shared files
with tasks still waiting to land were put on the board side by side, because the ready check never
looked at work waiting in review. The merges were clean only by luck.

`polaris new <draft.md>…` does it in one call. Each draft, written from the task template, gets the
next free ID and is checked (points 1–5, a plan name, a risk level, at least one owned file, and the
contract it names exists). Then the ready gate places it: ready, or backlog while it waits on another
task — and a task in ready, active or review that shares a file with it is added to what it waits on,
so it can never be built beside one. All the drafts land in ONE board commit, and any refusal writes
nothing at all. It lives in a new module, kit/ops/lib/author.sh.

### Acceptance
- [ ] ops/contracts/task-author.md § 1: `cmd_new` in kit/ops/lib/author.sh (its only public fn), the loader gains `author` after `skills`, the dispatch arm and the help block exactly as pinned
- [ ] § 3: every check, all-or-nothing, with the pinned refusal lines; refuses on feat/*
- [ ] § 4–§ 6: IDs, placement (review/ counted, earlier drafts counted), the task file edits, one `evt new` per task, ONE board commit `chore(board): new <IDs>`, sync_board; SPRINT.md never touched; drafts never modified
- [ ] § 7: one stdout line per draft in the pinned shapes, rc 0
- [ ] New golden new-task covers § 10; cli-help-parity re-pinned to 12 (`new` joins its alternation); api-kit.expected gains exactly the one cmd_new row (strict diff green)
- [ ] The entry stays under 500 lines, author.sh at most 250, startup-budget green

## T-263 — "Measure, don't assume: do folder guides load by themselves? Seven headless sessions, the answers written into the plan"
points 1 · risk normal · landed 5f5e889 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: plans/tidy-hardening.md

### Why
POLARIS's protocol says what reaches an agent by itself — does a folder's CLAUDE.md guide load when an
agent reads, edits or creates a file in that folder, in a subagent, or through a worktree path? Last
sprint's probe could not answer: no headless session could sign in, so all seven answers were
"unknown", and the protocol was written to count on none of them. The owner has said they will sign
the command-line Claude in, so this run measures it again.

This task runs the same seven headless sessions in a throwaway repo and writes their answers, the
harness version, the date and the seven raw replies under a `## Measurements` heading at the end of
the plan. If `claude -p` still cannot sign in, every answer is an honest `unknown`, one line says why,
and the task hands off green — it never holds the sprint up. The protocol text that cites these
answers is corrected afterwards by T-266.

### Acceptance
- [ ] ops/contracts/save-hops.md § 9's recipe and prompts, unchanged, run in a throwaway repo committed before the first session (the § 9 layout, a `.polaris/wt/T-1` worktree on `feat/T-1` included)
- [ ] `## Measurements` is the LAST heading of plans/tidy-hardening.md: the seven `probe: <key>: yes|no|unknown` lines, the harness version and date, the seven raw replies beneath; values only from what a session echoed — a refusal or a 90 s hang is `unknown`
- [ ] Signed out → seven `unknown` lines plus one line saying `claude -p` could not sign in; handoff green either way
- [ ] The handoff report names `worktree-root-claudemd-reloads: yes` when it is (the conductor files ONE IDEAS line); nothing else in the plan file changes

## T-264 — "hops proposes whole features, names a tidy task's whole file list, and says what a guide should tell you to leave alone"
points 5 · risk normal · landed 1907d93 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/index.py, kit/ops/polaris, ops/tests/hops-due.cmd, ops/tests/hops-due.expected, ops/tests/hops-map.cmd, ops/tests/hops-map.expected, ops/tests/hops-moves.cmd, ops/tests/hops-moves.expected, ops/tests/hops-pass.cmd, ops/tests/hops-pass.expected

### Why
The first live tidy pass had to work around the report in three more places. The proposal was cut
at 25 files mid-feature, so a feature could be half moved and never finished. The task's list of
files it may touch was missing its folder guides — 8 guessed, 3 written, and the commit trailer named
5 files that never existed. And a guide's "leave alone" line had nothing to be written from.

This task adds `hops --propose`, which prints the next pass's moves as plan rows, whole features only
and at most 25 files: a feature that does not fit waits whole for the next pass, and `--due` judges
whether a pass is worth it from the same cut. `--owned` now prints the WHOLE file list of a tidy
task — today's list plus the exact guides the pass will write (the busy folders after the moves),
CLAUDE.md and ops/LAYOUT.tsv — reading importers from whichever tree it is pointed at, so mid-pass
they are named where they now live. `--facts` gains a `leave alone:` line naming the folder's files
that must stay put (generated, vendored, guarded, test-mapped, kept, or public) and why.

### Acceptance
- [ ] save-hops.md § 12.4: `--propose` rows, whole clusters only, ≤ 25, a cluster that would pass 25 waits whole and the walk continues; `--due`'s F′ uses exactly those rows; the three usage strings byte-exact (index.py `_HOPS_USAGE`, `usage()`, the entry's help line)
- [ ] § 12.5: `--owned` = v1's list + the first 8 guides counted after the moves + CLAUDE.md + ops/LAYOUT.tsv, sorted, unique; an empty plan gives the guides-only list; importers come from the tree POLARIS_ROOT names
- [ ] § 12.6: `--facts` prints the `leave alone:` line after `tests:` (≤ 4, the six reasons in their order, `-` when none) and still ≤ 15 lines
- [ ] Goldens: hops-pass gains `--propose` and the in-worktree `--owned` (importers at their post-move paths); hops-moves re-pins `--owned`; hops-map re-pins `--facts`; hops-due green with the new cut (re-pinned only where it moved)
- [ ] No new public name in index.py; the entry's only change is the hops help line; cli-help-parity stays 12

## T-265 — "The tidy role says only what works: whole-feature proposals, a task filed by one command, guides from the file list, nobody stranded"
points 3 · risk normal · landed 2555304 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/roles/TIDY.md

### Why
`ops/roles/TIDY.md` is the whole instruction set for the layout pass, and the first live pass had to
work around it 17 times. It said "tests" where it meant `ops/tests/`, never mentioned that an update
already ran `upgrade`, gave no safe path when the run had no answers, cut the proposal mid-feature,
had the agent hand-write the board files for its task, guessed which folder guides the task would
own, asked for a `verify:` line the tool refuses, sent the agent to an importer lookup that answers
from the wrong copy of the code, and left the after-score and the suite run ambiguous.

This task rewrites the step list so every command in it is one that works as written: the questions
read safely with no answers, `hops --propose` for the proposal, `polaris new` to file the one task
with `hops --owned` as its exact file list, importers taken from the worktree mid-pass, guides taken
from that same list with their "leave alone" line from `--facts`, the true after-score from the
worktree, and the suite run from the worktree. Still at most 90 lines, the same four headings.

### Acceptance
- [ ] Every step change in ops/contracts/save-hops.md § 13 is made, steps 0–8, in the role's own plain voice
- [ ] ≤ 90 lines; exactly the four heading lines of § 7.1 and no other line starting with `#`; the api rows of kit/ops/roles/ unchanged
- [ ] Every command the file names was run once, as written, on a copy of `hops_fixture` with the kit's code before handoff (say so in Notes) — `POLARIS_ROOT=<copy> python kit/ops/index.py hops …` stands in for `bash ops/polaris hops …` until the dogfood
- [ ] Entry and Report keep their substance; no POLARIS command is added to the guide template

## T-266 — "SOLO, the Planner and the manual file tasks with polaris new; EVOLVE retires stale map rows; the protocol states what the probe measured"
points 3 · risk normal · landed 7f386f4 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/roles/EVOLVE.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md

### Why
`polaris new` only helps if the people who file tasks are told to use it. Today SOLO's first step, the
Planner's placing step and the manual each describe writing board files and a board commit by hand.
This task points all three at the one command — the manual keeps a by-hand version for tools that
cannot run commands — and adds `new` to the protocol's command table.

Two smaller follow-ups ride along, each one line. EVOLVE's list of changes it may make on its own
gains "retire each map row drift reports as stale", so the new MAP STALE advisory actually leads
somewhere. And the protocol's paragraph about what loads by itself is rewritten to state exactly
what this sprint's probe measured — a measured yes may be relied on, anything else is not.

### Acceptance
- [ ] ops/contracts/task-author.md § 8: SOLO step 1, PLANNER step 13, the MANUAL paragraph (no new heading) and the PROTOCOL § THE TOOL row, byte-exact where pinned
- [ ] save-hops.md § 14.4: EVOLVE's auto-reversible item 2 reads exactly the pinned line; nothing else in EVOLVE.md changes
- [ ] save-hops.md § 17.2: PROTOCOL § SAVE HOPS's "What loads by itself" paragraph states the seven values recorded under `## Measurements` in plans/tidy-hardening.md, and claims a guide loads by itself only where a value is `yes`
- [ ] No new heading line in any file (fenced `#` lines count); plain-voice green; kit/CLAUDE.md untouched

## T-267 — "The hops drill proves a whole pass on the practice shop, on every system the checks run on"
points 3 · risk normal · landed 0e29d88 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/lib/selftest/hops.sh

### Why
The goldens prove the new layout behaviour here, on one machine. The automatic checks that guard
every release run the drills instead, serially, on three operating systems — and the hops drill
does not yet know any of this sprint's fixes. This task teaches it six cases on the practice shop the
benchmark uses: a pass on its own task branch gets guides offered for the folders it creates; its
landed work ties nothing together, so the features it left behind are still proposed; a proposal
never splits a feature and stays at 25 files; the task's file list names its guides; a guide's
heading no longer repeats the folder name; and mid-pass, the files to fix are named where they now live.

### Acceptance
- [ ] drill_hops gains the six cases of ops/contracts/save-hops.md § 17.1, each failing with its pinned label, asserting rc and row shapes, never prose
- [ ] hops_fixture is unchanged (bench.sh reads its pinned facts); no new public fn (api rows of the file unchanged)
- [ ] `bash kit/ops/polaris doctor --selftest --only hops` passes, run by hand once before handoff, and the whole hops drill stays ≤ 120 s on this machine (say the time in Notes)
- [ ] Each new case was seen to fail once by a deliberate break of the code it guards, and the break's diff was read before the green counted

## T-268 — "Release 6.13.0 - the tidy pass, hardened, and tasks filed in one command: version and changelog (LAST)"
points 1 · risk normal · landed 22c4d17 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
Change version: in kit/ops/VERSION to 6.13.0 and leave every other line of that multi-line keyed file exactly as it is. Add a "## 6.13.0 — <the day it lands>" entry at the top of CHANGELOG.md, above 6.12.0, in the same plain-language style, saying what an owner gets: the layout pass now reads its own work correctly — guides are offered for the folders it creates, its before-and-after numbers are true, and it never ties features together by its own move — and it proposes whole features, never half of one; folder guides and the short map of where things live stop repeating folder names and stop listing folders that are gone, and the project check names the map lines that went stale; a run that crosses midnight still closes, and a refused close never leaves the project stranded; the first update from an older POLARIS offers the layout pass, and an update never rewrites settings it did not change; and `polaris new` files new tasks in one command, keeping work that shares a file in line behind it. No task IDs, no git or test words. Tagging, publishing, the dogfood and the end-to-end checks are the conductor's steps, not this task.

### Acceptance
- [ ] every verify: line passes (VERSION is multi-line: use grep, never test "$(cat kit/ops/VERSION)" = ..., the T-217 trap)
- [ ] the CHANGELOG entry is plain language, no git or test vocabulary, and names no task IDs

## T-269 — "The board's field reader ignores the task template's own guidance comments, so a task filed from TASK.md never owns a comment"
points 2 · risk normal · landed 78e67a9 (2026-11-07) · claimed 2026-11-07 → done 2026-11-07
files touched: kit/ops/lib/core.sh, ops/tests/fm-comments.cmd, ops/tests/fm-comments.expected

### Why
A task filed straight from the task template kept the template's own guidance comments as real values: `files_owned:` came back with "# ONLY paths this task may create/edit …" as an owned path, and `contract:` with "# ops/contracts/<name>.md — MUST exist …" as its contract. The reader trims the leading spaces first and only then looks for a " #" comment, so a value that is nothing but a comment survives. Now that `polaris new` makes filing from the template the normal path, every such task would look like it overlaps every other one. A value or a list item that is only a comment now reads as empty, exactly as YAML means it, and nothing else about the reader changes.

### Acceptance
- [ ] `fm_get` returns nothing for `key:   # a note`, and still returns `value` for `key: value  # a note`
- [ ] `fm_list` drops a `key:   # a note` scalar and a `  -   # a note` item, and still returns every real item, flow lists and trailing comments included
- [ ] a copy of the real kit/ops/templates/TASK.md, untouched, yields no files_owned, surface, verify, approved or context_files items and an empty contract
- [ ] a value with `#` inside it but not at its start (`title: Fix #12`) reads exactly as before
- [ ] the new-task and api-kit goldens are byte-identical, and `bash kit/ops/polaris doctor --selftest --only fmlist` passes, run once by hand through `bg run`

## T-270 — "Fable is the owner's to pick again in any project: the session guard and the installer stop blocking it, while routing still never picks it"
points 5 · risk normal · landed 490915e (2026-11-09) · claimed 2026-11-09
files touched: CHANGELOG.md, kit/ops/PROTOCOL.md, kit/ops/bootstrap.py, kit/ops/hooks/model-guard.sh, kit/ops/install.sh, kit/ops/lib/admin.sh, ops/tests/heal-model-line.cmd, ops/tests/heal-model-line.expected, ops/tests/machine-armed.cmd, ops/tests/machine-armed.expected, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected, ops/tests/update-arms.cmd, ops/tests/update-arms.expected

### Why
The owner lifted the Fable ban on 2026-11-09. Fable is theirs to pick again in any project: it shows in the model picker, a Fable session is never stopped, and an agent may name Fable when the owner asks. POLARIS's own routing still never picks Fable by itself, and Haiku stays blocked exactly as before. Today three machine-wide layers still block it. The session guard refuses every Fable session and switch. The installer strips Fable from the model picker on every install and update, so a hand fix lasts only until the next install anywhere. And every project's appended efficiency note tells agents "Fable and Haiku are forbidden outright". This change lifts all three and leaves routing untouched.

### Acceptance
- [ ] model-guard.sh refuses Haiku only, on every event. A Fable session, a switch to Fable, a spawn requesting fable and a subagent that ran on Fable pass silently. claude-code-guide is still refused. Every message is exactly the text in ops/contracts/speed.md § 2b.
- [ ] bootstrap.py's merge_model_guard never creates, strips or adds to availableModels again, except the ONE marked restore in § 2b. register=False writes neither the list nor the marker.
- [ ] Heal rewrites exactly the old model line in a root CLAUDE.md, once. A file without it is never written, and a second heal changes nothing.
- [ ] PROTOCOL.md § MODEL ROUTING states the split: routing never picks Fable or Haiku, and a Fable session is the owner's choice. The 6.13.0 CHANGELOG entry gains one plain-language bullet saying Fable is yours to pick again in any project, with no task IDs.
- [ ] route-tier and api-kit are byte-identical (routing and the public API do not move), and `bash kit/ops/polaris doctor --selftest --only hops` still passes, run once by hand through `bg run`.

## T-271 — "The release check proves the published kit is this commit's kit, byte for byte, then runs the quick check"
points 2 · risk normal · landed 8effd32 (2026-11-09) · claimed 2026-11-09
files touched: kit/ops/pack.py, ops/tests/dogfood-bytes.cmd, ops/tests/dogfood-bytes.expected

### Why
Every release ended by re-running the whole self-test one drill at a time on this machine, 37 minutes, after CI had already run that same test on Windows, macOS and Linux. And nothing ever checked that the kit people download is the code that was proven. The release check now compares the published kit with this commit's kit byte for byte, installs it, and runs the 20-second health check: about a minute, and a stronger promise than before. The old full run stays available on request.

### Acceptance
- [ ] the packer builds its file list through one private helper and, for the same commit, writes a zip with the same sha256 as before the change
- [ ] the release check refuses, before installing anything, a kit that differs from this commit's in any file, and names the first file that differs
- [ ] the two stamped lines of the version file never fail the comparison
- [ ] a matching kit installs and passes the quick check, and the closing line is the contract's, byte for byte
- [ ] the `--full` form behaves exactly as the release check did before

## T-272 — "One command proves a commit: CI judges the self-test on Linux while the goldens run here side by side"
points 2 · risk normal · landed b09b2c6 (2026-11-09) · claimed 2026-11-09
files touched: ops/tests/proof-ci.cmd, ops/tests/proof-ci.expected, tools/proof.sh

### Why
The full suite blocked every wave for about 50 minutes on this machine, yet the very same self-test takes under 3 minutes on CI's Linux runner, and CI runs it one drill at a time, which is the stricter test. So the proof moves to where it is fast: one command starts (or finds) the CI run for a commit, runs all the goldens here twelve at a time while CI works, and answers green only when both are green. With no CI in reach it falls back to the self-test on this machine.

### Acceptance
- [ ] `bash tools/proof.sh` follows ops/contracts/minutes.md § 2.1 step by step and prints its lines byte for byte
- [ ] with no CI in reach it says so in one line and runs the self-test here instead (§ 2.2)
- [ ] `--await <job>` and `--report` behave as § 2.3 says
- [ ] the golden covers every case of § 2.5 with a stub in place of `gh`, and never runs the real goldens
