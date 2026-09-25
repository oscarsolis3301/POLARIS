# MAP — POLARIS            (updated: 2026-09-17, by EVOLVE)

## Stack
Bash (>= 3.2 — macOS default; no mapfile, no assoc arrays) + Python 3 stdlib only.
No package manager, no dependencies, no build step beyond zipping. Runs on Linux, macOS and
Windows/Git Bash; CI proves all three on every push.

## The one thing to understand
The repo is BOTH the product and a user of it. `kit/` is what ships. `ops/` is a real POLARIS
installation running this repo's board. Never hand-edit `ops/` — see ops/CONVENTIONS.md § THE SPLIT.
The installed copy also LAGS the source mid-sprint, and the tell that a selftest ran on the right
driver is the LABEL LIST: `bash kit/ops/polaris doctor --selftest` registers kit-only drill labels
(kit 37 = installed 37 at the 6.5.0 dogfood — `surfaces` landed in 6.4.0 and `skills` in 6.5.0;
sprint 16 added NO drill, because the gallery arrived as a GOLDEN pair (`shots-gallery`) instead —
the counts converge at every dogfood, diverging again the first sprint that adds a drill), so a green
from `ops/polaris` can silently prove none of the sprint's new behavior. The counts move every
sprint: recount `SELFTEST_LABELS` in both `lib/selftest/spine.sh` copies rather than trusting this line.
Goldens are the OTHER suite and they drift faster: 31 pairs in `ops/tests/`, run by NOTHING automatic
— not CI, not the fast tier (§ Board mechanics, 6.6).

## Entry points
| Path | What it is |
|---|---|
| kit/ops/polaris | THE CLI **entry point** — 433 lines: fast paths (find/show/help), the lib loader (`core ownership workspace surfaces visual builder integrate knowledge search observe admin bg awake handover skills`), resolved globals (`SURFACES="$OPS/SURFACES.tsv"` sits under `RULES=`), dispatch (awake · next · surfaces joined it in 6.2–6.4; amend · learned · skill · interview · promote in 6.5; shots in 6.6); the preamble beats the task worktree on every call. Every `cmd_*` body lives in kit/ops/lib/ since 5.16.0. The `qa)` first-flag-only bug is FIXED (6.5.0, T-158): every flag is forwarded. |
| kit/ops/lib/ | The command bodies — runtime-sourced modules: core (cfg · frontmatter · the RULES cache · the surface-map data plane: surfaces_lines/seed, surface_row_matches/rows_for/row_from_item, surface_change_set/select_cmd, suite_stamp_scope, reading ops/SURFACES.tsv + CONVENTIONS `test_select:`) · ownership (check_rules → check_freshness, the stale-tests gate) · builder · integrate · knowledge · observe · admin · search (the thin `find`/`show` shim over index.py) · workspace (shared-checkout mechanics: id_ok · wt_add · stray_feat_repair · int_on/int_off integration lease, rc 3 queued · park/unpark · beat_touch/beat_age/beat_live, the worktree liveness signal at `$GCD/worktrees/<ID>/polaris-beat` · wt_remove, the ONLY worktree-removal primitive: rc 0 removed / 1 left / 2 archived to .polaris/wt-archive/, never --force) · bg (background jobs: run/status/tail/wait, dir-per-job `.polaris/bg/<name>/`, rc-file-first verdicts, `.prev` rotation, sweep --fix rotates >24h) · awake (keep-awake: status/start/stop/disable/enable/install; awake_ensure fires from claim/status/doctor/handoff/bg run and honours the machine `disabled` flag) · handover (`next`, `next --do`, `next --brief`: resume/integrate/stop/build/promote/wait/finish read off the board; next_promote IS the promote pass — the full ready gate under the board lock, ONE `chore(board): promote <IDs>` commit) · surfaces (6.4.0 — the scaffold engine behind `surfaces [--scaffold [--apply]]`: surfaces_runner · surfaces_pairs · surfaces_proposal; the SECOND sanctioned writer of ops/SURFACES.tsv) · skills (6.5.0 — the skills POLARIS writes for itself: cmd_skill · skill_gaps · skill_propose · skill_promote · skill_demote · skill_prune · skill_restore) · visual (6.6.0 — SEE YOUR WORK, the capture gate, the shots tree and the gallery: visual_slug · visual_shotdir · visual_shots_for · visual_pack · visual_gate · visual_file_strays · visual_caption · visual_index · visual_publish · cmd_shots; loaded between surfaces and builder, NEVER on the write-guard fast path) + selftest/ drill groups (fast.sh = the in-process tier). Contracts: module-layout (§ v8 caps visual.sh at 450 lines / 10 fns — it is AT that cap today) · shared-checkout · bg-jobs · worktree-liveness · keep-awake · role-handover · fast-tier · test-surfaces · self-skills · visual-check. |
| kit/ops/install.sh | Installs the kit into any repo. Two paths: fresh vs live-board (test = target has ops/CONVENTIONS.md). Settings merge: POLARIS-owned hook entries (identified by the `ops/hooks/` script PATH, never basename) are REPLACED with the kit's current fields on re-install; user-added hooks and all other keys keep skip-if-present (key-registry.md § 6). Ships ops/VISUAL.md, chmods awake-hook.sh + handover-hook.sh, and registers the repo in ~/.claude/polaris/awake/repos at install and update time (not only on awake activation). |
| kit/ops/bootstrap.py | The zipapp entry — packed to the archive ROOT as `__main__.py`, so `python polaris-v5.zip` just works. Also arms the machine: ~/.claude skill + cached kit + permission rules; arm_machine copies awake-hook.sh + awake-press.ps1 to ~/.claude/polaris/ and merges the four machine hooks (merge_awake_hooks); PERMS pre-authorize the harness's own tools (EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage — golden perm-tools pins the set and the two human gates' absence). Since 6.4.0 arm_machine also lands `~/.claude/output-styles/polaris.md` and `~/.claude/skills/i-have-adhd/` (arm_file, write-iff-different — never `outputStyle` in the machine settings), and install.sh flips i-have-adhd's `disable-model-invocation` to false when the target's CONVENTIONS says `adhd: on` (golden machine-armed). |
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
| kit/ops/templates/ | TASK.md (gains `surface:` in 6.4.0, `screen:` in 6.6.0), CONTRACT.md — what the Planner instantiates — plus ROADMAP.md, the human-authored standing-goal skeleton; SKILL.md (6.5.0, the self-written skill's static half — seven headings) and DESIGN.md (6.6.0, the design bar, copied ONCE to ops/DESIGN.md by INIT and by `heal` — never install.sh, never KIT_CODE). | |
| kit/ops/PROTOCOL.md | The extended protocol: full command table · LANES · TOKEN DISCIPLINE · § MODEL ROUTING (auto — `polaris route` decides; knobs, override, honest boundary) · § LONG COMMANDS (measured suite tiers vs the 600s tool cap, bg doctrine, subagent turn rule) · § N CHATS, ONE REPO (the second-chat decision table). | |
| kit/ops/VISUAL.md | The SEEING YOUR WORK doctrine — the capture is the proof. Installed as ops/VISUAL.md (6.2.0), and RULES-guarded as an installed copy since 6.6.0 — `ops/DESIGN.md` deliberately is NOT, because the bar is the repo's own to write. `pack` prints the SEE YOUR WORK section from shot:/visual:/port_base:/serve:, `handoff` refuses a visual change without fresh captures, `audit` lists them. | Contracts: ops/contracts/visual-check.md (§ v2 = the 6.6.0 breaking change) · the bar itself lives in ops/DESIGN.md. |
| kit/ops/KEYS.tsv | The CONVENTIONS key registry (key · since · default · absent-cost), shipped via KIT_CODE; doctor's one-line drift report and `polaris adopt` consume it. Rows since 6.1: landing (6.1.0) · wt_live_minutes shot visual port_base serve handover (6.2.0) · auto_update (6.3.0, default on in code) · test_select + adhd (6.4.0; test_select unset = byte-identical to 6.3) · gallery (6.6.0, `<dir or omit>`). Column 5 `ask` (6.4.0) carries the first-run interview question (`voice` · `adhd` · `claim` have one); `interview [--pending | --set k=v …]` generates the ≤4 questions from it and writes the answers into CONVENTIONS. | Contract: ops/contracts/key-registry.md. |
| kit/ops/MANUAL.md | Fallback git recipes for environments that cannot execute the CLI. | Must mirror the CLI's behaviour. |
| kit/ops/PROMPTS.md | Copy-paste kickoffs for every role. | |
| kit/ops/VERSION | version + the four URLs (channel/tarball/repo/zip) that installed kits poll. | **Human-only.** A bump is a release act. |
| kit/ops/ci/ | polaris-audit.yml — the OPTIONAL board gate shipped to users. Not our CI. | |
| kit/ops/selftest-install.sh | Local install drill: fresh · old-client · live-board · zip purity · uninstall. | The `test:` for any install.sh change. Run it with POLARIS_AWAKE_HOME pointed at a scratch dir. |
| kit/ops/selftest-dashboard.sh | Dashboard smoke drill: start · GET / + /state · kill. | |
| kit/.claude/ | settings.json (wires the two guards + readonly-allow, the handover hooks, the `startup` update hook; PERMS pre-authorize the harness's own tools) + skills/polaris (project) + skills/polaris-install (user-level, cached to ~/.claude at install). | |
| .github/workflows/ | OUR CI. ci.yml = 3-OS drills + "one version, everywhere". release.yml = tag → publish the zip. **ci.yml runs `doctor --selftest` ONLY** — it never runs `polaris check`, so no golden pair is gated by CI. | Danger zone: agents may not edit their own tests. |

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
- 6.5 the self-written shelf and the board's two new verbs (self-skills.md · grant.md v2 ·
  role-handover.md v2): `.claude/skills/<name>/SKILL.md` pairs POLARIS writes for ITSELF — born
  HIDDEN (`disable-model-invocation: true` injects 0 prompt bytes, so writing one costs nothing),
  proposed by EVOLVE off `skill gaps`, `skill promote`d ONLY by a human, evicted by `skill prune` on
  the data; `claim` emits one skill-hit event per skill whose paths overlap `files_owned` (the only
  skills telemetry) and `pack` prints a SKILLS section. `amend <ID> --verify <n>|--add|--drop -m why`
  is the sanctioned `verify:` surgery on a CLAIMED task (refuses on `feat/*`, refuses a bare
  full-suite command, one `chore(board): amend <ID> verify` commit) — `grant` widens `files_owned`
  and until 6.5 NOTHING widened a `verify:` line. `learned -m` is the one writer of a SPRINT Learned
  bullet; `seal` appends the burndown row. `next_promote` HOLDS a backlog candidate whose `plan:`
  differs from the run's under `drain: plan`. `drift`'s cruft check has three classes (waiting =
  silent · clearable = finding · diverged = finding, never auto-deleted) and `qa` runs `cruft_clear`
  first. `board_pull` fast-forwards `refs/heads/polaris/board` from origin ahead of
  status/board-fm/next/claim (≤1 fetch/60 s, `POLARIS_BOARD_PULL=0` skips; diverged ⇒ a warning,
  never a write). `update --all` runs THIS kit's `update --auto --say` inside every registered
  checkout and accepts `--major`.
- 6.6 the gallery and the bar (visual-check.md § v2 · module-layout.md § v8): a task's `screen:`
  becomes a SAFE slug and a per-task shot folder; `pack` says photograph the screen BEFORE you touch
  it; `handoff` counts TWO captures — before AND after, `--no-before <reason>` the escape hatch —
  takes `--saw` as recorded data, files the strays and writes the caption; `polaris shots` rebuilds
  `.polaris/shots/INDEX.md`, the one file the owner opens; and with CONVENTIONS `gallery: <dir>` set,
  `done` publishes ONE curated image + caption per screen onto the base commit it already makes.
  Three constraints the carve obeys and any future change must too: **POLARIS ships no capture
  tool**, so the gate is COUNT AND FRESHNESS and never inspects filenames (a filename rule would
  brick every 6.2–6.5 repo); `cmd_done` must NOT take the integration lease (the self-land tail
  calls it as a subprocess, so `int_on` there deadlocks the default path); and bash 3.2 has no
  `globstar` and no `${x,,}`. The bar itself lives in `ops/DESIGN.md` so it stops being pasted into
  every visual task.

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
drill label `adopt` in remote.sh proves it) · `next [--do|--brief]` (6.2.0) · `promote` (literally `next --do`, 6.5.0) · `awake
status|start|stop|disable|enable|install` (6.2.0) · `update [--auto|--all|--major]` (6.3.0) ·
`surfaces [--scaffold [--apply]]` (6.4.0) · `qa [--force] [--full]` (6.4.0; every flag forwarded
since 6.5.0) · `interview [--pending|--set k=v …]` (6.4.0) · `amend <ID> --verify <n>|--add|--drop
-m why` · `learned -m` · `skill gaps|list|propose|promote|demote|prune|restore` (6.5.0) · `shots`
(6.6.0). Selftest labels now 37: `wtreap` (history.sh) · `awake` (policy.sh) · `handover` (board.sh)
joined in 6.2.0, `autoupdate` (remote.sh) in 6.3.0, `surfaces` in 6.4.0 and `skills` in 6.5.0; the
spine exports POLARIS_AWAKE_HOME so no drill touches the owner's awake registry. The 31 goldens are
the second suite: handover-route + handover-stop pin every `next` verb and hook rung, perm-tools
pins the pre-authorized tool set, cli-help-parity counts `next` (10), checkout-guard-denies +
ownership-primary pin the two guards' refusal wording, skill-budget + skill-install pin the shelf,
rules-health pins the RULES count and route-tier the model refusal, and shots-gallery walks the
whole visual path hermetically. Read the § Board mechanics 6.6 note before trusting a green from
them: nothing runs this suite automatically.

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
  under ONE task for the same reason; sprint 16 chained FIVE tasks through the brand-new
  `kit/ops/lib/visual.sh` on the same rule — T-166→T-167→T-168→T-169→T-170, 0 kickbacks).
- `kit/ops/lib/visual.sh` — additionally SIZE-capped: module-layout.md § v8 pins it at 450 lines and
  ten top-level fns, and it landed at EXACTLY 450/450. Until the cap moves, any change to it is a
  trade, not an addition — point the task accordingly.
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

- kit/ops/hooks/model-guard.sh v2 — also handles SessionStart, PreModelSwitch, PostModelSwitch and PostToolUse(Agent); the per-call verdict reads ~/.claude/polaris/model-state/<session_id>; bench.sh gains a `guards` mode; new golden ops/tests/model-guard-v2  (T-173, 2026-09-24)

- new golden ops/tests/drift-deps — drift's dependency check is one awk pass over every column, its branch checks loop over feat/* refs, and `check` run from .polaris/wt/<ID> tests that worktree  (T-177, 2026-09-24)

- docs/spikes/ — new: laya-s1.md, the Laya host, latency and harness-probe verdict that Sprint 19's router reads  (T-181, 2026-09-24)

- new golden ops/tests/qa-stamp — qa keeps a green suite's stamp when only CRUFT is red; CONDUCTOR step 7.5 runs EVOLVE before the final qa; land --express runs verify: before seal  (T-179, 2026-09-24)
