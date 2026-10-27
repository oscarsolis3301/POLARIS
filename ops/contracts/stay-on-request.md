# CONTRACT: stay-on-request — a run works the request, never a leftover            (v1 — 2026-10-27)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-d-like-to-improve-playful-gosling.md` § A (owner-approved
2026-10-27) · tasks T-192 (A1 scope + triage IDs), T-193 (A2 drain default + park), T-194 (A3 prose)
· `plan: stay-on-request`.

## Purpose
Separate "the work this run was asked for" from "whatever already sits in ready/". The FIX-1
incident: a UI request ran an old cleanup task first because `triage`, `next`, a bare `claim` and
`finish` all read the whole board and nothing tied the run to the request.

## 1. `triage <ID…>` (T-192 — `cmd_triage`, kit/ops/lib/observe.sh; dispatch kit/ops/polaris)
```
bash ops/polaris triage                 # unchanged, byte-identical: every ready/ + active/ task counts
bash ops/polaris triage T-7 [T-8 …]     # ONLY the named tasks count toward the lane
```
- With IDs, the counting loop iterates the named IDs instead of `ready/*.md active/*.md`. Each ID must
  sit in ready/ or active/; otherwise `die "triage: <ID> is not in ready/ or active/"` (rc 1, nothing
  on stdout). Every downstream rule (points, risk, express, publish, RULES, the ≤4/≤6/≤3 budget,
  "already active" lane) is evaluated over the named set only.
- Line 1 stays exactly one word `solo|express|full`; reasons stay on `   ` note lines.
- **Scope recording.** With IDs AND `CLAUDE_CODE_SESSION_ID` set, triage writes the FIRST named task's
  `plan:` value (may be empty) to `$PRIMARY/.polaris/handover/$CLAUDE_CODE_SESSION_ID/plan`,
  OVERWRITING any previous value — the request defines the run. Best-effort (`|| true`), mkdir -p.
  No IDs → the file is never touched. `claim`'s existing first-claim write (builder.sh, only when the
  file is absent) stays as the fallback, unchanged.
- No new top-level function (api-kit.expected is surface-frozen for this task): inline the ID loop.

## 2. Foreign = missing or different plan (T-192 — `next_claimable`, kit/ops/lib/handover.sh)
Under `drain: plan` AND a recorded session plan (the `plan` file exists and is non-empty), a ready
task is FOREIGN when its `plan:` is empty OR differs from the session plan. Today only "set and
different" is foreign. No plan file, or an empty one → nothing is foreign (a bare `start` on an
untagged board keeps taking the top task, exactly as today). Foreign tasks keep landing in
`NX_FOREIGN`, so `next` says `finish` with the existing note line `foreign queued (drain: plan): <IDs>`
and the Stop hook never hops into them.

## 3. `drain` defaults to `plan` in code (T-193 — kit/ops/lib/observe.sh)
- `cmd_finish`: `dr="${dr:-queue}"` → `dr="${dr:-plan}"`; the unknown-value branch's text says
  "treating it as plan" and calls `fin_caveat`, not `fin_pending`.
- doctor's knob line (today `drain: ${dr:-queue}`) → `${dr:-plan}`.
- `handover.sh` already reads `cfg drain plan` — untouched. KEYS.tsv already says `plan` — untouched.
- A repo that set `drain: queue` or `drain: backlog` keeps it, byte-identical behaviour.

## 4. Parking a leftover: `release <ID> --to backlog` (T-193 — `cmd_release`, kit/ops/lib/builder.sh)
```
bash ops/polaris release <ID> --to backlog -m "parked: not part of <plan>"
```
- `--to` accepts `ready|blocked|backlog`; the usage/die text names all three.
- `--to backlog` also accepts a task sitting UNCLAIMED in ready/ (no lock, no worktree): it moves
  `ready/<ID>.md → backlog/<ID>.md`, sets `status: backlog` (owner stays null), appends
  `- ⛔ released by <who>: <msg>` to the file, `evt release <ID> "→ backlog: <msg>"`, ONE
  `board_commit "chore(board): release <ID> → backlog"`, `sync_board`, and touches no lock or worktree.
  From active/ it behaves exactly like `--to ready` (worktree + lock handling) but lands in backlog/.
- A task with a live lock held by another session is refused by the existing paths (unchanged).

## 5. Prose (T-194)
- `kit/CLAUDE.md` § ROLE DISPATCH "Unprompted work request" bullet: a work request ALWAYS authors its
  own task with a `plan:` slug, then `triage <ID>`, then claims that ID; a task already in ready/ is
  never picked up because it is there. kit/CLAUDE.md stays ≤ 10054 bytes (the T-189 budget).
- `kit/ops/roles/SOLO.md` § Entry + step 1: always author the request's task (drop "if none sits in
  ready/"), tag `plan:`, `triage <ID>`, `claim <ID>`. A leftover whose files_owned overlaps the
  request's task is parked with § 4 and named in ONE line of the close; never run first.
- `kit/ops/roles/PLANNER.md`: cleanup / test-debt work never becomes a `depends_on` of requested work;
  it goes to `ops/board/backlog/IDEAS.md`. Request tasks always carry `plan:`.
- `kit/ops/roles/CONDUCTOR.md`: the drain wording (today ~:143 and ~:278-279) says unset = `plan`.
- No markdown heading is added, renamed or removed in any of these files (api-kit.expected pins
  headings and is surface-frozen for T-194).

## Executable check
- `ops/tests/request-scope.cmd/.expected` (T-192, hermetic fixture repo, the triage-lane pattern):
  a leftover `FIX-1` (no `plan:`) and a request task `T-2` (`plan: req`) both in ready/ → `triage T-2`
  line 1 + its note count reflect ONLY T-2; `triage FIX-1 T-2`-style unknown ID → rc 1; with a session
  id set, after `triage T-2` the plan file reads `req`; after T-2 is done, `next` line 1 is `finish`
  and a note line names `FIX-1`.
- `ops/tests/drain-default.cmd/.expected` (T-193, hermetic): no `drain:` key, one leftover in ready/,
  everything else green → `finish` rc 0 with the caveat line; `release FIX-1 --to backlog -m …` from
  ready/ moves it to backlog/ with status backlog and one board commit.

## Invariants
- `triage` with no arguments is byte-identical to today (golden `triage-lane` unchanged).
- No session plan recorded ⇒ `next` behaves exactly as today.
- Drills that assumed unset drain = queue (kit/ops/lib/selftest/policy.sh finish drill ~:680) are
  updated to SET `drain: queue` explicitly for the queue half, so they still test both modes.

## Changelog
- v1 2026-10-27: created for T-192, T-193, T-194 (plan stay-on-request).
