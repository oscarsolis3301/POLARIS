# CONTRACT: one-yes — the approved plan covers every scope it named      (v1 — 2026-10-28)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-d-like-to-improve-playful-gosling.md` (owner-approved 2026-10-28,
"One yes, hands-free") · tasks T-210..T-217 · `plan: one-yes`. Extends `ask-approval.md` (cmd_approve,
`approved:`), `change-sized.md` (depth_for, test_select_for, related_cmds, `depth --commit`) and
`test-depth.md`. Nothing here changes a verdict those pin unless stated. The plan's tasks are
`risk: normal` on purpose: the owner approved this plan INCLUDING the change to the mechanism.

## Purpose
After the owner approves a plan and goes auto, the run is hands-free: no mid-run "approve <ID>" for a
scope the plan named, and a risky task does not drag the whole suite along. Python repos get related
tests like node repos did. `update` shows the speedup from the repo's own history.

## 1. `polaris approve --plan <slug> -m "<the owner's words>"`   (A — builder.sh, T-210)
Grammar: `approve --plan <slug> -m "why"` (flags in any order after `approve`). `-m` required, same
message as plain approve. Refusals — every one mutates NOTHING, same wording family as cmd_approve:
on any `feat/*` branch (`approve refused on <br> …`) · missing `-m` · no task on the board has
`plan: <slug>` (`approve --plan refused: no task carries plan: <slug>`). `approve <ID> <scope>` (the
plain form) is byte-unchanged; `--plan` with a positional ID/scope → usage error.
Effect, for EVERY task in any column whose `plan:` equals `<slug>`: append to its `approved:` list one
entry per scope it needs, skipping a scope already carrying a plan entry (idempotent re-run), one
board commit `chore(board): approve plan <slug>`, one evt `approve-plan <slug>`:
| scope token | written when |
|---|---|
| `merge` | `risk: high` |
| `need:<v>` | each value in the task's `needs:` list (`schema` \| `dependency` \| `delete`) |
| `<rule scope>` | each `ask` rule its `files_owned` hit (`ask_rule_matches`; the matching rule's scope string, as plain approve would take it) |
Entry shape (ONE line, the scope is the first token, as ask-approval.md § 2 parses it):
`<scope> — <who>, <date>: plan <slug>: <msg>` — the literal `plan <slug>: ` after the date marks it a
PLAN entry. Entries not in this shape (every hand `approve <ID> <scope>`) are NOT plan entries.
A task with an unknown `needs:` value, or no `approved:` field, is skipped with a `⚠` line naming it
(the rest proceed). Output: one line `approved plan <slug>: <n> scope(s) on <m> task(s)`.
`needs:` is a new optional list field on a task (`templates/TASK.md`, T-216): values `schema`,
`dependency`, `delete` — the STOP-AND-ASK items a task declares it will do. Read with `fm_list needs`.

## 2. The ONE predicate (A — ownership.sh `plan_covers`, T-210; callers T-210/T-211)
`plan_covers <taskfile>` rc 0 = "this task may land without a human's mid-run yes", rc 1 + ONE reason
line otherwise. rc 0 iff ALL hold:
1. `cfg autonomy trusted` is not `standard` (autonomy: standard keeps today's per-merge stop — rc 1,
   reason `autonomy: standard`);
2. `risk:` is non-empty (fail-closed on an unclassified task, as today);
3. `risk: high` ⇒ a plan entry with scope `merge`;
4. every `needs:` value `<v>` ⇒ a plan entry with scope `need:<v>`;
5. EVERY `approved:` entry is a plan entry (a hand-recorded approval still sends the merge to the
   human lane, exactly as today — nothing already protected gets weaker).
A task with `risk: normal`, empty `needs:` and empty `approved:` is rc 0 as today (so every existing
fixture is byte-identical). Plan entries carry no slug check at read time (the slug lives in the text).
Callers (replace "risk: high or any approved entry"): `self_land` (builder.sh) · `next_landable`
(handover.sh: rc 0 → NX_REV_OK, else NX_REV_HUMAN) · `land --express` (integrate.sh: `risk: high never
rides the express lane` is replaced by `plan_covers` rc 1 ⇒ die with the reason line, wording
`express refused: <reason> — integrate it by hand with the human in the loop`). The `self_land` skip
line stays `risk: high never self-lands — a human must approve the merge; task stays in review/`
whenever `plan_covers` rc 1 (byte-identical for today's cases).
STILL ASKS, unconditionally (not softened here): risk not named in the approved plan (no entry → rc
1) · force-push · secrets · any `ask` rule the task has no covering entry for.

## 3. `depth_for` (B — core.sh, T-212)
Rule 1 (`risk: high` forces `full`) is REMOVED. Depth follows the changed paths; `test_depth: full` on a
task remains the explicit force (rule 2, untouched). The `risk: high on T-…` why string disappears from
depth_for. Everything else in test-depth.md is untouched.

## 4. `integration: paranoid` (B — integrate.sh near `land_slow_suite_hint`, INTEGRATOR.md, T-212)
The per-land re-run is no longer "the whole suite": it is the depth-aware check of THAT one land — the
same decision `qa` makes (`depth_for` over that land's paths, `test_select_for` for the test key). A
CSS-only land under paranoid runs no suite. The slow-suite hint is dropped (its advice is moot); the
INTEGRATOR.md line that says paranoid re-runs the suite per land says this instead.

## 5. pytest related mode (C — surfaces.sh `related_cmds`, T-213/T-214)
`related_cmds <paths-file>` gains python. Pure awk over `git ls-files '*.py'`; no execution.
- Module map: a tracked `a/b.py` is module `a.b` (also `a/b/__init__.py` → `a.b`); import forms
  `import x[.y]`, `import x as z`, `from x import y`, `from x.y import z`, `from . import y` / relative
  `from .x import y` resolved against the importing file's package. An import resolves to the tracked
  module with the longest matching prefix; `from pkg import sub` also edges to `pkg.sub` when tracked.
  Unresolved (third-party) imports are ignored. Multi-line parenthesised imports are read.
- Test files: tracked `.py` whose basename matches `test_*.py` or `*_test.py`.
- Selection: reverse-reachability from each changed `.py` (a changed test file selects itself) to test
  files, transitively. Output files sorted, repo-relative.
- Command: the repo's `test:` split on ` && `; the segment containing `pytest` is rewritten: every
  token after `pytest` that does not start with `-` and is not the value of a known value-flag
  (`-k -m -p -c -o --tb --rootdir --maxfail --durations -n`) is a path argument and is dropped, the
  selected test files are appended at the position of the first dropped path (else directly after
  `pytest`/its leading flags). Other segments are NOT run. When `test:` is a `doctor`/`polaris`
  indirection or the pytest segment cannot be found/parsed → fallback.
  Example: `PYTHONPATH=. backend/.venv/Scripts/python -m pytest backend/tests -q` + selected
  `backend/tests/test_b.py` → `PYTHONPATH=. backend/.venv/Scripts/python -m pytest backend/tests/test_b.py -q`.
- Fallback to full (rc 1, ONE reason line `<path> has no related tests (<why>)`, `<why>` one of
  `pytest config changed` | `no test reaches it` | `test command not parseable`): a changed
  `conftest.py` · `pytest.ini` · `tox.ini` · `setup.cfg` · `pyproject.toml` · `requirements*.txt` ·
  a changed `.py` module no test reaches · no parseable pytest segment.
- Mixed node + python change: the path list is partitioned (`.py` → python, the rest → today's node
  rules); BOTH command sets are emitted (node packages first, then pytest). Still ALL-OR-NOTHING: any
  path with no related coverage → rc 1.
- why string (core.sh depth_for rule 5): `related tests via pytest (N file(s))`; mixed → node's string
  then ` + pytest (N file(s))`. `test_related: -` turns pytest mode off with the node mode. There is
  still ONE decision, `test_select_for`; qa, `land --express` and `depth --commit` agree by construction.

## 6. Speed report (D — admin.sh `cmd_speed`, kit/ops/polaris, readonly-allow.sh, T-215)
`polaris speed` (read-only: writes nothing, runs no suite, never edits config; `readonly-allow.sh`
`polaris_ok` approves it) and the same output as the last block of `update` (after the success lines,
only when the repo is a git repo with ≥1 commit; it must never fail the update — any internal error
prints nothing and rc stays 0). Over the last 30 commits on `<base>` (`git rev-list -n 30`), each
classified exactly as `depth --commit <sha>` classifies it (the same function, not a re-derivation):
```
Of your last <N> changes: <a> would skip the test run, <b> run only related tests, <c> run everything.
```
(`none` and `look` count as skip; `scoped` as related; `full` as everything.) Then, when
`.polaris/last-suite-seconds` is numeric: ` Your last full run took <T>.` appended to the same line
(`<n>s` under 60s else `<m>m`). Then ONE advice line per slowing setting present, in this order, each
`   → <what it costs>: set <exact line> in ops/CONVENTIONS.md`:
- `drain: queue` → `drain: plan`
- `autonomy: standard` → `autonomy: trusted`; `plan_gate: confirm` → `plan_gate: auto` (separate lines)
- `integration: paranoid` AND last suite > 120s → `integration: batch`
No such setting → no advice lines. Fewer than 1 commit → one line `speed: no history yet`.

## 7. Executable checks (hermetic, zero tokens; fixtures under `mktemp -d`)
- `ops/tests/plan-approval.cmd/.expected` (T-210): risk-high task + `approve --plan` → `plan_covers`
  rc 0, `self_land` lands it; same task unapproved → today's refusal; `autonomy: standard` + approval →
  refusal; `needs: [schema]` without `need:schema` → refusal, with it → rc 0; hand approval → human lane;
  `--plan` on `feat/*` and with no `-m` and unknown slug → refused, board byte-identical; re-run is
  idempotent.
- `ops/tests/plan-approval-gates.cmd/.expected` (T-211): `next` lists the covered risk-high task as
  landable (NX_REV_OK) and the unapproved one as human; `land --express` accepts / refuses likewise.
- `ops/tests/paranoid-depth.cmd/.expected` (T-212) and `test-depth.expected` (risk: high docs → `none`).
- `ops/tests/pytest-related.cmd/.expected` (T-213/T-214): `pkg/a.py` imported by `pkg/b.py`, imported by
  `tests/test_b.py` → command names exactly `tests/test_b.py`; changed `conftest.py` → full; unreached
  module → full; compound `test:` → only the pytest segment rewritten; mixed node+python → both sets.
- `ops/tests/speed-report.cmd/.expected` (T-215): a fixture history → the counts line and the
  paranoid/drain advice lines; read-only (repo byte-identical after).
- **DIRTY-TREE RULE (any task touching `cmd_qa`, `surface_change_set`, `test_select_for` or
  `related_cmds`):** its golden MUST include the case "dirty tree + ancestor suite stamp +
  `test_select` UNSET" and assert the suite STILL RUNS and `.polaris/last-suite-seconds` is written
  (that is how 6.9.0's release smoke selftest failed). Copy the shape of `ops/tests/qa-carry-dirty.cmd`.

## Invariants
- CI and `pack.py --dogfood` still run the full serial suite and never read these shortcuts.
- No change in verdict for a task with no `needs:` and no plan entries, except §3 (risk: high no longer
  forces full) and §4.
- `kit/CLAUDE.md` stays ≤ 10054 bytes (the T-189 budget; it is ~10046 now, so the one clause "unless the
  approved plan named it" must be paid for by trimming a few words elsewhere in the same file).
- `ops/RULES.tsv` and `.github/` are NOT touched by any task; no rule kind is converted.
- `ops/tests/api-kit.expected` / `cli-help.expected` owner order: T-210 → T-211 → T-212 → T-213 → T-214 → T-215.

## Changelog
- v1 2026-10-28: created for T-210..T-217 (plan one-yes).

## Fix wave 1: selftest drill hygiene (T-218)
T-213 removed `drill_hint`, whose tail was the only thing that committed the express drill's leftovers
(`test: true` in CONVENTIONS.md, dirty tree) onto main; park then swept `src/ex.dat` into feat/T-PK on
windows. `drill_express` now ends with its own hermetic cleanup (strip `test:`/`integration:` lines,
commit `express drill cleanup`). Owner: kit/ops/lib/selftest/history.sh only. No interface change.
