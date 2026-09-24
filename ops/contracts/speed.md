# CONTRACT: speed — Sprint 17 "Fast"            (v1 — 2026-09-24)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/v4.md` § Sprint 17 · evidence: `plans/audit-0924.md` (finding ids) · tasks T-173..T-183 (`plan: v4-fast`).

## Purpose
Make every guard, `drift`, `next` and the close cheap, and make the model ban hold even when a
guard is slow, WITHOUT moving any surface another lane or an installed repo reads.

## 1. Guard budgets — relative to the machine's floor (T-173 builds the meter, T-182 enforces it)
`bash kit/ops/bench.sh guards` (a new MODE of the existing script, not a new function) times each
hook best-of-`$RUNS` against a synthetic, side-effect-free input and prints TAB-separated lines, in
this order, and nothing else on stdout:
```
floor	<ms>                                   # bash -c true
model-guard	<ms>	<budget>	ok|OVER        # PreToolUse Read, state file present (the common path)
ownership-guard	<ms>	<budget>	ok|OVER    # non-builder Edit: cwd = primary, a path no rule scopes
checkout-guard	<ms>	<budget>	ok|OVER     # Bash `git status`
readonly-allow	<ms>	<budget>	ok|OVER     # Bash `git status`
awake-hook	<ms>	-	-                        # timed and reported, no budget yet
handover-hook	<ms>	-	-
```
| guard | budget (ms) |
|---|---|
| model-guard | floor + 300 |
| ownership-guard (non-builder) | floor + 600 |
| checkout-guard · readonly-allow | floor + 150 |

rc 1 iff any line says `OVER`, else 0. Hooks are timed from `kit/ops/hooks/` when it exists (the kit
repo), else `ops/hooks/`. Hermetic: a `mktemp -d` HOME, `POLARIS_AWAKE_HOME` pointed into it (awake-hook
must never reach the real registry or spawn the daemon), never the real `~/.claude/polaris/model-state/`.

## 2. The model ban — six veto layers, so it never rests on one mechanism
| # | layer | where | who |
|---|---|---|---|
| 1 | `availableModels` = `["opus","sonnet","haiku"]` — Fable absent at harness level | `~/.claude/settings.json`; `arm_machine` writes it on every arm, merging: an existing list keeps its entries MINUS any `fable*`, a missing key gets exactly that list | kickoff (machine) + T-173 (`kit/ops/bootstrap.py`) |
| 2 | `PreModelSwitch` deny | model-guard.sh | T-173 |
| 3 | per-call guard reads a state file | model-guard.sh | T-173 |
| 4 | spawn-input check on `Agent`/`Task`/`Workflow` | model-guard.sh | T-173 |
| 5 | `PostToolUse` `Agent` caveat on the resolved model | model-guard.sh | T-173 |
| 6 | `model_denied` in `core.sh` (route never names a forbidden model) | existing, UNCHANGED | — |

**Haiku stays refused everywhere in S17** — session, switch, spawn and caveat. There is no "marked
Haiku" yet: every Haiku request is unmarked and denied. The D6 carve-out arrives with the S19 router.

### model-guard.sh v2 — one script, branching on `hook_event_name` (T-173)
- **State file** `$HOME/.claude/polaris/model-state/<session_id>`: one line, the model id. `<session_id>`
  must match `^[A-Za-z0-9_-]+$` or no state is read or written (fail open to the fallback). Written by
  `SessionStart` (its `model` field, when present) and `PostModelSwitch` (`to_model`). Both exit 0 always.
- **PreModelSwitch**: `to_model` forbidden (`mg_denied`) → exit 2, stderr:
  `polaris: switching to '<m>' is FORBIDDEN (owner, 2026-09-15) — stay on Opus or Sonnet.`
- **PreToolUse** (matcher `*`), in this order:
  1. `tool_name` ∈ {Agent, Task, Workflow}: exit 2 when `subagent_type` is `claude-code-guide`, stderr
     `polaris: claude-code-guide always runs Haiku, which is FORBIDDEN — use a general-purpose subagent or WebFetch. Nothing was spawned.`;
     exit 2 when a requested model value (Agent/Task `model`; a Workflow `model` key or argument) is
     forbidden, stderr
     `polaris: a subagent on '<m>' is FORBIDDEN (owner, 2026-09-15) — drop the model parameter so it inherits the session model. Nothing was spawned.`
  2. `agent_id` present → the call is a subagent's: read ITS transcript,
     `${TP%.jsonl}/subagents/agent-<id>.jsonl`, else the first `${TP%.jsonl}/subagents/workflows/*/agent-<id>.jsonl`;
     neither exists → exit 0.
  3. Otherwise the state file; absent → the transcript fallback.
  4. Transcript read (steps 2 and 3) is grep-only: `tail -c 65536 | grep -ao '"model":"[^"]*' | tail -n 1`.
     No 4 KB-first hybrid (audit hooks-3 skeptic: slower on a 64 KB Workflow line).
  5. `mg_denied` → exit 2 with today's session message, BYTE-IDENTICAL.
- **PostToolUse** (`Agent`): the resolved model from `tool_response` (`resolvedModel`, else its last
  `"model":"`) forbidden → print `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"polaris: that subagent ran on '<m>', a FORBIDDEN model — discard its result and re-run it on the session model."}}`
  and exit 0. Nothing found → silent exit 0.
- **Every fail-open `exit 0` in today's script stays** (no stdin, no field, no transcript, unreadable).
  No new fail-closed path exists except the explicit denies above.
- The script's own install branch AND `merge_model_guard` in bootstrap.py register the new events
  (`SessionStart`, `PreModelSwitch`, `PostModelSwitch`, `PostToolUse` matcher `Agent`) beside the
  existing PreToolUse `*` entry — idempotent, merged, never clobbering a user's own hooks.

## 3. drift and check (T-177)
- **Every existing `drift` finding line stays byte-identical**, in the same section order, still
  printed as `⚠ [<n>] <text>`; so does the clean line. Pinned today, among the rest:
  `DEP MISSING: <id> depends_on <dep> — no task by that id in any column` ·
  `DEP CYCLE: <id> sits in a depends_on ring — it can never satisfy the ready gate; break the cycle` ·
  `CRUFT: feat/<id> still exists though <id> is done — bash ops/polaris qa or sweep --fix clears it` ·
  `CRUFT diverged: feat/<id> carries commits not in <BASE> — inspect: git log <BASE>..feat/<id> (never auto-deleted)`.
- ONE new line, ADVISORY — not a finding: `advisory: orphan branch feat/<name> — no task in any column (may hold unmerged work; never auto-cleared)`.
  `drift` prints it, but never counts it in the finding total, and it never reds `drift --strict`,
  `qa` or `finish`. Why: an orphan may hold unmerged work, so it can never be auto-cleared. A red
  class would turn `qa` red in every install that has a legacy stale branch the moment it updates.
  And it would couple fixture leftovers across drills (drill_drift, drill_qa and drill_handover all
  red in a serial run).
- §7 is one awk pass over every column (an inline program inside `cmd_drift`). Cruft, drift-cruft
  and sweep loop over the `feat/*` refs, never over `done/`. No `basename` fork inside any loop.
- `check` run with `$PWD` under `$PRIMARY/.polaris/wt/<ID>` reads `<wt>/ops/tests` and runs each `.cmd`
  from `<wt>`; from anywhere else, unchanged. `--only <glob>` matching nothing prints today's
  `no goldens matched '<glob>'` note and exits **1**; a bare `check` with zero pairs stays rc 0.

## 4. The stamp rule (T-179)
`qa` writes its suite stamp (same file, same format as today) when every set suite key is green,
HEAD and the dirty state did not move during the run, and the only other reds are CRUFT-class
(the cruft step's lines and drift findings whose text starts `CRUFT`). `qa` still exits 1 on them.
**MAP Deltas > 20 and LEARNED > 8 stay hard gates**: no stamp, rc 1 — as does every other red.
A later `qa` at the stamped HEAD runs no suite key. CONDUCTOR step 7.5 runs EVOLVE BEFORE the final
`qa`. `land --express` runs the task's `verify:` lines before `seal`; a red one unwinds and kicks back
exactly like a red suite. No gate is weakened.

## 5. The api-kit rule — every lane is surface-frozen until T-182
`ops/tests/api-kit` pins every `name()` definition in a kit `.sh` (nested ones too), every
module-level constant and def in a kit `.py`, every markdown heading and every KEYS.tsv row under
`kit/`. Under `landing: self` every lane's own land runs `uat: check`, so one new row reds that
lane's land and unwinds it. Therefore:
- **Named new api rows this sprint: NONE.** No new function, constant, heading or KEYS row, and no
  renamed one (a rename is a removed row plus an added row).
- What IS named, because none of it is an api row:
  - model-guard.sh: the new `hook_event_name` branches (§ 2) — top-level `case` code around `mg_denied`.
  - bench.sh: the `guards` mode (§ 1) — a branch of the script body, reusing `ms`.
  - bootstrap.py: `availableModels` and the new events live INSIDE `arm_machine` / `merge_model_guard`.
  - observe.sh: the §7 dependency pass is an inline awk program inside `cmd_drift`.
  - bg.sh retention: inside the existing prune path; N is an in-code constant (7 days), no KEYS row.
  - New goldens (not in api-kit): `ops/tests/model-guard-v2` (T-173), `ops/tests/drift-deps` (T-177),
    `ops/tests/qa-stamp` (T-179). All hermetic: `mktemp -d` fixtures, no live board, no real `~/.claude`.
  - Drills: NO new drill function or label. New assertions go inside `drill_brain` (T-178) and
    `drill_qa` / `drill_finish` / `drill_express` (T-179); every other drill stays green unchanged.
- A lane that finds it truly needs a new row STOPS and hands back (Invariant 3) — it never adds one.
- T-182 alone owns `api-kit.{cmd,expected}`: its `.cmd` indexes the tree it runs in (`POLARIS_ROOT`),
  and it re-pins api-kit, cli-help, keys-drift and startup-budget by CONTENT diff, stopping on any
  hunk this contract does not explain.

## 6. Worktree-true verification (the installed `ops/` stays 6.5.0 until the release checkpoint)
`bash ops/polaris check --only` and `find --api` are primary-anchored and pass vacuously from
`.polaris/wt/<ID>`. `verify:` lines therefore use:
- `bash ops/tests/<n>.cmd 2>/dev/null | diff - ops/tests/<n>.expected` — a golden against THIS tree;
- `POLARIS_ROOT="$PWD" python ops/index.py find --api 'kit/*' | grep -v '^kit/\.claude/skills/i-have-adhd/' | diff - ops/tests/api-kit.expected` — the surface freeze of § 5 (≈4 s cold);
- `bash kit/ops/polaris …` — the kit CLI from this worktree.

## 7. Laya spike verdict file — `docs/spikes/laya-s1.md` (T-181; read by Sprint 19)
Headings, exactly: `## Verdict` · `## Latency` · `## Probes` · `## Zero-shot accuracy` · `## Method`.
- Verdict: the recommended host (`cpu` or `gpu`) and go / no-go for S19, in one or two lines.
- Latency: p50 and p95 in ms per host measured, resident process, on 50 real spawn descriptions and prompts.
- Probes: (a) PreToolUse `updatedInput` sets an Agent's `model` · (b) `autoCompactWindow` written to
  `settings.local.json` mid-session takes effect · (c) a UserPromptSubmit `systemMessage` is visible —
  each `yes` / `no` / `partial` with its evidence.
- Zero-shot accuracy: 30 hand-labelled spawn difficulties and 30 continuation-vs-new-topic prompts,
  each against its majority-class baseline.
- No transcript text beyond short paraphrases; the labelled sets stay under `~/.claude/polaris/laya/`.

## Executable checks
| check | owned by | proves |
|---|---|---|
| `ops/tests/model-guard-v2` | T-173 | § 2 verdicts on five transcript tail shapes, spawn denies, fail-open |
| `ops/tests/machine-armed` | T-173 | § 2 layer 1 + the new event registrations on a fixture HOME |
| `ops/tests/ownership-primary` | T-174 | the fast-exit path exists; the pinned refusal is unchanged |
| `ops/tests/checkout-guard-denies` | T-175 | the PowerShell rows |
| `ops/tests/drift-deps` | T-177 | § 3 lines byte-identical on a fixture with one missing dep and one cycle |
| `ops/tests/handover-route` | T-178 | held reasons for all four gate failures |
| `ops/tests/qa-stamp` | T-179 | § 4 |
| `bash kit/ops/bench.sh guards` rc 0 | T-182 | § 1, once T-173..T-175 have all landed |

## Invariants
- No dependency enters the repo. Laya's venv is machine-level under `~/.claude/polaris/laya/`
  (owner-approved, plan D7).
- No kit code names a model except inside a deny list.
- Every golden a lane does not own stays byte-identical at that lane's land.

## Changelog
- v1 2026-09-24: created for T-173..T-183 (plan `v4-fast`).
- v1.1 2026-09-24 (conductor, during T-177): § 3's orphan-branch line changed from a CRUFT-class finding to an advisory, with the exact text above. Nothing else changed.
