---
name: polaris
description: POLARIS parallel-sprint protocol for this repo. TRIGGER when the user says "start", "start building", "go", "let's build" or "polaris start" on its own; when they mention POLARIS, the board, sprints, planning/claiming/building/integrating tasks, or parallel builders; or when they name a role (INIT, PLANNER, BUILDER, INTEGRATOR, EVOLVE). DO NOT TRIGGER for ordinary single-session coding questions unrelated to the board, or when a start-like word is attached to something else ("start the dev server", "go fix the header") — that is a normal request, not a kickoff.
---
This repo runs POLARIS. Sessions are single-role; the board (`ops/board/`) is the memory.

1. **Determine the role.**
   - The message names it → that role.
   - The message **is** a bare start phrase (`start`, `start building`, `go`, `let's build`, `polaris start`) → tasks in `ops/board/ready/` → **BUILDER**; `ready/` empty → **PLANNER** (ask what to build). This is the everyday kickoff: nobody should have to type a role name to do the obvious thing. But a start word with an object attached ("start the dev server") is an ordinary request — not a kickoff.
   - `ops/CONVENTIONS.md` missing → **INIT** (it is written by INIT and nothing else, so its absence means INIT never ran — an empty `ops/board/` from an older installer proves nothing). INIT chains into PLANNER in the same session; that is the one sanctioned two-role session.
   - Otherwise ask in one line.
2. Read `ops/roles/<ROLE>.md` and execute it. Read nothing else beyond what it lists.
3. Every board mechanic is one command — `bash ops/polaris <cmd>` (claim · verify · handoff · release · audit · kickback · done · status · metrics · drift · rules · dash). Never hand-roll the git recipes; `ops/MANUAL.md` only if commands can't run.
4. Invariants live in `CLAUDE.md` — ownership (diff ⊆ files_owned), RULES (`ops/RULES.tsv` danger zones + content guards, binding even inside owned files), contract-before-code, green-before-review, Integrator-only merges, `risk: high` needs human approval. A PreToolUse guard enforces ownership and RULES at write time; do not fight it and never edit RULES.tsv — hand back instead.
5. Talk to the human in the repo's `voice:` (`ops/CONVENTIONS.md`, default `standard` = plain and friendly). It governs what you SAY, never what you write to the board and never a gate — see CLAUDE.md § VOICE.

Copy-paste kickoffs for the human: `ops/PROMPTS.md`.
