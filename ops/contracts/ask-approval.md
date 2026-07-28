# CONTRACT: the `ask` rule kind + `polaris approve`      (v1 — 2026-07-28)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
`ops/RULES.tsv` has only two kinds, `path` and `content`, and both mean **never**. There is no way to
express "gated on a human's yes" — which is what a message like *"SQLAlchemy schema — human decision,
stop-and-ask"* plainly intends. The kit's own vocabulary already leans softer (`lib/ownership.sh`
calls them "danger zones"; `lib/observe.sh` comments the triage check `STOP-AND-ASK, mechanically`)
but enforcement only ever implements a wall.

Consequence, observed in the field (repo ARC, 2026-07): a human approved a schema change at the plan
gate. The ready gate never consults RULES, so the task was promoted to `ready/`. `triage` printed
`full`. A Builder claimed it and died on its first write. It correctly refused to edit the rule
(Invariant 11) and refused to route around it. **The work died with the decision already made**, and
a `path`-ruled directory is unbuildable by POLARIS forever regardless of human intent.

`ask` gives the approval a place to live, and moves the asking to the plan gate where it is cheap.

## Interface

### 1. The rule kind
```
<scope><TAB>ask<TAB>-<TAB><message>
```
- Denies **exactly as `path` does** unless the claimed task carries a recorded human approval
  covering that scope.
- `path` and `content` are untouched. Nothing currently protected gets weaker.
- Scope semantics are unchanged: exact path · `dir/` prefix · glob (`*` crosses `/`).
- The pattern column is `-`, as for `path`.
- `polaris rules` accepts `ask` as a valid kind in its health check.

### 2. Approval on the task — the `approved:` front-matter field
`ops/templates/TASK.md` gains an optional list field, placed directly after `files_owned:`:
```yaml
approved:                # human-granted exceptions to `ask` rules (polaris approve writes these)
  -                      # <scope> — <who>, <date>: <why>
```
- **Parse rule:** the scope is the leading whitespace-delimited token of the entry. Everything after
  it (conventionally ` — <who>, <date>: <why>`) is provenance for humans and is never parsed.
- **Coverage rule:** an entry covers a path when its scope, matched with the ordinary `files_owned`
  matcher, matches that path. Scope-for-scope equality is NOT required.
- Per-task and per-scope. It expires with the task. It never accumulates into repo-wide permission.
- Lives on the board branch in git, like every other board mutation.
- Absent or empty `approved:` = no approvals. Every existing task file stays valid unchanged.

### 3. `polaris approve <ID> <scope> -m "why"`
The sibling of `grant`, modelled directly on `cmd_grant`: same option parsing, same `-m` requirement,
same `mutex_on → append → evt → board_commit → sync_board` sequence, same append-only front-matter
writer. **The two commands stay distinct: `grant` widens ownership; `approve` clears a policy gate,
and only `approve` needs a human.**

```
polaris approve <ID> <scope> -m "why"
  preconditions (ALL, else exit non-zero, board untouched):
    - <ID> exists on the board
    - -m "why" given, non-empty
    - <scope> matches at least one `ask`-kind rule
        (approving something ungated is a no-op — it MUST say so, not silently write a line)
    - the current branch is NOT feat/*
        (a Builder cannot approve itself; mechanically impossible, not merely discouraged)
  effects (single board commit, "chore(board): approve <ID> <scope>"):
    - "<scope> — <who>, <date>: <why>" appended to <ID>'s approved: list
    - one line appended to <ID>'s Notes:  approve: <scope> — <why>
    - one event appended to EVENTS.ndjson (kind "approve", id, scope)
```
The append-only front-matter writer (`grant_append_owned`) is **generalized to take a field name**, so
`grant` and `approve` share one writer. Its existing behaviour for `files_owned` is unchanged: block
list gets a new `  - <item>` · `[a, b]` flow list gets `, <item>` before the `]` · `[]` is filled ·
an inline scalar becomes a two-item flow list · rc 1 + file untouched when the field is missing or
malformed. When the named field is absent from the front matter, the writer refuses (rc non-zero) —
it never invents a field.

### 4. Threaded enforcement
`rule_scan_path` takes an **optional second argument, the task ID**:
```
rule_scan_path <repo-relative-path> [<ID>|-]
```
- `path` match → deny (unchanged, always).
- `content` → unchanged (`rule_scan_content_file` is untouched).
- `ask` match, ID given, the task's `approved:` covers the scope → **pass**.
- `ask` match, ID given, not covered → deny.
- `ask` match, ID is `-` or omitted → **deny**. A session with no task has nothing to carry an
  approval. This is the fail-closed default, and it is what keeps `_rules <path>` (no ID) honest.

Callers threaded: `check_rules <ref> [<ID>]` and its four call sites (`cmd_verify`, `cmd_handoff` in
`lib/builder.sh`; `cmd_audit`, `cmd_land` in `lib/integrate.sh` — all four already know the ID);
`cmd_guard` (already receives the ID); `cmd_rules_check` (`_rules`, which has no ID and therefore
denies). Guard exit codes are unchanged: `0` clean · `1` rules deny · `3` ownership deny.

**When a check passes BECAUSE of an approval, it must say which one.** `check_rules` prints a line
naming the scope and the approval entry, so it lands in the handoff report where the Integrator sees
it. Silence would make the exception invisible at exactly the moment a human is meant to notice it.

### 5. The plan gate — where the ask actually belongs
- **Ready gate** (`cmd_drift`, step 2): a task in `ready/` whose `files_owned` intersects an `ask`
  scope with no covering `approved:` entry is a finding. Finding text begins `READY GATE:` and names
  the task, the owned pattern and the scope. It belongs in `blocked/`, not `ready/`. *This is the
  check that stops the ARC sequence at step 1.*
- **`cmd_triage`**: three cases instead of one.
  | what the task owns | lane | note |
  |---|---|---|
  | a `path` scope | `full` | `cannot be built as specified` |
  | an `ask` scope, no covering approval | `full` | `get the human's yes before starting` |
  | an `ask` scope, covered by an approval | — | the question is settled: fall through to ordinary points-based routing |
  Line 1 of `triage` stays exactly one bare word (`solo`/`express`/`full`); reasons stay on `   `
  note lines. The `triage-lane` golden asserts this.

## Invariants
- **Refusal mutates NOTHING** — no partial writes, no commit, no event.
- **`path` and `content` are unchanged.** An approval never clears a `path` rule. `ops/` and
  `.github/` protections in this repo are byte-for-byte as strong after this work as before.
- Approvals are **per-task and per-scope**; they never accumulate into repo-wide permission.
- **`approve` refuses inside a `feat/*` worktree.** A Builder cannot approve its own way out.
- **Converting an existing `path` rule to `ask` is itself a human decision.** Invariant 11 licenses
  agents to maintain `RULES.tsv`, but not this edit — without this clause `ask` becomes a legal way
  to dissolve any rule that blocks you, which is the single motive Invariant 11 exists to resist.
- `approve` is append-only: it never removes or rewrites an existing `approved:` entry.
- No new dependencies. bash 3.2 compatible (`case` inside `$(...)` does not parse there).

## Pinned phrasing — quote these verbatim, do not paraphrase
Documentation tasks land in parallel; identical strings merge without conflict, paraphrases do not.
Every doc surface below uses these exact strings:

- kind line, for `RULES.tsv` headers (`kit/ops/lib/admin.sh` seed + `ops/RULES.tsv`):
  `#           ask     = same denial as path, UNLESS the claimed task carries a human approval`
  `#                     covering the scope (polaris approve <ID> <scope> -m "why")`
  `# Converting a rule between path and ask is a HUMAN decision, never an agent's — Invariant 11.`
- the one-line summary of the kind, for prose surfaces (`kit/CLAUDE.md`, role files, PROTOCOL,
  MANUAL, SKILL):
  `` `ask` = the same denial as `path`, lifted only by a human's recorded approval on the task ``
- the conversion clause, prose variant (same sentence as the header line above, backticked for
  markdown surfaces):
  ``Converting a rule between `path` and `ask` is a HUMAN decision, never an agent's.``
- the remedy line, for the guard's rc-1 message and role files:
  `` If a human has already approved this, it belongs on the task: `polaris approve <ID> <scope> -m "why"` — a Builder cannot run it. ``
- the Builder's standing instruction (unchanged in meaning, made explicit):
  `` A Builder never approves. Hand back — the approval is granted at the plan gate, not mid-build. ``

## Executable check
`doctor --selftest` gains six assertions inside `drill_rules` (`kit/ops/lib/selftest/policy.sh`),
following that drill's existing shape — append a temp rule, assert, clean up so the fixture is left
exactly as found:
1. `ask` rule + no approval → `_guard <path> <ID>` denies (rc 1)
2. after `polaris approve <ID> <scope> -m "drill"` → the same `_guard` call passes (rc 0)
3. `_rules <path>` with no ID still denies even with the approval on the task
4. `approve` from a `feat/<ID>` branch refuses, board untouched
5. a `path` rule is NOT cleared by an approval
6. a `ready/` task owning an unapproved `ask` scope → `drift --strict` exits 1 with the finding

Owned by T-050 and listed in T-050's `verify:`.

## Example
```
# the human approves at the plan gate, in the primary checkout, never from a worktree:
polaris approve T-101 atlas_api/models/ -m "schema shape approved in the plan gate 2026-07-28"

# the task file now carries:
approved:
  - atlas_api/models/ — oscar, 2026-07-28: schema shape approved in the plan gate 2026-07-28
```

## Changelog
- v1 2026-07-28: created for T-047..T-050 (POLARIS 5.24.0), from the ARC field report.
