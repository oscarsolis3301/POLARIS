# CONTRACT: worktree-liveness            (v1 — 2026-09-01)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/v2.md` WS1 + WS5 (plan slug `cant-eat-itself`, POLARIS 6.2.0). Tasks: T-092 (workspace.sh
primitives) · T-093 (hook beat touches + guard verbs — see shared-checkout.md v2.5) · T-097 (core.sh lock
meta + steals) · T-098 (builder.sh beats, resume gate, release) · T-099 (integrate.sh done) · T-100
(observe.sh sweep + orphan grace) · T-103 (uninstall die) · T-104 (drills `wtreap` + selfland assert) ·
T-096 (KEYS row, MANUAL recipes, PROTOCOL row — the W1 api-kit owner).

## Purpose
No session removes a worktree it cannot prove dead. A sibling's seal fan-out ran `done ARC-428`, which
`git worktree remove --force`d a worktree another session was still typing in; everything uncommitted
died. This seam separates the ONE removal primitive (`wt_remove`, workspace.sh) and its liveness signal
(the beat file) from every caller — `done`, `release`, `sweep --fix`, `resume` — so each caller's decision
is a row in ONE table, not a judgement call. `--force` leaves lib code for good; dirty worktrees are
archived (`archive/`, never `rm`), and a live one is LEFT with a note that names the next step.

## Interface — the beat (the liveness signal; content-first, mtime fallback)
- File: `$GCD/worktrees/<ID>/polaris-beat` (git's own per-worktree dir; dies with the worktree).
  Content = epoch seconds (written by `beat_touch`), OR empty (mtime-only `: >` touches from the hooks
  and the entry preamble). Reader: content first; empty/non-numeric → `stat -c %Y || stat -f %m`;
  absent or unreadable → idle (age 999999). `echo 1 > <beat>` fakes idle in drills (backdate).
- **Liveness is beat-only.** The lock's sid/pid lines (below) inform MESSAGES and the same-session
  exception; they never decide a removal.
- Writers (every one best-effort, `2>/dev/null || true`, zero forks):
  - `beat_touch <ID>` from `cmd_claim`, `cmd_resume`, `cmd_verify`, `cmd_handoff` (T-098).
  - `kit/ops/polaris` preamble, builtins only, placed BELOW the `EVENTS=` line and never on the
    `_match|_rules|_guard` path (T-101 — pinned line):
    `case "$PWD" in */.polaris/wt/*) _w="${PWD##*/.polaris/wt/}"; _w="${_w%%/*}"; : > "$GCD/worktrees/$_w/polaris-beat" 2>/dev/null || true;; esac`
  - `kit/ops/hooks/checkout-guard.sh` at gate 2 (the `*/.polaris/wt/*` cwd branch — T-093):
    `_p="${CWD//\\//}"; _w="${_p##*/.polaris/wt/}"; _w="${_w%%/*}"; : > "${_p%%/.polaris/wt/*}/.git/worktrees/$_w/polaris-beat" 2>/dev/null || true`
  - `kit/ops/hooks/ownership-guard.sh` directly after its `WT_ID=`/`PRIMARY=` anchor (:207-209 — T-093):
    `[ -n "$WT_ID" ] && : > "$PRIMARY/.git/worktrees/$WT_ID/polaris-beat" 2>/dev/null || true`
  - `readonly-allow.sh` NEVER writes (its contract: only ever allows, touches nothing).

## Interface — `kit/ops/lib/workspace.sh` (T-092; all top-level, bash 3.2-safe; api-kit rows below)
```
beat_touch <ID>            # write epoch to the beat; mkdir -p the worktrees dir first; rc 0 always
beat_age <ID>              # prints seconds since the beat (999999 when absent/unreadable); rc 0
beat_live <ID>             # rc 0 iff beat_age < cfg wt_live_minutes 15 × 60 (non-numeric cfg ⇒ 15)
wt_remove <ID> <caller>    # caller ∈ done|release|sweep · rc 0 removed · 1 LEFT · 2 archived
```
`wt_remove` rules:
- dirty ⇔ `git -C <wt> status --porcelain` prints anything (untracked included).
- remove = `git -C "$PRIMARY" worktree remove "<wt>"` (NO `--force`, ever) + `git worktree prune`.
- archive = `mkdir -p "$PRIMARY/.polaris/wt-archive"` · `mv "<wt>" "$PRIMARY/.polaris/wt-archive/<ID>-<epoch>"`
  · `rm -f "<archive>/.git"` (the worktree pointer file — the bytes stay, git forgets it) ·
  `git -C "$PRIMARY" worktree prune`. Any `mv`/git failure ⇒ rc 1 + one note; never `die`, never partial.
- Output prefixes (pinned, ONE line each, greppable by drills):
  `worktree removed` · `worktree LEFT` · `worktree archived → .polaris/wt-archive/<ID>-<epoch>`
- The grep `worktree remove --force` returns 0 lines across `kit/ops/lib/*.sh` after W2 (T-092 removes
  none itself — builder.sh:331 is T-098's, integrate.sh:101 is T-099's; T-092's own verify asserts
  workspace.sh never introduces one).

### The decision table — caller × dirty × live (every row is an assertion in drill `wtreap`)
| caller | clean + idle | clean + LIVE | dirty + idle | dirty + LIVE |
|---|---|---|---|---|
| `done` (T-099) | remove, rc 0; then `branch -D feat/<ID>` | LEAVE, rc 1 + note; local branch KEPT | archive, rc 2; then `branch -D` | LEAVE, rc 1, louder note; branch kept |
| `release`, own lane (cwd inside the wt) | remove, rc 0 (branch kept, as today) | same — own lane is live by definition | archive, rc 2; EBUSY (Windows: cannot mv your own cwd) ⇒ LEAVE rc 1 + `cd out of .polaris/wt/<ID> and run: bash ops/polaris sweep --fix` | same |
| `release`, from outside the wt | remove, rc 0 | remove, rc 0 (a clean live worktree loses nothing) | archive, rc 2 | **DIE** — see the die text below (the caller dies BEFORE any board write) |
| `sweep --fix` (T-100) | remove; + `branch -D` when the task is in `done/` | report only (LIVE line) | archive | report only |

`done`'s kept-branch note (pinned): `branch feat/<ID> kept — checked out in a live worktree; sweep --fix finishes the cleanup once idle`
`done` runs `branch -D` ONLY after `wt_remove` returned 0 or 2 — never on a LEFT worktree.
Own-worktree `done` is designed OUT rather than handled: under `landing: self` the handoff just beat, so
`done` on the builder's own worktree hits clean+LIVE ⇒ LEFT + kept branch, and a later idle
`sweep --fix` finishes it (drill_selfland's new assertion, below). Nothing ever removes the worktree a
session is standing in.

### Die texts (pinned, byte-exact, ONE line each — `<n>` = beat age in seconds, `<beatfile>` absolute)
- `resume` (T-098): `resume refused: .polaris/wt/<ID> is live (beat <n>s ago) — another session is inside it. Takeover is explicit: rm "<beatfile>" then re-run (or work from inside that worktree)`
- `release` (T-098): `release refused: .polaris/wt/<ID> is live (beat <n>s ago) and dirty — another session may be working there; if you are sure it is dead: rm "<beatfile>" then re-run`

## Interface — lock meta grows two lines (core.sh `lock_take`, T-097)
`$LOCKS/<ID>/meta` lines: 1 epoch · 2 who · 3 id · **4 `$CLAUDE_CODE_SESSION_ID` or `-`** · **5 `$CLAUDE_PID`
or `-`**. Both env vars are exported into every Bash-tool environment (probed 2026-09-01) and stable for
the whole session, unlike `$$`. Every existing 3-line parser keeps reading lines 1-3 (`sed -n Np`); a
missing line reads `-`. `cmd_resume`'s own adopt-and-refresh write (builder.sh:592) writes all five.
- `resume` (T-098): `beat_live` AND lock line 4 ≠ my sid (or `-`) ⇒ die with the resume text above;
  live AND line 4 == my sid ⇒ allowed (a compacted session re-entering its own task); idle ⇒ adopt.
- `sweep` STALE line (T-100) gains ` · last activity <m>m ago · session alive|gone` — alive = line 5 pid
  answers `ps -W` (Windows, ONE call per sweep) else `kill -0`; `-` ⇒ `session gone`.
- park stash names carry `<epoch>-<sid8|pid>` (below); bg job dirs record `sid` (bg-jobs.md v2).

## Interface — the steals become pid-aware (T-092 lease, T-097 mutex)
- Lease (`int_on`, workspace.sh:111-113): steal iff `age > sm*60` AND (`$lease/pid` absent OR dead OR
  `age > 2*sm*60`). T-092 changes ONLY this predicate (dead = `kill -0` fails, or on Windows the pid is
  absent from ONE `ps -W` listing). The re-stamp that keeps a slow suite from looking abandoned lives in
  integrate.sh (T-099, W2): `land`/`seal` run `date +%s > "$LOCKS/.int-lease/epoch" 2>/dev/null || true`
  after each suite command and after each per-task land, only while `INT_HELD` is set.
- Mutex (`mutex_on`, core.sh:222): steal iff `age > 120` AND (`$MUTEX/pid` absent OR dead), OR `age > 1200`.
  The existing 120 s age-only steal is what let a slow board write get stolen mid-flight.
- `sync_board` (core.sh:297): re-stamp `$MUTEX/epoch` at the top of each retry iteration when
  `$MUTEX/pid` == `$$`; the remote tip is `git ls-remote origin refs/heads/polaris/board | cut -f1`
  — never bare `FETCH_HEAD` (a concurrent fetch of another ref moves it).
- Orphan-lock drop (`cmd_sweep`, T-100): a lock with no active/review task and age < 120 s is reported as
  `(age <s>s — younger than 120s, left alone: a claim may be mid-flight)` and NEVER dropped, `--fix` or not.

## Interface — park / unpark (T-092, workspace.sh:169-207)
- Stash name: `polaris/park-<epoch>-<sid8|pid>` — `sid8` = first 8 chars of `$CLAUDE_CODE_SESSION_ID`,
  else `$$`. `park` prints the stashed paths (`git stash show --name-only` of the new stash, indented
  three spaces) so the session whose dirt it was can see it went somewhere.
- `unpark` pops only OUR newest park (name suffix == my sid8|pid); none of ours ⇒ note naming how many
  parks exist and `--any`. `unpark --any` pops the newest park of anyone (crash recovery, explicit).
- `cmd_status` (T-100) lists parks: one line each `park: <name> · <age>m · <why>`.
- The six auto-park call sites (integrate.sh:246,343,424,562,667 · admin.sh:368) are NOT edited — they
  call `park`, which now names itself. (Dedicated integrate worktree = IDEAS.md, architecture change.)

## Interface — `wt_add <ID> [resume]` (T-092)
With `resume` and no local `feat/<ID>`: create it from `<base>` and print ONE note:
`⚠ feat/<ID> did not exist — recreated from <base>; earlier commits, if any, are on origin/feat/<ID> or were deleted by done/release`.
`cmd_resume` (T-098) passes `resume`; `cmd_claim` does not.

## Interface — `sweep` lines (T-100; pinned shapes, `<s>` seconds, `<m>` minutes, `<col>` the task's column)
- `   LIVE worktree: .polaris/wt/<ID> (beat <s>s ago) — left alone`
- `⚠ IDLE worktree: .polaris/wt/<ID> (task <col>, beat <m>m ago, clean) — sweep --fix removes it`
- `⚠ IDLE worktree: .polaris/wt/<ID> (task <col>, beat <m>m ago, dirty) — sweep --fix archives it`
- STALE lock line: existing text + ` · last activity <m>m ago · session alive` (or `session gone`).
- `⚠ ORPHAN lock: <ID> (age <s>s — younger than 120s, left alone: a claim may be mid-flight)`
- The worktree pass iterates `git -C "$PRIMARY" worktree list --porcelain` paths under `.polaris/wt/`;
  `--fix` calls `wt_remove <ID> sweep` and, on rc 0 with the task in `done/`, `branch -D feat/<ID>`.
  Today's `integrate/<date>` branch is never touched. `sweep --fix` also prunes
  `.polaris/handover/<sid>/` dirs older than 24 h (role-handover.md) and `.polaris/bg/.archive/*`
  older than 24 h (bg-jobs.md v2).

## Interface — `.polaris/wt-archive/` + `uninstall` (T-103, admin.sh:661+)
Layout: `$PRIMARY/.polaris/wt-archive/<ID>-<epoch>/` = the worktree's files minus `.git`. Nothing in the
kit ever deletes an archive. `cmd_uninstall` dies BEFORE its existing worktree check when the dir is
non-empty (pinned): `<n> archived worktree(s) in .polaris/wt-archive/ — uncommitted work lives there; move it out (or delete it yourself) before uninstall`.
The existing `N POLARIS worktree(s) still checked out — run: ops/polaris sweep --fix` die becomes TRUE
(sweep gains the worktree pass); a live worktree still blocks uninstall — by design.

## CONVENTIONS key (T-096 registers the row; `beat_live` reads it via `cfg`)
`wt_live_minutes	6.2.0	15	a task worktree counts as live for 15 minutes after its last beat; done/release/sweep never remove a live worktree`

## MANUAL.md recipes (T-096) + PROTOCOL row (T-096)
- MANUAL:100 and :122 lose `--force`: the by-hand release/done recipes read "`bash ops/polaris sweep --fix`
  removes it once idle; by hand only when the beat file is older than `wt_live_minutes`:
  `git worktree remove .polaris/wt/<ID>` (never `--force`; a dirty one is moved to `.polaris/wt-archive/`)".
- PROTOCOL § N CHATS table gains ONE row (byte-exact):
  `| a worktree that is not yours | a worktree is removed only by wt_remove, only when idle — never by hand; sweep --fix reaps idle ones | \`bash ops/polaris sweep\` shows beat age |`

## Executable check — drill `wtreap` (T-104, history.sh, gated after `drill_selfland`; label `wtreap`)
Fixture: the spine's throwaway repo; `export CLAUDE_CODE_SESSION_ID=drill-sid` for the claiming session.
1. claim `T-WR1` → dirty its worktree (untracked file) → backdate the beat (`echo 1 > <beat>`) → hand-land
   (fixture `landing: integrator`, land + seal by the spine's recipe) → `done T-WR1` prints
   `worktree archived`, rc 0; `.polaris/wt-archive/T-WR1-*/` holds the dirty file's bytes; `feat/T-WR1` gone.
2. claim `T-WR2` → fresh beat → land → `done T-WR2` prints `worktree LEFT`, `branch feat/T-WR2 kept`;
   the worktree dir still exists; `git branch --list feat/T-WR2` non-empty.
3. claim `T-WR3` → dirty + fresh beat → `release T-WR3` from the PRIMARY dies (rc ≠ 0) and the message
   names the beat file path; `rm <beat>` → `release T-WR3` prints `worktree archived`.
4. claim `T-WR4` → fresh beat → from the primary with a DIFFERENT `CLAUDE_CODE_SESSION_ID`,
   `resume T-WR4` dies `resume refused`; with the SAME sid, `resume T-WR4` succeeds.
5. `sweep` prints `LIVE worktree: .polaris/wt/T-WR4`; backdate → `sweep` prints `IDLE worktree … clean`;
   `sweep --fix` removes it; a dirty backdated one is archived by `sweep --fix`.
6. Assert rcs and file states, never message presence alone (Learned log: trust the rc).
`drill_selfland` gains (T-104): after case (a)'s self-landed handoff, the handoff's OWN worktree still
exists (`worktree LEFT` in the land tail) and a later backdated `sweep --fix` removes it.
Budget: ~44 s; scratch under `scratchpad/T-104/` only.

## api-kit rows (ONE golden owner per wave — key-registry.md §7)
- W1 (T-096 writes): `kit/ops/lib/workspace.sh	fn	beat_age` · `…	beat_live` · `…	beat_touch` · `…	wt_remove`
  + the `kit/ops/KEYS.tsv	key	wt_live_minutes` row + `kit/ops/hooks/checkout-guard.sh	fn	mutating_other`
  (shared-checkout v2.5).
- W3 (T-104 writes): `kit/ops/lib/selftest/history.sh	fn	drill_wtreap`.
- T-092/T-093/T-097/T-098/T-099/T-100 add NO other fn at any depth, no `#` heading, no KEYS row.

## Invariants
- `--force` never returns to `git worktree remove` in lib code; the only removal primitive is `wt_remove`.
- A live worktree (beat younger than `wt_live_minutes`) is never removed or archived by anyone except the
  session inside it (`release` own-lane) — and never by `done`.
- Dirty worktrees are archived, never deleted; archives are the human's to delete.
- Liveness is decided by the beat alone; sid/pid decide messages and the same-session exception only.
- Every writer of the beat is best-effort and fork-free; a missing worktrees dir is silently skipped.
- Existing 3-line lock parsers keep working; a missing line reads `-`.

## Example
```
$ bash ops/polaris done T-101          # T-101's builder is still inside .polaris/wt/T-101 (beat 40s ago)
✅ T-101 → done/ (landed 3f2a…)
   worktree LEFT: .polaris/wt/T-101 is live (beat 40s ago)
   branch feat/T-101 kept — checked out in a live worktree; sweep --fix finishes the cleanup once idle
```

## v1.1 — the beat writers redirect stderr FIRST (2026-09-01, board amendment; proved live by the T-093 lane)
v1 pinned the beat touches as `: > "$file" 2>/dev/null || true`. Bash applies redirections LEFT TO RIGHT:
the `>` open runs while stderr is still the terminal, so when `$GCD/worktrees/<ID>/` does not exist (a
`.polaris/wt/` path that is not a git worktree, a hook fired before `wt_add`, a CI checkout) every Bash call
from a worktree printed `No such file or directory` — a hook that is supposed to be silent talking on every
turn. The correction is ordering only: `2>/dev/null` BEFORE the `>`. Pinned, byte-exact, for ALL FOUR writers:
- `kit/ops/polaris` preamble (T-101 — MUST use this form, not v1's):
  `case "$PWD" in */.polaris/wt/*) _w="${PWD##*/.polaris/wt/}"; _w="${_w%%/*}"; : 2>/dev/null > "$GCD/worktrees/$_w/polaris-beat" || true;; esac`
- `kit/ops/hooks/checkout-guard.sh` gate 2 (T-093 shipped this form):
  `_p="${CWD//\\//}"; _w="${_p##*/.polaris/wt/}"; _w="${_w%%/*}"; : 2>/dev/null > "${_p%%/.polaris/wt/*}/.git/worktrees/$_w/polaris-beat" || true`
- `kit/ops/hooks/ownership-guard.sh` after the `WT_ID=`/`PRIMARY=` anchor (T-093 shipped this form):
  `[ -n "$WT_ID" ] && : 2>/dev/null > "$PRIMARY/.git/worktrees/$WT_ID/polaris-beat" || true`
- `beat_touch` (workspace.sh, T-092 — told mid-build): the epoch write is
  `printf '%s\n' "$(date +%s)" 2>/dev/null > "$GCD/worktrees/$1/polaris-beat" || true` (after its `mkdir -p`,
  which is itself `2>/dev/null || true`).
Every other v1 rule stands: best-effort, zero forks in the hooks, a missing dir is silently skipped, the
verdict never changes. The `wtreap` drill (T-104) adds one assertion: a hook payload from a
`.polaris/wt/T-NOPE` cwd whose worktrees dir does not exist produces EMPTY stderr and the normal verdict.

## Changelog
- v1 2026-09-01: created for T-092, T-093, T-096, T-097, T-098, T-099, T-100, T-103, T-104 (plan: cant-eat-itself, 6.2.0)
- v1.1 2026-09-01: beat writers redirect stderr FIRST (`: 2>/dev/null > "$file" || true`) — bash applies redirections left to right, so the v1 order printed `No such file or directory` on every Bash call from a worktree whose worktrees dir was missing (T-093 lane, live); T-093 shipped the fix, T-092 told, T-101's preamble must use it.
