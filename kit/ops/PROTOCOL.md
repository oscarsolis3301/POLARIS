# POLARIS v5 — PROTOCOL reference

The half of the protocol that only SOME sessions need. `CLAUDE.md` is the router every session pays
for (the harness injects it into the conductor and into every subagent); this file is what you open
when you actually need it. Read the section you need, not the file.

| you need | section |
|---|---|
| the command table — what `polaris <x>` does | THE TOOL |
| what lives where on disk | STATE = THE BOARD |
| why a lane exists, and why one role never does two jobs | LANES |
| what a second chat does when the lock, the lane or the tree is busy | N CHATS, ONE REPO |
| the lookup ladder · when the layout pass runs · ask first, then finish | SAVE HOPS |
| how to stay cheap: pack-first, find-first, read-less | TOKEN DISCIPLINE |
| which model tier a role deserves | MODEL ROUTING |
| how to run a command that outlives the 600s tool cap | LONG COMMANDS |
| how to TALK to the human | VOICE |
| how to behave as a model running this | MODEL NOTES |

## THE TOOL — `ops/polaris`
Every board mechanic is one command. You MUST use the script instead of hand-rolling git recipes; it is race-tested. (Environment can't execute commands? Follow the kit's `MANUAL.md` (beside `ops/polaris`) literally instead.) This table is a curated subset for daily board work — `ops/polaris help` prints the full command list, including admin/plumbing left out here on purpose (`init-board`, `resume`, `task-commit-msg`, `why`, `uninstall`). The script itself is `globals + lib-loader + dispatch`: `ops/polaris` is the only entry point, and every function body lives in `ops/lib/*.sh`, sourced in a fixed order at startup (a missing module refuses with a re-run-installer / `ops/polaris update` remedy).

| Command | Does |
|---|---|
| `ops/polaris pack <ID>` | **the whole context for one task, in ONE call** — frontmatter + Why + acceptance, the contract verbatim, the repo's detected house style, the code-map for every owned directory, the public API surface each owned path must not break, the gotchas/co-change lines that mention an owned path, and the exact `verify:` commands. Run it FIRST, before reading anything. It replaces the 6-15 exploratory round trips a cold Builder otherwise spends rediscovering its own task |
| `ops/polaris find <symbol>` · `show <path>#<symbol>` | the 1-hop "where is X": `path:line` + signature per hit, ranked, from a generated index; `show` prints ONE symbol's body instead of the file. `--api <glob>` = the sorted public surface of a path (the shape goldens lock). Run these BEFORE Grep |
| `ops/polaris new <draft.md>…` | file new tasks in ONE command: each draft (from `bash ops/polaris doc templates/TASK`) gets the next free `T-NNN`, is checked (points 1–5, or up to 13 with `steps:`, `plan:`, `risk:`, `files_owned`, a named contract exists) and placed by the ready gate — `ready/`, or `backlog/` while it waits on a task, and a task in `ready/`, `active/` or `review/` that shares a file with it joins its `depends_on`. ONE board commit for all of them; a refusal writes nothing. SOLO, TIDY and the Planner file their tasks with it; `bash ops/polaris doc MANUAL` keeps the by-hand recipe |
| `ops/polaris new --retire <map> <draft.md>…` | file the successors of a re-cut plan and retire their predecessors in the SAME board commit: every `old<TAB>new` pair of the map is checked as `retire` checks it (a successor may be a draft of this call), the old cards move to `ops/board/retired/` before placement, so no draft is chained to a card it retires. `new` also owns each draft's SURFACES-mapped tests itself, and the guide of each folder a draft adds a file to (a file git does not track yet — a card that only edits tracked files gains no guide, so two cards in one folder stay side by side), and lists on stderr the tests that name a card's files and the files that use them |
| `ops/polaris claim [ID]` | atomic lock + ready→active + worktree (no ID = top wsjf) |
| `ops/polaris verify` | proves `diff ⊆ files_owned`, no `ops/RULES.tsv` hit, and the stale-tests gate (a mapped surface that changed must have changed its tests — `ops/SURFACES.tsv`) + runs the task's `verify:` commands |
| `ops/polaris handoff` | verify + active→review; `publish: direct` with `push: wave` pushes feat/<ID>, `push: end` (the default) and `publish: pr` keep it local (seal pushes only integrate/<date> under pr) — run inside your worktree |
| `ops/polaris handoff --hold` | the handoff of a card waiting on the owner's yes: everything handoff does up to its board commit, plus `held: yes` — then it STOPS in `review/` with nothing landed. A held card is never landable on its own, never holds back another lane's seal, and the self-landing fan-out skips it. After the yes: `land <ID>`, then `seal` |
| `ops/polaris release <ID> --to ready\|blocked -m "why"` | clean abort |
| `ops/polaris grant <ID> <path> -m "why"` | append one path to a CLAIMED task's files_owned; refuses any overlap with another ready/active task's ownership |
| `ops/polaris note <ID> -m "<line>"` | append ONE Notes line to a CLAIMED task in its own board commit — how a Builder records an `assumed:` default |
| `ops/polaris amend <ID> --verify <n> -m "why" -- <cmd…>` | Integrator: replace, drop (`--drop`) or append (`--verify --add`) ONE `verify:` line of a CLAIMED task — the sibling of `grant`, which widens what a task may TOUCH where this corrects what it must PROVE. The case it exists for is a cross-lane golden owner handed a line that cannot pass until a sibling lands. Refuses on any `feat/*` branch (a Builder never rewrites its own gate) and refuses a bare full-suite command; a refusal mutates nothing, and the why lands on the task's record |
| `ops/polaris amend <ID> --deps +<ID>\|-<ID> -m "why"` | add or drop ONE `depends_on` of a card in `backlog/`, `ready/`, `blocked/` or `active/` — never a hand edit. Refuses on any `feat/*` branch, without `-m`, beside `--verify`, for a task not on the board, the card itself, a dependency already there (or not there), and a `+` that would close a cycle. A `ready/` card gaining an unfinished dependency moves to `backlog/` in the same commit; dropping one never promotes (`promote` does). ONE board commit |
| `ops/polaris audit / run-verify / kickback / done <ID>` | Integrator: check, re-check, bounce red work, land |
| `ops/polaris land <ID>` · `land --express <ID>` | Integrator: squash a reviewed task into ONE commit on `integrate/<date>`. `--express` = one-pass small-change landing (land + full suite + seal + done in one session); refuses unless exactly one review task, `risk: normal`, `express:` ≠ off, `publish: direct` |
| `ops/polaris seal [<date>]` | Integrator: before anything merges, the seal runs the wave check — the tests `ops/SURFACES.tsv` maps to what the wave changed, at every seal, and the whole `test:` for paths no row covers at most once per `wave_check:` minutes (default 60), and only while cards of the run are still to build (the last wave leaves it to `finish`) — and a red keeps `integrate/<date>` open, names the cards and records `wave-red` (silent when `test:` is unset). Then `publish: direct` — fold `integrate/<date>` into `<base>` with one `--no-ff` merge + tag `sprint/<n>` (a later seal MOVES the tag — the sprint's latest sealed checkpoint); `push: end` keeps both on this machine for `finish`, `push: wave` sends base and tag in ONE atomic push. `publish: pr` — push ONLY `integrate/<date>` + print the PR-create URL; the human merges it with a MERGE COMMIT; then `seal --sync` pulls `<base>`, verifies every `[<ID>]` landed, moves/creates the tag, deletes `integrate/<date>` both sides |
| `ops/polaris seal --no-check -m "why"` | the recorded way past a red wave check that is not the wave's code (a broken runner, a flaky machine): the seal skips the check, says `wave check: skipped by hand — <why>` and records a `wave-check-skipped` event. Refused on any `feat/*` branch and without `-m`; `finish` still runs the whole suite |
| `ops/polaris promote` | `= next --do`: hold every `backlog/` task to the full ready gate under the board lock, promote the ones that clear it in ONE `chore(board): promote <IDs>` commit, print `held:` lines for the rest, then print the fresh route. This is the dependency-chain pass after every wave — moving task files between folders by hand is the thing it replaces |
| `ops/polaris check` · `check --scaffold` | golden-output acceptance, ZERO LLM: `ops/tests/<name>.cmd` is run and its stdout diffed against `<name>.expected`. `--scaffold` GENERATES the pairs from observed behavior (public API surface per source dir + parsed output shapes), discarding anything that flaps or is empty. Regression locks, not correctness proofs — review them once, then they cost a subprocess forever |
| `ops/polaris report [--sprint <n> \| --all]` | read/write: render the management-readable per-sprint record to `<reports>/sprint-<n>.md` from board state (no flag = current sprint); never commits — `seal` rides the report into the wave |
| `ops/polaris learned -m "<bullet>"` | append ONE lesson to `ops/SPRINT.md` § Learned from any lane, any branch, as its own board commit — the Planner reads it first and EVOLVE prunes it. `seal` writes the burndown row itself, so SPRINT.md is never hand-edited |
| `ops/polaris history [--tasks <n>]` | read-only: `<base>`'s first-parent log, `chore(board):` commits filtered out; `--tasks <n>` spans all a sprint's waves |
| `ops/polaris rollback <ID \| sprint/<n>>` | revert a landed task, or `sprint/<n>` for the sprint's latest sealed wave — never resets, never force-pushes |
| `ops/polaris status [--brief\|--all] / sweep / doctor [--selftest [--only <pattern>]]` | board view (`--brief` = one plain-English paragraph, no table; `--all` adds the `retired` count and each retired card with its successor) · stale locks + merged `integrate/*` strays · env check (`--only <pattern>` = spine + only labeled drills matching `<pattern>`) |
| `ops/polaris board-fm [<col>…]` | one TAB line per task — the nine fields the ready gate and dedupe use. The Planner reads THIS, never the board files |
| `ops/polaris dash / metrics` | live board at 127.0.0.1:7373 · cycle/kickbacks/per-point calibration (`metrics` opens with a plain-English summary line) |
| `ops/polaris brain [--refresh]` | (re)build `.polaris/brain/` — a generated, gitignored, any-model knowledge base that kills cold-start re-derivation; `--refresh` = incremental rebuild. `doctor` warns when it's stale |
| `ops/polaris notify-gate <kind> [ID]` | fire the notify: hook at a human gate — kinds `plan` · `risk <ID>` · `question <ID>` · `done [ID]`; observe-only, never writes the board |
| `ops/polaris drift / rules / surfaces [--scaffold [--apply]]` | mechanical board-hygiene audit (`--strict` for CI) · policy file list + health · the test map (`ops/SURFACES.tsv`: which tests cover which source paths) + its health — a `tests` glob that covers its own surface is refused, a glob matching 0 or >200 tracked files is flagged, and `drift` carries the refusals as findings. `--scaffold` proposes a map from the layout and writes nothing; `--apply` writes the unambiguous rows and sets `test_select:`, on `<base>` only. Rows are written only by `done` from a task's `surface:` list or by `--scaffold --apply`, never by hand |
| `ops/polaris qa` | "is everything okay?" in ONE shot: CONVENTIONS suite (test/lint/typecheck/build/uat) + `drift --strict` + doctor. Runs every check even after a red; rc 1 on any red. `finish` runs this for you at the close. With `test_select:` set in `ops/CONVENTIONS.md`, `test:` is scoped to the `ops/SURFACES.tsv` rows a change can break (one unmapped changed path → the whole suite; `qa --full` runs `test:` verbatim); unset, every change runs the whole `test:` suite, byte-identical to before |
| `ops/polaris bg run/status/tail/wait` | run and collect suite-length commands without blocking: `run <suite-key\|name -- cmd…>` detaches it, `wait` collects in bounded chunks (`--max` defaults to 300s, deliberately half the 600s tool cap). rc 0 green · 1 red · 2 running · 3 unknown — parse the code, never the prose. Past the cap this is the only way a result comes back at all, because a timed-out call returns NOTHING and gets re-run; see § LONG COMMANDS |
| `ops/polaris finish` | "is the RUN over?" — the mechanical half of CONDUCTOR.md's run-over definition in ONE call: nothing building, nothing waiting to land, `ready/` drained per `drain:`, no unmerged `integrate/<date>`, no orphan lock, clean tree, `qa` green on `<base>`. Under `publish: direct` the green path then makes THE one push — base and the sprint tags to origin in one `--atomic` push (`pushed: <n> commit(s) and <k> tag(s) to origin in one push`); a failed push is rc 1 and `finish` runs again. rc 0 = complete, and the `notify-gate done` hook fires exactly once per finished state; rc 1 names every pending thing. `caveat:` lines are not gates — the close must mention them. **The last command of every lane**, and the only thing that licenses the `# 🎉 Complete!` H1 (ops/contracts/run-finish.md) |
| `ops/polaris route [<ID> \| --role R \| --points N --risk R]` | which model tier a task or role deserves, in one hop: line 1 is a bare `strong` \| `mid` \| `cheap`, so a caller branches on it blind, and a three-space `model:` note follows ONLY when a `model_*` knob (or the task's own `model:` frontmatter) maps that tier to a real name. Unset knobs = tier words only, behaviour unchanged. The CONDUCTOR runs it before every spawn; `fleet` injects its answer into every pane |
| `ops/polaris speed [--plan <slug> [<draft.md>…]]` | read-only: how changes get tested here, build and land medians, `build by lanes:` and the `lanes:` count that lands the most cards per hour. `--plan` prices a plan — its cards, waves on the critical path, lanes, and a `projected:` time against `target_minutes:` (default 60); over it, the Planner re-cuts once. Keys that shape a run's minutes: `push:` (`end` = one push at `finish`, `wave` = one push per seal), `heavy_slots:` (heavy jobs at once on this machine, default 1, 0 = no limit), `target_minutes:` |
| `ops/polaris presence` | read-only: is the owner here or away? Line 1 is a bare `away` \| `here`, then ONE `why:` line. `away` = a plan was approved in this session AND it runs in auto mode; anything else, an unknown included, is `here`. Away, nobody is asked anything (§ SAVE HOPS) |
| `ops/polaris fleet <N> [--launch]` | print N Builder kickoffs; `--launch` opens a session per ready task in tmux windows or side-by-side Windows Terminal panes (`--dry-run` previews). Planner runs this per `autolaunch:` |
| `ops/polaris slim [--apply\|--restore]` | the per-context TOKEN TAX, measured. Every skill/agent/command definition under `~/.claude` injects its name+description into the system prompt of every session AND every subagent, invoked or not. Reports bytes per family and what a 6-8 context run pays for them; `--apply` MOVES the identified claude-flow machinery into `~/.claude/.polaris-archived/` (never deletes, always `--restore`-able) and leaves anything it cannot positively identify alone |
| `ops/polaris tune` | the tune-up report: one line per thing that slows this project, each with its `   fix:` line — `cards:` (waiting chains that fold), `layout:` (the pass is due), and the settings kinds `lanes:` `landing:` `checks:` `behind:` `context:`, which come back as proposals and are never applied. rc 0 = nothing to do · 1 = findings · 2 = usage. Its only write is `.polaris/tune-due`, the verdict `next`, `triage` and `update` read for free |
| `ops/polaris fold <ID> <ID>…` | a chain of waiting cards (ready/ + backlog/, same plan, risk and contract, 1-5 points each, ≤ 13 in all) becomes ONE chain card: the first ID survives in place with the rest as its `steps:`, every card that waited on a folded ID waits on it instead. ONE board commit, so one `git revert` undoes it; every refusal writes nothing |
| `ops/polaris retire <ID>… --by <ID> -m "why"` · `retire --map <file> -m "why"` | re-cut a filed plan with a command, never hand edits: waiting cards (`backlog/` `ready/` `blocked/`, unclaimed) move to `ops/board/retired/` with `retired_by:` stamped, every card that waited on one waits on its successor (a rewired `ready/` card waiting on unfinished work drops to `backlog/`), an empty `feat/<ID>` branch goes. ONE board commit; every refusal writes nothing |
| `ops/polaris skill list / gaps / budget / propose <glob> / promote / demote / prune / restore` | the skills POLARIS writes for ITSELF about this repo's surfaces (`ops/contracts/self-skills.md`): `gaps` names the surfaces the board keeps returning to with no skill · `propose <glob> --write` writes one BORN HIDDEN, injecting 0 prompt bytes, so a repo pays nothing for a skill until it earns its place · `promote` flips it visible and `demote` flips it back · `budget` is the shelf · `prune` reads the eviction verdicts off `EVENTS.ndjson` and `--apply` ARCHIVES (never deletes — `restore` brings one back, even on a machine that never held the archive). Nothing fires uninvited: EVOLVE proposes a promotion, a human runs it, and every writer refuses on `feat/*` and commits nothing |
| `ops/polaris version / update` | which POLARIS this repo runs · **fetch the latest kit** — also re-caches it into `~/.claude` so the next repo gets it too. An installed repo self-updates at session start when the board is quiet (`auto_update: off` stops it); a MAJOR version only ever asks; `update --all` walks every repo on this machine with THIS kit's code, so an install too old to understand `--auto` is updated all the same — `--major` also applies major bumps (the session-start hook never passes it) |
| `ops/polaris upgrade` | migrate an OLD BOARD v3/v4→v5. Downloads nothing. **Not** `update` — one letter apart, unrelated jobs; "upgrade POLARIS" almost always means `update`. |

History model, in one line: a task lands as one squash commit, a sprint seals as one tagged `--no-ff` merge (a later seal moves the tag to the sprint's latest sealed checkpoint), and `history` reads it back with board chores filtered out — `--tasks` spans all a sprint's waves.

Board commits touch only the moved set (`ops/board/**` + `ops/SPRINT.md`) on `refs/heads/polaris/board`; everything else in `ops/` (`MAP.md`, `contracts/`, `CONVENTIONS.md`, `RULES.tsv`) stays on `<base>`.

## STATE = THE BOARD (git-tracked, human-readable)
```
ops/
  polaris          # the CLI above
  lib/             # ops/lib/*.sh — CLI function bodies sourced in fixed order: core·ownership·search·builder·integrate·knowledge·observe·admin + selftest/
  index.py         # `polaris find/show` — generated SQLite code index (.polaris/index.db)
  dashboard.py     # `polaris dash` — read-only live board (stdlib, no pip)
  VERSION          # kit version + update channel — `polaris version` reads this
  PROTOCOL.md      # this file — the half of the protocol only some sessions need
  MANUAL.md        # fallback recipes if you cannot execute commands
  PROMPTS.md       # copy-paste kickoffs for every role
  MAP.md           # ≤200-line codebase map. Read THIS, not the repo.
  RULES.tsv        # repo policy as DATA, one line each — three kinds: `path` · `content` · `ask`
                   #   `ask` = the same denial as `path`, lifted only by a human's recorded approval on the task
  CONVENTIONS.md   # config header (base/claim/integration/test cmds) + rules
  SPRINT.md        # goal, capacity, burndown, Learned log
  contracts/       # interface contracts — the seams between tasks
  templates/       # TASK.md, CONTRACT.md
  tests/           # <name>.cmd + <name>.expected — golden acceptance, run by `polaris check`
  hooks/ ci/       # Claude Code write-guard · optional GitHub Actions gate
  board/
    backlog/ ready/ active/ review/ done/ blocked/   # one .md per task
    EVENTS.ndjson  # append-only telemetry (union-merged) — never hand-edit
```
`.claude/` ships a project skill (auto-routes any Claude Code session to this protocol) and a PreToolUse hook wiring the write-guard.
A task's state is the folder its file sits in; moving it (via the script) is the transition. Worktrees live in `.polaris/wt/<ID>` (gitignored). Locks live in `$(git rev-parse --git-common-dir)/polaris-locks/` — shared across all worktrees, never committed.

Wherever a role file says "the value in ops/CONVENTIONS.md", it means the effective value: this repo's line, else this computer's preferences file, else the kit default — bash ops/polaris prefs shows all three and which one wins.

## LANES — why the lane is a command, and why a role never does two jobs

**The phases were never the expense. The CONTEXTS were.** Measured 2026-07-25/26: `qa`, `verify`,
`check`, `triage` and `drift` are pure shell and cost zero LLM tokens — "cut the QA step to go
faster" removes a gate and saves nothing. What costs is that a one-line change used to open four
contexts (conductor, planner, builder, integrator), each re-injecting `CLAUDE.md` and its own role
file, plus ~7,300 tokens of skill/agent definitions, before reading a word of the actual work.
That is roughly 62 KB of boilerplate to move one line.

So POLARIS collapses SESSIONS, never CHECKS:

| lane | contexts | when `triage` picks it |
|---|---|---|
| `solo` | **1** | small and few, nothing a human must decide — `triage` prints the budget it applied and the arithmetic behind it |
| `express` | 2 | one small task, one builder, one integrator |
| `full` | 4+ | anything else — real parallelism, real merge risk |

Every gate the long path runs, SOLO runs: `verify` (ownership + RULES), the task's `verify:` list,
the test run the change's size calls for at `land --express` (`polaris depth` — the whole suite only
at `full`; § LONG COMMANDS has the table), then `qa`. If you find yourself skipping a gate to make a
change fit the lane, **the lane is wrong** — release it back and take the full loop.

**Checks cost no tokens — they cost minutes.** Each card pays a claim, a worktree, its `verify:`
list, a land and a share of a seal, so ten one-point cards cost far more wall time than one card of
ten. **The unit to save is a card.** A card runs its own checks and the full suite runs once per
wave (Invariant 4); a chain of dependent work is one card of up to 13 points with `steps:`, built one
commit per step (Invariant 2); and `speed --plan <slug>` prices a plan before it is approved, against
`target_minutes:` (default 60). One heavy job (a verify list, `qa`, the express suite, the push) runs
at a time on a machine (`heavy_slots:`, default 1), and under `push: end` (the default) code reaches
origin once, at `finish`.

**`triage` is mechanical on purpose.** It reads points, risk, `express:` and the RULES-guarded
paths straight off the board. A model weighing those conditions from prose gets it
wrong occasionally, and a wrong guess toward `full` costs a whole sprint of contexts while a wrong
guess toward `solo` strands a half-built task. The command is free; the judgement is not. That is
also why the conditions are written in the command and nowhere else: a role file that restated them
drifted from the code within a release, a model reading both found itself holding a judgement call
the protocol never gave it, and it handed the tie-break to the human as a menu of lanes. Never
re-derive the lane in prose and never offer it as a choice — the interview is about the product.

**One role per session** because a role's whole safety argument is its narrow context: a Builder that
also plans starts inventing interfaces, and one that also integrates merges its own red work. The
sole exception is the one-time INIT → PLANNER bootstrap — it runs once per repo, before any Builder
exists, on the base branch, and writes zero feature code, so that installing POLARIS leaves you with
a planned board instead of homework. The CONDUCTOR is **not** a second exception: it holds no role
at all and delegates each one to a fresh subagent, so roles still never mix inside one context.

**Self-landing is that same collapse applied to every lane** (`landing:` in `ops/CONVENTIONS.md`,
since 6.1.0; unset composes to `self` in code, because `update` never rewrites an installed
CONVENTIONS). SOLO and `land --express` proved one session can carry one task from claim to merged;
`landing: self` generalizes the precedent: a Builder's `handoff` continues into a lease-gated
`land`, and the last lane out seals the wave. This is not a second role in the session — the
integration lease IS the Integrator (Invariant 9): there is exactly one holder at any instant, and
taking it is what makes a session one. No check moves: verify/ownership/RULES still gate the
handoff, `land` is still squash + audit, the full suite still runs once per wave, and the hard
stops keep the classic path — risk: high never self-lands — a human must approve the merge; task stays in review/ (unless the approved plan covered it: `approve --plan`).
The landing tail can wait on a busy lease, so a session detaches it (`bg run ship-<ID>` + chunked
`bg wait --max 120` — § LONG COMMANDS) and polls the rc; `landing: integrator` restores the classic
handoff byte-for-byte.

**Handover is that chain's last link** (`handover:` in `ops/CONVENTIONS.md`, since 6.2.0; default
`auto`). SOLO collapsed four contexts into one, `land --express` collapsed the Integrator's,
`landing: self` gave every lane that landing, and handover finishes the argument: at a boundary the
BOARD proves — a completion event `bash ops/polaris next` reads back — one chat sheds the finished
task and continues as the role `next` names, compaction being the context reset. SESSIONS again,
never CHECKS: every gate runs exactly as before, and **a hop consumes exactly one completion
event** (the hook licenses it by string equality, so a hop can never fire twice on the same event).
`handover: off` restores one task per session.

## N CHATS, ONE REPO — who waits, who parks, who queues
Several chats, one checkout. The second session finds the task locked, the integration lane held, or
somebody else's edits in the tree — and none of that is a question for the human:
**git/workspace mechanics are never ask material after plan approval — the CLI prints the next step; follow it.**
The behavior this replaces was emergent, never designed: nothing told a second chat what to DO, so it
improvised a question and stalled on a human who had walked away. This table is the instruction.

| you hit | the rule | the command |
|---|---|---|
| the task you wanted is locked | claim says taken → claim the next task; the lock already chose for you | `bash ops/polaris claim` again |
| the integration lane is held | integration lane busy → wait; rc 3 with a queued: line means report queued and retry at the next wave boundary | `land` · `seal` take the lease for you |
| the shared checkout is dirty | a dirty shared checkout is parked, never asked about: bash ops/polaris park | `bash ops/polaris unpark` puts it back |
| a lock, lease or task that is not yours | another session's locks, leases and tasks are invisible — never steal unless sweep flags them STALE | `bash ops/polaris sweep` names stale locks |
| a worktree that is not yours | a worktree is removed only by wt_remove, only when idle — never by hand; sweep --fix reaps idle ones | `bash ops/polaris sweep` shows beat age |

Exit codes carry the same answer, so a subagent or a script reads it without prose:

| rc | means | the tell |
|---|---|---|
| 0 | success — including the idempotent skips a second chat causes | `already landed — skipped` · `nothing new to seal` |
| 1 | refusal or error, worded honestly (real stderr, never swallowed) | fix what it names, or hand the task back |
| 3 | queued — the lane stayed busy past the bounded wait | LAST line begins `queued: ` and names the holder |

**rc 3 belongs to whoever can afford to wait.** A CONDUCTOR polls a queued lane at its next wave
boundary, never mid-task. A subagent does the opposite: it repeats the `queued:` line verbatim in its
report and ends its turn, because waiting on someone else's lease spends its own context and buys
nothing. (Ending a turn with your OWN suite still running is the opposite mistake, and it loses the
suite — foreground it, or poll its log.) Two optional `ops/CONVENTIONS.md` knobs tune the wait:
`integration_wait_minutes` (10) before rc 3 · `integration_stale_minutes` (45), past which an
abandoned lease is stolen with a note.

**The lease passes to the holder's own helpers** (`POLARIS_INT_TOKEN`). Taking the lease records a
token and hands it down, so a child process of the holder — the `land`, `seal` and `done` a
self-landing tail runs — steps back in without waiting; any other session has no token and queues as
above. Only the frame that took the lease lets it go, and the lease stays outermost: take it before
the board mutex, never while holding it.

**Plan and build as if you were alone.** Disjoint ownership is still the Planner's guarantee — but a
second planner can file a task between your board read and your claim, and the claim-time
disjointness gate is the backstop that blocks the loser rather than letting two chats edit one file.

## SAVE HOPS — fewest lookups, ask first, then finish
A hop is one lookup — a file opened, a search run — and each costs tokens and minutes. A Builder
starts with `bash ops/polaris pack <ID>`: one call, whose FOLDER GUIDES section already holds the
nearest guide for each owned folder; then rung 4. Everyone else stops at the first rung that answers:
1. **The root map** — `## Where things live`, ≤ 15 lines just below the POLARIS block of the repo's
   own `CLAUDE.md`: in context already, zero hops (`where --write` projects it from `ops/MAP.md` and
   the guides — edit those, never the map).
2. **`.polaris/brain/INDEX.md`** — any fact in ≤ 4 hops. No brain yet → `ops/MAP.md`.
3. **The folder's guide**, `<dir>/CLAUDE.md` — what the folder is for, what to read first, what to
   leave alone.
4. **`polaris find <symbol>`** → `path:line` · **`polaris show <path>#<symbol>`** → just that body.
5. **Grep, last** — for text nothing above can match.

**A layout that makes you jump is a bug.** `polaris hops` measures it (folders touched per change,
busy folders with no guide; no LLM, never edits) and the tidy lane fixes it: `bash ops/polaris role TIDY`,
one context, no subagents, ONE task. No drive-by moves in any other task.
- **When.** `next` prints `tidy` where a run would `finish`; `triage` prints it on an empty, quiet
  board; an explicit `update` ends with `▶ NEXT — save hops: …` and `update --auto` adds
  `· layout pass due — …` to its line. All three only read `.polaris/hops-due` (written by
  `hops --due`; `done`, `seal` and `heal` refresh it). At most once per session, never within 30
  changes of the last pass, and `hops: off` in `ops/CONVENTIONS.md` turns it off everywhere.
  The tune-up (`bash ops/polaris tune`, which TIDY runs first) rides the same lane: it runs whenever
  its verdict (`.polaris/tune-due`) is due and nothing is building or waiting to land — cards
  waiting in `ready/` or `backlog/` included, their files held so the pass never moves them.
- **May:** moves `hops --proof` shows changed nothing but paths (≤ 25 files, every step proven and
  checked green) · guides (≤ 8) · the root map · `ops/LAYOUT.tsv` rows. **Never:** a merge without
  the human's up-front yes (a merge deletes; a proven move does not) · a path `hops` holds FIXED
  (tooling, framework-routed, vendored, guarded, public API) · a logic change · a stop mid-run: what
  it cannot prove or decide becomes a `keep` row, and its report lists those.

**Ask first, then finish.** Here (`bash ops/polaris presence` says `here`: plan mode, or any mode
that is not hands-off): ask every question whose answer changes the plan, in rounds, until none is
left — the conductor's interview, plus the ≤ 3 `hops --questions` when the pass is due. Away
(`presence` says `away`: a plan was approved and the session runs in auto mode): never ask. Take the
recommended option and write it down as an `assumed:` line; park only what has no safe default (a
paid service, deleting data) and finish everything else; never stop for a busy lane, a taken task or
another chat's work; finish through publishing. Nothing stops mid-run. A builder question
default-safe cannot answer → the question into the task's Notes, `release <ID> --to blocked -m
"<question>"`, `notify-gate question <ID>`; the other lanes keep going. Away, a `risk: high` task of
the approved plan merges on the plan's yes: its handoff prints an `away:` line and the close names it
(Invariant 9). `risk: high` the plan did not cover → `notify-gate risk <ID>`; it stays in `review/`
and the close names it. `finish` names each blocked task and why; with only human-gated work left,
close on `⛔ waiting on you: approve <ID>` — no 🎉 (away, `finish: parked` prints those lines itself,
§ AWAY RUNS). Every close says how long the run took and where
the time went (`bash ops/polaris speed`), and names each task an `away:` line reported; a
pull-request project's close ends with its one link, and nothing follows it. `autonomy: standard`
asks right away at both gates, as before. Here, no hard gate gets softer.

**What loads by itself is measured, not assumed.** The 6.13.0 probe (2026-11-07) answered `unknown`
for all seven cases — a guide on Read, Edit, a new file, a subagent, a worktree path or a Bash `cat`;
a worktree's own `CLAUDE.md` — as no session could sign in, and only a measured `yes` counts: open
a guide when the ladder gets there. `pack` prints a builder's guides; the root map is in `CLAUDE.md`.

## TOKEN DISCIPLINE — this is how we stay cheap and fast
The lookup ladder lives in § SAVE HOPS.

> **THE MISSION, and it outranks thoroughness.** Every token is the owner's money and the supply is
> fixed. Finish the task, prove it, spend as little as possible. Prefer ONE context over three —
> twenty-five subagents in a day is a failure, not diligence. Run the smallest check that proves the
> change; never the full suite for a small diff. Ask early rather than burning tokens guessing.
> **The measure of a good run is the result divided by what it cost.**
>
> This is not an aspiration. On 2026-09-15 a single day's work took a weekly model limit to 87% and
> the main limit to 53%, on one project, in one chat — because routing sent a dozen agents to the
> most expensive model available and nobody checked. Routing now never picks Fable or Haiku
> (`core.sh model_denied`, § MODEL ROUTING); the habits below are the other half of the same lesson.

- **Long, mechanical, no judgement in it?** Run it yourself, detached: one command per line in a file, then
  `bash ops/polaris bg run <name> --steps <file>` and collect once. 🚩 only what needs a person, only while they are here.
  Away, the plan named it before approval or it parks (`defer`, § AWAY RUNS); what needs a person is
  listed exhaustively in `PLANNER.md` § Needs you before I start.

- **`pack` first, everything else second.** Working a task? `ops/polaris pack <ID>` returns its
  contract, house style, owned-directory map, public API surface and gotchas in ONE call. Reading
  those seven things by hand costs 6-15 round trips and lands you in the same place. The brain and
  `find` below are what `pack` is built out of — reach for them directly only when you have no task.
- **Read the brain first.** When it exists, read `.polaris/brain/INDEX.md` FIRST, repo second — a generated, gitignored, ≤4-hop knowledge base that digests the tracked MAP and kills cold-start re-derivation. No brain yet → `ops/MAP.md` is the fallback (next bullet).
- **Read the MAP, not the repo.** `ops/MAP.md` is the summary; `polaris status` is the board — never browse either raw.
- **`find` first, grep second.** `polaris find <symbol>` answers "where is X" in ONE hop — `path:line` + signature per hit, ranked exact→prefix→substring, from a generated index. `polaris show <path>#<symbol>` prints just that symbol's body instead of the file. Use them BEFORE Grep: the same answer costs a hunt of 6-15 grep/read round trips otherwise. Grep is the fallback for text `find` can't match (and `find -t <text>` covers most of that). NEVER read a large file end-to-end without a written reason.
- **A Builder's entire context** = `CLAUDE.md` + its role file + the task file + the contract + `files_owned` + listed `context_files`. Anything else needs a one-line justification in the task's Notes.
- **A skill `pack` names is read before the first edit.** `pack`'s SKILLS section lists the POLARIS-written skills whose paths overlap what you own; each is the distilled "what keeps going wrong here" for that surface, paid for once and reusable forever. One measured caveat, because it is not obvious: a skill's path-triggered twin loads when a matching file is **Read** (an Edit reads first, so editing counts) — a Write that CREATES a new file in that surface loads nothing at all. Building something new in a mapped area, open it yourself.
- **Summarize once, reuse.** Append findings to the task's Notes; never re-derive them.
- **One task, one session, then close.** A fresh session per task beats one long degraded chat.
- **Terse artifacts.** Frontmatter for machines, binary acceptance criteria, no essays. Reference `path:line`, never paste file bodies.
- **Spikes exist so five tasks don't each re-explore.** Time-boxed read, written verdict, done.
- **Prove it with a command, not a subagent.** Anything a shell command can check — a route responds, an export still exists, output still matches — belongs in the task's `verify:` list or in `ops/tests/` as a golden, written ONCE while the context is already in hand. `polaris check --scaffold` generates the mechanical half. A model re-checking by hand every wave is the single most expensive habit this protocol exists to kill.

## MODEL ROUTING (auto — polaris route decides)
- **Ask, never guess.** `ops/polaris route [<ID>] [--role <ROLE>] [--points <N>] [--risk <R>]` is the
  one oracle. Line 1 is always exactly one of `strong` · `mid` · `cheap` — bare, machine-parseable,
  parse it blind. Two notes follow it: `   model: <name>` then `   effort: <level>` — the model and
  the effort a spawn of that work should use. Read-only: no lock, no board write, no hook.
- **Sized by default** (owner, 2026-11-09): `cheap` → `sonnet` at `low` · `mid` → `opus` at `medium` ·
  `strong` → `opus` at `high`. The defaults live in the kit's code, so every project gets them on
  update with no config change. The effort note is never above the chat's own level when the
  machine guard has recorded it (`~/.claude/polaris/model-state/<session>.effort`).
- **The derivation**, which `route` runs whenever nothing overrides it: `risk:` ≠ `normal` → `strong`
  (risk dominates points) · points ≥5 → `strong` · points ≤1 → `cheap` · everything else → `mid`.
  Missing or non-numeric points → `mid`, the safe middle. Routing NEVER blocks work — an unknown role
  falls back to `mid` with a note and rc 0; only no-args and an unknown ID are errors.
- **Roles come from a table, tasks are derived.** INIT · PLANNER · INTEGRATOR · EVOLVE · CONDUCTOR →
  `strong`, because their mistakes multiply · SOLO and the qa scout → `mid` · BUILDER → whatever its
  task derives, so ask `route <ID>`, never `route --role BUILDER`.
- **A task may override.** Optional `model:` frontmatter: `strong`/`mid`/`cheap` names that tier; any
  other value is a LITERAL model name, echoed verbatim in the model note with the derived tier still
  on line 1 for information.
- **A project may override** — `model_strong:` / `model_mid:` / `model_cheap:` and `effort_strong:` /
  `effort_mid:` / `effort_cheap:` in `ops/CONVENTIONS.md`. Unset → the default above. The value
  `inherit` drops that note, so the spawn uses the chat's own model or effort. A task's literal
  `model:` still wins for the model note.
- **Fable and Haiku: routing never picks them, and only Haiku is blocked.** `route` never names
  either, whatever a knob or a task's `model:` says (`core.sh model_denied`, a kit constant no repo
  can switch off); a forbidden name drops the model note and prints a REFUSED note instead. A Fable
  session is the owner's choice: they pick it with `/model`, and the machine's session guard lets it
  run. A Haiku session, switch or spawn is refused there.
- **Consumers, so nobody re-derives it:** the CONDUCTOR runs `route` before EVERY spawn and passes
  the two notes as the spawn's `model` and `effort` (a missing note → leave that setting out, and the
  spawn uses the chat's own) · `fleet` injects `--model <name>` at the MAX tier over ready tasks, because panes claim
  racily and any pane may end up holding any task · `pack` prints `· tier <t>` in its header line.
- **The honest boundary.** A RUNNING session cannot switch its own model. Routing governs what gets
  SPAWNED (subagents) and LAUNCHED (panes); for the session already reading this, `triage` and
  `status` merely hint — acting on the hint means starting the next session at the right tier, not
  re-rolling this one.
- Phrase is tier-relative on purpose: models change, the routing rule doesn't.

## LONG COMMANDS — living under the 600s tool cap
A foreground tool call is capped at 600s (600000ms). Past its timeout the harness moves the call to the
background (a subagent's at about 180 s) and its output comes back only as a completion notification —
which wakes a top-level session, never a subagent whose turn has ended. So a long command starts
detached from the outset and its rc file is the truth. MEASURED on this repo, so nobody re-measures:

| command | measured | under the cap? |
|---|---|---|
| `doctor --fast` — the in-process tier, and this repo's `test_fast:` | 3s tier / 6s wall | yes |
| `doctor --selftest` spine only | 144s | yes |
| `doctor --selftest --parallel 3` — 34 drills, sharded; this repo's `test:` | 169-378s quiet · 729s busy | only on a quiet box |
| the full selftest, SERIAL — CI's tier now, not a local gate | 805s | **no** |
| `ops/polaris qa` — the whole loop | 1225s | **no** |

`qa` does not always pay for the row above it — `depth_for` (`ops/contracts/test-depth.md`) picks
how much of the suite a change actually needs, once per `qa` or `land --express`:

| depth | runs | when it applies |
|---|---|---|
| `none` | no suite key at all | every changed path is `test_skip` (docs, `.md`, `LICENSE*`) |
| `look` | no suite key, but the before/after capture still runs | every changed path is `test_look` (css/svg/images) |
| `ui` | `lint` + `typecheck` side by side and the before/after look; no `test`, `build` or `uat` | a `risk: normal` task of 1-2 points (or `test_depth: ui`) whose every remaining path is `test_ui` (components and pages), and only when `lint:` or `typecheck:` is set, or both `visual:` and `shot:` |
| `scoped` | only the related tests: the `test:` subset `SURFACES.tsv` maps to the change, or the runner's own related tests (vitest/jest) when the package has one installed; the live `uat` tier is deferred (uat deferred: it runs on full-depth changes, CI and release) | every non-look path is mapped or has related tests |
| `full` | the whole `test:` suite, unchanged | anything unmapped with no related tests, or `test_depth: full` |

`risk: high` does not force `full` — it gates the merge, not the depth. An edited test file
(`*.test.*`, `*.spec.*`, or under a `SURFACES.tsv` tests glob) is never `none`, `look` or `ui`: it
runs, narrowed when `test_select:` can, never escalating a small change to the whole suite on its own.
`test_skip`, `test_look` and `test_ui` set to `+ <globs>` extend the default instead of replacing it.
CI and `pack.py --dogfood` always run `full`, serially, and never read the stamp.

Three bands, and the band is a property of the MEASURED time, not of how important the command feels:
1. **Under ~60s** — plain foreground call. No ceremony.
2. **60s to the cap** — foreground WITH an explicit tool timeout ≥ the measured time (600000ms for
   anything near the top of the range). A defaulted timeout is how suites die at 120s.
3. **Past ~300s, or past the cap** — `ops/polaris bg run <key>` (a bare CONVENTIONS suite key: `test` ·
   `test_fast` · `lint` · `typecheck` · `build` · `uat` · `qa`, or `<name> -- <cmd…>`), then wait the
   way the table below names for where you are. `bg tail` reads the log without waiting.

**Which wait, when** — the cheapest path first (a detached job and ONE wake-up costs about a seventh
of polling it; the Haiku runner sits between):

| situation | path |
|---|---|
| any job measured or expected < 300 s | foreground with an explicit timeout ≥ the measured time |
| top-level session, ≥ 300 s | `bg run <name> -- <cmd>` · ONE `bg wait <name> --done` with `run_in_background: true` · end the turn; the harness wakes it once; the rc file is the truth |
| top-level, ≥ 300 s, no background wake-up in this harness, `runner:` not `off` | spawn the runner (`route --role RUNNER` prints `agent: polaris-runner`) with the job name |
| builder subagent | collect in-turn with `bg wait <name> --max 240` while rc 2, or hand `running: <name>` up to the caller |
| CI | `bg run proof-await -- bash tools/proof.sh --await macos-latest`, one backgrounded wait |
| runner unavailable (Haiku refused or `runner: off`) | the chunked foreground `bg wait --max 540` |

`bg wait` exits 0 green · 1 red · 2 still running (wait again) · 3 unknown · 4 timed out — the job ran
past its budget and was killed, retried, killed again (§ AWAY RUNS). The runner only ever waits and
reads the tail; the caller starts the job and names the command.

- **SUBAGENT rule — never end a turn with a job still running.** Your existence ends with your turn,
  and completion notifications re-invoke only the TOP-LEVEL session, so a job you leave behind has
  nobody left to collect it and needs a conductor rescue (two of those last sprint). Poll INSIDE your
  turn: chunked `bg wait` until it returns a verdict, then report.
- **TOP-LEVEL rule** — the main session waits with ONE backgrounded `bg wait <name> --done`
  (`run_in_background: true`), because it is the one context a completion notification can wake.
- **Invariant 4 is absolute either way.** `bg wait` must return 0 for YOUR suites BEFORE
  `handoff` · `land` · `seal` · `finish`. Backgrounding moves the suite off the critical path; it
  never moves the gate. `finish` enforces this — any job with no verdict is a pending line.
- **Stamp the wave with it.** `bg run qa` always executes in the primary checkout and stamps
  `.polaris/suite-stamp` when green, so a green `qa` on a clean tree makes the later `finish` seconds
  instead of 1225s. Start it at the top of the wave gate and drain `review/` while it runs.
- Mechanics — registry layout, rc-file-first verdicts (a pid check alone NEVER declares one), one-slot
  rotation, the `finish` guard — are specified in `ops/contracts/bg-jobs.md`.

## AWAY RUNS — budgets, the pulse, parked
A plan approved into auto mode **arms** the run (`.polaris/run/<sid>.armed`, written by the
presence hook; `ops/contracts/walk-away.md` § 1). Everything in this section is inert until then:
unarmed, every command prints what it always did.
- **Budgets.** Every `bg run` job has one: `--budget <s>`, else 3 × its longest green run, else its
  class (lint/typecheck/build 900 s; suites 3 × the last full run). Past it the whole process tree is
  killed and the job retried once (`bg_retries`); past that `bg wait` exits 4 with the ⛔ line and the
  `defer` command to park it. `bg reap` does the same for a job whose watchdog died. Only budgets kill.
- **Long mechanical work** goes in a file, one command per line: `bg run <name> --steps <file>` runs
  them in order as ONE job under one budget and stops at the first red.
- **Before approval: `bash ops/polaris preflight <slug>`** checks the mechanical things that would
  need a person later (remote reachable, `gh auth status`, a `risk: high` card or `ask` scope the plan
  does not cover, the measured suite time). The full list is `PLANNER.md` § Needs you before I start.
- **Mid-run: `bash ops/polaris defer -m "why" -- <cmd…>`** parks a step that needs a person and the
  run keeps going; the close names it.
- **The pulse.** At approval the conductor arms a timer every `pulse_minutes` (default 30) that runs
  `bash ops/polaris pulse` — it says `ok` / `act` / `parked` / `done` off the board — and deletes the
  timer at `done` or `parked`. `pulse --reenter` resumes a stalled run from the board (`reentry_max`).
- **Stall lines.** A busy heavy slot or lease, armed, says `queued:` once and never waits on it; the
  Stop gate blocks an armed session that tries to stop with work left, and after three blocks writes
  `.polaris/run/stalled` and lets it go — the close names it.
- **The two endings.** `finish` exits 0 when the run is truly over (then `# 🎉 Complete!`), or prints
  `finish: parked - <n> waiting on you` and one `⛔ waiting on you: …` line per item, exit 1, when
  everything left needs a person. Armed, both end with
  `run: <total> - <checks> in checks, <queue> waiting, <n> timeouts`, and both disarm the run.

## AWAKE — one keep-awake daemon per machine
The box used to sleep mid-run. ONE daemon per MACHINE keeps it awake while any session is still
working and exits by itself once every session and repo is idle — never one per chat. It lives in
`~/.claude/polaris/awake/` (registry, daemon pid, beat, logs) and is driven by four machine-level
hooks merged into `~/.claude/settings.json` — `SessionStart` · `UserPromptSubmit` · `Stop` ·
`SessionEnd`; hook entries that are not ours are never touched.
`bash ops/polaris awake status|start|stop|disable|enable` is the whole face: `status` prints one
line, `start` arms it now, `stop` is 60 minutes off, `disable`/`enable` are the standing switch.
`finish` never stops it; the next prompt anywhere respawns it. Opt out with the `disabled` flag
(`awake disable`); `KEY=none` in the registry's `config` keeps only the invisible execution-state
half, so nothing is ever typed. A closed lid, the power button and a critical battery are out of
reach for any user-mode program — nothing here can help with those.

## VOICE — how you TALK to the human (`voice:` in `ops/CONVENTIONS.md`, default `standard`)
| `voice:` | How you speak |
|---|---|
| `standard` | Warm, friendly, everyday English — the bar: someone who has never used git or run a test understands every sentence. No POLARIS jargon, and no trade words either — never "branch", "merge", "suite", "green", "CI", "worktree", "seal", "commit". Don't explain a technical word — drop it and say the outcome instead: merged → "saved into the main copy" · suite green → "every check passed" · branch → "a separate working copy" · parked/blocked → "set aside", plus why. Commands you tell them to run stay verbatim. Lead with what happened and what it means for them; leave out detail they didn't ask for. |
| `technical` | Dense, terse, expert-to-expert. Jargon is fine; assume they wrote this kit. |

**OUTPUT DISCIPLINE — applies under BOTH voices, always.** Adapted from the `i-have-adhd` skill
(github.com/ayghri/i-have-adhd, MIT), which ships with this kit at `.claude/skills/i-have-adhd/` and
can also be invoked directly. The main conversation now gets these natively from
`.claude/output-styles/polaris.md`, which the installer selects; **this copy is the one that reaches
the role files and every subagent**, where an output style never applies. These are not a style
preference; a preamble you did not need is a paragraph the human reads and pays for, and every one
of these rules is strictly less output:

1. **Lead with the action**, not the context. Answer first, explain only if asked.
2. **Number multi-step work; cap every list at 5.** More than five is a dump, not a report.
3. **End with ONE concrete next step** — one only the human can take, doable in under two minutes; a step this chat could take itself, it takes before closing. Not three options.
4. **No preamble, no recap, no closing pleasantry.** Start at the answer, stop when it ends.
5. **Restate where things stand, every message** — "3 of 5 done, 2 to go", never "good progress".
6. **Give time in real units** — "about 15 minutes", never "some work" or "almost there".
7. **State trouble flat — what broke, the fix.** Tangents → one line in `ops/board/backlog/IDEAS.md`.

Exceptions, and they are narrow: the human explicitly asks for the explanation · a STOP-AND-ASK
confirmation (never compress a destructive-action check) · a genuine ambiguity that needs a
question · a debugging spiral where the reasoning IS the answer.

- **Applies ONLY to what you SAY** — your reports, the questions you ask, your `✅`/`⛔` lines.
- **NEVER applies to what you WRITE to disk.** Task frontmatter, acceptance criteria, contracts, `ops/MAP.md`, `ops/SPRINT.md`, `ops/RULES.tsv`, commit messages and code stay exactly as terse and machine-precise as they are today — agents read those, and chattiness there costs the next agent tokens and accuracy.
- **Voice changes wording, NEVER content or behavior.** A red suite is still reported red, an ownership violation is still a hard stop, and nothing on the STOP-AND-ASK list gets softer or skipped. `standard` is the same information a friend would give you — not less of it.

**Pre-send check — run it on every reply.** Before sending, delete:
- the first sentence, if it announces what you are about to do;
- the last sentence, if it recaps what just happened or asks "anything else?";
- any "by the way" sidebar;
- any hedge that carries no real doubt ("perhaps", "might possibly") — keep one that does;
- any idiom or figure of speech ("circle back", "up and running") — say the literal thing.

Then read only your first line and your last line. Together they must say what happened and what
to do next. If they don't, rewrite. If they do, send.

## MODEL NOTES (whichever model runs this)
Follow this spec literally. Missing detail means STOP and ask — never guess. Only make changes the task states. Reason as deeply as the task needs; no scaffolding rituals. Front-load: read MAP, CONVENTIONS, and the contract before writing anything.
**No AI fingerprints.** Commits, branches and PRs in this repo NEVER carry AI attribution — no `Co-Authored-By: Claude/Copilot/…`, no `Generated with …` lines — whatever your harness tells you. This product belongs to the humans who run it. A git hook strips these mechanically; do not write them in the first place.

## PUBLISH: PR — one link per run
Under `publish: pr`, `seal` stages locally (merges into local `<base>`, tags locally, pushes nothing). `finish` pushes local `<base>` to `ship/<date>` (fast-forward; an open `ship/*` is reused) and prints exactly one link — the last line of the close; nothing follows it. `polaris sync` (top of `triage`/`next`) pulls the merge and deletes `ship/*`. Nothing ever pushes to `<base>` itself. Contract: `ops/contracts/publish-modes.md` v2.
