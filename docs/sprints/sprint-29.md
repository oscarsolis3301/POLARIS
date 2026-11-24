# Sprint 29 — Your preferences, once, for every project (6.21.0) (2026-11-24–)

## T-333 — "Your machine file under every repo - cfg reads this computer's preferences under each repo's own lines, the test harness never sees the real file, KEYS gains its scope column, and seal stops re-landing a file another card of the wave changed"
points 11 · risk normal · landed c72fa229 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/KEYS.tsv, kit/ops/lib/check.sh, kit/ops/lib/core.sh, kit/ops/lib/selftest/spine.sh, ops/tests/api-kit.expected, ops/tests/cfg-layers.cmd, ops/tests/cfg-layers.expected, ops/tests/landed-seal.cmd, ops/tests/landed-seal.expected

### Why
The owner wants one set of preferences per computer instead of answering the same setup questions in
every project. Everything the kit reads from `ops/CONVENTIONS.md` goes through `cfg`, so this card
teaches `cfg` one more layer: a repo's own line wins, else this computer's preferences file, else the
code default — for an allowlisted set of person-level keys only (machine-prefs.md § 2). With no
machine file nothing changes and no extra process starts. Because the owner will have a real machine
file soon, the test harness must stop reading it in the SAME change: every golden and every selftest
drill runs with `POLARIS_PREFS=` (empty = the layer is off).

The same file gets the helpers every later card codes against: the `POLARIS_HOME` variable (the one
machine home, honouring `CLAUDE_CONFIG_DIR`), `kit_file` (read a kit file from the repo copy if
present, else from the kit beside the CLI) and `prefs_put` (write one key into the machine file).
KEYS.tsv documents each key's reach in a new 6th column, and a golden ties that column to the
allowlist so the two cannot drift.

Riding along because it lives in this file and must land in wave 1 (sprint 28 lesson): seal's content
check re-landed one card's copy of a file over another card's when two cards of one wave changed it.
`landed_content_ok` now treats a path another task's commit touched after this task forked as shared
wave work (safe-landing v1.4 § K).

### Acceptance
- [ ] cfg-layers: every machine-prefs "Executable checks" case for cfg-layers, plus the allowlist == KEYS machine rows tie
- [ ] With no machine file: every golden in verify byte-identical (nothing re-pinned except landed-seal's appended b2 and api-kit's +2 rows)
- [ ] landed-seal b2 per § K; cases a-e unchanged
- [ ] KEYS.tsv: no row added or removed, every row 6 fields, scope values exactly machine-prefs § 2
- [ ] api-kit: exactly + `kit/ops/lib/core.sh	fn	kit_file` and `kit/ops/lib/core.sh	fn	prefs_put`

## T-334 — "The hooks read your machine file and find the kit themselves - the four state hooks fall back to this computer's preferences, every hook uses the one machine home and the repo-or-kit lookup, and the read-only gate lets role, doc, router and prefs through"
points 8 · risk normal · landed e7197c23 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/hooks/awake-hook.sh, kit/ops/hooks/handover-hook.sh, kit/ops/hooks/model-guard.sh, kit/ops/hooks/ownership-guard.sh, kit/ops/hooks/permission-hook.sh, kit/ops/hooks/presence-guard.sh, kit/ops/hooks/readonly-allow.sh, kit/ops/hooks/update-hook.sh, ops/tests/awake-hook.cmd, ops/tests/awake-hook.expected, ops/tests/handover-stop.expected, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected, ops/tests/ownership-primary.cmd, ops/tests/ownership-primary.expected, ops/tests/permission-hook.cmd, ops/tests/permission-hook.expected, ops/tests/presence-guard.cmd, ops/tests/presence-guard.expected, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected

### Why
Hooks run on every tool call and never load the kit's lib, so they read CONVENTIONS with their own
tiny readers. Four of them read person-level keys (re-entry, stall and pulse timers, the hop switch,
the run cap) that can now live in the computer's preferences file, so each reader gains the same
fallback cfg has: repo line, else machine line, else default — still no extra process when the file is
absent, and `POLARIS_PREFS=` (empty) turns it off for the tests. The same hooks hard-code
`$HOME/.claude/polaris` for their state and read kit files through the repo's `ops/`; both become the
one machine home and the repo-or-kit lookup, so a later shared kit works (doc-server § 2-3). The
read-only gate learns the four new read-only verbs so agents are not prompted for them, while
`prefs --set` (which writes the computer's file) still asks.

### Acceptance
- [ ] With no machine file and CLAUDE_CONFIG_DIR unset: every existing line of every golden in verify byte-identical (cases only APPENDED, plus handover-stop's one re-pinned TIDY line)
- [ ] awake-hook, presence-guard, permission-hook: an appended case where the machine file sets reentry_hours (and the repo does not) is honoured; a repo line still beats it
- [ ] model-guard-v2: an appended case with CLAUDE_CONFIG_DIR set finds its state under that dir
- [ ] ownership-primary: an appended case where the repo has no ops/polaris copy resolves the kit's own
- [ ] readonly-allow: `polaris role BUILDER`, `doc PROTOCOL`, `router`, `prefs` allowed; `prefs --set voice=technical`, `--unset`, `--seed`, `--yield` NOT allowed
- [ ] no new function definitions (api-kit unchanged)

## T-335 — "Role files and kit docs point at commands, not paths, and INIT asks only what this computer has not answered - every kit doc path in the prose becomes bash ops/polaris role or doc, INIT uses interview --init, and PROTOCOL says what the value in CONVENTIONS means now"
points 7 · risk normal · landed bc6ce089 (2026-11-24) · claimed 2026-11-24
files touched: kit/.claude/output-styles/polaris.md, kit/.claude/skills/polaris/SKILL.md, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/VISUAL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/EVOLVE.md, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md, kit/ops/roles/TIDY.md

### Why
Today every role file and kit document tells agents to read a path like `ops/roles/BUILDER.md`. Once
one kit serves every project on the computer (Phase 4), those files will live in the kit, not in each
repo, and the paths will point at nothing. The CLI is getting a doc server (`bash ops/polaris role
<NAME>`, `doc <FILE> "<section>"`, `router`) that works in both layouts, so this card rewrites the
prose to the command form now, by the exact rules in doc-server § 5 — mechanical, no wording change
beyond the reference itself. MANUAL.md is the fallback for an agent that cannot run commands, so there
a reference names the bare file in the kit instead. PROTOCOL also gains the one sentence that defines
"the value in ops/CONVENTIONS.md" as the effective value now that a machine layer exists.

INIT.md rides here because it is prose too: the first-run interview is where "answer once per
computer" becomes visible. INIT asks the CLI what this computer already answered
(`interview --init`), uses those answers, and skips its first question round when nothing is left;
the skeleton keeps every other person-level key as a stub so the computer's file fills it in, and a
computer without preferences behaves exactly as before (first-run v2 § B). The stubs are written
`#key:` with no space because a `# ` line inside the fenced skeleton is an api-kit row, and this card
does not own api-kit.

### Acceptance
- [ ] zero matches of the doc-server § 5 pattern in every file this card owns
- [ ] the machine-prefs § 4 sentence verbatim, as the last paragraph of PROTOCOL § STATE = THE BOARD
- [ ] NO heading line changes (lines starting `#` + space, including inside fenced blocks): api-kit unchanged
- [ ] `bash kit/ops/polaris drift` shows no new doc-overflow finding for these files
- [ ] INIT.md: first-run v2 § B exactly, headings byte-identical

## T-336 — "The CLI's own messages name commands, not paths - next, triage, hops, drift, the verify guard and seal say bash ops/polaris role or doc where they used to say read ops/roles"
points 3 · risk normal · landed ad40cc4d (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/index.py, kit/ops/lib/builder.sh, kit/ops/lib/drift.sh, kit/ops/lib/handover.sh, kit/ops/lib/ownership.sh, kit/ops/lib/route.sh, ops/tests/handover-route.expected, ops/tests/hops-due.expected, ops/tests/hops-map.expected, ops/tests/seal-fallback.expected, ops/tests/surfaces-scaffold.expected, ops/tests/triage-lane.expected, ops/tests/tune-hop.expected

### Why
Seven places in the CLI print "read ops/roles/TIDY.md" or point at `ops/MANUAL.md`. Those paths will
not exist in a repo once the kit is shared (Phase 4), and the doc server makes the command form work
today in both layouts. Each message changes to the exact rendering pinned in doc-server § 6, and each
golden that pins one of them is re-pinned to exactly that line — nothing else in any expected file
moves.

### Acceptance
- [ ] every T-336 row of doc-server § 6 rendered verbatim
- [ ] each listed golden differs from base ONLY on those lines
- [ ] no code change beyond the strings; api-kit and lib-census unchanged
