# CONTRACT: auto-update            (v1 — 2026-09-08)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Installed POLARIS repos go stale (measured 2026-09-08: three repos on 6.0.0 / 5.23.0 / unversioned
while the fixes for their own slow landing tail had shipped here months earlier). This seam makes
every repo update ITSELF at session start when it is safe, gives one command for the repos you do
not happen to open, and makes the machine registry complete. Tasks: T-124 (the engine, in
`kit/ops/lib/admin.sh`), T-125 (the SessionStart hook + installer registration), T-126 (the drill +
fast-tier gates). Owner decisions this encodes (2026-09-08): minor/patch apply silently · a MAJOR
bump asks · off switch defaults ON in code · pending changes never block an update.

## Interface — CLI (T-124, `cmd_update` in `kit/ops/lib/admin.sh`; dispatch line unchanged)
```
polaris update                      # explicit, as today — plus the dirt rule below
polaris update --repo-only          # as today
polaris update --auto [--say] [--repo-only]   # the SessionStart path (below); silent unless it acted
polaris update --all                # walk the machine registry; every quiescent installed repo updates
```
`cmd_update` keeps its re-exec-from-a-copy guard as the FIRST thing it does for every form, `--all`
included (the walk may reach this very repo). Flags parse from `"$@"`; unknown → today's die.

## CONVENTIONS key (T-124 adds the KEYS.tsv row; `update` NEVER writes it into any repo)
```
auto_update: on         # on (default in code when absent) | off
```
Registry row: `auto_update	6.3.0	on	the repo updates itself at session start when the board is quiet; off leaves today's notice only`.
Unknown value → behaves as `off` and says so once (fail closed to today's behavior).

## `update --auto` — the algorithm (pinned; every step is a silent rc 0 exit unless stated)
1. Self-hosting tell (`kit/ops/pack.py` exists) → exit 0, nothing printed. This repo never self-updates.
2. `cfg auto_update on` = `off` → exit 0.
3. `update_latest` → the newest version on the channel, via the SAME daily-throttled cache
   `update_check_maybe` uses (`.polaris/update-cache`; one network call per day per repo, fail-open
   on no curl/no network). Empty or not `semver_gt` current → exit 0.
4. MAJOR bump (first semver field greater) → print exactly ONE line and exit 0:
   `⬆ POLARIS <latest> is a MAJOR update (you have <cur>) — it will not apply itself; when you want it: bash ops/polaris update`
5. `board_quiescent` rc 1 → exit 0 (a busy board is normal; nothing to say).
6. `git status --porcelain | update_dirt_overlaps_kit` rc 0 → exit 0. `--auto` NEVER parks: a stash
   appearing at session start is a surprise; the explicit form keeps park.
7. Apply: the existing body (fetch tarball → `install.sh` → `refresh_machine_kit` unless
   `--repo-only` → `cmd_upgrade`), stdout+stderr to `.polaris/update.log` (truncated per run).
   Success → ONE line on stdout:
   `✅ POLARIS updated <cur> → <new> at session start — ops/ and CLAUDE.md are new; re-read your role file before acting`
   Failure → ONE line, rc still 0 (a hook must never fail the session):
   `⚠ auto-update <cur> → <latest> failed — see .polaris/update.log; the repo is unchanged unless the log says otherwise`
`--say` turns every silent exit above into one stdout line `skipped: <reason>` — `--all` uses it.

## `board_quiescent` (T-124, admin.sh) — rc 0 quiet · rc 1 busy; sets `QUIET_WHY` to the FIRST reason
Reads ONLY `$BOARD`, `$LOCKS`, `$PRIMARY/.polaris/bg` (all overridable, so the fast tier tests it
in a subshell over temp dirs). Busy when any of: a `.md` in `ready/` · `active/` · `review/` ·
a task lock dir under `$LOCKS` (any dir except `.int-lease`) · `$LOCKS/.int-lease` exists ·
a bg job dir `.polaris/bg/<name>/` (not `.prev`, not `.archive`) with NO `rc` file whose `pid` is
`bg_alive` (rc-file-first, exactly bg-jobs.md's rule — a dead pid without rc is crashed, not running).
A dirty tree is NOT a reason (owner decision). `QUIET_WHY` shapes: `ready: <n>` · `active: <n>` ·
`review: <n>` · `lock: <ID>` · `integration lease held` · `bg job running: <name>`.

## `update_dirt_overlaps_kit` (T-124, admin.sh) — stdin = `git status --porcelain`; rc 0 = overlap
The paths `install.sh` overwrites, and nothing else: everything under `ops/` EXCEPT `ops/board/`,
`ops/contracts/`, `ops/CONVENTIONS.md`, `ops/MAP.md`, `ops/SPRINT.md`, `ops/RULES.tsv`,
`ops/ROADMAP.md`, `ops/tests/`; plus `.claude/settings.json`, `.claude/skills/polaris/`,
`.claude/skills/i-have-adhd/`, `.claude/output-styles/polaris.md`, `CLAUDE.md`, `.gitignore`,
`.gitattributes`. Renames (`R old -> new`) test the NEW path. Any other dirty path is the human's
work, outside the kit's footprint, and must never block an update.
**Explicit `update` dirt rule (replaces the unconditional park):** dirty AND no overlap → proceed,
note `your uncommitted changes are outside the kit's paths — left alone`; dirty AND overlap → `park`
as today; park refuses → today's die, verbatim. (The venzeti field report: a dirty tree with app-only
dirt died on "commit or stash first". After this rule it updates.)

## `update --all` (T-124, `cmd_update_all`)
Registry root = `awake_home` (lib/awake.sh); `-` (unarmed machine) → die
`no machine registry yet — open one POLARIS repo in Claude Code first, or: ops/polaris awake install`.
For each `repos/*` file (line 1 = primary path), in filename order, print ONE line per repo:
- path missing → `<path>: gone (registry entry left for you to remove)` — never deletes.
- `<path>/kit/ops/pack.py` exists → `<path>: self-hosting — skipped`.
- else run `bash "<path>/ops/polaris" update --auto --say` from `<path>` and print its line(s)
  prefixed `<path>: `; a repo that printed nothing → `<path>: up to date`.
Exit 0 always; the walk never stops on one repo's failure. `--all` combines with `--repo-only`
(passed through) and with nothing else.

## Registration at install time (T-125, `kit/ops/install.sh`, once, after the hooks copy)
The registry entry is `repos/<cksum>` ← the PRIMARY path, cksum = first field of
`printf '%s' "$path" | cksum`, path = `git -C "$TARGET" rev-parse --show-toplevel` — byte-identical
to `ah_register_repo` (awake-hook.sh) and to `cmd_uninstall`'s deregistration, or the three disagree
and one repo is registered twice. Root = `${POLARIS_AWAKE_HOME:-$HOME/.claude/polaris/awake}`; skipped
silently when `$HOME/.claude` does not exist and `POLARIS_AWAKE_HOME` is unset (CI, no Claude Code).
Best effort, `|| true`, no output. `cmd_update` gets it for free (it runs install.sh).

## SessionStart hook (T-125)
`kit/ops/hooks/update-hook.sh` (≤ 90 lines, bash 3.2, `set -u`), top-level fns EXACTLY
`jstr` (verbatim copy of checkout-guard.sh's) · `uh_primary` (handover-hook.sh's `hh_primary`
resolution, verbatim semantics) · `uh_main`. Stdin = the hook JSON; `cwd` resolves to the primary;
no primary or no `<primary>/ops/polaris` → exit 0 silent. Otherwise
`cd <primary> && bash ops/polaris update --auto` with its stdout PASSED THROUGH (it is the one line
the model should read) and stderr appended to `<primary>/.polaris/update.log`. Exit 0 ALWAYS.
`--test` prints `update-hook: would run <primary>/ops/polaris update --auto` and runs nothing.
`kit/.claude/settings.json` gains, under the existing `SessionStart` array, a SECOND entry:
`{"matcher": "startup", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/ops/hooks/update-hook.sh\"", "timeout": 120}]}`
— identity is the `ops/hooks/` path, so install.sh's merge adds/repairs it and uninstall sweeps it.
install.sh's `chmod +x` list gains the new hook. Prose (T-127, the W2 prose owner — NOT T-125):
`kit/ops/PROTOCOL.md` § THE TOOL's `version / update` row loses "(manual; POLARIS never self-updates
mid-sprint)" and gains: "self-updates at session start when the board is quiet (`auto_update: off`
stops it); a MAJOR version only ever asks; `update --all` walks every repo on this machine". No new heading.

## Executable check
- Fast tier (T-126 adds sections `quiescent` and `dirt` inside `selftest_fast`): `board_quiescent`
  quiet on empty dirs · busy for each reason above with the pinned `QUIET_WHY` · a bg dir with an
  `rc` file is not running · `update_dirt_overlaps_kit`: `?? src/x.py` rc 1 · ` M ops/lib/core.sh`
  rc 0 · ` M ops/CONVENTIONS.md` rc 1 · `R  a.txt -> CLAUDE.md` rc 0 · `?? ops/board/ready/T-1.md` rc 1.
- Drill `autoupdate` (T-126, `drill_autoupdate` in `kit/ops/lib/selftest/remote.sh`, label appended
  to `SELFTEST_LABELS` after `handover`): in the spine fixture, `ops/VERSION` rewritten to
  `version: 0.0.1` + `channel: file://$T/chan/VERSION` + `tarball: file://$T/kit.tgz` (no `repo:`,
  no `zip:` — curl reads `file://`; git ls-remote and the machine cache are never reached).
  The kit dir behind the tarball is built from the CLI under test: `$T/polaris-v5/ops` ← copy of
  `$OPS_DIR` (the loaded kit's ops/, `${SELF%/*}`), plus `$OPS_DIR/../.claude` and
  `$OPS_DIR/../CLAUDE.md` when present, then its `ops/VERSION` set to `version: 0.0.2`; channel
  file says `0.0.2`. ALWAYS `--repo-only` in the drill (never touch the owner's `~/.claude`).
  Asserts, rc AND file state, never message presence alone: (1) quiet board + `--auto --say` →
  `ops/VERSION` reads 0.0.2, `.polaris/update.log` exists, stdout has the `✅ POLARIS updated` line;
  (2) reset to 0.0.1, a task in `active/` → 0.0.1 unchanged, `--say` line `skipped: active: 1`;
  (3) reset, `auto_update: off` in CONVENTIONS → unchanged, `skipped: auto_update: off`;
  (4) channel `1.0.0` → unchanged, the MAJOR line, rc 0; (5) explicit `update --repo-only` with
  `echo dirt >> src/a.txt` (app dirt) → applies WITHOUT a stash (`git stash list` empty) and the
  `outside the kit's paths` note; (6) `--all` with `POLARIS_AWAKE_HOME` pointing at a temp registry
  holding this fixture → the `<path>: ` prefixed line and 0.0.2. Restores `ops/VERSION`, CONVENTIONS
  and `src/a.txt` before returning (hermeticity, selftest-sharding.md v1.1).
- Testbed (human/conductor, not a task): `Desktop\polaris-testbed` pinned to an old version → a new
  session self-updates; a task left in `active/` → it does not; a major on the channel → it asks.

## api-kit rows (ops/contracts/key-registry.md § 8)
W1 owner T-122 writes: admin.sh `update_latest` · `board_quiescent` · `update_dirt_overlaps_kit` ·
`cmd_update_auto` · `cmd_update_all`; KEYS.tsv row `auto_update`. W2 owner T-125 writes:
update-hook.sh `jstr` · `uh_primary` · `uh_main`; remote.sh `drill_autoupdate`.

## Invariants
- `update` never writes a repo's CONVENTIONS.md, board, RULES, MAP or SPRINT (the 6.0.0 lesson).
- `--auto` never parks, never asks, never exits non-zero, never prints more than one line.
- Hot commands (`claim status doctor dash version`) keep `update_check_maybe`'s NOTICE behavior
  byte-identical — applying is the SessionStart path's job alone.
- A MAJOR bump never applies without a human running `update` (or saying yes to the model, which
  then runs `update`).
- bash 3.2; no `case` inside `$(...)`.

## Example
```
$ bash ops/polaris update --all
/c/Users/Owner/Desktop/job: ✅ POLARIS updated 6.2.2 → 6.3.0 at session start — ops/ and CLAUDE.md are new; re-read your role file before acting
/c/Users/Owner/Desktop/venzeti: skipped: active: 1
/c/Users/Owner/Desktop/Polaris: self-hosting — skipped
```

## Changelog
- v1 2026-09-08: created for T-124, T-125, T-126 (plan feel-fast)
