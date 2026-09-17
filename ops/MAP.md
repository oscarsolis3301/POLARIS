# MAP — POLARIS            (updated: 2026-09-14, by EVOLVE)

## Stack
Bash (>= 3.2 — macOS default; no mapfile, no assoc arrays) + Python 3 stdlib only.
No package manager, no dependencies, no build step beyond zipping. Runs on Linux, macOS and
Windows/Git Bash; CI proves all three on every push.

## The one thing to understand
The repo is BOTH the product and a user of it. `kit/` is what ships. `ops/` is a real POLARIS
installation running this repo's board. Never hand-edit `ops/` — see ops/CONVENTIONS.md § THE SPLIT.
The installed copy also LAGS the source mid-sprint, and the tell that a selftest ran on the right
driver is the LABEL LIST: `bash kit/ops/polaris doctor --selftest` registers kit-only drill labels
(kit 35 = installed 35 since the 6.3.1 dogfood — wtreap · awake · handover landed in 6.2.0 and
autoupdate in 6.3.0; sprint 14 added no drill, T-138's surfaces drill is still in backlog/ — the
counts converge at every dogfood, diverging again the first sprint that adds a drill), so a green
from `ops/polaris` can silently prove none of the sprint's new behavior. The counts move every
sprint: recount `SELFTEST_LABELS` in both `lib/selftest/spine.sh` copies rather than trusting this line.

## Entry points
| Path | What it is |
|---|---|
| kit/ops/polaris | THE CLI **entry point** — ~370 lines: fast paths (find/show/help), the lib loader (… bg, then awake and handover), resolved globals (`SURFACES="$OPS/SURFACES.tsv"` sits under `RULES=`), dispatch (awake · next · surfaces joined it in 6.2–6.4); the preamble beats the task worktree on every call. Every `cmd_*` body lives in kit/ops/lib/ since 5.16.0. Known: the `qa)` line forwards only its first flag (IDEAS.md, entry-owned). |
| kit/ops/lib/ | The command bodies — runtime-sourced modules: core (cfg · frontmatter · the RULES cache · the surface-map data plane: surfaces_lines/seed, surface_row_matches/rows_for/row_from_item, surface_change_set/select_cmd, suite_stamp_scope, reading ops/SURFACES.tsv + CONVENTIONS `test_select:`) · ownership (check_rules → check_freshness, the stale-tests gate) · builder · integrate · knowledge · observe · admin · search (the thin `find`/`show` shim over index.py) · workspace (shared-checkout mechanics: id_ok · wt_add · stray_feat_repair · int_on/int_off integration lease, rc 3 queued · park/unpark · beat_touch/beat_age/beat_live, the worktree liveness signal at `$GCD/worktrees/<ID>/polaris-beat` · wt_remove, the ONLY worktree-removal primitive: rc 0 removed / 1 left / 2 archived to .polaris/wt-archive/, never --force) · bg (background jobs: run/status/tail/wait, dir-per-job `.polaris/bg/<name>/`, rc-file-first verdicts, `.prev` rotation, sweep --fix rotates >24h) · awake (keep-awake: status/start/stop/disable/enable/install; awake_ensure fires from claim/status/doctor/handoff/bg run and honours the machine `disabled` flag) · handover (`next`, `next --do`, `next --brief`: resume/integrate/stop/build/promote/wait/finish read off the board; next_promote IS the promote pass — the full ready gate under the board lock, ONE `chore(board): promote <IDs>` commit) + selftest/ drill groups (fast.sh = the in-process tier). Contracts: module-layout · shared-checkout · bg-jobs · worktree-liveness · keep-awake · role-handover · fast-tier · test-surfaces. |
| kit/ops/install.sh | Installs the kit into any repo. Two paths: fresh vs live-board (test = target has ops/CONVENTIONS.md). Settings merge: POLARIS-owned hook entries (identified by the `ops/hooks/` script PATH, never basename) are REPLACED with the kit's current fields on re-install; user-added hooks and all other keys keep skip-if-present (key-registry.md § 6). Ships ops/VISUAL.md, chmods awake-hook.sh + handover-hook.sh, and registers the repo in ~/.claude/polaris/awake/repos at install and update time (not only on awake activation). |
| kit/ops/bootstrap.py | The zipapp entry — packed to the archive ROOT as `__main__.py`, so `python polaris-v5.zip` just works. Also arms the machine: ~/.claude skill + cached kit + permission rules; arm_machine copies awake-hook.sh + awake-press.ps1 to ~/.claude/polaris/ and merges the four machine hooks (merge_awake_hooks); PERMS pre-authorize the harness's own tools (EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage — golden perm-tools pins the set and the two human gates' absence). |
| kit/ops/pack.py | Kit-repo tool, never shipped. Builds polaris-v5.zip from `git ls-files` run inside kit/. `--dogfood` installs the published release here. |
| kit/ops/dashboard.py | `polaris dash` — read-only live board on 127.0.0.1:7373. stdlib http.server. |
| kit/ops/hooks/ownership-guard.sh | Claude Code PreToolUse guard. Three gates since 6.1.0: RULES (every session) + files_owned (feat/<ID> only) + primary_gate — writes to tracked source in the shared PRIMARY are denied while any task lock exists and HEAD is not feat/*. Fails OPEN by design. Beats the task worktree. |
| kit/ops/hooks/checkout-guard.sh | Claude Code PreToolUse deny hook (6.1.0): checkout-mutating git is refused in the shared primary, allowed inside `.polaris/wt/<ID>`. Since 6.2.0 also denies worktree remove/prune/move, `clean` (except -n), push --delete, rm/Remove-Item on .polaris and broad process kills (mutating_other). Beats the worktree too. |
| kit/ops/hooks/readonly-allow.sh | Claude Code PreToolUse auto-approver for Bash. Proves a command read-only, token by token, and skips the prompt (`next` and `next --brief` included). Deny by default: anything unparsed prompts as before. |
| kit/ops/hooks/handover-hook.sh | The handover hooks (6.2.0): Stop — blocks ONCE per board-proven completion event with the next role's instruction; SessionStart compact / resume — re-anchors via `next --brief`; UserPromptSubmit — the prompted-at clock. Wired in kit/.claude/settings.json. |
| kit/ops/hooks/awake-hook.sh + awake-press.ps1 | Machine-level keep-awake (6.2.0): the SessionStart/UserPromptSubmit/Stop/SessionEnd machine hooks AND the daemon loop (verdict from transcript mtime + live bg jobs, WMI spawn); the presser is an ES_SYSTEM_REQUIRED one-shot + F-key only while the user is idle and unlocked. ONE owner per machine, never per session; installed to ~/.claude/polaris/. `awake disable` must stop the daemon SPAWNING, not just the press (T-133). |
| kit/ops/hooks/update-hook.sh | SessionStart hook, matcher `startup` (6.3.0): runs `update --auto` and passes its one line to the model; never fails the session. |
| kit/ops/hooks/commit-msg | Git commit-msg hook: strips AI-provider attribution lines (bot co-authors, badge lines) — the product carries no AI fingerprints. |
| kit/ops/index.py | The code index behind `find`/`show`. SQLite + FTS5, rebuilt per query. Contract: ops/contracts/code-index.md. |
| kit/ops/bench.sh | Startup + lookup benchmark. Run before/after any change to the startup path. |

## Modules
| Path | Purpose | Notes |
|---|---|---|
| kit/CLAUDE.md | The protocol. Installed as a MARKED, managed block in the target's CLAUDE.md. | Source of truth for the invariants. |
| kit/ops/roles/ | INIT · PLANNER · SOLO · BUILDER · INTEGRATOR · CONDUCTOR · EVOLVE — one file each, read by the agent playing that role. | BUILDER/SOLO/CONDUCTOR co-change 6-8× (brain learned.md): role prose moves as a trio — one owner per wave. |
| kit/ops/templates/ | TASK.md, CONTRACT.md — what the Planner instantiates — plus ROADMAP.md, the human-authored standing-goal skeleton. | |
| kit/ops/PROTOCOL.md | The extended protocol: full command table · LANES · TOKEN DISCIPLINE · § MODEL ROUTING (auto — `polaris route` decides; knobs, override, honest boundary) · § LONG COMMANDS (measured suite tiers vs the 600s tool cap, bg doctrine, subagent turn rule) · § N CHATS, ONE REPO (the second-chat decision table). | |
| kit/ops/VISUAL.md | The SEEING YOUR WORK doctrine — the capture is the proof. Installed as ops/VISUAL.md (6.2.0). `pack` prints the SEE YOUR WORK section from shot:/visual:/port_base:/serve:, `handoff` refuses a visual change without a fresh .polaris/shots/<ID>-*.png, `audit` lists the captures. | Contract: ops/contracts/visual-check.md. |
| kit/ops/KEYS.tsv | The CONVENTIONS key registry (key · since · default · absent-cost), shipped via KIT_CODE; doctor's one-line drift report and `polaris adopt` consume it. Rows since 6.1: landing (6.1.0) · wt_live_minutes shot visual port_base serve handover (6.2.0) · auto_update (6.3.0, default on in code) · test_select (6.4.0; unset = byte-identical to 6.3). | Contract: ops/contracts/key-registry.md. |
| kit/ops/MANUAL.md | Fallback git recipes for environments that cannot execute the CLI. | Must mirror the CLI's behaviour. |
| kit/ops/PROMPTS.md | Copy-paste kickoffs for every role. | |
| kit/ops/VERSION | version + the four URLs (channel/tarball/repo/zip) that installed kits poll. | **Human-only.** A bump is a release act. |
| kit/ops/ci/ | polaris-audit.yml — the OPTIONAL board gate shipped to users. Not our CI. | |
| kit/ops/selftest-install.sh | Local install drill: fresh · old-client · live-board · zip purity · uninstall. | The `test:` for any install.sh change. Run it with POLARIS_AWAKE_HOME pointed at a scratch dir. |
| kit/ops/selftest-dashboard.sh | Dashboard smoke drill: start · GET / + /state · kill. | |
| kit/.claude/ | settings.json (wires the two guards + readonly-allow, the handover hooks, the `startup` update hook; PERMS pre-authorize the harness's own tools) + skills/polaris (project) + skills/polaris-install (user-level, cached to ~/.claude at install). | |
| .github/workflows/ | OUR CI. ci.yml = 3-OS drills + "one version, everywhere". release.yml = tag → publish the zip. | Danger zone: agents may not edit their own tests. |

## How a release reaches a user (know this before touching install/update)
- **fresh install** → the published `polaris-v5.zip`. Contains only `kit/`'s files, remapped to `polaris-v5/…`.
- **`polaris update`** → the branch **tarball** of `main`, and it runs `<root>/ops/install.sh` — the
  INSTANCE, not `kit/`. That is why the instance must stay committed and in sync: it is the
  compatibility surface for every kit installed before the `kit/` split. Refreshing it is `--dogfood`.
- **`update --auto`** (6.3.0) → the SessionStart `startup` hook applies minor/patch updates on a QUIET
  board — gates board_quiescent + update_dirt_overlaps_kit, never parks, one line — and
  `update --all` walks ~/.claude/polaris/awake/repos. KEYS `auto_update` is default-on in code.
- **the update notice** → `raw.githubusercontent.com/…/main/ops/VERSION` — again the instance.

## Board mechanics (how state, seals and publishing actually move)
- Board state lives on `refs/heads/polaris/board` — board mutations never touch `<base>`'s
  first-parent; a done task's `map_delta` lands as a `docs(map)` base commit. `upgrade` migrates a
  pre-5.14 board onto the ref, `doctor`/`resume` materialize it in a fresh clone, `uninstall`
  deletes it (and dies on a non-empty .polaris/wt-archive/, deregisters the repo from the awake
  registry, strips every ops/hooks/ entry across all hook events).
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
- 6.2 worktree liveness (worktree-liveness.md): claim/resume/verify/handoff — and the preamble of
  every CLI call — beat the task worktree; `resume` and `release` refuse a LIVE worktree (takeover
  = rm the beat file); `done` removes a worktree only via wt_remove (live ⇒ LEFT + branch kept,
  dirty ⇒ archived); land/seal re-stamp the integration lease between long steps; `sweep` gains the
  worktree pass (LIVE reported, IDLE clean removed / dirty archived with --fix), a 120 s orphan-lock
  grace, last-activity + session-alive lines, .archive and handover-dir pruning; `qa` stamps only
  when HEAD and the tree are unchanged AFTER the suite; `finish` stamps the session's finished marker.
- 6.2 role handover (role-handover.md): `next` names the next role off the board (resume ·
  integrate · stop · build · promote · wait · finish), `next --do` runs the promote pass, `next
  --brief` re-anchors after compaction; the Stop hook blocks once per completion event; the fleet
  kickoff ends in `polaris next`. Keep-awake (keep-awake.md): doctor warns when it is unarmed or
  disabled; the machine flag, not the session, decides.
- 6.3 latency (fast-tier.md · auto-update.md): `doctor --fast` is the in-process tier — pure kit
  functions, no CLI re-invocation, no scratch repo, seconds — beside the drills, never instead of
  them; an express land writes `.polaris/suite-stamp` so `finish` skips a green it already paid;
  `update --auto` is the delivery mechanism (see the release section).
- 6.4 surfaces (test-surfaces.md): `ops/SURFACES.tsv` (board state; seeded by init-board; written
  ONLY by `polaris done` from a task's `surface:` items — `docs(surfaces):` or riding `docs(map):`)
  + CONVENTIONS `test_select:` feed two gates. (a) The stale-tests gate — `check_freshness` in
  ownership.sh, reached through check_rules at verify/handoff/audit/land, never from the write
  guard: a change with real added lines under a mapped surface and none under its tests fails
  `verify`; `approve` also clears a SURFACES row; `pack` prints the SURFACES section. (b)
  Change-scoped `qa`: with `test_select:` set, `qa` and `land --express` select `test:` commands
  from the rows; the stamp is v3 (`<sha> <epoch> full|scoped` — suite_stamp_carry writes it and
  allows ops/SURFACES.tsv since-tested), `finish` accepts scoped and says what was proven, and a
  2-field stamp reads `full`. `surfaces` + surfaces_health (self-covering rows refused, 0/>200-match
  globs flagged) are wired into `drift`; `triage` prices contexts, routing several small tasks to
  solo by context cost. `test_select:` unset = byte-identical to 6.3, which is why `update` ships it.

## CLI surface beyond the build loop (claim · build · verify · handoff · pack · find/show · check)
`triage` (prints your lane) · `route [<ID>|--role R|--points N --risk R]` (mechanical model tier —
line 1 bare word, `model:` note from CONVENTIONS knobs; fleet injects `--model` per pane, `pack`
header carries `· tier`) · `brain [--refresh]` (generated `.polaris/brain/` knowledge base;
seal auto-refreshes, doctor warns when stale) · `land --express <ID>` (audit+land+one suite —
selected exactly as `qa` selects — +seal+run-verify+done in one pass) · `status --brief` ·
`metrics` (opens with a plain-English summary) · `doctor --selftest --only <glob>` /
`--parallel <N>` / `--fast` · `park`/`unpark` (dirty trees become named stashes) ·
`approve <ID> <scope> -m "why"` (records a human's yes to an `ask` rule) · `notify-gate <kind> [ID]`
+ `POLARIS_SEVERITY` in the notify env contract · `finish` (pends on running bg jobs) ·
`bg run/status/tail/wait` (see the lib row above) · `adopt` (appends a commented stub — default +
rationale — for every KEYS.tsv key missing from CONVENTIONS.md; never edits a value, idempotent;
drill label `adopt` in remote.sh proves it) · `next [--do|--brief]` (6.2.0) · `awake
status|start|stop|disable|enable|install` (6.2.0) · `update [--auto|--all]` (6.3.0) · `surfaces`
(6.4.0) · `qa [--force] [--full]` (6.4.0). Selftest labels now 35: `wtreap` (history.sh) · `awake`
(policy.sh) · `handover` (board.sh) joined in 6.2.0, `autoupdate` (remote.sh) in 6.3.0; the spine
exports POLARIS_AWAKE_HOME so no drill touches the owner's awake registry; goldens handover-route
+ handover-stop pin every `next` verb and hook rung, perm-tools pins the pre-authorized tool set,
cli-help-parity counts `next` (10), and checkout-guard-denies + ownership-primary pin the two
guards' refusal wording.

## Danger zones — agents NEVER edit these (machine-enforced, ops/RULES.tsv)
| Path | Why |
|---|---|
| ops/polaris, ops/install.sh, ops/dashboard.py, ops/VERSION, ops/MANUAL.md, ops/PROMPTS.md, ops/PROTOCOL.md, ops/KEYS.tsv, ops/index.py, ops/roles/, ops/hooks/, ops/templates/, ops/ci/, ops/lib/ | Installed copies. Edit `kit/ops/…` instead — the installed one is overwritten on the next release install, so the work is lost. |
| kit/ops/VERSION | A bump tells every installed kit in the world that a new POLARIS exists. Human only. |
| .github/ | The CI drills are the last gate between a bad kit and every user. |

`ops/board/`, `ops/contracts/`, `ops/SURFACES.tsv`, `ops/CONVENTIONS.md`, `ops/MAP.md`, `ops/SPRINT.md`
are board STATE, not installed code — they are written normally, by the board scripts and by the
Planner/Integrator (SURFACES.tsv only ever by `polaris done`).

## Generated / vendored — never edit, never read
`.polaris/` (worktrees + update cache + generated brain/ + bg/ job dirs + shots/ captures +
wt-archive/ + handover/ session dirs, gitignored) · `~/.claude/polaris/` (the machine-level awake
and handover copies + the awake registry — arm_machine writes it, never a hand) · `polaris-v5.zip`
(build output, gitignored) · `archive/` (retired files, kept for history — never ships) · `__pycache__/`

## Hotspot files (conflict magnets — Planner must chain these, never parallel-own)
- `kit/ops/polaris` + `kit/ops/lib/*.sh` — the entry is thin since the 5.16.0 split, but each lib
  module is a conflict magnet in its own right; chain tasks touching the SAME module (sprint 10
  chained observe.sh and install.sh serially, 0 kickbacks; sprint 14 put five concerns in observe.sh
  under ONE task for the same reason).
- `ops/tests/api-kit.expected` — a DERIVED-surface golden: it records every top-level fn AND every
  markdown heading AND every KEYS.tsv row under `kit/`, so it silently couples every task that adds
  one (co-change: observe.sh 8×, the entry 8×, spine.sh 5× — brain learned.md). ONE owner per wave
  (ops/contracts/key-registry.md § 5), everyone else surface-frozen — three sprints of defects,
  then four waves at 0 kickbacks, earned this rule. Corollary earned in sprint 14: a cross-lane
  owner's `verify:` never carries a STRICT diff of it (CONVENTIONS § Planner calibration, 2026-09-14).
- `kit/CLAUDE.md` — the protocol. Same problem.
- `kit/ops/install.sh` — fresh path and live-board path are ~40 lines apart.
- `kit/ops/roles/BUILDER.md` · `SOLO.md` · `CONDUCTOR.md` — role prose co-changes as a trio (6-8×);
  a wording change to one usually owes the other two.

## Unverified
- Whether anyone outside this machine has POLARIS installed. The `kit/` split keeps the old
  tarball/raw-channel paths working regardless, so this is untested-in-the-wild, not unsafe.

## Deltas


- "roles/CLAUDE.md/output-style carry the one-copy lane rule (CONDUCTOR 2.5 = run triage) and the named anti-pattern; TASK.md gains surface:; ops/RULES.tsv guards ops/SURFACES.tsv (16 rules)"  (T-139, 2026-09-14)

- "selftest gains the surfaces drill (label surfaces: gate · exemption · selection · stamp scope · health · drift) and five fast-tier sections (surfaces-tsv/match/select/item, stamp-scope)"  (T-138, 2026-09-14)

- "bootstrap.py arm_machine also lands ~/.claude/output-styles/polaris.md and ~/.claude/skills/i-have-adhd/ (arm_file, write-iff-different; never outputStyle in the machine settings); install.sh flips i-have-adhd's disable-model-invocation to false when the target's CONVENTIONS says adhd: on; golden machine-armed"  (T-143, 2026-09-14)

- "core.sh board_pull: under claim: claim-branch, status/board-fm/next/claim first fetch refs/heads/polaris/board from origin (≤1 fetch/60 s, POLARIS_BOARD_PULL=0 skips), fast-forward the local ref and re-materialize the moved set; diverged ⇒ a warning, no write; local-lock pays nothing; remote drill proves it"  (T-148, 2026-09-14)

- "kit/ops/lib/surfaces.sh (NEW, loader slot between workspace and builder): the scaffold engine — surfaces_runner (pytest · jest · vitest · go, grep-only), surfaces_pairs (name-based pairing, ambiguity/breadth/ancestor filters), surfaces_proposal (RUNNER/ROW/SKIP as data); entry gains surfaces [--scaffold [--apply]] and interview usage + dispatch"  (T-140, 2026-09-14)

- "observe.sh: surfaces --scaffold renders the engine's proposal (runner, rows, skips), --scaffold --apply (surfaces_apply; <base> only) writes the rows tagged [scaffold] and sets test_select: when unset — the second sanctioned writer of ops/SURFACES.tsv; doctor and qa print the one-line activation nudge only when a runner is detectable and the map is empty; doctor prints the interview's pending line; golden surfaces-scaffold"  (T-142, 2026-09-14)

- "KEYS.tsv gains column 5 ask (voice · adhd · claim carry it; adhd is a new 6.4.0 key, default off); admin.sh cmd_interview [--pending | --set k=v …] generates the ≤4 first-run questions from the registry and writes answers into CONVENTIONS (adhd: on flips the repo's i-have-adhd opt-in flag); update's epilogue names unanswered preferences; refresh_machine_kit also re-caches the output style + i-have-adhd into ~/.claude"  (T-141, 2026-09-14)

- "roles: INIT's interview is ONE AskUserQuestion generated from KEYS.tsv's ask column (2a renamed, 2c loses the claim question, the skeleton gains adhd:, step 3 runs interview --set then surfaces --scaffold --apply); PLANNER 5b scaffolds at the plan gate; the install skill acts on 'surfaces: none mapped' and 'preferences never set here'; PROTOCOL's tool row names surfaces --scaffold"  (T-145, 2026-09-14)

- "fast tier gains surfaces-runner · surfaces-pairs · surfaces-proposal · interview-pending; the surfaces drill gains steps 8–10 (NORUNNER on the bare fixture · scaffold --apply end to end + feat/* refusal · doctor's pending-preferences line before and after interview --set)"  (T-144, 2026-09-14)

- "update --all runs THIS kit's `update --auto --say` inside each registered checkout (never the target's own ops/polaris — a pre-6.3.0 install answered `unknown flag --auto` and stayed put), accepts --major to apply MAJOR bumps, and removes registry entries whose path is gone; auto-update.md v2"  (T-151, 2026-09-14)

- "seal (direct after the merge · pr at --sync) appends `| <date> | <done pts> | <remaining> |` to the current sprint's  (T-153, 2026-09-14)

- "next_promote (handover.sh) holds a backlog candidate whose plan: is set and differs from the run's plan under drain: plan (`held: <ID> — plan <slug> is not this run's (<P>) — drain: plan`); the run's plan = the session's handover plan file, else the one slug carried by ready ∪ active ∪ review; role-handover.md v2"  (T-154, 2026-09-14)

- "observe.sh: feat_tip_landed (a feat/<ID> tip proven landed — Landed-from equality or base ancestry) + cruft_clear (removes idle proven branches, worktree through wt_remove); drift's cruft check has three classes (waiting = silent · clearable = finding · diverged = finding, never auto-deleted); qa runs cruft_clear before drift --strict; sweep reports clearable cruft and --fix clears it; worktree-liveness.md v2"  (T-152, 2026-09-14)

- "kit/ops/lib/skills.sh (NEW, loader slot after handover; 14 fns: cmd_skill · skill_consts · skill_bytes · skill_paths · skill_tier · skill_hits · skill_list · skill_gaps · skill_budget · skill_propose · skill_promote · skill_demote · skill_prune · skill_restore) — skills POLARIS writes for itself: born hidden, promoted by a human, evicted by data; entry gains skill/amend/learned/promote dispatch + usage, `qa` forwards every flag, `update` usage shows --major; self-skills.md v1 · module-layout.md v7"  (T-155, 2026-09-14)

- "claim emits one skill-hit event per POLARIS-written skill whose paths overlap files_owned (the only skills telemetry); pack prints SKILLS — what POLARIS already knows about these paths (omitted when none overlap) and KNOWN TRAPS now prints WHOLE bullets (≤8/40 lines); slim_scan counts a disable-model-invocation: true definition as 0 B; uninstall's preview names the skills that stay; doctor prints the shelf's over-budget/eviction lines (command -v-guarded)"  (T-156, 2026-09-14)

- "kit/ops/templates/SKILL.md (NEW — the skeleton's static half, seven headings); EVOLVE may propose ONE skill per run and `skill demote` joins its inert allowlist while `skill promote` never does; CONDUCTOR step 7 names `next --do`; INTEGRATOR § 1/§ 6 name `amend` and `learned`; PROTOCOL THE TOOL gains skill/amend/learned/promote rows and the update --major note; MANUAL gains the amend recipe"  (T-158, 2026-09-14)

- "integrate.sh: cmd_amend (amend <ID> --verify <n>|--add|--drop -m why — the sanctioned verify: amendment for a CLAIMED task; refuses on feat/*, refuses a bare full-suite command, one chore(board): amend <ID> verify commit) + amend_verify (the pure list surgery, fast-tier section amend); grant.md v2"  (T-157, 2026-09-14)

- "selftest gains the skills drill (label skills: gaps · propose · twin-or-not per the probe · promote refusals and pass · claim's skill-hit · prune demote/archive · restore byte-identical) and the fast-tier section skills (constants · skill_bytes vs slim_scan on the same fixtures · skill_paths); goldens skill-budget (hermetic: constants, shelf, reserved-name and TODO refusals) + skill-install (a foreign skill survives install.sh and uninstall byte-identical); labels 37"  (T-159, 2026-09-15)

- kit/ops/templates/DESIGN.md — the design bar template INIT copies once to ops/DESIGN.md (never install.sh, never KIT_CODE)  (T-161, 2026-09-17)

- kit/ops/lib/visual.sh — the visual module (SEE YOUR WORK, the capture gate, and from later waves the shots tree and the gallery); loaded between surfaces and builder, never on the write-guard fast path  (T-166, 2026-09-17)
