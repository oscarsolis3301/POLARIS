# Sprint 19 — Stay on the request (6.9.0) (2026-10-27–)

## T-192 — "A run stays on its request — triage counts only the tasks you name, records the run's plan, and an untagged leftover counts as someone else's work"
points 3 · risk normal · landed b716747 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/lib/handover.sh, kit/ops/lib/observe.sh, kit/ops/polaris, ops/tests/request-scope.cmd, ops/tests/request-scope.expected

### Why
The owner asked for UI work and the agent ran FIX-1, an old cleanup task, first. Nothing tied the run
to the request: `triage` and `next` read the whole board, and a ready task without a `plan:` tag never
counted as "another run's work". This task closes the CLI half of that gap (ops/contracts/stay-on-request.md
§ 1-2):

1. `triage <ID…>` (`cmd_triage`, observe.sh; dispatch `triage) cmd_triage "$@";;` plus one help line in
   kit/ops/polaris): with IDs, only the named tasks count toward the lane. No IDs → byte-identical.
2. With IDs and a session id, triage writes the first named task's `plan:` to
   `.polaris/handover/<sid>/plan`, overwriting — the request defines the run's scope at the moment the
   task is authored, not at the first claim.
3. `next_claimable` (handover.sh ~:70): under `drain: plan` with a recorded session plan, a ready task
   whose `plan:` is EMPTY or different is foreign. So after the request's task lands, `next` says
   `finish` and names the leftover; the Stop hook never hops into it.

No new top-level function (api-kit.expected stays as it is) — inline the ID loop.

### Acceptance
- [ ] New hermetic golden `request-scope` (contract § Executable check, first bullet) passes and was seen failing once (sabotage, restore).
- [ ] `triage` with no arguments: triage-lane golden byte-identical.
- [ ] handover-route golden still green (extend it only if a row's meaning changed; say which in Notes).
- [ ] The handover drill in kit/ops/lib/selftest/board.sh still holds under the new foreign rule — run `bash kit/ops/polaris doctor --selftest --only handover` ONCE via `bg run` before handoff and paste the verdict line in Notes (not in verify:; it is minutes).

## T-193 — "A leftover task no longer blocks \"done\" — drain defaults to plan in code, and release can park a ready task back in the backlog"
points 3 · risk normal · landed fb32bee (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/MANUAL.md, kit/ops/lib/builder.sh, kit/ops/lib/observe.sh, kit/ops/lib/selftest/policy.sh, kit/ops/polaris, ops/tests/drain-default.cmd, ops/tests/drain-default.expected

### Why
KEYS.tsv says `drain` defaults to `plan`, but `finish` and doctor's knob line treat an unset `drain` as
`queue` (observe.sh ~:2439 and ~:573). So one leftover ready task blocks "done" and pushes the agent to
run it. And the protocol tells an agent to park a leftover that collides with the request's files with
`release <ID> --to backlog`, which today only accepts `ready|blocked` and only from active/.

1. `${dr:-queue}` → `${dr:-plan}` in both places; an unknown value is treated as plan (a caveat, not a
   pending item). A repo that set `drain: queue` keeps it.
2. `release <ID> --to backlog -m "…"` (contract § 4): also works on an UNCLAIMED task in ready/ — moves
   it to backlog/, one board commit, no lock or worktree touched. From active/ it behaves like `--to ready`
   but lands in backlog/. Help text in kit/ops/polaris and the recipe in kit/ops/MANUAL.md say so.
3. The finish drill in selftest/policy.sh (~:680) sets `drain: queue` explicitly for its queue half, so
   both modes stay tested; remote.sh's knob-warning drill updated only if its pinned text moved.

### Acceptance
- [ ] New hermetic golden `drain-default` (contract § Executable check, second bullet) passes and was seen failing once.
- [ ] No `dr:-queue` left in observe.sh.
- [ ] No markdown heading added/renamed in MANUAL.md (api-kit unchanged).
- [ ] `bash kit/ops/polaris doctor --selftest --only finish,remote` run ONCE via `bg run` before handoff; verdict pasted in Notes.

## T-194 — "The rulebook says it plainly — a request always gets its own task, a leftover is parked and named, never run first"
points 2 · risk normal · landed 3b53b2b (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/CLAUDE.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md

### Why
The FIX-1 incident started in the prose: SOLO says to author the request's task only "if one already
sits in ready/", so an old cleanup task took the request's place. This task changes the wording in the
four files every run reads (ops/contracts/stay-on-request.md § 5):

- kit/CLAUDE.md, "Unprompted work request" bullet: the request ALWAYS authors its own task with a
  `plan:` name, runs `triage <ID>`, and claims that ID; a ready task is never picked up just because it
  is there. Keep the file ≤ 10054 bytes (trim inside the same bullet; every byte is paid 6-8× a run).
- SOLO.md § Entry and step 1: always author; `triage <ID>`; `claim <ID>`; a leftover that shares files
  with the request's task is parked with `release <ID> --to backlog -m "parked: not part of <plan>"` and
  named in ONE line of the close.
- PLANNER.md: cleanup or test-debt work never becomes a `depends_on` of requested work — it goes to
  ops/board/backlog/IDEAS.md; request tasks always carry `plan:`.
- CONDUCTOR.md (~:143, ~:278-279): an unset `drain` means `plan`.

No heading added, renamed or removed (api-kit.expected pins headings). `triage <ID>` and
`release --to backlog` are built by T-192/T-193 in the same release.

### Acceptance
- [ ] Every verify line green; kit/CLAUDE.md within budget.
- [ ] SOLO's step 1 no longer has an "if one already sits in ready/" escape.
- [ ] The wording is plain English a first-time reader follows (voice: standard).

## T-195 — "Plan mode stops asking about PowerShell reads — the read-only approver learns PowerShell, deny by default"
points 5 · risk normal · landed b8ede0b (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/.claude/settings.json, kit/ops/hooks/readonly-allow.sh, ops/tests/api-kit.expected, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected

### Why
On Windows PowerShell is the main shell, but the read-only approver only looks at Bash
(readonly-allow.sh ~:421 exits unless `tool_name` is `Bash`; settings.json wires it with
`"matcher": "Bash"`). So every PowerShell read in plan mode — `git -C x log`, `Get-ChildItem`,
`Get-Content x | Select-String y` — stops and asks the owner. This task (ops/contracts/readonly-powershell.md):

1. Accept `tool_name` `PowerShell` and run a separate, pure-bash, deny-by-default parser: an allowed
   cmdlet/alias table, `git` through the existing `git_ok`, `bash ops/polaris` through `polaris_ok`,
   script blocks scanned recursively, `;`/`|` splitting, `-ErrorAction`/`2>$null` fine; every write,
   invoke, call operator, subexpression, here-string, assignment and ForEach-Object refused.
2. `--test-ps '<cmd>'` mirrors `--test` so the golden can drive it.
3. `polaris_ok` gains `depth` (T-197's new read-only command, same release).
4. settings.json matcher → `Bash|PowerShell`. install.sh already replaces our hook entries wholesale,
   so `update` carries it everywhere — do not touch install.sh.

You are the api-kit.expected owner this wave (T-197 waits for you): add exactly the new function lines
from this file, diffed by content (`… | diff - ops/tests/api-kit.expected`), and STOP if any other hunk
appears.

### Acceptance
- [ ] Existing Bash battery lines byte-identical; new PowerShell allow + ask cases per the contract, including the real `git -C … log --oneline -5; Get-ChildItem ops | Select-Object Name` line, plus one JSON-layer case each way.
- [ ] The golden was seen failing once (sabotage one refuse case to allow, see red, restore).
- [ ] readonly-allow stays within its bench budget.

## T-196 — "Tev1 spike — does Together AI's local decision model beat our rules and the plain majority answer on our own questions?"
points 3 · risk normal · landed a272aa6 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: docs/spikes/tev1.md

### Why
Tev1 is Together AI's experimental decision model; Ollama serves it from 0.35 on, on the same
`/v1/systemone` protocol Laya's server speaks. Laya scored no better than always giving the most common
answer on our questions (docs/spikes/laya-jev-rea.md). Whether Tev1 does better is unmeasured, so this
is a spike, not an integration: its only repo output is docs/spikes/tev1.md with the headings
ops/contracts/tev1.md pins.

Order of work — do everything that needs no owner step FIRST:
1. Build the NEW test-depth label set (~40 past kit commits) read-only from `git log --name-only`,
   labelling each by ops/contracts/test-depth.md § 2's rule table (the "rules" answer) and then by
   judgement; save `~/.claude/polaris/laya/data/test-depth.jsonl` in the same state/question shape as
   the T-181/T-190 sets.
2. Write the replay script `~/.claude/polaris/laya/tev1-replay.py` (outside the repo): replays all three
   sets against `http://127.0.0.1:11434/v1/systemone`, records answer, confidence, latency; computes
   accuracy vs majority baseline and vs rules on a held-out split, confidence separation, p50/p95.
3. Check the machine: `ollama --version`, whether its server runs, which models are pulled.
4. 🚩 OWNER GATE: Ollama ≥ 0.35 and both checkpoints pulled are the owner's step. If missing, STOP and
   hand back (`release T-196 --to blocked -m "…"`) with ONE paste-ready block (one command per line, no
   `&&`, no placeholders) and the sizes (tev1:0.8b 812 MB, tev1 4.5 GB). The conductor relays it and
   re-kicks you; then resume at step 5.
5. Run the replay for both checkpoints, measure VRAM with the 4B sharing the 8 GB, write tev1.md.

### Acceptance
- [ ] The eight pinned headings exist; every accuracy figure sits beside its majority baseline, and on the test-depth set beside the rules.
- [ ] Go/no-go stated with the held-out split and the margin; a blocked update or pull is a valid recorded no-go if the owner declines.
- [ ] Nothing in this repo changes except docs/spikes/tev1.md; label sets, script and logs live under ~/.claude/polaris/laya/.

## T-197 — "POLARIS can tell how much testing a change needs — none for text, look for styling, scoped or full for code — and says why"
points 5 · risk normal · landed 3850d8d (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/KEYS.tsv, kit/ops/lib/core.sh, kit/ops/lib/observe.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/test-depth.cmd, ops/tests/test-depth.expected

### Why
A docs edit or a one-line CSS change pays the same 26-minute suite as a code change. This task builds
the decision only — nothing calls it yet (T-198 wires it into qa and land). Per
ops/contracts/test-depth.md § 1-3:

1. KEYS.tsv gains `test_skip` (default `*.md docs/** *.txt LICENSE*`) and `test_look` (default
   `*.css *.scss *.less *.svg *.png *.jpg *.jpeg *.gif *.webp *.ico`), since 6.9.0. The defaults live in
   code (`cfg test_skip "<default>"`), never written into a repo's CONVENTIONS.
2. `depth_for [<taskfile>…] < paths` in core.sh next to `tier_for`: pure, ONE line `<depth><TAB><why>`,
   the six-row rule table with the pinned why strings. `test_depth:` can only raise depth.
3. `polaris depth [<ID>]` (`cmd_depth` in observe.sh; dispatch + help line in kit/ops/polaris): read-only,
   line 1 the depth word, then `   why:` and `   paths:` note lines.

You own api-kit.expected after T-195: add exactly `depth_for`, `cmd_depth` and the two KEYS rows,
diffed by content; STOP on any other hunk.

### Acceptance
- [ ] Hermetic golden `test-depth` covers every row of the contract's table plus the `test_skip: -` and ignored `test_depth: none` cases, and `polaris depth` on a fixture branch; seen failing once.
- [ ] depth_for writes nothing and calls no git (pure — input on stdin, task files as args).
- [ ] KEYS rows carry an honest absent-cost sentence in plain English.

## T-198 — "Text and styling changes stop paying the whole test suite — qa and the express lane test to the depth the change needs, and log every decision"
points 5 · risk normal · landed e27d8b6 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/lib/core.sh, kit/ops/lib/integrate.sh, kit/ops/lib/observe.sh, kit/ops/lib/selftest/history.sh, kit/ops/lib/selftest/policy.sh, ops/tests/api-kit.expected, ops/tests/depth-stamp.cmd, ops/tests/depth-stamp.expected

### Why
`finish` always runs `qa`, and qa runs the whole suite unless the last green run was at this exact
commit — so a docs-only commit (EVOLVE's, a sprint report) or a CSS tweak re-pays 26 minutes. This task
wires T-197's `depth_for` into the two callers (ops/contracts/test-depth.md § 4-5):

1. `cmd_qa` (observe.sh ~:2240-2306) and `land --express` (integrate.sh ~:659-711) ask depth_for.
   `none`/`look` run no suite key but every board check qa makes today; `scoped`/`full` unchanged.
   `qa --full`/`--force` and an unbounded change set stay full. Task files come from the `[<ID>]`
   subject scan (§ 4). `look` leaves the visual capture + `--saw` gate at handoff exactly as it is.
2. The stamp's third field records the depth word.
3. `surface_change_set` (core.sh ~:310) and `suite_stamp_carry` (integrate.sh ~:484) drop test_skip
   paths, so a green stamp carries across a docs-only commit.
4. Plan § E: every qa / land --express decision, and every `finish`, appends one row to
   `.polaris/decisions.ndjson` after the run (§ 5 shape). At most one new helper function for it.

CI and `pack.py --dogfood` still run the full serial suite and never read the stamp — untouched.
Drills that pin stamp format/behaviour (selftest history.sh ~:203-222, policy.sh ~:99-167, fast.sh
~:398-415) move only if their pinned meaning changed; say which in Notes. You own api-kit.expected
after T-197: add only your helper's line; STOP on any other hunk.

### Acceptance
- [ ] Hermetic golden `depth-stamp`: docs-only commit after a green stamp → no suite key runs and the stamp carries; CSS-only → stamp field `look`; one decisions.ndjson row per qa with every § 5 key. Seen failing once.
- [ ] qa-stamp golden green (re-pinned only where the depth line legitimately appears — content diff, STOP on anything else).
- [ ] A change with no test_skip/test_look path gets a byte-identical verdict to 6.8.0.
- [ ] `bash kit/ops/polaris doctor --selftest --only qa,express,surfaces,finish` run ONCE via `bg run` + chunked `bg wait` before handoff; verdict pasted in Notes.

## T-199 — "See where the time goes — metrics shows suite minutes skipped and the build / land / suite / finish split, and builders stop being pointed at the full suite"
points 3 · risk normal · landed ded70b5 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/lib/builder.sh, kit/ops/lib/observe.sh, ops/tests/api-kit.expected, ops/tests/depth-metrics.cmd, ops/tests/depth-metrics.expected

### Why
Two leftovers from the test-depth work (ops/contracts/test-depth.md § 6-7):

1. `polaris metrics` gains two lines, appended last: suite minutes skipped this sprint (by depth) and
   the per-run wall-clock split build / land / suite / finish, read from `.polaris/decisions.ndjson`
   (T-198) and EVENTS.ndjson, sprint-scoped by SPRINT.md line 1's `dates:`. With no log both lines still
   print (`n/a`, `-`). This is how the owner sees whether the sprint actually made runs faster.
2. `pack` (builder.sh ~:835) stops falling back to `test:` when `test_fast:` is unset — it was pointing
   builders at the 26-minute suite. It prints the pinned "(none set — …)" line instead.

You own api-kit.expected after T-198: no new function is expected; if you add one, add only its line,
diffed by content, and STOP on any other hunk.

### Acceptance
- [ ] Hermetic golden `depth-metrics` with a seeded decisions.ndjson pins both § 6 lines (with data, and with no log); seen failing once.
- [ ] Existing metrics output above the new lines is unchanged.
- [ ] pack-visual golden green (re-pin only the fast-tier line if it shows there — content diff).

## T-200 — "The rulebook stops paying the suite twice — integrator and conductor run one stamped check, builders test what they touched, and the task template documents test_depth and plan"
points 3 · risk normal · landed 0357fac (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/PROTOCOL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/templates/TASK.md

### Why
The suite is paid twice in three places, and the prose is why (ops/contracts/test-depth.md § 8):

- INTEGRATOR.md ~:30 hand-runs the suite, which writes no stamp, so the next `qa` pays again → "run
  `bash ops/polaris qa`" (stamped, depth-aware).
- CONDUCTOR.md runs qa at 6.5 AND ~:306 (EVOLVE's commit moves HEAD in between) → ONE `qa` at the end
  of the run (a docs-only EVOLVE commit now carries the stamp anyway).
- BUILDER.md ~:51: write tests for the acceptance criteria the change touches, not a new suite.
- PLANNER.md ~:36: `verify:` lines must take seconds — never `doctor --selftest` (the full suite runs once
  at the wave gate); replace the "scope it with `--only`" advice.
- PROTOCOL.md testing-tiers table gains a depth row (none / look / scoped / full and when each applies).
- templates/TASK.md documents `test_depth:` (raise-only, `full` is the only honoured value) and `plan:`
  (required on every task a request authors).

No heading added, renamed or removed in any of these files (api-kit.expected pins headings).
CONDUCTOR.md and PLANNER.md were last edited by T-194 — build on its wording, do not undo it.

### Acceptance
- [ ] Every verify line green; PLANNER.md says verify: lines never carry `doctor --selftest`.
- [ ] Plain English a first-time reader follows (voice: standard).

## T-201 — "Release prep 6.9.0 — the version number and one changelog entry for staying on the request, test depth, PowerShell reads and the Tev1 verdict"
points 1 · risk normal · landed 69a3607 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
Every release lands in four places at once (ops/VERSION via the kit, CHANGELOG, git tag, published
release); this task does the two file halves — the tag, the publish and the dogfood are the owner's 🚩
step after the wave gate. Bump kit/ops/VERSION to 6.9.0 (URLs unchanged) and add ONE `## 6.9.0 — <date>`
CHANGELOG entry in plain English: a run stays on its request (FIX-1 can't hijack it), text and styling
changes skip the suite, PowerShell reads stop prompting in plan mode, and the Tev1 spike's verdict in a
sentence. Sprint 19 (Laya) moves to 6.10.0.

### Acceptance
- [ ] VERSION and CHANGELOG agree on 6.9.0; nothing else changes.

## T-202 — "A small change in a never-green repo checks only what this run changed: the change set is bounded to the commits the run landed"
points 5 · risk normal · landed 2750616 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/lib/core.sh, kit/ops/lib/observe.sh, ops/tests/api-kit.expected, ops/tests/change-bound.cmd, ops/tests/change-bound.expected

### Why
Implements contract change-sized section 1. With no earlier green run, surface_change_set gives up and every finish pays the full suite, even for a docs edit. Instead, union the files changed by this run's landed plan tasks (landed_sha) and set SURFACE_BOUND=run, so depth_for decides on the real change and cmd_qa's bounded-and-empty branch stamps scope none. No plan recorded or nothing landed stays unbounded exactly as today. Owns api-kit.expected first in the chain (T-202, T-203, T-204, T-205).

### Acceptance
- [ ] every verify: line passes

## T-203 — "A component change runs only the tests that import it: the test runner picks the related tests, one decision shared by depth, qa and land"
points 5 · risk normal · landed fbc63e3 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/KEYS.tsv, kit/ops/lib/core.sh, kit/ops/lib/integrate.sh, kit/ops/lib/observe.sh, kit/ops/lib/surfaces.sh, ops/tests/api-kit.expected, ops/tests/related-tests.cmd, ops/tests/related-tests.expected

### Why
Implements contract change-sized sections 2-4. Add related_cmds (vitest related --run / jest --findRelatedTests via the package's own node_modules/.bin, all-or-nothing, nearest tracked package.json) and the single test_select_for decision (SURFACES rows first, then related), wired through depth_for, cmd_qa's test key and land --express. New key test_related: (unset = on, - = off). Python repos keep today's behavior. If keys-drift.expected or cli-help need a one-line move, say so in Notes and use grant.

### Acceptance
- [ ] every verify: line passes

## T-204 — "A narrowed run skips the slow live acceptance tier and says why: uat deferred at scoped, one depth line on every run"
points 3 · risk normal · landed ce3416a (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/observe.sh, ops/tests/api-kit.expected, ops/tests/depth-uat.cmd, ops/tests/depth-uat.expected

### Why
Implements contract change-sized section 5. At scoped depth qa and land --express skip the uat key and print the one pinned deferral line; every run prints one depth line, and at full it names what forced it and the last measured full time from .polaris/last-suite-seconds, so the owner sees why a run is slow before it starts. The golden uses a fake vitest that echoes its argv.

### Acceptance
- [ ] every verify: line passes

## T-205 — "Ask why a commit would be slow without running anything: polaris depth --commit <sha>"
points 3 · risk normal · landed 6e6bc54 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/hooks/readonly-allow.sh, kit/ops/lib/observe.sh, kit/ops/polaris, ops/tests/cli-help.expected, ops/tests/depth-commit.cmd, ops/tests/depth-commit.expected, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected

### Why
Implements contract change-sized section 6. cmd_depth gains --commit <sha>: read-only, prints depth, why and the exact commands qa would run (and the uat it would skip). Added to help, dispatch and the readonly-allow polaris_ok list, so it needs no permission prompt. The conductor runs it on real history (job cb0a1ea) at release time.

### Acceptance
- [ ] every verify: line passes

## T-206 — "Tell the roles the new truth: SOLO, the depth table and the task template drop the old full-suite-after-self-land wording"
points 2 · risk normal · landed 0dd23e4 (2026-10-27) · claimed 2026-10-27 → done 2026-10-27
files touched: kit/ops/PROTOCOL.md, kit/ops/roles/SOLO.md, kit/ops/templates/TASK.md

### Why
Prose for contract change-sized. SOLO.md steps 4/5/7 no longer say a self-land finish pays the full suite (it now sizes to the run's own change); the PROTOCOL.md depth table says scoped means related tests and uat deferred; TASK.md notes test_depth: full is the way to force everything. No heading added, renamed or removed. Disjoint from the code chain, so it can run in parallel.

### Acceptance
- [ ] every verify: line passes

## T-207 — "Write the release note: the 6.9.0 changelog entry gains the change-sized checks (no version bump)"
points 1 · risk normal · landed 2a02db3 (2026-10-27) · claimed 2026-10-27
files touched: CHANGELOG.md

### Why
Extend the EXISTING ## 6.9.0 entry in CHANGELOG.md (6.9.0 was never tagged, so this folds in): run-scoped change set, related tests, uat deferral plus the depth line, polaris depth --commit. Do NOT bump kit/ops/VERSION and do not add a second 6.9.0 heading. Tag, dogfood, publish and product-repo updates are the conductor's release ritual, not this task.

### Acceptance
- [ ] every verify: line passes
