# Laya spike S1: measured facts for the Sprint 19 router

T-181 · 2026-09-24 · Laya 0.3.20, English checkpoint `convaiinnovations/laya` (ModernBERT-large, 421M).
Sprint 19 reads this file instead of redoing the work. Headings are pinned by `ops/contracts/speed.md` § 7.

## Verdict

**Host: `gpu`.** p95 is 230 ms on the GPU and 2,363 ms on the best CPU path (ONNX), and even the fastest CPU call was 5× the 150 ms bar.
**S19: go for shadow mode, plus the decision export. Act mode is no-go on the shipped checkpoint.** Zero-shot accuracy equals the majority baseline on both sets (0.27 vs 0.27, 0.60 vs 0.57). A fine-tuned checkpoint has to clear the D5 agreement bar before Laya picks a model or a compaction point.

What S19 should build on:
- **(a) works.** A PreToolUse `updatedInput` can set a spawn's `model`, so act mode has a lever.
- **(b) does not.** Writing `autoCompactWindow` mid-session changes nothing until the next session. S1-3's settings lever is out, and the nudge is what's left.
- **(c) is partial.** A UserPromptSubmit `systemMessage` reaches the human only. Anything meant for the model goes in `additionalContext`.

## Latency

These times come from a resident process: the checkpoint is loaded once, then 3 warm-up calls run and are discarded. Each call asks one question: a 4-option difficulty choice for a spawn text, or a 2-option topic choice for a prompt pair. The 50 real texts ran twice, so each row covers 100 timed calls.

| host | runtime | p50 ms | p95 ms | fastest ms | load s | notes |
|---|---|---|---|---|---|---|
| `gpu` | torch 2.14 + CUDA 12.6, fp16 autocast | **154** | **230** | 87 | 20 | peak VRAM 2.3 GB; fits the ~4 GB the local GPU (8 GB) had free |
| `cpu` | ONNX Runtime 1.23 (CPU EP), fp32 | 1,905 | 2,363 | 740 | 22 | graph exported on this machine (see Method) |
| `cpu` | torch 2.14 CPU, fp32 | 4,697 | 11,759 | 1,537 | 18 | the baseline before ONNX |

**What was loading the machine.** Every run happened with the machine's CPU at 94–100% busy from other work, and with the GPU shared with another process (~4.3 GB VRAM, ~40% utilisation). So all three rows are upper bounds. The host choice holds anyway: the fastest CPU call (740 ms) was still 5× the 150 ms bar that decided whether to install CUDA. The GPU row also carries the CPU contention, because a one-question forward pass spends much of its time launching kernels from Python.

**For S19:**
- Start the daemon without blocking, because a load takes ~20 s.
- Size the loopback timeout from `metrics --laya` p95 measured on a normal day, not from these loaded numbers.
- Budget roughly 150–250 ms per decision for this checkpoint.
- Laya's `[fast]` TileLang path and `laya-multilingual` (mmBERT-base, ~2× faster per its README) were not measured. They are the next levers if 230 ms is too slow.

## Probes

All three probes ran headless (`claude -p`, `--max-turns` ≤ 3) in a throwaway git repo outside this one. They used Claude Code **2.1.281**, the IDE build. The `claude` on PATH was 2.1.251 and was not used. `--setting-sources project,local` kept the machine's own user hooks out of the probe. The session model was Opus 5.5 with a 1M window.

| probe | answer | evidence |
|---|---|---|
| (a) PreToolUse `updatedInput` sets an Agent's `model` | **yes** | Details below. |
| (b) `autoCompactWindow` written to `.claude/settings.local.json` mid-session takes effect | **no** | Details below. |
| (c) a UserPromptSubmit `systemMessage` is visible | **partial** | Shown to the human, not to the model. Details below. |

**(a) Evidence.**
- *Setup.* A PreToolUse hook (matcher `Agent\|Task`) returned `permissionDecision: "allow"` and an `updatedInput` equal to the original input plus `"model": "sonnet"`. The spawn the model wrote had no `model` field.
- *With the rewrite.*
  - PostToolUse saw `tool_input.model = "sonnet"`.
  - `tool_response.resolvedModel` was `claude-sonnet-5`.
  - The subagent's messages and the run's `modelUsage` show `claude-sonnet-5`, while the parent stayed on Opus.
- *Control, same prompt without the rewrite.* `resolvedModel` was the session's Opus model.
- *Caveat.* `updatedInput` replaces the whole input, so the hook must echo every original field.
- *Implication for S19 (from the hooks docs, not tested).* "All matching hooks run in parallel." A sibling PreToolUse hook, such as the S17 layer-4 spawn check, therefore sees the spawn before the rewrite. Layer 5, the PostToolUse check of `resolvedModel`, does see the rewritten model, as observed here.

**(b) Evidence.** One long-lived session was driven through `--input-format stream-json`. `/context` is a local command, so it cost $0.
1. `/context` reported `/ 1m`.
2. The probe wrote `{"autoCompactWindow": 200000}` to `settings.local.json`.
3. A `ConfigChange` hook fired (`source: local_settings`), which proves the file watcher reloaded the file.
4. `/context` sent after that event still reported `/ 1m`.
5. A fresh session started with the same file reported `/ 200k`.

The docs agree:
- `/autocompact` "saves it to your user settings … and applies it to the current session". The command applies the value itself; the saved file does not.
- The binary seeds the session's window once at start-up, from the `--autocompact` flag or else the merged settings. Afterwards only `/autocompact` or the SDK's `apply_flag_settings` control request change it.
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW` overrides everything, but it too is read when a session starts.

So S1-3 has no settings-file lever. What remains is the nudge, or a window chosen at launch.

**(c) Evidence.** One UserPromptSubmit hook returned a `systemMessage` carrying one codeword and an `additionalContext` carrying another. The model was asked to list every codeword it could see.
- The model named only the `additionalContext` codeword.
- The `systemMessage` appeared in the output stream as a `system`/`informational` notice ("UserPromptSubmit says: …"), which is the user-facing channel.
- The hooks docs agree: `systemMessage` is a "warning message shown to the user".

For S19, S1-3's "/compact now" nudge works as a `systemMessage` because it is addressed to the human. Anything the model must act on belongs in `additionalContext`.

## Zero-shot accuracy

Both sets were answered on the `gpu` host with neutral option keys (A/B/C/D, A/B), as Laya's README advises. Each option's text describes its class; the keys themselves carry no meaning.

| set | n | classes (gold count) | Laya zero-shot | majority baseline | what it predicted |
|---|---|---|---|---|---|
| spawn difficulty | 30 | A trivial_tool 8 · B mechanical 8 · C standard 7 · D deep 7 | **0.267** (8/30) | 0.267 (A) | spread across all four classes; chance is 0.25 |
| continuation vs new topic | 30 | A continuation 17 · B new topic 13 | **0.600** (18/30) | 0.567 (A) | "continuation" on 29 of 30 |

**Neither set shows usable signal.**
- *Difficulty.* The result matches the baseline, and confidence did not separate right answers from wrong ones (mean 0.056 vs 0.062).
- *Continuation.* The model answers the majority class almost every time, so its 0.03 edge is one lucky item. It caught 1 of the 13 new-topic pairs.
- *Cross-check.* The CPU ONNX host gave the same continuation answers and 0.300 on difficulty (one item flipped), so the result does not depend on the host.

This matches the README's own warning that the base checkpoints are "near chance on typed-decisions zero-shot". The labelled sets are the seed for the S1-5 export and fine-tuning. They live under `~/.claude/polaris/laya/data/`.

## Method

**Install.**
- A venv at `~/.claude/polaris/laya/venv` holds `python -m pip install "laya[onnx]"` on Python 3.10.11. That pulled laya 0.3.20, torch 2.14.0 (CPU), transformers 5.17, onnxruntime 1.23.2 and onnx 1.23.
- CUDA torch (`torch==2.14.0` from the PyTorch cu126 index) went into the same venv only after CPU p95 came in above 150 ms.
- It is a machine-level install, owner-approved under plan D7. Nothing in this repo depends on it.

**ONNX.** The Hub checkpoints ship no `.onnx` file, so the graph had to be exported on this machine.
- Upstream `scripts/export_onnx.py` fails on torch 2.14 without `onnxscript`, because the default exporter is now dynamo.
- Forcing the legacy exporter (`dynamo=False`) exports, but it bakes the traced sequence length into an attention `Reshape`. Every real input then fails at run time.
- Installing `onnxscript` (0.7.2) and running the upstream script unchanged works: a ~5 min export produced 1.7 GB of fp32 weights.
- S19 must either build this artifact on each machine or skip ONNX.

**Texts.** Everything was read-only, from `~/.claude/projects/*/*.jsonl`.
- The pull found 294 `Agent`/`Task` spawns (290 unique descriptions) and ~50 distinct human prompts. Programmatic prompts, hook notices and tool results were filtered out.
- *Latency set.* 25 spawn texts (the description plus the first part of the brief, ≤ 500 chars) and 25 prompt pairs (previous and new request, ≤ 400 chars each).
- *Difficulty set.* 30 hand-picked spawns, labelled by the builder from the description and brief:
  - trivial_tool: land, promote, run-and-hand-off, read-only listing
  - mechanical: version bumps, golden refreshes, code lookups, docs
  - standard: feature builds and traces that need judgement
  - deep: sprint planning, design, adversarial review, audits, platform-only debugging
- *Continuation set.* 30 real prompt pairs:
  - 16 consecutive pairs from one session
  - 14 pairs that join the last prompt of one session to the first prompt of the next session in the same project
  - Labels were assigned by the builder. The one ambiguous within-session shift was labelled "new topic".
- This file carries counts only, never transcript text.

**Questions.** One `choice` question per call, with option keys A–D (difficulty) and A/B (topic):
- *Difficulty*: "How much reasoning does this delegated coding-agent task need?", with one description per class.
- *Topic*: "Does the new request continue the previous request's work, or start a different topic?", asked over a `{previous_request, new_request}` state.

**Timing.**
- `time.perf_counter()` around `predict()`, with `torch.cuda.synchronize()` on the GPU.
- p50 and p95 are nearest-rank over the 100 calls.
- System CPU load was sampled before and after each run.

**Probe costs.** About $0.40 in total across the headless runs, all on Opus plus one Sonnet subagent. Every `/context` call cost $0.

**Scripts, sets, raw timings and per-call results** all live under `~/.claude/polaris/laya/` (`scripts/`, `data/`), outside the repo.
