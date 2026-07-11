---
name: polaris
description: POLARIS parallel-sprint protocol for this repo. TRIGGER when the user mentions POLARIS, the board, sprints, planning/claiming/building/integrating tasks, parallel builders, or names a role (INIT, PLANNER, BUILDER, INTEGRATOR, EVOLVE). DO NOT TRIGGER for ordinary single-session coding questions unrelated to the board.
---
This repo runs POLARIS. Sessions are single-role; the board (`ops/board/`) is the memory.

1. Determine the role: the user's message names it, or `ops/board/` missing → INIT, else ask in one line.
2. Read `ops/roles/<ROLE>.md` and execute it. Read nothing else beyond what it lists.
3. Every board mechanic is one command — `bash ops/polaris <cmd>` (claim · verify · handoff · release · audit · kickback · done · status · metrics · drift · rules · dash). Never hand-roll the git recipes; `ops/MANUAL.md` only if commands can't run.
4. Invariants live in `CLAUDE.md` — ownership (diff ⊆ files_owned), RULES (`ops/RULES.tsv` danger zones + content guards, binding even inside owned files), contract-before-code, green-before-review, Integrator-only merges, `risk: high` needs human approval. A PreToolUse guard enforces ownership and RULES at write time; do not fight it and never edit RULES.tsv — hand back instead.

Copy-paste kickoffs for the human: `ops/PROMPTS.md`.
