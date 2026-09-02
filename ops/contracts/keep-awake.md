# CONTRACT: keep-awake            (v1 — 2026-09-01)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/v2.md` WS3 (plan slug `cant-eat-itself`, 6.2.0). Tasks: T-102 (the hook + presser) · T-101
(`lib/awake.sh`, entry wiring, W2 api-kit owner) · T-096 (PROTOCOL `## AWAKE`) · T-100 (doctor lines) ·
T-103 (bootstrap/admin install + uninstall deregistration) · T-104 (drill `awake` + hermetic spine
export) · T-106 (golden `awake-hook`).

## Purpose
The machine sleeps mid-run. Wanted: ONE machine-wide keep-awake owner that keeps the box awake while ANY
session is still working and stops only when ALL are done — never one per session, never interrupting a
human who is typing. It is MACHINE-level: hooks in `~/.claude/settings.json`, a registry under
`~/.claude/polaris/awake/`, **no CONVENTIONS keys** (a repo key cannot gate machine-level hooks). This seam
separates the hook+daemon (T-102, one file), the CLI face (T-101), the installers (T-103) and the proofs
(T-104/T-106) so they are built in parallel from the names below.

## Interface — the registry (`~/.claude/polaris/awake/`)
Root resolution, in order: `$POLARIS_AWAKE_HOME` → `${0%/*}/awake` when the script runs from under
`.claude/polaris/` → `$HOME/.claude/polaris/awake`. Never `~` or `$HOME` inside a settings.json command
(`env -i` empties `$HOME`): every installed hook entry carries ABSOLUTE paths.
```
sessions/<sid>        4 lines: `busy|idle <epoch>` · transcript path · claude pid or `-` · repo primary or `-`
repos/<cksum>         line 1 = the repo's primary path (cksum = `cksum` of the path, first field)
daemon/pid            MSYS/posix pid of the daemon loop      daemon/winpid   Win32 ProcessId (WMI spawn) or absent
daemon/beat           epoch, rewritten every tick            daemon/log      daemon stdout+stderr
daemon/hook.log       every hook subcommand's stderr          daemon/last-press  one presser word per tick
lock/                 mkdir singleton (the daemon holds it)   stop            flag: exit now
disabled              flag: never press (daemon keeps ticking, verdicts still logged)
config                KEY=F15 TICK=55 STALE=2700 IDLE=900 GRACE=300 DISPLAY=1 INPUT_IDLE=60
```
`config` is parsed with `case` line by line, NEVER sourced; an env `POLARIS_AWAKE_<KEY>` wins over the
file (the drill seams). Missing file ⇒ the defaults above.

## Interface — `kit/ops/hooks/awake-hook.sh` (T-102; ≤320 lines, bash 3.2, `set -u`)
Functions, EXACTLY these top-level names (the W2 api-kit rows T-101 writes — 19 rows, one per fn):
`jstr` (verbatim copy of checkout-guard.sh:59-95) · `ah_home` · `ah_log` · `ah_now` · `ah_mtime` ·
`ah_alive` · `ah_win_alive` · `ah_repo_of` · `ah_register_repo` · `ah_hook_start` · `ah_hook_busy` ·
`ah_hook_idle` · `ah_hook_end` · `ah_spawn` · `ah_press` · `ah_verdict` · `ah_tick` · `ah_daemon` · `ah_install`.
Dispatch `case "$1"`: `start|busy|idle|end|ensure|daemon|tick|install|--test`.
- **Every hook subcommand** (`start busy idle end`): `exec >/dev/null 2>>"$AWAKE/daemon/hook.log"`, `set +e`,
  `trap 'exit 0' EXIT`, exit 0 ALWAYS, ZERO stdout (rc 2 on Stop means "keep going"; UserPromptSubmit
  stdout is injected into the model's context). Input = the hook JSON on stdin (`session_id`,
  `transcript_path`, `cwd`, `hook_event_name`); `session_id` absent ⇒ exit 0 silently.
- `start`: create `sessions/<sid>` as `idle <now>` ONLY when absent (a `compact`/`resume` start must never
  downgrade `busy`); when present, refresh lines 2-4 only. `busy`: write `busy <now>` + lines 2-4, then
  `ah_register_repo` (cwd's primary via `${cwd%/.polaris/wt/*}`, `git rev-parse --show-toplevel` fallback,
  `-` on failure) and ensure the daemon. `idle`: write `idle <now>`. `end`: `rm -f sessions/<sid>`.
- `ensure <primary>` (called by `awake_ensure`, T-101): register the repo, then spawn the daemon unless
  `daemon/beat` is younger than 3×TICK; rc 0 always.
- `daemon`: the loop — `mkdir lock` or exit (loser); `trap 'rm -rf "$AWAKE/lock"; exit 0' TERM INT`;
  each iteration: `ah_tick`, `date +%s > daemon/beat`, `[ -e stop ]` ⇒ `rm -f stop`, rm lock, exit;
  quiet (no active verdict) for ≥ GRACE seconds ⇒ rm lock, exit; `sleep "$TICK" & wait $!` (so `stop`
  interrupts within a second). A daemon whose lock exists but whose `daemon/beat` is older than 3×TICK
  is stale: the next spawner removes the lock and takes over.
- `ah_verdict` (one pass): `ps -W` ONCE on Windows (else `kill -0`); a session whose pid (line 3, not `-`)
  is dead ⇒ `rm` its file; files older than 24 h ⇒ `rm`; beat = max(mtime of the transcript, mtime of the
  newest `<transcript dir>/<sid>/subagents/*.jsonl`); `busy` ⇒ active iff `now − beat < STALE`; `idle` ⇒
  active iff `beat > idle-stamp` AND `now − beat < IDLE`; any registered repo with a `.polaris/bg/*/` dir
  lacking `rc` whose `pid` is alive ⇒ active. Result: `active` or `quiet` (+ counts for the status line).
- `ah_press`: active AND no `disabled` ⇒ run the presser (below) and write its ONE word to
  `daemon/last-press`; `disabled` ⇒ write `disabled`. Presser failure (GPO, Constrained Language Mode, AV)
  logs once per 100 ticks and never kills the daemon.
- `ah_spawn` (Windows): `Invoke-CimMethod -ClassName Win32_Process -MethodName Create` with the command
  line in env `POLARIS_AWAKE_CMD` (bash.exe absolute: `cygpath -w "$(command -v bash)"`) — the child of
  WmiPrvSE is outside every caller's Job Object, has no console, and survives the spawning terminal;
  record ProcessId as `daemon/winpid`. Fallback `Start-Process -WindowStyle Hidden -PassThru`; last resort
  inline `( ah_daemon & )` + a logged warning. macOS/Linux: `nohup bash "$0" daemon >/dev/null 2>&1 & disown`
  (no `setsid` on macOS). `POLARIS_AWAKE_SPAWN=inline` forces the inline path (drill seam). powershell at
  `"$(cygpath "$SYSTEMROOT")/System32/WindowsPowerShell/v1.0/powershell.exe"` else `command -v powershell`.
- `ah_install`: merge the four machine hooks into `~/.claude/settings.json` via a python heredoc
  (stdlib only): identity regex `polaris/awake-hook\.sh` on each entry's command; replace OURS in place,
  append when absent, FOREIGN entries untouched, tmp file + `os.replace`, fails OPEN (unparseable ⇒ print
  the four entries and exit 0). Entries (timeouts in seconds):
  `SessionStart`→`start` (5) · `UserPromptSubmit`→`busy` (10) · `Stop`→`idle` (5) · `SessionEnd`→`end` (5);
  command = `"<bash abs>" "<abs>/awake-hook.sh" <sub> 2>/dev/null || true`. `<abs>` = `~/.claude/polaris`
  expanded; `<bash abs>` = `cygpath -w`-free posix path of `command -v bash` (the harness runs hooks via
  its own shell resolution; a Windows path with backslashes is JSON-escaped).
- `--test <start|busy|idle|end|tick>` (T-106's golden, the drill): same JSON on stdin, same writes into
  `$POLARIS_AWAKE_HOME`, but prints ONE line to stdout instead of nothing:
  `start: <sid> <busy|idle> (created|kept)` · `busy: <sid> busy` · `idle: <sid> idle` · `end: <sid> removed` ·
  `tick: <active|quiet> <presser word|no-press>` (one verdict pass + at most one press; never sleeps,
  never spawns; `disabled` ⇒ `tick: active disabled`).

## Interface — `kit/ops/hooks/awake-press.ps1` (T-102; ≤80 lines; NOT indexed — no api-kit row)
`param([string]$Key='F15',[int]$Display=1,[int]$InputIdle=60)`. Add-Type P/Invoke: `SetThreadExecutionState`,
`GetLastInputInfo`, `OpenInputDesktop`, `keybd_event`.
- ALWAYS `SetThreadExecutionState(ES_SYSTEM_REQUIRED)` one-shot (0x00000001, NO `ES_CONTINUOUS`): resets the
  idle timer under Windows' 1-minute floor, works on the lock screen, holds nothing.
- Locked (`OpenInputDesktop` returns 0, or a `LogonUI` process exists) ⇒ prints `skipped-locked`.
- Unlocked and `$Display -eq 1`: add `ES_DISPLAY_REQUIRED` (0x00000002); then the key (F13=0x7C · F14=0x7D ·
  F15=0x7E; `none` = no key) ONLY when input-idle ms > `$InputIdle*1000` ⇒ `pressed`; a typing human ⇒
  `skipped-active`. `$Display -eq 0` or `none` ⇒ `state-only`.
- Prints exactly one word: `pressed|skipped-active|skipped-locked|state-only`.
- macOS: `caffeinate -u -t 75` (`-i` when DISPLAY=0) ⇒ `pressed`. Linux: `xdotool key F15` →
  `xdg-screensaver reset` → log once ⇒ `pressed`/`state-only`. `POLARIS_AWAKE_PRESSER="<cmd>"` env
  replaces the presser wholesale (drill seam: `touch $T/pressed` ⇒ the daemon writes `pressed`).
- Cannot cover lid-close / power button / critical battery — no user-mode API can; say so in PROTOCOL.

## Interface — `kit/ops/lib/awake.sh` (T-101; ≤150 lines; 5 fns, api-kit rows)
```
awake_home                     # prints the registry root (same resolution as ah_home; `-` when unarmed)
awake_conf <key> <default>     # env POLARIS_AWAKE_<KEY> → config line → default
awake_ensure                   # fork-free when daemon/beat is fresh (< 3×TICK); no-op (rc 0) when neither
                               # $POLARIS_AWAKE_HOME nor ~/.claude/polaris/awake-hook.sh exists (unarmed
                               # machine, CI); else `bash <hook> ensure "$PRIMARY" </dev/null >/dev/null 2>&1 &`
awake_status_line              # ONE of the three status shapes below
cmd_awake <status|start|stop|disable|enable|install>
```
- `status` prints the status line; `start` = `ensure` now; `stop` = `touch stop` + kill the MSYS pid +
  `rm -rf lock` + `touch disabled` with a 60-minute expiry stamp inside it (the daemon re-enables itself
  after 60 min: `disabled` older than 3600 s is removed by the next tick); `disable` = `touch disabled`
  (no expiry); `enable` = `rm -f disabled`; `install` execs the hook's `install`.
- Status line shapes (pinned): `awake: running (pid <p>, beat <s>s ago, <n> busy session(s), <m> repo(s))` ·
  `awake: idle — not running` · `awake: off (disabled)`.
- Entry wiring (T-101, `kit/ops/polaris`): loader FULL list `+awake` immediately after `bg`, and
  `+handover` after `awake` (module-layout v5); the `_match|_rules|_guard` list stays EXACTLY
  `core ownership`. Dispatch `awake) shift; cmd_awake "$@";;`. `awake_ensure || true` on
  `claim|status|doctor|handoff|bg run` — in the dispatch case, BELOW the `EVENTS=` line, never on the
  guard path. Usage block, 3 lines, byte-exact (T-108 re-pins `cli-help.expected` after dogfood):
```
  awake [status|start|stop]      ONE keep-awake daemon per machine (~/.claude/polaris/awake): presses
                                 F15 every ~55s while any session is busy; exits by itself once every
                                 session and repo is idle. start = arm now · stop = 60 min off
```

## Interface — installers (T-103) and doctor (T-100)
- `bootstrap.py::arm_machine`: extract `kit/ops/hooks/awake-hook.sh` + `awake-press.ps1` from the archive
  to `~/.claude/polaris/` (dir created), chmod the .sh, run `bash ~/.claude/polaris/awake-hook.sh install`
  via a NEW fn `merge_awake_hooks(bash_path)` (the ONE new python fn — W3 api-kit row, T-104 writes it);
  failure prints one ⚠ line and never fails the install.
- `admin.sh::refresh_machine_kit`: copy the same two files (source `kit/ops/hooks/` first, `ops/hooks/`
  fallback — the two-path pattern at admin.sh:204-207) to `~/.claude/polaris/` and run `install`; fails open.
- `install.sh:106` chmod list gains `ops/hooks/awake-hook.sh` and `ops/hooks/handover-hook.sh` (T-103).
- `cmd_uninstall` (T-103): remove `~/.claude/polaris/awake/repos/<cksum-of-this-primary>` only — never the
  daemon, the hooks or other repos' registrations.
- `cmd_doctor` (T-100), gated on `[ -d "$HOME/.claude" ]`: the four hooks not merged ⇒
  `⚠ keep-awake not armed on this machine — ops/polaris awake install`; `disabled` flag present ⇒
  `⚠ keep-awake is DISABLED (ops/polaris awake enable)`. Silent otherwise.

## PROTOCOL.md (T-096) — new H2, the ONLY new H2 in PROTOCOL this sprint (api-kit row)
`## AWAKE — one keep-awake daemon per machine` — ≤12 lines: registry path · the four machine hooks ·
`awake status|start|stop|disable|enable` · "`finish` never stops it; the next prompt anywhere respawns it" ·
opt-out = the `disabled` flag (`awake disable`) · `KEY=none` keeps only the invisible execution-state half ·
lid-close/power-button/critical-battery are out of reach for any user-mode program.
`kit/.claude/skills/polaris-install/SKILL.md`'s "arms the machine" sentence gains the keep-awake hooks —
T-103 owns that file (board amendment 2026-09-01); one sentence, no heading change (the skill is indexed
by api-kit). The project skill `kit/.claude/skills/polaris/SKILL.md` is T-107's.

## Executable check
### Drill `awake` (T-104, policy.sh after `drill_checkoutguard`, template `drill_bg` :419-480; label `awake`)
Seams exported for the drill: `POLARIS_AWAKE_HOME=$T/awake-home POLARIS_AWAKE_PRESSER="touch $T/pressed"
POLARIS_AWAKE_TICK=1 POLARIS_AWAKE_IDLE=3 POLARIS_AWAKE_STALE=5 POLARIS_AWAKE_GRACE=2 POLARIS_AWAKE_SPAWN=inline`.
`spine.sh` exports `POLARIS_AWAKE_HOME="$T/awake-home"` right after `T="$(mktemp -d)"` (:115) so `bg run`
inside ANY drill never registers a fixture repo on the owner's real registry; `ops/tests/bg-lifecycle.cmd`
gets the same export (its `.expected` is unchanged). Asserts (rc + file state, never message alone):
1. each of `start busy idle end` fed a JSON payload (with a Windows-escaped `transcript_path`, e.g.
   `C:\\Users\\x\\.claude\\projects\\p\\<sid>.jsonl`) writes the right `sessions/<sid>` lines with EMPTY stdout,
   EMPTY stderr and rc 0; `start` on an existing `busy` file leaves it `busy`;
2. busy + a fake transcript touched now ⇒ daemon (inline) writes `daemon/last-press` = `pressed` within 3 s
   and `$T/pressed` exists;
3. all sessions idle and stale ⇒ no press, the daemon exits by itself after GRACE, `lock/` gone;
4. stale-daemon steal: plant `lock/` + `daemon/beat` backdated (`touch -t`) + a dead pid ⇒ a new `ensure`
   takes over (one daemon, fresh beat);
5. `stop` flag ⇒ exit within 2 s; `disabled` ⇒ `last-press` = `disabled`, no `$T/pressed`;
6. re-entrant `ensure` ×2 ⇒ exactly one daemon pid;
7. bg-job clause: a fake `.polaris/bg/x/{pid,cmd,start,log}` (live `sleep`, no `rc`) in a registered repo
   ⇒ verdict active with every session idle;
8. `install` on a FIXTURE settings.json (`HOME=$T/home`): a foreign `Stop` entry is kept, a stale OURS
   entry is replaced, all four events present exactly once; skipped with a note when `python` is absent.
Budget ~44 s; scratch under `scratchpad/T-104/`.
### Golden `awake-hook` (T-106; hermetic, `POLARIS_AWAKE_HOME` = a mktemp dir, presser stubbed)
`--test start|busy|idle|end` per event (+ `start` twice to prove `kept`), `--test tick` with the stub presser
(`tick: active pressed`), `disabled` (`tick: active disabled`), all-idle (`tick: quiet no-press`); registry
paths normalized to `<home>`; hook stdout for the LIVE subcommands asserted EMPTY (`wc -c` = 0) and rc 0.

## api-kit rows
- W2 (T-101 writes): 19 rows `kit/ops/hooks/awake-hook.sh	fn	<name>` for the fn list above (incl. `jstr`
  — the index keys rows by file, so it is a new row) + 5 rows `kit/ops/lib/awake.sh	fn	<name>`.
- W3 (T-104 writes): `kit/ops/lib/selftest/policy.sh	fn	drill_awake` · `kit/ops/bootstrap.py	fn	merge_awake_hooks`.
- W1 (T-096 writes): `kit/ops/PROTOCOL.md	heading	AWAKE — one keep-awake daemon per machine`.
- `awake-press.ps1` is not indexed. T-102/T-103/T-100/T-106 add no other fn/heading/key.

## Invariants
- Hook subcommands: zero stdout, rc 0, always; `2>/dev/null || true` on every installed command line.
- ONE daemon per machine (mkdir lock + stale-beat steal); `finish` never stops it; every session's next
  prompt re-ensures it.
- The presser never fires while a human has typed in the last INPUT_IDLE seconds, never on a locked
  station; `ES_SYSTEM_REQUIRED` one-shot ALWAYS fires on an active tick (the guarantee).
- No CONVENTIONS key; no repo-hook writes; the activity signal is transcript mtime + bg jobs.
- Everything hermetic under `POLARIS_AWAKE_HOME`; no drill or golden touches the owner's real registry.
- bash 3.2 (CI runs macOS `/bin/bash`): no `case` inside `$(...)`, no associative arrays, no `mapfile`.

## Manual checklist after dogfood (the release tail, plans/v2.md § Verification — run from a FRESH chat)
`grep -c awake-hook ~/.claude/settings.json` = 4 · daemon's parent is `WmiPrvSE.exe` · survives closing the
spawning terminal · "sleep after 1 min" power plan + a 15-min `bg run` ⇒ no sleep, `awake stop` ⇒ sleeps ·
Win+L 3 min ⇒ no sleep, `last-press` = `skipped-locked`, nothing typed into the password box · Notepad typing
⇒ `skipped-active`; 90 s still ⇒ `pressed`; a console `ReadKey` sees F15 · all idle ⇒ exits after GRACE ·
two prompts in one second ⇒ one daemon · Task-Manager-kill a busy claude.exe ⇒ its session file gone within
a tick.

## Example
```
$ bash ops/polaris awake status
awake: running (pid 41232, beat 12s ago, 2 busy session(s), 1 repo(s))
$ cat ~/.claude/polaris/awake/daemon/last-press
skipped-active
```

## Changelog
- v1 2026-09-01: created for T-096, T-100, T-101, T-102, T-103, T-104, T-106 (plan: cant-eat-itself, 6.2.0)
