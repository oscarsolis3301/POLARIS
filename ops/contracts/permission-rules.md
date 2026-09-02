# CONTRACT: permission-rules            (v1 — 2026-09-01)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/v2.md` WS2 (plan slug `cant-eat-itself`, 6.2.0). Tasks: T-095 (the rules + golden) ·
T-107 (the two role-file rewordings) · T-103 (bootstrap/admin union blocks stay byte-identical).

## Purpose
Auto mode still prompts ("Do you want to proceed with EnterWorktree"). Every kit permission rule is a
`Bash(...)`/`PowerShell(...)` prefix; nothing pre-authorizes the harness's OWN tools, so five top-level
sessions each stall on the same click. Owner's rule: in auto mode a POLARIS session asks nothing unless
the harness itself insists. This seam separates the RULE SET (settings data, two files, one golden) from
the prose that promises "no prompt" (BUILDER.md:16, SOLO.md:50) — the promise becomes true only when the
rule lands, and the golden is what proves it stays.

## Interface — the seven bare tool-name rules (T-095)
Appended, in this order, to BOTH:
1. `kit/.claude/settings.json` → `permissions.allow`, AFTER the last `PowerShell(...)` rule;
2. `kit/ops/bootstrap.py` → `PERMS`, as its final block, preceded by the comment block below.
```
"EnterWorktree", "ExitWorktree", "Workflow", "Task", "Agent", "TodoWrite", "SendMessage"
```
- Bare names, no parenthesised argument: a tool rule without a specifier matches every invocation of that
  tool. `EnterWorktree({path: ".polaris/wt/<ID>"})` is accepted on first entry from the launch directory
  (tool description, read 2026-09-01) — the ONLY defect was the missing allow rule.
- `Workflow` covers the prompt spelling the owner saw ("EnterWorkflow"); an unknown tool name is INERT on
  builds that lack the tool, so both spellings ship.
- `SendMessage` is the seventh: a conductor nudging a standing integrator (plan decision 3).
- **Deliberately ABSENT — never add:** `ExitPlanMode`, `AskUserQuestion` (the human gates: a plan approval
  and a question are exactly the two clicks POLARIS must keep), `NotebookEdit` (ownership-guard denies
  regardless; an allow rule would only pretend otherwise).
- `readonly-allow.sh` is NOT widened. Its contract is "only ever allows Bash reads"; tool-name permission
  is settings data, not hook logic.
- The `PERMS` comment block (T-095 writes; wording free, three facts mandatory): why the names are bare,
  why the three absences are absent, and that unknown names are inert on older builds.

## Existing union paths (unchanged — the golden's `union blocks intact` line greps them)
- `bootstrap.py:210` — `added = [rule for rule in PERMS if rule not in allow]` (machine settings, on arm).
- `admin.sh:294` — `for rule in rules:` (the `update` path's settings merge).
Both are set-if-absent unions: a rule already present is never duplicated, a foreign rule never removed.
Neither file needs a code change for the seven names to reach `~/.claude/settings.json` — they ride the
existing union on the next `polaris update` / dogfood.

## Golden — `ops/tests/perm-tools.{cmd,expected}` (T-095; hermetic — greps the two kit files, no live board)
Exactly four pinned lines:
```
settings.json: EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage → 7 of 7
bootstrap.py PERMS: EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage → 7 of 7
gates absent (ExitPlanMode AskUserQuestion): settings.json 0 · bootstrap.py 0
union blocks intact: bootstrap.py 1 · admin.sh 1
```
- Line 1/2: each name present as a bare quoted string (`"Name"` — a `Bash(Name` form does NOT count).
- Line 3: `grep -c` of each gate name in each file, summed per file — MUST be 0 (a comment naming them
  would break this line: the comment block explains the absences without spelling the names).
- Line 4: `grep -c 'added = \[rule for rule in PERMS'` on bootstrap.py · `grep -c 'for rule in rules:'` on admin.sh.
- Proven from the worktree with `bash -c "$(cat ops/tests/perm-tools.cmd)" | diff - ops/tests/perm-tools.expected`
  (never `check --only` — `cmd_check` is primary-anchored; a new golden passes vacuously there).

## Role prose (T-107, W3 — bold/list edits only, `^#` set unchanged)
`BUILDER.md:16` and `SOLO.md:50` both read today `— no prompt, this file is your instruction to run it.`
Both become, byte-identical: `— no prompt: the kit's own permission rule allows it (6.2.0).`

## Human clicks that remain (pre-announced — G11; nothing else may prompt)
1. ONE click when dogfood (`pack.py --dogfood` → `arm_machine`) rewrites the LIVE `~/.claude/settings.json`
   — the harness's self-modification classifier prompts on that file, and no rule can pre-approve it.
2. Possibly one when T-095's builder edits the repo's own `.claude/settings.json`… NO: T-095 edits
   `kit/.claude/settings.json` (the product), not `.claude/settings.json` (this repo's live file). No click
   expected in W1. The dogfood click is the release tail's.

## The owner's pre-approval (verbatim; why T-095 is `risk: normal` with `approved:` empty)
plans/v2.md, 2026-09-01: **"Owner decisions carried from v1 (2026-09-01): the permission-rules task
(`risk: high`) merge is PRE-APPROVED for exactly the bare tool names listed in WS2; the product-repo step
is in scope."** Plan-gate decision 1 (approved with the plan): "Default: `risk: normal`, `approved:` empty,
your 2026-09-01 pre-approval quoted verbatim in the task Notes and `permission-rules.md`; the real human
gate on the live settings file is the ONE classifier click at dogfood." A `risk: high` task cannot
self-land (`self_land` refuses it) and would park in `review/` for a human lane mid-W1 — the exact
mid-sprint gate the plan exists to remove. Any name OUTSIDE the seven is NOT covered by this approval.

## Invariants
- Exactly seven bare names, exactly these, in both files; the golden reds on any drift in either direction.
- The two human gates stay prompts forever; a future task adding either is a plan-gate decision, not a rider.
- `readonly-allow.sh` stays write-free and tool-name-blind.
- No code change in the union paths; the names travel by the existing set-if-absent merges.

## Example
```
$ bash -c "$(cat ops/tests/perm-tools.cmd)"
settings.json: EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage → 7 of 7
bootstrap.py PERMS: EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage → 7 of 7
gates absent (ExitPlanMode AskUserQuestion): settings.json 0 · bootstrap.py 0
union blocks intact: bootstrap.py 1 · admin.sh 1
```

## Changelog
- v1 2026-09-01: created for T-095, T-107 (plan: cant-eat-itself, 6.2.0)
