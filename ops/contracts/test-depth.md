# CONTRACT: test-depth — run only what the change can break            (v1 — 2026-10-27)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-d-like-to-improve-playful-gosling.md` § B + § E (owner-approved
2026-10-27; owner decisions: text and look-only changes skip the suite; look-only changes keep the
before/after capture) · tasks T-197 (B1 depth_for + keys + `depth`), T-198 (B2 qa/land/stamp +
decision log), T-199 (B3 pack + metrics), T-200 (B4 prose) · `plan: stay-on-request`.

## Purpose
Separate "what changed" from "how much testing it needs", so a docs edit or a CSS tweak stops paying
a 26-minute suite, while code still gets exactly today's scoped-or-full verdict.

## 1. Keys (T-197 — kit/ops/KEYS.tsv, two new rows, since `6.9.0`)
```
test_skip   6.9.0   *.md docs/** *.txt LICENSE*                               <absent-cost prose>
test_look   6.9.0   *.css *.scss *.less *.svg *.png *.jpg *.jpeg *.gif *.webp *.ico   <absent-cost prose>
```
Defaults are composed IN CODE (`cfg test_skip "<default>"`), never written into a repo's CONVENTIONS
(`update` never rewrites a repo's config). Value `-` = the empty list. Patterns are space-separated
shell globs matched with `case` against the whole repo-relative path, `*` crossing `/` (so `*.md`
matches `a/b/c.md`, `docs/**` matches everything under `docs/`).

## 2. `depth_for` (T-197 — kit/ops/lib/core.sh, next to `tier_for`; PURE: no writes, no git)
```
depth_for [<taskfile>…] < <paths, one per line>
  stdout: ONE line  "<depth><TAB><why>"   depth ∈ none | look | scoped | full     rc 0 always
```
Rules, first match wins (the `why` strings are pinned byte-exact):
| # | condition | depth | why |
|---|---|---|---|
| 1 | any taskfile has `risk: high` | full | `risk: high on <ID>` |
| 2 | any taskfile has `test_depth: full` | full | `test_depth: full on <ID>` |
| 3 | no path left after dropping test_skip matches (incl. empty input) | none | `only test_skip paths` |
| 4 | every remaining path matches test_look | look | `only look paths (<n>)` |
| 5 | the remaining non-look paths: `surface_select_cmd` rc 0 | scoped | `every code path mapped in SURFACES.tsv` |
| 6 | otherwise | full | `<surface_select_cmd's one-line reason>` (e.g. `unmapped: x (+2 more)`, `test_select unset`) |
A task's `test_depth:` can only RAISE depth: any value other than `full` is ignored (no error).
`qa --full` / `qa --force` / an UNBOUNDED change set (no stamp ancestor) never call depth_for: full.

## 3. `polaris depth [<ID>]` (T-197 — `cmd_depth` in kit/ops/lib/observe.sh; dispatch + help in kit/ops/polaris)
Read-only. Line 1 = the depth word alone; then `   ` note lines: `   why: <why>` and
`   paths: <n> changed (<k> skipped by test_skip)`. With `<ID>`: paths = `git diff --name-only
$BASE...feat/<ID>`, taskfile = that task's file. No ID: paths = `surface_change_set` (unbounded →
line 1 `full`, why `no suite baseline`), taskfiles = § 4's subject scan. `readonly-allow.sh` lists
`depth` in `polaris_ok` (done in T-195).

## 4. Callers (T-198 — kit/ops/lib/observe.sh `cmd_qa`, kit/ops/lib/integrate.sh `land --express`)
- Task files for a qa: every `[<ID>]` suffix on `git log --format=%s <baseline>..HEAD` subjects
  (baseline = SURFACE_BASELINE, else `$BASE` on a branch), plus `<ID>` when HEAD is `feat/<ID>`,
  resolved with `task_file` in any column; missing files ignored. `land --express <ID>` passes its task.
- `none` and `look`: run NO suite key (test/lint/typecheck/build/uat); every board check qa makes
  today still runs; print `   depth: <depth> — <why>`; stamp. `look` changes nothing about the
  `visual:` capture + `--saw` gate at handoff (owner decision).
- `scoped`: today's selection, unchanged. `full`: today's whole suite, unchanged.
- Stamp: `.polaris/suite-stamp` third field = the depth word (`none|look|scoped|full`); the existing
  `scoped`/`full` meanings are unchanged, so `suite_stamp_scope` readers keep working.
- Noise filters: `surface_change_set` (core.sh ~:310) and `suite_stamp_carry` (integrate.sh ~:484)
  ALSO drop test_skip paths, so a green stamp carries across a docs-only commit (EVOLVE's, a report).

## 5. Decision log (T-198 — plan § E)
Every `qa` and `land --express` that reached a depth appends ONE line to `$PRIMARY/.polaris/decisions.ndjson`
(gitignored dir; best-effort, never fails the caller), AFTER the run so secs/rc are real:
```
{"ts":<epoch>,"plan":"<session plan or first task's plan: or empty>","task":"<first ID or empty>","kind":"test_depth","depth":"<d>","why":"<why>","paths":[<≤20 changed paths>],"secs":<int>,"rc":<int>}
```
`cmd_finish` appends `{"ts":…,"plan":…,"task":"","kind":"finish","secs":<int>,"rc":<int>}`.
At most ONE new helper function may be added for the append (e.g. `decision_log` in core.sh).

## 6. metrics (T-199 — `cmd_metrics`, kit/ops/lib/observe.sh) — two new lines, appended last
```
suite skipped this sprint: <M> min (none <a> · look <b> · scoped <c>)
per run: build <x>m · land <y>m · suite <z>m · finish <w>m
```
Sprint = rows with ts ≥ the `dates: YYYY-MM-DD` on SPRINT.md line 1 (absent → all rows). Skipped
secs per non-full row = max(0, median_full − secs), median_full = median secs of this sprint's full
rows (fallback: all full rows); none timed → the first line reads
`suite skipped this sprint: n/a (no full suite timed yet)`. a/b/c = row counts. build/land = the existing
claim→handoff / handoff→done averages restricted to the sprint; suite/finish = mean secs of the
sprint's test_depth / finish rows; a missing figure prints `-`. No decisions.ndjson → both lines
still print (`n/a`, `-`). Minutes round to one decimal.

## 7. pack (T-199 — kit/ops/lib/builder.sh ~:835)
`pack` no longer falls back to `test:`: unset `test_fast:` prints
`then the fast tier: (none set — verify: above is the per-task proof; the suite runs once at the wave gate)`.

## 8. Prose (T-200)
INTEGRATOR.md ~:30 runs `bash ops/polaris qa` (stamped) instead of a hand-run suite · CONDUCTOR runs
ONE `qa` at the end of the run · BUILDER.md ~:51 tests the acceptance criteria the change touches,
not a new suite · PLANNER.md ~:36 `verify:` lines are seconds, never `doctor --selftest` ·
PROTOCOL.md testing-tiers table gains a depth row · templates/TASK.md documents `test_depth:`
(raise-only) and `plan:` (required on request tasks). No heading added/renamed/removed.

## Executable check
- `ops/tests/test-depth.cmd/.expected` (T-197, hermetic, pure): docs → `none`, CSS → `look`, docs+CSS →
  `look`, a mapped lib file (fixture SURFACES row + test_select) → `scoped`, an unmapped lib file →
  `full`, `risk: high` → `full`, `test_depth: full` → `full`, `test_depth: none` ignored; `test_skip: -`
  turns a docs path into `full`; `polaris depth` line 1 on a fixture branch.
- `ops/tests/depth-stamp.cmd/.expected` (T-198, hermetic): docs-only commit after a green stamp →
  qa runs no suite key, stamp carries; CSS-only → stamp field `look`; one decisions.ndjson row per qa
  with the § 5 keys.
- `ops/tests/depth-metrics.cmd/.expected` (T-199, hermetic, seeded decisions.ndjson): the two § 6 lines.

## Invariants
- CI and `pack.py --dogfood` always run the full serial suite and never read the stamp — a skipped
  suite on a chat run can never ship a release unchecked. Nothing here touches `.github/` or pack.py.
- With no test_skip/test_look path in a change, every verdict is byte-identical to 6.8.0.
- One owner at a time for `ops/tests/api-kit.expected`: T-195 → T-197 → T-198 → T-199 (chained).

## Changelog
- v1 2026-10-27: created for T-197, T-198, T-199, T-200 (plan stay-on-request).
