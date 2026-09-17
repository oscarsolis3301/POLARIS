# Sprint 16 — The gallery and the bar (6.6.0) (2026-09-17–)

## T-161 — "The interface first — the gallery: key, the screen: field, and ops/DESIGN.md as a shippable template"
points 3 · risk normal · landed 68dc065 (2026-09-17) · claimed 2026-09-17
files touched: kit/ops/KEYS.tsv, kit/ops/templates/DESIGN.md, kit/ops/templates/TASK.md, ops/tests/api-kit.expected

### Why
Nothing else in this sprint can be written until these three pieces exist, because every later task
codes against them. Two of them are one line each; the third is the whole point of the sprint's
second half.

1. **`gallery:`** — one new row in `kit/ops/KEYS.tsv`, the registry of every CONVENTIONS key the kit
   reads. It is inert data today; T-169 is what makes `cfg gallery` mean something. It goes LAST in
   the file on purpose: `doctor` names the first six absent keys in file order, and a new key at the
   end cannot push an older one out of that list.
2. **`screen:`** — one new optional field in `kit/ops/templates/TASK.md`. It is how a human names the
   surface a task changes ("Homepage / Universal Search Bar"), which becomes the folder its
   screenshots live in. The Planner writes it; nothing derives it.
3. **`ops/DESIGN.md`** — right now this repo has no design guidance anywhere, so a long "make it
   beautiful, Apple-esque, no AI slop, legible in 3 seconds" brief gets retyped into every visual
   task, or forgotten. This task writes it once, as a TEMPLATE, so every repo gets it and each repo
   fills in its own `## THIS PRODUCT` paragraph.

Read `ops/contracts/visual-check.md` § v2 sections 2, 3 and 12 — they pin the key row byte-exact, the
field's comment text, and DESIGN.md's ten headings in order. Do not invent headings: they are indexed
into `ops/tests/api-kit.expected`, which you also own and must re-pin.

### Acceptance
- [ ] `kit/ops/KEYS.tsv` ends with the `gallery` row exactly as § 2 pins it — four TAB-separated fields, no fifth (ask) column.
- [ ] `kit/ops/templates/TASK.md` carries `screen:` directly after `scope:`, with the two-line comment from § 3 and the same comment style as its neighbours.
- [ ] `kit/ops/templates/DESIGN.md` exists, is 60 lines or fewer, and has EXACTLY the ten headings of § 12 in that order.
- [ ] `## THIS PRODUCT` is a clearly marked placeholder a human (or INIT) fills in one sentence — it must read as an empty slot, not as advice.
- [ ] `## What AI slop looks like` lists the seven concrete failures named in § 12, each short enough to fail a screen against at a glance.
- [ ] `## Where to go deeper` NAMES `apple-design`, `frontend-design` and `make-interfaces-feel-better` and says nothing those skills already say. Pointing costs a line; duplicating costs every context that reads the file.
- [ ] `ops/tests/api-kit.expected` re-pinned: ten new `kit/ops/templates/DESIGN.md heading` rows plus one `kit/ops/KEYS.tsv key gallery` row, and NOTHING else moved.

## T-162 — "The rule that was claimed but never written — ops/VISUAL.md gets its path guard, ops/DESIGN.md deliberately gets none, and the red rules-health golden goes green"
points 1 · risk normal · landed a799ba5 (2026-09-17) · claimed 2026-09-17
files touched: ops/RULES.tsv, ops/tests/rules-health.expected

### Why
Every installed `ops/*.md` file carries a `path` row in `ops/RULES.tsv` pointing edits back at its
source in `kit/` — `ops/PROTOCOL.md`, `ops/MANUAL.md`, `ops/PROMPTS.md`, `ops/roles/`,
`ops/templates/` and the rest. `ops/VISUAL.md` has none, even though
`ops/contracts/visual-check.md:61` states it is "RULES-guarded there like every installed
`ops/*.md`". It never was. Anyone editing the installed copy loses the work at the next dogfood and,
until then, the board runs a document that exists nowhere in the source.

The same sprint adds `ops/DESIGN.md`, which sits right beside it, looks exactly like it, and must
have the OPPOSITE treatment: it is repo state the owner is meant to edit, like `ops/CONVENTIONS.md`.
Two adjacent files with identical shapes and opposite rules is a trap, so this task writes the
comment that stops someone "fixing" the asymmetry later.

**Found while planning, and it comes with this task:** `ops/tests/rules-health.expected` is pinned at
`✅ 16 rule(s), all healthy` but `bash ops/polaris rules` already answers **17** — the model-ban
content rule added on 2026-09-15 never re-pinned the golden, so `check` has been red on base ever
since. Adding your row makes it 18. Re-pin the golden to the number the command actually prints and
say so in your report; a golden nobody noticed go red is worth more than the line that fixed it.

Invariant 11 makes RULES yours to maintain: add the line, and record who decided and why in a `#`
comment above it, exactly as every other block in the file does.

### Acceptance
- [ ] `ops/RULES.tsv` gains one `path` row for `ops/VISUAL.md` naming `kit/ops/VISUAL.md` as the file to edit instead, in the same four-TAB shape and the same message voice as its siblings.
- [ ] A `#` comment above it records WHO decided and WHY (plan `gallery-and-bar`, 6.6.0, the contract claim that was never true), matching the house style of the `ops/lib/` and `ops/KEYS.tsv` blocks.
- [ ] That comment ALSO states, in one or two lines, that `ops/DESIGN.md` gets no row on purpose because it is owner-editable repo state like `ops/CONVENTIONS.md` — so the asymmetry reads as a decision, not an oversight.
- [ ] The `ops/SURFACES.tsv` block's stale "the rule count stays 16" sentence is corrected to the new count in the same edit, so the file does not contradict itself.
- [ ] `ops/tests/rules-health.expected` reads `✅ 18 rule(s), all healthy` — 16 shipped rules, plus the model-ban content rule that was never pinned, plus yours.

## T-163 — "The three roles that take the picture — BUILDER, SOLO and CONDUCTOR learn before-and-after, the bar, and a --saw that rides the detached ship line"
points 3 · risk normal · landed 950ca80 (2026-09-17) · claimed 2026-09-17
files touched: kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/SOLO.md

### Why
These are the three role files a session actually reads while it is changing a screen, and all three
currently describe the OLD deal: one screenshot, taken afterwards, and a `saw:` line written as prose
in a report that nothing records. The new deal is: photograph it BEFORE you touch it, photograph it
after, read both, and pass what you saw to `handoff` as data — where it becomes the caption under the
picture in a gallery a human opens.

There is one trap here that is easy to miss and expensive to get wrong. **The default ship recipe is
detached**: `bash ops/polaris bg run ship-<ID> -- bash ops/polaris handoff`, printed in all three
files. A detached job has nobody at a keyboard to answer a prompt, so the `--saw` text must be on
that printed line, inline, or the gate simply refuses a job nobody can rescue. Every printed ship
recipe in all three files carries it.

`ops/contracts/visual-check.md` § v2 sections 6, 7 and 8 are the source of truth for the wording of
the gate, the flags and what `pack` prints. Say the same things these files already say, with the new
facts folded in — do not restructure them.

### Acceptance
- [ ] BUILDER.md § 4b is rewritten: run the `shot:` line BEFORE you edit and again after · both land in the `shotdir` `pack` printed · READ both · `read: ops/DESIGN.md` is the bar this screen must clear · hand off with `--saw "<what the after shot shows, and how it measures against the bar — PASS / WEAK / FAIL>"` · a brand-new screen uses `--no-before "<why>"` · `handoff` refuses without two captures or without `--saw`.
- [ ] BUILDER.md § 5's printed ship recipe carries `--saw` inline, and NO printed recipe anywhere in the file still ends at a bare `handoff`.
- [ ] SOLO.md step 4's visual sentence and its "What you must NOT skip" gate list both say before-AND-after, name `ops/DESIGN.md`, and carry `--saw`; SOLO's own step-5 ship line carries it too.
- [ ] CONDUCTOR.md's builder-kickoff template `>` block says the same thing in one line a spawned subagent can act on, including `--saw` on the ship command it hands down.
- [ ] CONDUCTOR.md's stall paragraph keeps its "a lane that stopped on a capture refusal is not dead" sentence and extends it: a lane refused for a MISSING `--saw` needs the sentence written, not a respawn.
- [ ] The `^#` heading line set of all three files is byte-identical to base — bold paragraphs and list items only. These headings are indexed into `ops/tests/api-kit.expected`, which you do NOT own.
- [ ] Nothing in any of the three grows a paragraph about the gallery mechanics. A builder needs to know what to run and what will refuse it; where the pictures end up is `ops/VISUAL.md`'s job.

## T-164 — "The three roles that set it up — the Planner names the screen, INIT installs the bar and asks the one design question, the Integrator opens the pair, and the fleet kickoff says so"
points 3 · risk normal · landed dbb4320 (2026-09-17) · claimed 2026-09-17
files touched: kit/ops/lib/observe.sh, kit/ops/roles/INIT.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md

### Why
Three roles set up a visual task rather than doing it, and each one has exactly one thing to learn.

**The Planner** now names the folder. A screenshot filed under `T-042` means nothing to a human;
filed under `homepage / universal search bar` it means everything, and only a person can supply that
name. § 7c grows from "name your capture" to "name your screen, and fold the bar into the acceptance
criteria". It also has to carry a warning the Planner cannot discover on its own: the `gallery:`
directory must NEVER appear in a task's `files_owned`, because three separate gates — the ownership
check, the claim-time disjointness gate and `drift` — would refuse two parallel visual tasks outright
if it did. `ops/SURFACES.tsv` already says exactly this about itself; copy the shape.

**INIT** installs the bar. `ops/DESIGN.md` is copied ONCE from `ops/templates/DESIGN.md` and never
overwritten afterwards, exactly like `ops/CONVENTIONS.md` — the installer must never do it, because
`$KIT_CODE` is overwritten on every update and would clobber the owner's own design bar. INIT also
asks the one question no repo can answer for itself ("describe the look and feel you want, in a
sentence") and writes the answer into `## THIS PRODUCT`, and derives `gallery:` the way it already
derives `shot:`/`visual:`.

**The Integrator** opens the PAIR, not one picture. Before and after side by side is the only view
that shows whether anything actually improved, and the caption next to it is the builder's own claim
— when the two disagree, that is exactly what a kickback is for.

And the **fleet kickoff string** (`kit/ops/lib/observe.sh`) is the one line a terminal pane gets
instead of a conductor's template, so it carries the same sentence in one clause.

### Acceptance
- [ ] PLANNER.md § 7c rewritten: a task touching a `visual:` path names its `screen:` (the human name of the surface, e.g. `Homepage / Universal Search Bar`), carries an acceptance box naming what the after-shot must show, and folds `ops/DESIGN.md` into its acceptance criteria rather than pasting a design brief.
- [ ] PLANNER.md says, in one sentence, that the `gallery:` directory never appears in any `files_owned` — it is written by `done` alone, like `ops/SURFACES.tsv`.
- [ ] INTEGRATOR.md § 1's capture line becomes the PAIR plus the caption: open before and after and read the `--saw` text beside them before landing; a caption that does not match the picture is a kickback, not a note.
- [ ] INIT.md gains a DERIVE row for `gallery:` beside the existing `shot:`/`visual:`/`port_base:`/`serve:` row, and a `gallery: <dir or omit>` skeleton line beside the other optional keys, in the same comment style.
- [ ] INIT.md step 3 says to copy `ops/templates/DESIGN.md` to `ops/DESIGN.md` if and only if it does not already exist, and never to overwrite it.
- [ ] INIT.md asks ONE new interview question — the look-and-feel sentence — and writes the answer into `## THIS PRODUCT`; under the express path it is folded in with the rest, never asked as its own round.
- [ ] The fleet kickoff string in `observe.sh` names before-and-after and `--saw` in one clause, and keeps its existing constraints: SINGLE quotes only inside `msg` (the tmux branch embeds it in double quotes), and the whole thing stays one line.
- [ ] The `^#` heading line set of all three role files is byte-identical to base, and `observe.sh` gains NO new function.

## T-165 — "The two documents and the one attribute — VISUAL.md describes the new deal, MANUAL.md's hand-rolled handoff keeps up, and gallery PNGs stop being text"
points 3 · risk normal · landed fd4c563 (2026-09-17) · claimed 2026-09-17
files touched: kit/ops/MANUAL.md, kit/ops/VISUAL.md, kit/ops/install.sh

### Why
Three small, unglamorous pieces that keep the rest of the sprint honest.

**`kit/ops/VISUAL.md`** is the document `pack` tells every builder to read, and it currently
describes a one-screenshot world. It has to describe the new one: before and after, the `screen:`
name and the folder it becomes, `--saw` as the caption rather than a line in a report, the generated
`INDEX.md` a human opens, and `gallery:` for a committed set you can show someone. It must stay
short — this is a file agents read, not a manual — and it must keep its seven headings exactly,
because they are indexed into `ops/tests/api-kit.expected`, which another lane owns this wave.

**`kit/ops/MANUAL.md`** is the fallback for a session that cannot run the CLI, and it documents the
hand-rolled handoff. `handoff` is growing flags, so the manual path has to say what a human does in
their place — or the fallback quietly stops matching the tool, which is exactly the drift
`ops/contracts/cli-docs-parity.md` exists to prevent.

**`kit/ops/install.sh`** arms a target repo's `.gitattributes`. A committed gallery means PNG files
land in git; without a `-text` attribute a Windows checkout with `core.autocrlf=true` can mangle
them. One line, next to the LF pins that are already there — and **no new output line**, because CI
counts the lines a quiet install prints and a new `say` would trip that tripwire.

### Acceptance
- [ ] `kit/ops/VISUAL.md` keeps EXACTLY its seven existing headings, byte-identical, and stays 60 lines or fewer.
- [ ] Its `## The keys` block gains `gallery:` alongside the four it already shows, and its `## The rule` / `## What pack prints` / `## What handoff checks` sections describe before-and-after, the `shotdir`, `--saw`, and `--no-before`.
- [ ] `## Doctrine` keeps every existing bullet and gains: a capture you did not look at proves nothing applies twice over now (before and after) · the gate counts captures and never inspects filenames, so `-before-`/`-after-` is a naming convention for the gallery, not a rule.
- [ ] Its `## Adding it to a repo` section names `gallery:` and `screen:` and points at `ops/DESIGN.md`.
- [ ] `kit/ops/MANUAL.md`'s handoff section documents the new signature — `handoff [ID] [--saw "…"] [--no-before "<why>"]` — and what a human does by hand when the capture gate would have fired.
- [ ] `kit/ops/install.sh` appends `docs/screens/**/*.png -text` to the target's `.gitattributes`, guarded by its own `grep -q` the way the `commit-msg` line is (pre-6.6 installs already carry the older block, so a new line inside it would never reach them).
- [ ] The installer prints NO new output line for it — the `say` count is unchanged from base.
- [ ] Neither markdown file gains or loses a `^#` line.
