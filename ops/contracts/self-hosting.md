# CONTRACT: self-hosting detection            (v1 — 2026-07-14)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates "a kit source tree" from "an installed POLARIS". Several kit files must branch on this, and
they MUST all branch on the SAME fact, or they disagree about what repo they are standing in.

## Interface
The tell is the existence of `<kit-root>/ops/pack.py`.

```
pack.py present  →  <kit-root> is a KIT SOURCE TREE (the product)
pack.py absent   →  <kit-root> is an INSTALLED kit  (a target repo)
```

Why this file: `pack.py` is a kit-repo tool and is the ONE file `install.sh` deliberately never copies
into a target. So it exists in a source tree and nowhere else, by construction. It is already the tell
`install.sh` uses (see its "the kit folder is now redundant" note) — this contract just names it.

Derived, for a repo that self-hosts (i.e. the CWD repo has BOTH):
```
<repo>/kit/ops/pack.py exists   →  this repo builds POLARIS *and* runs it
<repo>/ops/            exists   →  ...and ops/ is its INSTALLATION, not its source
```

## Invariants
- Never test for `ops/board/` or `ops/CONVENTIONS.md` to answer this question. `CONVENTIONS.md`
  answers a DIFFERENT one ("has INIT run in this target?") and conflating them is what shipped the
  bug where a fresh install looked like a live board and locked INIT out.
- A self-hosting repo's `ops/` is refreshed ONLY by installing a published release
  (`python kit/ops/pack.py --dogfood`). Nothing else may write it.
- Detection must be cheap and side-effect free: one file-existence test, no git calls, no network.

## Example
```bash
# in kit/ops/polaris — is the repo I am running inside also my own source tree?
if [ -f "$PRIMARY/kit/ops/pack.py" ]; then
  # yes: `update` is the wrong command here — it would install ops/ over itself.
  # Point the human at:  python kit/ops/pack.py --dogfood
fi
```

## Changelog
- v1 2026-07-14: created for T-001, T-002.
