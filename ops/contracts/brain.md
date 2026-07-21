# CONTRACT: brain            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the brain GENERATOR (`polaris brain`, freshness hooks in `seal`/`done`/`doctor` — T-030) from
its CONSUMERS (role files, CONDUCTOR kickoff templates, kit CLAUDE.md, MANUAL — T-034/T-035/T-036/T-037):
a generated, git-ignored, any-model-readable knowledge base that kills cold-start context re-derivation.

## Interface
```
polaris brain               # full build of .polaris/brain/ (create or overwrite)
polaris brain --refresh     # incremental: board.md/contracts.md/commands.md/gotchas.md always rebuilt
                            # (cheap — few small sources); code-map.md rebuilt ONLY when
                            # `git diff --name-only <stamp-sha>..HEAD` is non-empty. Missing brain → full build.
# exit 0 on success; never mutates the board, never touches git refs, never writes outside .polaris/brain/
```

## Layout — `.polaris/brain/` (under `.polaris/`, therefore gitignored; NEVER git-added)
| File | Content | Cap |
|---|---|---|
| `INDEX.md` | routing table: one `looking for X → read Y` row per domain file below, plus the hop guarantee line | ≤40 lines |
| `code-map.md` | per-directory: purpose (1 line) + key symbols (grepped `^cmd_\|^def \|^function\|^class` etc.) + hotspot flag (from ops/MAP.md hotspot section when present) | ≤15 lines/dir, ≤300 total |
| `board.md` | live digest: `# SPRINT <n> — <goal>` header line · per-column counts · active (id · owner) · ready top 5 by wsjf (id · title · pts) · blocked (id · reason) · last 10 done (id · title · landed sha when stamped) | ≤80 lines |
| `contracts.md` | per `ops/contracts/*.md`: `## <name>` + its `## Purpose` first paragraph; no contracts dir → `none` | ≤120 lines |
| `commands.md` | effective CONVENTIONS values (base · claim · integration · publish · express · stale_hours · test · build) FIRST, then `polaris help` output — the cap may cut the help tail, NEVER the values (v1.1) | ≤80 lines |
| `gotchas.md` | SPRINT.md `## Learned` bullets verbatim + CONVENTIONS `## Planner calibration` bullets verbatim | ≤60 lines |
| `.stamp` | machine line: `<epoch> <BASE short sha>` — written by every brain run | 1 line |

## Hop guarantee (INDEX.md must state it)
Any fact is reachable in ≤4 file-opens starting from `INDEX.md` (INDEX = hop 1, domain file = hop 2,
repo file the domain file cites by path = hops 3–4). Scale by SUMMARIZING PER DIRECTORY, never by
listing files — a multi-thousand-file repo stays within the caps above. Pinned count phrasing (v1.1,
consumer docs copy it verbatim): the layout is "7 entries — 6 `.md` files + `.stamp`"; greenfield
repos get "the same 6 `.md` files, near-empty".

## Freshness
- `done <ID>` and `seal` (both publish modes; `--sync` included) touch `.polaris/board-changed`
  (epoch line) after their board/base mutation succeeds. Best-effort: a touch failure never fails them.
- `seal` additionally AUTO-REFRESHES: after a successful fold, `[ -d .polaris/brain ]` → run
  `brain --refresh`; failure prints a `⚠` note and never fails the seal. No brain dir → do nothing.
- (v1.1) `done <ID>` AUTO-REFRESHES the same way, mirroring seal: after its board mutation and
  `board-changed` touch, `[ -d .polaris/brain ]` → run `brain --refresh`; failure prints a `⚠` note
  and never fails the done. No brain dir → do nothing. Net effect: the documented wave close
  (land → suite → seal → run-verify → done) ends FRESH — `doctor` prints no `brain is stale`.
- `doctor`: `[ -d .polaris/brain ]` AND `.polaris/board-changed` newer (`-nt`) than
  `.polaris/brain/.stamp` → one warn line containing `brain is stale` and naming
  `ops/polaris brain --refresh`. No brain dir → silent (feature is opt-in by first run).

## Consumers — pinned phrases (grep targets; write them VERBATIM)
- Role files BUILDER/PLANNER/INTEGRATOR "read first" sections + CONDUCTOR subagent kickoff templates
  + kit CLAUDE.md TOKEN DISCIPLINE gain: `read .polaris/brain/INDEX.md FIRST, repo second`
  (formatted per file, but the literal substring `.polaris/brain/INDEX.md` FIRST must appear).
- The brain SUPERSEDES raw MAP reads for subagents; `ops/MAP.md` stays the tracked source the brain
  digests — consumer docs must keep MAP as the fallback when no brain exists.

## Executable check (rides the kit selftest — T-030 adds, later tasks re-run)
Drills in `selftest()` of `kit/ops/polaris`, asserted in the throwaway repo:
1. `brain` → all 7 files above exist; `git status --porcelain` shows NO brain path (untracked stays untracked).
2. `INDEX.md` names all 5 domain files (routing resolves).
3. `board.md` contains the selftest's landed task id `T-1`.
4. Staleness: `board-changed` touched newer than `.stamp` → `doctor` output matches `brain is stale`;
   after `brain --refresh` → warn gone.
5. Seal auto-refresh: with a brain present, a seal leaves `.stamp` newer than `board-changed`.
6. (v1.1) Commands keys: after `brain`, `commands.md` contains ALL 8 CONVENTIONS keys (`base:` ·
   `claim:` · `integration:` · `publish:` · `express:` · `stale_hours:` · `test:` · `build:`) —
   fail token `BRAIN COMMANDS KEYS FAIL`.
7. (v1.1) Post-done freshness, REAL order: with a brain present, land → seal → run-verify → done →
   `doctor` output does NOT match `brain is stale` — fail token `DONE BRAIN STALE FAIL`.
Run: `bash kit/ops/polaris doctor --selftest`.

## Invariants
- Bash >= 3.2 only (no mapfile, no assoc arrays, NO `case` inside `$(...)`), stdlib/git/grep/awk/sed only.
- Brain generation reads the repo; it never writes outside `.polaris/brain/` + the two stamp files.
- Full `--selftest` semantics unchanged: every existing drill still runs, pass line still starts `selftest passed`.

## Example
```
$ ops/polaris brain
✅ brain built: .polaris/brain/ (INDEX + code-map + board + contracts + commands + gotchas) · stamp 1789… abc1234
$ ops/polaris doctor        # after a done, before a refresh
⚠ brain is stale — run: ops/polaris brain --refresh
```

## Changelog
- v1 2026-07-20: created for T-030 (generator + hooks) · T-034/T-035/T-036/T-037 (consumers)
- v1.1 2026-07-20 (QA fix wave, T-038): (a) commands.md prints CONVENTIONS values BEFORE the help
  dump — `head -n 80` was cutting 5 of 8 values (usage() alone is ~75 lines); drill 6. (b) `done`
  gains seal's auto-refresh so a completed wave ends fresh — `cmd_done` touched `board-changed`
  AFTER seal's refresh, guaranteeing a stale warn; drill 7 asserts the real order. (c) pinned count
  phrasing "7 entries — 6 `.md` files + `.stamp`" reconciles MANUAL's 7-vs-6 contradiction.
