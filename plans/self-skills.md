# Skills POLARIS writes for itself — the T-146 spike (2026-09-14, plan `spend-less`, feeds the T-149 re-carve)

**Verdict first.** Worth building — but smaller than T-149's 13 points and not in the shape B3 sketched.
Two facts, both verified below, move the problem: (1) a skill with `disable-model-invocation: true` is
hidden from the model entirely and costs ZERO prompt bytes, and (2) a repo-committed skill is injected
only into sessions *in that repo*, never "every session on the machine" — the owner's home decision
already bounds the blast radius. So the budget governs a small, deliberately promoted shelf, and every
skill is born free. Most of the value is not the writer at all: it is (a) delivering a lesson WHOLE
(`pack`'s KNOWN TRAPS is a line-grep — the best lesson on this board is 19 lines and a builder gets 1),
(b) a zero-LLM skeleton that is literally `pack` over a surface instead of a task, and (c) a
path-triggered pointer that fires in a plain session when someone opens the surface. "Not like this":
no writer that a model runs inside the landing lane, no skill that is not born hidden, no key that
makes any of it run uninvited.

## The tension
Every model-invocable skill's `name:` + `description:` rides in the system prompt of every session and
every subagent, invoked or not. `cmd_slim` (kit/ops/lib/admin.sh:691-710 rationale, `slim_scan` :718,
`cmd_slim` :796) exists because that tax was the largest single token line item in a run. A skill that
saves a builder a 2-5k-token rediscovery is a win in the sessions that touch its surface and a pure tax
in the ones that do not; fifty speculative skills are POLARIS re-creating the problem `slim` measures.
Three corrections to the framing in plans/v3.md § B3, each of which changes the design:
- **Scope.** `slim` scans `~/.claude` only (`claude_home`, admin.sh:716) — that is the machine-wide
  tax. Repo skills under `.claude/skills/` load only in that repo (docs: skill locations, personal →
  project → nested). The owner's home decision therefore already confines the cost to the repo's own
  sessions. What remains is real: every session in the repo pays for every skill, including the five
  of six that never touch its surface.
- **The zero tier.** `disable-model-invocation: true` "hides it from Claude entirely until you invoke it
  manually" (code.claude.com/docs/en/features-overview, context-cost table; confirmed by observation:
  this session's injected list carries `polaris`, `kit:polaris`, `polaris-install`, `kit:polaris-install`
  and NEITHER copy of `i-have-adhd`). Such a skill costs 0 B per context and is still loadable by
  `/name` and by any command that prints its path. `slim_scan` does not know this yet — it counts
  i-have-adhd's 276 B in both trees.
- **A path trigger exists.** `.claude/rules/<name>.md` with a `paths:` glob loads only when Claude reads
  a matching file (docs/en/memory, "Path-specific rules") — the owner's scenario ("when someone changes
  it") keyed on exactly the event, at zero standing cost. Skills have no `paths:`; rules do. The home
  stays the skill (decided); a 3-line rule can point at it. OPEN-1 below; the probe leaf proves it.
So: the budget is for the promoted tier only, promotion is earned by evidence, and eviction is a
demotion first (free, reversible) and an archive second.

## Measurements
`bash ops/polaris slim` (report only), this machine, 2026-09-14, pasted in full:
```
CONTEXT TAX — bytes every session AND every subagent pays before any work
  source: /c/Users/Owner/.claude

  claude-flow machinery, by family                  bytes ~tokens
  agents/v3                                          2956     739
  agents/templates                                   2315     578
  agents/github                                      2229     557
  agents/sublinear                                   1781     445
  commands/sparc                                     1648     412
  agents/flow-nexus                                  1366     341
  agents/consensus                                    848     212
  agents/optimization                                 613     153
  agents/core                                         455     113
  agents/sparc                                        433     108
  agents/swarm                                        384      96
  agents/goal                                         358      89

  MACHINERY — archived by --apply                 24245    6061   (196 files)
  referenced by POLARIS — kept                     2031     507   (18 files)
  unrecognised — kept, never moved                 2848     712   (9 files)
  total paid per context                            29124    7281

  A conductor run spawns 6-8 contexts: 36366-48488 tokens recoverable per run.

   report only — nothing moved. To recover the machinery:  polaris slim --apply
   always reversible:                                      polaris slim --restore
   the 'unrecognised' rows are YOUR skills — slim never moves what it cannot identify
```
- The figure B3 quotes (251 files / 34,119 B / ~8,500 tok, admin.sh:702, 2026-07-26) is stale:
  today 223 / 29,124 / 7,281. `--apply` was never run (196 machinery files still present).
- Shipped SKILL.md frontmatter, measured with `slim_scan`'s own rule (`name:`/`description:` lines +1
  each, folded continuation lines included) — the same awk, never a second measurement:

  | file | fence-to-fence | name+description (slim rule) | actually injected |
  |---|---|---|---|
  | kit/.claude/skills/i-have-adhd/SKILL.md | 447 B | 276 B | **0** (`disable-model-invocation: true`) |
  | kit/.claude/skills/polaris-install/SKILL.md | 556 B | 556 B | 556 B |
  | kit/.claude/skills/polaris/SKILL.md | 827 B | 827 B | 827 B |

- What a session in THIS repo pays for POLARIS's own skills: `polaris` 827 + `kit:polaris` 827+114
  (the nested-dir scope suffix is 114 B) + `polaris-install` 556 (in slim's "kept" 2,031) +
  `kit:polaris-install` 556+114 = **2,994 B ≈ 748 tok per context**; 1,611 B of it is the dogfood
  layout's nested copy. Out of scope here, but it is the number a new shelf must be judged against.
- Per-context cost of ONE more skill, tokens = bytes ÷ 4 (slim's arithmetic), × a 6-8-context run:

  | frontmatter | per context | per 6-context run | per 8-context run |
  |---|---|---|---|
  | 827 B (the `polaris` size) | 206 | 1,236 | 1,648 |
  | 556 B (`polaris-install`) | 139 | 834 | 1,112 |
  | 320 B (the per-skill cap proposed below) | 80 | 480 | 640 |
  | 1,600 B (the shelf cap proposed below) | 400 | 2,400 | 3,200 |

- What it competes with: this task's `pack` is 16,772 B ≈ 4,193 tok in ONE call (BUILDER.md § 2 says
  it replaced 6-15 calls). The Learned bullet on `ops/tests/api-kit.expected` is 19 lines ≈ 475 tok;
  `pack_brain_grep` (builder.sh:584-590) is `grep -E … | head -8` over wrapped bullets, so a builder
  owning that file receives exactly 1 of those 19 lines.
- The board's own signal (139 done tasks, 93 distinct owned paths): **36 paths owned exactly once
  (39 %)**, 45 owned ≥ 3, 26 ≥ 5, 9 ≥ 10. Top: `kit/ops/polaris` 35 (25 %), `ops/tests/api-kit.expected`
  21 (15 %), `kit/ops/lib/observe.sh` 15 (11 %), `kit/ops/roles/BUILDER.md` 14, `kit/ops/MANUAL.md` 12,
  `kit/CLAUDE.md` 12, `kit/ops/lib/builder.sh` 11, CONDUCTOR.md 10, PROTOCOL.md 10. By directory:
  kit/ops 84 · ops/tests 68 · kit/ops/lib 64 · kit/ops/roles 60 · kit/ops/lib/selftest 36.
- Kickbacks: 3 of 139 (2.2 %) — T-047 and T-062 are the SAME lesson (the api-kit golden), T-082 the
  third. EVENTS.ndjson: 509 lines over 62 days; 48 `done` since sprint/12 (12 days); the last 40 `done`
  span 12 days ≈ 2 sprints (sprint/11 08-23 · /12 09-02 · /13 09-08 · /14 09-14).
- `ops/SURFACES.tsv`: 0 rows here (D2 ships it empty) and 0 done tasks carry `surface:` yet — the
  gap-finder's primary signal today is `files_owned`; rows become the better unit as they arrive.
- `probe:` lines (SK-0 appends three here: hidden-tier list check · rules `paths:` fires on Read ·
  nested-dir prefix) — pending.

## Budget
Break-even, per context: a tier-1 skill of f bytes costs f/4 tokens; it saves S tokens in the fraction p
of contexts that touch its surface. Worth it iff **p·S > f/4**. With f = 320 (80 tok) and S = 2,000 (a
whole Learned bullet plus the API surface a builder otherwise re-reads by hand) the bar is p > 4 %.
`kit/ops/polaris` (25 %), the api-kit golden (15 %) and observe.sh (11 %) clear it 3-6×. A path owned
once (0.7 %) fails it even at S = 10,000 (72 < 80). p here is the share of DONE TASKS; only a task's
builder context reads the skill, so the true per-context p is lower — the bar is a floor, not a ceiling.
- **Per skill: frontmatter ≤ 320 B** by the slim rule (name ≤ 24 + one `description:` line ≤ ~290 chars —
  two lines of the proven `polaris` pattern "TRIGGER when … DO NOT TRIGGER when …"). `polaris-install`'s
  556-B description is the longest trigger the kit ever needed and is 2× too long for a surface skill.
- **Per repo: Σ tier-1 frontmatter ≤ 1,600 B** = five skills at the cap ≈ 400 tok/context ≈ 2,400-3,200
  tok per run — under ONE `pack` (4,193) and about half of what POLARIS's own two skills already cost
  here (748/context). Why not more: the machine tax is 7,281 tok and the owner is trying to get it DOWN;
  a shelf allowed to outgrow POLARIS itself would be POLARIS re-creating what `slim` exists to remove.
- **Tier 0 is uncounted in bytes** (0 injected) — bounded by a count WARNING at 24 per repo (`skill
  list`/`doctor`), never a refusal: its cost is tree hygiene and one `pack` line per overlapping skill.
- **At the cap:** `skill promote` REFUSES, prints the shelf with each skill's hits and last hit, names
  the demotion candidate, writes nothing, rc 1. Never a silent eviction to make room; the writer of a
  tier-0 skill is never blocked by the cap. Both numbers are constants in code pinned by a golden — no
  CONVENTIONS key; nothing here runs uninvited, so there is nothing to switch off.

## Eviction
"Used" needs a record of a skill being READ. Today none exists: `pack` is read-only by contract
(context-pack.md: never writes the board — and EVENTS.ndjson IS board state), the harness's `Skill`
tool is invisible to the kit, and `EVENTS.ndjson` (`{"ts","ev","id","who","note"[,"pts"]}`, `evt` at
core.sh:91) carries claim/handoff/done/kickback/… and nothing about skills. What must be added — ONE
event kind, emitted by the one board write that already knows the task's surface:
```
{"ts":<epoch>,"ev":"skill-hit","id":"<skill name>","who":"…","note":"<task ID>"}
```
`claim` (builder.sh:125, beside `evt claim`) emits one `skill-hit` per skill whose `metadata.polaris.paths`
overlaps the task's `files_owned` (`pat_overlap`, both directions — the SURFACES section's matcher).
Inside the mutex, on the same board commit, union-merged like every other line. Explicit `/name` use
in a plain session is NOT recorded in 6.4 (OPEN-2). The rule, as data a command evaluates:
```
W            := 40 done events            # ≈ 2 sprints / 12 days on this board — done events, not days:
                                          # a repo can idle for a month and idle is not disuse
hits(s, n)   := count of skill-hit lines for s with ts ≥ ts(the n-th most recent done event)
young(s)     := fewer than W done events since s's metadata.polaris.since     # never judged before W
demote(s)    := tier(s)=1 ∧ ¬young(s) ∧ hits(s, W)=0      → disable-model-invocation: true  (0 B, reversible)
archive(s)   := tier(s)=0 ∧ ¬young(s) ∧ hits(s, 2W)=0     → git mv .claude/skills/<s> .polaris/skills-archived/<s>
gap(g)       := ¬covered(g) ∧ owners(g, 2W) ≥ 5           # § Gap-finder; the same window, the same counter
```
- `polaris skill prune` prints the verdicts (`demote <s> · 0/40` · `archive <s> · 0/80` · `keep <s> · 7/40`),
  rc 1 when any is due; `--apply` performs them on `<base>` only, as a tree change the human commits
  (`nothing was committed for you` — the `interview --set` precedent). `doctor` prints the one summary line.
- **The reversible move.** Archive under `.polaris/skills-archived/<name>/` mirroring the original path
  (local, gitignored — `slim --apply`'s exact shape, RESTORE.md included), and the removal is a commit
  titled `chore(skills): archive <name> — 0 hits in 80 done`. `skill restore <name>` moves it back when
  the local archive exists, else `git show <that commit>^:.claude/skills/<name>/SKILL.md` — so a second
  machine, which never had the archive, restores what the first one evicted. Nothing is ever deleted.
- Who applies: EVOLVE, between sprints, from `prune`'s report. A demote is byte-reversible and inert;
  whether it joins EVOLVE's fixed auto-reversible allowlist is a HUMAN decision (OPEN-3).

## Gap-finder
A skill is worth writing for a surface the board keeps returning to. Three signals, in rank order:
1. **Kickback pairs on one path** (2 of this board's 3 kickbacks are the api-kit golden — the same
   lesson twice is the strongest "what POLARIS keeps getting wrong here" there is). Any kickback or
   `⛔` note naming a path counts as k; a candidate is sorted by n·(1+k).
2. **`ops/SURFACES.tsv` rows** (when present): a row whose surface glob overlaps ≥ 5 of the last 2W = 80
   done tasks' `files_owned` and no skill's `paths` overlaps. Rows are the better unit — a row is a
   NAMED surface with a `note` and a `tests` glob that seed two skeleton sections. Zero rows here today.
3. **`files_owned` frequency** (exists today, board-only): a path, or the deepest directory holding ≥ 5
   hits, owned by ≥ 5 of the last 80 done tasks and covered by no skill. Fold to the directory when the
   files share it — `kit/ops/roles/` is 60 hits over 6 files: ONE skill "the role files", not six.
- **Why 5 over 80, not 3:** 5/80 = 6.25 % → p·S = 125 > 80 clears the § Budget bar; 3/80 = 3.75 % → 75 < 80
  does not. Over the last 80, not all-time: the all-time top (`kit/ops/polaris`, 35×) reflects the CLI-split
  era; a surface that stopped recurring is a Learned bullet, not a skill.
- **Why NOT a surface worked once:** 36 of 93 paths were owned exactly once. A 320-B skill each is 11.5 KB
  ≈ 2,880 tok per context — more than a third of the machinery `slim` is trying to recover — and each
  would fire in 0.7 % of contexts. One task's lesson already has free homes: the Learned log,
  `learned.md`, KNOWN TRAPS. A skill is for what recurs; the writer refuses below the threshold unless
  `--force` (a human's call, recorded in the skill's `evidence:`).
- `polaris skill gaps` → one line per candidate: `<surface>  <n>/80 tasks · <k> kickbacks · skill: none`;
  read-only; rc 0 always.

## The writer
**Who.** The SKELETON is a command — zero-LLM, deterministic over (board, brain, index), goldenable:
`polaris skill propose <surface-glob> [--name <n>] [--write] [--force]`. The PROSE — the one-sentence
trigger and the distillation of "what keeps going wrong" — is EVOLVE's: the role that already reads the
Learned log, the kickbacks and `done/` frontmatter between sprints, is human-gated, and writes no feature
code, so a skill becomes the ONE artifact it may create (≤ 1 per run; an EVOLVE.md "legal targets" line).
Not the Integrator at `done`: the landing lane is serialized and the most expensive place to run a model
writing prose; `done` already writes SURFACES rows, mechanically, and that is the right shape for it. Not
the Builder: mid-task, and writing about its own file — the self-interest D1 named. A human may run
`propose` at any time. `--write` creates `.claude/skills/<name>/` on `<base>` only (refuses on `feat/*`,
like `interview --set`), never overwrites, and commits nothing.
**The skeleton reuses what `pack` already computes** — the owned-path ERE `pat` (builder.sh:675) and the
four section producers behind WHERE THIS LIVES (the `code-map.md` awk), PUBLIC SURFACE (`find --api`),
KNOWN TRAPS (`pack_brain_grep` over `learned.md`/`gotchas.md`) and SURFACES (`surfaces_lines` +
`pat_overlap`) — over a SURFACE instead of a task. One producer changes for both callers: KNOWN TRAPS
prints WHOLE bullets (awk paragraph mode, ≤ 8 bullets / 40 lines), not the one line the grep hits.
```
---
name: <name>                        # ≤ 24 B, kebab-case, never a reserved name (§ Names and homes)
description: TODO(<surface>) — ≤ 290 chars: TRIGGER when …; DO NOT TRIGGER when …   # EVOLVE writes it
disable-model-invocation: true      # tier 0 — every skill is born here; `skill promote` flips it
metadata:
  polaris: { paths: [<globs>], since: 2026-09-14, tier: 0, evidence: "<n>/80 tasks · <k> kickbacks" }
---
# <surface> — what POLARIS already knows
## What it is                ← code-map entry + the SURFACES row's note
## Public surface            ← find --api, ≤ 25 lines
## What keeps going wrong    ← whole Learned bullets + kickback notes naming these paths, ≤ 40 lines
## Files that move together  ← learned.md co-change pairs touching these paths
## Tests that cover it       ← SURFACES rows + the verify: lines of the last 3 done tasks here
## Last worked               ← the last 5 done task IDs + titles
```
Frontmatter is the ONLY thing the budget counts; the body (≤ 200 lines) is where the savings live.
`metadata:` is free — slim's rule counts name/description only, and i-have-adhd's `license:`/`metadata:`
keys prove the harness ignores unknown fields. `promote` refuses while `TODO(` is in the description: a
generated trigger sentence is a lie about when to fire.
**Delivery.** `pack` gains ONE section, `SKILLS — what POLARIS already knows about these paths`, one
line per skill whose paths overlap `files_owned`: `read: .claude/skills/<name>/SKILL.md · tier 0 · 7/40
hits · 88 lines` — OMITTED when nothing overlaps (pack-visual's absent-by-default precedent; that golden
slices only SEE YOUR WORK, so it stays byte-identical). Plain sessions: `/name`, and — OPEN-1 — a
`.claude/rules/<name>.md` twin (`paths:` = the skill's globs, body = two lines pointing at the skill).
`slim_scan` learns the flag (a `disable-model-invocation: true` definition counts 0), a one-line awk change.

## Names and homes
- **Home:** `.claude/skills/<name>/SKILL.md`, committed — owner decision; the repo carries it to every
  device. The local archive is `.polaris/skills-archived/<name>/`; the rules twin, if OPEN-1 says yes,
  `.claude/rules/<name>.md`. Identity = the `metadata.polaris` key, not a name prefix (OPEN-6).
- **Reserved names** — what `update` manages and would overwrite. admin.sh:557 (B3 cites :552; the
  line has since moved), `update_dirt_overlaps_kit`'s footprint test, verbatim:
  ```
        .claude/settings.json|.claude/skills/polaris/*|.claude/skills/i-have-adhd/*|.claude/output-styles/polaris.md) return 0;;
  ```
  install.sh:249-260 copies exactly `polaris` and `i-have-adhd` (`polaris-install` lives in `~/.claude`,
  `refresh_machine_kit` admin.sh:212); uninstall (admin.sh:982-983) removes exactly those two, then
  `rmdir .claude/skills` only if empty; slim's hard-keep list (admin.sh:779) names all three. So:
  `polaris` · `polaris-install` · `i-have-adhd`, plus any `polaris-*` (future kit skills), are refused
  by `propose`; so is any name that exists under `~/.claude/skills/` — personal beats project in the
  harness's conflict order, so such a repo skill would be shadowed and silently never fire.
- **How `update` treats them:** untouched — the installer copies two named dirs and `update_dirt_overlaps_kit`
  never lists other skills, so a dirty POLARIS-written skill never blocks an update. Pin it: a fixture
  repo with a foreign `.claude/skills/know-x/` is byte-identical after `install.sh` (SK-3 golden).
- **How `uninstall` treats them:** leaves them, by design (today by accident of the `rmdir`). The preview
  gains one line: `N skill(s) POLARIS wrote stay — they are this repo's knowledge; rm by hand`. The
  local archive goes with `.polaris/`; git history still holds every archived skill (OPEN-8).
- The dogfood layout (`kit/.claude/skills/` injected as `kit:polaris` etc.) doubles this repo's own tax;
  a spike finding, not this design's problem — one line in IDEAS.md.

## Proposed contract
Lift into `ops/contracts/self-skills.md` (CONTRACT.md shape).
```
# CONTRACT: self-skills            (v1 — 2026-09-14, plan spend-less, 6.4.x)
## Purpose
Separates the SKELETON (a deterministic command over board+brain+index), the SHELF (a byte budget on
model-invocable frontmatter) and the EVICTION (a data rule over EVENTS.ndjson) from the PROSE (EVOLVE,
human-gated). Every skill is born hidden; promotion is earned; nothing runs uninvited.
## Interface
polaris skill list                          name · tier · bytes · hits/W · last hit · paths   (rc 0; W-count over 24 = ⚠)
polaris skill gaps                          candidates: <surface> <n>/80 tasks · <k> kickbacks · skill: none   (rc 0)
polaris skill budget                        constants + Σ tier-1 bytes; rc 1 when over (doctor's line)
polaris skill propose <glob> [--name N] [--write] [--force]
                                            skeleton on stdout; --write creates .claude/skills/N/ on <base> only,
                                            refuses reserved/shadowed names, never overwrites; below threshold ⇒ rc 1 unless --force
polaris skill promote <name> | demote <name>
                                            flip disable-model-invocation; promote refuses TODO( ·  >320 B · shelf >1600 B (rc 1, prints shelf)
polaris skill prune [--apply]               verdicts per § Eviction; --apply = base only, tree change, no commit
polaris skill restore <name>                from .polaris/skills-archived/, else from git history
claim <ID>                                  ALSO emits one skill-hit event per overlapping skill (the only telemetry)
pack <ID>                                   ALSO prints SKILLS — … when any skill overlaps; omitted otherwise
slim                                        counts a disable-model-invocation: true definition as 0 B
## Shared types / schema
frontmatter: name · description · disable-model-invocation · metadata.polaris{paths[],since,tier,evidence}
event:       {"ev":"skill-hit","id":"<skill>","note":"<task ID>"}   ridden by claim's board commit
constants:   SKILL_FM_MAX=320 · SKILLS_SHELF_MAX=1600 · SKILLS_WINDOW=40 · SKILLS_GAP_MIN=5 · SKILLS_T0_WARN=24
reserved:    polaris · polaris-install · i-have-adhd · polaris-* · any ~/.claude/skills/<name>
archive:     .polaris/skills-archived/<name>/SKILL.md (+ RESTORE.md) · commit "chore(skills): archive <name> — 0 hits in 80 done"
## Executable check
ops/tests/skill-budget.cmd/.expected  — constants + the kit's three skills through the flag-aware counter
                                        (i-have-adhd 0 · polaris-install 556 · polaris 827) + reserved-name refusals
ops/tests/skill-install.cmd/.expected — a foreign .claude/skills/know-x/ survives install.sh and uninstall byte-identical
drill_skills (kit/ops/lib/selftest/policy.sh) — hermetic board: 6 done on src/search/, 1 on src/other/ ⇒ gaps lists
    only src/search/; propose ⇒ TODO skeleton; promote refuses TODO, passes after edit, third promote past 1600 refuses;
    claim of a task owning src/search/x emits skill-hit; 41 synthetic done + 0 hits ⇒ prune says demote; --apply flips;
    81 ⇒ archive; restore ⇒ byte-identical. Asserts rc + file bytes, never message text (sprint-11 lesson).
selftest_fast section `skills` — skill_bytes / skill_budget_check / skill_window on fixture strings.
## Invariants
1. Born hidden: propose always writes disable-model-invocation: true; only promote flips it.
2. One counter: budget bytes are slim_scan's rule — `slim` and `skill budget` can never disagree.
3. Nothing uninvited: no hook, no SessionStart path, no auto-write, no CONVENTIONS key; claim's skill-hit is the only telemetry.
4. Archive, never delete; restore works on a machine that never held the archive.
5. update/uninstall never touch a skill carrying metadata.polaris; reserved names are refused, not renamed.
6. The skeleton is deterministic (same board+brain+index ⇒ same bytes); the description is never generated.
7. Body ≤ 200 lines; tier-1 frontmatter ≤ 320 B; shelf ≤ 1,600 B; window in done events, floor W.
## Example
$ polaris skill gaps
ops/tests/api-kit.expected   21/80 tasks · 2 kickbacks · skill: none
kit/ops/roles/               14/80 tasks · 0 kickbacks · skill: none
$ polaris skill propose ops/tests/api-kit.expected --name api-kit-golden --write
✅ wrote .claude/skills/api-kit-golden/SKILL.md (tier 0 · 96 lines · description is TODO — EVOLVE writes it)
$ polaris skill promote api-kit-golden
⛔ description still TODO(ops/tests/api-kit.expected) — write the trigger sentence first (≤ 290 chars)
```
OPEN lines — two options each, my recommendation last:
- **OPEN-1 rules twin.** A: SK-2 writes `.claude/rules/<name>.md` beside every skill (SK-0 proves it fires on
  Read). B: skills only, `pack` + `/name` delivery. → A iff SK-0 proves it; B otherwise, never assumed.
- **OPEN-2 explicit-invocation telemetry.** A: a PreToolUse matcher on the `Skill` tool appends an event.
  B: claim-time only. → B for 6.4: a hook writes EVENTS outside the board mutex (a race the union-merge
  hides), and claim-time is what eviction needs; revisit if a plain-session skill is ever demoted wrongly.
- **OPEN-3 EVOLVE's auto-reversible allowlist.** A: `skill demote` joins it (byte-reversible, inert).
  B: approve queue. → A for demote, B for archive — a HUMAN decision (EVOLVE.md forbids self-escalation).
- **OPEN-4 who may promote.** A: EVOLVE with `approve <n>`. B: any human, any time. → A: promotion spends
  every future session's budget; a human running the command is still A.
- **OPEN-5 window unit.** A: 40 done events. B: 2 sealed sprints. → A with the floor: sprints here run
  6-10 days but 12-25 tasks; done events track work, calendar tracks nothing.
- **OPEN-6 name prefix (`know-`).** A: prefix. B: free names, identity via `metadata.polaris`. → B.
- **OPEN-7 the stale 251/34,119 figure** in plans/v3.md and admin.sh:702. A: rewrite. B: leave, dated. → B,
  with today's number beside it in the CHANGELOG entry.
- **OPEN-8 uninstall.** A: leave POLARIS-written skills + one preview line. B: `--skills` removes them. → A.
- **OPEN-9 tier-0 count.** A: uncapped. B: ⚠ at 24. → B, warning only.
- **OPEN-10 body producer change** (KNOWN TRAPS whole bullets) changes `pack` output for every repo with a
  brain. A: ship in SK-2. B: separate 1-pt task. → A: it is the same producer the skeleton reuses.

## Proposed carve
Five leaves, ≤ 5 pts, disjoint `files_owned`, api-kit ONE owner per wave (test-surfaces.md § 11/§ 18 rule).
No new CONVENTIONS key, no KEYS.tsv row, no RULES line. Total 14 pts against T-149's 13; the minimum
that is still the design is SK-1 + SK-3 (8 pts); SK-0 first because OPEN-1 hangs on it.
- **SK-0 · 1 pt · W0 · probe (a TOP-LEVEL session — the T-087 lesson: a pinned-cwd subagent cannot see
  its own injected list).** Throwaway repo, three facts by experiment, appended as `probe:` lines under
  `## Measurements` here: (a) a hidden skill is absent from the model's list while its plain twin is
  present; (b) a `.claude/rules/x.md` with `paths: [src/search/**]` is loaded on Read of a matching file
  and not before; (c) the nested-dir prefix. `files_owned: plans/self-skills.md`. No api-kit row.
- **SK-1 · 5 pts · W1 · the module.** NEW `kit/ops/lib/skills.sh` (module-layout.md gains `## v7 —
  lib/skills.sh joins the census`, Planner-written) with EXACTLY these top-level fns: `cmd_skill` ·
  `skill_bytes` (slim's awk, flag-aware) · `skill_paths` · `skill_tier` · `skill_hits` · `skill_list` ·
  `skill_gaps` · `skill_budget` · `skill_propose` · `skill_promote` · `skill_demote` · `skill_prune` ·
  `skill_restore`. Entry `kit/ops/polaris`: loader line, usage entry (after `slim`), dispatch
  `skill) shift; cmd_skill "$@";;`. `files_owned`: kit/ops/lib/skills.sh · kit/ops/polaris ·
  ops/tests/api-kit.expected (W1 owner: +13 `kit/ops/lib/skills.sh<TAB>fn<TAB>…` rows, nothing else
  under kit/ moves in W1). `verify:` the content diff of api-kit (§ 18 recipe) + `bash kit/ops/polaris
  skill budget` prints the constants + `skill propose` on a reserved name dies.
- **SK-2 · 3 pts · W2 · the wiring, NO new top-level fn (surface-frozen, inline sections).** builder.sh:
  `claim` emits `skill-hit` (beside :125) · `pack` gains the SKILLS section · `pack_brain_grep` prints
  whole bullets (OPEN-10). admin.sh: `slim_scan` counts a flagged definition as 0 (one awk line; the
  rationale block gains today's figure, OPEN-7). observe.sh: `doctor` prints `skill budget`/`prune`'s one
  line, guarded `command -v skill_budget` (the T-141/T-142 same-wave guard). Rules twin iff OPEN-1 = A.
  `files_owned`: kit/ops/lib/builder.sh · kit/ops/lib/admin.sh · kit/ops/lib/observe.sh. api-kit rows: none.
- **SK-3 · 3 pts · W2 · W2 api-kit owner · the proof.** `drill_skills` in kit/ops/lib/selftest/policy.sh
  (the drill above — proves the eviction end to end, asserts rc + bytes) · a `skills` section inside
  `selftest_fast` (fast.sh, no new fn) · goldens `ops/tests/skill-budget.*` (pins BOTH budget constants and
  the three shipped sizes — the golden that pins the budget) and `ops/tests/skill-install.*` (install/
  uninstall leave a foreign skill byte-identical). `files_owned`: kit/ops/lib/selftest/policy.sh ·
  kit/ops/lib/selftest/fast.sh · ops/tests/skill-budget.cmd · .expected · ops/tests/skill-install.cmd ·
  .expected · ops/tests/api-kit.expected (+1 row `kit/ops/lib/selftest/policy.sh<TAB>fn<TAB>drill_skills`;
  SK-2 adds none). Existing goldens unchanged and green: pack-visual (slices SEE YOUR WORK only) ·
  startup-budget · adhd-skill-installed · cli-help (regenerates at the dogfood) · rules-health (no new rule).
- **SK-4 · 2 pts · W3 · W3 api-kit owner · the prose.** `kit/ops/templates/SKILL.md` (the skeleton's
  static half — its `## ` headings are the W3 rows, 6 of them) · EVOLVE.md "legal targets" gains the
  `skill propose` line + ≤ 1 skill per run (a list item, no heading) · PROTOCOL.md THE TOOL row + one
  TOKEN DISCIPLINE bullet · MANUAL.md paragraph · `polaris` SKILL.md body line 3 lists `skill` (its
  description is UNTOUCHED — 827 B stays 827 B). kit/CLAUDE.md: untouched, it is paid 6-8× a run.
  `files_owned`: kit/ops/templates/SKILL.md · kit/ops/roles/EVOLVE.md · kit/ops/PROTOCOL.md ·
  kit/ops/MANUAL.md · kit/.claude/skills/polaris/SKILL.md · ops/tests/api-kit.expected.
- Release rider: VERSION + CHANGELOG (the CHANGELOG line carries both slim figures, OPEN-7).
- T-149: retired by the Planner's re-carve commit; its provisional `files_owned` (knowledge.sh, EVOLVE.md,
  templates/SKILL.md) were guesses — knowledge.sh is untouched here (the brain is a producer, not a home).
