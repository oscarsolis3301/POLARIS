# The tidy pass, hardened: POLARIS 6.13.0 — plan

## Context
The first real tidy pass, on a practice shop updated from 6.11.0 to 6.12.0 with nobody answering, did
the job: it went from 2.80 to 1.34 folders per change with 25 proven moves, and the tests stayed green.
It also needed 17 workarounds, now recorded as seven IDEAS lines on board ac281c7. Updating the test
repo and the shop showed one more gap: the first update from an older kit never offers the pass.

Left as they are, real owners' passes would:
- pick no guides;
- report a wrong after-score;
- never finish a feature the 25-file cap split;
- strand the session on the integration branch when a seal refuses;
- churn `.claude/settings.json`;
- make every agent hand-write board commits.

This plan fixes each one at its root cause, then proves it with a second live pass.

**Your decisions (asked up front; nothing waits on you mid-run):**
- Add a command that files tasks. The release becomes **6.13.0**.
- Re-run the live tidy pass as the proof.
- You'll sign the command-line Claude in, so the guide probe and the lookup benchmark finally run. If
  sign-in is still missing when the run reaches them, they park.

## What ships

### 1. The engine sees the pass's own work correctly — `kit/ops/index.py`
- **In flight** (`_hops_in_flight`, index.py:1017).
  - It never counts the caller's own task branch, or that worktree's own changes. Today, under
    `POLARIS_ROOT=<worktree>`, `git log --branches --not <base>` includes `feat/<ID>`, so every moved
    file is FIXED.
  - It never counts `feat/<ID>` of a task already in done/, read from the board ref. `done` keeps a
    live worktree's branch for `sweep`.
  - Fixes F1 (no GUIDES rows at step 8) and F5 (after-score said 2.37 → 1.31 when the truth was
    2.80 → 1.34; bare `hops` on main read 2.00 over 22 changes).
- **History** (`_hops_history`, index.py:1185).
  - Under a task worktree it reads HEAD's history.
  - The task's own commits (`<base>..HEAD`) and any commit touching `ops/LAYOUT.tsv` only map
    renames; they never count as a change.
  - Fixes F4. The pass's 31-rename land commit sat under the 40-path skip, welded every feature
    through `src/App.tsx`, and the five leftover search files were never proposed again.
- **`hops --propose`** prints the pass's proposal as plan-file rows: whole clusters only, at most 25
  files. A cluster that doesn't fit waits whole for the next pass. `--due` estimates from the same
  cut (today it uses `[:25]`, index.py:1931). Fixes F6.
- **`--owned`** (`_hops_owned`, index.py:1545) prints a tidy task's WHOLE `files_owned`: today's list,
  plus the exact guides the pass will write (folders with 5+ files after the moves, no guide, first
  8), plus `CLAUDE.md` and `ops/LAYOUT.tsv`. Fixes F12: 8 guide paths owned, 3 written, and the
  `Files:` trailer named 5 that never existed.
- **Purpose reader** (`_hops_purpose`) strips the template's leading `<folder>/ — `. Fixes F10.
- **`--facts`** gains a `leave alone:` line from the folder's FIXED files: generated, vendored,
  RULES/SURFACES-guarded, keep rows, public entry points. Fixes F17.

### 2. The role file says only what works — `kit/ops/roles/TIDY.md` (stays ≤ 90 lines)
- **Step 0:** "tests" means `ops/tests/`. The updater already ran `upgrade`.
- **Step 1:** conductor-entered with no answers → run `hops --questions` read-only, so every unanswered
  item becomes the safe default (F16).
- **Step 3:** `hops --propose`.
- **Step 5:**
  - file the task with `polaris new`;
  - `files_owned` = `hops --owned` exactly;
  - `verify:` = the proof, plus the proving check only when it is `typecheck:` or the harness line.
    `verify` refuses a bare `test:`/`build:` (ownership.sh:56), and the step-8 suite proves the rest
    (F2);
  - one `map_delta` per new folder (F11).
- **Step 6:**
  - at most 5 plan rows per step; importer edits ride along (F8);
  - the files to fix come from `POLARIS_ROOT=<worktree> bash ops/polaris hops --owned <full path of
    the plan>`, run before `git mv`. `_hops_edges` re-indexes the root it is given, so paths are
    current. `find --importers` reads the primary's stale index (F7).
- **Step 7:** `--remap` rc 1 "nothing to remap" is fine when there is no harness (F14).
- **Step 8:**
  - guides = those `--owned` named;
  - `bg run test` from the worktree (F9);
  - "leave alone" filled from `--facts`.

### 3. Guides and the root map stay true — `kit/ops/lib/knowledge.sh`, `kit/ops/lib/observe.sh`
- `guide_purpose` (knowledge.sh:327) strips the same `<folder>/ — ` prefix (F10). The brain's code map
  benefits too.
- `where` (knowledge.sh:670) drops any item whose path no longer exists. It checks against the tracked
  files and folders, read from a temp file, never the environment (Windows' 32 KB cap). Fixes F11:
  the vanished `src/components/` stays out of the root map.
- `drift` warns `MAP STALE: ops/MAP.md lists <path> (missing)`, so EVOLVE's auto-reversible MAP fold
  retires the row. Builders never edit MAP.md (Invariant 1).

### 4. A seal that refuses strands nothing — `kit/ops/lib/integrate.sh`, `kit/ops/lib/builder.sh`
- `seal` with no date, when `integrate/<today>` is absent, uses the ONE unmerged `integrate/<date>`.
  Wave 4 crossed midnight, and `self_land` always calls `seal` with no date.
- `seal`'s early refusals (no header, reused sprint number) return the primary to `<base>` when it sits
  on the wave branch. `land` deliberately leaves it there (integrate.sh:502), and only a good seal
  switches back.
- `self_land` (builder.sh:329) checks the SPRINT header before it lands. If unreadable: no land, the
  task stays in review/, and one remedy line is printed (F3).

### 5. Updates: the first jump offers the pass, with no churn — `kit/ops/install.sh`, `kit/ops/lib/admin.sh`
- `.claude/settings.json` is written with its existing line endings, and not at all when the merge
  changes nothing (install.sh:387, :439; Python text mode turned LF into CRLF on Windows). Fixes F15.
- The new `update` passes a marker env to `install.sh`.
  - `install.sh` run by any updater (`POLARIS_SHA` set: every updater since at least 6.0 does this)
    drops the "finish it with … `upgrade`" hint, because the updater runs `upgrade` itself.
  - Run by an OLDER updater (no marker) on a configured repo, `install.sh` prints the
    `▶ NEXT — save hops` line itself, after heal refreshes the verdict. Today only the new `update`
    prints it, so the first jump never did.
  - A fresh install never prints it: INIT's epilogue keeps winning. Old `--auto` runs log install
    output to `.polaris/update.log`, so their one-line contract holds.

### 6. `polaris new` — file tasks in one command (new module `kit/ops/lib/author.sh` + `kit/ops/polaris` dispatch)
- `bash ops/polaris new <draft.md>…` takes drafts written from `ops/templates/TASK.md` and:
  - assigns the next free T-NNN and writes `id:`;
  - validates: ≤ 5 points, `plan:`, `risk:`, `files_owned`, and the contract exists when named;
  - applies the ready gate (Invariant 2): every `depends_on` done and no overlap with ready/ or
    active/ → `ready/`. Deps pending → `backlog/`;
  - handles review/: a file shared with a task still in review/ adds that ID to `depends_on` and the
    task waits in backlog/. This closes wave 4's lesson that the gate ignored review/;
  - makes ONE race-tested board commit for all drafts, then syncs. One line per task:
    `<ID> ready|backlog — <why>`.
- SOLO step 1, TIDY step 5 and PLANNER all use it. PROTOCOL § THE TOOL lists it. MANUAL.md keeps the
  by-hand recipe for harnesses that cannot run commands. kit/CLAUDE.md is not touched, since every
  byte there is paid in every session.

### 7. Tests
- **hops drill** (`kit/ops/lib/selftest/hops.sh`):
  - a pass on a worktree branch sees GUIDES rows for its new folders;
  - its land commit welds nothing, so the leftover cluster still gets MOVE rows;
  - `--propose` cuts whole clusters;
  - `--owned` names the guides;
  - the purpose prefix is stripped;
  - `--owned` under `POLARIS_ROOT` names importers at their post-move paths.
- **New drill cases:**
  - `new`: IDs, gate, review overlap → depends_on, one board commit, refusals;
  - `seal`: midnight fallback, refusal returns to base, self_land header check;
  - `install`: a no-op merge leaves settings.json byte-identical, CRLF is kept, and the save-hops
    line prints under an old updater only, never on a fresh install;
  - `where`: a vanished row is dropped.
- **Goldens:** cli-help (+ `new`, + `--propose`), cli-help-parity, api-kit, hops-map / hops-due /
  hops-moves, PROTOCOL headings, keys-drift, plain-voice for every new user-facing line.
- CI (serial, three OSes) must be green on the release commit before the tag. Release 6.12.0 learned
  that a sharded green is not a CI green.

### 8. Release 6.13.0
The CONVENTIONS ritual:
1. `kit/ops/VERSION`;
2. CHANGELOG;
3. tag and publish;
4. `pack.py --dogfood`;
5. `polaris version`;
6. the cli-help re-pin;
7. the ten goldens that read the installed `ops/`.

## Verification (end to end)
1. The suite and goldens are green; CI is green on the release commit before the tag; the dogfood
   self-test passes.
2. **Probe** (save-hops § 9), after your sign-in: 7 headless sessions. The answers are recorded in
   this plan's `## Measurements`. Any answer that contradicts PROTOCOL § SAVE HOPS gets that claim
   corrected. Still signed out → recorded as unknown and parked.
3. **The live proof:**
   1. Build a fresh `hops_fixture`. Install 6.12.0 (cached kit, fake HOME) with a full INIT-shaped
      setup: CONVENTIONS, MAP, the SPRINT header, a board.
   2. Run `update` → 6.13.0, and check two things: the `▶ NEXT — save hops` line prints on that first
      jump, and there is zero settings.json churn.
   3. Benchmark before: `bash ops/bench.sh hops <shop>`, 5 headless runs.
   4. One TIDY session, nobody answering. It must need NONE of the 17 workarounds:
      - guides come from `--owned`;
      - the after-score matches a clean-clone measure;
      - no branch is stranded;
      - the root map has no vanished folder and no doubled names.
   5. Then `hops --tsv` on main proposes the leftover cluster.
   6. Benchmark after: 5 runs, and total turns must be lower than before.
4. **Test repo:** 6.12.0 → 6.13.0, nothing due, committed under the `POLARIS <old> → <new>` rule.
5. The final `finish` exits 0.

## How it runs after you approve
- This chat is the CONDUCTOR. A PLANNER subagent carves the tasks with disjoint `files_owned`, and
  `plan_gate` is auto. It also writes the contracts first: amendments to `ops/contracts/save-hops.md`,
  and a new contract for `new`.
- Likely waves:
  - **W1:** engine A (§1 in-flight + history), seal (§4), update path (§5), knowledge/drift (§3),
    `new` (§6);
  - **W2:** engine B (§1 propose/owned/purpose/facts), TIDY/SOLO/PLANNER/PROTOCOL/MANUAL docs, the
    probe;
  - **W3:** drills + goldens;
  - **W4:** release.
- Nothing waits on you mid-run (no `risk: high` is expected). The approval covers commits and pushes,
  with plain messages and no attribution.
- The budget is 360 min. A budget stop closes cleanly and "continue" resumes it.
- This plan is saved to `plans/tidy-hardening.md`.
