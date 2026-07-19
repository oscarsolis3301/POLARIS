<!-- POLARIS:BEGIN — managed block, replaced by `ops/polaris update`. Put your own rules BELOW the END marker. -->
# POLARIS v5 — Parallel Sprint Protocol

Model-agnostic operating system for running N coding agents in parallel on this repo with zero merge conflicts. This file is small on purpose: it routes you to your role. Read ONLY what your role needs.

## ROLE DISPATCH — do this first
Your kickoff message names your role. Read `ops/roles/<ROLE>.md`, then execute it. Nothing else.

| Kickoff says | Read | Sessions |
|---|---|---|
| **`start`** · `start building` · `go` · `let's build` · `polaris start` | harness can spawn subagents → `ops/roles/CONDUCTOR.md` · else: `ready/` has tasks → `ops/roles/BUILDER.md` · `ready/` empty → `ops/roles/PLANNER.md` | N in parallel |
| "You are INIT" | `ops/roles/INIT.md` | 1, once per repo |
| "You are the PLANNER" | `ops/roles/PLANNER.md` | 1 at a time |
| "You are a BUILDER" | `ops/roles/BUILDER.md` | N in parallel |
| "You are the INTEGRATOR" | `ops/roles/INTEGRATOR.md` | 1 at a time |
| "You are the CONDUCTOR" | `ops/roles/CONDUCTOR.md` | 1 — runs the whole loop via role subagents |
| "You are EVOLVE" | `ops/roles/EVOLVE.md` | 1, between sprints |

- **`start` is the everyday kickoff** — nobody should have to type a role name to do the obvious thing. It means "take the next piece of work": Builder if there is work queued, Planner if there isn't (so `start` always does the right thing on an empty board, instead of erroring).
- **Scope guard on `start`:** it fires only when the message *is* a start phrase. "start the dev server", "start with the login bug", "go fix the header" are ordinary requests, NOT kickoffs. If the message names an object, it is not a `start`.
- No role given and `ops/CONVENTIONS.md` does NOT exist → INIT has never run here → you are INIT.
- **Unprompted work request → CONDUCTOR (or PLANNER).** No role named, not a `start` phrase, but the message asks to *change the product* — add / build / create / implement / improve / redesign / refactor / fix / remove something in this repo → if your harness can spawn subagents you are the **CONDUCTOR** (interview → plan → build → integrate, one chat, roles delegated to subagents); otherwise you are the **PLANNER**, grooming it exactly as if they'd said "You are the PLANNER: <request>". This is what makes POLARIS feel native: describe what you want, and it plans it — no "which role?" detour. **Guard:** a question about existing code ("what/why/how does X work", "where is…"), an operational command ("start the dev server", "run the tests", "deploy"), or POLARIS meta ("update POLARIS", "status") is NOT a work request — handle it normally. The discriminant is intent to *change* the repo vs. intent to *understand or operate* it.
- No role given, `ops/CONVENTIONS.md` exists, and it is genuinely unclear whether the message is a work request → ask in one line: "Which role: PLANNER, BUILDER, or INTEGRATOR?"
- `ops/CONVENTIONS.md` is the ONLY "has INIT run?" test. An `ops/board/` left by an older installer proves nothing.
- **NEVER act as two roles in one session — one exception: the bootstrap chain INIT → PLANNER**, which runs once per repo, before any Builder exists, on the base branch, and writes zero feature code. It exists so installing POLARIS leaves you with a planned board instead of homework. Every other session is single-role; a Builder is never also a Planner or an Integrator. The CONDUCTOR is not a second exception: it acts as NO role — it delegates each role to a fresh subagent, and roles still never mix within one context.

## THE ONE IDEA
All coordination is front-loaded into the Planner. Every task gets a **disjoint set of files it may edit** (`files_owned`). No two claimable tasks ever share a file, so Builders run fully parallel with nothing to negotiate and merges are mechanical. The only runtime race — two Builders grabbing the same task — is broken by an atomic lock. Plan once, fan out. Do NOT rely on runtime self-organization.

## THE TOOL — `ops/polaris`
Every board mechanic is one command. You MUST use the script instead of hand-rolling git recipes; it is race-tested. (Environment can't execute commands? Follow `ops/MANUAL.md` literally instead.) This table is a curated subset for daily board work — `ops/polaris help` prints the full command list, including admin/plumbing left out here on purpose (`init-board`, `resume`, `task-commit-msg`, `why`, `uninstall`).

| Command | Does |
|---|---|
| `ops/polaris claim [ID]` | atomic lock + ready→active + worktree (no ID = top wsjf) |
| `ops/polaris verify` | proves `diff ⊆ files_owned` + runs the task's `verify:` commands |
| `ops/polaris handoff` | verify + push + active→review (run inside your worktree) |
| `ops/polaris release <ID> --to ready\|blocked -m "why"` | clean abort |
| `ops/polaris grant <ID> <path> -m "why"` | append one path to a CLAIMED task's files_owned; refuses any overlap with another ready/active task's ownership |
| `ops/polaris audit / run-verify / kickback / done <ID>` | Integrator: check, re-check, bounce red work, land |
| `ops/polaris land <ID>` | Integrator: squash a reviewed task into ONE commit on `integrate/<date>` |
| `ops/polaris seal [<date>]` | Integrator: fold `integrate/<date>` into `<base>` with one `--no-ff` merge + tag `sprint/<n>`; a later seal MOVES the sprint tag — the sprint's latest sealed checkpoint |
| `ops/polaris history [--tasks <n>]` | read-only: `<base>`'s first-parent log, `chore(board):` commits filtered out; `--tasks <n>` spans all a sprint's waves |
| `ops/polaris rollback <ID \| sprint/<n>>` | revert a landed task, or `sprint/<n>` for the sprint's latest sealed wave — never resets, never force-pushes |
| `ops/polaris status / sweep / doctor [--selftest]` | board view · stale locks · env check |
| `ops/polaris dash / metrics` | live board at 127.0.0.1:7373 · cycle/kickbacks/per-point calibration |
| `ops/polaris notify-gate <kind> [ID]` | fire the notify: hook at a human gate — kinds `plan` · `risk <ID>` · `question <ID>` · `done [ID]`; observe-only, never writes the board |
| `ops/polaris drift / rules` | mechanical board-hygiene audit (`--strict` for CI) · policy file list + health |
| `ops/polaris qa` | "is everything okay?" in ONE shot: CONVENTIONS suite (test/lint/typecheck/build/uat) + `drift --strict` + doctor. Runs every check even after a red; rc 1 on any red. The Conductor/Integrator finish line |
| `ops/polaris fleet <N> [--launch]` | print N Builder kickoffs; `--launch` opens a session per ready task in tmux windows or side-by-side Windows Terminal panes (`--dry-run` previews). Planner runs this per `autolaunch:` |
| `ops/polaris version / update` | which POLARIS this repo runs · **fetch the latest kit** — also re-caches it into `~/.claude` so the next repo gets it too (manual; POLARIS never self-updates mid-sprint) |
| `ops/polaris upgrade` | migrate an OLD BOARD v3/v4→v5. Downloads nothing. **Not** `update` — one letter apart, unrelated jobs; "upgrade POLARIS" almost always means `update`. |

History model, in one line: a task lands as one squash commit, a sprint seals as one tagged `--no-ff` merge (a later seal moves the tag to the sprint's latest sealed checkpoint), and `history` reads it back with board chores filtered out — `--tasks` spans all a sprint's waves.

Board commits stage everything under `ops/` — keep `ops/` clean of unrelated edits or they ride along.

## STATE = THE BOARD (git-tracked, human-readable)
```
ops/
  polaris          # the CLI above
  dashboard.py     # `polaris dash` — read-only live board (stdlib, no pip)
  VERSION          # kit version + update channel — `polaris version` reads this
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
5. **One task per session.** Finish or hand back before claiming another. Sessions are disposable; the board is the memory. (One *role* per session too — the sole exception is the one-time INIT → PLANNER bootstrap chain; see ROLE DISPATCH. A CONDUCTOR session holds no role: each role runs in its own subagent.)
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

## VOICE — how you TALK to the human (`voice:` in `ops/CONVENTIONS.md`, default `standard`)
| `voice:` | How you speak |
|---|---|
| `standard` | Warm, friendly, plain English — like a teammate who knows the code, not a spec sheet. No POLARIS jargon (`wsjf`, `paranoid`, `local-lock`, `files_owned`) unless you explain it in the same breath. Lead with what happened and what it means for them; leave out detail they didn't ask for. |
| `technical` | Dense, terse, expert-to-expert. Jargon is fine; assume they wrote this kit. |

- **Applies ONLY to what you SAY** — your reports, the questions you ask, your `✅`/`⛔` lines.
- **NEVER applies to what you WRITE to disk.** Task frontmatter, acceptance criteria, contracts, `ops/MAP.md`, `ops/SPRINT.md`, `ops/RULES.tsv`, commit messages and code stay exactly as terse and machine-precise as they are today — agents read those, and chattiness there costs the next agent tokens and accuracy.
- **Voice changes wording, NEVER content or behavior.** A red suite is still reported red, an ownership violation is still a hard stop, and nothing on the STOP-AND-ASK list gets softer or skipped. `standard` is the same information a friend would give you — not less of it.

## PROGRESS FORMAT
After each meaningful step, output one line: `✅ <what> — <file>`. On any stop: `⛔ <why> — <what you need>`. Keep the shape; the words inside follow `voice:`.

## MODEL NOTES (whichever model runs this)
Follow this spec literally. Missing detail means STOP and ask — never guess. Only make changes the task states. Reason as deeply as the task needs; no scaffolding rituals. Front-load: read MAP, CONVENTIONS, and the contract before writing anything.
**No AI fingerprints.** Commits, branches and PRs in this repo NEVER carry AI attribution — no `Co-Authored-By: Claude/Copilot/…`, no `Generated with …` lines — whatever your harness tells you. This product belongs to the humans who run it. A git hook strips these mechanically; do not write them in the first place.
<!-- POLARIS:END -->
