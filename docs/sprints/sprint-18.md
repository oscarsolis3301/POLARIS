# Sprint 18 — Effort ceiling + REA (6.8.0) (2026-10-11–)

## T-185 — "Effort probe spike — which hook events carry the chat's effort, how a notice reaches the human, and whether a spawn's effort can be rewritten"
points 2 · risk normal · landed 6e52797 (2026-10-11) · claimed 2026-10-11 → done 2026-10-12
files touched: docs/spikes/effort-live.md

### Why
The owner wants subagents to never run at a higher effort than the chat itself, and wants to be told
(not interrupted) when the chat's effort drops while a subagent is still running. Before the guard
(T-186) is written we need hard facts from the harness, because the guard can only use what the
harness actually sends. This spike writes no kit code: its only repo output is
`docs/spikes/effort-live.md`, with the six headings `ops/contracts/effort-ceiling.md` § 1 pins.

1. In a throwaway git repo OUTSIDE this one, using the method of `docs/spikes/laya-s1.md` § Method
   (headless `claude -p`, `--max-turns` ≤ 3, `--setting-sources project,local`, a throwaway hook that
   logs every event payload and its environment), answer contract questions 2–4: which events carry
   `$CLAUDE_EFFORT` / `effort.level` (main vs subagent; PreToolUse, PostToolUse, UserPromptSubmit,
   SubagentStart/Stop, ConfigChange); whether a subagent's PreToolUse `systemMessage` reaches the human
   and which main-session event can deliver `additionalContext`; whether a PreToolUse `updatedInput` can
   set an Agent spawn's `effort` (proved from the spawned subagent's own transcript).
2. Question 1 (does an already-running inheriting subagent follow a mid-run effort change; does a pinned
   one stay) is answered by the CONDUCTOR in the top-level chat, the only caller that can change a live
   chat's effort. Its result arrives in your kickoff; write it under `## Live mid-run check` and name who
   ran it and when.
3. `## Verdict` gives one line per question (yes / no / partial) and what T-186 should do with it.

### Acceptance
- [ ] The six pinned headings exist; questions 2–4 each answered yes / no / partial with the evidence that decided it.
- [ ] `## Hook events` is a table: event × env/payload × main/subagent, with the observed value.
- [ ] `## Live mid-run check` carries the conductor's result, attributed (who, when) — never fabricated by the builder.
- [ ] Nothing in this repo changes except `docs/spikes/effort-live.md`; the probe repo and logs live outside it.

## T-186 — "The effort ceiling — model-guard refuses a spawn above the chat's effort and tells you once when a running subagent is left above a lowered one"
points 5 · risk normal · landed 67b0830 (2026-10-12) · claimed 2026-10-12 → done 2026-10-12
files touched: kit/ops/hooks/model-guard.sh, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected

### Why
Owner decision E1: a subagent may run at the main chat's effort or lower, never higher. With Opus 5.5
on high, subagents run at high or below. Today nothing stops a spawn from asking for `max`, or an agent
definition from pinning `effort: xhigh`. Owner decision E2: if the human lowers the chat's effort while
a subagent is running, the subagent is NOT stopped; the human gets one plain notice, and a restart
happens only when they ask. Both belong in `kit/ops/hooks/model-guard.sh`, which already sees every
tool call on the machine and already checks every spawn for forbidden models.

Build exactly `ops/contracts/effort-ceiling.md` § 2: the effort order and fail-open rule; the ceiling
file, written only on change, with builtins; the spawn check after the forbidden-model check (parameter,
then a Workflow's per-agent option, then a non-built-in agent definition's `effort:`), limited by the
smaller of the caller's own effort and the ceiling, refusing with one line that names the level to drop
to; and the mid-run path that never blocks a subagent, writes one marker, emits one notice through the
channel `docs/spikes/effort-live.md` proved, and hands the main agent the note once. Extend the golden
with every case the contract lists.

### Acceptance
- [ ] Spawn above / equal / below the limit → refused (exit 2, one line naming the level) / allowed / allowed.
- [ ] A nested spawn is limited by its caller's own effort; an `effort: xhigh` definition under `high` is refused and the same spawn with an explicit `high` allowed; a Workflow `effort:'max'` under `high` is refused; no source or an unknown word → allowed.
- [ ] A subagent over the ceiling → allowed, one notice, marker written; its next call → no duplicate notice.
- [ ] The forbidden-model ban, hook registration, `mg_denied` and every fail-open path are unchanged; model-guard stays `ok` in `bench.sh guards`.
- [ ] No new top-level function in model-guard.sh (the api-kit diff is empty).

## T-189 — "Asking to use REA works in any POLARIS project — one routing clause in the protocol every session reads"
points 1 · risk normal · landed 3e1950b (2026-10-11) · claimed 2026-10-11 → done 2026-10-12
files touched: kit/CLAUDE.md

### Why
REA becomes standard equipment this sprint (owner decision R1), so a human in any POLARIS project should
be able to say "Use REA to…" and get the right behaviour without a detour. `kit/CLAUDE.md` is injected
into every session and every subagent, so every byte there is paid 6–8 times a run: the clause must be
tiny (about 120 B, at most 160 B added; the file is 9,894 B today, so ≤ 10,054 B after).

Add ONE clause inside § ROLE DISPATCH, next to the Guard bullet, that says (in substance,
`ops/contracts/rea.md` § 3): "Use REA to…" means REA's skill (`reverse-engineer-anything`) gathers the
evidence first; then a question gets answered, and a build request goes to `triage` with that evidence
attached. No new heading.

### Acceptance
- [ ] The clause sits in § ROLE DISPATCH and routes build requests to `triage` with the evidence attached.
- [ ] kit/CLAUDE.md grows by at most 160 bytes.
- [ ] No heading added or changed (api-kit diff empty).

## T-190 — "REA studies Laya and Jev — the real checkpoints and wire exchange, the newer checkpoint measured on our own questions, and what REA costs every chat"
points 3 · risk normal · landed fe6e062 (2026-10-11) · claimed 2026-10-11 → done 2026-10-12
files touched: docs/spikes/laya-jev-rea.md

### Why
Sprint 19 will let Laya (a small local encoder; free) make cheap decisions, including each spawn's effort
(owner decision L1), and its server speaks the protocol of Jev, TypeSafe's paid hosted version. The T-181
spike (`docs/spikes/laya-s1.md`) found the shipped base checkpoint no better than chance on our
questions; a newer `laya-typed-decisions` checkpoint scores far better on Laya's own benchmark but has
never been measured on ours. Owner decision R1 also says REA's first job is to study Laya and Jev before
the decision layer is built. This spike writes no kit code: its only repo output is
`docs/spikes/laya-jev-rea.md`, with the eight headings `ops/contracts/rea.md` § 4 pins.

1. Use REA (already installed on this machine) on shipped artifacts only: (a) the installed `laya`
   package and its checkpoints, meaning which checkpoint answers which question and how confidence is
   calibrated; (b) the `laya-serve` runtime's real `POST /v1/systemone` exchange; (c) Jev's hosted API
   only if the conductor passes you the NAME of an env var holding the owner's key, otherwise write
   "skipped: no key".
2. Measure `laya-typed-decisions` against the T-181 base checkpoint on the 30 spawn-difficulty labels
   plus 30 new effort labels taken from real spawns and judged by outcome, each beside its majority
   baseline, with GPU p50/p95.
3. Measure REA's footprint: the bytes its tool names add to a main chat and to a subagent, against the
   `polaris slim` budget; over budget → write the proposal (keep the skill, connect the MCP server only on
   demand). Change nothing about the registration.
4. `## Verdict`: which checkpoint, which host, Jev vs Laya on cost and latency, go/no-go for shadow-mode
   effort decisions.

### Acceptance
- [ ] The eight pinned headings exist; (a) and (b) answered from runtime evidence; (c) answered or "skipped: no key".
- [ ] Both label sets scored for both checkpoints, each beside its majority baseline; GPU p50/p95 per checkpoint.
- [ ] REA footprint in bytes for a main chat and a subagent, compared with the slim budget.
- [ ] Nothing in this repo changes except `docs/spikes/laya-jev-rea.md`; the venv, checkpoints, labelled sets and logs live outside it.

## T-191 — "Release prep 6.8.0 — the version number and one changelog entry for the effort ceiling, the Use-REA-to routing clause and the two spikes"
points 1 · risk normal · landed f5bab4a (2026-10-12) · claimed 2026-10-12
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
This sprint ships as its own release, before the next planned sprint. The kit is on 6.7.1, so this is
6.8.0. This task writes the two files a release needs from the repo: `kit/ops/VERSION` says
`version: 6.8.0`, and `CHANGELOG.md` gets ONE new entry at the top, `## 6.8.0 — <date>`, in plain words:
subagents can no longer run above the chat's effort, and you get one notice (never an automatic restart)
when you lower it mid-run; REA is set up on every armed machine and keeps itself updated after a 7-day
soak; "Use REA to…" works in any project. Include any numbers the lanes recorded in their Notes (guard
time, bytes added to CLAUDE.md).

### Acceptance
- [ ] `kit/ops/VERSION` says `version: 6.8.0`; the newest CHANGELOG heading is `## 6.8.0 — <date>`; the 6.7.1 entry is untouched below it.
- [ ] The entry covers the effort ceiling, the mid-run notice, REA arming, REA updates and the routing clause, in plain words.
