# CONTRACT: context pack — `polaris pack`            (v1 — 2026-07-26)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Turns "read the brain first, `find` before Grep, match the house style, read the contract" from
PROSE a model may skip into a COMMAND whose output is the context itself.

Two costs motivated it, both measured 2026-07-26:
- An agent that ignores the prose reads the wrong things and writes in the wrong style.
- An agent that obeys the prose spends 6-15 tool calls assembling seven facts the CLI already has,
  each call costing a request, a result, and a re-read of everything above it in the transcript.

`pack` collapses both into one call, and every fact in it is generated — nothing here is authored
twice, so nothing here can drift from the board.

## Interface
```
polaris pack <ID>          → the context for that task, on stdout
polaris pack               → inside a feat/<ID> worktree, that task
```
rc 0 always on a resolvable task. Unknown ID → `⛔` naming `board-fm` as the remedy.

**Read-only, absolutely.** Never writes the board, never touches a git ref, never mutates
`.polaris/`. It is safe to run at any point, in any column, by any role — including a session that
holds no claim.

Sections, in this fixed order (a caller may parse on the `=== NAME ===` rulers):

| section | source | degrades to |
|---|---|---|
| `THE TASK` | the task file's `## Why` + `## Acceptance` | a note that `## Why` is missing |
| `THE CONTRACT` | `contract:` verbatim, ≤120 lines | ⛔ if NAMED but MISSING (Invariant 3) · "(none)" if unset |
| `HOUSE STYLE` | `.polaris/brain/prefs.md` table rows | "run: ops/polaris brain" |
| `FILES YOU OWN` | `files_owned` + `context_files` | a note that undeclared ownership is a task bug |
| `WHERE THIS LIVES` | `.polaris/brain/code-map.md`, per owned directory | "run: ops/polaris brain" |
| `PUBLIC SURFACE` | `find --api <path>` per owned path, ≤25 lines each | "new files, or run: ops/polaris brain" |
| `KNOWN TRAPS` | `learned.md` + `gotchas.md` lines matching an owned path | "(none recorded)" |
| `WHAT PROVES IT` | the task's `verify:` list + effective `test_fast:`/`test:` | a note to add a narrow `verify:` |

## Invariants
- **Every section degrades, none dies.** A missing brain, an unindexed path or an absent contract
  produces a one-line note and the rest of the pack. A cold repo with no brain must still get a
  usable pack — that is precisely the session with the least context to spare.
- **Generated only.** No section may be hand-authored or cached to disk. `pack` composes existing
  producers (`fm_get`/`fm_list`, `find --api`, the `brain_*` writers) and adds no new index.
- **A named-but-missing contract is a hard `⛔` inside the pack**, not a silent omission. Invariant 3
  says never invent an interface, and the pack is where that is now visible.
- **`KNOWN TRAPS` filters to the task's own paths.** A Builder needs the two lines about its files,
  not all sixty; an unfiltered dump would re-create the cost the command exists to remove.
- Bounded: no section may exceed its cap above. `pack` must stay cheaper than what it replaces even
  on a repo with a 200-line contract and a 40-path `files_owned`.

## Changelog
- v1 2026-07-26: created for the 5.21.0 token-efficiency work. Replaces the four-line brain/find
  prose block in every conductor kickoff and the read-list in BUILDER.md § 2 and SOLO.md § Context.
