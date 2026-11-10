# Sprint 22 — The speed release (6.14.0) (2026-11-09–)

## T-273 — "observe.sh becomes five modules, move-only, with a machine proof that nothing changed"
points 5 · risk normal · landed eb5f239 (2026-11-09) · claimed 2026-11-09
files touched: kit/ops/lib/check.sh, kit/ops/lib/drift.sh, kit/ops/lib/observe.sh, kit/ops/lib/qa.sh, kit/ops/lib/route.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/lib-census.cmd, ops/tests/lib-census.expected, ops/tests/triage-lane.cmd, tools/fnmove.sh

### Why
observe.sh is 3,267 lines, and four of this sprint's tasks need to change it. If they all owned that one file they would have to run one after another, which is the slowness this sprint exists to remove. This task cuts it into five files by moving functions, and changes nothing else: drift.sh (board hygiene), check.sh (the goldens), route.sh (triage, route and depth), qa.sh (qa and finish), and observe.sh keeps the rest. Because "nothing else changed" is the whole promise, it is proven by a small tool, tools/fnmove.sh, that lists every function as its name and body before and after and checks the two lists are the same. ops/contracts/minutes.md section 3 has the exact lists, the loader line and the tool's output.

### Acceptance
- [ ] the five files hold exactly the functions minutes.md § 3.1 lists, bodies byte for byte, each with its leading comment
- [ ] the loader line in kit/ops/polaris is § 3.2 literally; the guard path stays `core ownership`; the entry gains no line
- [ ] `tools/fnmove.sh` behaves as § 3.3 and prints the equal line for this move
- [ ] golden `lib-census` (§ 3.4) is new and green; api-kit rows change file only, same count; triage-lane greps route.sh
- [ ] every verify line is green
