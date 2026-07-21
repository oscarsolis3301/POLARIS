# Sprint 5 — The fast lane (2026-07-20–)

## T-030 — brain command — generated .polaris/brain/ knowledge base + freshness hooks
points 5 · risk normal · landed 6c07990 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
Every subagent today re-reads the protocol and re-locates the same code from scratch — 11 subagents
burned ~1.6M heavily-duplicated tokens in one day. This task adds `polaris brain [--refresh]` to
kit/ops/polaris: it generates `.polaris/brain/` (git-ignored, any-model-readable) with INDEX.md
routing plus code-map/board/contracts/commands/gotchas digests, so a cold agent finds any fact in
≤4 file-opens instead of exploring the repo. `seal` and `done` mark the board changed, `seal`
auto-refreshes an existing brain, and `doctor` warns when the brain is stale. The contract pins the
exact layout, caps, stamp files and drill list — build precisely that, nothing more.

### Acceptance
- [ ] `polaris brain` builds all 7 files of ops/contracts/brain.md § Layout, within their line caps
- [ ] `polaris brain --refresh` rebuilds the cheap files always, code-map.md only when tracked files changed since the stamp sha; missing brain → full build
- [ ] brain writes ONLY under .polaris/brain/ (+ the two stamp files); `git status --porcelain` never shows a brain path
- [ ] `done` and `seal` touch .polaris/board-changed best-effort; seal auto-runs `brain --refresh` when .polaris/brain/ exists, and its failure never fails the seal
- [ ] `doctor` warns `brain is stale` when board-changed is newer (-nt) than .polaris/brain/.stamp; silent with no brain dir
- [ ] the 5 contract drills ride selftest(); plain `--selftest` still runs every existing drill, pass line unchanged
- [ ] `polaris help` lists brain

## T-031 — land --express — one-pass small-change landing + slow-suite hint
points 5 · risk normal · landed d415c1e (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
A 1-file 2-point request pays the same session ceremony as a 25-point sprint — that is why small
asks take hours. `land --express <ID>` collapses the integrator's long path (integrate branch →
audit+land → full suite → seal → run-verify → done → branch cleanup) into one command for the
single-task case, refusing loudly whenever the case is not single/safe (four pinned refusals in the
contract). Every gate still runs — express collapses sessions, never checks. Same task, second seam:
`qa` records how long the suite took (.polaris/last-suite-seconds) and `land` prints a one-line hint
when a paranoid-mode suite exceeds 2 minutes, making INTEGRATOR.md's batch-first rule mechanical.

### Acceptance
- [ ] `land --express <ID>` runs the contract's 5 steps and exits green on the happy path: task in done/ with a landed: stamp, sprint tag set/moved, integrate branch deleted, tree clean
- [ ] all four refusals die BEFORE any mutation, each printing its pinned fragment
- [ ] a red suite mid-express unwinds the land (reset --hard HEAD~1), kicks the task back with the failing tail, and dies
- [ ] `land <ID>` without --express is byte-identical to today
- [ ] `qa` writes .polaris/last-suite-seconds ("<seconds> <epoch>") only when ≥1 suite command ran
- [ ] `land` prints the `suite last took` hint ONLY when integration: paranoid AND stamp >120s; exit status never changes
- [ ] happy-path + 4 refusal + hint/silent drills ride selftest(); existing drills untouched
- [ ] `polaris help` shows the --express form

## T-032 — status --brief + metrics plain-English summary line
points 2 · risk normal · landed e09e4e6 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/polaris

### Why
Mid-run, a human wants one sentence — what's done, what's building, what lands next — not a column
table. `status --brief` prints exactly the contract's one-paragraph skeleton (grep-stable markers
`Last landed:` / `Next up:`), and `metrics` gains one `In plain English:` line above its existing
table, built from numbers the awk already computes. Plain `status` and the metrics table stay
byte-identical.

### Acceptance
- [ ] `status --brief` prints ONE paragraph per the contract skeleton; empty clauses dropped, no table pipes
- [ ] plain `status` output unchanged
- [ ] `metrics` first line starts `In plain English:`; EVENTS empty → existing no-telemetry note, no summary
- [ ] both drills ride selftest(); existing drills untouched
- [ ] `polaris help` shows the --brief form

## T-033 — doctor --selftest --only <pattern> — targeted drill subset
points 3 · risk normal · landed f7566f1 (2026-07-20) · claimed 2026-07-20
files touched: kit/ops/polaris

### Why
The full selftest ran ~15 times in one day (~45 min of pure re-checking) because it is the only
granularity we have. `--only <pattern>` runs the selftest's always-on spine plus just the labeled
drills matching one shell glob — the per-red re-check and express pre-flight tier. The contract pins
the spine/label split, the minimum label set, the pre-spine `unknown drill label` failure, and the
distinct `selftest passed (subset:` pass line so a subset can never impersonate the full gate.
Runs LAST in the CLI chain so it labels the brain/express/brief drills the earlier tasks added.

### Acceptance
- [ ] plain `doctor --selftest` is byte-identical in behavior: every drill runs, pass line still starts `selftest passed`
- [ ] `--only <glob>` runs spine + only matching labeled drills via a `drill_on` helper (plain case match, never inside `$(...)`)
- [ ] every label of the contract's minimum set exists, including brain · express · brief · hint from T-030..T-032
- [ ] pattern matching no label → dies BEFORE the spine, listing valid labels, message contains `unknown drill label`
- [ ] subset pass line starts `selftest passed (subset:` with pattern + counts
- [ ] two contract drills ride selftest(): nonsense pattern rc 1 · `--only fmlist` rc 0 with subset pass line

## T-034 — CONDUCTOR.md — express triage, pipelined integration, foreground gates, dead-lane recovery
points 3 · risk normal · landed c8701a7 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/roles/CONDUCTOR.md

### Why
Three sprint-4 time sinks live in the conductor's own protocol: integration waits for the slowest
lane, subagents stall on background notifications that never fire for them, and a 2-point request
pays the full pipeline. This task rewrites kit/ops/roles/CONDUCTOR.md against two contracts:
(1) express triage — the exact conditions from express-lane § Conductor triage, the verbatim
disclosure line, and an integrator kickoff that uses `land --express <ID>`; (2) pipelined
integration — spawn the integrator at FIRST handoff, landing arrivals in dependency order, plus the
verbatim foreground sentence in EVERY subagent kickoff template and the dead-lane recovery
paragraph. Kickoff templates also gain the brain-first line (read .polaris/brain/INDEX.md FIRST,
repo second — when it exists). Wording is contract-pinned so T-035 edits INTEGRATOR.md in parallel
with zero conflicts.

### Acceptance
- [ ] express triage section states ALL six conditions of express-lane § Conductor triage, the skip of scout+EVOLVE, the conductor's own final `qa`, and the verbatim disclosure line
- [ ] integrator spawn moves to FIRST handoff; the all-review `Integrate now` notice stays the last-lane signal; no gate weakened
- [ ] all five subagent kickoff templates (planner, builder, integrator, QA scout, EVOLVE) carry the verbatim foreground sentence
- [ ] snag section gains the recovery paragraph with pinned fragments `resume the same agent` and `re-anchor`
- [ ] subagent kickoff templates tell agents to read .polaris/brain/INDEX.md FIRST, repo second, falling back to ops/MAP.md when no brain exists
- [ ] no other CONDUCTOR.md semantics change (plan gate, drain, snags, cost discipline read as today)

## T-035 — role files — brain-first reads, INTEGRATOR arrival-order recipe, INIT skeleton keys
points 3 · risk normal · landed bee62c5 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/roles/BUILDER.md, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md

### Why
The brain only pays off if every role reads it first: BUILDER, PLANNER and INTEGRATOR "read first"
sections gain the pinned brain-first line (read .polaris/brain/INDEX.md FIRST, repo second — when it
exists; ops/MAP.md stays the tracked fallback). INTEGRATOR.md additionally gains the arrival-order
recipe from the pipelined-integration contract — start at first handoff, land tasks as they arrive
in review/, in dependency order, same suite/seal discipline. INIT.md's CONVENTIONS skeleton catches
up with what sprint 4/5 learned: `stale_hours: 1` (both the chosen-values prose and the skeleton
line — an hour-idle lock is a dead lane, not a slow build), a documented `express: auto` key, and a
one-line skeleton comment that `ops/polaris brain` generates the untracked .polaris/brain/ knowledge
base. Wording is contract-pinned so T-034 edits CONDUCTOR.md in parallel with zero conflicts.

### Acceptance
- [ ] BUILDER/PLANNER/INTEGRATOR read sections carry the brain-first line with MAP as the no-brain fallback
- [ ] INTEGRATOR.md describes arrival-order landing with the verbatim pinned fragment; last-lane signal and every gate unchanged
- [ ] INIT.md: both stale_hours mentions read 1, skeleton documents `express: auto | off` (default auto, unknown behaves as off), and names `polaris brain` in a comment
- [ ] no other semantics change in any of the four files

## T-036 — kit/CLAUDE.md — tool-table rows for brain/express/--brief/--only + brain-first token discipline
points 2 · risk normal · landed 6902471 (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/CLAUDE.md

### Why
kit/CLAUDE.md is every agent's first read — a command that is not in its tool table effectively does
not exist. Add the 5.15 surface: a `brain [--refresh]` row (generated knowledge base, doctor warns
when stale), `--express <ID>` on the land row (one-pass small-change landing, refusals per
contract), `--brief` on the status/metrics row, `--only <pattern>` on the doctor row. TOKEN
DISCIPLINE gains a brain-first bullet ABOVE "Read the MAP": read .polaris/brain/INDEX.md FIRST, repo
second — when it exists; the MAP stays the tracked source the brain digests. Keep every row one
line, same table voice; change nothing else.

### Acceptance
- [ ] tool table covers brain [--refresh] · land --express <ID> · status --brief · doctor --selftest --only <pattern>, each ≤1 row, semantics matching the contracts
- [ ] TOKEN DISCIPLINE opens with the brain-first bullet carrying the pinned `.polaris/brain/INDEX.md` FIRST phrase and the MAP fallback
- [ ] no other section of kit/CLAUDE.md changes

## T-037 — MANUAL.md — brain and express-lane by-hand recipes
points 2 · risk normal · landed fe81c1a (2026-07-20) · claimed 2026-07-20 → done 2026-07-20
files touched: kit/ops/MANUAL.md

### Why
MANUAL.md's promise is that every CLI behavior has a literal by-hand recipe for environments that
cannot execute the script — a recipe gap means an agent improvises. Add two sections in the existing
recipe voice: `## Brain by hand` (what `polaris brain` generates per the brain contract's layout
table — the 7 files, their sources, the stamp files, and the staleness rule doctor checks) and
`## Express lane by hand` (the express refusal checklist verbatim from the contract, then the
one-pass sequence as the existing Integrate/Land/Seal recipes already spell it: audit → land → full
suite → seal → run-verify → done — cross-reference those sections instead of duplicating their git
commands). Mirror the CLI exactly; invent nothing.

### Acceptance
- [ ] `## Brain by hand` names all 7 generated files, their sources, and the board-changed/.stamp staleness rule
- [ ] `## Express lane by hand` lists all four refusal conditions and the 5-step sequence, cross-referencing the existing Land/Seal recipes
- [ ] both sections match the contracts — no semantics invented beyond them
- [ ] no other MANUAL.md section changes
