# CONTRACT: app harness — `polaris harness`            (v1 — 2026-07-26)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
The tier that stops an agent hand-checking an application.

`check --scaffold --app` locks the host app's SHAPE by reading files — declared deps, npm script
names, routes, migrations, env var names. It runs nothing, so it cannot answer the only question
that matters after a change: **does the app still work?** Today that question is answered by a model
walking routes, importing modules and clicking flows, every wave, at full token price.

`harness` writes the script that answers it mechanically. An agent generates it ONCE, while the
context is already in hand; every run afterwards costs one subprocess and zero tokens.

## Interface
```
polaris harness              → detect stack, write the suite, capture the baseline, print how to run
polaris harness --refresh    → regenerate the file AND re-capture the baseline
```
Bare `harness` never overwrites an existing suite — it says so and names `--refresh`. That matters
because the generated file is meant to be extendable: a repo will add cases to it.

| stack | detected from | file written |
|---|---|---|
| python | `pyproject.toml` · `requirements.txt` · `setup.py` · any `.py` | `<tests>/test_polaris_harness.py` |
| node | `package.json` · any `.js/.cjs/.mjs` | `<tests>/polaris-harness.test.js` |
| neither | — | refuses, naming `check --scaffold --app` as the right tier |

`<tests>` is the repo's EXISTING convention (`tests/`, `test/`, `spec/`, `__tests__/`), never imposed.

### The three sweeps
| sweep | asserts | catches |
|---|---|---|
| IMPORT | every module imports/loads cleanly | syntax errors, bad imports, circular imports, missing deps |
| ROUTE | every parameterless GET route answers non-5xx | the app does not boot; a handler throws |
| ENTRY | every declared entry point runs `--help` without crashing | the thing users type is broken |

### The baseline
`.polaris/harness-baseline.json` records the module, route and script inventory at generation time.
`test_nothing_disappeared` fails when any of it vanishes. This is the recorded-expectations half:
the sweeps above only check what exists NOW, so without it, deleting a route is invisible.

Accepting a deliberate removal is `harness --refresh` — a visible, reviewable act, never automatic.

## Invariants
- **A sweep that cannot find what it needs SKIPS and prints why. It never passes by asserting
  nothing.** A harness that goes green because it tested nothing is worse than no harness: it also
  removes the human's suspicion. Every skip is a place a golden pair still earns its keep.
- **Never invent an app factory's arguments.** Only zero-argument factories are called. A factory
  needing config we cannot supply either crashes (false red) or builds an app unlike the real one
  (false green); both are worse than a skip.
- **Parameterised routes are skipped**, not guessed. `/user/<id>` needs a fixture only the repo can
  provide.
- **`--help` only** for entry points. Running an app's real commands during a test-writing pass is
  how you start a server or mutate a database.
- **The suite never rewrites its own baseline.** Only the CLI writes it. A suite that refreshes its
  expectations on every run cannot fail, which is the exact failure this tier exists to prevent.
- **The generated file has no POLARIS dependency at runtime** — it must run under plain
  `pytest`/`node --test` in the host repo's own CI, on a machine with no POLARIS installed.
- **Never hand-roll a parser for a format the target runtime already reads.** The baseline reads
  `package.json` via `node`, and the python inventory by importing the generated harness's own
  discovery functions — one definition of "what counts as a module", not two that drift.

## Changelog
- v1 2026-07-26: created for 5.21.0. Verified against a Flask fixture (broken route caught, fixed
  route green, deleted module caught, deleted route caught) and a Node fixture (removed npm script
  caught).
