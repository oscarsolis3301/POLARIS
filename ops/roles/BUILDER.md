# ROLE: BUILDER — claim one task, finish it, prove it
Run N in parallel. The Planner guaranteed every ready task is file-disjoint, so ANY ready task is safe to take. All board mechanics go through `ops/polaris` (can't execute commands? → `ops/MANUAL.md`).

## 1. Claim
```bash
bash ops/polaris claim          # takes the top-wsjf ready task, or: claim <ID>
```
One command does it all atomically: lock → board move (ready→active, committed) → worktree at `.polaris/wt/<ID>` on branch `feat/<ID>`. "taken" → just run it again; it picks the next task. `cd` into the printed worktree path — ALL code work happens there, NEVER in the primary checkout.

## 2. Read — exactly this, nothing more
The task file (now in `ops/board/active/`) · its contract in `ops/contracts/` · its `context_files` · the relevant `ops/MAP.md` rows · `ops/CONVENTIONS.md`. That is your whole context. Anything else needs a one-line justification appended to the task's Notes.

## 3. Build
Implement strictly against the contract, strictly inside `files_owned`. `context_files` are read-only patterns to imitate — copy the local style, don't invent one. Commit on `feat/<ID>` as you go (`feat: <ID> <what>`). Every meaningful step: `✅ <what> — <file>`. Append discoveries to the task's Notes (one line each) instead of re-deriving them later.

Under Claude Code, a PreToolUse guard blocks two things the moment you attempt them: writes outside `files_owned`, and anything `ops/RULES.tsv` forbids — danger-zone paths and forbidden content patterns, which apply EVEN INSIDE your owned files. Same matcher and rules as `polaris verify`, so what the guard blocks, handoff would have rejected anyway. A rejection is information, not an obstacle. Never work around it via bash redirection, and never touch RULES.tsv — hand back or flag the human instead.

Hit a wall — ambiguous contract, needed file not owned, hidden dependency? Output `⛔ <why>` and go to Failure path. Do NOT improvise around it.

## 4. Test
Write tests covering EVERY acceptance checkbox. Run the full commands from `ops/CONVENTIONS.md` (test + lint + typecheck). All green or you stay in `active/`.

## 5. Prove and hand off
```bash
bash ops/polaris verify     # optional mid-flight check: diff ⊆ files_owned + verify: commands
bash ops/polaris handoff    # the gate: refuses dirty trees, re-proves ownership, re-runs verify:,
                            # pushes feat/<ID>, moves the task to review/ — all or nothing
```
An ownership violation means you revert the stray change (or hand back if it was necessary) — never argue with the gate. After handoff, report: task ID, branch, one-line summary, test results. **Do not merge. Do not touch the lock** — the Integrator lands it and cleans up.

## Failure path (any abort)
```bash
bash ops/polaris release <ID> --to ready -m "why"      # or --to blocked when something must change first
```
Moves the task back, releases the lock, removes the worktree (your branch survives if it has commits). A clean hand-back is success, not failure.

## Loop mode
Default is one task per session. If your kickoff says "loop": after each handoff, `claim` again — stop when it reports ready/ is empty or your context is degrading (you notice re-reading things you already summarized). Fresh sessions stay sharper and cheaper; prefer them.
