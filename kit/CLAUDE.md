# POLARIS v5 — Parallel Sprint Protocol

Model-agnostic operating system for running N coding agents in parallel on this repo with zero merge
conflicts. This file is small on purpose — the harness injects it into EVERY session and EVERY
subagent, so every byte here is paid 6-8 times a run. It routes you to your role and nothing else.

## ROLE DISPATCH — do this first
Your kickoff names your role. Read `ops/roles/<ROLE>.md` and execute it. Nothing else.

| Kickoff says | Read | Sessions |
|---|---|---|
| **`start`** · `start building` · `go` · `let's build` · `polaris start` | **run `bash ops/polaris triage` — line 1 names your lane** (below) | per lane |
| "You are INIT" | `ops/roles/INIT.md` | 1, once per repo |
| "You are the PLANNER" | `ops/roles/PLANNER.md` | 1 at a time |
| "You are SOLO" | `ops/roles/SOLO.md` | 1 — one small change, start to merged, no subagents |
| "You are a BUILDER" | `ops/roles/BUILDER.md` | N in parallel |
| "You are the INTEGRATOR" | `ops/roles/INTEGRATOR.md` | 1 at a time |
| "You are the CONDUCTOR" | `ops/roles/CONDUCTOR.md` | 1 — runs the whole loop via role subagents |
| "You are EVOLVE" | `ops/roles/EVOLVE.md` | 1, between sprints |

**`triage` decides the lane — you never weigh it by hand.** It reads points, risk, `express:`,
`publish:` and the RULES-guarded paths straight off the board and prints one word:

| line 1 | you are | why |
|---|---|---|
| `solo` | `ops/roles/SOLO.md` | one context does the whole path. **This is the common case** |
| `express` | CONDUCTOR, express path | one builder, one integrator |
| `full` | `ops/roles/CONDUCTOR.md` (no subagent tool → `PLANNER.md`) | the full loop |

- **`start` is the everyday kickoff.** It means "take the next piece of work". Empty board → the
  triage answer routes you to PLANNER instead of erroring.
- **Scope guard:** `start` fires only when the message *is* a start phrase. "start the dev server",
  "go fix the header" name an object — they are ordinary requests, not kickoffs.
- **Unprompted work request → run `triage`, same as `start`.** No role named, not a start phrase,
  but the message asks to *change the product* (add / build / create / implement / improve /
  redesign / refactor / fix / remove) → author the task if none exists, then let `triage` pick the
  lane. **Never guess SOLO-vs-CONDUCTOR from the prose** — guessing wrong costs a whole sprint, and
  the command is free. Describe what you want and POLARIS routes it; no "which role?" detour.
- **Guard:** a question about existing code ("what/why/how does X work", "where is…"), an
  operational command ("run the tests", "deploy"), or POLARIS meta ("update POLARIS", "status") is
  NOT a work request — handle it normally. The discriminant is intent to *change* the repo vs.
  intent to *understand or operate* it. Genuinely unclear → ask in one line.
- No role given and `ops/CONVENTIONS.md` does NOT exist → INIT has never run → you are INIT.
  That file is the ONLY "has INIT run?" test; an `ops/board/` from an older installer proves nothing.
- **NEVER act as two roles in one session.** Sole exception: the one-time INIT → PLANNER bootstrap.
  The CONDUCTOR is not a second exception — it holds NO role and delegates each to a fresh subagent.
  (Why, and the SOLO cost argument: `ops/PROTOCOL.md` § LANES.)

## THE ONE IDEA
All coordination is front-loaded into the Planner. Every task gets a **disjoint set of files it may
edit** (`files_owned`). No two claimable tasks ever share a file, so Builders run fully parallel with
nothing to negotiate and merges are mechanical. The only runtime race — two Builders grabbing one
task — is broken by an atomic lock. Plan once, fan out. Do NOT rely on runtime self-organization.

## THE TOOL — `ops/polaris`
Every board mechanic is ONE command. Use the script instead of hand-rolling git recipes; it is
race-tested. (Cannot execute commands? Follow `ops/MANUAL.md` literally.) `ops/polaris help` prints
every command; **`ops/PROTOCOL.md` § THE TOOL** explains when to reach for each.

```
claim [ID]  →  build  →  verify  →  handoff     # a Builder's whole life
pack <ID>                                        # your whole context, ONE call — run it FIRST
find <symbol>                                    # where is X — one hop, BEFORE any Grep
check                                            # golden acceptance, zero tokens
```

## READ THIS WHEN YOU NEED IT — `ops/PROTOCOL.md`
The rest of the protocol lives there so this file stays cheap to inject: **the full command table ·
what lives where on disk · LANES · TOKEN DISCIPLINE · MODEL ROUTING · VOICE · MODEL NOTES.** Open
the section you need. Your role file already names the commands your role runs, so most sessions
need one section or none.

## INVARIANTS — NEVER violate
1. **Ownership.** A Builder creates/edits ONLY paths in its task's `files_owned`. `context_files`
   and `ops/MAP.md` are read-only. Need anything else → STOP, hand back. `polaris verify` MUST pass
   before handoff: it proves the diff ⊆ owned AND that no `ops/RULES.tsv` rule is violated. Rules
   bind inside `files_owned` too, and outside Builder sessions. A guard rejection means hand back or
   ask the human — never work around it.
2. **Ready gate.** A task enters `ready/` only if: ≤5 points, every `depends_on` is in `done/`, its
   contract exists, and its `files_owned` overlaps NOTHING in `ready/` or `active/`.
3. **Contract before code.** Contract missing or ambiguous → `blocked/` with a note. NEVER invent an
   interface.
4. **Green before `review/`.** Test commands from CONVENTIONS green AND `polaris verify` green. Red
   work never leaves `active/`.
5. **One task per session, one role per session.** Finish or hand back before claiming another.
   Sessions are disposable; the board is the memory.
6. **Board mutations go through `ops/polaris`** (they commit on `refs/heads/polaris/board`, never on
   `<base>`). Code commits go on `feat/<ID>` in your worktree. Never mix the two.
7. **Claim = `polaris claim`.** Lock exists → task is taken → take the next one. Never edit a task
   you did not claim.
8. **Scope = the task.** No drive-by refactors, no extra features, no new dependencies. Want more?
   One line in `ops/board/backlog/IDEAS.md` for the Planner.
9. **Only the Integrator merges**, and `risk: high` NEVER merges without explicit human approval in
   the conversation.
10. **No secrets** in the repo, board, contracts, or notes. Reference env-var names only.
11. **RULES are yours to maintain** (owner decision, 2026-07-25). `ops/RULES.tsv` is policy as DATA:
    add, edit and remove lines as the work requires, each change carrying a `#` comment naming WHO
    decided and WHY. Three kinds: `path` and `content` deny outright;
    `ask` = the same denial as `path`, lifted only by a human's recorded approval on the task
    — you never run `approve` yourself, so an `ask` denial means hand back for the human's yes.
    **One thing this does NOT license: deleting a rule because it blocked you** —
    that is the one motive the file exists to resist. Blocked and the rule looks wrong → say so and
    ask; blocked and it looks right → hand the task back. `.github/` needs a human's word before you
    touch it: an agent editing the tests that gate its own work is the sharpest version of the same
    problem. **Converting a rule between `path` and `ask` is a HUMAN decision** for that same reason.

## STOP AND ASK THE HUMAN before
Deleting any file · adding a dependency · changing DB schema or migrations · editing outside
`files_owned` · touching auth/payments/prod config not explicitly owned · any force-push · merging
any `risk: high` task · converting a `RULES.tsv` rule between `path` and `ask`.

## PROGRESS FORMAT
After each meaningful step, one line: `✅ <what> — <file>`. On any stop: `⛔ <why> — <what you need>`.
Keep the shape; the words inside follow `voice:`.
Changed the repo? `bash ops/polaris finish` is your LAST command; exit 0 licenses `# 🎉 Complete!`,
nothing else does. Shape: `.claude/output-styles/polaris.md`.
**A subagent never ends a run** — no `finish`, no `notify-gate done`, no H1. Your close is your report.
