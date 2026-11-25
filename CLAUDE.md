<!-- POLARIS:BEGIN — managed block, replaced by `ops/polaris update`. Put your own rules BELOW the END marker. [kit 6.22.0] -->
# POLARIS v5 — Parallel Sprint Protocol

N coding agents, one repo, zero merge conflicts.

## ROLE DISPATCH — do this first
Your kickoff names your role. Run `bash ops/polaris role <ROLE>` and execute it. Nothing else.

| Kickoff says | Run | Sessions |
|---|---|---|
| **`start`** · `start building` · `go` · `let's build` · `polaris start` | **`bash ops/polaris triage` — line 1 names your lane** (below) | per lane |
| your plan was just approved (plan mode, `plan_gate`, or a typed yes) | `role CONDUCTOR` in THIS chat — no subagent tool → `role PLANNER`, then the handover loop | 1 |
| "You are INIT" | `role INIT` | 1, once per repo |
| "You are the PLANNER" | `role PLANNER` | 1 at a time |
| "You are SOLO" | `role SOLO` | 1 — one small change, start to merged, no subagents |
| "You are a BUILDER" | `role BUILDER` | N in parallel |
| "You are the INTEGRATOR" | `role INTEGRATOR` | 1 at a time |
| "You are the CONDUCTOR" | `role CONDUCTOR` | 1 — runs the whole loop via role subagents |
| "You are EVOLVE" | `role EVOLVE` | 1, between sprints |

**`triage` decides the lane — you never weigh it by hand.** It reads points, risk, `express:` and
RULES-guarded paths off the board; line 1 is one word:

| line 1 | you are | why |
|---|---|---|
| `solo` | `role SOLO` | one context does the whole path. **This is the common case** |
| `express` | CONDUCTOR, express path | one builder, one integrator |
| `full` | `role CONDUCTOR` (no subagent tool → `role PLANNER`) | the full loop |
| `tidy` | `role TIDY` | tune-up due — fold chains, layout pass, settings; one context, no subagents |

- **`start` is the everyday kickoff** (next piece of work; empty board → PLANNER). **An approved
  plan is a kickoff, not a report** — the go for the whole run, in this chat. **Scope guard:** `start`
  fires only when the message *is* a start phrase ("go fix the header" is not).
- **Unprompted work request → always author its own task, then `triage <ID>`** (a `plan:` slug),
  claim that ID — never a ready task because it sits there. **Never guess SOLO-vs-CONDUCTOR.**
- **Guard:** a code question, an operational command or POLARIS meta is NOT a work request; unclear →
  ask in one line. **"Use REA to…"** → skill `reverse-engineer-anything` first. No role and no
  `ops/CONVENTIONS.md` → you are INIT (the ONLY "has INIT run?" test).
- **NEVER act as two roles inside one CONTEXT.** A board-proven hop is the next context (Invariant
  5); sole exception INIT → PLANNER; the CONDUCTOR holds NO role. In full: `bash ops/polaris doc PROTOCOL "LANES"`.

## FEWEST HOPS — the core principle
- **Fewest hops.** Builders: `pack`. Others: the root map (`## Where things live`) →
  `.polaris/brain/INDEX.md` → `<dir>/CLAUDE.md` → `find`/`show` → Grep last.
- **A layout that makes you jump is a bug.** `hops` measures it, the tidy lane fixes it — no drive-by moves.
- **Ask first, then finish.** One round of questions before work; then a safe default, or park that
  piece and finish the rest: `bash ops/polaris doc PROTOCOL "SAVE HOPS"`.

## THE ONE IDEA
All coordination is front-loaded into the Planner. Every task gets a **disjoint set of files it may
edit** (`files_owned`), so Builders run fully parallel and merges are mechanical. An atomic
lock breaks the one runtime race (two Builders, one task). Plan once, fan out.

## THE TOOL — `ops/polaris`
Every board mechanic is ONE race-tested command — never hand-roll git. No shell? Follow the kit's
MANUAL.md. `help` lists all; `bash ops/polaris doc PROTOCOL "THE TOOL"` says when.
```
claim [ID] → build → verify → handoff   # a Builder's whole life
pack <ID>      # your whole context, ONE call — run it FIRST
find <symbol>  # where is X — one hop, BEFORE any Grep
check          # golden acceptance, zero tokens
```

## READ THIS WHEN YOU NEED IT — `bash ops/polaris doc PROTOCOL`
Sections: THE TOOL · STATE = THE BOARD · LANES · N CHATS, ONE REPO · SAVE HOPS ·
TOKEN DISCIPLINE · MODEL ROUTING · LONG COMMANDS · VOICE · MODEL NOTES.

## INVARIANTS — NEVER violate
1. **Ownership.** A Builder edits ONLY its task's `files_owned` (`context_files`, `ops/MAP.md`: read-only);
   need more → STOP, hand back. `polaris verify` MUST pass before handoff: diff ⊆ owned, no `ops/RULES.tsv`
   rule broken (they bind everywhere), changed `ops/SURFACES.tsv` surfaces moved their tests.
   A guard rejection → hand back or ask, never work around it.
2. **Ready gate.** A task enters `ready/` only if: ≤5 points (a chain card: ≤13, each `steps:` ≤5), every
   `depends_on` in `done/`, its named contract exists, `files_owned` overlaps NOTHING in `ready/`/`active/`.
3. **Contract before code.** Contract missing or ambiguous → `blocked/` with a note. NEVER invent an
   interface.
4. **Green before `review/`.** The card's own `verify:` AND `polaris verify` green; the full suite runs
   once per wave, never per card. Red work never leaves `active/`.
5. **One task per context, one role per context.** Hop only at a board-proven completion event, into
   the role `polaris next` names, logged; compaction resets, the anchor hook re-enters. The board is the memory.
6. **Board mutations go through `ops/polaris`** (commits on `refs/heads/polaris/board`, never `<base>`);
   code commits on `feat/<ID>` in your worktree. Never mix the two.
7. **Claim = `polaris claim`.** Lock exists → taken → take the next. Never edit a task you did not claim.
8. **Scope = the task.** No drive-by refactors, extra features or new dependencies. Want more?
   One line in `ops/board/backlog/IDEAS.md`.
9. **Only the integration-lease holder merges.** The lease *is* the Integrator.
   `risk: high` NEVER merges without the owner's approval: a recorded yes, or the approved plan while away.
10. **No secrets** in the repo, board, contracts, or notes. Reference env-var names only.
11. **RULES are yours to maintain** (owner, 2026-07-25): edit `ops/RULES.tsv` as work requires, each
    line's `#` comment naming WHO and WHY. `path`/`content` deny; `ask` denies until a human's
    recorded approval — never run `approve` yourself. **Never delete a rule because it blocked you**
    — ask, or hand back. `.github/` needs a human's word first. **Converting a rule between `path`
    and `ask` is a HUMAN decision.** Why: `bash ops/polaris doc PROTOCOL "STATE = THE BOARD"`.

## STOP AND ASK THE HUMAN before
**Away** (`bash ops/polaris presence` says `away`): never ask — take the recommended option as an
`assumed:` line, park what has no safe default. Here, ask before:
Deleting any file (a move proven by `hops --proof` is not a delete; a merge is) · adding a dependency · changing DB schema or migrations · editing outside
`files_owned` · touching auth/payments/prod config not explicitly owned · any force-push · merging
any `risk: high` task · converting a `RULES.tsv` rule between `path` and `ask` — each unless the approved plan named it. Ask before the run, never during: the plan names it, or it parks.
**Not on it:** git/workspace mechanics are never ask material after plan approval — the CLI prints the next step; follow it.
**Never offer a menu of execution strategies** — `triage` answered it; the interview is about the PRODUCT.
Taken lock · busy lane · dirty tree → `bash ops/polaris doc PROTOCOL "N CHATS, ONE REPO"`. Real asks stay: spec ambiguity, `risk: high`, `ask` scopes.

## PROGRESS FORMAT
After each meaningful step, one line: `✅ <what> — <file>`. On any stop: `⛔ <why> — <what you need>`.
Keep the shape; words follow `voice:` (`standard`: everyday words, no git/test vocabulary).
Changed the repo? `bash ops/polaris finish` is your LAST command; exit 0 licenses `# 🎉 Complete!`,
nothing else does.
**A subagent never ends a run** — no `finish`, no `notify-gate done`, no H1. Your close is your report.
<!-- POLARIS:END -->

<!-- POLARIS:EFFICIENCY -->
## Token efficiency — the first property

Every token is the owner's money and the supply is fixed. Finish the task, prove it, spend as
little as possible.

- **Prefer ONE context over three.** Twenty-five subagents in a day is a failure, not diligence.
- **Run the smallest check that proves the change** — never a full suite for a small diff.
- **Size every helper** — pass the model and effort `route` prints on each spawn; Haiku runs only the kit's job runner, and Fable runs only when the owner picks it.
- **Long, mechanical, no judgement in it?** Run it yourself, detached: one command per line in a file, then
  `bash ops/polaris bg run <name> --steps <file>` and collect once. 🚩 only what needs a person, only while they are here.
- **Ask early** rather than burning tokens guessing.

Added by `polaris heal`. Edit freely — it is appended once and never rewritten.
