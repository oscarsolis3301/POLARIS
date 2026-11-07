# CONTRACT: task-author — `polaris new`, file tasks in one command (v1 — 2026-11-06)
plan `tidy-hardening` · brief `plans/tidy-hardening.md` § 6 (owner-approved; the owner chose to add this
command, which makes the release 6.13.0). T-262 builds it; T-265 (TIDY.md) and T-266 (SOLO, PLANNER,
MANUAL, PROTOCOL) adopt it. Owned by the Planner; append-only once T-262 is claimed.

## Purpose
Every lane that files a task — SOLO step 1, TIDY step 5, the Planner — writes board files and a
board commit by hand today (the 2026-11-06 IDEAS lines). `new` takes drafts written from
`ops/templates/TASK.md` and files them: IDs, checks, the ready gate with review/ counted, ONE board
commit. The gate also closes wave 4's lesson: a task that shares a file with one still in review/ waits
for it instead of entering ready/ beside it.

## § 1 Interface
- `bash ops/polaris new <draft.md> [<draft.md>…]` — `cmd_new` in a NEW module `kit/ops/lib/author.sh`
  (≤ 250 lines, a 1–2 line header, definitions only, bash 3.2, split `local`s). `cmd_new` is its only
  public fn; every helper is `_new_…`. It reuses `fm_get` `fm_list` `set_fm` `fm_stamp` `task_file`
  `mutex_on` `mutex_off` `evt` `board_commit` `sync_board` `board_pull` (core.sh) and `pat_overlap`
  `rules_gate` `dep_ids` (observe.sh) — never a copy of one.
- Entry (`kit/ops/polaris`, T-262): the full-load `_mods` list gains `author` right after `skills`
  (`… handover skills author selftest/spine …`); the `_match|_rules|_guard` list stays `core ownership`;
  dispatch, directly above the `claim)` arm: `  new)        shift; cmd_new "$@";;` (no
  `update_check_maybe`, no `awake_ensure`). The entry stays < 500 lines.
- Help, directly above the `  claim [ID]` line, byte-exact:
```
  new <draft.md>…                FILE NEW TASKS in one command: each draft, written from
                                 ops/templates/TASK.md, gets the next free T-NNN and is checked
                                 (points 1-5 · plan: · risk: · files_owned · a named contract
                                 exists), then placed by the ready gate: ready/, or backlog/ while
                                 it waits on another task — a task in ready/, active/ or review/
                                 that shares a file with it joins its depends_on. ONE board commit
                                 for all of them; any refusal writes nothing. Refuses on feat/*
```

## § 2 A draft
A file holding a task in TASK.md's shape (frontmatter between `---` lines, then the body). A relative
path is the current directory's, then the primary's. A draft is read and never modified, moved or
deleted. A draft under `ops/board/` is refused (§ 3): a draft lives outside the board.

## § 3 Checks — every draft, before anything is written (all or nothing)
In argument order, the first failure refuses the WHOLE call: one line on stderr, rc 1, nothing
written, no commit, the board ref unmoved. The lines, byte-exact (`<draft>` = the argument as given):
```
⛔ usage: polaris new <draft.md> [<draft.md>…]                                    (no argument)
⛔ new: run it from the primary checkout — a builder never files work for itself   (on feat/*)
⛔ new: <draft>: no such file
⛔ new: <draft>: is inside ops/board/ — a draft lives outside the board
⛔ new: <draft>: no frontmatter — the first line must be ---
⛔ new: <draft>: title: is empty
⛔ new: <draft>: points: must be 1-5 (got <v>) — split anything bigger
⛔ new: <draft>: plan: is empty — every task names the plan it belongs to
⛔ new: <draft>: risk: must be normal or high (got <v>)
⛔ new: <draft>: files_owned: lists nothing
⛔ new: <draft>: contract: <path> does not exist
⛔ new: <draft>: id: <v> is not T-<number>
⛔ new: <draft>: id: <ID> is taken
⛔ new: <draft>: depends_on: <ID> is no task on the board
```
- `points:` is a whole number 1–5. `risk:` is `normal` or `high`. `plan:` must be an uncommented line
  (TASK.md ships it commented). `files_owned:` needs at least one item that is not blank.
- `contract:` blank = none named (most small tasks have no seam); named → the file exists, relative to
  the primary.
- `id:` blank or TASK.md's placeholder `XXX-000` → assigned (§ 4). `T-<digits>` held by no task on the
  board and no earlier draft of this call → kept, so a later draft's `depends_on` can name it.
  Anything else → refused.
- Each `depends_on` entry (both list forms, `dep_ids`) names a task in any board column or an earlier
  draft of this call.
- The feat/* refusal reads the current directory's branch: a Builder never files work for itself
  (Invariant 8 — its idea goes to IDEAS.md).

## § 4 IDs
Under the board mutex, after `board_pull`: next free = 1 + the highest `<n>` of every `T-<n>.md` in any
`ops/board/<column>/` and every id this call has taken so far; printed `T-%03d` (T-007, T-258, T-1000).

## § 5 Placement — the ready gate (Invariant 2), review/ counted
Drafts are placed in argument order, each against the board AND the drafts placed before it:
- **Shares a file** → for every task in `ready/`, `active/` or `review/` — and every earlier draft of
  this call, wherever it went — with an owned pattern that `pat_overlap` says can meet one of the
  draft's, that task's ID is appended to `depends_on` (once, in the order found). This is the chain
  the Planner would write by hand; `review/` is what wave 4 lacked.
- **ready/** iff every `depends_on` is in `done/` AND no `files_owned` entry hits an `ask` rule the task
  is not approved for (`rules_gate <pattern> <ID>` → `ask`). Else **backlog/**, from where
  `bash ops/polaris next --do` promotes it once the gate clears — the promotion pass already re-checks
  everything except review/, and the depends_on added above covers review/.
- `path` rules, `blocked/` and `backlog/` tasks never decide placement (verify, handoff and the
  promotion pass judge those).

## § 6 Writing, and the ONE commit
- Each task file `ops/board/<ready|backlog>/<ID>.md` = the draft's bytes with exactly: `id: <ID>` ·
  `status: <ready|backlog>` · `depends_on:` rewritten as ONE inline line `[<ID>, <ID>]` (the draft's
  entries first, in order, then the added ones; any block-list items under it removed) when an ID was
  added · `wsjf:` when blank and `value:`, `time_criticality:` and `risk_opportunity:` are all
  numbers, (value + time_criticality + risk_opportunity) / points with two decimals. Nothing else
  changes; `owner`, `branch`, `approved` stay as drafted.
- One `evt new <ID> <ready|backlog> <points>` per task, then ONE
  `board_commit "chore(board): new <ID> <ID> …"` (every ID, argument order), `sync_board`, mutex off.
  `ops/SPRINT.md` is never touched — the sprint header stays the Planner's own board commit.

## § 7 Output — one line per draft, argument order, stdout, rc 0
```
<ID> ready — nothing to wait for
<ID> backlog — waits on <dep>, <dep>…
<ID> backlog — needs a human's yes for <scope> first
<ID> backlog — waits on <dep>, …; needs a human's yes for <scope> first
```
`<dep>` = `<DID> (<column>)` for a drafted dependency not yet done, `<DID> (<column>, shares <pattern>)`
for one § 5 added (`<pattern>` = the draft's first owned pattern that meets it; `<column>` = the
column that task is in — for an earlier draft, the one it was just placed in). `<scope>` = the `ask`
rule's scope. Nothing else
is printed on success. Every line passes the plain-voice bar: no trade word from the
`plain-voice` golden's alternation.

## § 8 Adoption — the prose (T-265, T-266)
- **SOLO.md step 1**: the task is written from TASK.md into a draft outside the board (e.g.
  `.polaris/drafts/<slug>.md`), then `bash ops/polaris new <draft>`; the ID it prints is what
  `triage <ID>` and `claim <ID>` take. The by-hand board-commit sentence goes. The rest of step 1 stays.
- **TIDY.md step 5**: save-hops.md § 13.
- **PLANNER.md step 13**: every task is filed with ONE `bash ops/polaris new <draft.md>…` call — drafts
  outside the board; a draft a later draft's `depends_on` must name sets `id:` to a free `T-NNN`; `new`
  applies the ready gate, so a task in ready/ never shares a file with one in ready/, active/ or
  review/. The sprint header in `ops/SPRINT.md` stays a by-hand board commit (MANUAL); step 13b's
  `drift` stays.
- **PROTOCOL.md § THE TOOL**: one row directly above the `ops/polaris claim [ID]` row, byte-exact:
```
| `ops/polaris new <draft.md>…` | file new tasks in ONE command: each draft (from `ops/templates/TASK.md`) gets the next free `T-NNN`, is checked (points 1–5, `plan:`, `risk:`, `files_owned`, a named contract exists) and placed by the ready gate — `ready/`, or `backlog/` while it waits on a task, and a task in `ready/`, `active/` or `review/` that shares a file with it joins its `depends_on`. ONE board commit for all of them; a refusal writes nothing. SOLO, TIDY and the Planner file their tasks with it; `ops/MANUAL.md` keeps the by-hand recipe |
```
- **MANUAL.md**: one bold paragraph inside `## Plan commit (Planner)` — no new heading line — giving
  § 3–§ 6 as steps on top of the board_commit recipe above it, and opening byte-exact with:
```
**New task (any lane) — what `ops/polaris new <draft.md>…` does by hand.**
```
- **kit/CLAUDE.md** is not touched: every byte there is paid in every session.

## § 9 Surface
- api-kit.expected gains exactly `kit/ops/lib/author.sh<TAB>fn<TAB>cmd_new` — T-262 is the file's only
  owner this sprint (save-hops.md § 12.0), so its verify carries the STRICT whole-golden diff.
- `ops/tests/cli-help-parity.cmd`'s alternation gains `new` → expected `12`.
- `ops/tests/cli-help.expected` reads the INSTALLED CLI: the conductor re-pins it after the dogfood.
- `startup-budget` stays green (no `IFS="$(printf` in a loop, nothing above the loader).
- module-layout.md v6 records the module.

## § 10 Tests — new golden `new-task` (T-262)
Hermetic (a throwaway repo under `mktemp -d`, `KIT="$(pwd)/kit/ops/polaris"`, `init-board`, a contract
file, an `ask` rule in ops/RULES.tsv; LF `.cmd`/`.expected`). The board holds T-007 in done/, T-009 in
review/ owning `src/shared.txt`, T-010 in ready/ owning `src/ready.txt`. Pinned cases:
1. ONE call, four drafts → `T-011 ready` (disjoint) · `T-012 backlog — waits on T-009 (review, shares src/shared.txt)`
   · `T-013 ready` (depends_on [T-007], done) · `T-014 backlog — waits on T-011 (ready, shares src/a.txt)`
   (shares a file with the first draft); the board ref gained exactly ONE commit, subject
   `chore(board): new T-011 T-012 T-013 T-014`; the four files carry the right `id:`, `status:`,
   `depends_on:`; the drafts are byte-identical (`cmp`); `drift` says the board is clean.
2. A draft owning a path under the `ask` scope → backlog, the needs-a-yes line.
3. A preset free `id:` is kept; a later draft in the same call may depend on it.
4. Refusals, each rc 1 with its § 3 line and the board ref unmoved: points 8 · no plan · a missing
   contract · empty files_owned · a taken id · an unknown depends_on · a draft under ops/board/ · from a
   `feat/*` worktree.

## Invariants
- Writes only `ops/board/<column>/<ID>.md` and EVENTS.ndjson, in ONE board commit per call; never
  `<base>`, never SPRINT.md, never a draft.
- All or nothing: a refused call leaves disk and refs exactly as they were.
- The ready gate is Invariant 2 plus review/ — never weaker than `next --do`'s.

## Changelog
- v1 2026-11-06 · PLANNER · plan `tidy-hardening` — T-262 builds; T-265, T-266 adopt.
