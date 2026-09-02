# MAP — POLARIS            (updated: 2026-08-23, by EVOLVE)

## Stack
Bash (>= 3.2 — macOS default; no mapfile, no assoc arrays) + Python 3 stdlib only.
No package manager, no dependencies, no build step beyond zipping. Runs on Linux, macOS and
Windows/Git Bash; CI proves all three on every push.

## The one thing to understand
The repo is BOTH the product and a user of it. `kit/` is what ships. `ops/` is a real POLARIS
installation running this repo's board. Never hand-edit `ops/` — see ops/CONVENTIONS.md § THE SPLIT.
The installed copy also LAGS the source mid-sprint, and the tell that a selftest ran on the right
driver is the LABEL LIST: `bash kit/ops/polaris doctor --selftest` registers kit-only drill labels
(kit 31 = installed 31 since the 6.1.0 dogfood — checkoutguard · readyoverlap · selfland landed and
the counts converge at every dogfood, diverging again the first sprint that adds a drill), so a green
from `ops/polaris` can silently prove none of the sprint's new behavior. The counts move every
sprint: recount `SELFTEST_LABELS` in both `lib/selftest/spine.sh` copies rather than trusting this line.

## Entry points
| Path | What it is |
|---|---|
| kit/ops/polaris | THE CLI **entry point** — ~230 lines: fast paths (find/show/help), lib loader, resolved globals, dispatch. Every `cmd_*` body lives in kit/ops/lib/ since 5.16.0. |
| kit/ops/lib/ | The command bodies — runtime-sourced modules: core · ownership · builder · integrate · knowledge · observe · admin · workspace (shared-checkout mechanics: id_ok · wt_add · stray_feat_repair · int_on/int_off integration lease, rc 3 queued · park/unpark) · bg (background jobs: run/status/tail/wait, dir-per-job `.polaris/bg/<name>/`, rc-file-first verdicts, `.prev` rotation, sweep --fix rotates >24h) + selftest/ drill groups. Contracts: module-layout · shared-checkout · bg-jobs. |
| kit/ops/install.sh | Installs the kit into any repo. Two paths: fresh vs live-board (test = target has ops/CONVENTIONS.md). Settings merge: POLARIS-owned hook entries (identified by the `ops/hooks/` script PATH, never basename) are REPLACED with the kit's current fields on re-install; user-added hooks and all other keys keep skip-if-present (key-registry.md § 6). |
| kit/ops/bootstrap.py | The zipapp entry — packed to the archive ROOT as `__main__.py`, so `python polaris-v5.zip` just works. Also arms the machine (~/.claude skill + cached kit + permission rules). |
| kit/ops/pack.py | Kit-repo tool, never shipped. Builds polaris-v5.zip from `git ls-files` run inside kit/. `--dogfood` installs the published release here. |
| kit/ops/dashboard.py | `polaris dash` — read-only live board on 127.0.0.1:7373. stdlib http.server. |
| kit/ops/hooks/ownership-guard.sh | Claude Code PreToolUse guard. Three gates since 6.1.0: RULES (every session) + files_owned (feat/<ID> only) + primary_gate — writes to tracked source in the shared PRIMARY are denied while any task lock exists and HEAD is not feat/*. Fails OPEN by design. |
| kit/ops/hooks/checkout-guard.sh | Claude Code PreToolUse deny hook (6.1.0): checkout-mutating git is refused in the shared primary, allowed inside `.polaris/wt/<ID>`. |
| kit/ops/hooks/readonly-allow.sh | Claude Code PreToolUse auto-approver for Bash. Proves a command read-only, token by token, and skips the prompt. Deny by default: anything unparsed prompts as before. |
| kit/ops/index.py | The code index behind `find`/`show`. SQLite + FTS5, rebuilt per query. Contract: ops/contracts/code-index.md. |
| kit/ops/bench.sh | Startup + lookup benchmark. Run before/after any change to the startup path. |

## Modules
| Path | Purpose | Notes |
|---|---|---|
| kit/CLAUDE.md | The protocol. Installed as a MARKED, managed block in the target's CLAUDE.md. | Source of truth for the invariants. |
| kit/ops/roles/ | INIT · PLANNER · SOLO · BUILDER · INTEGRATOR · CONDUCTOR · EVOLVE — one file each, read by the agent playing that role. | |
| kit/ops/templates/ | TASK.md, CONTRACT.md — what the Planner instantiates — plus ROADMAP.md, the human-authored standing-goal skeleton. | |
| kit/ops/PROTOCOL.md | The extended protocol: full command table · LANES · TOKEN DISCIPLINE · § MODEL ROUTING (auto — `polaris route` decides; knobs, override, honest boundary) · § LONG COMMANDS (measured suite tiers vs the 600s tool cap, bg doctrine, subagent turn rule) · § N CHATS, ONE REPO (the second-chat decision table). | |
| kit/ops/KEYS.tsv | The CONVENTIONS key registry (key · since · default · absent-cost), shipped via KIT_CODE; doctor's one-line drift report and `polaris adopt` consume it. | Contract: ops/contracts/key-registry.md. |
| kit/ops/MANUAL.md | Fallback git recipes for environments that cannot execute the CLI. | Must mirror the CLI's behaviour. |
| kit/ops/PROMPTS.md | Copy-paste kickoffs for every role. | |
| kit/ops/VERSION | version + the four URLs (channel/tarball/repo/zip) that installed kits poll. | **Human-only.** A bump is a release act. |
| kit/ops/ci/ | polaris-audit.yml — the OPTIONAL board gate shipped to users. Not our CI. | |
| kit/ops/selftest-install.sh | Local install drill: fresh · old-client · live-board · zip purity · uninstall. | The `test:` for any install.sh change. |
| kit/ops/selftest-dashboard.sh | Dashboard smoke drill: start · GET / + /state · kill. | |
| kit/.claude/ | settings.json (wires the guard) + skills/polaris (project) + skills/polaris-install (user-level, cached to ~/.claude at install). | |
| .github/workflows/ | OUR CI. ci.yml = 3-OS drills + "one version, everywhere". release.yml = tag → publish the zip. | Danger zone: agents may not edit their own tests. |

## How a release reaches a user (know this before touching install/update)
- **fresh install** → the published `polaris-v5.zip`. Contains only `kit/`'s files, remapped to `polaris-v5/…`.
- **`polaris update`** → the branch **tarball** of `main`, and it runs `<root>/ops/install.sh` — the
  INSTANCE, not `kit/`. That is why the instance must stay committed and in sync: it is the
  compatibility surface for every kit installed before the `kit/` split. Refreshing it is `--dogfood`.
- **the update notice** → `raw.githubusercontent.com/…/main/ops/VERSION` — again the instance.

## Board mechanics (how state, seals and publishing actually move)
- Board state lives on `refs/heads/polaris/board` — board mutations never touch `<base>`'s
  first-parent; a done task's `map_delta` lands as a `docs(map)` base commit. `upgrade` migrates a
  pre-5.14 board onto the ref, `doctor`/`resume` materialize it in a fresh clone, `uninstall`
  deletes it.
- `seal` is per integration wave: the `sprint/<n>` tag moves to each wave's merge, and
  `history --tasks` spans waves. `polaris report` renders `docs/sprints/sprint-<n>.md`; seal
  commits it on each wave.
- `publish: direct|pr` — pr mode keeps feat branches local; seal pushes ONE integrate branch and
  prints the host PR URL; `seal --sync` finishes after the human merges.
- 6.0 autonomy defaults: unset knobs compose auto / default-safe / auto-reversible;
  `autonomy: standard` is the one-line opt-out; doctor prints the effective composition
  unconditionally (ops/contracts/hands-free-knobs.md v2).
- 6.1 enforced isolation: CONVENTIONS key `landing` (self|integrator, default self IN CODE) —
  `handoff` continues into `land` through the existing integration lease (the lease holder IS the
  Integrator — Invariant 9 reworded in kit/CLAUDE.md); `autolaunch_max` default 5; `claim`'s
  disjointness gate sweeps `ready/` as well as `active/`; `drift --strict` exits nonzero on
  OWNERSHIP OVERLAP; `self_land` refuses silently on tasks with no `risk:` frontmatter and refuses
  outright on risk: high / STOP-AND-ASK — hard gates move nowhere.
- 6.0 discovery loop (key-registry.md § 2-4): doctor reads `ops/KEYS.tsv` and reports CONVENTIONS
  keys absent from the live file as ONE summary line naming the remedy (`ops/polaris adopt`) —
  the drift class the CLAUDE.md stamp check covers for exactly one file; `update` prints the
  BREAKING banner when the incoming kit is >=6.0.0 and no autonomy knob is set.

## CLI surface beyond the build loop (claim · build · verify · handoff · pack · find/show · check)
`triage` (prints your lane) · `route [<ID>|--role R|--points N --risk R]` (mechanical model tier —
line 1 bare word, `model:` note from CONVENTIONS knobs; fleet injects `--model` per pane, `pack`
header carries `· tier`) · `brain [--refresh]` (generated `.polaris/brain/` knowledge base;
seal auto-refreshes, doctor warns when stale) · `land --express <ID>` (audit+land+one full
suite+seal+run-verify+done in one pass) · `status --brief` · `metrics` (opens with a plain-English
summary) · `doctor --selftest --only <glob>` / `--parallel <N>` · `park`/`unpark` (dirty trees
become named stashes) · `approve <ID> <scope> -m "why"` (records a human's yes to an `ask` rule) ·
`notify-gate <kind> [ID]` + `POLARIS_SEVERITY` in the notify env contract · `finish` (pends on
running bg jobs) · `bg run/status/tail/wait` (see the lib row above) · `adopt` (appends a
commented stub — default + rationale — for every KEYS.tsv key missing from CONVENTIONS.md;
never edits a value, idempotent; drill label `adopt` in remote.sh proves it) · selftest labels
now 31: `checkoutguard` · `readyoverlap` · `selfland` (6.1.0), with golden pairs
checkout-guard-denies + ownership-primary pinning the two guards' refusal wording.

## Danger zones — agents NEVER edit these (machine-enforced, ops/RULES.tsv)
| Path | Why |
|---|---|
| ops/polaris, ops/install.sh, ops/dashboard.py, ops/VERSION, ops/MANUAL.md, ops/PROMPTS.md, ops/roles/, ops/hooks/, ops/templates/, ops/ci/ | Installed copies. Edit `kit/ops/…` instead — the installed one is overwritten on the next release install, so the work is lost. |
| kit/ops/VERSION | A bump tells every installed kit in the world that a new POLARIS exists. Human only. |
| .github/ | The CI drills are the last gate between a bad kit and every user. |

`ops/board/`, `ops/contracts/`, `ops/CONVENTIONS.md`, `ops/MAP.md`, `ops/SPRINT.md` are board STATE,
not installed code — they are written normally, by the board scripts and by the Planner/Integrator.

## Generated / vendored — never edit, never read
`.polaris/` (worktrees + update cache + generated brain/ + bg/ job dirs, gitignored) · `polaris-v5.zip` (build output, gitignored) ·
`archive/` (retired files, kept for history — never ships) · `__pycache__/`

## Hotspot files (conflict magnets — Planner must chain these, never parallel-own)
- `kit/ops/polaris` + `kit/ops/lib/*.sh` — the entry is thin since the 5.16.0 split, but each lib
  module is a conflict magnet in its own right; chain tasks touching the SAME module (sprint 10
  chained observe.sh and install.sh serially, 0 kickbacks).
- `ops/tests/api-kit.expected` — a DERIVED-surface golden: it records every top-level fn AND every
  markdown heading under `kit/`, so it silently couples every task that adds either. ONE owner per
  wave (ops/contracts/key-registry.md § 5), everyone else surface-frozen — three sprints of
  defects, then four waves at 0 kickbacks, earned this rule.
- `kit/CLAUDE.md` — the protocol. Same problem.
- `kit/ops/install.sh` — fresh path and live-board path are ~40 lines apart.

## Unverified
- Whether anyone outside this machine has POLARIS installed. The `kit/` split keeps the old
  tarball/raw-channel paths working regardless, so this is untested-in-the-wild, not unsafe.

## Deltas

- "lib/workspace.sh gains beat_touch/beat_age/beat_live (the worktree liveness signal, $GCD/worktrees/<ID>/polaris-beat) and wt_remove — the ONLY worktree-removal primitive (rc 0 removed / 1 left / 2 archived to .polaris/wt-archive/, never --force)"  (T-092, 2026-09-02)

- "kit/ops/VISUAL.md — the SEEING YOUR WORK doctrine ships in the kit (installed as ops/VISUAL.md by T-103); KEYS.tsv gains wt_live_minutes shot visual port_base serve handover; PROTOCOL gains  (T-096, 2026-09-02)

- "kit settings + bootstrap PERMS pre-authorize the harness's own tools (EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage); golden perm-tools pins the set and the two human gates' absence"  (T-095, 2026-09-02)

- "checkout-guard.sh denies worktree remove/prune/move, clean (except -n), push --delete, rm/Remove-Item on .polaris and broad process kills (mutating_other); both guards touch the worktree beat"  (T-093, 2026-09-02)

- "claim/resume/verify/handoff beat the worktree; resume and release refuse a live worktree (takeover = rm the beat file); pack prints the SEE YOUR WORK section from shot:/visual:/port_base:/serve:; handoff refuses a visual change without a fresh .polaris/shots/<ID>-*.png"  (T-098, 2026-09-02)

- "done removes a task worktree only via wt_remove (live ⇒ LEFT + branch kept, dirty ⇒ archived); land/seal re-stamp the integration lease between long steps; audit lists .polaris/shots/<ID>-*.png captures"  (T-099, 2026-09-02)

- "sweep gains the worktree pass (LIVE reported, IDLE clean removed / dirty archived with --fix), 120 s orphan-lock grace, last-activity + session-alive lines, .archive and handover-dir pruning; doctor warns when keep-awake is unarmed/disabled; qa stamps only when HEAD and the tree are unchanged AFTER the suite; finish stamps the session's finished marker; fleet kickoff ends in polaris next"  (T-100, 2026-09-02)

- "new module lib/awake.sh (awake status|start|stop|disable|enable|install, awake_ensure); entry loader +awake +handover after bg; dispatch awake + next; preamble beats the worktree on every CLI call; awake_ensure fires from claim/status/doctor/handoff/bg run"  (T-101, 2026-09-02)

- "kit/ops/hooks/awake-hook.sh (SessionStart/UserPromptSubmit/Stop/SessionEnd machine hooks + the daemon loop, verdict from transcript mtime + live bg jobs, WMI spawn) and awake-press.ps1 (ES_SYSTEM_REQUIRED one-shot + F-key only when the user is idle and unlocked) — installed to ~/.claude/polaris/ by T-103"  (T-102, 2026-09-02)

- "new module lib/handover.sh — polaris next [--do|--brief]: resume/integrate/stop/build/promote/wait/finish off the board (T-101 wires the dispatch + loader)"  (T-109, 2026-09-02)

- "kit/ops/hooks/handover-hook.sh — Stop (block once per board-proven completion event with the next role's instruction), SessionStart compact|resume (re-anchor via next --brief), UserPromptSubmit (prompted-at clock); wired in kit/.claude/settings.json; readonly-allow auto-approves next and next --brief"  (T-110, 2026-09-02)

- "install.sh ships ops/VISUAL.md and chmods awake-hook.sh + handover-hook.sh; bootstrap.py arm_machine and admin.sh refresh copy the two awake files to ~/.claude/polaris/ and merge the four machine hooks (merge_awake_hooks); uninstall dies on a non-empty .polaris/wt-archive/, deregisters the repo from the awake registry, and strips every ops/hooks/ entry across all hook events"  (T-103, 2026-09-02)

- "doctor --selftest gains wtreap (history.sh), awake (policy.sh) and the handover label (drill body in board.sh, T-111) — 31 to 34 labels; selfland asserts the self-landed worktree survives; the spine exports POLARIS_AWAKE_HOME so no drill touches the owner's awake registry"  (T-104, 2026-09-02)
