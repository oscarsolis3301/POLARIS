# POLARIS v5 — install & operate

Drop-in parallel-agent operating system for any repo. Any model/CLI that loads a repo instruction file runs it; under Claude Code the shipped `.claude/` folder adds a project **skill** (sessions auto-discover the protocol) and a **PreToolUse write-guard**. `CLAUDE.md` stays a thin router on purpose — adherence drops on long instruction files.

New in v5, the guard and the gates enforce **two** things: ownership (diff ⊆ `files_owned`, unchanged since v3) and **RULES** — your repo's policy as data. One TAB-separated line in `ops/RULES.tsv` is a danger zone (`path`: forbidden to write, even inside owned files) or a content guard (`content`: added lines must not match an ERE). INIT turns your "never touch X" interview answers into armed rules instead of prose; EVOLVE proposes new lines from kickback/Learned evidence and a human approves each one. That is "hooks that create themselves" done safely: evidence → proposal → approve → one appended line, zero new scripts.

## Install (any repo, greenfield or 10k files)
1. Copy `CLAUDE.md` + `ops/` + `.claude/` into the repo root. `chmod +x ops/polaris ops/hooks/ownership-guard.sh`.
   - Repo already has a `CLAUDE.md`? Paste the POLARIS content at the TOP (constraints early = better adherence).
   - Repo already has `.claude/settings.json`? Merge the `hooks` block instead of overwriting.
   - Upgrading a live v3 or v4 board? Copy the kit files over, then `bash ops/polaris upgrade` (idempotent; board, tasks and locks untouched — v5 adds no task frontmatter fields, so there is zero task migration).
2. Commit. Open a session: **"You are INIT."** It runs `doctor` (+ `--selftest` on a machine's first use), surveys within a hard read budget, interviews you (~10 questions), writes `ops/MAP.md` / `CONVENTIONS.md` / `SPRINT.md`, and arms `ops/RULES.tsv` from your danger-zone answers.
3. Claude Code will ask to trust the project hook on first use — that's the write-guard; approving it is expected. (Read it first: `ops/hooks/ownership-guard.sh`, ~100 lines.)

## The loop (every sprint) — kickoffs in `ops/PROMPTS.md`
1. **Plan** — 1 session: PLANNER reads `metrics` (per-point calibration) + `drift`, runs a pre-mortem against the Learned log, then grooms your idea into contract-backed, file-disjoint tasks.
2. **Fan out** — `bash ops/polaris fleet N` (or N terminals with the identical Builder kickoff).
3. **Watch** — `bash ops/polaris dash` → **http://127.0.0.1:7373**: constellation task graph, six columns, ticking lock ages, **points strip**, **drift rail**, metrics, Learned log — plus an opt-in 🔔 that fires a browser notification the moment any task changes column. Read-only, SSE, stdlib-only Python.
4. **Integrate** — 1 session: INTEGRATOR audits (ownership + rules), batch-merges, runs the suite once, runs your optional `uat:` command once, lands, sweeps, runs `drift`, promotes.
5. **Evolve** (optional, between sprints) — EVOLVE reads `metrics`/`drift`/`rules` + Learned and proposes ≤3 evidence-backed amendments — including new RULES lines; nothing applies without your "approve".

## Why it can't conflict
The Planner assigns every task a disjoint `files_owned` set — and v5 makes that invariant **machine-checkable**: `ops/polaris drift` cross-tests every pattern pair across `ready/ ∪ active/` (identical · exact⊂glob · exact⊂dir/ · dir/⊂dir/ are proven; non-identical glob∩glob is undecidable, which is why the Planner rule says keep globs narrow). Enforcement of ownership + rules is three-deep: the write-guard blocks at the keystroke (Claude Code), `polaris verify`/`handoff` proves it on the diff (ANY model or CLI), and `polaris audit` re-proves it before merge (optionally in CI — `ops/ci/polaris-audit.yml`, which can also gate on `drift --strict`). The only runtime race — two Builders grabbing one task — is broken by an atomic lock, or a claim-branch push for multi-machine setups.

## Points, calibrated
Every `claim` and `done` telemetry line now carries the task's points, so `polaris metrics` reports cycle-p50 **per point bucket** — "your 3-pointers actually take 9h" is the sentence that fixes pointing. The Planner reads it before every sprint; EVOLVE watches it across sprints; the dashboard shows ready/WIP points at a glance.

## Optional per-repo keys (CONVENTIONS.md)
`uat: <cmd>` — an end-to-end suite the Integrator runs ONCE on the integrate branch (red bisects exactly like a red unit suite). `notify: <cmd>` — runs in the background on every board event with `POLARIS_EV`/`POLARIS_ID`/`POLARIS_NOTE` env vars; wire it to ntfy, Slack, `osascript`, anything — it can observe the board but can never stall or fail it. Both are slots, not dependencies: POLARIS stays language-agnostic and ships neither.

## Dependencies — still deliberately near-zero
git ≥ 2.5 + bash (+ your test runner). The dashboard needs a stock **Python 3.8+, stdlib only — no pip, no node, no build step**. Windows: **Git Bash**. The moat is the protocol, not tooling.

## Verified / unverified — this build
Verified by execution: v5 selftest end-to-end (8-way claim race → 1 winner · ownership accept/reject · verify commands · handoff · done cleanup · claim/done events **with points** · per-point metrics buckets · `_match` · RULES path deny overriding ownership · RULES content deny on payload AND on the committed diff · drift catching a seeded ownership overlap · `drift --strict` exit code) · guard scenario matrix incl. rules-vs-owned-file, content block from Write/Edit/MultiEdit payloads, fail-open without python, non-POLARIS-repo stand-down · full lifecycle telemetry + metrics math · two-clone EVENTS union-merge (zero conflicts) · dashboard `/state` v5 contract (pts · drift · rules_n), SSE push-on-change, drift rail + points strip + bell markers, extracted script passes `node --check` · notify: fires per event, a failing notify command cannot break a claim · `upgrade` on a live v4 board is purely additive and idempotent · virgin install of this zip passes `doctor --selftest` and boots the dashboard.
Unverified, on purpose (test on YOUR machines — that's what `doctor --selftest` is for): macOS bash 3.2 · your specific Windows Git Bash · the hook under a native-Windows (non-Git-Bash) Claude Code shell · browser-notification permission UX varies per browser · the GitHub Actions wrapper (audit/drift logic verified locally; first CI run is its test).

## v4 → v5
- **`ops/RULES.tsv` policy engine** — danger zones + content guards as data, enforced three-deep (write-guard → verify/handoff → audit). Deny-only by design: on PreToolUse, exit-0 stdout is debug-log-only, so an "advisory" the model can't see must not exist.
- **`polaris drift [--strict]`** — the board's invariants, machine-checked: files_owned overlap across ready∪active, ready-gate (contract exists, deps done, ≤5pts), branch cruft, stale `TODO(task)` refs, MAP/Learned overflow, telemetry safety. CI-able.
- **Per-point calibration** — points ride the claim/done telemetry; `metrics` prints cycle-p50 per bucket; PLANNER §read + EVOLVE consume it.
- **Planner pre-mortem + wired-controls guardrail** · **Integrator `uat:` gate** · **`notify:` event hook** · **dashboard**: points strip, drift rail, rules count, opt-in browser notifications.
- **Write routing table** (CONVENTIONS skeleton): one fact, one home, one writer — the drift class where two files disagree about the same fact can't start.
- Unchanged and untouched: v3/v4's race-tested claim/lock/worktree/merge mechanics, all invariants, task format (**zero migration**).

## Publish as a repo (optional)
This folder is repo-ready. From the kit root: `git init && git add -A && git commit -m "POLARIS v5" && gh repo create polaris-kit --private --source=. --push`. (No repo is created for you — run that yourself.)

## Safety note
These prompts drive agents with real filesystem and git access. Keep the stop-and-ask list in `CLAUDE.md` intact when customizing. Deliberately NOT included, and why: agents never auto-install dependencies (supply-chain risk — the stop-and-ask gate stays), agents never edit `ops/RULES.tsv` (append is human-only; EVOLVE proposes), and `notify:`/`uat:` run with your user's permissions like any `verify:` command — treat CONVENTIONS.md as executable config. The hook runs with your user's permissions — read it before approving. The dashboard is read-only and binds localhost; `--host 0.0.0.0` exposes board text to your network.
