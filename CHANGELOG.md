# Changelog

Versions here are the **kit version** (`kit/ops/VERSION`), not the board protocol version.
A bump in `version:` is what notifies every installed kit on its next daily check — routine
commits to `main` deliberately do not.

## 6.2.2 — 2026-09-02

**The first published 6.2 kit.** 6.2.0 and 6.2.1 were both tagged, but neither ever published —
each release run failed its smoke step, so no artifact exists for either one. The blocker was the
brain's house-style detection: it samples tracked source files and pipes them through `xargs` into
one `awk` pass, and on a repo with no application code that sample is empty. GNU `xargs` still runs
the utility once on empty input; BSD `xargs` (macOS) does not run it at all, so `awk` never
executed, `prefs.md` lost its `indent` row entirely, and the selftest drill asserting that row went
red — aborting the suite before the bash-3.2 step downstream ever got to run. That failure was not
introduced by this sprint: it has been in the code since 5.19.0 (2026-07-25) and had been failing
macOS CI, undetected, for six weeks. Fixed by handing `awk` one extra empty file argument so it
always runs regardless of what the sample contains. This tag carries all of 6.2.0's content.

## 6.2.1 — 2026-09-02

**The release below was tagged and never published — this is the fix that lets it out.**
`--claude-skill --no-permissions` armed the keep-awake hooks anyway: item (4) of `arm_machine`
sat outside the `permissions` gate, so the four hook entries landed in `~/.claude/settings.json`
under a flag whose entire promise is that the file is not touched. CI caught it on Linux, macOS
and Windows before any artifact shipped, but a second, unrelated release-blocking failure kept
this tag from publishing too — 6.2.2 is the first published 6.2 kit, and everything in the entry
below ships with it.

## 6.2.0 — 2026-09-02

**Five sessions on one machine, and any one of them could still delete another's work.**

The last release made isolation enforceable — guards on the shared checkout, a disjointness gate at
claim, a builder that lands its own work. What it never stopped was a session destroying the ground
another session was standing on. A sibling's seal fan-out ran `done`, which
`git worktree remove --force`d a worktree somebody was still typing in, and everything uncommitted
in it died. That is not a merge conflict, it is data loss, and nothing could see it coming because
"is anyone in there?" was a question the system never asked. 6.2.0 gives a worktree a pulse and
makes every remover read it, teaches the guard the five other verbs that destroy, and gives a
background job an owner. Then, with the machinery open, it closes the three things that still made a
run stop and wait for a person: the harness's own tools kept asking permission, the machine went to
sleep mid-run, and every change of role needed somebody to open a new chat. **BREAKING: none.**

| | before | after |
|---|---|---|
| removing a task worktree | `git worktree remove --force` — whatever was uncommitted in it is gone | `wt_remove` reads a beat file: live ⇒ LEFT with a note · dirty ⇒ archived to `.polaris/wt-archive/` · `--force` gone from lib code |
| `worktree remove` · `git clean` · `push --delete` · `rm -rf .polaris` · `pkill` / `taskkill /IM` | allowed, from anywhere | denied by `checkout-guard.sh`, each with one line naming the safe command instead |
| five sessions each running `bg run qa` | the same name silently rotated another session's live job, and `--force` killed by a reusable pid | a live job whose `cwd` is not yours is refused, `--force` included; old logs are archived, never deleted |
| `EnterWorktree`, `Task`, `TodoWrite` and four more under auto mode | a permission prompt, every session | pre-authorised by name in the kit's own settings; the two human gates stay prompts forever |
| the machine, mid-run | sleeps, and the run sleeps with it | ONE keep-awake owner per machine — awake while any session is busy, gone once all of them are idle |
| a change you can only judge by looking | "did anyone actually look?", answered by hope | a capture step in `pack`, a `handoff` that refuses without a fresh screenshot, and a `saw:` line in the report |
| the end of a task | the chat ends; a person opens a new one for the next role | `polaris next` reads the board and names the next role, and the same chat carries on into it |
| a plan you just got approved | a report, ending in "open a new chat and say start" | the kickoff — the approval is the go for the whole run, in this chat |

- **Nothing removes a worktree it cannot prove dead.** Every task worktree now carries a beat file in
  git's own per-worktree directory, touched by `claim`, `resume`, `verify` and `handoff`, by the CLI
  preamble on any command run from inside one, and by two hooks — so a session that is merely typing
  still counts as alive. One primitive, `wt_remove <ID> <caller>`, is the only thing in the kit that
  removes a worktree, and its answer is a table: clean and idle ⇒ removed · dirty ⇒ **archived** to
  `.polaris/wt-archive/<ID>-<epoch>` · live ⇒ **left alone**, with a note naming the next step.
  `--force` is gone from `kit/ops/lib/*.sh` for good, nothing in the kit ever deletes an archive, and
  `uninstall` refuses while one is non-empty. `resume` and `release` die on a live worktree with a
  one-line takeover recipe instead of guessing. A session's `done` on its own lane lands on
  clean-and-live and leaves it standing: **nothing removes the ground you are standing on**, and an
  idle `sweep --fix` finishes the cleanup later. The lease and the board mutex now check a pid before
  stealing, `sweep` reports whether the owning session is alive or gone, and a lock younger than two
  minutes with no task behind it is left alone — a claim may simply be mid-flight.
- **The guard learns the other five destroyers.** `checkout-guard.sh` gains one function and three
  pinned refusals. Removing, pruning or moving a worktree, a recursive `rm` or `Remove-Item` that
  touches `.polaris`, and every kill-by-name (`pkill`, `killall`, `taskkill /IM`,
  `Stop-Process -Name`, `kill -9 -1`, `npx kill-port`, `fuser -k`) are denied **everywhere** — there
  is no checkout where those are safe, including the worktree you are sitting in, whose removal would
  take the script that is running with it. `git clean` and a remote-branch delete are denied in the
  shared primary. Still allowed, deliberately: `kill <pid>`, `taskkill /PID`, `Stop-Process -Id`,
  `rm -rf node_modules`, `rm -f` a single file, `git clean -n`, `git push -u`. Deny stays narrow,
  silence stays the default, and the common path still forks nothing.
- **A background job belongs to the folder that started it.** The job's `cwd` is the ownership key: a
  live job of the same name started from somewhere else is refused, with or without `--force`, and
  the message names the fix (`bg run <name>-<ID>`). Rotating a job no longer deletes the previous
  run — the old directory moves into `.polaris/bg/.archive/<name>-<epoch>`, invisible to every
  reader, pruned by `sweep --fix` after a day. Job directories also record the session that started
  them.
- **Seven of the harness's own tools are pre-authorised.** `EnterWorktree`, `ExitWorktree`,
  `Workflow`, `Task`, `Agent`, `TodoWrite` and `SendMessage` ship as bare tool names in the kit's
  settings and in the machine-arming list, riding the set-if-absent merges that were already there —
  no code change, and they arrive on the next update. Entering your worktree stops being a prompt.
  `ExitPlanMode` and `AskUserQuestion` are deliberately **absent and stay that way**: a plan approval
  and a direct question are the two clicks POLARIS must never take for you. The read-allow hook is
  not widened — its contract is that it only ever allows.
- **One keep-awake daemon per machine.** Four machine-level hooks merge into `~/.claude/settings.json`
  and keep a small registry under `~/.claude/polaris/awake/`. While any session anywhere is busy — or
  any registered repo has a background job still running — the daemon resets the system idle timer
  every tick and, on an unlocked station where nobody has typed for a minute, taps F15 so the display
  stays up too. It never presses while a human is typing, never touches a locked screen, and exits by
  itself once every session and repo has gone quiet; a second one cannot start, and a dead one is
  taken over. `ops/polaris awake status|start|stop|disable|enable|install` drives it, `doctor` says
  when it is unarmed or disabled, and `awake stop` buys an hour of silence. There is no CONVENTIONS
  key for it on purpose — a repo setting cannot gate machine-level hooks. Lid-close, the power button
  and a critical battery stay out of reach of any user-mode program; `ops/PROTOCOL.md` says so
  plainly.
- **The capture step, for work you can only judge by looking.** Four new keys — `shot:` (how to take
  a screenshot), `visual:` (which paths are visual), `port_base:` (each task gets its own port, so
  parallel builders never fight over one dev server) and `serve:` (how to start this worktree's app)
  — turn "SEEING YOUR WORK", pasted by hand on every visual task, into part of the Builder contract.
  `pack` prints a SEE YOUR WORK section naming the exact commands and where the image goes;
  `handoff` refuses when a task changed a visual path and there is no capture newer than the branch
  base, while `verify` only warns; and the prose half stays human — the report carries a `saw:` line
  and the Integrator opens the picture. `ops/VISUAL.md` explains how a repo plugs in its own tool. A
  repo that sets no `visual:` key sees none of it.
- **`polaris next` — one chat, role after role.** A session used to end with its task, so every next
  role needed a human kickoff. `next` reads the board and answers in one verb — `resume`, `build`,
  `integrate`, `promote`, `wait`, `stop` or `finish` — with the reasoning underneath; `--do` promotes
  everything that passes the full ready gate under the board lock; `--brief` re-anchors a chat that
  lost its context. Three hooks carry it: a `Stop` hook that hands a finished session into the next
  role once per completion event (never a subagent, never a session that stopped to ask you
  something, never past the run's budget), a `SessionStart` hook that re-enters a compacted chat from
  the board, and a stamp on every prompt. Invariant 5 is reworded to match: one task and one role per
  **context**, hopping only at a boundary the board can prove. Compaction is the context reset; the
  anchor hook is the re-entry.
- **An approved plan is a kickoff, not a report.** New dispatch row: a plan you wrote and just got
  approved means you run it, in the same chat, starting now. Closing with "open a new chat and say
  start" is exactly the failure that row exists to end. The rule about ending on one concrete next
  step now says the rest out loud too — a step this chat could take itself, it takes before closing.
- **New defaults, arriving on `update` without touching a single repo's config.** `wt_live_minutes`
  defaults to 15 (how long after its last beat a worktree counts as live) and `handover` defaults to
  `auto` (a session hops into the role `next` names). Both live in kit code, by the pattern the
  autonomy release established, because `update` must never rewrite a repo's own CONVENTIONS.md. The
  opt-outs are one line each: `handover: off` restores one task per session, `wt_live_minutes: 0`
  makes every worktree removable the moment it goes quiet, and `ops/polaris awake disable` silences
  the keep-awake owner without unarming the machine. **NEW at update time:** the keep-awake hooks
  reach every armed machine on the next `polaris update` — they are machine-level, so updating one
  repo arms the whole box.
- Four contracts land with this release — `worktree-liveness.md`, `keep-awake.md`, `visual-check.md`
  and `role-handover.md` — plus a new section on `shared-checkout.md` (the added deny classes) and on
  `bg-jobs.md` (cwd ownership, archived logs). Three new drills — `wtreap`, `awake` and `handover` —
  bring the labeled suite to 34, and five new goldens (`perm-tools`, `pack-visual`, `awake-hook`,
  `handover-route`, `handover-stop`) bring `check` to 24/24.

## 6.1.0 — 2026-08-23

**Every piece of parallel isolation was already here except the part that enforces it.**

A worktree per task, disjoint `files_owned`, an atomic claim lock, one integration lease — the
machinery has shipped for releases. None of it was binding. Five concurrent sessions still shared
ONE primary checkout, and any of them could `git switch` or `git reset` it out from under the other
four; the claim gate promised Invariant 2 but only ever swept `active/`; a session sitting in the
primary on a non-`feat/*` branch passed no ownership check whatsoever. Not hypothetical: on
2026-08-23 one PR silently carried another session's commits. 6.1.0 closes the three seams where
isolation was a convention nobody could see, and lets a finishing builder land its own work instead
of waiting for somebody to come collect it. Additive throughout — every 6.0 interface is unchanged,
and the one behavior flip composes from an unset key with a one-line opt-out.

| | before | after |
|---|---|---|
| `git switch` / `reset` / `stash` in the shared primary | allowed — moves the ground under four other sessions | denied by `checkout-guard.sh`, which names the worktree command to run instead; silent inside `.polaris/wt/<ID>` |
| a session in the primary on a non-`feat/*` branch | no ownership gate at all | `primary_gate` refuses tracked-source writes while any task lock is live |
| Invariant 2 disjointness at claim | swept `active/` only, outside the mutex | sweeps `ready/` ∪ `active/` INSIDE the board mutex; `drift --strict` fails on overlap |
| a builder whose task just went green | hands to `review/` and waits for an integrator to appear | `landing: self` continues into a lease-gated `land`: queue behind the other lanes, then merge itself |
| "cd into your worktree" in the role files | one form, which half the callers structurally cannot use | two caller forms named: `EnterWorktree` for top-level sessions, absolute paths for pinned-cwd subagents |

- **`ops/hooks/checkout-guard.sh` — the primary checkout is not yours to switch.** A new PreToolUse
  guard denies exactly one thing: a checkout-mutating git invocation issued from the shared primary
  — `switch`, `checkout`, `reset`, `merge`, `rebase`, `cherry-pick`, `worktree add`, `branch`
  `-d/-D/-m/-M`, and `stash` except the read-only `list`/`show`. The same commands inside
  `.polaris/wt/<ID>`, all read-only git, and every non-git command produce NO output at all. Deny is
  narrow and silence is the default: any token it cannot read confidently as a command-position
  `git` is left alone on purpose, and the common path forks nothing — no interpreter, no
  `ops/polaris`, no git — because the lesson of the ownership guard is that a hook killed at its
  timeout FAILS OPEN and drops its gate silently. It refuses through `hookSpecificOutput` JSON on
  stdout, and it is deliberately NOT wired into `readonly-allow.sh`, whose whole safety contract is
  that it only ever ALLOWS. Deny lives in its own file.
- **`primary_gate` closes the hole underneath the other guard.** `ownership-guard.sh` gated a
  `feat/*` HEAD and nothing else, so the single most dangerous place to be — the shared primary, on
  the base branch, while four builders hold locks — was the one place with no gate. Now a write to
  tracked source from the primary is refused (exit 2 + stderr, the shape that call site reads)
  whenever a task lock is live, naming the worktree to run in instead. Primary-role surfaces stay
  open by design: `ops/board/`, `ops/contracts/`, top-level `ops/*.md`, `.polaris/`, and anything
  untracked. Nobody building → nothing to collide with → no gate.
- **Invariant 2 stops being a promise and becomes a gate.** The claim-time disjointness sweep now
  covers `ready/` ∪ `active/` rather than `active/` alone, and runs INSIDE the board mutex, closing
  the TOCTOU window where two sessions could each check a clean board and then both claim into it.
  `pat_overlap` is fork-free (it was a subshell per pattern pair, on the hot path of every claim),
  and `drift --strict` now fails on an overlap instead of merely mentioning it — so the planner
  hears about it one gate earlier, where re-grooming is cheap.
- **`landing: self` — the session that finishes the work lands the work.** New CONVENTIONS knob,
  `self` | `integrator`, defaulting to `self` in kit code by the 6.0.0 pattern (`update` must never
  rewrite a repo's own config, so a default that matters ships in code). A handoff continues
  straight into `land`, which takes the integration lease first: a finishing builder queues behind
  whoever holds the lane and merges itself when its turn comes, instead of leaving a green task in
  `review/` waiting for an integrator to be spawned. The opt-out is one line —
  `landing: integrator` restores the classic handoff exactly. `risk: high` tasks and anything on the
  STOP-AND-ASK list NEVER self-land, under any setting. `autolaunch_max` goes 3 → 5, re-sized for
  five lanes; `integration_wait_minutes` deliberately STAYS 10 — raising it past the harness's 600s
  tool cap does not buy a longer wait, it loses the wait entirely.
- **Worktree entry stops being folklore.** `claim`, `fleet` and the BUILDER, SOLO and CONDUCTOR role
  files now spell out both caller forms, because one instruction could never fit both: a top-level
  session uses `EnterWorktree` (verified working), and a pinned-cwd subagent uses an absolute `cd`
  or absolute paths, since `EnterWorktree` structurally refuses there. Half the callers were being
  told to run a command that cannot work for them.
- **Invariant 9, reworded with the human's word on it:** *"Only the integration-lease holder merges.
  The lease IS the Integrator."* The lease has been the real authority since 5.24.0; the invariant
  still named a role, which is exactly the ambiguity a self-landing builder walks into.
- `ops/contracts/shared-checkout.md` gains a `## v2` section (enforced isolation) covering all of
  the above. Three new drills — `checkoutguard`, `readyoverlap`, `selfland` — bring the labeled
  suite to 31, and two new golden pairs (`checkout-guard-denies`, `ownership-primary`) plus a
  refreshed `cli-help` (the `approve` and `adopt` help blocks had never been captured) bring `check`
  to 19/19.

## 6.0.0 — 2026-08-04

**Eleven releases of autonomy machinery, and nobody was running any of it.**

The hands-free knobs shipped in 5.13.0 defaulting to the asking behavior, and in practice were
never switched on anywhere — this repo ran two sprints with them off; polaris-testbed still has
them off. The system was structurally unable to say so: `doctor` printed the autonomy composition
only when a knob was already set, so exactly the repos that had never found the knobs were
guaranteed never to hear about them — and `update`, correctly, never writes into a repo's
CONVENTIONS.md, so no update could deliver the values. 6.0.0 flips the defaults in kit code,
which is precisely what `update` already replaces: every installed repo becomes autonomous on its
next update without anyone editing a file, and without `update` touching that repo's
CONVENTIONS.md, RULES.tsv, MAP.md, SPRINT.md or board.

**BREAKING — the new default posture, stated plainly:**

- **Unset autonomy knobs now compose the trusted values:** `plan_gate=auto` ·
  `builder_questions=default-safe` · `evolve_apply=auto-reversible`. Before 6.0, unset meant
  `confirm` / `ask` / `confirm`.
- **The one-line revert: add `autonomy: standard` to `ops/CONVENTIONS.md`.** It restores
  `confirm` / `ask` / `confirm` exactly. An explicitly set individual knob still beats
  `autonomy:`, in both directions — precedence itself (explicit > `autonomy:` > default) is
  unchanged, and `autonomy: trusted` stays legal, now equal to the default.
- **A typo can NEVER grant autonomy.** An unknown value on an individual knob falls back to that
  knob's STANDARD value (`confirm` / `ask` / `confirm`) — even under `autonomy: trusted`. An
  unknown `autonomy:` value behaves as `standard`. Both warn once. This deliberately inverts the
  old fail-to-default rule: unknown input now fails to the safe side, not to the default.
- **The hard gates never move, under any setting:** `risk: high` approval, the STOP-AND-ASK
  list, RULES.tsv, the ready gate, contract-before-code, green-before-review. EVOLVE still may
  never set or change the autonomy dial or its components, in either direction.
- **You are told at update time.** Incoming kit >= 6.0.0 and none of the four knobs explicitly
  set → `update` prints a two-line BREAKING banner naming the new composition and the one-line
  revert. Any of the four set, either direction → silent.
- **`doctor` now prints the effective composition unconditionally** whenever CONVENTIONS.md
  exists — the guard that printed it only when a knob was already set is deleted; the silence
  WAS the bug.

| | before | after |
|---|---|---|
| unset autonomy knobs | confirm / ask / confirm — dormant since 5.13.0 | auto / default-safe / auto-reversible |
| doctor on the composition | printed only when a knob was already set | printed always |
| a CONVENTIONS key a repo never learned about | capability ships dormant, invisibly | doctor names it; `polaris adopt` explains it |
| a shipped hook field change | never arrived (merge keyed on basename) | arrives (merge keyed on script path) |
| an `ask`-ruled scope, human's yes already given | Builder dies on its first write | settled at the plan gate, carried on the task |

- **`kit/ops/KEYS.tsv` — every CONVENTIONS key, on the record.** 37 rows: key, the version that
  introduced it, the effective value when absent, and one plain line naming what the repo loses
  while it is unset. `doctor` compares the registry against CONVENTIONS.md and reports drift in
  ONE line (this repo read "lacks 14 of 37 known keys"); a pre-6.0 install with no registry gets
  silence, not a warning storm. Rows document; they never execute.
- **`polaris adopt` — discovery, not enablement.** For every absent key it appends a COMMENTED
  stub to the end of CONVENTIONS.md — default, absent-cost, since — under a one-time marker
  line. It never edits an existing line, never uncomments, never writes a live value, and a
  second run is a byte-identical no-op that says so. Uncommenting a stub is and stays a human
  act; autonomy itself arrives via the kit-code defaults above, never through this command.
- **The settings.json hook merge learns path identity — and can finally repair what it ships.**
  The old merge keyed on script BASENAME and skipped any existing match, so an entry once
  written was never re-examined: a shipped field change (the ownership guard's timeout,
  10 → 20) could never arrive — and, sharper, a user hook that merely SHARED our basename made
  the POLARIS guard look already-wired, so in such a repo the guard was never installed at all.
  Now a POLARIS-owned entry is one whose command runs a script under `ops/hooks/`; kit entries
  REPLACE their existing counterpart wholesale (matcher, timeout, command) preserving list
  position, user-added hooks are byte-untouched whatever script they run, non-hook keys keep
  their exact merge semantics, and a second run changes nothing.
- **`polaris approve` finishes the `ask` rule kind — which this changelog never announced.**
  Backfill, owed since 2026-07-28: the third RULES kind landed then (contract 64c3742, then the
  RULES.tsv header, the `approved:` task field, the guard's remedy line, and the role/protocol
  surfaces) with no changelog entry. The kind: `ask` = the same denial as `path`, lifted only by
  a human's recorded approval on the task. 6.0.0 completes it: `approve <ID> <scope> -m "why"`
  records the approval (append-only, one board commit, modeled on `grant` via one generalized
  front-matter writer — `grant` widens ownership, `approve` clears a policy gate, and only
  `approve` needs a human). It refuses inside a `feat/*` worktree — a Builder cannot approve its
  own way out, mechanically. Enforcement threads the task ID through the rule scan, so verify,
  handoff, audit, land and the write guard all honor a covering approval — and print WHICH
  approval cleared the scope, so the exception is visible exactly where the Integrator looks.
  No ID → deny, fail-closed. `path` and `content` rules are untouched; an approval never clears
  a `path` rule.
- **`ask` reaches the plan gate, where the question is cheap.** The field failure this kind was
  built for (repo ARC: a human approved a schema change at the plan gate, the ready gate never
  consulted RULES, a Builder claimed the task and died on its first write — the work died with
  the decision already made) is now caught at step 1: `drift` flags a ready task owning an
  unapproved `ask` scope as a `READY GATE:` finding, and `triage` answers three ways — a `path`
  scope → `full`, cannot be built as specified · an unapproved `ask` scope → `full`, get the
  human's yes before starting · a covered `ask` scope → the question is settled, fall through to
  ordinary points-based routing.
- **`voice: standard` is rewritten radically plain.** Under the old row a real close read "Wave
  1 is sealed as sprint/10, the tree is clean…" — short, dense, every noun jargon — because the
  row's "unless you explain it in the same breath" escape hatch LICENSED jargon, the seven
  output rules optimized volume rather than simplicity, and the style's own worked examples (the
  model's actual imitation target) said "Full suite is green". The rewrite kills the escape
  hatch, bans trade words outright — drop the word and say the outcome: merged → "saved into the
  main copy", suite green → "every check passed" — restores the Pre-send check the vendored
  skill always had, and replaces the worked examples with closes that pass the ban. Commands to
  run stay verbatim; `voice: technical` is untouched. A new `plain-voice` golden pins the bar
  sentence, the dead escape hatch and the examples' register — the first mechanical guard the
  style/PROTOCOL byte-parity invariant has had.
- New contract `ops/contracts/key-registry.md`; `hands-free-knobs.md` and `output-style.md` gain
  `## v2` sections. New drills: `adopt` (stubs against the real registry, idempotent, live
  values survive byte-identical) brings the labeled suite to 28; `drill_hookmerge` joins the
  install suite with `drill_live_board` green UNCHANGED — the preserve guarantee is the thing
  being protected. Three new goldens (`keys-drift`, `adopt-stub`, `plain-voice`) bring the
  battery to 17 pairs, all hermetic, none pinning a line that embeds a version number.

## 5.24.0 — 2026-08-03

**Open a second chat on the same repo and it used to become your problem.**

Two sessions collided in the working tree, and every collision surfaced as a question: the second
integrator died on the first one's branch state, a dirty tree stopped `land` cold, one push hiccup
stranded a finished task with its lock held — and none of it was ask-worthy. After plan approval the
mechanics are POLARIS's job. Two sprints, one story: N chats on one repo stop colliding and stop
asking, models route themselves, and the commands longer than the harness's patience stop blocking.

| | before | after |
|---|---|---|
| second integrator, busy lane | dies on the other session's state | bounded wait, then rc 3 with one `queued:` line — never a question |
| dirty tree at land/seal/update | `working tree not clean`, dead stop | parked as `polaris/park-<epoch>`, caveat, proceed; `unpark` restores byte-identical |
| push fails at handoff | finished task stranded in active/, lock held | 3 tries + repair, then degrade: board moves, work safe locally, one ⚠ Note |
| which model a spawn runs on | whatever the platform defaults to | `polaris route` answers; conductor and fleet pass it |
| an 805s suite under a 600s tool cap | times out, returns NOTHING, gets re-run | `bg run test` → keep working → chunked `bg wait`; rc 0/1/2/3, never prose |

- **The integration lease.** `land`, `seal`, `rollback` and express all take ONE shared lane,
  serialized: a busy lane means a 2s-poll wait with progress notes, then rc 3 with a single
  `queued:` line — the conductor polls at wave boundaries instead of asking you to referee. Stale
  leases (crashed holders) are stolen past `integration_stale_minutes`, and a dying process
  releases its own lease on the way out.
- **Park, don't die.** The five dirty-tree die sites become `park` + caveat + proceed: tracked and
  untracked into a named stash, reversible in one command. `update` parks too. `status` and
  `finish` surface the lease and every parked stash, so a second chat's first read explains the
  world.
- **Waves adopt; re-lands are idempotent.** `land` on the base creates, fast-forward-reuses or
  ADOPTS the open `integrate/<date>` instead of demanding you finish it by hand; an already-landed
  ID prints `already landed — skipped` rc 0; a seal with only board noise says `nothing new to
  seal`. Two integrators can no longer die on each other's completed work.
- **Claims and pushes get honest.** IDs are validated BEFORE any lock exists; a stray ref
  literally named `feat` is repaired to `stray/feat-<sha7>` (archived, never deleted); claim
  re-checks ownership disjointness against every active task, catching a planner race at claim
  time instead of as an integrator conflict two builds later. A handoff push gets three attempts
  with a repair between; still failing → the board still moves, the work is safe locally, and the
  task carries one ⚠ Note instead of a stranded lock.
- **Locks learn whose they are.** The board mutex — the one lock in the kit without an ownership
  check — now writes a pid and refuses to release for any other process, mirroring the lease. Any
  process exit in one session could previously delete a mutex another session legitimately held,
  un-serializing two board mutations mid-flight.
- **The doctrine in one place.** `PROTOCOL.md` § N CHATS, ONE REPO is the second-chat decision
  table: claim says taken → claim the next · lane busy → bounded wait · `queued:` → report it and
  end the turn · dirty tree → park · another session's locks, leases and tasks → invisible, never
  stolen unless flagged STALE. And CLAUDE.md's stop-ask list gains the carve-out: git/workspace
  mechanics are never ask material after plan approval — the CLI prints the next step; follow it.
  Real asks stay.
- **Models route themselves.** `polaris route [<ID> | --role R | --points N --risk R]` answers
  with a bare tier word — strong where mistakes multiply (5 points or risk ≠ normal), cheap where
  they don't — overridable per task via `model:` frontmatter. Three CONVENTIONS knobs map tiers to
  real names (this repo: fable / opus / sonnet, never haiku; unset knobs = tier words only,
  behavior unchanged). The CONDUCTOR routes before every spawn, `fleet` injects the ready queue's
  max tier into every pane it opens, `pack` headers carry `· tier`. § MODEL ROUTING goes auto,
  with the honest boundary written down: a RUNNING session cannot switch its own model — routing
  governs what gets spawned and launched.
- **`bg` — the 600s cap stops eating suites.** Measured here so nobody re-measures: spine 144s,
  the 4-drill subset 320s, the sharded suite 169-378s — all inside the cap; the full serial suite
  at 805s and `qa` at 1225s are not, and a capped call returns NOTHING and gets re-run. `bg run
  <key>` detaches it, `bg wait --max 300` collects in bounded chunks, `bg status` speaks rc
  0/1/2/3 — every verdict is rc-file-first, then a live-pid check, because Windows reuses pids.
  Completed jobs rotate to `.prev` (archive, never delete), `sweep --fix` rotates day-old strays,
  a green `qa` warm-stamps so `finish` skips the re-run, and `finish` pends on any job still
  running — but never on a `.prev` archive (one `--force` replace used to wall the run-over gate
  forever). § LONG COMMANDS writes the three bands down, including the subagent rule: never end a
  turn with your job still running.
- **The auto-approver learns the new verbs — and unlearns one.** `route` and `bg
  status/tail/wait` run without prompting inside compound reads; `bg run` keeps its prompt. And
  `check --update` / `--scaffold` LOSE their silent pass: an agent quietly rewriting the goldens
  that gate its own work is the `.github/` problem in miniature. The deliberate, visible path
  stays sanctioned.
- Fixed in passing: the triage-lane golden ran against the LIVE board, so any session filing a
  task turned it red — re-founded hermetic, the pattern both new goldens follow; sprint reports
  gain an LF pin (the goldens' own CRLF pin shipped in-repo at sprint 7) and the report writer now
  commits its own file when it is the only dirt, so session B stops paying for session A's
  forgotten hint.
- New contracts `ops/contracts/shared-checkout.md`, `model-routing.md`, `bg-jobs.md`; six new
  drills (`park`, `claimguard`, `busyint`, `pushdegrade`, `route`, `bg`) bring the suite to 27
  labels; two hermetic goldens (`route-tier`, `bg-lifecycle`) bring the battery to 14 pairs.

## 5.23.0 — 2026-07-27

**5.22.0 shipped the confetti. Across six installed projects, nobody ever saw it.**

Three separate causes, and the first one is the kind of bug that hides behind a healthy-looking
status line.

| | before | after |
|---|---|---|
| a repo whose CLAUDE.md never updates | reports the new version, injects the old protocol | healed in place, and `doctor` can see it |
| the output discipline | a skill only a human can invoke | auto-selected output style, every session |
| the confetti trigger | formal board runs only | any session that changed the repo |
| `update` says | `updated 5.21.0 → 5.22.0` | …and what was refreshed, and what was not |

- **A version that lied.** A `CLAUDE.md` written before managed markers existed could never be
  replaced, so `update` refreshed `ops/`, stamped `ops/VERSION` to the new release, and left the one
  file every session actually reads frozen at install day. Found in the wild: a repo reporting 5.22.0
  while injecting a protocol from three weeks earlier, with every command — `doctor` included —
  calling it healthy. Now the installer wraps that text in markers and refreshes it, keeping anything
  below the separator and saving a byte-exact backup at `.polaris/CLAUDE.md.pre-heal`. If the POLARIS
  text is **not** at the top of the file, the boundary is unknowable and it refuses instead, leaving
  the file byte-identical: a heal that rewrites what it cannot delimit is how rules get lost.
- **The BEGIN marker now carries `[kit X.Y.Z]`,** so the block states its own provenance and `doctor`
  compares it against `ops/VERSION`. Three distinct warnings — no markers, unstamped, stamp
  mismatched — and silence when it is current. Blocks written before stamping still match the marker
  prefix, so one install migrates every kit in the field with no special case.
- **`.claude/output-styles/polaris.md` — the discipline finally arrives on its own.** The vendored
  `i-have-adhd` skill sets `disable-model-invocation: true` in its *upstream* frontmatter, so it only
  ever fires when a human types `/i-have-adhd`; its stated fallback lives in a `PROTOCOL.md` section
  `CLAUDE.md` tells sessions they probably need not open. The "always-on" layer was, in practice,
  neither. The installer now ships an output style and selects it — seven rules, the voice, and the
  closing contract, in every session, with nothing to type.
- **`keep-coding-instructions: true`, and why it gets three guards.** A custom output style
  *excludes* Claude Code's built-in software-engineering instructions unless that key is set — the
  harness would keep POLARIS's voice and forget how to scope a change or verify its work, a failure
  invisible in review and expensive in use. A golden, a `doctor` check and a contract invariant all
  hold that one line down.
- **The confetti fires for ordinary work now,** not just formal board runs — any session that changed
  the repo ends at `polaris finish`, and the exit code still decides. "Changed the repo" is defined
  by tool effect, never intent. Four endings that are *not* exit 0 get explicit rules, including the
  one that matters most: on a POLARIS too old to have `finish`, there is still no H1. The mark is
  worth exactly what checked it.
- `outputStyle` is seeded **set-if-absent, never forced** — `/config` writes your choice to
  `settings.local.json`, which outranks the file we write, so POLARIS never fights for a key it would
  lose. `doctor` reports the effective style instead. Uninstall removes our style and our key and
  leaves any other style alone.
- Deleted a line that had been false for four releases: `upgrade` recited a hardcoded "New since
  v4: …" on every 5.x→5.x run. It now points at the changelog URL that was already in `ops/VERSION`.
- New contract `ops/contracts/output-style.md`; `run-finish.md` gains a `## v2` for the broadened
  trigger. Three new install drills (`heal-pure`, `heal-unmarked`, `heal-refuses`, each asserting the
  quiet-line budget locally), a new `claudemd` selftest label, and a new golden pair.

## 5.22.0 — 2026-07-26

**You could never tell "done" from "stopped talking".**

A lane printed `✅ qa: all green` and went quiet. So did a Builder handing off mid-wave, a Conductor
pausing at a budget cap, and a run that was genuinely, completely finished. Three different states,
one indistinguishable ending — so the human went and re-read the board to find out which one it was.

The definition of "finished" was not missing. It was written down, precisely, at `CONDUCTOR.md`
§ "The second rule" — and locked inside that one role file, where SOLO, the INTEGRATOR and every lane
that ends a run without a conductor could not reach it. This release makes it a command.

| | before | after |
|---|---|---|
| "is the run over?" | re-read the board by hand | `bash ops/polaris finish` |
| the run-over definition | prose, in 1 of 8 role files | executable, inherited by every lane |
| lanes that fire the `done` hook | 1 of 4 (pr-mode seal only) | **all of them** |
| a finished run, on screen | `✅ qa: all green` | **`# 🎉 Complete!`** |

- **`polaris finish` — the run-over gate.** Eleven free board and git checks, then `qa`. Nothing
  building, nothing waiting to land, `ready/` drained per `drain:`, no unmerged `integrate/<date>`,
  no orphan lock, clean tree on base, suite green. rc 0 = the run is over. rc 1 names every pending
  thing on its own line, so "not done" is always actionable rather than a mood. It runs `qa` for you
  instead of trusting that you remember running it — and pays seconds when the suite stamp is
  already green at this commit.
- **The confetti, and why it lives in the reply.** On rc 0 the agent opens its closing message with a
  markdown H1 — `# 🎉 Complete!` — which renders huge and bold in the client. A command cannot do
  this: terminals do not render markdown. So the two halves are split deliberately, and the split is
  the whole point. The command owns the *verdict*; the reply owns the *signal*; the exit code is the
  only bridge. An agent can no longer decide it feels finished.
- **A partial ending now reads as one.** Budget cap, blocked work, red suite: no H1, no confetti —
  two or three warm sentences naming what landed, the one thing still pending, and the single next
  command, per the ADHD output discipline already in `PROTOCOL.md` § VOICE. Seeing 🎉 means 100%
  done, every time, or it means nothing.
- **`blocked/` is a caveat, never a gate.** Whether the human was *told* about parked work is not
  mechanically knowable, so gating on it would make runs un-finishable. Instead `finish` prints it as
  a `caveat:` line and the role files make naming every caveat mandatory. rc 0 means "the run is
  over", never "nothing was left behind".
- **The `done` hook fires exactly once, and now actually fires.** Keyed on the base tip sha in
  `.polaris/finish-stamp`, so it self-clears the moment the next run lands a commit — no expiry, no
  `--reset`. Before this, `notify-gate done` fired only from a pr-mode seal; direct-mode seal,
  `land --express` and SOLO never fired it at all. Every lane ends at `finish` now, so every lane
  fires it.
- **A Builder cannot celebrate, by construction rather than by good behaviour.** `finish` refuses
  outside the primary checkout, and a worktree builder is never in it. That closes five of the six
  subagent dispatch sites mechanically; two lines in `CLAUDE.md` — the only context every subagent
  shares — close the sixth.
- Fixed in passing: `CONDUCTOR.md` contradicted itself on the `drain:` default (one section said
  `queue`, another said `plan`; the CLI's fallback is `queue`, and `plan` is what INIT seeds).
- New contract `ops/contracts/run-finish.md`; new `drill_finish` (six assertions, hermetic);
  `cli-help-parity` 8 → 9.

## 5.21.0 — 2026-07-26

**The phases were never the expense. The contexts were.**

The standing theory was that POLARIS burns tokens because every change — even a one-line change — is
dragged through planner → builder → integrator → QA, paying at each phase. Measured, that is half
right, and the wrong half is the expensive one. `qa`, `verify`, `check`, `triage` and `drift` are
pure shell with zero LLM calls; cutting a phase removes a gate and saves nothing.

What costs is that every context carries a passenger. Measured on the author's machine: **251
skill/agent/command definition files under `~/.claude` inject 34,119 B (~8,500 tokens) into the
system prompt of every session and every subagent it spawns**, invoked or not. A conductor run
opens 6–8 contexts. 197 of those files were the claude-flow/RuFlo agent library, which POLARIS has
never called once.

| | before | after |
|---|---|---|
| unused definitions per context | 24,393 B (~6,100 tok) | **0, archived** |
| …per 6–8 context run | 36,588–48,784 tok | **0** |
| `ownership-guard.sh` (every Edit/Write) | 4,045ms | **976ms** |
| `kit/CLAUDE.md` (injected into every subagent) | 9,340 B | **7,607 B** |
| a Builder's context assembly | 6–15 tool calls | **1** |
| `polaris slim` itself | 1m52s | **2.7s** |

- **`polaris slim` — the token tax, measured and recoverable.** Reports what every context pays,
  per family, and what a run pays for it. `--apply` MOVES the identified machinery into
  `~/.claude/.polaris-archived/`; `--restore` puts it back (verified byte-identical). It is
  deny-by-default about *archiving*: three classes, not two, and anything it cannot positively
  identify as claude-flow machinery is reported and left alone. The first cut had two classes and
  would have archived `apple-design`, `frontend-design` and `emil-design-eng` — craft skills a human
  installed on purpose. The installer prints the report and never applies it.
- **`polaris pack <ID>` — one call replaces a Builder's whole cold start.** Task `## Why` and
  acceptance, the contract verbatim, the repo's *detected* house style, owned vs read-only files,
  the code-map for every owned directory, the public API surface not to break, the traps recorded
  against those exact paths, and the `verify:` list. "Read the brain first, `find` before Grep" was
  prose in five role files and every kickoff — prose a model can skip, and that an obedient model
  spends 6–15 round trips obeying. Now it is a command whose output *is* the context.
  Contract: `ops/contracts/context-pack.md`.
- **`polaris harness` — the app's test suite, generated once, run forever.** The behaviour tier above
  `check --scaffold --app`, which locks shape by reading files and so cannot tell you the app still
  boots. Detects the stack, writes ONE runnable suite (pytest or `node --test`), and captures a
  baseline inventory. Three sweeps — every module imports · every parameterless GET route answers
  non-5xx · every declared entry point runs `--help` — plus "nothing disappeared" against the
  baseline. **A sweep that cannot find what it needs SKIPS and says why; it never passes by
  asserting nothing, and never invents an app factory's arguments.** Verified against a Flask
  fixture (broken route caught, fixed route green, deleted module caught, deleted route caught) and
  a Node fixture (removed npm script caught). Contract: `ops/contracts/app-harness.md`.
- **The write-guard was failing open, and now it does not.** It cost 4,045ms per Edit, of which
  2,900ms was proving Python exists (`python3 -c pass` 559ms + `python -c pass` 920ms) and starting
  it to parse one JSON object. At twice that cost it exceeded its 10s hook timeout under parallel
  builders, got killed, and **silently dropped all three gates**. Now: the interpreter answer is
  cached (as `index_engine()` has always done for the index), `file_path`/`cwd` are read by the same
  pure-bash JSON parser `readonly-allow.sh` uses, and Python is not started at all unless a
  `content` rule could actually match — most repos have none. On a machine with no Python the path
  and ownership gates are now **enforced** rather than skipped entirely.
- **`find … -exec <read-only verb>` stops asking permission.** `-exec` is a launcher, so it is
  exactly as safe as what it launches — the same reasoning `xargs` has always had. It now recurses
  through the verb gate. `find . -exec rm`, `-exec sed -i`, `-exec sort -o`, `-exec python`,
  `-exec bash -c`, `-execdir`, and a `-o -delete` tail all still stop and ask. `{}` is accepted as a
  literal because bash requires whitespace after `{` to open a group, so `{}` can never be command
  syntax. The golden battery grew 47 → 63 cases.
- **SOLO is the default lane, and the lane is a command.** `start` and any unprompted work request
  now run `bash ops/polaris triage` and take line 1 — no more guessing SOLO-vs-CONDUCTOR from prose,
  where a wrong guess toward `full` costs a whole sprint of contexts. The SOLO envelope widens from
  ≤2 to ≤3 points: this repo's own calibration records that points predict scope and merge risk, not
  wall clock (5pt p50 = 2pt p50 = 0.5h, n=8, 0 kickbacks). Every gate still runs — SOLO collapses
  sessions, never checks.
- **`i-have-adhd` ships with the kit** (MIT, github.com/ayghri/i-have-adhd), vendored verbatim with
  its licence and a `SOURCE.md`, so `/i-have-adhd` works the moment POLARIS is installed with no
  `claude plugin install` step. Its frontmatter sets `disable-model-invocation: true`, so on its own
  it would never fire — `ops/PROTOCOL.md` § VOICE therefore carries the same discipline as seven
  always-on rules under BOTH voices. Less preamble is directly fewer output tokens.
  `ops/tests/adhd-skill-installed` proves it landed, licence and opt-in flag intact.
- **`bench.sh --context`** reports injected-context bytes per source, so the claims above are
  reproducible rather than asserted. `ops/PROTOCOL.md` gains § LANES (why a lane is a command, why
  one role never does two jobs) — moved out of the router, which every subagent pays for.
- **Answered, with numbers: no, a native C/Rust search engine is not the fix.** `bash -c true` costs
  115ms on this machine; `find`'s 810ms is ~115ms bash + ~500ms Python start + ~100ms of query, and
  `grep -rn` beats it outright at this repo size. A native binary would save ~600ms of wall clock
  and **zero tokens**. The win is cutting the NUMBER of calls, which is what `pack` does. The
  `index_engine()` seam stays for the day a repo is large enough to change that arithmetic.

## 5.20.0 — 2026-07-25

**Measure first, then fix what the measurement actually found.** Every performance claim in this
kit was a comment written from memory, and when they were finally timed several were wrong by 5×.
`find` was documented at 0.70s and ran at 1.1–2.0s. `hostname` was documented at 0.07s and cost
0.52s. The fix for "searching is slow" turned out not to be a faster search at all.

Measured on this repo (136 files, Windows/Git Bash), before → after:

| | before | after |
|---|---|---|
| `polaris help` | 2820ms | **201ms** |
| `_guard` (runs on every Edit/Write) | 2647ms | **572ms** |
| `polaris find` | 1119–2038ms | **666ms** |
| `polaris rules` | 1822ms | **1096ms** |
| `polaris check` (goldens) | 19s | **12.7s** |

- **Plan mode stops asking permission — in every repo, on every machine.** New
  `ops/hooks/readonly-allow.sh`: a PreToolUse hook that parses a Bash command and auto-approves it
  only when *every* segment is provably read-only. An allowlist structurally cannot do this —
  `Bash(grep:*)` matches one command, not `find … | xargs wc -l | sort | head`, and a fresh repo or
  machine starts empty regardless. Deny by default: an unknown verb, an unparsed construct or an
  unrecognised redirection produces no output at all and the normal prompt runs. `python -c`,
  `node -e`, `bash -c`, `tee`, `sed -i`, `sort -o` and `find -exec` are refused by name — they are
  the write doors on otherwise-read verbs. 47 cases (23 allow, 24 refuse) are pinned by
  `ops/tests/readonly-allow`.
- **…and installation now actually delivers it.** Three silent no-ops fixed: `install.sh` merged
  only `hooks.PreToolUse[0]` and bailed early on `grep -q ownership-guard.sh`, so a repo that
  already had `.claude/settings.json` never received a second hook; `refresh_machine_kit` armed
  three auto-mode keys and never re-applied the permission rules, so existing installs never got new
  ones; and the shipped settings template had no `permissions` key at all. Merging is by hook script
  NAME now, not array position, and is idempotent.
- **~2.2s of preamble removed from every command.** It ran before any command did any work, and the
  write-guard paid it on every edit: `cfg base` 683ms + `hostname` 524ms + a redundant
  `rev-parse --git-dir` 171ms + `SELF` in three subshells 132ms. Now one git call, one `cfg_boot`
  awk for all three keys, `SELF` from the already-resolved `OPS_DIR`, and `WHO` computed on demand.
  Two more forks found by tracing: `IFS="$(printf '\t')"` sits in a *while condition*, so it
  re-forked once per RULES line (42 rules ≈ 42 forks) on the guard's path, and `rule_scan_path`
  built a pipe per rule to reach `owned_match`. `help` now answers above the module loader entirely.
- **`ops/bench.sh`** reproduces the table above, and `ops/tests/startup-budget` asserts the
  *structure* that produced it — timings flap, fork counts do not.
- **The suite is paid once, not two or three times.** `polaris verify` now REFUSES a `verify:` entry
  that is the full suite: it runs 2–3× per task on top of the wave gate that already covers it, and
  the 2026-07-25 audit found 24 of 46 landed tasks doing exactly that. `PLANNER.md` had said so in
  prose since 5.15.0; a rule half the board violates is not a rule. `qa` also skips the suite when
  HEAD has not moved since the last green run and the tree is clean (`.polaris/suite-stamp`) — this
  is what stops a conductor re-running a suite the integrator just passed. `qa --force` overrides.
- **New SOLO lane: a one-line change costs one context, not four.** `ops/roles/SOLO.md` — one
  session plans, builds and integrates a trivial change with zero subagents. Entry is mechanical:
  `polaris triage` prints `solo` | `express` | `full` from points, risk, `express:`, `publish:` and
  the RULES-guarded paths, so nothing re-derives the six conditions by reading the board. Every gate
  still runs; SOLO collapses SESSIONS, never CHECKS.
- **The brain maintains itself.** `doctor` now REFRESHES a stale brain instead of advising you to,
  and it compares the code sha as well as the board timestamp — the old test looked only at
  `board-changed`, so this repo's own brain sat four releases behind while every role file told
  agents to read it first. `prefs.md` had two real bugs: the indent rules ended in `next`, so quote
  and line-length counting never saw an indented line (i.e. never saw code inside a function), and
  an empty sample printed zeros as though they were measurements.
- **`find --importers` resolves variable-built and mirrored paths.** `. "$OPS_DIR/lib/core.sh"`
  matches on its literal tail, and in a self-hosting repo the candidate in the importer's own tree
  wins — an exact tie resolves to NULL rather than a coin flip, because an edge into the mirror
  would point a Planner at a file that did not change. Both rules are pinned by `index.py
  selfcheck` and were each verified to fail it when disabled.
- **`check --scaffold --app`** generates goldens for the HOST application: declared dependencies
  (Invariant 8 as a diff — an unauthorised package reds instantly), npm script names, the HTTP route
  table, the migration set, and referenced env var NAMES. All by reading tracked files; it never
  runs the app, opens a port or touches a database.
- **`ops/contracts/code-index.md`** written — `search.sh` and `index.py` had both cited it for two
  releases and it had never existed.

## 5.19.1 — 2026-07-25

**What scaffolding this repo taught us.** Running `check --scaffold` on POLARIS itself produced
three goldens that were worse than nothing, and every repo would have got the same ones. Fixed in
the generator rather than deleted by hand, because the point is that the next repo gets it right
without anyone reviewing it twice.

- **Never lock a tree whose job is to change.** `scaffold_dirs` now skips `ops/` and `kit/ops/`
  (POLARIS's own INSTALLED copy — a 571-line `api-ops` golden would have reddened on every
  `polaris update`, asserting the opposite of the intended workflow), `docs/` (where `seal` writes a
  sprint report every wave), and `.github/` (human-owned and RULES-guarded, so an agent could not fix
  a red there anyway). Same reasoning that already excluded them from `prefs.md`.
- **No duplicate goldens.** A candidate whose output is byte-identical to an existing golden is
  skipped and counted. Caught for real: a generated `board-fm-cols` that duplicated the hand-written
  `board-fm-shape`. Two goldens asserting one thing double the cost of every real change.
- **`cli-help-parity` counts distinct commands, not matching lines.** Adding `check --scaffold` as a
  second usage form took the count 8 → 9 and reddened an addition that broke nothing. The assertion
  was always "all 8 daily commands are documented"; it now measures that, and still drops to 7 the
  moment one disappears.

## 5.19.0 — 2026-07-25

**Use what we already built.** 5.18.0 shipped a working code index and then never told anyone it
existed: no role file mentioned `polaris find`, and `CLAUDE.md` still said "Grep, don't browse". The
index was correct, fast, and dead weight. This release wires it in, makes the hot path actually
fast, and turns the golden-test harness from a mechanism into a corpus you can generate.

- **`find` / `show` are now the protocol's first move.** `CLAUDE.md`, all four role files, the brain's
  routing table and `MANUAL.md` say find-first, grep-second. The brain's INDEX gains a top row that
  routes a symbol lookup to a COMMAND rather than a file — 0 hops, not 2. A selftest drill asserts the
  row, so the index can never again be built, correct, and unused.
- **The hot path lost its 1.9s of dead weight.** `find` read none of the globals the entry point
  resolved for it. Traced: git-common-dir 0.47s, three `cfg` reads 1.0s, hostname 0.07s — on a command
  an agent runs ten times a task. `find`/`show` now run in a fast path above the loader, one git call
  deep, and exit. The engine probe is cached in `.polaris/index-engine`. **3.64s → 0.70s**, output
  byte-identical.
- **The index is O(changed), not O(repo).** `find` rebuilds incrementally on every lookup, which meant
  reading and SHA-1ing every tracked file *per lookup* — 0.5s of pure hashing on a 3,000-file repo,
  every time. Now it stats first and only reads what moved, with git's own racily-clean guard so a
  same-second same-size edit is still caught. Measured on a 3,000-file repo: **943ms → 628ms** warm.
  Schema 2; an older index rebuilds itself once.
- **`polaris check --scaffold` writes the tests.** The harness existed with four goldens and no
  generator. Scaffold detects the repo's public surface from the index and writes `.cmd`/`.expected`
  pairs, running each candidate twice and discarding anything that flaps, is empty, or whose command
  is missing. Never overwrites a reviewed pair. New `find --api <glob>` gives it the one output shape
  stable enough to lock — sorted `path/kind/name`, with line numbers and churn deliberately excluded.
  These are regression locks, not correctness proofs, and they say so.
- **`CLAUDE.md` 17,661 → 8,734 bytes.** The harness injects it into the conductor *and* every
  subagent, so its size was multiplied by four on every run. Role dispatch, the invariants and
  stop-and-ask stay; the command table, disk layout, token discipline, model routing and voice move to
  the new `ops/PROTOCOL.md`, read on demand. Roughly 9k tokens back per run.
- **The brain accumulates now.** `prefs.md` detects house style by counting — indent, quotes, naming,
  test layout — and prints the evidence behind every row, saying `mixed` rather than guessing when no
  majority exists. `learned.md` distills co-change pairs from git history, which is the one fact
  neither `metrics` nor the Learned log can give the Planner: which files move together, and therefore
  cannot sit in two different `files_owned` sets. Both zero-LLM. `ops/contracts/brain.md` v2.
- **A bug worth naming:** `prefs.md` first shipped counting POLARIS's own installed `ops/` bash, and
  told a fresh TypeScript repo its convention was snake_case on the strength of 165 functions that
  came with the tool. `ops/`, `kit/ops/` and `.claude/` are now excluded from style detection.

## 5.18.0 — 2026-07-25

**Stop paying for what you already know.** A run was burning tokens and hours on work no model
needed to do: agents hunted for code with repeated greps, the Planner read the whole board to learn
nine fields, a QA scout re-checked a green that a deterministic command had already proven, and
nothing put a ceiling on a run at all. This release moves that work off the model and onto the
machine — and fixes a guard that was quietly on its way to failing open.

- **`polaris find` / `polaris show` — the one-hop answer to "where is X".** A generated SQLite index
  (`.polaris/index.db`) over ~15 languages returns `path:line` + signature, one line per hit, ranked
  exact → prefix → substring and boosted by git churn and import fan-in. `show <path>#<symbol>`
  prints just that symbol's body instead of the file. Measured on this repo: a lookup that produced
  an ambiguous 81-token grep dump now costs 36 tokens with the definition first. Stdlib python +
  sqlite3, three tiers (FTS5 → LIKE → live scan) so it works with no compiler, no pip, and degrades
  to plain Grep when there is no python at all. New `kit/ops/index.py`, `kit/ops/lib/search.sh`.
- **`polaris check` — golden-output acceptance, zero LLM.** `ops/tests/<name>.cmd` runs and its
  stdout is diffed against `<name>.expected` (optional `.rc` for the exit code). A missing golden is
  RED, never silently green. Rides the existing `uat:` slot, so `qa` needed no change. Write the
  pair once while the context is already in hand; every run afterwards costs a subprocess instead of
  a subagent.
- **`polaris board-fm` — the Planner stops reading the board.** One TAB line per task carrying the
  nine fields the ready gate and dedupe actually use. Measured here: **159,093 B → 7,999 B, −94%**,
  and the gap widens with every task you finish.
- **The write-guard was heading for a silent failure.** It ran two full CLI startups per edit at
  ~6.7s against a 10s hook timeout; under parallel builders it would exceed that and **fail open**,
  dropping ownership enforcement with no sign. Root cause was `cfg`: a five-process pipeline costing
  ~1.2s per config read on Windows, called four-plus times on every single invocation. Now one awk.
  With a merged `_guard` entry point and a need-scoped module loader: **6,660 → 3,799 ms per write**,
  18% of a raised 20s budget. A cost fix and a correctness fix in the same change.
- **Runs are bounded.** `drain: plan` is the new default — one approval authorizes the plan the human
  approved, not the whole ready queue. Plus `run_max_tasks` / `run_max_minutes` / `run_max_agents` /
  `run_fix_waves`, checked at wave boundaries, ending in a clean stop that integrates what landed and
  reports. The interview is capped at 3 rounds, matching INIT.
- **`qa_scout: auto`** — the runtime scout spawns only where no automated check exists and the run
  touched a declared `runnable:` path. It found real drift once; the fix became a permanent `verify:`
  grep, which is the whole lifecycle. It should be earned, not assumed.
- **`test_fast:`** — a per-task gate for repos whose suite outgrew the harness. This kit's own suite
  measured 820s against a 600s tool ceiling, so every foreground run was timing out and being re-run;
  the fast tier is 320s and completes. The full suite still gates the wave, `qa`, and CI.
- **Rules maintenance is an agent's job** (owner decision). `ops/RULES.tsv` may be added to, edited,
  and pruned directly, with the reason recorded inline. Removing a rule remains a judgement about
  policy — never a way to get unstuck. Two long-missing rules landed with it: `ops/lib/` (unguarded
  since the 5.16.0 split, so every installed module was quietly hand-editable) and `ops/index.py`.

## 5.17.0 — 2026-07-22

**Seamless by default: the board reads the repo without stopping to ask.** Planning meant a
permission prompt on nearly every bash command — `grep`, `git status`, a `python -c` that only
reads a file — because a shell command can't be classified read-only ahead of time, and a compound
or interpreter command can never be safely allow-listed. So POLARIS now arms Claude Code's **auto
mode** at install AND update time: non-destructive commands run unprompted, in plan and execute
mode, while anything destructive or irreversible still stops and asks. The hands-free loop can
finally read freely.

- **Auto mode armed on install.** `bootstrap.py::merge_permissions` sets `permissions.defaultMode
  = "auto"` plus `skipAutoPermissionPrompt` and `useAutoModeDuringPlan` in `~/.claude/settings.json`,
  in the same atomic, fail-open pass that pre-authorizes the POLARIS commands. Set-if-absent, and
  gated by the existing `--no-permissions` flag. `kit/ops/bootstrap.py`.
- **...and on update.** `ops/polaris update` used to refresh the cached kit but leave settings
  untouched — so updating an existing machine stayed prompt-heavy. `refresh_machine_kit` now arms
  the same keys, silently and fail-open under `set -eu`, so updating ANY machine makes it seamless
  there too, not just the next fresh repo. `kit/ops/lib/admin.sh`.
- **Guardrails unchanged.** Auto mode decides only whether to PROMPT — it never disables hooks. The
  ownership write-guard, `ops/RULES.tsv`, and `polaris verify` still hard-block out-of-scope writes
  and danger zones in every mode, and the STOP-AND-ASK list (delete, add dependency, schema change,
  force-push, merge `risk: high`) is destructive, so it keeps asking.
- **Opt-out kept.** `--no-permissions` skips it, and an explicit stricter `defaultMode` you set
  yourself is respected — arming never overrides a choice already on disk.

Why it matters: a planner that has to ask before every `grep` is a planner nobody lets run
unattended. This closes the last routine prompt between POLARIS and a genuinely hands-free read.

## 5.16.0 — 2026-07-21

**Many hands: the CLI is no longer one 3,800-line file.** `ops/polaris` was a single monolith —
the reason every CLI sprint ran serially (one file, one owner at a time) and the reason the
embedded ~1,800-line selftest pushed the suite past the tool's time limit and stalled healthy
work. It's now a 163-line entry (globals + lib-loader + dispatch) that sources seven runtime
modules, with the selftest split into labelled groups that can run sharded. Verbatim relocation —
zero behavior change, proven byte-identical and by a full command-by-command scout pass on a real
modular install. `ops/contracts/module-layout.md` · `selftest-sharding.md` · `install-parity.md`.

- **Runtime-sourced modules.** `ops/polaris` loads `ops/lib/{core,ownership,builder,integrate,knowledge,observe,admin}.sh`
  in fixed order, then dispatches. A missing module dies before anything runs with a remedy that
  names the installer and `update`. No build step — `install.sh` copies `ops/lib/` recursively and
  `pack.py` ships every tracked module. `kit/ops/polaris`, `kit/ops/lib/*.sh`, `kit/ops/install.sh`.
- **Selftest split + opt-in sharding.** The suite moved into `ops/lib/selftest/` (spine + six drill
  groups, one `drill_<label>` per label). `doctor --selftest --only <labels>` takes comma-lists for
  targeted re-checks, and `--selftest --parallel <N>` runs the drill set across N shards with an
  aggregated verdict. Serial stays the default; CI stays serial. `kit/ops/lib/selftest/`.
- **Hermetic drills.** Every labelled drill now leaves the shared fixture as it found it, so
  `--only` subsets and `--parallel` shards are order-invariant — the coupling that made sharding
  unsafe is gone. `kit/ops/lib/selftest/policy.sh`.
- **Docs track the layout.** `kit/CLAUDE.md` STATE tree + THE TOOL and `kit/ops/MANUAL.md` gain the
  modular-CLI map and the missing-module remedy. Contracts pin the loader order, module boundaries,
  sharding semantics, and installer parity.

Why it matters going forward: future CLI sprints get disjoint per-module ownership (real parallel
lanes instead of a serial chain), every file under review is small, and the suite can be sharded
back under the time limit. This sprint itself was the last one the monolith forced to run serially.

## 5.15.0 — 2026-07-20

**The fast lane: requests stop taking hours.** Telemetry showed building averaged 12 minutes
while everything around it — serial waves, cold-start context, full-suite re-runs, fixed
ceremony — consumed the day (integrate avg 2.3h, 92% of cycle time). 5.15.0 attacks each
cause; every quality gate survives untouched.
`ops/contracts/brain.md` · `express-lane.md` · `pipelined-integration.md` ·
`verification-tiering.md` · `status-brief.md`.

- **The brain.** `brain [--refresh]` generates `.polaris/brain/` — a git-ignored, any-model
  knowledge base (INDEX routing + code map + board digest + contract digests + commands +
  gotchas) with a ≤4-hop lookup guarantee. `seal` and `done` keep it fresh automatically;
  `doctor` warns when it's stale. Role files and conductor kickoffs read the brain FIRST,
  repo second — cold-start re-derivation (measured at ~1.6M duplicated tokens per sprint)
  stops. Scales from greenfield to multi-thousand-file repos via per-directory
  summarization. `kit/ops/polaris`, `kit/ops/roles/`.
- **Express lane.** Small requests stop paying the full pipeline: conductor triage routes a
  single ≤2-pt normal-risk task to one builder + `land --express <ID>` — audit, land, ONE
  full suite, seal, run-verify, done in a single pass — skipping the QA scout and EVOLVE
  (no signal in a sample of one), still ending at the full `qa` gate. Four refusals guard it
  (>1 task · risk:high · `express: off` · `publish: pr`). New key `express: auto | off`,
  default auto. `kit/ops/polaris`, `kit/ops/roles/CONDUCTOR.md`.
- **Pipelined integration.** The integrator spawns at the FIRST handoff and lands tasks as
  they arrive in review/, in dependency order — a wave's wall-clock is no longer hostage to
  its slowest lane (measured here: integrate avg 2.3h → 1.8h). Every conductor kickoff
  template now carries the foreground rule that ends the background-notification stalls,
  plus dead-lane recovery guidance. `kit/ops/roles/CONDUCTOR.md`, `kit/ops/roles/INTEGRATOR.md`.
- **Verification tiering.** `doctor --selftest --only <pattern>` runs the always-on spine
  plus a labeled drill subset for cheap targeted re-checks (distinct subset pass line —
  it can never impersonate the full gate); `qa` stamps suite duration and `land` hints when
  a suite outgrows paranoid mode's <2-minute rule. `kit/ops/polaris`.
- **Readable feedback.** `status --brief` answers "where are things?" in one plain-English
  paragraph; `metrics` opens with an "In plain English:" line. `kit/ops/polaris`.
- **Post-scout fixes** (caught in a scratch install before tagging): brain `commands.md` no
  longer truncates the effective-CONVENTIONS values; a completed wave now ends with the
  brain FRESH (done refreshes like seal); `land` output is free of git merge chatter on
  Windows; `type: test`/`docs` tasks land as `test(...)`/`docs(...)`; MANUAL's brain file
  count reconciled. `kit/ops/polaris`, `kit/ops/MANUAL.md`.

## 5.14.1 — 2026-07-20

**`report --all` attributes sealed tasks correctly.** A combined `local` declaration in
`resolve_sprint_ids` expanded `$n` before assigning it, so the `--all` pass resolved sprint tags
from the caller's variable and quietly filed sealed tasks under "(unsealed)". Caught by the
testbed verification of the published release, not the fixture's happy path — the selftest now
carries a Rule-2-blind drill that is red on the unfixed function. `kit/ops/polaris`.

## 5.14.0 — 2026-07-20

**One PR, clean graph: the shared remote finally reads like a changelog.** Board bookkeeping
moves off `<base>` onto its own `polaris/board` branch, a wave can ship as ONE pull request on
a protected main, and every sealed sprint writes a management-readable report that rides the
same merge. Defaults preserve today's behavior — `publish: direct` until you opt in; existing
boards migrate with one explicit `polaris upgrade`.
`ops/contracts/quiet-board.md` · `ops/contracts/publish-modes.md` · `ops/contracts/sprint-report.md`.

- **Quiet board.** `chore(board):` commits leave `<base>` forever: every board mutation now
  commits the moved set (`ops/board/**` + `ops/SPRINT.md`) to `refs/heads/polaris/board` via
  secondary-index plumbing — files stay at their on-disk paths, no second worktree, and
  `sync_board` pushes the board ref (which a protected main can't reject). `done`'s `map_delta`
  lands as its own `docs(map): <ID>` commit only when non-empty. `upgrade` migrates a 5.13
  board idempotently; `doctor`/`resume` materialize the board in a fresh clone; `uninstall`
  removes the branch; `claim`/`resume` print primary-anchored task paths (worktrees no longer
  carry `ops/board`). `kit/ops/polaris`.
- **`publish: direct | pr`.** New CONVENTIONS key. Under `pr`, `handoff` keeps `feat/<ID>`
  local — feature branches never reach the remote — and `seal` pushes ONLY `integrate/<date>`,
  printing the ready-made Bitbucket PR-create URL plus a suggested title/description. After the
  human merges the PR (merge commit, never squash), `seal --sync` fast-forwards `<base>`,
  verifies every `[<ID>]` landed, moves the `sprint/<n>` tag, and deletes the integrate branch
  both sides. Under `direct`, a rejected base push now suggests `publish: pr` instead of
  failing quietly. `kit/ops/polaris`, `kit/ops/roles/INTEGRATOR.md`, `kit/ops/roles/INIT.md`.
- **Sprint reports.** `report [--sprint <n> | --all]` renders `<reports>/sprint-<n>.md`
  (default `docs/sprints/`) — per task: ID, title, points, risk, the `## Why`, acceptance
  criteria, files touched, landed sha, dates — from board state and history, including past
  sprints. `seal` auto-commits the wave's report as `docs(sprint-N): report` on
  `integrate/<date>`, so the record rides the same merge/PR management will browse.
  `kit/ops/polaris`.
- **Remote hygiene.** `sweep` flags merged `integrate/*` strays (`--fix` deletes, diverged ones
  are never touched); `seal` counts rejected base pushes and `doctor` recommends `publish: pr`
  once the pattern is clear. `kit/ops/polaris`.
- **Docs catch up.** Invariant 6 now names the board ref; THE TOOL table covers
  `report`/`seal --sync`/mode-aware `handoff`; MANUAL gains by-hand recipes for the board
  commit, both publish modes, migration, and fresh-clone materialization; role files teach the
  new flow. `kit/CLAUDE.md`, `kit/ops/MANUAL.md`, `kit/ops/roles/`.

## 5.13.0 — 2026-07-18

**Hands-free core: the loop can run past the plan-gate wait, keep draining backlog, read a
standing roadmap, and page you only at the moments it actually needs a human.** Every knob
defaults to today's exact behavior — nothing changes until you opt in.
`ops/contracts/hands-free-knobs.md`.

- **The autonomy dial.** One `autonomy: standard | trusted` composition knob (or `plan_gate`,
  `builder_questions`, `evolve_apply` set individually) lets the Conductor skip the plan-gate wait
  on genuinely low-risk plans, Builders default reversible spec details instead of asking, and
  EVOLVE auto-apply its fixed, reversible allowlist — risk:high approval, STOP-AND-ASK, and RULES
  stay in force under every setting. `kit/ops/roles/CONDUCTOR.md`, `kit/ops/roles/BUILDER.md`,
  `kit/ops/roles/EVOLVE.md`.
- **Backlog drain.** `drain: backlog` (+ `drain_slices`) has the Conductor keep promoting a plan's
  next ready-gated slice from `backlog/` after the original ready set empties, instead of ending
  the run with groomed work parked. `kit/ops/roles/CONDUCTOR.md`, `kit/ops/roles/PLANNER.md`.
- **ROADMAP.** A human-authored, ordered outcome list agents read — never write — when a kickoff
  carries no objective and the board is empty, offering the next unstarted line as the candidate
  objective. Skeleton ships at `kit/ops/templates/ROADMAP.md`. `kit/ops/roles/PLANNER.md`.
- **Notify v2.** `POLARIS_SEVERITY` (`info` / `gate` / `done`) rides every `notify:` hook
  alongside a distinct `blocked` board event, plus a `notify-gate` shim the Conductor calls at
  every human wait — so a recipe can page only when the run is actually stuck. Copy-paste
  ntfy.sh/Slack recipes in `ops/PROMPTS.md`. `kit/ops/polaris`.

## 5.12.0 — 2026-07-18

**One clean commit per landed task, one tagged commit per sealed sprint.** A landed task used to
arrive on `<base>` as a `--no-ff` merge of its whole `feat/<ID>` branch — WIP commits, false
starts, and all — so `git log` on `<base>` was unreadable as a changelog. History is now
squash-per-task, tag-per-sprint, and reversible; existing history is never rewritten.

- **`land` / `seal` replace the per-task `--no-ff` merge.** `land <ID>` squashes a reviewed
  task's branch into ONE commit on `integrate/<date>`, message built from the task file itself
  (`## Why` body + acceptance criteria + builder Notes, via the new pure helper
  `task-commit-msg`) plus a `Landed-from:` trailer pointing at the branch tip. `seal [<date>]`
  folds a sprint's `integrate/<date>` into `<base>` with one `--no-ff` merge and a lightweight
  `sprint/<n>` tag. `kit/ops/polaris`.
- **`history` and `rollback` read and undo it.** `history [--tasks <n>]` prints `<base>`'s
  first-parent log with `chore(board):` commits filtered out — a changelog for free.
  `rollback <ID | sprint/<n>>` reverts a landed task or a whole sealed sprint, never resetting or
  force-pushing. `kit/ops/polaris`.
- **Squash breaks feat-branch ancestry, on purpose.** Everywhere the kit asked "is this task
  merged?" via `merge-base --is-ancestor`, it now checks for a commit ending `[<ID>]` in `<base>`
  history first, falling back to the old ancestor check so hand `--no-ff` merges (MANUAL.md) keep
  working. Covers `done`'s merge gate, its remote-branch cleanup, and `sweep`'s stray detection.
  `kit/ops/polaris`.
- **The Integrator recipe moves to land → seal.** Per-task audit + `land` in dependency order on
  `integrate/<date>`, full suite once the combined tree is green, `seal`, then per-task
  `run-verify` + `done` on `<base>`. `kit/ops/roles/INTEGRATOR.md`.
- **Docs catch up.** THE TOOL table gains `land`/`seal`/`history`/`rollback` and the one-line
  history model; MANUAL.md gains hand-runnable fallback recipes for `land` and `seal`; INIT notes
  the history model and offers a clean-log git alias for new repos. `kit/CLAUDE.md`,
  `kit/ops/MANUAL.md`, `kit/ops/roles/INIT.md`.

## 5.11.0 — 2026-07-17

**Your product carries no AI fingerprints.** Sprints were landing commits stamped
`Co-Authored-By: Claude … <noreply@anthropic.com>` — written by the coding harness, not by the
kit, so nothing in the kit prevented them. And every landed task left its `feat/<ID>` branch
rotting on the remote. Both are now the kit's problem, mechanically.

- **AI attribution is dead, three layers deep.** (1) The shipped `.claude/settings.json` turns
  the harness behavior off at the source (`"includeCoAuthoredBy": false` + empty `attribution`),
  and the installer heals EXISTING settings that pre-date the key. (2) A new git `commit-msg`
  hook — installed into the repo's shared hooks dir, so every builder worktree runs it — strips
  AI-provider attribution from every commit whatever wrote it: Claude/Anthropic, Copilot,
  Cursor, Codex/ChatGPT, Gemini, Devin, aider, `[bot]` co-authors, `🤖 Generated with …` badges.
  Human `Co-Authored-By` trailers pass untouched; the hook cleans, it never blocks. A foreign
  commit-msg hook or `core.hooksPath` is respected with a chain-by-hand note, never clobbered.
  `doctor` re-installs the hook on fresh clones (clones don't carry `.git/hooks`). (3) One line
  in the protocol tells every model, on any harness: no attribution lines, ever.
  `kit/.claude/settings.json`, `kit/ops/hooks/commit-msg`, `kit/ops/install.sh`,
  `kit/ops/polaris`, `kit/CLAUDE.md`.
- **`done` takes the remote branch with it.** `handoff` pushes `feat/<ID>`; `done` now deletes
  it from origin too — but only after proving the remote tip is fully merged into base. A
  diverged tip is left in place with a pointer, never lost. `kit/ops/polaris`,
  `kit/ops/roles/INTEGRATOR.md`, `kit/ops/MANUAL.md`.
- **`sweep` cleans up the past.** New remote-hygiene pass: any `origin/feat/<ID>` whose task is
  in `done/` is flagged; `sweep --fix` deletes the fully-merged ones and refuses the diverged
  ones (those it names, with the exact inspect command). Point it at a board that predates this
  release and the branch wall comes down. `kit/ops/polaris`.
- **Selftest proves both.** New drills: a commit stamped with AI trailers must come out clean
  (subject intact), and a bare-origin fixture proves handoff pushes, `done` deletes, and
  `sweep --fix` removes a resurrected stray. `kit/ops/polaris`.

## 5.10.0 — 2026-07-16

**The loop closes itself.** 5.9.0 promised hands-free after the one plan approval; real runs
still stalled at phase boundaries, ended without proof the work was green, and left queued work
and self-tuning for the human to come back for. Now a conductor run has a mechanical finish
line — and setup got a question shorter.

- **`polaris qa` — "is everything okay?" in one shot.** Runs the full CONVENTIONS suite
  (test/lint/typecheck/build, `uat:` if set), then `drift --strict`, then doctor's env check —
  every check even after a red, one line each, rc 1 if anything was red. The Integrator runs it
  before reporting; the Conductor runs it ITSELF after integration — a subagent's "green" is
  never taken on faith. Selftest gains green/red qa drills. Building it surfaced a latent config
  bug, also fixed: a blank CONVENTIONS key with a trailing comment (`lint:  # none`) used to read
  as the comment text — qa would have run it as a no-op and called it green. `kit/ops/polaris`,
  `kit/ops/roles/INTEGRATOR.md`, `kit/ops/MANUAL.md`.
- **Phase boundaries are not stopping points.** The conductor's contract now says it as a rule: a
  finished phase is a starting gun — the next phase launches in the same turn, and the run is over
  only when every planned task is done or parked-with-reason, the queue is drained, `qa` is green
  on base, EVOLVE's proposals are in, and the close report is delivered. Plus a
  compaction-recovery recipe: the board is the run's memory — re-anchor from `polaris status`,
  never re-interview. `kit/ops/roles/CONDUCTOR.md`.
- **The run checks its own work — and fixes it.** New Check phase after integration: `qa` plus one
  read-only QA scout that exercises the changed flows hunting for runtime errors. Anything red
  starts a fix wave (a planner files the bugs, builders fix, integrate, re-check), capped at two
  per run, then parks the offenders and says so plainly. `kit/ops/roles/CONDUCTOR.md`.
- **The queue drains itself.** New `drain:` convention (default `queue`): after the plan's own
  tasks land, the run keeps going until `ready/` is empty — disclosed at the plan gate, never a
  surprise. `drain: plan` restores stop-after-plan. `kit/ops/roles/CONDUCTOR.md`,
  `kit/ops/roles/INIT.md`.
- **The run tunes the kit before signing off.** After the final green `qa`, an EVOLVE subagent
  diagnoses the sprint's data; its ≤3 evidence-backed proposals land numbered in the close report —
  apply one with "approve <n>"; nothing ever applies itself. `kit/ops/roles/CONDUCTOR.md`.
- **Terminal panes stop dying silently.** When the last builder hands off and nothing is left to
  build, `polaris handoff` says so and prints the integrator kickoff (plus an `all-review` event
  for `notify:`); with work still queued it says how to start it. `kit/ops/polaris`.
- **Setup is two questions.** INIT's express lane is now the default, not an offer: voice, then
  the goal — the config-confirm round fires only for what genuinely cannot default (an
  unclassifiable danger zone, an underivable command). `kit/ops/roles/INIT.md`.

## 5.9.3 — 2026-07-16

**Setup starts itself, whichever door you came through.** A real "update POLARIS" on a
never-configured repo showed an agent quoting the run-INIT epilogue and still deferring it as "a
separate step from the update you asked for". Every install- or update-shaped interaction on an
unconfigured repo (no `ops/CONVENTIONS.md`) now ends by RUNNING setup in the same chat, not by
suggesting it.

- **The epilogue closes the loophole**: "this holds whatever the human asked for — install, update,
  or reinstall: an unconfigured POLARIS is not delivered. Running setup now IS the request."
  `kit/ops/install.sh`.
- **`polaris update` finishes the job.** On an unconfigured repo it re-prints the run-INIT epilogue
  as the LAST thing on stdout (the closing "updated X → Y" lines used to bury it), and its
  dirty-tree refusal now prescribes the sanctioned path — re-run the cached installer; there is no
  board to protect — instead of leaving agents to improvise. `kit/ops/polaris`.
- **The skill's Update section gets the same terminal gate as installs**: after any update, or a
  refused one, `ops/CONVENTIONS.md` missing → § After the install, now, this session. The
  "already installed" routing row gains the same check. `kit/.claude/skills/polaris-install/SKILL.md`,
  one-line promise in `kit/ops/PROMPTS.md`.

## 5.9.2 — 2026-07-16

**The epilogue learns the house rules.** 5.9.1's run-INIT epilogue quoted the retired kickoff
phrase — once as a "don't say this" and once as a human fallback — and CI's homework tripwire
(which greps install output for that literal phrase, deliberately unable to tell mention from use)
correctly went red. The epilogue now describes the job without quoting the phrase; the tripwire
stays maximally strict; the quiet-line drill counts only the lines above the epilogue and asserts
the epilogue is present. `kit/ops/install.sh`, `.github/workflows/ci.yml` (owner-approved rule
lift, restored same commit).

## 5.9.1 — 2026-07-16

**First-contact installs finish the job.** On a machine that had never seen POLARIS, "install
POLARIS" installed correctly and then stopped — the session told the human to *"say 'You are
INIT'"* instead of running the setup interview itself (observed on a real first install). The
chain-into-INIT instruction lived only in the `polaris-install` skill, which by definition isn't
loaded during a machine's first-ever install.

- **The installer now routes the agent itself.** On a `fresh` install (INIT never ran —
  `ops/CONVENTIONS.md` absent), the installer prints a "▶ NEXT" epilogue addressed to the AI agent
  running it: read `ops/roles/INIT.md` and execute it in THIS chat; never hand the human "say 'You
  are INIT'" homework. A `live-board` install stays silent — INIT never re-runs. Installer stdout is
  the one channel that reaches every installing agent, skill or no skill. `kit/ops/install.sh`,
  comment truth in `kit/ops/bootstrap.py`.
- **Both READMEs carry the same routing** for agents that explore before installing (that is
  exactly what the failing session did). Root `README.md`, `kit/README.md`.
- **The install drill proves it stays.** `selftest-install.sh` now asserts the fresh output carries
  the epilogue and the live-board output does not. `kit/ops/selftest-install.sh`,
  `kit/.claude/skills/polaris-install/SKILL.md`.

## 5.9.0 — 2026-07-16

**One chat, the whole loop.** Until now every phase needed a fresh chat: plan, then open a window per
builder, then another for integration. The new **CONDUCTOR** role runs the entire loop in the one
conversation you already have — it interviews you until it truly understands, proves it with a brief,
plans, builds in parallel, integrates, and reports — each phase a fresh subagent, so context never
degrades and token discipline holds.

- **The Conductor.** In a subagent-capable CLI (Claude Code), a work request or `start` now runs
  interview → brief → plan gate → parallel builders → integration → report, hands-free after the one
  plan approval. The conductor acts as NO role itself — every role runs in its own subagent with its
  classic minimal context, so invariant 5 (one role per session) holds by construction. Live
  plain-language one-liners as each lane lands; snags surface immediately (decisions go to you, red
  work gets one fresh-builder retry, then parks in `blocked/`); `risk: high` still never merges
  without your literal approval. Lanes capped by `autolaunch_max`. New `builders:` convention key
  (`subagents` default · `panes` keeps the terminal-pane flow); CLIs without subagents fall back to
  the classic dispatch automatically. `kit/ops/roles/CONDUCTOR.md` + dispatch in `kit/CLAUDE.md`,
  `kit/.claude/skills/polaris/SKILL.md`, subagent notes in `BUILDER.md`/`INTEGRATOR.md`/`PLANNER.md`.
- **Planning that proves it understood.** The Planner's interview is no longer capped at 2 rounds: it
  lists every decision that would change the carving and asks until one more answer wouldn't change
  it — zero questions for a concrete request, several rounds for "improve the UI/UX" — always as
  concrete pick-one options in your chosen voice. Then a **brief gate**: "here's what I WILL change,
  what I WON'T touch, and what DONE looks like" — confirmed by you before a single task exists. A
  wrong brief costs one message; a wrong sprint costs every builder. `kit/ops/roles/PLANNER.md`.
- **Windows panes actually open.** 5.8.0's `fleet --launch` resolved `claude` to the npm bash shim,
  which Windows Terminal's process launcher cannot start — every pane died with `0x80070002 "file
  not found"`. The launcher now resolves a real `claude.exe`/`claude.cmd` to its full (8.3, space-safe)
  Windows path, falls back to a `bash -lc` wrapper for bash-only shims, and `--dry-run` prints the
  exact resolved command. `kit/ops/polaris`.

## 5.8.0 — 2026-07-15

**The gates hold, the loop closes.** This sprint makes POLARIS's core promise — many builders, zero
collisions, machine-enforced — true where it used to lean on a careful Planner or plain luck; clears
the snags that made a fresh sprint fail before a line of code; and gives the human real visibility
into a running board.

- **Harder gates.** `verify`/`audit` now diff with `--no-renames`, so a `git mv` can no longer smuggle
  a non-owned file's deletion past the ownership check. `drift` catches nested-glob overlaps it used to
  call "undecidable", and the Planner re-runs `drift` on the plan it just wrote before fanning out — an
  overlap now costs nothing instead of surfacing as an Integrator merge conflict two builds later.
  `kit/ops/roles/PLANNER.md`, `kit/ops/polaris`.
- **`claim` fans out for real.** With no ID, `claim` now skips a locked task and takes the next, so a
  fleet of Builder panes lands on distinct work instead of all grabbing the top one and N-1 dying; the
  worktree-add step retries under concurrency. Also fixes a hard `claim` parse error on macOS's stock
  `/bin/bash` 3.2. `kit/ops/polaris`.
- **A fresh sprint reaches green.** New `bootstrap:` convention installs deps in each Builder's worktree
  on claim; a blank `map_delta` warns at handoff so `ops/MAP.md` stops silently rotting; and `generated:`
  keeps git-tracked build output from failing a handoff. `kit/ops/roles/INIT.md`, `kit/ops/polaris`.
- **See what the board is doing.** `polaris why <ID>` shows why a task bounced or blocked; `polaris
  resume` takes over a crashed Builder's task; blocked tasks surface in `status` with their reason;
  `drift` flags dependency cycles and dangling deps; `metrics` splits build time from integration wait
  and names the oldest task awaiting integration; and the Integrator rules out a pre-existing flake
  before kicking good work back. `kit/ops/polaris`, `kit/ops/roles/INTEGRATOR.md`.
- **Windows launch actually fires.** `fleet --launch` resolves the `claude` `.cmd`/`.exe` shim that Git
  Bash's `command -v` misses, and says so plainly when it truly cannot open panes. The write-guard no
  longer false-blocks a legitimate edit when the path's case differs from git's.
  `kit/ops/polaris`, `kit/ops/hooks/ownership-guard.sh`.
- **Orientation back in the box.** The zip ships a `README.md` again; `pack.py --dogfood` refuses on a
  version mismatch instead of installing the old artifact and calling it new; the two install paths copy
  identically. `kit/README.md`, `kit/ops/pack.py`, `kit/ops/install.sh`.
- **Self-hosting honesty.** `doctor` reports when `kit/ops/VERSION` is ahead of the installed `ops/` —
  a release built but never dogfooded — and `update` refuses to run in the repo that builds POLARIS,
  where it would install `ops/` over itself. `kit/ops/polaris`.
- **An install drill a Builder can run.** `kit/ops/selftest-install.sh` exercises the fresh /
  live-board / old-client / uninstall paths end to end — the one path CI covered but a Builder could
  not is now testable by hand.

## 5.7.0 — 2026-07-15

**POLARIS takes the wheel.** Describe what you want in plain English and POLARIS routes it to the
Planner itself, asks a few simple questions to get it right, then opens a Builder per task in
side-by-side terminal panes — no "which role?" detour, no pasted kickoffs.

- **Auto-route.** A work request ("improve the settings page") with no role and no `start` word now
  becomes a PLANNER run. A guard keeps questions ("what does auth do?") and operational commands
  ("start the dev server") as ordinary chat — the discriminant is intent to *change* the repo vs. to
  *understand or operate* it. `kit/.claude/skills/polaris/SKILL.md` + `kit/CLAUDE.md`.
- **Clarify before carving.** The Planner asks bounded, voice-appropriate questions up front
  (≤2 rounds of ≤4) so the sprint's accuracy is bought once; a Builder may ask a single question when
  a spec detail is genuinely ambiguous, while structural blocks still hard-stop to the failure path.
- **Auto-launch.** New `autolaunch:` convention key (`wt` | `ask` | `off`, default `ask`). After
  planning, the Planner fans out builders per that setting: on Windows, side-by-side Windows Terminal
  panes each running `claude start`, capped at `autolaunch_max` (default 3). `polaris fleet <N>` gains
  `--launch` and `--dry-run`; the tmux path is unchanged and it falls back to printing the kickoff
  where neither tmux nor Windows Terminal is present.

## 5.6.0 — 2026-07-14

**POLARIS now builds POLARIS.** The kit runs its own board — parallel Builders, the write-guard, the
lot — which it could not do before without shipping its own board to every user.

The blocker was that the kit source and a POLARIS installation both wanted the same directory,
`ops/`. Installing here would have made our `CONVENTIONS.md`, `MAP.md`, `SPRINT.md`, `RULES.tsv` and
`board/` git-tracked *inside the product*. `pack.py` packs whatever `git ls-files` returns, so all of
it would have shipped — and a repo that has a `CONVENTIONS.md` **is** a live board by the installer's
own test, so every fresh install would have arrived pre-initialized and locked INIT out of the repo it
had just been installed into. Uninstalling would have deleted the product.

- **The product moved to `kit/`.** `kit/CLAUDE.md` + `kit/ops/` + `kit/.claude/` are everything that
  ships. The repo root is now an ordinary POLARIS installation like any other. `pack.py` runs
  `git ls-files` *inside* `kit/`, so the board is excluded structurally — not by a blacklist somebody
  has to remember to extend. The zip's internal layout is unchanged; `.github/` and `archive/` stop
  shipping as a bonus.
- **`pack.py --dogfood`** — downloads the zip **from the published release**, installs it here, and
  runs the board's selftest. It is the release's acceptance test: the only one that walks the path a
  stranger walks. A release that cannot run our own board is not a release, and CI's daily job now
  goes red if this repo lags the newest published version — *"we shipped something we never ran."*
- **`install.sh` no longer copies `ops/*.md` by glob.** Named list. A glob run from a self-hosting
  checkout — which is exactly what `polaris update` does, since it installs from the branch tarball's
  root — would have raked our `CONVENTIONS.md`/`MAP.md`/`SPRINT.md` into a stranger's repo.
- **`emit_block` unwraps a managed source.** Our root `CLAUDE.md` is now itself a managed block, and
  it is the file `update` reads. Cat it raw and every update nested one more marker pair inside the
  last, until `uninstall` — which stops at the first marker it meets — could no longer delimit the
  block it exists to remove. It now emits what lies *between* the markers, which also makes the whole
  operation idempotent, as it always claimed to be.
- **`uninstall` takes the installation and leaves the product.** In this repo `rm -rf ops/` is one
  keystroke from deleting POLARIS itself. CI clones the repo, uninstalls, and asserts `kit/` still
  builds a working kit.
- **Already-installed kits keep working.** They poll `main/ops/VERSION` and install from the tarball's
  `<root>/ops/install.sh` — both of which still resolve, because the installation committed at the
  root *is* that layout. They now serve the last **published** release rather than an unreleased tip,
  which makes the whole "bumped but never tagged" class of skew structurally impossible.

## 5.5.1 — 2026-07-14

**`update`'s success message could lie about what it had just cached.** Caught within minutes of
shipping 5.5.0, by running the thing rather than trusting it.

`refresh_machine_kit` announced *"every new install on this box now gets X"* — where X was **the
repo's** new version, not the version of the zip it had actually downloaded. `releases/latest` takes
about a minute to start serving a freshly tagged release, so an `update` run right after a release
caches the **previous** kit. A real run proved it: the repo went to 5.5.0, the message said
*"now gets 5.5.0"*, and the bytes on disk were 5.4.0. That is precisely the silent version skew this
whole feature exists to eliminate, reintroduced by the feature itself.

- **It now reads the version back out of the bytes it downloaded** and reports *that*. If the
  release hasn't propagated yet it says so plainly, names the version you actually got, and tells
  you to re-run — instead of quietly leaving the next repo on the old kit.
- **A download is validated before it becomes the cache.** `curl -f` rejects 4xx/5xx, but a
  truncated fetch is still a file, and a corrupt cached kit is worse than a stale one: every future
  install on the machine copies from it. Anything that isn't a real POLARIS kit is discarded and
  the existing cache is left exactly as it was.
- CI now asserts the report matches the bytes: whatever version `update` claims to have cached must
  be the version actually inside the cached zip.

## 5.5.0 — 2026-07-14

**"Can I just tell any chat to upgrade POLARIS?" Nearly — and the gap was the one that nearly
downgraded a live board this week.**

- **`update` now updates the MACHINE, not just the repo.** It re-caches the new kit into
  `~/.claude/skills/polaris-install/` (and refreshes the skill text, which rides along in the
  tarball it already downloaded — no second request). Before this, you could update ten repos and
  the machine would still hand the *old* kit to the eleventh, because the cache is what every
  future `"install POLARIS"` copies from. That is not hypothetical: a repo ended up with a 5.1.0
  zip in its root while the cache held 5.3.0, and following the install skill literally would have
  installed the older one over the newer. One `update`, in any repo, now makes the whole box
  current. `--repo-only` opts out. The zip is fetched from the new `zip:` key in `ops/VERSION` —
  the same pinned release URL the installer's own permission rule already names. Fails open: a
  cache problem never fails a repo update that already succeeded.
- **Fixed: `update` could execute garbage after overwriting itself.** `install.sh` replaces
  `ops/polaris` — the very file bash is still reading. Bash reads scripts lazily, in chunks, *by
  byte offset*, so a script replaced mid-run resumes at the old offset inside the new bytes:
  `syntax error near unexpected token`, or worse, half a command. This was latent from the day
  `update` was written and only ever survived because the old and new files happened to line up.
  It stopped lining up. `update` now re-execs from a temp copy before touching anything — the same
  guard `uninstall` has always had, for exactly the same reason.
- **`upgrade` is not `update`, and the kit now says so.** They are one letter apart and do
  unrelated jobs: `update` fetches a newer kit; `upgrade` migrates an old v3/v4 *board* to v5 and
  downloads nothing. Someone who says "upgrade POLARIS" almost always means `update` — and would
  get a wall of green ticks and stay on the old kit. `upgrade` now says so when run directly, and
  the CLI help, `CLAUDE.md` and the install skill spell out the difference.
- **Fixed: the install skill's trigger contradicted itself.** It said *"TRIGGER when the user asks
  to update or uninstall POLARIS"* and, in the same sentence, *"DO NOT TRIGGER inside a repo that
  already has a working `ops/polaris`"* — but update and uninstall **only ever happen** in such a
  repo. The file documenting update was instructed never to fire when update was possible. It now
  triggers on install/update/upgrade/uninstall/version anywhere, and stands down only for ordinary
  board work, which the project's own `polaris` skill governs.

Note: an existing kit updates itself using its OWN `update` code, so a repo on 5.4.0 or older will
not refresh the machine cache on the way to 5.5.0 — that lands from 5.5.0 onward. Run
`python polaris-v5.zip --claude-skill` once if you want the cache current immediately.

## 5.4.0 — 2026-07-14

**Installing POLARIS took four steps across three chats, and buried you in output doing it.** Run
the installer, read a wall of ✅ lines, open a *new* chat, say "You are INIT", answer ten questions
written in kit jargon, open *another* chat, say "You are the PLANNER", open *another* chat, say
"You are a BUILDER. Claim the top ready task and complete it end to end." A protocol for going fast
that took a quarter of an hour to switch on.

The centrepiece of this release is a deletion. **The "now start a new session" rule was never a
technical requirement** — it was repeated in seven files and it was wrong in all of them. The
PreToolUse write-guard only enforces ownership on `feat/*` branches, so it is a no-op for INIT and
PLANNER, which run on the base branch. `settings.json` — hooks and permissions — hot-reloads
mid-session. And `CLAUDE.md` never needed re-reading: it is a routing table, and an agent that
already knows its role can just read `ops/roles/INIT.md`. So the whole thing runs in one chat.

- **Say "install POLARIS" and you end up on a ready board.** The install continues straight into
  INIT, which interviews you and then chains into the PLANNER, which fills the board — one session,
  no handoffs. Chaining INIT → PLANNER is now the single sanctioned exception to "never act as two
  roles in one session": it happens once per repo, before any Builder exists, on the base branch,
  and writes zero feature code. Every other session stays strictly single-role.
- **Three questions, not ten.** INIT's survey already reads every package manifest, so it now
  *derives* what it used to interrogate you for: test/lint/typecheck/build from `package.json`
  scripts, Makefile targets, `pyproject.toml`, `Cargo.toml`, `go.mod`; base branch and remote from
  git. It asks only what a repo genuinely cannot answer — how you want to be spoken to, what you
  want to build first, and one batched confirmation (the commands it found · one machine or several
  · re-test every merge or once at the end · what's radioactive, pre-ticked from the survey).
  Suite duration, DoD extras, sprint capacity and past scars are gone from the interview: they are
  derivable, defaultable, or EVOLVE's job once there is real data. Someone who has just typed
  "install polaris" does not yet know their sprint capacity in points.
- **`start`.** Nobody should have to type "You are a BUILDER. Claim the top ready task and complete
  it end to end" to do the obvious thing. `start` (or `start building`, `go`, `let's build`,
  `polaris start`) means *take the next piece of work*: it becomes a BUILDER when tasks are queued
  and a PLANNER when the board is empty, so it always does the right thing instead of erroring. It
  fires only on a bare start phrase — "start the dev server" is an ordinary request, not a kickoff.
- **The installer stopped shouting.** Quiet is now the default: one line, and its last token is a
  routing contract (`POLARIS 5.4.0 installed · fresh` | `· live-board`). The full detail still
  exists, in `.polaris/install.log`, and `--verbose` puts it back on stdout. Failures always print
  in full. This mattered more than it looks: an agent relays whatever the installer prints, so a
  chatty installer *is* a chatty agent — and the role files now carry hard caps on what gets said
  (INIT: one report, ≤8 lines, at the very end; PLANNER: ≤6 under `voice: standard`; the install
  skill: an explicit list of things not to narrate).
- **A normal install now arms the machine** — it caches the kit into
  `~/.claude/skills/polaris-install/` and appends six pinned Bash rules to `permissions.allow`, so
  every install after the first is offline and prompt-free. This was `--claude-skill`, an opt-in
  flag, on the reasoning that writing outside the project must never be implicit. That reasoning
  was wrong in practice: a per-machine setup step nobody knows about is a step nobody runs, and its
  absence surfaced as a *denied install in a different repo weeks later*. You still explicitly
  approve the `python polaris-v5.zip` run that writes them, the curl URL is still pinned in full
  rather than wildcarded, and `--no-machine-setup` opts out. Net effect: on a machine that has
  never heard of POLARIS, name the source once — `install POLARIS from
  github.com/oscarsolis3301/POLARIS` — and never again, in any repo.
- **Fixed: the cached kit was re-copied on every install.** The `samefile` guard added in 5.3.0
  stops the archive truncating itself when run *from* the cache, but it never checked whether the
  cache was already identical — so arming reported "changed" forever. It now compares content.

## 5.3.0 — 2026-07-13

**"Install POLARIS" was getting denied, and it looked like a broken installer.** It was a blocked
one. The skill told the agent to `curl` the kit from a GitHub release and execute it — and Claude
Code's permission classifier refuses, by design, to fetch code from a source the user never named
themselves. Nothing was wrong with the zip, the URL, or `install.sh`. The install simply died on
that rung, in every fresh repo, every time.

The fix is to stop needing the download at all.

- **`--claude-skill` now caches the kit.** It writes `polaris-v5.zip` next to the skill in
  `~/.claude/skills/polaris-install/`. Installing into a repo becomes `cp` + `python
  polaris-v5.zip` — a local file, no network, nothing for the classifier to object to. (Re-running
  `--claude-skill` *from* the cached copy no longer truncates it — there's a `samefile` guard, and
  CI proves it.)
- **`--claude-skill` now pre-authorizes the commands.** Six Bash rules are appended to
  `permissions.allow` in `~/.claude/settings.json` — the `python polaris-v5.zip` run, the pinned
  release URL (in full; never a wildcard), and `ops/polaris`, whose `update` curls a tarball
  internally. A rule in your own settings *is* you naming the source, which is exactly what the
  classifier asks for. Existing settings are preserved — append-if-absent, written through a temp
  file so an interrupted run can't truncate it, and a `settings.json` that won't parse is left
  alone with the rules printed to paste. Opt out with `--no-permissions`.
- **The skill can no longer dead-end.** Its install section is an explicit ladder: zip in the repo
  root → cached kit → *ask the user to name the source, then* download. If a denial happens anyway
  it reports it and prescribes `--claude-skill` instead of hand-rolling an install around the
  guard.
- **Fixed: `releases/latest` served 5.1.0 while `main` advertised 5.2.0.** 5.2.0 was never tagged,
  so every installed kit nagged about an update the release URL couldn't actually deliver, and
  every fresh download got a version-old kit. This release carries the 5.2.0 work below it.

Net effect: `python polaris-v5.zip --claude-skill`, once per machine, and `"install POLARIS"` works
in any repo — offline, no download, no prompts.

## 5.2.0 — 2026-07-13

Two things a real 843-file brownfield install taught us: agents only had one register, and a fresh
install lied to the kit about its own state.

- **`voice:` — pick how agents talk to you.** A new `ops/CONVENTIONS.md` key: `standard` (plain,
  friendly English — the default) or `technical` (dense, terse, what every POLARIS agent sounded like
  until now). INIT asks it **first, alone, before the interview**, then runs the interview itself in
  that voice — so nobody is asked to choose between `paranoid` and `batch` before they've read a word
  of the docs; they're asked whether to re-run the tests after every merge or once at the end, and
  INIT maps the answer. Voice governs **only what an agent says to you** — reports, questions, `✅`
  and `⛔` lines. What gets written to disk (task frontmatter, contracts, MAP, SPRINT, RULES, commit
  messages, code) stays exactly as machine-terse as before, because agents read those. And voice
  changes wording, never content or behavior: a red suite is still reported red, and no gate softens.
  Existing boards need no migration — `update` never rewrites `CONVENTIONS.md`, so they get the
  `standard` default, and `polaris doctor` now prints the effective voice so the knob is findable.
- **Fixed: a fresh install was indistinguishable from a live board, so INIT refused to run.** The kit
  tested "has INIT run?" by asking whether `ops/board/` existed — but `install.sh` *created*
  `ops/board/`, shipping the six empty columns and their `.gitkeep`s. So on every fresh install the
  test was false: `CLAUDE.md`'s role dispatch never offered INIT, `INIT.md`'s precondition told the
  agent to refuse ("never re-initialize over a live board"), and a second `install.sh` run announced
  "live board detected" and sent you to `polaris upgrade`. Agents got through it only by overruling
  their own role file. **`ops/CONVENTIONS.md` is now the single "has INIT run?" test everywhere** —
  it is written by INIT and by nothing else, and it is the test `doctor` already used. The installer
  no longer ships `ops/board/` at all: `polaris init-board` creates it during INIT, so the old test
  is *true* again as well as unused. CI now asserts both (no board before INIT · the installer still
  routes a re-run to INIT), so the predicate cannot rot back.
- **INIT flags git-tracked build output** (`.next/`, `dist/`, `build/`, `*.tsbuildinfo`) during the
  survey. A Builder that runs the build in such a repo dirties hundreds of files it does not own and
  `polaris verify` rejects its handoff — day one, every time. INIT reports it and proposes the
  `git rm -r --cached` + `.gitignore` fix; the human runs it, because deleting files is stop-and-ask.

## 5.1.0 — 2026-07-13

Portable kit. POLARIS now moves between projects as a single zip with no `.git` attached.

- **`CLAUDE.md` is now a managed block** (`<!-- POLARIS:BEGIN -->` … `<!-- POLARIS:END -->`), and
  `update` replaces exactly that block. **This fixes a real bug:** installs used to bail with
  *"already carries POLARIS — left as is"*, so the protocol document froze at install time — every
  kit file was refreshable *except* the protocol itself, and no CLAUDE.md change could ever reach an
  installed repo. Put your own rules below the END marker; they survive every update. A legacy
  unmarked block is left alone rather than guessed at.
- **`polaris uninstall --yes`** — removes `ops/`, the managed block, the guard hook and the POLARIS
  gitignore lines, while keeping your own `CLAUDE.md` content and your other hooks. Refuses while
  work sits in `active/` or `review/`. Re-execs from a temp copy first, because it is about to
  delete the script bash is currently reading — and on Windows you cannot unlink an open file.
- **`--claude-skill`** — `python polaris-v5.zip --claude-skill` installs a user-level Claude Code
  skill, after which "install POLARIS" works in any repo and Claude fetches the release itself.
  The *project* skill can't do this: it only exists after POLARIS is installed.
- **CI on Linux, macOS and Windows** — the kit had never run outside one Windows box. The macOS job
  pins `/bin/bash` (3.2) and asserts the version, because GitHub's image puts a newer Homebrew bash
  first on `PATH` and a bare `bash` would silently test bash 5 and prove nothing. Exec bits are
  asserted against the mode *stored in the archive*, not the extracted file — Git Bash fakes
  `test -x` on Windows, so an extraction check would pass vacuously and let a dead kit ship.
- **Drag-and-run** — `polaris-v5.zip` is a Python zipapp (`__main__.py` at the archive root),
  so installing is one command with no unzip step: drop the zip in a project and run
  `python polaris-v5.zip`. It self-extracts to a temp dir, restores the exec bits the archive
  carries, and hands off to `ops/install.sh`. The target is resolved from your working
  directory, and it `git init`s only a directory you explicitly named.
  On Windows it locates Git Bash from git's own install root and probes it before use —
  `shutil.which("bash")` from native Python finds `System32\bash.exe`, which is WSL's launcher
  and dies instantly with no distro installed. That bug broke drag-and-run on every Windows box.
- **`ops/pack.py`** — builds `polaris-v5.zip` from `git ls-files`. Written in Python because
  Git Bash ships no `zip` and PowerShell's `Compress-Archive` cannot store unix permissions:
  three kit files are mode `100755` (`ops/polaris`, `ops/install.sh`,
  `ops/hooks/ownership-guard.sh`) and an archive that drops the exec bit delivers a dead kit.
  Bytes are normalised to LF, so an `autocrlf=true` checkout can't poison the archive.
  Reproducible — the same commit packs to the same bytes.
- **`ops/install.sh`** — zero-arg mode installs into the git repo the kit was unzipped inside.
  Naming a target explicitly `git init`s it if needed (greenfield); zero-arg mode never will,
  so unzipping on your Desktop can't turn the Desktop into a repo. Adds `polaris-v5/` to the
  target's `.gitignore`, so a leftover kit folder can't be committed.
- **`ops/VERSION` + `polaris version`** — every installed kit knows which POLARIS it runs
  (version, commit, build date) and what the latest is.
- **`polaris update`** — fetches the latest kit from the public channel and refreshes kit code
  only; board, RULES, CONVENTIONS, MAP and SPRINT are untouched. Manual and explicit: POLARIS
  never updates itself under a running sprint.
- **Update notices** — the network check is throttled to once a day; the notice prints on every
  command until you act on it. Fails open: offline, no curl, or a bad response → silent.
  Never runs inside the write-guard, which fires on every edit.
- **`polaris doctor`** — warns when `polaris-v5.zip` lags `HEAD`. This is the exact rot that
  left the previous zip shipping pre-CRLF-fix code.

## 5.0.0

POLARIS v5 protocol: `RULES.tsv` policy engine (danger zones + content guards), `drift`
board-hygiene audit, per-point cycle calibration in `metrics`, dashboard points/drift rails.
