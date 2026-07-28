# Sprint 7 — The recorded yes (2026-07-28–)

## T-052 — "RULES.tsv header documents `ask` — and that converting a rule is a human call"
points 2 · risk normal · landed abfd554 (2026-07-28) · claimed 2026-07-28
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
points 2 · risk normal · landed e7e1f9d (2026-07-28) · claimed 2026-07-28
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
points 2 · risk normal · landed 0a336c4 (2026-07-28) · claimed 2026-07-28
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
