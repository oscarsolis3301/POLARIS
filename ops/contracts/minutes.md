# CONTRACT: minutes — proof runs where it is fast, and a release check proves bytes   (v2.7 — 2026-11-09)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Measured 2026-11-09 (plans/minutes.md): the full self-test takes 166 s on CI's Linux runner and 13–37
minutes on this Windows machine; the release check then repeats it for another 37 minutes. This
contract moves the self-test's verdict to CI, keeps the goldens local and parallel, and replaces the
release check's self-test with a byte comparison. Phase 1 = § 1 and § 2. Later phases append.

## 1. The release check proves bytes — `kit/ops/pack.py`
### 1.1 `_build_entries()` (private: no new public name, so api-kit does not move)
The loop that builds `entries` in the packer (the `git ls-files -s` walk, the `archive/` skip, the LF
normalisation of text, the `commit:`/`built:` stamp appended to `ops/VERSION`, and the root
`__main__.py` taken from `kit/ops/bootstrap.py`) moves into ONE function:
```
_build_entries() -> (entries, execs)      # entries: [(path, blob, is_exec)], execs: [path]
```
The packer calls it and writes the zip exactly as today: for the same commit the output zip is
byte-identical to today's (the golden pins that with a sha256 before/after the refactor, taken in the
builder's own session — not in the golden).

### 1.2 `dogfood()` — order of work
dirty check → read `want` + url → download → `zip_version` check → version equality check (all four
unchanged, same texts) → **byte check** → install (unchanged) → **quick check** → closing lines.
- The url: `POLARIS_DOGFOOD_ZIP` when that environment variable is set and non-empty (a test seam:
  any url `urllib` opens, e.g. `file:///…`), otherwise the `zip:` field as today.
- **Byte check.** `got` = every member of the downloaded zip as `{name: bytes}`. `exp` = from
  `_build_entries()`: `__main__.py` keeps its name, every other path becomes `polaris-v5/<path>`.
  Compare the two name sets, then the bytes of each name in sorted order. One exemption:
  `polaris-v5/ops/VERSION` is compared after removing, on both sides, every line that starts with
  `commit: ` or `built: `. First difference → `sys.exit` with exactly:
  ```
  ⛔ the published kit is not this commit's kit — <name> differs. Repo untouched.
     Dogfood from the commit the tag points at, or publish again.
  ```
  (`<name>` = the first differing or one-sided member, sorted order.) Before it, print:
  `   proving the bytes:  the published kit against this commit`
- **Quick check.** Print `   proving the board still works:  ops/polaris doctor --fast` and run
  `[bash, "ops/polaris", "doctor", "--fast"]` in the repo. Non-zero → `sys.exit` with exactly:
  ```
  ⛔ <got> installs, but FAILS its quick check here. Do not ship it — this is
     exactly the bug --dogfood exists to catch. Undo with: git checkout -- .
  ```
- **Closing line** (replaces today's ✅ line; the "review, then commit" listing after it is unchanged):
  `✅ POLARIS <got> installed from the published release — same bytes CI proved, and the quick check passes.`
- **`--dogfood --full`**: skips nothing above, and runs today's `doctor --selftest` INSTEAD of the
  quick check, with today's two texts (the "proving the board still works:  ops/polaris doctor
  --selftest" line and today's ✅ and ⛔ lines), byte for byte.

### 1.3 Executable check — golden `dogfood-bytes`
Hermetic: a `git clone` of this repo at HEAD into a temp dir, `core.autocrlf=false`, fake HOME **and**
USERPROFILE. In the clone: `python kit/ops/pack.py` builds the zip; then, each on a fresh copy of the
clone, with `POLARIS_DOGFOOD_ZIP` pointing at a `file://` url:
1. the zip as built → rc 0, the closing line, the clone's `ops/VERSION` equals `kit/ops/VERSION`'s version;
2. the same zip with ONE byte changed in one member other than `ops/VERSION` → rc ≠ 0, the ⛔ byte
   line naming that member, and `git status --porcelain` in the clone is empty (nothing installed);
3. the zip as built, dogfooded after one extra commit that touches only a file outside `kit/` → rc 0
   (the stamp exemption).
The golden prints verdict lines only (no timings, no temp paths).

## 2. CI is the self-test's judge — `tools/proof.sh` (this repo's own tool; never shipped in the kit)
`bash tools/proof.sh` proves ONE commit, HEAD, with two halves that overlap in time.
### 2.1 The run
1. `sha` = `git rev-parse HEAD`, `s7` = its first 7 characters, `br` = `proof/<first 12 of sha>`.
2. **CI half — find or start.** `$GH run list --workflow ci.yml --commit "$sha" --json databaseId --jq '.[0].databaseId'`
   - an id → reuse it; say `proof: <s7> — CI run <id> (found)`.
   - none → delete every OTHER remote `proof/*` branch (`git ls-remote --heads origin 'proof/*'`,
     `git push -q origin --delete <name>`, failures ignored); `git push -q origin "$sha:refs/heads/$br"`;
     `$GH workflow run ci.yml --ref "$br"`; poll the listing every `PROOF_FIND_POLL` s (default 5),
     at most 90 s, until an id appears; say `proof: <s7> — CI run <id> (started)`.
3. **Goldens half, meanwhile.** Run `$PROOF_GOLDENS` when set; otherwise every golden, 12 at a time:
   each name from `ops/tests/*.cmd` through `bash kit/ops/polaris check --only <name>`, its output and
   exit code kept per name in a temp dir. Say `proof: goldens — <n> green`, or
   `proof: goldens — <k> red: <names, space-separated>` followed by each red golden's output.
4. **Wait for Linux.** Poll `$GH run view <id> --json jobs` every `PROOF_POLL` s (default 15) for the
   job named `ubuntu-latest`, at most 20 minutes. Say `proof: linux — green`, or `proof: linux — RED`
   followed by the last 40 lines of `$GH run view <id> --log-failed`, or
   `proof: linux — no answer after 20 minutes` (counts red).
5. Write `.polaris/ci-proof` = `<sha> <id>` (one line). Close with `✅ proof: <s7> green` and rc 0 when
   both halves are green, else `⛔ proof: <s7> red` and rc 1. Other CI jobs (`macos-latest`,
   `windows-latest`, `one version, everywhere`) are never read here: the version job is expected red
   whenever `kit/ops/VERSION` is ahead of the newest tag.
### 2.2 No CI
`$GH` missing, `$GH auth status` failing, no `origin` remote, a failed push or dispatch, or no run id
within 90 s → say `proof: no CI here (<reason>) — running the self-test on this machine` and run
`bash kit/ops/polaris doctor --selftest --parallel 3` as the first half; the goldens half and the
closing lines are unchanged; `.polaris/ci-proof` is not written.
### 2.3 Flags
- `--await <job>`: needs `.polaris/ci-proof` naming HEAD's sha, else
  `⛔ proof: no recorded run for <s7> — run tools/proof.sh first` and rc 1. Polls that job as in step 4
  and says `proof: <job> — green` (rc 0), `proof: <job> — RED` (rc 1) or the 20-minute line (rc 1).
- `--report`: one line per job of the recorded run, `<name>: <status> <conclusion>`; rc 0.
### 2.4 Seams and limits
`GH="${PROOF_GH:-gh}"`. bash 3.2-safe (no `case` inside `$(...)`, no `${v,,}`, no `wait -n`, no
arrays). No `sleep` longer than the poll interval. Never touches the primary's branch or index; the
only refs it writes are remote `proof/*` branches.
### 2.5 Executable check — golden `proof-ci`
A scratch repo with a bare `origin`, a stub `gh` first on PATH (reads its answers from files), and
`PROOF_GOLDENS` set to a stub, so the golden never recurses into the real goldens:
found-run green · started-run green (asserts the `proof/…` branch was pushed and an older `proof/*`
branch deleted) · red Linux job (rc 1, the log tail printed) · red goldens (rc 1) · no `gh` (the
fallback line; `PROOF_SELFTEST` stubs the self-test command) · `--await macos-latest` green and red ·
`--await` with no state file · `--report`.

## Phase 2 — the speed release, 6.14.0 (sprint 22, plan `minutes`)
Every section below is one task. **Rules for all of them** (plans/minutes.md "Rules every builder…"):
bash 3.2 (no `case` inside `$(...)`, no `${v,,}`, no `wait -n`, no arrays, no `mapfile`); one awk
beats a loop, never fork per line or per item; tests fake HOME **and** USERPROFILE and never touch the
real `~/.claude`; verify lines use `bash kit/ops/polaris …` (the installed `ops/` is 6.13.0 until the
dogfood); never edit `kit/ops/polaris` or `kit/ops/lib/*.sh` in the primary while a suite runs.
**Names.** In wave 2 only § 9 (G) adds public function names and only G re-pins
`ops/tests/api-kit.expected`; § 6, § 7 and § 8 add `_private` names only and change NO markdown
heading text in `kit/` (api-kit pins headings too). **Voice.** Every new user-facing line below is
plain: no task IDs, and no "suite", "merge", "branch", "worktree", "seal" or "repo" unless the line
already had the word.

## 3. M — `observe.sh` becomes five modules, move-only (wave 1)
### 3.1 What moves where (top-level functions, each with the comment block directly above it)
| new file `kit/ops/lib/…` | functions, in this order |
|---|---|
| `drift.sh` | `pat_overlap` `rules_gate` `dep_ids` `dep_reaches` `cmd_drift` `cmd_rules` `surfaces_health` `cmd_surfaces` `surfaces_apply` |
| `check.sh` | `scaffold_try` `scaffold_dirs` `harness_testdir` `harness_stack` `harness_write_python` `harness_write_node` `harness_baseline` `cmd_harness` `cmd_scaffold` `cmd_check` |
| `route.sh` | `cmd_triage` `cmd_route` `depth_line_say` `uat_deferred_say` `cmd_depth` |
| `qa.sh` | `cmd_qa` `cmd_finish` |
| `observe.sh` keeps | `cmd_notify_gate` `status_brief` `cmd_status` `cmd_board_fm` `feat_tip_landed` `cruft_clear` `cmd_sweep` `cmd_doctor` `cmd_metrics` `metrics_depth_lines` `cmd_why` `cmd_dash` `find_claude` `find_claude_windows` `cmd_fleet` |

Each new file opens with a 2–4 line `#` header naming what it holds and pointing here; nothing else is
new. Bodies are untouched byte for byte; nothing executes at source time.
### 3.2 The loader (`kit/ops/polaris`)
The FULL-load list becomes, literally (words added on the existing lines — the entry gains no line):
`core ownership workspace surfaces visual builder integrate knowledge search observe drift check route qa admin bg awake handover skills author`
followed by the selftest words, unchanged. `_match|_rules|_guard` stays EXACTLY `core ownership`. Both
lists stay LITERAL, never a glob. The header comment that counts modules ("source all 15 lib modules")
says 19.
### 3.3 The move proof — `tools/fnmove.sh` (this repo's own tool, new, never shipped)
`bash tools/fnmove.sh <rev>:<path>… -- <path>…` — the left side is read with `git show`, the right
side from disk. A **function** is a column-0 line matching `^[A-Za-z_][A-Za-z0-9_]*\(\) *\{`; its
**body** runs from that line through the first later column-0 line that is exactly `}` — or is that
line alone when it matches `; *\} *$` (a one-liner, e.g. `uat_deferred_say`). Comments above a
function are not part of it. ONE `LC_ALL=C awk` per side emits `name<TAB>body` (newlines in the body
written as the two characters `\n`), then `LC_ALL=C sort`, then the two sorted lists are compared.
- equal → `fnmove: <n> functions, same names and bodies (list <first 7 of git hash-object of the sorted list>)`, rc 0
- not equal → `fnmove: DIFFERS`, then one line per difference — `- <name>` (left only, or body
  changed) and `+ <name>` (right only, or body changed) — sorted, rc 1.

bash 3.2-safe; temp files only inside one `mktemp -d`, removed on exit.
### 3.4 Golden `lib-census` (new, M's)
Prints, for `kit/ops/lib/` `observe.sh drift.sh check.sh route.sh qa.sh` in that order, one line
`<basename> <name>` per top-level function (the § 3.3 definition) whose name does not start with `_`,
in file order. It pins which public function lives in which module from now on; a later task that adds
a `_private` helper never moves it.
### 3.5 What else moves with the code
`ops/tests/api-kit.expected`: rows change file only (same row count, same names, re-sorted as the
indexer sorts). `ops/tests/triage-lane.cmd` line 41 greps `kit/ops/lib/route.sh` instead of
`observe.sh` (its .expected unchanged). `ops/contracts/module-layout.md` v9 is the placement authority.

## 4. C — the knowledge base rebuilds in one pass (wave 1, `kit/ops/lib/knowledge.sh`)
### 4.1 `brain_code_map` — same line shapes, one pass
Header line unchanged. Then per folder: a blank line, `## <dir>/`, `- files: <n> (<ext> <ext> <ext>)`
(no parenthesis when no file has an extension), `- purpose: <text>` (only when found),
`- symbols: <names>` (only when any), `- hotspot: <path> — chain edits, never parallel-own (ops/MAP.md)`
(only when MAP lists one). The root folder prints as `## ./`.
- **Inputs:** ONE `git -C "$PRIMARY" ls-files -z`; ONE symbol grep over all of those files
  (`xargs -0 grep -HIE` with today's pattern, run from `$PRIMARY`); ONE `LC_ALL=C` awk that reads the
  file list, the grep output and the MAP hotspot list and prints every folder. Purposes still come
  from `guide_purpose` (folder has a `CLAUDE.md`), then the first README heading — read only for
  folders that have one, computed before the awk (one call per such folder, never per file).
- **Ordering, pinned:** folders in C byte order; extensions: top three by count, ties by extension
  ascending (C order); symbols: today's name rule (the sed chain), unique, C byte order, first twelve;
  hotspot: the first MAP hotspot path directly in that folder, in MAP order.
### 4.2 Atomic writes
Every file the brain writes under `.polaris/brain/` goes to `<name>.tmp.$$` in the same folder, then
`mv -f` onto `<name>`; a failed write removes the temp file and leaves the old file in place.
### 4.3 Executable check — golden `brain-codemap`
Hermetic scratch repo (fake HOME and USERPROFILE) built by `hops_fixture` from
`kit/ops/lib/selftest/hops.sh` (sourced, read-only — the practice shop `hops-pass` uses), plus one
folder with a `CLAUDE.md` guide, one with a `README.md`, one with two extensions tied and one with more
than twelve symbols. It runs `bash "$KIT" brain --refresh` and prints `.polaris/brain/code-map.md`
verbatim, then `brain files: <n>` (`*.md` count there) and `temp files left: <n>` (must be 0).
The `brain` drill (`kit/ops/lib/selftest/brain.sh`) stays green, edited only where it pinned the old
tie order. Targets (acceptance, timed by hand and noted): under 3 s on the shop, under 10 s here.

## 5. F — one update covers the PC (wave 1, `kit/ops/lib/admin.sh`)
### 5.1 Self-commit
After `update` (typed) or `update --auto` applies a new version in a project, it commits when ALL hold:
HEAD is on `<base>` (a branch, not detached); no merge, rebase, cherry-pick or revert in progress
(`MERGE_HEAD`, `rebase-merge/`, `rebase-apply/`, `CHERRY_PICK_HEAD`, `REVERT_HEAD` in the git dir);
`git diff --cached --quiet` was true BEFORE the update ran; `cfg publish` is not `pr`.
- It stages exactly the paths the update changed that were clean before it (`git status --porcelain`
  read once before and once after; a path dirty before is never staged — it is parked or left alone
  exactly as today) and commits with subject `chore(polaris): POLARIS <old> → <new>`, no body, no
  attribution. Never pushes. Nothing changed → no commit, no line.
- On commit, the note `review the diff, then commit ops/ — nothing was committed for you` is replaced by
  `committed for you: chore(polaris): POLARIS <old> → <new> — <k> files, not pushed`.
- Any condition false → today's note, unchanged, then one note naming the first false condition:
  `not committed: <reason>`, `<reason>` one of `not on <base>` · `a merge or rebase is in progress` ·
  `something was already staged` · `publish: pr — the change goes through a pull request`.
- `--auto`'s one pinned line is unchanged; its commit adds no line.
### 5.2 Fan-out
A typed `update` with none of `--auto`, `--all`, `--repo-only` ends — after its own output and its
self-commit — by counting the machine registry's other projects (the `repos/*` entries `--all` walks,
minus this one). `<n>` = 0 → nothing. Otherwise it starts `bash "$SELF" update --all` detached, the way
`bg run` detaches (a background subshell, stdin from /dev/null, no nohup/setsid), appending to
`<awake_home>/update-all.log` (`~/.claude/polaris/update-all.log` by default), and prints one note:
`updating <n> other projects on this PC in the background — see <log>`. `POLARIS_UPDATE_NO_FANOUT=1`
skips it silently (test seam). `--all` keeps its rules (quiet boards only, one line per project) and
each project it updates self-commits by § 5.1. `--auto` never fans out.
### 5.3 `speed` shows landing time
From `EVENTS.ndjson`: the last 20 tasks (by `done` time) that have a `claim`, a `handoff` and a `done`.
build = the last `handoff` ts before the `done` − the last `claim` ts before that handoff; built → done
= `done` ts − that `handoff` ts. Median of each (sorted ascending, element `int((n-1)/2)`, zero-based),
in whole minutes rounded to nearest. Two lines, printed directly after the `Of your last …` line and
before any `→` line: `build: median <m> min` and `built → done: median <m> min`. No such task →
neither line. ONE awk.
### 5.4 Homes and checks
`ops/contracts/auto-update.md` v4 restates § 5.1–5.2. No new CONVENTIONS key. Drill `autoupdate`
(`kit/ops/lib/selftest/remote.sh`) gains: self-commit on base (one commit, that subject, clean tree
after); refused on a feature branch, with staged work, and under `publish: pr` (the `not committed:`
note, no new commit); the fan-out line with a 2-entry fake registry and the launched command stubbed;
`--auto` never fans out. Golden `speed-report` re-pinned for the two lines (a fixture EVENTS log with
known times). `install-update` stays green (re-pinned only if its fixture's update now commits).

## 6. A — goldens run side by side (wave 2, `kit/ops/lib/check.sh`, `tools/proof.sh`)
- `check [--only <glob>] [--update] [--jobs <N>]`. N: the `--jobs` value, else `POLARIS_CHECK_JOBS`,
  else cores (first non-empty of `getconf _NPROCESSORS_ONLN`, `nproc`, `sysctl -n hw.ncpu`, else 4);
  capped at 12, floored at 1. Not a number → `check: --jobs takes a number` via `die`.
- `--update`, N = 1, or one selected golden → today's serial loop, byte for byte, no new line.
- Otherwise N workers, each a background subshell running its share one after another. Shares are
  dealt longest-first from `.polaris/check-times` (`<name> <seconds>` per line; unknown = 20) by ONE
  awk call (round-robin over the descending list). Then `wait` for all — no `wait -n`, no arrays.
- Each golden's stdout and rc go to files in one `mktemp -d`; after `wait`, results print in today's
  order with today's exact lines, and the closing summary and rc are today's.
- A golden red beside others is re-run once alone (after all workers end) before it counts. Green
  alone → it counts green, and directly after its result line comes:
  `   note: <name> passed alone but not beside others — it shares state with another golden`
- `.polaris/check-times` is rewritten after every run, parallel or serial, for each golden that ran.
- `tools/proof.sh` § 2.1 step 3's default becomes ONE `bash kit/ops/polaris check` call, its output
  read for the green/red names exactly as the per-name loop's was; `PROOF_GOLDENS` stays as the seam.
- Golden `check-parallel`: scratch repo, six tiny goldens (one red, one with a `.rc`, two that append
  start/end epoch times to a log and sleep 1 s); `--jobs 3` and `--jobs 1` print identical output
  (`same output: yes`); the logged intervals overlap under 3 (`overlap at 3: yes`) and never under 1
  (`overlap at 1: no`); a seventh golden, red only while another is running, shows the note line.
  The help text for `--jobs` is G's (§ 9.4).

## 7. D — the end of a run never stalls or pays twice (wave 2)
- **Housekeeping is advice.** In `cmd_drift` the two doc-overflow findings become notes, same
  thresholds, never counted, exactly like `advisory: MAP STALE:`:
  `   advisory: MAP: <n> delta lines — fold them into the sections (EVOLVE target)` and
  `   advisory: LEARNED: <n> bullets — prune to ≤5 carry-overs (EVOLVE target)`.
  They never turn `drift --strict`, `qa` or `finish` red and never withhold `.polaris/suite-stamp`.
  Golden `qa-stamp` is re-pinned (its two hard-gate cases become green with the advisory line).
- **Verify once.** A green `verify` writes `.polaris/verify-stamp/<ID>` (under the PRIMARY's
  `.polaris/`) = the worktree's HEAD sha. `handoff` skips re-running the verify COMMANDS when that stamp
  equals HEAD and `git status --porcelain` in the worktree is empty, printing
  `verify: proven at <sha7> — not re-run`; ownership, rules, surfaces and freshness gates still run.
  `run-verify <ID>` skips when `git rev-parse HEAD^{tree}` equals `git rev-parse feat/<ID>^{tree}`,
  printing `run-verify: same tree the builder proved — not re-run` (rc 0).
- **A self-landed lane ends clean.** Golden `self-land-finish`: scratch repo, `landing: self`,
  claim → edit → handoff → `finish` exits 0 with no manual `sweep`. Fix whatever makes it red.
- **The route drill, carried for § 8.** `kit/ops/lib/selftest/policy.sh`'s "ROUTE QUIET FAIL" check
  becomes: `route --points 5 --risk normal` with no knobs prints exactly 3 lines (tier, model, effort),
  message `ROUTE NOTES FAIL (the default route prints the tier, then model, then effort)`. D owns that
  file this wave; § 8 never touches it; both land in the same wave.
- **INTEGRATOR.md:** section 3 no longer tells anyone to type `git checkout -b` (`land` creates the
  wave branch); every wait says `bg wait --max 120`; the wave gate is the tasks' verify lines, and the
  full proof (`bg run` of CONVENTIONS `test:`) runs in the background after the seal and never blocks
  the next wave; a red background proof becomes a fix task before `finish`. No heading text changes.

## 8. E — helpers are sized by the kit (wave 2)
- `route` line 1 unchanged. Then, unless dropped, always `   model: <name>` then `   effort: <level>`,
  then the existing REFUSED / role notes in today's order.
- **Defaults in code** (`route.sh`, a `_private` helper): cheap → `sonnet` / `low`; mid → `opus` /
  `medium`; strong → `opus` / `high`. `model_<tier>` (existing keys) and `effort_<tier>` (new keys) in
  CONVENTIONS override; the value `inherit` drops that note. A task's literal `model:` still wins for the
  model note. `model_denied` is untouched: a forbidden name is never printed — the REFUSED note runs as
  today and the model note is dropped (never swapped for the default). Defaults never name Fable or
  Haiku. `model_for_tier` (core.sh) is not edited; `fleet` is unchanged.
- **Effort clamp.** When `CLAUDE_CODE_SESSION_ID` is set and
  `$HOME/.claude/polaris/model-state/$CLAUDE_CODE_SESSION_ID.effort` holds a known level, the effort
  note is the lower of the two in `low < medium < high < xhigh < max`. An unknown value is ignored.
- **KEYS.tsv:** rows `effort_strong`, `effort_mid`, `effort_cheap` (since `6.14.0`, defaults `high`,
  `medium`, `low`); the three `model_*` rows' default column becomes `opus`, `opus`, `sonnet`, with
  plain cost text. Goldens `route-tier` and `keys-drift` re-pinned; `route-tier` fakes HOME and
  USERPROFILE and unsets `CLAUDE_CODE_SESSION_ID` except in its clamp case.
- **CONDUCTOR.md:** every spawn passes route's two notes as the spawn's `model` and `effort` (a dropped
  note → that parameter omitted). A kicked-back task is retried one effort level higher (cap `max`).
  EVOLVE is spawned only when the run had a kickback, a blocked task, a red proof or more than five
  Learned bullets; otherwise one line: `EVOLVE skipped — nothing to learn from this run`.
- **PLANNER.md (kit):** verify lines name the narrowest proof; `doctor --fast` only for tasks that change
  the CLI entry or its lib (`kit/ops/polaris`, `kit/ops/lib/` here); never a check `handoff` already runs.
- **EVOLVE.md:** states the skip rule in one sentence.
- **PROTOCOL.md:** § MODEL ROUTING states the defaults and the two notes; § LONG COMMANDS says
  `bg wait --max 120`. `plain-voice` stays green. No heading text changes.
- `ops/contracts/model-routing.md` v4 restates this section. The help text for the notes is G's (§ 9.4).

## 9. G — one call in, one call out (wave 2, new `kit/ops/lib/flow.sh`)
### 9.1 `polaris begin <draft.md>` — `cmd_begin`
`cmd_new <draft>` (output printed as is) → the new ID read from it → `cmd_triage <ID>` → line 1 must be
`solo`; otherwise print triage's whole answer, then
`begin: <ID> needs the <lane> lane, not solo — it waits in ready/ for the conductor` and exit 3 (the task
stays in ready/). Then `cmd_claim <ID>` → `cmd_pack <ID>`. Any step's failure exits with its rc.
### 9.2 `polaris wrap [<ID>]` — `cmd_wrap`
From the task's worktree (the ID defaults as `handoff`'s does): `cmd_handoff <ID>` → when
`cfg landing` is `integrator` and the task triages `solo`, `land --express <ID>` run from the primary →
`cmd_next`. When next's line 1 is `finish`, run `cmd_finish` and exit with its code; otherwise print
next's answer and exit 0. Both only call existing commands in order; no gate changes.
### 9.3 Wiring
Loader: `flow` after `author` (`… skills author flow`, then the selftest words). Dispatch arms `begin)`
and `wrap)` beside `new)`. `kit/ops/polaris` stays under 500 lines. SOLO.md uses `begin` and `wrap`;
BUILDER.md drops the separate `verify` before `handoff` (handoff runs it). api-kit gains the rows for
`cmd_begin` and `cmd_wrap` (and for any heading G changes); `cli-help-parity` adds `begin` and `wrap`
to its list (expected `14`). `module-layout.md` v9 lists flow.sh.
### 9.4 Help lines, byte-exact (G writes all of them)
Directly after the `new <draft.md>…` block:
```
  begin <draft.md>               ONE CALL IN: new → triage → claim → pack. A task whose lane is
                                 not solo stays in ready/ and triage's answer is printed (rc 3)
  wrap [ID]                      ONE CALL OUT, from the task's worktree: handoff → land --express
                                 (landing: integrator, solo task) → next; runs finish when next
                                 says finish, and exits with its code
```
The `check` usage line becomes `  check [--only <glob>] [--update] [--jobs <N>]`, and after its last
description line (the one ending `in ops/CONVENTIONS.md`) two lines follow:
```
                                 side by side: --jobs <N> goldens at once (default = this PC's
                                 cores, at most 12; POLARIS_CHECK_JOBS overrides), same output as --jobs 1
```
The `route` block becomes:
```
  route [<ID> | --role <R> | --points <N> [--risk <R>]]
                                 which MODEL TIER runs a piece of work — line 1 is always one
                                 word: strong | mid | cheap (a task's model: frontmatter
                                 overrides; unknown role → mid, routing never blocks work). Then
                                 `   model: <name>` and `   effort: <level>` for the spawn (cheap
                                 sonnet/low · mid opus/medium · strong opus/high; model_<tier> and
                                 effort_<tier> in ops/CONVENTIONS.md override, inherit drops the
                                 note). Read-only: the CONDUCTOR asks it before every spawn; fleet
                                 rides the max tier over ready/
```
### 9.5 Golden `flow-solo`
Scratch repo (fake HOME and USERPROFILE, `landing: integrator`): `begin <draft>` (a 1-point draft),
then from the worktree `pack` printed an edit and `wrap` → the task is in `done/` and `finish` exited 0;
a 5-point draft → rc 3, the `begin:` line, the task still in ready/.

## 10. R — release 6.14.0 (wave 3, `kit/ops/VERSION`, `CHANGELOG.md`)
`version: 6.14.0` and a plain-language CHANGELOG entry at the top, no task IDs: the goldens run side by
side, a wave no longer waits on the full proof, helpers are sized to the task, the knowledge base
rebuilds in one pass, one update covers the PC and commits itself, `begin` and `wrap`, housekeeping
never blocks the end of a run. The ritual after it (tag, publish, dogfood, `update --all`) is the
conductor's.

## 11. Riders from the 6.13.0 live proof and the carve (conductor, 2026-11-09)
Three small additions, each inside files its task already owns or was given here.
### 11.1 T-275 (F) — heal's model line follows the sizing (`kit/ops/lib/admin.sh`, golden `heal-model-line`)
Why: once `route` names a model and an effort (§ 8), a project CLAUDE.md that still says "never name a
model" overrides CONDUCTOR.md there and silently switches the sizing off.
- ONE target line, `T`:
  `- **Size every helper** — pass the model and effort \`route\` prints on each spawn; Haiku is blocked, and Fable runs only when the owner picks it.`
- THREE source lines. Each is replaced by `T` when it is a whole line of the root CLAUDE.md (LF or CRLF,
  its line ending kept, the first occurrence only, every other byte unchanged; a file holding none of
  them is not written):
  - A `- **Never name a model.** Fable and Haiku are forbidden outright; every spawn inherits the session.`
  - B `- **Never name a model.** Every spawn inherits the session; Haiku is blocked, and Fable runs only when the owner picks it.`
  - C `- **Never name a model** — every spawn inherits the session.`
- The block heal appends on a first heal prints `T` where it printed C.
- The note, once per heal that changed the file:
  `healed: CLAUDE.md — the model line now says helpers are sized by route (your prose untouched)`
- T-275 owns and re-pins `ops/tests/heal-model-line.cmd` and `.expected`: A, B and C each become `T` · a
  hand-edited line is left alone · a second heal changes nothing.
### 11.2 T-277 (D) — `finish` clears merged wave branches itself (`kit/ops/lib/qa.sh`)
Where `cmd_finish` printed the caveat `<branch> is merged but the branch is still here — git branch -d <branch>`,
it now deletes that branch (`git -C "$PRIMARY" branch -d <branch>`, which refuses an unmerged one) and
prints `   cleaned: <branch> (merged)`. Only when the delete fails does today's caveat print, unchanged.
The `self-land-finish` golden asserts that no `integrate/*` branch is left after `finish`.
INTEGRATOR.md § 4 loses its by-hand `git branch -d` step.
### 11.3 T-279 (G) — three wording fixes in `kit/ops/roles/TIDY.md` (now one of T-279's files; ≤ 90 lines, same four headings)
- Step 8, the layout record: APPEND to `ops/LAYOUT.tsv`; create it, with exactly that first line, only
  when it is missing — never overwrite it (the 6.13.0 proof overwrote an existing keep row).
- Steps 5–6: say once that `.polaris/hops-plan.tsv`, named by that relative path from the task
  worktree, is the primary's file.
- Report: the guides figure is `<guided>/<busy folders>` before and after, each with its own denominator.
No command in the role file changes.

## 12. The verify stamp proves what was proven (conductor, 2026-11-09 — corrects § 7)
§ 7 let `run-verify` skip on tree equality alone. That is unsound: the same tree says nothing about
whether a green verify ever ran on it, or whether the verify list is still the one that ran. CI caught
it at the `express` drill, which edits the list to a failing line and requires `land --express` to die
(`EXPRESS VERIFY RED FAIL`). The stamp now carries both facts, and both skips require both.
- **The stamp.** `.polaris/verify-stamp/<ID>` in the primary, ONE line: `<sha> <listsum>`.
  `<sha>` = the worktree HEAD a green `verify` ran on (unchanged: only a clean tree is stamped, and a
  dirty run removes the stamp). `<listsum>` = `cksum` of the task's verify list exactly as
  `fm_list verify <taskfile>` prints it, written `<crc>-<bytes>` (cksum's two numbers joined by `-`).
- **`handoff`** skips the verify commands only when ALL hold: the stamp's sha equals HEAD · the stamp's
  listsum equals the listsum of the task file's verify list NOW · the worktree is clean. Its line is
  unchanged: `verify: proven at <sha7> — not re-run`.
- **`run-verify <ID>`** skips only when ALL hold: `HEAD^{tree}` equals `feat/<ID>^{tree}` ·
  `git diff --quiet HEAD` · a stamp exists whose sha equals `git rev-parse feat/<ID>` · its listsum
  equals the listsum of the task file's verify list NOW. Its line is unchanged. Anything missing — no
  stamp, a one-field stamp, a changed list, a moved branch — and the commands run.
- `amend` keeps deleting the stamp. `done` now deletes it too (best-effort) once the task is in done/.
- **An empty verify list is never "proven" (v2.4).** A task with no verify commands behaves exactly as
  it did before this release, in `verify`, `handoff` and `run-verify` alike: `run_verify_cmds` runs and
  prints its `   no verify: commands on task (acceptance is manual)` line, NO stamp is written (an
  existing one is removed), and neither "not re-run" line is ever printed. Three goldens that pin
  `handoff`'s output for such tasks caught the regression: `guide-stale`, `pack-visual`,
  `shots-gallery` — they must pass UNCHANGED. Golden `verify-stamp` gains case (8): an empty list →
  the manual-acceptance line, no stamp file, no proven line, for handoff and for run-verify.
- **Executable check.** Golden `verify-stamp` (new): (1) a green verify → the stamp is
  `<HEAD sha> <crc>-<bytes>` · (2) handoff after it prints the proven line · (3) the verify list edited
  by hand after the stamp → handoff runs the commands again (no proven line) and refuses when the new
  line fails · (4) run-verify on a same-tree land with a matching stamp → the skip line · (5) same
  tree, NO stamp → the commands run · (6) same tree and stamp, the list edited to a failing line →
  run-verify exits non-zero and prints the failing output · (7) `done` removes the stamp.
  `self-land-finish` is re-pinned for the two-field stamp (its "stamp names the commit" check reads
  field 1). The `express` drill passes again, run once by hand through `bg run`.

## 13. The update's commit stages one step at a time (conductor, 2026-11-09 — corrects § 5.1)
§ 5.1's staging ran `git status --porcelain | awk … | git add --pathspec-from-file=-` as ONE pipeline. All
three run at the same moment, and both git commands want `.git/index.lock`: `status` holds it while it
looks for changes, and `add` takes it first thing and dies if it is held, before it reads one path.
Whichever starts faster wins. macOS CI lost it in three runs of three (`AUTOUPDATE (5b) COMMIT DIRT FAIL`
twice, `AUTOUPDATE (9) COMMIT FAIL` once; the log shows awk's "i/o error occurred while closing
/dev/stdout", its reader already gone, then `nothing was committed for you`). The fallback was safe, so
no repo was harmed: the update simply did not commit, and said nothing about why.
- **One after the other.** The list is computed FIRST into a variable (the same status + awk, byte for
  byte), and only then handed to `git add` (`printf '%s\n' "$list" | git … add --pathspec-from-file=-`).
  An empty list → no `add`, no commit, no line (unchanged). No pipeline in the kit may have a
  `git status` feeding a command that writes the index.
- **Another program holding the lock** (an editor's git view, a second terminal): when the `add` or the
  `commit` fails and git's message names `index.lock`, wait 1 second and try again, 3 tries in all.
  Any other failure is not retried.
- **Never silent.** When staging or the commit still fails: the index is left empty as found
  (unchanged), today's note prints, then one more note says why, from git's own first line:
  `not committed: git could not stage the update's files — <first line of git's message>` or
  `not committed: git refused the commit — <first line of git's message>`. `--auto` stays one line.
- **The drill asserts the commit where it expects one.** In `drill_autoupdate`, every case whose update
  applies with all § 5.1 conditions true — at least (5), (5b), (7), (9); (1) too when its fixture meets
  them — FIRST checks that HEAD is exactly one new commit on top of where that case started and that
  its subject is `chore(polaris): POLARIS <old> → <new>` (`AUTOUPDATE (<n>) COMMIT FAIL (…)`), and only
  then checks what is in it. (5) and (5b) used to check only that a dirty path was absent from HEAD's
  commit, which fails for the wrong reason when no commit was made.
- **Executable checks** (same drill, two new cases; a `git` stand-in placed first on PATH that passes
  everything to the real git except `add` with `--pathspec-from-file=-`): **(10)** the stand-in refuses
  the FIRST such add with git's lock message on stderr and exit 128, without reading its input → the
  update still commits (one new commit, the `committed for you` note). **(10b)** it refuses EVERY such
  add → no commit, HEAD unchanged, nothing staged, the update's files still changed in the tree, both
  notes printed (`nothing was committed for you`, then `not committed: git could not stage the update's
  files — …`), rc 0. The stand-in is a plain `sh` script found by name; it never touches the real git
  or any config, and the real git's path is resolved before PATH is changed.
- Proof: the drill green on CI's Linux AND macOS runs of the task's own commit (`PROOF_GOLDENS=true bash
  tools/proof.sh`, then `bash tools/proof.sh --await macos-latest`), each started once by hand through
  `bg run`. One green macOS run is the bar: three of three were red before.

## 14. `wrap` ends green from the task's own folder (conductor, 2026-11-09 — corrects § 7 and § 9.2)
Found by a fresh-install test of 6.14.0 before its release. § 9.2 has `wrap` run from the task's
worktree, and there the command that is running IS the worktree's own copy of `ops/polaris`. § 7 quiets
a landed lane's beat so the next clear-up may take its worktree — but a worktree is never removed from
under the command standing in it (worktree-liveness v1.2), so it is LEFT, its branch stays with it,
`drift` then counts that branch as a leftover, and the `finish` that `wrap` runs exits 1 with
`CRUFT: feat/<ID> still exists though <ID> is done`. Every `wrap` typed the documented way ended red
(golden `flow-solo` did not see it: it runs the kit by an absolute path from outside its fixture).
- **Standing in it = still here.** A done task's worktree that the running command stands in — the two
  tests of `wt_remove`'s first guard, `$SELF` inside it or `$PWD` inside it — is treated exactly like a
  live beat: `drift` says nothing about its branch, so `qa` and `finish` are not red for it.
  The two tests move, unchanged, into ONE private helper in `workspace.sh`, `_wt_stood_in <ID>`
  (rc 0 = the running command stands in it; it also tells `wt_remove` which of its two notes applies),
  used by `wt_remove` and by `drift`'s leftover check. `wt_remove`'s output does not change by a byte.
- **finish says what is left, and that there is nothing to do.** For such a worktree, finish's caveat
  `worktree .polaris/wt/<ID> has no active task — bash ops/polaris sweep --fix` reads instead
  `worktree .polaris/wt/<ID> is where this command ran from — the next finish from the project folder clears it`.
  It stays a caveat (rc 0; something was left behind), never a pending item.
- **It does clear.** The next `finish`, `qa` or `sweep --fix` run from anywhere else removes the
  worktree and its branch (today's `cruft_clear`, unchanged).
- **Golden `wrap-own-folder`** (new): a throwaway repo with the kit INSTALLED in it, so the fixture runs
  its own `ops/polaris` and never a path outside itself; default landing (no `landing:` line).
  `begin` a 1-point draft → one commit in the worktree → `bash ops/polaris wrap` typed from inside that
  worktree → rc 0, finish's `✅ finish: run complete` line, the task in done/, its file on main, the new
  caveat exactly once, and no line starting `⛔`. Then `bash ops/polaris finish` from the project
  folder → rc 0, the worktree folder gone, `feat/<ID>` gone, no caveat about it. HOME and USERPROFILE
  faked together; nothing printed carries a sha, a time, or a path outside the fixture.
- Unchanged and still green: `flow-solo`, `self-land-finish`, `finish-blocked`, `drift-deps`, and the
  drills that cover drift, finish, self-landing and worktree liveness (CI's Linux run of the task's own
  commit, once, by hand: `PROOF_GOLDENS=true bash tools/proof.sh`).

## 15. `check --only` takes a list (conductor, 2026-11-09 — extends § 6; ships in 6.15.0)
Since § 7 a task's own verify list is the whole gate at handoff and again at landing, and such a list
often names several goldens, one `check --only <name>` line each. Each line is its own `check`, so
they run one after another: T-286's five took 8 minutes here, T-223's twelve take about 12, while the
same goldens side by side take about 2. `--only` only ever took ONE glob, so a list could not ask for
its goldens together.
- **`--only <glob>[,<glob>…]`.** The value is split on commas; a golden is selected when its name
  matches ANY of the globs. Order of the globs never matters: selection, deal-out and printing follow
  the directory order exactly as today. One glob with no comma behaves byte for byte as today.
- **Every glob must match something.** A glob that selects no golden is red, with today's line for a
  named check that ran nothing, naming that glob — a typo in a list never passes silently. Empty
  entries (`a,,b`, a trailing comma) are a usage error.
- Two or more goldens selected → side by side under the § 6 rules (jobs, the alone re-run, output in
  today's order). `--update` with a list stays serial, as today.
- No new key, no new public function name, and the help line is unchanged in this task (the command
  table moves at the next dogfood with everything else); `kit/ops/roles/PLANNER.md` tells the planner
  to put a task's goldens on ONE verify line: `bash kit/ops/polaris check --only a,b,c`.
- Golden `check-parallel` gains the cases: a two-name list selects exactly those two and prints them
  in directory order; `b,a` prints the same as `a,b`; a list with one unknown name is red and names
  it; a one-name value prints exactly what it prints today.

## Changelog
- v1 2026-11-09: created for the Phase 1 tasks of plans/minutes.md.
- v2 2026-11-09: § 3–§ 10 added for Phase 2 (sprint 22, plan minutes, 6.14.0).
- v2.1 2026-11-09 (conductor): § 11 — three riders (heal's model line, finish clears merged wave branches, TIDY.md wording).
- v2.2 2026-11-09 (conductor): § 9 — the `begin:` refusal line reads "needs the <lane> lane" ("is a express lane" was not English).
- v2.3 2026-11-09 (conductor): § 12 — the verify stamp carries the verify list's checksum, and run-verify needs the stamp; § 7's tree-only skip was unsound (CI: EXPRESS VERIFY RED FAIL).
- v2.4 2026-11-09 (conductor): § 12 — an empty verify list is never "proven" (goldens guide-stale, pack-visual, shots-gallery caught it).
- v2.5 2026-11-09 (conductor): § 13 — the update's commit stages one step at a time, retries a held index lock, and says why when it cannot commit (macOS CI: the status and the add in one pipeline raced for the index lock).
- v2.6 2026-11-09 (conductor): § 14 — `wrap` typed from the task's own folder ends green: a worktree the running command stands in counts as still in use, and finish says the next finish clears it (found by a fresh-install test).
- v2.7 2026-11-09 (conductor): § 15 — `check --only` takes a comma list, so a task's goldens run side by side on one verify line.
