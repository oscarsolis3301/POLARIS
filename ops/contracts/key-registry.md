# CONTRACT: the key registry + 6.0 repair seams      (v1 — 2026-08-03)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
`polaris update` refreshes kit code and never rewrites CONVENTIONS.md — correct, that is what makes
updating safe — but nothing in the system compares an installed repo's config against the kit's
feature set, so every capability gated on a NEW key ships dormant. Measured: polaris-testbed runs
byte-identical kit code with a CONVENTIONS.md missing 19 keys; this repo ran two sprints with the
5.13.0 autonomy machinery switched off because no line said it existed. `cfg()` cannot distinguish
a missing key from an empty one, and doctor printed the autonomy composition ONLY when a knob was
already set — the repos most needing the message were guaranteed not to get it. This contract gives
keys a registry, doctor a drift report, and the human a discovery command. It also carries the two
6.0 repair seams (settings.json hook merge; cross-wave api-kit registry) so one file covers the
program's seams. **Autonomy itself arrives via kit-code defaults (hands-free-knobs.md v2), never by
anything here writing a live value into CONVENTIONS.md.**

## 1. `kit/ops/KEYS.tsv` — one row per CONVENTIONS key (T-074)
- TAB-separated: `key<TAB>since<TAB>default<TAB>absent-cost`. `#` comment lines and blank lines
  ignored. `since` = kit version that introduced the key. `default` = the EFFECTIVE value when the
  key is absent (the 6.0 default for the autonomy knobs, per hands-free-knobs.md v2). `absent-cost`
  = one plain-English line: what the repo loses while the key is unset.
- Ships and refreshes via `install.sh` `KIT_CODE` (both fresh and live-board paths use the same
  list). Installed copy = `ops/KEYS.tsv`, guarded by a new `path` rule in `ops/RULES.tsv` matching
  the 14 sibling rules, with a `#` comment naming who/why (Invariant 11).
- Required rows (37 — the INIT.md:104-195 skeleton keys PLUS the three `cfg` reads the skeleton
  never documents):
  `base claim integration voice autolaunch builders model_strong model_mid model_cheap autonomy
  plan_gate builder_questions evolve_apply drain drain_slices run_max_tasks run_max_minutes
  run_max_agents run_fix_waves qa_scout runnable test_fast stale_hours uat notify bootstrap
  generated publish express reports test lint typecheck build autolaunch_max
  integration_wait_minutes integration_stale_minutes`
- Rows document; they never execute. Adding a row is data, not behavior.

## 2. Doctor reports drift (T-076 — inside `cmd_doctor`, after the CONVENTIONS presence check)
- `$OPS/KEYS.tsv` missing → say nothing (pre-6.0 installed copy; the next update delivers it).
- A key counts as PRESENT when CONVENTIONS.md has `key:` at line start (live value, even empty) OR
  a commented stub whose first tokens are `# key:` — a stub means "known and deliberately unset",
  which is how `adopt` silences this line without changing any behavior.
- Any absent keys → ONE line, matching the CLAUDE.md stamp check's tone (one line, names the
  remedy, never a warning storm). Pinned shape (`<k1..k6>` = first six absent keys in KEYS.tsv
  order; drop the `+<r> more` tail when ≤6 are absent):
  `⚠ CONVENTIONS.md lacks <n> of <m> known keys (<k1> · <k2> · <k3> · <k4> · <k5> · <k6> +<r> more) — see what each unlocks: ops/polaris adopt`
- NO new top-level function — implement inline in `cmd_doctor` (api-kit surface freeze, § 5).
- NEVER embed a kit version number in the line (derived-surface golden trap).

## 3. `polaris adopt` (T-077 — `cmd_adopt` in `kit/ops/lib/admin.sh`, dispatched in `kit/ops/polaris`
   beside `update`/`upgrade`, documented in `help`)
- For every absent key (same presence test as § 2, same KEYS.tsv order): append a commented stub to
  the END of CONVENTIONS.md. First append in a file ever writes the marker line once:
  `# --- known keys not set here (polaris adopt; uncomment a line to enable it) ---`
  then per key: `# <key>: <default>   # <absent-cost> (since <since>)`
- NEVER edits an existing line, never uncomments, never reorders, never writes a live value.
  Idempotent: a second run appends nothing, leaves the file byte-identical, prints
  `nothing to adopt — all <m> known keys present or stubbed`, rc 0.
- Output otherwise: one `   + # <key>: <default>` note per appended key, then
  `✅ adopted <n> stub(s) — uncomment in ops/CONVENTIONS.md to enable; nothing changed behavior`.
- No `$OPS/KEYS.tsv` → die naming the remedy (`ops/polaris update` ships it).
- CONVENTIONS.md missing (INIT never ran) → die pointing at INIT; adopt never creates the file.
- This is the DISCOVERY mechanism. It is NOT how autonomy arrives (hands-free-knobs.md v2 is).

## 4. Update banner (T-077 — `cmd_update`, directly after the `untouched:` line at admin.sh:404)
When the incoming kit version is >= 6.0.0 AND none of `autonomy` / `plan_gate` /
`builder_questions` / `evolve_apply` is explicitly set in the target's CONVENTIONS.md, print the
two pinned BREAKING lines from hands-free-knobs.md v2 § Pinned strings. Any of the four set
(either direction) → silent. Never golden this banner (it names a version boundary).

## 5. Cross-wave surface registry — `ops/tests/api-kit.expected` has ONE owner per wave
The Learned log's earned rule (three defects, then sprint 9 held at 0 kickbacks): every new
top-level fn is pinned here so the wave's single golden owner writes the matching line without
seeing the other lane's diff.
- W1 owner T-048: adds `cmd_approve` + the generalized field writer (names per ask-approval.md).
- W2 owner T-077: adds `cmd_adopt` (its own), and writes the line for T-078's pinned
  `drill_hookmerge` (`kit/ops/selftest-install.sh`) — T-078 MUST use exactly that fn name and add
  no other top-level fn.
- W3 owner T-049: any helper it introduces in observe.sh (its own call).
- W4 owner T-080: adds `drill_adopt` (`kit/ops/lib/selftest/remote.sh`); T-050 (same wave) is
  surface-frozen — its assertions live INSIDE the existing `drill_rules`.
- Surface-frozen tasks (MUST add no top-level fn and no markdown heading anywhere under `kit/`):
  T-074, T-075, T-076, T-079, T-050. (T-074's KEYS.tsv is data; if `find --api` ever indexes it,
  the W1 owner T-048 reconciles — T-074 never touches the golden.)
- A mid-wave `api-kit` red while only one of a pinned pair has landed is the design working; the
  wave gate is the run that counts (Learned log, sprint 9).

## 6. settings.json hook merge repair (T-078 — `kit/ops/install.sh:267-297`)
Today's merge keys on hook script BASENAME and `continue`s when present, so an existing entry is
never re-examined and shipped field changes (e.g. ownership-guard timeout 10 → 20) can never
arrive. Repair, precisely scoped:
- POLARIS-OWNED entry := a `hooks[<event>][]` entry any of whose `hooks[].command` strings contains
  the path segment `ops/hooks/` (script PATH identity, never basename).
- For each kit entry (all kit entries are POLARIS-owned): an existing target entry running the same
  `ops/hooks/<script>` → REPLACE that entry wholesale with the kit's (matcher, timeout, command),
  preserving its list position; none → append (today's behavior).
- Entries that are NOT POLARIS-owned (user-added hooks) are byte-untouched, whatever script they
  run. Every non-hook key keeps today's merge semantics exactly.
- Idempotent: a second run changes nothing. The install report line extends to name updated
  entries, not only added ones.

## Executable checks
- Goldens (never a version number in either; both HERMETIC by construction — fixture repo +
  fixture KEYS.tsv with FAKE keys/versions, the triage-lane/route-tier pattern, so the real
  registry can grow without redding them):
  - `ops/tests/keys-drift.{cmd,expected}` (T-076): fixture CONVENTIONS missing fixture keys →
    doctor prints the pinned § 2 line; all keys present-or-stubbed → doctor prints nothing of it.
  - `ops/tests/adopt-stub.{cmd,expected}` (T-077): adopt appends the pinned stubs · a second run
    is a byte-identical no-op · an existing live value and an existing stub are never modified.
- Drills:
  - `drill_adopt` (T-080, `remote.sh`, new label `adopt` in spine.sh SELFTEST_LABELS): in the
    scratch repo against the REAL registry — adopt twice, second run no-op; a pre-set live value
    survives byte-identical; rc 0 both times.
  - `drill_hookmerge` (T-078, `kit/ops/selftest-install.sh`): target settings.json with a
    POLARIS ownership-guard entry pinned at `"timeout": 10` PLUS a user-added hook entry →
    re-install → the POLARIS entry carries the kit's current fields (timeout 20), the user entry
    is byte-identical, re-run changes nothing — and `drill_live_board` stays green UNCHANGED
    (the preserve guarantee is the thing being protected here).

## Invariants
- `update`/`install` NEVER write CONVENTIONS.md, RULES.tsv, MAP.md, SPRINT.md, or the board —
  `board_snapshot` (selftest-install.sh:262-292) is the proof and stays byte-identical.
- `adopt` appends comments only. It never writes, edits, or uncomments a live value.
- `doctor` drift is one line, fires only on genuine absence, and a stub silences it.
- Hard gates unchanged (hands-free-knobs.md v1 list). No new dependencies. bash 3.2 compatible
  (no `case` inside `$(...)`); Python for JSON only, stdlib only.

## Changelog
- v1 2026-08-03: created for T-074/T-076/T-077/T-078/T-080 (POLARIS 6.0.0 "autonomy by default").
