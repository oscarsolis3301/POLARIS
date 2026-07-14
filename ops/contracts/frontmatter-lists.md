# CONTRACT: task frontmatter list parsing            (v1 — 2026-07-14)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Defines what shapes of YAML-ish list `fm_list` (kit/ops/polaris) accepts. Every board mechanic that
reads `files_owned`, `depends_on`, `verify:` or `map_delta` depends on this; a shape the template
teaches must parse.

## Interface
```
fm_list <key> <file>   → one item per output line, from the FIRST frontmatter block only
  key: v               → "v"                       (inline scalar — one item)
  key: []              → (nothing)
  key: [a, b, c]       → "a" "b" "c"               (inline flow list: strip [ ], split on ",", trim)
  key:                 → items from following "- x" lines, one per line
    - x
  everywhere: trailing " #comment" and \r stripped; leading/trailing whitespace trimmed;
              empty items (e.g. from "[a,,b]" or trailing comma) dropped
```
Out of scope (unchanged from today): quoted items keep their quotes; no nested lists; no multi-line
flow lists. Commas inside an item are not representable inline — use block form.

## Executable check
`doctor --selftest` gains parse drills for all four shapes — owned by T-004, listed in T-004's `verify:`.

## Example
```
depends_on: [T-001, T-002]   →  two items: "T-001", "T-002"   (today: ONE literal "[T-001, T-002]")
```

## Changelog
- v1 2026-07-14: created for T-004, from the 5.6.0 field report (bug 1).
