# Sprint 14 — Spend less, stay current (6.4.0) (2026-09-14–)

## T-134 — "The surface map's data plane — SURFACES.tsv, the test_select key, and the pure functions every gate reads"
points 5 · risk normal · landed 1776c8a (2026-09-14) · claimed 2026-09-14
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
