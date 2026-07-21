# CONTRACT: install-parity            (v1 — 2026-07-21)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
`ops/lib/` must reach every install path — fresh, live-board refresh, `polaris update`, the packed
zip — or the shipped CLI dies at the loader. This contract pins the exact install.sh edits, the
drill asserts that prove them, and the two installer-output tripwires that have each cost a release.
Task: T-039.

## Interface — kit/ops/install.sh (the ONLY installer edits)
BOTH named dir loops gain `lib`, nothing else changes:
- live-board branch (today's line 83):  `for d in roles templates hooks ci lib; do …`
- fresh branch (today's line 96):       `for d in roles templates hooks ci lib; do`
`KIT_CODE` (line 76) is UNTOUCHED — it lists files; lib/ is a directory and rides the dir loops.
The `chmod +x` line is UNTOUCHED — lib modules are sourced, never executed; no exec bit.
`cmd_uninstall` is UNTOUCHED — `rm -rf "$PRIMARY/ops"` already removes lib/.
`kit/ops/pack.py` is UNTOUCHED — it packs `git ls-files` output (pack.py:139), so tracked
`kit/ops/lib/**` ships automatically.

## Invariants — the two tripwires (each has already cost a release; both are asserted by
## RULES-guarded .github/ CI that NO task may edit)
1. **Quiet-install line count.** `--quiet` install prints ≤ 2 lines above the epilogue
   (.github/workflows/ci.yml:330 counts them). Adding `lib` to the dir loops must add ZERO output
   lines — the loops print nothing today; keep it that way.
2. **The INIT kickoff phrase.** No installer output — any path, any mode — ever prints the literal
   INIT kickoff phrase. Do not add epilogue text.

## Executable check — kit/ops/selftest-install.sh additions (owned by T-039)
- `drill_fresh`: after install, assert `[ -f "$T_FRESH/ops/lib/core.sh" ]`.
- `drill_live_board`: corrupt `ops/lib/core.sh` with the sentinel (alongside the existing MANUAL.md
  corruption); assert the second install repairs it and the board snapshot still `cmp`s clean.
- No other drill changes. Note: the existing drills already EXECUTE `ops/polaris` inside the install
  target (`doctor`, `uninstall`) — with the loader in place that is the strongest parity proof: a
  missed lib copy fails no-leaks/old-client loudly, today.
Run: `bash kit/ops/selftest-install.sh` — every drill green.

## Human-applied follow-ups (proposed in the sprint close report — NOT owned by any task)
- This repo's `ops/RULES.tsv` gains (human applies; RULES change = human decision):
  `ops/lib/	path	-	installed copy — edit kit/ops/lib/; refresh with: python kit/ops/pack.py --dogfood`
- `.github/workflows/ci.yml` + `release.yml` zip asserts gain a `polaris-v5/ops/lib/core.sh`
  presence line (`.github/` is RULES-guarded — agents never edit their own tests).
Meanwhile T-039 DOES edit `kit/ops/roles/INIT.md` (normal kit work): the CONVENTIONS-skeleton
write-routing row "kit code + invariants" gains `ops/lib/`, so NEW repos ship the guard from day one.

## Example
`python polaris-v5.zip` into a fresh repo → `ops/lib/` present beside `ops/polaris` →
`bash ops/polaris doctor` sources 13 modules and answers normally. A 5.15.0 board running
`ops/polaris update` → new install.sh's live-board branch lays down `ops/lib/` → the refreshed
CLI boots. (The update path on a real live board is the testbed proof — conductor-owned.)

## Changelog
- v1 2026-07-21: created for T-039 (plan: many-hands)
