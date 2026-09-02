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
points 5 · risk normal · landed 5053399 (2026-09-02) · claimed 2026-09-02
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
points 2 · risk normal · landed 2efabcc (2026-09-02) · claimed 2026-09-02
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
points 5 · risk normal · landed 93cd6e4 (2026-09-02) · claimed 2026-09-02
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
points 5 · risk normal · landed 02a941e (2026-09-02) · claimed 2026-09-02
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
points 3 · risk normal · landed fb5bf3c (2026-09-02) · claimed 2026-09-02
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

## T-109 — "lib/handover.sh — polaris next: the seven-verb router off the board, --do promotes under the lock, --brief re-anchors a compacted chat"
points 5 · risk normal · landed 0c1c6fe (2026-09-02) · claimed 2026-09-02
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
points 3 · risk normal · landed 74effdb (2026-09-02) · claimed 2026-09-02
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
