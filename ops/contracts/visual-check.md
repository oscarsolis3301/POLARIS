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

## v2 — the gallery and the bar (2026-09-17, plan `gallery-and-bar`, 6.6.0)

**Why a new section.** v1's § Invariants says "No new fn anywhere for the pack section or the handoff
gate" and pins a ONE-capture gate. Both change here: the visual code becomes a module of new
functions, and the gate counts TWO captures. That is a breaking change to a shipped interface, so it
gets a `## v2` rather than an edit (this file is append-only, line 3). Where v2 and v1 disagree, **v2
wins**; everything v2 does not mention is v1 unchanged — above all **absent-by-default**: a repo with
no `visual:` key sees nothing in this section happen.

Tasks: T-161 (keys · `screen:` · the DESIGN template, W1) · T-162 (the RULES rider, W1) ·
T-163/T-164/T-165 (role prose · VISUAL.md · MANUAL.md · the gitattributes pin, W1) ·
T-166 (the module + the move, W2) · T-167 (`screen:` to shotdir + pack v2, W3) ·
T-168 (the before/after gate + `--saw` + captions, W4) · T-169 (`shots` · INDEX.md · the gallery
publish, W5) · T-170 (the `shots-gallery` golden, W6).
Where the code LIVES is `ops/contracts/module-layout.md` § v8, not this file.

### 1. Three things POLARIS may NOT assume (the constraints every rule below obeys)

- **POLARIS ships no capture tool.** `shot:` is the repo's own command and may be positional
  (`python tools/shot.py {ID} {PORT}`) with no output flag. POLARIS can therefore NEVER require a
  capture to have a particular FILENAME, a particular directory, or an `-after-` infix. Any gate
  that did would make every visual task in every 6.2.0–6.5.0 repo permanently un-handoffable.
- **The gate is COUNT AND FRESHNESS, never names.** `-before-` / `-after-` are a *documented naming
  convention* used to pair captures for display. They are never tested.
- **bash 3.2** has no `globstar` and no `${x,,}`: recursive search is `find`, lowercasing is `tr`.

### 2. New CONVENTIONS key — ONE row, appended to `kit/ops/KEYS.tsv` after `auto_update`, byte-exact
```
gallery	6.6.0	<dir or omit>	captures stay local and vanish on a fresh clone: nothing committed, nothing to show anyone
```
Semantics: `gallery: docs/screens` means `done` publishes one curated image + caption per screen
there and commits it on `<base>`. UNSET means the whole publish step is off and only
`.polaris/shots/` exists.

### 3. New TASK.md field — `screen:` (the Planner names the folder; nothing is auto-derived)
Appended to `kit/ops/templates/TASK.md` immediately after the `scope:` line, same comment style:
```
screen:                  # optional; the human name of the surface this task changes, e.g.
                         # Homepage / Universal Search Bar — becomes the shot folder
```

**`visual_slug <text>`** — stdout is a safe relative path, or EMPTY when the input cannot be made
safe. Rules, in order: lowercase via `tr 'A-Z' 'a-z'` · spaces and underscores become `-` · drop
every character outside `[a-z0-9/-]` · collapse repeated `-` and `/` · strip leading/trailing `-`
and `/` · **reject and return empty** on any `..` segment, a leading `/`, a drive letter, a
backslash, or more than **2** path segments. `Homepage / Universal Search Bar` becomes
`homepage/universal-search-bar`. Directory-traversal sanitising is a house rule, and this is the
only place a human string becomes a path.

**`visual_shotdir <ID>`** — stdout is the task's capture directory, always printed, always created
(`mkdir -p`): `$PRIMARY/.polaris/shots/` plus `visual_slug` of the task's `screen:` value, falling
back to `$PRIMARY/.polaris/shots/misc` when `screen:` is unset, unreadable, or slugs to empty.

### 4. The tree
```
.polaris/shots/                     # local, gitignored, churns freely — every capture ever taken
  INDEX.md                          # GENERATED; open in VS Code's Markdown preview
  homepage/
    universal-search-bar/
      T-042-before-search.png
      T-042-after-search.png
      T-042.md                      # the caption: title, the saw: text, before/after, date
  misc/                             # tasks whose Planner named no screen:
```
**There is no `{SHOTDIR}` placeholder.** `pack` PRINTS the directory as information; a repo whose
`shot:` takes an output path may write straight into it, and for every repo that cannot, the stray
sweep (§ 6) files the captures at handoff. One mechanism, one thing to test.

### 5. `visual_shots_for <ID> <since-epoch>` — the THREE-location search, in this order
1. the task's shotdir (§ 3) · 2. `.polaris/shots/misc/` · 3. flat `.polaris/shots/` (pre-6.6 repos).
Use `find "$PRIMARY/.polaris/shots" -name "<ID>-*.png"` — never a `**` glob. A file counts only when
it is **non-empty** (`-s`, so an empty file buys nothing — v1 doctrine) and its mtime is **at or
after `since`**. Output: one absolute path per line, oldest mtime first, de-duplicated by basename.
Searching all three is not belt-and-braces: the stray sweep only runs at handoff, so `verify` would
warn spuriously otherwise, and a `screen:` added after a capture was taken would orphan it.

### 6. `visual_gate <ID> <mode> <need> <saw>` — one body, both callers
Replaces v1's two inline blocks verbatim. `mode` is `warn` (from `cmd_verify`) or `die` (from
`cmd_handoff`), and mode alone decides the git anchor: `warn` reads
`git diff --name-only --no-renames "$BASE...HEAD"` in the worktree, `die` reads
`git -C "$PRIMARY" diff --name-only --no-renames "$BASE...feat/<ID>"` — exactly as v1 did.

Fires iff `visual:` is set AND `shot:` is set AND that diff has a path matching a `visual:` glob
(`owned_match`, reused, both directions). Then, with
`since` = the commit time of `git merge-base` of base and the branch:

- `count` = the number of lines from `visual_shots_for <ID> <since>`; `count < need` means refuse.
- `mode=die` and `saw` EMPTY means refuse.
- `mode=warn` ignores `saw` entirely and never refuses — it prints the same sentence with `⚠ `
  in place of `⛔ handoff refused: ` and returns 0. `cmd_verify` always passes `need=2`.

Refusals, pinned VERBATIM (the ID substituted; `die` prefixes `⛔ handoff refused: `):
```
<ID> changed a visual: path but .polaris/shots/ has fewer than 2 captures for <ID> newer than the branch base — run the shot: line from pack BEFORE and AFTER your edit, LOOK at both, then hand off
<ID> changed a visual: path but .polaris/shots/ has no capture for <ID> newer than the branch base — run the shot: line from pack, LOOK at the image, then hand off
<ID> changed a visual: path — say what you saw: bash ops/polaris handoff --saw "<what the after shot shows, and how it measures against ops/DESIGN.md>"
```
(The second is the `need=1` wording, used under `--no-before`.)

**`--saw` validation is NON-EMPTY, and nothing else.** No length floor, no PASS/WEAK/FAIL vocabulary
check. A validator cannot tell whether anyone looked; the value is the caption a human reads next to
the picture, and a refusal a builder satisfies by padding is a compliance ritual. The bar verdict is
ASKED for — in `pack`'s proof line, in `ops/DESIGN.md` § The verdict, and in the role prose — never
enforced.

**The stray sweep, `visual_file_strays <ID>`**, runs at handoff AFTER the gate passes and before the
board write: every `<ID>-*.png` found outside the task's shotdir is moved into it. It never deletes
and never overwrites — a name collision keeps the existing file and leaves the stray where it is.
This is what keeps a pre-6.6 `shot:` line working forever.

**`visual_caption <ID> <saw> <no-before-reason>`**, at the same point in `handoff`, writes
`<shotdir>/<ID>.md` (overwritten on a re-handoff):
```
# <ID> — <task title>

<the --saw text, verbatim, one blank line around it>

- screen: <the screen: value, or (unset — filed under misc/)>
- before: <basename of the oldest capture, or (skipped — <reason>)>
- after: <basename of the newest capture>
- date: <YYYY-MM-DD>
```

### 7. `cmd_handoff` grows a flag loop — and it is the only reason this is a breaking change
`kit/ops/lib/builder.sh:242` is `local id="${1:-}"` with NO flag parsing at all, so today
`handoff --saw "…"` is read as a task ID literally named `--saw`. The new signature:
```
handoff [ID] [--saw "<text>"] [--no-before "<why there was nothing to photograph>"]
```
Both flags take a value; the FIRST non-flag argument is the ID; flags may come in any order, before
or after it. **Ten call sites across five files pass the ID positionally and MUST keep working
byte-identically** — that compatibility is what the golden pins.

`--no-before` sets `need=1` and its reason is recorded in the caption and shown in the gallery, so a
skipped before-shot is visible rather than silent.

**The default ship recipe is DETACHED** (`bg run ship-<ID> -- bash ops/polaris handoff`, in
`BUILDER.md`, `CONDUCTOR.md` and `SOLO.md`), and a detached job has no operator to prompt. Every one
of those printed recipes therefore carries `--saw` INLINE, on the same line.

### 8. `cmd_pack` § SEE YOUR WORK, v2 — pinned line for line
`visual:` unset gives v1's single line, unchanged. Set gives these lines, in this order:
```
visual: <globs> · this task touches it: <yes|no>
screen: <the screen: value>                       <- or: screen: (unset — no name for this surface; shots land in misc/)
shotdir: .polaris/shots/<slug>                    <- repo-relative, always printed
serve: <cmd>                                      <- only when serve: is set   (v1, unchanged)
shot BEFORE you edit: <cmd>                       <- only when shot: is set
shot AFTER you edit: <cmd>                        <- the same command, printed twice on purpose
name them: <ID>-before-<what>.png and <ID>-after-<what>.png, in the shotdir above
port: <n>                                         <- v1, unchanged (incl. the port_base-unset line)
proof: TWO non-empty captures for <ID>, both newer than your branch base — READ both, then:
       bash ops/polaris handoff --saw "<what the after shot shows, and how it measures against ops/DESIGN.md — PASS / WEAK / FAIL>"
nothing existed to photograph (a brand-new screen)? bash ops/polaris handoff --no-before "<why>" --saw "…"
read: ops/VISUAL.md
read: ops/DESIGN.md — the bar this screen must clear     <- only when ops/DESIGN.md exists
```
`shot:` unset keeps v1's `shot: (unset — set shot: in ops/CONVENTIONS.md; ops/VISUAL.md)` line in
place of the two `shot …` lines and the `name them:` line.
The before-capture is the point, not a formality: it makes the agent LOOK at the screen it is about
to overhaul, and it is the half a stakeholder actually reacts to.
`visual_pack <ID> <owned>` takes the owned-pattern list as its SECOND ARGUMENT — never by reaching
into `cmd_pack`'s locals through dynamic scoping.

### 9. `.polaris/shots/INDEX.md` — generated, never edited
```
# SHOTS — what this repo looked like, before and after
<!-- generated by `bash ops/polaris shots` — never edit by hand; it is rewritten in place -->

## homepage / universal search bar

### T-042 — <task title>
<the saw text>

| before | after |
| --- | --- |
| ![before](homepage/universal-search-bar/T-042-before-search.png) | ![after](homepage/universal-search-bar/T-042-after-search.png) |
```
Screens are `##` sections in path order, their heading the slug with `/` and `-` read back as
spaces. Tasks are `###` sections, newest first within a screen. Image links are RELATIVE to
`.polaris/shots/`, so VS Code's Markdown preview renders them. A screen folder with no `<ID>.md`
caption is listed with its images and the line `(no caption recorded)`. No captures at all gives the
two header lines and `_(nothing captured yet)_`.

### 10. `polaris shots` — ONE bare arm, no subcommands
```
shots                          rebuild .polaris/shots/INDEX.md and say where the gallery is
```
Regenerates the index, then prints the screen and capture counts, the index path, and either the
`gallery:` directory or one line saying the key is unset. There is deliberately no `index`, `open`
or `publish` verb: `index` is what the bare command does, `open` is useless to an agent, and
publishing already happens automatically at `done`.

### 11. The committed gallery — published by `cmd_done`, inside the mutex it ALREADY holds
**The concurrency story matters more than the copy.** `cmd_done` does NOT hold the integration lease
— only `cmd_land`, `cmd_land_express` and `cmd_seal` call `int_on` — and adding `int_on` here would
DEADLOCK the default `landing: self` path: the self-land tail invokes `done` as a SUBPROCESS
(`builder.sh:422,426`), a different `$$`, so the re-entrancy check fails, it blocks for
`integration_wait_minutes` and returns rc 3. So:

- the publish runs inside `cmd_done`'s EXISTING `mutex_on` window, which already serialises it;
- it writes through a temp name in the SAME directory and renames it into place (atomic `mv`);
- it rides the EXISTING pathspec-limited commit with its 5-attempt retry and fallback
  (`integrate.sh:280-296`) by adding its paths to that command's path list — never a second commit;
- the whole block is gated on `cfg gallery` being non-empty, so for a repo that never opted in
  nothing new runs and `cmd_done`'s "must be on base" die is not newly reachable.

Subject precedence for that one commit: a `map_delta` gives `docs(map): <ID> <first>` (unchanged) ·
else surfaces rows give `docs(surfaces): <ID> <sfirst>` (unchanged) · else `docs(screens): <ID>
<screen>`. Whichever applied, all their paths ride the same commit.

`visual_publish <ID>` copies, per screen, the NEWEST capture and its caption:
```
docs/screens/                       # COMMITTED — bounded, curated, stakeholder-facing
  INDEX.md
  homepage/
    universal-search-bar.png
    universal-search-bar.md
```
One image per screen, replaced in place, so git weight stays bounded while the churn stays local.
`<gallery>/INDEX.md` is regenerated the same way as § 9, with one `##` per screen and one image.

**`docs/screens/` (or whatever `gallery:` names) must NEVER appear in any task's `files_owned`.**
Three separate gates — `check_ownership`, the claim-time disjointness gate and `drift` — would refuse
two parallel visual tasks outright if it did. It is written by `done` and by nothing else, exactly as
`ops/SURFACES.tsv` is; `PLANNER.md` § 7c says so, and so does this line.

Binary safety: the kit's installed `.gitattributes` gains `docs/screens/**/*.png -text` beside the
existing LF pins in `install.sh`, armed with NO new output line — the CI tripwire counts the quiet
install's lines.

### 12. `ops/DESIGN.md` — the bar, as a file
New template `kit/ops/templates/DESIGN.md`, 60 lines or fewer. Headings, EXACTLY these ten, in this
order (they are indexed — `ops/tests/api-kit.expected`):
`# THE BAR — what a screen must clear` · `## The 3-second rule` · `## Legible to a non-technician` ·
`## Progressive disclosure` · `## Icons must be self-evident` · `## Density without clutter` ·
`## What AI slop looks like` · `## THIS PRODUCT` · `## The verdict` · `## Where to go deeper`.

- **The 3-second rule** — the first impression IS the product: what a stranger must understand
  without being told.
- **Legible to a non-technician** — a stakeholder who has never been a technician reads the screen
  and knows what is going on.
- **Progressive disclosure** — not everything at once; depth lives inline or behind a sheet on the
  SAME page, never a context switch.
- **Icons must be self-evident**, with fast tooltips; an icon that needs a caption is a failed icon.
- **Density without clutter** — people live here for hours; real estate is spent, not filled.
- **What AI slop looks like** — a concrete list to fail against: generic gradient hero · purple-blue
  everything · emoji as iconography · three font weights doing one job · equal visual weight on
  every element · card grid for its own sake · lorem-ipsum polish with no real data shape.
- **`## THIS PRODUCT`** — a marked section INIT fills from ONE interview question ("describe the look
  and feel you want, in a sentence"), so the bar is the repo's and not the kit's.
- **`## The verdict`** — defines `PASS` / `WEAK` / `FAIL`, the words a `--saw` line is asked (never
  forced) to use.
- **`## Where to go deeper`** — POINTS AT, never duplicates, the design skills already on the
  machine (`apple-design`, `frontend-design`, `make-interfaces-feel-better`). Token discipline.

**INIT copies it; `install.sh` never does.** `ops/DESIGN.md` is repo-editable state, like
`ops/CONVENTIONS.md`. Putting it on `$KIT_CODE` would clobber the owner's filled-in bar on every
update, and an exists-check-then-copy in `install.sh` risks the quiet-line CI tripwire. Because
`templates/` IS copied recursively on both install paths (`install.sh:86,100`), improvements to the
TEMPLATE still reach every repo, while the repo's own `ops/DESIGN.md` is never touched.

**The RULES asymmetry, and why the two files look alike and behave oppositely:** `ops/VISUAL.md`
gains the `path` row every other installed `ops/*.md` has and that this file's v1 already claimed it
had. `ops/DESIGN.md` deliberately gets NO row — it is meant to be edited in the repo. A comment in
`ops/RULES.tsv` must say so, or someone will "fix" it.

### 13. Executable check — golden `shots-gallery` (T-170; hermetic, the `pack-visual` fixture pattern)
ONE throwaway repo under `mktemp -d`, with its own CONVENTIONS (`visual: web/*` · `shot:` ·
`port_base:` · `gallery: docs/screens` · `landing: integrator`), its own board, an `ops/DESIGN.md`,
and the CLI run from INSIDE it. Asserts: the `screen:` slug and shotdir · `misc/` when `screen:` is
unset · a traversal-shaped `screen:` refusing to escape · ONE capture is refused · two pass ·
`--saw` missing is refused · `--no-before "<why>"` with one capture passes and the reason reaches the
caption · a FLAT `<ID>-*.png` written by a pre-6.6 `shot:` line counts for the gate and is then filed
into the shotdir · `INDEX.md` contents · `polaris shots` output · and, after `done`, `docs/screens/`
holding the curated pair with a `docs(screens):` commit on base.
`ops/tests/pack-visual.*` is RE-PINNED, not tweaked: five of its six asserts change, and assert 6
flips rc 0 to 1 (one capture is no longer enough). Keep its hermetic fixture shape and its
`landing: integrator` line.

### 14. Invariants (v2)
- **Absent-by-default, still.** No `visual:` means pack prints the unset line, no gate fires, no
  prose fires. No `gallery:` means nothing is committed anywhere.
- **Never test a capture's filename.** Count and mtime only.
- Captures live under the repo's `.polaris/shots/` — never `/tmp` (prompts on other machines).
- A pre-6.6 repo whose `shot:` line predates all of this keeps working: flat captures satisfy the
  gate and are filed afterwards.
- `--saw` is required only when the gate fires, and is validated as non-empty only.
- `docs/screens/` never appears in a `files_owned`.
- `visual.sh` is in the FULL loader list only — NEVER on the `_match|_rules|_guard` short list. That
  list is a correctness fix: a slow guard once failed OPEN under parallel builders.
- The loader line naming `visual` and the file `kit/ops/lib/visual.sh` land in the SAME commit — a
  loader naming a module that does not exist kills every CLI call in the repo.

### Changelog
- v2 2026-09-17: the shots tree plus a generated INDEX.md, the committed `gallery:`, `screen:`,
  before AND after (count-and-freshness, never filenames), `--saw` as recorded data,
  `ops/DESIGN.md`, and `polaris shots`. Supersedes v1's one-capture gate and its "no new fn
  anywhere" invariant (T-161..T-170, plan `gallery-and-bar`, 6.6.0).
