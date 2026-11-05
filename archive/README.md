# archive — where retired files go to rest

Nothing in POLARIS gets deleted. When a change makes a file obsolete, it moves here instead —
under a dated folder, keeping its original path — so there is always a record of what the kit
used to look like and why it changed.

Everything in here is kept in git and **excluded from the shipped zip** (`ops/pack.py` skips
`archive/`), so retired files never land in anybody's project.

To bring something back: `git mv archive/<folder>/<original/path> <original/path>`.

---

## 2026-07-13 — the empty board skeleton
`2026-07-13-empty-board-skeleton/`

The six board columns and the contracts folder, as empty `.gitkeep` files. The installer used to
copy these into every project, which meant a brand-new install looked — to POLARIS itself — exactly
like a project it had already set up. So when you asked it to get started, it tried to talk you out
of it.

Setting up a project now creates the board itself (`polaris init-board`, which INIT runs), so the
installer has nothing to copy and these files have no job left. Retired in v5.2.0.

## 2026-11-04 — the first draft of the save-hops plan
`2026-11-04-save-hops-draft/`

The first write-up of "POLARIS should reorganize a project so agents need fewer lookups". A review
against the kit's real code found it would not reliably deliver — its shortcut chain started with
pieces most repos never get, its trigger rarely fired, and moving files safely needed more than the
import finder could see. The reviewed version lives at `plans/save-hops.md`; this draft is kept so
the reasoning behind every fix stays readable.
