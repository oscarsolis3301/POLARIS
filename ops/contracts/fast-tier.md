# CONTRACT: fast-tier            (v1 — 2026-09-08)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
A verification tier that is genuinely SECONDS: one in-process pass over the kit's pure functions,
with ZERO `polaris` re-invocations and no throwaway git repo. Today's `test_fast:` is 320s because it
is still four full drills, each spawning the CLI dozens of times at ~57ms per git fork on Windows.
This tier sits BESIDE the drills (never instead of them): the drills keep proving the real entry
point at the wave gate and in CI; this tier proves the logic on every change. Tasks: T-122 (the
tier), T-126 (extends it with the auto-update gates), T-127 (makes it this repo's `test_fast:`).

## Interface — CLI (T-122, `cmd_doctor` in `kit/ops/lib/observe.sh`)
```
polaris doctor --fast        # doctor's env check, then the in-process tier; rc 0 all green / rc 1 any red
```
- Exactly like `--selftest`, `--fast` is read as `$1` of `cmd_doctor` after the env check; no other
  flag combines with it (`--fast --only x` → `⛔ doctor --fast takes no options`, rc 1).
- The tier is `selftest_fast` in the NEW module `kit/ops/lib/selftest/fast.sh`, added to the
  loader's default `_mods` list in `kit/ops/polaris` as the LAST selftest entry (`selftest/fast`),
  never to the `_match|_rules|_guard` list (the guard path must not pay for it).
- `help` gains the flag on the existing doctor line:
  `doctor [--selftest [--only <patterns>] [--parallel <N>] | --fast]` — and ONE indented line under
  the existing `--only` explanation: `doctor --fast = the in-process tier: pure functions, no CLI
  re-invocation, no scratch repo — seconds` (`ops/tests/cli-help.expected` refreshes by content diff).

## Shape of the run (pinned — the log-and-poll recipe and the drill grep for these)
```
✅ fast: <section>                          # one line per section, in the order below
⛔ FAST <SECTION> FAIL (<what was expected>) # any red; the run CONTINUES — one pass paints the whole picture
✅ fast tier passed — <n> checks in <s>s     # last line, rc 0; absent on any red (rc 1)
```
`<n>` counts individual `ft_assert` calls; `<s>` is wall seconds (`date +%s` twice — the tier's only
permitted `date` forks). No `say`/`note` indentation games: `✅`/`⛔` at column 0, as `qa` prints.

## Shared types — the module (`kit/ops/lib/selftest/fast.sh`, ≤ 400 lines, bash 3.2, `set -u` clean)
Exactly THREE top-level functions (the W1 api-kit rows T-122 writes):
- `ft_section <name>` — prints the section's `✅ fast: <name>` line ONLY if no `ft_assert` in it failed.
- `ft_assert <label> <cmd…>` — runs `"$@"` as a bash command (a function call, never a subprocess),
  counts it, and on non-zero prints `⛔ FAST <SECTION> FAIL (<label>)`.
- `selftest_fast` — the run. Sources NOTHING (the loader already did); overrides globals in a
  SUBSHELL per section (`( BOARD=… LOCKS=… CONV=… PRIMARY=…; … )`) so nothing here can touch the
  live board — the tier never writes under `$PRIMARY`; every fixture lives in ONE `mktemp -d`,
  removed by trap.
**Fork budget:** ONE `mktemp -d`, TWO `date +%s`, one subshell per section. No `git` at all. No
`"$SELF"`. `grep`/`sed` inside the functions under test are theirs, not the tier's.

## Minimum check set (v1 — T-122; implementer may add, never remove)
| section | what is proven, in process |
|---|---|
| `semver` | `semver_gt`: 6.2.10>6.2.9 · 7.0.0>6.9.9 · 6.3.0>6.2.2 · NOT 6.2.2>6.2.2 · NOT 6.2.2>6.3.0 · 10.0.0>9.9.9 |
| `frontmatter` | `fm_get` scalar + trailing `# comment` + `\r` stripped · `fm_list` on `[]`, flow `[a, b]`, block `- x` list, messy spacing (from a temp task file) |
| `cfg` | `cfg key default` from a temp CONVENTIONS: value · comment stripped · absent → default · empty value → empty (not default) |
| `ownership` | `owned_match`/`match_one`: exact · `dir/` prefix · glob crossing `/` (`src/api/util_*.py` vs `src/api/x/util_a.py`) · non-match rc 1 |
| `ids` | `id_ok` accepts `T-9`, rejects empty and literal `feat` (rc 1) |
| `commit-msg` | `cmd_task_commit_msg <temp task>`: line 1 = `type(scope): title [ID]`, body carries the `## Why` text |
| `json` | `jesc` escapes `"` and `\`, drops newlines |
| `rules` | `rules_lines` over a temp `ops/RULES.tsv`: comments/blank/CR dropped, all three kinds (`path` `content` `ask`) survive |
| `awake-conf` | `awake_conf`: env `POLARIS_AWAKE_TICK` beats the config file beats the default |
| `bg` | `bg_age` humanizes 42→`42s`, 420→`7m`, 10800→`3h` |

## Executable check
Test file: this module IS the check. Owned by T-122; listed in T-127's `verify:`:
`bash kit/ops/polaris doctor --fast` → last line matches `fast tier passed — [0-9]+ checks in [0-9]+s`, rc 0,
and T-122 records the measured wall time in the task Notes AND in `kit/ops/PROTOCOL.md` § LONG
COMMANDS's table as a new ROW (no new heading): `| \`doctor --fast\` — the in-process tier | <s>s | yes |`.
Budget: **≤ 15s on Windows/Git Bash**, target ≤ 5s. Over 15s = the tier forked; find the fork.

## Invariants
- The tier NEVER shells out to `polaris`, never `git init`s, never reads the live board, never writes
  under `$PRIMARY`. A check that needs a repo belongs in a labeled DRILL, not here.
- Plain `doctor`, `doctor --selftest`, `--only`, `--parallel` are byte-identical to today.
- bash 3.2: no `case` inside `$(...)`, no `mapfile`, no `wait -n`.
- v2 rule for extenders (T-126): new sections go INSIDE `selftest_fast` — no new top-level fn.

## Example
```
$ bash kit/ops/polaris doctor --fast
✅ doctor: OK
✅ fast: semver
✅ fast: frontmatter
…
✅ fast tier passed — 41 checks in 3s
```

## Changelog
- v1 2026-09-08: created for T-122, T-126, T-127 (plan feel-fast)
