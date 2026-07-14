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
