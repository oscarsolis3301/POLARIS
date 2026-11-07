# Sprint 21 — The tidy pass, hardened (6.13.0) (2026-11-06–)

## T-258 — "hops sees a tidy pass's own work: its own branch, finished tasks' branches and its land commit stop skewing the report"
points 5 · risk normal · landed 042b826 (2026-11-07) · claimed 2026-11-07
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
points 3 · risk normal · landed 4009585 (2026-11-07) · claimed 2026-11-07
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
points 3 · risk normal · landed 8a53e05 (2026-11-07) · claimed 2026-11-07
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
points 3 · risk normal · landed 54c5a7b (2026-11-07) · claimed 2026-11-07
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
points 5 · risk normal · landed 8ef0291 (2026-11-07) · claimed 2026-11-07
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
