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
points 5 · risk normal · landed f8e197f (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
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
points 3 · risk normal · landed 4298ed6 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
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
points 3 · risk normal · landed 72625a0 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
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
points 3 · risk normal · landed cecbfa4 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
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
points 3 · risk normal · landed 8694426 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
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
points 2 · risk normal · landed c4bdf26 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/roles/INIT.md, kit/ops/roles/PLANNER.md

### Why
A repo that starts tidy never needs a big reorganizing pass later. When POLARIS is first set up in a repo, INIT writes MAP.md and the conventions but never builds the knowledge base or the root map, and nothing tells the first planner where new code should go. This task adds three small things. INIT runs polaris brain and polaris where --write once its files exist, and the MAP.md it writes carries a Layout line: new code lives with its feature (UI, logic and tests in one folder) unless the framework routes by folder. The planner applies the same rule when it splits work, and the task that creates a new folder also owns that folder's guide, made from the template; it is a new file, so it can never collide with another task.

### Acceptance
- [ ] INIT step 3 runs bash ops/polaris brain and then bash ops/polaris where --write after the artifacts are written (§ 7.6)
- [ ] INIT's MAP.md skeleton has ## Layout and the pinned sentence right after the Modules block, before Danger zones
- [ ] PLANNER step 3 carries the pinned layout sentence; step 5 says the folder-creating task owns <dir>/CLAUDE.md from ops/templates/FOLDER-CLAUDE.md and sets map_delta as today
- [ ] INIT.md gains exactly the one Layout heading row; PLANNER.md gains none (no new line starting with #, inside code fences included)

## T-247 — "The hop benchmark: five fixed lookups on the practice shop, counted in turns, before and after a layout pass"
points 2 · risk normal · landed 5e6e28f (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/bench.sh

### Why
The plan promises a measured saving, not just a better score: the real test is whether an agent needs fewer turns to find things after the layout pass. This task adds a hops mode to bench.sh, the kit's benchmark script: it builds the practice shop from T-235 (or reuses a copy), asks five fixed questions such as "Where is the checkout cart total computed?" through headless claude -p runs, and prints how many turns each answer took plus the total. The conductor runs it once before and once after a tidy pass on a copy of the fixture (ten runs at most, because each spends real tokens) and the after total must be lower. A dry-run mode prints the questions and the exact commands without running anything, which is the only form a test may use.

### Acceptance
- [ ] bench.sh hops <dir> builds the fixture with hops_fixture when <dir> is missing, then runs the five pinned questions with the exact § 10 command, one run each
- [ ] each run prints q<n>, its num_turns and the first line of its answer (or - and error); then the total
- [ ] --dry-run prints the five questions and five command lines, builds nothing, runs nothing, exits 0
- [ ] bench.sh gains no function (inline in its dispatch) and existing modes behave as before

## T-248 — "hops proves a move changed nothing but paths: --score, --owned, --proof, --remap, and published code stays put"
points 5 · risk normal · landed 2b709d1 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/index.py, ops/tests/api-kit.expected, ops/tests/hops-moves.cmd, ops/tests/hops-moves.expected

### Why
"Guaranteed" here means failure is safe: a move that cannot be proven never ships. This task adds the four flags that turn a list of moves into something checkable. --score shows the before and after folders-per-change and, per feature, "change checkout: 4 folders → 1". --owned lists every file a pass must own: the moved files, everything that imports them (aliases included) and every config or doc that mentions their paths. --proof is the guarantee: it compares the working tree against the base and is green only if every changed line is an import or a path mention that now points at the moved file, with nothing deleted that was not moved; any real logic change is red. --remap renames moved modules inside the harness baseline, so a genuinely lost module still fails instead of being hidden by a blind refresh. The task also stops hops from ever proposing to move published code: a package's entry points, Python packages, Go and Java files, and Unity moves across an .asmdef. It owns the api-kit golden for this wave.

### Acceptance
- [ ] --score, --owned, --proof and --remap behave exactly as § 1.6, including the pinned output lines and exit codes
- [ ] --proof runs in the current directory's repository against the merge base, before a commit, and is red with one line per offence for a logic edit, an unplanned deletion or a missing destination
- [ ] a relative moves path resolves against the current directory first, then the primary (§ 0.3)
- [ ] FIXED rule 9 (published package closure, pyproject packages and scripts, .go/.java/.kt files, cross-.asmdef Unity moves) is enforced in every MOVE row
- [ ] the new hops-moves golden covers: a pure move proves green, a logic edit and a Java package-line change prove red, --score drops after the moves, --owned lists an @/ alias importer and a doc mention, --remap renames a baseline module, published paths are never proposed
- [ ] hops-map stays green; api-kit.expected holds this task's rows plus the W3 sibling rows of § 0.9

## T-249 — "A guide that points at a path that no longer exists gets noticed: drift says so, and handoff warns the task that removed it"
points 3 · risk normal · landed 475c047 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/lib/builder.sh, kit/ops/lib/observe.sh, kit/ops/lib/ownership.sh, ops/tests/guide-stale.cmd, ops/tests/guide-stale.expected

### Why
Folder guides hold stable knowledge, but they still name files ("to change prices, read pricing.ts first"), and a guide that points at a file that was moved or deleted sends the next agent hunting. Two cheap warnings catch it without ever blocking anyone. drift, which the planner reads first, prints an advisory line for every guide that cites a missing path. And when a task deletes a path that some guide it does not own still cites, handoff and verify print one warning telling it to own the guide and fix it, the same way they already warn about a missing map_delta. Both use hops --stale, so the rule for what counts as a citation lives in one place. They are advisories on purpose: a stale guide must never stop a run.

### Acceptance
- [ ] drift prints advisory: GUIDE STALE: <guide> cites <path> (missing) per stale citation; never counted, never red under --strict, qa or finish; silent without a python engine (§ 6)
- [ ] guide_stale_hint warns once per (guide, path) when the task deletes a path cited by a guide outside its files_owned, using hops --stale on the task's own tree; it never fails handoff or verify
- [ ] handoff calls it right after map_delta_hint, and verify calls it too
- [ ] the new guide-stale golden covers the drift advisory, the warning, and silence when the task owns the guide; drift-deps is unchanged
- [ ] ownership.sh gains exactly guide_stale_hint; observe.sh and builder.sh gain no function

## T-250 — "The TIDY role: one context that proves every move, writes the folder guides and lands one task — plus the guide template"
points 3 · risk normal · landed 3a121d7 (2026-11-05) · claimed 2026-11-05 → done 2026-11-05
files touched: kit/ops/roles/TIDY.md, kit/ops/templates/FOLDER-CLAUDE.md

### Why
This is the role that acts on what hops measures, and it is written so it can run to the end with nobody watching. It enters from four places (the end of a run, a bare start on an empty board, a conductor's subagent, a typed update), uses only answers gathered before work started, and turns everything it cannot decide into a keep row marked "unsure — left for you". Its pass: commit a pending update first, show the map, write the proposal (at most 25 moved files and 8 guides), pick a proving check (typecheck, build, test, or the generated harness; with none it writes guides only), author and claim one task whose files are exactly what hops --owned lists, move files five at a time with hops --proof and the check green before each commit, remap the harness baseline, write the guides from hops --facts, refresh the root map, run the suite once and land. The folder guide template ships beside it: at most 25 lines of plain Markdown, so a guide keeps helping any agent or person even after POLARIS is removed.

### Acceptance
- [ ] TIDY.md is at most 90 lines with exactly the four pinned headings and no other line starting with # (code fences included)
- [ ] the Entry and The pass sections carry every rule and command of § 7.1, in order; merges only with a recorded up-front yes, via approve --plan
- [ ] conductor-entered, TIDY returns its report and never runs next or finish
- [ ] the Report section asks for the before/after table, the per-feature "fewer lookups" lines and what was left for the human
- [ ] FOLDER-CLAUDE.md is at most 25 lines, starts and ends with the guide markers, has exactly the one pinned heading, plain Markdown, no POLARIS command
- [ ] the two files add exactly the five heading rows of § 0.9 (T-248 records them)

## T-251 — "hops knows when a pass is worth it: tiny-file merges, oversized files, the due verdict with its cooldown, guide facts and the up-front questions"
points 5 · risk normal · landed 3433317 (2026-11-05) · claimed 2026-11-05 → done 2026-11-06
files touched: kit/ops/index.py, ops/tests/api-kit.expected, ops/tests/hops-due.cmd, ops/tests/hops-due.expected, ops/tests/hops-map.cmd, ops/tests/hops-map.expected

### Why
A pass must be offered only when it pays, never loop, and stay silent on small or brand-new repos. This task adds the deciding half of hops. MERGE finds tiny files that always change together (merging one away needs the human's yes, so they only become questions), and SPLIT flags files and folders grown too big. --due gives the verdict: due when one pass would cut folders-per-change by 15% or more, or when three or more sizeable folders have no guide; silent with hops: off, under 20 tracked files, and within 30 changes of the last pass, so a pass whose moves were all reverted cannot fire again and again. Every run saves the verdict to .polaris/hops-due, which is the only thing next, triage and update read. --facts prints the 15 lines a folder guide is written from, so a pass never explores the repo to write one. --questions prints at most three pick-one questions for the run's single up-front round. It owns the api-kit golden for this wave.

### Acceptance
- [ ] MERGE and SPLIT rows, the screen sections and --tsv rows follow § 1.5 and § 1.7; hops-map is re-pinned if its fixture gains rows (and only then)
- [ ] --due follows the five ordered steps of § 1.7 (the self-hosting kit repo is never due), prints the pinned line when due and nothing otherwise, and always rewrites the cache in the § 0.5 format with LF
- [ ] --facts prints at most 15 lines in the pinned shape; --questions at most 3 lines in the pinned shape, rc 1 when nothing to ask
- [ ] the new hops-due golden covers: due and not-due exit codes, a keep row removing the saving, the 30-change cooldown, hops: off, the tiny-repo silence, the cache line, and a REAL next and triage in the fixture reading that cache (tidy once, then finish) after heal writes it
- [ ] hops-moves stays green; api-kit.expected holds this task's rows plus drill_hops for T-252

## T-252 — "The hops drill: the practice shop proves scatter is found, guarded paths never move, the score drops and the proof holds, in CI on three systems"
points 5 · risk normal · landed 2a4ff35 (2026-11-05) · claimed 2026-11-05 → done 2026-11-06
files touched: kit/ops/lib/selftest/hops.sh, kit/ops/lib/selftest/spine.sh, kit/ops/polaris

### Why
Goldens prove each piece on this machine, but CI runs only the selftest drills, on Linux, macOS and Windows. This drill is the one place the whole engine is proven on the realistic practice shop from T-235, on every push. It builds the fixture and checks the things that must never regress: the scattered checkout feature is found with a home under src/, nothing guarded (Unity Resources, the published package, RULES, SURFACES and keep paths, Java) ever appears in a MOVE row, applying the proposed moves lowers the score, and --proof passes a real move with its import fixes while failing a logic edit and a Java package-line change. It is registered last, so every existing --only selection keeps its meaning.

### Acceptance
- [ ] label hops is appended LAST to SELFTEST_LABELS and its gate runs last; the loader list gains selftest/hops right after selftest/fast (§ 8.3)
- [ ] drill_hops builds the fixture in its own throwaway dir and asserts exit codes and row shapes, never prose
- [ ] it checks: SCATTER names checkout and one more feature with homes under src/; no MOVE row touches FIXED bait; --score after is lower than before; --proof is 0 for a pure move and 1 for a logic edit and for Money.java with a changed package line
- [ ] it runs in at most 60 seconds and is bash 3.2 safe (macOS CI)
- [ ] hops.sh gains exactly drill_hops; spine.sh and the entry gain no function; the entry stays under 500 lines

## T-253 — "Release 6.12.0 - fewer lookups, found and fixed by POLARIS itself: version and changelog (LAST)"
points 1 · risk normal · landed 1b24054 (2026-11-06) · claimed 2026-11-06
files touched: CHANGELOG.md, kit/ops/VERSION

### Why
Change version: in kit/ops/VERSION to 6.12.0 and leave every other line of that multi-line keyed file exactly as it is. Add a "## 6.12.0 — <the day it lands>" entry at the top of CHANGELOG.md, above 6.11.0, in the same plain-language style, saying what an owner gets: POLARIS now notices when a project's layout makes agents jump between folders, measures it, and fixes it by itself at the end of a run with moves a check proves changed nothing but paths (anything it cannot prove is skipped and recorded); folder guides now reach every builder through pack, a short root map lands in CLAUDE.md, and the knowledge base builds itself; brand-new repos start tidy; and a run no longer stops in the middle — questions come first, and the close says plainly what waits on you, including why each parked task is parked. Tagging, publishing, the dogfood and the end-to-end checks are the conductor's steps, not this task.

### Acceptance
- [ ] every verify: line passes (VERSION is multi-line: use grep, never test "$(cat kit/ops/VERSION)" = ..., the T-217 trap)
- [ ] the CHANGELOG entry is plain language, no git or test vocabulary, and names no task IDs

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

## T-255 — "Builders and integrators follow tidy too, a builder's question parks by default, and route knows the TIDY role"
points 2 · risk normal · landed deb144d (2026-11-05) · claimed 2026-11-05 → done 2026-11-06
files touched: kit/ops/lib/observe.sh, kit/ops/roles/BUILDER.md, kit/ops/roles/INTEGRATOR.md

### Why
T-245 taught CONDUCTOR.md and SOLO.md the new `tidy` answer that `next` and `triage` print when the
layout pass is due, and changed what happens to a builder's question: by default the conductor now
parks it instead of stopping the run. Three places outside T-245's files were left behind.

1. BUILDER.md. A builder in a terminal pane loops on `next`, but Loop mode lists only `build`,
   `integrate`, `promote`, `wait`, `stop` and `finish`, so a pane whose `next` says `tidy` would not
   know what to do. Step 3 still says the conductor asks the human and re-dispatches; that is now
   true only under `autonomy: standard`. By default the conductor parks the question
   (`release --to blocked`, then `notify-gate question`) and keeps the other lanes going.
2. INTEGRATOR.md section 5 runs `next --do`, which can print `tidy` too, and the role does not say
   what to do with it. A top-level integrator takes it as a board-proven hop. A conductor-entered one
   must report it: it shares the conductor's session, so the once-per-session marker its call just
   set is the run's, and the conductor's own `next` will never print `tidy` again.
3. Routing. The conductor runs `route --role TIDY` before it spawns the TIDY subagent, and gets `mid`
   plus an "unknown role 'TIDY'" note, because the role table in `cmd_route` has no TIDY row.

The fix is wording in the two role files (no new heading line) and one more pattern in the existing
`case`. TIDY gets `mid`, the tier it already falls back to, so no spawn changes: the note just goes
away.

### Acceptance
- [ ] BUILDER.md Loop mode names `tidy` with the other verbs: read `ops/roles/TIDY.md` and run the pass here (a board-proven hop, as in SOLO.md step 7), then `next`
- [ ] BUILDER.md step 3, conductor-entered: by default the conductor parks the question (`bash ops/polaris release <ID> --to blocked -m "<question>"`, then `bash ops/polaris notify-gate question <ID>`); it asks the human and re-dispatches only under `autonomy: standard` (or `builder_questions: ask`)
- [ ] INTEGRATOR.md section 5, after the `next --do` paragraph: line 1 `tidy` → top-level: a board-proven hop (read `ops/roles/TIDY.md`, run the pass, then `next`); conductor-entered: put line 1 in the report unedited and let the conductor act, because it carries the conductor's `CLAUDE_CODE_SESSION_ID` and the marker is the run's
- [ ] `route --role TIDY` answers `mid` with no "unknown role" note; every other role answers exactly as before
- [ ] no line starting with `#` added or changed in any of the three files, and no new function: the api-kit rows for all three stay as they are

## T-256 — "pr-publish cleans up the day's integration branch it made, so CI's one-by-one drill run gets past express again"
points 2 · risk normal · landed 6846371 (2026-11-05) · claimed 2026-11-05 → done 2026-11-06
files touched: kit/ops/lib/selftest/history.sh

### Why
CI on `main` has been red on all three systems since v6.11.0 (v6.10.1 was the last green run). The
step that fails is `doctor --selftest (the full mechanics drill)`, which runs every drill one after
another (serially) inside a fresh install. The conductor reproduced it the same way (pack the kit,
install it into a scratch app, `bash ops/polaris doctor --selftest`): it fails after 1007 s with
`EXPRESS REFUSE MUTATE FAIL (integrate branch created)` (`kit/ops/lib/selftest/history.sh:81`).

What happens, step by step:

1. In the serial order (the `if drill_on` gates in `kit/ops/lib/selftest/spine.sh`) pr-publish runs
   immediately before express.
2. pr-publish's "v2 local staging seal" (`history.sh:278-293`, new in 6.11.0 with T-228) lands `T-Q`
   and runs `seal "$prd"` with `prd="$(date +%F)"`, under `publish: pr`. The land makes today's wave
   branch, `integrate/<today>`. A plain `seal` merges it into local `main` and tags it, but never
   deletes it (only `seal --sync` deletes a wave). So the drill ends with `integrate/<today>` still there.
3. express then checks that its refusals changed nothing, and one of those checks is "no
   `integrate/<today>` exists" (`history.sh:81`). It finds pr-publish's leftover and fails, although
   express made nothing.

busyint trips over the same leftover: its "a queued land must mutate nothing" check
(`history.sh:344`) looks for `integrate/<today>` too. That is the open IDEAS line from the T-254 fix
wave (`BUSYINT QUEUE MUTATE FAIL`, pr-publish the prime suspect). Of the drills in that repro,
pr-publish is the only one that lands on today's wave, so this task closes that line as well.

Why nobody saw it: the wave gate runs `doctor --selftest --parallel 3`, which spreads the drills over
three shards, each with its own practice repo, and pr-publish and express end up in different shards.
A sharded green is not a CI green (the sprint-13 lesson): only the serial run puts the two drills in
one repo.

The fix is hermeticity. The Hermeticity rule in `ops/contracts/selftest-sharding.md` says every drill
leaves the shared practice repo exactly as it found it, refs included:

- **pr-publish removes the local `integrate/<today>` branch it made** once its staging-seal checks are
  done (after `done T-Q`, or at the drill's end), standing on `main`, the way drill_park already drops
  its wave (`kit/ops/lib/selftest/policy.sh:831-833`). Then it checks the branch really is gone, the
  way express already does for its own wave (`history.sh:179`), so a future leak fails pr-publish
  itself instead of an innocent drill later in the run.
- **Optional:** express's refusal check (`history.sh:81`) compares `integrate/<today>` before and after
  the refusals (did a refusal CREATE or move it?) instead of asking whether it exists at all. This
  alone does not fix the run: express's red-suite step still needs a fresh day (`wave: created
  integrate/`, `history.sh:95`).

Only this one drill file changes. No change to the CLI.

### Acceptance
- [ ] `bash kit/ops/polaris doctor --selftest --only pr-publish,express` is green (red before the fix: `EXPRESS REFUSE MUTATE FAIL (integrate branch created)`)
- [ ] `bash kit/ops/polaris doctor --selftest --only pr-publish,busyint` is green (red before the fix: `BUSYINT QUEUE MUTATE FAIL`)
- [ ] `bash kit/ops/polaris doctor --selftest --only express` is still green
- [ ] drill_pr-publish leaves no local `integrate/<today>` branch behind, and fails with its own `PR ...` line if one is still there
- [ ] no other drill check is loosened: express's `wave: created` (`history.sh:95`) and branch-deleted (`history.sh:179`) checks stay as they are
- [ ] the diff touches only `kit/ops/lib/selftest/history.sh` (no CLI change)

## T-257 — "hops reads the tree it is pointed at, so a tidy pass can write guides for the folders its moves just made"
points 2 · risk normal · landed 2fd7258 (2026-11-05) · claimed 2026-11-05 → done 2026-11-06
files touched: kit/ops/lib/search.sh, kit/ops/roles/TIDY.md

### Why
`polaris hops` describes a repo's layout, and it describes whichever tree POLARIS_ROOT names. The
CLI's shim, `index_fast` in kit/ops/lib/search.sh, always sets POLARIS_ROOT to the primary checkout.
That is right for `find` and `show`, which need the primary's index, but wrong for a tidy pass: the
pass makes its moves in its task worktree, so when TIDY.md step 8 asks `hops --facts <dir>` for a
folder's facts it gets the layout from before the moves, and a folder the moves just created does
not exist there at all (rc 2). T-250 worked around that by writing guides only for folders that
already existed, which skips exactly the feature folders a pass creates: the ones most worth a
guide. The engine (ops/index.py) already reads any tree POLARIS_ROOT names, for every hops flag
(T-251), so the fix is small. For `hops` only, the shim keeps a POLARIS_ROOT the caller set, when it
names a real directory. TIDY.md step 8 then asks with `POLARIS_ROOT=<task worktree>`, and a pass can
guide the folders it made, still at most 8 per pass.

### Acceptance
- [ ] Checked FIRST: the CLI never exports POLARIS_ROOT into its own child processes. kit/ops/polaris,
- [ ] `index_fast`, `hops` only: a caller-set POLARIS_ROOT naming an existing directory is the root
- [ ] The engine is still resolved from the primary (`index_engine` on what `index_root` prints);
- [ ] TIDY.md step 8 calls `POLARIS_ROOT=<task worktree> bash ops/polaris hops --facts <dir>`, that
- [ ] TIDY.md no longer limits guides to folders that existed before the moves: a home folder the
- [ ] Surface-frozen: no new or changed `#` heading in TIDY.md, no new function in search.sh (both
