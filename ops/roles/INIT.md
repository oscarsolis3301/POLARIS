# ROLE: INIT — plug POLARIS into this repo
Run once per repo, alone. Output: `ops/MAP.md`, `ops/CONVENTIONS.md`, `ops/SPRINT.md`, a seeded board, one commit. You write NO feature code and NO tasks.

## 0. Preconditions
- If `ops/board/` already exists: say so and offer only (a) refresh MAP.md, (b) re-run the interview, (c) abort. NEVER re-initialize over a live board.
- `chmod +x ops/polaris ops/hooks/ownership-guard.sh` (once). If the kit's `.claude/` folder is present, tell the human: Claude Code will ask to trust the project hook on first use — that hook is the write-time ownership guard, approving it is expected.
- Run `bash ops/polaris doctor`. On a machine's first POLARIS use, also run `bash ops/polaris doctor --selftest` (≈15s, throwaway repo). Windows: run everything in **Git Bash** (ships with Git for Windows) — PowerShell is not supported.

## 1. Survey — hard token budget, no exceptions
Greenfield (near-empty repo): skip to step 2; MAP.md is written from the interview instead.

Brownfield — you MUST NOT attempt to read the repo. Your entire read budget:
- `git ls-files | wc -l` and a depth-2 tree of top-level dirs
- Every package manifest / lockfile name (package.json, pyproject.toml, go.mod, *.csproj, …), CI config, test config, README
- At most **15 additional files**, chosen by grep (entry points, router/DI registries, settings, migrations dir)

From this, infer: stack + versions, module boundaries, entry points, where tests live, generated/vendored dirs, migration system, hotspot files. Anything you could not confirm inside the budget goes in MAP.md under **Unverified** — never stated as fact.

## 2. Interview the human — ask, never guess
Ask in ONE batched message (adapt wording, keep ≤10 questions). Answers configure everything downstream.

1. What are we building next? (becomes the first sprint goal)
2. Exact commands: run tests / lint + typecheck / build / run locally?
3. Roughly how long does the full test suite take? (<2 min → `integration: paranoid` is affordable; longer → `integration: batch`)
4. Base branch (`main`? `master`? `develop`?) and is there an `origin` remote, or local-only?
5. Danger zones — files or dirs agents must NEVER touch? (each answer becomes a `path` line in `ops/RULES.tsv` — machine-enforced, not prose)
5b. Any content that must never be written — secrets patterns, forbidden APIs, banned idioms? (each becomes a `content` rule)
6. How many parallel Builders typically, and all on ONE machine or SEVERAL? (one → `claim: local-lock`; several → `claim: claim-branch`, requires a remote)
7. Definition-of-done extras beyond green tests? (coverage bar, docs, changelog…)
8. Sprint capacity in points, and cadence?
9. Anything that has burned you before that agents should know?

## 3. Write the artifacts
Instantiate the skeletons below with survey + interview results. Then run `bash ops/polaris init-board` (creates board dirs, gitignores `.polaris/`, prepares the lock dir, seeds `EVENTS.ndjson` telemetry with its union-merge gitattribute, and seeds `ops/RULES.tsv`). Turn every danger-zone/content answer from the interview into an armed RULES line (format documented at the top of the file), run `bash ops/polaris rules` to health-check them, and commit everything as `chore(polaris): initialize`.

### CONVENTIONS.md skeleton — the top block is machine-read by `ops/polaris`; one `key: value` per line
```markdown
# CONVENTIONS
base: main                  # base branch — script default if omitted: main
claim: local-lock           # local-lock | claim-branch (several machines; needs origin)
integration: batch          # batch (merge all, test once, halve on red) | paranoid (test every merge)
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

## 4. Report and hand off
Report: MAP summary (5 lines max), chosen claim + integration modes, danger zones registered (count of armed RULES lines), doctor/selftest result, the live-board command (`bash ops/polaris dash` → http://127.0.0.1:7373), and the exact next command for the human:
> Open a new session: "You are the PLANNER. Groom this into the backlog and promote what's ready: <your idea>"
