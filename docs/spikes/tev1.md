# Tev1, replayed on our own questions: does Together AI's local decision model beat the rules?

T-196 · 2026-10-27 · Ollama 0.40.11 · RTX 3070 (8 GB). The headings are pinned by `ops/contracts/tev1.md`.

## Verdict

**No-go. Neither checkpoint beats the majority baseline, let alone the rules, on the one set that
carries a rules answer (`test_depth`) — on the held-out split both checkpoints land BELOW baseline by
40-60 points, and 90 points below the rules.**

- `test_depth` (the decisive set, rules = `depth_for`-equivalent from `ops/contracts/test-depth.md` § 2):
  - `tev1:0.8b`: accuracy 0.250 vs majority baseline 0.700 (held-out 0.250 vs 0.667) vs rules 0.975
    (held-out 1.0). **39 points below baseline, 72-75 points below rules, on both the full set and the
    held-out split.**
  - `tev1` (4B): accuracy 0.075 vs baseline 0.700 (held-out 0.167 vs 0.667) vs rules 0.975 (held-out
    1.0). **Worse than the small checkpoint and worse than always guessing "none."**
  - Both checkpoints over-predict the expensive answers (`full`/`scoped`) on a set that is 70% `none`;
    the rules table gets this almost perfect because the questions are mechanical path-matching, not
    judgement, which is exactly what the rules are built for.
- `difficulty` (T-181, no rules answer defined — informational only): `tev1:0.8b` 0.400 vs baseline
  0.267 (held-out 0.556 vs 0.444); `tev1` 0.500 vs baseline 0.267 (held-out 0.778 vs 0.444). Both beat
  baseline here, the 4B checkpoint by the largest margin in this spike — but this set has no rules
  comparator and 30 items is a small denominator (one item ≈ 3.3 points).
- `effort` (T-190, no rules answer defined — informational only): `tev1:0.8b` 0.367 vs baseline 0.333
  (held-out 0.333 vs 0.444 — BELOW baseline held-out); `tev1` 0.300 vs baseline 0.333 (held-out 0.444 vs
  0.444 — tied). Neither checkpoint clears baseline on the held-out split.
- Net: the only set with a rules comparator is a clear loss for both checkpoints, by far more than
  noise (the held-out split is only 9-12 items, but the gaps are 40-90 points, an order of magnitude
  past what 9-12 items of noise could produce). The two sets with no rules comparator are mixed and do
  not change the call, because the contract's go bar requires beating BOTH the rules and the baseline,
  and the rules-bearing set is the one that matters for Sprint 19's `depth_for` decision.
- Sprint 19 (6.10.0) stays on the deterministic `depth_for` rules table; it does not build on Ollama +
  Tev1. The decision log (`.polaris/decisions.ndjson`, `test-depth.md` § 5) keeps collecting data for a
  future fine-tune, same as the no-go call in `docs/spikes/laya-jev-rea.md`.

## Checkpoints

| checkpoint | Ollama tag | digest | size on disk | GPU fit (8 GB card) |
|---|---|---|---|---|
| `tev1:0.8b` | `tev1:0.8b` | `abc31fdb0bf5` | 833 MB | fits fully: `ollama ps` reports 100% GPU, 1.3 GB resident |
| `tev1` (4B) | `tev1:latest` | `7954dce22bc6` | 4.6 GB | **does not fit fully**: `ollama ps` reports a 17%/83% CPU/GPU split, 6.5 GB combined footprint |

Ollama version: 0.40.11 (`ollama --version`). Both checkpoints were pulled by the owner before this
task resumed (prior attempt blocked on Ollama 0.30.7 with zero models pulled).

## Exchange

One real `POST http://127.0.0.1:11434/v1/systemone` request/response against `tev1:0.8b` (shape only;
the real question text is withheld per Invariant on transcript text):
```
POST /v1/systemone
{"model": "tev1:0.8b", "state": "<question state text>",
 "questions": {"q1": {"type": "choice", "instructions": "pick A or B", "criteria": {"A": "a", "B": "b"}}}}

200 OK
{"model": "tev1:0.8b",
 "answers": {"q1": {"type": "choice", "choice": "B",
   "probabilities": {"A": 0.4216, "B": 0.5784}, "confidence": 0.1568}},
 "usage": {"input_tokens": 104, "output_tokens": 0}}
```
Same wire shape as `laya-serve`'s `/v1/systemone` (`docs/spikes/laya-jev-rea.md` § laya-serve exchange):
`answers.<id>.choice` + `probabilities` + `confidence`, and a token-count-only `usage` block. Tev1's
`answers` block has no `answer_confidence` field (unlike Laya) — the replay script falls back to
`confidence` for Tev1, noted in § Confidence below. There is no `routing` block; the checkpoint served
is whatever Ollama resolves `model` to.

## Accuracy

Majority baseline = always answer the most common gold class. Held-out = last 30% of a seed-190
shuffle (9 items of 30 for `difficulty`/`effort`, 12 of 40 for `test_depth`). Rules = `ops/contracts/
test-depth.md` § 2's `depth_for` table applied to each commit's changed paths (`test_depth` set only;
the other two sets have no rules definition).

| set | n | checkpoint | accuracy | majority baseline | rules | held-out accuracy | held-out baseline | held-out rules |
|---|---|---|---|---|---|---|---|---|
| difficulty (T-181) | 30 | `tev1:0.8b` | **0.400** | 0.267 | — | 0.556 | 0.444 | — |
| difficulty (T-181) | 30 | `tev1` (4B) | **0.500** | 0.267 | — | 0.778 | 0.444 | — |
| effort (T-190) | 30 | `tev1:0.8b` | 0.367 | 0.333 | — | **0.333** | 0.444 | — |
| effort (T-190) | 30 | `tev1` (4B) | 0.300 | 0.333 | — | 0.444 | 0.444 | — |
| test_depth (new) | 40 | `tev1:0.8b` | **0.250** | 0.700 | **0.975** | **0.250** | 0.667 | **1.000** |
| test_depth (new) | 40 | `tev1` (4B) | **0.075** | 0.700 | **0.975** | **0.167** | 0.667 | **1.000** |

What the numbers mean:
- **`test_depth` is the set that matters for the go/no-go**, and it is a rout for the rules: 0.975-1.0
  for a deterministic path-matching table vs 0.075-0.25 for either checkpoint. The checkpoints predict
  `full`/`scoped` almost every time (`tev1:0.8b`: 39 of 40 `full`; `tev1`: 22 `full` + 16 `scoped` of
  40), on a set that is 28/40 `none` — they are badly miscalibrated toward the expensive answer on
  exactly the question `depth_for` already answers near-perfectly from path patterns.
- **`difficulty` favors the bigger checkpoint** (0.500 vs 0.400), and both beat baseline by more than
  one item. No rules comparator exists for this set.
- **`effort` is a wash to a loss.** Full-set numbers hover near baseline; held-out, `tev1:0.8b` drops
  below its own baseline and `tev1` ties it. Both checkpoints lean hard on one class (`tev1:0.8b`:
  20 of 30 "B"; `tev1`: 21 of 30 "A").

## Confidence

Tev1's `/v1/systemone` answers carry only `confidence` (entropy-based; no calibrated
`answer_confidence` field like Laya's). Mean confidence, correct vs wrong answers, per set:

| set | checkpoint | mean confidence (correct) | mean confidence (wrong) | separates? |
|---|---|---|---|---|
| difficulty | `tev1:0.8b` | 0.388 | 0.262 | some (+0.126) |
| difficulty | `tev1` (4B) | 0.503 | 0.304 | some (+0.199) |
| effort | `tev1:0.8b` | 0.197 | 0.198 | no (-0.001) |
| effort | `tev1` (4B) | 0.382 | 0.315 | weak (+0.067) |
| test_depth | `tev1:0.8b` | 0.366 | 0.426 | **inverted (-0.060)** |
| test_depth | `tev1` (4B) | 0.556 | 0.326 | some (+0.230), but only 3/40 were correct |

No set gives a confidence threshold worth gating on. `test_depth` is the worst case: the 0.8b
checkpoint is MORE confident when wrong than when right, and the 4B checkpoint's apparent separation
rests on 3 correct answers out of 40.

## Latency

Wall-clock through the HTTP exchange on loopback, after Ollama's model-load (model loads lazily on
first call; load time is included in that call's latency and excluded from these percentiles, same
convention as `laya-jev-rea.md`). All 100 items per checkpoint (30 + 30 + 40), p50/p95 nearest-rank per
set.

| checkpoint | set | p50 ms | p95 ms |
|---|---|---|---|
| `tev1:0.8b` | difficulty | 47 | 78 |
| `tev1:0.8b` | effort | 47 | 63 |
| `tev1:0.8b` | test_depth | 32 | 63 |
| `tev1` (4B) | difficulty | 140 | 172 |
| `tev1` (4B) | effort | 125 | 141 |
| `tev1` (4B) | test_depth | 110 | 126 |

The 4B checkpoint is roughly 2.5-3x slower than the 0.8b checkpoint at both p50 and p95, consistent
with the ~5.5x parameter difference and its partial CPU offload (see § VRAM). Both are well under
laya-serve's measured figures for base Laya (p50 52-103 ms, p95 74-282 ms), but neither checkpoint's
accuracy earns the latency budget.

## VRAM

`nvidia-smi --query-gpu=memory.used` before/after each run, plus `ollama ps` mid-run for the GPU/CPU
split. The card had ~3.8 GB already in use from another process throughout (same as T-181/T-190's
baseline load).

| checkpoint | VRAM before | VRAM after | delta | `ollama ps` split | fits in 8 GB alone? |
|---|---|---|---|---|---|
| `tev1:0.8b` | 3811 MB | 3840 MB | **+29 MB** | 100% GPU, 1.3 GB resident | yes, trivially |
| `tev1` (4B) | 3842 MB | 7503 MB | **+3661 MB** | 17%/83% CPU/GPU, 6.5 GB combined | **no — partially offloaded to CPU**, card peaked at ~7.5 GB of 8 GB total |

The 4B checkpoint does not comfortably share the 8 GB card with the ~3.8 GB already resident: Ollama's
own loader reports a CPU/GPU split rather than full GPU residency, and total GPU usage peaked within
~700 MB of the card's 8 GB ceiling. A production host running Tev1 4B alongside anything else on this
GPU would be VRAM-constrained even before weighing its accuracy loss.

## Method

- **Server.** Ollama 0.40.11, both checkpoints pulled by the owner (🚩 gate from the prior attempt,
  cleared 2026-10-27): `tev1:latest` (4.6 GB) and `tev1:0.8b` (833 MB). Ollama's own background service
  was already listening on `127.0.0.1:11434`; nothing was started or updated by this task.
- **Replay script.** `~/.claude/polaris/laya/tev1-replay.py` (machine-level, outside this repo),
  written in the prior attempt. This task fixed one bug found while resuming at step 5: the three
  label sets store their gold answer under a uniform `label` key, but the script's `SETS` table named
  mismatched keys (`"difficulty"`, `"effort"`, `"depth"`), which raised `KeyError` on the first run.
  Corrected to `"label"` for all three; no other change. Ran once per checkpoint:
  `python tev1-replay.py tev1:0.8b` and `python tev1-replay.py tev1`, against
  `http://127.0.0.1:11434/v1/systemone`. Raw per-run JSON written to
  `~/.claude/polaris/laya/data/tev1-tev1-0-8b.json` and `~/.claude/polaris/laya/data/tev1-tev1.json`.
- **Label sets** (all pre-existing from the prior attempt, unmodified; read-only on this repo):
  - `difficulty`: T-181's 30 hand labels (`set_spawn_difficulty.json`).
  - `effort`: T-190's 30 outcome-judged labels (`set_effort_outcome.json`).
  - `test_depth`: the new 40-commit set (`test-depth.jsonl`), built read-only from `git log
    --name-only` against `ops/contracts/test-depth.md` § 2's rule table for the `rule_label` field,
    then hand-checked for the `label` field (28 `none`, 1 `scoped`, 11 `full`). Both fields were
    produced before this task and are unchanged here.
- **Held-out split.** Seed 190, last 30% of a shuffle of each set's indices, same seed and convention
  the script uses for all three sets, reported alongside the full-set figure.
- **VRAM.** `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`, captured by the script
  immediately before and after each full run (both best-effort; not a hard dependency per the script's
  own docstring). `ollama ps` was also read manually mid-run for the GPU/CPU split, since the
  before/after delta alone does not show partial CPU offload.
- **Privacy.** This file carries counts and one synthetic-shape example only. The label sets, raw
  per-run JSON, and the replay script live under `~/.claude/polaris/laya/` (`data/`, `tev1-replay.py`),
  outside this repo. No transcript text or commit messages are reproduced beyond the shape already
  visible in `ops/contracts/test-depth.md` § 2's own examples.
