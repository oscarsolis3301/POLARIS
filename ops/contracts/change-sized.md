# CONTRACT: change-sized — checks in proportion to the change            (v1 — 2026-10-27)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-d-like-to-improve-playful-gosling.md` (owner-approved 2026-10-27,
"Change-sized checks") · tasks T-202 (A), T-203 (B), T-204 (C), T-205 (D), T-206 (prose), T-207
(release prep) · `plan: change-sized`. Extends `test-depth.md` (depth_for, surface_change_set,
decision_log, cmd_depth) and `stay-on-request.md`. Nothing here changes a verdict that test-depth.md
pins unless stated.

## Purpose
A small UI change in a repo that has never been green must pay seconds, not a full suite: bound the
change set to what THIS run landed, let the test runner pick the related tests, defer the live `uat`
tier at `scoped`, and say plainly why a run is slow before it starts.

## 1. Run-scoped change set (A — core.sh `surface_change_set`, observe.sh `cmd_qa`)
On `$BASE` with NO usable stamp ancestor (today: rc 1, unbounded), before giving up:
1. read the session plan (the slug `triage <ID>` records; the same source `decision_log` uses);
2. every task in `done/` and `review/` whose `plan:` equals it → its `landed_sha <ID>`;
3. union `git diff-tree --no-commit-id --name-only -r <sha>` of those commits, then the usual filters
   (board noise, test_skip).
Result: rc 0 (BOUNDED) and the global `SURFACE_BOUND=run` (set to `""` on every other path, reset at
entry like SURFACE_BASELINE). `SURFACE_BASELINE` stays `""` in this mode.
No plan recorded, no task of the plan landed, or any landed_sha unresolved → rc 1, nothing printed:
UNBOUNDED, exactly as today. `--force` still → rc 1. A usable stamp ancestor still wins (SURFACE_BOUND
empty); the run-scope is only the no-stamp fallback.
`cmd_qa` bounded-and-empty carry branch: when `SURFACE_BOUND=run` and the set is empty it stamps scope
`none` (never `full`) and prints `   nothing this run changed needs a suite`. All other carry behavior
is unchanged.

## 2. `related_cmds` (B — kit/ops/lib/surfaces.sh, next to `surfaces_runner`; PURE apart from reading files)
```
related_cmds <paths-file>   stdout: one complete command per qualifying package, rc 0 | rc 1 + ONE reason line
```
Input: repo-relative changed code paths (the non-skip, non-look remainder). For each, the nearest
ancestor directory holding a TRACKED `package.json` (`git ls-files`; root counts) is its package.
The package qualifies only when its `test` script (read exactly as `surfaces_runner` reads it) invokes
`vitest` or `jest` AND `<pkg>/node_modules/.bin/vitest` (resp. `jest`) exists as a file.
Commands (paths relative to the package, space-separated, in input order; one command per package,
packages in first-seen order):
```
vitest:  cd <pkg> && ./node_modules/.bin/vitest related --run <rel paths>
jest:    cd <pkg> && ./node_modules/.bin/jest --findRelatedTests <rel paths> --passWithNoTests
```
(`<pkg>` = `.` → no `cd`.) No npx, no network. ALL-OR-NOTHING: if any path has no package, or its
package does not qualify, rc 1 and the reason is `<path> has no related tests (<why>)` where `<why>` is
one of `no package.json` | `no vitest/jest in test script` | `node_modules not installed`. Python/pytest
repos and any non-package path are therefore never related-mode: today's SURFACES-or-full behavior is
unchanged for them (pytest has no "related" mode — stated, not a gap).

## 3. The ONE shared decision (B — core.sh, used by depth_for, cmd_qa's test key, `land --express`)
One function, `test_select_for <paths-file>` (name pinned; core.sh): stdout the command(s) to run for
the `test` key, one line each; rc 0 = scoped, rc 1 + one reason line = full. Order, first win:
1. `surface_select_cmd` (SURFACES rows) rc 0 → its commands;
2. unless `test_related` is `-`: `related_cmds` rc 0 → its commands;
3. rc 1, reason = the related reason when related ran and failed, else surface_select_cmd's reason.
`depth_for` rule 5 becomes: `test_select_for` rc 0 → `scoped`. why strings (byte-exact):
- via SURFACES: unchanged `every code path mapped in SURFACES.tsv`
- via related: `related tests via <vitest|jest> in <pkg>/` (several packages: first, then ` (+N more)`;
  root package: `in ./`)
Rule 6 `full` why = the reason line from step 3. cmd_qa's test key and land --express run exactly
what `test_select_for` prints; they may never re-derive it.

## 4. Key `test_related:` (B — kit/ops/KEYS.tsv, since `6.9.0`)
Unset = on; value `-` = off; any other value = on. Default composed in code (`cfg test_related ""`),
never written to a repo's CONVENTIONS. One KEYS.tsv row, same column shape as `test_skip`.

## 5. uat deferral + the depth line (C — observe.sh `cmd_qa`, integrate.sh `land --express`)
At depth `scoped` ONLY: the `uat` key is not run; print exactly one line
`   uat — deferred: runs on full-depth changes, CI and release`
(only when a `uat:` command is configured). `test` (selected), `lint`, `typecheck`, `build` still run.
`full`, `look`, `none` unchanged. Both callers.
Both callers ALWAYS print one depth line before running, whatever the depth:
`   depth: <depth> — <why>` for none/look/scoped (as today); at `full`:
`   depth: full — <why> (last full run <T>)` where `<T>` is `.polaris/last-suite-seconds` rendered
`<n>s` under 60s else `<m>m`, and the parenthetical is OMITTED when the file is absent/non-numeric.
`<why>` at full names the forcing cause (first unmapped path, `risk: high on T-…`, `no suite baseline`).

## 6. `polaris depth --commit <sha>` (D — observe.sh `cmd_depth`, kit/ops/polaris dispatch + help)
Read-only: no writes, no stamp, runs nothing. Paths = `git diff-tree --no-commit-id --name-only -r <sha>`
(root commit: `--root`); taskfiles = the `[<ID>]` subject suffix of `<sha>`. Unknown sha → rc 2,
`⛔ no such commit: <sha>`. Output (extends test-depth.md § 3):
```
<depth word>
   why: <why>
   paths: <n> changed (<k> skipped by test_skip)
   would run: <command>          (one line per command qa would run at that depth, in order)
   would skip: uat               (only at scoped, when uat is configured)
```
none/look print one line `   would run: nothing`. `would run` lines come from the same helpers qa uses
(test_select_for for `test`, then lint, typecheck, build when configured; at `full` the configured
`test`/`lint`/`typecheck`/`build`/`uat`). `--commit` and `<ID>` together → rc 2 with usage.
`readonly-allow.sh` `polaris_ok` approves `depth` with `--commit <sha>` (a hex sha or ref name; no shell
metacharacters).

## 7. Executable checks (hermetic, zero tokens; fake `node_modules/.bin/vitest` that echoes its argv)
- `ops/tests/change-bound.cmd/.expected` (T-202): no stamp + one landed CSS-only plan task → `look`, no
  suite; docs-only → `none`; no plan recorded → full (today); stamp present → stamp path unchanged.
- `ops/tests/related-tests.cmd/.expected` (T-203): `.tsx` in a sub-package with vitest → `scoped` and
  the command names exactly the changed file relative to the package; one stray path outside any
  package → `full`; `test_related: -` → `full`; jest shape; no node_modules → `full`; pytest repo
  unchanged.
- `ops/tests/depth-uat.cmd/.expected` (T-204): scoped → uat line printed and uat not run; full → depth
  line names the cause and last time; absent last-suite-seconds → no parenthetical.
- `ops/tests/depth-commit.cmd/.expected` (T-205): same decision as `qa` for the same paths; read-only
  (repo byte-identical after); bad sha rc 2. `ops/tests/readonly-allow.*` gain the approval case.

## Invariants
- CI and `pack.py --dogfood` still run the full serial suite and never read these shortcuts.
- A change touching no test_skip/test_look path and no package with an installed runner decides
  byte-identically to 6.9.0-so-far.
- `ops/tests/api-kit.expected` owner order: T-202 → T-203 → T-204 → T-205.
- `risk: high` and `test_depth: full` still force `full` (rules 1-2 of test-depth.md are untouched).

## Changelog
- v1 2026-10-27: created for T-202..T-207 (plan change-sized).
