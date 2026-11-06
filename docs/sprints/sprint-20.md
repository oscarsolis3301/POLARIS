# Sprint 20 — Save hops (6.12.0) (2026-11-05–)

## T-233 — "Probe first: does a folder's own CLAUDE.md ever reach a session, and when?"
points 1 · risk normal · landed c376584 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: plans/save-hops.md

### Why
The save-hops plan puts short guide files (CLAUDE.md) inside folders so an agent learns a folder before it edits there. Nobody has measured whether those files actually reach an agent: Claude Code loads them when a file is read, but builders start from a shell command, often as subagents working in a worktree. This spike measures it with seven tiny headless sessions in a throwaway repo, exactly as the T-150 probe did for skills, and writes the answers down. Nothing else waits on the result, because pack will print the guides either way; the answers only decide what CLAUDE.md and PROTOCOL claim (T-244).

### Acceptance
- [ ] the throwaway repo, its worktree and the seven sessions follow ops/contracts/save-hops.md § 9 exactly
- [ ] the seven probe: lines sit under a new ## Measurements heading at the END of plans/save-hops.md, values taken only from what a session echoed
- [ ] the harness version, the date and the seven raw replies are pasted under the lines
- [ ] a refused or hung session is recorded as unknown, never guessed
- [ ] if worktree-root-claudemd-reloads is yes, the handoff report says so in one line for an IDEAS entry
- [ ] nothing outside plans/save-hops.md changed (the contract cites these lines; never edit it)

## T-234 — "The import finder learns aliases, src/ layouts and path mentions, and prints plain line endings"
points 5 · risk normal · landed 550dece (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/index.py, ops/tests/api-kit.expected, ops/tests/index-selfcheck.expected

### Why
find --importers is how a Planner proves two tasks cannot collide and how the coming layout pass knows which files a move touches, and today it misses most real imports. It cannot see TypeScript and JavaScript path aliases like @/components/Cart, Python packages kept under src/, or paths written in configs, Dockerfiles, CI files and docs. This task teaches the resolver the aliases from tsconfig.json and jsconfig.json, the src/ root and package __init__.py files, and adds path mentions in non-code files as their own kind of hit. It also makes index.py print plain LF line endings on Windows, so every new golden can compare its output byte for byte. It is also this wave's owner of the api-kit golden: it records its own new index.py rows and the four rows its sibling tasks add.

### Acceptance
- [ ] resolve_import takes aliases=None and pyroots=None and every existing selfcheck case passes unchanged (§ 1.1)
- [ ] tsconfig/jsconfig paths and a bare baseUrl resolve, comments and trailing commas tolerated, extends documented as not followed
- [ ] a dotted python import resolves through src/ and through package __init__.py files
- [ ] find --importers prints mention lines after the import edges; with no mention the output is byte-identical to today
- [ ] selfcheck gains at least 4 resolve cases and 2 mention cases (one proving components/CartItem does not match components/Cart), and the golden is re-pinned to the new summary line
- [ ] index.py output has no carriage returns on Windows (stdout, stderr and every file it writes)
- [ ] api-kit.expected holds this task's index.py rows plus the four W1 sibling rows of § 0.9, sorted; the strict whole-file diff is the wave gate's job, not this task's

## T-235 — "A scripted practice shop: the fixture repo the layout drill, the benchmark and the end-to-end check share"
points 3 · risk normal · landed 34c8d34 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/lib/selftest/hops.sh

### Why
Every later piece of the layout work needs the same realistic repo to prove itself on: a small app sorted by file type (components, hooks, services, utils) whose features are scattered across those folders, with about 120 commits of history, @/ import aliases and a test command that fails when an import breaks. This task writes ONE function, hops_fixture, that builds that repo from scratch, deterministically, in under 30 seconds. The layout drill (T-252), the hop benchmark (T-247) and the conductor's end-to-end run all call it, so they all measure the same thing. It also plants bait the layout pass must never touch (a Unity Resources asset, a published package, files guarded by RULES, SURFACES and a keep row, a Java file).

### Acceptance
- [ ] hops_fixture is the ONLY function in kit/ops/lib/selftest/hops.sh (no helper functions, not even nested ones; the file is a module: definitions plus a short header, nothing runs when sourced)
- [ ] the repo matches § 8.2 of the contract: files, the five benchmark facts by exact name, the FIXED bait, the ops/ state files, at least 100 commits and 40 tracked files
- [ ] two builds give the same HEAD commit id (fixed author, committer and dates) — checked once by hand, noted in Notes
- [ ] tests/run.sh passes on the fresh fixture and fails, naming the import, when one @/ import target is renamed (checked once by hand)
- [ ] bash 3.2 safe: no mapfile, no associative arrays, no case inside $(...), split local declarations
- [ ] the file is NOT added to the loader list in kit/ops/polaris (T-252 does that with the drill)

## T-236 — "next says tidy once when the layout pass is due, and a task waiting only on a human no longer holds the run open"
points 5 · risk normal · landed 2d1a440 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/hooks/handover-hook.sh, kit/ops/lib/handover.sh, kit/ops/lib/selftest/board.sh, ops/tests/handover-route.cmd, ops/tests/handover-route.expected, ops/tests/handover-stop.cmd, ops/tests/handover-stop.expected, ops/tests/plan-approval-gates.expected

### Why
The owner wants the layout pass to run at the end of a run, without being asked, and never wants a run to stop in the middle to wait for them. Two changes in the router that decides what a session does next make both true. First, when the board is done and the saved verdict says the layout pass is due, next prints tidy (once per session) before it would print finish, and the Stop hook turns that into the instruction to run the TIDY role. Second, a task that only a human can merge no longer makes next print wait forever: it prints finish, so the run closes and names what waits on the human. Both read only files on disk, so next stays inside the anchor hook's 10-second budget.

### Acceptance
- [ ] next prints tidy with the two pinned notes only when nothing else is left, review/ holds nothing human-gated, the cached verdict is due for the current base and this session has not been routed there yet; the marker is written in the same call (§ 0.5, § 0.6, § 2.1)
- [ ] a second next in the same session prints finish
- [ ] human-gated review work alone prints finish with the existing risk: high awaiting approval note (role-handover.md v3)
- [ ] next --brief maps tidy to ops/roles/TIDY.md
- [ ] the Stop hook blocks on tidy with the pinned reason, counts it as a free hop, and lets a pending question through like finish (§ 2.2)
- [ ] handover-route, handover-stop and the handover drill's case (14) are re-pinned to the new behavior; run-caps-plan and stop-question are unchanged
- [ ] no new function anywhere (all three files are surface-frozen)

## T-237 — "triage offers the layout pass on an empty board, finish says why each parked task is parked, and the hops switch is registered"
points 3 · risk normal · landed dd2ca78 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/KEYS.tsv, kit/ops/lib/observe.sh, ops/tests/finish-blocked.cmd, ops/tests/finish-blocked.expected, ops/tests/triage-lane.cmd, ops/tests/triage-lane.expected

### Why
Two small gaps around the edges of a run. When someone says start and the board is empty, triage can only say full today; if the saved verdict says the layout pass is due and nothing else is happening, it should name the tidy lane instead, so a bare start does the useful thing. And at the very end, finish already lists blocked task IDs, but not why each one is blocked, so the closing message cannot tell the owner what each one needs; it should read each task's last blocked event and print a one-line reason beside it. The task also adds the hops: switch to the key registry, so doctor and adopt know it exists (it defaults to on in code, and update never writes it).

### Acceptance
- [ ] bare triage on an empty, quiet board with a due verdict prints tidy with the two pinned notes and writes the session marker (§ 2.3); otherwise its output is byte-identical to today
- [ ] triage with IDs named never prints tidy
- [ ] the finish caveat names each blocked task with its reason from its newest blocked event, cut at 80 characters, or no reason recorded (§ 2.4); it is still never a gate
- [ ] KEYS.tsv ends with the pinned hops row; keys-drift stays green (it uses a fake registry)
- [ ] triage-lane is re-pinned with the tidy cases and its line-1 pattern knows tidy; the new finish-blocked golden pins the caveat
- [ ] observe.sh gains no function (inline code only); KEYS.tsv gains exactly the one row

## T-238 — "heal builds the knowledge base when it is missing, refreshes the layout verdict, and gives new installs a shorter efficiency note"
points 3 · risk normal · landed b1eaa4a (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/lib/admin.sh, ops/tests/heal-design.cmd, ops/tests/heal-design.expected

### Why
Every role file tells an agent to read the generated knowledge base (.polaris/brain/) first, yet nothing ever builds it, so most repos never have one and the shortcut chain starts with a missing step. heal already runs on every update and every reinstall, so it is the one place that reaches every installed repo: when the brain is missing, heal now builds it once, quietly, with a single note. heal also refreshes the saved layout verdict, which is how an update learns whether the layout pass is due. Last, the efficiency section heal appends to a repo's own CLAUDE.md (once, for repos that never had it) gets shorter and points at the new FEWEST HOPS section instead of repeating it; existing sections are never touched.

### Acceptance
- [ ] with ops/CONVENTIONS.md present and no .polaris/brain/, heal builds it and prints exactly the pinned note once; a second heal prints nothing about it (§ 3.1)
- [ ] heal then runs the exact verdict-refresh call of § 0.5, which never fails heal
- [ ] a failed brain build is silent and heal still returns 0
- [ ] the appended efficiency text for a repo that never had it is the § 3.1 block, byte-exact; a CLAUDE.md that already has the marker is untouched
- [ ] heal-design is extended with the brain cases (brain: yes, second run silent) and stays green for its existing cases
- [ ] admin.sh gains no function (inline code only)

## T-239 — "polaris where: a short root map in CLAUDE.md, built from MAP.md and the folder guides"
points 3 · risk normal · landed 4a1e569 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/lib/knowledge.sh, kit/ops/polaris, ops/tests/where-map.cmd, ops/tests/where-map.expected

### Why
An agent that starts in a repo should know where things live before it searches for anything, and the cheapest place to say that is the repo's own CLAUDE.md, which every session already has in context. This task adds polaris where, which builds a map of at most 15 lines from what MAP.md already records (entry points, modules, new modules from the Deltas) plus each folder guide's one-line purpose, and writes it between markers just below the POLARIS block. It is a projection, never a second source: edit MAP.md or a guide and the map follows. The brain's code map learns the same trick, taking a folder's purpose from its guide before its README. The task also owns this wave's edits to the CLI entry: the where dispatch and the help lines that mention where, tidy and heal's new duties.

### Acceptance
- [ ] where prints the block of § 0.2; --write places it right below <!-- POLARIS:END --> the first time and replaces it in place after; an unchanged map is reported as unchanged and the file is not rewritten
- [ ] --write never touches a byte outside the markers; no CLAUDE.md means rc 1 with the pinned note
- [ ] --strip removes the block, its markers and one blank line above it; absent means silent rc 0
- [ ] items come from Entry points, Modules, Deltas path lines, then guided folders; at most 13 items, the overflow line otherwise
- [ ] guide_purpose prints a guide's purpose line (rc 1 without a guide) and brain_code_map uses it before the README heading
- [ ] the entry gains the where dispatch and exactly the help edits of § 3.4, stays under 500 lines, and adds no function
- [ ] the new where-map golden covers preview, first write, idempotent second write, strip, the Deltas and guide rows and the code map purpose

## T-240 — "pack hands a builder the folder guide for every folder it owns, and builds the knowledge base once if it is missing"
points 3 · risk normal · landed cfd9463 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/lib/builder.sh, ops/tests/pack-guides.cmd, ops/tests/pack-guides.expected

### Why
Builders start with one command, pack, which prints their whole context, and never open a folder's guide on their own: Claude Code loads a folder's CLAUDE.md only when a file there is read, which a builder that creates files may never do, and other agents never load it at all. So pack itself must carry the guides. This task adds a FOLDER GUIDES section that prints the nearest guide for each folder the task owns (at most three, 25 lines each), and leaves the section out entirely when there are none, so every pack without guides stays byte-identical. pack also builds the knowledge base once when it is missing, instead of telling the builder to run another command.

### Acceptance
- [ ] the FOLDER GUIDES section sits right after WHERE THIS LIVES, prints a # <dir>/CLAUDE.md line then the block body for each guide found by the § 3.2 walk, de-duplicated, at most 3, at most 25 lines each
- [ ] no guide means no section at all; pack-visual stays green and byte-identical
- [ ] a missing .polaris/brain/ is built once, quietly, before HOUSE STYLE; if the build fails, the old no-brain line prints
- [ ] the new pack-guides golden covers: a guide two folders up is found, a guide-less task has no section, the brain exists after the first pack
- [ ] builder.sh gains no function (inline, the SKILLS/SURFACES pattern)

## T-241 — "polaris hops: measure how many folders one change touches and propose where scattered features should live"
points 5 · risk normal · landed f8e197f (2026-11-05) · claimed 2026-11-05
files touched: kit/ops/index.py, kit/ops/lib/search.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/cli-help-parity.cmd, ops/tests/cli-help-parity.expected, ops/tests/hops-map.cmd, ops/tests/hops-map.expected

### Why
This is the measuring half of the layout work, and it lives inside index.py because that file already ships to every installed repo (a new file would not). hops reads the last 300 changes and the import graph and answers one question: how many folders does a typical change touch? Then it finds clusters of files that always change together but live in three or more folders (a feature scattered across components/, hooks/ and utils/), suggests one home folder for each, and lists them as MOVE rows a later pass can act on. It never proposes moving anything FIXED: framework-routed folders, POLARIS's own files, vendored code, paths guarded by RULES, SURFACES or a keep row, Unity's special folders, or anything someone has unmerged work on. It also reports each folder's size and guide, folders that need a guide, and guides that cite missing paths. It is read-only, uses no LLM, and is this wave's owner of the api-kit golden.

### Acceptance
- [ ] hops runs on the fast path beside find and show (kit/ops/polaris + search.sh), with the exact help lines of § 1.2; cli-help-parity counts 11
- [ ] signals, score, FIXED rules 1–8 and 10, clusters, homes, MOVE rows with the 30-file guardrail, MAP, GUIDES and STALE follow § 1.3–§ 1.5
- [ ] the bare screen is at most 40 lines in the pinned layout; under 20 tracked files it is the single too-small line
- [ ] --tsv prints every row in the pinned kinds and order; --stale prints only STALE rows (rc 0 any, rc 1 none) without reading history
- [ ] flags of later tasks (--score --owned --proof --remap --due --facts --questions) exit 2 with a usage line, never a traceback
- [ ] the new hops-map golden: a small scripted fixture whose scatter is detected and whose FIXED, RULES, SURFACES and keep paths never appear in a MOVE row
- [ ] api-kit.expected holds this task's index.py rows plus the four W2 sibling rows of § 0.9; the entry and search.sh add no row

## T-242 — "update says when the layout pass is due, treats LAYOUT.tsv as the owner's, and uninstall takes the root map with it"
points 3 · risk normal · landed 4298ed6 (2026-11-05) · claimed 2026-11-05
files touched: kit/ops/lib/admin.sh, kit/ops/lib/selftest/fast.sh

### Why
The owner decided that a quiet automatic update only flags the layout pass, while an update someone typed offers it right away. heal (T-238) already refreshes the verdict during every update; this task makes update say it. A typed update ends with one ▶ NEXT line (run the pass now on a quiet board, or it runs when the next piece of work wraps up on a busy one), never a second ▶ NEXT, and the never-set-up INIT message still wins. The silent session-start update keeps its single line and gains a short suffix when the pass is due. ops/LAYOUT.tsv, the record of what the pass kept or moved, is the owner's file: update must never set it aside as kit dirt, and its untouched line names it. And uninstall removes the generated root map from CLAUDE.md, while folder guides stay, because they are plain Markdown that belongs to the repo.

### Acceptance
- [ ] update_hops_hint explicit|auto behaves exactly as § 5 (quiet line, busy line, suffix, rc 1 and silence when not due)
- [ ] a typed update prints the hint as its very last output, and never when the INIT epilogue printed
- [ ] the --auto success line is byte-identical when not due, and carries the suffix when due
- [ ] update_dirt_overlaps_kit treats ops/LAYOUT.tsv as state, and the untouched line names LAYOUT.tsv
- [ ] uninstall runs cmd_where --strip before removing the managed block
- [ ] fast.sh gains the LAYOUT dirt case and the six update_hops_hint cases (git stubbed as a shell function, temp dirs), and doctor --fast stays green
- [ ] admin.sh gains exactly one function, update_hops_hint; fast.sh gains none

## T-243 — "done keeps the root map fresh inside the one map commit it already makes, and done and seal refresh the layout verdict"
points 3 · risk normal · landed 72625a0 (2026-11-05) · claimed 2026-11-05
files touched: kit/ops/lib/integrate.sh, ops/tests/where-done.cmd, ops/tests/where-done.expected

### Why
The root map in CLAUDE.md is only useful while it matches MAP.md, and MAP.md changes when a task lands with a map_delta: done appends the delta and records it in exactly one docs(map) commit on the base branch. This task makes done refresh the root map at that same moment and put CLAUDE.md into that same commit, so the map never goes stale and the board still makes no new base commits. It refreshes only when the repo already has a root map, and never when CLAUDE.md has edits someone has not committed, because committing a person's unfinished work is never acceptable. done and seal also refresh the saved layout verdict after they finish, which is how next learns at the end of a run that the layout pass is due.

### Acceptance
- [ ] only when a map_delta was applied, a root CLAUDE.md that holds the where block and has no pending edits is refreshed with where --write and rides the SAME docs(map) commit (§ 4)
- [ ] a dirty CLAUDE.md is never refreshed and never committed; MAP.md still lands in its one commit
- [ ] a repo without a root map gets no CLAUDE.md change at all
- [ ] done (after its board commit and brain refresh) and seal (after its merge and tag) run the exact verdict call of § 0.5; neither can fail because of it
- [ ] the new where-done golden: a map_delta through done refreshes the map in ONE docs(map) commit carrying MAP.md and CLAUDE.md; dirty CLAUDE.md gives one commit with MAP.md only
- [ ] integrate.sh gains no function (inline code only)

## T-244 — "The principle, written where every agent reads it: FEWEST HOPS in CLAUDE.md and SAVE HOPS in the protocol"
points 3 · risk normal · landed cecbfa4 (2026-11-05) · claimed 2026-11-05
files touched: kit/CLAUDE.md, kit/ops/PROTOCOL.md

### Why
The owner wants "save hops, keep going to the end, spend few tokens" to be the core principle in every repo, new or old. kit/CLAUDE.md is the managed block every update writes into every repo and every session reads, so the principle goes there as one short section: builders start with pack; everyone else reads the root map that is already in their context, then the brain's index, then the folder's guide, then find and show, and only then Grep; a layout that makes you jump around is a bug that hops measures and the tidy lane fixes; and every question is asked before work starts, after which the run parks what needs the human and finishes. The same file's stop-and-ask list learns that a move proven by hops --proof is not a deletion, and its lane table learns the tidy lane. PROTOCOL.md gets the longer explanation in a SAVE HOPS section. What a folder guide loads by itself is stated only as far as the T-233 probe measured.

### Acceptance
- [ ] kit/CLAUDE.md: the FEWEST HOPS section (heading + at most 7 non-blank lines) sits between ROLE DISPATCH and THE ONE IDEA with the three bullets of § 7.3
- [ ] the STOP-AND-ASK line carries both pinned phrases and the lane table the tidy row; net growth at most 12 lines
- [ ] no line of kit/CLAUDE.md is a where or guide marker (installs would carry it inside the managed block)
- [ ] PROTOCOL.md: the SAVE HOPS section sits before TOKEN DISCIPLINE, has no heading lines in its body, covers every point of § 7.4, and TOKEN DISCIPLINE opens with the pinned pointer sentence
- [ ] every claim about what loads by itself matches the probe: lines under ## Measurements in plans/save-hops.md
- [ ] plain-voice stays green; the two files gain exactly the two pinned heading rows

## T-245 — "CONDUCTOR and SOLO ask everything first, park what needs the human, run the tidy lane, and close with what waits on you"
points 3 · risk normal · landed 8694426 (2026-11-05) · claimed 2026-11-05
files touched: kit/ops/roles/CONDUCTOR.md, kit/ops/roles/SOLO.md

### Why
The owner may walk away once a run starts, so a run must never stop in the middle to ask something. Today the conductor stops mid-run when a builder has a question or when a risk: high task wants approval. This task rewrites those two places: a builder's question goes into the task's notes, the task parks in blocked/ with a notification, and the other lanes keep going; a risk: high task the plan did not cover sends a notification and waits in review/ for the close, still never merging without the human's recorded yes. Questions instead go into the one round before work starts, including the layout pass's questions when it is due. Both roles learn the tidy lane (the conductor spawns one TIDY subagent when next says tidy; SOLO runs the pass itself), and both close with a plain "waiting on you: approve <ID>" when only human-gated work is left. Under autonomy: standard nothing changes: they still ask right away.

### Acceptance
- [ ] CONDUCTOR step 1 folds hops --questions into the same round when the pass is due, and carries the answers into the TIDY kickoff (§ 7.5)
- [ ] CONDUCTOR step 2.5 has the tidy branch with the pinned kickoff first line and the standing kickoff lines; step 7 spawns it when next says tidy
- [ ] steps 5 and 6 park instead of stopping under the default autonomy, and ask right away under autonomy: standard
- [ ] both roles close with ⛔ waiting on you: approve <ID> when finish names only human-gated work: no 🎉 and no looping
- [ ] SOLO step 7 follows tidy, and its STOP-AND-ASK line parks that piece and finishes the rest
- [ ] no heading line added or changed in either file

## T-246 — "Brand-new repos start tidy: INIT builds the brain and the root map, and the first plan keeps features in one folder"
points 2 · risk normal · landed c4bdf26 (2026-11-05) · claimed 2026-11-05
files touched: kit/ops/roles/INIT.md, kit/ops/roles/PLANNER.md

### Why
A repo that starts tidy never needs a big reorganizing pass later. When POLARIS is first set up in a repo, INIT writes MAP.md and the conventions but never builds the knowledge base or the root map, and nothing tells the first planner where new code should go. This task adds three small things. INIT runs polaris brain and polaris where --write once its files exist, and the MAP.md it writes carries a Layout line: new code lives with its feature (UI, logic and tests in one folder) unless the framework routes by folder. The planner applies the same rule when it splits work, and the task that creates a new folder also owns that folder's guide, made from the template; it is a new file, so it can never collide with another task.

### Acceptance
- [ ] INIT step 3 runs bash ops/polaris brain and then bash ops/polaris where --write after the artifacts are written (§ 7.6)
- [ ] INIT's MAP.md skeleton has ## Layout and the pinned sentence right after the Modules block, before Danger zones
- [ ] PLANNER step 3 carries the pinned layout sentence; step 5 says the folder-creating task owns <dir>/CLAUDE.md from ops/templates/FOLDER-CLAUDE.md and sets map_delta as today
- [ ] INIT.md gains exactly the one Layout heading row; PLANNER.md gains none (no new line starting with #, inside code fences included)

## T-247 — "The hop benchmark: five fixed lookups on the practice shop, counted in turns, before and after a layout pass"
points 2 · risk normal · landed 5e6e28f (2026-11-05) · claimed 2026-11-05
files touched: kit/ops/bench.sh

### Why
The plan promises a measured saving, not just a better score: the real test is whether an agent needs fewer turns to find things after the layout pass. This task adds a hops mode to bench.sh, the kit's benchmark script: it builds the practice shop from T-235 (or reuses a copy), asks five fixed questions such as "Where is the checkout cart total computed?" through headless claude -p runs, and prints how many turns each answer took plus the total. The conductor runs it once before and once after a tidy pass on a copy of the fixture (ten runs at most, because each spends real tokens) and the after total must be lower. A dry-run mode prints the questions and the exact commands without running anything, which is the only form a test may use.

### Acceptance
- [ ] bench.sh hops <dir> builds the fixture with hops_fixture when <dir> is missing, then runs the five pinned questions with the exact § 10 command, one run each
- [ ] each run prints q<n>, its num_turns and the first line of its answer (or - and error); then the total
- [ ] --dry-run prints the five questions and five command lines, builds nothing, runs nothing, exits 0
- [ ] bench.sh gains no function (inline in its dispatch) and existing modes behave as before

## T-254 — "Drills tidy up after themselves: notify puts the settings file back byte for byte, and park commits only its own file"
points 2 · risk normal · landed 1a24c7f (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/lib/selftest/policy.sh, kit/ops/lib/selftest/remote.sh

### Why
The wave gate (`bash kit/ops/polaris doctor --selftest --parallel 3`) is red on the park drill with
`PARK LAND RC FAIL`, but only when the notify drill ran earlier in the same shard. `--only park` is
green, `--only adopt,park` is green, `--only notify,park` is red. It is red on `main` (176d6b9)
too, so this sprint did not cause it; the shard split just happens to put notify before park.

What happens, step by step:

1. The notify drill overwrites the practice repo's settings file `ops/CONVENTIONS.md`, commits it
   with `git add -A` (`kit/ops/lib/selftest/remote.sh:171`), and at the end "puts it back" with
   `git checkout -q -- ops/CONVENTIONS.md` (`remote.sh:240`). That does not bring back the
   original: it brings back the copy notify itself committed. And on Windows the practice repo
   inherits `core.autocrlf=true`, so git writes that file out with Windows line endings (CRLF).
2. The park drill switches `core.autocrlf` off for its own run (`kit/ops/lib/selftest/policy.sh:802`).
   With it off, git compares bytes literally, sees the CRLF endings, and reports
   `ops/CONVENTIONS.md` as changed, although nobody meant to change it.
3. Park makes its practice commit with `git add -A` (`policy.sh:819`), which grabs every changed
   file, the settings file included, into `feat/T-PK`.
4. `land T-PK` checks that a branch only touches the files its task owns. `T-PK` owns only
   `src/pk.txt`, so the land is refused and the drill fails.

The fix is two small habits, one per drill:

- **park commits only its own file**: `git add src/pk.txt` in place of `git add -A` at `policy.sh:819`.
- **notify puts the settings file back byte for byte**: copy `ops/CONVENTIONS.md` aside before its
  first rewrite (remember when it did not exist), and at the end copy it back (or remove it), then
  commit that restore so `main` holds exactly what it held before the drill and the tree is clean.
  Both of notify's commits stage only `ops/CONVENTIONS.md`, never `git add -A`. `drill_busyint` in
  `kit/ops/lib/selftest/history.sh` already saves and restores this file; copy its shape.

Either change alone makes this failure go away. We want both, because the Hermeticity rule in
`ops/contracts/selftest-sharding.md` says every drill leaves the practice repo exactly as it found
it, so the order the drills run in can never matter. No change to the CLI itself: only the two
drill files move.

### Acceptance
- [ ] `bash kit/ops/polaris doctor --selftest --only notify,park` is green (red before the fix)
- [ ] `bash kit/ops/polaris doctor --selftest --only park` is still green
- [ ] drill_park's fixture commit stages only `src/pk.txt`
- [ ] after drill_notify, `ops/CONVENTIONS.md` is byte-identical to what it was before the drill,
- [ ] no file changes outside `kit/ops/lib/selftest/policy.sh` and `kit/ops/lib/selftest/remote.sh`
