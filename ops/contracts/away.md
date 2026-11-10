# CONTRACT: away — "approved + auto means the owner has left", and small means fast   (v1 — 2026-11-10)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = a new `## v2` section + a migration task.
Plan: `plans/away.md`, Phase B (release 6.16.0, plan slug `away`). Owner decisions are that plan's
"Your decisions" list; every rule below traces to one of them.

## Purpose
Once the owner approves a plan and switches the chat to auto mode, nothing in a run waits on them: the
question tool is refused, a closing question is bounced, and a `risk: high` task of the approved plan
merges on the plan's yes. Anything else — plan mode, default mode, no approved plan, an unreadable
payload — is **here**, and every behaviour is today's, byte for byte. Separately: a small UI change
gets lint + typecheck side by side and a before/after look instead of a suite, every bigger change runs
its checks side by side, and a landing refreshes the brain once.

## 0. Words
- **session id** (`<sid>`): the hook payload's `session_id`, or `$CLAUDE_CODE_SESSION_ID` in a Bash call
  (every Bash call of a session and of its subagents carries the parent session's id). A `<sid>` is
  used only when it is non-empty and matches `[A-Za-z0-9_-]+` — model-guard.sh's exact test; anything
  else ⇒ no state is read or written ⇒ **here**.
- **state dir**: `$HOME/.claude/polaris/model-state/` — the folder `kit/ops/hooks/model-guard.sh` already
  keeps `<sid>.effort` in. `$HOME` unset ⇒ no state ⇒ **here**. Created with `mkdir -p` only on a write.
- **away modes**: `auto` · `bypassPermissions` · `dontAsk`. **Every other value** (`default`,
  `acceptEdits`, `plan`, an unknown word, empty, missing) is NOT an away mode.

## 1. State files (B1 writes · B2/B3 read · builtins and one small read each)
| file | content | written by | removed by |
|---|---|---|---|
| `<sid>.mode` | ONE line: the last `permission_mode` any presence-guard call saw | presence-guard.sh, ONLY when the value differs from the file (one builtin read + compare, write on change) | nothing |
| `<sid>.approved` | line 1: epoch seconds of the approval · lines 2+: one plan slug per line, bound to that approval (§ 4) | presence-guard.sh writes line 1 (§ 2.2); `_presence_bind` appends lines 2+ | presence-guard.sh when it sees mode `plan` (a new plan is being drafted; the old yes does not cover it) |

- Line 1 is written ONLY when the file is absent: an approval already on record keeps its epoch and
  its slugs. ExitPlanMode and the plan→other mode change both fire for one approval; the second is a no-op.
- Writes are `printf … > file` / `>> file` with `2>/dev/null`; a failed write is silent.
- A payload with no `permission_mode` falls back to line 1 of `<sid>.mode`; no file there ⇒ unknown ⇒ here.

## 2. B1 — `kit/ops/hooks/presence-guard.sh` (new) + `kit/ops/lib/presence.sh` (new)
### 2.1 Registration — ONLY through `kit/.claude/settings.json` (the installer merges it) + install.sh's chmod line
Three new entries, each `{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/ops/hooks/presence-guard.sh\"","timeout":5}`:
- `PreToolUse`, matcher `AskUserQuestion|Bash|PowerShell` (a NEW entry; the existing ones are untouched);
- `PostToolUse`, matcher `ExitPlanMode` (a new event key in the kit file);
- `UserPromptSubmit`, no matcher (a second entry beside handover-hook's `prompt`).

`kit/ops/install.sh`: add `"$TARGET/ops/hooks/presence-guard.sh"` to the one `chmod +x` line; the file
itself rides the existing `hooks` directory copy. **No edit to `kit/ops/bootstrap.py`** (machine-level
only, and refused to subagents — T-187). The installer's merge (python, keyed on the `ops/hooks/<script>`
path, iterating every event of the kit file) must place all three entries into a project that already has
a settings.json; the install-into-fixture golden proves it. If it cannot, that is a finding to hand back,
never a bootstrap.py edit.

### 2.2 What the hook does — one payload, at most one decision
Parse the HEAD of the payload exactly as model-guard.sh does (cut at `"tool_input":`, then `[[ =~ ]]`):
`hook_event_name`, `session_id`, `tool_name`, `permission_mode`. Then, in order:
1. Record the mode (§ 1). If the previously recorded mode was `plan` and the new one is not `plan`,
   write `<sid>.approved` line 1 (if absent). If the new mode is `plan`, remove `<sid>.approved`.
2. `PostToolUse` + `tool_name` `ExitPlanMode` ⇒ write `<sid>.approved` line 1 (if absent). No output.
3. `PreToolUse` + `tool_name` `AskUserQuestion` + **away** (§ 2.3) ⇒ deny on stdout in the
   checkout-guard shape, nothing on stderr, exit 0:
   `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<AWAY_SAY>"}}`
4. Everything else ⇒ no output, exit 0 (no opinion: the call goes through and the other hooks decide).

**Fail-open:** any parse miss, unset HOME, bad `<sid>`, unreadable file ⇒ step 4. The script never
exits non-zero and never writes stderr. Builtins only, plus at most one `mkdir -p` on a first write and
one `date +%s` on an approval write (bash 3.2 has no epoch builtin). No `ops/polaris` call, no git.

**AWAY_SAY** (byte-exact; the sentence a model reads; B2 reuses it verbatim; no backticks or quotes in
it, because it travels through JSON in two hooks):
`The owner approved the plan and left. Do not ask. Take the recommended option and write it down as an assumed: line; if there is no safe default, park that one piece and finish the rest.`

`--test` as the first argument: print ONE word instead of the output layer, after performing the SAME
state writes: `deny:away` · `allow:here` · `allow:not-question` · `allow:error`.

### 2.3 The away predicate (one definition, three readers)
**away** ⇔ `<sid>` valid AND `<sid>.approved` exists AND the mode is an away mode, where the mode is the
payload's `permission_mode` when present, else line 1 of `<sid>.mode`. Anything else ⇒ **here**.

### 2.4 `kit/ops/lib/presence.sh` — private names only (`_presence_*`); `presence` joins the literal module list in kit/ops/polaris (after `handover`)
- `_presence_state` — sets `PRESENCE` (`away`|`here`) and `PRESENCE_WHY` from `$CLAUDE_CODE_SESSION_ID`
  and the two files (a Bash call has no payload ⇒ the mode is `<sid>.mode`). rc 0 always.
- `_presence_away` — rc 0 iff away.
- `_presence_bind <slug>` — when `<sid>.approved` exists and `<slug>` is not already on lines 2+, append
  it. No approval on record ⇒ nothing. rc 0 always.
- `_presence_covers <slug>` — rc 0 iff away AND `<slug>` is on lines 2+ of `<sid>.approved`.
- `_presence_cmd` — `polaris presence`: line 1 `away` or `here`, then ONE note line, rc 0 always:
  - `   why: the plan was approved and this session runs in <mode> mode`  (away)
  - `   why: no session id`
  - `   why: no plan approved in this session`
  - `   why: this session runs in <mode> mode`  (approved, not an away mode)
  - `   why: this session's mode is unknown`  (approved, no mode on record)

  Read-only; no `update_check_maybe` (the same class as `depth`).
- kit/ops/polaris: dispatch `presence)` → `_presence_cmd`, and ONE help line right after the `depth`
  block: `  presence                       away or here: away = a plan approved in this session AND auto mode; then a why: line`.
  Because B1 owns kit/ops/polaris, it also writes B4's word into the `depth` help text (§ 5.1).

## 3. B2 — a closing question never ends an away run (`kit/ops/hooks/handover-hook.sh`)
- Read `permission_mode` from the Stop payload (fallback `<sid>.mode`) and `<sid>.approved` with
  builtins, per § 2.3. New code is inline or ONE new private fn `_hh_away` (role-handover.md § v4).
- **Away**, a closing question (`hh_question` sets `REPLY=q`), and the router names work left
  (`build` | `integrate` | `promote`) ⇒ test word `block:away`, reason byte-exact:
  `<AWAY_SAY> Work left - next says <l1>; do it.`
  This holds on EVERY such stop, `stop_hook_active: true` included: the `allow:harness-cap` rung is
  skipped for exactly this case (away AND `REPLY=q`). The harness's own cap on consecutive Stop blocks
  stays the backstop. The words "ask again and you will be let through" never appear while away.
- Away, but `next` says `finish` | `tidy` | `wait` | `stop`, or the text carries the `⛔` stop mark, or
  no completion event licenses the rung ⇒ today's rung, unchanged.
- **Here** ⇒ today's ladder byte for byte: `ops/tests/stop-question.expected` and
  `ops/tests/handover-stop.expected` stay byte-identical.

## 4. B3 — away, the approved plan's yes is the yes (`kit/ops/lib/builder.sh`, `kit/ops/lib/author.sh`)
- **Binding a slug** (`_presence_bind`): `new` (author.sh) binds the `plan:` slug of every task it files;
  `approve --plan <slug>` (`cmd_approve_plan`) binds `<slug>`. Binding happens only while an approval is
  on record (§ 1), so a slug filed before the approval or in another session is never covered. `claim`
  never binds: a task waiting on the board is not the owner's plan just because it sits there.
- **Recording at handoff** (`cmd_handoff`, on the board, inside handoff's own board mutation — the same
  board commit, no second mutex): when `_presence_covers <the task's plan: slug>` AND `cfg autonomy
  trusted` is not `standard` AND the task carries NO hand-recorded `approved:` entry, write the plan
  entries `cmd_approve_plan` would write for THIS task only (`merge` for `risk: high`, `need:<v>` per
  `needs:`, every covering `ask` scope). Reuse its writer: factor the per-task part of
  `cmd_approve_plan` into ONE private fn `_approve_plan_entries <taskfile> <slug> <msg>` that both call
  (cmd_approve_plan's own output stays byte-identical). `<msg>` is byte-exact `approved plan, owner away`,
  so each entry reads `<scope> — <WHO>, <YYYY-MM-DD>: plan <slug>: approved plan, owner away`, which
  `approved_entries` already parses as a plan entry. `plan_covers` (ownership.sh, NOT edited) then
  passes, and every caller (self_land, next_landable, land --express) follows with no edit.
- For each task that gained a `merge` entry this way, handoff prints ONE line, byte-exact:
  `away: <ID> merges on the approved plan's yes (plan <slug>, risk: high) — the close names it`
  and appends the event `away-yes <ID>` through `evt`.
- Unchanged: here (for any reason) · a task whose slug is not bound · a hand-recorded approval on the
  task · `autonomy: standard` · the `feat/*` refusals of `approve` and `approve --plan`.

## 5. B4 — depth `ui` and two keys (`kit/ops/lib/core.sh`, `kit/ops/KEYS.tsv`, `kit/ops/lib/route.sh`)
The rules live in `ops/contracts/test-depth.md` § v2 (2026-11-10). Depth words become
`none · look · ui · scoped · full`.
### 5.1 `depth` help wording (kit/ops/polaris; written by B1, which owns the file)
After `look (only test_look paths, e.g. css/images) ·` the list gains
`ui (only test_ui paths, in 1-2 point risk: normal tasks: lint + typecheck + a look) ·`.

## 6. B5 — checks side by side (`kit/ops/lib/qa.sh`)
Rules: test-depth.md § v2.4. The decision half of each key (selection, carry, skip, the uat deferral)
runs first, exactly as today; only the execution of the chosen commands overlaps. Output is replayed in
today's order (`test, lint, typecheck, build, uat`) and wording. PIDs live in scalar variables and each
is `wait`ed by its PID — no arrays, no `wait -n`; one background subshell per key, never one per item.

## 7. B6 — the landing refreshes the brain once (`kit/ops/lib/integrate.sh`, `kit/ops/lib/knowledge.sh`)
- `seal` under an INHERITED lease (a parent frame holds it: the self-land tail), while at least one task
  it just sealed still waits in `review/` for its `done` ⇒ skip `brain_refresh_if_present` and
  `touch .polaris/brain-due`. Otherwise seal refreshes as today. `seal --sync` (pr mode) is unchanged.
- `done` refreshes as today, EXCEPT under an inherited lease while another landed task still waits in
  `review/` for its done ⇒ skip (the marker stays). Whichever refresh runs removes `.polaris/brain-due`.
- `board_changed_touch` still runs at every site (the beacon is cheap, and today's stale warning reads
  it, so a refresh lost to a crash is still caught).
- knowledge.sh `brain_refresh_if_present`: when `POLARIS_BRAIN_TRACE` names a file, append ONE line
  `refresh` to it before refreshing (test-only; unset ⇒ byte-identical behaviour).
- Target (Notes, not verify): a self-landing handoff on a fresh project in 20 s or less (34 s today),
  measured before and after with the tracing script already written.

## 8. B7 — the words (prose; exact anchors; every heading byte-identical)
kit/CLAUDE.md — at most THREE lines changed or added:
- Invariant 9's last sentence becomes:
  ``` `risk: high` NEVER merges without the owner's approval: a recorded yes, or the approved plan while away.```
- ONE new line as the first line under `## STOP AND ASK THE HUMAN before`:
  ``` **Away** (`bash ops/polaris presence` says `away`: plan approved + auto mode): never ask — take the recommended option, write it as an `assumed:` line, park only what has no safe default. The list below binds only while the owner is here.```

Role files (`kit/ops/roles/{CONDUCTOR,INTEGRATOR,BUILDER,SOLO,PLANNER}.md`), `kit/ops/PROTOCOL.md`,
`kit/.claude/output-styles/polaris.md` — only these rules are added, each where its role acts on it:
- **Here** (plan mode, or not auto): ask every question whose answer changes the plan, in rounds,
  until none is left. **Away**: never ask; take the recommended option; park only what has no safe
  default; never stop for a busy lane, a taken task or another chat's work; finish through publishing.
- A pull-request project's close ends with the pull-request link; nothing follows it.
- Every close says how long the run took and where the time went (`bash ops/polaris speed`), and names
  each task an `away:` line reported (merged on the approved plan's yes).
- PLANNER: carve for side-by-side lanes; a `depends_on` chain longer than two tasks carries a one-line
  reason in the task's Notes; the plan it shows names the number of lanes, waves and an estimated time.
- PROTOCOL.md full command table: ONE row for `presence` — away or here, and why (read-only).
- PROTOCOL.md § VOICE and the output style's voice rows stay byte-identical with each other (plain-voice).

## 9. B8 — release 6.16.0
`kit/ops/VERSION` → `version: 6.16.0`; `CHANGELOG.md` gains `## 6.16.0`, plain words, covering B1–B7.

## Executable checks
Hermetic: `mktemp -d` fixtures; HOME, USERPROFILE and POLARIS_AWAKE_HOME faked together; never the
real `~/.claude`; no sha, time or absolute path printed. Each behaviour has at least one golden that
installs the kit INTO its fixture and runs the fixture's own `ops/polaris` (wrap-own-folder.cmd shows how).
- **B1** `ops/tests/presence-guard.cmd/.expected` — canned payloads through `presence-guard.sh --test`:
  approved + `auto` AskUserQuestion ⇒ `deny:away` · approved + `bypassPermissions` ⇒ `deny:away` ·
  approved + `default` ⇒ `allow:here` · mode `plan` ⇒ `allow:here` and `<sid>.approved` gone · no
  approval ⇒ `allow:here` · garbage or empty payload ⇒ `allow:error`, rc 0 · a Bash call ⇒
  `allow:not-question` and `<sid>.mode` recorded · no `permission_mode` after a recorded `auto` ⇒
  `deny:away` · ExitPlanMode PostToolUse ⇒ `<sid>.approved` exists · `plan` → `auto` ⇒ it exists ·
  session id `../x` ⇒ nothing written · the real-output deny JSON equals the pinned line.
- **B1** `ops/tests/presence-installed.cmd/.expected` — installs the kit into a fixture that already has
  a `.claude/settings.json`; the three entries are merged; the fixture's own `ops/polaris presence`
  prints each § 2.4 reason for its matching state.
- **B2** `ops/tests/stop-away.cmd/.expected` — approved + auto + `continue?` + `build T-1` ⇒ `block:away`,
  and again with `stop_hook_active: true` ⇒ `block:away` · same with `finish` ⇒ `allow:question` ·
  approved + `default` ⇒ `block:question`, then `allow:harness-cap` (today's) · plan mode ⇒ today's ·
  the real-output reason carries AWAY_SAY and no "let through".
- **B3** `ops/tests/away-yes.cmd/.expected` — kit installed into the fixture; approval on record + `auto`
  + a `risk: high` task filed by `new` in that session ⇒ its handoff writes the `merge` entry ending
  `approved plan, owner away`, prints the `away:` line, and `plan_covers` is rc 0 · `default` mode ⇒ no
  entry, today's refusal · a slug filed BEFORE the approval ⇒ no entry · a hand entry ⇒ no entry ·
  `autonomy: standard` ⇒ no entry.
- **B4** `ops/tests/depth-ui.cmd/.expected` — the test-depth.md § v2.5 list.
- **B5** `ops/tests/qa-parallel.cmd/.expected` — two keys that append `start`/`end` lines to one log ⇒
  overlapped at `scoped` and at `ui`; `qa_parallel: off` ⇒ strictly in order; at `ui` the test key's
  marker file is never created; qa's printed text is identical between on and off.
- **B6** `ops/tests/brain-once.cmd/.expected` — kit installed into a fixture with a brain; a self-landing
  handoff that seals and dones under one lease ⇒ `POLARIS_BRAIN_TRACE` holds exactly ONE `refresh`; a
  plain `done` outside a lease ⇒ one; `.polaris/brain-due` absent after both.

## Invariants
- Here is the default. Every unknown is here; every here path is today's code path, byte for byte.
- Hooks fail open, print nothing on allow, and stay builtins plus one small file read.
- No task edits `kit/ops/bootstrap.py`, `.github/`, or `ops/SURFACES.tsv` by hand.
- One owner at a time per file. T-225 (in flight) keeps integrate.sh, qa.sh, selftest/policy.sh and
  ops/tests/api-kit.expected until it is done; the ready gate holds B5 and B6 in backlog until then.
- Every new function name in this plan is private (`_name`); no task owns ops/tests/api-kit.expected.
- Every task of this plan lands itself at handoff; its verify list is its whole gate.

## Changelog
- v1 2026-11-10: created for plan `away` (Phase B of plans/away.md): B1–B8.
