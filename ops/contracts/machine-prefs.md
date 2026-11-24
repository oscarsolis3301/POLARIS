# CONTRACT: machine-prefs — your preferences, once, for every project   (v1 — 2026-11-24, plan `prefs`, 6.21.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
One file per computer holds the person's POLARIS preferences; every repo on that computer reads it
underneath its own `ops/CONVENTIONS.md`. This contract pins the file, which keys it may carry, the one
reader (`cfg`) and the readers that cannot call `cfg` (hooks, the installer, the interview), the
`polaris prefs` command, and the test isolation that keeps the owner's real file out of every fixture.
Owner decisions (plans/prefs.md, approved 2026-11-24 — the plan's yes): autonomy keys and `notify`
are eligible but settable only by a person; no machine-wide `outputStyle`; **with no machine file
every existing behaviour and every existing golden is byte-identical.**
Cards: T-333 (core, W1) · T-334 (hooks, W1) · T-337 (prefs command, W2) · T-338 (interview +
installer, W2) · T-339 (doctor line, W2) · T-340 (joined proof, W3).

## 1. The file
- Path: `$POLARIS_HOME/preferences`, where core.sh sets, at top level (a variable, zero forks, no
  api-kit row): `POLARIS_HOME="${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/polaris"`.
- Test seam `POLARIS_PREFS`: unset → the path above · set to a path → that file · **set but EMPTY →
  the machine layer is OFF** everywhere (cfg, hooks, installer, interview, prefs show). Every reader
  uses the same expansion: `m="${POLARIS_PREFS-$POLARIS_HOME/preferences}"` (hooks inline the
  POLARIS_HOME expansion; they do not load core.sh).
- Grammar = the CONVENTIONS header grammar: `key: value   # comment`; a line starting `#` is a
  comment; CRLF tolerated; leading/trailing blanks and a ` #…` tail stripped; **first match wins**;
  a blank value reads unset.
- Written only by `prefs --set/--unset/--seed` and `interview --set … --remember`, always through
  `prefs_put` (§ 6) or a temp file + `mv` — never `sed -i`, never a partial write. LF endings.

## 2. Which keys — `scope` (KEYS.tsv column 6, T-333)
Precedence: **a non-blank repo line > the machine line > the code default.** A blank repo line still
reads unset (falls through to the machine line).
- `machine` (live from the machine file) — exactly these 39, in this order (the literal allowlist):
  `voice adhd autolaunch autolaunch_max builders model_strong model_mid model_cheap effort_strong effort_mid effort_cheap autonomy plan_gate builder_questions evolve_apply drain drain_slices run_max_tasks run_max_minutes run_max_agents run_fix_waves qa_scout qa_parallel landing handover express auto_update notify heavy_slots target_minutes runner model_runner stall_minutes pulse_minutes reentry reentry_hours reentry_max away_gate bg_retries`
- `seed` — `claim` only: INIT copies the machine value into a new repo; it is NEVER read live.
- `repo` — every other KEYS row (base, integration, every command and glob key, publish, push,
  reports, stale_hours, hops, wave_check, the lease timers integration_wait_minutes /
  integration_stale_minutes / wt_live_minutes, shot, visual, port_base, serve, gallery, …).
- An unclassified key is `repo` (fail safe). A machine-file line for a non-`machine` key is ignored
  by every reader.
- **Autonomy mask:** a repo with a non-blank `autonomy:` line ignores the machine file's
  `plan_gate`, `builder_questions` and `evolve_apply` (a repo's `autonomy: standard` must beat a
  machine-level `plan_gate: auto` — the documented opt-out). The mask sees EVERY repo line,
  including lines after a blank trio line.

## 3. `cfg` (kit/ops/lib/core.sh, T-333) — the shape
No extra fork when the machine file is absent; the SAME single awk when present, the machine file
passed by ARGV position (a path through `-v` loses backslashes on Windows). Normative shape (the
plan's, with the mask rule moved ABOVE `got { next }` so a blank trio line cannot hide the mask):
```bash
cfg() { # cfg <key> <default>  — repo ops/CONVENTIONS.md > this machine's preferences > <default>
  local v="" c="" m="${POLARIS_PREFS-$POLARIS_HOME/preferences}"
  [ -f "$CONV" ] && c="$CONV"
  [ -n "$m" ] && [ -f "$m" ] || m=""
  [ -n "$c$m" ] && v="$(awk -v k="$1" -v two="${m:+1}" '
    function val(s) { sub(/\r$/,"",s); sub(/^[ \t]*/,"",s); if (s ~ /^#/) return ""
                      sub(/[ \t]#.*$/,"",s); sub(/[ \t]*$/,"",s); return s }
    BEGIN { mf = two ? ARGV[ARGC-1] : ""
            ok = index(" <the § 2 machine list, one line, single spaces> ", " " k " ")
            trio = index(" plan_gate builder_questions evolve_apply ", " " k " ") }
    mf != "" && FILENAME == mf {
      if (!ok || mask) exit
      if (index($0, k":") == 1) { s = val(substr($0, length(k)+2)); if (s != "") { print s; exit } }
      next }
    trio && index($0, "autonomy:") == 1 && val(substr($0, 10)) != "" { mask = 1 }
    got { next }
    index($0, k":") == 1 { s = val(substr($0, length(k)+2)); if (s != "") { print s; exit }; got = 1; next }
  ' ${c:+"$c"} ${m:+"$m"})"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}
```
- The allowlist is ONE literal line inside the awk (`ok = index(" … ", …)`), byte-equal to § 2's list;
  golden `cfg-layers` ties it to KEYS.tsv's `machine` rows.
- `cfg_boot` stays byte-identical (base/claim/stale_hours are not live machine keys).
  `startup-budget` stays byte-identical. cfg's def line keeps its name (api-kit row unchanged).

## 4. Readers that cannot call cfg — keep them in step
| reader | owner | rule |
|---|---|---|
| `hh_cfg` + the builtin read-loop fallback (`kit/ops/hooks/handover-hook.sh`) | T-334 | repo line non-blank, else the machine line, else default; keys read: handover, run_max_tasks, away_gate, pulse_minutes, reentry_hours |
| `_ah_cfg` (`awake-hook.sh`), `_pg_cfg` (`presence-guard.sh`), `_ph_cfg` (`permission-hook.sh`) | T-334 | same rule; keys: reentry, reentry_hours, reentry_max, stall_minutes |
| the `adhd:` read (`kit/ops/install.sh`, ~:280) | T-338 | same rule for `adhd` |
| `interview_pending` (`kit/ops/lib/admin.sh`) | T-338 | the machine file is a third awk input (by ARGV name): an `ask` key with a non-blank machine line counts as answered |
| `prefs` show (`kit/ops/lib/prefs.sh`) | T-337 | ONE awk over KEYS.tsv + CONVENTIONS + machine file, semantics identical to § 3 (mask included); golden `prefs-cli` asserts prefs value == `cfg` value for every key of its fixture |
Every hook call site reads only `machine`-scope keys, so hooks need no allowlist; none reads a trio
key, so hooks need no mask. All honour `POLARIS_PREFS` exactly as § 1. No extra fork when the file is
absent (`[ -f ]` is a builtin). `index.py`, `dashboard.py` and `install.sh`'s other reads use only
`repo` keys — unchanged.
**Prose (T-335):** one sentence, the last paragraph of PROTOCOL.md § `STATE = THE BOARD`, verbatim:
`Wherever a role file says "the value in ops/CONVENTIONS.md", it means the effective value: this repo's line, else this computer's preferences file, else the kit default — bash ops/polaris prefs shows all three and which one wins.`

## 5. Test isolation (T-333 — lands with the cfg change, never after it)
- `kit/ops/lib/check.sh`: every golden runs with `POLARIS_PREFS=` (set, empty) beside its
  `POLARIS_HEAVY_DIR=…` on all three run sites (parallel, alone, `--changed`/serial; today :673,
  :687, :773).
- `kit/ops/lib/selftest/spine.sh`: `export POLARIS_PREFS=` beside `export POLARIS_HEAVY_DIR` (~:124).
- A golden that needs the layer ON sets `POLARIS_PREFS=<fixture path>` itself. No golden, drill or
  verify line ever reads `$HOME/.claude/polaris/preferences`.

## 6. Core helpers (T-333; api-kit rows `kit/ops/lib/core.sh	fn	kit_file`, `…	fn	prefs_put`)
- `kit_file <rel>` — prints `$OPS/<rel>` when that path exists (file or dir), else `$OPS_DIR/<rel>`;
  never fails. Repo-first because the interview, keys-drift and adopt-stub goldens plant a fake
  `ops/KEYS.tsv`. Spec of its callers: `ops/contracts/doc-server.md` § 2.
- `prefs_put <key> <value>` — writes ONE key into the machine file: an existing live `key:` line
  keeps its place and its ` # …` tail, only the value changes; else the line `key: value` is
  appended (one trailing newline ensured first). Creates the file and its directory when absent,
  with this first line: `# POLARIS machine preferences — one key: value per line; a repo's ops/CONVENTIONS.md line beats this file`.
  Temp file + `mv`. rc 1 (and no write) when the layer is off (`POLARIS_PREFS` empty) or the key is
  not `machine`/`seed` scope in KEYS. Validation of the VALUE is the caller's.

## 7. `polaris prefs` (new `kit/ops/lib/prefs.sh`, T-337)
```
prefs                                  # show
prefs --set <key>=<value> [<key>=<value> …]
prefs --unset <key> [<key> …]
prefs --seed                           # owner command, once per computer
prefs --yield                          # owner command, never run by a card or the conductor
```
- **show**: one header line then one line per KEYS row, KEYS order, TAB-separated:
  `key	value	source	scope` header; rows `<key>	<effective value or ->	repo|machine|default	repo|machine|seed`.
  Last line: `machine file: <path>` · `machine file: none — bash ops/polaris prefs --seed creates it from this repo` ·
  `machine file: off (POLARIS_PREFS is empty)`. rc 0. A KEYS.tsv without column 6 → every row `repo`.
- **--set**: ALL-OR-NOTHING — every pair validated before any write. Refusals (`⛔ prefs: …`, rc 1,
  nothing written): key not in KEYS · scope `repo` (`⛔ prefs: <key> is per-project — set it in ops/CONVENTIONS.md`) ·
  value fails the row's `ask` options when the row has them (`⛔ prefs: <key> takes <v1> | <v2>, not '<v>'`) ·
  value carries TAB, newline or `#` · `model_*` value refused by core.sh `model_denied` · the line
  `<key>: <value>` matches any `content` rule of `$RULES` whose path is `ops/CONVENTIONS.md` (the RULES
  model ban; the rule's reason is printed) · **`CLAUDECODE=1` and the key is one of `autonomy plan_gate builder_questions evolve_apply`**:
  `⛔ prefs: <key> is the autonomy dial — no agent may set the dial; set it yourself from a terminal outside Claude Code: bash ops/polaris prefs --set <key>=<value>`
  · layer off. Success: `✅ prefs: <key> = <value> (every project on this computer, unless its ops/CONVENTIONS.md says otherwise)` per key.
- **--unset**: removes the key's live line(s) (temp + mv); the same dial refusal under `CLAUDECODE=1`;
  a key not set → `   prefs: <key> was not set here` (rc 0).
- **--seed**: refuses when the machine file exists (`⛔ prefs: <path> exists — --seed only creates it; change one key with --set`).
  Copies this repo's non-blank live lines of `machine`/`seed` keys (values only, comments dropped) via
  `prefs_put`; under `CLAUDECODE=1` the four dial keys are skipped and named in one note line.
  Prints `✅ prefs: seeded <n> key(s) into <path>`.
- **--yield**: in THIS repo's CONVENTIONS, comments out (`# ` prefix, temp + mv) each live `machine`-scope
  line whose value equals the machine file's; NEVER the four dial keys. Prints
  `yielded: <k> · <k> …` and, one line each, `differs: <key> (here <v> · machine <w>)`; nothing equal →
  `   prefs: nothing to yield`. Under `CLAUDECODE=1` it refuses (`⛔ prefs: --yield is an owner command — run it yourself from a terminal outside Claude Code`).
- Dispatch + loader rows are T-337's (`doc-server.md` § 1). `readonly-allow.sh` approves bare
  `prefs` only (T-334).

## 8. Interview (admin.sh, T-338 — no new function definitions; first-run.md v2 is the INIT side)
- `interview --init` works with NO `ops/CONVENTIONS.md`: for every KEYS row with an `ask` column, a
  non-blank machine line prints `ANSWERED	<key>	<value>	machine`; every other ask row prints its
  QUESTION/OPTION lines exactly as plain mode does. Nothing else is printed; rc 0. Layer off → every
  ask row is a question.
- `interview --set <k>=<v> … --remember`: unchanged validation and writes, then, for each pair whose
  key has no non-blank line in the machine file, `prefs_put <k> <v>` (existing machine lines are never
  overwritten). Layer off → `--remember` writes nothing, says nothing.
- Every existing form (`interview`, `--pending`, `--set` without `--remember`) is byte-identical.

## 9. Doctor (observe.sh `cmd_doctor`, T-339)
Only when the machine file exists (layer on), ONE line directly after the autonomy composition line:
`   machine preferences: <path> — bash ops/polaris prefs shows which keys it sets here`
No machine file → doctor output byte-identical.

## Executable checks
- `ops/tests/cfg-layers.{cmd,expected}` (T-333): repo > machine > default · blank repo line falls
  through · `autonomy: standard` masks a machine `plan_gate: auto` (and with a blank `plan_gate:` line
  ABOVE the autonomy line) · a machine line for a `repo` key (e.g. `base`, `test`) ignored · CRLF
  machine file · a machine path containing a backslash (Windows form) · `POLARIS_PREFS=` (empty) =
  off · no CONVENTIONS + machine file → machine value · the allowlist literal == KEYS.tsv `machine` rows.
- `ops/tests/prefs-cli.{cmd,expected}` (T-337): show / set / unset / seed / yield, every § 7 refusal,
  prefs value == cfg value for every key of the fixture.
- `ops/tests/doctor-prefs.{cmd,expected}` (T-339): no file → doctor unchanged (the provenance line
  absent); file → the § 9 line once.
- `ops/tests/interview.{cmd,expected}` (T-338): existing lines byte-identical; `--init` and
  `--remember` cases APPENDED.

## Invariants
- No machine file → every existing golden byte-identical, no new output, no new fork.
- The harness never reads the real machine file (§ 5).
- No agent sets the autonomy dial on the machine file (§ 7); EVOLVE never writes it.
- `prefs --yield` and `prefs --seed` are owner commands; no card's verify or the conductor runs them.
- No new runtime dependency (bash + awk + git, as today).

## Changelog
- v1 2026-11-24: created for plan `prefs` (T-333 · T-334 · T-337 · T-338 · T-339 · T-340).
