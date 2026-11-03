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
- v1.1 2026-07-20 (QA fix wave, T-027 + T-028): corrects the --sync missing-subject die wording — by the time it fires, step 1 has ALREADY moved local `<base>` (--ff-only pull), so "nothing mutated" is false. The die keeps naming the missing IDs and now states the pinned phrase "already fast-forwarded" plus that tag, integrate/<date> and the board are untouched. `kit/ops/MANUAL.md` --sync step 2 mirrors the same wording (T-028).

## v2 — one link per run  (plan: one-link · 2026-11-03 · T-228..T-231)
Why: under `publish: pr` every dependency layer cost a PR, a human merge and a "continue?" stop.
v2 makes pr mode behave like direct mode LOCALLY and ships the whole run as ONE link at the end.
Consumed by T-228 (seal/sync), T-229 (finish/triage), T-230 (hook/caps), T-231 (prose).

### Local staging seal (pr mode)
- `seal` in pr mode merges the wave into LOCAL `<base>` and tags `sprint/<n>` locally exactly as direct
  mode does, but pushes NOTHING (no `<base>`, no tag, no `integrate/<date>`). Tasks reach `done/`
  normally, dependents are claimable at once, and claims see the earlier code.
- Local `<base>` therefore RUNS AHEAD of origin until the human merges the PR. That is intended.
- `land --express` and `triage` no longer treat pr as special: small requests take the SOLO/express lane.
- Legacy: a pushed `integrate/<date>` from the v1 flow still works with `seal --sync` (steps in v1).

### ship branch
- Name `ship/<date>` (the run's first-ship date, YYYY-MM-DD). Reuse rule: an open `ship/*` on origin
  is reused (fast-forward only), so the same PR updates; none open -> create `ship/<today>`.
- `finish` (pr mode, all else green, local `<base>` ahead of origin) pushes local `<base>` to
  `origin ship/<date>` fast-forward, prints EXACTLY ONE link via `pr_create_url <source-branch>`
  (source arg defaults to `integrate/<date>`), writes `.polaris/ship`, fires `notify-gate done`, exits 0.
  The pending reasons "on integrate", "waiting to land", "integrate not in main" and the unpushed
  caveat do not apply in pr mode. Nothing ever pushes to `<base>` itself.

### `polaris sync` (pr mode only; silent; runs at the top of `triage` and in `next`'s entry; ONE fetch)
| origin state | action | output |
|---|---|---|
| ship branch merged into origin `<base>` (merge commit) | `pull --ff-only`, push tags, delete `ship/*` local + remote | one line |
| ship branch not merged / none | nothing; new work stacks on the same ship branch | none |
| squash-merged or diverged `<base>` | touch nothing | one ⛔ line |
| offline / fetch fails | touch nothing | one ⚠ line |
Direct mode: `sync` is a no-op.

### Stop-hook bounce rule
A closing message ending in "?" is bounced ONCE while `next` line 1 is `build|integrate|promote`:
"Work left — next says <line>. The plan approval covers it; do it. A real product/approval question?
ask again and you will be let through." The second attempt (`stop_hook_active`) passes. `next` line 1
`finish|wait|stop` keeps the question allowed.

### Run-cap rule
`run_max_tasks` / `run_max_minutes` / `run_max_agents` and the hook's `allow:cap` count ONLY work
outside the session's recorded plan (`.polaris/handover/<sid>/plan`). Fix waves, scouts and foreign
drain still count. Runaway-guard agent cap = max(run_max_agents, 2 x plan tasks).

### Executable check
Golden `pr-one-link` (T-229): 3 chained tasks reach `done/` with no human step · origin gains only
`ship/<date>` (pre-receive rejects `<base>`) · `finish` exits 0 with exactly one link · simulated merge
then `triage` syncs · unmerged + second run fast-forwards the same ship branch.

- v2 2026-11-03: one-link program; breaking-ish: pr-mode `seal` no longer pushes `integrate/<date>`.
