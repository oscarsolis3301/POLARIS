# CONTRACT: polaris grant            (v1 — 2026-07-14)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
The sanctioned way to amend a claimed task's `files_owned` mid-flight (invariant 6 routes all board
mutations through the CLI; until now no command existed and repos hand-edited the board). Disjointness
is preserved mechanically by the refusal rule, so the ONE IDEA survives.

## Interface
```
polaris grant <ID> <path> -m "why"
  preconditions (ALL, else exit non-zero, board untouched):
    - <ID> is in active/            # amending unclaimed/finished work is a Planner act, not a grant
    - -m "why" given, non-empty
    - <path> overlaps NO files_owned entry of ANY other task in ready/ or active/
      (overlap = same pattern semantics as `polaris verify`: exact · dir/ prefix · glob)
  effects (single board commit, "chore(board): grant <ID> <path>"):
    - <path> appended to <ID>'s files_owned
    - one line appended to <ID>'s Notes:  grant: <path> — <why>
    - one event appended to EVENTS.ndjson (kind "grant", id, path)
```

## Invariants
- Refusal mutates NOTHING — no partial writes, no commit.
- RULES.tsv still binds: granting a danger-zone path does not make it writable; the guard and
  `verify` check RULES independently of ownership.
- grant never removes or rewrites existing entries — append-only.

## Executable check
`doctor --selftest` gains a grant drill (success + overlap refusal + missing -m refusal) — owned by
T-005, listed in T-005's `verify:`.

## Example
```
polaris grant T-042 src/api/limits.py -m "rate-limit constant lives here, discovered during wiring"
```

## Changelog
- v1 2026-07-14: created for T-005, from the 5.6.0 field report (gap 5).

## v2 — `polaris amend <ID> --verify` — the sibling for the acceptance list (2026-09-14, plan sprint-c, 6.5.0 — T-157 code · T-155 entry · T-158 prose)

**Why.** `grant` widens a claimed task's `files_owned`; nothing widens or corrects its `verify:`. A
cross-lane golden owner is handed a verify line that is unsatisfiable by construction (its branch is
based on `<base>`, the sibling's rows read as hunks until the sibling lands): T-122, T-125, T-136,
T-139 — each a round trip to a human or conductor to hand-edit a board file. A calibration note fixes
FUTURE carves and cannot reach work already on the board; a command can.

### Interface (`cmd_amend` in `kit/ops/lib/integrate.sh` — the Integrator's module, because a Builder never runs it)
```
polaris amend <ID> --verify <n> -m "why" -- <command…>      # replace verify: line n (1-based) with <command…>
polaris amend <ID> --verify <n> --drop -m "why"             # remove verify: line n
polaris amend <ID> --verify --add -m "why" -- <command…>    # append a line
  preconditions (ALL, else rc 1, board untouched):
    - <ID> is in active/ or review/       # a claimed task; anything else is a Planner edit
    - -m "why" given, non-empty
    - NOT on any feat/* branch            # approve's rule: a Builder never rewrites its own gate
    - <n> within the list (1..len)         # else: ⛔ amend: verify has <len> line(s), no line <n>
    - the new command is not a bare full-suite command (run_verify_cmds' predicate: _norm_cmd
      equals CONVENTIONS test: or build:) — ⛔ amend refused: that is the wave gate, never a verify: line
  effects (ONE board commit "chore(board): amend <ID> verify"):
    - the verify: list edited in place (order kept)
    - one Notes line:  - amend: verify[<n>] "<old>" → "<new>" — <why>     (drop: "<old>" → dropped · add: verify[+] "<new>")
    - one event: {"ev":"amend","id":"<ID>","note":"verify[<n>]"}
    - sync_board
```
`amend_verify <taskfile> <n|add> <newline|->` (integrate.sh) is the pure list surgery — awk over the
frontmatter, `-` = drop, `add` = append — rc 1 out of range, no board side-effects, so the fast tier
proves it on fixture files. Refusals mutate NOTHING (grant's rule). `--verify` is the only field in v2;
the flag exists so a later field can join without a new command.
The feat/* refusal text, verbatim (T-157 asserts it): `⛔ amend refused on <branch> — a Builder never rewrites its own gate; run it from the primary checkout`.

Dispatch line (T-155, verbatim, directly under `grant)`): `amend)      shift; cmd_amend "$@";;`.
Usage entry (T-155, verbatim, directly under the `grant` entry):
```
  amend <ID> --verify <n> -m "why" -- <cmd…>
        | --verify <n> --drop -m "why" | --verify --add -m "why" -- <cmd…>
                                 replace, drop or append ONE verify: line of a CLAIMED task (the
                                 sibling of grant: grant widens ownership, amend corrects the
                                 acceptance list). REFUSES on any feat/* branch — a Builder never
                                 rewrites its own gate — and refuses a bare full-suite command;
                                 refusal mutates nothing; the why lands on the task's record
```

### Executable check
- `drill_grant` (board.sh, T-157; no new fn, label unchanged): replace line 2 of a fixture active task's
  three-line `verify:` → the file's list reads old-1 / new / old-3, the Notes line and the event exist,
  ONE board commit with the pinned subject; `--drop` leaves two lines; `--add` appends; from a `feat/*`
  worktree → rc 1 and the file byte-identical; `<n>` = 9 → rc 1, byte-identical; a bare `test:` command
  → rc 1, byte-identical. Asserts rc + bytes.
- `selftest_fast` section `amend` (fast.sh, T-157): `amend_verify` on a fixture file — replace / drop /
  add / out-of-range rc 1.

### Prose (T-158)
PROTOCOL.md THE TOOL gains the row beside `grant`; MANUAL.md gains the by-hand equivalent (edit the
list, append the Notes line, board_commit) beside the grant recipe; INTEGRATOR.md § 1 gains one
sentence: "A verify line the builder proved unsatisfiable by construction is amended from the primary —
`bash ops/polaris amend <ID> --verify <n> -m "why" -- <cmd>` — never by hand, never by the builder."

### Changelog
- v2 2026-09-14: `amend <ID> --verify` (T-157 · T-155 · T-158, plan sprint-c).
