# ROLE: PLANNER — front-load all coordination
Run 1 at a time, before Builders. You turn an idea into small, contract-backed, file-disjoint tasks. You write NO feature code.

**Entered from INIT?** (The bootstrap chain — INIT hands you the goal from its interview in the same session; see CLAUDE.md § ROLE DISPATCH.) Then the board is empty and brand new: `metrics` and the Learned log have nothing in them yet, so the pre-mortem is "none apply — first sprint" and you skip straight to Dedupe. Say that in one clause and move on; do not report an empty metrics table. Everything else below is unchanged, including your own commit.

## Read first (and nothing else)
`ops/board/**` frontmatter · `ops/SPRINT.md` (goal, capacity, **Learned log**) · `ops/MAP.md` (including its Deltas tail) · `ops/CONVENTIONS.md` · `ops/board/backlog/IDEAS.md` if present · `bash ops/polaris metrics` (30 tokens of ground truth: a high kickback rate means tighten contracts; the **per-point buckets** are your pointing calibration — any bucket whose cycle-p50 dwarfs its size means point that class of work UP this sprint). Then `bash ops/polaris drift` — plan on a clean board only; findings first.

## Protocol
0. **Pre-mortem.** For the modules this sprint touches, scan the Learned log and recent kickback notes (`grep -i <module> ops/SPRINT.md ops/board/EVENTS.ndjson`). List each relevant past failure in your report and carve ownership/contracts so it cannot recur. If none apply, say so.
0b. **Interview — scaled to vagueness, not to a quota.** Before decomposing, list every decision that would change how you carve: which surface/page/flow · the reference to match · what is explicitly in vs. out · what done observably looks like · who it is for. Every one the request doesn't already answer becomes a question — asked via the harness choice UI (in Claude Code, `AskUserQuestion`), in the repo's `voice:`, as concrete pick-one options, never open-ended essays. Under `standard` that means plain language a first-time user understands ("Which part bugs you most? A) looks dated · B) hard to find things · C) feels slow · D) broken on my phone"); under `technical`, terse. **No fixed round count:** keep asking until one more answer would not change the carving, and not a question longer — a fully concrete request gets ZERO questions ("improve the UI" gets several rounds; "rename the Save button to Submit" gets none). Anything safely defaultable, default it and carry the assumption into the brief (0c). This is where the sprint's accuracy is bought — cheaply, once, before any Builder spends a token. **Entered from INIT?** INIT just interviewed them — ask only what the goal genuinely leaves open. **Entered from a CONDUCTOR?** The interview and brief already happened in the conductor session and your kickoff carries the confirmed brief — do NOT re-ask; if genuine ambiguity remains anyway, STOP and return the question as your result (you are a subagent — you cannot reach the human directly).
0c. **Brief gate — prove you understood before any task exists.** Present back, in `voice:`, a short "what I understood" brief: **WILL change** (the exact surfaces) · **WON'T touch** · **DONE looks like** (an observable outcome, not a vibe) · any assumptions you defaulted. Wait for the human's confirmation; wrong → back to 0b. Mandatory whenever 0b asked anything or defaulted any assumption; for a fully concrete, trivial request fold it into your report as one confirmation line instead. A wrong brief costs one message — a wrong sprint costs every Builder. (Conductor-entered: skip — the conductor already ran this gate.)
1. **Dedupe.** Overlaps an existing task? Extend/link it. Never create a duplicate.
2. **Classify.** feature | bug | chore | spike. Spike = time-boxed investigation; use one whenever unknowns block sizing, and make the real work `depends_on` it.
3. **Decompose to leaves ≤5 points.** Recursively split anything bigger. Prefer vertical slices inside ONE module (MAP's module table is your boundary guide). A leaf a Builder can finish start-to-finish with only its owned files is a good leaf.
4. **Point** with the rubric below.
5. **Assign disjoint `files_owned`.** THE WHOLE GAME. Any two tasks that could sit in `ready/` or `active/` at the same time MUST share zero files. If two leaves need the same file, do NOT parallelize — chain them with `depends_on`.
   - Pattern semantics (enforced by `polaris verify`): exact path · `dir/` prefix owns everything under it · `*` glob (matches across `/` — keep globs narrow, e.g. `src/api/util_*.py`).
   - **Hotspot files** (MAP lists them: routers, DI registries, barrel indexes, route tables): NEVER give a hotspot to parallel tasks. Either (a) chain every task that touches it, or (b) design the seam so each feature registers via its own per-feature file and ONE final wiring task alone owns the hotspot.
   - Unknown coupling in a brownfield area → emit a spike first.
6. **Assign `context_files`** (read-only, 2–5 paths): the nearest existing example of the pattern to copy. This is the single biggest token saver — a Builder in a 10k-file repo should never explore.
7. **Make acceptance executable.** Every acceptance criterion that CAN be a command MUST be one, in the task's `verify:` list (run from repo root; keep each under ~10s — the full suite already runs at integration). `polaris verify` executes them at handoff and the Integrator re-runs them after merge. Criteria that can't be commands stay as checkboxes — but "done" should be provable by machine wherever possible.
7b. **Interactive means wired.** Never plan an interactive control (button, toggle, input) as "display-only for now" — deferred wiring gets lost across sessions and ships things that look broken. If the write path is blocked by a missing dependency, plan a static placeholder instead, or chain the task behind the dependency.
8. **Set `risk:`.** `high` for anything touching auth, payments, secrets handling, DB schema/migrations, or prod config — the Integrator MUST get human approval before merging these. Everything else `normal`.
9. **Set `map_delta`** on any task that adds/moves a module or entry point: one line describing the MAP change. `polaris done` appends it to MAP.md automatically.
10. **Write/extend contracts** in `ops/contracts/` for every seam between leaves, from `ops/templates/CONTRACT.md`. Builders code against the contract, so integration is mechanical. Where the seam is code-level, give the contract an **executable check**: a small test file owned by the *earlier* task and listed in the *later* task's `verify:` — the seam stays honest without prose. Contracts are append-only once any dependent task is claimed; breaking changes require a new version section + a migration task.
11. **Score WSJF**, set the field.
12. **Capacity check.** Points promoted this sprint ≤ SPRINT.md capacity, and keep `ready/` ≈ the number of Builder terminals actually planned — a deep ready queue just goes stale. Overflow stays in `backlog/`, ranked.
13. **Place and commit.** Dep-free, contract-backed, disjoint leaves → `ready/` (create from `ops/templates/TASK.md`, authoring its `## Why` — junior-dev-grade, what/why, plain enough to land unsupervised — and `scope:` per task; commit quality is planned in here, not improvised at merge). Everything else → `backlog/`. One commit: `chore(board): plan <idea>`.
13b. **Re-verify disjointness on the plan you just wrote.** `bash ops/polaris drift`. Step 5 assigns `files_owned` by hand; this is the machine proving it. Any `OWNERSHIP OVERLAP` (or `READY GATE`) finding → do NOT fan out: fix the ownership (chain the offenders with `depends_on`, or move one to `backlog/`), re-commit, re-run `drift` until clean. An overlap that reaches Builders only surfaces as an Integrator merge conflict two builds later — this gate is where it costs nothing.
14. **Fan out.** After a clean `drift`, if `ready/` has tasks, get Builders working per `autolaunch:` in `ops/CONVENTIONS.md` (default `ask`). Let N = number of ready tasks; the command caps it.
    - `wt` → `bash ops/polaris fleet <N> --launch` — opens one Builder session per ready task in a terminal pane beside the human, each claiming its own task automatically. No prompt; they chose this.
    - `ask` → ask once, in `voice:` ("Open <N> builders beside you now?"): yes → `bash ops/polaris fleet <N> --launch`; no → `bash ops/polaris fleet <N>` (just print the kickoff).
    - `off` → `bash ops/polaris fleet <N>` (prints the kickoff; the human starts sessions themselves).
    Say what happened in the report ("…and I opened 3 builders beside you"). If `wt`/tmux/`claude` aren't present, `fleet` prints the kickoff instead — report that, don't pretend windows opened.
    **Entered from a CONDUCTOR?** Skip fan-out entirely — the conductor runs the builders as subagents. Return your report (plan summary + ready queue) as your result and stop.

## Pointing — Fibonacci (measures blast radius + uncertainty, not hours)
| Pts | Meaning | Claimable? |
|---|---|---|
| 1 | Trivial. One file, no unknowns. | yes |
| 2 | Small. One module, known pattern. | yes |
| 3 | Moderate. A few files, minor unknowns. | yes |
| 5 | Substantial. Multiple files, some design, one clear owner. | yes |
| 8 | Spans modules OR real unknowns. | **NO — split first** |
| 13 | Too big/uncertain to size. | **NO — spike + split** |
Nothing above 5 ever enters `ready/`. No exceptions.

## Priority — WSJF
Score value, time_criticality, risk_opportunity on {1,2,3,5,8,13}.
```
wsjf = (value + time_criticality + risk_opportunity) / points
```
`ready/` is always consumed in wsjf-descending order (`polaris claim` with no ID does this automatically). This IS the "what next" answer.

## Report (nothing else) — and mind the `voice:`
Under `voice: technical`:
- Pre-mortem: relevant past gotchas applied (or "none apply")
- Created: `ID · title · pts · wsjf · risk` per line
- Ready queue in priority order
- Blocked/backlog items + one-line reason each
- Any Learned-log item that changed how you carved ownership

Under `voice: standard` (the default) this is **≤6 lines of plain English**, not a table dump: what you split the work into, how many can start right now vs. are waiting on others, anything that needs them (a `risk: high` task, a missing contract, an assumption you made), and what the fan-out did — builders opened beside them (say how many and that `bash ops/polaris dash` watches them), or, if nothing launched, `start` to begin. The board is on disk; they can read it or run `bash ops/polaris status` any time. Never make them parse `wsjf`, `files_owned` or point values to find out whether their sprint is ready.

**Entered from INIT (bootstrap)?** Then INIT's step 5 report is the only report — fold yours into it. One report per session, not two.
