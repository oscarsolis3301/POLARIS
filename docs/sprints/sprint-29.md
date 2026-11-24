# Sprint 29 — Your preferences, once, for every project (6.21.0) (2026-11-24–)

## T-333 — "Your machine file under every repo - cfg reads this computer's preferences under each repo's own lines, the test harness never sees the real file, KEYS gains its scope column, and seal stops re-landing a file another card of the wave changed"
points 11 · risk normal · landed c72fa229 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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
points 8 · risk normal · landed e7197c23 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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
points 7 · risk normal · landed bc6ce089 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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
points 3 · risk normal · landed ad40cc4d (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
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

## T-337 — "polaris prefs, role, doc and router - the CLI finds its own code, shows and sets your machine preferences, serves role files and kit documents in pages, and CLAUDE.md routes through commands"
points 13 · risk normal · landed fd26cbc1 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/CLAUDE.md, kit/ops/lib/docs.sh, kit/ops/lib/prefs.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/doc-server.cmd, ops/tests/doc-server.expected, ops/tests/prefs-cli.cmd, ops/tests/prefs-cli.expected

### Why
This is the one card that edits the CLI's entry script, so everything the release adds to it lands
here. Three things. (1) The CLI locates its own code from its own path (`BASH_SOURCE`), so a later
shared kit can run it from outside any repo; in a vendored install every path is the same as today.
(2) `polaris prefs` lets a person see, for every key, which value wins here and where it came from
(repo, this computer, or the default), and set, unset, seed or yield the computer's file — with the
refusals that keep an agent from ever setting the autonomy dial. (3) `role`, `doc` and `router` serve
the kit's own role files and documents, split into pages at `##` boundaries because the harness only
inlines about 30,000 characters and CONDUCTOR.md is larger. kit/CLAUDE.md — the router every session
reads — switches to the command form in the same change, because its one heading with a path is an
api-kit row and this card owns api-kit in wave 2.

### Acceptance
- [ ] doc-server golden: every case listed under its "Executable checks"
- [ ] prefs-cli golden: every machine-prefs § 7 form and refusal, including the CLAUDECODE=1 dial refusal, and prefs value == cfg value for every key of its fixture
- [ ] vendored install: every pre-existing golden in verify byte-identical; startup-budget unchanged (docs/prefs load only for their verbs and doctor)
- [ ] api-kit: + docs.sh `cmd_role` `cmd_doc` `cmd_router` `kit_mode` + prefs.sh `cmd_prefs` (name any other public function in the handback) + kit/CLAUDE.md's rewritten heading row; nothing else
- [ ] `bash kit/ops/polaris role CONDUCTOR` ends with `— page 1 of <n> · next: bash ops/polaris role CONDUCTOR --page 2`

## T-338 — "Setup answers once per computer - interview --init answers from your machine file before a repo has CONVENTIONS, --remember keeps new answers for next time, and the installer and admin commands read the kit and the machine home through one lookup"
points 8 · risk normal · landed 8e7f9fa6 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/install.sh, kit/ops/lib/admin.sh, kit/ops/lib/selftest/fast.sh, ops/tests/adopt-stub.expected, ops/tests/install-update.expected, ops/tests/interview.cmd, ops/tests/interview.expected

### Why
Today every new repo asks the same three setup questions (how to talk to you, ADHD-shaped replies,
one computer or several). With a machine preferences file those answers already exist on this
computer, so `interview --init` — which works before the repo has any CONVENTIONS — prints what the
machine file answers as `ANSWERED` lines and asks only the rest; `--remember` records a new answer in
the machine file when it has none, so the next project asks nothing. `interview_pending` (what doctor
and update use to nag) counts a machine answer as answered. The same file reads kit files through the
repo state dir in a dozen places and hard-codes the machine home; both switch to the one lookup and
the one home variable from T-333, byte-identical in a vendored install. The installer's adhd read
gains the same machine fallback. The admin and installer messages that say "read ops/roles/…" switch
to the command form, except the installer's INIT epilogue, which CI greps.

### Acceptance
- [ ] interview: existing lines byte-identical except doc-server § 6's one re-pinned line; appended cases: --init with no CONVENTIONS and no machine file (all questions), with a machine file answering voice (ANSWERED voice … machine, questions for the rest), --remember writing only keys the machine file lacks, POLARIS_PREFS= making --remember a silent no-op
- [ ] no new function definitions in admin.sh (api-kit unchanged)
- [ ] install-update and adopt-stub differ from base only on the § 6 lines
- [ ] install.sh still prints `read ops/roles/INIT.md` (ci.yml:331, selftest-install.sh:184/293)

## T-339 — "Doctor names your machine file, and the rest of the CLI finds the kit and the machine home through one lookup - status, find, keep-awake, presence, routing, heavy slots and the tune-up line"
points 5 · risk normal · landed 415995d2 (2026-11-24) · claimed 2026-11-24 → done 2026-11-24
files touched: kit/ops/lib/awake.sh, kit/ops/lib/observe.sh, kit/ops/lib/presence.sh, kit/ops/lib/route.sh, kit/ops/lib/search.sh, kit/ops/lib/tune.sh, kit/ops/lib/workspace.sh, ops/tests/doctor-prefs.cmd, ops/tests/doctor-prefs.expected, ops/tests/keys-drift.cmd, ops/tests/keys-drift.expected, ops/tests/tune-report.expected

### Why
The remaining CLI modules read kit files (VERSION, KEYS.tsv, index.py, the hooks) through the repo's
`ops/` and hard-code `$HOME/.claude/polaris` for machine state. Both switch to T-333's `kit_file`
and `POLARIS_HOME`, so the same code runs from a shared kit later and is byte-identical in a vendored
install now (doc-server § 2-3). Doctor gains exactly one line, only when a machine preferences file
exists, so a person can see that one is in play (machine-prefs § 9). The tune-up report's "read
ops/roles/TIDY.md" becomes the command form (doc-server § 6).

### Acceptance
- [ ] doctor-prefs: no machine file → the provenance line absent and the doctor lines the golden samples unchanged; a fixture machine file (POLARIS_PREFS=<path>) → the § 9 line exactly once
- [ ] tune-report differs from base only on the § 6 line
- [ ] no new function definitions (api-kit, lib-census unchanged); startup-budget unchanged
- [ ] every listed $HOME/.claude/polaris code site uses POLARIS_HOME; POLARIS_AWAKE_HOME and POLARIS_HEAVY_DIR still win

## T-340 — "Preferences once, proven on the joined tree - the CLI runs from a kit outside the repo and asks nothing the machine file answers, no kit doc path is left in the prose, every shared golden runs once, version 6.21.0 and its changelog"
points 4 · risk normal · landed fa2bb8a6 (2026-11-24) · claimed 2026-11-24
files touched: CHANGELOG.md, kit/ops/VERSION, kit/ops/hooks/handover-hook.sh, kit/ops/lib/builder.sh, kit/ops/lib/presence.sh, kit/ops/lib/route.sh, kit/ops/lib/visual.sh, kit/ops/selftest-install.sh, ops/contracts/doc-server.md, ops/tests/depth-ui.expected, ops/tests/doc-refs.cmd, ops/tests/doc-refs.expected, ops/tests/express-ui.expected, ops/tests/kit-mode.cmd, ops/tests/kit-mode.expected, ops/tests/pack-visual.expected, ops/tests/qa-parallel.expected, ops/tests/shots-gallery.cmd, ops/tests/shots-gallery.expected

### Why
The release is proven where the seams meet. `kit-mode` runs the CLI from a kit directory outside a
repo that holds only board state (the shape Phase 4 ships): status, role, doc, router, prefs and
`interview --init` all work, and the interview asks nothing the fixture machine file answers.
`doc-refs` proves no kit doc path is left in the prose and that the only printed path left is the
installer's epilogue CI greps. Every golden the waves touched runs once on the joined tree (sprint 27
lesson: two side-by-side cards met at a seam that went red only after both landed). The version goes
to 6.21.0 with a changelog that states only what was measured. Tag, push, `--dogfood` and the
cli-help re-pin stay the conductor's release ritual.

### Acceptance
- [ ] kit-mode and doc-refs per doc-server "Executable checks" (kit-mode includes `interview --init` with a fixture machine file answering voice)
- [ ] every golden in verify green on the joined tree; any re-pin is exactly a contract-pinned line, otherwise hand back
- [ ] api-kit unchanged by this card unless the joined tree shows a contract-pinned row missing
- [ ] VERSION 6.21.0; CHANGELOG `## 6.21.0 — <date>` with measured claims only
