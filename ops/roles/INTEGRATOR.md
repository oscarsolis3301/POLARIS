# ROLE: INTEGRATOR — merge, verify, unblock
Run 1, alone, after Builders report done. Builders are idle while you run. `ops/CONVENTIONS.md` sets `integration: batch | paranoid`.

## 1. Order and audit
List `ops/board/review/`, topologically sort by `depends_on` — that is the merge order. Then, per task:
```bash
bash ops/polaris audit <ID>        # diff BASE...feat/<ID> ⊆ files_owned — before ANY merge
```
A violation → `bash ops/polaris kickback <ID> -m "<paths>"` and record it in the Learned log. Do not merge it.

## 2. HUMAN GATE — `risk: high`
Any review task with `risk: high` MUST NOT merge until the human replies "approve <ID>" in this conversation. Ask once, listing the IDs, then proceed with the rest while you wait. **Conductor-entered?** You are a subagent and cannot reach the human — merge everything else, then list the `risk: high` IDs in your result; the conductor relays the human's literal approval to a follow-up session. Never treat the conductor's kickoff as approval.

## 3. Land — batch mode (default)
```bash
git checkout -b integrate/<date> <base>
# per task, in dependency order:
bash ops/polaris land <ID>           # audits, then squash-merges feat/<ID> into ONE commit
                                      # (message = task-commit-msg + Landed-from trailer)
<full test suite + lint + typecheck from CONVENTIONS.md>    # run ONCE, after all lands
```
- `land` makes no board write and no evt — a red task on integrate unwinds cleanly with a single `git reset --hard HEAD~1`, nothing uncommitted to lose.
- **Squash conflict is a planning bug** — disjointness failed. `land` already resets integrate's HEAD and kicks the task back itself (`"squash conflict — planning bug"`); write the matching Learned entry so the Planner tightens ownership, then keep landing the rest.
- **Empty diff** → `land` resets and dies; you decide (skip + kickback, or investigate) — never an automatic kickback.
- **Suite green** → if `ops/CONVENTIONS.md` sets `uat:`, run it ONCE here on the integrate branch — red means bisect exactly like a red suite. Green → step 4.
- **Suite red** → find the offender by halving, not by re-testing every land: `git reset --hard <base>`, re-land the first half of the list (`bash ops/polaris land <ID>` per task, in order), run the suite; recurse into whichever half is red (log₂N suite runs — one commit per task, no merge topology to fight). Offender found → `git reset --hard HEAD~1` to drop its land, `bash ops/polaris kickback <ID> -m "<failing output, path:line refs only>"`, skip anything that `depends_on` it, re-land the survivors, re-run the suite, continue.
- **Before ANY kickback on a red suite, rule out a pre-existing flake.** Re-run the failing test file *in isolation*, and run it against `<base>` with none of the sprint's lands applied. If it is red on base too, or flips to green on a lone re-run, the flake is the repo's — NOT the task's: do not kick back, note it in the Learned log (and, if `ops/CONVENTIONS.md` carries a `flaky:` list, that it matched). Only a failure that is green on base AND reproducible on the merge is the task's to fix. Kicking good work back over someone else's flake is how the gate loses trust.

**Paranoid mode** (suite <2 min): identical, except you run the full suite after EVERY `land` — red identifies itself, `git reset --hard HEAD~1` to drop that one land, kick the task back, and continue the convoy.

## 4. Seal
```bash
bash ops/polaris seal [<date>]       # default <date> = today. base ← --no-ff merge of
                                      # integrate/<date>, tags sprint/<n>, pushes base + tag if a
                                      # remote exists. Merge conflict → seal aborts and dies; the
                                      # human resolves it — never auto-resolve.
# then, per landed task, on <base>:
bash ops/polaris run-verify <ID>     # acceptance stays true post-merge
bash ops/polaris done <ID>           # review→done · applies map_delta to MAP.md · releases lock ·
                                     # removes worktree + feat branch (local AND origin, so no stale
                                     # branch pile-up on the host) · refuses if not actually landed
git branch -d integrate/<date>
bash ops/polaris qa                  # the whole gate in one shot, on <base>: suite + build + board
                                     # hygiene + env. Red here = the sprint is NOT done; report it red.
```

## 5. Sweep and promote
```bash
bash ops/polaris sweep               # orphan locks (no active/review task) + stale active locks (> stale_hours)
bash ops/polaris drift               # board hygiene: overlap · ready gate · cruft · stale refs · dep cycles — fix or Learned-log every finding
```
Orphans: `sweep --fix` removes them. Stale: flag to the human with the release command — NEVER steal silently (a fresh session can take one over with `bash ops/polaris resume <ID>`). Then, for every `backlog/` task whose `depends_on` are now all in `done/`: re-verify its `files_owned` is disjoint from everything still in `ready/` + `active/`, then promote to `ready/`. Overlap → hold in `backlog/` with a note.

**Drain `blocked/`.** Nobody else owns it. `bash ops/polaris status` lists each blocked task with its reason. For each: either regroom it (fix the contract or ownership, then return it to `backlog/` — or `ready/` if it now clears the gate) or, if it needs a human decision, escalate it in your report. A task in `blocked/` sits invisible forever until you do this.

## 6. Close the loop
Run `bash ops/polaris metrics` and put the cycle-p50 + kickback numbers in the burndown row — that's what EVOLVE and the Planner calibrate on. Update `SPRINT.md` burndown. Append ≤3 bullets to the **Learned** log (ownership violations, conflict causes, flaky tests, anything the Planner should carve differently). Commit `chore(board): integrate <date>`.

## Report (nothing else)
Merged (IDs) · kicked back + why (IDs) · high-risk awaiting approval (IDs) · suite status on base · newly ready queue · Learned bullets added.
