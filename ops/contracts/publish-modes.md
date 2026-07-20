# CONTRACT: publish-modes            (v1 — 2026-07-20)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates HOW a sealed wave reaches origin's `<base>`: direct push (today) vs one host PR per wave.

## Interface
```
CONVENTIONS key:  publish: direct | pr      # default direct; absent → direct;
                                            # unknown value → warn once, behave as direct
```
Read via `cfg` at command runtime, never cached.

### direct (today's behavior + friendlier failure)
- handoff pushes feat/<ID>; seal merges --no-ff locally, tags, pushes base + tag — all unchanged.
- NEW: a rejected `<base>` push at seal keeps the existing by-hand note AND adds one line suggesting
  `publish: pr` (protected-branch detection). Rejection stamps `$PRIMARY/.polaris/base-push-rejected`
  (date + running count); a successful base push deletes the stamp. `doctor`: stamp count >= 2 →
  warn "origin keeps rejecting pushes to <base> — protected branch? set publish: pr in
  ops/CONVENTIONS.md". (Stamp + doctor warning land with T-024; the suggestion line with T-022.)

### pr
- `handoff`: NO `git push origin feat/<ID>` — feat branches never leave the machine. All else identical.
- `seal` (pr): preconditions unchanged (integrate/<date> exists · >=1 non-chore subject · tag gate
  per clean-history v2, checked BEFORE anything mutates). Then:
  1. generate + commit the wave's sprint report on integrate/<date> (per ops/contracts/sprint-report.md;
     step arrives with T-023 — until then seal skips it),
  2. push ONLY `integrate/<date>` to origin (no base, no tag, nothing else),
  3. print the PR-create URL + suggested title `Sprint <n> — <goal>` + description (the per-task
     bullet list seal already builds),
  4. fire `notify-gate done`.
  NO local merge; base untouched (local and remote); tasks stay in review/; locks stay; the
  integrate branch stays until `seal --sync`.
- URL composition from `git remote get-url origin` matching `bitbucket.org` (ssh or https):
  `https://bitbucket.org/<workspace>/<repo>/pull-requests/new?source=integrate/<date>&dest=<BASE>`.
  Non-Bitbucket or unparseable origin → print source/dest branches and say "open a PR from
  integrate/<date> into <base> on your host" (never die).
- The human merges the PR with the host's MERGE COMMIT strategy (never squash — the per-task
  squash commits must survive on `<base>`).
- `seal --sync [<date>]` (pr mode only; in direct mode → die "publish: direct seals locally —
  nothing to sync"):
  1. clean tree required; `git pull --ff-only origin <base>` (never rebase, never merge).
  2. verify EVERY `[<ID>]` subject on integrate/<date> is now in `<base>` history. Any missing →
     die naming them; nothing mutated.
  3. tag per clean-history v2 on the new `<base>` HEAD: absent → create sprint/<n>; existing
     ancestor tag → move (`tag -f`) + compare-and-swap push
     (`--force-with-lease=refs/tags/sprint/<n>:<old>`); existing non-ancestor → die (reused number).
     Tag-push failure → by-hand note, as seal does today.
  4. delete integrate/<date> local + remote (`git push origin :refs/heads/integrate/<date>`).
  5. note the next step: `run-verify` / `done` per task (done's `[<ID>]`-in-base gate now passes).

## Invariants
- pr-mode seal changes NO ref on `<base>` (local or remote) and creates no tag before --sync.
- `done`'s remote feat-branch cleanup and `sweep`'s remote-stray pass stay correct when feat
  branches were never pushed (existing tip-equality guards make them no-ops).
- Every die/note keeps the ⛔/✅ output format; bash >= 3.2 (NO `case` inside `$(...)`), POSIX awk.

## Executable check
Selftest drill `pr-publish` (T-022) against a scratch bare origin, simulated PR merge included;
runs via `bash kit/ops/polaris doctor --selftest`.

## Example
publish: pr · wave lands T-7, T-8 → `seal` → origin gains ONLY integrate/2026-07-20; output ends
with `https://bitbucket.org/acme/arc/pull-requests/new?source=integrate/2026-07-20&dest=main`.
Human merges (merge commit) → `seal --sync` → base pulled, `[T-7]` `[T-8]` verified, sprint/4
tagged + pushed, integrate/2026-07-20 gone both sides → `done T-7`, `done T-8`.

## Changelog
- v1 2026-07-20: created for T-022, T-024 (consumed by T-025, T-026)
