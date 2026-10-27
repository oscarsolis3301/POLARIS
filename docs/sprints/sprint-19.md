# Sprint 19 — Stay on the request (6.9.0) (2026-10-27–)

## T-192 — "A run stays on its request — triage counts only the tasks you name, records the run's plan, and an untagged leftover counts as someone else's work"
points 3 · risk normal · landed b716747 (2026-10-27) · claimed 2026-10-27
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

## T-194 — "The rulebook says it plainly — a request always gets its own task, a leftover is parked and named, never run first"
points 2 · risk normal · landed 3b53b2b (2026-10-27) · claimed 2026-10-27
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
points 5 · risk normal · landed b8ede0b (2026-10-27) · claimed 2026-10-27
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
