# POLARIS v5 — parallel-sprint protocol

Run N coding agents in parallel on one repo with **zero merge conflicts**. All coordination is
front-loaded into a planning pass that gives every task a *disjoint set of files it may edit*, so
builders run fully parallel with nothing to negotiate and merges stay mechanical. Model-agnostic;
pure bash + git, no dependencies.

## Install (into any git repo)

```
cd /path/to/your/repo
python /path/to/polaris-v5.zip .
```

That one command arms your machine (a Claude Code skill, a cached copy of the kit, and permission
rules) and installs POLARIS into the current repo. Under Claude Code it then runs INIT → PLANNER for
you: answer a couple of questions and you land on a planned board, ready to build.

No Python on the target machine? `ops/MANUAL.md` has the hand-run fallback for every command.

## Everyday use

- **`start`** — take the next piece of work: a builder if the board has ready tasks, otherwise the planner.
- **Describe what you want built** — POLARIS grooms it into small, file-disjoint tasks and can open one
  builder session per task beside you.
- `ops/polaris status` — the board at a glance.  `ops/polaris dash` — a live web view (needs python).
- `ops/polaris --help` — every command (claim · verify · handoff · audit · done · why · resume · drift · metrics · fleet …).

## The pieces

| Path | What it is |
|---|---|
| `ops/polaris` | the board CLI — every board mechanic is one race-tested command |
| `ops/roles/` | INIT · PLANNER · BUILDER · INTEGRATOR · EVOLVE — your kickoff message names your role |
| `CLAUDE.md` | the protocol and its invariants; small on purpose — it routes you to your role |
| `ops/CONVENTIONS.md` · `ops/MAP.md` · `ops/SPRINT.md` · `ops/board/` | your board state, git-tracked and human-readable |

## The one idea

Plan once, fan out. Two tasks that can be claimed at the same time never share a file, so builders
never collide. The only runtime race — two builders grabbing the same task — is broken by an atomic
lock, and `claim` skips a locked task to take the next one, so a fleet of builders lands on distinct
work. Every gate (`verify`, `audit`, the write-time guard) mechanically proves a builder only touched
the files its task owns.

Docs and issues: https://github.com/oscarsolis3301/POLARIS
