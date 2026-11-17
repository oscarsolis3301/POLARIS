# CONTRACT: the hour — push once, one heavy job, fewer cards, a price on every plan   (v1 — 2026-11-16)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/hour.md` (approved by the owner in plan mode, 2026-11-16). Kit release: 6.17.0. Slug: `hour`.

## Purpose
Separate the six cards of the hour program: the heavy slot and the new keys (T-300), the landing tail in
builder.sh (T-301), the price of a plan in admin.sh (T-302), the card rules and the lighter `next`
(T-303), the one push at the end in integrate.sh / qa.sh / observe.sh (T-304), and the words plus the
release (T-305). Every name, line and default below is pinned so each card codes against it alone.

## Cross-card rules (every card)
- Every NEW function is private (`_name`), so no card owns `ops/tests/api-kit.expected`; every lib card
  carries `api-kit` in its verify line to prove no public name crept in.
- An unset key composes to the NEW behaviour in kit code (`update` never rewrites a repo's
  CONVENTIONS.md). Every default below is the in-code default.
- Lock order, outermost first: integration lease (`int_on`) → heavy slot (`_heavy_on`) → board mutex
  (`mutex_on`). Nothing takes the heavy slot while holding the board mutex; nothing takes the lease
  while holding the heavy slot (a child re-entering by token is not a take).
- bash 3.2: no `case` inside `$(...)`, no `${v,,}`, no `wait -n`, no arrays in new code paths that run
  on macOS hooks; never fork per item in a loop over the board.
- Tests fake HOME and USERPROFILE together and never touch the real `~/.claude`; a golden prints no sha,
  time or absolute path; scratch paths are namespaced `<scratch>/<ID>/…`.
- `kit/` is the source; the root `ops/` is the dogfooded copy and no card edits it. `.github/` is not
  touched. Nothing is deleted.

## 1. Keys (T-300 owns all three rows of `kit/ops/KEYS.tsv`)
Appended after the `publish` row, TAB-separated, column 5 empty:
```
push	6.17.0	end	end: code reaches origin once, when finish closes the run (default with claim: local-lock); wave: every seal pushes base and its tag in one push (default with claim: claim-branch)
heavy_slots	6.17.0	1	how many heavy jobs (verify lists, qa, the express suite, the push) run at once on this machine; 0 = no limit
target_minutes	6.17.0	60	speed --plan compares a plan's projected time with this; over it, the planner re-cuts once
```
The `default` column for `push` documents the local-lock value; the claim-branch value is in the cost
text. `keys-drift` goes strict only where every reader has landed: T-300, T-304 and T-305 carry it;
T-301 and T-302 read a key whose row lives in T-300 and must NOT carry `keys-drift` (cross-lane golden
rule, 2026-09-14).

## 2. `push: end | wave` (resolver T-301 in core.sh; handoff T-301; seal, done, finish, status T-304)
`_push_resolve` (core.sh, beside `publish_resolve`): sets `$PUSH`, never in a `$(...)`.
- `cfg push ""` = `end` or `wave` → that value.
- empty → `wave` when `$CLAIM_MODE` = `claim-branch`, else `end`.
- anything else → stderr once per invocation, then the claim-mode default:
  `   ⚠ push: '<v>' unknown (end | wave) — behaving as <default>`
- `publish: pr` ignores `push` entirely: every pr-mode path stays byte-identical.

Behaviour under `publish: direct`:

| step | `push: end` | `push: wave` |
|---|---|---|
| handoff | NO `git push` of `feat/<ID>`; no ⚠ Note, no `push-fail` event; the stray-feat repair is not reached | today, byte for byte |
| done | no `ls-remote`, no remote delete (nothing was pushed) | today, byte for byte |
| seal | merge + tag locally, no push; one note: `seal: kept on this machine — finish pushes base and tags in one push (push: end)` | ONE `git push --atomic` carrying `$BASE` and `refs/tags/sprint/<n>` (a moved tag rides as `--force-with-lease=refs/tags/sprint/<n>:<old>`); success → `base_push_clear`, rejection → `base_push_reject` + today's ⚠ notes |
| finish (green path only) | the one push, below | the same catch-up push when anything is still ahead (normally nothing) |

**The one push** (finish, after the `board clear` line and its caveats, before the done signal; skipped
with no remote or under `publish: pr`):
- reads ONE `git ls-remote origin "refs/heads/$BASE" 'refs/tags/sprint/*'`; ahead = commits in
  `$BASE` not at origin's `$BASE`; a tag counts when origin lacks it or holds another sha.
- nothing ahead and no tag to send → no push, no line.
- else ONE `git push --atomic origin "refs/heads/$BASE:refs/heads/$BASE" <tags>` — a new tag as a plain
  refspec, a moved tag with `--force-with-lease=refs/tags/sprint/<n>:<origin sha>`.
- green → `say "pushed: <n> commit(s) and <k> tag(s) to origin in one push"`; `base_push_clear`.
- red → `base_push_reject`, stderr
  `⛔ finish: the push to origin failed — <n> commit(s) stay on this machine only; nothing else changed — run finish again`,
  rc 1, no done signal, no finish stamp.
- the board ref is never part of it (the board keeps syncing as it goes).

**status** (`cmd_status`, observe.sh): when `publish: direct`, a remote exists, the tracking ref
`refs/remotes/origin/$BASE` exists and `rev-list --count origin/$BASE..$BASE` = n > 0, one note line,
no network:
- end: `   on this machine only: <n> commit(s) — finish pushes them in one push (push: end)`
- wave: `   on this machine only: <n> commit(s) — the next seal pushes them (push: wave)`
n = 0, no remote, no tracking ref, or pr mode → no line.

## 3. The heavy slot (T-300: workspace.sh + ownership.sh; T-304 wraps its own sites)
Same mechanism as the integration lease (atomic `mkdir` + `epoch`/`who`/`pid`/`why`/`token` files and a
token exported to children) — written as new private functions; `int_on`/`int_off`/`int_mine` are NOT
edited, so `busyint`, `lease-token` and `land-race` stay byte-identical.
```
_heavy_on <why>    # rc 0 always — never refuses work
_heavy_off         # releases only in the frame that took it, only while its token matches
```
- Dir: `${POLARIS_HEAVY_DIR:-$HOME/.claude/polaris/heavy}`, slots `slot-1` … `slot-<N>`; it spans
  worktrees and projects on purpose. A slot also records `repo` (= `$PRIMARY`) so a waiter can name it.
- N = `cfg heavy_slots 1`; `0` → both functions are no-ops; non-numeric → 1.
- Re-entrant: `POLARIS_HEAVY_TOKEN` matching any slot's token → rc 0, nothing taken (children of a
  holder — a golden or drill running the kit inside a verify line — never wait on their parent).
  Same pid already holding → rc 0.
- Busy: poll every 2 s; every ~30 s one note
  `heavy: waiting for <who> (<why>, <m>m, <repo basename>) — one heavy job at a time on this machine`.
- Steal, with one note `heavy: took a stale slot from <who> (<reason>)`: the holder pid is dead (checked
  on the first busy look and at each 30-s note; dead = `kill -0` fails, on msys/cygwin absent from one
  `ps -W`), or its epoch is older than 120 min.
- Fail-open: still busy after `${POLARIS_HEAVY_WAIT:-1800}` seconds → note
  `heavy: waited <m>m for <who> — running without the slot`, rc 0, nothing taken.
- No crash trap is added (core.sh `on_die` is not edited): a dead holder is stolen by the next waiter.
- Known cost, accepted: a verify line that only waits on CI (`tools/proof.sh`) holds the slot while it waits.

Wrapped sites — each takes the slot once around the whole job and releases it right after:
| site | file | card |
|---|---|---|
| `run_verify_cmds` (the whole list; covers builder `verify`, `handoff`, integrator `run-verify`) | ownership.sh | T-300 |
| `cmd_qa`'s suite run | qa.sh | T-304 |
| `land --express`'s suite loop | integrate.sh | T-304 |
| the one push in `finish`; the seal push under `push: wave` | qa.sh, integrate.sh | T-304 |

## 4. Lanes from the log (T-302, `cmd_speed`)
Bare `speed` gains at most two lines, printed right after `built → done: median …`, from the same
EVENTS read (one awk). For each task: its build interval is `[last claim ≤ handoff, last handoff ≤ done]`
(the pairing the medians already use). Lanes in use for a task = how many build intervals (its own
included) contain the midpoint of its interval. Buckets: 1, 2, 3, 4, `5+`, over the last 200 tasks by
done time; a bucket prints only with n ≥ 3. Median as `med()` does today, whole minutes.
```
build by lanes: 1 lane 29 min (n=12) · 2 lanes 44 min (n=30) · 5+ lanes 97 min (n=8)
lanes: 2 — the most cards per hour here (2.7 an hour)
```
Cards per hour = L × 60 / median, one decimal (`5+` counts as 5); ties go to fewer lanes. No bucket with
n ≥ 3 → neither line.

## 5. The price of a plan (T-302, `speed --plan <slug> [<draft.md>…]`)
Read-only, no git history walk. Cards = board tasks with `plan: <slug>` in backlog/ ready/ active/
review/ blocked/ (never done/), plus each draft named (counted whatever its plan; its `id:` resolves
depends_on between drafts). Output, exactly three lines, then the fourth only when over target:
```
plan <slug>: <C> cards · <W> waves on the critical path · <L> lanes
each card: about <B> min to build + <D> min to land (<source>)
projected: about <T> (target <M> min)
over the target — re-cut once: merge each chain into one card with steps:, fold riders into the card that causes them; still over, it runs as one release and this projection is shown before approval
```
- W = the longest `depends_on` chain inside the card set (a dep outside the set, or in done/, adds 0;
  a card with none is 1).
- L = the `lanes:` value of § 4 when it exists, else min(C, 5); always capped at C.
- B = the build median of bucket L when it has n ≥ 3, else the overall build median, else 30.
  D = the built → done median, else 15.
  `<source>` = `this project's medians at <L> lanes` | `this project's medians` |
  `no history here yet — kit defaults`.
- minutes = max(W, ceil(C / L)) × (B + D). `<T>` = `<minutes> min` when < 90, else `<x.y> h`
  (minutes / 60, one decimal, rounded half up).
- M = `cfg target_minutes 60` (non-numeric → 60); over = minutes > M.
- No card → `speed --plan <slug>: no cards carry plan: <slug>`, rc 1. Otherwise rc 0.
- `kit/ops/hooks/readonly-allow.sh` allows `speed --plan <slug>` with or without draft paths (it reads
  only); `speed --apply` keeps its prompt.
- Help text (T-302 owns `kit/ops/polaris`, including T-303's `new` line): the `speed` entry names
  `[--plan <slug> [<draft.md>…]]`, the lanes lines and the projection; the `new` entry reads
  `(points 1-5, or up to 13 with steps: · plan: · risk: · files_owned · a named contract`. The
  `cli-help` golden pins the INSTALLED help and is re-pinned after the dogfood, by the conductor.

## 6. Chain cards: `steps:` (T-303: author.sh, handover.sh, drift.sh, templates/TASK.md; pack T-301)
Shape, in the frontmatter, one list item per step: `<points 1-5> <what this step does>`.
```
points: 13
steps:
  - 5 the push key and the handoff gate
  - 5 seal and done under push: end
  - 3 finish makes the one push
```
ONE predicate everywhere (`new`, `next`'s promote pass, `drift`'s ready gate):
- points 1-5: legal; `steps:` optional, and when present it must pass the step rules.
- points 6-13: legal only with `steps:` of 2 or more items, each starting with a number 1-5 then a
  space and text, the numbers adding up to `points:`.
- anything else (empty, non-numeric, > 13): refused.
`new` refusals (each writes nothing):
```
new: <draft>: points: must be 1-5, or up to 13 with steps: (got <v>) — split anything bigger
new: <draft>: steps: a card over 5 points lists its steps (2 or more, each 1-5 points)
new: <draft>: steps: step <n> is not "<points 1-5> <what>"
new: <draft>: steps: steps add up to <s>, points: says <p>
```
promote (`next` / `next --do`) holds with: `held: <id> — points <p> must be 1-5, or up to 13 with steps: — split it`
(an empty `points:` keeps today's `held: <id> — points not set (must be 1-5)`).
drift: `READY GATE: <id> is <p>pts without valid steps: — must be split before ready/`.
`route` and `triage` are unchanged in code: `tier_for` already gives `strong` at ≥ 5 points, and a
chain card triages like any one task over 3 points.
`kit/ops/templates/TASK.md` gains, after `points:`, a commented `steps:` key describing the shape.
`pack` (T-301, builder.sh) prints, when the card has steps, a section right after the verify list:
```
STEPS — one commit per step; the verify lines that cover a step are green before the next one starts
  1. 5 pts — the push key and the handoff gate
```
No steps → no section, so every existing pack output is byte-identical.

## 7. A chain does not wait for the wave (T-301, builder.sh `self_land` / `_sl_last_out`)
Let P = the landing card's `plan:`.
- **Last lane out counts only this run's cards.** `_sl_last_out` ignores every ready/ active/ review/
  task whose `plan:` is non-empty and differs from P (P empty → today's count, byte for byte). The
  handoff notice (`all-review` event, `integrate`/`queue` lines) is unchanged.
- **Seal on demand.** After a green `land`, when `_sl_last_out` says no: if a backlog/ task of plan P
  (P non-empty) has every `depends_on` either in done/ or a review/ task already landed (`landed_sha`),
  and at least one of them is such a landed review/ task, note
  `seal on demand: <SUCC> waits only on work that just landed — sealing the wave now so it can start`
  and take the last-lane-out tail (seal, then `done` for every landed review/ task, own ID last).
- **Promote in the same step.** After either tail, when a backlog/ task of plan P now has every
  `depends_on` in done/, run `( cd "$PRIMARY" && "$SELF" next --do )` once, inside the lease, and pass
  its output through. No such task → nothing runs, so every existing self-land output is byte-identical.
- Under `push: end` a seal pushes nothing, so seal on demand costs seconds; under `wave` it costs one push.

## 8. A lighter board (T-303 `next_promote`; T-301 `resolve_sprint_ids`)
- `next_promote`: the backlog scan reads every backlog/ task's `id wsjf points contract plan deps steps`
  in ONE awk pass over `backlog/*.md`, the in-flight plan in one more pass over ready/ active/ review/,
  and resolves deps against one listing of each column. No `fm_get` and no `dep_ids` remain inside the
  function; `fm_list files_owned` stays for the disjointness walk of tasks that reached it. Every line
  it prints (`held:` lines, promoted IDs, the board commit) is byte-identical.
- `resolve_sprint_ids`: at most three git processes whatever the size of done/ — one `git log` for
  Rule 1 (subjects and bodies together), one `git rev-list` of `sprint/<n>` (excluding `sprint/<n-1>`
  when it exists) for Rule 2 — and ONE awk over `done/*.md` for `id:` + `landed:`, joined against the
  rev-list (a `landed:` shorter than 40 hex matches by prefix). No `merge-base` and no `fm_get` remain
  inside the function. Output (sorted, deduped IDs) is byte-identical.

## 9. Words (T-305)
Pinned phrases (verify greps them):
- `kit/CLAUDE.md` Invariant 2: `A task enters \`ready/\` only if: ≤5 points (a chain card: up to 13, with \`steps:\` each ≤5), every …`
  Invariant 4: `**Green before \`review/\`.** The card's own \`verify:\` checks green AND \`polaris verify\` green; the full suite runs once per wave, never per card. Red work never leaves \`active/\`.`
- `kit/ops/PROTOCOL.md` § LANES gains: `Checks cost no tokens — they cost minutes.` and `The unit to save is a card.`
  plus the three keys and `speed --plan` in the command table.
- `kit/ops/roles/PLANNER.md`: the estimated-time line comes only from `bash ops/polaris speed --plan <slug>`
  (run on the drafts before `new`, again after); over `target_minutes` → re-cut once (merge chains into
  `steps:` cards, fold riders), then file it as ONE release and put the `projected:` line in the report;
  owner-only "record" cards are not cards — they go in the close. Pointing table: 8 and 13 are legal
  only as chain cards.
- `kit/ops/roles/CONDUCTOR.md`: lanes = min(ready, `autolaunch_max`, the `lanes:` value of `speed` when
  it prints one); the plan shown for approval carries the `projected:` line; every close quotes it and
  the real time.
- `kit/ops/roles/BUILDER.md` and `SOLO.md`: the card's own checks per card (never the whole suite); a
  chain card is built step by step, one commit per step.
- `kit/ops/roles/INTEGRATOR.md` + `kit/ops/MANUAL.md`: under `push: end` a seal pushes nothing; `finish`
  makes the one push.
- `kit/ops/VERSION` → `version: 6.17.0`; `CHANGELOG.md` `## 6.17.0 — <date>` in plain words.

## Executable check
| card | proof |
|---|---|
| T-300 | new golden `ops/tests/heavy-slot.{cmd,expected}` (POLARIS_HEAVY_DIR in mktemp, POLARIS_HEAVY_TOKEN unset): (a) two `run-verify` calls started together on a fixture task whose verify line logs start/end with a 2-s sleep never overlap; (b) a slot held by a live pid → the waiting note, then the run once it frees; (c) a dead-pid holder → the stale-slot note at once; (d) `heavy_slots: 0` → no slot dir is ever made; (e) a child carrying the holder's token re-enters without waiting; (f) `POLARIS_HEAVY_WAIT=2` and a live holder → the running-without note, rc 0. Plus `keys-drift` strict. |
| T-301 | `drill_selfland` (selftest/history.sh) gains: (a) a wave seals with another plan's card in ready/; (b) plan X: A lands while sibling C (plan X) is still active with a live beat, B (backlog, depends on A) → the seal-on-demand note, A in done/, B in ready/ in the same self-land. `drill_remote` and `drill_pushdegrade` (selftest/remote.sh) run their existing assertions under an explicit `push: wave` (restored after), and drill_remote gains: (c) unset push → handoff leaves origin with no `feat/<ID>` and logs no `push-fail`. New golden `ops/tests/pack-steps.{cmd,expected}`: a 13-point steps card's pack prints the STEPS section; a card without steps prints none. Static: no `merge-base`/`fm_get` in `resolve_sprint_ids`; `drill_report` (Rule-2 attribution) unchanged and green. |
| T-302 | new golden `ops/tests/speed-plan.{cmd,expected}` (fixture board + EVENTS): the three lines for a 6-card plan with a 3-link chain; the re-cut line when `target_minutes: 10`; drafts counted with their own ids; kit defaults with no EVENTS; rc 1 line for an unknown slug; repo byte-identical after. `speed-report` re-pinned with the two lanes lines (fixture gains overlapping tasks) and silent when no bucket reaches n=3. `readonly-allow` re-pinned: `speed --plan hour` and `speed --plan hour a.md` allow, `speed --apply` asks. |
| T-303 | `drill_newcmds` (selftest/board.sh) gains: `new` files a 13-point card with three valid steps; refuses 13 without steps, steps adding to 12, a step of 8, points 21 — each with its pinned line and nothing written; `next --do` promotes a valid chain card and holds an 8-point card without steps with the pinned held line; `drift` reports the pinned READY GATE line for it and nothing for the valid one. Goldens re-pinned: `new-task` (steps cases), `handover-route` (new held line). Static: no `fm_get`/`dep_ids` in `next_promote`. |
| T-304 | `drill_remote` (selftest/remote.sh) gains, with a `git` stand-in first on PATH counting `push` calls that name anything but `polaris/board` (the T-285 pattern in drill_autoupdate): (a) under unset push: handoff, land, seal and done leave origin's refs other than `polaris/board` unchanged, `status` prints the on-this-machine line, `finish` makes exactly ONE such push carrying base and the sprint tag, origin's base equals local after, `status` prints no line, a second `finish` makes zero; (b) under `push: wave`: each seal makes exactly one such push with base and tag. `express-pr` and `pr-one-link` stay byte-identical (pr mode untouched). |
| T-305 | the § 9 greps; `plain-voice` stays green. |
Every drill change is proven in a SERIAL multi-drill run that includes the origin-creating drills:
`PROOF_GOLDENS=true bash tools/proof.sh` (CI Linux, serial, about 4 min) — never a lone `--only` run.

## Invariants
- `publish: pr` behaviour is byte-identical everywhere (handoff, seal, done, finish, express).
- `push: wave` is today's behaviour except that a seal's two pushes become one atomic push.
- Nothing refuses work because of the heavy slot; nothing refuses a plan because of its price.
- `int_on`/`int_off`/`int_mine`, `on_die`, `tier_for` and `publish_resolve` are not edited.
- The first push of a run under `end` is `finish`'s; the board ref keeps syncing as it goes.

## Example
```
$ bash ops/polaris speed --plan hour
plan hour: 6 cards · 2 waves on the critical path · 4 lanes
each card: about 37 min to build + 4 min to land (this project's medians)
projected: about 82 min (target 60 min)
over the target — re-cut once: merge each chain into one card with steps:, fold riders into the card that causes them; still over, it runs as one release and this projection is shown before approval
```

## v1.1 — 2026-11-16: who owns `ops/tests/api-kit.expected`
Supersedes the v1 cross-card line "no card owns `ops/tests/api-kit.expected`". `api-kit` runs
`find --api 'kit/*'`, which pins more than functions: every public (non-`_`) shell/python function and
constant, every h1-h4 heading of a `kit/**/*.md` file (role files, PROTOCOL, MANUAL, PROMPTS,
kit/CLAUDE.md, templates — including a column-0 `# …` comment line in `templates/TASK.md`), and the
first column of every row of a `kit/**/*.tsv` file (KEYS.tsv). So:
- **T-300 owns it first**, for exactly the three `kit/ops/KEYS.tsv	key	push|heavy_slots|target_minutes`
  rows of § 1 — nothing else in that file moves.
- **T-305 owns it after T-300** (it already depends on T-300), for any heading it adds, rewords or removes
  in the files it owns; prefer sentences to new headings. T-305 carries `api-kit` in its check line.
- **No other card moves it.** T-301, T-302, T-303 and T-304 add no public function, no new `drill_*`
  function (they extend existing drills) and no heading; T-303 writes the template's `steps:` key as a
  real key with an inline comment (`steps:   # …`) or an indented comment — never a column-0 `# steps:`
  line, which would be a heading row. Each keeps `api-kit` in its verify line as the proof.
- Order: T-300 → T-305. T-304 never touches the file, so T-304 and T-305 still run side by side.

## Changelog
- v1 2026-11-16: created for T-300 … T-305 (plan `hour`, kit 6.17.0).
- v1.1 2026-11-16: ownership of `ops/tests/api-kit.expected` (T-300 then T-305); the TASK.md `steps:` shape that keeps it still.
