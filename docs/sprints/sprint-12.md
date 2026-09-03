# Sprint 12 — Parallel work that can't eat itself (6.2.0) (2026-09-01–)

## T-092 — "workspace.sh — beats, wt_remove (archive, never --force), pid-aware lease steal, owned parks"
points 5 · risk normal · landed ff868a8 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
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
points 3 · risk normal · landed fe25859 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
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
points 2 · risk normal · landed ecd3856 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
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
points 2 · risk normal · landed fa4e3b2 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
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
points 4 · risk normal · landed c0a5c56 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
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
points 2 · risk normal · landed a5bb2dc (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
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

## T-098 — "builder.sh — beats on every step, resume/release respect a live worktree, pack prints SEE YOUR WORK, handoff needs the capture"
points 5 · risk normal · landed 5053399 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/builder.sh

### Why
This is where the worktree-liveness primitives (T-092) and the capture step (visual-check.md) meet
the builder's own commands. Beats: `claim`, `resume`, `verify` and `handoff` each touch the worktree
beat so a working session is provably live. Resume: today it adopts ANY lock unconditionally — the
documented takeover path and the lock-side twin of the worktree bug; now a live beat from a
different session refuses with the pinned message naming the beat file (takeover is explicit:
`rm <beat>`), the same session (after a compaction) is allowed, an idle one is adopted, and its meta
rewrite writes all five lines. Release: the worktree goes through `wt_remove <ID> release` (dirty
own-lane ⇒ archive; outside + dirty + live ⇒ the pinned die BEFORE any board write). Pack: a new
"SEE YOUR WORK" section, driven by real `cfg` reads of `visual:`/`shot:`/`port_base:`/`serve:` with
`{ID}`/`{PORT}` substituted (per-task port = port_base + numeric tail mod 100 — T-207 ⇒ 4007), and
the unset line when a repo declares no visual surface. Handoff: when the diff touches a `visual:`
path and `shot:` is set, a non-empty `.polaris/shots/<ID>-*.png` newer than the branch base must
exist, else the pinned refusal (verify only warns). Claim records `task` and `plan` in the session's
handover state dir; the queue notice stops telling the HUMAN to "say start" — the board hands the
session its next step: `bash ops/polaris next`. Specs: worktree-liveness.md (beats, die texts),
visual-check.md (section lines, gate rule), role-handover.md (state dir, the notice).

### Acceptance
- [ ] `beat_touch "$id"` in cmd_claim (after wt_add), cmd_resume, cmd_verify, cmd_handoff — best-effort
- [ ] `cmd_resume`: `beat_live` AND lock meta line 4 ≠ my sid (or `-`) ⇒ die with the pinned resume text (beat age + absolute beat path); same sid ⇒ allowed; idle ⇒ adopt; the meta rewrite writes 5 lines; vanished worktree ⇒ `wt_add "$id" resume` (the recreate warning is workspace.sh's)
- [ ] `cmd_release`: `wt_remove "$id" release` replaces the `--force` line; from outside on dirty+live ⇒ the pinned release die BEFORE `mutex_on`/`mv`; the success line reads `worktree removed|archived|LEFT` per rc; lock dropped in every non-die path
- [ ] `cmd_pack`: the `SEE YOUR WORK — capture before handoff (ops/VISUAL.md)` section between §7 and §8 with the exact lines of visual-check.md § cmd_pack (unset line; `visual: <globs> · this task touches it: yes|no` via `owned_match` both directions; serve/shot substituted; `port:`; `proof:`; `read:`); inline, no new fn at any depth
- [ ] `cmd_handoff`: after `run_verify_cmds` — visual set AND shot set AND diff ∩ visual ≠ ∅ ⇒ require a non-empty `$PRIMARY/.polaris/shots/<ID>-*.png` with mtime ≥ merge-base commit time, else the pinned `⛔ handoff refused: …` die (rc 1, task stays active); `cmd_verify` prints the `⚠` variant and continues
- [ ] `cmd_claim` writes `.polaris/handover/<sid>/task` (every claim) and `plan` (first claim only, from the task's `plan:`), only when `$CLAUDE_CODE_SESSION_ID` is set; best-effort
- [ ] handoff queue notice (:239) reads `$nrdy ready task(s) still queued — the board hands you the next step: bash ops/polaris next`; the `integrate` notice unchanged
- [ ] the hermetic pack probe (verify) prints `shot: snap T-207 4007` and `this task touches it: yes`; a task owning `src/b.txt` prints `touches it: no`
- [ ] `bash kit/ops/polaris doctor --selftest --only claimguard,selfland,park` green (foreground, ≥600000 ms timeout); `resume` on a fresh-beat lock from a DIFFERENT sid dies, from the SAME sid succeeds (drill wtreap automates in W3)

## T-099 — "integrate.sh — done removes a worktree only through wt_remove, keeps the branch of a live one, re-stamps the lease during long steps"
points 2 · risk normal · landed 2efabcc (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/integrate.sh

### Why
`done` is the command that killed ARC-428's worktree: it ran `git worktree remove --force` on
whatever `.polaris/wt/<ID>` existed, then deleted the branch. Now it asks `wt_remove <ID> done`
(T-092): clean and idle ⇒ removed and the local branch deleted as before; dirty and idle ⇒ archived
to `.polaris/wt-archive/<ID>-<epoch>` and the branch deleted; live ⇒ LEFT with the pinned
`branch feat/<ID> kept — checked out in a live worktree; sweep --fix finishes the cleanup once idle`
note and NO `branch -D` — a checked-out branch cannot be deleted anyway, and the builder standing in
it may still need it. The remote-branch cleanup (tip-equality proof) is unchanged. Two riders in the
same file: `land` and `seal` re-stamp the integration lease's epoch after each suite command and each
per-task land while they hold it, so a slow suite never looks abandoned to the pid-aware steal
(T-092); and `audit` prints one `capture: <path>` line per `.polaris/shots/<ID>-*.png` so the
Integrator sees what the builder looked at (visual-check.md). Spec: worktree-liveness.md § decision
table (the `done` row), § steals (the re-stamp).

### Acceptance
- [ ] `cmd_done`: `wt_remove "$id" done`; `branch -q -D feat/$id` runs ONLY after rc 0 or 2; rc 1 prints the pinned kept-branch note; remote cleanup unchanged; no `--force` remains in integrate.sh
- [ ] `land`/`land --express`/`seal`: `date +%s > "$LOCKS/.int-lease/epoch" 2>/dev/null || true` after each suite command and after each per-task land, only while `INT_HELD` is set (at least two sites)
- [ ] `cmd_audit`: prints `capture: <path>` for each `$PRIMARY/.polaris/shots/<ID>-*.png` (none ⇒ nothing); read-only
- [ ] no new fn; `bash kit/ops/polaris doctor --selftest --only selfland,express,busyint` green (foreground, ≥600000 ms timeout) — `done` on the self-landed task's OWN live worktree now LEAVES it (drill_selfland's new assert lands with T-104; keep the existing asserts green)

## T-100 — "observe.sh — sweep reaps idle worktrees and reports live ones, orphan grace, qa stamps after, doctor sees keep-awake, finish and fleet learn the handover"
points 5 · risk normal · landed 93cd6e4 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/observe.sh

### Why
The observing commands learn what the primitives now make true. `sweep` gains a worktree pass:
every `.polaris/wt/<ID>` is reported as LIVE (beat age, left alone) or IDLE (task column, age,
clean/dirty), and `--fix` removes idle clean ones (plus `branch -D` when the task is in done/) and
archives idle dirty ones through `wt_remove <ID> sweep` — which is what finally makes `finish`'s
caveat and `uninstall`'s "run sweep --fix" remedy true. Stale-lock lines gain "last activity <m>m
ago · session alive|gone" (lock meta line 5 via ONE `ps -W` on Windows, else `kill -0`); an orphan
lock younger than 120 s is reported but never dropped (a claim may be mid-flight); today's
`integrate/<date>` is never swept; `.polaris/bg/.archive/*` and `.polaris/handover/<sid>/` older than
24 h are pruned by `--fix`; `status` lists parks with age. `qa` writes its suite stamp only when HEAD
is unmoved AND the tree is clean AFTER the suite (`stamp withheld` otherwise) — a stamp taken before
a sibling's land could green a `finish` on code nobody tested. `doctor` warns when the keep-awake
hooks are not merged into `~/.claude/settings.json` or the daemon is disabled (gated on
`~/.claude` existing). `finish` rc 0 writes `.polaris/handover/<sid>/finished` so the Stop hook
never hops a finished session. The fleet kickoff carries the visual sentence and ends with
`then bash ops/polaris next and follow it` instead of "Stop at the review handoff". Specs:
worktree-liveness.md (sweep lines, grace), keep-awake.md (doctor lines), role-handover.md (state
dir, kickoff), bg-jobs.md v2 (archive pruning), visual-check.md (kickoff sentence).

### Acceptance
- [ ] `cmd_sweep` worktree pass over `git worktree list --porcelain` paths under `.polaris/wt/`: LIVE/IDLE lines byte-exact per contract; `--fix` ⇒ `wt_remove <ID> sweep`, `branch -D` on rc 0 when the task is in done/; `integrate/<date>` of today untouched; `--fix` prunes `.polaris/bg/.archive/*` and `.polaris/handover/<sid>/` older than 24 h
- [ ] orphan lock < 120 s ⇒ the pinned "younger than 120s" line, never dropped; STALE line gains ` · last activity <m>m ago · session alive|gone` (line 5 pid; `-` ⇒ gone); ONE `ps -W` per sweep on Windows
- [ ] `cmd_qa`: stamp written only when `git rev-parse HEAD` before == after AND `git status --porcelain` empty after; else one `⚠ … stamp withheld` line
- [ ] `cmd_doctor`: the two pinned keep-awake lines, gated on `[ -d "$HOME/.claude" ]`; silent when armed and enabled; `keys-drift` golden byte-identical
- [ ] `cmd_finish` rc 0 ⇒ `.polaris/handover/<sid>/finished` (epoch, best-effort, only with a sid); `cmd_status` lists parks `park: <name> · <age>m · <why>`
- [ ] `cmd_fleet` kickoff `msg` (:1869): visual sentence appended (single quotes only inside `msg`), `Stop at the review handoff.` → `then bash ops/polaris next and follow it.`; `--launch`/tmux quoting unchanged
- [ ] no new fn; `startup-budget` unchanged; `bash kit/ops/polaris doctor --selftest --only finish,qa,drift,hint` green (foreground, ≥600000 ms timeout)

## T-101 — "polaris awake + polaris next reach the CLI — lib/awake.sh, loader +awake +handover, dispatch, usage blocks, preamble beat, awake_ensure; api-kit owner W2"
points 5 · risk normal · landed 02a941e (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/awake.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
Two new commands reach the CLI here: `polaris awake` (the machine's keep-awake face, T-102 builds
the hook it drives) and `polaris next` (the handover router, T-109 builds the module). This task owns
the entry script — the ONE owner of `kit/ops/polaris` this sprint — and `lib/awake.sh`: `awake_home`,
`awake_conf`, `awake_ensure` (fork-free when the daemon's beat is fresh; a silent no-op on an unarmed
machine or in CI), `awake_status_line` (three pinned shapes) and `cmd_awake` (status · start · stop =
60 minutes off · disable · enable · install). The loader gains `awake` after `bg` and `handover`
after `awake` (module-layout v5); the guard path stays `core ownership`. Dispatch: `awake`, `next`;
the two byte-pinned usage blocks (`cli-help-parity` learns `next` in W3; `cli-help.expected` moves
only after dogfood — T-108). The preamble gets the builtins-only worktree beat below `EVENTS=`, so
every CLI call from inside a worktree keeps it live; `awake_ensure || true` fires from the dispatch
arms of `claim`, `status`, `doctor`, `handoff` and `bg run`. This task is also the W2 api-kit owner:
it writes the whole 44-row union — its own 5, the 19 awake-hook fns (T-102), the 8 handover fns
(T-109) and the 12 handover-hook fns (T-110) — from the names the contracts pin. Specs: keep-awake.md
(awake.sh + entry wiring + usage bytes), role-handover.md (next usage bytes + dispatch + the
parallel-build note), module-layout.md v5, key-registry.md §7.

### Acceptance
- [ ] `lib/awake.sh`: exactly the five fns, ≤150 lines; `awake_ensure` returns 0 without forking when `daemon/beat` < 3×TICK old, returns 0 silently when neither `$POLARIS_AWAKE_HOME` nor `~/.claude/polaris/awake-hook.sh` exists, else backgrounds `bash <hook> ensure "$PRIMARY"`; `stop` = stop flag + kill MSYS pid + rm lock + `disabled` with a 60-min expiry; status line shapes byte-exact
- [ ] entry: loader `… admin bg awake handover` (guard list untouched); `awake)` and `next)` dispatch arms (no `update_check_maybe` on `next`); the preamble beat `case` below `EVENTS=` and above the dispatch; `awake_ensure || true` inside the five arms; both usage blocks byte-exact (3 lines each, description column 34); entry < 500 lines; `startup-budget` unchanged
- [ ] api-kit.expected = 625 lines: the 44 pinned W2 rows in `find --api` order; completeness `<` count 0 in this worktree; sibling `>` rows are exactly the awake-hook/handover/handover-hook rows until the wave lands
- [ ] `bash kit/ops/polaris awake status` prints one of the three shapes (tested with the untracked stub described in Notes, then the stub deleted); `bash kit/ops/polaris doctor --selftest --only fmlist,newcmds` green after T-109 lands (or with the stub, foreground ≥600000 ms)
- [ ] no other fn anywhere; no heading; no KEYS row

## T-102 — "awake-hook.sh + awake-press.ps1 — the machine-level keep-awake daemon: silent hooks, transcript-mtime verdict, WMI spawn, lock-screen-safe press"
points 3 · risk normal · landed fb5bf3c (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/hooks/awake-hook.sh, kit/ops/hooks/awake-press.ps1

### Why
The machine sleeps mid-run. One keep-awake owner per machine, never one per session, never
interrupting a human who is typing, and it must keep working on the LOCK screen — synthetic
keypresses never reach the secure desktop, which is exactly the moment the box is about to sleep.
Two files: `awake-hook.sh` is both the four machine-level hooks (`start` `busy` `idle` `end` — zero
stdout, rc 0 always, because UserPromptSubmit stdout enters the model's context and rc 2 on Stop
means "keep going") and the daemon (`daemon`/`tick`: one pass per TICK over the registry under
`~/.claude/polaris/awake/`; a session is active when it is busy and its transcript — or a
`<sid>/subagents/*.jsonl` — moved within STALE, or idle-but-recently-active, or any registered repo
has a live bg job; quiet for GRACE ⇒ exit; `stop` ⇒ exit; two spawners ⇒ `mkdir lock` decides;
a stale beat is stolen). The daemon is spawned via `Invoke-CimMethod Win32_Process Create` so it
lives outside every caller's Job Object and survives the spawning terminal; `Start-Process` and
inline are fallbacks. `awake-press.ps1` ALWAYS calls `SetThreadExecutionState(ES_SYSTEM_REQUIRED)`
one-shot (works locked, holds nothing) and adds the F-key (F15 default, `none` disables) only when
the station is unlocked and the user has been input-idle > 60 s; it prints one word
(`pressed|skipped-active|skipped-locked|state-only`). `install` merges the four hook entries into
`~/.claude/settings.json` by script-path identity, foreign entries untouched, fails open. `--test`
prints one line per subcommand for the golden (T-106) and the drill (T-104). No CONVENTIONS key —
this is machine-level. Every name, path, default and word is pinned in keep-awake.md.

### Acceptance
- [ ] exactly the 19 pinned fns (`jstr` verbatim from checkout-guard.sh:59-95 + 18 `ah_*`); dispatch `start|busy|idle|end|ensure|daemon|tick|install|--test`; ≤320 lines; bash 3.2; `set -u`
- [ ] the four hook subcommands: `exec >/dev/null 2>>hook.log`, `set +e`, `trap 'exit 0' EXIT`, exit 0 always, ZERO stdout even on malformed input; `start` creates idle only when absent (never downgrades busy); `busy` writes busy + registers the repo + ensures the daemon; `end` deletes
- [ ] registry root resolution (`POLARIS_AWAKE_HOME` → `${0%/*}/awake` under `.claude/polaris/` → `$HOME/.claude/polaris/awake`); `config` parsed by `case`, never sourced; `POLARIS_AWAKE_<KEY>` env wins; defaults KEY=F15 TICK=55 STALE=2700 IDLE=900 GRACE=300 DISPLAY=1 INPUT_IDLE=60
- [ ] `ah_verdict` per contract (dead pid ⇒ rm session; >24 h ⇒ rm; transcript + newest subagents jsonl mtime; busy/idle rules; bg-job clause); `ah_press` writes `daemon/last-press`; presser failure logs once per 100 ticks, never kills the daemon; `disabled` ⇒ no press
- [ ] `ah_daemon`: mkdir-lock singleton, stale-beat steal (> 3×TICK), `daemon/beat` each tick, `stop` flag, GRACE exit, `sleep TICK & wait $!`, TERM/INT trap removes the lock
- [ ] `ah_spawn`: WMI Create with `POLARIS_AWAKE_CMD` (records `daemon/winpid`), `Start-Process -WindowStyle Hidden -PassThru` fallback, inline last resort with a logged warning; `POLARIS_AWAKE_SPAWN=inline` seam; mac/Linux `nohup … & disown`; powershell path per contract
- [ ] `ah_install`: python heredoc (stdlib), identity regex `polaris/awake-hook\.sh`, replace ours / append absent / foreign untouched, tmp + os.replace, fails open; entries SessionStart(5) UserPromptSubmit(10) Stop(5) SessionEnd(5) with the pinned command shape and ABSOLUTE paths (never `$HOME`)
- [ ] `awake-press.ps1` ≤80 lines with the four P/Invokes and the pinned word contract; `POLARIS_AWAKE_PRESSER` replaces it wholesale; mac `caffeinate -u -t 75` (`-i` when DISPLAY=0); Linux xdotool → xdg-screensaver → log once
- [ ] `--test start|busy|idle|end|tick` print exactly the pinned one-liners and never spawn or sleep
- [ ] proven by hand with the drill seams (`POLARIS_AWAKE_HOME=$T POLARIS_AWAKE_PRESSER="touch $T/pressed" TICK=1 IDLE=3 STALE=5 GRACE=2 SPAWN=inline`): busy + fresh fake transcript ⇒ `pressed` within 3 s; all idle ⇒ self-exit after GRACE with `lock/` gone (drill `awake` in W3 automates it)

## T-103 — "Install side — VISUAL.md ships, new hooks are executable, keep-awake reaches every armed machine, uninstall refuses archives and strips every hook entry"
points 3 · risk normal · landed 64eeaca (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/.claude/skills/polaris-install/SKILL.md, kit/ops/bootstrap.py, kit/ops/install.sh, kit/ops/lib/admin.sh

### Why
Everything the sprint built has to reach installed repos and armed machines, and be removable.
`install.sh`: `VISUAL.md` joins the `KIT_CODE` manifest (so `ops/VISUAL.md` exists in every repo and
is RULES-guarded like its siblings) and the chmod list gains the two new hooks. `bootstrap.py`
(`arm_machine`, the installer's machine step): extract `awake-hook.sh` + `awake-press.ps1` from the
archive into `~/.claude/polaris/` and run the hook's `install` through ONE new fn
`merge_awake_hooks` (fails open with one ⚠ line — a machine problem never fails a repo install).
`admin.sh` (`refresh_machine_kit`, the `update` path): copy the same two files (source `kit/ops/hooks/`
first, `ops/hooks/` fallback — the existing two-path pattern) and run `install`. `cmd_uninstall`:
die BEFORE the worktree check when `.polaris/wt-archive/` is non-empty (uncommitted work lives there
— the human moves it out), deregister this repo from `~/.claude/polaris/awake/repos/` (never the
daemon or the hooks — other repos use them), and strip EVERY `ops/hooks/` entry across ALL hook
events (Stop, SessionStart, UserPromptSubmit, PreToolUse …), foreign entries kept — today it strips
only the ownership guard, and a dangling Stop hook would error on every turn of an uninstalled
repo. The machine-level install skill (`kit/.claude/skills/polaris-install/SKILL.md`) says what
"arms the machine" now includes: its sentence gains the keep-awake hooks — one prose edit, no
heading change. Specs: keep-awake.md § installers, worktree-liveness.md § wt-archive,
role-handover.md (uninstall strip), visual-check.md (manifest).

### Acceptance
- [ ] `install.sh`: `KIT_CODE` += `VISUAL.md`; chmod line (:106) += `ops/hooks/awake-hook.sh` and `ops/hooks/handover-hook.sh`; fresh and live-board paths both copy it (they share the list); nothing else changes
- [ ] `bootstrap.py`: `merge_awake_hooks(bash_path)` (the ONLY new def; no new module-level constant) extracts both files to `~/.claude/polaris/`, chmods the .sh, runs `bash <abs>/awake-hook.sh install`; called from `arm_machine`; any failure ⇒ one ⚠ line, install continues; `PERMS` untouched
- [ ] `admin.sh` `refresh_machine_kit`: copies both files (two-path fallback like :204-207) to `~/.claude/polaris/` and runs `install`; fails open; no new fn
- [ ] `cmd_uninstall`: the pinned wt-archive die (count in the message) BEFORE the existing worktree-count die; removes `~/.claude/polaris/awake/repos/<cksum>` for THIS primary only; the settings-strip python removes every entry whose command matches `ops/hooks/` under EVERY hook event, keeps foreign entries and empties-out events with no entries left; existing prompts/notes unchanged
- [ ] proven by hand in a throwaway repo (scratchpad/T-103/): `bash kit/ops/install.sh <dir>` then plant a foreign Stop entry + the three handover entries + the awake-style entries in its `.claude/settings.json`, `uninstall --yes` ⇒ exactly the foreign entry remains; with a non-empty `.polaris/wt-archive/x-1/` ⇒ the pinned die; `HOME=$T/home python kit/ops/bootstrap.py`-style arm on a fixture home ⇒ `~/.claude/polaris/awake-hook.sh` present and four hook entries merged (never against your real `~/.claude`)
- [ ] `kit/.claude/skills/polaris-install/SKILL.md`: the "arms the machine" sentence mentions the keep-awake hooks (plans/v2.md WS3); the `^#` line set byte-identical to `main` (the skill is indexed by api-kit); nothing else in the file changes
- [ ] `bash kit/ops/polaris doctor --selftest --only upgrade,adopt` green (foreground, ≥600000 ms timeout); `python kit/ops/pack.py --allow-dirty` green (the build:)

## T-104 — "Prove it — drills wtreap + awake, selfland keeps its own worktree, checkoutguard/bg learn the new cases, hermetic awake home in the spine; api-kit owner W3"
points 5 · risk normal · landed 725bfa3 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/selftest/history.sh, kit/ops/lib/selftest/policy.sh, kit/ops/lib/selftest/spine.sh, ops/tests/api-kit.expected

### Why
Behavior that prose cannot hold must be drilled or it silently regresses — that is the Learned log's
first lesson and why sprint 11 held at zero kickbacks. Three drills for the sprint's mechanics, two
of them here: `wtreap` (history.sh, after `drill_selfland`) walks the worktree-liveness decision
table end to end — dirty + backdated beat ⇒ `done` archives with the bytes intact and deletes the
branch; fresh beat ⇒ `done` LEAVES it and keeps the branch; `release` from outside on a dirty live
worktree dies naming the beat file, `rm <beat>` ⇒ archives; `resume` from another session id is
refused, from the same id succeeds; `sweep` reports LIVE, backdated ⇒ `sweep --fix` removes clean /
archives dirty. `awake` (policy.sh, after `drill_checkoutguard`, on the `drill_bg` template) proves
the daemon hermetically with the contract's seams: silent hooks, never-downgrade start, press within
3 s when busy, self-exit after GRACE, stale steal, stop, disabled, re-entrant start, the bg-job
clause, and `install`'s merge on a fixture settings.json. `drill_selfland` gains the assertion that
the self-landed handoff's OWN worktree survives (LEFT) and a later backdated `sweep --fix` removes
it; `drill_checkoutguard` gains the worktree/rm/kill cases; `drill_bg` the foreign-cwd refusal. The
spine registers the three labels (`wtreap awake handover` — the `handover` body is T-111's, board.sh)
and exports `POLARIS_AWAKE_HOME="$T/awake-home"` right after `T="$(mktemp -d)"` so `bg run` inside
ANY drill never registers a fixture repo on the owner's real machine. This task is also the W3
api-kit owner: the four pinned rows (three drills + `merge_awake_hooks`). Specs: worktree-liveness.md
§ executable check, keep-awake.md § drill, shared-checkout.md v2.5 §3, bg-jobs.md v2, key-registry.md §7.

### Acceptance
- [ ] `drill_wtreap` asserts every numbered item of worktree-liveness.md § executable check with rcs and file states (bytes in the archive, branch presence, beat-file path in the die text), `export CLAUDE_CODE_SESSION_ID=drill-sid` for the claiming session and a different sid for the refusal case; hermetic (`git status --porcelain` unchanged across it, green twice in a row)
- [ ] `drill_awake` asserts the eight numbered items of keep-awake.md § drill with the pinned seams; every daemon it starts is stopped or has exited before the drill returns; skips the `install` merge with a note when `python` is absent
- [ ] `drill_selfland`: after case (a), the handoff's own worktree still exists (`worktree LEFT` in the land tail) and a backdated `sweep --fix` removes it; existing asserts unchanged
- [ ] `drill_checkoutguard` + `drill_bg` gain the pinned cases (shared-checkout v2.5 §3, bg-jobs v2); rc + JSON shape asserted, never message presence alone
- [ ] spine: `SELFTEST_LABELS` ends `… checkoutguard readyoverlap selfland wtreap awake handover`; `drill_on` blocks for all three in run order (wtreap after selfland, awake after checkoutguard, handover after readyoverlap); the `POLARIS_AWAKE_HOME` export at :115; `--only` selects each individually; full-run label count 31 → 34
- [ ] each new assertion watched RED once under a semantic sabotage in a throwaway kit copy (read the sabotage diff), then green on restore; sabotage evidence from a possibly-corrupted run re-proven in a clean dir
- [ ] `bash kit/ops/polaris doctor --selftest --only wtreap,awake,selfland,checkoutguard,bg` green (foreground, ≥600000 ms timeout, or `bg run` + chunked `bg wait`); `--only handover` green once T-111 has landed
- [ ] api-kit.expected = 629 lines: the four pinned W3 rows in `find --api` order; completeness `<` count 0 here; the only sibling `>` rows until the wave lands are `drill_handover` (T-111) and `merge_awake_hooks` (T-103)

## T-105 — "Golden pack-visual — the SEE YOUR WORK section, the per-task port, and the handoff capture gate, hermetically"
points 2 · risk normal · landed a02d0f9 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: ops/tests/pack-visual.cmd, ops/tests/pack-visual.expected

### Why
The capture step is absent-by-default and driven by four keys, which is exactly the kind of
behavior that rots invisibly: a repo without `visual:` must see nothing, a repo with it must see
the section with the right port, and `handoff` must refuse a visual change without a fresh capture
and pass with one. This golden pins all of it in ONE hermetic fixture repo (the `keys-drift`/
`triage-lane` pattern: throwaway repo, CLI run from inside it, byte-identical from any board state):
`visual: web/*`, `shot: snap {ID} {PORT}`, `serve: dev {PORT}`, `port_base: 4000`,
`landing: integrator` (so the handoff never runs a land tail), `T-207` owning `web/a.txt` and
`T-300` owning `src/b.txt`. Asserts: `pack T-207` prints the section verbatim with port 4007
(207 mod 100 = 7) and `touches it: yes`; `pack T-300` ⇒ `touches it: no`; `visual:` removed ⇒ the
unset line only; claim T-207, commit a `web/a.txt` change, `handoff` without a capture ⇒ the pinned
refusal and rc 1 with T-207 still in `active/`; a non-empty `.polaris/shots/T-207-home.png` ⇒ rc 0
and T-207 in `review/`. Spec: visual-check.md § executable check.

### Acceptance
- [ ] the five numbered asserts of visual-check.md § executable check, each printing the CLI lines that matter plus `rc N`; machine-specific bytes (paths, pids, durations, epochs) normalized like `bg-lifecycle.cmd`'s `N()`; no kit version number in the expected file
- [ ] hermetic: builds its own repo under `mktemp -d`, `trap … EXIT` cleanup, never reads the live board, config or registry; byte-identical on a second run; total runtime measured and written in the `.cmd` header (target < 10 s — if the two handoffs push it over, keep them and say so: `check` pays it once per run)
- [ ] the `.cmd` header comment explains WHY each assert exists (the house style of every golden here); no `#`-leading line problem (goldens are not indexed)
- [ ] proven from the worktree with the `.cmd`-body diff; sabotaged red once (port_base 4001 ⇒ 4008) before trusting green; after landing, the integrator runs `check --only pack-visual` on the primary, sabotages it red, restores green (a golden nobody has seen fail is not evidence)

## T-106 — "Golden awake-hook — every hook subcommand's --test line, a stub-presser tick, the disabled flag, silence on the live path"
points 1 · risk normal · landed 045257e (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: ops/tests/awake-hook.cmd, ops/tests/awake-hook.expected

### Why
The keep-awake hook's ONE hard contract is silence — a byte on stdout from UserPromptSubmit lands
in the model's context, an rc 2 from Stop tells the harness to keep going — and the `--test` words
are what the drill and the humans read. This 1-point golden pins both, cheaply, on every `check`:
each of `start busy idle end` via `--test` (with `start` run twice to prove `(kept)` never
downgrades busy, and a Windows-escaped `transcript_path` in the JSON), `--test tick` with the stub
presser (`tick: active pressed`), with the `disabled` flag (`tick: active disabled`), and with every
session idle (`tick: quiet no-press`); then the LIVE subcommands once each with stdout byte-counted
(`live-stdout-bytes: 0`) and rc printed. Registry paths normalized to `<home>`. Hermetic under a
mktemp `POLARIS_AWAKE_HOME`; never touches the owner's registry. Spec: keep-awake.md § golden.

### Acceptance
- [ ] the `.cmd` sets `POLARIS_AWAKE_HOME=<mktemp>`, `POLARIS_AWAKE_PRESSER="touch $H/pressed"`, `POLARIS_AWAKE_SPAWN=inline`, `POLARIS_AWAKE_TICK=1`; never spawns a daemon (only `--test tick`, which does one pass); cleans up with `trap … EXIT`
- [ ] the pinned lines for each case exactly as keep-awake.md § `--test` specifies; `live-stdout-bytes: 0` and `rc 0` for the four live subcommands; paths normalized to `<home>`
- [ ] runtime < 3 s; byte-identical on a second run; no kit version number in the expected file
- [ ] proven from the worktree with the `.cmd`-body diff; sabotaged red once (a stray `echo` in `ah_hook_idle` in a throwaway copy) before trusting green

## T-107 — "Role prose for 6.2.0 — see your work, the port rule, Loop mode becomes handover, Invariant 5 per context, an approved plan is a kickoff"
points 3 · risk normal · landed e460cdc (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/.claude/skills/polaris/SKILL.md, kit/CLAUDE.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md

### Why
Every mechanic this sprint ships needs one sentence in the role that uses it, or it is a feature
nobody follows. Bold paragraphs and list items ONLY — the api-kit golden records every `#` line
(fenced ones included), so the heading set of all eight files stays byte-identical to `main`.
BUILDER: `**4b. See your work.**` between §4 and §5 (run the printed `shot:` line, READ the image,
one `saw:` line, blank = failure, never build your own capture tool, `handoff` refuses without the
capture), the port sentence in §3, step 1b's "no prompt" reason becomes the kit's own rule (6.2.0),
`## Loop mode`'s body becomes the default under `handover: auto` (run `next` after every handoff and
follow it; `off` restores one task per session), and "you never end the run" narrows to
conductor-entered builders. SOLO: step 4 + "What you must NOT skip" + the port bullet + the close
follows `next`. PLANNER: 7c (a visual surface names its capture) + may continue as BUILDER at the
boundary. CONDUCTOR: the visual kickoff line, the dead-lane sentence, "compacted mid-run?" → the
anchor already re-read the board, panes loop via `next`, and **Entered from an approved plan?** —
the plan IS the brief. INTEGRATOR: open the capture before landing; §5 promote → `next --do`. INIT:
the DERIVE row for the four keys + four skeleton lines beside `runnable:` + the §2c allow-rule note.
`kit/CLAUDE.md`: Invariant 5 rewritten per context (verbatim from role-handover.md), the :45-47
bullet, the "approved plan" dispatch row + bullet; `SKILL.md`:5 + the step-1 routing row. Every
line is pinned verbatim in visual-check.md § role prose, role-handover.md § role prose / § WS8 and
permission-rules.md § role prose — copy them, do not paraphrase.

### Acceptance
- [ ] every pinned line landed byte-exact in its named place (visual-check.md, role-handover.md, permission-rules.md); the `^#` line set of all eight files identical to `main`'s
- [ ] BUILDER `## Loop mode` heading kept, body rewritten; "You never end the run" paragraph narrowed to conductor-entered builders; `kit/CLAUDE.md` keeps `subagent never ends a run` and `🎉 Complete!` (`output-style-installed` golden green)
- [ ] `kit/CLAUDE.md` § ROLE DISPATCH table gains the approved-plan row (3 columns, the table still renders) and the bold bullet; Invariant 5 reads exactly the pinned text; the :45-47 bullet reworded per role-handover.md
- [ ] INIT skeleton lines carry trailing `#` comments only, in the `runnable:` style; the DERIVE row fits the table; §2c note added
- [ ] `kit/CLAUDE.md` byte budget respected: the file is injected into every subagent — the two additions total ≤ 6 lines
- [ ] `python kit/ops/pack.py --allow-dirty` green; `bash kit/ops/polaris doctor --selftest --only claudemd,hint` green (foreground, ≥600000 ms timeout)

## T-108 — "Release 6.2.0 — parallel work that can't eat itself ships to every POLARIS repo"
points 2 · risk normal · landed 003838f (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
The sprint's last task: bump `kit/ops/VERSION` to 6.2.0 and write the CHANGELOG entry in the 6.1.0
style — a before/after table (worktree removal · auto-mode prompts · machine sleep · visual proof ·
guard verbs · bg ownership · role handover · approval is the kickoff), the two new defaults that
live in code (`wt_live_minutes` 15, `handover` auto), the awake `disabled` opt-out, the three drills
(`wtreap` `awake` `handover`) and the five goldens (`perm-tools` `pack-visual` `awake-hook`
`handover-route` `handover-stop`); BREAKING: none; NEW: the awake hooks reach every armed machine on
`update`. The bump is the WHOLE release (CONVENTIONS § Release ritual, CI's one-version job):
after this task lands and the board is drained, the conductor tags `v6.2.0`, waits for the
published zip, runs `python kit/ops/pack.py --dogfood` (the ONE pre-announced classifier click when
it rewrites `~/.claude/settings.json`), re-pins `ops/tests/cli-help.expected` (it runs the INSTALLED
`ops/polaris`, which only now knows `awake` and `next` — the golden moves here and nowhere earlier),
commits the refreshed `ops/`, and confirms `bash ops/polaris version` reads 6.2.0. This task's own
verify proves the bump and the entry; the installed `ops/VERSION` must still read 6.1.0 at handoff —
dogfood is the finish ritual's, never a build step.

### Acceptance
- [ ] `kit/ops/VERSION` `version: 6.2.0`; nothing else in the file changes
- [ ] `CHANGELOG.md` `## 6.2.0 — <date>` above 6.1.0, in the 6.1.0 style, naming every item above; no other version quoted in the entry except the single "since 6.1.0" reference; docs elsewhere quote no version (CI's one-version sweep)
- [ ] `ops/tests/cli-help.expected` untouched at handoff (it is re-pinned by the release tail after dogfood — the task owns it so the re-pin commit is inside a task's ownership); at the tail: `bash ops/polaris check --only cli-help` green, the diff against `main` shows ONLY the `awake` and `next` usage blocks added
- [ ] installed `ops/VERSION` still 6.1.0 at handoff; `polaris-v5.zip` still STALE — by design until the tail
- [ ] release tail (conductor + human, after finish): `git tag v6.2.0 && git push --tags` → zip published → `python kit/ops/pack.py --dogfood` (one click) → re-pin cli-help → commit `ops/` → `bash ops/polaris version` = 6.2.0 → the keep-awake manual checklist from a fresh chat → product repo `polaris update` + keys (owner names the path)

## T-109 — "lib/handover.sh — polaris next: the seven-verb router off the board, --do promotes under the lock, --brief re-anchors a compacted chat"
points 5 · risk normal · landed 0c1c6fe (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/handover.sh

### Why
A session ends with its task, so every next role needs a human kickoff — and a five-pane run needs
`start` nudges at every wave. `polaris next` reads the board and says, in ONE word on line 1, what
THIS session does next: `resume <ID>` (my own live lock — never a second task mid-task),
`integrate` (something landable in review/ and the lease is free, stale or mine — under both landing
modes, because a self-land tail that queued leaves its task for nobody), `stop` (a run budget hit —
the conductor's verbatim budget line), `build <ID>` (an unlocked, un-avoided, non-foreign ready
task, top wsjf), `promote` (backlog work that passes the full ready gate), `wait` (only with work
genuinely in flight — never with nothing), else `finish`. Notes follow on three-space lines (the
`triage` shape); `next` writes nothing. `--do` performs the promote reusing what exists — `mutex_on`,
drift's ready-gate checks, `rules_gate`, claim's disjointness loop (including tasks promoted earlier
in the same pass), `mv` + `set_fm` + `evt promote` + ONE `board_commit` + `sync_board`, then `drift`
as audit; a second `--do` says `nothing to promote`. `--brief` prints ≤8 lines (`role:` `task:`
`worktree:` `last:` `next:` and the role-file pointer) so a compacted chat re-anchors from disk.
Every rule, note text and marker is pinned in role-handover.md — the hook (T-110), the drill and
goldens (T-111) and the role prose (T-107) all build against that table, so no verb may drift.

### Acceptance
- [ ] exactly the eight pinned fns, ≤300 lines, bash 3.2; line 1 always `<verb>[ <ID>]`, every other line `^   `, rc 0 (rc 1 only on a usage error); `next` never writes the board or the state dir
- [ ] `next_route` implements the seven rows IN ORDER with the pinned note texts; `wait` never with nothing in flight; `stop` only when a build/promote would otherwise fire; foreign = `drain: plan` ∧ task `plan:` set ∧ ≠ `<dir>/plan` (missing `plan` file ⇒ nothing foreign); `avoid` honored; budget = hops ≥ `run_max_tasks` (≠0) or minutes since max(`started`, `prompted-at`) ≥ `run_max_minutes` (≠0)
- [ ] `--do`: the promotion algorithm exactly as pinned (mutex, re-check inside, `held:` notes for ask scopes and overlaps, ONE `board_commit "chore(board): promote <IDs>"` + EVENTS, `sync_board`, `mutex_off; trap - EXIT`, `cmd_drift` audit); nothing eligible ⇒ `nothing to promote` rc 0; `evt promote "$id" "deps done: <list>" "$pts"`
- [ ] `--brief`: ≤8 lines, no `|`, markers `role:` `task:` `worktree:` `last:` `next:` + `read ops/roles/<ROLE>.md if this context lost it`
- [ ] proven in a throwaway kit copy (the verify harness): empty board ⇒ `finish`; one ready task ⇒ `build T-1`; a backlog task with its dep in done/ ⇒ `promote`, then `--do` moves it to ready/ with the promote event and board subject, and a second `--do` prints `nothing to promote`; an overlapping backlog task is held with the note; a lock with a foreign sid on an active task ⇒ `wait`; `run_max_tasks: 1` with `hops`=1 ⇒ `stop` + the budget line
- [ ] no other fn; nothing in this task touches `kit/ops/polaris` (T-101 wires dispatch/loader/usage)

## T-110 — "handover-hook.sh — the Stop backstop, the compaction anchor and the prompt clock; kit settings entries; readonly-allow learns next"
points 3 · risk normal · landed 74effdb (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/.claude/settings.json, kit/ops/hooks/handover-hook.sh, kit/ops/hooks/readonly-allow.sh, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected

### Why
The loop lives in role prose (every role runs `polaris next` at its boundary); this hook is the
backstop for a model that stopped anyway, and the re-entry after a compaction. `stop` runs a ladder
of cheap gates — no state dir (ordinary Q&A pays ~150 ms and is allowed), `handover: off`, an event
that is not a completion, an event already hopped (string equality of `last-event` and
`hopped-event`: ONE event, ONE hop), a finished run, the harness cap, our own hop cap, a subagent's
event in the parent's dir (a conductor is never hopped into BUILDER), a session that stopped to ask
(`⛔` line or trailing `?`), a `ship-<ID>` job still running (block with "collect it") — and only then
asks `polaris next`, blocking with the pinned reason for `build`/`integrate`/`promote`/`finish` and
allowing `wait`/`stop`/`resume`. It NEVER writes the board: `promote` tells the model to run
`next --do` in its own turn. `anchor` prints `next --brief` after a compaction or resume when the
state dir exists; `prompt` writes `prompted-at` with zero stdout (UserPromptSubmit stdout enters the
model's context). The three entries land in `kit/.claude/settings.json` (the same file T-095 gave
the seven tool names in W1); `readonly-allow.sh` auto-approves `next` and `next --brief` (reads)
and keeps asking for `--do` (a board write), with two golden lines. Every rung word, reason template
and file is pinned in role-handover.md; T-111 goldens the ladder in W3.

### Acceptance
- [ ] exactly the 12 pinned fns; subcommands `stop|anchor|prompt|--test [stop|anchor|prompt]`; ≤220 lines; bash 3.2; reads `session_id` `transcript_path` `cwd` `stop_hook_active` from stdin JSON (`hh_jstr`, the checkout-guard reader); primary per `hh_primary`'s pinned order (cwd segment · cwd with `ops/board` · `$CLAUDE_PROJECT_DIR` · rev-parse); `hh_cfg` reads CONVENTIONS with `sed`, never `ops/polaris`, on the allow path
- [ ] the ladder in the pinned order with the pinned `--test` words; a block writes `hops` (+1) and `hopped-event` BEFORE emitting; `--test` differs from live ONLY in output shape; `POLARIS_HANDOVER_NEXT` replaces the `next` call; `POLARIS_HANDOVER_CLI` replaces `<primary>/ops/polaris`
- [ ] `hh_emit` is the ONE emitter: block = `{"decision":"block","reason":"…"}` on stdout, exit 0 — or the shape the harness docs specify at build (verify and record in Notes; exit 2 + stderr as the documented fallback); allow = no output, exit 0; the five reason templates byte-exact with N/<cap>/IDs/PRIMARY substituted
- [ ] `anchor`: prints `bash <primary>/ops/polaris next --brief` output only when the state dir exists (else nothing); `prompt`: builtins only, writes `prompted-at`, zero stdout, rc 0
- [ ] `kit/.claude/settings.json`: Stop (30 s) · SessionStart matcher `compact|resume` (10 s) · UserPromptSubmit (5 s) entries with `bash "$CLAUDE_PROJECT_DIR/ops/hooks/handover-hook.sh" <sub>`; the seven tool names and every existing entry untouched; `perm-tools` + `output-style-installed` goldens green
- [ ] `readonly-allow.sh` `polaris_ok`: `next` bare and `--brief` allow, `--do` asks; golden +2 lines (`allow  bash ops/polaris next` · `ask  bash ops/polaris next --do`); every existing line byte-identical
- [ ] the four build-time verifications recorded in Notes: `stop_hook_active`/cap semantics, the Stop block JSON shape, subagents-dir mtime freshness, the last-assistant-text shape; a fact that does not hold ⇒ that rung fails OPEN (allow) and Notes say so
- [ ] never mutates the board; never forks `ops/polaris` before the `block:collect` rung

## T-111 — "Drill handover + goldens handover-route / handover-stop — every verb, --do, the hook ladder, hop cap, handover: off; cli-help-parity learns next"
points 3 · risk normal · landed 1a34c67 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/selftest/board.sh, ops/tests/cli-help-parity.cmd, ops/tests/cli-help-parity.expected, ops/tests/handover-route.cmd, ops/tests/handover-route.expected, ops/tests/handover-stop.cmd, ops/tests/handover-stop.expected

### Why
`polaris next` is now the router every role follows and the Stop hook's oracle — a wrong line 1
misroutes a whole session, and a hook that blocks when it should allow traps a chat in a loop. Both
must be proven where prose cannot hold them. `drill_handover` (board.sh, `export
CLAUDE_CODE_SESSION_ID=drill-sid`, hermetic on the spine repo) walks the contract's assertion list
in order: help lists `next`; a ready task ⇒ `build`; claim ⇒ `task` + `last-event` + `resume`;
self-land handoff ⇒ `done` event ⇒ `finish` and the hook says `block:finish` with `hops`=1; `finish`
rc 0 ⇒ `finished` ⇒ `allow:finished`; a backlog task whose dep is done ⇒ `promote`, `--do` moves it
with the event and the board subject, a second `--do` ⇒ `nothing to promote`, an overlapping one is
held; an un-hopped fresh event ⇒ `block:build` then `allow:consumed`; release ⇒ `avoid`; hop cap ⇒
`stop` + `allow:cap`; foreign lock ⇒ `wait`; live foreign lease ⇒ `wait`, stale ⇒ `integrate`;
risk-high review alone ⇒ `finish` + the approve note; `handover: off` ⇒ `allow:off`;
`stop_hook_active` ⇒ `allow:harness-cap`; a newer `subagents/x.jsonl` ⇒ `allow:subagent`; `--brief`
≤8 lines with the markers and no `|`. Two goldens carry the cheap half on every `check`:
`handover-route` (the `triage-lane` fixture pattern: per board state line 1, the verb regex count,
the 3-space count; the `--do` state adds `ls ready`, the promote-event count and the board subject)
and `handover-stop` (a fixture state dir, `POLARIS_HANDOVER_NEXT` for the rail cases both ways, one
un-stubbed real-`next` case via `POLARIS_HANDOVER_CLI`, one raw JSON invocation pinning the shipped
block shape, `pinned-reason-lines: 1`). `cli-help-parity`'s alternation gains `next` (expected 10).
Spec: role-handover.md § executable check.

### Acceptance
- [ ] `drill_handover` asserts every item of role-handover.md § drill, in order, by rc and file state (never message presence alone); fixtures declare `risk:` explicitly; the sh forwarder to `$SELF` is planted as `ops/polaris` in the throwaway repo (the hook and `next` need a CLI at `<primary>/ops/polaris`, or `POLARIS_HANDOVER_CLI=$SELF`); hermetic — `git status --porcelain` unchanged across it, green twice in a row, no daemon or job left behind
- [ ] `handover-route.{cmd,expected}` and `handover-stop.{cmd,expected}` as pinned; machine-specific bytes normalized; no kit version number; each < 10 s and byte-identical on a second run
- [ ] `cli-help-parity.cmd` alternation `…|finish|next)`, expected `10`; every other byte of the `.cmd` unchanged
- [ ] each new assertion watched RED once under a semantic sabotage in a throwaway kit copy (e.g. drop the `consumed` rung; swap rows 3/4 in `next_route`), then green on restore — read the sabotage diff
- [ ] `bash kit/ops/polaris doctor --selftest --only handover` green (foreground, ≥600000 ms timeout) once T-104's label has landed (before that, run the drill body directly from a scratch spine copy and say so in Notes); goldens proven from the worktree with the `.cmd`-body form; after landing, the integrator sabotages each golden red on the primary and restores green

## T-112 — "polaris next --brief — a session with no role must not be told to read ops/roles/none.md"
points 1 · risk normal · landed 568c4a0 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/handover.sh

### Why
`bash ops/polaris next --brief` is what a compacted chat runs to find out who it is. Its last line
points at the role file to re-read — `read ops/roles/BUILDER.md if this context lost it`. The role
name comes from the `role:` line, and when the session holds no task lock and no integration lease
that value is the literal word `none`. So the one command whose whole job is to re-orient a lost
session currently ends by telling it to read `ops/roles/none.md`, a file that does not exist. The
session is then either stuck or invents a role, which is the exact failure the anchor exists to
prevent.

T-109 built this straight from the contract, which said to take the name off the `role:` line. The
contract was wrong, not the build; `ops/contracts/role-handover.md` § v1.1 item 2 now pins the fix.

Change ONE line, the tail of `next_brief` — guard the pointer so it prints only when it names a real
file. Everything else about `--brief` is untouched: same markers, same order, still no `|`, still
≤8 lines. A `role: none` brief simply ends at its `next:` line.

```
  case "${line1%% *}" in
    resume|build)      rfile=BUILDER;;
    integrate|promote) rfile=INTEGRATOR;;
    *)                 rfile="$role";;
  esac
  [ "$rfile" = none ] || printf 'read ops/roles/%s.md if this context lost it\n' "$rfile"
```

No new function, no new heading: the file's EIGHT-function census and the api-kit rows T-101 wrote
stay exactly as they are. T-111 is independent of this task in both directions — its `--brief`
assertions run with a live lock, so they never see `role: none`.

### Acceptance
- [ ] `next --brief` with no lock and no lease prints `role: none` and NO `read ops/roles/…` line (verify 4)
- [ ] `next --brief` with a live lock on an active task still prints `read ops/roles/BUILDER.md if this context lost it`
- [ ] the pointer `printf` still exists exactly once in the file (verify 2) — guarded, not deleted
- [ ] the file still defines exactly 8 functions, names unchanged (verify 3)
- [ ] `bash -n` clean, bash 3.2 constructs only (verify 1)

## T-113 — "Drill upgrade is red — the migration fixture must finish like a session that walked away, not one still sitting in its worktree"
points 1 · risk normal · landed 90a6d40 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/selftest/remote.sh

### Why
`bash kit/ops/polaris doctor --selftest --only upgrade` is RED on `main` right now. I reproduced it
before filing this: it fails at `kit/ops/lib/selftest/remote.sh:240` with

```
UNINSTALL SUMMARY FAIL (pre-confirm must name the board-history branch)
⛔ selftest FAILED — do not trust this environment until fixed
```

**The drill is not wrong about uninstall — its fixture is just untidy.** This is the same interaction
that reddened `drill_qa`, and it is a deliberate wave-2 design change catching up with a wave-0
fixture:

1. `cmd_handoff` now beats its own worktree (`kit/ops/lib/builder.sh:213`, T-098) — on purpose, so
   `done` sees a LIVE own lane and WS1 designs own-worktree `done` out.
2. `wt_remove` returns 1 (LEFT) for a live worktree (`kit/ops/lib/workspace.sh`, T-099), so `cmd_done`
   keeps both the worktree and the branch and prints its kept-branch note.
3. `drill_upgrade`'s fixture claims `T-M`, hands off, merges and calls `done` — all inside seconds —
   so `.polaris/wt/T-M` is still checked out when the drill reaches `uninstall`.
4. `uninstall`'s pre-existing guard (`kit/ops/lib/admin.sh:707`) dies with
   `N POLARIS worktree(s) still checked out — run: ops/polaris sweep --fix` **before** printing the
   summary, so the summary never names `polaris/board` and line 240's grep fails.

Every one of those four steps is behaving as designed. The only thing that is unrealistic is the
fixture: a real builder's worktree goes quiet when the session walks away, and `sweep`/`done` reap it
once idle. The drill finishes in under 15 minutes, so its beat is always fresh and the worktree is
never idle.

**Fix direction — use the contract's own seam, nothing else.** `ops/contracts/worktree-liveness.md`
line 22 sanctions exactly this for drills: the beat file is
`$(git rev-parse --git-common-dir)/worktrees/<ID>/polaris-beat`, and *absent or unreadable → idle
(age 999999)*, with `echo 1 > <beat>` as the documented backdate. Immediately before the `done T-M`
at remote.sh:233, make `T-M`'s worktree look idle (remove the beat file, or backdate it), so `done`
takes the idle path, `wt_remove` actually removes the worktree, and the fixture is clean by the time
`uninstall` runs. The `grep -B4` verify pins the seam to within four lines above that `done` so it
cannot drift away from the call it exists to set up.

**Three things NOT to do** (each has its own verify guard):
- Do NOT weaken or skip `uninstall`'s "worktrees still checked out" die. It is a real safety check and
  it is doing its job here; the fixture is what is wrong.
- Do NOT remove worktrees by hand (`rm -rf`, `git worktree remove`). A worktree is removed only by
  `wt_remove`, only when idle — that rule is the contract's, and a drill that breaks it stops proving
  anything about the code that ships.
- Do NOT touch any file outside `files_owned`. `admin.sh`, `workspace.sh` and `builder.sh` are
  read-only context here.

**Then sweep the rest of the file for the same latent failure.** Any drill that claims, hands off and
finishes inside 15 minutes has a live worktree at `done` for the same reason. The claim→handoff→done
sites in this file are: `drill_remote` T-C (~:9-13, note it already expects a stray and runs
`sweep --fix` — check before changing it), `drill_notify` T-PU (~:37-46) and T-PF (~:53-64),
`drill_upgrade` T-M (~:211-233, the one that is red), `drill_pushdegrade` T-PD (~:320-329) and T-PD2
(~:335-346). Apply the same seam only where a live worktree actually changes the assertion — a drill
that is green today and does not assert anything about worktree count needs no edit, and churn in a
green drill is its own risk.

### Acceptance
- [ ] `bash kit/ops/polaris doctor --selftest --only upgrade` exits 0 (measured ~4m35s — see Notes)
- [ ] Sabotage check: restore the un-faked beat (drop the seam), re-run, and the drill goes RED again at `UNINSTALL SUMMARY FAIL` — then restore the fix
- [ ] The seam is the contract's (beat file removed or backdated); no worktree is deleted by hand (verify 6)
- [ ] `uninstall`'s "worktrees still checked out" die is untouched (verify 5)
- [ ] The seam sits within four lines above the `done T-M` call it sets up (verify 4)
- [ ] All six drills still present, `bash -n` clean (verify 1, 2)
- [ ] Every other claim→handoff→done site in `remote.sh` reviewed; any left unchanged, say why in one line in Notes

## T-114 — "wt_remove must never delete the worktree holding the running script or your cwd — beat age must not be able to override it"
points 2 · risk normal · landed 41ba554 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/workspace.sh

### Why
**This one deleted work.** On 2026-09-02 the T-104 lane's own self-land removed the worktree it was
running from; `$SELF` vanished mid-execution and the seal fan-out died, stranding six landed tasks in
`review/` with orphaned worktrees. It is the ARC-428 class this whole sprint exists to end, and it is
live in `main` right now.

The chain, all of it landed code, every step behaving as designed:

1. A builder runs `bash ops/polaris handoff` FROM its worktree, so `$SELF` is
   `.polaris/wt/<ID>/ops/polaris` — **the running script lives inside the worktree.**
2. `cmd_handoff` beats that worktree once (`kit/ops/lib/builder.sh:213`).
3. The landing tail is long: lease wait → `land` → `seal` → suite → fan-out. **Nothing re-beats
   during it.** T-104's tail ran well past `wt_live_minutes` (default 15).
4. The fan-out runs `( cd "$PRIMARY" && "$SELF" done "$tid" )` for every landed review task,
   including the lane's own id. `done <own-ID>` runs from the primary, so `wt_remove`'s existing
   `own` test (`case "$PWD" in */.polaris/wt/<ID>...`) does not fire.
5. `beat_live` says idle → `refuse=0` → `git worktree remove` → rc 0. The worktree, and the script
   executing out of it, are gone. Every remaining `done` in the loop then fails.

The contract's § decision table literally asserted this could not happen — "the handoff just beat, so
`done` on the builder's own worktree hits clean+LIVE ⇒ LEFT … Nothing ever removes the worktree a
session is standing in." That reasoning is only true while the beat stays fresh, and the tail outlives
it. `ops/contracts/worktree-liveness.md` § v1.2 now pins the correction; build to it.

**The change.** In `wt_remove`, add a refusal evaluated **BEFORE** the liveness/dirty decision — before
`beat_age`/`beat_live` are consulted at all, so no beat age, no caller and no `--fix` can override it.
Hard refusal: **LEFT, rc 1**, nothing touched, for every caller (`done`, `release`, `sweep`) and every
cell of the decision table. Two conditions, either one refuses:

1. `$SELF` — the running script, resolved to an absolute real path — is inside the target worktree.
2. `$PWD` is the target worktree or inside it.

Resolve both sides to absolute paths and normalize separators before comparing: on Windows the
worktree path can arrive with mixed `\` and `/`. `next_route` in `kit/ops/lib/handover.sh` already
does this for bg-job cwds (`tr 'A-Z\' 'a-z/'`) — copy that shape rather than inventing one.

Pinned notes, byte-exact (the `worktree LEFT: ` prefix is unchanged so existing drill greps still
match; the `$SELF` note wins when both conditions hold):

```
worktree LEFT: .polaris/wt/<ID> holds the running script — never remove the ground you are standing on; a later sweep --fix finishes it once the session is gone
worktree LEFT: .polaris/wt/<ID> is your current directory — cd out and run: bash ops/polaris sweep --fix
```

**Inline the guard — NO new top-level function.** `workspace.sh` has exactly 14 top-level functions
and the api-kit golden pins every name; adding one reds a golden this task does not own. (Same call
the shared-checkout v1.1 amendment made for the mutex owner guard.)

This is one of two guards. T-115 stops the observed trigger by making the fan-out skip its own task;
this task makes the whole class impossible — a hand-run `done`, a `sweep --fix` from inside a
worktree, any future caller. Both are required before T-108 ships 6.2.0. They own different files and
can run in parallel.

### Acceptance
- [ ] **Regression proof, both directions.** A fixture worktree whose beat is deliberately backdated
- [ ] **Sabotage:** with the guard removed the same fixture DELETES the worktree and the assertion
- [ ] Standing inside the target worktree, `sweep --fix` refuses with the `is your current directory` note
- [ ] The guard runs before any beat/liveness call (verify 4)
- [ ] A worktree that holds neither `$SELF` nor `$PWD` behaves EXACTLY as the v1 decision table says —
- [ ] No new top-level function; `bash -n` clean (verify 5, 1)

## T-115 — "The seal fan-out must skip its own task — a lane never runs done on the task it is landing"
points 1 · risk normal · landed f38871a (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/builder.sh

### Why
`self_land`'s post-seal fan-out finishes every landed task in `review/`:

```
  for f in "$BOARD/review/"*.md; do
    ...
    ( cd "$PRIMARY" && "$SELF" done "$tid" ) \
      || note "⚠ done $tid failed — finish it by hand: bash ops/polaris done $tid"
  done
```

That loop includes **the lane's own `$id`**. Running `done` on your own task from the primary is
exactly the case the plan says is "designed out" — and the loop is where it was supposed to be
designed out, but never was.

It bit on 2026-09-02: T-104's lane self-landed, the landing tail (lease wait → `land` → `seal` →
suite → fan-out) outran `wt_live_minutes`, so by the time the loop reached T-104's own id the beat was
stale, `wt_remove` returned 0, and `done` deleted the worktree that `$SELF` was executing from. The
script vanished mid-loop and every remaining `done` failed — six landed tasks left stranded in
`review/` with orphaned worktrees.

**The change, and nothing else:** skip `$tid` when it equals the lane's own `$id`, and leave that one
`done` to the next `sweep --fix` or the next session. Emit this note once, after the loop, only when
the own id was actually skipped — byte-exact:

```
<ID> stays in review/ — a lane never runs done on its own task; the next sweep --fix or session finishes it
```

Everything else in `self_land` stays byte-identical: same ordering, same rc semantics, same hard stops
(`risk: high` and any `approved:` entry still never self-land), same `queued:`/rc 3 path, same
`⚠ done <tid> failed` fallback for every OTHER task. No new function — `builder.sh` has exactly 13
top-level functions and the api-kit golden pins the names.

This is one of two guards pinned by `ops/contracts/worktree-liveness.md` § v1.2. This one removes the
observed trigger; T-114 (`kit/ops/lib/workspace.sh`) makes the class impossible by refusing in
`wt_remove` itself. Both are required before T-108 ships 6.2.0. Different files — they can run in
parallel, and neither depends on the other.

### Acceptance
- [ ] After a successful seal, the fan-out runs `done` for every landed `review/` task EXCEPT the
- [ ] The skip note is emitted exactly once, and only when the own id was in the landed set
- [ ] Every other landed task still gets its `done`, and a failing one still prints the existing
- [ ] A lane whose own task is NOT in the landed set (refused `risk: high`, nothing to skip) prints no
- [ ] `bash -n` clean, function count unchanged, `self_land` still a single definition (verify 1, 4, 5)

## T-116 — "SOURCE.md's vendoring provenance line false-matches the version sweep regex"
points 1 · risk normal · landed 817243f (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/.claude/skills/i-have-adhd/SOURCE.md

### Why
CI's "one version, everywhere" job (`.github/workflows/ci.yml`, job `consistency`) sweeps
`README.md`, `kit/.claude/skills/` and `kit/ops/*.md` for any literal `POLARIS <x.y.z>` and reds if
it finds one that isn't the current `kit/ops/VERSION` (6.2.0). `kit/.claude/skills/i-have-adhd/SOURCE.md`
line 12 reads:

    | vendored | 2026-07-26, for POLARIS 5.23.0 |

That's a provenance record of when the vendored upstream skill was copied in — genuinely true at the
time, and it will never stop matching the regex, so the job has been red since 5.24.0 (this predates
today's 6.2.0 release and isn't caused by it). The fix is NOT to bump the number — that would state a
falsehood (it wasn't vendored at 6.2.0) and would need re-bumping every release forever. Instead reword
the line so it keeps the same meaning and the same date but no longer matches `POLARIS <x.y.z>`:

    | vendored | 2026-07-26, at kit 5.23.0 |

Only that one line changes. Everything else in SOURCE.md (upstream URL, author, licence, the "Why it
ships" prose) and the table shape stay untouched. `SKILL.md` and `LICENSE` are not touched — this
directory is a byte-for-byte vendored copy of upstream and `ops/tests/adhd-skill-installed` pins that
it shipped, kept its licence/attribution, and kept its opt-in frontmatter flag.

### Acceptance
- [ ] `kit/.claude/skills/i-have-adhd/SOURCE.md` line 12 no longer matches `POLARIS [0-9]+\.[0-9]+\.[0-9]+`
- [ ] the CI sweep command, run locally, returns an empty `bad` set at `ver=6.2.0`
- [ ] `ops/tests/adhd-skill-installed` golden stays green (SKILL.md/LICENSE untouched, opt-in flag intact)

## T-117 — "--no-permissions still armed the keep-awake hooks — one call sat outside the gate"
points 1 · risk normal · landed 6ee28f5 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: CHANGELOG.md, kit/ops/VERSION, kit/ops/bootstrap.py

### Why
`python polaris-v5.zip --claude-skill --no-permissions` writes the four keep-awake hook entries into
`~/.claude/settings.json` even though the whole promise of that flag is "I will not touch your
settings file". CI caught it on ubuntu, macOS and Windows with the assertion
`--no-permissions wrote to settings.json anyway`, and the release workflow's smoke step went down
with it — so v6.2.0 was tagged but never published, and there is no artifact for it.

The cause is a one-line placement mistake in `kit/ops/bootstrap.py::arm_machine`. Item (4) of the
four things that arm a machine, `merge_awake_hooks(archive, find_bash())`, sits ABOVE the
`if permissions:` block instead of inside it. Both it and `merge_permissions` write to the same
file — `merge_awake_hooks` registers SessionStart/UserPromptSubmit/Stop/SessionEnd via
`awake-hook.sh install` — so both belong behind the same gate. Move the call inside, keep the
comment above it accurate (its point still stands: the two hook files are rewritten on every
install, so folding them into `changed` would make the one-off "machine armed" line nag forever),
and add the reason the gate is shared. `--no-machine-setup` is a different, wider opt-out and keeps
working exactly as it does: `arm_machine` is not called at all, so nothing outside the repo is
written.

Then ship it: `kit/ops/VERSION` to 6.2.1 and a CHANGELOG entry above the existing 6.2.0 one. The
6.2.0 entry stays untouched — it is the real content release; this is only the fix that lets it
reach anybody.

### Acceptance
- [ ] `--claude-skill --no-permissions` against a fixture HOME leaves `~/.claude/settings.json` byte-identical
- [ ] the same run still caches the kit and installs the skill (the flag opts out of settings, not of arming)
- [ ] moving the call back outside the gate makes the CI assertion fire again
- [ ] `kit/ops/VERSION` says 6.2.1 and the newest CHANGELOG heading is 6.2.1
- [ ] `bash kit/ops/selftest-install.sh` green and the archive-integrity check passes on the rebuilt zip

## T-118 — "The seal fan-out runs its OWN done LAST, never skips it — landing: self must reach done/"
points 1 · risk normal · landed e2cdb59 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/builder.sh, ops/contracts/worktree-liveness.md

### Why
Two things that shipped in the same release disagree, and the disagreement fails
`doctor --selftest` deterministically:

```
HANDOVER SELFLAND FAIL (landing: self must carry the task to done/)
```

`kit/ops/lib/builder.sh` (worktree-liveness v1.2 "Guard 2", T-115) makes the post-seal fan-out SKIP
`done` for the lane's own task and print that the task stays in `review/`. `kit/ops/lib/selftest/board.sh:260`
(drill `handover`, T-111) asserts that the self-landed task reaches `ops/board/done/`. One of them
has to give.

**The drill is right, and the skip is now an over-correction.** Guard 2 was written when nothing
protected the running script: the fan-out ran `done <own-ID>`, `wt_remove` deleted the worktree the
script was executing from, and every later `done` in the loop died — that is how six tasks were
stranded earlier in this sprint. T-114 then landed the real protection in `wt_remove`: it refuses,
LEFT with rc 1, whenever the target worktree holds the running script (`$SELF`) or the caller's
`$PWD`, and that guard is evaluated BEFORE beat age, so nothing can override it.

With Guard 1 in place, `done <own-ID>` is safe: the worktree is LEFT, the branch is kept (`cmd_done`
deletes the branch only on `wt_remove` rc 0 or 2), the board still moves to `done/`, and the script
survives to finish the loop. The leftover worktree is reaped later by `sweep --fix` once it goes idle.
Skipping instead breaks the promise of `landing: self` — that one command carries a task from claim
to done — and leaves a task stranded in `review/` after every solo run, which is the exact mess this
sprint exists to end.

So the fan-out stops skipping. It runs every landed task's `done`, with the lane's OWN id LAST, so
that a failure there cannot strand the siblings behind it in the loop. The two fixes forbidden in
T-115 stay forbidden: the loop must NOT be made to tolerate a vanished `$SELF`, and nothing re-beats
to survive the landing tail. Guard 1 is the protection; own-last is only ordering.

### Acceptance
- [x] `self_land`'s post-seal fan-out no longer `continue`s past the lane's own id; it defers that
- [x] The "stays in review/ — a lane never runs done on its own task" note is gone.
- [x] The deferred call carries a comment naming T-114's Guard 1 in `wt_remove` as the reason
- [x] No new top-level function in `builder.sh` (the api-kit census stays at 13).
- [x] `ops/contracts/worktree-liveness.md` gains an append-only `## v1.3` section recording that
- [x] `bash kit/ops/polaris doctor --selftest --only handover,selfland,wtreap` is green.
- [x] Sabotaged both ways: restore the skip → the drill reds; restore the fix → green.

## T-119 — "The handover drill puts CONVENTIONS.md back instead of deleting it — hermetic teardown after the self-land"
points 1 · risk normal · landed 5d667b2 (2026-09-02) · claimed 2026-09-02 → done 2026-09-02
files touched: kit/ops/lib/selftest/board.sh

### Why
The full check suite is failing. The handover drill borrows the project's settings file while it
works, and when it finishes it throws that file away instead of putting the original back. On its
own the drill never noticed, because in a small run there was no settings file to begin with. In the
full run there is one, so the drill ends by leaving the project short a file it started with — and
the drill's own last question, "did I leave everything exactly as I found it?", correctly answers no
and stops the whole suite.

The fix is the one every neighbouring drill already uses: take a copy of the settings file before
touching it, and put that copy back at the end. Nothing about what the drill checks changes, and the
"leave no trace" question it asks itself at the end is left exactly as strict as it is today.

### Acceptance
- [ ] the drill saves ops/CONVENTIONS.md before it overwrites it, and restores it byte-for-byte at teardown
- [ ] a run with no settings file present still ends with no settings file present
- [ ] the "leave no trace" assertion at the end of the drill is unchanged
- [ ] the drill adds no new shell function (the kit's public-surface golden stays green)
- [ ] `bash ops/polaris doctor --selftest --only handover` is green twice in a row
- [ ] the full `bash ops/polaris doctor --selftest` is green

## T-120 — The house-style sample must still speak when the sample is empty — macOS CI has been red since 5.19.0
points 1 · risk normal · landed c13b69c (2026-09-02) · claimed 2026-09-02
files touched: kit/ops/lib/knowledge.sh

### Why
The macOS side of CI has been failing for weeks and nobody could see why, because the job log is
only reachable to someone signed in. It fails seven seconds in, always at the same place: the step
that runs the full mechanics drill.

The drill that dies is the one that checks the repo's "house style" summary — the little table that
tells the next session whether this codebase indents with tabs or spaces, prefers single or double
quotes, and how long its longest line is. That table is produced by sampling the repo's own source
files and counting. In the drill's throwaway repo there is no application code at all, so the sample
is legitimately empty — and the summary is supposed to say exactly that, in a row that reads
"not detected".

On Linux and on Windows it does. On macOS it prints nothing at all, so the row is missing and the
drill correctly reports that the house-style table came out blank.

The reason is a one-word difference between two versions of the same standard tool. The list of
files to sample is handed to the counter through `xargs`. When the list is empty, the GNU version
still runs the counter once — which is how the "not detected" row gets written. The BSD version
that macOS ships does not run it at all, so nothing is written. The counter's own
"nothing was sampled, say so" branch never gets a chance to run.

The fix is one line: always hand the counter at least one file to open — the system's empty file —
so it runs on every platform and the summary always speaks. An empty file contributes nothing to
any count, so on Linux and Windows every number stays exactly what it was.

### Acceptance
- [ ] `brain_prefs` hands its counter a `/dev/null` sentinel, so the counter runs even when the
- [ ] With a BSD-`xargs` stand-in on PATH (one that skips the utility on empty input, as macOS
- [ ] With the normal GNU tools, the same drill stays green and the counted rows are unchanged for
- [ ] `bash -n kit/ops/lib/knowledge.sh` is clean; no other file changes.
