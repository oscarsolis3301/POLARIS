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

## Integrate (Integrator)
Audit each review branch: `git diff --name-only <base>...feat/<ID>` ⊆ `files_owned`. Merge all approved branches onto `integrate/<date>` with `--no-ff` in dependency order; ANY conflict = planning bug → abort that merge, kick the task back. Run the full suite ONCE (batch) or per merge (paranoid). Red in batch → halve: reset to `<base>`, re-merge half, test, recurse (log₂N runs). Land: merge integrate into `<base>`, push, re-run each task's `verify:` commands, move tasks to `done/`, append their `map_delta` lines to `ops/MAP.md`, release locks, `git worktree remove` + delete `feat/<ID>` branches, `git worktree prune`.

## Telemetry (every transition above)
Before each board commit, append ONE line to `ops/board/EVENTS.ndjson`:
`{"ts":<epoch>,"ev":"<claim|handoff|release|kickback|done>","id":"<ID>","who":"<you@host>","note":""}`
Append-only; the file is union-merged (`.gitattributes`) so parallel machines never conflict on it. Never edit existing lines.

## Notes that keep this safe
- Board mutations = commits on `<base>` in the primary checkout ONLY; code = `feat/<ID>` in worktrees ONLY.
- Locks are runtime race-breakers; the task file's `owner:` is the durable record.
- A lock with no matching `active/` or `review/` task is an orphan — safe to remove. A stale active lock is a HUMAN decision.
