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
  `cat kit/ops/polaris kit/ops/lib/*.sh kit/ops/lib/selftest/*.sh | wc -l` in **[3750, 4120]**
  (relocation band 3826 ± 2% + the `--parallel` sharding feature as MEASURED at ~150 lines —
  in-scope new code, not relocation drift — + 10 module headers ~25; v1's ~80-line allowance
  under-counted the sharding implementation: measured total was 3998 pre-T-042, ~4008 expected final).

## Example
`bash ops/polaris status` → entry sources 13 lib files in fixed order → dispatch calls
`cmd_status` (lib/observe.sh) → which calls `cfg`/`fm_get` (lib/core.sh) — output identical to 5.15.0.
Delete `ops/lib/core.sh` → `⛔ POLARIS: ops/lib/core.sh is missing — this kit is incomplete. …` rc 1.

## v2 — the loader becomes need-scoped (2026-07-25, token/wall-clock audit)

**Why v1's verbatim pin had to move.** The PreToolUse write-guard (`ops/hooks/ownership-guard.sh`)
calls `polaris _rules` AND `polaris _match` on **every** Edit/Write/MultiEdit. Under v1 each call
sourced all 14 modules — **248,879 B, of which those two commands need 22,704 B (core + ownership):
90% waste.** Measured cost ~2 s per invocation, ~4.4 s per write. `.claude/settings.json` gives the
guard a **10 s** timeout, so with parallel builders it exceeded the budget and the guard **failed
open** — silently dropping the ownership gate mid-wave. This is therefore a CORRECTNESS fix that
happens to also be a cost fix; v1's pin was actively unsafe.

`_match`/`_rules` call exactly: `fm_list` `task_file` (core) · `owned_match` `rule_scan_path`
`rule_scan_content_file` (ownership). Nothing else. Verified by reading both function bodies.

**The loader — pinned verbatim, v2:**
```bash
# --- lib loader: every function body lives in lib/ — fixed order, core first ---
# The write-guard calls _match/_rules on EVERY edit and needs only core+ownership (22KB of 249KB).
# Sourcing all 14 there cost ~2s/call — twice per write against a 10s hook timeout, which under
# parallel builders EXCEEDED it and made the guard fail OPEN. Load what the command needs.
OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  _match|_rules) _mods="core ownership" ;;
  *)             _mods="core ownership builder integrate knowledge observe admin
                        selftest/spine selftest/board selftest/history selftest/report
                        selftest/brain selftest/policy selftest/remote" ;;
esac
for _m in $_mods; do
  if [ ! -f "$OPS_DIR/lib/$_m.sh" ]; then
    printf '⛔ POLARIS: ops/lib/%s.sh is missing — this kit is incomplete. Re-run the installer (bash ops/install.sh) or fetch a fresh kit: ops/polaris update\n' "$_m" >&2
    exit 1
  fi
  . "$OPS_DIR/lib/$_m.sh"
done
unset _m _mods
```
- Both v1 rules survive: the missing-lib message is still raw `printf` (core.sh may be what's
  missing), and both lists are still LITERAL, never a glob.
- The `case` is at top level, NOT inside `$(...)` — the bash 3.2 restriction is unaffected.
- `_mods` is unquoted on purpose in `for _m in $_mods` (word-splitting is the mechanism); this is
  the one place `set -u` word-splitting is intended. Names contain no globs or spaces.
- **Scope discipline:** ONLY `_match`/`_rules` get the short list. Every other command keeps the
  full 14 — a subcommand that silently lost a module would fail far from its cause.

### v2 grand-total band: [3750, 4120] → [3750, 4300]

v1.1's ceiling was derived before the 2026-07-25 performance work and is now exceeded. Itemized
re-derivation from the measured 4058 at v1.1:

| delta | lines | why |
|---|---|---|
| `cfg` one-awk rewrite (`core.sh`) | +12 | was a 5-fork pipeline at ~1.2s/call on Windows; the globals block calls it 4+ times on EVERY invocation |
| need-scoped loader `case` (entry) | +9 | this contract's v2 above |
| `cmd_guard` (`ownership.sh`) | +18 | merges the write-guard's two polaris startups into one |
| `cmd_board_fm` (`observe.sh`) | +24 | kills the Planner's ~40k-token board read |
| **measured total** | **4131** | over v1.1's 4120 |
| planned: `search.sh` shim | +90 | `polaris find`/`show`; all real logic lives in `ops/index.py`, which this band does NOT count |
| planned: `selftest/search.sh` | +45 | its drills |
| **projected** | **~4266** | +34 headroom under the new 4300 |

The band exists to stop logic creeping back into the entry script and to keep modules readable — it
is not a cap on the CLI's capability. Entry `< 500 lines` and per-module `≤ 1,200` are UNCHANGED and
remain the real structural guards. **Design consequence, and the right one:** because `ops/index.py`
is not counted, the band actively pushes indexing logic into python and keeps `search.sh` a thin
shim — which is also what makes a native engine a drop-in later.

## v3 — lib/workspace.sh joins the census (2026-08-03, plan n-chats-one-repo)

New module `kit/ops/lib/workspace.sh` (T-057, ≤350 lines): `id_ok` · `wt_add` ·
`stray_feat_repair` · `int_on` · `int_off` · `wave_on` · `park` · `unpark` · `cmd_park` ·
`cmd_unpark` — semantics in `ops/contracts/shared-checkout.md`, which is the authority on their
behavior; THIS contract stays the authority on where code lives and the loader's shape.

**The loader, v3:** the FULL-load `_mods` list gains `workspace`, inserted between `ownership` and
`builder` (builder/integrate call workspace fns at dispatch time). The `_match|_rules|_guard`
guard path stays EXACTLY `core ownership` — the write-guard never touches workspace, and its
latency budget (v2's whole point) must not pay for it. Both lists stay LITERAL, never a glob.

**Census corrections + budget honesty:**
- v1's core.sh header says "33 fns" but its NAMED list counts 34 — the NAMED list is and was
  authoritative (census audited green at the sprint-6 close); header corrected here per the
  Learned log's instruction to fix it on the next version bump.
- The v1/v2 line-budget bands ([3750,4300]) and the per-module ≤1,200 cap described the SPRINT-6
  RELOCATION and are HISTORICAL: five feature sprints later the tree measures ~6,080 and
  observe.sh alone is 1,648. Binding going forward: entry `kit/ops/polaris` < 500 lines ·
  workspace.sh ≤ 350 · new fns land in the module this census names, never in the entry script.
  Re-legislating the other modules' sizes is future grooming, not this sprint's scope.

## v4 — lib/bg.sh joins the census (2026-08-03, plan routing-and-bg)

New module `kit/ops/lib/bg.sh` (T-070, ≤300 lines): the background job runner — `cmd_bg` dispatch
plus `bg_`-prefixed workers (intended census in `ops/contracts/bg-jobs.md` § Module census; the
landed api-kit delta is authoritative on final names). Registry `$PRIMARY/.polaris/bg/<name>/` is
runtime state, never tracked. bg-jobs.md is the authority on behavior; THIS contract stays the
authority on where code lives and the loader's shape.

**The loader, v4:** the FULL-load `_mods` list gains `bg`, inserted immediately after `admin`.
The `_match|_rules|_guard` guard path stays EXACTLY `core ownership` — the write-guard's latency
budget (v2's whole point) never pays for job plumbing. Both lists stay LITERAL, never a glob.

## v5 — lib/awake.sh and lib/handover.sh join the census (2026-09-01, plan cant-eat-itself, 6.2.0)

Two new modules (T-101 owns the loader and `lib/awake.sh`; T-109 owns `lib/handover.sh`):
- `kit/ops/lib/awake.sh` (≤150 lines): `awake_home` · `awake_conf` · `awake_ensure` · `awake_status_line` ·
  `cmd_awake` — semantics in `ops/contracts/keep-awake.md`.
- `kit/ops/lib/handover.sh` (≤300 lines): `cmd_next` · `next_dir` · `next_route` · `next_landable` ·
  `next_claimable` · `next_promote` · `next_budget` · `next_brief` — semantics in `ops/contracts/role-handover.md`.
THIS contract stays the authority on where code lives and the loader's shape.

**The loader, v5:** the FULL-load `_mods` list gains `awake` immediately after `bg`, then `handover`
immediately after `awake` (`… admin bg awake handover selftest/spine …`). The `_match|_rules|_guard` guard
path stays EXACTLY `core ownership`. Both lists stay LITERAL, never a glob.

**The entry preamble (T-101):** the worktree beat touch (worktree-liveness.md § beat writers) is ONE
builtins-only `case` placed BELOW the `EVENTS=` line and ABOVE the dispatch `case` — after the loader, so it
never runs on the guard path, and before any command, so every CLI call from inside a worktree beats.
`awake_ensure || true` calls sit INSIDE the dispatch arms for `claim`, `status`, `doctor`, `handoff` and
`bg run` (bg's arm tests `"$2" = run`), never above the dispatch. `startup-budget` golden unchanged.

**Hooks are not modules** but are counted here so the census stays complete: `kit/ops/hooks/awake-hook.sh`
(≤320) and `kit/ops/hooks/handover-hook.sh` (≤220) are standalone scripts that never source `lib/`
(hook latency: the ownership-guard lesson). `kit/ops/hooks/awake-press.ps1` (≤80) is not indexed.

**Budgets, binding:** entry `kit/ops/polaris` < 500 lines (today 332; this sprint adds ≈20) · awake.sh ≤ 150 ·
handover.sh ≤ 300 · workspace.sh ≤ 350 stays (T-092 adds ≈90 to today's ≈210) · new fns land in the module
this census names, never in the entry script.

## Changelog
- v4 2026-08-03: bg.sh joins the census (≤300 lines, fn census in bg-jobs.md); loader full-load
  list gains `bg` after `admin` (guard path unchanged).
- v3 2026-08-03: workspace.sh joins the census; loader full-load list gains `workspace`
  (guard path unchanged); core.sh 33→34 header count corrected (named list authoritative);
  v1/v2 line bands marked historical — binding: entry <500, workspace ≤350.
- v2 2026-07-25: loader is need-scoped for `_match`/`_rules`/`_guard` (guard hot path) — correctness
  fix, the guard was exceeding its 10s hook timeout and failing open. Grand-total band
  [3750, 4120] → [3750, 4300], itemized above. Entry <500 and per-module ≤1,200 UNCHANGED.
- v1 2026-07-21: created for T-039, T-040, T-041, T-042, T-043, T-044, T-045 (plan: many-hands)
- v1.1 2026-07-21: grand-total band [3750, 3985] → [3750, 4120] — v1 under-counted T-040's
  deliberate `--parallel` code (~150 measured lines) + 10 module headers; band re-derived itemized
  (T-042 builder's measurement: 3998 on main pre-T-042). Entry <500 and per-module ≤1,200 UNCHANGED.
- v5 2026-09-01: lib/awake.sh (5 fns, ≤150) and lib/handover.sh (8 fns, ≤300) join the census; loader `+awake +handover` after `bg`; entry preamble beat is builtins-only below `EVENTS=` (T-101, T-109; plan cant-eat-itself).
