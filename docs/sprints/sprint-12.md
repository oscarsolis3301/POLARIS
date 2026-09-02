# Sprint 12 — Parallel work that can't eat itself (6.2.0) (2026-09-01–)

## T-092 — "workspace.sh — beats, wt_remove (archive, never --force), pid-aware lease steal, owned parks"
points 5 · risk normal · landed ff868a8 (2026-09-02) · claimed 2026-09-02
files touched: kit/ops/lib/workspace.sh

### Why
A sibling session's cleanup ran `git worktree remove --force` on a worktree someone else was still
typing in, and everything uncommitted died. Nothing in the kit can tell a live worktree from a dead
one, so every remover guesses. This task gives the kit the ONE way to ask ("is this worktree live?")
and the ONE way to remove ("wt_remove") — and wt_remove never uses `--force`: a clean idle worktree
is removed, a dirty one is moved to `.polaris/wt-archive/<ID>-<epoch>` with its bytes intact, and a
live one is left alone with a note that says what to do next. The liveness signal is a beat file
inside git's own per-worktree dir (`$GCD/worktrees/<ID>/polaris-beat`), touched by the CLI and the
hooks; `wt_live_minutes` (default 15, KEYS row registered by T-096) says how long a beat counts.
Same file, same sprint, two smaller fixes from the plan: the integration-lease steal becomes
pid-aware (a slow but alive integrator is never stolen from), park stashes carry
`<epoch>-<sid8|pid>` so `unpark` pops only YOUR park (`--any` for crash recovery) and `park` prints
what it stashed, and `wt_add <ID> resume` warns when it had to recreate a vanished branch.
Everything is pinned in ops/contracts/worktree-liveness.md — signatures, the caller×dirty×live
decision table, the three output prefixes and the archive layout. Callers (done/release/sweep/
resume) are other tasks in wave 2; this task ships the primitives only.

### Acceptance
- [ ] `beat_touch <ID>` writes an epoch to `$GCD/worktrees/<ID>/polaris-beat` (mkdir -p first), rc 0 always; `beat_age` prints seconds (999999 when absent/unreadable, content-first then `stat -c %Y || stat -f %m`); `beat_live` rc 0 iff age < `cfg wt_live_minutes 15` × 60 (non-numeric ⇒ 15)
- [ ] `wt_remove <ID> <done|release|sweep>` implements the contract's decision table exactly: rc 0 removed · 1 LEFT · 2 archived; dirty = `git status --porcelain` non-empty (untracked included); archive = mv to `$PRIMARY/.polaris/wt-archive/<ID>-<epoch>` + `rm -f <archive>/.git` + `git worktree prune`; any mv/git failure ⇒ rc 1 + one note, never die, never partial; own-lane release EBUSY ⇒ LEFT + the pinned `cd out of .polaris/wt/<ID> and run: bash ops/polaris sweep --fix` note
- [ ] output prefixes byte-exact: `worktree removed` · `worktree LEFT` · `worktree archived → .polaris/wt-archive/<ID>-<epoch>`; `grep -c 'worktree remove --force'` on workspace.sh is 0
- [ ] lease steal (`int_on`): iff age > sm×60 AND (pid absent OR dead OR age > 2×sm×60); dead = `kill -0` fails, or on Windows the pid is absent from ONE `ps -W` listing; wait/queue behavior otherwise byte-identical (busyint drill stays green)
- [ ] park: stash name `polaris/park-<epoch>-<sid8|pid>`, prints the stashed paths (3-space indent); `unpark` pops only OUR newest park, says how many foreign parks exist when none is ours; `unpark --any` pops the newest of anyone (drill park stays green — extend it only inside its body if a name assertion needs the new suffix, and say so in Notes)
- [ ] `wt_add <ID> resume` with no local `feat/<ID>` creates it from `<base>` and prints the pinned `⚠ feat/<ID> did not exist — recreated from <base>; …` note; plain `wt_add <ID>` unchanged
- [ ] proven in a throwaway kit copy + fixture repo (the T-089 pattern): a dirty worktree with a backdated beat (`echo 1 > <beat>`) archives with bytes intact; a fresh beat leaves it; a clean idle one is removed — rc asserted, not just the words (drill `wtreap` in W3 automates this)
- [ ] no new fn beyond the four pinned; `bash kit/ops/polaris doctor --selftest --only park,busyint` green (foreground, ≥600000 ms timeout)

## T-093 — "checkout-guard learns the other destroyers — worktree remove/prune/move, clean, push --delete, rm on .polaris, broad kills; both hooks beat"
points 3 · risk normal · landed fe25859 (2026-09-02) · claimed 2026-09-02
files touched: kit/ops/hooks/checkout-guard.sh, kit/ops/hooks/ownership-guard.sh, ops/tests/checkout-guard-denies.cmd, ops/tests/checkout-guard-denies.expected

### Why
Four things still destroy another session's work and nothing stops them: `git worktree remove`
(the ARC-428 incident), `git clean -fdx` in the primary (deletes the whole gitignored `.polaris/` —
every worktree, the index, the bg logs), `rm -rf .polaris` / `Remove-Item -Recurse .polaris`, and
by-name process kills (`taskkill /IM`, `pkill`, `killall`, `npx kill-port` — the "port 8001 instance
vanished" incident, a launcher reclaiming a port by killing whoever held it). The checkout-guard hook
already refuses checkout-mutating git in the primary; this task teaches it the rest, with the same
discipline: deny narrow, silence default, zero forks on the common path. Pid-targeted kills, dry-run
cleans and ordinary pushes stay allowed — you may kill what you started. Each new class has its own
pinned one-line message and `--test` label, and the golden grows to prove every case in both
directions. Both hooks also gain a zero-fork touch of the worktree beat (worktree-liveness.md), so a
session that only edits files still counts as live. Spec: shared-checkout.md v2.5 (verbatim messages,
labels, golden lines) + worktree-liveness.md § beat writers (the two pinned touch lines).

### Acceptance
- [ ] gate 1 widened to `*git*|*rm*|*Remove-Item*|*kill*|*Stop-Process*|*fuser*`; gate 2 (wt cwd) allows only when the command contains none of worktree/rm/Remove-Item/kill/Stop-Process/fuser, and touches the beat via the pinned string-ops line before deciding
- [ ] `mutating_git` grows `worktree remove|prune|move` (HIT `worktree-remove|prune|move`), `clean` (allow on `-n`/`--dry-run`), `push --delete|-d|:ref` (HIT `push-delete`); `git worktree list`/`add` behave as before (`add` stays `deny:worktree`)
- [ ] ONE new fn `mutating_other` (rm-polaris · kill-broad per the contract's allow/deny lists); top-level fns are exactly deny · jstr · mutating_git · mutating_other
- [ ] worktree-*/rm-polaris/kill-broad deny EVERYWHERE (no placement probe); clean/push-delete deny in the primary only (probe unchanged); `deny <sub> <msg>` keeps ONE printf emitter; the v2 MSG byte-identical; MSG_WT/MSG_PUSH/MSG_KILL byte-exact per contract
- [ ] golden `checkout-guard-denies`: every existing line byte-identical in place; +20 deny lines, +9 allow lines, +3 wt-cwd deny lines, +4 count lines exactly as pinned in shared-checkout.md v2.5 §2; proven from the worktree with the `.cmd`-body diff (never `check --only`)
- [ ] `ownership-guard.sh`: exactly ONE added line after the `WT_ID=`/`PRIMARY=` anchor (:207-209) — the pinned beat touch; `ownership-primary` golden byte-identical; `readonly-allow.sh` untouched
- [ ] hermetic: `/tmp/fakerepo` still fails closed for primary-only classes; no live board or real repo read by the golden
- [ ] `bash kit/ops/polaris doctor --selftest --only checkoutguard` green (foreground, ≥600000 ms timeout) — the existing drill must not red on the widened gate 1

## T-094 — "bg.sh — jobs are owned by their cwd: foreign same-name live jobs refuse, .prev archives instead of dying"
points 2 · risk normal · landed ecd3856 (2026-09-02) · claimed 2026-09-02
files touched: kit/ops/lib/bg.sh, ops/tests/bg-lifecycle.cmd, ops/tests/bg-lifecycle.expected

### Why
Five sessions on one machine each run `bg run qa` (or `bg run test_fast`). Today a same-name job
started from another session silently rotates the live job's `.prev` archive away (`rm -rf`), and
`--force` kills whatever pid the old job recorded — a pid Windows may have handed to someone else by
now. This task makes a background job belong to the directory it was started from: a live same-name
job from ANOTHER cwd is refused (rc 1, message names the owner's cwd and suggests `<name>-<ID>`),
with or without `--force`; the same-cwd behavior is byte-identical to today. Rotation stops deleting:
an existing `<name>.prev` moves to `.polaris/bg/.archive/<name>-<epoch>` (a dot-dir every `*/`
listing already ignores), and `sweep --fix` prunes that archive by age (T-100). The job dir also
records the session id beside `cwd`, for messages only. The golden grows by two blocks; every
existing line stays byte-identical. Spec: bg-jobs.md v2.

### Acceptance
- [ ] `bg_run`: live same-name job with `cwd` ≠ caller `$PWD` (normalize `\` to `/`, case-fold) ⇒ the pinned die, rc 1, WITH and WITHOUT `--force`; same-cwd refusal and `--force` byte-identical to v1
- [ ] `bg_rotate`: `<name>.prev` present ⇒ `mkdir -p .archive` + `mv` to `.archive/<name>-<epoch>`; no `rm -rf` of any `.prev` remains in bg.sh
- [ ] job dir records `sid` (`$CLAUDE_CODE_SESSION_ID` or `-`); `bg status`/`tail`/`wait`/`sweep`/finish-guard unchanged and never descend into `.archive/`
- [ ] golden `bg-lifecycle`: +2 blocks at the END exactly as bg-jobs.md v2 pins (foreign-cwd refusal with `$FIX` normalized to `<fix>`; third run archives — `ls .polaris/bg/.archive | grep -c '^ok-'` prints 1, `ok.prev/cmd` prints `echo second-run`); `export POLARIS_AWAKE_HOME="$FIX/awake-home"` added right after the `trap … EXIT` line; every existing line byte-identical
- [ ] `bash -c "$(cat ops/tests/bg-lifecycle.cmd)" | diff - ops/tests/bg-lifecycle.expected` clean from the worktree (~40 s because of the deliberate `sleep 8`s — run it by hand, it is NOT a verify: line; `polaris check` re-proves it on the primary after landing)
- [ ] no new fn in bg.sh (9 fns before and after)
- [ ] `bash kit/ops/polaris doctor --selftest --only bg` green (foreground, ≥600000 ms timeout)

## T-095 — "Auto mode prompts for nothing it doesn't have to — seven bare tool-name rules in kit settings + bootstrap PERMS, golden perm-tools"
points 2 · risk normal · landed fa4e3b2 (2026-09-02) · claimed 2026-09-02
files touched: kit/.claude/settings.json, kit/ops/bootstrap.py, ops/tests/perm-tools.cmd, ops/tests/perm-tools.expected

### Why
In auto mode a POLARIS session still stops to ask "Do you want to proceed with EnterWorktree?" —
every one of five parallel chats, on the same click. Every permission rule the kit ships is a
`Bash(...)`/`PowerShell(...)` prefix; nothing pre-authorizes the harness's OWN tools. The fix is
data: seven bare tool names appended to `permissions.allow` in `kit/.claude/settings.json` and to
`PERMS` in `kit/ops/bootstrap.py` (the machine-level list `arm_machine` unions into
`~/.claude/settings.json`). Bare = every invocation of that tool. Two names are deliberately NOT
added — `ExitPlanMode` and `AskUserQuestion` are the human gates POLARIS must keep — and
`NotebookEdit` stays out because the ownership guard denies it anyway. `readonly-allow.sh` is not
touched: it is a Bash-read approver, not a tool-permission store. A new golden `perm-tools` pins the
exact set in both files and the absence of the gates, so the rule never drifts in either direction.
The `EnterWorktree({path: ".polaris/wt/<ID>"})` entry the sprint-11 contract left open is settled by
the tool's own description: it accepts any `git worktree list` path on first entry from the launch
dir — the missing rule was the whole defect. Spec: permission-rules.md.

### Acceptance
- [ ] `kit/.claude/settings.json` `permissions.allow` ends with, in order after the last PowerShell rule: "EnterWorktree", "ExitWorktree", "Workflow", "Task", "Agent", "TodoWrite", "SendMessage" — valid JSON, nothing else changed
- [ ] `bootstrap.py` `PERMS` gains the same seven as its final block, preceded by a comment block stating: why bare names, why the two gates and NotebookEdit are absent (without spelling the gate names — the golden counts them as 0), and that unknown names are inert on older builds; no new module-level constant or def (the index records both)
- [ ] `ExitPlanMode`, `AskUserQuestion` appear in NEITHER file; the union paths (`added = [rule for rule in PERMS` in bootstrap.py, `for rule in rules:` in admin.sh) untouched
- [ ] golden `ops/tests/perm-tools.{cmd,expected}`: exactly the four pinned lines of permission-rules.md; greps the two kit files only (hermetic); proven from the worktree with the `.cmd`-body diff; sabotaged red once (remove one name) before trusting green
- [ ] `output-style-installed` and `readonly-allow` goldens byte-identical (settings.json's outputStyle and hook entries untouched)
- [ ] the pre-approval below is understood: it covers exactly these seven names; anything else is a plan-gate decision

## T-096 — "Docs + keys for 6.2.0 — six KEYS rows, ops/VISUAL.md, PROTOCOL AWAKE + rows, rule 3 rewrite in both copies, MANUAL without --force; api-kit owner W1"
points 4 · risk normal · landed c0a5c56 (2026-09-02) · claimed 2026-09-02
files touched: kit/.claude/output-styles/polaris.md, kit/ops/KEYS.tsv, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/VISUAL.md, ops/tests/api-kit.expected

### Why
Wave 1's prose and data, in one lane so five code lanes never touch a shared doc: (1) six new
CONVENTIONS keys registered in `kit/ops/KEYS.tsv` — `wt_live_minutes` (worktree liveness), `shot`
`visual` `port_base` `serve` (the capture step) and `handover` (role hops) — rows are inert data, and
`keys-drift` ties every future `cfg` read to its row, so they land BEFORE the code that reads them;
(2) a new kit doc `kit/ops/VISUAL.md` carrying the "seeing your work" doctrine the owner has been
pasting by hand (≤40 lines, seven pinned headings); (3) PROTOCOL.md gains the `## AWAKE` section
(one keep-awake daemon per machine), one N-CHATS table row (a worktree that is not yours), a bold
§ LANES paragraph extending the precedent chain to handover, and the rewritten § VOICE rule 3;
(4) the output style gets the SAME rule 3 bytes (the `plain-voice` golden diffs the two copies) and
one bold "A hop is not an ending" line in "How a session ends"; (5) MANUAL.md's by-hand recipes lose
`git worktree remove --force`. And because this repo's api-kit golden records every heading and
KEYS row, this task is the wave's ONE api-kit owner: it writes the whole 19-row W1 union up front —
its own 14 rows plus T-092's four workspace fns and T-093's `mutating_other` — from the names the
contracts pin. Specs: key-registry.md §7 (the union + owner recipe), visual-check.md (keys + VISUAL.md),
keep-awake.md (AWAKE section), role-handover.md (LANES paragraph, rule 3, the output-style line),
worktree-liveness.md (MANUAL recipes, the N-CHATS row).

### Acceptance
- [ ] KEYS.tsv: the six rows appended after `landing`, in the pinned order and byte-exact text (visual-check.md § keys); `keys-drift` golden green
- [ ] VISUAL.md: exactly the seven pinned headings, ≤40 lines, every doctrine bullet present, no `#`-leading line inside a fence, "Adding it to a repo" names the four keys + python-not-python3 + the `.claude/settings.json` allow line
- [ ] PROTOCOL.md: `## AWAKE — one keep-awake daemon per machine` is the ONLY new H2 (10 H2s total), ≤12 lines with the pinned content; the N-CHATS row byte-exact; the § LANES bold paragraph; rule 3 rewritten — the numbered-rule set of § VOICE stays 7 lines and byte-identical to the output style's
- [ ] output style: rule 3 identical bytes; the pinned bold line placed in "How a session ends" ABOVE `## What a close reads like`; still 7 numbered rules; no heading change (`output-style-installed` + `plain-voice` green)
- [ ] MANUAL.md :100 and :122 recipes reworded per worktree-liveness.md (no `--force`; `sweep --fix` first; `wt-archive` for dirty); heading set unchanged
- [ ] api-kit.expected: 581 lines = 562 + the 19 pinned W1 rows inserted in `find --api` order (key-registry.md §7); the completeness check (`<` count) is 0 in this worktree; sibling rows (`>`) are exactly T-092's four + T-093's one until the wave lands
- [ ] no other `#` line added anywhere under kit/ by this task; no fn; no python

## T-097 — "core.sh — lock meta learns the session (sid + claude pid), pid-aware mutex steal, ls-remote board tip, evt writes the handover last-event"
points 2 · risk normal · landed a5bb2dc (2026-09-02) · claimed 2026-09-02
files touched: kit/ops/lib/core.sh

### Why
Three small changes to the board's core, all pinned by contract, none adding a function.
(1) The task lock's `meta` file gains two lines: the session id (`$CLAUDE_CODE_SESSION_ID`) and the
harness pid (`$CLAUDE_PID`) — both live in every Bash-tool environment and stay stable for the whole
session, unlike `$$`. They never decide liveness (the beat does — T-092); they let `resume` recognize
its own session after a compaction, `sweep` say "session alive/gone", and `next` know whose lock it
is. Every 3-line reader keeps working; a missing line reads `-`. (2) The board mutex steal at
`mutex_on` becomes pid-aware — a holder that is still alive is not stolen from after 120 s of a slow
board write; a dead or absent pid still is, and 20 minutes steals regardless — and `sync_board`
re-stamps the mutex epoch on each retry and reads the remote tip with `ls-remote`, never a bare
`FETCH_HEAD` another fetch may have moved. (3) `evt()` records the event it just wrote into the
session's handover state dir (`.polaris/handover/<sid>/last-event`, plus `started` on first write and
`avoid` on release/blocked/kickback) when a session id is set — the file the handover hook (T-110)
and `polaris next` (T-109) read. Specs: worktree-liveness.md § lock meta / § steals;
role-handover.md § session state.

### Acceptance
- [ ] `lock_take` writes 5 lines: epoch · who · id · `$CLAUDE_CODE_SESSION_ID` or `-` · `$CLAUDE_PID` or `-`; `lock_age` and every other 3-line reader unchanged; probe in a fixture repo: `CLAUDE_CODE_SESSION_ID=sid-x CLAUDE_PID=4242 bash <kit> claim T-1` then `sed -n 4p .git/polaris-locks/T-1/meta` prints `sid-x`, line 5 `4242`; unset env ⇒ `-`
- [ ] `mutex_on` steal: iff age > 120 AND (pid absent OR dead), OR age > 1200; `mutex_off` unchanged
- [ ] `sync_board`: re-stamps `$MUTEX/epoch` at the top of each retry when `$MUTEX/pid` == `$$`; remote tip via `git ls-remote origin refs/heads/polaris/board | cut -f1`; no `FETCH_HEAD` read remains
- [ ] `evt()`: when `$CLAUDE_CODE_SESSION_ID` is set, `mkdir -p "$PRIMARY/.polaris/handover/<sid>"`, overwrite `last-event` with the exact `<ts> <kind> <id>` just appended, create `started` on first write, append the id to `avoid` for kinds release/blocked/kickback — all best-effort (`2>/dev/null || true`), never a failed evt; unset sid ⇒ no state write
- [ ] no new fn (38 before and after); `startup-budget`, `triage-lane` goldens green from the worktree
- [ ] `bash kit/ops/polaris doctor --selftest --only syncrace,claimguard,busyint` green (foreground, ≥600000 ms timeout)
