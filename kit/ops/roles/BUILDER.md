# ROLE: BUILDER — claim one task, finish it, prove it
Run N in parallel. The Planner guaranteed every ready task is file-disjoint, so ANY ready task is safe to take. All board mechanics go through `ops/polaris` (can't execute commands? → `ops/MANUAL.md`).

## 1. Claim
```bash
bash ops/polaris claim          # takes the top-wsjf ready task, or: claim <ID>
```
One command does it all atomically: lock → board move (ready→active, committed) → worktree at `.polaris/wt/<ID>` on branch `feat/<ID>`. ALL code work happens in that worktree, NEVER in the primary checkout.

**Another chat may already hold the one you wanted, and that is a non-event, not a question:**
claim says taken → claim the next task; the lock already chose for you — re-run `bash ops/polaris claim` and build what it hands you.

**1b. Enter the worktree — a step, not a suggestion.** Claim ends by telling you to; do it before
anything else, because a session that stays put edits the checkout four other chats are using. Two
callers, and you are one of them — use the line that matches how you were started:
- **Top-level session** (a chat or a fleet pane, the human at the keyboard): `EnterWorktree({path: ".polaris/wt/<ID>"})` — no prompt: the kit's own permission rule allows it (6.2.0).
- **Pinned-cwd subagent or any other CLI:** run everything via absolute paths under .polaris/wt/<ID> (or `cd` there — a shell's cwd persists between calls). `EnterWorktree` refuses here: your cwd was fixed at launch, and the tool only accepts paths under `.claude/worktrees/`.

Which one you used is convenience; staying in the primary is what actually fails. The ownership
guard denies writes to shared source the moment any task lock exists, so "I forgot to enter" shows
up as a blocked edit, not as a merge conflict someone else pays for.

## 2. Read — ONE command, then stop
```bash
bash ops/polaris pack <ID>      # your whole context, in one call
```
That output **is** your context: the task's `## Why` and acceptance boxes, its contract verbatim, the house style this repo actually uses (detected, not guessed), the files you own versus the ones you may only read, the code-map for each owned directory, the public API surface you must not break, the traps already recorded against those exact paths, and the `verify:` commands that will be run against you.

Do not go assembling those seven things by hand — that is 6-15 tool calls to arrive where `pack` already put you, and it is the single most expensive habit this role has. Anything `pack` does not answer needs a one-line justification appended to the task's Notes.

**Then, for anything else: `find` first, never grep first.** `bash ops/polaris find <symbol>` returns `path:line` + signature in one hop; `bash ops/polaris show <path>#<symbol>` prints that symbol's body without the file around it. Grep only when `find` and `find -t <text>` both miss.

(No `pack` — an older installed kit? Fall back to the manual sequence: `.polaris/brain/INDEX.md` first, repo second, `ops/MAP.md` when no brain exists; then the task file at the primary-anchored path `claim` printed, its contract in `ops/contracts/`, its `context_files`, and `ops/CONVENTIONS.md`.)

## 3. Build
Implement strictly against the contract, strictly inside `files_owned`. `context_files` are read-only patterns to imitate — copy the local style, don't invent one. Commit on `feat/<ID>` as you go (`feat: <ID> <what>`). Every meaningful step: `✅ <what> — <file>` — the words follow the repo's `voice:`; in panes mode a human reads these live. Append discoveries to the task's Notes (one line each) instead of re-deriving them later — these lines become the squash commit's `Notes:` body verbatim at `land`, so keep each to one real discovery, no chatter; HTML comments and `⛔` lines are filtered out automatically.

Under Claude Code, a PreToolUse guard blocks two things the moment you attempt them: writes outside `files_owned`, and anything `ops/RULES.tsv` forbids — danger-zone paths and forbidden content patterns, which apply EVEN INSIDE your owned files. Same matcher and rules as `polaris verify`, so what the guard blocks, handoff would have rejected anyway. A rejection is information, not an obstacle. Never work around it via bash redirection, and never edit `ops/RULES.tsv` to get unstuck — Invariant 11 makes the rules agent-maintained, but "it blocked me" is the one motive that file exists to resist. Hand back or flag the human instead.

One rule kind reads differently: `ask` = the same denial as `path`, lifted only by a human's recorded approval on the task. A Builder never approves. Hand back — the approval is granted at the plan gate, not mid-build. If a human has already approved this, it belongs on the task: `polaris approve <ID> <scope> -m "why"` — a Builder cannot run it. (The command refuses inside a `feat/*` worktree, which is where you are.) Converting a rule between `path` and `ask` is a HUMAN decision, never an agent's.

Hit a wall? Two kinds, two responses:
- **Structural block** — a needed file isn't in `files_owned`, a hidden dependency, a missing or self-contradictory contract. Output `⛔ <why>` and go to the Failure path. Do NOT improvise around it.
- **Spec ambiguity** — a detail of *your own task* is genuinely underspecified (which of two behaviors? what wording? which edge case?) and guessing could ship the wrong thing. Ask the human **one** concise question in the repo's `voice:` (Claude Code: `AskUserQuestion`), then build on the answer. **Conductor-entered?** You are a subagent and cannot reach the human — return the question as your result instead; the conductor asks and re-dispatches. Don't guess — but don't stack up questions either: if it takes more than one or two, the task itself is underspecified, so hand it back to `blocked/` with a note for the Planner.

builder_questions in ops/CONVENTIONS.md defaults to default-safe since 6.0 (builder_questions: ask — or autonomy: standard — restores exactly the above), and default-safe narrows ONLY the spec-ambiguity path: you may default the most conventional interpretation instead of asking, ONLY when certain the choice is BOTH reversible AND low-stakes, and MUST append one Notes line: `- assumed: <choice> (default-safe)`. Not certain → ask / return the question exactly as above; a question the run cannot answer degrades to `release --to blocked` — never a stall. Structural blocks and seam/contract gaps keep the invariant-3 `blocked/` path, and `risk: high` tasks ALWAYS ask — those behaviors never change under any setting. A port in use is someone else's — take the port `pack` gave you; never reclaim a port by killing.

## 4. Test
Write tests covering EVERY acceptance checkbox. Then run the commands from `ops/CONVENTIONS.md`: **`test_fast:` if it is set, otherwise `test:`** — plus `lint:` and `typecheck:`. All green or you stay in `active/`. (`test_fast:` is the per-task gate; the full `test:` still runs at the wave gate, in the Integrator's `qa`, and in CI — you are not skipping a gate, you are not re-paying the wave's gate on every handoff. A suite over the harness's tool timeout returns NOTHING and gets re-run, which is worse than useless.)

Long command? `ops/PROTOCOL.md` § LONG COMMANDS: foreground with an explicit timeout ≥ the measured time; past the 600s cap → `bg run` + chunked `bg wait`. A subagent never ends its turn with a job still running.

**4b. See your work.** If `pack` printed a SEE YOUR WORK section and your diff touches a `visual:` path: run the printed `shot:` line (unique filename carrying your ID; the capture lock queues you — never fight it), then READ the image and put one `saw: <what the screenshot shows>` line in your handoff. A blank image is a failure. Never build your own capture tool or force opacity to fake a paint; a screenshot nobody opened proves nothing. `handoff` refuses when the capture is missing.

## 5. Prove and hand off
```bash
bash ops/polaris verify                                        # optional mid-flight check: diff ⊆ files_owned + verify: commands
bash ops/polaris bg run ship-<ID> -- bash ops/polaris handoff  # the gate + the landing tail, detached
bash ops/polaris bg wait ship-<ID> --max 300                   # collect in chunks: rc 0 green · 1 red · 2 still running → wait again · 3 unknown
```
`handoff` is still the all-or-nothing gate: it refuses dirty trees, re-proves ownership, re-runs `verify:`, pushes `feat/<ID>` under `publish: direct` (`publish: pr` keeps it local; seal pushes only `integrate/<date>`) and moves the task to `review/`. Since 6.1.0 it then keeps going by default — `landing: self` (unset composes to `self`): the same command takes the integration lease (wait-your-turn behind every other session), squashes your branch onto the wave, and when yours is the last lane out it seals the wave and finishes the landed tasks. No full suite runs here — `land` is squash + audit; the suite stays per-wave.

That tail can WAIT (a busy lease polls up to 10 minutes — deliberately exactly the harness's 600s tool cap), which is why the recipe above detaches it: `bg run ship-<ID>` + chunked `bg wait --max 300` (half the cap), repeating `bg wait` until the rc is not 2 — never a foreground wait that can cross the cap, never a background notification. Parse the rc, not the prose. A `queued:` line (rc 3) means the lane stayed busy, not broken:
integration lane busy → wait; rc 3 with a queued: line means report queued and retry at the next wave boundary

Two paths keep the classic ending, byte-for-byte: `landing: integrator` in `ops/CONVENTIONS.md`, and the hard stops no knob softens — risk: high never self-lands — a human must approve the merge; task stays in review/ (same for anything on CLAUDE.md's STOP-AND-ASK list). In those cases **do not merge, do not touch the lock** — the Integrator lands it and cleans up.

An ownership violation means you revert the stray change (or hand back if it was necessary) — never argue with the gate. After the collect, report: task ID, branch, one-line summary, test results — and whether the task landed, queued, or stays in `review/`.

**Conductor-entered? You never end the run.** Do not run `bash ops/polaris finish`, never fire
`notify-gate done`, and never open a reply with `# 🎉 Complete!` or any `🎉`. Your task going green is
a **handoff, not an ending** — even when your own tail landed and sealed it, the run is still checked,
reported and closed by the conductor that spawned you, and a
builder celebrating is how a human gets told the work is done while three lanes are still running.
Your close is the four-part report above and nothing more. (`finish` would refuse you anyway: it runs
only in the primary checkout, and your own task sitting in `review/` is itself a pending item — but
the rule is yours to keep, not the command's to enforce.) **Top-level?** The report is still your
close, then Loop mode below takes over: `finish` only when `next` says `finish`, never on your own read
of the board.

## Failure path (any abort)
```bash
bash ops/polaris release <ID> --to ready -m "why"      # or --to blocked when something must change first
```
Moves the task back, releases the lock, removes the worktree (your branch survives if it has commits). A clean hand-back is success, not failure.

## Loop mode
**This is the default now, under `handover: auto`.** After every handoff run `bash ops/polaris next` and follow its line 1 — it reads the board and names the one thing this chat does next: `build <ID>` (claim it and start over at step 1) · `integrate` · `promote` · `wait` · `stop` · `finish`. Shed the finished task's context and continue as the role it names; the hop is the next context, not a second role in this one (Invariant 5). A compaction along the way is fine — the anchor hook re-reads the board for you.

`handover: off` in `ops/CONVENTIONS.md` restores one task per session: report, and stop at the handoff. Either way, notice your own context degrading (you are re-reading things you already summarized) and hand the rest to a fresh session — sharper and cheaper.
