# CONTRACT: visual-check            (v1 — 2026-09-01)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/v2.md` WS4 (plan slug `cant-eat-itself`, 6.2.0). Tasks: T-096 (the four KEYS rows +
`kit/ops/VISUAL.md`, W1) · T-098 (`pack` section + `handoff` gate, W2) · T-100 (fleet kickoff line, W2) ·
T-103 (install manifest, W3) · T-105 (golden `pack-visual`, W3) · T-107 (role prose, W3).

## Purpose
"SEEING YOUR WORK" is pasted by hand every visual task. It becomes part of the Builder/SOLO contract,
driven by CONVENTIONS keys so each repo plugs in its own capture tool (`tools/shot.py`). Two halves,
neither replacing the other (G10): `handoff` proves a capture EXISTS (mechanical); prose proves someone
LOOKED (`saw:` line + the Integrator opens the PNG). Absent-by-default: a repo that sets no `visual:` key
sees nothing change.

## Interface — CONVENTIONS keys (T-096 appends these SIX rows to `kit/ops/KEYS.tsv` after `landing`, in
this order, byte-exact; `wt_live_minutes` is worktree-liveness's and `handover` is role-handover's — rows
are inert data and `keys-drift` ties `cfg` reads to rows, so ONE task registers all six)
```
wt_live_minutes	6.2.0	15	a task worktree counts as live for 15 minutes after its last beat; done/release/sweep never remove a live worktree
shot	6.2.0	<cmd or omit>	no capture step: pack prints no SEE YOUR WORK section and handoff never asks for a screenshot
visual	6.2.0	<globs or omit>	this repo declares no visual surface, so shot: never runs and a visually broken page can ship green
port_base	6.2.0	<number or omit>	{PORT} in shot:/serve: stays literal — parallel builders share one dev-server port
serve	6.2.0	<cmd or omit>	pack prints no way to start the app for a capture; builders improvise a server
handover	6.2.0	auto	a session hops into the role polaris next names at each board-proven boundary; off restores one task per session
```
Semantics (real `cfg` reads in `cmd_pack`/`cmd_handoff` — unlike `runnable:`/`qa_scout:`, which are prose-only):
- `shot: <cmd template>` — `{ID}` → the task id, `{PORT}` → the task's port. Output convention:
  `.polaris/shots/<ID>-<name>.png` (inside the repo so `Read` never prompts; `.polaris/` is ignored).
- `visual: <globs>` — space-separated `files_owned`-style patterns (exact · `dir/` · `*`); UNSET ⇒ the
  whole step is off (pack prints the unset line, handoff never gates).
- `port_base: <n>` — per-task port = `port_base + (numeric tail of ID mod 100)`; `T-207` ⇒ `port_base+7`;
  no digits in the ID ⇒ `port_base`; unset ⇒ `{PORT}` stays literal and pack adds a note. The human's own
  port is never touched (G3).
- `serve: <cmd template>` — how to start THIS worktree's server on `{PORT}`; optional.
- On Windows the product repo's `shot:` line is written with `python`, never `python3` (G12 — INIT's DERIVE
  row says so; T-107).

## Interface — `cmd_pack` (T-098; inline in the existing fn, NO new fn at any depth)
New `pack_section "SEE YOUR WORK — capture before handoff (ops/VISUAL.md)"` between §7 and §8:
- `visual` unset ⇒ ONE line: `(visual: unset — no capture step; ops/VISUAL.md explains how to add one)`
- set ⇒ lines, in this order (`<yes|no>` = `owned_match` (ownership.sh:14-26) of any `files_owned` pattern
  against the `visual:` globs — reuse it, both directions):
  `visual: <globs> · this task touches it: <yes|no>`
  `serve: <cmd with {PORT} substituted>` (only when `serve:` is set)
  `shot: <cmd with {ID} and {PORT} substituted>` (only when `shot:` is set; unset ⇒ `shot: (unset — set shot: in ops/CONVENTIONS.md; ops/VISUAL.md)`)
  `port: <n>` (or `port: (port_base unset — {PORT} stays literal)`)
  `proof: .polaris/shots/<ID>-*.png — then READ it and write one "saw: <what it shows>" line in your handoff`
  `read: ops/VISUAL.md`

## Interface — `cmd_handoff` capture-exists gate (T-098; after `run_verify_cmds`, before the board write)
Fires iff `visual` is set AND `shot` is set AND `git -C <wt> diff --name-only $BASE...feat/<ID>` has a path
matching a `visual:` glob. Then at least one file `$PRIMARY/.polaris/shots/<ID>-*.png` must be non-empty
AND have mtime ≥ the commit time of `git merge-base $BASE feat/<ID>` (`stat -c %Y || stat -f %m`), else:
`die "⛔ handoff refused: <ID> changed a visual: path but .polaris/shots/<ID>-*.png has no capture newer than the branch base — run the shot: line from pack, LOOK at the image, then hand off"`
`cmd_verify` (mid-flight) only WARNS with the same sentence prefixed `⚠ ` in place of `⛔ handoff refused:`.
Prose owns the other half: the Builder's report carries `✅ saw: <what the picture shows>`; the INTEGRATOR
opens the named PNG before `land` (`audit` prints `capture: <path>` lines for `.polaris/shots/<ID>-*.png` — T-099
adds that to `cmd_audit` only if trivially inline; otherwise it is the Integrator's `ls`).

## Interface — `kit/ops/VISUAL.md` (T-096; ≤40 lines; installed as `ops/VISUAL.md` — `install.sh` KIT_CODE
+= `VISUAL.md`, T-103; RULES-guarded there like every installed `ops/*.md`)
Headings, EXACTLY these seven (all indexed — W1 api-kit rows; no `#`-leading line inside a fence anywhere):
`# SEEING YOUR WORK — the capture is the proof` · `## The rule` · `## The keys (ops/CONVENTIONS.md)` ·
`## What pack prints` · `## What handoff checks` · `## Doctrine` · `## Adding it to a repo`.
Doctrine bullets (wording free, every item present): a unique filename carrying the task ID · the capture
lock queues you — never fight it · a blank image is a failure · never build your own capture tool or force
opacity to fake a paint · a screenshot you did not look at proves nothing · one `saw:` line in the handoff ·
run the tool's own `--help` / `--list-harnesses` ONCE — repo-specific flags come from the tool, not this doc.
"Adding it to a repo": the four keys, the `python`-not-`python3` note, and: add the `shot:` command prefix
to `.claude/settings.json` `permissions.allow` (one line) — `readonly-allow.sh` never auto-approves `python …`.

## Role prose (T-107, W3 — bold paragraphs / list items ONLY; the `^#` line set of every role file stays
byte-identical to `main`; each line below is pinned VERBATIM)
- BUILDER.md, a paragraph between §4 and §5:
  `**4b. See your work.** If \`pack\` printed a SEE YOUR WORK section and your diff touches a \`visual:\` path: run the printed \`shot:\` line (unique filename carrying your ID; the capture lock queues you — never fight it), then READ the image and put one \`saw: <what the screenshot shows>\` line in your handoff. A blank image is a failure. Never build your own capture tool or force opacity to fake a paint; a screenshot nobody opened proves nothing. \`handoff\` refuses when the capture is missing.`
- BUILDER.md §3, ONE sentence appended to its last paragraph: `A port in use is someone else's — take the port \`pack\` gave you; never reclaim a port by killing.`
- SOLO.md step 4, appended: ` Touching a \`visual:\` path? Run the \`shot:\` line \`pack\` printed, READ the png, carry a \`saw:\` line into your close — \`handoff\` refuses without the capture.`
  SOLO "What you must NOT skip", appended to the gate list: ` · the capture, when \`pack\` printed one`.
  SOLO hard limits gain the port sentence above as its own bullet.
- PLANNER.md, after 7b: `7c. **A visual surface names its capture.** A task whose \`files_owned\` touch a \`visual:\` path carries an acceptance box "capture .polaris/shots/<ID>-*.png shows <what>" — \`pack\` prints the \`shot:\` line and \`handoff\` refuses without the capture.`
- CONDUCTOR.md builder kickoff template (:141-150), one more `>` line: `> Touching a visual: path? run the shot: line pack printed, READ the png, and put a saw: line in your report — handoff refuses without the capture.`
  plus the dead-lane rule as a bold sentence in the stall paragraph: `**A lane that stopped on a capture refusal is not dead** — it needs the shot: line run, not a respawn.`
- INTEGRATOR.md §1, a bold line after the `ask` paragraph: `**Open the capture named in the handoff** (\`saw:\` line + \`.polaris/shots/<ID>-*.png\`) before landing a visual task — a green suite shipped a broken page once.`
- INIT.md DERIVE table, one row: `| \`shot:\` \`visual:\` \`port_base:\` \`serve:\` | \`tools/shot*.py\` · screenshot scripts · playwright/puppeteer deps ⇒ suggest \`shot:\`; the app's page/component dirs ⇒ \`visual:\` globs; the dev-server script ⇒ \`serve:\` + a free \`port_base:\`; on Windows write python, never python3 |`
  + four skeleton lines beside `runnable:` (trailing `#` comments only, same style):
  `shot: <cmd or omit>`, `visual: <globs or omit>`, `port_base: <number or omit>`, `serve: <cmd or omit>`
  + a §2c note: add the shot command prefix to `.claude/settings.json` allow.
- fleet kickoff (observe.sh:1869, T-100): append ` Touching a visual: path? run the shot: line pack printed, READ the png, and put a saw: line in your report.` (single quotes ONLY inside `msg` — the tmux branch embeds it in double quotes) and the sentence `Stop at the review handoff.` becomes `then bash ops/polaris next and follow it.` (role-handover.md).

## Executable check — golden `pack-visual` (T-105; hermetic, the `keys-drift` fixture pattern, ONE fixture repo)
Fixture `ops/CONVENTIONS.md`: `base: main` · `visual: web/*` · `shot: snap {ID} {PORT}` · `serve: dev {PORT}` ·
`port_base: 4000` · `landing: integrator`. Tasks: `T-207` (`risk: normal`, owns `web/a.txt`) and `T-300`
(owns `src/b.txt`), both `ready`. Asserts:
1. `pack T-207` prints the section verbatim with `port: 4007`, `shot: snap T-207 4007`, `serve: dev 4007`,
   `this task touches it: yes`;
2. `pack T-300` ⇒ `this task touches it: no`;
3. `visual:` removed ⇒ the unset line only;
4. claim `T-207`, commit a `web/a.txt` change in its worktree, `handoff` without a capture ⇒ the pinned
   refusal on stdout+stderr and rc 1; `T-207` still in `active/`;
5. a non-empty `.polaris/shots/T-207-home.png` (any bytes) ⇒ `handoff` passes (rc 0, task in `review/`).
The T-098 verify probe is a one-line version of assert 1 (`grep -q 'snap T-207 4007'`).

## Invariants
- Absent-by-default: no `visual:` ⇒ pack prints the unset line, handoff gates nothing, no role prose fires.
- The gate proves existence and freshness only; looking is prose (`saw:` + the Integrator's open).
- Screenshots live under the repo's `.polaris/shots/` — never `/tmp` (prompts on other machines).
- No new fn anywhere for the pack section or the handoff gate; no new heading outside VISUAL.md.
- KEYS rows are data: `keys-drift`'s count stays 0 because every `cfg` read has its row.

## Example
```
=== SEE YOUR WORK — capture before handoff (ops/VISUAL.md) ===
visual: web/* · this task touches it: yes
serve: dev 4007
shot: snap T-207 4007
port: 4007
proof: .polaris/shots/T-207-*.png — then READ it and write one "saw: <what it shows>" line in your handoff
read: ops/VISUAL.md
```

## Changelog
- v1 2026-09-01: created for T-096, T-098, T-100, T-103, T-105, T-107 (plan: cant-eat-itself, 6.2.0)
