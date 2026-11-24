# Your preferences, once (kit 6.21.0) — plan slug `prefs`

Phase 3 of the owner-approved program (approved 2026-11-24; full text:
`C:\Users\oscar\.claude\plans\i-d-like-for-you-iterative-stearns-of-92029365-0619-40e8-8939-d1581417c574.md`).
Phase 2 (`walk-away`, 6.20.0) shipped 2026-11-24. Phase 4 (`one-kit`, 7.0.0) is cut after this ships.

## The owner's words (2026-11-24)
"install it so that one installation works for all projects ... in the future one POLARIS installation
is necessary for ALL projects on the computer using the same preferences from the POLARIS install."

## Owner decisions recorded with the approval (the plan's yes — do not re-ask)
- Machine preferences include the autonomy keys and `notify`, settable only by a person (an agent
  `prefs --set` of an autonomy key refuses under `CLAUDECODE=1`).
- No machine-wide `outputStyle`; per-repo seeding is unchanged in this release.
- Existing installs behave byte-identically until a machine file exists.
- "Human only" write-routing rows are in scope: `kit/CLAUDE.md`, `kit/ops/polaris`, `kit/ops/hooks/*`.
- WON'T touch: `.github/` · `ops/` by hand · RULES lines (new lines allowed with a who/why comment) ·
  `ops/CONVENTIONS.md` values (`prefs --yield` is a command the OWNER runs, never a card) · other
  projects · no new runtime dependency.

## A. The machine preferences file
- `<claude home>/polaris/preferences` (claude home = `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`), same
  `key: value` grammar as CONVENTIONS. Test seam `POLARIS_PREFS` (set but EMPTY = layer off).
  Precedence: a repo line > the machine line > the code default. A blank repo line still reads unset.
- Eligible (live from the machine file): voice, adhd, autolaunch, autolaunch_max, builders, model_*,
  effort_*, autonomy, plan_gate, builder_questions, evolve_apply, drain, drain_slices, run_max_*,
  run_fix_waves, qa_scout, qa_parallel, landing, handover, express, auto_update, notify, heavy_slots,
  target_minutes, and the 6.20.0 person-level keys (runner, model_runner, effort_runner,
  stall_minutes, pulse_minutes, reentry*, away_gate, bg_retries — check KEYS.tsv for the exact set).
  Seed-only: `claim` (INIT copies it into the repo; never read live). Never: base, every command and
  glob key, publish, push, reports, stale_hours, integration, hops, wave_check, `*_minutes` lease
  timers. Encoding: a literal allowlist inside `cfg`'s awk (fails safe: an unclassified key is
  repo-only); a new 6th KEYS.tsv column `scope` (repo|machine|seed) documents it; a golden ties the
  allowlist and the column together.
- `cfg` (`kit/ops/lib/core.sh:8-28`): no extra fork when the file is absent; the SAME single awk
  when present, the machine file passed by ARGV position (a path through `-v` loses backslashes on
  Windows). Shape (from the Phase-4 design study):
  ```bash
  cfg() { # repo CONVENTIONS.md > this machine's preferences > <default>
    local v="" c="" m="${POLARIS_PREFS-${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/polaris/preferences}"
    [ -f "$CONV" ] && c="$CONV"
    [ -n "$m" ] && [ -f "$m" ] || m=""
    [ -n "$c$m" ] && v="$(awk -v k="$1" -v two="${m:+1}" '
      function val(s) { sub(/\r$/,"",s); sub(/^[ \t]*/,"",s); if (s ~ /^#/) return ""
                        sub(/[ \t]#.*$/,"",s); sub(/[ \t]*$/,"",s); return s }
      BEGIN { mf = two ? ARGV[ARGC-1] : ""
              ok = index(" <allowlist> ", " " k " ")
              trio = index(" plan_gate builder_questions evolve_apply ", " " k " ") }
      mf != "" && FILENAME == mf {
        if (!ok || mask) exit
        if (index($0, k":") == 1) { s = val(substr($0, length(k)+2)); if (s != "") { print s; exit } }
        next }
      got { next }
      index($0, k":") == 1 { s = val(substr($0, length(k)+2)); if (s != "") { print s; exit }; got = 1; next }
      trio && index($0, "autonomy:") == 1 && val(substr($0, 10)) != "" { mask = 1 }
    ' ${c:+"$c"} ${m:+"$m"})"
    [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
  }
  ```
  `mask`: a repo's `autonomy: standard` must beat a machine-level `plan_gate: auto` (the documented
  opt-out). `cfg_boot` stays byte-identical (its keys are repo-only); `startup-budget` unchanged.
- Other readers to keep in step: `kit/ops/hooks/handover-hook.sh:77-84,187,193` (`hh_cfg`, builtin
  read loop fallback), `kit/ops/install.sh:280-281` (adhd grep), `interview_pending`
  (`kit/ops/lib/admin.sh:1535-1555`, machine file as a third awk input). `index.py`, `dashboard.py`
  and `install.sh:632` read only repo-only keys and need nothing. One PROTOCOL sentence defines
  "the value in ops/CONVENTIONS.md" in role prose as the effective value.
- Test isolation (must land with or before the cfg change): `POLARIS_PREFS=` beside
  `POLARIS_HEAVY_DIR` in `kit/ops/lib/check.sh:673,687,773` and `kit/ops/lib/selftest/spine.sh:123-124`,
  so the owner's real preferences never leak into fixture repos.

## B. `polaris prefs` (new `kit/ops/lib/prefs.sh`)
- `prefs` prints key · value · source (repo | machine | default) for every KEYS row.
- `prefs --set k=v…` / `--unset k…` write the machine file (temp file + mv); refuse non-eligible
  keys and forbidden models (the RULES model ban); under `CLAUDECODE=1` refuse the four autonomy
  keys ("no agent may set the dial", hands-free-knobs).
- `prefs --seed` creates the machine file from THIS repo's eligible lines (the owner runs it once in
  the POLARIS repo).
- `prefs --yield` comments out, in this repo, eligible lines equal to the machine's and lists the
  ones that differ (an owner command; never run by a card or the conductor).
- `interview --init` works before CONVENTIONS exists and prints `ANSWERED key value machine`;
  `interview --set … --remember` also records answers in the machine file when it has none. Existing
  forms byte-identical. `doctor` adds one provenance line only when a machine file exists.

## C. Setup questions once per machine
- `kit/ops/roles/INIT.md`: interaction 1 asks only what the machine file does not answer; all
  answered → skip it entirely. INIT still writes `voice:`/`adhd:`/`claim:` into the new repo from the
  machine's answers (every existing reader works), and writes stubs instead of live lines for the
  other eligible keys (KEYS defaults equal the skeleton's values, so a machine without preferences
  behaves the same). Spec: `ops/contracts/first-run.md` new `## v2`.

## D. Groundwork for the shared kit (no change for today's installs)
- The CLI locates its own code: `kit/ops/polaris:8` becomes
  `case "${BASH_SOURCE[0]}" in "$0") OPS_DIR="$(cd "$(dirname "$0")" && pwd)";; *) OPS_DIR="${BASH_SOURCE[0]%/*}";; esac`,
  `:426` `SELF="$OPS_DIR/${BASH_SOURCE[0]##*/}"`, plus `KIT_MODE=machine|vendored` from the path.
- One `kit_file <rel>` lookup (repo copy if present, else `$OPS_DIR/<rel>`; repo-first because the
  interview, keys-drift and adopt-stub goldens plant a fake `ops/KEYS.tsv`) replaces the reads of
  kit files through the state dir: `polaris:425` (VER), `admin.sh:66-67, 1324, 1353, 1505-1506,
  1541, 1563, 1586, 1743, 685, 919, 1907, 1001-1023`, `observe.sh:513, 529, 668-677, 710-716,
  727-759, 977`, `search.sh:32, 36`, `awake.sh:12, 44, 119`, `hooks/ownership-guard.sh:220, 229,
  314-315, 369`, `hooks/update-hook.sh:81, 86, 96` (line numbers as of 6.19.0; re-find them).
- One machine-home resolver replaces the scattered `$HOME/.claude/polaris` literals (honours
  `CLAUDE_CONFIG_DIR`; today `claude_home()` lives in admin.sh, which hooks never load).
- A doc server: `polaris role <NAME>` (paged at `##` boundaries — Bash inlines ~30,000 chars and
  CONDUCTOR.md is ~37k), `polaris doc <FILE> "<section>"`, `polaris router`; works in both layouts;
  `readonly-allow.sh` `polaris_ok` approves them. Rewrite the ~78 prose references (roles 32,
  PROTOCOL 21, MANUAL 7, PROMPTS 2, VISUAL 2, templates 12, KEYS 2) and ~17 printed strings to the
  command form. Keep `install.sh:609`'s literal `read ops/roles/INIT.md` (ci.yml:331 greps it).

## Also in this release (from the walk-away EVOLVE, owner applies by plan approval)
- EVOLVE finding 1 (bug): `landed_content_ok` (`core.sh` ~:738) treats a path another task's
  `[<ID>]` commit changed after this task's fork point as shared wave work, never re-landed (the
  exact diff is in sprint-28's EVOLVE report; golden: `landed-seal` case b2). Contract
  `safe-landing.md` new v1.4 note.
- EVOLVE finding 2: CONVENTIONS § Planner calibration line (census goldens ride every card that
  feeds them: keys-drift for kit/ops/polaris|lib edits, rules-health for RULES edits) — the
  conductor appends it as the owner-approved calibration note; and a `surface:` item on the first
  card that owns ops/RULES.tsv mapping it to `ops/tests/rules-health.*`.
- EVOLVE finding 3 (in-wave fix cards cut from the open wave) is Phase 4 material; leave it.

## DONE looks like
- With no machine file every existing golden is byte-identical; `cfg-layers` precedence matrix
  (repo > machine > default, blank repo line, `autonomy: standard` mask, non-eligible key ignored,
  CRLF machine file, backslash path); the harness never reads the real machine file.
- `prefs` show/set/unset/seed/yield with refusals; INIT asks nothing the machine file answers.
- `role`/`doc`/`router` serve both layouts; zero prose references left to `ops/roles/` paths
  (golden `doc-refs`); the CLI runs from a kit dir with no `lib/` beside the repo state (drill).
- `landed-seal` b2 green; `finish` exit 0; release ritual complete (6.21.0 everywhere).
