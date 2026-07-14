# IDEAS — one line each. The Planner grooms these; Builders append, never plan.

- `kit/ops/dashboard.py` has no automated test — CI never launches it. Smoke it: start, GET /, assert 200 + the six columns, kill.
- `polaris doctor` could warn when the local `polaris-v5.zip` lags HEAD (README claims it does; it does not). Root cause: the check exists (kit/ops/polaris cmd_doctor, stale-zip block) but gates on `$OPS/pack.py` — a pre-split path — so it never fires; gate on `kit/ops/pack.py` per ops/contracts/self-hosting.md instead.
- The zip stopped shipping `README.md` after the `kit/` split — a manual `unzip` now gives you no orientation. Ship `kit/README.md`?
- `install.sh`'s fresh and live-board paths are ~40 lines apart and share a copy list. One drifted from the other once (the `ops/*.md` glob). Fold them.
- EVOLVE has never run here. After sprint 1, feed it the kickbacks and let it calibrate points.
