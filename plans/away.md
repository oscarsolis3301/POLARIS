# Finish 6.15.0, then 6.16.0: "approved + auto means you have left" and "small means fast"

## Context

Two things came in while 6.15.0 was being built.

1. **You want 6.15.0 finished completely and published.** It is two-thirds done and paused only
   because this chat went into plan mode (the last builder stopped with it).
2. **You want a run to never wait on you once you approve a plan and switch to auto mode.** Today an
   agent can still stop on a question ("approve this merge?") and sit idle until you notice, often
   30 minutes later. And you want small changes to be fast: a small UI tweak should not pay a full
   test suite, big changes should still be proven fully but never take hours.

**Your decisions (2026-11-09, this chat):**
- Approved plan + auto mode = you have left. Approved but not in auto mode = you may still be asked.
- Away, a high-risk task that belongs to the approved plan: **merge it**; the close says which.
- Away, something the plan did not cover and that has no safe default: **park that one piece**, finish
  everything else, list it in the close.
- Projects that ship through pull requests (ARC on Bitbucket): the run ends with **one pull request
  and its link** as the last line. Merging it stays yours.
- A small UI change (1–2 points): **lint and type checks side by side plus a before/after look**; no
  test suite.

### What I found (read-only, this evening)

| Finding | Evidence | Fix |
|---|---|---|
| Nothing stops the "ask" tool. The stop-hook bounces a closing question once, then lets it through; the question tool itself is never intercepted | `kit/ops/hooks/handover-hook.sh` (`block:question … ask again and you will be let through`); no hook is registered for `AskUserQuestion` | B1, B2 |
| "One yes covers the plan" exists, but only if the agent remembers to type `approve --plan` | `plan_covers` in `kit/ops/lib/ownership.sh`; `cmd_approve_plan` in `kit/ops/lib/builder.sh`; the step is prose in `CONDUCTOR.md` | B3 |
| Hooks are told the session's mode | every hook payload carries `permission_mode` (plans/audit-0924.md, Q2a); the kit arms `defaultMode: "auto"` in `bootstrap.py` | B1 |
| The pull-request link for Bitbucket already exists | `pr_create_url` in `kit/ops/lib/core.sh`, golden `pr-one-link` | B7 proves the close ends with it |
| Your projects take about an hour per task, mostly waiting to land | from each project's own event log: claim→done median 56–77 min (The Director, job, venzeti, pip); handoff→done median 12–71 min, worst cases 2–16 hours | 6.15.0 (lands itself, safely in parallel) + the update rule fix so they actually receive it |
| A project's checks run one after another | `cmd_qa` loops `test lint typecheck build uat` in order (`kit/ops/lib/qa.sh`) | B5 |
| Only style/image files get the light "look" depth; a small component edit pays the whole suite unless the runner can relate tests | `depth_for` in `kit/ops/lib/core.sh` (none · look · scoped · full) | B4 |
| One change costs about 60 s of command time on a fresh project; 34 s of it is the landing, and the knowledge refresh runs twice in it | timed and traced on a 6.14.0 practice project (`brain_refresh_if_present` at seal and again at done, `kit/ops/lib/integrate.sh`) | B6 |

---

## Phase A — finish and publish 6.15.0 (about 60 minutes)

State: 6.14.0 is released and green on Linux, macOS and Windows. On main for 6.15.0: T-221 (race
check), T-222 (lease + silent-death fix), T-223 (one lock per landing; race check 5 of 5 green),
T-224 (done proves the files are on main), T-226 (role wording), T-287 (a task's checks side by
side), T-288 (waiting tasks no longer hold an update back). Left: T-225, T-227.

1. **Raise the helper cap for this run**: `run_max_agents: 40 → 60` in `ops/CONVENTIONS.md` (38 used;
   both phases need about 12 more). Dated owner comment, one commit.
2. **Answer T-225's one question** in `ops/contracts/safe-landing.md` (new v1.3 note): at `finish`, a
   done task's path counts as missing only when no later landed task commit touched it after the
   task's own landed commit; a task with no landed commit on main counts every differing path. (Later
   tasks rightly change the same files; without this, finish would refuse a healthy run.) `seal` and
   `done` stay as specified. Then resume the same builder with that answer (no new agent).
3. **T-225** builds, proves on CI Linux and macOS, lands itself.
4. **T-227** (version 6.15.0 + release notes; Sonnet, low) lands itself. Notes cover T-221…T-226,
   T-287, T-288 in plain words.
5. **Release gate and ritual** (unchanged from `ops/CONVENTIONS.md`): `finish` green →
   `tools/proof.sh --await macos-latest` → tag `v6.15.0` → wait for the published release →
   `python kit/ops/pack.py --dogfood` → re-pin `cli-help` → installed-copy goldens → dogfood commit →
   push → CI green on all four jobs.
6. **Tests of the published 6.15.0** (scripts already written in the scratchpad):
   - `race615.sh`: a brand-new project, six tasks handed off at the same moment → all done, all on
     main, one wave, `finish` green. (On 6.14.0 the same test left one task stuck and three unsealed.)
   - `shoptest.sh`: fresh install → `begin` → `wrap` → green, in both landing modes, timed.
   - `twojump.sh`: a 6.13 project updates to 6.15, then to a pretend next version → the update commits
     itself and brings a second project along.
   - `land-race` golden three more times on the final commit.
   - `bash ops/polaris update --all` → The Director, job, venzeti, pip and the test repo; report each
     line (the test repo uses pull-request mode, so its update is committed by hand as before).

Phase B's planning and first builders start during steps 3–5 (they do not touch T-225's files) and
hold their landing until 6.15.0 is tagged and installed.

---

## Phase B — 6.16.0 (about 85 minutes, two parallel waves)

One planner pass (Opus, high) carves these into tasks with disjoint files and writes the contract
`ops/contracts/away.md` first. Sizes and owners below are the intended carve.

### Wave 1 (five lanes side by side)

**B1 — POLARIS knows whether you are here (3 pts).**
New `kit/ops/hooks/presence-guard.sh`, new `kit/ops/lib/presence.sh`; registered in
`kit/.claude/settings.json` and by `kit/ops/install.sh` / `kit/ops/bootstrap.py` the way the other
hooks are; dispatch and help line in `kit/ops/polaris`; `ops/tests/api-kit.expected`.
- State, per session, under `~/.claude/polaris/model-state/` (beside the existing `<sid>.effort`):
  `<sid>.mode` = the last `permission_mode` any hook saw; `<sid>.approved` = written when a plan is
  approved (a `PostToolUse` hook on `ExitPlanMode`, or the mode going from `plan` to another mode, or
  an `approve --plan` record).
- **Away** = `<sid>.approved` exists AND the mode is `auto`, `bypassPermissions` or `dontAsk`.
  Anything else, including an unreadable payload, is **here**.
- `PreToolUse` on `AskUserQuestion`: away → deny, with the reason the model reads: "The owner
  approved the plan and left. Do not ask. Take the recommended option and write it down as an
  `assumed:` line; if there is no safe default, park that one piece and finish the rest." Here → no
  opinion (the question goes through).
- `bash ops/polaris presence` prints `away` or `here` and one reason line.
- Fail-open: any error in the hook lets the tool call through; it never blocks a session.
- Goldens with canned payloads: away denies; here allows; plan mode allows; no approval allows;
  garbage payload allows; HOME and USERPROFILE faked together.

**B2 — a closing question never ends an away run (2 pts).**
`kit/ops/hooks/handover-hook.sh` and its drill. Away and work left → the stop is bounced every time,
with the same instruction as B1 and without "ask again and you will be let through". Here → today's
behaviour, byte for byte. The harness's own cap on consecutive bounces stays the backstop.

**B4 — a small UI change gets quick checks and a look (3 pts).**
`kit/ops/lib/core.sh` (`depth_for`), `kit/ops/KEYS.tsv`, `kit/ops/lib/route.sh` (`depth` says it),
`ops/contracts/test-depth.md`, goldens.
- New depth `ui`, between `look` and `scoped`: every changed path matches the new key `test_ui`
  (default in code: `*.tsx *.jsx *.vue *.svelte *.html *.astro` plus the `test_look` list) AND every
  task in the change is 1–2 points and `risk: normal`. A task may also say `test_depth: ui`; it is
  honoured only when the path rule holds. Anything else keeps today's verdict.
- New key `qa_parallel` (default `on`), same row set, for B5.
- `risk: high`, `test_depth: full`, an unbounded change set: full, as today.

**B6 — the landing does its bookkeeping once (2 pts).**
`kit/ops/lib/integrate.sh`. One knowledge refresh per landing: when a seal and the dones that follow
run under one lease, the refresh happens once, after the last done. Measured before and after on a
quiet machine with the tracing script already written; target: a self-landing handoff on a fresh
project in 20 s or less (34 s today).

**B7 — the words match (3 pts).**
`kit/CLAUDE.md` (three lines at most: the away rule; the stop-and-ask list applies only while you are
here; Invariant 9 reads "…without the owner's approval: a recorded yes, or the approved plan while
away"), `kit/ops/roles/{CONDUCTOR,INTEGRATOR,BUILDER,SOLO,PLANNER}.md`, `kit/ops/PROTOCOL.md`,
`kit/.claude/output-styles/polaris.md`.
- Here (plan mode, or not auto): ask every question whose answer changes the plan, in rounds, until
  none is left.
- Away: never ask; recommended option; park only what has no safe default; never stop for a busy
  lane, a taken task or another chat's work; finish through publishing.
- The close of a pull-request project ends with the pull-request link; nothing follows it.
- The close always says how long the run took and where the time went (`polaris speed`).
- The planner carves for side-by-side lanes: a chain longer than two tasks needs a one-line reason,
  and the plan it shows you names the number of lanes, waves and an estimated time.

### Wave 2 (two lanes, after B1 and B4)

**B3 — away, your approval of the plan is the approval (3 pts).**
`kit/ops/lib/ownership.sh` (`plan_covers`), `kit/ops/lib/builder.sh` (reuse `cmd_approve_plan`'s
writer), goldens. When the session is away and a task belongs to the session's approved plan, the
kit records the plan entries itself (the same lines `approve --plan` writes, marked "approved plan,
owner away"), so a high-risk task of that plan merges with no question. A task outside the plan, a
hand-recorded approval, `autonomy: standard`: unchanged. The close lists every high-risk task that
merged this way.

**B5 — quick checks side by side (3 pts).**
`kit/ops/lib/qa.sh`, goldens.
- At depth `ui`: `lint` and `typecheck` run at the same moment; `test`, `build`, `uat` do not run;
  the before/after capture rule of `look` applies when the project declares a `visual:` surface.
- At `scoped` and `full`: `test`, `lint` and `typecheck` run at the same moment, then `build`, then
  `uat` (`build` can write where tests read, so it stays in line). `qa_parallel: off` restores
  today's one-after-another order. Output stays in today's order and wording.
- A golden with two keys that log start and end times proves they overlapped, and that
  `qa_parallel: off` does not.

### Wave 3
**B8 — release 6.16.0** (1 pt), the same ritual, then `update --all` again.

### Conductor steps inside Phase B
- Before wave 1: `tools/proof.sh` removes only `proof/` branches older than 30 minutes (today it
  removes every other one, so five lanes proving at once would break each other).
- Each builder proves its own commit on CI Linux before handoff; B1, B3 and B5 also on macOS.

---

## Rules every builder follows (each has cost a release before)
- macOS runs bash 3.2: no `case` inside `$(...)`, no `${v,,}`, no `wait -n`, no arrays; never fork
  per item.
- Two git commands that both need the index lock never share a pipeline.
- Tests fake HOME and USERPROFILE together (and POLARIS_AWAKE_HOME) and never touch the real
  `~/.claude`. A golden prints no sha, time or absolute path.
- New names are private (`_name`) unless the task owns `ops/tests/api-kit.expected`.
- At least one golden per new behaviour installs the kit INTO its fixture and runs the fixture's own
  `ops/polaris` (the fault that hid `wrap`'s red ending).
- A task that changes what a command prints owns every golden and drill that pins it.
- A hook fails open and stays fast (builtins and one small file read).
- Commit messages are plain and friendly, with no attribution lines.

## Verification
1. **6.15.0:** the six-lane live race passes on the published kit; CI green on all four jobs for the
   release and dogfood commits; your four projects report their update line.
2. **Away:** with canned hook payloads — approved + auto → the question tool is denied and a closing
   question is bounced; approved + default mode → both go through; plan mode → both go through.
   A practice project with a high-risk task in an approved plan lands it with no question when away,
   and waits when here.
3. **Pull request:** a practice project with a Bitbucket-style remote and `publish: pr` ends `finish`
   with the pull-request link as its last line.
4. **Small UI change:** a 1-point task touching one `.tsx` file reports depth `ui`; `lint` and
   `typecheck` overlap in time and `test` does not run; the same file in a 3-point task, or beside a
   `.py` file, gets today's verdict.
5. **Speed:** begin → wrap on a fresh project, quiet machine: 62 s today; the target after B6 is
   45 s. `polaris speed` in this repo shows "built → done" under 5 minutes for 6.15.0 and 6.16.0.
6. Both releases end with `bash ops/polaris finish` exiting 0.

## How it runs after you approve
- This chat is the conductor and continues at once with Phase A step 1. Nothing waits on you; this
  run itself follows the rule being built: recommended options, park what has no safe default.
- Budget: about 2 hours 25 minutes in all (Phase A 60, Phase B 85). Most of it is two full release
  proofs on three systems and builders working side by side.
- The approval covers: commits, pushes, tags and publishing for 6.15.0 and 6.16.0, proof branches on
  GitHub, raising the helper cap to 60, and updating and committing inside your other POLARIS
  projects on this PC.
- **Waiting on you afterwards:** update POLARIS on the ARC device (one `update` there; it is on a
  different machine) · delete the throwaway branch `debug/au5b` on GitHub and locally (the guards
  refuse it for me) · your `claude` sign-in for the two checks parked on it.
- This plan is saved to `plans/away.md`.
