# Sprint 14 — Spend less, stay current (6.4.0) (2026-09-14–)

## T-134 — "The surface map's data plane — SURFACES.tsv, the test_select key, and the pure functions every gate reads"
points 5 · risk normal · landed 1776c8a (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/KEYS.tsv, kit/ops/lib/admin.sh, kit/ops/lib/core.sh, kit/ops/polaris, ops/SURFACES.tsv, ops/tests/api-kit.expected

### Why
POLARIS runs the whole 12-minute test suite for a one-line change, and nothing checks that a
feature's tests moved when the feature did. Both fixes need the same fact — which tests cover which
source paths — so this task lays down the ONE data file that answers it, `ops/SURFACES.tsv`
(TAB-separated, modeled on `ops/RULES.tsv`), the `test_select:` CONVENTIONS key that switches
change-scoped selection on, and the small pure functions every later gate reads through. Nothing
here changes behavior on its own: with the key unset and the file header-only, every command is
byte-identical to today. That is deliberate — it is what lets the next wave build the gate, the
selection and the health check in parallel against these names.

Read `ops/contracts/test-surfaces.md` § 1–4 and § 11 first; every name, signature, message and the
seeded header are pinned there. You are also this wave's single owner of the derived golden
`ops/tests/api-kit.expected`: write the nine pinned rows (eight fns + the KEYS key) by content
diff, sorted into place. `cli-help.expected` is NOT yours — it regenerates at the release dogfood.

### Acceptance
- [ ] `kit/ops/lib/core.sh` defines exactly the eight pinned functions with the pinned rc/stdout semantics (contract § 4); `surfaces_lines` memoizes on `_SURFACES_CACHED`/`_SURFACES_CACHE` and never touches `_RULES_CACHED` (startup-budget `rules-lines-memoized 3` unchanged); `surface_row_matches` uses args only — no pipe into `owned_match`/`match_one`
- [ ] `surface_change_set`: on a non-base branch prints `$BASE...HEAD` paths minus the three board-noise paths; on base uses an ancestor stamp as baseline (rc 0, `SURFACE_BASELINE`/`SURFACE_BASELINE_SCOPE` set) and is rc 1 for `--force`, no stamp, or a non-ancestor sha — prove each case in a scratch repo and record it in Notes
- [ ] `surface_select_cmd`: dedupes complete cmds in first-appearance order, folds `-` rows into ONE `{tests}`-substituted template line, and returns rc 1 with the pinned reason for `test_select unset` · `no rows` · `no changed paths` · `unmapped: <p> (+n more)`
- [ ] `kit/ops/polaris`: `SURFACES="$OPS/SURFACES.tsv"` directly under `RULES=`; dispatch `surfaces)   cmd_surfaces;;` (no update_check_maybe); the three usage hunks byte-exact per contract § 4, `surfaces` directly after `rules`; loader lists untouched; `startup-budget` stays green (no `$(cfg ` in the globals block)
- [ ] `kit/ops/KEYS.tsv`: the pinned `test_select` row (TAB-separated), placed after `test_fast`; `adopt-stub` and `keys-drift` goldens unchanged and green
- [ ] `cmd_init_board` calls `surfaces_seed` after the RULES seed, and the seeded RULES header gains the ONE commented `#ops/SURFACES.tsv<TAB>path<TAB>-<TAB>…` example line (commented, never armed)
- [ ] `ops/SURFACES.tsv` exists in this repo = the seeded header, no rows
- [ ] `ops/tests/api-kit.expected` carries exactly the nine W1 rows pinned in contract § 11, refreshed BY CONTENT DIFF with the worktree-honest `index.py` recipe; an unexpected hunk is a STOP, not a refresh
- [ ] `bash kit/ops/polaris doctor --fast` green; `bash kit/ops/polaris check --only startup-budget,adopt-stub,keys-drift,cli-help-parity` green after landing (integrator re-proves — goldens are primary-anchored and pass vacuously in a worktree)
- [ ] bash 3.2 clean: no `case` inside `$(...)`, no `mapfile`; `bash -n` on every touched script

## T-135 — "The stale-tests gate — a mapped surface can't hand off without its tests moving too"
points 5 · risk normal · landed 481590b (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/builder.sh, kit/ops/lib/ownership.sh

### Why
Nothing in POLARIS notices when a feature changes and its tests do not. This task adds the second
reader of `ops/SURFACES.tsv`: `check_freshness`, a scanner beside `check_rules` with the same shape
— every changed path of the branch, matched against each row's `surface` and `tests` globs. A
change with real added lines under a mapped surface and no change under its tests fails `verify`,
naming the row and the tests to update. It is reached THROUGH `check_rules`, so verify, handoff,
audit and land all get it with zero new call sites — and the write-time guard never does (it sees
one path at a time and could only ever deny the first edit of every task).

The hard part is false positives, and the answer is never "delete the row": docs-only and
comment-only diffs do not count; a change that touches the tests is fine by construction; a
genuine exception is a human's recorded `polaris approve <ID> <surface> -m "why"` — the same path
that lifts `ask` rules, so `approve` learns that a SURFACES row is also something worth approving.
`pack` shows a Builder up front which tests it is expected to move. Contract § 5 pins the algorithm,
the deny lines and the exemption; T-138 proves them in the drill, so make every message match.

### Acceptance
- [ ] `check_freshness <ref> [<ID>]` per contract § 5: inert without rows; S/T sets computed as pinned (added non-blank, non-`#`, non-`//` lines under surface; any change under tests); violation ⇔ S non-empty and T empty; deny lines and trailer byte-exact; `surfaces clean: <k> row(s) checked` on a clean pass with rows present
- [ ] exemption: every path in S covered by an `approved:` entry ⇒ pass + `⚠ SURFACES exception used — …` note per path; no ID or `-` ⇒ no approvals
- [ ] `check_rules` runs the freshness pass in ALL cases (its early returns become skips) with two flags — the `RULES violation` trailer never prints for a freshness-only failure; with no rules and no rows the output is byte-identical to today
- [ ] `cmd_guard` and `cmd_rules_check` still never call `check_rules`/`check_freshness` (D4); `per-rule-match-pipes 0` holds (args, never a pipe, inside `check_freshness`)
- [ ] `cmd_approve`'s no-op precondition widened to `ask_rule_matches || surface_rows_for … | grep -q .` with the pinned die text; the feat/* refusal and the recorded entry unchanged (the `rules` drill's ask assertions stay green)
- [ ] `cmd_pack` prints the pinned SURFACES section only when a covering row or a `surface:` item exists; `pack-visual` golden and every existing pack output byte-identical
- [ ] proven in a scratch repo (record the transcript lines in Notes): src-only change ⇒ verify rc 1 with `SURFACES stale:`; tests change added ⇒ rc 0; comment-only ⇒ rc 0; approval ⇒ rc 0 with the exception note
- [ ] no new top-level fn beyond `check_freshness` (T-136 writes its api-kit row); no heading; bash 3.2 clean

## T-136 — "qa runs only what a change can break, surfaces gets a health check, and triage prices contexts instead of tasks"
points 5 · risk normal · landed b993918 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/observe.sh, ops/tests/api-kit.expected, ops/tests/triage-lane.cmd, ops/tests/triage-lane.expected

### Why
Five concerns live in one 2,124-line file, so they are one task: (1) `qa`'s test loop learns to run
only the SURFACES.tsv commands a change maps to — with the switch being the `test_select:` key, so
an unset repo is byte-identical — and the suite stamp learns a third field saying whether the green
was full or scoped, which `finish` then says out loud; (2) `polaris surfaces` lists the map and
refuses the one row shape that would make the whole feature lie (a tests glob covering its own
surface), flagging globs that match nothing or far too much; (3) `drift` carries those refusals and
checks every ready task's `surface:` items so a typo is caught at the plan gate, not at `done`; (4)
`triage` stops sending four one-point tasks to a full wave of seven cold starts — it prices contexts,
states the arithmetic in its note, and hands small-and-few work to one solo context; (5) the
`express:` default here says `on` while the rest of the kit says `auto` — fix it.

Contract § 6–8 pins every line, flag and threshold; `surface_change_set`/`surface_select_cmd` from
T-134 make the decision so `land --express` (T-137) cannot disagree with you. You are this wave's
single owner of `ops/tests/api-kit.expected`: write your two rows and T-135's pinned
`check_freshness` row from the names, never from its diff. Extend the `triage-lane` golden with the
multi-task cases; keep every existing line.

### Acceptance
- [ ] `qa [--force] [--full]` per contract § 6: unset `test_select:` ⇒ byte-identical output and stamp shape (`<sha> <epoch> full`); bounded+empty change set ⇒ the pinned carry skip line + re-stamp with the baseline scope; unmapped ⇒ `running the whole suite: <p> has no ops/SURFACES.tsv row`; mapped ⇒ the `scoped to <m> command(s)` note, each command run in `$PRIMARY`, `test — green (scoped: <m> command(s))`, stamp `scoped`; the skip line keeps its `suite already green at <sha7> — skipped` prefix and gains `, proven <scope>`
- [ ] `finish` prints `qa green on <BASE> — proven <scope> at <sha7>` (plain when no stamp); never rejects a scoped stamp
- [ ] `cmd_surfaces` + `surfaces_health` per contract § 7: table, per-row `⛔`/`⚠` lines, row-0 unguarded warning, tail line `✅ <n> surface row(s), all healthy` / `⛔ <n> surface row(s), <e> unhealthy`, rc 1 iff an E; ONE `git ls-files` fork
- [ ] `drift`: `SURFACES: row <n> …` findings for E lines only; `READY GATE: <ID> surface: '<item>' — <reason>` for malformed/self-covering items on ready tasks; the clean line unchanged
- [ ] `triage` per contract § 8: n=1 path unchanged (the `pts" -le 3 ]` literal once); n>1 rules in the pinned order with the pinned notes; `cfg express auto`
- [ ] `triage-lane.cmd/.expected` extended: two 1-pt tasks ⇒ `solo` + a `≤ 6` note; four 2-pt tasks ⇒ `full` + `over the solo budget`; every prior line kept; `bash kit/ops/polaris check --only triage-lane` green after landing
- [ ] `api-kit.expected`: `cmd_surfaces`, `surfaces_health`, `check_freshness` rows added by content diff (index.py recipe); an unexpected hunk is a STOP
- [ ] no new top-level fn beyond `cmd_surfaces` + `surfaces_health`; no heading; bash 3.2 clean; `doctor --fast` green; the `qa`, `finish`, `express` drills green at the wave gate (`bg run test`)

## T-137 — "The integrator lane keeps step — express selects like qa, the stamp carries its scope, done writes the rows"
points 3 · risk normal · landed 69d5b97 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/selftest/history.sh

### Why
Three places in the integrator lane must move in lockstep with T-136 or the suite stamp starts
disagreeing with itself. `land --express` runs the same test loop as `qa`, duplicated verbatim — so
its `test` step now asks the same two functions (`surface_change_set`, `surface_select_cmd`) and
prints the same lines. `suite_stamp_carry` gains the scope argument and writes the three-field stamp,
and it must let `ops/SURFACES.tsv` change after the suite ran, because `done` now writes that file
on base right after the suite. And `done` itself becomes the ONLY writer of the map: every
`surface:` item on the task becomes one TSV row, seeded header first, committed on base beside the
map delta. A malformed item is skipped with a warning, never a die — a row must never block a
landing. The express drill's end-anchored stamp regex would go red the moment the third field
appears, so you own `history.sh` too and relax it to demand ` full` (its fixture never sets
`test_select:`). Contract § 6 and § 9 pin all of it.

### Acceptance
- [ ] express step 3's `test` iteration: same decision, same note/say/RED lines as contract § 6 (reds on stderr as today); `ex_scope` recorded; never `--full`
- [ ] `suite_stamp_carry <tested-sha> <scope>`: writes `<HEAD> <epoch> <scope>`; empty scope ⇒ stamp withheld with the existing note; since-tested allowlist = reports dir + `ops/MAP.md` + `ops/SURFACES.tsv`; never changes express's exit status
- [ ] `cmd_done`: `surface:` items parsed BEFORE the mv via `surface_row_from_item`; malformed / self-covering / duplicate ⇒ `⚠ surface row skipped: … — <reason>` and continue; rows require `$BASE` checked out (die names surface rows); `surfaces_seed` then append; ONE base commit — `docs(map): …` gains the SURFACES pathspec when deltas exist, else `docs(surfaces): <ID> <first surface>`; no items ⇒ byte-identical
- [ ] `drill_express` regex → `^[0-9a-f]{7,} [0-9]+ full$`; every other express assertion unchanged; drill green (`bg run` with `--only express`, record the seconds in Notes)
- [ ] no new top-level fn in either file; no heading; bash 3.2 clean

## T-138 — "Prove it — the surfaces drill and the fast-tier sections"
points 5 · risk normal · landed 0c19364 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/selftest/fast.sh, kit/ops/lib/selftest/policy.sh, kit/ops/lib/selftest/spine.sh

### Why
Three waves of code are only as good as the proof that they stay honest. This task writes it at both
tiers: five in-process fast sections (seconds, every change) over the pure functions — TSV parsing,
glob matching, selection algebra, the item grammar, stamp scope — and ONE end-to-end drill,
`surfaces`, in a throwaway repo that walks the whole path: a task's `surface:` row written by `done`,
the stale-tests gate refusing and then passing, the comment-only exemption, the human's `approve`
exemption, `qa` running only the mapped command and stamping `scoped`, the whole suite on an unmapped
change, `--full`, a `-` template row, and the health check refusing a self-covering row through
`drift --strict`. Contract § 10 lists the minimum assertions; every one checks rc, file state or qa's
own report line — never qa's exit code and never a printed refusal alone (T-089, T-131). Keep the
drill hermetic and under the ~44s budget, and record its measured seconds in Notes.

### Acceptance
- [ ] `drill_surfaces` in policy.sh with every § 10 assertion (1–7); label `surfaces` appended LAST in `SELFTEST_LABELS`; gate directly after the `rules` gate; hermetic restore of SURFACES.tsv (header-only), CONVENTIONS keys, tasks, branches, stamp; a sabotage in a throwaway copy (e.g. skip the tests change) reds the drill — record the sabotage diff in Notes
- [ ] fast.sh sections `surfaces-tsv` · `surfaces-match` · `surfaces-select` · `surfaces-item` · `stamp-scope`, ≥4 asserts each, fixtures under `$FT_TMP`, globals overridden inside the section subshell only; no new top-level fn in fast.sh
- [ ] `bash kit/ops/polaris doctor --selftest --only surfaces` green (600000 ms or `bg run`); full `bg run test` green at the wave gate; measured drill seconds in Notes
- [ ] no new top-level fn beyond `drill_surfaces` (T-139 writes its api-kit row); no heading; bash 3.2 clean (no `case` inside `$(...)`)

## T-139 — "Stop asking which lane — delete the second copy, name the anti-pattern, guard the map file, teach every role"
points 5 · risk normal · landed 7d2e6fd (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/.claude/output-styles/polaris.md, kit/CLAUDE.md, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md, kit/ops/templates/TASK.md, ops/RULES.tsv, ops/tests/api-kit.expected, ops/tests/rules-health.expected

### Why
The reason POLARIS asks "which lane?" is that the answer exists twice: `polaris triage` computes it,
and CONDUCTOR.md step 2.5 restates the six conditions in prose — and the prose drifted (it says two
points, the code says three). A model re-derives, disagrees with the CLI, finds itself holding a
judgment call, and asks. Delete the second copy: step 2.5 becomes "run triage, branch on line 1",
and the named anti-pattern — never offer a menu of execution strategies — goes into kit/CLAUDE.md,
the output style and PLANNER 0b, verbatim from contract § 12. The same pass teaches every role the
surface map: Builders and SOLO learn the stale-tests refusal and that the file is never edited by
hand, SOLO learns to work several small tasks one at a time, the Integrator learns `done` writes
the rows, INIT learns to arm the guard, the task template gains `surface:`, PROTOCOL and MANUAL
learn the command and the by-hand proof. Finally this repo arms the RULES `path` line on
`ops/SURFACES.tsv` (rules-health goes 15 → 16). You are W3's single owner of `api-kit.expected`:
add T-138's pinned `drill_surfaces` row, and add no heading of your own — every edit is a
paragraph, list item, step or table row. `plain-voice` and `output-style-installed` must stay
byte-identical: the anti-pattern is a paragraph after the numbered rules, never rule 8.

### Acceptance
- [ ] CONDUCTOR.md 2.5 per contract § 12: `triage` → line 1 → solo (ONE SOLO subagent; conductor runs `finish`) · express (existing choreography verbatim) · full (steps 3–8, silently); no lane condition or point threshold restated anywhere in the file
- [ ] the pinned anti-pattern paragraph, verbatim, in kit/CLAUDE.md (after `Not on it:`), the output style (after the numbered list, not as a rule) and PLANNER.md 0b (its one-line form); CLAUDE.md Invariant 1 gains the surfaces clause; CLAUDE.md net growth ≤ 4 lines
- [ ] PLANNER.md step 5b (map the surfaces, § 3 grammar) · BUILDER.md + SOLO.md (stale-tests refusal, approve is the only exemption, never edit the file, IDEAS/Notes for a wrong row; SOLO: up to 4 tasks one at a time, subagent stops before `finish`) · INTEGRATOR.md (gate at audit/land, exception line carried, `done` writes rows) · INIT.md (seeded file, arm the commented RULES line) · TASK.md (`surface:` field) · PROTOCOL.md (THE TOOL rows) · MANUAL.md (by-hand freshness proof + rows commit)
- [ ] `ops/RULES.tsv` gains the pinned `ops/SURFACES.tsv<TAB>path<TAB>-<TAB>…` line with a `#` comment naming who and why (Invariant 11); `rules-health.expected` = `✅ 16 rule(s), all healthy`; `bash ops/polaris rules` on base prints exactly that after landing (integrator re-proves — primary-anchored)
- [ ] `api-kit.expected` gains exactly `kit/ops/lib/selftest/policy.sh	fn	drill_surfaces` and no heading rows (content diff, index.py recipe); an unexpected hunk is a STOP
- [ ] `plain-voice`, `output-style-installed`, `cli-help-parity` goldens byte-identical and green; `bash kit/ops/polaris check` green at the wave gate (except `cli-help`, which regenerates at the release dogfood by design — say so in the handoff report)

## T-140 — "The scaffold engine — lib/surfaces.sh proposes a repo's test map from its own layout, and the entry learns surfaces --scaffold and interview"
points 5 · risk normal · landed 42c7eb9 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/surfaces.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
Sprint A made `qa` and `land --express` able to run only the tests a change can break — and, by
design, switched nothing on: `test_select:` unset plus an empty `ops/SURFACES.tsv` is byte-identical
to 6.3. `update --auto` therefore delivers 6.4.0 to every installed repo and makes none of them
faster. Somebody has to write the rows, and in a repo nobody is watching that somebody is POLARIS.
This task is the engine that proposes them: given the repo's manifests and its tracked-file list, it
names the test runner it can PROVE takes path arguments (pytest, jest, vitest — and go, whose rows
carry complete package commands), pairs test dirs to source dirs only where the stack's own
convention implies the pairing (`tests/api/` ↔ exactly one `api/` dir; `tests/test_util.py` ↔
exactly one `util.py`; `src/foo/__tests__/` ↔ `src/foo/`; a dir with `*_test.go`), and refuses to
guess: two candidate dirs is a SKIP that says so, a surface over 200 paths is a SKIP, a narrower
pairing under an emitted one is folded. Mis-mapping is the unsafe failure (a row that skips real
coverage while reporting green), so the whole engine leans toward emitting three honest rows and
admitting the rest. It is pure — no git, no network, no map read — so the fast tier proves it in
milliseconds and the golden pins every byte. Contract § 13 is the spec: three functions, exactly.

You are also this wave's single owner of `kit/ops/polaris` and `ops/tests/api-kit.expected`: add
`surfaces` to the loader (§ 13, module-layout v6), write the `surfaces [--scaffold [--apply]]` usage
entry (§ 14 replaces the v1 lines verbatim) and the `interview` entry + dispatch (first-run.md § 2,
verbatim — `cmd_interview` lands in W2; naming an undefined function until then is accepted), and
write the api-kit rows for T-143's `arm_file` and T-148's `board_pull` from their pinned names (§ 18),
never from a diff you cannot see.

### Acceptance
- [ ] `kit/ops/lib/surfaces.sh` exists, ≤ 350 lines, exactly three top-level functions (`surfaces_runner` · `surfaces_pairs` · `surfaces_proposal`), bash 3.2 clean, matching only via `match_one` with args
- [ ] `surfaces_runner` answers the § 13 table in the § 13 order (node by grep on package.json → pytest by its five tells → go by go.mod); everything else rc 1
- [ ] `surfaces_pairs` emits the per-stack rows and the three shared filters in order (ambiguity → breadth → ancestor), sorted `LC_ALL=C`, SKIP lines as data; `surfaces_proposal` adds `already mapped` and `tests glob covers its own surface`, and prints `NORUNNER … seen: <manifests>` as its only line when nothing scopes
- [ ] contract § 17 case 1 by hand in a scratch repo (`scratchpad/T-140/…`): FOUR rows, TWO skips, byte-exact per the contract — the golden itself is T-142's, but its case 1 is your engine's spec
- [ ] loader: `surfaces` between `workspace` and `builder`; the `_match|_rules|_guard` list untouched; `startup-budget` green
- [ ] usage: the § 14 `surfaces` block replaces v1's, the first-run.md § 2 `interview` block sits directly after `adopt`; dispatch lines exactly as pinned; `cli-help-parity` still 10; `bash kit/ops/polaris help | diff - ops/tests/cli-help.expected` shows the v1 hunks + the two new ones and nothing else
- [ ] `api-kit.expected`: your three rows + `arm_file` + `board_pull` added by content diff (§ 18); no other hunk
- [ ] `doctor --fast` green; the `surfaces` and `qa` drills green at the wave gate (`bg run test`)

## T-141 — "The first-run interview — KEYS.tsv learns to ask, polaris interview generates the questions and writes the answers, update carries the style and the ADHD skill to the machine"
points 5 · risk normal · landed 9cd023d (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/KEYS.tsv, kit/ops/lib/admin.sh, ops/tests/interview.cmd, ops/tests/interview.expected

### Why
Installing POLARIS asks nothing. `voice:` is guessed by INIT, `claim:` is defaulted, and the
vendored `/i-have-adhd` skill stays a secret unless someone reads PROTOCOL § VOICE. plans/v3.md § B1
wants ONE round of at most four questions — how to be talked to, ADHD-shaped replies, one computer
or several — and wants the questions to come from DATA, so they cannot drift from the keys they
set. That is a fifth KEYS.tsv column, `ask`, on exactly three rows (one of them the new `adhd` key),
and one command: `polaris interview` prints what is still unanswered as QUESTION/OPTION lines the
model turns into a single AskUserQuestion; `--set key=value` validates every pair against the row's
options and writes live lines into CONVENTIONS (a stub is replaced in place — one `adopt` run
silences the interview, deliberately); `--pending` is the one-line probe `doctor` (T-142) and the
explicit `update` epilogue (yours, admin.sh) print. `adhd: on` has a side effect: the repo's copy of
the skill gets `disable-model-invocation: false` — the kit copy is never touched, and `install.sh`
(T-143) keeps the flip across updates. `update --auto` stays exactly one pinned line: it never asks,
never nudges. Your admin.sh also finishes B2's machine half: `refresh_machine_kit` re-caches the
output style and the ADHD skill beside the installer skill, so an `update` in one repo arms the
machine the way a fresh install (T-143) does. Contract first-run.md § 1–3 pins the rows, the
grammar, every die text and the golden.

### Acceptance
- [ ] KEYS.tsv: the three `ask` rows verbatim from § 1 (voice · adhd · claim; `adhd` directly after `voice`), no other row gains a fifth column, the header comment describes column 5; `cmd_adopt` reads a fifth variable and its stub line is byte-identical (`adopt-stub` green; the `adopt` drill green)
- [ ] `interview_pending` · `interview_set` · `cmd_interview` are the ONLY new top-level fns; grammar, tails, die texts, precedence (`feat/*` refusal, then the claim-branch remote check), the all-or-nothing validation, the three write modes (live / stub / absent), the adhd side effect and its `⚠ … not installed here` note — all per § 2
- [ ] `update`'s explicit epilogue prints the pinned `preferences never set here:` line after `untouched:` when `$CONV` exists and something is pending; `update --auto` output unchanged (the `autoupdate` drill green)
- [ ] `refresh_machine_kit` copies the output style + i-have-adhd trio from the tarball (kit/ path first, root fallback), silent, fail-open
- [ ] golden `ops/tests/interview.cmd/.expected` per § 2 (hermetic fixture; the fake registry's ADHD row is named `adhd` so the side effect is exercised); `keys-drift` and `adopt-stub` byte-identical
- [ ] no heading anywhere under kit/; `doctor --fast` green; `doctor --selftest --only adopt,autoupdate,upgrade` green in the worktree (explicit 600000 ms timeout)

## T-142 — "surfaces --scaffold proposes the map and --apply writes the unambiguous rows; doctor and qa say when a repo has no map"
points 5 · risk normal · landed b34be07 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/observe.sh, ops/tests/api-kit.expected, ops/tests/surfaces-scaffold.cmd, ops/tests/surfaces-scaffold.expected

### Why
T-140 built the engine; this is the command a human or a planner runs. `surfaces --scaffold` shows
the proposal — the runner it found, the rows it would write, and every pairing it skipped with the
reason — and writes nothing. `--scaffold --apply` writes exactly those rows into `ops/SURFACES.tsv`
tagged `[scaffold]` and sets `test_select:` when the repo has never set it (a stub is replaced in
place; a live value, even empty, is the human's and is kept), on `<base>` only, and then says
"review, then commit" instead of committing. That makes it the second sanctioned writer of a
RULES-guarded file, so the contract's § 16 widens D1/D2 for it and nothing else. The other half of
activation is telling a repo its map is empty at the moments it matters: `doctor` (one line, after
the config-drift line) and `qa` (one line, after a whole-suite run of a minute or more) — both gated
on the engine detecting a runner, so a repo the scaffold cannot help (this one) is never nagged.
`doctor` also prints the interview's `preferences never set here:` line (first-run.md § 2) through a
`command -v` guard, because T-141 lands beside you this wave. You are this wave's single owner of
`ops/tests/api-kit.expected`: write your `surfaces_apply` row and T-141's three fns + `adhd` key row
from the contract's names. The golden `surfaces-scaffold` (§ 17, five fixtures) is yours and is the
whole activation's regression lock — pin every byte the contract pins.

### Acceptance
- [ ] `cmd_surfaces` flags: none · `--scaffold` · `--scaffold --apply`; anything else dies with the pinned usage; plain `surfaces` byte-identical to v1 § 7 (the `surfaces` drill's steps 1–7 unchanged)
- [ ] `--scaffold` renders per § 14: the `runner:` note, the three-column table, `   ⚠ skipped:` lines, the three tails; NORUNNER ⇒ the pinned note; rc 0 always; writes nothing (assert the map and CONVENTIONS byte-identical after)
- [ ] `--scaffold --apply` per § 14: the `feat/*` and no-CONVENTIONS refusals; `surfaces_apply` (the ONLY new top-level fn) seeds, appends `[scaffold]` rows, handles `test_select:` live/stub/absent exactly as pinned, temp file + mv; the two tail lines; idempotent second run
- [ ] doctor: the surfaces nudge directly after the CONFIG DRIFT block, gated on `$CONV` + `cfg test` + runner + empty map; then the guarded preferences line; `qa`: the whole-suite nudge after `last-suite-seconds`, gated on `ran ≥ 1`, no selection, `t1 - t0 ≥ 60`, runner, empty map — every existing drill that greps doctor/qa lines still green
- [ ] golden `ops/tests/surfaces-scaffold.cmd/.expected` with the five § 17 fixtures — hermetic, run from the repo root, < 20 s; each fixture commits its files; case 1 asserts the four rows, the two skips, the apply, the health tail, the idempotent rerun, the stub replacement, the kept live value and the feat/* refusal
- [ ] `api-kit.expected`: `surfaces_apply` + T-141's four pinned rows by content diff; no other hunk; `rules-health` unchanged (16)
- [ ] `doctor --fast` green; `doctor --selftest --only surfaces,qa,finish,drift` green in the worktree (explicit 600000 ms timeout); the whole `test:` green at the wave gate via `bg run test`

## T-143 — "Arm the machine with the voice — bootstrap.py lands the output style and the ADHD skill in ~/.claude, install.sh honours adhd: on"
points 3 · risk normal · landed 92c83dd (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/bootstrap.py, kit/ops/install.sh, kit/ops/selftest-install.sh, ops/tests/machine-armed.cmd, ops/tests/machine-armed.expected

### Why
`arm_machine()` teaches a machine how to install POLARIS: the installer skill, the cached kit, the
permission rules, keep-awake. It does not teach it how to TALK. The output style (the warm, plain
voice and the 🎉 that `finish` earns) and the vendored `/i-have-adhd` skill are copied per repo by
`install.sh`, so on a second computer — or in any repo where the installer never ran — there is no
style to select and no skill to invoke. That is the confetti gap. Land both in `~/.claude` from the
archive, write-if-different so a repeat install stays quiet, and say what landed. Two things stay
exactly as they are, on purpose: `outputStyle` in the MACHINE settings is never written (a
machine-wide style would restyle every non-POLARIS repo — selection stays per repo or per session),
and the machine copy of i-have-adhd keeps `disable-model-invocation: true` (the opt-in is a repo
preference, `adhd:`, asked by the interview T-141 ships). The repo half of that preference is yours
too: `install.sh` copies the kit's skill verbatim on every update, which would silently re-arm the
opt-in flag in a repo that said `adhd: on` — so after the copy, honour the line. Contract
first-run.md § 2 (install.sh) and § 3 (arming + the golden) pin every path and line.

### Acceptance
- [ ] `arm_file(z, member, dest) -> bool` is the ONLY new top-level def in bootstrap.py; `arm_machine` uses it for the style and the three i-have-adhd files, folds the results into `changed`, prints the two pinned `✅ … armed:` lines, skips a missing member silently
- [ ] `--no-machine-setup` skips it; `--no-permissions` unaffected; `outputStyle` never appears in bootstrap.py; PERMS unchanged (`perm-tools` green)
- [ ] `install.sh`: after the vendored copy, a live `^adhd:[[:space:]]*on` in the target's CONVENTIONS ⇒ the copied SKILL.md reads `disable-model-invocation: false` (temp file + mv); otherwise the copy stays verbatim — the kit copy is never touched (`adhd-skill-installed` green)
- [ ] `kit/ops/selftest-install.sh` gains the two-way case inside its live-board section (no new top-level fn); run it once with `POLARIS_AWAKE_HOME` pointed at a scratch dir (foreground, explicit ≥ 180000 ms timeout) — green
- [ ] golden `ops/tests/machine-armed.cmd/.expected` per first-run.md § 3: builds the zip with the repo's own `build:` (`python kit/ops/pack.py --allow-dirty`), arms a fake `HOME`/`USERPROFILE`, asserts the files, the kept flag, the absent settings.json, and a byte-identical second run; runs from the repo root, hermetic, < 15 s
- [ ] CI's own `--claude-skill` job (`.github/workflows/ci.yml`, human-owned — read, never edit) still passes by inspection: its asserts are about the skill and the permissions, both untouched

## T-144 — "Prove the activation — fast-tier sections for the engine and the interview, and the surfaces drill scaffolds, applies and asks"
points 5 · risk normal · landed 51ee8ba (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/selftest/fast.sh, kit/ops/lib/selftest/policy.sh

### Why
T-140's engine and T-141's interview are pure over files, which is exactly what the in-process tier
is for: prove the runner table, the pairing filters, the RUNNER/ROW/SKIP grammar and the pending
computation in milliseconds, on every change, with fixtures under `$FT_TMP` and `PRIMARY`/`OPS`/`CONV`
overridden inside each section's subshell — no CLI re-invocation, no scratch repo. The drill proves
the real entry point: the fixture that has no runner gets NORUNNER, the fixture that gains a pytest
layout gets one `[scaffold]` row and a `test_select:` line from `--scaffold --apply`, the refusal
from a task worktree fires, and doctor's `preferences never set here:` line appears and then
disappears once `interview --set` has answered. Contract test-surfaces.md v2 § 17 and first-run.md
§ Executable check pin the sections, the steps and their assertions. No new top-level function
anywhere: sections live inside `selftest_fast`, steps inside `drill_surfaces` — this wave's golden
owner is T-145 and you add no api-kit row.

### Acceptance
- [ ] fast.sh sections `surfaces-runner` · `surfaces-pairs` · `surfaces-proposal` · `interview-pending`, ≥ 4 asserts each, inside `selftest_fast`; fixtures written with builtins; the whole fast tier still under its budget (`doctor --fast` prints the pass line with the check count)
- [ ] `drill_surfaces` steps 8–10 exactly per § 17: (8) NORUNNER, rc 0, header-only map; (9) pytest layout ⇒ one row ending ` [scaffold]`, `^test_select: pytest {tests}` in CONVENTIONS, `surfaces` rc 0, rerun ⇒ `nothing to propose`, feat/* worktree ⇒ rc 1; (10) `ops/KEYS.tsv` copied from the kit, CONVENTIONS with only `voice:` + `test:` ⇒ doctor has `preferences never set here: adhd · claim`; after `interview --set adhd=off --set claim=local-lock` it does not
- [ ] hermetic: the drill's existing cleanup restores the header-only map and removes the CONVENTIONS keys it added — steps 8–10 leave nothing behind for step 11 or the next drill; assertions are rc + file state, never qa's rc
- [ ] `bash kit/ops/polaris doctor --selftest --only surfaces,qa,finish` green in the worktree (explicit 600000 ms timeout); the sharded `test:` green at the wave gate via `bg run test`; re-measure the surfaces drill's cost and record it in Notes for EVOLVE (CONVENTIONS' `test:` comment budgets ~44 s per drill)

## T-145 — "Teach the roles — INIT asks its questions in one call, the Planner scaffolds at the plan gate, the install skill knows both lines"
points 5 · risk normal · landed 71ac854 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/.claude/skills/polaris-install/SKILL.md, kit/ops/PROTOCOL.md, kit/ops/roles/INIT.md, kit/ops/roles/PLANNER.md, ops/tests/api-kit.expected

### Why
The code landed in W1 and W2; nothing tells an agent to use it. INIT still asks its own hand-written
voice question and a `claim:` question in the long form — now both come from `polaris interview`
and are asked in ONE call, with the ADHD question beside them (first-run.md § 4 pins the new 2a
heading, the 2c cut, the `adhd: off` skeleton line and the `interview --set` call in step 3, followed
by `surfaces --scaffold --apply` so a fresh repo is mapped before its first sprint). The PLANNER's
step 5b gains its first sentence: an empty map plus tests means scaffold at the plan gate and commit
the two files with the contracts — a conductor-entered planner reports what it wrote rather than
asking (test-surfaces.md v2 § 19). The install skill learns the two lines an update or a doctor can
now print and what to do with each, in one question at most. PROTOCOL's tool row names the new flag.
You are W3's single owner of `ops/tests/api-kit.expected`: INIT.md's renamed heading is a row change,
and it is the only heading change in this task — every other edit is a paragraph, a list item or a
table row (assert the `^#` counts of PROTOCOL.md and PLANNER.md are unchanged, and the skill's `## `
count too). T-144, beside you, adds no fn and no heading.

### Acceptance
- [ ] INIT.md § 2 per first-run.md § 4: 2a renamed and rewritten (run `interview`, ask everything it prints in ONE AskUserQuestion, voice first; before CONVENTIONS exists read the questions off `ops/KEYS.tsv`'s ask column), 2b untouched, 2c heading untouched and its question 2 removed; § 3 skeleton gains `adhd: off` under `voice:`, step 3 runs `bash ops/polaris interview --set …` then `bash ops/polaris surfaces --scaffold --apply` (test-surfaces v2 § 19 wording); the 3-interaction cap sentence still holds
- [ ] PLANNER.md step 5b's first sentence verbatim from test-surfaces v2 § 19; no other PLANNER change
- [ ] polaris-install SKILL.md § Update gains the two pinned paragraphs (surfaces, preferences); `§ After the install` unchanged; no heading added or renamed
- [ ] PROTOCOL.md THE TOOL row updated; no heading change; MANUAL.md, CLAUDE.md, BUILDER/SOLO/INTEGRATOR/CONDUCTOR/EVOLVE untouched
- [ ] `api-kit.expected`: INIT.md's heading row updated by content diff — a strict diff is green in your worktree (you own every hunk this wave); `plain-voice`, `output-style-installed`, `adhd-skill-installed` green
- [ ] `bash kit/ops/polaris doctor --selftest --only claudemd,brief,hint` green in the worktree (explicit 600000 ms timeout)

## T-146 — "SPIKE — skills POLARIS writes for itself: the token budget, the eviction rule, the gap-finder and the writer, designed before a line of code"
points 3 · risk normal · landed ca2dddd (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: plans/self-skills.md

### Why
plans/v3.md § B3 asks for skills POLARIS writes for itself — a repo's `.claude/skills/<name>/SKILL.md`,
committed, so a surface the agents keep rediscovering gets a skill that saves the rediscovery. No
mechanism for that exists anywhere in the kit, and the governing tension is not a writer, it is a
budget: every skill's frontmatter is injected into EVERY session's system prompt — `cmd_slim`
measured 251 definitions / 34,119 B / ~8,500 tokens per context on this machine. A skill that saves
5k tokens of rediscovery per use is a clear win; fifty speculative skills are a permanent tax on
every session, including the ones that never needed them. Five points of greenfield off one
paragraph would be a guess, so this is a time-boxed design pass that produces the DOCUMENT the real
tasks are carved from. Write no kit code. Measure first, decide second, propose third.

### Acceptance
- [ ] `plans/self-skills.md` with these headings, in order: `## The tension` · `## Measurements` · `## Budget` · `## Eviction` · `## Gap-finder` · `## The writer` · `## Names and homes` · `## Proposed contract` · `## Proposed carve`
- [ ] Measurements are REAL numbers from this machine: `bash ops/polaris slim` (report only — never `--apply`) pasted in full; the byte size of each shipped SKILL.md frontmatter (`kit/.claude/skills/*/SKILL.md`, lines between the `---` fences); the per-context cost of one more skill at that size, in tokens (÷4) and multiplied by a 6–8-context conductor run
- [ ] Budget: a hard cap in BYTES of frontmatter per repo that POLARIS-written skills may add (derive it from the numbers — say why), and what happens at the cap (refuse to write, or evict)
- [ ] Eviction: a rule stated as data a command can evaluate — what "unused" means (which board or `pack` signal records a skill being read; `ops/board/EVENTS.ndjson` is the only telemetry that exists; say what would have to be added), the window, and the reversible move (archive under `.polaris/`, never delete — `slim --apply` is the precedent)
- [ ] Gap-finder: how `ops/SURFACES.tsv` and the done tasks' `files_owned` identify "a surface worked on repeatedly with no skill", with the exact threshold; and why NOT to write a skill for a surface worked once
- [ ] The writer: who writes (EVOLVE between sprints, the Integrator at `done`, or a `polaris skill propose <surface>` command a human runs) and what the skeleton contains (the skill's frontmatter must stay under a stated byte size; the body is where the savings live); name the input `pack` already computes that the skeleton would reuse
- [ ] Names and homes: `.claude/skills/<name>/SKILL.md` committed in the repo (owner choice — travels with the repo); the reserved names `update` manages and this must never collide with (`polaris`, `polaris-install`, `i-have-adhd` — admin.sh's uninstall list; quote the line); how `update` and `uninstall` treat POLARIS-written skills
- [ ] Proposed contract: a CONTRACT.md-shaped draft (interface, invariants, executable check, example) the Planner can lift into `ops/contracts/self-skills.md`
- [ ] Proposed carve: ≤ 5-point leaves with disjoint `files_owned`, pointed; which golden(s) pin the budget; which drill proves the eviction; the api-kit rows each leaf adds
- [ ] Every open question you could not settle is listed under `## Proposed contract` as `OPEN:` lines with the two options and your recommendation — never silently defaulted

## T-147 — "Release 6.4.0 — spend less, stay current, everywhere: the kit that maps its own tests, asks its three questions, and follows you"
points 2 · risk normal · landed bd9c17a (2026-09-14) · claimed 2026-09-14
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
Sprint A gave `qa` and `land --express` a test map to select from; Sprint B gave every repo a way to
get one without a human writing rows, an interview that asks the three questions a repo cannot
answer for itself, a machine that carries the voice, and a board that follows you across computers.
None of it reaches anyone until it is released — and `update --auto` only ever delivers a PUBLISHED
minor. Four places at once: `kit/ops/VERSION`, the CHANGELOG, the git tag, the GitHub release with
`polaris-v5.zip`. Sprint 13's lesson is on the board: 6.2.0, 6.2.1 and 6.3.0 were all tagged and
never shipped because a sharded green is not a CI green — the serial suite shares one fixture across
every drill and reds on what the shards never see. So this task bumps and documents, and it does not
hand off until the SERIAL suite is green in its own worktree, with nobody else editing `kit/`. The
CHANGELOG entry is written for the humans who will read it after `update --auto` prints one line:
what got faster, what now asks, what changed on the machine, in the house voice of the 6.3.x entries
— and a `BREAKING: none` line, because nothing in 6.4.0 changes a repo's behavior until it opts in
(`test_select:` unset stays byte-identical; the interview only asks; the style lands unselected).

### Acceptance
- [ ] `kit/ops/VERSION` reads `version: 6.4.0`; every other line untouched
- [ ] CHANGELOG has `## 6.4.0 — <today>` above 6.3.1, covering Sprint A (SURFACES.tsv, the stale-tests gate, change-scoped `qa`/express, the stamp scope, triage pricing contexts, the one-copy lane rule) and Sprint B (`surfaces --scaffold [--apply]`, the interview, `adhd:`, the machine-armed style + skill, `board_pull`), a before/after table in the 6.3.0 style, and `BREAKING: none`; the 6.3.1 and 6.3.0 entries unchanged
- [ ] the SERIAL suite green in your worktree: `bash ops/polaris bg run serial -- bash kit/ops/polaris doctor --selftest` then chunked `bash ops/polaris bg wait serial --max 300` until it returns a verdict (expect 900–1000 s; three or four waits); paste the `selftest passed` line and `git rev-parse HEAD` into Notes — the serial run is the CI tier, and it must be green BEFORE the tag exists
- [ ] no other lane is active while the serial suite runs (this task depends on every other one, so `bash ops/polaris status` shows nothing in active/ besides you — check before starting; editing `kit/ops/lib/*.sh` mid-run fabricates a spurious failure)
- [ ] `bash kit/ops/polaris check` green (every golden, against your worktree) and `doctor --fast` green

## T-148 — "The board follows you — board_pull fetches origin's board ref under claim-branch, so a second machine's status, next and claim read the truth"
points 5 · risk normal · landed c225ba4 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/builder.sh, kit/ops/lib/core.sh, kit/ops/lib/handover.sh, kit/ops/lib/observe.sh, kit/ops/lib/selftest/remote.sh

### Why
plans/v3.md § B4 says cross-device tracking is "mostly configuration": `claim: claim-branch` plus an
origin remote, because `sync_board()` opens with `has_remote || return 0` and without a remote every
board mutation is silently machine-local. Reading the code shows the other half is missing: with a
remote, every mutation PUSHES `refs/heads/polaris/board`, but nothing ever FETCHES it — a second
machine reads `ops/board/` exactly as it was at its last clone (`board_materialize` only fires when
the directory is absent). The claim-branch lock still prevents two machines building one task, but
`status`, `next`, `board-fm` and the dashboard on the second machine show a board that stopped
moving. `board_pull` is the read side: under `claim-branch` with a remote, fetch the ref (at most
once a minute), fast-forward the local ref when it is an ancestor of origin's, and re-materialize
the moved set with the same plumbing `board_materialize` uses — never a branch switch, never the
primary index. A diverged local ref is reported and left alone; a `local-lock` repo (this one) pays
nothing at all. Contract first-run.md § 5 pins the algorithm, the throttle, the four call sites and
the drill.

### Acceptance
- [ ] `board_pull` in core.sh (≤ 45 lines, the only new top-level fn): gate on `CLAIM_MODE = claim-branch` AND `has_remote`, else rc 0 with no fork; 60 s throttle on `$PRIMARY/.polaris/board-pulled`; `POLARIS_BOARD_PULL=0` skips
- [ ] remote tip by `ls-remote … | cut -f1`, never FETCH_HEAD; equal ⇒ nothing; ancestor ⇒ delete the local tip's tracked moved-set files, `update-ref`, `read-tree` into a secondary index + `checkout-index -a -f --prefix`, then `board pulled: <n> commit(s) from origin (claim-branch)`; diverged ⇒ the pinned `⚠ board diverged from origin …` note and no write
- [ ] call sites: first statement of `cmd_status` and `cmd_board_fm` (observe.sh), `cmd_next` (handover.sh), `cmd_claim` (builder.sh); nowhere else — not the guard path, not doctor
- [ ] `sync_board` byte-identical; `startup-budget` green; `board-fm-shape` green
- [ ] `drill_remote` (remote.sh) gains the clone-and-pull step per § 5: claim in a second clone ⇒ `status` in the first shows active/ + the stamp file; `POLARIS_BOARD_PULL=0` keeps a later change stale; a diverged local ref ⇒ the note, files untouched; the fixture is restored to `local-lock` and the clone removed afterwards
- [ ] `bash kit/ops/polaris doctor --selftest --only remote,syncrace` green in the worktree (foreground, explicit 600000 ms timeout — the spine alone is ~144 s) and the whole `test:` green at the wave gate via `bg run test`
