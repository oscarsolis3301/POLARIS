# CONTRACT: effort-ceiling — subagent effort never exceeds the chat's            (v1 — 2026-10-11)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-want-to-ensure-vectorized-token.md` § Sprint A (owner-approved
2026-10-11) · tasks T-185 (A1 probe spike) and T-186 (A2 the guard) · `plan: effort-ceiling-rea`.
Owner decisions this contract implements: **E1** (subagent effort ≤ the main chat's; lower is allowed —
the main agent chooses what the work needs) and **E2** (a mid-run change NOTIFIES; it never
auto-restarts; a restart happens only on the human's word, at a clean point).

## Purpose
Separate "what effort may a spawn get" (a deterministic veto in `kit/ops/hooks/model-guard.sh`) from
"what effort should it get" (the caller's choice today, Laya's in Sprint 19 under L1), and tell the
human — never stop the work — when a running subagent is above a ceiling that dropped.

## 1. The probe spike — `docs/spikes/effort-live.md` (T-185)
No kit code. Headless probes run in a throwaway git repo OUTSIDE this one, by the method of
`docs/spikes/laya-s1.md` § Method (`claude -p`, `--max-turns` ≤ 3, `--setting-sources project,local`
so the machine's own user hooks stay out, a throwaway hook that appends every event's payload to a log).
Headings, pinned (T-186 and Sprint 19 read them by name):
```
## Verdict                one line per question below: yes / no / partial, and what T-186 should do
## Live mid-run check     question 1 — RUN BY THE CONDUCTOR in the top-level chat, not by the builder
## Hook events            question 2
## Delivery               question 3
## updatedInput effort    question 4
## Method
```
1. **(conductor-run)** Does an inheriting subagent that is already running follow a mid-run effort
   change? Does a pinned one stay where it is? A pinned-cwd/headless builder cannot change a live
   chat's effort, so the conductor runs this in the top-level chat (with the owner's OK, restoring the
   effort afterwards) and hands the result to T-185's builder in its kickoff; the builder writes it
   under `## Live mid-run check` verbatim in substance and names who ran it and when.
2. Which hook events carry the effort — `$CLAUDE_EFFORT` in the hook env and/or `effort.level` in the
   payload: PreToolUse from the main chat, PreToolUse from a subagent, PostToolUse, UserPromptSubmit,
   SubagentStart/SubagentStop, and ConfigChange when effort is changed. A table: event × {env, payload}
   × {main, subagent}, with the observed value.
3. Does a `systemMessage` emitted by a SUBAGENT's PreToolUse reach the human in the desktop app (headless
   can only prove it reaches the transcript/stream — say which)? Which MAIN-session event can deliver
   `additionalContext` to the main agent? Name the event(s) and the exact JSON shape that worked.
4. Can a PreToolUse `updatedInput` set an Agent spawn's `effort` (as T-181 proved it can set `model`)?
   Prove it from the spawned subagent's own transcript `"effort"` field, not from the hook's echo.

Model ban holds inside probes: a probe that sets a model sets `sonnet` or `opus`, never haiku or fable;
never spawn `claude-code-guide`. Privacy: numbers and short paraphrases only, never transcript text.

## 2. The guard — `kit/ops/hooks/model-guard.sh` (T-186)
### Effort order
`low < medium < high < xhigh < max` (ranks 1..5). An unknown, empty or missing value ⇒ **allow** —
the guard's fail-open rule (its header, "IT MUST FAIL OPEN") stands: a detection miss never blocks.

### The ceiling
The ceiling is the MAIN chat's current effort. Every main-session call (payload with no `agent_id`) of
an event the script is already registered for reads `$CLAUDE_EFFORT`, falling back to the payload's
`effort.level` (read from the payload HEAD by `=~`, like every other field), and writes it to
```
$HOME/.claude/polaris/model-state/<session_id>.effort        # one line: the level word, LF
```
ONLY when it differs from what the file holds. The read and compare are shell builtins (`read`, `[[ ]]`)
and start no process; the write happens only on a change. Same `<session_id>` plain-name rule as the
existing state file (`/`, `\` or `..` ⇒ no state at all ⇒ allow). Known limit, accepted: the ceiling is
as fresh as the main session's last hook call.

**Which calls may set it (T-185, `docs/spikes/effort-live.md` § Hook events).** ONLY main-session
(no `agent_id`) **PreToolUse and PostToolUse** — both carry `$CLAUDE_EFFORT` and `effort.level`, and they
always agree. A subagent's calls carry the SUBAGENT's level and never touch the ceiling file.
SessionStart, UserPromptSubmit, SubagentStart and ConfigChange carry NEITHER — and in those events an
apparent `$CLAUDE_EFFORT` is the launching shell's leaked value, not the chat's: never read the ceiling
from them, even if a future registration routes them through this script. No new hook registration:
model-guard's existing entries already see every main PreToolUse/PostToolUse.

### The spawn check (Agent, Task, Workflow) — placed AFTER the existing forbidden-model check
- **Requested effort**, first source that is present wins:
  1. the call's `effort` parameter (Agent/Task `tool_input.effort`; for a Workflow, EVERY per-agent
     `effort` option in the script — each one checked, exactly as the model check walks every `model`);
  2. otherwise, the agent definition's `effort:` frontmatter line, looked up ONLY for a
     `subagent_type` that is not built in (built-in: `general-purpose`, `Explore`, `Plan`, `claude`,
     `statusline-setup`, `claude-code-guide`, and an absent type). Lookup is a builtin glob, first hit
     wins, in this order: `<cwd>/.claude/agents/<name>.md`, `$HOME/.claude/agents/<name>.md`, then a
     plugin's `…/agents/<name>.md` under `$HOME/.claude/plugins/` (a `<plugin>:<agent>` type names the
     agent after the colon; read the real on-disk layout off this machine — installed claude-security
     agents ship `effort: xhigh`). Frontmatter is read with a builtin `read` loop, stopping at the
     closing `---`.
  3. neither ⇒ nothing requested ⇒ allow (the subagent inherits, which is already ≤ the caller).
- **The limit** = the smaller of the CALLER's own effort (`$CLAUDE_EFFORT` / `effort.level` of THIS
  call — for a nested spawn that is the subagent's) and the recorded ceiling. One side unknown ⇒ the
  other is the limit; both unknown ⇒ allow. A subagent can never hand out more than it has.
- **Above the limit** ⇒ exit 2, nothing spawned, ONE line on stderr naming the level to drop to:
  ```
  polaris: effort '<requested>' is above this chat's '<limit>' (owner, E1) — spawn at effort '<limit>' or lower, or drop the effort parameter to inherit. Nothing was spawned.
  ```
  (For a definition source, say `the agent definition asks for '<requested>'` and suggest passing an
  explicit `effort: '<limit>'`.) Equal or below ⇒ allow.

### Mid-run: a subagent's own calls are NEVER blocked by effort
- A subagent call (payload has `agent_id`) whose `$CLAUDE_EFFORT` ranks above the recorded ceiling is
  ALLOWED (exit 0 as far as effort goes; the model ban is unaffected).
- **Who this is about (T-185, § Live mid-run check): PINNED subagents only.** An inheriting subagent
  follows a mid-run change from its next turn, so its level never ranks above the ceiling and it never
  trips this path. Only a subagent spawned with an explicit `effort` (or an agent definition's) stays
  where it was pinned and can be left above a lowered chat. No special-casing is needed: the rank
  comparison below already selects exactly those.
- The first time this happens for a given `(agent_id, ceiling)`, the guard — SILENTLY on the subagent's
  call (nothing on stdout: a subagent's `systemMessage` lands only in the SUBAGENT's transcript and never
  reaches the human or the main agent, § Delivery) — writes the marker
  ```
  $HOME/.claude/polaris/model-state/<session_id>.over/<agent_id>     # one line: "<agent effort> <ceiling>"
  ```
  and appends the note to the pending-notes file `model-state/<session_id>.over/.pending`.
  A later call with the same marker content writes nothing (no duplicate). A changed ceiling rewrites
  the marker and appends once more.
- **Delivery — the main session's next PreToolUse, and only there.** A main-session (no `agent_id`)
  PreToolUse that finds `.pending` emits, ONCE, on stdout (consume-on-read: `.pending` removed after the
  emit), the exact shape T-185 proved reaches the main agent:
  ```
  {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"<notice> <restart recipe>"}}
  ```
  carrying both the notice
  `polaris: a subagent is still on <agent effort> after the chat dropped to <ceiling>; it will finish there — say "restart it" to re-run it at <ceiling>.`
  and the restart recipe: message the subagent to write a handoff and release its claim or lock, then
  spawn the replacement at the new level from that handoff. **Only on the human's word** (E2) — the
  note says so. That emit never changes the call's allow/deny outcome (a spawn refusal on the same call
  still exits 2; the pending note then waits for the next main PreToolUse).
- **NEVER emit `additionalContext` on SubagentStop** (nor any output there): it attaches to the subagent
  and re-prompts it in a loop (T-185 saw 9 re-fires). model-guard is not registered on SubagentStop and
  must not be; a SubagentStop payload fed to the script produces no stdout.
- Raising effort mid-run: inheriting subagents follow (T-185 confirmed); pinned-lower ones stay lower
  (E1 allows it). No notice.

### Unchanged — pinned
The forbidden-model ban and its messages · hook registration (the five entries; `install`) · `mg_denied`
and its mirror in core.sh · the 300 ms budget (`bash kit/ops/bench.sh guards` → model-guard `ok`) ·
fail-open on every unexpected input. **No new top-level function** in model-guard.sh: the
`ops/tests/api-kit.expected` surface stays frozen this sprint (T-187 owns that file). If T-185 shows the
ceiling cannot be kept without registering a NEW event, T-186 STOPS and hands back — registration is an
owner decision, not a builder's.

## Executable check
Golden `ops/tests/model-guard-v2.{cmd,expected}` — owned by T-186 (the existing SURFACES row
`kit/ops/hooks/model-guard.sh` → `ops/tests/model-guard-v2.*` requires it to move with the script).
New cases, all hermetic (`mktemp -d` HOME, `CLAUDE_EFFORT` set per call):
- a parameter above / equal / below the limit → refused / allowed / allowed;
- a nested spawn (payload with `agent_id`) limited by its caller's own effort below the ceiling;
- a fixture agent definition with `effort: xhigh` under a `high` chat → refused; the same spawn with an
  explicit `effort: "high"` → allowed;
- a Workflow script with `effort:'max'` under `high` → refused;
- no source at all → allowed; unknown level word → allowed;
- a pinned subagent over the ceiling → allowed, NO stdout, the marker and `.pending` written; its next
  call → nothing new; the next main-session PreToolUse → exactly one `additionalContext` JSON line
  (shape above) carrying the notice + recipe, `.pending` removed; the main call after → no stdout;
- a SubagentStop payload → no stdout;
- the ceiling file is NOT touched by a subagent's call, nor by a UserPromptSubmit/SessionStart payload
  even with `CLAUDE_EFFORT` set (the leaked-shell-value case);
- the ceiling file is written on a change and NOT rewritten when unchanged (mtime or content proof).
Worktree-true run: `bash ops/tests/model-guard-v2.cmd 2>/dev/null | diff - ops/tests/model-guard-v2.expected`.

## Example
Main chat on `high`; the main agent calls Agent with `{"subagent_type":"general-purpose","effort":"max",…}`
→ exit 2, stderr: `polaris: effort 'max' is above this chat's 'high' (owner, E1) — spawn at effort 'high' or lower, or drop the effort parameter to inherit. Nothing was spawned.`
Same call with `"effort":"high"` → exit 0.

## Recorded v2 option — NOT built
T-185 § updatedInput effort proved a PreToolUse `updatedInput` CAN rewrite an Agent spawn's `effort`
(the spawned subagent's own transcript read `"effort":"low"`), so the guard could CLAMP an over-limit
spawn to the limit instead of refusing it. v1 keeps **refuse-at-spawn** (exit 2, the message above).
Clamping is a v2 contract + an owner decision; T-186 does not implement it.

## Changelog
- v1 2026-10-11: created for T-185, T-186.
- v1.1 2026-10-11: T-185 findings folded in before T-186 is claimed (Planner regroom, owner-directed): ceiling set from main PreToolUse/PostToolUse only, never SessionStart/UserPromptSubmit/SubagentStart/ConfigChange (leaked shell value); the mid-run path concerns pinned subagents only; notice + recipe delivered as `additionalContext` on the main session's next PreToolUse; never any output on SubagentStop; the updatedInput clamp recorded as a v2 option, not built. No new hook registration.
