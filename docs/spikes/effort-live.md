# Spike — effort live: which events carry it, how a notice lands, can a spawn be rewritten (T-185)

Contract: `ops/contracts/effort-ceiling.md` § 1. Owner decisions E1/E2 (plan § Decisions, 2026-10-11).
Harness: Claude Code 2.1.295 (the desktop app's bundled CLI, the same build as the live chat), Opus.

## Verdict

| # | Question | Answer | What T-186 does with it |
|---|---|---|---|
| 1 | Does a running inheriting subagent follow a mid-run effort change, and does a pinned one stay? | **yes / yes** (conductor, live) | Notify only about PINNED subagents that a later drop leaves above the chat. Inheriting ones follow on their next turn and need nothing. Effort is not locked at spawn for inheriting subagents. |
| 2 | Which events carry the effort? | **partial** | PreToolUse, PostToolUse, Stop and SubagentStop carry it in both `$CLAUDE_EFFORT` and `effort.level`. SessionStart, UserPromptSubmit, SubagentStart and ConfigChange carry neither. A subagent's own calls carry the SUBAGENT's level, so the ceiling must be recorded from main-session calls only (no `agent_id`), exactly as the contract says. No new event is needed: model-guard's existing PreToolUse registration is enough. |
| 3 | Does a subagent's PreToolUse `systemMessage` reach the human, and which main event delivers `additionalContext`? | **partial** | Headless proves only that a subagent `systemMessage` reaches the SUBAGENT's transcript, as a `hook_system_message` attachment. It never reaches the main transcript, and whether the desktop app shows it is unproven. A main-session `systemMessage` does land in the main transcript. `additionalContext` reaches the main agent from **PreToolUse, PostToolUse and UserPromptSubmit**. T-186 should deliver both the notice and the pending note from the main session's next PreToolUse, which is already registered. **Never** put `additionalContext` on SubagentStop: it re-prompts the subagent in a loop. |
| 4 | Can a PreToolUse `updatedInput` set an Agent spawn's `effort`? | **yes** | The spawned subagent's own transcript recorded `"effort":"low"` after a hook rewrote an effort-less spawn from a `high` chat. T-186 may therefore clamp instead of refusing. The contract pins exit 2 (refuse), so clamping would need a v2 contract and an owner decision. Recorded here only as an option. |

## Live mid-run check

**Run by the CONDUCTOR in the top-level chat** (Claude Code 2.1.295, desktop app, Opus 5.5) on
2026-10-12, at about 23:16 local. Recorded here from its kickoff to this builder; the builder did not
re-run it. All of the observations below are the conductor's.

- **Method.** Two background general-purpose subagents each made 6 Bash calls, one per turn, echoing
  `$CLAUDE_EFFORT`. s1 ran immediately, s2 after about 60 s, then s3–s6 every 16 s or so. One subagent
  inherited (no effort parameter). The other was spawned with `effort: "xhigh"`. The chat was on `high`
  at spawn. The human switched the chat's effort picker to `medium` between s2 and s3.
- **Inheriting probe.** s1 high · s2 high · s3 medium · s4 medium · s5 medium · s6 medium. An inheriting
  subagent **follows** a mid-run change from its next turn.
- **Pinned probe (xhigh).** xhigh on all six steps. A pinned subagent **stays** pinned. Today it ran
  ABOVE the chat: xhigh under high, then xhigh under medium. That is the leak the ceiling closes.
- **Also observed.** The main session's own Bash `$CLAUDE_EFFORT` tracks the live setting on every turn.
  It read `high` after the session moved xhigh → max → high, and the transcript `effort` fields show the
  same sequence. `set_session_effort` refuses to change the calling session's own effort.
- **Consequence for T-186.** The mid-run notice is needed ONLY for pinned subagents that a later drop
  leaves above the chat. Inheriting ones need nothing.

## Hook events

Main chat at `--effort high`. Subagent spawned two ways: inheriting, and with `effort: low`.
`$CLAUDE_EFFORT` was unset in the launching shell. Without the unset, the parent's value leaked into
the events that set nothing: they read `medium`, which was the conductor's chat at the time.

| Event | Caller | `$CLAUDE_EFFORT` (env) | `effort.level` (payload) | Observed |
|---|---|---|---|---|
| SessionStart | main | unset | absent | nothing |
| UserPromptSubmit | main | unset | absent | nothing, on every prompt |
| PreToolUse | main | `high` | `high` | the chat's level |
| PostToolUse | main | `high` | `high` | the chat's level |
| Stop | main | `high` | `high` | the chat's level |
| PreToolUse (Agent) | main | `high` | `high` | the caller's level. `tool_input.effort` = `low` when passed |
| SubagentStart | subagent (`agent_id` present) | unset | absent | nothing |
| PreToolUse | subagent | `low` pinned / `high` inheriting | same | the SUBAGENT's own level |
| PostToolUse | subagent | `low` / `high` | same | the subagent's level |
| SubagentStop | subagent | `low` / `high` | same | the subagent's level (+ `agent_transcript_path`) |
| ConfigChange | main | unset | absent | payload is `source` + `file_path` only (fired on a `settings.local.json` write) |

Notes:
- Env and payload always agreed whenever either one was present.
- With no `--effort`, the default read `medium` in both.
- A `/effort low` prompt sent headless (stream-json input) was treated as a plain prompt. Effort stayed
  `high` and no ConfigChange fired, so ConfigChange on an effort change is unproven headless.
- It does not matter for T-186: the ceiling is read from the next main PreToolUse, which carries the
  live level.

## Delivery

One headless run, with the hook emitting a distinct token per channel. Evidence comes from
`--include-hook-events` stream-json, both transcripts, and the agents' own reports of what they saw.

- **Subagent PreToolUse `{"systemMessage": "..."}`** — partial. It lands as an attachment of type
  `hook_system_message` in the **subagent's** transcript only. It never appears in the main transcript or
  the main agent's context. In the stream it shows up only as a raw `hook_response`. Headless cannot show
  whether the desktop app surfaces it to the human.
- **Main PreToolUse `{"systemMessage": "..."}`** — it lands as `hook_system_message` in the **main**
  transcript. That is the surface the app renders for the main chat, so it is the safer notice channel.
- **`additionalContext` to the main agent** — confirmed by the main agent naming each token and its
  source. The shape that worked:
  ```
  {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"..."}}
  {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}
  {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
  ```
  PreToolUse and PostToolUse delivered on every main call; UserPromptSubmit delivered once per prompt.
- **Hazard: SubagentStop `additionalContext`.** It is attached to the subagent and re-prompts it. In
  the probe it fired 9 times (`stop_hook_active` true on 8), and the subagent's final answer became the
  injected text. Never emit it.

## updatedInput effort

- **Setup.** The chat was at `--effort high`. The model was told to spawn a general-purpose subagent
  with NO effort parameter, and `tool_input` on the Agent PreToolUse confirmed none was passed.
- **Hook output.**
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{<original input>,"effort":"low"}}}`
- **Evidence from the spawned subagent's own transcript.** It holds 2 `"effort":"low"` fields and none
  at any other level, while the main transcript holds 4 `"effort":"high"`. The subagent's PreToolUse,
  PostToolUse and SubagentStop all read `low` in both env and payload. The main PostToolUse for the
  Agent call echoes `tool_input.effort` = `low`, so the rewritten input is what ran.
- **Answer: yes.** It works like T-181's `model` rewrite.

## Method

- **Probe repo.** A throwaway `git init` outside this repo, in the session scratchpad (`effort-probe/`).
  Its `.claude/settings.json` registers one throwaway hook on PreToolUse and PostToolUse (matcher `*`),
  UserPromptSubmit, SubagentStart, SubagentStop, ConfigChange, SessionStart and Stop.
- **The hook.** It appends `=== <event> env_CLAUDE_EFFORT=<value>` plus the raw payload to a log. A
  `MODE` file switches its emissions: `base` emits nothing, `deliver` emits a token per channel, and
  `rewrite` rewrites the Agent spawn.
- **Runs.** 8 headless runs: `claude -p`, `--max-turns` 3–4, `--setting-sources project,local`,
  `--model opus`, `--allowedTools Bash,Agent`, `--output-format stream-json --verbose
  --include-hook-events`, launched with `env -u CLAUDE_EFFORT`.
- **Binary.** The first two runs used the npm CLI (2.1.251). Its Agent tool has no `effort` parameter:
  `tool_input` keys are description, prompt, subagent_type and run_in_background. All evidence above
  therefore comes from the desktop-bundled 2.1.295 binary
  (`%APPDATA%\Claude\claude-code\2.1.295\…\claude.exe`), the live chat's own build. T-186's tests should
  not assume an older CLI sends `effort` at all. A missing value means allow.
- **Mid-session changes.** Effort was changed mid-session two ways: by a `/effort low` prompt over
  stream-json input, and by an external write of `effortLevel` to `.claude/settings.local.json`.
- **Cost and privacy.** About $3.55 in total, all Opus. No model other than opus was set, and no
  `claude-code-guide` was spawned. Logs and transcripts stay outside the repo. This file carries counts,
  field names and probe tokens only, never transcript text.
