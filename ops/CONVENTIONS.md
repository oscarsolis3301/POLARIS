# CONVENTIONS
base: main                  # base branch
claim: local-lock           # one machine, many sessions — file lock, no network round-trip
integration: paranoid       # the suite is ~15s; on infrastructure a bad merge is expensive. Test every merge.
voice: standard             # plain, friendly English when talking to the human
autolaunch: wt              # Planner opens a Builder pane per ready task in Windows Terminal, beside you
stale_hours: 4              # sweep warns on active locks older than this
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
| conventions values + Planner calibration notes | EVOLVE (human-approved) | this file · ops/roles/PLANNER.md |
| RULES lines | human (EVOLVE proposes) | ops/RULES.tsv |
| task truth | the board scripts | ops/board/** frontmatter |
| kit code + invariants | human only | kit/CLAUDE.md · kit/ops/polaris · kit/ops/dashboard.py · kit/ops/hooks/ |
| the installed instance | `pack.py --dogfood` only | ops/ (never hand-edited) |
