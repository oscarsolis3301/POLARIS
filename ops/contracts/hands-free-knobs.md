# CONTRACT: hands-free-knobs            (v1 — 2026-07-18)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
One seam for Phase 2 "Hands-Free Core" (5.13.0): the autonomy knobs, the backlog drain, the
ROADMAP read protocol, and the notify v2 env contract. Tasks T-012..T-016 all code against THIS
file. Governing invariant: **every knob unset = byte-identical to today's behavior.**

## Knobs (CONVENTIONS.md header, read via `cfg`; all optional)
```
autonomy: standard          # standard | trusted — composition macro; nothing reads it directly
plan_gate: confirm          # confirm | auto
builder_questions: ask      # ask | default-safe
evolve_apply: confirm       # confirm | auto-reversible
drain: queue                # queue | plan | backlog        (existing key, ONE new value)
drain_slices: 2             # backlog mode only: max planner-promotion rounds per run
```

### Composition + precedence (normative)
- effective(knob) = explicit CONVENTIONS value if set · else the trusted-value when
  `autonomy: trusted` · else the default above.
  `autonomy: trusted` ≡ `plan_gate: auto` + `builder_questions: default-safe` +
  `evolve_apply: auto-reversible`, applied ONLY where the individual knob is unset.
  An explicitly set individual knob ALWAYS beats `autonomy`, in both directions.
- Unknown/misspelled value → behave as the default (fail closed to today) and say so once.
- `autonomy` composes ONLY those three knobs. It never touches `drain` or any other key.

### plan_gate: auto (CONDUCTOR step 3)
Same full disclosure, then proceed WITHOUT waiting ONLY when BOTH hold: no `risk: high` task in
the plan or in the disclosed drain depth · nothing on the STOP-AND-ASK list touched by any of it.
Either present → wait exactly as `confirm`. The proceed line must SAY it proceeded
("plan_gate: auto — proceeding; say stop to halt").

### builder_questions: default-safe (BUILDER §3)
Applies ONLY to spec-detail ambiguity. Structural blocks and seam/contract gaps keep the
invariant-3 `blocked/` path; `risk: high` tasks ALWAYS ask. The builder may default the most
conventional interpretation ONLY when certain the choice is BOTH reversible AND low-stakes, and
MUST append one Notes line: `- assumed: <choice> (default-safe)`. Not certain → ask (attended) /
return the question (conductor-entered); a question the run cannot answer degrades to
`release --to blocked` — never a stall.

### evolve_apply: auto-reversible (EVOLVE step 3)
EVOLVE may apply WITHOUT "approve <n>" ONLY this fixed inert allowlist:
1. Planner calibration notes (the repo's calibration home)
2. Folding `ops/MAP.md` Deltas into its sections
3. Pruning SPRINT Learned to ≤5 carry-overs
4. CONVENTIONS values `stale_hours` and `voice` — nothing else ("non-gate value" is defined as
   exactly these two; every other key executes commands, spawns sessions, or gates)
NEVER auto-applied (always the approve queue): any `ops/RULES.tsv` line · every executed-command
key (`test` `lint` `typecheck` `build` `uat` `notify` `bootstrap`) · `generated` · `autolaunch` /
`autolaunch_max` · `integration` · `builders` · `drain` / `drain_slices` · `autonomy` /
`plan_gate` / `evolve_apply` / `builder_questions`.
**No self-escalation:** EVOLVE may never set or change the autonomy dial or its components, under
any setting. Auto-applied items are still recorded in the Kit changelog and numbered in the report
as "applied (auto-reversible)" so one reply can revert them.

### drain: backlog (CONDUCTOR step 7)
`backlog` = `queue` behavior first, then loop: spawn ONE planner subagent → it promotes the next
capacity-bounded, ready-gate-passing slice from `backlog/`, restricted to tasks whose `plan:`
equals THIS run's plan id → it runs `drift` → conductor loops steps 4–6.5. Stop when:
`drain_slices` promotion rounds are spent · no this-plan backlog remains · a promotion-blocking
drift finding. Rounds count planner-promotion passes only; the original ready set and integrator
dependency-wave promotions are round 0. The plan-gate disclosure MUST enumerate the full drain
depth (every task the cap could reach) so one "go" covers all of it; beyond-cap tasks are named as
staying parked. No subagent harness → classic `start`-per-slice, exactly today.

### plan: (task frontmatter, optional)
`plan: <slug>` — set by the Planner at authoring time on every task of a conductor run (slug from
the brief, e.g. `hands-free-core`). The step-7 "this plan" test = equal `plan:` values. Tasks
without `plan:` are NEVER backlog-drained. `fm_get plan` already parses it; no CLI change.

## ROADMAP (P3)
- Home in an installed repo: `ops/ROADMAP.md` — HUMAN-authored ordered outcome lines (`- [ ]`
  boxes optional). Agents NEVER write or check off this file. Skeleton ships at
  `kit/ops/templates/ROADMAP.md` (install.sh already copies `templates/` recursively — no
  installer change).
- Read protocol: kickoff carries NO objective + `ready/` empty + `ops/ROADMAP.md` exists → the
  next unstarted line becomes the CANDIDATE objective. "Next unstarted" = first line neither
  checked off by the human nor evidenced done (SPRINT history / done tasks). It substitutes ONLY
  for the typed objective: interview 0b, brief gate 0c and the plan gate still run in full.
  Conductor on an empty board confirms first: "Next on your roadmap: <line> — plan it?".
- EVOLVE: when a roadmap exists, its report MAY end with a next-goal proposal quoting the human's
  next line VERBATIM, applied only via "approve <n>". EVOLVE never writes ROADMAP.

## notify v2 (backward-compatible superset of v1)
v1 (unchanged): CONVENTIONS `notify: <cmd>` runs in background per board event; env `POLARIS_EV`
`POLARIS_ID` `POLARIS_NOTE`; output discarded; failures ignored; can never stall the board.
v2 adds:
- `POLARIS_SEVERITY` ∈ {info, gate, done}, exported alongside. From evt(): event `blocked` → gate;
  every other board event → info. From notify-gate: kind `done` → done; all other kinds → gate.
- Distinct board event: `release --to blocked` emits ev=`blocked` (note format unchanged:
  `→ blocked: <msg>`); `--to ready` keeps ev=`release`. Every EVENTS consumer in the CLI that
  reads `release` lines (`why`, at minimum) must accept BOTH names.
- Shim: `polaris notify-gate <kind> [ID]` · kind ∈ {plan, risk, question, done}
  ```
  plan          POLARIS_EV=waiting    POLARIS_NOTE=plan-gate         SEVERITY=gate    (no ID)
  risk <ID>     POLARIS_EV=waiting    POLARIS_NOTE=risk-approval     SEVERITY=gate
  question <ID> POLARIS_EV=waiting    POLARIS_NOTE=builder-question  SEVERITY=gate
  done [ID]     POLARIS_EV=run-done   POLARIS_NOTE=run-done          SEVERITY=done
  ```
  Behavior: `cfg notify` empty → rc 0, silent. Else invoke the hook exactly as evt() does
  (background subshell, output discarded, failure ignored), rc 0. MUST NOT: call evt(), append
  EVENTS.ndjson, take the board mutex, move/edit any board file, or commit. Unknown/missing
  kind → usage error, rc≠0.
- Conductor call sites (ADDITIVE to — never a substitute for — the in-conversation gate):
  entering the plan-gate wait (`plan`) · asking risk:high approval (`risk <ID>`) · relaying a
  builder question (`question <ID>`) · after the close report (`done`).

## Executable check
Selftest drills — owned by T-013; `bash kit/ops/polaris doctor --selftest` must prove, in the
scratch repo: notify-gate with no `notify:` → rc 0 silent · with a `notify:` that logs its env to
a temp file → `waiting/gate`, `waiting/gate/<ID>` and `run-done/done` lines appear, EVENTS.ndjson
line count UNCHANGED and work tree clean (shim never writes) · `release --to blocked` appends
ev "blocked" and the hook sees SEVERITY=gate · an ordinary board event sees SEVERITY=info.
Role/docs tasks (T-012, T-014..T-016): the greps in their own `verify:` lists are their checks.

## Invariants
- Every knob unset → byte-identical current behavior; every default above = today.
- Hard gates never soften under any knob: risk:high approval, STOP-AND-ASK, RULES human-only,
  ready gate, contract-before-code, green-before-review.
- The notify path can never stall or fail a run; the board never learns whether the hook ran.
- No agent, under any knob, may set or change the autonomy dial or its components.
