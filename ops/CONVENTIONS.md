# CONVENTIONS
base: main                  # base branch
claim: local-lock           # one machine, many sessions — file lock, no network round-trip
integration: batch          # suite ~3min (selftest+pack), over paranoid's <2min rule — and sprint-4 per-land coverage was selftest-only anyway. Batch = full suite once per wave + final qa; a red land is found by the bisect recipe. Subagent shells: the permission classifier can block `build:` invoked directly (both shells, sprint 4) — run it via `bash ops/polaris qa` at the wave gate and record the reduced per-land coverage in the burndown; never silently skip it. Revisit if kickbacks appear.
voice: standard             # plain, friendly English when talking to the human
autolaunch: wt              # Planner opens a Builder pane per ready task in Windows Terminal, beside you
stale_hours: 1              # sweep warns on active locks older than this — build avg 0.2h (n=28); an hour-idle lock is a dead lane, not a slow one (sprint 4: 2 subagent stalls + 1 API-error death)
test: bash kit/ops/polaris doctor --selftest
build: python kit/ops/pack.py --allow-dirty
lint:                       # none — bash + python, no package manager
typecheck:                  # none

branch format: feat/<ID> · integration branch: integrate/<date>
commit format: type(scope): message   # types: feat fix chore test docs
Definition of Done: acceptance boxes checked · `test:` green · `build:` green · `polaris verify` green

## THE SPLIT — read this before you touch anything
This repo IS POLARIS, and it RUNS POLARIS. Those are two different trees and confusing them is the
one mistake that costs real work:

| | `kit/` | `ops/` |
|---|---|---|
| what | the PRODUCT — every file that ships to users | the INSTALLATION — the board you are standing on |
| edit it? | yes, this is where all work happens | NEVER by hand (RULES enforce it) |
| how it changes | you write code | `python kit/ops/pack.py --dogfood` installs a published release |
| ships to users? | yes | no — `pack.py` only ever packs `kit/` |

Every kit file exists twice: `kit/ops/polaris` (source) and `ops/polaris` (installed). Edit the
installed copy and the work is lost the next time we install a release — and until then the board is
running code that exists nowhere in the source. `ops/RULES.tsv` blocks it at write time and names the
source file to edit instead.

The installed instance also LAGS the source: mid-sprint, `kit/ops/` docs and role files describe
behavior the installed CLI does not have yet. When they disagree, the installed CLI plus
`ops/MANUAL.md` are the truth for board mechanics until the next dogfood — check
`bash ops/polaris version` before following any recipe that landed this sprint.

The board (`ops/board/`, `ops/contracts/`, and this file) IS state, and is written normally.

## Release ritual — a release is not done until we run it ourselves
1. bump `kit/ops/VERSION` (human only — it is what tells every installed kit a new POLARIS exists)
2. CHANGELOG entry, same version
3. commit · `git tag vX.Y.Z && git push --tags` — CI builds and publishes the zip
4. **`python kit/ops/pack.py --dogfood`** — downloads the PUBLISHED zip, installs it here, runs the
   board's selftest. This is the only test that walks the path a stranger walks.
5. commit the refreshed `ops/`

The daily CI job fails if `ops/VERSION` ≠ the latest published release — i.e. if we shipped something
we never ran. Skipping step 4 also leaves `main`'s tarball and the raw channel URL serving the OLD
kit to everyone who installed before the `kit/` split existed.

## Write routing — one fact, one home (a fact in two files means one is drifting)
| Fact | Only writer | Only home |
|---|---|---|
| burndown row + Learned log | Integrator | ops/SPRINT.md |
| MAP content | Integrator (via task map_delta) | ops/MAP.md |
| conventions values + Planner calibration notes | EVOLVE (human-approved) | this file, § Planner calibration (ops/roles/ is a RULES-guarded installed copy here) |
| RULES lines | human (EVOLVE proposes) | ops/RULES.tsv |
| task truth | the board scripts | ops/board/** frontmatter |
| kit code + invariants | human only | kit/CLAUDE.md · kit/ops/polaris · kit/ops/dashboard.py · kit/ops/hooks/ |
| the installed instance | `pack.py --dogfood` only | ops/ (never hand-edited) |

## Planner calibration (appended by EVOLVE, human-approved; Planner reads before pointing)
- 2026-07-18 · Ignore the 3pt p50 30.4h bucket (n=1 = T-002): review parking during the off-board-edit collision, not build effort (build split avg 0.1h). Do not point up 3-pointers from it.
- 2026-07-18 · Points do not predict wall-clock here (5pt p50 = 2pt p50 = 0.5h, n=8, 0 kickbacks); they predict scope and merge risk. Wave capacity is planning-bound (carve quality), not build-bound.
- 2026-07-20 · Two carve patterns held at 0 kickbacks across 6 sprint-4 waves (T-020..T-028): (a) serial-chain the hotspot file; run contract-sourced doc tasks parallel to the chain; (b) parallel wording tasks need no depends_on — pin the exact phrase in the contract (T-027/T-028 both cite "already fast-forwarded", merged zero-conflict).

## Kit changelog
- 2026-07-18 · MAP folded: header re-dated, CLI row gains clean-history commands, selftest-install/selftest-dashboard promoted to Modules, dashboard Unverified bullet cleared, Deltas emptied · 3 Deltas lines (T-001, T-003, T-007) + T-003 clearing the untested-dashboard claim
- 2026-07-18 · SPRINT Learned pruned to ≤5: dropped the zero-conflict/paranoid-cost bullet · content institutionalized in CONVENTIONS integration comment + MAP hotspots
- 2026-07-18 · Calibration home moved to this file (§ Planner calibration) with two notes; write-routing row updated; fallback-home gap logged to IDEAS · ops/roles/ is RULES-guarded here, blocking EVOLVE's kit-default target (PLANNER.md §Pointing); metrics n=8, 0 kickbacks, T-002 30.4h outlier
- 2026-07-18 · SPRINT Learned pruned 9→4: dropped write-guard-prefix, off-board-collision, stale 5.11-lag, integrate-lag, seal-blocked bullets; merged the two seal/fold bullets into one corrected installed-vs-source bullet · drift finding LEARNED 9>5; waves 2-6 all folded via MANUAL fallback, sprint 3 complete
- 2026-07-18 · integration: paranoid comment rewritten with real suite cost (~2-3min), keep-rationale (zero-bisect red lands) and revisit triggers (>5min suite or >5-task waves) · 6 paranoid waves this sprint, 0 kickbacks; old comment claimed 15s
- 2026-07-18 · THE SPLIT gains installed-LAGS-source paragraph: installed CLI + ops/MANUAL.md are board-mechanics truth until the next dogfood · sprint 3 ran installed 5.12.0 against kit 5.13.0-unreleased; T-017 seal recipe unrunnable, 5 waves needed MANUAL fold
- 2026-07-20 · stale_hours 4→1 · build avg 0.2h (n=28); sprint 4's stale locks were dead lanes (2 subagent stalls + 1 API-error death), not slow builds
- 2026-07-20 · integration comment codifies the classifier-safe fallback (build: via bash ops/polaris qa at the wave gate, reduced per-land coverage recorded in burndown); kit-entrypoint gap logged to IDEAS · build: classifier-blocked in both subagent shells all sprint 4, 6 waves ran selftest-only per land
- 2026-07-20 · integration: paranoid → batch · suite ~3min over paranoid's <2min rule; per-land coverage was selftest-only anyway; batch = full suite once per wave + final qa, red lands found by the bisect recipe; revisit if kickbacks appear
- 2026-07-20 · Planner calibration gains the two sprint-4 carve patterns; SPRINT Learned pruned 8→5 (carve-pattern ×2 + classifier/pack bullets institutionalized) · 0 kickbacks across 6 waves T-020..T-028; T-027/T-028 merged zero-conflict on a contract-pinned phrase
