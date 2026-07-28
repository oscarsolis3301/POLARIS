# Sprint 7 — The recorded yes (2026-07-28–)

## T-051 — "`approved:` field on TASK.md + the guard's rc-1 message names the remedy"
points 2 · risk normal · landed 37ebc94 (2026-07-28) · claimed 2026-07-28 → done 2026-07-28
files touched: kit/ops/hooks/ownership-guard.sh, kit/ops/templates/TASK.md

### Why
Two small surfaces, both on the path a human or an agent actually walks.

The template is where the `approved:` field becomes discoverable — a field nobody can see in the
template is a field the Planner never writes and `approve` writes into nothing.

The guard's rc-1 message is what an agent reads at the exact moment it is blocked. Today it says
"if the rule is wrong, that is a HUMAN decision: propose the change, do not work around it" — correct
and complete when every rule meant *never*. With `ask` there is now a legitimate third answer, and it
is the one that would have saved the ARC sprint: the human may have already said yes, and if so the
yes belongs on the task. The message must name that remedy AND make clear the Builder does not run it.

### Acceptance
- [ ] `kit/ops/templates/TASK.md` gains the optional `approved:` field directly after `files_owned:`,
- [ ] the comment says `polaris approve` writes these — a Planner never hand-edits them
- [ ] a task file with no `approved:` field, or an empty one, stays valid: `bash ops/polaris board-fm`
- [ ] the guard's rc-1 branch in `kit/ops/hooks/ownership-guard.sh` adds the contract's pinned remedy
- [ ] the existing rc-1 lines are kept — "rules bind even inside files_owned" and "if the rule is
- [ ] rc 2 (the value returned to Claude Code) and the rc 0/1/3 handling are unchanged; no new

## T-052 — "RULES.tsv header documents `ask` — and that converting a rule is a human call"
points 2 · risk normal · landed abfd554 (2026-07-28) · claimed 2026-07-28 → done 2026-07-28
files touched: kit/ops/lib/admin.sh, ops/RULES.tsv

### Why
Containment (d) of the design, and the one that stops `ask` from eating the whole rule file.
Invariant 11 lets an agent maintain `ops/RULES.tsv` — add lines, edit them, remove them — but it
draws one line: *never delete a rule because it blocked you*. A third kind that lifts denials on
approval hands a stuck agent a new way to do exactly that: flip the `path` to `ask`, approve it,
walk through. So the file itself has to say that flipping a rule between `path` and `ask` is a human
decision.

Two homes, one fact: `kit/ops/lib/admin.sh` holds the heredoc `init-board` writes into every NEW
repo's `RULES.tsv`, and `ops/RULES.tsv` is this repo's own already-seeded copy. Both get the same
lines, verbatim.

### Acceptance
- [ ] the `RULES.tsv` seed heredoc in `kit/ops/lib/admin.sh` documents the `ask` kind, using the
- [ ] the same lines are added to this repo's `ops/RULES.tsv` header comment, verbatim
- [ ] the seed's `#   kind` block reads path · content · ask, in that order
- [ ] `bash ops/polaris check --only rules-health` still prints `✅ 14 rule(s), all healthy` — you are
- [ ] `bash kit/ops/polaris rules` exits 0

## T-053 — "kit/CLAUDE.md: `ask` in Invariant 11 and STOP AND ASK"
points 2 · risk normal · landed e7e1f9d (2026-07-28) · claimed 2026-07-28 → done 2026-07-28
files touched: kit/CLAUDE.md

### Why
Invariant 11 is where an agent looks when a rule blocks it. Today it offers two outcomes — "the rule
looks wrong, say so and ask" or "the rule looks right, hand the task back". `ask` adds a third, and
if the invariant does not name it, agents will either never find it or invent their own version of
it. STOP AND ASK needs the same: converting a rule between `path` and `ask` joins the list of things
that need a human's word first, right beside `.github/`.

**This file is injected into EVERY session and EVERY subagent, six to eight times a run.** Every byte
is paid that many times. Add clauses, not paragraphs — the budget check in `verify:` allows +8 lines
over today's 114 and it is deliberately tight.

### Acceptance
- [ ] Invariant 11 names the three kinds and what `ask` means, quoting the contract's pinned
- [ ] Invariant 11 states that converting a rule between `path` and `ask` is a HUMAN decision, in the
- [ ] the STOP AND ASK list gains converting a rule between `path` and `ask`
- [ ] a Builder reading only this file learns that it never runs `approve` itself — it hands back
- [ ] `kit/CLAUDE.md` stays ≤122 lines
- [ ] no other section is reworded (this is an addition, not a rewrite — the ROLE DISPATCH table and

## T-054 — "Role files: the Planner asks, the Builder hands back, the Integrator sees it"
points 2 · risk normal · landed 0a336c4 (2026-07-28) · claimed 2026-07-28 → done 2026-07-28
files touched: kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md

### Why
The mechanism only works if the ask lands in the right session. Wrong session and it is either an
agent approving itself (the failure mode the whole design is built to prevent) or a human being
interrupted mid-build for a decision that was cheap ten minutes earlier and is expensive now.

The routing is: **the Planner asks, at the plan gate, before any task is promoted.** The Builder
never approves — it hands back exactly as it does today. The Integrator sees the approval named in
the handoff report and treats it as part of what it is landing. The Conductor knows an unapproved
`ask` scope is a human gate, like `risk: high`.

Five short insertions, each quoting the contract's pinned phrasing. This is not a rewrite of any role.

### Acceptance
- [ ] PLANNER.md: the ready gate (Invariant 2 / protocol step 5) states that a task owning an `ask`
- [ ] BUILDER.md: its existing "never touch RULES.tsv — hand back" paragraph gains the contract's
- [ ] SOLO.md: same pinned line, in its "a RULES rejection is an answer, not an obstacle" section —
- [ ] CONDUCTOR.md: an unapproved `ask` scope is a human gate at the plan gate, handled like any
- [ ] INTEGRATOR.md: an approval named in a handoff report is part of what is being landed — read it,
- [ ] no role file's ROLE header, its step numbering, or its report format changes

## T-055 — "MANUAL, PROTOCOL and the skill learn the third rule kind"
points 2 · risk normal · landed 30c5bce (2026-07-28) · claimed 2026-07-28
files touched: kit/.claude/skills/polaris/SKILL.md, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md

### Why
Three surfaces still describe a two-kind world, and each one is load-bearing somewhere the CLI is not.

`kit/ops/MANUAL.md` § "Ownership + RULES proof" is the recipe an agent follows when it CANNOT execute
the CLI — it spells out the two kinds by hand. If it never learns the third, the manual path silently
enforces `ask` as `path`, which is the ARC failure with extra steps. `kit/ops/PROTOCOL.md` § LANES
says `solo` requires "nothing RULES-guarded", which after T-049 is no longer true — an `ask` scope
WITH an approval falls through to ordinary routing, and one fact must have one home. The skill file
tells every session "never edit RULES.tsv", which predates Invariant 11 and now also misses the
approval route.

Added by the Planner beyond the brief's file list: leaving these stale is documentation drift that
contradicts shipped behaviour, which is the exact failure mode `check --only triage-lane` exists to
catch on the CLI side.

### Acceptance
- [ ] MANUAL.md § "Ownership + RULES proof" describes all three kinds and how to check an `ask` rule
- [ ] MANUAL.md's "never edit RULES.tsv" sentence is corrected — RULES are agent-maintained
- [ ] PROTOCOL.md's `RULES.tsv` line names three kinds, and the LANES table's `solo` row reads
- [ ] SKILL.md's invariant summary names `ask` and the approval route, and drops "never edit
- [ ] all three quote the contract's pinned one-liner verbatim
- [ ] no line count grows by more than ~4 lines per file — these are clauses, not sections
