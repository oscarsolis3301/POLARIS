# CONTRACT: model-routing            (v1 — 2026-08-03)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
`PROTOCOL.md § MODEL ROUTING` states a mechanical rule that zero code reads: nothing computes a
tier, no `model:` task field exists, and neither the CONDUCTOR's spawns nor the `fleet` pane
launcher pass a model. This contract makes routing code: ONE derivation (`tier_for`), ONE oracle
(`polaris route`), THREE mapping knobs, and the consumer rules. The core stays model-agnostic:
with the knobs unset the CLI speaks tier words only and behavior on unconfigured repos is
byte-identical to today. Tasks: T-065 (CLI) · T-066 (PROTOCOL) · T-068 (CONDUCTOR) ·
T-069 (roles/template/knobs) · T-071 (golden + drill).

## Interface — the derivation (`tier_for`, in `kit/ops/lib/core.sh`)
`tier_for <points> <risk>` echoes exactly ONE word:
- `risk` ≠ `normal` → `strong` (risk dominates points)
- points ≥ 5 → `strong`
- points ≤ 1 → `cheap`
- else → `mid`
Empty or non-numeric points → `mid` (the safe middle; never an error — callers pass frontmatter
as-is). `model_for_tier <tier>` (also core.sh) echoes the matching CONVENTIONS knob's value, or
nothing when unset. core.sh rides the write-guard's hot path — both functions stay tiny, fork-free.

## Interface — the oracle (`cmd_route`, in `kit/ops/lib/observe.sh`)
`bash ops/polaris route [<ID>] [--role <ROLE>] [--points <N>] [--risk <R>]`
- line 1: `strong` | `mid` | `cheap` — bare word, always present, machine-parseable.
- line 2, ONLY when the winning tier's knob is set: `   model: <name>` (three-space note indent,
  triage's shape). Unset knob → no second line.
- Precedence: explicit `--points`/`--risk` (pure, board-free; missing half defaults `--risk normal`,
  `--points` empty → `mid` rule above) → `--role` (table below) → `<ID>` (frontmatter `model:`
  override, else `tier_for(points, risk)`). No args at all → ⛔ one usage line, rc 1. Unknown ID →
  ⛔ rc 1.
- Role table (lives in cmd_route; this is its spec): INIT · PLANNER · INTEGRATOR · EVOLVE ·
  CONDUCTOR → `strong` · SOLO · scout → `mid` · BUILDER → per task (call route with the task's ID).
  Unknown role → `mid` + a note line, rc 0 (routing never blocks work).
- Task override `model:` (frontmatter, optional): value `strong`/`mid`/`cheap` → that tier; any
  other non-empty value is a LITERAL model name — line 1 = derived tier (informational), line 2 =
  `   model: <the literal>` verbatim, knob or no knob.
- Read-only: touches no lock, writes no board file, fires no hook — `readonly-allow.sh` may
  auto-approve it (T-067).

## Interface — CONVENTIONS mapping knobs (T-069 sets them here; every repo may)
`model_strong:` / `model_mid:` / `model_cheap:` — literal model names handed to the harness (for
the Agent tool: a `model` param value). Empty or absent = that tier stays a bare word everywhere.
THIS repo pins strong=fable · mid=opus · cheap=sonnet, with a `#` comment on the knobs recording
the owner decision (2026-08-02): fable carries planning/integration and hard tasks, opus and
sonnet carry execution, NEVER haiku here.

## Consumers (each its own task; parallel lanes agree by pinned wording, not depends_on)
- CONDUCTOR (T-068): run `route` before EVERY spawn — builders `route <ID>`, roles
  `route --role <R>` — and pass line 2's name as the Agent-tool `model` param when present; no
  line 2 → omit the param and let the platform default run.
- fleet (T-065, `cmd_fleet` + `find_claude_windows` in observe.sh): inject `--model <name>` into
  BOTH the tmux command and the wt.exe pane token list. Tier = MAX over ready tasks
  (strong > mid > cheap) because panes claim racily — any pane may end up holding any task.
  `--dry-run` previews the token. Max tier's knob unset → no token; command byte-identical to today.
- pack (T-065, `cmd_pack` in builder.sh): the task header line gains `· tier <t>`.
- The honest boundary (T-066 documents it, verbatim idea): a RUNNING session cannot switch its own
  model — routing governs what gets SPAWNED (subagents) and LAUNCHED (panes); `triage`/`status`
  merely hint.

## Surface pins — the api-kit golden (`ops/tests/api-kit.expected`)
The golden records every kit top-level fn and heading by name; ONE task per wave owns it. Wave 1's
owner is T-065. Its hand-authored delta (recipe: T-062 Notes — `POLARIS_ROOT=<worktree> python
ops/index.py`, emit the `--api 'kit/*'` shape, byte-exact, sorted position; em-dash in headings
normalizes to `-`):
- add `kit/ops/lib/core.sh	fn	tier_for` · `kit/ops/lib/core.sh	fn	model_for_tier` ·
  `kit/ops/lib/observe.sh	fn	cmd_route`
- carry T-066's heading swap (one owner per wave — the Learned-log rule):
  remove `MODEL ROUTING (cost - set per session by the human)` ·
  add `MODEL ROUTING (auto - polaris route decides)` ·
  add `LONG COMMANDS - living under the 600s tool cap`
T-065 adds NO top-level functions beyond those three. T-066 MUST use these exact heading lines
(with real em-dashes in the file): `## MODEL ROUTING (auto — polaris route decides)` and
`## LONG COMMANDS — living under the 600s tool cap`. T-067, T-068, T-069 add NO headings and NO
top-level functions — their api-kit surface is frozen this wave. (cli-help goldens do NOT move:
`cli-help.cmd` runs the INSTALLED 5.23.0 CLI and regenerates at dogfood; `cli-help-parity` counts
nine fixed daily commands.)

## Executable check
- `bash kit/ops/polaris route --points 5 --risk normal | head -1` → `strong`
- `bash kit/ops/polaris route --points 3 --risk normal | head -1` → `mid`
- `bash kit/ops/polaris route --points 1 --risk normal | head -1` → `cheap`
- `bash kit/ops/polaris route --points 2 --risk high | head -1` → `strong`
- `bash kit/ops/polaris route --role PLANNER | head -1` → `strong`
- T-071's `ops/tests/route-tier.cmd` golden runs the full battery from a FIXTURE repo with known
  knobs (hermetic by construction — this repo's future knob edits cannot red it), including the
  `   model:` note shape and the fleet `--dry-run` token.

## Invariants
- Unset knobs change NOTHING: no second line, no `--model` token, no model text in pack.
- Line 1 is always exactly one of the three tier words — consumers parse it blind.
- Routing never blocks work: malformed points/unknown role fall back to `mid` with a note, rc 0
  (only no-args and unknown-ID are errors).
- bash 3.2: the role table is a `case`, no assoc arrays; split `local` declarations.

## Example
`bash ops/polaris route T-070` → `strong` + `   model: fable` (5 pts, this repo's knobs). The
CONDUCTOR spawns that builder with model=fable. `fleet 3 --dry-run` over a ready queue whose max
tier is mid → pane tokens contain `--model opus`.

## Changelog
- v1 2026-08-03: created for T-065, T-066, T-068, T-069, T-071 (plan: routing-and-bg)
