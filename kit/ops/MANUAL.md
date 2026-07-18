# MANUAL — raw recipes when you cannot run `ops/polaris`
The script is the source of truth; these recipes reproduce it by hand. Follow them LITERALLY. `<base>` and the claim mechanism come from `ops/CONVENTIONS.md`.

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
Then, in the PRIMARY checkout on `<base>`: `git mv ops/board/ready/<ID>.md ops/board/active/<ID>.md`, set `owner:`/`branch:`/`status:` in its frontmatter, commit `chore(board): claim <ID>`, push (on rejection: `git pull --rebase` and retry — board files are disjoint, it merges clean; on `index.lock`, wait 2s and retry). Worktree:
```bash
git worktree add .polaris/wt/<ID> -b feat/<ID> <base> && cd .polaris/wt/<ID>
```

## Ownership + RULES proof (Builder, before handoff — mandatory)
```bash
git diff --name-only <base>...HEAD     # run INSIDE your worktree
```
Every path MUST match a `files_owned` pattern (exact · `dir/` prefix · glob). Then, per non-comment line of `ops/RULES.tsv` (TAB-separated `scope · path|content · ERE · message`): no changed path may match a `path` rule's scope, and for each `content` rule, `git diff -U0 <base>...HEAD -- <scope>`'s ADDED lines must not match the ERE. Then run every `verify:` command from the task file; all must exit 0. Stray path, rule hit, or red command → fix or hand back. Never proceed past a violation, and never edit RULES.tsv.

## Handoff (Builder)
Commit everything on `feat/<ID>`, push it, then board commit on `<base>` in the primary checkout: move `active/<ID>.md` → `review/<ID>.md`, acceptance boxes checked. **Do not merge; do not release the lock.**

## Release / abort (Builder)
Board commit: task back to `ready/` (or `blocked/` + note). Remove the lock (`rm -rf "$LOCKS/<ID>"`, and in claim-branch mode `git push origin :refs/heads/claim/<ID>`). `git worktree remove .polaris/wt/<ID> --force`.

## Grant (Builder) — amend `files_owned` mid-flight, the sanctioned way
What `ops/polaris grant <ID> <path> -m "why"` does by hand. Preconditions — ALL must hold, else STOP and change NOTHING (no partial write, no commit):
- `<ID>` is in `ops/board/active/` — amending unclaimed or finished work is a Planner act, not a grant;
- you have a non-empty reason (`-m "why"`);
- `<path>` overlaps NO `files_owned` entry of ANY other task in `ready/` or `active/`, with the same pattern semantics as the ownership proof above (exact · `dir/` prefix · glob) checked in BOTH directions — a granted `dir/` that swallows another task's exact path refuses just like a path under another task's `dir/`. Any overlap → refuse; chain the tasks (`depends_on`) or hand back instead.
Then ONE board commit on `<base>` in the primary checkout, `chore(board): grant <ID> <path>`, containing all three edits:
1. append `  - <path>` to the task's `files_owned` list (append-only — never remove or rewrite existing entries);
2. append `- grant: <path> — <why>` to the task's Notes;
3. append the telemetry line: `{"ts":<epoch>,"ev":"grant","id":"<ID>","who":"<you@host>","note":"<path>"}`.
RULES.tsv still binds inside granted paths: granting a danger zone does NOT make it writable — rules are checked independently of ownership at write time, verify, and audit.

## Integrate (Integrator) — audit → land-per-task → suite → seal
List `ops/board/review/`, topologically sort by `depends_on` — that is the merge order. On `integrate/<date>` (never on `<base>`), per task in order: audit it (same ownership + RULES proof as above, run against `feat/<ID>` — before ANY merge; a violation kicks the task back, never merges it), then squash-land it (see Land below). Batch mode: run the full suite ONCE after all lands are in. Paranoid mode (suite <2 min): run the full suite after EVERY land.
Suite red → find the offender by halving, not by re-testing every land: `git reset --hard <base>`, re-land the first half of the list, run the suite, recurse into whichever half is red (log₂N runs — one commit per task, no merge topology to fight). Offender found → `git reset --hard HEAD~1` to drop its land, kick it back with the failing output (path:line only), skip anything that `depends_on` it, re-land the survivors, re-run the suite.
**Before ANY kickback on a red suite, rule out a pre-existing flake.** Re-run the failing test file *in isolation*, and again against `<base>` with none of the sprint's lands applied. Red on `<base>` too, or green on the lone re-run → the flake is the repo's, not the task's: do not kick back, log it in the Learned log instead (and check `ops/CONVENTIONS.md`'s `flaky:` list if it has one). Only a failure that is green on base AND reproducible on the merge is the task's to fix.
Suite green (and `uat:` from CONVENTIONS.md, if set, run once on `integrate/<date>` and green) → `seal` (below). Then, per landed task on `<base>`: re-run its `verify:` commands, move it to `done/`, append its `map_delta` lines to `ops/MAP.md`, release its lock, `git worktree remove` + delete `feat/<ID>` — local AND remote (`git push origin :refs/heads/feat/<ID>`; handoff pushed it, and landed tasks must not pile up as stale branches on the host) — `git worktree prune`.

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
   `type`: feature→feat · bug→fix · chore/spike/missing→chore. `scope`: the task's `scope:` frontmatter, else the first path component of the first `files_owned` entry.
4. `git commit` with that message plus a trailing blank line and a `Landed-from: <feat/<ID> tip SHA>` trailer.

Land makes NO board write, NO evt, NO board commit — the board stays clean so a red task on `integrate/<date>` unwinds completely with `git reset --hard HEAD~1`, nothing uncommitted lost. `done` stamps `landed: <sha>` onto the task file later, once it moves review → done. Re-land after a kickback simply repeats these four steps.

## Seal (Integrator) — what `ops/polaris seal [<date>]` does by hand
Primary checkout, working tree clean, default `<date>` = today. Folds a sprint's `integrate/<date>` into `<base>` as one tagged merge.
Preconditions (else stop, nothing mutated): `integrate/<date>` exists · `<base>..integrate/<date>` has ≥1 non-`chore(board):` commit (else die "nothing to seal") · tag `sprint/<n>` is absent OR points to an ancestor of `<base>` (an earlier wave's checkpoint — the tag moves after this merge); anything else is a reused sprint number (die "bump the SPRINT.md header").
```bash
git checkout <base>
git merge --no-ff "integrate/<date>" -m "Sprint <n> — <goal>

- <subject of each non-chore(board) commit in base..integrate, oldest first>"
git tag sprint/<n>                       # lightweight, on the merge commit
git push origin <base> "sprint/<n>"      # only if a remote exists
```
`<n>` and `<goal>` parse from `ops/SPRINT.md`'s header line `# SPRINT <n> — <goal>` (goal ends at 2+ spaces or `capacity:`; `—` or `-` both accepted). Merge conflict → `git merge --abort` → die; a human resolves it, never auto-resolve.
**Sealing the same sprint again (a later integration wave):** identical merge and message (bullets are naturally the new wave's commits — `<base>..integrate/<date>` excludes prior waves). Then MOVE the tag instead of creating it, and push it compare-and-swap — the only forced ref update POLARIS ever makes, and it is leased:
```bash
git tag -f "sprint/<n>"                  # onto the new merge; log the move (old → new SHA)
git push origin <base>
git push --force-with-lease=refs/tags/sprint/<n>:<old-sha> origin "refs/tags/sprint/<n>"
```
`sprint/<n>` always marks the sprint's latest sealed checkpoint — end of sprint = final checkpoint. `rollback sprint/<n>` reverts the LATEST wave; earlier waves revert by SHA: `git revert --no-edit -m 1 <sha>`.

## QA — "is everything okay?" by hand
What `ops/polaris qa` does in one shot. From the repo root on `<base>`, run in order: the `test:` `lint:` `typecheck:` `build:` and `uat:` commands from `ops/CONVENTIONS.md` (skip blank keys), then the board-hygiene audit (the per-task ownership + RULES proof from Integrate above) and the env sanity checks. Run EVERY check even after one goes red — one pass paints the whole picture — then report red if anything was. The Integrator runs this before reporting; a Conductor runs it after integration and never takes a subagent's "green" on faith.

## Telemetry (every transition above)
Before each board commit, append ONE line to `ops/board/EVENTS.ndjson`:
`{"ts":<epoch>,"ev":"<claim|handoff|release|kickback|done>","id":"<ID>","who":"<you@host>","note":""}`
Append-only; the file is union-merged (`.gitattributes`) so parallel machines never conflict on it. Never edit existing lines.

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
- Board mutations = commits on `<base>` in the primary checkout ONLY; code = `feat/<ID>` in worktrees ONLY.
- Locks are runtime race-breakers; the task file's `owner:` is the durable record.
- A lock with no matching `active/` or `review/` task is an orphan — safe to remove. A stale active lock is a HUMAN decision.
