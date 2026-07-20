# CONTRACT: status-brief            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates the human-readable digest (`status --brief`, metrics summary line — T-032) from the
machine views, which stay untouched: one plain-English paragraph a human actually wants mid-run.

## Interface — `status --brief` (T-032)
```
polaris status --brief      # ONE paragraph, plain English, no table. Plain `status` unchanged.
```
Skeleton (placeholders filled from the board; clauses with nothing to say are DROPPED, not zero-padded):
```
Sprint <n> (<goal>): <done> done · <active> building (<IDs>) · <review> waiting to land · <ready> queued.
Last landed: <title of newest done/ task>. Next up: <top-wsjf ready title>.
```
- `<done>` = count of `done/`; `<active>`/`<review>`/`<ready>` = column counts; `<IDs>` = active ids.
- Fixed grep-stable markers (write VERBATIM): `Last landed:` and `Next up:`.
- Newest done = highest-mtime file in `ops/board/done/` (good enough; no telemetry parse).
- No SPRINT header → open with `No sprint header —` instead of the sprint clause.
- Empty board columns everywhere → still one paragraph, e.g. `Nothing building.` + whatever clauses apply.

## Interface — metrics summary line (T-032)
FIRST output line of `polaris metrics`, ABOVE the existing table, starting VERBATIM `In plain English:`:
```
In plain English: <done> tasks done, a typical task takes <p50>h door to door; building averages
<build>h, landing <integrate>h; <kickbacks> bounced.
```
One line, built from the numbers the awk already computes. EVENTS empty → existing
`no telemetry yet` note unchanged, no summary line.

## Executable check (rides the kit selftest — T-032 adds)
Drills in `selftest()`: `status --brief` output matches `Last landed:` and `Next up:` and contains no
`|` table pipe; `metrics` first line matches `^In plain English:`. Run: `bash kit/ops/polaris doctor --selftest`.

## Invariants
- Plain `status` and the `metrics` table below the summary stay byte-identical to today.
- The paragraph follows `voice: standard` rules: no `wsjf`, no `files_owned`, no jargon.
- Bash >= 3.2; no `case` inside `$(...)`.

## Example
```
$ ops/polaris status --brief
Sprint 5 (The fast lane): 2 done · 2 building (T-031, T-034) · 1 waiting to land · 3 queued.
Last landed: brain command. Next up: conductor express triage.
```

## Changelog
- v1 2026-07-20: created for T-032
