# CONTRACT: role-handover            (v1 — 2026-09-01)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/v2.md` WS7 + WS8 (plan slug `cant-eat-itself`, 6.2.0). Tasks: T-109 (`lib/handover.sh`) ·
T-110 (`hooks/handover-hook.sh` + settings entries + readonly-allow) · T-097 (`evt()` writes `last-event`) ·
T-098 (`claim` records task/plan; queue notice) · T-100 (`finish` stamps `finished`; sweep prunes; fleet
kickoff) · T-101 (dispatch + usage + loader, W2 api-kit owner) · T-096 (PROTOCOL § LANES paragraph +
§ VOICE rule 3; output-style rule 3 + the "hop is not an ending" line; `handover` KEYS row) · T-107 (role
prose, Invariant 5, the approved-plan dispatch row) · T-111 (drill `handover` + goldens `handover-route`,
`handover-stop`, `cli-help-parity`) · T-104 (spine label). Companion: `run-finish.md` v3.

## Purpose
A session ends with its task (Invariant 5), so every next role needs a human kickoff. Wanted: one chat
finishes a task, sheds that task's context, and continues as the next role by itself — and an approved plan
is the go, in the same chat. Two harness facts bound the design: nothing can fire a compaction on demand;
a `Stop` hook may refuse the stop ONCE per completion with `decision: block` + `reason` (capped at 8 in a
row, then `stop_hook_active`), and a `SessionStart` hook with matcher `compact|resume` injects stdout after
every compaction. So: **the loop lives in role prose** (every role runs `bash ops/polaris next` at each
boundary and follows line 1), the Stop hook is a backstop for a model that stopped anyway, and the anchor
hook re-enters a compacted session from the board. The CONDUCTOR (a fresh subagent per role) stays the
recommended shape when subagents exist.

## Interface — Invariant 5 (kit/CLAUDE.md:85-86, T-107; byte-exact)
`5. **One task per context, one role per context.** A session hops roles only at a boundary the board proves (a completion event), into the role \`polaris next\` names, with the hop logged; compaction is the context reset and the anchor hook the re-entry. Sessions are disposable; the board is the memory.`
CLAUDE.md:45-47 bullet becomes: two roles never mix inside one CONTEXT; a hop at a board-proven boundary is
not a second role, it is the next context; INIT → PLANNER and the CONDUCTOR are unchanged.
`kit/.claude/skills/polaris/SKILL.md:5` mirrors ("Sessions are single-role per context; the board is the
memory and `polaris next` names the next context's role"). PROTOCOL § LANES (T-096): ONE bold paragraph
extending the precedent chain — SOLO → `land --express` → `landing: self` → handover: each collapses
SESSIONS, never CHECKS; a hop consumes exactly one completion event.

## Interface — `polaris next [--do|--brief]` (`kit/ops/lib/handover.sh`, T-109; ≤300 lines; 8 fns)
Fns, EXACTLY: `cmd_next` · `next_dir` · `next_route` · `next_landable` · `next_claimable` · `next_promote` ·
`next_budget` · `next_brief`. No others at any depth.
- Output: line 1 = `<verb>[ <ID>]`, verb ∈ {`resume`, `build`, `integrate`, `promote`, `wait`, `stop`, `finish`};
  every other line starts with three spaces (the `triage` shape); rc 0 always (rc 1 only on a usage error).
  `next` writes NOTHING (read-only like `triage`); `--do` writes the board, never the state dir.
- "my sid" = `$CLAUDE_CODE_SESSION_ID` (unset ⇒ `-`, which matches no lock). State dir = `next_dir` =
  `$PRIMARY/.polaris/handover/<sid>/`.
### Decision table — first match wins (`next_route`)
| # | condition (all read from disk, one pass) | line 1 | note lines |
|---|---|---|---|
| 0 | a lock in `$LOCKS/<ID>/meta` whose line 4 == my sid AND `<ID>` is in `active/` | `resume <ID>` | `   mid-task: your own lock is live — finish or release before anything else` |
| 1 | `review/` holds a landable task (`risk` ≠ `high`, `approved:` empty or absent) AND the lease `$LOCKS/.int-lease` is absent, stale (worktree-liveness steal predicate) or mine (`pid` == `$$` or `who` == my WHO) — under BOTH landing modes | `integrate` | `   review/: <IDs>` (+ `   risk: high, human approves: <IDs>` when any) |
| 2 | (`hops` ≥ `run_max_tasks`, cap ≠ 0) OR (minutes since max(`started`, `prompted-at`) ≥ `run_max_minutes`, cap ≠ 0), AND row 3 or 4 would otherwise fire | `stop` | `   budget: <cap> reached — N tasks left on the board; say start to continue` (the conductor's verbatim budget line; `<cap>` = `run_max_tasks` or `run_max_minutes`; N = ready + eligible backlog count) |
| 3 | `ready/` has a task that is unlocked (no `$LOCKS/<ID>`), not in `avoid`, and not foreign — foreign = `drain: plan` AND task `plan:` set AND ≠ the plan in `<dir>/plan` (a missing `plan` file ⇒ nothing is foreign) — highest `wsjf` first, ties by ID | `build <ID>` | `   <title> (<pts> pts, wsjf <w>)` |
| 4 | `backlog/` has a task passing the FULL ready gate: every `depends_on` in `done/` · `contract:` file exists · `points` ∉ {8, 13, ''} · no `ask` scope without a covering `approved:` entry (`rules_gate`) · `files_owned` disjoint from every task in `ready/` ∪ `active/` BOTH directions (`pat_overlap`) | `promote` | `   eligible: <IDs> — bash ops/polaris next --do promotes them under the board lock` |
| 5 | something is in flight: any `active/` task (others' lanes) · a live foreign lease · a live OWN bg job without `rc` (job `cwd` == `$PRIMARY` or my worktree) · `review/` work only the human can land (`risk: high`, or an `ask` awaiting approval) | `wait` | one line per reason (`   active: <IDs>` · `   lease: <who> (<m>m)` · `   bg: <name> running` · `   review/ awaits a human: <IDs>`) — `wait` is NEVER emitted with nothing in flight |
| 6 | otherwise | `finish` | `   foreign queued (drain: plan): <IDs>` · `   blocked/: <IDs>` · `   risk: high awaiting approval: <IDs>` — each only when non-empty |
- `next_landable`, `next_claimable`, `next_budget` are the row-1/3/2 predicates; `next_promote` is row 4's
  scan (and `--do`'s worker); `next_brief` is `--brief`.
### `--do` (promote only; every other verb is the role's own command)
`mutex_on`; scan `backlog/*.md` by `wsjf` desc, skip files without frontmatter (IDEAS.md); for each, re-check
INSIDE the mutex: deps ∈ `done/` · contract file exists · points sane · `rules_gate` (an unapproved `ask`
scope ⇒ hold with `   held: <ID> — ask scope <scope> needs a human's yes`) · the claim-time disjointness loop
(builder.sh:67-86, over `ready/` ∪ `active/` INCLUDING tasks promoted earlier in this pass) ⇒ overlap ⇒
`   held: <ID> — overlaps <ID2> on '<pat>'`; passing ⇒ `mv backlog→ready`, `set_fm status ready`,
`evt promote "$id" "deps done: <dep list>" "$pts"`. Then ONE `board_commit "chore(board): promote <IDs>"`
(+ `ops/board/EVENTS.ndjson`), `sync_board`, `mutex_off; trap - EXIT`, then `cmd_drift` as the audit
(findings printed, rc still 0). Nothing eligible ⇒ `nothing to promote`, rc 0. `evt promote` is a NEW event
kind (`ev":"promote"`) — `evt()` needs no change (it takes any kind).
### `--brief` (≤8 lines, no `|` anywhere, markers verbatim)
`role: <BUILDER|INTEGRATOR|none>` (my live lock on an active task ⇒ BUILDER; lease mine ⇒ INTEGRATOR; else
none) · `task: <ID> (<column>, yours)` (only with a lock) · `worktree: .polaris/wt/<ID> — <n> uncommitted`
(only when the dir exists; `git status --porcelain | wc -l`) · up to 3 `last: <kind> <ID> <age>m ago`
(from `EVENTS.ndjson` tail, my `who`) · `next: <line 1 of next>` · `read ops/roles/<ROLE>.md if this context lost it`
(ROLE = the role line 1 implies: resume/build ⇒ BUILDER, integrate/promote ⇒ INTEGRATOR, else the `role:` line).
### Usage block (T-101 writes into `kit/ops/polaris` `usage()`, 3 lines, byte-exact; `cli-help-parity`
alternation gains `next`, count 10 — T-111; `cli-help.expected` moves only at T-108)
```
  next [--do|--brief]            what this session does NEXT, read off the board — line 1 is ONE verb:
                                 resume <ID> · build <ID> · integrate · promote · wait · stop · finish;
                                 --do performs a promote under the board lock · --brief re-anchors a chat
```
Dispatch (T-101): `next) shift; cmd_next "$@";;` — no `update_check_maybe` (it rides hot loops; keep it pure).
**Testing `next` before T-101 lands (T-109 builds in parallel with the entry owner):** T-109's worktree has
no `next` dispatch and no `handover` in the loader, and `kit/ops/polaris` is T-101's file. T-109 proves its
module in a THROWAWAY KIT COPY (the T-089 pattern): `cp -R kit "$T/kit"`, then in the copy only,
`sed -i -e 's/admin bg$/admin bg handover/' -e '/^  triage)     cmd_triage;;$/a next) shift; cmd_next "$@";;' "$T/kit/ops/polaris"`,
and drive a fixture board with `bash "$T/kit/ops/polaris" next`. Never edit the real entry, never leave a
stub in the worktree. Conversely T-101 (loader `+handover`) has no `lib/handover.sh` in ITS worktree — the
loader dies on a missing module by design (install-parity), so T-101's `verify:` never runs a
loader-dependent command; for local testing it may drop an UNTRACKED empty `kit/ops/lib/handover.sh` that
is deleted before `verify`/`handoff` (nothing uncommitted leaves a worktree — the live-race rule). The
integrator lands T-109 before T-101 in W2 so the integrate branch's kit CLI is never loader-broken between
two lands; the W2 gate proves the real pair.

## Interface — session state `.polaris/handover/<sid>/` (gitignored via `.polaris/`; per checkout; never the board)
| file | writer | content |
|---|---|---|
| `last-event` | `evt()` (T-097) when `$CLAUDE_CODE_SESSION_ID` is set: `mkdir -p` + overwrite | the exact `<ts> <kind> <id>` of the line just appended |
| `started` | `evt()` — first write only (`[ -e ] ||`) | epoch |
| `avoid` | `evt()` — append on kinds `release`, `blocked`, `kickback` | one ID per line |
| `task` · `plan` | `cmd_claim` (T-098): `task` every claim; `plan` on the FIRST claim only (from the task's `plan:` frontmatter, may be empty) | ID · slug |
| `hops` · `hopped-event` | the Stop hook on a block (T-110) | integer · the `last-event` line it consumed |
| `prompted-at` | the UserPromptSubmit hook (T-110), builtins only | epoch |
| `finished` | `cmd_finish` rc 0 (T-100) | epoch |
`sweep --fix` (T-100) prunes `<sid>` dirs whose newest file is older than 24 h. "This plan" for `drain: plan`
= the `plan` file (set at first claim); a session that never claimed has no foreign tasks.

## Interface — `kit/ops/hooks/handover-hook.sh` (T-110; ≤220 lines, bash 3.2; 12 fns)
Fns, EXACTLY: `hh_jstr` · `hh_primary` · `hh_cfg` · `hh_state` · `hh_licensed` · `hh_subagent` · `hh_question` ·
`hh_bg_live` · `hh_emit` · `hh_stop` · `hh_anchor` · `hh_prompt`. Subcommands: `stop | anchor | prompt | --test`.
Input = the hook JSON on stdin: `session_id` · `transcript_path` · `cwd` · `stop_hook_active` (bool) ·
`hook_event_name`. Primary (`hh_primary`, in this order): `${cwd%/.polaris/wt/*}` when cwd carries that
segment · `$cwd` itself when `$cwd/ops/board` exists (a primary is where the board is — this is what makes
a mktemp fixture dir a primary for goldens and verify probes) · `$CLAUDE_PROJECT_DIR` · `git -C "$cwd"
rev-parse --show-toplevel`. `hh_cfg` reads ONE key from `<primary>/ops/CONVENTIONS.md` with `sed`, never
`ops/polaris` (~2 s) on the allow path. The CLI the hook runs for `next` is `<primary>/ops/polaris`, or
`$POLARIS_HANDOVER_CLI` when set (the seam goldens, drills and pre-dogfood builders use — the INSTALLED
`ops/polaris` has no `next` until 6.2.0 is dogfooded; `kit/ops/polaris` does once T-101 lands).
- `stop` — the gate ladder, cheapest first; each rung's `--test` word (pinned):
  `allow:no-state` (no `<primary>/.polaris/handover/<sid>/last-event` — ordinary Q&A pays ~150 ms) ·
  `allow:off` (`handover: off`) · `allow:no-event` (kind ∉ {`handoff`, `done`, `all-review`}) ·
  `allow:consumed` (`last-event` == `hopped-event`, string equality — **one event, one hop**, never a
  timestamp comparison) · `allow:finished` (`finished` exists and is newer than `last-event`) ·
  `allow:harness-cap` (`stop_hook_active` true) · `allow:cap` (`hops` ≥ `run_max_tasks` ≠ 0) ·
  `allow:subagent` (a `<transcript dir>/<sid>/subagents/*.jsonl` newer than `last-event`'s ts, OR a
  `"name":"Task"`/`"name":"Agent"` tool_use in the transcript's last 200 lines — subagent events land in the
  PARENT's state dir, so a conductor whose builders just handed off is never hopped into BUILDER) ·
  `allow:question` (the last assistant text block in the transcript carries a line starting `⛔` or ends
  with `?` — the session stopped to ask; shape verified at build) · `block:collect` (an OWN `ship-<ID>` bg
  job without `rc` — consumes nothing) · then `bash <primary>/ops/polaris next` ⇒
  `block:build` · `block:integrate` · `block:promote` · `block:finish` / `allow:wait` · `allow:stop` · `allow:resume`.
  A block writes `hops` (+1) and `hopped-event` (= `last-event`) BEFORE emitting.
  `POLARIS_HANDOVER_NEXT="<line 1>"` env replaces the `next` call (golden seam for the rail cases).
- `hh_emit` is the ONE emitter. Live block output: `{"decision":"block","reason":"<reason>"}` on stdout,
  exit 0 — the top-level `decision`/`reason` shape the harness documents for `Stop` hooks. T-110 verifies the
  shape against the harness docs at build and records the verdict in its handoff Notes; if the docs name a
  different shape, `hh_emit` changes (one fn) and T-111's raw-JSON golden case pins WHAT SHIPPED. Fallback if
  JSON is not honored: exit 2 with the reason on stderr. Allow = no output, exit 0. `--test` prints the word
  only, but performs the same state writes as live (so `hops` is asserted after a `--test` block).
- **The hook never mutates the board**: `promote` blocks with the reason below and the model runs
  `next --do` in its own turn (a 30 s mutex wait inside a 30 s hook would strand the mutex).
- `anchor` (SessionStart, matcher `compact|resume`): prints `bash <primary>/ops/polaris next --brief` ONLY
  when the state dir exists; else nothing. `prompt` (UserPromptSubmit): builtins only, writes `prompted-at`,
  ZERO stdout, rc 0; `--test prompt` prints `prompt: prompted-at written`.
- Settings entries (T-110, `kit/.claude/settings.json`; `install.sh`'s path-identity merge picks them up):
  `Stop` → `bash "$CLAUDE_PROJECT_DIR/ops/hooks/handover-hook.sh" stop` timeout 30 ·
  `SessionStart` matcher `compact|resume` → `… anchor` timeout 10 · `UserPromptSubmit` → `… prompt` timeout 5.
- `readonly-allow.sh` `polaris_ok` (T-110): `next` bare and `next --brief` ⇒ allow; `next --do` ⇒ ask.
  Golden `readonly-allow` +2 lines: `allow  bash ops/polaris next` · `ask  bash ops/polaris next --do`.

### Reason templates (pinned; `N` = hops after this one, `<cap>` = `run_max_tasks`; every reason ends with
the boundary sentence so the loop stays prose-primary)
- build: `You are a BUILDER (hop N of <cap>). The board hands you <ID> — <title> (<pts> pts). Leave the finished worktree first (ExitWorktree, or cd "<PRIMARY>"), then: bash ops/polaris claim <ID> — taken? bash ops/polaris claim takes the next. Read ops/roles/BUILDER.md if this context no longer has it; at your handoff run bash ops/polaris next and follow it.`
- integrate: `You are the INTEGRATOR (hop N). From the primary checkout land what waits in ops/board/review/ — <IDs>: bash ops/polaris land <ID> per task, then seal, run-verify + done each. <high IDs> are risk: high — the human approves those, never you. Read ops/roles/INTEGRATOR.md if this context no longer has it; then bash ops/polaris next.` (the `<high IDs>` sentence only when any)
- promote: `Backlog work is unblocked (<IDs>). From the primary: bash ops/polaris next --do — it promotes what passes the ready gate under the board lock — then follow its line 1.`
- finish: `This run's board is done. From the primary: bash ops/polaris finish — its exit code decides your close (0 opens with # 🎉 Complete!; otherwise no H1, name the one pending thing).`
- collect: `Your landing tail <name> is still running: bash ops/polaris bg wait <name> --max 300 (repeat while rc 2), then bash ops/polaris next.`
Verbs are idempotent: a taken claim ⇒ auto-pick takes the next; already landed/promoted ⇒ skipped.

## Interface — role prose and the queue notice (T-107 unless noted; bold/list only, `^#` set unchanged)
- BUILDER `## Loop mode` body (heading KEPT) → the default under `handover: auto`: after every handoff run
  `bash ops/polaris next` and follow its line 1; `handover: off` restores one task per session. BUILDER
  :68-75 "You never end the run" narrows to conductor-entered builders (a top-level session follows `next`,
  and `finish` only when `next` says so).
- SOLO close: follow `next` when it names more work; `finish` only when `next` says `finish`.
- INTEGRATOR §5 promote sentence → `bash ops/polaris next --do` (the by-hand re-verify stays as prose).
- CONDUCTOR :60-63 "compacted mid-run?" → the anchor hook already re-read the board — continue from its
  `next:` line; panes loop via `next` (no `start` nudges).
- PLANNER: may continue as BUILDER at the boundary (`next` names it).
- `handoff` queue notice (builder.sh:239, T-098): `queue) note "$nrdy ready task(s) still queued — the board hands you the next step: bash ops/polaris next";;`
- fleet kickoff (observe.sh:1869, T-100): `Stop at the review handoff.` → `then bash ops/polaris next and follow it.`
- Output style (T-096): ONE bold line in "How a session ends", ABOVE `## What a close reads like`:
  `**A hop is not an ending.** No H1 until \`bash ops/polaris next\` says \`finish\` and \`finish\` returns 0 — a role change mid-chat is the next context, not the close.`
- `run-finish.md` v3: a hop ends a CONTEXT, `finish` ends a RUN — run `finish` only when `next` says so, and
  then it IS the last command.
- `cmd_uninstall` (T-103): strips EVERY `ops/hooks/` entry across ALL hook events (Stop, SessionStart,
  UserPromptSubmit, PreToolUse …), foreign entries kept — today it strips only the ownership guard, and a
  dangling Stop hook would error on every turn.

## WS8 — approval is the kickoff (prose-only; T-096 W1 for the two rule-3 copies, T-107 W3 for the rest)
- Rule 3, BOTH `kit/ops/PROTOCOL.md` § VOICE and `kit/.claude/output-styles/polaris.md`, identical bytes
  (the `plain-voice` golden diffs them; `output-style-installed` still counts 7 rules):
  `3. **End with ONE concrete next step** — one only the human can take, doable in under two minutes; a step this chat could take itself, it takes before closing. Not three options.`
- `kit/CLAUDE.md` § ROLE DISPATCH table row: `| a plan you wrote was just approved (harness plan mode, \`plan_gate\`, or a typed yes) | \`ops/roles/CONDUCTOR.md\` in THIS chat — no subagent tool → \`PLANNER.md\`, then the handover loop | 1 |`
  + bullet: `**An approved plan is a kickoff, not a report.** The approval is the go for the whole run, in the same chat; closing with "open a new chat and say…" is the exact failure this row exists to end.`
  `SKILL.md` step 1 mirrors the row as one more list item.
- `CONDUCTOR.md`, a bold paragraph directly after step 1: `**Entered from an approved plan?** The plan IS the brief: skip step 1's interview and the 0c brief (the human approved the text), carry the plan path verbatim into the planner kickoff, and treat step 3 as passed unless the plan names a \`risk: high\` task or a STOP-AND-ASK item — those are still relayed. Budget caps and every other rule stand.`

## Compaction threshold — documentation only, never load-bearing
POLARIS never forces a compaction. Auto-compaction fires at the harness's own threshold; the anchor hook
makes ANY threshold safe. An owner wanting earlier compaction sets the harness's knob once — T-110's builder
verifies the current key name in the harness docs at build (candidates known today: an `autoCompact`
setting in `settings.json`, or the `DISABLE_AUTO_COMPACT` env for the opposite) and records it in the
handoff Notes and the sprint report; PROTOCOL § AWAKE/LANES does NOT name it (a doc naming a knob that
renames is a doc that lies).

## Executable check
### Drill `handover` (T-111, `kit/ops/lib/selftest/board.sh`; label `handover` registered by T-104 in spine.sh)
`export CLAUDE_CODE_SESSION_ID=drill-sid`; hermetic on the spine repo. Asserts, in order:
help lists `^  next ` · ready `T-HO1` ⇒ `next` line 1 `build T-HO1`, every other line `^   ` · claim ⇒
`task` = `T-HO1`, `last-event` matches `^[0-9]+ claim T-HO1$`, `next` ⇒ `resume T-HO1` · handoff (self-land,
`risk: normal` declared) ⇒ `last-event` kind `done`, `next` ⇒ `finish`, hook `--test` ⇒ `block:finish`,
`hops` = 1 · `finish` rc 0 ⇒ `finished` ⇒ hook ⇒ `allow:finished` · backlog `T-HO2` (`depends_on: T-HO1`,
contract present, `risk: normal`) ⇒ `next` ⇒ `promote` · `--do` ⇒ `ready/T-HO2.md`, an `"ev":"promote"`
line, board subject `chore(board): promote T-HO2` · second `--do` ⇒ `nothing to promote` · overlapping
`T-HO3` (same file as `T-HO2`) held with the note · a fresh `done` event un-hopped ⇒ `block:build`,
`hops` = 2; again ⇒ `allow:consumed` · release `T-HO2` ⇒ `avoid` contains it ⇒ `next` never says
`build T-HO2` · `hops` = `run_max_tasks` ⇒ `next` ⇒ `stop` + the budget note, hook ⇒ `allow:cap` ·
a lock with a foreign sid on an active task ⇒ `wait` · live foreign lease + review ⇒ `wait`; lease
backdated stale ⇒ `integrate` · `risk: high` review alone ⇒ `finish` + the approve note · `handover: off`
⇒ `allow:off` · `stop_hook_active: true` ⇒ `allow:harness-cap` · a fake `<sid>/subagents/x.jsonl` newer than
the event ⇒ `allow:subagent` · `--brief` ≤ 8 lines containing `role:`, `task:`, `next:` and no `|`.
Assert rc and file state; never message presence alone. Budget ~44 s; scratch under `scratchpad/T-111/`.
### Goldens (T-111; the `triage-lane` hermetic pattern, ONE fixture repo, CLI run from inside it)
- `handover-route`: per board state — `sed -n 1p`, `grep -cE '^(resume|build|integrate|promote|wait|stop|finish)( T-[A-Z0-9]+)?$'`
  on line 1, the `^   ` count; the `--do` state adds `ls ops/board/ready`, the `"ev":"promote"` count, and
  the board ref's subject.
- `handover-stop`: a fixture state dir under the fixture repo; `POLARIS_HANDOVER_NEXT` stubs the verb for the
  rail cases (one line per rung, both directions); ONE un-stubbed real-`next` case; ONE raw JSON invocation
  (no `--test`) pinning the shipped block shape; `pinned-reason-lines: <n>` = `grep -c 'You are a BUILDER (hop'`
  on the hook (must be 1).
- `readonly-allow` +2 cases (T-110). `cli-help-parity` +`next`, expected `10` (T-111).
### Build-time verifications (the four facts the design rests on — T-110 confirms each and notes it)
1. `stop_hook_active` and the consecutive-block cap semantics; 2. the Stop block JSON shape (`hh_emit`);
3. `<sid>/subagents/*.jsonl` mtime freshness while a subagent runs; 4. the last-assistant-text shape in
the transcript for the `⛔`/`?` recognizer. A fact that does not hold ⇒ the rung fails OPEN (allow) and the
handoff Notes say so — never a guess.

## api-kit rows
- W2 (T-101 writes): 8 rows `kit/ops/lib/handover.sh	fn	<name>` + 12 rows `kit/ops/hooks/handover-hook.sh	fn	<name>`.
- W1 (T-096 writes): `kit/ops/KEYS.tsv	key	handover`.
- W3 (T-104 writes): `kit/ops/lib/selftest/board.sh	fn	drill_handover` (T-111 uses exactly that name).
- T-097/T-098/T-100/T-107/T-110/T-111 add no other fn/heading/key.

## Invariants
- One event, one hop — licensed by string equality of `last-event` and `hopped-event`.
- The hook never writes the board; `--do` is the only promoter and runs in the model's turn.
- `wait` only with work in flight; `stop` only when a build/promote would otherwise fire.
- `drain: plan` ⇒ foreign tasks are never auto-built; the `avoid` list stops ping-pong.
- `handover: off` ⇒ the hook allows before any fork; subagent ends (`SubagentStop`) are untouched.
- The two Stop hooks (machine-level awake `idle`, repo-level handover) are independent; a blocked stop keeps
  the session busy and the awake verdict's transcript beat sees it.
- A hop ends a CONTEXT; `finish` ends a RUN (run-finish.md v3). `kit/CLAUDE.md`'s
  `subagent never ends a run` phrase stays (a golden pins it).

## Example
```
$ bash ops/polaris next
build T-099
   integrate.sh: done → wt_remove (2 pts, wsjf 4.5)
$ bash ops/polaris next --brief
role: BUILDER
task: T-098 (active, yours)
worktree: .polaris/wt/T-098 — 0 uncommitted
last: claim T-098 12m ago
next: resume T-098
read ops/roles/BUILDER.md if this context lost it
```

## v1.1 — human-gated review is `wait`; `--brief` names no role file when there is no role (2026-09-02, T-109 · T-112)

Found live by the T-109 lane. v1's decision table put human-gated review work — a `review/` task with
`risk: high`, or an `ask` scope awaiting approval — in BOTH row 5's condition column (⇒ `wait`, note
`   review/ awaits a human: <IDs>`) AND row 6's note list under `finish` (`   risk: high awaiting
approval: <IDs>`). Both cannot be reachable, and the drill spec in § Executable check was written to
the row-6 reading. **T-109 shipped the row-5 reading.** This section pins WHAT SHIPPED, byte-exact
against `kit/ops/lib/handover.sh` as landed (`0c1c6fe`, `integrate/2026-09-02`), so T-111's
`handover-route` golden and the `handover` drill are written to what runs — not to the contradiction.
No interface any claimed task implements changes: T-110's ladder already maps line 1 `wait` ⇒
`allow:wait`, and the anchor hook prints the `--brief` command without parsing its output.

### 1. Human-gated review work routes to `wait`, and row 6's approval note is unreachable
- **Human-gated** is decided in `next_landable`: a `review/` task counts as human-gated when
  `risk: high` **OR** its `approved:` list is non-empty. Those IDs collect in `NX_REV_HUMAN`; the
  rest in `NX_REV_OK`. (A recorded `ask` approval keeps the MERGE in human hands on purpose — the
  approval licensed the write, not the land. This is row 1's v1 condition, unchanged.)
- Row 1 fires only when `NX_REV_OK` is non-empty and the lane is open. Human-gated tasks ALONE never
  open row 1 — `next_landable` returns 1.
- Row 5's condition includes `[ -n "$NX_REV_HUMAN" ]`. So the moment anything human-gated sits in
  `review/`, row 5 fires as soon as rows 0–4 do not, with `   review/ awaits a human: <IDs>` — IDs
  space-separated in glob order, printed LAST among row 5's notes (`active` · `lease` · `bg` ·
  `review`). This does NOT violate "`wait` is never emitted with nothing in flight": a task waiting
  on a human IS in flight, with the human.
- Row 6 is therefore reached only with `NX_REV_HUMAN` EMPTY, which makes its third note,
  `   risk: high awaiting approval: <IDs>`, **UNREACHABLE**. It survives in the source as a guarded
  dead line (`handover.sh` row-6 block) and is deliberately NOT removed — deleting it is a diff on a
  landed file for zero behaviour. **T-111 writes no case for it**, and no case may assert `finish`
  for human-gated review work.
- Still reachable, unchanged: landable AND human-gated together ⇒ row 1 `integrate`, with
  `   risk: high, human approves: <IDs>` under it.
- **Correction to § Executable check.** The drill line "`risk: high` review alone ⇒ `finish` + the
  approve note" is VOID. It reads: **`risk: high` review alone ⇒ `wait` + `   review/ awaits a
  human: <ID>`**. Verified on a hermetic fixture (one `risk: high` task in `review/`, nothing else
  on the board, no lock, no lease):
```
$ bash ops/polaris next
wait
   review/ awaits a human: T-H1
```

### 2. `--brief` omits the pointer line at `role: none` (T-112)
- Shipped: `--brief`'s last line is `read ops/roles/<ROLE>.md if this context lost it`, where ROLE
  falls back to the `role:` line whenever line 1 is not `resume`/`build`/`integrate`/`promote`. With
  no lock and no lease that value is `none`, so a session with no role literally prints
  `read ops/roles/none.md if this context lost it` — a path that does not exist. T-109 implemented
  v1 literally, which was correct; v1 was wrong.
- **T-112** (`kit/ops/lib/handover.sh`, `depends_on: [T-109]`, 1 pt) changes exactly one line — the
  tail of `next_brief`, byte-exact:
```
  case "${line1%% *}" in
    resume|build)      rfile=BUILDER;;
    integrate|promote) rfile=INTEGRATOR;;
    *)                 rfile="$role";;
  esac
  [ "$rfile" = none ] || printf 'read ops/roles/%s.md if this context lost it\n' "$rfile"
```
- **Amended `--brief` shape.** Still ≤8 lines, still no `|` anywhere, all other markers verbatim and
  unchanged. The pointer line is present for every ROLE that names a real file and ABSENT exactly
  when `role: none` (i.e. no live lock on an active task and the lease is not mine — line 1 is then
  `wait`, `stop` or `finish`). A `role: none` brief has no `task:` and no `worktree:` either, so it
  is at most 5 lines: `role:` · up to three `last:` · `next:`.
```
$ bash ops/polaris next --brief        # no lock, no lease, nothing on the board
role: none
next: finish
```
- T-112 adds no function and no heading: the EIGHT-fn census of `lib/handover.sh` and the § api-kit
  rows stand exactly as v1 wrote them.
- **T-111 stays INDEPENDENT of T-112** (no dep either way; disjoint `files_owned`). The drill's
  `--brief` assertion runs with a live lock — it asserts `task:` is present, hence `role: BUILDER` —
  so it never reaches `role: none`. **T-111 MUST NOT** assert the pointer line's presence, nor a
  fixed line count, for a `role: none` brief in either golden; that is the only thing that would
  couple the two, and it would go red whichever order they land in.

### 3. The settings entries are JSON — assert the ESCAPED bytes, never the shell string
- v1's § Interface — `kit/ops/hooks/handover-hook.sh` writes the three entries as the SHELL command
  (`bash "$CLAUDE_PROJECT_DIR/ops/hooks/handover-hook.sh" stop`), which is what the harness runs and
  stays correct as prose. What lands in `kit/.claude/settings.json` is that string JSON-encoded:
  `"command": "bash \"$CLAUDE_PROJECT_DIR/ops/hooks/handover-hook.sh\" stop"` — exactly as the
  pre-existing `ownership-guard.sh\"` entry does it.
- So any `verify:` line or golden that greps `settings.json` for these entries MUST match the
  escaped bytes: `grep -q 'handover-hook.sh\\" stop' kit/.claude/settings.json` (`\\` = a literal
  backslash). A grep for the un-escaped `handover-hook.sh" stop` can never match a valid file, and
  is mutually exclusive with the `json.load` line sitting next to it. T-110's three verify lines
  were written against the shell string and were corrected on the board (2026-09-02).

## Changelog
- v1 2026-09-01: created for T-096, T-097, T-098, T-100, T-101, T-103, T-104, T-107, T-109, T-110, T-111 (plan: cant-eat-itself, 6.2.0)
- v1.1 2026-09-02: pinned what T-109 SHIPPED where v1 contradicted itself — human-gated `review/` routes to row 5 `wait` (row 6's approval note is unreachable; the drill line saying `finish` is void), `--brief` drops its pointer line at `role: none` (T-112), and the settings-entry assertions must match the JSON-escaped quote (T-110). No claimed task's interface changes.
