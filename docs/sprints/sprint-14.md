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
points 5 · risk normal · landed 0c19364 (2026-09-14) · claimed 2026-09-14
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
points 5 · risk normal · landed 7d2e6fd (2026-09-14) · claimed 2026-09-14
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
