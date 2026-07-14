# IDEAS — one line each. The Planner grooms these; Builders append, never plan.

- `kit/ops/dashboard.py` has no automated test — CI never launches it. Smoke it: start, GET /, assert 200 + the six columns, kill.
- `polaris doctor` could warn when the local `polaris-v5.zip` lags HEAD (README claims it does; it does not). Root cause: the check exists (kit/ops/polaris cmd_doctor, stale-zip block) but gates on `$OPS/pack.py` — a pre-split path — so it never fires; gate on `kit/ops/pack.py` per ops/contracts/self-hosting.md instead.
- The zip stopped shipping `README.md` after the `kit/` split — a manual `unzip` now gives you no orientation. Ship `kit/README.md`?
- `install.sh`'s fresh and live-board paths are ~40 lines apart and share a copy list. One drifted from the other once (the `ops/*.md` glob). Fold them.
- EVOLVE has never run here. After sprint 1, feed it the kickbacks and let it calibrate points.
- FIELD REPORT (external repo on 5.6.0, all six verified against source 2026-07-14; priority per reporter: 1, 5, then 2, 4, 6, 3):
- (1) BUG `fm_list` (kit/ops/polaris:79) only special-cases empty `[]`; a populated inline list `depends_on: [A, B]` prints as ONE literal bracketed item → ready gate false-positives forever, `drift --strict` can never pass; `done` would splice `[...]` into MAP.md via map_delta (kit/ops/polaris:443). templates/TASK.md teaches the shape that breaks. Fix: strip brackets + split on commas in fm_list.
- (2) BUG `cmd_version` (kit/ops/polaris:848) reads `latest` from the once-per-calendar-day update cache and told a user "up to date" while 3 releases behind on release day. Explicit `version`/`update` must bust the cache; only the passive nag should throttle.
- (3) GAP nothing gates `map_delta` — Definition of Done demands it, `done` applies it, nothing enforces it; 4/5 tasks landed blank in one external sprint and MAP rotted. Handoff should refuse when the diff touches mapped files and map_delta is blank.
- (4) GAP `claim` builds a bare worktree (no deps installed) so every `verify:` fails until manual install; external Planner hand-wrote `pnpm install` boilerplate into all 5 tasks. Add `bootstrap:` key in CONVENTIONS.md, run by claim.
- (5) GAP no sanctioned way to amend `files_owned` — invariant 6 says board mutations go through the CLI, no command exists, so the external repo had to hand-edit the board to finish a task. Add `polaris grant <ID> <path> -m why`: append + record + commit, REFUSE if path overlaps any ready/active task (preserves disjointness).
- (6) GAP `integration: paranoid` has no concept of a pre-existing flake; a 15% flake bounced good work and the Integrator improvised a wrong heuristic. Either a `flaky:` quarantine list or a rule: re-run failing file in isolation AND against base before any kickback.
