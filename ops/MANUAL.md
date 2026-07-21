# MANUAL — raw recipes when you cannot run `ops/polaris`
The script is the source of truth; these recipes reproduce it by hand. Follow them LITERALLY. `<base>`, the claim mechanism, and `publish:` come from `ops/CONVENTIONS.md`.

## Board commit by hand — the `polaris/board` ref (EVERY mutation below uses this)
Board state lives on its OWN ref, `refs/heads/polaris/board`, NOT on `<base>`. The MOVED SET —
`ops/board/**` + `ops/SPRINT.md`, at their on-disk paths — is that branch's whole tree; everything
else in `ops/` (`MAP.md`, `contracts/`, `CONVENTIONS.md`, `RULES.tsv`, installed kit files) stays on
`<base>`. Both `ops/board/` and `ops/SPRINT.md` are gitignored on `<base>` (see the lifecycle section),
so board files are moved with plain `mv`, NEVER `git mv`, and committed via a SECONDARY index that
bypasses gitignore. Run in the PRIMARY checkout — never a second worktree, never `git checkout` or a
branch switch; the working tree and the primary index stay untouched:
```bash
board_commit() {   # $1 = subject, e.g. "chore(board): claim T-9"; remaining args = the changed paths
  msg="$1"; shift
  prev=$(git rev-parse -q --verify refs/heads/polaris/board)     # empty on the very first commit
  tmp="$(git rev-parse --git-dir)/polaris-board.index"; rm -f "$tmp"
  export GIT_INDEX_FILE="$tmp"
  [ -n "$prev" ] && git read-tree "$prev" || git read-tree --empty
  git update-index --add --remove -- "$@"      # per changed path; --remove records mv'd-away paths
  tree=$(git write-tree)
  commit=$(git commit-tree "$tree" ${prev:+-p "$prev"} -m "$msg")
  git update-ref refs/heads/polaris/board "$commit"
  unset GIT_INDEX_FILE
}
```
The first commit is parentless (orphan); every later mutation appends exactly one commit; subjects are
unchanged (`chore(board): claim <ID>`, etc.). Contention — another session advanced the ref between
your `rev-parse` and `update-ref` → re-read the tip and retry, bounded.

### Push the board — `sync_board` (NEVER `<base>`)
```bash
git push origin refs/heads/polaris/board:refs/heads/polaris/board
```
On rejection: `git fetch origin polaris/board` → union-append into the on-disk
`ops/board/EVENTS.ndjson` any lines present on the fetched tip but missing locally → re-run
`board_commit` with the parent set to the fetched tip → retry (bounded, 5). Other board files: local
wins (same-machine writers are mutex-serialized by the lock). No EVENTS line is ever lost to a push race.

## Plan commit (Planner) — the moved set and `<base>` files split into TWO commits
A grooming pass usually writes both board state and base-tracked seams. They go to different refs:
- moved set — new/edited task files under `ops/board/**`, `ops/board/EVENTS.ndjson`, `ops/SPRINT.md`
  → ONE `board_commit "chore(board): plan <IDs>" <the changed board paths>` + `sync_board` (polaris/board);
- `ops/contracts/**` and `ops/MAP.md` are NOT in the moved set — commit them normally on `<base>`
  (e.g. `docs(contract): <name>`, `docs(map): …`), a separate commit from the board_commit.
Never stage a contract or MAP change into a `board_commit`, and never `board_commit` on `<base>`.

## Claim (Builder)
**local-lock** — atomic, shared across every worktree of this repo:
```bash
LOCKS="$(git rev-parse --git-common-dir)/polaris-locks"; mkdir -p "$LOCKS"
mkdir "$LOCKS/<ID>" 2>/dev/null && echo claimed || echo "taken — next task"
date +%s > "$LOCKS/<ID>/meta"; echo "<you>@<host>" >> "$LOCKS/<ID>/meta"
```
**claim-branch** — several machines; pure plumbing, touches no working tree:
```bash
sha=$(git commit-tree "<base>^{tree}" -p "<base>" -m "claim <ID> by <you>")
git push origin "$sha:refs/heads/claim/<ID>" --force-with-lease="refs/heads/claim/<ID>:" \
  && echo claimed || echo "taken — next task"        # empty lease = ref must not exist yet
```
Then, in the PRIMARY checkout: `mv ops/board/ready/<ID>.md ops/board/active/<ID>.md` (plain `mv` — the
set is gitignored on `<base>`), set `owner:`/`branch:`/`status:` in its frontmatter, append the claim
telemetry line (Telemetry below), then `board_commit "chore(board): claim <ID>" ops/board/ready/<ID>.md ops/board/active/<ID>.md ops/board/EVENTS.ndjson`
and `sync_board`. Worktree:
```bash
git worktree add .polaris/wt/<ID> -b feat/<ID> <base> && cd .polaris/wt/<ID>
```

## Ownership + RULES proof (Builder, before handoff — mandatory)
```bash
git diff --name-only <base>...HEAD     # run INSIDE your worktree
```
Every path MUST match a `files_owned` pattern (exact · `dir/` prefix · glob). Then, per non-comment line of `ops/RULES.tsv` (TAB-separated `scope · path|content · ERE · message`): no changed path may match a `path` rule's scope, and for each `content` rule, `git diff -U0 <base>...HEAD -- <scope>`'s ADDED lines must not match the ERE. Then run every `verify:` command from the task file; all must exit 0. Stray path, rule hit, or red command → fix or hand back. Never proceed past a violation, and never edit RULES.tsv.

## Handoff (Builder)
Commit everything on `feat/<ID>`. Then, gated on `publish:` in `ops/CONVENTIONS.md`:
- `publish: direct` (default / absent / unknown value) → `git push origin feat/<ID>`.
- `publish: pr` → do NOT push (feat branches never leave the machine); all else identical.
Then, in the PRIMARY checkout: `mv ops/board/active/<ID>.md ops/board/review/<ID>.md` with the
acceptance boxes checked, append the handoff telemetry line, `board_commit "chore(board): handoff <ID>" ops/board/active/<ID>.md ops/board/review/<ID>.md ops/board/EVENTS.ndjson`
+ `sync_board`. **Do not merge; do not release the lock.**

## Release / abort (Builder)
In the PRIMARY checkout: `mv` the task back to `ops/board/ready/` (or `ops/board/blocked/` + a note),
append the release telemetry line, `board_commit "chore(board): release <ID>" <the two task paths> ops/board/EVENTS.ndjson`
+ `sync_board`. Remove the lock (`rm -rf "$LOCKS/<ID>"`, and in claim-branch mode `git push origin :refs/heads/claim/<ID>`). `git worktree remove .polaris/wt/<ID> --force`.

## Grant (Builder) — amend `files_owned` mid-flight, the sanctioned way
What `ops/polaris grant <ID> <path> -m "why"` does by hand. Preconditions — ALL must hold, else STOP and change NOTHING (no partial write, no commit):
- `<ID>` is in `ops/board/active/` — amending unclaimed or finished work is a Planner act, not a grant;
- you have a non-empty reason (`-m "why"`);
- `<path>` overlaps NO `files_owned` entry of ANY other task in `ready/` or `active/`, with the same pattern semantics as the ownership proof above (exact · `dir/` prefix · glob) checked in BOTH directions — a granted `dir/` that swallows another task's exact path refuses just like a path under another task's `dir/`. Any overlap → refuse; chain the tasks (`depends_on`) or hand back instead.
Then ONE `board_commit` (polaris/board — never `<base>`), subject `chore(board): grant <ID> <path>`, over `ops/board/active/<ID>.md` + `ops/board/EVENTS.ndjson`, containing all three edits, then `sync_board`:
1. append `  - <path>` to the task's `files_owned` list (append-only — never remove or rewrite existing entries);
2. append `- grant: <path> — <why>` to the task's Notes;
3. append the telemetry line: `{"ts":<epoch>,"ev":"grant","id":"<ID>","who":"<you@host>","note":"<path>"}`.
RULES.tsv still binds inside granted paths: granting a danger zone does NOT make it writable — rules are checked independently of ownership at write time, verify, and audit.

## Integrate (Integrator) — audit → land-per-task → suite → seal
List `ops/board/review/`, topologically sort by `depends_on` — that is the merge order. On `integrate/<date>` (never on `<base>`), per task in order: audit it (same ownership + RULES proof as above, run against `feat/<ID>` — before ANY merge; a violation kicks the task back, never merges it), then squash-land it (see Land below). Batch mode: run the full suite ONCE after all lands are in. Paranoid mode (suite <2 min): run the full suite after EVERY land.
Suite red → find the offender by halving, not by re-testing every land: `git reset --hard <base>`, re-land the first half of the list, run the suite, recurse into whichever half is red (log₂N runs — one commit per task, no merge topology to fight). Offender found → `git reset --hard HEAD~1` to drop its land, kick it back with the failing output (path:line only), skip anything that `depends_on` it, re-land the survivors, re-run the suite.
**Kickback is a board mutation:** `mv ops/board/review/<ID>.md ops/board/active/<ID>.md`, append the failing output (path:line only) to its Notes, append the kickback telemetry line, `board_commit "chore(board): kickback <ID>" <the two task paths> ops/board/EVENTS.ndjson` + `sync_board` — polaris/board, never `<base>`.
**Before ANY kickback on a red suite, rule out a pre-existing flake.** Re-run the failing test file *in isolation*, and again against `<base>` with none of the sprint's lands applied. Red on `<base>` too, or green on the lone re-run → the flake is the repo's, not the task's: do not kick back, log it in the Learned log instead (and check `ops/CONVENTIONS.md`'s `flaky:` list if it has one). Only a failure that is green on base AND reproducible on the merge is the task's to fix.
Suite green (and `uat:` from CONVENTIONS.md, if set, run once on `integrate/<date>` and green) → `seal` (below).
Then, per landed task (`publish: direct` → right after seal; `publish: pr` → after `seal --sync`): re-run its `verify:` commands on `<base>`, then **`done`**:
- `mv ops/board/review/<ID>.md ops/board/done/<ID>.md`, stamp `landed: <sha>` onto its frontmatter, append the done telemetry line, `board_commit "chore(board): done <ID>" <the two task paths> ops/board/EVENTS.ndjson` + `sync_board`;
- **map_delta is a SEPARATE base commit, not part of the board_commit:** ONLY when the task's `map_delta` is non-empty, append those lines to `ops/MAP.md` and commit on `<base>` as `docs(map): <ID> <first delta line>`. This is the ONLY commit any board mutation ever makes on `<base>`;
- release its lock, `git worktree remove` + delete `feat/<ID>` local AND — `publish: direct` only — remote (`git push origin :refs/heads/feat/<ID>`; under `publish: pr` the feat branch was never pushed, so the remote delete is a no-op — skip it), `git worktree prune`.

## Land (Integrator) — what `ops/polaris land <ID>` does by hand
Inside the PRIMARY checkout, on the `integrate/<date>` branch — NEVER on `<base>` (create `integrate/<date>` first if you're on it). Squashes one reviewed task into exactly one commit.
1. Audit `<ID>`: same ownership + RULES proof as above, run against `feat/<ID>` — before any merge.
2. `git merge --squash feat/<ID>`
   - conflict → `git reset --hard` (restores `integrate/<date>` to its pre-merge tip) → kickback `<ID>` -m "squash conflict — planning bug" → stop, non-zero.
   - empty diff → `git reset --hard` → stop; die, the Integrator decides (no auto-kickback).
3. Write the commit message — by hand, or via the pure helper `ops/polaris task-commit-msg ops/board/review/<ID>.md` (prints only, mutates nothing):
   ```
   <type>(<scope>): <title> [<ID>]

   <Why body>                       # omit block (and its blank line) when empty

   What changed:
   - <acceptance criterion>         # one per checkbox line, "- [ ] "/"- [x] " marker stripped

   Notes:                           # omit block when no qualifying lines
   - <builder note>

   Files: <files_owned, comma-space joined, one line>
   ```
   `type`: feature→feat · bug→fix · test→test · docs→docs · chore/spike/missing→chore. `scope`: the task's `scope:` frontmatter, else the first path component of the first `files_owned` entry.
4. `git commit` with that message plus a trailing blank line and a `Landed-from: <feat/<ID> tip SHA>` trailer.

Land makes NO board write, NO evt, NO board commit — the board stays clean so a red task on `integrate/<date>` unwinds completely with `git reset --hard HEAD~1`, nothing uncommitted lost. `done` stamps `landed: <sha>` onto the task file later, once it moves review → done. Re-land after a kickback simply repeats these four steps.

## Report (Integrator/anyone) — what `ops/polaris report [--sprint <n> | --all]` does by hand
Renders the management-readable per-sprint record from board state; mutates ONLY the report file(s), never the board, never a board commit. Output dir = `reports:` in `ops/CONVENTIONS.md` (default `docs/sprints/`); one file `<reports>/sprint-<n>.md`, regenerated WHOLE each run (idempotent — a later wave overwrites it). No flag = the current sprint (top `# SPRINT <n>` header of `ops/SPRINT.md`).
Resolve the sprint's task IDs, layered, degrade-gracefully: (1) the `[T-…]` bullets of `<base>` first-parent merges whose subject starts `Sprint <n> — `; (2) plus any `done/` task whose `landed:` sha is an ancestor of tag `sprint/<n>` (and not of `sprint/<n-1>` when that tag exists); (3) `--all` → one file per `# SPRINT <n>` header in `ops/SPRINT.md`, and `done/` tasks attributable to no sealed sprint go into the newest sprint's file under an `(unsealed)` marker. Missing data (no tag, no landed sha, no EVENTS line) → omit the field, never die.
File content, ID order, one section per task — byte-stable given the same inputs (NO generation timestamp inside):
```
# Sprint <n> — <goal>            (dates from the SPRINT.md header, when present)
## <ID> — <title>
  points · risk · landed <short-sha> (<date>) · claimed <date> → done <date>
  files touched: git diff-tree --no-commit-id --name-only -r <landed>   (fallback: files_owned)
  ### Why           — the task's `## Why` body, verbatim
  ### Acceptance    — the task's acceptance checkboxes, verbatim
```
Sources: task frontmatter (`done/`, and `review/` at seal time) · `[<ID>]` subject grep on the ref (landed sha) · `ops/board/EVENTS.ndjson` (first claim ts, last done ts). `report` for a past `--sprint <n>` back-fills on any repo with a surviving `done/` + history.

## Seal (Integrator) — what `ops/polaris seal [<date>]` does by hand
Primary checkout, working tree clean, default `<date>` = today. Behavior FORKS on `publish:` in `ops/CONVENTIONS.md` (absent / unknown value → `direct`, warn once). Preconditions are checked FIRST, both modes, before anything mutates: `integrate/<date>` exists · `<base>..integrate/<date>` has ≥1 non-`chore(board):` commit (else die "nothing to seal") · tag `sprint/<n>` is absent OR points to an ancestor of the tip being sealed (an earlier wave's checkpoint — the tag moves after this wave); anything else is a reused sprint number (die "bump the SPRINT.md header").
`<n>` and `<goal>` parse from `ops/SPRINT.md`'s header line `# SPRINT <n> — <goal>` (goal ends at 2+ spaces or `capacity:`; `—` or `-` both accepted).
**Report commit (BOTH modes), after preconditions pass and BEFORE the merge (direct) / the push (pr):** generate the current sprint's report from the wave's KNOWN subjects (see Report; ref = `integrate/<date>`, no membership guessing) and commit it on `integrate/<date>` as `docs(sprint-<n>): report` — it carries NO `[<ID>]` suffix and is ignored by ID resolution.

### `publish: direct` (default) — fold + tag locally
```bash
git checkout <base>
git merge --no-ff "integrate/<date>" -m "Sprint <n> — <goal>

- <subject of each non-chore(board) commit in base..integrate, oldest first>"
git tag sprint/<n>                       # lightweight, on the merge commit
git push origin <base> "sprint/<n>"      # only if a remote exists
```
Merge conflict → `git merge --abort` → die; a human resolves it, never auto-resolve.
Rejected `<base>` push → keep the by-hand note AND add one line: origin may be a protected branch — set `publish: pr` in `ops/CONVENTIONS.md`. (Record the rejection under `.polaris/base-push-rejected`; two or more → `doctor` warns.)
**Sealing the same sprint again (a later wave):** identical merge and message (bullets are naturally the new wave's commits — `<base>..integrate/<date>` excludes prior waves). Then MOVE the tag instead of creating it, and push it compare-and-swap — the only forced ref update POLARIS ever makes, and it is leased:
```bash
git tag -f "sprint/<n>"                  # onto the new merge; log the move (old → new SHA)
git push origin <base>
git push --force-with-lease=refs/tags/sprint/<n>:<old-sha> origin "refs/tags/sprint/<n>"
```
`sprint/<n>` always marks the sprint's latest sealed checkpoint — end of sprint = final checkpoint. `rollback sprint/<n>` reverts the LATEST wave; earlier waves revert by SHA: `git revert --no-edit -m 1 <sha>`.

### `publish: pr` — one host PR per wave, the human merges
NO local merge; `<base>` is untouched (local AND remote); tasks stay in `review/`; locks stay; `integrate/<date>` stays until `seal --sync`. After the report commit:
1. push ONLY `integrate/<date>` to origin (no `<base>`, no tag, nothing else): `git push origin integrate/<date>`.
2. print the PR-create URL + suggested title `Sprint <n> — <goal>` + description (the per-task bullet list the direct merge message would carry). Compose the URL from `git remote get-url origin`; for Bitbucket (`bitbucket.org`, ssh or https):
   `https://bitbucket.org/<workspace>/<repo>/pull-requests/new?source=integrate/<date>&dest=<base>`.
   Non-Bitbucket / unparseable origin → print source (`integrate/<date>`) and dest (`<base>`) and say "open a PR from integrate/<date> into <base> on your host" — never die.
3. fire the `done` notify gate (`notify-gate done`).
The human merges the PR with the host's **MERGE COMMIT** strategy — NEVER squash: the per-task squash commits must survive on `<base>`.
**`seal --sync [<date>]` (pr mode ONLY — in direct mode it dies "publish: direct seals locally — nothing to sync"), by hand, after the human merges:**
1. clean tree required; `git pull --ff-only origin <base>` (never rebase, never merge).
2. verify EVERY `[<ID>]` subject on `integrate/<date>` is now in `<base>` history (`git log <base>`); any missing → die naming them. Step 1 has already fast-forwarded local `<base>`; the tag, `integrate/<date>` and the board are untouched.
3. tag the new `<base>` HEAD per clean-history rules: absent → `git tag sprint/<n>`; existing ancestor tag → move (`git tag -f sprint/<n>`) + compare-and-swap push (`git push --force-with-lease=refs/tags/sprint/<n>:<old-sha> origin refs/tags/sprint/<n>`); existing non-ancestor → die (reused number). Tag-push failure → by-hand note, as direct seal does.
4. delete `integrate/<date>` local + remote: `git branch -D integrate/<date>` and `git push origin :refs/heads/integrate/<date>`.
5. next: per task, `run-verify` / `done` (done's `[<ID>]`-in-base gate now passes) — see Integrate's done recipe.

## Express lane by hand (Integrator) — one small task, one pass
What `ops/polaris land --express <ID>` does by hand: a single ≤2-point task collapses the whole
Integrate → Land → Seal → done pipeline into ONE session, so trivial work stops paying full ceremony.
Opt-in via `express:` in `ops/CONVENTIONS.md`:
```
express: auto               # auto (default; unset = auto) | off (full ceremony always)
# unknown value → warn once, behave as OFF (fail to the full ceremony — the safe side)
```
Primary checkout, ON `<base>`, clean tree. **REFUSE before step 1** — check all four; die on the first
hit and the message MUST contain the quoted fragment:
- `review/` holds any task other than `<ID>`, or `<ID>` is not in `review/` → `express lands exactly one task`
- the task's frontmatter is `risk: high` → `risk: high never rides the express lane`
- CONVENTIONS `express: off` (or an unknown value) → `express: off`
- CONVENTIONS `publish: pr` → `express needs publish: direct`
All four pass → the one pass, reusing the recipes above verbatim (no new git here):
1. create `integrate/<today>` from `<base>`, or reuse it if it already exists.
2. audit + squash-land `<ID>` — the **Land** recipe above, unchanged (audit first; a violation kicks it back, never merges).
3. run the FULL CONVENTIONS suite ONCE — `test:` `lint:` `typecheck:` `build:` (+ `uat:` if set), the same set as **QA** below. Red → `git reset --hard HEAD~1`, kickback `<ID>` with the failing tail (the **Integrate** kickback recipe), then die.
4. seal `<today>` — the **Seal** recipe above (`publish: direct`), unchanged.
5. `run-verify` `<ID>` · `done` `<ID>` (Integrate's done recipe) · delete `integrate/<today>`.
Green → exit 0; the final note still names `ops/polaris qa` (below) as the mandatory finish line.
Express collapses SESSIONS, never checks: audit, RULES, the full suite, seal preconditions, `done`'s
landed-record gate and the final `qa` all run exactly as in the long path. `land <ID>` without
`--express` is byte-identical to the Land recipe above.

## QA — "is everything okay?" by hand
What `ops/polaris qa` does in one shot. From the repo root on `<base>`, run in order: the `test:` `lint:` `typecheck:` `build:` and `uat:` commands from `ops/CONVENTIONS.md` (skip blank keys), then the board-hygiene audit (the per-task ownership + RULES proof from Integrate above) and the env sanity checks. Run EVERY check even after one goes red — one pass paints the whole picture — then report red if anything was. The Integrator runs this before reporting; a Conductor runs it after integration and never takes a subagent's "green" on faith.

## Brain by hand — the generated knowledge base
What `ops/polaris brain` generates by hand: a git-ignored, any-model-readable digest under
`.polaris/brain/` that kills cold-start context re-derivation. It READS the repo and writes nowhere
else — never mutates the board, never touches a git ref, never writes outside `.polaris/brain/` plus
the `.polaris/board-changed` stamp. `.polaris/` is gitignored, so these files are NEVER `git add`ed.
```
ops/polaris brain             # full build: create or overwrite all of .polaris/brain/
ops/polaris brain --refresh   # incremental: board.md/contracts.md/commands.md/gotchas.md always
                              #   rebuilt (cheap — small sources); code-map.md rebuilt ONLY when
                              #   `git diff --name-only <stamp-sha>..HEAD` is non-empty. No brain → full build.
# exit 0 on success
```
Build 7 entries — 6 `.md` files + `.stamp` — under `.polaris/brain/`, each capped, mirroring the CLI (where a source is silent, do as the CLI does — invent nothing):
- `INDEX.md` (≤40 lines) — routing table: one `looking for X → read Y` row per domain file below, plus the hop-guarantee line.
- `code-map.md` (≤15 lines/dir, ≤300 total) — per directory: purpose (1 line) + key symbols (grep `^cmd_` / `^def ` / `^function` / `^class`) + a hotspot flag from `ops/MAP.md`'s hotspot section.
- `board.md` (≤80 lines) — live digest: `# SPRINT <n> — <goal>` line · per-column counts · active (id·owner) · ready top 5 by wsjf (id·title·pts) · blocked (id·reason) · last 10 done (id·title·landed sha).
- `contracts.md` (≤120 lines) — per `ops/contracts/*.md`: `## <name>` + its `## Purpose` first paragraph; no contracts dir → `none`.
- `commands.md` (≤80 lines) — effective CONVENTIONS values (base · claim · integration · publish · express · stale_hours · test · build) FIRST, then `ops/polaris help` output; the cap may cut the help tail, NEVER the values.
- `gotchas.md` (≤60 lines) — SPRINT.md `## Learned` bullets verbatim + CONVENTIONS `## Planner calibration` bullets verbatim.
- `.stamp` (1 line) — machine line `<epoch> <BASE short sha>`, rewritten by every brain run.
`INDEX.md` must state the hop guarantee: any fact is reachable in ≤4 file-opens from `INDEX.md` (INDEX = hop 1, domain file = hop 2, the repo file it cites by path = hops 3–4). Scale by SUMMARIZING PER DIRECTORY, never by listing files; a greenfield repo gets the same 6 `.md` files, near-empty.

**Staleness — the two stamp files, what `doctor` checks.** Freshness rides two stamps: `.polaris/brain/.stamp` (rewritten by every brain run) and `.polaris/board-changed` (an epoch line the board bumps):
- `done <ID>` and `seal` (both publish modes, `--sync` included) `touch` `.polaris/board-changed` AFTER their board/base mutation succeeds — best-effort; a touch failure never fails them.
- `seal` AND `done <ID>` also auto-refresh: after the caller's mutation and its `board-changed` touch, `[ -d .polaris/brain ]` → run `brain --refresh`; a failure prints a `⚠` note and never fails the caller. No brain dir → do nothing. Net effect: the documented wave close (land → seal → run-verify → done) ends FRESH — `doctor` prints no `brain is stale`.
- `doctor`: `[ -d .polaris/brain ]` AND `.polaris/board-changed` newer (`-nt`) than `.polaris/brain/.stamp` → one warn line containing `brain is stale`, naming `ops/polaris brain --refresh`. No brain dir → silent (the feature is opt-in by the first `brain` run).

## Telemetry (every transition above)
Before each `board_commit`, append ONE line to `ops/board/EVENTS.ndjson`:
`{"ts":<epoch>,"ev":"<claim|handoff|release|kickback|done>","id":"<ID>","who":"<you@host>","note":""}`
It rides the moved set onto `polaris/board`. Append-only; the file is union-merged (`.gitattributes`) and `sync_board` union-appends remote-only lines on a push race, so parallel machines never lose a line. Never edit existing lines.

## Board ref lifecycle by hand — fresh install · fresh clone · migrate 5.13→5.14
The by-hand equivalents of what `init-board`, `doctor`/`resume`, and `upgrade` do for the `polaris/board` ref.

**Fresh install (`init-board`):** append `ops/board/` and `ops/SPRINT.md` to `.gitignore`, write the
board files to disk; the ref itself is created by the FIRST `board_commit` (parentless / orphan). No
base commit ever stages the moved set — it is ignored there.

**Fresh clone — materialize the board (`doctor` / `resume`):** when `ops/board/` is missing on disk but
`polaris/board` exists (local; else create the local ref from `origin/polaris/board`), write the moved
set's files from the ref into the working tree WITHOUT a branch switch — read the tree into a secondary
index and `git checkout-index`, or `git show polaris/board:<path> > <path>` per file:
```bash
git rev-parse -q --verify refs/heads/polaris/board \
  || git fetch origin polaris/board:refs/heads/polaris/board
tmp="$(git rev-parse --git-dir)/polaris-board.index"; rm -f "$tmp"
GIT_INDEX_FILE="$tmp" git read-tree refs/heads/polaris/board
GIT_INDEX_FILE="$tmp" git checkout-index -a -f
```
Then say what was materialized.

**Migrate 5.13→5.14 (`upgrade`, idempotent):** runs ONLY when `polaris/board` is ABSENT and the moved
set is still TRACKED on `<base>`. Never rewrites history:
1. orphan-commit the current moved-set state to `polaris/board` (`board_commit` with an empty parent, over every tracked `ops/board/**` + `ops/SPRINT.md` path);
2. `git rm -r --cached ops/board ops/SPRINT.md` on `<base>` (untrack, keep the files on disk);
3. append `ops/board/` + `ops/SPRINT.md` to `.gitignore`;
4. ONE final base commit `chore(board): board moves to polaris/board`.
Re-run = no-op (ref already present). This migration commit is the LAST `chore(board):` subject that ever appears on `<base>`'s first-parent history.

## Kit lifecycle by hand (no `ops/polaris`)
`ops/VERSION` is plain `key: value` text — read it to learn what this repo runs:
```
version: <semver>   commit: <sha>   built: <date>
channel:  <raw URL of ops/VERSION on main>       # what "latest" means
tarball:  <URL of the kit tarball>               # what `update` downloads
```
- **Which version am I on?** `sed -n 's/^version: //p' ops/VERSION`
- **Is there a newer one?** `curl -fsS "$(sed -n 's/^channel: //p' ops/VERSION)" | sed -n 's/^version: //p'` — compare the two semvers. A newer one means the kit is behind; nothing breaks in the meantime.
- **Update by hand:** download the `tarball:`, extract it, and run its `ops/install.sh <this-repo>`. That refreshes kit code only — board, `RULES.tsv`, `CONVENTIONS.md`, `MAP.md`, `SPRINT.md` are never touched. Never do this mid-sprint.
- **The POLARIS section of `CLAUDE.md` is a managed block** between `<!-- POLARIS:BEGIN ... -->` and `<!-- POLARIS:END -->`. An update replaces exactly that block. Put your own rules BELOW the END marker and they survive every update. Never edit inside the block — your edits are overwritten.

## Notes that keep this safe
- Board mutations = `board_commit` on `refs/heads/polaris/board` in the primary checkout ONLY (the sole `<base>` commit any mutation makes is `done`'s `docs(map):` when `map_delta` is non-empty); code = `feat/<ID>` in worktrees ONLY.
- Locks are runtime race-breakers; the task file's `owner:` is the durable record.
- A lock with no matching `active/` or `review/` task is an orphan — safe to remove. A stale active lock is a HUMAN decision.
