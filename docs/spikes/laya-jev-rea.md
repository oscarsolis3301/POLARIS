# Laya and Jev, studied with REA: checkpoints, the wire exchange, accuracy, and what REA costs

T-190 · 2026-10-12 · REA 6.4.0 · Laya 0.3.20 · RTX 3070 (8 GB). Sprint 19 reads this file instead of
redoing the work. The headings are pinned by `ops/contracts/rea.md` § 4.

The `laya-typed-decisions` checkpoint was downloaded with the owner's yes (2026-10-11): only the bundle
subfolder `https://huggingface.co/convaiinnovations/laya/tree/main/typed-decisions`, 846,195,716 bytes
(807 MiB), into `~/.claude/polaris/laya/hf/`. The router fetches that subfolder by default. The same
files are also published as their own repo, `convaiinnovations/laya-typed-decisions`.

## Verdict

- **Checkpoint: neither shipped checkpoint is usable zero-shot. `laya-typed-decisions` is the one to
  fine-tune from.**
  - Base `laya`: difficulty 0.267, the same as the 0.267 baseline. Effort 0.400 against 0.333, but it
    answered "medium" 24 times out of 30.
  - `laya-typed-decisions`: difficulty 0.300 against 0.267. Effort 0.367 against 0.333.
  - Every margin above is one or two items out of 30.
  - typed-decisions never answers "low" effort, and answers "deep" difficulty on 16 of 30.
  - On both checkpoints, `answer_confidence` is the same on right and wrong answers.
  - Why typed-decisions is still the starting point for S19's fine-tune: it is the faster of the two
    here, it has a 1024-token window, and it has already been fine-tuned on decision workflows.
- **Host: `laya-serve` on the local GPU, bound to loopback.**
  - Short spawn text, base checkpoint: p50 52 ms / p95 74 ms.
  - The ~500-character label-set texts: base p50 103 / p95 282 ms; typed-decisions p50 88 / p95 154 ms.
  - Load time to `/health`: 21 s for base, 6 s for typed-decisions on a warm disk.
- **Jev vs Laya on cost and latency: unmeasured.** There is no key, so part (c) was skipped. Laya costs
  nothing per call. The server reports `usage.input_tokens` of 69–215 per request and `output_tokens`
  is always 0. That usage block is the unit a paid Jev bill would meter.
- **Shadow-mode effort decisions: no-go on both shipped checkpoints.**
  - Neither checkpoint beats its baseline by more than two items, so shadow-mode logs would measure
    noise against the D5 agreement bar.
  - Go instead for S19's decision export. Its first job is to grow the outcome-judged effort set past 30
    and fine-tune `laya-typed-decisions` on it.
  - Shadow mode starts once a fine-tuned checkpoint clears its baseline on a held-out set.
  - The wire contract and the host below are ready for that.
- **REA footprint: over budget, and the owner has decided.** REA adds about 5.8 kB to every main chat
  and every subagent, a third on top of the 17.7 kB that `polaris slim` measures per context today.
  The owner has decided REA connects on demand (see § REA footprint). This task did not change the
  registration.

## Checkpoints

**(a) Which checkpoint answers which question.** The evidence is the installed package plus its
runtime routing. REA 6.4.0 has no route for a Python package: `inspect-artifact` on the package
directory returned `target_unavailable` ("open_binary accepts files and macOS app bundles"). On the
`laya-serve.exe` launcher it inventoried a PE console-script shim (evidence
`ev_07c197c3ac522265b6181d6df6843bdd1bdf19568affd0396046852e3ada3a50`). So the routing facts below come
from the shipped `laya/router.py` and `laya/serve.py`, and from the router's own `routing` block on
every live response, which the REA capture records (see § laya-serve exchange).

| checkpoint | Hub id | size | when the router picks it |
|---|---|---|---|
| english | `convaiinnovations/laya` (bundle root) | 421M params, 804 MiB fp32, 512 tokens | English Latin text; also the default when the language cannot be identified |
| multilingual | bundle subfolder `multilingual` | 322M, 1024 tokens | non-Latin script, or Latin text that is not English |
| typed-decisions | bundle subfolder `typed-decisions` | 421M, 846 MB, 1024 tokens | **never automatically**. Only on an explicit `model` or `task`, or with `LAYA_AUTO_TASK=1` when the question ids match one of its four trained workflows |

The order of precedence is: explicit `model`, then explicit `task`, then a detected workflow (opt-in
only), then `lang`, then `lang_guess`, then script detection, then the default. The four workflows
whose question ids trigger auto-routing are `agent_trace_observability`, `customer_service`,
`invoice_processing` and `security_incidents`. None of them is ours, so **S19 must name
`typed-decisions` explicitly**, because auto-detection will never select it for our questions.

**How confidence is calibrated.** Every answer carries two numbers, and only one of them is calibrated:
- `answer_confidence` is max(p) after temperature scaling. The temperatures ship in each checkpoint's
  `rl_agent_config.json`, one per question type and per option-count bucket. On the base checkpoint
  they are: choice 1.64; choice with 2 options 1.91; choice with 3–5 options 1.76; choice with 11+
  options 0.10; noul 1.98; score 1.25. The package documents this as the quantity its ECE figures are
  computed on.
- `confidence` is 1 − H(p)/log k, the normalised entropy. The package itself marks it "not calibrated".
- **For S19:** gate on `answer_confidence`, never on `confidence`. T-181's 0.056-vs-0.062 comparison
  used `confidence`. Re-run on `answer_confidence`, neither checkpoint separates right answers from
  wrong ones (see § Accuracy).
- **The 3–5-option temperature was not refitted.** typed-decisions refits the per-type temperatures
  to ~1.01–1.06, but its `temperature_by_options` buckets are byte-identical to the base checkpoint's.
  Our 3- and 4-option questions use the 3–5 bucket, so their calibration comes from the base model,
  not the fine-tune.
- The package warns that the English checkpoint is confidently wrong off-language (ECE 0.855 on Hindi).
  Our traffic is English, so the router keeps it on `english` (observed `routed: english` on all 60
  items).

## laya-serve exchange

**(b) The real exchange.** `laya-serve` (Laya 0.3.20) ran on `127.0.0.1:18917` with
`LAYA_DEVICE=cuda`, `LAYA_MODELS=english` and `HF_HUB_OFFLINE=1`. It answered `/health` 21 s after
start. A client recorded 52 exchanges as HAR 1.2. REA's `inspect-web-network-capture` decoded the
capture (evidence `ev_a4a78c165dc3fb6adb1bb787917a8b455d0b55947cb08834c78b6f0535c571d8`, 52 records,
capture sha256 `9404a711…`). The capture and the scripts live under `~/.claude/polaris/laya/rea/`.

Request, `POST /v1/systemone`, `Content-Type: application/json`:
```
{"model": "<optional>", "state": <string or object>, "questions": {"<id>": {"type": "choice"|"score"|"noul", "instructions": "...", "criteria": ...}}}
```
Response, 200:
```
{"model": "laya-rl-agent",
 "answers": {"<id>": {"type": "choice", "choice": "A", "probabilities": {...}, "confidence": 0.17, "answer_confidence": 0.54, "action": {"act_probability": 1.0}}},
 "usage": {"input_tokens": 107, "output_tokens": 0},
 "routing": {"model": "english", "repo": "convaiinnovations/laya", "reason": "English Latin text", "detection": {...}, "workflow": null}}
```

What the capture shows:
- **Answer shapes.**
  - `score` answers carry `score` (the expected value), `legend` and `probabilities`.
  - `noul` answers carry `noul` (p(true)) and no `probabilities`.
  - A dict `state` is accepted.
- **The top-level `model` is the head's name** (`laya-rl-agent`), not the checkpoint. The checkpoint is
  `routing.model`, so a client that logs the checkpoint must read `routing.model`.
- **The `model` field.**
  - A Jev model id (`jev-1`) is ignored and auto-routed.
  - `english` is honoured.
  - The Hub ids `convaiinnovations/laya-multilingual` and `convaiinnovations/laya-typed-decisions` are
    accepted.
  - Naming a checkpoint that is not on disk while `HF_HUB_OFFLINE=1` is set returns
    `500 {"detail":"inference failed"}`. **Without** offline mode, the same request would start an
    846 MB download in the middle of the request. S19 must start the daemon with `HF_HUB_OFFLINE=1`
    and `LAYA_MODELS` pinned.
- **Errors.**
  - A missing `questions` field gives 400.
  - A malformed question gives 422, with a message naming the question.
  - `state` over 50,000 characters gives 413.
  - Other caps: 64 questions and a 2 MiB body.
  - A bearer token is checked only when `LAYA_API_KEY` is set.
- **Defaults S19 must override.** The server binds `0.0.0.0:8000` with no auth unless told otherwise.
  Set `LAYA_HOST=127.0.0.1`. Port 8000 and our first choice, 18790, were both taken on this machine;
  18790 belonged to another local adapter. Use the port POLARIS allocates, never a fixed one.
- **One request at a time.** There is a single inference worker behind an asyncio lock, so concurrent
  spawns queue behind each other.

## Jev

skipped: no key. The conductor passed no env-var name for an owner key, so Jev's hosted API was not
called. What is known without a call: `laya-serve` describes itself as speaking "TypeSafe Jev's
`/v1/systemone` wire protocol", and says a Jev client (`hs-jev`) works against it unchanged by decoding
`answers` and `usage` and ignoring `routing`. A client built for S19 against the exchange above should
therefore also work against Jev. That is an inference, not an observation.

## Accuracy

Both sets were answered through the live `laya-serve` exchange on the GPU, with neutral option keys.
Majority baseline = always answer the most common gold class.

| set | n | gold classes | checkpoint | accuracy | majority baseline | what it predicted | answer_confidence right / wrong |
|---|---|---|---|---|---|---|---|
| spawn difficulty (T-181 labels) | 30 | A 8 · B 8 · C 7 · D 7 | base `laya` | **0.267** | 0.267 | A 11 · B 4 · C 7 · D 8 | 0.374 / 0.389 |
| spawn difficulty (T-181 labels) | 30 | same | `laya-typed-decisions` | **0.300** | 0.267 | A 1 · B 4 · C 9 · D 16 | 0.323 / 0.319 |
| effort, judged by outcome (new) | 30 | low 10 · medium 10 · high 10 | base `laya` | **0.400** | 0.333 | low 3 · medium 24 · high 3 | 0.475 / 0.494 |
| effort, judged by outcome (new) | 30 | same | `laya-typed-decisions` | **0.367** | 0.333 | low 0 · medium 16 · high 14 | 0.466 / 0.447 |

What the numbers mean:
- **Base, difficulty.** It reproduces T-181 exactly, which shows the live server and T-181's in-process
  run agree.
- **Base, effort.** The 0.067 edge is two items. It comes from answering "medium" for 80% of the set,
  which happens to be right for a third of a balanced set.
- **typed-decisions.** Each edge is one item.
  - It leans hard toward the expensive end: "deep" on 16 of 30 difficulty items, and "low" effort on
    none.
  - Used for effort, that bias would spend more, not less.
  - Its 0.766 on Laya's own benchmark does not carry over to our questions, which are not among its
    four trained workflows.
- **Confidence.** On every row, the gap between right and wrong answers is under 0.02, so no gating
  threshold can be set on these checkpoints.

## Latency

Every row is wall-clock time through the HTTP exchange on loopback, after the checkpoint is loaded and
3 warm-up calls are discarded. p50 and p95 are nearest-rank. The GPU was shared with another process
throughout (1.9–3.9 GB VRAM in use before ours, 9–29% utilisation).

| host | checkpoint | texts | calls | p50 ms | p95 ms | fastest ms |
|---|---|---|---|---|---|---|
| `gpu` laya-serve | base `laya` | one short synthetic spawn line, 1 question | 40 | **52** | **74** | 49 |
| `gpu` laya-serve | base `laya` | the 60 label-set spawn texts (≤ 500 chars), each twice | 120 | **103** | **282** | 68 |
| `gpu` laya-serve | `laya-typed-decisions` | the same 60, each twice | 120 | **88** | **154** | 55 |
| `gpu` in-process (T-181) | base `laya` | 50 texts, twice | 100 | 154 | 230 | 87 |
| Jev hosted | — | — | — | skipped: no key | — | — |

The machine was less loaded than during T-181, which explains why the short-text p50 is faster than
T-181's in-process figure. The tail is set by input length: a ~500-character spawn text roughly doubles
p50 compared with a one-line text. `typed-decisions` runs the same ModernBERT-large encoder with a
1024-token window. It came out faster here (p95 154 vs 282 ms), but the two runs were sequential on a
shared GPU, so treat them as the same speed class rather than a ranking. Load time to `/health` was
21 s for base (in line with T-181's 20 s) and 6 s for typed-decisions.

## REA footprint

Measured in bytes of text injected into the context, on Claude Code 2.1.251. A headless probe connected
the user-scope `rea` MCP server and spawned one subagent. The bytes were then read from the probe's own
transcripts, from the `deferred_tools_delta` attachments.

| what REA adds | main chat | subagent | how it was measured |
|---|---|---|---|
| 170 deferred tool names (`mcp__rea__…`, one per line) | **5,206 B** | **5,206 B** | read from the transcripts, both contexts |
| MCP server instructions | 304 B | 304 B (assumed: same system prompt) | from the server's `initialize` reply |
| `reverse-engineer-anything` skill listing line | ~300 B (~110 tokens in `/context`) | ~300 B | listing line; `/context` Skills table |
| **total per context** | **~5.8 kB (~1.45k tokens)** | **~5.8 kB** | |
| full schemas, if a session ever loads them all | 465 kB (`/context`: 198.7k tokens "deferred") | same | never injected unless fetched |

Against the `polaris slim` budget:
- `polaris slim` reports **17,661 B** paid per context today (11,906 B kept for POLARIS, 5,755 B
  unrecognised). REA alone adds **+33%** to that.
- A conductor run spawns 6–8 contexts, so REA costs ~35–46 kB per run. That is roughly a quarter of
  everything slim archived (24 kB per context) handed back.
- **Over budget.**

Other findings from the measurement:
- **Contexts started before the server connects get no REA tools at all.** A headless session's
  `init` showed `rea: pending` with 0 REA tools, and 170 tools ~20 s later.
- **No real session has used REA yet.** Of 500 real transcripts with tool deltas (202 main, 298
  subagent), none carries a REA name. The registration is from 2026-10-11 22:52, after every one of
  them started.
- **This study needed no MCP tools.** It used REA only through the `rea` CLI (`inspect-artifact`,
  `inspect-web-network-capture`, `mcp doctor`) via Bash. That is direct evidence that the CLI covers
  the job without the 5.8 kB per context.

**Owner decision.** "Owner 2026-10-11: REA connects on demand — skill and CLI always installed, MCP
server connected only when 'Use REA to…' is invoked." It adopts the proposal below. This task did not
change the registration. Putting the decision into effect is the follow-up named at the end of the
proposal.

**The proposal it adopts.** Keep the `reverse-engineer-anything` skill (~300 B) and
the global `rea` CLI. Take the `rea` MCP server out of the always-on user scope, and connect it only
when a "Use REA to…" request needs a tool the CLI lacks, which REA's own skill already supports
("Connect only when needed"). That saves ~5.5 kB per context, ~33–44 kB per conductor run. T-187's
`arm_rea` registers machine-wide through `rea setup --client claude_code`, so adopting this also needs
a change to what arming registers. That is a follow-up for the Planner, not part of this task.

## Method

**REA.**
- REA 6.4.0, the global npm CLI. `rea mcp doctor` reports healthy: 170 tools, 6 prompts, catalog
  digest `85d80276…`.
- The REA MCP tools were not available inside this builder's own context (see § REA footprint for
  why), so every REA operation ran through the CLI.
- Routes used:
  - `inspect-artifact`: works on a file, refuses a directory.
  - `inspect-web-network-capture`: the HAR route, used for (b).
- `capture-process` is Linux/macOS only, so it was not usable on this Windows host. That is why (b)
  was captured as HAR by a client and then decoded by REA.

**Server.**
- `laya-serve` needed the `serve` extra: fastapi 0.143, uvicorn 0.54, python-multipart, pydantic 2.14.
  It was installed into the existing machine-level venv `~/.claude/polaris/laya/venv` with
  `pip install "laya[serve]==0.3.20"`. Torch and the laya version did not change.
- The base checkpoint came from the existing Hub cache.
- `laya-typed-decisions` was downloaded after the owner's yes. Only the `typed-decisions/*` files of
  the bundle were fetched, into `HF_HUB_CACHE=~/.claude/polaris/laya/hf`.
- Each checkpoint was served alone (`LAYA_MODELS` pinned), with `HF_HUB_OFFLINE=1` set on every server
  run, on `127.0.0.1:18917`. The server was stopped after each run.
- Scoring used the calibrated `answer_confidence` field.

**Labels.**
- *Difficulty:* T-181's 30 hand labels, unchanged.
- *Effort:* 30 new labels, built by `~/.claude/polaris/laya/rea/build_effort_set.py`.
  - Source: 300 real subagent transcripts under `~/.claude/projects/*/*/subagents/`, read-only.
  - Each spawn was labelled by its **outcome**: output tokens the run used, tool calls, and whether it
    ended stopped (⛔ / blocked).
  - **low** = finished cleanly with under 15k output tokens.
  - **medium** = finished cleanly with 15k–60k output tokens.
  - **high** = over 60k output tokens, or the run stopped short.
  - Selection: 10 per class, seeded random (seed 190). Probes, spawns under 5 tool calls and T-181's
    texts were excluded.
- The model saw the description plus the start of the brief (≤ 500 characters) and one 3-option
  choice: "How much reasoning effort will this delegated coding-agent task turn out to need?"

**Footprint.**
- Tool names, schemas and server instructions came from a direct MCP `initialize` + `tools/list`
  against the registered server (`~/.claude/polaris/laya/rea/mcp_footprint.py`).
- Per-context bytes came from a headless `claude -p` stream-json probe in a throwaway repo outside this
  one. It ran `/context` twice (local, $0) and spawned one subagent, which cost $0.71 on Opus with a
  Sonnet subagent. Bytes were read from that probe's main and subagent transcripts.

**Privacy.** This file carries counts, ids of public checkpoints and synthetic example text only. The
label sets, the HAR capture, per-item results and scripts live under `~/.claude/polaris/laya/`
(`data/`, `rea/`), outside the repo.
