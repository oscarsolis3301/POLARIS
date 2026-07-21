# CONTRACT: module-layout            (v1 — 2026-07-21)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Splits `kit/ops/polaris` (3,826 lines) into a thin entry script + runtime-sourced `kit/ops/lib/*.sh`
modules — verbatim relocation, ZERO behavior change. This file is the single authority on which
function lives where, the loader's shape, and the line budgets. Tasks: T-039, T-040, T-042..T-045.

## Interface — the entry script
`kit/ops/polaris` remains the ONLY entry point and keeps, in this order:
1. shebang · `set -eu` · `POLARIS_V=5` (today's lines 1–6, verbatim)
2. **the lib loader** (NEW code — the only new code this sprint besides `--parallel`; see below)
3. the git-repo guard (today's line 13 — `die` is available: core.sh is already sourced)
4. every top-level variable assignment, in today's relative order:
   `GCD PRIMARY OPS BOARD LOCKS CONV VER SELF` · `BASE CLAIM_MODE STALE_H WHO EVENTS` · `RULES` ·
   `MUTEX FAIL_LOCK_ID` · `PUB PUBLISH_WARNED` · `BOARD_REF` (moved up from lines 127/158/197 —
   pure assignments, no calls besides `cfg`, which core.sh has already provided)
5. `usage()` + the dispatch `case` (today's lines 3711–3826, verbatim)
Nothing else. Final size (gated at T-045): **< 500 lines**.

## The loader — pinned verbatim (bash 3.2-safe; grows per the schedule below)
```bash
# --- lib loader: every function body lives in lib/ — fixed order, core first ---
OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
for _m in core ownership builder integrate knowledge observe admin \
          selftest/spine selftest/board selftest/history selftest/report \
          selftest/brain selftest/policy selftest/remote; do
  if [ ! -f "$OPS_DIR/lib/$_m.sh" ]; then
    printf '⛔ POLARIS: ops/lib/%s.sh is missing — this kit is incomplete. Re-run the installer (bash ops/install.sh) or fetch a fresh kit: ops/polaris update\n' "$_m" >&2
    exit 1
  fi
  . "$OPS_DIR/lib/$_m.sh"
done
unset _m
```
- The missing-lib message uses raw `printf`, NEVER `die` — core.sh may be the missing file.
- The list is literal, never a glob (glob order is locale-dependent).
- Growth schedule — each task extends the list, inserting names at their FINAL position:
  T-039 `core` · T-040 `selftest/*` (all 7) · T-042 `ownership builder` · T-043 `integrate` ·
  T-044 `knowledge observe` · T-045 `admin` (list complete = the block above, byte-for-byte).

## Shared types / schema — function → module (complete; today's definition-line refs)
Every function moves VERBATIM, comments included, keeping its module-internal relative order.

**lib/core.sh** (33 fns, ~350 lines): die say note (9–11) · cfg (25) · jesc evt notify_fire (42–68) ·
rules_lines (69) · fm_get fm_list (75–115) · task_file task_col (116–125) · mutex_off on_die
mutex_on (129–152) · has_remote (153) · publish_resolve base_push_reject base_push_clear
pr_create_url (160–196) · board_paths board_ref_commit sync_board board_commit
board_materialize (198–287) · lock_take lock_drop lock_age claim_branch_take
claim_branch_drop (288–306) · wt_path current_task_id set_fm fm_stamp (436–457)

**lib/ownership.sh** (9 fns, ~160 lines): owned_match (308) · check_ownership (319) ·
run_verify_cmds (346) · map_delta_hint (357) · rule_scan_path (385) · rule_scan_content_file (398) ·
check_rules (413) · cmd_match (3691) · cmd_rules_check (3701)

**lib/builder.sh** (7 fns, ~260 lines): cmd_claim (490) · cmd_verify (577) · cmd_handoff (585) ·
cmd_release (625) · grant_append_owned (650) · cmd_grant (681) · cmd_resume (747)

**lib/integrate.sh** (15 fns, ~590 lines): cmd_kickback (769) · cmd_audit (784) · cmd_run_verify (791) ·
landed_sha (797) · cmd_done (812) · cmd_task_commit_msg (898) · in_primary (953) ·
land_slow_suite_hint (960) · cmd_land (975) · cmd_land_express (1026) · tag_push_recovery_note (1104) ·
cmd_seal (1113) · seal_sync (1235) · cmd_history (1303) · cmd_rollback (1328)

**lib/knowledge.sh** (26 fns, ~405 lines): report_dir report_file report_rel (1362–1367) ·
sprint_hdr sprint_hdr_num all_sprint_numbers sprint_goal sprint_dates (1369–1390) ·
ts_date event_ts resolve_sprint_ids (1391–1436) · render_task_section render_sprint (1437–1494) ·
report_dirty_hint report_one cmd_report (1495–1552) · seal_report_commit (1553) ·
board_changed_touch (1573) · brain_refresh_if_present (1578) · brain_index brain_code_map
brain_board brain_contracts brain_commands brain_gotchas (1587–1734) · cmd_brain (1735)

**lib/observe.sh** (17 fns, ~680 lines): cmd_notify_gate (726) · status_brief (1767) · cmd_status (1806) ·
cmd_sweep (1837) · cmd_doctor (1904) · pat_overlap (2920) · dep_ids dep_reaches (2942–2961) ·
cmd_drift (2962) · cmd_rules (3046) · cmd_qa (3065) · cmd_metrics (3115) · cmd_why (3160) ·
cmd_dash (3181) · find_claude find_claude_windows (3190–3216) · cmd_fleet (3217)

**lib/admin.sh** (10 fns, ~430 lines): cmd_init_board (458) · cmd_upgrade (3294) · ver semver_gt (3334–3347) ·
update_check_maybe (3348) · cmd_version (3383) · kit_zip_version (3403) · refresh_machine_kit (3434) ·
cmd_update (3497) · cmd_uninstall (3592)

**lib/selftest/** (~890 lines total): spine.sh = drill_on (2030) · ngwait (2038) · ensure_origin (2044) ·
selftest() (2056) with each labeled drill block replaced by a call to its `drill_<label>` function at
the exact same point, behind the same `drill_on` gate. Group files, one fn per label:
board.sh `fmlist grant` · history.sh `tcm express pr-publish` · report.sh `report metrics brief hint` ·
brain.sh `brain` · policy.sh `rules drift hardening qa` · remote.sh `remote syncrace notify upgrade`

## Executable check
After EVERY extraction task, in this order:
1. `bash -n kit/ops/polaris` + `bash -n` each new/changed lib file
2. `bash kit/ops/polaris help >/dev/null` (loader + dispatch alive)
3. the task's `verify:` `--only` subset(s)
4. handoff gate: full `bash kit/ops/polaris doctor --selftest` green (CONVENTIONS `test:`) — the
   byte-identical referee. No extraction lands on a red or skipped suite.

## Invariants
- **Zero behavior change.** Serial output of every command is byte-identical to pre-split for the
  same input. The ONLY new surfaces: the loader (+ its missing-lib refusal) and T-040's `--parallel`.
- Modules contain ONLY function definitions + a 1–2 line header comment. No shebang, no `set -e`,
  no top-level executable code, no top-level variable assignments. Nothing executes at source time.
- Runtime cross-module calls are free — every module is sourced before dispatch.
- bash 3.2: no `case` inside `$(...)` · no mapfile/assoc arrays · SPLIT `local` declarations (one
  `local` per line whenever a value derives from an earlier one — the T-029 lesson).
- Extracted selftest drill functions add NO `local` declarations: spine state reaches them by bash
  dynamic scoping, and a stray `local` would shadow it (e.g. `bstamp1` spans blocks).
- `SELF` stays the entry-script path; selftest keeps invoking `"$SELF"` — lib resolution rides
  `dirname $0`, so the throwaway repo needs no lib copy.
- Update self-overwrite safety: every lib is FULLY read at startup, so install.sh overwriting
  `ops/lib/` mid-`update` cannot corrupt a running process; cmd_update's re-exec guard for the
  entry file itself moves to lib/admin.sh unchanged (.github CI asserts it still exists).
- Line budgets: entry < 500 (final) · every module ≤ 1,200 · grand total
  `cat kit/ops/polaris kit/ops/lib/*.sh kit/ops/lib/selftest/*.sh | wc -l` in **[3750, 3985]**
  (baseline 3826 ± 2%, + ~80-line allowance for loader, module headers, and `--parallel`).

## Example
`bash ops/polaris status` → entry sources 13 lib files in fixed order → dispatch calls
`cmd_status` (lib/observe.sh) → which calls `cfg`/`fm_get` (lib/core.sh) — output identical to 5.15.0.
Delete `ops/lib/core.sh` → `⛔ POLARIS: ops/lib/core.sh is missing — this kit is incomplete. …` rc 1.

## Changelog
- v1 2026-07-21: created for T-039, T-040, T-041, T-042, T-043, T-044, T-045 (plan: many-hands)
