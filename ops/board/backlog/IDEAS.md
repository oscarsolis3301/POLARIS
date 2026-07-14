# IDEAS — one line each. The Planner grooms these; Builders append, never plan.

- The zip stopped shipping `README.md` after the `kit/` split — a manual `unzip` now gives you no orientation. Ship `kit/README.md`?
- `install.sh`'s fresh and live-board paths are ~40 lines apart and share a copy list. One drifted from the other once (the `ops/*.md` glob). Fold them — AFTER T-001 lands, so the drill guards the refactor.
- EVOLVE has never run here. After sprint 1, feed it the kickbacks and let it calibrate points.
- FIELD REPORT (external repo on 5.6.0, 2026-07-14) — items 1, 2, 5 became T-004, T-006, T-005; remaining, deferred to next sprint on capacity:
- (3) GAP nothing gates `map_delta` — Definition of Done demands it, `done` applies it, nothing enforces it; 4/5 tasks landed blank in one external sprint and MAP rotted. Handoff should refuse when the diff touches mapped files and map_delta is blank.
- (4) GAP `claim` builds a bare worktree (no deps installed) so every `verify:` fails until manual install; external Planner hand-wrote `pnpm install` boilerplate into all 5 tasks. Add `bootstrap:` key in CONVENTIONS.md, run by claim.
- (6) GAP `integration: paranoid` has no concept of a pre-existing flake; a 15% flake bounced good work and the Integrator improvised a wrong heuristic. Either a `flaky:` quarantine list or a rule: re-run failing file in isolation AND against base before any kickback.
