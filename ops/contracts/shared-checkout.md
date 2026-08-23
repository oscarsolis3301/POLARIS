# CONTRACT: shared-checkout            (v1 — 2026-08-03)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
N chats share ONE repo without ever asking the human a git/workspace question. Today the second
session dies on someone else's dirt, a stray `feat` ref, a busy integration branch, or a failed
push. This contract defines `kit/ops/lib/workspace.sh` (T-057) and how claim/handoff (T-059), the
integration lane (T-058), finish/status/doctor/update (T-060) and the drills (T-062) consume it.
Design decision (settled): integration is a SINGLE shared lane serialized by a lease — never
per-run integrate branches. `files_owned` are disjoint, so ANY integrator can land ANY review task;
whoever holds the lane lands everything, a second session waits briefly or queues. The linear
one-PR history model is unchanged.

## Interface — lib/workspace.sh (all fns top-level, bash 3.2-safe)
```
id_ok <ID>                rc 0 = usable. rc 1 + one ⛔ line when "feat/<ID>" fails
                          `git check-ref-format refs/heads/feat/<ID>` (or ID is empty/`feat`).
                          Callers: cmd_claim BEFORE lock_take; wt_add.
wt_add <ID>               shared worktree-add for claim/resume: create .polaris/wt/<ID> on
                          feat/<ID> (existing branch reused, else -b from $BASE). CAPTURES stderr
                          to a temp file — never 2>/dev/null. Retries (7 × 0.3s) ONLY when stderr
                          mentions index.lock; a stray ref literally named `feat` → one
                          stray_feat_repair attempt, then one more try; anything else dies
                          honestly, re-emitting the captured stderr. Prints nothing on success.
stray_feat_repair         a ref literally named `feat` is ownerless junk that shadows the feat/<ID>
                          namespace. Rename (archive, NEVER delete): local branch feat →
                          stray/feat-<sha7>; origin's feat → push it to stray/feat-<sha7> then
                          delete origin's feat. <sha7> = the ref's own short sha. Silent no-op
                          when no such ref exists. One `note` per repair.
int_on [<why>]            take the integration lease $LOCKS/.int-lease (board-mutex pattern:
                          atomic mkdir + epoch + who files). Busy → poll every 2s, a progress
                          note ~every 30s naming holder + age; holder epoch older than
                          integration_stale_minutes → steal with a note. After
                          integration_wait_minutes of waiting → print ONE final line beginning
                          `queued: ` + return/exit rc 3 — NEVER a question, NEVER a raw die.
                          Re-entrant: already ours (same pid file) → rc 0.
int_off                   release the lease if ours; silent no-op otherwise.
wave_on                   ensure + check out today's integrate/<date> (caller holds the lease):
                          absent → create from $BASE · present and fast-forwardable to $BASE →
                          ff + reuse · present with unsealed lands (NOT ff-able) → ADOPT it as-is
                          and keep landing on top (the "finish that wave by hand first" die is
                          deleted). Prints which of the three it did.
park [<why>]              `git stash push --include-untracked -m polaris/park-<epoch>` in the
                          primary. Success → say line containing `parked as polaris/park-` + the
                          name; rc 1 when the stash itself fails (caller falls back to today's
                          dirty-tree die, tree untouched). Nothing to park → note, rc 0.
unpark                    pop the NEWEST polaris/park-* stash (say what was restored); none →
                          note `nothing parked`, rc 0. Reversible in one command by design.
cmd_park / cmd_unpark     CLI wrappers dispatched by kit/ops/polaris (`polaris park [-m why]` ·
                          `polaris unpark`), documented in usage().
```

## CONVENTIONS knobs (unset = default; doctor validates when set — positive integers)
```
integration_wait_minutes: 10     # bounded wait for the lease before rc 3 `queued:`
integration_stale_minutes: 45    # lease older than this = abandoned → steal with a note
```

## rc table + machine-readable lines (drills grep these EXACT fragments)
- rc 0 = success — including idempotent skips: an already-landed `land <ID>` prints a line
  containing `already landed — skipped`; a seal with only board noise prints a line containing
  `nothing new to seal` (both rc 0, board untouched).
- rc 1 = refusal/error, message stays honest (real stderr re-emitted, never swallowed).
- rc 3 = queued: the lane stayed busy past the bounded wait. LAST line begins `queued: ` and names
  holder + what to do (re-run when the lane frees; a conductor polls at wave boundaries).

## Consumers — exact semantics per call site
- **cmd_claim (T-059):** `id_ok` runs BEFORE lock_take. NEW claim-time disjointness gate: the
  locked candidate's `files_owned` vs EVERY `active/` task via `pat_overlap` (both directions).
  Overlap + auto-pick → move candidate to `blocked/` with a ⛔ note naming the active task + both
  patterns + remedy (`re-groom or wait for <ID>`), ONE board commit `chore(board): block <ID>
  (ownership overlap)`, release its lock, claim the NEXT candidate. Overlap + explicit ID → die
  naming the same. Kills the multi-planner overlap race at its last gate. `wt_add` replaces the
  inline retry loop (builder.sh:62-71).
- **cmd_handoff (T-059):** push gets 3 attempts (0.5s apart) + ONE stray_feat_repair between
  attempts when stderr implicates a stray `feat`. Still failing → PROCEED with the board move
  (direct-mode landing merges the LOCAL branch; the work is safe), append a task Note
  `- ⚠ push failed at handoff — feat/<ID> is local-only; land merges the local branch`, emit
  `evt push-fail`, and say so. A finished task is NEVER stranded in active/ by the network.
- **cmd_resume (T-059):** worktree recreation goes through `wt_add`.
- **cmd_land · cmd_land_express · cmd_seal · seal_sync · cmd_rollback (T-058):** each takes the
  lease first (`int_on`; rc 3 propagates to the caller's exit). Their dirty-tree dies
  (integrate.sh:226/296/366/481/572) become: `park` + a caveat note (`parked your dirt as
  polaris/park-<epoch> — bash ops/polaris unpark returns it`) + PROCEED; `park` rc 1 → today's
  die verbatim, tree untouched. `cmd_land` on $BASE → `wave_on` instead of the :225 die;
  express's hand-rolled branch block (:298-305) → `wave_on`. `int_off` on every exit path that
  ends the lane's work (success or die — see lock ordering).
- **cmd_update (T-060, admin.sh):** the configured-repo dirty die (:359) becomes park + caveat +
  proceed (park failure → today's die). The never-configured branch (:350-358) is UNCHANGED.
- **cmd_finish (T-060):** the dirty-tree pending line names the remedy (`… or park it: bash
  ops/polaris park`); NEW pending line when the integration lease is held by another live session
  (named holder + age); parked `polaris/park-*` stashes → a caveat line each (never a gate).
- **cmd_status (T-060):** one line for the lease when held (holder · age) + one line per parked
  stash — a second chat's FIRST read explains the world.
- **cmd_doctor (T-060):** validates the two knobs when set (positive integers; else one ⚠ line);
  warns once when git < 2.13 (`stash push` needs it).
- **on_die (T-057, core.sh):** gains lease cleanup — when the process holds the lease (a global
  `INT_HELD` flag set by int_on, `${INT_HELD:-}`-guarded so the 2-module guard path never
  notices), on_die releases it. A crashed integrator must not cost 45 minutes of staleness.

## Lock ordering — the deadlock rule
The integration lease is OUTERMOST. Take `int_on` BEFORE any `mutex_on`; NEVER call `int_on`
while holding the board mutex; the board mutex stays what it is — a short-lived guard around
single board mutations. Kickback/done inside a landing session nest normally (lease held, board
mutex briefly). `int_off` runs after the last board mutation of the landing pass.

## Pinned phrasing (T-063 docs + kit/CLAUDE.md; each ON ONE LINE, NEVER HARD-WRAPPED — greps in
verify: for EVERY file that carries it)
- `git/workspace mechanics are never ask material after plan approval — the CLI prints the next step; follow it`
- `claim says taken → claim the next task; the lock already chose for you`
- `integration lane busy → wait; rc 3 with a queued: line means report queued and retry at the next wave boundary`
- `a dirty shared checkout is parked, never asked about: bash ops/polaris park`
- `another session's locks, leases and tasks are invisible — never steal unless sweep flags them STALE`

## Executable check (T-062 — four new drills; labels registered in spine.sh SELFTEST_LABELS)
- `park`: park a dirty tree (tracked + untracked) → clean; unpark → byte-identical restore; a
  dirty tree at `land` parks + proceeds + prints `parked as polaris/park-`.
- `claimguard`: claim with an invalid ID dies via id_ok pre-lock; a planted ref named `feat`
  (local + scratch origin) is renamed `stray/feat-<sha7>` and claim succeeds; two tasks with
  overlapping files_owned → the second auto-moves to blocked/ with the remedy note.
- `busyint`: a held lease → land waits with notes, then rc 3 + `queued: `; a stale lease (epoch
  aged past the knob) is stolen with a note; re-land of a landed ID → `already landed — skipped`
  rc 0; an open non-ff integrate/<date> is ADOPTED (no die), sealed once.
- `pushdegrade`: a planted `feat` ref on the scratch origin breaks the first push → handoff
  retries, repairs, and even with push forced dead the board move happens + the task Note + the
  `push-fail` event exist.
Each drill leaves the throwaway repo assertions-clean (T-046 hermeticity discipline).

## Invariants
- Every gate stays: audit, RULES, green-before-review, risk:high human approval, seal
  preconditions. This contract reroutes MECHANICS (waits, parks, retries, renames); it weakens no
  check and auto-answers no judgment call. Spec ambiguity, `risk: high` and `ask`-rule scopes
  still stop for the human.
- Archive, never delete: stray refs are renamed, dirt is stashed by name, stale leases are stolen
  with a note. No force-push anywhere (the sprint-tag CAS lease stays the one exception, as today).
- Single-session behavior with knobs unset is unchanged except: honest errors instead of
  swallowed ones, parks instead of dies, skips instead of dies on idempotent re-runs.
- bash >= 3.2: no `case` inside `$(...)`, split `local` declarations, POSIX awk. No new deps.
- Windows/Git Bash: never assert on `\r`-sensitive output via grep/sed in drills — use awk/od
  (T-056 lesson); new goldens are auto-LF-pinned.

## Example
Session B lands while session A integrates: B's `land T-070` → `int_on` polls 2s with notes →
A seals + `int_off` → B's `int_on` acquires, `wave_on` says `adopted integrate/2026-08-03
(1 unsealed land)` → B lands, seals; B's re-run of `land T-069` (A already landed it) prints
`✅ T-069 already landed — skipped` rc 0. A third session past the wait: `queued: integration
lane busy (held by oscar@host, 4m) — re-run when free; conductors poll at the next wave boundary`
rc 3.

## v1.1 — the board mutex learns ownership (2026-08-03, T-064)

Found by the integrator's audit of T-058 (pre-existing in main, made hittable by this sprint):
`mutex_off` is an unconditional `rm -rf "$MUTEX"` and `mutex_on` records no owner, while `on_die`'s
EXIT trap is never disarmed — and v1 arms that trap for the WHOLE int_on lease lifetime, so any
process exit could delete a board mutex another session legitimately holds. The lease already got
this right (pid file, pid-guarded release); the board mutex now mirrors it:
- `mutex_on` writes `$MUTEX/pid` (the acquiring process) beside `epoch`.
- `mutex_off` is a NO-OP unless `$MUTEX/pid` exists and matches the calling process — a foreign,
  missing or unreadable pid leaves the mutex in place. Removing one's OWN mutex stays exactly today.
- The waiter-side staleness steal in `mutex_on` (epoch age > 120s → remove + retake) is UNCHANGED
  and deliberately pid-blind: it is the crashed-holder recovery path.
- `on_die` still calls `mutex_off` (and lease cleanup per v1) — both now ownership-guarded, so an
  arbitrary exit can no longer eat another session's locks.
- Inline the guard: NO new top-level function (the kit surface is frozen until T-062's golden delta).

## v2 — enforced isolation (2026-08-23, plan enforced-isolation, T-084..T-090)

v1 built the machinery (worktree per task, disjoint files_owned, claim lock, single lease); v2
makes it ENFORCED. Verified holes: nothing puts a session into its worktree (claim only prints a
cd), the ownership hook keys off the current dir's branch so the primary on `main` has no gate at
all, nothing refuses checkout-mutating git in the primary, the claim gate sweeps only `active/`,
and the board sits in `review/` forever when no integrator exists. Five live sessions collided on
exactly these. Additive: every v1 interface above is unchanged.

### 1. `kit/ops/hooks/checkout-guard.sh` — NEW PreToolUse hook (T-084)
Pure bash, NO fork to `ops/polaris`, no interpreter — the readonly-allow timeout lesson (a slow
hook is killed and FAILS OPEN) sizes the budget. Copies v1's `jstr` payload reader. Registered in
`kit/.claude/settings.json` alongside ownership-guard (matcher `Bash`); `kit/ops/install.sh`
settings merge picks it up by path identity (no merge-code change) but the chmod line at
install.sh:106 gains the new path. NOT an extension of readonly-allow.sh — that hook's safety
contract is "only ever ALLOWS"; deny lives in its own file.
- **Deny** when CWD is the PRIMARY worktree (resolve: `git rev-parse --git-common-dir` vs
  `--git-dir` equal means primary; a `.polaris/wt/` path segment means worktree) AND the Bash
  command contains a checkout-mutating git invocation: `git switch` · `git checkout` (all forms) ·
  `git reset` · `git stash` (incl. pop/apply — but `git stash list` and `git stash show`, the
  only read-only stash forms, stay ALLOWED: readonly-allow's `git_ok` already allows both, and
  denying them would break the allow/deny disjointness the two-hook design rests on; T-084
  default-safe assumption, ratified) · `git merge` · `git rebase` · `git cherry-pick` ·
  `git worktree add` · `git branch -D|-d|-m|-M`. Read-only git and everything non-git pass through
  untouched (exit 0, no output). Inside `.polaris/wt/<ID>` ALL of these stay allowed.
- Deny mechanism: readonly-allow-style `hookSpecificOutput` JSON with
  `permissionDecision: deny` on STDOUT — this section's own pinned verify greps STDOUT for the
  refusal, so an exit-2+stderr deny could never satisfy it. NOTE (T-084 finding): the two hooks
  legitimately deny by DIFFERENT mechanisms — ownership-guard denies via exit 2 + stderr,
  checkout-guard via JSON-on-stdout. Both are correct as shipped; do not "fix" either to match
  the other. Refusal text pinned ON ONE LINE, greppable:
- `the primary checkout is shared by every session — never switch it: work in your task's worktree (bash ops/polaris claim, then cd .polaris/wt/<ID>); a dirty tree is parked (bash ops/polaris park), never switched around`
- Top-level fns EXACTLY (api-kit pins, sorted): `deny` · `jstr` · `mutating_git`. No others.

### 2. ownership-guard learns the primary (T-085)
New top-level fn `primary_gate`, called before the existing branch-keyed path. When (a) CWD is the
primary worktree, (b) HEAD is not `feat/*`, and (c) at least one task lock dir exists under
`$LOCKS` (`<git-common-dir>/polaris-locks/*/`, ignoring `.int-lease` and the board mutex), DENY
writes to tracked source paths. Allowlist (primary-role surfaces, checked first): `ops/board/` ·
`ops/contracts/` · `ops/*.md` (top-level ops docs: SPRINT/MAP/CONVENTIONS…) · `.polaris/` ·
untracked scratch. The lock-existence test keeps INIT and a lone PLANNER on an empty board
ungated — accepted trade, recorded here. Refusal pinned ON ONE LINE:
- `builders never edit the shared primary — claim a task and work in its worktree: bash ops/polaris claim, then cd .polaris/wt/<ID>`
- New top-level fns EXACTLY: `primary_gate`. (`cleanup`/`jstr`/`lc`/`norm` stay.)

### 3. Claim gate sweeps ready ∪ active; drift --strict fails on overlap (T-086)
- `cmd_claim` (builder.sh): the T-059 disjointness loop iterates `"$BOARD/active/"*.md` — it now
  ALSO iterates `"$BOARD/ready/"*.md` (skipping the candidate itself). Same `pat_overlap` both
  directions, same explicit-vs-auto behavior; the auto-pick blocked/ note and the explicit-die
  message gain the ready variant. Pinned fragment (explicit case): `overlaps ready` (mirror of the
  existing `overlaps active`).
- `cmd_drift` (observe.sh): `OWNERSHIP OVERLAP` findings become FAILING (nonzero exit) under
  `--strict`, like the ready-gate findings. Plain `drift` output unchanged.
- NO new top-level fns in either file. T-086 owns `ops/tests/api-kit.expected` for wave 1 and
  writes EXACTLY these additions (sorted into place), pinned here so it never needs the other
  lanes' diffs — the key-registry § 5 recipe, third use:
  - `kit/ops/hooks/checkout-guard.sh	fn	deny`
  - `kit/ops/hooks/checkout-guard.sh	fn	jstr`
  - `kit/ops/hooks/checkout-guard.sh	fn	mutating_git`
  - `kit/ops/hooks/ownership-guard.sh	fn	primary_gate`

### 4. Worktree entry is a numbered step (T-087)
TWO callers, two entries — pin BOTH, never one recipe (wave-1 field finding, T-085's builder:
a conductor-spawned subagent has its cwd PINNED at launch and EnterWorktree REFUSES there —
"the current working directory … is the repository root, not an isolated worktree" — while a
top-level session, the human's actual ~5-chat workflow, enters normally and needs no prompt).
Sharpened cause (T-084 wave): EnterWorktree only accepts paths under `.claude/worktrees/`, so
`.polaris/wt/<ID>` may be structurally outside what it accepts for ANY caller — T-087 MUST
re-verify the top-level entry LIVE before pinning it; if it refuses there too, the
absolute-paths/cd form becomes the sole pinned instruction for all callers, the EnterWorktree
mention is dropped from every kickoff, and the finding goes in the handoff report.
- `cmd_claim` closes with an INSTRUCTION, not an observation. Pinned (one line each):
  - `now enter the worktree — every command until handoff runs there`
  - `top-level session: EnterWorktree({path: ".polaris/wt/<ID>"}) · pinned-cwd subagent or any other CLI: run everything via absolute paths under .polaris/wt/<ID> (or cd there — the shell's cwd persists between calls)`
- `cmd_fleet` pane kickoffs are top-level panes: they carry the EnterWorktree line. The
  CONDUCTOR builder-kickoff template must NOT instruct EnterWorktree — it refuses every time for
  a subagent, and an instruction that always fails teaches builders to ignore the step, the exact
  failure mode this sprint removes. Its pinned line instead:
  - `you are a pinned-cwd subagent: work via absolute paths under .polaris/wt/<ID> (EnterWorktree will refuse) — never touch the primary checkout`
- `kit/ops/roles/BUILDER.md` step 1b / `SOLO.md`: entering the worktree is a numbered step
  carrying BOTH caller lines (a builder session may be either). No new fns; no new H2 headings
  anywhere (api-kit records headings).

### 5. `landing:` knob — a builder lands its own task (T-088)
- KEYS.tsv row: `landing` · since 6.1.0 · default `self` · values `self | integrator`.
  `update` never rewrites CONVENTIONS.md, so existing repos get the behavior by DEFAULT-IN-CODE
  (the 6.0.0 lesson): unset composes to `self`.
- Under `self`, `cmd_handoff` continues into `land <ID>` in the same session (new top-level fn
  `self_land` in builder.sh — the ONLY new fn this task adds; api-kit line
  `kit/ops/lib/builder.sh	fn	self_land`, and T-088 owns the golden for its wave). `int_on`
  already provides wait-your-turn: atomic lease, 2s poll, stale steal, `queued: ` + rc 3 past the
  wait — self_land inherits ALL of it unchanged. The all-review condition already computed at
  handoff also triggers `seal` (last lane out seals the wave).
- **Hard stops no knob softens** (refusal pinned ON ONE LINE): `risk: high` tasks and anything on
  the STOP-AND-ASK list NEVER self-land — handoff prints the classic integrate notice instead:
  - `risk: high never self-lands — a human must approve the merge; task stays in review/`
- Under `integrator` (and on any self-land refusal) behavior is byte-for-byte today's.
- Defaults re-sized for 5 lanes: `autolaunch_max` 3 → 5 (KEYS.tsv row + the `cfg autolaunch_max 3`
  fallback at observe.sh:1869 + CONDUCTOR.md "default 3"). **`integration_wait_minutes` STAYS 10**
  — human decision 2026-08-23, measured and load-bearing: `int_on` polls in the FOREGROUND
  (workspace.sh:105-125 sleep-2 loop), so a 10-minute bound is already EXACTLY the harness's 600s
  tool cap. At 20 a session that genuinely waits blows the cap — its tool call returns NOTHING and
  is re-run, so it loses the whole wait and learns nothing. A bigger number buys strictly less
  than the smaller one: NEVER raise this knob past 10, and KEYS.tsv's prose for the key carries
  this same 600s-cap warning (T-088). The long-wait fix is DETACHING, not a bigger bound: a
  self-landing session runs its landing tail under `bg run ship-<ID> -- …` and collects it with
  chunked `bg wait --max 300` (half the cap — why that default exists); the roles T-088 edits
  carry this recipe. Polling is not notification, so pipelined-integration.md's pinned foreground
  rule stays literally true. Suite economics unchanged: `land` is squash+audit (fast); the full
  suite stays per-wave (`integration: batch`).
- **Invariant 9 REWORDED** (human-approved VERBATIM, 2026-08-23; lives in `kit/CLAUDE.md`, which
  T-088 now owns — replace the existing invariant-9 line with exactly this, no new headings):
  > 9. **Only the integration-lease holder merges.** The lease *is* the Integrator — there is exactly one at any instant, and taking it is what makes a session one. `risk: high` NEVER merges without explicit human approval in the conversation.
  Rationale, recorded: this is what the code has always actually done — `wave_on`
  (workspace.sh:146-167) says outright that any integrator lands any task because `files_owned`
  are disjoint, so the lands compose; the words were narrower than the machinery. Self-landing
  needs no exception once the invariant names the lease.
- `kit/ops/PROTOCOL.md` § LANES documents self-landing as the SOLO / `land --express` precedent
  generalized — one session carrying one task to merged. Edit INSIDE the section; no new heading.

### 6. Executable check (T-089 — three drills + goldens; labels in spine.sh SELFTEST_LABELS)
- `checkoutguard` (drill_checkoutguard, policy.sh): pipe a PreToolUse payload with cwd=primary +
  `git switch x` → deny as `hookSpecificOutput` JSON on STDOUT carrying `the primary checkout
  is shared` (assert the shape, not just the string); same command with cwd=.polaris/wt/T-000 →
  exit 0, no deny; `git status` in primary → exit 0; `git stash list` and `git stash show` in
  the primary → exit 0, NO deny (the §1 carve-out — a golden asserting all stash forms deny
  would fail against correct behavior). Also primary_gate:
  primary + planted lock + non-feat HEAD + tracked source path → deny; an ops/board/ path →
  allow; no locks → allow. And the FALLBACK entry — the path every conductor lane actually
  takes: with cwd pinned at the primary, a write via an ABSOLUTE path under `.polaris/wt/<ID>`
  is allowed (the `.polaris/` allowlist) and the resulting commit lands on `feat/<ID>`.
- `readyoverlap` (drill_readyoverlap, board.sh): two ready tasks sharing a file → explicit
  `claim` of the second dies `overlaps ready`; auto-pick moves it to blocked/ with the remedy
  note; `drift --strict` exits nonzero naming OWNERSHIP OVERLAP; plain `drift` exits 0.
- `selfland` (drill_selfland, history.sh): landing unset (composes self) → handoff of a normal
  task lands it (task reaches done/, lease released); a `risk: high` task stays in review/ with
  the pinned refusal; `landing: integrator` → classic notice, no land.
- Golden pairs (polaris check --scaffold): `checkout-guard-denies` · `ownership-primary` grepping
  the pinned refusal lines out of the hook scripts themselves (hermetic — no live board).
- Budget: ~44s/drill + 144s spine; drills namespace ALL scratch under `scratchpad/<ID>/`.
- New fns are the three `drill_*` bodies; T-089 owns api-kit.expected for the final wave.

### v2 invariants
- Layer 1+2 are HOOKS: they gate the agent's Bash/Edit tools, never git run inside `ops/polaris`
  itself (`wave_on`, `park` keep working in the primary).
- **Entry is enforced by the GUARD, not by the entry tool.** EnterWorktree vs `cd` vs absolute
  paths is a convenience question; §2's `primary_gate` is what makes staying in the primary
  actually fail. If the harness's worktree tooling changes again, the layer still holds.
- Field note (T-084, deliberate and recorded): checkout-guard's `--git-common-dir` probe runs
  only when a deny is otherwise imminent and FAILS CLOSED — an unreadable or absent repo at cwd
  counts as primary (the `/tmp/fakerepo` verify case requires exactly this). A deliberate
  fail-closed choice in a file whose other paths all fail open; do not "normalize" it.
- Field note (T-084): `find --api` anchors to the PRIMARY's index by design (search.sh:13), so a
  worktree-run api-kit check reads green and CANNOT see a file added in that worktree. Golden
  deltas are proven via the index db / POLARIS_ROOT recipe, never by running api-kit from the
  worktree.
- Field note (wave 1, applies to §1 AND §2, additive — both hooks were claimed when learned):
  `git rev-parse --git-common-dir` prints a RELATIVE path from the primary and an absolute one
  only from a linked worktree, so `$LOCKS` and every path derived from it must be anchored to
  the payload cwd before any comparison — never to the hook process's own cwd. (T-085 landed
  this way, folding the second rev-parse into the first and dropping a ~460ms `git worktree
  list` — zero added forks is the budget to match.)
- Every v1 gate, pin and rc stays. `queued: `/rc 3, lease stealing, park semantics: unchanged.
- Only the deny messages above are new agent-facing strings; each lives ON ONE LINE.
- bash >= 3.2 everywhere; hooks stay fork-free pure bash.

## Changelog
- v2 2026-08-23: enforced isolation - checkout-guard hook, ownership-guard primary_gate, ready-union-active claim sweep, drift --strict fails overlap, landing: self knob + autolaunch_max 5, drills checkoutguard/readyoverlap/selfland (T-084..T-090, plan enforced-isolation).
- v2 amended pre-claim 2026-08-23 (T-088 unclaimed, so edited in place per the append-only rule): integration_wait_minutes REVERTED to 10 - the foreground int_on poll makes 10min exactly the harness 600s tool cap, so 20 loses the whole wait (detach with bg run ship-<ID> + chunked bg wait --max 300 instead); Invariant 9 reworded (human-approved verbatim: the lease holder IS the Integrator) - kit/CLAUDE.md joins T-088's files_owned. Wave-1 sections 1-4 and 6 byte-identical.
- v2 amended 2026-08-23 (T-087/T-089 unclaimed; claimed sections untouched, field notes additive): section 4 now pins TWO caller entries - EnterWorktree refuses in a pinned-cwd subagent (wave-1 finding, T-085's builder), so top-level sessions keep EnterWorktree while subagents get absolute-paths-as-primary and the CONDUCTOR kickoff never instructs EnterWorktree; checkoutguard drill gains the fallback-entry assertion; invariants gain entry-enforced-by-the-guard + the relative --git-common-dir anchoring note.
- v2 corrected 2026-08-23 post-T-084-handoff, pre-T-089 (recording shipped behavior before goldens bake in a wrong assumption): section 1's deny mechanism is hookSpecificOutput JSON on STDOUT (the ownership-guard comparison was self-contradictory - that hook denies via exit 2 + stderr; the two mechanisms legitimately differ); git stash list/show carved out of the deny list (read-only forms, allowed by git_ok - denying them breaks the two-hook disjointness); drill spec pins both + the fail-closed probe and primary-anchored find --api field notes; section 4 records the sharpened EnterWorktree cause (.claude/worktrees/ only) and requires live re-verification of the top-level entry.
- v1.1 2026-08-03: board mutex pid-guarded — mutex_on writes $MUTEX/pid, mutex_off no-ops on a
  foreign/missing pid; staleness steal + on_die wiring unchanged (T-064, integrator audit filing).
- v1 2026-08-03: created for T-057 (module + CLI + on_die), T-058 (integration lane), T-059
  (claim/handoff/resume), T-060 (finish/status/doctor/update), T-062 (drills), T-063 (docs
  pinned phrases). plan: n-chats-one-repo.
