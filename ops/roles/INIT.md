# ROLE: INIT — plug POLARIS into this repo, and leave them with a planned first sprint
Run once per repo. Output: `ops/MAP.md`, `ops/CONVENTIONS.md`, `ops/SPRINT.md`, armed `ops/RULES.tsv`, a seeded board, one commit — and then, in the same session, a Planner pass that fills that board (step 4). You write NO feature code. You write no tasks *as INIT*; the tasks are the Planner's, under its own rules and its own commit.

The point is that a human says "install polaris" once and ends up ready to build, without opening a second chat. Steps 1–3 are yours; step 4 hands the baton without dropping it.

## 0. Preconditions
- **Has INIT already run?** The test is `ops/CONVENTIONS.md` — INIT writes it and nothing else does. It exists → say so and offer only (a) refresh MAP.md, (b) re-run the interview, (c) abort; NEVER re-initialize over a live board. It does NOT exist → this repo has never been initialized; proceed, and do not ask. An `ops/board/` with no `ops/CONVENTIONS.md` is a bare install from an older kit, not a live board — ignore it, `init-board` in step 3 is idempotent.
- `chmod +x ops/polaris ops/hooks/ownership-guard.sh` (once). If the kit's `.claude/` folder is present, tell the human: Claude Code will ask to trust the project hook on first use — that hook is the write-time ownership guard, approving it is expected.
- Run `bash ops/polaris doctor`. On a machine's first POLARIS use, also run `bash ops/polaris doctor --selftest` (≈15s, throwaway repo). Windows: run everything in **Git Bash** (ships with Git for Windows) — PowerShell is not supported.

## 1. Survey — hard token budget, no exceptions
Greenfield (near-empty repo): skip to step 2; MAP.md is written from the interview instead.

Brownfield — you MUST NOT attempt to read the repo. Your entire read budget:
- `git ls-files | wc -l` and a depth-2 tree of top-level dirs
- Every package manifest / lockfile name (package.json, pyproject.toml, go.mod, *.csproj, …), CI config, test config, README
- At most **15 additional files**, chosen by grep (entry points, router/DI registries, settings, migrations dir)

From this, infer: stack + versions, module boundaries, entry points, where tests live, generated/vendored dirs, migration system, hotspot files. Anything you could not confirm inside the budget goes in MAP.md under **Unverified** — never stated as fact.

**Also flag, don't fix: git-tracked build output.** `git ls-files` hitting `.next/`, `dist/`, `build/`, `out/`, `*.tsbuildinfo` means a Builder who runs the build dirties hundreds of files it does not own and `polaris verify` rejects its handoff — a day-one failure in most brownfield repos. Report it in step 4 with the fix (`git rm -r --cached <dir>` + a `.gitignore` line) and let the human run it: deleting files is on the STOP-AND-ASK list.

## 2. Interview — DETECT FIRST, then ask only what the repo cannot answer

**HARD CAP: 3 interactions.** Most of what INIT used to ask is written down in the repo already.
Asking a human to recite their own `package.json` is not diligence, it is an interrogation, and it
is why installing POLARIS felt like a chore. Derive everything derivable; ask the rest; move on.

Where your harness renders choices as clickable options (Claude Code: the `AskUserQuestion` tool),
use it — it is faster and less intimidating than a wall of numbered markdown. Otherwise, a short
numbered list. Never more than 4 questions in one call.

### 2a. Interaction 1 — voice. Alone, first, before anything else.
> Before we start — how would you like me to talk to you?
> **Plain English** — friendly, no jargon. I explain as we go. *(default)*
> **Technical** — dense and terse. You know this stuff; don't pad it.

That answer is `voice:` (`standard` | `technical`) and it binds **from this moment on**, including
everything below. Ask it by itself and wait. It is one round trip and it is the difference between
a human who understands their own config and one who guessed.

### 2b. DERIVE — silently, from the survey you already did. Ask none of this.
Step 1 already read every manifest. Use it:

| Config | Where it comes from — no question needed |
|---|---|
| `test:` `lint:` `typecheck:` `build:` | `package.json` scripts · Makefile targets · `pyproject.toml` · `Cargo.toml` · `go.mod` · CI workflow |
| `base:` | `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`), else the current branch |
| origin remote? | `git remote` |
| candidate danger zones | what the survey saw: `.env*`, migrations dirs, prod config, lockfiles, generated/vendored dirs |
| `stale_hours:` `uat:` `notify:` | defaults; EVOLVE tunes them later from real data |

Anything you genuinely cannot find, leave blank and say so in 2c — do not invent a command.

### 2c. Interactions 2 and 3 — the only things a repo cannot tell you
**Interaction 2 — the goal.** Plain prose, free text, on its own:
> What do you want to build first?

It becomes the sprint goal AND the Planner's input in step 4. Take it in their words; do not make
them phrase it as a ticket.

**Interaction 3 — one batched call, ≤4 questions, IN THEIR VOICE.** Under `voice: standard` you
MUST translate — never make a human choose between `paranoid` and `batch`:

1. **Confirm what you found.** Show it compactly and let them correct it in one move:
   *"Tests: `pnpm test` · Build: `pnpm build` · Branch: `main`"* → **Looks right** | **Let me fix those**
2. **`claim:`** — *"Will you run agents on one computer, or several?"* → one → `local-lock` ·
   several → `claim-branch` (needs an origin remote — if there is none, say so and use `local-lock`)
3. **`integration:`** — *"After each piece of work lands, should I re-run your whole test suite, or
   wait and run it once at the end?"* → every → `paranoid` · once → `batch`
4. **Danger zones** — *"Anything I should treat as radioactive — files I must never touch?"*
   Multi-select, **pre-ticked with the candidates from 2b**, plus a free-text escape. Each answer
   becomes an armed `path` line in `ops/RULES.tsv` — machine-enforced, not prose. If they name
   forbidden *content* (secret patterns, banned APIs), that is a `content` rule.

Everything else INIT used to ask — suite duration, DoD extras, capacity, cadence, past scars — is
either derivable, defaultable, or EVOLVE's job once there is real data. Do not ask it. A human who
has just said "install polaris" does not yet know their own sprint capacity in points.

## 3. Write the artifacts — silently. No progress commentary.
Instantiate the skeletons below with survey + interview results. Then run `bash ops/polaris init-board` (creates board dirs, gitignores `.polaris/`, prepares the lock dir, seeds `EVENTS.ndjson` telemetry with its union-merge gitattribute, and seeds `ops/RULES.tsv`). Turn every danger-zone/content answer from the interview into an armed RULES line (format documented at the top of the file), run `bash ops/polaris rules` to health-check them, and commit everything as `chore(polaris): initialize`.

Values you no longer ask for, so choose them: `stale_hours: 4`; `autolaunch: ask` (safe default — offers to open Builders after planning rather than surprising a brand-new user with spawned windows); SPRINT capacity — start at **10 points** and let EVOLVE calibrate it from real cycle data; omit `uat:` and `notify:` unless the survey found an obvious end-to-end command. Do not narrate any of this. The human sees one report, in step 4, after the Planner has run.

### CONVENTIONS.md skeleton — the top block is machine-read by `ops/polaris`; one `key: value` per line
```markdown
# CONVENTIONS
base: main                  # base branch — script default if omitted: main
claim: local-lock           # local-lock | claim-branch (several machines; needs origin)
integration: batch          # batch (merge all, test once, halve on red) | paranoid (test every merge)
voice: standard             # standard (plain, friendly) | technical (dense, terse) — how agents TALK to
                            # the human. Never changes what they write to disk, or any gate. Default: standard.
autolaunch: ask             # wt (Planner opens a Builder pane per ready task beside you) | ask (offer once
                            # after planning) | off (just print the kickoff). Windows Terminal only; harmless
                            # elsewhere — falls back to printing. Default: ask.
stale_hours: 4              # sweep warns on active locks older than this
uat: <cmd or omit>          # optional end-to-end/UAT command — Integrator runs it ONCE on the integrate branch
notify: <cmd or omit>       # optional: runs in background per board event with POLARIS_EV/ID/NOTE env vars
test: <cmd>
lint: <cmd>
typecheck: <cmd>
build: <cmd>

branch format: feat/<ID> · integration branch: integrate/<date>
commit format: type(scope): message   # types: feat fix chore test docs
Definition of Done: acceptance boxes checked · tests green · lint/typecheck green · `polaris verify` green · <extras from interview>
code style: <pointers, or "match surrounding code">

## Write routing — one fact, one home (a fact in two files means one is drifting)
| Fact | Only writer | Only home |
|---|---|---|
| burndown row + Learned log | Integrator | ops/SPRINT.md |
| MAP content | Integrator (via task map_delta) | ops/MAP.md |
| conventions values + Planner calibration notes | EVOLVE (human-approved) | this file · ops/roles/PLANNER.md |
| RULES lines | human (EVOLVE proposes) | ops/RULES.tsv |
| task truth | the board scripts | ops/board/** frontmatter |
| kit code + invariants | human only | CLAUDE.md · ops/polaris · ops/dashboard.py · hooks |
```

### MAP.md skeleton (HARD CAP 200 lines — it is a map, not documentation)
```markdown
# MAP — <repo name>            (updated: <date>, by INIT)
## Stack
<lang + version, framework, DB, package manager>
## Entry points
<path — what it is>
## Modules
| Path | Purpose | Notes |
|---|---|---|
## Danger zones — agents NEVER edit these
<paths + why>
## Generated / vendored — never edit, never read
<paths>
## Hotspot files (conflict magnets: routers, DI registries, index barrels)
<paths — Planner must chain, never parallel-own>
## Unverified
<what INIT could not confirm within budget>
```
(A `## Deltas` tail accumulates automatically: `polaris done` appends each task's `map_delta` line so the MAP never rots. When Deltas exceed ~20 lines, fold them into the sections above.)

### SPRINT.md skeleton
```markdown
# SPRINT <n> — <goal>          capacity: <pts>   dates: <start>–<end>
## Burndown
| date | done pts | remaining |
## Learned (Integrator appends ≤3 bullets per integration; Planner reads first)
```

## 4. Chain straight into the PLANNER — same session, no restart, no handoff message
Do **not** tell them to open a new session. Read `ops/roles/PLANNER.md` and execute it now, with the goal from 2c as the idea to groom. This is the ONE sanctioned two-role session (see CLAUDE.md § ROLE DISPATCH): it runs before any Builder exists, on the base branch, and writes zero feature code. Every other session stays single-role.

The Planner's board commit is separate from yours — plan, place, commit as `chore(board): plan <goal>`, exactly as PLANNER.md says.

## 5. ONE report, at the very end, in the voice they chose in 2a
The human has now waited through an install, an interview and a planning pass. They get **one** report, and under `voice: standard` it is **≤8 lines**. Not a walkthrough. Not a tour of what POLARIS is.

Say only:
- that it worked, and what you're building (their words, not yours);
- how the work got split — *"I split X into 6 pieces; 4 can start now, 2 are chained behind them"*;
- **anything that needs them**: git-tracked build output (step 1), a `risk: high` task, a command you couldn't find, a danger zone you guessed at. This is the one thing you must never trim.
- how to start: *"Open a terminal here and say **start** — I'll pick up the top task and build it."*
- how to watch: `bash ops/polaris dash` → http://127.0.0.1:7373

Do NOT list every task, print the board, explain `wsjf`/`files_owned`/worktrees, recap the config you just wrote, or describe the write-guard. It is all on disk and they can ask. Under `voice: technical`, be dense and drop the explanations — but the warnings stay.
