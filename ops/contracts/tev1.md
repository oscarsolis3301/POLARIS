# CONTRACT: tev1 — does Together AI's Tev1 beat the rules on our decisions?            (v1 — 2026-10-27)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-d-like-to-improve-playful-gosling.md` § D (owner-approved
2026-10-27, owner decision: "measure Tev1 to see whether it benefits us") · task T-196 ·
`plan: stay-on-request`. A spike: NO kit code, NO integration.

## Purpose
Decide go/no-go for building Sprint 19 (now 6.10.0) on Ollama + Tev1 instead of the `laya-serve`
daemon, from numbers measured on our own questions.

## The output — `docs/spikes/tev1.md`
Same headings as `docs/spikes/laya-jev-rea.md` where they apply, pinned:
```
## Verdict      go | no-go, one paragraph; every margin stated against BOTH the majority baseline and the rules
## Checkpoints  tev1:0.8b and tev1 (4B): Ollama version, model digests, sizes
## Exchange     one real /v1/systemone request→response from Ollama (shape only, no transcript text)
## Accuracy     per checkpoint × label set: accuracy, majority baseline, rules (test-depth set only), held-out split
## Confidence   does confidence separate right from wrong (e.g. accuracy above/below a threshold)
## Latency      p50/p95 per checkpoint on the RTX 3070
## VRAM         peak use, 4B sharing the 8 GB
## Method
```

## Label sets (all outside the repo, `~/.claude/polaris/laya/data/`)
- T-181 difficulty: the existing 30 items. T-190 effort: the existing 30 items.
- NEW test-depth set, ~40 past kit commits, built READ-ONLY from `git log --name-only` on this repo:
  each labelled `none | look | scoped | full` by applying `ops/contracts/test-depth.md` § 2's rule
  table to its changed paths with the § 1 default patterns and this repo's `ops/SURFACES.tsv`
  (the "rules" answer), then hand-checked; record both the rule label and the judged label. Saved
  as `test-depth.jsonl` with the same state/question shape as the other sets.
- The replay script lives at `~/.claude/polaris/laya/tev1-replay.py` (machine-level, outside the repo).

## Go / no-go
- **Go** = beats BOTH the rules and the majority baseline by more than noise on a held-out split
  (state the split and the margin). Then Sprint 19 builds on Ollama + Tev1 and drops its daemon task.
- **No-go** = anything else, including "Ollama could not be updated" or "models not pulled" — the
  decision log (`.polaris/decisions.ndjson`, test-depth.md § 5) keeps collecting data for a fine-tune.

## 🚩 Owner gate (the builder never runs these itself)
Updating Ollama to ≥ 0.35 and pulling `tev1:0.8b` (812 MB) and `tev1` (4.5 GB) are large downloads
and a software update: the owner's step. The builder does every step that needs neither first, then
hands back with ONE paste-ready block (one command per line, no `&&`, no placeholders) and the sizes.

## Invariants
- Nothing in the repo changes except `docs/spikes/tev1.md`.
- Numbers and short paraphrases only — never transcript text, never a key (Invariant 10).
- Model ban holds inside any probe (never haiku or fable; never `claude-code-guide`).

## Changelog
- v1 2026-10-27: created for T-196 (plan stay-on-request).
