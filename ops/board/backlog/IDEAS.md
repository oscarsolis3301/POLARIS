# IDEAS — one line each. The Planner grooms these; Builders append, never plan.

- The zip stopped shipping `README.md` after the `kit/` split — a manual `unzip` now gives you no orientation. Ship `kit/README.md`?
- `install.sh`'s fresh and live-board paths are ~40 lines apart and share a copy list. One drifted from the other once (the `ops/*.md` glob). Fold them — AFTER T-001 lands, so the drill guards the refactor.
- EVOLVE has never run here. After sprint 1, feed it the kickbacks and let it calibrate points.
- FIELD REPORT (external repo on 5.6.0, 2026-07-14) — items 1, 2, 5 became T-004, T-006, T-005; remaining, deferred to next sprint on capacity:
- (3) GAP nothing gates `map_delta` — Definition of Done demands it, `done` applies it, nothing enforces it; 4/5 tasks landed blank in one external sprint and MAP rotted. Handoff should refuse when the diff touches mapped files and map_delta is blank.
- (4) GAP `claim` builds a bare worktree (no deps installed) so every `verify:` fails until manual install; external Planner hand-wrote `pnpm install` boilerplate into all 5 tasks. Add `bootstrap:` key in CONVENTIONS.md, run by claim.
- (6) GAP `integration: paranoid` has no concept of a pre-existing flake; a 15% flake bounced good work and the Integrator improvised a wrong heuristic. Either a `flaky:` quarantine list or a rule: re-run failing file in isolation AND against base before any kickback.
- QA scout 2026-07-18: bad-arg errors from `${N:?usage...}` leak raw bash "line NNN" noise instead of the ⛔ format across ~10 subcommands (task-commit-msg/land/rollback/history --tasks inherited it from release/kickback/audit/run-verify/done/why) — worth one systemic usage-guard helper.
- QA scout 2026-07-18: `history --tasks 1 extra` silently ignores the stray arg while plain `history` rejects strays — align the branches.
- EVOLVE 2026-07-18: self-hosted repos RULES-guard ops/roles/ and ops/templates/, blocking EVOLVE's own legal targets (PLANNER.md §Pointing notes, TASK.md field guidance) — kit/ops/roles/EVOLVE.md needs a documented fallback home (CONVENTIONS § Planner calibration) for when those paths are guarded.
- Testbed 2026-07-20: bare `polaris audit` leaks raw `line 785: 1: usage` garble instead of a clean usage line — and kit CLAUDE.md's command table implies bare `audit` checks the review queue; align behavior + doc (fits the existing systemic usage-guard-helper idea above).
- Testbed 2026-07-20: pr-mode seal on a non-bitbucket origin prints title/instructions but no PR URL — verify once against a real bitbucket.org origin before trusting the URL path.
- Testbed 2026-07-20: quiet-board mode — kit PLANNER.md should state explicitly that the Planner's contract commit on base rides the NEXT wave's PR on protected mains (implicit today, surprises the first pr-mode Planner).
- EVOLVE 2026-07-20: paranoid per-land `build:` was classifier-blocked in subagent shells all sprint 4 (6 waves ran selftest-only per land; build proven only at qa) — give the kit a classifier-safe entrypoint, e.g. a `polaris build` passthrough running CONVENTIONS `build:`, or arm the installer's permission rule for `python kit/ops/pack.py`.
