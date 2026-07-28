# POLARIS v5 — PROTOCOL reference

The half of the protocol that only SOME sessions need. `CLAUDE.md` is the router every session pays
for (the harness injects it into the conductor and into every subagent); this file is what you open
when you actually need it. Read the section you need, not the file.

| you need | section |
|---|---|
| the command table — what `polaris <x>` does | THE TOOL |
| what lives where on disk | STATE = THE BOARD |
| why a lane exists, and why one role never does two jobs | LANES |
| how to stay cheap: pack-first, find-first, read-less | TOKEN DISCIPLINE |
| which model tier a role deserves | MODEL ROUTING |
| how to TALK to the human | VOICE |
| how to behave as a model running this | MODEL NOTES |

## THE TOOL — `ops/polaris`
Every board mechanic is one command. You MUST use the script instead of hand-rolling git recipes; it is race-tested. (Environment can't execute commands? Follow `ops/MANUAL.md` literally instead.) This table is a curated subset for daily board work — `ops/polaris help` prints the full command list, including admin/plumbing left out here on purpose (`init-board`, `resume`, `task-commit-msg`, `why`, `uninstall`). The script itself is `globals + lib-loader + dispatch`: `ops/polaris` is the only entry point, and every function body lives in `ops/lib/*.sh`, sourced in a fixed order at startup (a missing module refuses with a re-run-installer / `ops/polaris update` remedy).

| Command | Does |
|---|---|
| `ops/polaris pack <ID>` | **the whole context for one task, in ONE call** — frontmatter + Why + acceptance, the contract verbatim, the repo's detected house style, the code-map for every owned directory, the public API surface each owned path must not break, the gotchas/co-change lines that mention an owned path, and the exact `verify:` commands. Run it FIRST, before reading anything. It replaces the 6-15 exploratory round trips a cold Builder otherwise spends rediscovering its own task |
| `ops/polaris find <symbol>` · `show <path>#<symbol>` | the 1-hop "where is X": `path:line` + signature per hit, ranked, from a generated index; `show` prints ONE symbol's body instead of the file. `--api <glob>` = the sorted public surface of a path (the shape goldens lock). Run these BEFORE Grep |
| `ops/polaris claim [ID]` | atomic lock + ready→active + worktree (no ID = top wsjf) |
| `ops/polaris verify` | proves `diff ⊆ files_owned` + runs the task's `verify:` commands |
| `ops/polaris handoff` | verify + active→review; `publish: direct` pushes feat/<ID>, `publish: pr` keeps it local (seal pushes only integrate/<date>) — run inside your worktree |
| `ops/polaris release <ID> --to ready\|blocked -m "why"` | clean abort |
| `ops/polaris grant <ID> <path> -m "why"` | append one path to a CLAIMED task's files_owned; refuses any overlap with another ready/active task's ownership |
| `ops/polaris audit / run-verify / kickback / done <ID>` | Integrator: check, re-check, bounce red work, land |
| `ops/polaris land <ID>` · `land --express <ID>` | Integrator: squash a reviewed task into ONE commit on `integrate/<date>`. `--express` = one-pass small-change landing (land + full suite + seal + done in one session); refuses unless exactly one review task, `risk: normal`, `express:` ≠ off, `publish: direct` |
| `ops/polaris seal [<date>]` | Integrator: `publish: direct` — fold `integrate/<date>` into `<base>` with one `--no-ff` merge + tag `sprint/<n>` (a later seal MOVES the tag — the sprint's latest sealed checkpoint). `publish: pr` — push ONLY `integrate/<date>` + print the PR-create URL; the human merges it with a MERGE COMMIT; then `seal --sync` pulls `<base>`, verifies every `[<ID>]` landed, moves/creates the tag, deletes `integrate/<date>` both sides |
| `ops/polaris check` · `check --scaffold` | golden-output acceptance, ZERO LLM: `ops/tests/<name>.cmd` is run and its stdout diffed against `<name>.expected`. `--scaffold` GENERATES the pairs from observed behavior (public API surface per source dir + parsed output shapes), discarding anything that flaps or is empty. Regression locks, not correctness proofs — review them once, then they cost a subprocess forever |
| `ops/polaris report [--sprint <n> \| --all]` | read/write: render the management-readable per-sprint record to `<reports>/sprint-<n>.md` from board state (no flag = current sprint); never commits — `seal` rides the report into the wave |
| `ops/polaris history [--tasks <n>]` | read-only: `<base>`'s first-parent log, `chore(board):` commits filtered out; `--tasks <n>` spans all a sprint's waves |
| `ops/polaris rollback <ID \| sprint/<n>>` | revert a landed task, or `sprint/<n>` for the sprint's latest sealed wave — never resets, never force-pushes |
| `ops/polaris status [--brief] / sweep / doctor [--selftest [--only <pattern>]]` | board view (`--brief` = one plain-English paragraph, no table) · stale locks + merged `integrate/*` strays · env check (`--only <pattern>` = spine + only labeled drills matching `<pattern>`) |
| `ops/polaris board-fm [<col>…]` | one TAB line per task — the nine fields the ready gate and dedupe use. The Planner reads THIS, never the board files |
| `ops/polaris dash / metrics` | live board at 127.0.0.1:7373 · cycle/kickbacks/per-point calibration (`metrics` opens with a plain-English summary line) |
| `ops/polaris brain [--refresh]` | (re)build `.polaris/brain/` — a generated, gitignored, any-model knowledge base that kills cold-start re-derivation; `--refresh` = incremental rebuild. `doctor` warns when it's stale |
| `ops/polaris notify-gate <kind> [ID]` | fire the notify: hook at a human gate — kinds `plan` · `risk <ID>` · `question <ID>` · `done [ID]`; observe-only, never writes the board |
| `ops/polaris drift / rules` | mechanical board-hygiene audit (`--strict` for CI) · policy file list + health |
| `ops/polaris qa` | "is everything okay?" in ONE shot: CONVENTIONS suite (test/lint/typecheck/build/uat) + `drift --strict` + doctor. Runs every check even after a red; rc 1 on any red. `finish` runs this for you at the close |
| `ops/polaris finish` | "is the RUN over?" — the mechanical half of CONDUCTOR.md's run-over definition in ONE call: nothing building, nothing waiting to land, `ready/` drained per `drain:`, no unmerged `integrate/<date>`, no orphan lock, clean tree, `qa` green on `<base>`. rc 0 = complete, and the `notify-gate done` hook fires exactly once per finished state; rc 1 names every pending thing. `caveat:` lines are not gates — the close must mention them. **The last command of every lane**, and the only thing that licenses the `# 🎉 Complete!` H1 (ops/contracts/run-finish.md) |
| `ops/polaris fleet <N> [--launch]` | print N Builder kickoffs; `--launch` opens a session per ready task in tmux windows or side-by-side Windows Terminal panes (`--dry-run` previews). Planner runs this per `autolaunch:` |
| `ops/polaris slim [--apply\|--restore]` | the per-context TOKEN TAX, measured. Every skill/agent/command definition under `~/.claude` injects its name+description into the system prompt of every session AND every subagent, invoked or not. Reports bytes per family and what a 6-8 context run pays for them; `--apply` MOVES the identified claude-flow machinery into `~/.claude/.polaris-archived/` (never deletes, always `--restore`-able) and leaves anything it cannot positively identify alone |
| `ops/polaris version / update` | which POLARIS this repo runs · **fetch the latest kit** — also re-caches it into `~/.claude` so the next repo gets it too (manual; POLARIS never self-updates mid-sprint) |
| `ops/polaris upgrade` | migrate an OLD BOARD v3/v4→v5. Downloads nothing. **Not** `update` — one letter apart, unrelated jobs; "upgrade POLARIS" almost always means `update`. |

History model, in one line: a task lands as one squash commit, a sprint seals as one tagged `--no-ff` merge (a later seal moves the tag to the sprint's latest sealed checkpoint), and `history` reads it back with board chores filtered out — `--tasks` spans all a sprint's waves.

Board commits touch only the moved set (`ops/board/**` + `ops/SPRINT.md`) on `refs/heads/polaris/board`; everything else in `ops/` (`MAP.md`, `contracts/`, `CONVENTIONS.md`, `RULES.tsv`) stays on `<base>`.

## STATE = THE BOARD (git-tracked, human-readable)
```
ops/
  polaris          # the CLI above
  lib/             # ops/lib/*.sh — CLI function bodies sourced in fixed order: core·ownership·search·builder·integrate·knowledge·observe·admin + selftest/
  index.py         # `polaris find/show` — generated SQLite code index (.polaris/index.db)
  dashboard.py     # `polaris dash` — read-only live board (stdlib, no pip)
  VERSION          # kit version + update channel — `polaris version` reads this
  PROTOCOL.md      # this file — the half of the protocol only some sessions need
  MANUAL.md        # fallback recipes if you cannot execute commands
  PROMPTS.md       # copy-paste kickoffs for every role
  MAP.md           # ≤200-line codebase map. Read THIS, not the repo.
  RULES.tsv        # repo policy as DATA, one line each — three kinds: `path` · `content` · `ask`
                   #   `ask` = the same denial as `path`, lifted only by a human's recorded approval on the task
  CONVENTIONS.md   # config header (base/claim/integration/test cmds) + rules
  SPRINT.md        # goal, capacity, burndown, Learned log
  contracts/       # interface contracts — the seams between tasks
  templates/       # TASK.md, CONTRACT.md
  tests/           # <name>.cmd + <name>.expected — golden acceptance, run by `polaris check`
  hooks/ ci/       # Claude Code write-guard · optional GitHub Actions gate
  board/
    backlog/ ready/ active/ review/ done/ blocked/   # one .md per task
    EVENTS.ndjson  # append-only telemetry (union-merged) — never hand-edit
```
`.claude/` ships a project skill (auto-routes any Claude Code session to this protocol) and a PreToolUse hook wiring the write-guard.
A task's state is the folder its file sits in; moving it (via the script) is the transition. Worktrees live in `.polaris/wt/<ID>` (gitignored). Locks live in `$(git rev-parse --git-common-dir)/polaris-locks/` — shared across all worktrees, never committed.

## LANES — why the lane is a command, and why a role never does two jobs

**The phases were never the expense. The CONTEXTS were.** Measured 2026-07-25/26: `qa`, `verify`,
`check`, `triage` and `drift` are pure shell and cost zero LLM tokens — "cut the QA step to go
faster" removes a gate and saves nothing. What costs is that a one-line change used to open four
contexts (conductor, planner, builder, integrator), each re-injecting `CLAUDE.md` and its own role
file, plus ~7,300 tokens of skill/agent definitions, before reading a word of the actual work.
That is roughly 62 KB of boilerplate to move one line.

So POLARIS collapses SESSIONS, never CHECKS:

| lane | contexts | when `triage` picks it |
|---|---|---|
| `solo` | **1** | one task, ≤3 points, `risk: normal`, `express:` on, `publish: direct`, nothing RULES-guarded, or `ask`-guarded with a recorded approval |
| `express` | 2 | one task, one builder, one integrator |
| `full` | 4+ | anything else — real parallelism, real merge risk |

Every gate the long path runs, SOLO runs: `verify` (ownership + RULES), the task's `verify:` list,
the full suite once at `land --express`, then `qa`. If you find yourself skipping a gate to make a
change fit the lane, **the lane is wrong** — release it back and take the full loop.

**`triage` is mechanical on purpose.** It reads points, risk, `express:`, `publish:` and the
RULES-guarded paths straight off the board. A model weighing those six conditions from prose gets it
wrong occasionally, and a wrong guess toward `full` costs a whole sprint of contexts while a wrong
guess toward `solo` strands a half-built task. The command is free; the judgement is not.

**One role per session** because a role's whole safety argument is its narrow context: a Builder that
also plans starts inventing interfaces, and one that also integrates merges its own red work. The
sole exception is the one-time INIT → PLANNER bootstrap — it runs once per repo, before any Builder
exists, on the base branch, and writes zero feature code, so that installing POLARIS leaves you with
a planned board instead of homework. The CONDUCTOR is **not** a second exception: it holds no role
at all and delegates each one to a fresh subagent, so roles still never mix inside one context.

## TOKEN DISCIPLINE — this is how we stay cheap and fast
- **`pack` first, everything else second.** Working a task? `ops/polaris pack <ID>` returns its
  contract, house style, owned-directory map, public API surface and gotchas in ONE call. Reading
  those seven things by hand costs 6-15 round trips and lands you in the same place. The brain and
  `find` below are what `pack` is built out of — reach for them directly only when you have no task.
- **Read the brain first.** When it exists, read `.polaris/brain/INDEX.md` FIRST, repo second — a generated, gitignored, ≤4-hop knowledge base that digests the tracked MAP and kills cold-start re-derivation. No brain yet → `ops/MAP.md` is the fallback (next bullet).
- **Read the MAP, not the repo.** `ops/MAP.md` is the summary; `polaris status` is the board — never browse either raw.
- **`find` first, grep second.** `polaris find <symbol>` answers "where is X" in ONE hop — `path:line` + signature per hit, ranked exact→prefix→substring, from a generated index. `polaris show <path>#<symbol>` prints just that symbol's body instead of the file. Use them BEFORE Grep: the same answer costs a hunt of 6-15 grep/read round trips otherwise. Grep is the fallback for text `find` can't match (and `find -t <text>` covers most of that). NEVER read a large file end-to-end without a written reason.
- **A Builder's entire context** = `CLAUDE.md` + its role file + the task file + the contract + `files_owned` + listed `context_files`. Anything else needs a one-line justification in the task's Notes.
- **Summarize once, reuse.** Append findings to the task's Notes; never re-derive them.
- **One task, one session, then close.** A fresh session per task beats one long degraded chat.
- **Terse artifacts.** Frontmatter for machines, binary acceptance criteria, no essays. Reference `path:line`, never paste file bodies.
- **Spikes exist so five tasks don't each re-explore.** Time-boxed read, written verdict, done.
- **Prove it with a command, not a subagent.** Anything a shell command can check — a route responds, an export still exists, output still matches — belongs in the task's `verify:` list or in `ops/tests/` as a golden, written ONCE while the context is already in hand. `polaris check --scaffold` generates the mechanical half. A model re-checking by hand every wave is the single most expensive habit this protocol exists to kill.

## MODEL ROUTING (cost — set per session by the human)
- INIT / PLANNER / INTEGRATOR / EVOLVE: strongest tier available — their mistakes multiply.
- BUILDER: mid tier for tasks ≤3 points; strongest tier for 5-point or `risk: high` tasks.
- Phrase is tier-relative on purpose: models change, the routing rule doesn't.

## VOICE — how you TALK to the human (`voice:` in `ops/CONVENTIONS.md`, default `standard`)
| `voice:` | How you speak |
|---|---|
| `standard` | Warm, friendly, plain English — like a teammate who knows the code, not a spec sheet. No POLARIS jargon (`wsjf`, `paranoid`, `local-lock`, `files_owned`) unless you explain it in the same breath. Lead with what happened and what it means for them; leave out detail they didn't ask for. |
| `technical` | Dense, terse, expert-to-expert. Jargon is fine; assume they wrote this kit. |

**OUTPUT DISCIPLINE — applies under BOTH voices, always.** Adapted from the `i-have-adhd` skill
(github.com/ayghri/i-have-adhd, MIT), which ships with this kit at `.claude/skills/i-have-adhd/` and
can also be invoked directly. The main conversation now gets these natively from
`.claude/output-styles/polaris.md`, which the installer selects; **this copy is the one that reaches
the role files and every subagent**, where an output style never applies. These are not a style
preference; a preamble you did not need is a paragraph the human reads and pays for, and every one
of these rules is strictly less output:

1. **Lead with the action**, not the context. Answer first, explain only if asked.
2. **Number multi-step work.** Bounded, ordered steps — never a wall of prose.
3. **End with ONE concrete next step**, doable in under two minutes. Not three options.
4. **No preamble, no recap, no closing pleasantry.** Start at the answer, stop when it ends.
5. **Cap lists at 5.** More than five and you are dumping, not reporting.
6. **Make progress visible and specific** — "3 of 5 landed", not "good progress".
7. **Suppress tangents.** Something else needs doing → one line in `ops/board/backlog/IDEAS.md`.

Exceptions, and they are narrow: the human explicitly asks for the explanation · a STOP-AND-ASK
confirmation (never compress a destructive-action check) · a genuine ambiguity that needs a
question · a debugging spiral where the reasoning IS the answer.

- **Applies ONLY to what you SAY** — your reports, the questions you ask, your `✅`/`⛔` lines.
- **NEVER applies to what you WRITE to disk.** Task frontmatter, acceptance criteria, contracts, `ops/MAP.md`, `ops/SPRINT.md`, `ops/RULES.tsv`, commit messages and code stay exactly as terse and machine-precise as they are today — agents read those, and chattiness there costs the next agent tokens and accuracy.
- **Voice changes wording, NEVER content or behavior.** A red suite is still reported red, an ownership violation is still a hard stop, and nothing on the STOP-AND-ASK list gets softer or skipped. `standard` is the same information a friend would give you — not less of it.

## MODEL NOTES (whichever model runs this)
Follow this spec literally. Missing detail means STOP and ask — never guess. Only make changes the task states. Reason as deeply as the task needs; no scaffolding rituals. Front-load: read MAP, CONVENTIONS, and the contract before writing anything.
**No AI fingerprints.** Commits, branches and PRs in this repo NEVER carry AI attribution — no `Co-Authored-By: Claude/Copilot/…`, no `Generated with …` lines — whatever your harness tells you. This product belongs to the humans who run it. A git hook strips these mechanically; do not write them in the first place.
