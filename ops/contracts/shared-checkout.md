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

## Changelog
- v1 2026-08-03: created for T-057 (module + CLI + on_die), T-058 (integration lane), T-059
  (claim/handoff/resume), T-060 (finish/status/doctor/update), T-062 (drills), T-063 (docs
  pinned phrases). plan: n-chats-one-repo.
