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
Every board mechanic is ONE command. You MUST use the script instead of hand-rolling git recipes; it is race-tested. (Environment can't execute commands? Follow `ops/MANUAL.md` literally instead.) `ops/polaris help` prints every command; **`ops/PROTOCOL.md` § THE TOOL** explains what each one does and when to reach for it.

The five you will actually type, and the two that keep you cheap:
```
claim [ID]   →  build  →  verify  →  handoff          # a Builder's whole life
find <symbol>                                          # where is X — ONE hop, BEFORE any Grep
check                                                  # golden acceptance, zero tokens
```

## READ THIS WHEN YOU NEED IT — `ops/PROTOCOL.md`
The rest of the protocol lives there, so this file stays small enough to be injected into every
session and every subagent without paying for it each time: **the full command table · what lives
where on disk · TOKEN DISCIPLINE (find-first, brain-first, prove-it-with-a-command) · MODEL ROUTING ·
VOICE (how you talk to the human) · MODEL NOTES.** Open the section you need. Your role file
(`ops/roles/<ROLE>.md`) already names the commands your role runs, so most sessions need one section
or none.

## INVARIANTS — NEVER violate
1. **Ownership.** A Builder creates/edits ONLY paths in its task's `files_owned`. `context_files` and `ops/MAP.md` are read-only. Need anything else → STOP, hand back. `polaris verify` MUST pass before handoff — it mechanically proves the diff ⊆ owned AND that no `ops/RULES.tsv` rule is violated. Rules bind even inside `files_owned` and even outside Builder sessions — they are the repo's danger zones and content guards, machine-enforced. (Under Claude Code a PreToolUse guard also blocks both as writes happen; a guard rejection means hand back or ask the human, never work around it.)
2. **Ready gate.** A task enters `ready/` only if: ≤5 points, every `depends_on` is in `done/`, its contract exists, and its `files_owned` overlaps NOTHING in `ready/` or `active/`.
3. **Contract before code.** Contract missing or ambiguous → `blocked/` with a note. NEVER invent an interface.
4. **Green before `review/`.** Full test commands from CONVENTIONS green AND `polaris verify` green. Red work never leaves `active/`.
5. **One task per session.** Finish or hand back before claiming another. Sessions are disposable; the board is the memory. (One *role* per session too — the sole exception is the one-time INIT → PLANNER bootstrap chain; see ROLE DISPATCH. A CONDUCTOR session holds no role: each role runs in its own subagent.)
6. **Board mutations go through `ops/polaris`** (they commit on `refs/heads/polaris/board`, never on `<base>`). Code commits go on `feat/<ID>` in your worktree. Never mix the two.
7. **Claim = `polaris claim`.** Lock exists → task is taken → take the next one. Never edit a task you did not claim.
8. **Scope = the task.** No drive-by refactors, no extra features, no new dependencies. Want more? One line in `ops/board/backlog/IDEAS.md` for the Planner.
9. **Only the Integrator merges**, and a task with `risk: high` NEVER merges without explicit human approval in the conversation.
10. **No secrets** in the repo, board, contracts, or notes. Reference env-var names only.
11. **RULES are yours to maintain** (owner decision, 2026-07-25 — previously human-only). `ops/RULES.tsv` is policy as DATA and you may add, edit, and remove lines as the work requires. Every change carries a `#` comment above it saying WHO decided and WHY — a rule whose reason is lost gets deleted by the next agent that trips on it, and a rule deleted without a trace is indistinguishable from one that was never there. **One thing this does NOT license: deleting a rule because it blocked you.** That is the one motive the whole file exists to resist — a policy layer an agent edits its way past protects nothing. Blocked by a rule and the rule looks wrong → say so and ask; blocked and the rule looks right → hand the task back. Removing a rule is a judgement about POLICY, never a way to get unstuck. `.github/` still carries its own rule line (an agent editing the tests that gate its own work is the sharpest version of the same problem) — treat that one as needing a human's word before you touch it.

## STOP AND ASK THE HUMAN before
Deleting any file · adding a dependency · changing DB schema or migrations · editing outside `files_owned` · touching auth/payments/prod config not explicitly owned · any force-push · merging any `risk: high` task.

## PROGRESS FORMAT
After each meaningful step, output one line: `✅ <what> — <file>`. On any stop: `⛔ <why> — <what you need>`. Keep the shape; the words inside follow `voice:`.

<!-- POLARIS:END -->
