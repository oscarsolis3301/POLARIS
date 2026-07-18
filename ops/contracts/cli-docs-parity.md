# CONTRACT: CLI ↔ docs parity            (v1 — 2026-07-18)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the CLI's authoritative self-description from the prose that mirrors it, so the mirrors
cannot drift silently (QA scout 2026-07-18 caught both directions rotting).

## Interface
Authority chain — one fact, one home:
```
version truth        = ops/VERSION, surfaced ONLY by `polaris version`
                       → the usage() banner carries NO version number, ever ("POLARIS board CLI").
command truth        = `polaris help` (usage()) — exhaustive, updated by the task that ships a command
kit/CLAUDE.md table  = CURATED subset of help: daily board mechanics only. Admin/plumbing
                       (init-board · resume · task-commit-msg · why · uninstall) stays OUT.
                       The table intro carries one clause naming `ops/polaris help` as the full list,
                       so the omission reads as intent, not drift.
semantics wording    = the owning contract (clean-history.md v2 for seal/history/rollback,
                       hands-free-knobs.md for notify-gate, grant.md for grant) — never invented.
```

## Executable check (when the seam is code-level)
T-018 `verify:` greps kit/CLAUDE.md for the required rows/wording; T-019 `verify:` greps the banner
number away (`! grep -qE 'POLARIS v[0-9]+ board CLI'`). The checks ARE the contract; prose above is commentary.

## Invariants
- A task that adds/changes a CLI command updates usage() in the same diff (existing practice — keep it).
- The kit/CLAUDE.md table stays curated; new rows only for commands an agent runs in a normal wave.
- No version number in any banner or doc heading that is not generated from ops/VERSION.

## Changelog
- v1 2026-07-18: created for T-018, T-019 (fix wave 2 — QA scout findings).
