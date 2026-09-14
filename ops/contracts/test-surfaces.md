# CONTRACT: test-surfaces            (v1 — 2026-09-14, plan `spend-less`, 6.4.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
One data file, `ops/SURFACES.tsv`, answers two questions the kit could not answer before: *which tests
cover this path* (so a change to a mapped surface cannot hand off without its tests moving — R2, the
stale-tests gate) and *which tests can this change break* (so `qa` and `land --express` run only those
instead of the whole 729-805s suite — R1, change-scoped selection). Both read the same rows, because
they need the same fact. This contract pins EVERY new name so the six tasks (T-134..T-139) build in
parallel from it — the Sprint-13 api-kit pattern: the golden owner writes the other lanes' rows from
the names here, never from their diffs. Brief: `plans/v3.md`.

## 0. The six decisions (plans/v3.md D1–D6) — pinned
- **D1 — rows come from the Planner, applied by `done`.** A row is a `surface:` frontmatter item
  (§ 3) set at the plan gate; `polaris done` writes it to `ops/SURFACES.tsv` beside `map_delta`.
  No task ever owns the file; no Builder writes a row (a row buys R1's savings and arms R2 against
  you, so the rational Builder move is to write none — the incentive is removed, not policed).
- **D2 — the file is RULES-guarded `path`.** THIS repo arms `ops/SURFACES.tsv<TAB>path<TAB>-` in
  `ops/RULES.tsv` (T-139); fresh repos get the line seeded COMMENTED in the RULES header and INIT
  arms it. `done` writes the file with a shell redirect — the write-time guard sees Edit/Write tools,
  and `check_rules` sees feat-branch diffs — so `done` is unaffected. Consequence: no task in this
  sprint both arms the rule and writes rows; **`ops/SURFACES.tsv` ships header-only** (T-134 creates
  it in W1, T-139 guards it in W3); this repo's own rows arrive next sprint via `surface:`.
- **D3 — no gate on an unmapped surface.** Absent file, empty file, or a changed path with no row ⇒
  the gate is silent. Never build a gate whose cheapest satisfying move is a lie.
- **D4 — the gate is never reached from the write-time guard.** `cmd_guard`/`cmd_rules_check` call
  `rule_scan_*` directly and MUST NOT call `check_rules` or `check_freshness`. The gate runs where a
  whole diff exists: verify · handoff · audit · land — reached through `check_rules` (§ 5).
- **D5 — DECIDED: the stamp records its scope; `finish` accepts a scoped green; nothing that
  publishes reads the stamp.** Checked against the code before accepting the plan's recommendation:
  `cmd_qa` skips on field-1 equality only (observe.sh:1631-1634) and writes `"<sha> <epoch>"`
  (:1694); `suite_stamp_carry` writes the same two fields (integrate.sh:252); `cmd_finish` runs
  `cmd_qa` and never reads the stamp itself (observe.sh:1858); the express drill's format regex is
  END-anchored (history.sh:140 — so it moves in lockstep, § 6). Arithmetic: today an express land is
  ONE full suite (805s serial / 729s sharded here) + a `finish` that skips on the stamp ≈ 805s. If
  `finish` refused a scoped stamp: scoped S + full 805s > 805s — scoping would be inert on the one lane
  a one-line change takes. So `finish` accepts `scoped`, and the third field makes the acceptance
  visible (`finish` prints what was proven). What keeps this honest: NO release step reads the
  stamp — `pack.py --dogfood` runs the full serial `doctor --selftest` (pack.py:270), CI runs it on
  three OSes (ci.yml:502-518, release.yml:79) — and that is pinned below as an invariant, so nobody
  wires a release to the stamp later. Residual risk = a mis-mapped row (D6), caught by CI's full run
  on the sealed push, before any tag.
- **D6 — R1 fails UNSAFE, so health is mandatory.** A wrong `tests` glob skips coverage while
  reporting green. `polaris surfaces` refuses a self-covering row, flags a glob matching 0 or >200
  tracked files, and `drift` carries the refusals as findings (§ 7).

## 1. The data file — `ops/SURFACES.tsv`
TAB-separated, one row per (surface, tests) pair; `#` lines and blank lines ignored; CR stripped.
```
surface<TAB>tests<TAB>cmd<TAB>note
```
| column | meaning |
|---|---|
| `surface` | glob of SOURCE paths, `files_owned` semantics (exact · `dir/` prefix · glob, `*` crosses `/`). One glob per row — a surface needing several globs gets several rows |
| `tests` | glob of the TEST paths covering that surface. A changed `surface` path (with ≥1 added non-comment line) with NO changed path under `tests` is a stale-tests violation |
| `cmd` | the COMPLETE shell command that exercises just this surface, run from the repo root in `$PRIMARY` via `bash -c` — or `-` = derive it from the CONVENTIONS `test_select:` template (§ 2). Only `test:` is ever replaced; lint/typecheck/build/uat stay whole-project |
| `note` | plain English: what this surface is, suffixed by the task that mapped it: `<note> [<ID>]` |
- Repo-state file like `ops/RULES.tsv` — never shipped in `kit/`, never touched by `install.sh`/`update`.
  `.gitattributes` already pins `*.tsv text eol=lf`.
- **Seeded header** (`surfaces_seed`, § 4) — written verbatim when the file is absent, comment lines only:
```
# POLARIS SURFACES — which tests cover which source paths, as data. TAB-separated:
#   surface<TAB>tests<TAB>cmd<TAB>note
#   surface  glob of source paths, files_owned semantics: exact path · dir/ prefix · glob
#   tests    glob of the test paths covering that surface — a changed surface must change these too
#   cmd      the COMPLETE shell command that exercises just this surface (repo root), or `-` =
#            derive from ops/CONVENTIONS.md test_select: ({tests} becomes this row's tests glob)
#   note     plain English: what this surface is [the task that mapped it]
# Read at verify/handoff/audit/land (the stale-tests gate) and by qa / land --express (which tests a
# change can break). Written ONLY by `polaris done`, from a task's `surface:` list — never by hand: a
# row you could delete when it blocked you would guard nothing. Health: ops/polaris surfaces
```
- Absent file ⇒ zero rows everywhere (`surfaces_lines` prints nothing, rc 0). `done` seeds it before
  the first row; `init-board` seeds it for fresh repos; existing repos simply have none until a
  `surface:` task lands.

## 2. CONVENTIONS key — `test_select:` (KEYS.tsv row, T-134)
```
test_select	6.4.0	<cmd or omit>	every change runs the whole test: suite — set a template whose {tests} becomes the matched rows' tests globs, then map surfaces (surface: on tasks) to run only what a change can break
```
(one TAB between columns, exactly as every other row). Semantics:
- **absent or empty ⇒ selection OFF ⇒ `qa`, `land --express`, `finish` are byte-identical to 6.3.**
  This is what lets `update` ship the feature everywhere and change nothing.
- set ⇒ selection ON. Every `{tests}` in the template is replaced by the space-joined distinct `tests`
  globs of the matched `-` rows; a template with no `{tests}` runs verbatim, once. Rows with a complete
  `cmd` ignore the template. This repo (next sprint) will set
  `test_select: bash kit/ops/polaris doctor --selftest --only {tests}` and map rows with complete cmds
  such as `bash kit/ops/polaris doctor --selftest --only express,tcm`.

## 3. Task frontmatter — `surface:` (the ONLY channel into the file)
```
surface:                 # optional; rows `polaris done` appends to ops/SURFACES.tsv (the ONLY writer)
  - <surface-glob> tests: <tests-glob> [cmd: <complete command | ->] [note: <plain English>]
```
Item grammar (`surface_row_from_item`, § 4): the first whitespace-delimited token is the surface;
`tests:` is REQUIRED and its value is the single next token; `cmd:` is optional — its value is
everything after `cmd: ` up to ` note: ` (if present) or the end, trimmed; absent or empty ⇒ `-`;
`note:` is optional — the rest of the line, trimmed; absent ⇒ the task's `title:` (surrounding
double quotes stripped). Keywords appear in the order tests, cmd, note. No TAB anywhere in an item;
no ` #` (frontmatter-lists strips a trailing comment). The written row is
`<surface><TAB><tests><TAB><cmd><TAB><note> [<ID>]`. Examples:
```
  - src/api/ tests: tests/api/ note: the HTTP API           → src/api/	tests/api/	-	the HTTP API [T-9]
  - kit/ops/lib/integrate.sh tests: kit/ops/lib/selftest/history.sh cmd: bash kit/ops/polaris doctor --selftest --only express,tcm note: the integrator lane
```
A malformed item is a `READY GATE` drift finding while the task sits in `ready/` (§ 7) and is
skipped with a `⚠` at `done` (§ 9) — it never blocks a landing.

## 4. The data plane — `kit/ops/lib/core.sh` + entry (T-134, W1)
Global, in `kit/ops/polaris`'s resolve-env block directly under `RULES="$OPS/RULES.tsv"`:
`SURFACES="$OPS/SURFACES.tsv"` (a plain assignment — `startup-budget`'s `cfg-forks-in-globals 0`
stays 0). Loader lists unchanged (no new module). Eight functions in core.sh, ALL pure enough for the
fast tier (no `polaris` re-invocation; `surface_change_set` alone runs git):
```
surfaces_lines                       # normalized SURFACES.tsv: comments/blank/CR stripped. Memoized on
                                     # its OWN sentinel pair `_SURFACES_CACHED` / `_SURFACES_CACHE`
                                     # (declared beside the RULES pair; resettable with _SURFACES_CACHED="").
                                     # Absent file → prints nothing, rc 0. NEVER reuse _RULES_CACHED —
                                     # startup-budget asserts `rules-lines-memoized 3` (grep -c on core.sh)
surfaces_seed [<path>]               # write the § 1 header iff <path> (default $SURFACES) does not exist;
                                     # rc 0 always; never rewrites an existing file
surface_row_matches <path> <row>     # rc 0 when the row's column 1 (a files_owned-style pattern) matches
                                     # <path> — `${row%%<TAB>*}` + match_one, ARGS only: no pipe, no fork
surface_rows_for <path>              # every row (whole TSV line) whose surface matches <path>, in file
                                     # order; rc 0 when ≥1, else rc 1 (prints nothing)
surface_row_from_item <item> <ID> <title>
                                     # § 3 grammar → ONE TSV row on stdout, rc 0. rc 1 + ONE reason line
                                     # on stdout: `needs 'tests: <glob>'` · `empty surface` ·
                                     # `a TAB in the item` · `surface or tests glob is not one token`
surface_change_set [--force]         # the paths a verdict is about, one per line, rc 0 = BOUNDED.
                                     # $PRIMARY HEAD not on $BASE → `git diff --name-only $BASE...HEAD`
                                     # (never consults the stamp). On $BASE → the stamp's sha when it is
                                     # an ancestor of HEAD: `git diff --name-only <sha> HEAD`, and sets
                                     # SURFACE_BASELINE=<sha> SURFACE_BASELINE_SCOPE=<field 3, § 6>;
                                     # --force, no stamp, or a non-ancestor sha → rc 1, prints nothing
                                     # (UNBOUNDED: the caller runs everything). Both cases drop the
                                     # board-noise paths: anything under `$(cfg reports docs/sprints)/`,
                                     # ops/MAP.md, ops/SURFACES.tsv — the same three suite_stamp_carry allows
surface_select_cmd <paths-file>      # rc 0: the commands to run INSTEAD of test:, one per line — every
                                     # distinct non-`-` cmd of the matched rows (first-appearance order),
                                     # then, if any matched row is `-`, ONE line = test_select with every
                                     # {tests} replaced by the space-joined distinct tests globs of those
                                     # rows. rc 1 + ONE reason on stdout, the caller runs test: verbatim:
                                     # `test_select unset` · `no rows` · `no changed paths` ·
                                     # `unmapped: <first path with no row> (+<n> more)`. Selection is
                                     # ALL-OR-NOTHING: one unmapped changed path ⇒ the whole suite (D3)
suite_stamp_scope [<file>]           # field 3 of the stamp (default $PRIMARY/.polaris/suite-stamp):
                                     # `full` | `scoped`; a 2-field (pre-6.4) stamp → `full` — every
                                     # pre-6.4 writer ran everything; missing/empty file → nothing, rc 1
```
- `cmd_init_board` (admin.sh) calls `surfaces_seed` after the RULES seed, and the seeded RULES header
  gains ONE commented example line (after the existing three): `#ops/SURFACES.tsv<TAB>path<TAB>-<TAB>rows come
  from a task's surface: list via polaris done — edit the task, never this file`. Commented, not armed:
  arming it in every drill fixture would make `check_rules` scan (and talk) in every drill.
- THIS repo: T-134 creates `ops/SURFACES.tsv` = the § 1 header, nothing else (board-state write; the
  guard arrives in W3).
- **`usage` (kit/ops/polaris), three hunks, verbatim.** New entry directly AFTER the `rules` line:
```
  surfaces                       list + health-check ops/SURFACES.tsv (which tests cover which
                                 source paths, as data): refuses a row whose tests glob covers its
                                 own surface, flags a glob matching 0 or >200 tracked files. Rows
                                 are written ONLY by `done` from a task's surface: list — never
                                 by hand (RULES-guarded); drift carries the ⛔ findings
```
The `qa` entry becomes:
```
  qa [--force] [--full]          is everything okay, in ONE shot: test/lint/typecheck/build/uat
                                 from CONVENTIONS + drift --strict + doctor env check. Runs every
                                 check even after a red; rc 1 if anything was red.
                                 SKIPS the suite when HEAD is unchanged since the last green run
                                 and the tree is clean (.polaris/suite-stamp) — drift and doctor
                                 still run every time. --force always re-runs the suite.
                                 With test_select: set, test: runs ONLY the SURFACES.tsv commands
                                 the changed paths map to (every changed path needs a row, else
                                 the whole suite runs); the stamp records full|scoped.
                                 --full runs test: verbatim. `finish` runs this for you at the close.
```
The `triage` entry becomes (the substring `1 task ≤3pts` MUST survive — triage-lane counts it):
```
  triage                         which LANE this board's work belongs in — line 1 is one word:
                                 solo (one context, zero subagents; 1 task ≤3pts — or up to 4
                                 tasks, ≤3pts each and ≤6pts in all, worked one at a time — risk
                                 normal, express on, publish direct) · express (one task, one
                                 builder, one integrator) · full (everything else). Reasons follow
                                 on note lines. Decide with this, never by re-reading the board
                                 and weighing the conditions by hand.
```
Dispatch: `surfaces)   cmd_surfaces;;` (no `update_check_maybe`: read-only, drift calls it). Between
W1 and W2 `polaris surfaces` names an undefined function — accepted: nothing calls it before T-136.

## 5. The stale-tests gate — `kit/ops/lib/ownership.sh` + `builder.sh` (T-135, W2)
```
check_freshness <ref> [<ID>]         # rc 0 clean · rc 1 a mapped surface changed and its tests did not
```
- Inert unless `$SURFACES` exists AND has ≥1 row. Same `gdiff` as `check_rules`: `HEAD` resolves in the
  caller's worktree, named refs in `$PRIMARY`; changed = `git diff --name-only "$BASE...$ref"`.
- Per row, over the changed paths: **T** = paths matching `tests` (any change counts — `--name-only`
  lists it); **S** = paths matching `surface`, NOT matching `tests`, whose diff (`-U0`, `^+` minus
  `^+++`, `cut -c2-`) has ≥1 added line that is not blank and whose first non-blank characters are
  not `#` or `//`. Violation ⇔ S non-empty AND T empty. This encodes the plan's table: docs-only /
  comment-only ⇒ no S; the task IS the test task ⇒ T non-empty; new surface, no row ⇒ no row (D3);
  pure refactor ⇒ violation by design.
- **Exemption** = a human's recorded decision, the existing `approved:` path: when
  `ask_approval_covers <p> <ID>` holds for EVERY p in S, the row passes and each clearance is announced
  `⚠ SURFACES exception used — <p> — stale-tests gate on '<surface>' cleared by approved: <entry>`
  (a `note`, riding the handoff report exactly as `RULES exception used` does). Omitted ID or `-` ⇒ no
  approvals apply.
- **Deny shape** (stderr, one line per violating row, then one trailer, then rc 1):
```
⛔ SURFACES stale: <first path in S> changed under '<surface>' but nothing under '<tests>' did — <note>
⛔ SURFACES violation — a mapped surface changed and its tests did not (ops/SURFACES.tsv). Update the tests, or a human records the exception: polaris approve <ID> <surface> -m "why"
```
  `(+<n> more)` follows the path when S has more than one. Clean with rows present ⇒ ONE `say`:
  `surfaces clean: <k> row(s) checked`.
- **Reached through `check_rules`, never by a new call site.** `check_rules <ref> [<ID>]` runs its
  RULES pass exactly as today (its two early returns become plain skips so the freshness pass still
  runs when RULES.tsv is absent/empty), then `check_freshness "$ref" "$id"` — two flags, so the
  `RULES violation` trailer prints only for a RULES failure and never for a freshness one. That gives
  verify · handoff · audit · land the gate with ZERO edits to integrate.sh (T-137 stays parallel) and
  satisfies D4 by construction (`cmd_guard`/`cmd_rules_check` never call `check_rules`). No RULES rule
  and no rows ⇒ byte-identical output to today.
- **startup-budget trap:** `check_freshness` matches with ARGS — `match_one "$p" "$pat"` /
  `owned_match "$p" "$pat"` — NEVER `printf … | owned_match`. `per-rule-match-pipes` stays 0.
- **`cmd_approve` (builder.sh)** widens its no-op precondition to
  `ask_rule_matches "$scope" || surface_rows_for "$scope" | grep -q .`, die text:
  `approve refused: nothing gates '<scope>' — no ask-kind rule in ops/RULES.tsv and no ops/SURFACES.tsv row — approving something ungated is a no-op, nothing written`.
  Everything else (feat/* refusal, per-task per-scope entry, board commit) unchanged.
- **`cmd_pack` (builder.sh)** gains `pack_section "SURFACES — change these, change their tests (ops/SURFACES.tsv)"`
  after KNOWN TRAPS: one line per (owned pattern × covering row) `<surface> → <tests>  (<cmd>)  — <note>`,
  then, when the task carries `surface:` items, `rows done will write for this task:` + each item as
  its TSV row (or `⚠ malformed: <reason>`). The section is OMITTED entirely when nothing applies —
  `pack-visual` and every existing pack output stay byte-identical.
- No other new top-level fn in ownership.sh or builder.sh (T-136 writes the `check_freshness` golden row).

## 6. Selection — `qa` (T-136) and `land --express` (T-137) in lockstep, and stamp v3
Both loops keep their shape; ONLY the `test` iteration changes, and ONLY when `cfg test_select ""` is
non-empty (the one switch). The decision lives in `surface_change_set` + `surface_select_cmd` (§ 4),
so the two loops cannot disagree.
- `qa [--force] [--full]`, flags in any order. `--force` = ignore the stamp (no skip; on `$BASE` also
  no baseline ⇒ whole suite). `--full` = never select (run `test:` verbatim). Skip line becomes
  `suite already green at <sha7> — skipped, proven <scope> (qa --force re-runs it)` (the prefix
  `suite already green at <sha7> — skipped` is grepped by the express drill and MUST survive).
- Change set: `surface_change_set ${force:+--force}`. UNBOUNDED (rc 1) ⇒
  `note "test — running the whole suite: no proven baseline on <BASE> (no stamp, --force, or a stamp that is not an ancestor)"`
  then `test:` verbatim. BOUNDED and EMPTY (only board-noise paths since an ancestor stamp — the
  batch-wave `finish` case) ⇒ the baseline's verdict carries: skip the whole loop with
  `say "suite already green at <baseline7> — only board files changed since; skipped, proven <baseline scope> (qa --force re-runs it)"`
  and re-stamp HEAD with the baseline's scope. BOUNDED and non-empty ⇒ `surface_select_cmd`: rc 1 ⇒
  `note "test — running the whole suite: <reason>"` where `unmapped: <p> (+n more)` is printed as
  `<p> has no ops/SURFACES.tsv row (+n more)` and `no rows` as `ops/SURFACES.tsv has no rows`, then
  `test:` verbatim; rc 0 ⇒ `note "test — scoped to <m> command(s): <n> changed path(s) all mapped (qa --full runs test: verbatim)"`,
  run each command in `$PRIMARY` via `bash -c` in order; first red ⇒ `⛔ test — RED: <that command>`
  + tail, exactly today's red shape; all green ⇒ `say "test — green (scoped: <m> command(s))"` — the
  substring `test — green` is grepped by the qa and express drills and MUST survive.
- lint/typecheck/build/uat: untouched, whole-project, every time.
- **Stamp v3** — `.polaris/suite-stamp` is ONE line `<sha> <epoch> <scope>`, scope ∈ `full` | `scoped`.
  Every 6.4 writer writes the field; readers use `suite_stamp_scope` (2-field ⇒ `full`). `scoped` iff
  the `test` key ran a selection; `full` otherwise (selection off, `--full`, unbounded, unmapped, or
  no `test:` key at all — the last still requires ≥1 suite command to have run, as today).
  `.polaris/last-suite-seconds` unchanged. A chain of scoped stamps (each proven against the previous)
  is accepted — that is the map's assumption, stated once here.
- **`finish`** (T-136): after `qa` green the line becomes `qa green on <BASE> — proven <scope> at <sha7>`
  (plain `qa green on <BASE>` when no stamp exists, e.g. no `test:` key). `finish` never rejects a
  scoped stamp; `finish --force` still forwards `--force`.
- **`land --express`** (T-137): step 3's `test` iteration = the same decision, same lines (its reds go
  to stderr as today). Express never takes `--full`; `qa --full` afterwards is the escape hatch. It
  records `ex_scope` (scoped|full) and calls `suite_stamp_carry "$ex_tested" "$ex_scope"`.
- **`suite_stamp_carry <tested-sha> <scope>`** (T-137): writes `<HEAD> <epoch> <scope>`; an EMPTY
  scope withholds the stamp with the existing `⚠ suite stamp withheld` note (fail closed); the allowed
  since-tested paths become the § 4 board-noise set: `$(cfg reports docs/sprints)/`, `ops/MAP.md`, **and
  `ops/SURFACES.tsv`** (done now writes it after the suite ran). Nothing else changes.
- **Drill lockstep** (T-137 owns `kit/ops/lib/selftest/history.sh`): the express drill's format regex
  becomes `^[0-9a-f]{7,} [0-9]+ full$` (its fixture has no `test_select:`, so express proves full); the
  `EXPRESS CARRY SHA` / `QA SKIP` / `RERUN` assertions are unchanged.
- **Invariant (D5): no publishing step may read the stamp.** `pack.py --dogfood`, CI and the release
  ritual run the full serial suite and stay that way; a future release-side check wanting "full" reads
  its own run, never `.polaris/suite-stamp`.

## 7. `surfaces` + health + `drift` (T-136, observe.sh)
```
surfaces_health                      # stdout: one line per problem  E|W<TAB><row#>|0<TAB><surface>|-<TAB><reason>
                                     # rc = number of E lines (0 = healthy). Row numbers are 1-based over
                                     # surfaces_lines; row 0 = repo-level
cmd_surfaces                         # list + health; rc 1 iff any E
```
Per-row checks: **E** `fewer than 2 columns` (empty surface or tests) · **E** `tests glob covers its own
surface` ⇔ `match_one "<surface>" "<tests>"` (the tests pattern, applied as a files_owned matcher,
covers the surface taken as a path — `src/x.py`+`src/x.py`, `src/x.py`+`src/`, `src/*.py`+`src/`
all refuse; `src/`+`src/tests/` is legal) · **W** `surface matches 0 tracked files` / `tests matches 0
tracked files` / `surface matches <n> tracked files (>200 — too broad to select anything)` — ONE
`git ls-files` fork, then `match_one` per file (builtins) · **W** `cmd is - but test_select: is unset`.
Repo-level (row 0, W): `ops/SURFACES.tsv is not RULES-guarded — arm a path rule so only done writes it`
when no `path` rule covers `ops/SURFACES.tsv` (`rules_gate ops/SURFACES.tsv -` with `RULES_GATE=path`).
`cmd_surfaces` output: no file or no rows ⇒ `note "no surfaces yet — ops/SURFACES.tsv (init-board seeds the header; rows arrive from a task's surface: list when done lands it — never by hand)"`, rc 0.
Else `printf '%-28s %-28s %-32s %s\n' SURFACE TESTS CMD NOTE`, one row per line, each problem
indented under its row as `   ⛔ <reason>` / `   ⚠ <reason>`, row-0 warnings after the table, then the
tail line `✅ <n> surface row(s), all healthy` (rc 0; ` · <w> warning(s)` appended when W>0) or
`⛔ <n> surface row(s), <e> unhealthy` (rc 1). Mirrors `cmd_rules` / `rules-health`.
**drift:** (a) per E line, `finding "SURFACES: row <n> '<surface>' — <reason> (ops/polaris surfaces)"`;
warnings are never findings (a rename window must not red every wave gate). (b) READY GATE: for every
`ready/` task and every `surface:` item, `surface_row_from_item` rc 1 or a self-covering pair ⇒
`finding "READY GATE: <ID> surface: '<item>' — <reason> — fix the item before a builder claims it"`.
The clean line `drift: board clean (…)` is NOT changed.

## 8. `triage` prices contexts, not tasks (T-136) — and the `express:` default
Cold start ≈ 7,300 tokens per context (cmd_triage's own comment). A `full` wave for n tasks opens
n+3 contexts (conductor, planner, n builders, integrator). Rules, in order:
- n = 0 ⇒ `full` (unchanged). n = 1 ⇒ unchanged, including the literal `[ "$pts" -le 3 ]` solo cap —
  the spelling `pts" -le 3 ]` MUST occur exactly once (triage-lane counts it).
- n > 1: any task in `active/` ⇒ `full`, note `<k> task(s) already active — another lane is building; parallel lanes are the point` ·
  any task failing a per-task gate (risk ≠ normal · non-numeric points · owns a RULES `path` scope or an
  unapproved `ask` scope) ⇒ `full`, note `<ID>: <why>` (first offender; same wording as today's single-task
  notes) · `express: off` or `publish: ≠ direct` ⇒ `full` as today · every task ≤3 pts AND n ≤ 4 AND
  Σpts ≤ 6 ⇒ **`solo`**, note
  `<n> tasks · <P> pts ≤ 6 — one context (~7,300 tokens cold start) beats a full wave's <n+3> contexts (~<(n+3)×7300> tokens); work them one at a time: claim → build → land --express → next` ·
  otherwise ⇒ `full`, note `<n> claimable tasks · <P> pts — over the solo budget (4 tasks / 6 pts / 3 pts each); parallel lanes are the point`.
- `cfg express on` → `cfg express auto` in cmd_triage (integrate.sh:375 and KEYS.tsv already say `auto`;
  the note text `express on` is prose and stays).
- `triage-lane.cmd/.expected` (T-136 owns): every existing line kept; append the multi-task cases —
  two 1-pt ready tasks ⇒ `solo` + a note containing `≤ 6`; four 2-pt ⇒ `full` + `over the solo budget`.

## 9. `done` writes the rows (T-137, integrate.sh)
- BEFORE the `mv`: `fm_list surface "$tf"` → each item through `surface_row_from_item "$item" "$id" "$title"`;
  rc 1 ⇒ `note "⚠ surface row skipped: <item> — <reason>"`; self-covering (§ 7 test) ⇒
  `… — tests glob covers its own surface`; an identical (surface, tests) pair already in the file ⇒
  `… — already mapped to <tests>`. Never a die: a row never blocks a landing.
- Any row to write ⇒ the same on-`$BASE` requirement as `map_delta` (die names surface rows too).
- After map_delta application: `surfaces_seed`, then append each row with `printf '%s\n'`. ONE base
  commit, same index.lock retry: when map deltas were applied the existing `docs(map): <ID> <first>`
  commit's pathspec gains `$OPS/SURFACES.tsv`; rows only ⇒ `docs(surfaces): <ID> <first row's surface>`
  over `$OPS/SURFACES.tsv` alone. No rows ⇒ byte-identical to today.
- No new top-level fn in integrate.sh (parsing lives in core.sh).

## 10. Tests (T-138, W3) — `policy.sh` · `spine.sh` · `fast.sh`
- `drill_surfaces` in `kit/ops/lib/selftest/policy.sh`, label `surfaces` appended at the END of
  `SELFTEST_LABELS` (`… autoupdate surfaces`), gate placed directly after the `rules` gate. Hermetic:
  restores `ops/SURFACES.tsv` to header-only, removes its CONVENTIONS keys, tasks, branches and stamp.
  Assertions are rc + file state + qa's own report lines, never qa's rc (T-131). Minimum set:
  1. after init-board the fixture's `ops/SURFACES.tsv` exists, first line starts `# POLARIS SURFACES`;
     `surfaces` prints `no surfaces yet`, rc 0.
  2. a task with `surface: - src/sf/ tests: tests/sf/ cmd: sh -c "echo MAPPED >> <T>/sf.ran" note: the sf surface`
     claimed, built (src/sf/a.txt + tests/sf/a_test.txt), verified, handed off, landed, sealed, done ⇒
     the file has exactly one non-comment row `src/sf/<TAB>tests/sf/<TAB>sh -c …<TAB>the sf surface [<ID>]`
     and base HEAD's subject starts `docs(surfaces): <ID>`.
  3. a second task owning both dirs: src-only change ⇒ `verify` rc 1, stderr has `SURFACES stale: src/sf/a.txt changed under 'src/sf/'`;
     `handoff` rc 1, task still in active/; add a tests/sf/ change ⇒ `verify` rc 0, stdout has
     `surfaces clean: 1 row(s) checked`.
  4. comment-only added line under src/sf/ ⇒ `verify` rc 0.
  5. src-only change + `approve <ID> src/sf/ -m drill` from the primary (no ask rule — the row gates it)
     ⇒ `verify` rc 0, output has `SURFACES exception used`; on feat/* the approve still refuses.
  6. selection: `test: sh -c "echo FULL >> <T>/sf.ran"` + `test_select: sh -c "echo TPL {tests} >> <T>/sf.ran"`;
     an ancestor stamp `<HEAD~1> <epoch> full` + a mapped change ⇒ `qa` output has `test — green (scoped: 1 command(s))`,
     sf.ran gained MAPPED and not FULL, stamp is `<HEAD> <epoch> scoped`; an unmapped change ⇒ output has
     `running the whole suite` and FULL ran, stamp ends ` full`; `qa --full` on a mapped change ⇒ FULL ran;
     `qa` with stamp = HEAD ⇒ skip line contains `proven full`; a by-hand `-` row + its change ⇒ sf.ran
     gained `TPL tests/tpl/`.
  7. health: a by-hand self-covering row ⇒ `surfaces` rc 1 and last line starts `⛔`; `drift` prints
     `SURFACES: row`; `drift --strict` rc 1; row removed ⇒ `drift` clean.
- `fast.sh` sections INSIDE `selftest_fast` (no new top-level fn): `surfaces-tsv` · `surfaces-match` ·
  `surfaces-select` · `surfaces-item` · `stamp-scope`, ≥4 asserts each (fixtures under `$FT_TMP`,
  `SURFACES`/`CONV` overridden inside the section subshell, `_SURFACES_CACHED=""` between cases).
- Budget ~44s for the drill; re-measure CONVENTIONS' `test:` comment afterwards (Integrator/EVOLVE).

## 11. Goldens — ONE owner per wave, deltas pinned BYTE-EXACT
`ops/tests/api-kit.expected` (installed `find --api 'kit/*'`; a worktree-honest diff is
`POLARIS_ROOT=$PWD python kit/ops/index.py find --api 'kit/*' | grep -v '^kit/\.claude/skills/i-have-adhd/' | diff - ops/tests/api-kit.expected`,
verified empty on base 2026-09-14). Sorted into place by content diff; an unexpected hunk is a STOP.
- **W1 owner T-134**: `kit/ops/KEYS.tsv	key	test_select` · `kit/ops/lib/core.sh	fn	suite_stamp_scope` ·
  `surface_change_set` · `surface_row_from_item` · `surface_row_matches` · `surface_rows_for` ·
  `surface_select_cmd` · `surfaces_lines` · `surfaces_seed`. Nothing else under kit/ moves in W1.
- **W2 owner T-136**: its own `kit/ops/lib/observe.sh	fn	cmd_surfaces` + `surfaces_health`, and
  T-135's pinned `kit/ops/lib/ownership.sh	fn	check_freshness`. T-135 and T-137 add NO other
  top-level fn and no heading.
- **W3 owner T-139**: T-138's pinned `kit/ops/lib/selftest/policy.sh	fn	drill_surfaces` (T-138 adds no
  other fn); T-139 itself adds ZERO headings anywhere under kit/ — every prose edit is a paragraph,
  list item, step or table row.
- `ops/tests/cli-help.expected`: touched by NO task. Its `.cmd` runs the INSTALLED `ops/polaris help`,
  which changes only at the release dogfood; it regenerates there (`check --only cli-help --update`
  after a line-by-line review — the conductor's release step, CONVENTIONS § Release ritual). Until then
  `bash kit/ops/polaris help | diff - ops/tests/cli-help.expected` differs by EXACTLY the three § 4
  hunks; a fourth is a defect.
- `ops/tests/rules-health.expected` → `✅ 16 rule(s), all healthy` (T-139, with the RULES line).
- `ops/tests/triage-lane.*` → T-136 (§ 8). `startup-budget`, `guard-denies`, `keys-drift`, `adopt-stub`,
  `plain-voice`, `output-style-installed`, `pack-visual`, `cli-help-parity` (do NOT add `surfaces` to its
  list): unchanged and green.
- Drill fixtures gain a header-only SURFACES.tsv and no `test_select:`, so every existing drill stays
  byte-identical (the spine commits after init-board; `QUIET CLEAN` holds).

## 12. Prose (T-139, W3) — the "stop asking" half; no new heading anywhere
- **CONDUCTOR.md step 2.5** no longer restates any condition or point threshold: run
  `bash ops/polaris triage`, branch on line 1 — `solo` ⇒ ONE subagent kicked off "You are SOLO"
  (it stops after its last `land --express`; the conductor runs `finish`) · `express` ⇒ the existing
  express choreography verbatim (`small change — taking the express lane`, one builder → one
  integrator with `land --express <ID>`, conductor runs `finish`, skip scout + EVOLVE) · `full` ⇒
  steps 3–8, silently. `grep -nE '≤ ?[0-9]+ points|<= ?[0-9]+ points' kit/ops/roles/CONDUCTOR.md` finds nothing.
- **kit/CLAUDE.md** § STOP AND ASK, after the `Not on it:` line, verbatim:
  `**Never offer a menu of execution strategies.** How many builders, one chat or several, board or no board, which lane — these are `triage`'s answer, never a question. The interview (0b) is about the PRODUCT. The moment a question is about how POLARIS itself will run, the CLI already answered it and you are asking anyway.`
  Invariant 1's `polaris verify` clause gains: `…AND that every mapped surface it changed moved its tests too (`ops/SURFACES.tsv`)`. Net ≤ +4 lines.
- **kit/.claude/output-styles/polaris.md**: the same paragraph directly after the numbered discipline
  list — a paragraph, NOT rule 8 (`output-style-installed` counts rules; `plain-voice` diffs the
  numbered lines against PROTOCOL § VOICE).
- **PLANNER.md**: 0b gains one line `**Never offer a menu of execution strategies** — lanes, builder counts, one chat or several are `triage`'s answer; every question here is about the PRODUCT.`;
  new step **5b. Map the surfaces.** — for every task whose `files_owned` touch code with tests set
  `surface:` (§ 3 grammar); the ONLY way rows reach `ops/SURFACES.tsv`; `done` writes them; `polaris
  surfaces` shows the map; `drift` refuses a malformed item at the ready gate.
- **BUILDER.md / SOLO.md**: `verify` also refuses a change to a mapped surface whose tests did not
  change (`⛔ SURFACES stale`) — update the tests; a genuine exception is a human's
  `polaris approve <ID> <surface> -m "why"`, never a row edit; `ops/SURFACES.tsv` is written only by
  `done`; a wrong or missing row → one IDEAS.md line or a `surface:` proposal in Notes. SOLO.md also:
  triage may hand you up to 4 small tasks (≤6 pts in all) — work them ONE AT A TIME (claim → build →
  `land --express` → `polaris next`), `finish` once at the end; entered as a conductor's subagent ⇒ stop
  after the last land, the conductor runs `finish`.
- **INTEGRATOR.md**: `audit`/`land` run the stale-tests gate too; a `SURFACES exception used` line is a
  human's recorded decision — carry it into the report; `done` writes `surface:` rows and commits them on
  base (`docs(surfaces):`, or riding `docs(map):`).
- **INIT.md**: `init-board` also seeds `ops/SURFACES.tsv`; arm the commented `ops/SURFACES.tsv` RULES
  line (delete its leading `#`) as part of turning answers into armed lines.
- **templates/TASK.md**: the § 3 two-line `surface:` field after `map_delta:`.
- **PROTOCOL.md**: THE TOOL row `drift / rules` → `drift / rules / surfaces` (+ health phrase); the `qa`
  row gains the `test_select:` sentence; **MANUAL.md** § Ownership + RULES proof gains the by-hand
  freshness proof (§ 5 algorithm in prose) and the `done` recipe gains the rows commit.
- **ops/RULES.tsv** (this repo): `ops/SURFACES.tsv<TAB>path<TAB>-<TAB>rows are written only by polaris done from a task's surface: list — edit the task, never this file`
  with a `#` comment naming who/why (Invariant 11).

## Invariants
1. `test_select:` absent ⇒ `qa`, `land --express`, `finish` byte-identical to 6.3 (selection OFF).
2. No rows (absent or header-only file) ⇒ the stale-tests gate is silent everywhere (D3).
3. Selection is all-or-nothing per change set: one unmapped changed path ⇒ the whole `test:` runs.
4. Only `test:` is ever replaced; lint/typecheck/build/uat run whole-project, every time.
5. `.polaris/suite-stamp` = `<sha> <epoch> <scope>`; every 6.4 writer writes the scope; 2-field ⇒ `full`.
6. NO publishing step (dogfood, CI, release) reads the stamp — the full serial suite is its own proof.
7. Rows are written only by `done`; the file is RULES `path`-guarded; an exemption is `polaris approve`.
8. `check_freshness` is reached only through `check_rules` (verify · handoff · audit · land), never from
   `cmd_guard`/`cmd_rules_check` (D4); it matches with args, never a pipe (startup-budget).
9. `surfaces_lines` memoizes on `_SURFACES_CACHED` — `rules-lines-memoized 3` stays 3.
10. Bash ≥ 3.2: no `case` inside `$(...)`, no `mapfile`, no assoc arrays.
11. One api-kit owner per wave (§ 11); surface-frozen tasks add no fn and no heading.

## Executable check
- Fast tier (T-138, every change): `bash kit/ops/polaris doctor --fast` — sections § 10.
- Drill (T-138, wave gate + CI): `bash kit/ops/polaris doctor --selftest --only surfaces` (≥ 600000 ms
  timeout or `bg run`); the express drill's regex (T-137) proves the carried `full` stamp.
- Goldens: `bash kit/ops/polaris check` — `startup-budget` (memo count + no pipes), `triage-lane`
  (T-136), `rules-health` (T-139), `api-kit` (per-wave owner).

## Example
```
$ bash ops/polaris surfaces
SURFACE                      TESTS                        CMD                              NOTE
kit/ops/lib/integrate.sh     kit/ops/lib/selftest/history.sh bash kit/ops/polaris doctor --selftest --only express,tcm the integrator lane [T-140]
✅ 1 surface row(s), all healthy
$ bash ops/polaris verify           # integrate.sh changed, history.sh did not
⛔ SURFACES stale: kit/ops/lib/integrate.sh changed under 'kit/ops/lib/integrate.sh' but nothing under 'kit/ops/lib/selftest/history.sh' did — the integrator lane [T-140]
⛔ SURFACES violation — a mapped surface changed and its tests did not (ops/SURFACES.tsv). Update the tests, or a human records the exception: polaris approve T-141 kit/ops/lib/integrate.sh -m "why"
$ bash ops/polaris qa               # on integrate/2026-10-01, test_select: set
   test — scoped to 1 command(s): 2 changed path(s) all mapped (qa --full runs test: verbatim)
✅ test — green (scoped: 1 command(s))
…
$ cat .polaris/suite-stamp
3f9c2a1e… 1790000000 scoped
$ bash ops/polaris finish
✅ qa green on main — proven scoped at 3f9c2a1
```

## Changelog
- v1 2026-09-14: created for T-134 (data plane) · T-135 (gate) · T-136 (selection · surfaces · drift ·
  triage) · T-137 (express · carry · done) · T-138 (tests) · T-139 (prose · RULES · goldens W3).
  Extends verification-tiering.md v2 (stamp gains field 3) and ask-approval.md (approve's precondition
  widens to SURFACES rows).

## v2 — ACTIVATION (2026-09-14, Sprint B of plan `spend-less`, 6.4.0)
v1 shipped the machinery and, by design, changed nothing anywhere: `test_select:` unset and a
header-only map ⇒ byte-identical to 6.3. `update --auto` therefore delivers 6.4.0 to every installed
repo and makes none of them faster. This section is the activation: POLARIS proposes a repo's map
ITSELF from the stack's own layout, writes only the unambiguous subset, and says exactly what it did.
Governing constraint (plans/v3.md § B0, D6): a MIS-mapped row skips coverage while reporting green,
so the generator is conservative BY CONSTRUCTION — unambiguous pairings only, over-select in doubt,
`test_select:` only where the runner provably takes path arguments, and nothing on the release/CI
path reads any of it (Invariant 6 stands). A scaffold that guesses to look useful is worse than one
that emits three rows and admits the rest. Tasks: T-140 (engine + entry, W1) · T-142 (command +
nudges, W2) · T-144 (tests, W3) · T-145 (prose, W3). The sprint's other seams — the interview, the
machine arming, `board_pull` — live in `ops/contracts/first-run.md`; the loader change in
`ops/contracts/module-layout.md` v6. Every name below is pinned so the waves build in parallel.

### 13. The engine — NEW module `kit/ops/lib/surfaces.sh` (T-140, W1; ≤ 350 lines, EXACTLY 3 top-level fns)
Pure: reads `$PRIMARY/<manifest>` files and a tracked-file LIST it is handed — never `git` itself,
never `$SURFACES` (the caller passes the map), never the network. Every function is fast-tier
testable with `PRIMARY` pointed at a fixture dir and the list a hand-written file. Loader: the
FULL `_mods` list in `kit/ops/polaris` gains `surfaces` between `workspace` and `builder`; the
`_match|_rules|_guard` list stays EXACTLY `core ownership` (module-layout.md v6). Matching uses
`match_one <path> <pattern>` with ARGS (ownership.sh) — never a pipe (startup-budget). Helpers, if
any, are inlined or nested INSIDE these three (the golden `api-kit` records column-0 definitions).

```
surfaces_runner <ls-file>            # stdout ONE line `<runner><TAB><template>`, rc 0 — or nothing, rc 1
                                     # (no runner this contract knows how to scope). Detection ORDER,
                                     # first match wins, over the list + the manifests it names:
                                     #   node   `package.json` in the list AND, by grep on that file:
                                     #          "test" script value contains `vitest` → vitest ·
                                     #          contains `jest` → jest · else a `"vitest"` key → vitest ·
                                     #          a `"jest"` key → jest · else NOT node (fall through)
                                     #            vitest → `npx vitest run {tests}` · jest → `npx jest {tests}`
                                     #   pytest `pytest.ini` in the list · any `conftest.py` in the list ·
                                     #          `pyproject.toml` containing `[tool.pytest` · `setup.cfg`
                                     #          containing `[tool:pytest]` · ≥1 list path matching
                                     #          `^(tests?/|.*/tests?/).*test_[^/]*\.py$`   → `pytest {tests}`
                                     #   go     `go.mod` in the list                        → `go test ./...`
                                     #          (go takes PACKAGE paths, never test-file paths: the
                                     #          template is the whole suite — over-selection by design —
                                     #          and every scaffolded Go row carries a COMPLETE cmd)
                                     # grep only, no python, bash 3.2. mocha · cargo · dotnet · rspec ·
                                     # make · a bare `npm test` with an unknown script ⇒ rc 1: each of
                                     # those either filters by NAME, not path, or cannot be proven to
                                     # take a path — so the command says NORUNNER instead of guessing
surfaces_pairs <runner> <ls-file>    # stdout: candidate rows `<surface><TAB><tests><TAB><cmd><TAB><note>`,
                                     # sorted by surface (LC_ALL=C), rc 0 always. Rules below
surfaces_proposal <ls-file> [<map-file>]
                                     # the whole decision as DATA, rc 0 always; lines in this order:
                                     #   RUNNER<TAB><runner><TAB><template>     — or, as the ONLY line:
                                     #   NORUNNER<TAB>no test runner this kit can scope (pytest · jest · vitest · go) — seen: <manifests>
                                     #   ROW<TAB><surface><TAB><tests><TAB><cmd><TAB><note>   (survivors, sorted)
                                     #   SKIP<TAB><what><TAB><reason>                          (one per dropped pairing)
                                     # <manifests> = the space-joined subset of `package.json pyproject.toml
                                     # setup.cfg pytest.ini go.mod Cargo.toml Makefile Gemfile` present in
                                     # the list, else `no manifest`. <map-file> supplies existing rows
                                     # (caller passes $SURFACES when it exists; absent ⇒ none)
```
**Pairing rules (`surfaces_pairs`) — a row appears ONLY when the stack's own convention implies it;
anything else is not a row (D3's principle applied to a generator).** `<name>` is used verbatim:
no case-folding, no singular/plural guessing. `<dir>` never has a leading `./`; the repo root is
never a surface. A "source dir" is a directory in the list holding ≥ 1 path, of ≤ 3 components,
whose basename is not one of `tests test __tests__ spec __mocks__ node_modules`.
- **pytest** (a) `tests/<name>/` or `test/<name>/` (≥ 1 tracked path) ↔ EXACTLY ONE source dir of
  basename `<name>` outside the tests tree → `<dir>/<TAB>tests/<name>/<TAB>pytest tests/<name>/<TAB><name> tests`;
  (b) `tests/…/test_<name>.py` ↔ EXACTLY ONE list path `**/<name>.py` outside the tests tree →
  `<that path><TAB>tests/…/test_<name>.py<TAB>pytest tests/…/test_<name>.py<TAB><name>`;
  (c) in-package `<dir>/tests/` ↔ its parent source dir `<dir>/` →
  `<dir>/<TAB><dir>/tests/<TAB>pytest <dir>/tests/<TAB><basename of dir> tests`.
- **jest / vitest** (`<run>` = `npx jest` | `npx vitest run`): (a) `<dir>/__tests__/` ↔ its parent
  source dir → `<dir>/<TAB><dir>/__tests__/<TAB><run> <dir>/__tests__<TAB><basename> tests`;
  (b) `tests/<name>/` · `test/<name>/` · `__tests__/<name>/` ↔ EXACTLY ONE source dir of basename
  `<name>` → as pytest (a) with `<run> tests/<name>`; (c) co-located: every source dir `<dir>`
  holding ≥ 1 list path `<dir>/*.test.<ext>` (ext ∈ js jsx ts tsx mjs cjs) →
  `<dir>/<TAB><dir>/*.test.*<TAB><run> <dir><TAB><basename> co-located tests`; the same for `*.spec.<ext>`
  with tests glob `<dir>/*.spec.*` (both present ⇒ two rows).
- **go** every dir holding ≥ 1 list path `*_test.go` →
  `<dir>/<TAB><dir>/*_test.go<TAB>go test ./<dir>/...<TAB><basename> package tests`.
- **Shared filters, applied by `surfaces_pairs` AFTER the per-stack rules, in this order over the
  candidates sorted by surface:**
  1. AMBIGUITY (the `EXACTLY ONE` clauses): 0 or ≥ 2 matching source dirs/paths ⇒ no row; reported
     by `surfaces_proposal` as `SKIP<TAB><tests-path><TAB>ambiguous: <name> matches <n> dirs (<d1> <d2> …)`
     (dirs sorted, LC_ALL=C; `0` ⇒ `ambiguous: <name> matches 0 dirs`).
  2. BREADTH: a surface matching > 200 list paths is dropped —
     `SKIP<TAB><surface><TAB>surface matches <n> paths (>200)` — its descendants may qualify alone.
  3. ANCESTOR: a candidate whose surface has an already-emitted surface as a prefix is dropped; ALL
     such drops collapse into ONE line `SKIP<TAB><n> narrower pairing(s)<TAB>covered by an emitted ancestor row`.
  4. every emitted surface and tests glob matches ≥ 1 list path; no TAB in any column.
  `surfaces_pairs` emits the SKIP lines too (they are decisions, as data); `surfaces_proposal` then
  drops, per row, an identical (surface, tests) pair already in `<map-file>`
  (`SKIP<TAB><surface><TAB>already mapped to <tests>`) and a self-covering pair (`match_one <surface>
  <tests>` — surfaces_health's exact test; `SKIP<TAB><surface><TAB>tests glob covers its own surface`).
  Determinism is an invariant: same (manifests, list, map) ⇒ same bytes. ONE `git ls-files` per
  command, run by the CALLER (§ 14).

### 14. `surfaces --scaffold [--apply]` — `cmd_surfaces` in observe.sh (T-142, W2)
**Usage entry** (kit/ops/polaris — T-140 writes it in W1 from here; the v1 § 4 `surfaces` lines are
REPLACED by these, verbatim; the `qa` and `triage` entries of v1 § 4 are unchanged):
```
  surfaces [--scaffold [--apply]]
                                 list + health-check ops/SURFACES.tsv (which tests cover which
                                 source paths, as data): refuses a row whose tests glob covers its
                                 own surface, flags a glob matching 0 or >200 tracked files. Rows
                                 are written ONLY by `done` from a task's surface: list, or by
                                 --scaffold --apply — never by hand (RULES-guarded); drift carries
                                 the ⛔ findings. --scaffold PROPOSES rows from the stack's own
                                 layout (pytest · jest · vitest · go): only pairings the layout
                                 makes unambiguous, over-selecting in doubt, the ambiguous ones
                                 listed as skipped; writes nothing. --apply writes those rows
                                 (tagged [scaffold]) and sets test_select: when it is unset — on
                                 <base> only; nothing is committed for you
```
Dispatch: `surfaces)   shift 2>/dev/null || true; cmd_surfaces "$@";;` (still no `update_check_maybe`).
Flags: none · `--scaffold` · `--scaffold --apply`; anything else ⇒ `die "usage: polaris surfaces [--scaffold [--apply]]"`.
Plain `surfaces` is byte-identical to v1 § 7.

**`surfaces --scaffold`** (propose; writes nothing, ever): `git -C "$PRIMARY" ls-files` → temp file →
`surfaces_proposal <tmp> [$SURFACES]`. Rendering, stdout:
- NORUNNER ⇒ `note "<the NORUNNER text>. Map rows by hand: a task's surface: items (ops/roles/PLANNER.md step 5b)"`, rc 0.
- else `note "runner: <runner> — test_select: <template>"`, then `printf '%-28s %-28s %s\n' SURFACE TESTS CMD`
  and one such line per ROW, then one `   ⚠ skipped: <what> — <reason>` per SKIP, then the tail:
  `say "<n> row(s) proposed · <s> skipped — write them: ops/polaris surfaces --scaffold --apply"` (n ≥ 1) ·
  `note "nothing to propose — <s> pairing(s) skipped, listed above"` (n = 0, s ≥ 1) ·
  `note "nothing to propose — no pairing the layout makes unambiguous (map rows by hand: surface: items)"` (n = s = 0).
  rc 0 in every case. `<s>` = the number of SKIP lines.

**`surfaces --scaffold --apply`** — the SECOND sanctioned writer (§ 16):
- REFUSES on any `feat/*` branch: `die "surfaces --scaffold --apply runs on $BASE only — from a task, rows are surface: items (polaris done writes them)"`;
  REFUSES without `$CONV`: `die "no ops/CONVENTIONS.md — run INIT first; the scaffold sets test_select: in it"`.
- n = 0 ⇒ the same `nothing to propose` note, rc 0, no write.
- else, through the helper **`surfaces_apply <proposal-file>`** (the ONLY new top-level fn in
  observe.sh): `surfaces_seed`; append each ROW as `<surface><TAB><tests><TAB><cmd><TAB><note> [scaffold]`
  with `printf '%s\n' >> "$SURFACES"`; then `test_select:` in `$CONV` —
  a LIVE `^test_select:` line (any value, even empty) ⇒ untouched, reported `kept (already set here)` ·
  a stub `^#[[:space:]]*test_select:` ⇒ replaced IN PLACE by
  `test_select: <template>   # set by surfaces --scaffold --apply: {tests} = the changed rows' tests globs; delete this line to run the whole test: suite on every change` ·
  neither ⇒ that line appended at the END (after one blank line). Temp file + `mv`, LF kept, never `sed -i`.
- Tail: `say "<n> row(s) written to ops/SURFACES.tsv · test_select: <set|kept (already set here)>"` then
  `note "review, then commit ops/SURFACES.tsv ops/CONVENTIONS.md — nothing was committed for you"`. rc 0.
- Idempotent: a second run proposes nothing (`already mapped`) and writes nothing.

### 15. The activation nudges — where a repo learns its map is empty (T-142; prose T-145 § 19)
Three moments, three one-liners, ALL gated on `surfaces_runner` rc 0 (a repo the scaffold cannot
help is never nagged — THIS repo, bash + drills, stays silent) AND on `surfaces_lines` printing no row:
- **`doctor`**: directly AFTER the CONFIG DRIFT block, only when `$CONV` exists and `cfg test` is
  non-empty: `note "surfaces: none mapped — every change runs the whole test: suite; propose a map: ops/polaris surfaces --scaffold"`.
  Directly after it, the first-run.md § 2 preferences line (guarded: `command -v interview_pending`).
- **`qa`**: after the `last-suite-seconds` write, only when the `test` key ran (`ran ≥ 1`), no
  selection happened, and `t1 - t0 ≥ 60`:
  `note "test — ran the whole suite (<t1-t0>s). A surface map runs only what a change can break: ops/polaris surfaces --scaffold"`.
- **role prose** (§ 19): PLANNER step 5b · INIT step 3 · the install skill § Update.
NOT a nudge site: `update --auto` (auto-update.md: one pinned line, never more) and `update`'s
explicit epilogue — `cmd_update` re-execs from a tmp copy of the PRE-update lib, so a 6.3→6.4 update
could never print it; dropped rather than shipped inert (IDEAS.md records it).
Drill safety: every existing fixture has no manifest ⇒ `surfaces_runner` rc 1 ⇒ all three silent;
the drills that grep doctor (`brain`, the knob, CLAUDE.md and self-hosting checks) and qa
(`test — green`, `suite already green`, `running the whole suite`) lines are unaffected.

### 16. Amendments to v1 (append-only; v1 stands, these override where they overlap)
- **D1 / D2 / Invariant 7 — TWO writers now:** `polaris done` (a task's `surface:` items) and
  `surfaces --scaffold --apply` (on `<base>` only, rows tagged `[scaffold]`, unambiguous pairings
  only). Both write with a shell redirect; the RULES `path` guard still denies every hand edit and
  every feat-branch diff. THIS repo's RULES line message becomes
  `rows are written only by polaris done (a task's surface: list) or surfaces --scaffold --apply — edit the task, never this file`
  (Planner-written with the plan under Invariant 11). The init-board seeded example line and the
  `surfaces_seed` header (§ 1) are NOT changed — "never by hand" is still exactly true.
- **§ 11's cli-help sentence:** until the release dogfood, `bash kit/ops/polaris help | diff - ops/tests/cli-help.expected`
  differs by exactly the v1 § 4 hunks PLUS the § 14 `surfaces` hunk PLUS first-run.md § 2's
  `interview` hunk; anything else is a defect. `cli-help-parity`'s 10-command list is not extended.
- **Invariant 1** (`test_select:` absent ⇒ OFF) is unchanged — `--apply` is what sets it, only where
  it derived a template; nothing in the kit derives selection from rows alone.

### 17. Tests (T-144, W3) — `fast.sh` sections · the `surfaces` drill · one new golden (T-142, W2)
- **NEW golden `ops/tests/surfaces-scaffold.cmd/.expected`** (T-142 owns; hermetic — throwaway repos,
  run from inside them, the adopt-stub pattern; every fixture COMMITS its files, the list is
  `git ls-files`; `KIT="$(pwd)/kit/ops/polaris"`). Cases, each its own fixture:
  1. **pytest:** `pyproject.toml` containing `[tool.pytest.ini_options]` · `src/api/x.py` · `src/db/y.py` ·
     `src/util.py` · `src/common/a.py` · `lib/common/b.py` · `tests/api/test_x.py` · `tests/db/test_y.py` ·
     `tests/test_util.py` · `tests/common/test_a.py` · `README.md`; `init-board`; a CONVENTIONS with
     `test: pytest -q`. `--scaffold` ⇒ runner pytest, template `pytest {tests}`, FOUR rows —
     `src/api/`↔`tests/api/` · `src/common/a.py`↔`tests/common/test_a.py` · `src/db/`↔`tests/db/` ·
     `src/util.py`↔`tests/test_util.py` — and TWO skips: `tests/common/ — ambiguous: common matches 2 dirs (lib/common src/common)`
     and `2 narrower pairing(s) — covered by an emitted ancestor row`; rc 0; the map still header-only.
     `--scaffold --apply` ⇒ 4 `[scaffold]` rows, `test_select: pytest {tests}` appended (the pinned
     comment), the review note; `surfaces` ⇒ `✅ 4 surface row(s), all healthy`; again ⇒ `nothing to
     propose — 4 pairing(s) skipped, listed above` and the two files byte-identical; a stub
     `# test_select: x` in a fresh copy ⇒ replaced in place; a live `test_select: custom` ⇒ kept and
     said; from `git checkout -b feat/T-X` ⇒ rc 1 + the refusal.
  2. **jest:** `package.json` = `{"scripts":{"test":"jest"}}` · `src/foo/a.ts` · `src/foo/__tests__/a.test.ts` ·
     `src/bar/b.ts` · `src/bar/b.test.ts` ⇒ runner jest, template `npx jest {tests}`, rows
     `src/bar/`↔`src/bar/*.test.*` (`npx jest src/bar`) · `src/foo/`↔`src/foo/__tests__/` (`npx jest src/foo/__tests__`),
     one skip `1 narrower pairing(s)`.
  3. **go:** `go.mod` · `internal/foo/x.go` · `internal/foo/x_test.go` · `cmd/app/main.go` ⇒ one row
     `internal/foo/`↔`internal/foo/*_test.go` cmd `go test ./internal/foo/...`, template `go test ./...`, 0 skips.
  4. **no runner:** `Makefile` · `bin/tool.sh` ⇒ the NORUNNER note with `seen: Makefile`, rc 0; `--apply` writes nothing.
  5. **breadth:** `package.json` with `"test":"vitest"` · `src/a.js` · `src/a.test.js` · 250 tracked
     `src/gen/g<n>.js` ⇒ runner vitest, `src/ — surface matches 252 paths (>200)`, `nothing to propose — 1 pairing(s) skipped, listed above`.
- **`fast.sh` sections INSIDE `selftest_fast`** (no new top-level fn): `surfaces-runner` ·
  `surfaces-pairs` · `surfaces-proposal`, ≥ 4 asserts each, `PRIMARY` overridden to a fixture dir
  under `$FT_TMP` inside the section subshell, the list a hand-written file.
- **`drill_surfaces`** (policy.sh) gains steps 8–10 after step 7: (8) `surfaces --scaffold` ⇒ output
  has `no test runner this kit can scope`, rc 0, the map still header-only; (9) add + commit
  `pytest.ini`, `src/sf2/a.py`, `tests/sf2/test_a.py` ⇒ `--scaffold --apply` ⇒ exactly one
  non-comment row, ending ` [scaffold]`, `^test_select: pytest {tests}` in CONVENTIONS, `surfaces`
  rc 0; again ⇒ `nothing to propose`; from a `feat/*` worktree ⇒ rc 1 + the refusal on stderr;
  (10) first-run.md § 2's doctor line: with `ops/KEYS.tsv` copied from the kit and a CONVENTIONS
  holding only `voice: standard` + `test:`, `doctor` prints `preferences never set here: adhd · claim`;
  after `interview --set adhd=off --set claim=local-lock` it does not. The hermetic cleanup already
  restores the header and the keys. Budget +8 s (re-measure CONVENTIONS' `test:` comment — Integrator/EVOLVE).

### 18. Goldens — ONE `api-kit.expected` owner per wave (key-registry.md § 5 rule; Sprint B)
Diff by content (`POLARIS_ROOT=$PWD python kit/ops/index.py find --api 'kit/*' | grep -v '^kit/\.claude/skills/i-have-adhd/' | diff - ops/tests/api-kit.expected`),
never by commit range; an unexpected hunk is a STOP. A cross-lane owner's `verify:` asserts the
pinned sibling rows are PRESENT and diffs with those rows excluded from BOTH sides (CONVENTIONS
§ Planner calibration 2026-09-14); the strict diff runs at the wave gate and in CI.
- **W1 owner T-140:** its own `kit/ops/lib/surfaces.sh	fn	surfaces_pairs` · `surfaces_proposal` ·
  `surfaces_runner`; T-143's pinned `kit/ops/bootstrap.py	fn	arm_file`; T-148's pinned
  `kit/ops/lib/core.sh	fn	board_pull`. T-143, T-146 and T-148 add NO other top-level fn and NO
  heading anywhere under kit/ (T-146 writes under plans/, outside the index).
- **W2 owner T-142:** its own `kit/ops/lib/observe.sh	fn	surfaces_apply`; T-141's pinned
  `kit/ops/lib/admin.sh	fn	cmd_interview` · `interview_pending` · `interview_set` and the row
  `kit/ops/KEYS.tsv	key	adhd`. T-141 adds NO other top-level fn and NO heading.
- **W3 owner T-145:** its own INIT.md heading rows (first-run.md § 4 pins the texts); T-144 adds
  no fn (sections inside `selftest_fast`, steps inside `drill_surfaces`) and no heading.
- **W4** T-147 (release): VERSION + CHANGELOG only; api-kit untouched; `cli-help.expected`
  regenerates at the dogfood (`check --only cli-help --update` after a line-by-line review).
- Unchanged and green: `startup-budget` (`rules-lines-memoized 3`; the engine matches with args) ·
  `cli-help-parity` · `rules-health` (a message edit changes no count) · `triage-lane` · `keys-drift` ·
  `adopt-stub` · `pack-visual` · `plain-voice` · `output-style-installed` · `adhd-skill-installed` ·
  `perm-tools` (first-run.md says why for the last four).

### 19. Prose (T-145, W3) — headings under kit/ unchanged except INIT.md's (first-run.md § 4)
- **PLANNER.md step 5b** gains, as its FIRST sentence:
  `No rows yet and the repo has tests? `bash ops/polaris surfaces --scaffold` proposes rows from the stack's own layout (pytest · jest · vitest · go) and lists what it skipped as ambiguous; `--scaffold --apply` writes the unambiguous ones and sets `test_select:` — run it here, at the plan gate, and commit both files with your contracts (a conductor-entered planner reports what it wrote instead of asking). Ambiguous pairings are skipped by design: map those with `surface:` items.`
- **INIT.md step 3**, after arming the RULES line:
  `Then `bash ops/polaris surfaces --scaffold --apply` — the survey already derived `test:`; this maps what the layout makes unambiguous (zero rows is a fine answer) and the step-5 report says how many.`
- **polaris-install SKILL.md § Update**, after the one-line report rule:
  `If `doctor` or the update says `surfaces: none mapped`, that repo's checks can get faster: run `bash ops/polaris surfaces --scaffold`, show them what it would map in one line, and apply on their yes (`--scaffold --apply`). One question, never folded into the update line.`
- **PROTOCOL.md** THE TOOL row: `surfaces` → `surfaces [--scaffold [--apply]]` + `proposes a map from the layout`.
  **MANUAL.md**: unchanged (a generator has no by-hand twin; its rows are reviewed in the diff).

### Invariants (v2 additions)
12. `--scaffold` alone writes nothing; `--apply` writes only on `<base>`, only rows the engine
    proposed, and never touches a live `test_select:` line.
13. The engine is deterministic over (manifests, tracked list, existing map): same input, same
    bytes — it is goldened.
14. `update --auto` never proposes, applies, or nudges; the doctor/qa nudges are gated on a
    detectable runner AND an empty map.
15. Every scaffolded runner both takes path arguments AND emits complete per-row cmds; a runner
    that cannot is NORUNNER, said aloud.

### Changelog
- v2 2026-09-14: activation — engine (T-140), command + nudges + golden (T-142), tests (T-144),
  prose (T-145); D1/D2/Invariant 7 widened to the second writer; § 11's cli-help sentence extended.
  Sibling seams in `ops/contracts/first-run.md`; the loader in `ops/contracts/module-layout.md` v6.
