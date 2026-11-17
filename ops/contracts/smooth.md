# CONTRACT: the smooth run — fewer hand edits, reds found in their own wave   (v1 — 2026-11-17)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/smooth.md` (the eighteen gap lines dated 2026-11-17 on `ops/board/backlog/IDEAS.md`;
approved; owner away). Kit release: 6.19.0. Slug: `smooth`.

Five cards, two waves. Wave 1, side by side, files disjoint: **T-313** (filing: `new`, `retire`,
`status --all`, the reach list, the help words) · **T-314** (the builder's commands: `grant`, `release`,
`handoff --hold`, `approve --plan`, the lock's folder, `next`/`triage`, `pack`'s first section) ·
**T-315** (the wave check in `seal`, `amend --deps`, the role, PROTOCOL and MANUAL words) · **T-316** (updates, `speed
--plan`, `tools/proof.sh`). Wave 2: **T-317** (the joined tree: the seam golden, every joined-tree
golden, `api-kit`, VERSION and CHANGELOG) depends on all four.

## § 0 Cross-card rules (every card)
- **One owner per shared file.** `kit/ops/polaris` (dispatch + help) belongs to **T-313 alone**;
  `ops/tests/api-kit.expected` to **T-317 alone**. T-313's help text covers EVERY new verb and flag of
  this plan (§ 9), written from this contract. No card re-pins `cli-help`: it is re-pinned after the
  dogfood, never in a card.
- **Public names.** The only new public names in this release are T-313's `cmd_retire`
  (`kit/ops/lib/author.sh`) and T-315's three new MANUAL headings (§ 9). Every other helper any card writes
  is `_`-prefixed; no new column-0 public shell fn, python def/class, KEYS row or kit `.md` heading
  anywhere else. `kit/ops/lib/handover.sh` keeps exactly its eight public fns and gains no fn at all
  (inline changes only); `kit/ops/lib/route.sh` gains no public fn (`lib-census`). `update_hops_hint`
  keeps its name (install.sh greps `^update_hops_hint()`).
- No `IFS="$(printf` in new code (`startup-budget`) — use `$POLARIS_TAB`. bash 3.2: no `case` inside
  `$(...)`, no assoc arrays, no `mapfile`; never one fork per card in a loop over the board. An awk
  `function` takes at least one parameter (or a dummy local).
- No new CONVENTIONS key; nothing here edits `ops/CONVENTIONS.md`, `ops/RULES.tsv`, `.github/` or
  anything under `~/.claude`. No new dependency. No repo file deleted (a retired card is MOVED, § 2).
- Goldens are hermetic (mktemp repos, fake HOME + USERPROFILE, `file://` channels), print no
  sha/time/absolute path, never wait on a fixed `sleep` (poll an observable line), pipe python output
  through `tr -d '\r'`. A golden's `.cmd` lists commands with stdout captured (`2>/dev/null` is what
  `check` captures) — a case about a stderr line redirects it with `2>&1` itself.
- No `tools/proof.sh`, no full-suite command and no `doctor --selftest` in any `verify:`. A drill that
  a card must run (named per card below) is run by its builder by hand, in the background
  (`bg run` + chunked `bg wait --max 150`), and the result goes in the handoff Notes.
- `kit/` is the source; the root `ops/` is the dogfooded copy and no card edits it.
- Every refusal below writes nothing (no file, no event, no commit) and exits 1 unless stated.

## § 1 A card owns its tests before it starts (T-313: `new`; T-314: `pack`'s call)
### 1.1 `new` owns the SURFACES-mapped tests and the folder guides (author.sh)
- For each draft, after its `files_owned` is read, two kinds of path join the draft's owned set —
  each unless an owned pattern is already that exact path/glob or `owned_match` covers it:
  - **mapped tests**: every `ops/SURFACES.tsv` row (via `surfaces_lines`) whose column-1 surface
    `pat_overlap`s one of the draft's owned patterns adds its column-2 `tests` glob;
  - **folder guides** (coordinator addition, 2026-11-17 — Sonoba: 1 of 12 new grants was the guide of a
    folder the card adds a file to): for every folder the draft owns a file in — the `dirname` of each
    exact-path entry, and each `dir/` entry itself — `<dir>/CLAUDE.md` when it is a tracked file
    (`git -C "$PRIMARY" ls-files`, the ONE call § 1.2 also uses). The repo root's `CLAUDE.md` never
    joins (dirname `.`).
- The board file gets each addition with `fm_append_item files_owned <path> <file>`; the draft on
  disk is never modified.
- The § 5 overlap gate (`_new_place`) uses the EXTENDED set, so a mapped test or a guide that another
  open card owns sequences the two cards by `depends_on` exactly as any shared file does today.
- One line per addition, on **stderr**, after that draft's `<ID> <col> — …` line:
  `   <ID>: owns <tests-glob> too — ops/SURFACES.tsv maps <surface> to it`
  `   <ID>: owns <dir>/CLAUDE.md too — the guide of a folder it changes`
- No SURFACES row and no guide → nothing added, nothing printed (byte-identical to 6.18.1).

### 1.2 `_card_reach <taskfile>` — what touches a card's files without being on it (author.sh, private)
Prints LC_ALL=C sorted, unique lines `<kind><TAB><path><TAB><name>`, kind `test` or `uses`; rc 0
always, never dies. Excluded from both kinds: paths the task's own `files_owned` covers
(`owned_match`).
- **Names** = for every `files_owned` entry that is an exact path (no trailing `/`, no `*`): its
  basename and its stem (the basename minus its last `.ext`) — tests name a module far more often than
  its file — plus every item of the task's optional `replaces:` list (a path → its basename and stem;
  a bare name → itself). A name shorter than 4 characters is skipped.
- **`test` — tests that NAME the card's files.** Test files = tracked files (`git -C "$PRIMARY"
  ls-files`, ONE call) that a SURFACES `tests` glob matches, OR have a path segment `test`, `tests`,
  `spec`, `specs` or `__tests__`, OR a basename matching `test_*`, `*_test.*`, `*.test.*` or
  `*.spec.*`. A test file names <name> when its content contains it as a fixed string: ONE `git grep
  -o -F` with one `-e` per name over the test files (no fork per file or per name). A name that more
  than 25 test files contain prints ONE line instead of its files: `test<TAB><n> test files<TAB><name>`
  (n a number) — too common to list.
- **`uses` — files that import or call the card's files** (coordinator addition, 2026-11-17 — Sonoba:
  4 of 12 new grants were source files that use the card's own files). ONE index call for all the
  card's exact owned paths: `"$SELF" find --importers <path> <path>…`; code-edge rows only (a row whose
  text starts `mention ` is dropped — those are docs); `<name>` = the basename of the owned path the
  row answers; test files are left to the `test` kind. More than 25 users of one name → one line
  `uses<TAB><n> files<TAB><name>`. No index (`find` fails) → no `uses` lines, silently.
- **`find --importers` takes several paths** (kit/ops/index.py, T-313): ONE path → byte-identical to
  6.18.1; two or more → ONE build, each path's rows in argument order, every row prefixed
  `<queried path><TAB>`. No new def/class (private `_` helpers only).
- No test files, no users, or no names → prints nothing.
- New optional frontmatter list `replaces:` in `kit/ops/templates/TASK.md` (after `files_owned:`),
  commented: `names or paths this card renames, replaces or redefines — the tests that name them are
  listed at new and pack`. Nothing else reads it.
- LISTED, never auto-owned (plans/smooth.md assumed: auto-owning a search hit could chain cards that
  have nothing to do with each other).

### 1.3 `new`'s advisory block (author.sh)
After every ID line (and the § 1.1 lines), when `_card_reach` prints anything for any filed card,
ONE block on **stderr**:
```
files that touch these cards' files and are not on files_owned — a builder that must change one returns NEEDS PATH in its first minute:
   <ID>: <path> names <name>        (kind test)
   <ID>: <path> uses <name>         (kind uses)
```
(the too-common lines read `<ID>: <n> test files name <name>` / `<ID>: <n> files use <name>`). The
`(kind …)` text is not printed. Nothing printed when every card's list is empty. Advisory: it never
refuses, never moves a card, never adds to `files_owned`.

### 1.4 `pack` prints the list first (builder.sh `cmd_pack`, T-314)
Right after pack's opening header block (before any other section), when `_card_reach` is defined
(`command -v _card_reach >/dev/null 2>&1` — it is not until T-313 lands) and prints anything:
```
FILES THAT TOUCH YOURS — not on files_owned. One you will have to change → stop now: return NEEDS PATH <path> — <why> (BUILDER.md), not after the build
   <path> — names <name>
   <path> — uses <name>
```
Empty list → the section is omitted entirely, so every other pack stays byte-identical.

## § 2 Re-cutting a filed plan is commands (T-313: `retire`, `new`, `status --all`)
### 2.1 `polaris retire` (author.sh, `cmd_retire` — the one new public fn)
Usage: `usage: polaris retire <ID>… --by <ID> -m "why"  |  retire --map <file> -m "why"`
- `--map <file>`: one `old<TAB>new` pair per line; blank lines and `#` lines skipped; CR stripped.
- **Accept** only when ALL hold (checked before any write; refusal = `retire refused: <reason>`):
  not on a `feat/*` branch (`retire refused on <br> — run it from the primary checkout`) · `-m` given ·
  at least one old ID · every old ID in backlog/, ready/ or blocked/ with no lock under `$LOCKS/<ID>`
  (active → `<ID> is claimed — release it first`; review/ or done/ → `<ID> is in <col>/ — only waiting
  cards retire`; nowhere → `<ID> is no task on the board`) · every successor on the board in any
  column but retired/ and not itself one of the old IDs (`<new> is no task on the board` / `<new> is
  retired too`). Runs under the board mutex, after `board_pull`.
- **Effect**, per old card: moved (plain `mv`) to `ops/board/retired/<ID>.md`; `status: retired`;
  `retired_by: <new>` stamped (`fm_stamp`); Notes line `- retired: by <new> — <why>`; event `retire`
  with note `→ <new>`. Its `feat/<ID>` branch is deleted when it exists, no worktree has it checked
  out, and `git rev-list --count "$BASE..feat/<ID>"` is 0; otherwise kept, silently.
- **Rewiring**: every task file in backlog/ ready/ active/ review/ blocked/ whose `depends_on` names an
  old ID gets that ID replaced by its successor (once, first appearance order, via `_new_deps`),
  dropped when the dependent IS the successor. A rewired ready/ card that now depends on a card not in
  done/ moves to backlog/ (`status: backlog`) — the ready gate, in the same commit.
- **ONE board commit**: `chore(board): retire <old> <old>… → <new>` (`--by`) or
  `chore(board): retire <old> <old>… (map)` (`--map`); then `sync_board`.
- Prints one `retired <old> → <new>` line per old card, then `   <k> dependent(s) rewired`.
- **What `retired/` changes elsewhere — nothing reads it but `status --all`.** Every board reader in
  the kit lists its columns by name (status, board-fm, next, drift, brain, metrics, speed, tune, the
  index hold rule); `task_file` searches six named columns, so a `depends_on` naming a retired card is
  refused at `new` ("is no task on the board"); `new`'s ID counter globs `$BOARD/*/T-*.md`, so a
  retired ID is never reused; `board_paths` commits every file under `ops/board/`, so the folder rides
  the board ref with no change. T-313 proves the list with one grep in its Notes and touches none of
  those readers.

### 2.2 `status --all` (observe.sh `cmd_status`)
`status --all` = today's `status` output, plus a `  retired  <n>` row right after the `done` row, and
after the blocked list (only when n > 0): `retired:` then one `  <ID> → <retired_by>` line per card
(LC_ALL=C order by ID). Bare `status` and `status --brief` are byte-identical to 6.18.1. Dispatch
already passes `${1:-}`.

### 2.3 `new` sorts its drafts and takes a retire map (author.sh)
- Usage: `usage: polaris new [--retire <map>] <draft.md> [<draft.md>…]`
- **Sort**: before the checks, the drafts are put in a stable dependency order — a draft moves after
  every draft whose preset `id:` its `depends_on` names; otherwise the given order stands. A cycle
  among the drafts → `new: depends_on cycle among the drafts: <ID> → <ID> → <ID>`, nothing written.
  The ID lines and the commit subject follow the sorted order.
- **`--retire <map>`** (the § 2.1 map format): every pair is checked by § 2.1's acceptance, except
  that a successor may also be a preset `id:` of a draft in this call. Then, inside the SAME mutex
  hold and BEFORE the § 5 placement reads ready/ active/ review/: the § 2.1 effect for every pair
  (successors that are drafts are written after placement, so rewiring a dependent to one is a plain
  frontmatter edit). Placement therefore never chains a draft to a card this call retires. ONE board
  commit for all of it: `chore(board): new <ID>… · retire <old>…`. Output: the `retired …` lines,
  then the ID lines, then the § 1 stderr lines.

## § 3 The wave check — a wave's reds show up in that wave (T-315, integrate.sh `cmd_seal`)
### 3.0 What the seal runs TODAY (6.18.1), proven from the code
Under `landing: self` a handoff continues into `self_land` (builder.sh): `land <ID>` (cmd_land: audit +
ONE squash commit, no suite — "Self-landing runs NO full suite"), then the last lane out — or seal on
demand (hour.md § 7, `_sl_chain … wait`) — runs `seal`. `cmd_seal` merges, tags, writes the report and
burndown, refreshes the brain and both verdicts, re-lands anything that did not arrive, and runs NO
test command at all. The CONVENTIONS suite (`test:` and the other keys) runs in exactly two places:
`cmd_qa` (which `finish` calls) and `land --express` (the express lane only; `self_land` calls plain
`land`). `run_verify_cmds` runs only the card's own `verify:` lines — `test_fast:` is printed by
`pack` and never executed by `verify`/`handoff`. The `depth_for` / `test_select_for` block lives only
inside those two callers. So under `landing: self` + `push: end` a project with only `test:` set ran
no suite between a card's own filters and `finish`, and seal on demand split one plan into several
waves that each sealed untested. (`landing: integrator` was covered only by INTEGRATOR.md's prose
background proof after the seal.)

### 3.1 When and what
- Runs inside `cmd_seal` (direct and the pr-mode local staging seal; NOT `seal --sync`), under the
  lease it already holds, AFTER the "nothing new to seal" exit, the sprint-number gate and the tag
  gate, and BEFORE the report commit and the merge — with `integrate/<date>` checked out.
- `test:` unset → skipped silently (byte-identical to 6.18.1 — every fixture without `test:`).
- Skipped with ONE note line when: `POLARIS_SEAL_NOCHECK` is set (the re-land child seal) → silent ·
  `.polaris/suite-stamp` field 1 or `.polaris/wave-check` (green) field 1 equals the wave tip sha →
  `✅ wave check — already green at <sha7>` · `depth_for <wave task files>` answers none/look/ui →
  `   wave check: skipped — <depth>: <why>`.
- **Change set** = `git diff --name-only --no-renames "$BASE...integrate/<date>"` minus `ops/MAP.md`,
  `ops/SURFACES.tsv` and the sprint report directory (the paths `surface_change_set` already drops).
  **Wave cards** = the `[<ID>]` suffixes of the wave's non-board subjects (`$subjects`).
- **Selection** = `test_select_for <change-set file>` — the one decision qa and express share: rc 0 →
  those commands; rc 1 → `test:` verbatim (so a project with only `test:` set runs `test:` once).
- Runs each command once from `$PRIMARY` (`bash -c`), under the heavy slot (`_heavy_on "seal wave
  check"` once, `_heavy_off` after the last command or before a red exit), re-stamping the lease epoch
  after each command like express does. At most one run per wave; nothing per card.
### 3.2 Green
One line: `✅ wave check — <k> command(s) green (<scoped: … | whole test: <reason>>)` then the seal
goes on unchanged. Writes `.polaris/wave-check` = one LF line `<wave-tip-sha> green <scoped|full>`.
### 3.3 Red — the wave stays open
- Stops at the first red command. Primary checked back out to `$BASE` (best-effort, as § 15.2's
  refusals do), lease released, NOTHING merged or tagged, no report commit; `integrate/<date>` keeps
  every landed card. The cards stay in review/ landed, so a fix card lands on the same wave and the
  next `seal` re-runs the check.
- **Named cards**: a SELECTED command → the wave cards whose own changed files (one `git log
  --name-only` over the wave) match the surface of any SURFACES row that produced that command (a row's
  `cmd`, or a `-` row through `test_select`); `test:` verbatim or nothing matched → every wave card.
- Prints, on stderr, then dies rc 1:
  ```
  ⛔ wave check red — integrate/<date> stays open: <command>
     <last 15 lines of its output, indented 5>
     cards: <ID>, <ID>
     fix: file a fix card for them (it lands on this wave), then: bash ops/polaris seal
  ```
- Board: one event `wave-red` per named card (note = the command, cut to 200 chars) in ONE board
  commit `chore(board): wave check red integrate/<date> — <ID> <ID>`. `.polaris/wave-check` is not
  written. `self_land`'s existing `⚠ wave not sealed (rc 1) …` note follows unchanged.
### 3.4 `seal --no-check -m "why"` — the recorded way past a red that is not the wave's fault
Refused on any `feat/*` branch (`seal --no-check refused on <br> — run it from the primary
checkout`) and without `-m`. Skips the check, prints `   wave check: skipped by hand — <why>`, adds one
event `wave-check-skipped` (note = why) to the seal's board writes. `finish` still runs the whole suite.
Usage line: `seal [<date>] [--no-check -m "why"] | seal --sync [<date>]`.

## § 4 `amend <ID> --deps +<ID>|-<ID> -m "why"` (T-315, integrate.sh `cmd_amend`)
- For a card in backlog/ ready/ blocked/ or active/. Same containment as today: any `feat/*` branch
  refuses first; `-m` required. `--deps` and `--verify` in one call → `amend: --deps and --verify are
  separate amendments — one per call`. One `--deps` value per call.
- Refusals: the target not in those columns → `<ID> is not waiting or claimed (state: <col|unknown>)`
  · `<X>` not on the board → `amend: depends_on: <X> is no task on the board` · `<X>` = the card →
  `amend: a card cannot wait on itself` · `+X` already listed / `-X` not listed → `amend: <ID> already
  waits on <X>` / `amend: <ID> does not wait on <X>` · `+X` where X reaches the card through
  `depends_on` (`dep_reaches`) → `amend refused: <X> already waits on <ID> — that would be a cycle`.
- Effect: `depends_on` rewritten as one inline list (`_new_deps`); Notes `- amend: deps <+|-><X> —
  <why>`; event `amend`; a ready/ card gaining a dep not in done/ moves to backlog/ in the same commit
  (removing one never promotes — `next --do` does). ONE board commit `chore(board): amend <ID> deps
  <+|-><X>`; prints `amended <ID>: depends_on <+|-><X>`.
- Usage line gains `  |  amend <ID> --deps +<ID>|-<ID> -m "why"`.

## § 5 Smaller hops (T-314: builder.sh, handover.sh, route.sh)
### 5.1 `grant` refuses from the card's own lane
FIRST, before reading the board: HEAD on any `feat/*` branch, or `$PWD` inside any `*/.polaris/wt/*`
→ `grant refused on <branch, or the worktree path> — a builder never widens its own card; return
NEEDS PATH <path> — <why> and the conductor grants it from the primary checkout`. Everything else in
grant is unchanged (the grant drill runs from the fixture's primary).
### 5.2 `release`
- `--to blocked` works on an UNCLAIMED ready/ card exactly as `--to backlog` does (ready/ → blocked/,
  owner null, `status: blocked`, `- ⛔ released by <who>: <msg>` when `-m`, event `blocked`, commit
  `chore(board): release <ID> → blocked`, prints `<ID> → blocked/ · no lock or worktree held`).
- A release that leaves no worktree (wt_remove rc 0, or none existed) deletes `feat/<ID>` when it
  exists, is checked out nowhere and `git rev-list --count "$BASE..feat/<ID>"` is 0; the closing line's
  `(branch feat/<ID> kept)` then reads `(branch feat/<ID> removed — it held no commits)`. Any other case
  keeps the branch and today's words. The unclaimed paths do the same cleanup, silently.
### 5.3 `handoff --hold` — stop at review/
- Usage: `handoff [ID] [--saw "…"] [--no-before "<why>"] [--hold]`.
- Everything handoff does up to and including its board commit, plus, inside that commit: `held: yes`
  stamped (`fm_stamp`), Notes `- held at handoff: waits in review/ for a yes — then: bash ops/polaris
  land <ID>`, event `hold`. Then NO `self_land`; prints `held: <ID> waits in review/ — nothing landed.
  After the yes: bash ops/polaris land <ID>, then bash ops/polaris seal`.
- A `held: yes` card: `next_landable` never counts it landable (row 1 never routes `integrate` for it
  alone; its note lists it as `held for a yes: <ID>`); `_sl_last_out` never treats it as on its way
  (it never holds a sibling's seal back); the `self_land` fan-out never lands it. A typed `land <ID>`
  lands it like any review card; `done` finishes it as today (both unchanged).
- `--no-before` with a diff that touches no `visual:` path already asks for no capture
  (`visual_gate`'s `vhit=0`); T-314's golden pins that case and `visual.sh` is not touched.
### 5.4 `approve --plan <slug>` makes it the run's plan
After a successful record, when `CLAUDE_CODE_SESSION_ID` is set: `<slug>` is written to
`$(next_dir)/plan` (mkdir -p; overwrite) and one more line prints `   this run's plan is now <slug> —
drain: plan takes its cards`. No session id → unchanged.
### 5.5 The lock records its worktree — `next` answers for the caller's folder
- **The lock's new field: line 6 of `$LOCKS/<ID>/meta`** = the card's worktree path exactly as
  `wt_path <ID>` prints it, written by `claim` (appended after `lock_take`'s five lines — core.sh is not
  touched) and by `resume` (its meta rewrite gains the sixth line). Readers that read lines 1–5 are
  unchanged.
- `next` row 0: a lock whose line 4 is this session's id AND whose line 6 is present prints `resume
  <ID>` only when the caller's `$PWD` is that folder or inside it, compared after lowercasing, `\` →
  `/`, and a leading `/<letter>/` → `<letter>:/` on both sides (builtins only). Otherwise row 0 goes on
  to the next lock, then the rest of the table — so a conductor in the primary is never told to resume
  its builder's card. A lock without line 6 → today's behaviour. `mine` (own bg-job folders) unchanged.
### 5.6 A stale verdict means recompute (next row 1.5, bare triage)
Where today a cache "names another commit" reads as not due: when the row's own quiet gate passes
(next: no tidy marker, nothing in active/ or review/, lease not live; triage: `board_quiescent
inflight`) and no due verdict was found, and `.polaris/tune-due` exists with field 1 ≠ `$BASE`'s sha,
or `.polaris/hops-due` exists with field 1 ≠ it and `hops:` is not off → run, once, `"$SELF" hops --due
>/dev/null 2>&1 || true` then `"$SELF" tune >/dev/null 2>&1 || true`, and read both again by the same
rules. Missing caches stay silent (never computed here). `next --brief` never recomputes. The refresh
names the new base, so it is paid at most once per base commit.

## § 6 Updates (T-316, admin.sh)
- **Cache epoch**: `update_latest` writes a third line `epoch: <unix seconds>` to
  `.polaris/update-cache` on every write (readers ignore unknown lines).
- **`update --all` asks the channel itself**: the walk runs each child with `POLARIS_UPDATE_FORCE=1`;
  `cmd_update_auto` step 3 calls `update_latest force` when it is set.
- **`--auto` re-asks a stale "up to date"**: not forced, cache `checked:` is today, cached `latest`
  equals the installed version, and `epoch` is missing or ≥ 3600 s old → `update_latest force`.
- **Registry walk** (`cmd_update_all`), in this order per entry: gone → today's removal · a path whose
  folded key (lowercase, `\` → `/`, leading `/<letter>/` → `<letter>:/`) equals an earlier entry's →
  file removed, `<p>: same project as <first> — registry entry removed` · `$p/.git` is a FILE (a
  worktree) → `<p>: a worktree — skipped` · no `$p/ops/VERSION` → file removed, `<p>: no POLARIS here
  (no ops/VERSION) — registry entry removed` · self-hosting → today's skip · else the update.
- **The kit's own pending update** (`publish: pr`, or any update that did not commit itself):
  - Record `.polaris/kit-pending`: after a successful install whose self-commit did not happen, one LF
    line `<git hash-object of the file, or - for a deleted path><TAB><path>` per footprint path
    (`update_dirt_overlaps_kit`'s footprint) that was clean before this update and is dirty after it,
    unioned with the previous record's lines whose path is still dirty AND still hashes the same;
    LC_ALL=C sorted. Removed when the self-commit succeeds or no recorded path is dirty.
  - Both dirt checks (`cmd_update`'s park decision and `cmd_update_auto` step 6) first drop every
    porcelain line whose path is recorded with the hash it has NOW (`-` = still deleted) —
    byte-equality, so a person's later edit to a kit file is NOT dropped and holds the update exactly
    as today. The install then goes on top; the record is rewritten.
  - A project frozen before 6.19.0 has no record: unchanged (it needs its pending update committed
    once, by a person) — said in CHANGELOG.
- **Drill**: T-316 changes `update --auto` and the registry walk, so its builder MUST run `bash
  kit/ops/polaris doctor --selftest --only autoupdate` (about 16 min, serial) before handoff.

## § 7 Price (T-316, admin.sh `_speed_plan`)
- A card's build minutes: `B` when points ≤ 5 or unset; otherwise `round(B × (1 + (points − 5) / 8))`
  (13 points → 2 × B), where B is today's per-card figure.
- `mins = max(P, ceil(nc / L) × (B + Dl))`, P = the longest `depends_on` chain summing `(card build +
  Dl)` per card. The `plan …`, `each card: …` and `projected: about <T> (target <M> min)` lines keep
  their format (tune.md § 1 parses `projected: about `).
- New line after `each card:` when any card is over 5 points: `chain cards: <k> priced from their
  points (largest: <p> points, about <c> min to build)`.
- Release checks, after the `projected:` line, only when `.polaris/last-suite-seconds` holds a number
  > 0 (s = it, rounded to whole minutes, at least 1): `release checks: about <r> min more — <w> wave
  check(s) and the finish check at about <s> min each (the last whole suite)` with w = the critical
  path's wave count and r = (w + 1) × s; then `with the release checks: about <T2>` (T2 = mins + r,
  formatted like T). The over-target sentence still compares `mins` alone.

## § 8 `tools/proof.sh` (T-316)
`await_job` returns 4 for a job that completed with conclusion `cancelled`. On 4 (in `--await` and in
the main path's linux wait): print `proof: <job> — cancelled — no answer`, then find the newest run of
the same commit with `--event push` (`gh run list --workflow ci.yml --commit <sha> --event push --json
databaseId --jq '.[0].databaseId'`); a different run found → `proof: <job> — waiting on the push run
<id> of <s7>` and await that job with today's green / RED / no-answer lines and rc; none → rc 3 with
`proof: <job> — no push run of <s7> yet`. Never RED for a cancelled job.

## § 9 Words (T-313 — kit/ops/polaris help; T-315 — PROTOCOL, MANUAL, roles; T-317 — release)
- **Help** (`kit/ops/polaris`, T-313): dispatch `retire) shift; cmd_retire "$@";;`; help entries:
  `retire <ID>… --by <ID> -m "why" | retire --map <file> -m "why"` (after `fold`); `new` shows
  `[--retire <map>]`; `amend` gains the `--deps` form; `release` says `--to blocked|backlog` also parks
  an unclaimed ready card and that an empty feat branch is removed; `handoff` shows `[--hold]`;
  `status [--brief|--all]`; `seal [<date>] [--no-check -m "why"]`; `update --all` says it asks the
  channel itself.
- **PROTOCOL** (T-315): command-table rows for `retire`, `new --retire`, `amend --deps`, `handoff
  --hold`, `seal --no-check`, `status --all`; one sentence in the table's `seal` row: the seal runs the
  wave check (§ 3).
- **MANUAL** (T-315): by-hand recipes, the only new headings: `## Retire — move waiting cards aside
  for their successor`, `## Hold — stop a handoff at review/`, `## Wave check — the tests a wave
  changed, before it seals`; the `amend --deps`, `release --to blocked` and `new --retire` recipes go
  under existing headings.
- **Roles** (T-315): `BUILDER.md` — pack's first section: any listed test you will have to touch →
  return `NEEDS PATH` in the first minute, not after the build; `grant` refuses from your lane.
  `SOLO.md` — a lone session short a path hands the card back (`release -m "NEEDS PATH <path> — <why>"`),
  never grants itself. `CONDUCTOR.md` — `handoff --hold` for a card waiting on the owner's yes;
  `approve --plan` makes that plan the run's; a re-cut is `retire`/`new --retire`, never hand edits; a
  red wave check → a fix card on the same wave (`seal --no-check` only for a red that is not the wave's
  code, with the why). `INTEGRATOR.md` — the seal runs the wave check; the background-proof paragraph
  says so. `PLANNER.md` — re-cut with `retire`/`new --retire`; `new` owns mapped tests itself and lists
  the tests that name a card's files (`replaces:` for a renamed thing).
- **Release** (T-317): `kit/ops/VERSION` → `version: 6.19.0`; `CHANGELOG.md` `## 6.19.0` — measured
  claims only (the IDEAS numbers: 24 of 27 grants were tests at 25–40 min each; 5 reds landed unseen;
  124 hand board edits and 78 parked cards; 6.18.1 unseen for hours), naming all four cards' changes,
  and the frozen-project note of § 6.

## § 10 Joined-tree goldens — which run the real thing, and who runs them
- The one code seam between side-by-side cards: `_card_reach` (T-313) ← `pack` (T-314, guarded).
  The golden that runs the real pair is NEW, `ops/tests/pack-named-tests` — a fixture card owning
  `src/alpha.py` and `src/beta.sh`, with a tracked `src/CLAUDE.md`, a `tests/test_alpha.py` that names
  `alpha`, a `src/gamma.py` that imports `alpha` (an edge `find --importers` resolves), and a SURFACES
  row mapping `src/beta.sh` to `tests/beta.*`: `new` owns `tests/beta.*` and `src/CLAUDE.md` (stderr
  lines) and lists `tests/test_alpha.py` (names) and `src/gamma.py` (uses); `pack` prints the § 1.4
  section with the same two paths — owned and run by **T-317** on the joined tree.
- **T-317's last step** runs, side by side on the joined tree, every golden a wave-1 card created or
  re-pinned plus every golden more than one card's code reaches: `api-kit` (strict, rows for
  `cmd_retire` and the three MANUAL headings), `pack-named-tests`, `pack-guides`, `pack-steps`,
  `pack-visual`, `shots-gallery`, `new-task`, `retire-board`, `hops-map`, `fm-comments`,
  `builder-cmds`, `next-own-folder`, `handover-route`, `triage-lane`, `tune-hop`, `tune-report`,
  `wave-check`, `amend-deps`, `away-yes`, `brain-once`, `express-pr`, `pr-one-link`,
  `update-registry`, `update-pending`, `update-waiting`, `speed-plan`, `proof-ci`, `lib-census`,
  `startup-budget`, `readonly-allow`, `plain-voice`. A red there is re-pinned by T-317 only when the
  diff is exactly what this contract says the joined tree prints (it owns the `pack-*`,
  `shots-gallery` and `away-yes` expected files for that); anything else → NEEDS PATH / hand back.
- Wave-1 cards keep `api-kit` and `lib-census` in their own `verify:` (proof that they add no public
  name); in their worktrees, based on `<base>`, both stay green. `cli-help` is re-pinned after the
  dogfood. The CI self-test (serial) is the conductor's release ritual, not a card.

## Executable checks (per card; each card's `verify:` names them)
- T-313: `new-task` (sort, cycle refusal, auto-owned mapped test and folder guide + their stderr
  lines, the advisory block's `names` and `uses` lines, `--retire`, the new usage line) ·
  `index-selfcheck` (unchanged — `find --importers` with one path stays byte-identical) · `retire-board` (§ 2.1 refusals write nothing; `--by` and
  `--map`; rewired dependent; ready → backlog; one commit subject; `status` unchanged; `status --all`
  lists the retired card; a re-run `new` refuses a draft that depends on a retired ID).
- T-314: `builder-cmds` (grant refused from a feat branch and from inside a worktree; `release --to
  blocked` of an unclaimed ready card; an empty feat branch removed; `handoff --hold` → review/ held,
  nothing landed, `next` never says `integrate` for it; `--no-before` with no visual path asks no
  capture; `approve --plan` writes the plan marker) · `next-own-folder` (a lock with line 6: `next`
  from the primary does not say `resume`, from the worktree it does; a stale tune-due + a quiet board →
  `next` and bare `triage` recompute and answer from the fresh verdict).
- T-315: `wave-check` (a wave whose joined tree fails a mapped test does not seal, names the card,
  `integrate/<date>` still open; a green wave seals and writes the stamp; `test:` unset is silent; an
  unmapped path runs `test:` verbatim; `seal --no-check` records the why) · `amend-deps` (§ 4).
- T-316: `update-registry` (case-folded duplicate removed, worktree skipped, no-VERSION entry removed,
  typed `--all` forces the channel, `--auto` re-asks a same-version cache older than an hour) ·
  `update-pending` (a publish: pr fixture whose only dirt is its recorded pending update is not held;
  one kit file edited after the record is) · `speed-plan` re-pinned (a 13-point chain card priced from
  its points, the release-checks lines) · `proof-ci` re-pinned (a cancelled job → push-run fallback).
- T-317: `pack-named-tests` and § 10's list.
