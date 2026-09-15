# CONTRACT: self-skills            (v1 — 2026-09-14, plan `sprint-c`, 6.5.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the SKELETON (a deterministic command over board + brain + index), the SHELF (a byte
budget on model-invocable frontmatter), the EVICTION (a data rule over `EVENTS.ndjson`) and the
DELIVERY (`pack`, `/name`, the path-triggered twin) from the PROSE (EVOLVE's trigger sentence,
human-gated). Every skill is born hidden; promotion is earned and human-approved; nothing runs
uninvited. Lifted from `plans/self-skills.md` (the T-146 spike) with the owner's two recorded calls
(plans/v3.md § SPRINT C): the twin is PROBED before it is built, and EVOLVE proposes promotion while
a human approves it. Tasks: T-150 (the probe, W0) · T-155 (module + entry, W1 api-kit owner) ·
T-156 (wiring) · T-158 (prose + template, W2 api-kit owner) · T-159 (proof, W3 api-kit owner).
Names are pinned HERE; outputs are pinned by the running code and its goldens — when this file's
worked arithmetic and the built behaviour disagree, the name here wins and the number there does.

## 0. The decisions, pinned (the spike's OPEN lines, answered)
| OPEN | decision |
|---|---|
| 1 rules twin | PROBE-GATED (owner: prove first, then build). T-150 records `probe: rules-paths-fires-on-read: yes\|no` in `plans/self-skills.md` § Measurements. `yes` ⇒ `skill propose --write` also writes the twin (§ 6) and `prune --apply` / `restore` move it with the skill; `no` ⇒ no twin anywhere, `skill list` prints `twin -`, and NOTHING else changes — SK-1..SK-4 ship as plain skills. The fn census (§ 2) is identical in both outcomes. |
| 2 explicit-invocation telemetry | claim-time only: `claim` emits `skill-hit` events (§ 4). A plain-session `/name` use is not recorded in 6.5. |
| 3 EVOLVE's inert allowlist | **ASYMMETRIC BY DESIGN.** `skill demote <name>` frees budget, is byte-reversible and cannot break a session, so it MAY sit in EVOLVE's auto-reversible allowlist (EVOLVE.md item 5). `skill promote <name>` NEVER does: it spends every future session's budget in that repo, so it goes in the approve queue like every other escalation — consistent with EVOLVE never self-escalating. `prune --apply` (archive) is the approve queue too. A reader who files the asymmetry as a bug has read it correctly; the answer is "deliberate, owner 2026-09-14". |
| 4 who may promote | EVOLVE PROPOSES (`skill promote <name>` as a numbered proposal carrying the `hits/W` evidence line); the human's `approve <n>` runs it — or a human runs the command directly. Both are the same yes. No agent runs `skill promote` on its own initiative, under ANY autonomy setting. |
| 5 window unit | 40 done events (`SKILLS_WINDOW`), floor W: a skill is never judged before W done events have passed since its `since:`. Done events track work; calendar tracks nothing. |
| 6 name prefix | free names; identity is the `metadata.polaris` key. |
| 7 the stale 251 / 34,119 B figure | stays, dated, in admin.sh's rationale; today's 223 / 29,124 B / 7,281 tok goes beside it; the CHANGELOG line carries both. |
| 8 uninstall | POLARIS-written skills STAY; the preview gains one line (§ 7). |
| 9 tier-0 count | ⚠ at 24 (`SKILLS_T0_WARN`), warning only, never a refusal. |
| 10 KNOWN TRAPS whole bullets | ships in T-156 with the SKILLS section — same producer, one change for both callers. |

## 1. Interface — CLI (T-155 owns `kit/ops/polaris`: loader, usage, dispatch)
```
polaris skill list                          one line per POLARIS-written skill + a summary line; rc 0
polaris skill gaps                          candidate surfaces with no skill; rc 0
polaris skill budget                        constants + Σ tier-1 bytes; rc 1 when the shelf is over
polaris skill propose <glob> [--name <n>] [--write] [--force]
polaris skill promote <name> | demote <name>
polaris skill prune [--apply]
polaris skill restore <name>
```
Dispatch line (verbatim): `skill)      shift; cmd_skill "$@";;` placed directly under `slim)`.
Usage entry (verbatim, placed directly under the `slim` entry):
```
  skill list | gaps | budget | propose <glob> [--name N] [--write] [--force]
        | promote <name> | demote <name> | prune [--apply] | restore <name>
                                 skills POLARIS writes for itself (ops/contracts/self-skills.md):
                                 list = name · tier · bytes · hits/W · last hit · paths; gaps = the
                                 surfaces the board keeps returning to with no skill; budget = the
                                 shelf constants + Σ tier-1 frontmatter bytes (rc 1 when over);
                                 propose = a deterministic SKELETON on stdout — --write creates
                                 .claude/skills/N/SKILL.md born HIDDEN (disable-model-invocation:
                                 true = 0 prompt bytes) on <base> only, never overwrites, refuses
                                 reserved names; promote flips it visible (refuses a TODO( trigger,
                                 >320 B, a shelf past 1600 B) — EVOLVE proposes it, a human runs it;
                                 demote is the free reverse; prune = eviction verdicts over
                                 EVENTS.ndjson, --apply archives under .polaris/skills-archived/
                                 (never deletes); restore brings one back from the archive or git
```
Loader: `skills` joins the FULL-load `_mods` list immediately after `handover` (module-layout.md v7).
Every subcommand runs from any cwd inside the repo; the writers (`propose --write`, `promote`,
`demote`, `prune --apply`, `restore`) REFUSE on any `feat/*` branch with
`⛔ skill <sub> runs on <base> — a skill is repo knowledge, not a task's diff` (the `interview --set`
precedent) and commit NOTHING (`nothing was committed for you` closes every write).

## 2. Interface — `kit/ops/lib/skills.sh` (T-155; EXACTLY these 14 top-level fns, ≤ 500 lines)
| fn | contract |
|---|---|
| `cmd_skill` | dispatch; bad sub/flag ⇒ `die "usage: polaris skill list \| gaps \| budget \| propose <glob> [--name N] [--write] [--force] \| promote <name> \| demote <name> \| prune [--apply] \| restore <name>"` |
| `skill_consts` | sets the five globals (builtins only, idempotent): `SKILL_FM_MAX=320 SKILLS_SHELF_MAX=1600 SKILLS_WINDOW=40 SKILLS_GAP_MIN=5 SKILLS_T0_WARN=24`. Called at the top of every fn that reads them — module-layout forbids top-level assignments. No CONVENTIONS key, ever. |
| `skill_bytes <SKILL.md>` | prints the injected byte count by slim's rule (`name:`/`description:` lines +1 each, folded continuation lines included) — **0 when the frontmatter carries `disable-model-invocation: true`**. Same awk as `slim_scan` with the flag clause; the fast tier proves both counters agree (§ 9). |
| `skill_paths <name>` | prints `metadata.polaris.paths` globs, one per line (flow `[a, b]` and block lists both parse); nothing + rc 1 when the skill carries no `metadata.polaris`. |
| `skill_tier <name>` | prints `0` when the flag is `true`, else `1` — the FLAG is the truth; `metadata.polaris.tier` mirrors it. |
| `skill_hits <name> <events>` | prints the count of `"ev":"skill-hit"` lines with `"id":"<name>"` whose `ts` ≥ the ts of the `<events>`-th most recent `"ev":"done"` line (fewer done lines than `<events>` ⇒ all history); second word: the last hit's task ID or `-`. |
| `skill_list` | the `list` body (§ 3). |
| `skill_gaps` | the `gaps` body (§ 3). |
| `skill_budget` | the `budget` body (§ 3); rc 1 over the shelf. |
| `skill_propose <glob> [--name N] [--write] [--force]` | the skeleton (§ 5) + `--write` (§ 5, § 6). |
| `skill_promote <name>` / `skill_demote <name>` | the flag flip (§ 3). |
| `skill_prune [--apply]` | the eviction verdicts (§ 4). |
| `skill_restore <name>` | archive-first, git-history second (§ 4). |
A skill "is POLARIS-written" iff `$PRIMARY/.claude/skills/<name>/SKILL.md` exists and its frontmatter
carries a `metadata:` block with a `polaris:` key. Everything else under `.claude/skills/` is invisible
to every subcommand — `list` never names `polaris` or `i-have-adhd`.

## 3. Output shapes (pinned — the goldens diff them)
`skill list` — one line per skill, name order, then ONE summary line:
```
<name>  tier <0|1> · <b> B · <h>/<W> hits · last <ID|-> · paths <g1>,<g2> · twin <yes|->
<n> skill(s) · shelf <Σ>/1600 B · tier 0: <n0>
```
plus `⚠ tier 0 count <n0> > 24 — archive the dead ones: ops/polaris skill prune` when n0 > 24.
No skill ⇒ the one line `no POLARIS-written skills here — find candidates: ops/polaris skill gaps`. rc 0 always.

`skill gaps` — one line per uncovered candidate, sorted by `n·(1+k)` descending, ties by surface:
```
<surface>  <n>/<2W> tasks · <k> kickbacks · skill: none
```
`n` = done tasks among the last 2W whose `files_owned` overlap the surface (`pat_overlap`, both
directions); `k` = kickback events + `⛔` Notes lines naming a path under it; a surface = an owned path,
or the deepest directory holding ≥ `SKILLS_GAP_MIN` hits when its files share it (`kit/ops/roles/` is
ONE candidate, not six); an `ops/SURFACES.tsv` row's surface glob is a candidate in its own right.
Covered surfaces (any skill's paths overlap) are omitted. Below `SKILLS_GAP_MIN` ⇒ omitted. None ⇒
`no surface reaches 5/80 done tasks — nothing worth a skill yet`. rc 0 always.

`skill budget` — exactly two lines, then rc 1 + a third when over:
```
SKILL_FM_MAX=320 SKILLS_SHELF_MAX=1600 SKILLS_WINDOW=40 SKILLS_GAP_MIN=5 SKILLS_T0_WARN=24
shelf: <Σ> B of 1600 (<n1> tier-1 skill(s)) · tier 0: <n0> (0 B injected)
⛔ shelf over budget by <x> B — demote one: ops/polaris skill demote <name>
```

`skill promote <name>` — refusals (rc 1, nothing written), in this order:
`⛔ no POLARIS-written skill named <name>` ·
`⛔ description still TODO(<glob>) — write the trigger sentence first (≤ 290 chars)` ·
`⛔ <name> frontmatter is <b> B — the per-skill cap is 320` ·
`⛔ shelf would be <Σ+b> B — over 1600; demote one first:` followed by `skill list`'s lines.
Success: the line `disable-model-invocation: true` becomes `disable-model-invocation: false` (the
line STAYS, so demote is a one-line flip back and both counters read the flag either way),
`metadata.polaris` gains/sets `tier: 1`, then
`✅ promoted <name> — <b> B now rides every session in this repo (shelf <Σ>/1600)`.
`skill demote <name>` — the reverse flip, `tier: 0`, `✅ demoted <name> — 0 B injected; /<name> still loads it`.
Already in the requested state ⇒ `<name> is already tier <t>` rc 0, nothing written.

## 4. Telemetry + eviction (the data rule)
Event, ridden by `claim`'s existing board commit (T-156, builder.sh beside `evt claim`):
```
{"ts":<epoch>,"ev":"skill-hit","id":"<skill name>","who":"…","note":"<task ID>"}
```
one per skill whose `skill_paths` overlap the task's `files_owned` (`pat_overlap`, both directions),
emitted INSIDE the mutex — the only telemetry this seam adds. Rule, as data `skill prune` evaluates:
```
W            := SKILLS_WINDOW (40 done events)
hits(s, n)   := skill_hits s n
young(s)     := fewer than W done events with ts_date(ts) ≥ s.since
demote(s)    := tier(s)=1 ∧ ¬young(s) ∧ hits(s, W)=0      → disable-model-invocation: true
archive(s)   := tier(s)=0 ∧ ¬young(s) ∧ hits(s, 2W)=0     → .polaris/skills-archived/<s>/
```
`skill prune` prints one verdict per skill — `keep <s> · <h>/<W>` · `young <s> · <d>/<W> done since <since>` ·
`demote <s> · 0/<W>` · `archive <s> · 0/<2W>` — rc 1 when any demote/archive is due, rc 0 otherwise.
`--apply` performs them on `<base>` only: demote = the flip; archive = `mkdir -p .polaris/skills-archived`
+ `mv .claude/skills/<s> .polaris/skills-archived/<s>` + `git rm -r -q --cached .claude/skills/<s>`
+ a `RESTORE.md` beside it (`slim --apply`'s shape) + the twin, when one exists, moved next to it;
then `nothing was committed for you — review, then: git commit -m "chore(skills): archive <s> — 0 hits in <2W> done"`.
`skill restore <name>`: the archive dir when present (`mv` back, twin included), else
`git log --all --diff-filter=D --format=%H -- .claude/skills/<name>/SKILL.md | head -1` and
`git checkout <sha>^ -- .claude/skills/<name>/` — so a second machine that never held the archive
restores what the first evicted. Refuses when the dir exists. Prints
`✅ restored .claude/skills/<name>/ (from <archive|git <sha7>>) — tier 0, hidden; promote when it earns it`.
Nothing is ever deleted.

## 5. The skeleton (`skill propose`, deterministic over board + brain + index)
Default `--name` = the glob's last path component, kebab-cased, extension dot → `-`
(`ops/tests/api-kit.expected` → `api-kit-expected`; `kit/ops/roles/` → `roles`). Threshold: the glob
must be owned by ≥ `SKILLS_GAP_MIN` of the last 2W done tasks, else rc 1
`⛔ <glob> is owned by <n>/<2W> recent done tasks — below 5; one task's lesson belongs in Learned, not a skill (--force overrides, recorded in evidence:)`.
Frontmatter (exact; `since` = today, the ONLY non-deterministic byte):
```
---
name: <name>
description: TODO(<glob>) — ≤ 290 chars: TRIGGER when …; DO NOT TRIGGER when …
disable-model-invocation: true
metadata:
  polaris: { paths: [<glob>], since: <YYYY-MM-DD>, tier: 0, evidence: "<n>/<2W> tasks · <k> kickbacks" }
---
```
Body — these SEVEN heading lines verbatim (they are `kit/ops/templates/SKILL.md`'s static half, T-158,
and the index's rows for that file), each followed by its producer's output, ≤ 200 lines total:
```
# <glob> — what POLARIS already knows
## What it is                ← the code-map.md entry for the dir(s) + the SURFACES row's note
## Public surface            ← find --api <glob>, ≤ 25 lines
## What keeps going wrong    ← WHOLE Learned/gotchas bullets + kickback notes naming these paths, ≤ 40 lines
## Files that move together  ← learned.md co-change pairs touching these paths
## Tests that cover it       ← SURFACES rows + the verify: lines of the last 3 done tasks here
## Last worked               ← the last 5 done task IDs + titles
```
No brain ⇒ the section body is `(no brain — run: ops/polaris brain)`. The producers are `pack`'s
(WHERE THIS LIVES · PUBLIC SURFACE · KNOWN TRAPS · SURFACES) applied to a surface instead of a task.
Refusals, in THIS order (each rc 1, nothing written — the order is pinned so a lane inside a
`feat/*` worktree can still prove the name checks): (1) reserved name
`⛔ <N> is reserved — polaris, polaris-install, i-have-adhd and polaris-* are managed by update` ·
(2) shadowed name — present under `$(claude_home)/skills/` —
`⛔ <N> exists under ~/.claude/skills/ — a repo skill of that name would be shadowed and never fire` ·
(3) below threshold, unless `--force` (the line above) · (4) `--write` on a `feat/*` branch (§ 1's line) ·
(5) `--write` onto an existing dir `⛔ .claude/skills/<N>/ exists — never overwritten`.
Then `--write` writes the skeleton and prints
`✅ wrote .claude/skills/<N>/SKILL.md (tier 0 · <L> lines · description is TODO — EVOLVE writes it)`.

## 6. The twin (`.claude/rules/<name>.md`) — written ONLY when T-150 recorded `yes`
```
---
paths:
  - "<glob1>"
  - "<glob2>"
---
This surface has a POLARIS skill: `.claude/skills/<name>/SKILL.md` — read it before you change these files.
It records what keeps going wrong here, the public surface and the tests that cover it (`/<name>` loads it too).
```
Same globs as `metadata.polaris.paths`, same lifecycle (written by `propose --write`, moved by archive,
returned by restore). Zero standing cost: a `paths:` rule loads only when a matching file is read.

## 7. Delivery + the rest of the wiring (T-156, SURFACE-FROZEN: no new fn anywhere)
- `pack` (builder.sh): after KNOWN TRAPS and before SURFACES, `pack_section "SKILLS — what POLARIS already knows about these paths"`, one line per POLARIS-written skill whose paths overlap `files_owned`:
  `read: .claude/skills/<name>/SKILL.md · tier <t> · <h>/<W> hits · <L> lines` — the WHOLE section OMITTED when nothing overlaps (pack-visual's golden stays byte-identical).
- `pack_brain_grep` (builder.sh): prints WHOLE bullets — awk paragraph mode over `- ` items, a bullet is emitted when any of its lines matches — ≤ 8 bullets / 40 lines per file (today: 1 line of a 19-line lesson).
- `claim` (builder.sh): the `skill-hit` events (§ 4).
- `slim_scan` (admin.sh): a definition whose frontmatter carries `disable-model-invocation: true` counts 0 B (one awk clause); the rationale block keeps 251 / 34,119 dated and gains `223 / 29,124 / 7,281 tok on 2026-09-14`.
- `uninstall` preview (admin.sh): after the `.claude/output-styles/` line, when n > 0: `<n> skill(s) POLARIS wrote stay — they are this repo's knowledge; rm .claude/skills/<name> by hand`.
- `doctor` (observe.sh, `command -v skill_budget`-guarded): the `⛔ shelf over budget …` line when `skill_budget` is rc 1; `⚠ <n> skill(s) due for eviction — ops/polaris skill prune` when `skill_prune` is rc 1.

## 8. `update` / `uninstall` treat POLARIS-written skills as the repo's own
`update_dirt_overlaps_kit` lists exactly `.claude/skills/polaris/*` and `.claude/skills/i-have-adhd/*`; a
dirty POLARIS-written skill never blocks an update. `install.sh` copies exactly those two dirs. `uninstall`
removes exactly those two. Pinned by the `skill-install` golden: a foreign `.claude/skills/know-x/SKILL.md`
is byte-identical after `install.sh --quiet` and after `uninstall --yes`.

## 9. Executable check (T-159 owns all of it; W3 api-kit owner)
- `ops/tests/skill-budget.{cmd,expected}` — HERMETIC (the triage-lane pattern): a throwaway repo with
  three fixture skills carrying `metadata.polaris` — `fx-hidden` (flag true, 300-B description),
  `fx-small` (flag false, ≤ 320 B), `fx-big` (flag false, 827 B) — asserts `skill budget`'s two lines
  (Σ = small + big), `skill list`'s three lines + summary, `skill propose --name polaris --write` and
  `--name polaris-x --write` each rc 1 on the reserved-name line, `skill promote fx-hidden` rc 1 on the
  TODO line (its description is `TODO(src/x)`), and a fourth promote that would cross 1600 rc 1 on the
  shelf line. No path, timestamp, user or version in the bytes.
- `ops/tests/skill-install.{cmd,expected}` — fixture repo + `.claude/skills/know-x/SKILL.md` →
  `bash kit/ops/install.sh --quiet <fixture>` → `cmp` says identical → `bash <fixture>/ops/polaris uninstall --yes`
  → still identical, dir present.
- `drill_skills` (`kit/ops/lib/selftest/policy.sh`, label `skills` added to `SELFTEST_LABELS` in spine.sh,
  gated after `drill_qa`): a hermetic board with 6 done tasks on `src/search/` and 1 on `src/other/` ⇒
  `gaps` lists only `src/search/`; `propose src/search/ --write` ⇒ the file, TODO in the description,
  the seven headings, flag true; the twin exists iff `plans/self-skills.md` says `yes` (the drill reads
  the probe line and asserts EITHER way); `promote` refuses TODO, passes after the description is
  rewritten, a third promote past 1600 refuses; `claim` of a task owning `src/search/x` writes ONE
  `skill-hit` line; 41 synthetic done events + 0 hits ⇒ `prune` says demote (rc 1), `--apply` flips;
  81 ⇒ archive, the dir moves, `git ls-files` no longer lists it; `restore` ⇒ byte-identical.
  Asserts rc + file bytes, never message text (the sprint-11 lesson).
- `selftest_fast` section `skills` (fast.sh): `skill_consts` values · `skill_bytes` on the three fixture
  frontmatters (0 / ≤320 / 827) · `slim_scan` over a fixture `CLAUDE_CONFIG_DIR` holding the same three
  files reports the SAME three numbers (the one-counter invariant, proven) · `skill_paths` parses flow
  and block lists.

## 10. api-kit rows this seam adds (the owner table is `ops/contracts/key-registry.md` § 9)
W1 (T-155): `kit/ops/lib/skills.sh	fn	<each of the 14 names in § 2>`. W2 (T-158):
`kit/ops/templates/SKILL.md	heading	<the seven § 5 heading texts>`. W3 (T-159):
`kit/ops/lib/selftest/policy.sh	fn	drill_skills`. T-156 adds NO row.

## Invariants
1. Born hidden: `propose` always writes `disable-model-invocation: true`; only `promote` flips it, and only a human's yes runs `promote`.
2. One counter: `skill_bytes` and `slim_scan` implement the same rule; the fast tier proves it.
3. Nothing uninvited: no hook, no SessionStart path, no auto-write, no CONVENTIONS key; `claim`'s `skill-hit` is the only telemetry.
4. Archive, never delete; `restore` works on a machine that never held the archive.
5. `update` / `uninstall` never touch a skill carrying `metadata.polaris`; reserved names are refused, never renamed.
6. The skeleton is deterministic (same board + brain + index ⇒ same bytes, `since:` aside); the description is never generated.
7. Body ≤ 200 lines; tier-1 frontmatter ≤ 320 B; shelf ≤ 1,600 B; window in done events, floor W.
8. Every writer refuses on `feat/*` and commits nothing.
9. The twin exists only if the probe said yes; the census does not change with the answer.

## The probe (T-150 — SK-0, runs FIRST; a top-level session is REQUIRED and this recipe provides one)
A pinned-cwd subagent cannot observe another repo's injected list — but it CAN launch a fresh top-level
session there: `claude -p` from Bash, in a throwaway repo, with `CLAUDECODE` unset (measured 2026-09-14
from inside a session: `PONG`, rc 0). Build the repo, then run three headless sessions and record what
each echoed. The repo (`git init`, commit everything before the first run — the harness scans rules at
session start):
```
.claude/rules/sk0-paths.md     ---\npaths:\n  - "src/probe/**"\n---\nSK0-PATHS-FIRED
.claude/rules/sk0-always.md    SK0-ALWAYS-FIRED           (no frontmatter: the control that proves rules load at all)
src/probe/hello.txt            hello
```
```
A (control, no read):  claude -p 'Do not read any file. Reply with every token in your context that starts with SK0-, one per line, or NONE.' --max-turns 1 --output-format text
B (read):              claude -p 'Use the Read tool on src/probe/hello.txt. Then reply with every token in your context that starts with SK0-, one per line, or NONE.' --max-turns 3 --output-format text --allowedTools Read
C (edit):              claude -p 'Use the Edit tool to append the line "probe" to src/probe/hello.txt. Then reply with every token in your context that starts with SK0-, one per line, or NONE.' --max-turns 3 --output-format text --allowedTools Read,Edit
```
Record, appended under `## Measurements` in `plans/self-skills.md`, one line each, exact keys:
`probe: rules-always-fires: yes|no` (A echoes SK0-ALWAYS) · `probe: rules-paths-fires-on-read: yes|no`
(B echoes SK0-PATHS and A did NOT) · `probe: rules-paths-fires-on-edit: yes|no|unknown` ·
`probe: hidden-skill-absent: yes` (already observed twice — i-have-adhd absent while polaris is present) ·
`probe: nested-dir-prefix: kit:` (observed). Paste the three raw replies under the lines. A `claude -p`
that refuses or hangs (60 s cap) is an honest `unknown`: say so and return the question — never guess.

## Example
```
$ polaris skill gaps
ops/tests/api-kit.expected   21/80 tasks · 2 kickbacks · skill: none
kit/ops/roles/               14/80 tasks · 0 kickbacks · skill: none
$ polaris skill propose ops/tests/api-kit.expected --name api-kit-golden --write
✅ wrote .claude/skills/api-kit-golden/SKILL.md (tier 0 · 96 lines · description is TODO — EVOLVE writes it)
$ polaris skill promote api-kit-golden
⛔ description still TODO(ops/tests/api-kit.expected) — write the trigger sentence first (≤ 290 chars)
```

## Changelog
- v1 2026-09-14: created for T-150, T-155, T-156, T-158, T-159 (plan sprint-c, 6.5.0) from plans/self-skills.md; OPEN-1/3/4 answered by the owner, the rest per the spike's recommendations.
