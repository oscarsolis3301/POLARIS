# Contract: code-index (`polaris find` / `polaris show`)

Version 1 · 2026-07-25 · referenced by `ops/lib/search.sh:2` and `ops/index.py:10`

## Purpose

The 1-hop "where is X". An agent that cannot answer that in one command answers it with a Grep
sweep, reads three files to disambiguate, and pays for all of it in context. `find` exists so the
answer costs ONE line of output instead of a file dump — the win is the OUTPUT SHAPE, not raw
speed, which is why the engine is Python and not a native binary.

Measured 2026-07-25 on this repo (136 files): `find` 666ms vs `grep -rn` 170ms. **Grep is faster
here and the index still earns its place**, because a lookup that produced an ambiguous 81-token
grep dump costs 36 tokens as one ranked line, and because grep's cost grows with the repo while the
index's does not (628ms warm on a 3,000-file repo). Do not "optimize" this by replacing it with
grep; that trade only looks good on a small repo, and tokens are the scarce resource, not milliseconds.

## Interface

```
polaris find <symbol>              ranked symbol lookup
polaris find -f <glob>             files by path glob, ordered by churn
polaris find -t <text>             full-text, with line hits
polaris find --importers <path>    who imports this
polaris find --imports <path>      what this imports
polaris find --api <glob>          public surface, sorted, NEVER truncated by -n
polaris show <path>#<symbol>       just that symbol's body
polaris show <path>:<line>
```

Exit codes are load-bearing: **0** hits · **1** none · **2** usage · **3** engine unavailable.
rc 3 must never be fatal to a caller — it prints `no python3 — 'find' is unavailable; use
Grep/Glob` and the agent falls back. A missing interpreter degrades the kit, it does not break it.

`--api` output (`path<TAB>kind<TAB>name`, sorted) is the one shape stable enough to be a golden;
`ops/tests/api-kit.expected` depends on it. Ranked output is deliberately NOT golden-stable — it
moves with churn and fan-in, which is the point.

## Storage

`<primary>/.polaris/index.db` — SQLite, WAL, gitignored, rebuilt incrementally on every query.
Three tiers, byte-identical output: FTS5 → LIKE-over-body → live scan with no persistence.
Schema bump = hard rebuild. The index is a CACHE: deleting it must only ever cost time.

Freshness is per-query, not scheduled. A stat cache (size+mtime, with git's 1-second racily-clean
guard) means an unchanged file is never re-read or re-hashed — without it a 5,000-file repo would
pay ~4s per lookup.

## Resolution rules (`resolve_import`)

**A wrong edge is worse than a missing one**, because `--importers` is what a Planner uses to prove
`files_owned` disjointness. Unresolvable is therefore always a legal answer, and external packages
(`os`, `react`) resolve to NULL by design — a repo whose edges are mostly stdlib imports will show
mostly NULL, and that is correct, not a fault.

Two rules exist because the obvious implementation silently returned nothing for whole classes of repo:

1. **Variable-built paths.** Shell sources modules as `. "$OPS_DIR/lib/core.sh"`, and Make/CI do
   the same with `$(VAR)`. The literal tail (`lib/core.sh`) is matched against the tracked set.
   A segment that is itself a variable (`lib/$_m.sh`) leaves no usable tail and stays unresolved.
2. **Mirrored trees.** A self-hosting repo holds every file twice (`ops/lib/core.sh` and its source
   `kit/ops/lib/core.sh`), so basenames and tails are routinely ambiguous. The candidate sharing the
   longest directory prefix with the importer wins; **an exact tie resolves to NULL**, never to a
   coin flip — an edge into the mirror would point a Planner at a file that did not change.

Both rules are pinned by `python ops/index.py selfcheck`, which is wired into `polaris check` via
`ops/tests/index-selfcheck.cmd`. Each was verified to FAIL that selfcheck when disabled; a rule
here that no case exercises should be deleted, not kept on faith.

## Invariants

- **Never fatal.** No missing engine, corrupt db or unreadable file may fail a caller.
- **Never authoritative.** `churn` and `fanin` rank results; they never decide correctness.
- **Primary-rooted.** `index_root` resolves the PRIMARY checkout, because `.polaris/` lives there.
  A Builder in a worktree therefore sees the primary's committed view — uncommitted worktree edits
  are invisible to `find`. Use Read/Grep for your own in-flight changes.
- **Adding a language means adding a fixture.** `SYMS`/`IMPORTS` are data tables; `FIXTURES` in
  `selfcheck()` is what keeps them honest.
