# CONTRACT: verification-tiering            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates targeted re-checking (`doctor --selftest --only` — T-033; slow-suite hint in `land` +
duration stamp in `qa` — T-031) from the full gates, which stay untouched: check what changed often,
prove everything once.

## Interface — `doctor --selftest --only <pattern>` (T-033)
```
polaris doctor --selftest                    # unchanged: every drill, byte-identical semantics,
                                             # pass line still starts `selftest passed`
polaris doctor --selftest --only <pattern>   # SPINE + only labeled drills whose label matches
                                             # <pattern> (one shell glob, case-glob match)
```
- **Spine** (always runs — it builds the throwaway repo's state): bootstrap + the core mechanics
  chain (race → ownership/verify → handoff → land → seal → history → done → rollback → second seal →
  quiet-board assertions). The spine is not skippable and has no label.
- **Labeled drills**: every self-contained section AFTER/AROUND the spine gets a label via a tiny
  `drill_on <label>` helper (plain `case`/pattern match — NEVER inside `$(...)`). Minimum label set
  (implementer may add more, never fewer): `fmlist` `tcm` `report` `rules` `drift` `metrics` `qa`
  `notify` `grant` `upgrade` `pr-publish` `brain` `express` `brief` `hint`.
- Pattern matching NOTHING in the label list → die BEFORE the spine, listing the valid labels
  (message contains `unknown drill label`). Fail loud — a no-op subset must never look green.
- Subset pass line is DISTINCT: starts `selftest passed (subset:` and names the pattern + counts —
  a subset run can never be mistaken for the full gate.

## Interface — suite-duration stamp + slow-suite hint (T-031)
```
.polaris/last-suite-seconds     # one line: "<seconds> <epoch>" — written by qa after its
                                # test/lint/typecheck/build/uat loop, only when ≥1 command ran
```
- `land <ID>` (both forms), after a successful land: if CONVENTIONS `integration:` = `paranoid` AND
  the stamp exists AND seconds > 120 → print ONE note containing `suite last took` and
  `integration: batch` (the batch-first guidance, made mechanical). Silent when: no stamp · `batch` ·
  ≤120s. Never changes exit status.

## Executable check (rides the kit selftest)
- T-033 drills: `--only` with a nonsense pattern → rc 1 + `unknown drill label` (cheap, pre-spine);
  `--only fmlist` → rc 0 + pass line starts `selftest passed (subset:`.
- T-031 drills: fake stamp `180 <epoch>` + `integration: paranoid` → land output matches
  `suite last took`; `integration: batch` same stamp → no such line.
Run: `bash kit/ops/polaris doctor --selftest`.

## Invariants
- Full-suite semantics untouched: no drill deleted, no assertion weakened, plain `--selftest`
  behavior identical. `qa` remains the unchanged, full, final gate in every flow.
- Bash >= 3.2; no `case` inside `$(...)`.

## Example
```
$ ops/polaris doctor --selftest --only 'express'
…
selftest passed (subset: express — 1 of 15 labeled drills; spine always runs)
$ ops/polaris land T-042        # paranoid repo, suite stamp 178s
✅ landed T-042 …
⚠ suite last took 178s (>2 min) — paranoid re-runs it per land; consider integration: batch
```

## Changelog
- v1 2026-07-20: created for T-031 (stamp + hint) · T-033 (--only)

## v2 — the express lane carries its suite verdict to `finish` (2026-09-08, plan feel-fast, 6.3.0)
Measured cause of a 20-minute duplicate: `cmd_land_express` (kit/ops/lib/integrate.sh) runs the FULL
suite at step 3 but never writes `.polaris/suite-stamp`; only `cmd_qa` does. So under
`landing: integrator` the next `finish` runs the identical suite again over the identical tree.
- NEW fn `suite_stamp_carry <tested-sha>` in integrate.sh (T-123; the W1 api-kit row T-122 writes).
  Called ONCE, as the LAST thing express does before its closing `say` (after `cmd_done`, after the
  integrate branch is deleted), in the primary on `<base>`. It writes `.polaris/suite-stamp` as
  `"<HEAD-sha> <epoch>"` — the SAME shape `cmd_qa` writes and reads — ONLY when ALL hold:
  the tree is clean (same porcelain read as qa) · `<tested-sha>` is an ancestor of HEAD ·
  `git diff --name-only <tested-sha> HEAD` lists NOTHING outside `$(cfg reports docs/sprints/)`
  and `ops/MAP.md` (the two things seal and done write after the suite ran). Otherwise it prints
  `⚠ suite stamp withheld — HEAD gained more than the sprint report since the suite ran; finish will
  re-run it` and writes nothing. Never changes express's exit status.
- `<tested-sha>` = `git rev-parse HEAD` taken right after step 3's last green, on integrate/<date>.
- Express also writes `.polaris/last-suite-seconds` (`"<seconds> <epoch>"`, wall time of step 3's
  loop) when ≥ 1 suite command ran — the slow-suite hint reads it, same as after `qa`.
- `cmd_qa` is UNTOUCHED: the stamp it finds is exactly the stamp it would have written.
- Drill (inside the existing `drill_express`, history.sh — surface-frozen, no new drill fn): after
  the happy-path express, line 1 of `.polaris/suite-stamp` equals `git rev-parse main` and `qa`
  prints `suite already green`; then a commit on main → `qa` runs the suite again (stamp keyed on
  the commit, exactly as before). Assert file content and rc, never the message alone.
- Self-landing (`landing: self`) runs NO suite by design; nothing changes there — `finish` remains
  that path's one full run, now sharded (ops/CONVENTIONS.md `test:`), and the in-process tier
  (ops/contracts/fast-tier.md) is the per-change gate.
