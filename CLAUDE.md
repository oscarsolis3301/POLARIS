# POLARIS v5 — Parallel Sprint Protocol

Model-agnostic operating system for running N coding agents in parallel on this repo with zero merge conflicts. This file is small on purpose: it routes you to your role. Read ONLY what your role needs.

## ROLE DISPATCH — do this first
Your kickoff message names your role. Read `ops/roles/<ROLE>.md`, then execute it. Nothing else.

| Kickoff says | Read | Sessions |
|---|---|---|
| "You are INIT" | `ops/roles/INIT.md` | 1, once per repo |
| "You are the PLANNER" | `ops/roles/PLANNER.md` | 1 at a time |
| "You are a BUILDER" | `ops/roles/BUILDER.md` | N in parallel |
| "You are the INTEGRATOR" | `ops/roles/INTEGRATOR.md` | 1 at a time |
| "You are EVOLVE" | `ops/roles/EVOLVE.md` | 1, between sprints |

- No role given and `ops/board/` does NOT exist → you are INIT.
- No role given and `ops/board/` exists → ask in one line: "Which role: PLANNER, BUILDER, or INTEGRATOR?"
- NEVER act as two roles in one session.

## THE ONE IDEA
All coordination is front-loaded into the Planner. Every task gets a **disjoint set of files it may edit** (`files_owned`). No two claimable tasks ever share a file, so Builders run fully parallel with nothing to negotiate and merges are mechanical. The only runtime race — two Builders grabbing the same task — is broken by an atomic lock. Plan once, fan out. Do NOT rely on runtime self-organization.

## THE TOOL — `ops/polaris`
Every board mechanic is one command. You MUST use the script instead of hand-rolling git recipes; it is race-tested. (Environment can't execute commands? Follow `ops/MANUAL.md` literally instead.)

| Command | Does |
|---|---|
| `ops/polaris claim [ID]` | atomic lock + ready→active + worktree (no ID = top wsjf) |
| `ops/polaris verify` | proves `diff ⊆ files_owned` + runs the task's `verify:` commands |
| `ops/polaris handoff` | verify + push + active→review (run inside your worktree) |
| `ops/polaris release <ID> --to ready\|blocked -m "why"` | clean abort |
| `ops/polaris audit / run-verify / kickback / done <ID>` | Integrator: check, re-check, bounce red work, land |
| `ops/polaris status / sweep / doctor [--selftest]` | board view · stale locks · env check |
| `ops/polaris dash / metrics` | live board at 127.0.0.1:7373 · cycle/kickbacks/per-point calibration |
| `ops/polaris drift / rules` | mechanical board-hygiene audit (`--strict` for CI) · policy file list + health |
| `ops/polaris fleet <N> / upgrade` | print or tmux-launch N Builder kickoffs · idempotent v3/v4→v5 |

Board commits stage everything under `ops/` — keep `ops/` clean of unrelated edits or they ride along.

## STATE = THE BOARD (git-tracked, human-readable)
```
ops/
  polaris          # the CLI above
  dashboard.py     # `polaris dash` — read-only live board (stdlib, no pip)
  MANUAL.md        # fallback recipes if you cannot execute commands
  PROMPTS.md       # copy-paste kickoffs for every role
  MAP.md           # ≤200-line codebase map. Read THIS, not the repo.
  RULES.tsv        # repo policy as DATA: danger zones + content guards, one line each
  CONVENTIONS.md   # config header (base/claim/integration/test cmds) + rules
  SPRINT.md        # goal, capacity, burndown, Learned log
  contracts/       # interface contracts — the seams between tasks
  templates/       # TASK.md, CONTRACT.md
  hooks/ ci/       # Claude Code write-guard · optional GitHub Actions gate
  board/
    backlog/ ready/ active/ review/ done/ blocked/   # one .md per task
    EVENTS.ndjson  # append-only telemetry (union-merged) — never hand-edit
```
`.claude/` ships a project skill (auto-routes any Claude Code session to this protocol) and a PreToolUse hook wiring the write-guard.
A task's state is the folder its file sits in; moving it (via the script) is the transition. Worktrees live in `.polaris/wt/<ID>` (gitignored). Locks live in `$(git rev-parse --git-common-dir)/polaris-locks/` — shared across all worktrees, never committed.

## INVARIANTS — NEVER violate
1. **Ownership.** A Builder creates/edits ONLY paths in its task's `files_owned`. `context_files` and `ops/MAP.md` are read-only. Need anything else → STOP, hand back. `polaris verify` MUST pass before handoff — it mechanically proves the diff ⊆ owned AND that no `ops/RULES.tsv` rule is violated. Rules bind even inside `files_owned` and even outside Builder sessions — they are the repo's danger zones and content guards, machine-enforced. (Under Claude Code a PreToolUse guard also blocks both as writes happen; a guard rejection means hand back or ask the human, never work around it.)
2. **Ready gate.** A task enters `ready/` only if: ≤5 points, every `depends_on` is in `done/`, its contract exists, and its `files_owned` overlaps NOTHING in `ready/` or `active/`.
3. **Contract before code.** Contract missing or ambiguous → `blocked/` with a note. NEVER invent an interface.
4. **Green before `review/`.** Full test commands from CONVENTIONS green AND `polaris verify` green. Red work never leaves `active/`.
5. **One task per session.** Finish or hand back before claiming another. Sessions are disposable; the board is the memory.
6. **Board mutations go through `ops/polaris`** (they commit on the base branch in the primary checkout). Code commits go on `feat/<ID>` in your worktree. Never mix the two.
7. **Claim = `polaris claim`.** Lock exists → task is taken → take the next one. Never edit a task you did not claim.
8. **Scope = the task.** No drive-by refactors, no extra features, no new dependencies. Want more? One line in `ops/board/backlog/IDEAS.md` for the Planner.
9. **Only the Integrator merges**, and a task with `risk: high` NEVER merges without explicit human approval in the conversation.
10. **No secrets** in the repo, board, contracts, or notes. Reference env-var names only.
11. **RULES change = human decision.** Agents may PROPOSE `ops/RULES.tsv` lines (EVOLVE does this from evidence); only the human applies them. Never edit or delete a rule to get unblocked.

## STOP AND ASK THE HUMAN before
Deleting any file · adding a dependency · changing DB schema or migrations · editing outside `files_owned` · touching auth/payments/prod config not explicitly owned · any force-push · merging any `risk: high` task.

## TOKEN DISCIPLINE — this is how we stay cheap and fast
- **Read the MAP, not the repo.** `ops/MAP.md` is the summary; `polaris status` is the board — never browse either raw.
- **Grep, don't browse.** Locate by search; open files at targeted line ranges. NEVER read a large file end-to-end without a written reason.
- **A Builder's entire context** = this file + its role file + the task file + the contract + `files_owned` + listed `context_files`. Anything else needs a one-line justification in the task's Notes.
- **Summarize once, reuse.** Append findings to the task's Notes; never re-derive them.
- **One task, one session, then close.** A fresh session per task beats one long degraded chat.
- **Terse artifacts.** Frontmatter for machines, binary acceptance criteria, no essays. Reference `path:line`, never paste file bodies.
- **Spikes exist so five tasks don't each re-explore.** Time-boxed read, written verdict, done.

## MODEL ROUTING (cost — set per session by the human)
- INIT / PLANNER / INTEGRATOR / EVOLVE: strongest tier available — their mistakes multiply.
- BUILDER: mid tier for tasks ≤3 points; strongest tier for 5-point or `risk: high` tasks.
- Phrase is tier-relative on purpose: models change, the routing rule doesn't.

## PROGRESS FORMAT
After each meaningful step, output one line: `✅ <what> — <file>`. On any stop: `⛔ <why> — <what you need>`.

## MODEL NOTES (whichever model runs this)
Follow this spec literally. Missing detail means STOP and ask — never guess. Only make changes the task states. Reason as deeply as the task needs; no scaffolding rituals. Front-load: read MAP, CONVENTIONS, and the contract before writing anything.
