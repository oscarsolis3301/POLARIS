# Sprint 9 — Route and background (2026-08-03–)

## T-065 — "tier_for + `polaris route` + fleet --model + pack tier + finish bg-guard — routing becomes code"
points 5 · risk normal · landed 220de96 (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/lib/builder.sh, kit/ops/lib/core.sh, kit/ops/lib/observe.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
`PROTOCOL.md § MODEL ROUTING` already states the rule (strong models where mistakes multiply, cheap
where they don't), but it is prose: nothing computes a tier and nothing passes a model, so every
conductor spawn and every fleet pane runs on whatever the platform defaults to. This task makes the
rule executable. `tier_for <points> <risk>` and `model_for_tier <tier>` go in core.sh (tiny and
fork-free — core.sh rides the write-guard's hot path); `cmd_route` goes in observe.sh beside
`cmd_triage` and answers with a machine-parseable bare tier word, plus a `   model: <name>` note
line only when the repo's CONVENTIONS maps that tier to a real model. Three consumers wire in:
`fleet` injects `--model <name>` into both the tmux command and the wt.exe pane token list built by
`find_claude_windows` (MAX tier over ready tasks — panes claim racily, any pane may get any task;
`--dry-run` previews it), `pack`'s task header gains `· tier <t>`, and `finish` gains the bg-jobs
pending line (per `ops/contracts/bg-jobs.md` § finish — it simply never fires until T-070's bg.sh
exists, because no `.polaris/bg/` job dirs exist). Dispatch + usage entries for `route` go in
kit/ops/polaris. Everything is spec'd in `ops/contracts/model-routing.md` — code to it, invent
nothing.

This task also owns the wave's `ops/tests/api-kit.expected` delta (the surface golden — one owner
per wave, the Learned-log rule): its own three fn lines PLUS the PROTOCOL heading swap that T-066
makes in a parallel lane. Both heading texts are pinned verbatim in the contract § Surface pins, so
the two lanes agree without touching each other's files.

### Acceptance
- [ ] `tier_for` + `model_for_tier` in core.sh exactly per contract (risk≠normal → strong · ≥5 →
- [ ] `cmd_route` in observe.sh: line 1 always one bare tier word; `   model:` note ONLY when the
- [ ] `route` dispatch + usage entry in kit/ops/polaris (cli-help goldens do NOT move — they record
- [ ] fleet: `--model` in tmux AND wt.exe pane paths; max tier over ready/; `--dry-run` shows it;
- [ ] pack header carries `· tier <t>` for the packed task
- [ ] finish: pending line for any rc-less `.polaris/bg/<name>/` job dir, wording per bg-jobs.md
- [ ] api-kit.expected: hand-authored delta = `tier_for` + `model_for_tier` + `cmd_route` fn lines
- [ ] `route` stays read-only: no lock, no board write, no hook fire

## T-066 — "PROTOCOL: § MODEL ROUTING goes auto, § LONG COMMANDS teaches the measured tiers"
points 2 · risk normal · landed d1d6960 (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/PROTOCOL.md

### Why
Two doctrine gaps get closed in the file where doctrine lives. First, § MODEL ROUTING still says
model choice is "set per session by the human" — false once T-065 lands `polaris route`. Rewrite
the section body to teach the mechanical rule: derive by default (`tier_for`), override by task
`model:` field, map tiers to real names via the three CONVENTIONS knobs (unset = tier words only),
consumers (conductor route-per-spawn, fleet max-tier `--model`, pack `· tier`), and the honest
boundary — a RUNNING session cannot switch its own model; routing governs what gets SPAWNED and
LAUNCHED, `triage`/`status` merely hint. Second, the log-and-poll recipe for suite-length commands
has been folklore across three sprints and was never written down. § LONG COMMANDS writes it once,
with MEASURED numbers, per `ops/contracts/bg-jobs.md` § Doctrine: spine 144s · `test_fast` 320s ·
full serial 805s · sharded `--parallel 3` 169-330s (25 drills — fits the cap) · `qa` 1225s ·
the harness cap 600s/600000ms. Three bands: <60s plain foreground · 60s→cap foreground WITH an
explicit tool timeout ≥ the measured time · past the cap → `bg run <key>`, keep working, chunked
`bg wait`. The SUBAGENT rule (two live instances last sprint): never end a turn with your job still
running — completion notifications reach only the TOP-LEVEL session, a subagent polls inside its
turn; top-level sessions may use the harness's native run_in_background. Invariant 4 stays
absolute: `bg wait` returns 0 BEFORE handoff/land/seal/finish.

Both heading texts are pinned VERBATIM in model-routing.md § Surface pins — T-065 owns the api-kit
golden this wave and hand-authors your heading lines from that pin. Deviate by one byte and the
wave gate reds on a file you cannot legally fix.

### Acceptance
- [ ] heading swap EXACT: `## MODEL ROUTING (auto — polaris route decides)` — body rewritten per
- [ ] NEW section, heading EXACT: `## LONG COMMANDS — living under the 600s tool cap`, placed after
- [ ] the routing table row at PROTOCOL.md:14 ("which model tier a role deserves") still points to
- [ ] NO other headings added, removed, or reworded — the api-kit golden is T-065's this wave
- [ ] tier-relative phrasing survives where models are not named: knob VALUES (fable/opus/sonnet)

## T-067 — "readonly-allow arms route + bg read forms — with both-direction golden cases"
points 2 · risk normal · landed b728461 (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/hooks/readonly-allow.sh, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected

### Why
The auto-approver is what lets an agent's reads run without prompting a human, and it is deny-by-
default: any subcommand it has not proven read-only falls through to a prompt. T-065/T-070 add
commands that agents will run constantly INSIDE compound lines (`bash ops/polaris bg status x &&
…`, `route … | head -1`), where the standing settings.json allow rule cannot match. Extend
`polaris_ok` (readonly-allow.sh:206): `route` joins the plain read list (it computes from
frontmatter + CONVENTIONS, writes nothing); `bg` gets a two-arm split exactly like `slim`'s —
`status`/`tail`/`wait` return 0, EVERYTHING else (`run`, `--force`, bare `bg`, unknown words)
returns 1 and keeps its prompt, because `bg run` spawns processes and writes the registry. The
golden battery (readonly-allow.cmd/.expected) gains cases in BOTH directions — the hook's own
header says a new verb MUST arrive with its cases or it is not shipped, and the refuse cases are
the security half.

### Acceptance
- [ ] `route` allowed with any flag tail; `bg status|tail|wait` allowed with their flag tails
- [ ] `bg run` refused in ALL forms (with/without `--`, `--force`, suite keys); bare `bg` and
- [ ] golden gains ≥3 allow cases and ≥3 refuse cases covering the above, including one compound
- [ ] NO new top-level functions in the hook (extend `polaris_ok` in place — the api-kit surface
- [ ] hook stays fork-free pure bash (its speed contract: ~100ms parse, no interpreter calls)

## T-068 — "CONDUCTOR: route before every spawn; five duplicated suite blockquotes become one pointer"
points 2 · risk normal · landed 1f902ca (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/roles/CONDUCTOR.md

### Why
The CONDUCTOR is where routing becomes real: it spawns every role and every builder, so it is the
one file that must actually RUN `route` and pass the answer. Two edits, both pinned by contract.

1. Standing route-per-spawn line (model-routing.md § Consumers): before EVERY spawn, run
   `bash ops/polaris route <ID>` for a builder or `bash ops/polaris route --role <R>` for a role
   subagent; when line 2 (`   model: <name>`) is present, pass that name as the Agent-tool `model`
   param; no line 2 → omit the param. Place it once, where the spawn mechanics are described, so
   every kickoff site inherits it.
2. The identical two-line blockquote ("Foreground every command. A suite past your tool timeout
   goes to a log you POLL…") appears FIVE times — CONDUCTOR.md lines 86, 138, 175, 209, 242. Each
   becomes the ONE canonical pointer line pinned VERBATIM in bg-jobs.md § Doctrine (the
   "Long command? …" line). Five sites stay five sites — each kickoff text still carries the rule
   into the subagent it launches — but the wording collapses to a single maintained sentence that
   points at § LONG COMMANDS.

### Acceptance
- [ ] all five blockquote sites carry the canonical line EXACTLY as pinned in bg-jobs.md
- [ ] the route-per-spawn standing rule appears once, covering both `route <ID>` (builders) and
- [ ] NO headings added/removed/reworded and no top-level structure change — the api-kit golden is
- [ ] every other kickoff sentence is untouched — this task changes exactly the six things above

## T-069 — "Role pointers + INIT honesty + TASK.md model: + this repo's knobs (fable/opus/sonnet) + the report EOL pin"
points 2 · risk normal · landed 58eb983 (2026-08-03) · claimed 2026-08-03
files touched: .gitattributes, kit/ops/roles/BUILDER.md, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md, kit/ops/templates/TASK.md, ops/CONVENTIONS.md

### Why
Five small truths land together because they are all one-line docs/config edits with zero code.

1. **Role pointers.** BUILDER, SOLO, INTEGRATOR, PLANNER each gain the canonical long-command
   pointer line ONCE, verbatim from bg-jobs.md § Doctrine, placed beside each role's existing
   suite/verify instructions. One maintained sentence instead of four drifting paraphrases.
2. **INIT stops lying about the suite.** INIT.md:9 claims `doctor --selftest` takes "≈15s"; it
   takes minutes (measured 805s here). An agent that believes 15s runs it with a default 120s tool
   timeout and eats a spurious failure. Replace with honest wording + the pointer: minutes, not
   seconds — explicit generous timeout per ops/PROTOCOL.md § LONG COMMANDS.
3. **TASK.md `model:` field.** Optional frontmatter row (after `risk:`): tier word
   (`strong|mid|cheap`) or literal model name — overrides the routed tier for this task's builder;
   comment points at ops/contracts/model-routing.md. `fm_get` makes a missing key free, so old
   tasks need no stamping.
4. **This repo's knobs.** ops/CONVENTIONS.md gains the three mapping knobs with the owner decision
   recorded as comments (2026-08-02): `model_strong: fable` · `model_mid: opus` ·
   `model_cheap: sonnet` — fable carries planning/integration and hard tasks, opus/sonnet carry
   execution, NEVER haiku here; unset knobs on other repos = tier words only. Values must be exact
   knob-key lines (`^model_strong: fable` etc.) so `cfg` reads them; same-line `#` comments follow
   the file's own style.
5. **The report EOL pin** (Learned-log rider): `docs/sprints/*.md` still falls through
   `* text=auto`, so every `report` write warns about CRLF and the sprint-report contract's
   "byte-stable" claim is only literally true once pinned. One line in .gitattributes, in the
   golden-fixtures block: `docs/sprints/*.md text eol=lf`.

### Acceptance
- [ ] four role files carry the canonical pointer line byte-identical to bg-jobs.md's pin, once
- [ ] TASK.md `model:` row matches the template's comment style (aligned `#` column, two-line
- [ ] CONVENTIONS knob lines parse: `bash kit/ops/polaris route --points 5 --risk normal` on the
- [ ] NO headings added/removed/reworded in any owned file; no other CONVENTIONS value touched
- [ ] .gitattributes line sits with the other eol pins, commented like its neighbors
