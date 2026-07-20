# Sprint 5 — The fast lane (2026-07-20–)

## T-030 — brain command — generated .polaris/brain/ knowledge base + freshness hooks
points 5 · risk normal · landed 6c07990 (2026-07-20) · claimed 2026-07-20
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

## T-034 — CONDUCTOR.md — express triage, pipelined integration, foreground gates, dead-lane recovery
points 3 · risk normal · landed c8701a7 (2026-07-20) · claimed 2026-07-20
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
points 3 · risk normal · landed bee62c5 (2026-07-20) · claimed 2026-07-20
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
points 2 · risk normal · landed 6902471 (2026-07-20) · claimed 2026-07-20
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
points 2 · risk normal · landed fe81c1a (2026-07-20) · claimed 2026-07-20
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
