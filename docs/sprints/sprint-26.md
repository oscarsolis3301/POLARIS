# Sprint 26 — The tune-up: every install ends faster than it started (6.18.0) (2026-11-17–)

## T-308 — "The tune-up commands - tune reports what slows a project, fold turns a waiting chain into one card, note records a line on a claimed card"
points 13 · risk normal · landed c3eed71 (2026-11-17) · claimed 2026-11-17 → done 2026-11-17
files touched: CHANGELOG.md, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/VERSION, kit/ops/hooks/readonly-allow.sh, kit/ops/lib/builder.sh, kit/ops/lib/tune.sh, kit/ops/polaris, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/SOLO.md, ops/tests/api-kit.expected, ops/tests/fold-chain.cmd, ops/tests/fold-chain.expected, ops/tests/note-line.cmd, ops/tests/note-line.expected, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected, ops/tests/tune-report.cmd, ops/tests/tune-report.expected

### Why
An update refreshes a project's kit code and stops there: the layout pass is never run anywhere but
here, cards cut under the old 5-point rule keep costing about 36 minutes each, and settings that slow a
project (integration: paranoid, a too-high autolaunch_max) are never compared with its own numbers.
This card builds the three commands the tune-up needs, all mechanical and model-free:

- `tune` reads data the project already has and prints one line per thing that slows it, each with the
  one step that fixes it, and writes the small verdict file `.polaris/tune-due` that the routers read
  for free (contract section 1 and 2). It never edits config: settings come back as proposals.
- `fold` turns a chain of waiting cards into ONE chain card in one board commit, losslessly, and one
  revert undoes it (contract section 4).
- `note` gives builders a proper writer for an `assumed:` line, so their lines stop riding other lanes'
  board commits (contract section 3, lesson 3 of plan hour). And a builder short exactly one path now
  returns NEEDS PATH and keeps its claim, so the conductor grants it instead of a release, planner and
  cold start (lesson 2).

This card is the ONLY owner of kit/ops/polaris and ops/tests/api-kit.expected this wave (T-309 adds no
public name). It carries the release words: version 6.18.0 and the changelog for both cards.

### Acceptance
- [ ] tune prints exactly the contract's lines and exit codes; rc 0 prints the one nothing-to-do line
- [ ] every tune run (rc 0 or 1) writes `.polaris/tune-due` in the section 2 shape; rc 2 writes nothing
- [ ] tune and fold never edit ops/CONVENTIONS.md, ops/RULES.tsv or ~/.claude
- [ ] fold refuses every case in section 4 with nothing written; a good fold is one board commit `chore(board): fold <C2>… → <C1>` and one git revert restores the board
- [ ] note appends one line in its own board commit and refuses the four cases in section 3
- [ ] CONDUCTOR.md and BUILDER.md carry the NEEDS PATH path; BUILDER.md and SOLO.md point at note for assumed: lines
- [ ] api-kit.expected gains exactly cmd_tune, cmd_fold, cmd_note and the two MANUAL headings
- [ ] kit/ops/VERSION is 6.18.0 and CHANGELOG.md has a 6.18.0 entry with measured claims only

## T-309 — "Every install ends in the tune-up - next and triage hop to it with cards waiting, updates name it, the layout pass keeps off waiting cards' files"
points 13 · risk normal · landed 559ea32 (2026-11-17) · claimed 2026-11-17 → done 2026-11-17
files touched: kit/CLAUDE.md, kit/ops/index.py, kit/ops/install.sh, kit/ops/lib/admin.sh, kit/ops/lib/handover.sh, kit/ops/lib/integrate.sh, kit/ops/lib/route.sh, kit/ops/lib/selftest/fast.sh, kit/ops/roles/INIT.md, kit/ops/roles/TIDY.md, ops/tests/handover-route.cmd, ops/tests/handover-route.expected, ops/tests/hops-due.expected, ops/tests/hops-hold.cmd, ops/tests/hops-hold.expected, ops/tests/index-selfcheck.expected, ops/tests/install-update.cmd, ops/tests/install-update.expected, ops/tests/triage-lane.cmd, ops/tests/triage-lane.expected, ops/tests/tune-hop.cmd, ops/tests/tune-hop.expected, ops/tests/update-waiting.cmd, ops/tests/update-waiting.expected

### Why
Today the layout pass reaches a project only at the very end of a run or on an empty board
(handover.sh row 5.5 sits after the build, promote and wait rows; triage's tidy branch needs ready/ and
active/ empty), so a project that always has cards waiting never gets it — no project but this one has
ever run it. An update ends on a layout-only line, `update --auto` leaves silently when a project is
stuck, and nothing after an update looks at speed.

This card makes every update and install END in the tune-up and makes the next agent take it:
- `next` and a bare `triage` send a session to the tune-up (the `tidy` lane, `ops/roles/TIDY.md`) when
  the verdict in `.polaris/tune-due` (or `.polaris/hops-due`) says due and nothing is building or
  waiting to land; cards merely waiting in ready/ or backlog/ no longer hold it off (contract section 6).
- That is only safe because of the hold rule: today `_hops_in_flight` holds dirty paths and unmerged
  branches only, so a pass could move a file an unclaimed ready or backlog card owns and that card would
  then fail its own ownership check. Now every path an open card owns or reads is fixed for the pass,
  and a whole feature that would need an edit inside one waits for the next pass.
- The update and install lines name the tune-up with its count; `update --auto` says, once over a day,
  what an update has been waiting on and the step that frees it (contract section 5).
- TIDY.md runs `tune` first and applies its folds; INIT ends with `tune`; CLAUDE.md's lane row says
  what the lane now does. And `find --api` stops pinning nested helpers (lesson 1 of plan hour) — its
  seven golden rows leave at the post-dogfood re-pin, not here.

`tune` itself is T-308's; this card only calls `"$SELF" tune >/dev/null 2>&1 || true`, which stays a
silent no-op until T-308 lands, and its goldens write fixture `.polaris/tune-due` files.

### Acceptance
- [ ] on a fixture board with a ready card and a backlog card waiting plus a due verdict, `next` and a bare `triage` print `tidy` once per session, then their usual answer
- [ ] an active card, any review card, a live lease or an own live bg job holds the hop off; every other next/triage answer is byte-identical
- [ ] `hops --propose` never moves, and never needs to edit, a path an open card's files_owned or context_files names; no board ref = today's output
- [ ] a typed update ends with the contract's `▶ NEXT — tune-up` line; the session-start line carries ` · tune-up due (<n>)`; n = 0 leaves both byte-identical
- [ ] `update --auto` blocked over a day prints the one section 5 line; under a day it is unchanged
- [ ] install.sh still prints exactly one `▶ NEXT` line and a fresh install still ends with the setup epilogue
- [ ] find --api skips indented shell fns; column-0 fns, find, show and pack are unchanged
- [ ] no new public name under kit/ (api-kit stays green with the installed indexer)

## T-310 — Re-pin the hops-due golden to the tune-up note its two cards now print together
points 1 · risk normal · landed 83b9566 (2026-11-17) · claimed 2026-11-17
files touched: ops/tests/hops-due.expected

### Why
The two tune-up cards met in one check: heal now runs the real tune-up, which leaves a note saying
the layout pass is due, and next and triage read that note first, just as the tune-up contract
says. So the hops-due check's expected output now shows "tune-up due: layout" in two places where
it used to show the older, longer message. This updates the expected output to match; nothing else
changes.
