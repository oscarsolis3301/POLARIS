# Sprint 16 — The gallery and the bar (6.6.0) (2026-09-17–)

## T-161 — "The interface first — the gallery: key, the screen: field, and ops/DESIGN.md as a shippable template"
points 3 · risk normal · landed 68dc065 (2026-09-17) · claimed 2026-09-17 → done 2026-09-17
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
points 1 · risk normal · landed a799ba5 (2026-09-17) · claimed 2026-09-17 → done 2026-09-17
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
points 3 · risk normal · landed 950ca80 (2026-09-17) · claimed 2026-09-17 → done 2026-09-17
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
points 3 · risk normal · landed dbb4320 (2026-09-17) · claimed 2026-09-17 → done 2026-09-17
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
points 3 · risk normal · landed fd4c563 (2026-09-17) · claimed 2026-09-17 → done 2026-09-17
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

## T-166 — "One home for the visual code — lib/visual.sh, the loader that names it, and the three inline blocks moved out of builder.sh with zero behavior change"
points 3 · risk normal · landed c048e25 (2026-09-17) · claimed 2026-09-17 → done 2026-09-17
files touched: kit/ops/lib/builder.sh, kit/ops/lib/visual.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
Everything left in this sprint adds code to one subject, and that subject currently lives as three
INLINE blocks inside `kit/ops/lib/builder.sh`, which is already 921 lines. The standing rule is that
new code goes in a new module rather than growing a long file. So before any new behavior is written,
the existing behavior moves to `kit/ops/lib/visual.sh` and gets one home.

**This task changes nothing a user can see.** It is a relocation, and the proof is that
`ops/tests/pack-visual.*` — the golden that pins the whole visual feature's output, including the
handoff refusal, byte for byte — stays untouched and green. If you find yourself wanting to edit that
golden, you have changed behavior and the move is wrong.

The three blocks and their new homes are pinned in `ops/contracts/module-layout.md` § v8:

| moved from | becomes |
|---|---|
| `builder.sh:833-879`, inline in `cmd_pack` | `visual_pack <ID> <owned>` |
| `builder.sh:216-239`, inline in `cmd_verify` | `visual_gate <ID> warn 2 ""` |
| `builder.sh:250-277`, inline in `cmd_handoff` | `visual_gate <ID> die 1 ""` |

Two functions, not three: the verify twin and the handoff gate are the same test with two different
endings, so they become one body whose `mode` argument decides both the git anchor and whether it
warns or dies. That is the shape every later wave builds on, and unifying them now is the last moment
it is free.

One thing is not negotiable: **the loader line naming `visual` and the file `kit/ops/lib/visual.sh`
must land in the same commit.** A loader that names a module which does not exist kills every single
CLI call in the repo.

### Acceptance
- [ ] `kit/ops/lib/visual.sh` exists with EXACTLY two top-level functions, `visual_pack` and `visual_gate`, a one-or-two line header comment, and nothing that executes at source time.
- [ ] `visual_pack <ID> <owned>` takes the owned-pattern list as its SECOND ARGUMENT. It must NOT reach into `cmd_pack`'s locals through bash dynamic scoping the way the inline block does today.
- [ ] `visual_gate <ID> <mode> <need> <saw>` carries both endings: `mode=warn` reads the worktree's `$BASE...HEAD` diff and prints the `⚠ ` sentence, `mode=die` reads `git -C "$PRIMARY" … $BASE...feat/<ID>` and dies with `⛔ handoff refused: `. `need` and `saw` are accepted now and used from T-168; today `need` is 1 and `saw` is ignored, so the shipped behavior is v1's.
- [ ] `cmd_pack`, `cmd_verify` and `cmd_handoff` each call the new function at EXACTLY the point their inline block sat, with no other change to `builder.sh`.
- [ ] The loader's FULL list reads `core ownership workspace surfaces visual builder integrate knowledge search observe admin bg awake handover skills`, and the `_match|_rules|_guard` list still reads EXACTLY `core ownership`.
- [ ] `ops/tests/pack-visual.expected` and `.cmd` are byte-identical to base and the golden passes — this is the proof the move changed nothing.
- [ ] `ops/tests/api-kit.expected` gains exactly two `kit/ops/lib/visual.sh fn` rows and loses nothing: the moved blocks were inline, so `builder.sh`'s own fn census is unchanged.

## T-167 — "A folder a human can read — screen: becomes a safe slug, every task gets a shotdir, and pack tells you to photograph the screen BEFORE you touch it"
points 5 · risk normal · landed ac9221c (2026-09-17) · claimed 2026-09-17
files touched: kit/ops/lib/visual.sh, ops/tests/api-kit.expected, ops/tests/pack-visual.cmd, ops/tests/pack-visual.expected

### Why
Today every capture lands flat as `.polaris/shots/T-042-home.png` — keyed by a task ID that means
nothing to a human, in a gitignored folder with no index. Nobody can browse them and nobody can show
them to anyone. This task gives them a place: a folder named after the SCREEN, using the `screen:`
field T-161 added, and it teaches `pack` to ask for the before-shot as well as the after-shot.

**The before-capture is the point, not a formality.** It forces the agent to look at the screen it is
about to overhaul before touching it — which is the "know what you are changing" half of the ask —
and it is the half a stakeholder actually reacts to.

Three functions carry it, all pinned in `ops/contracts/visual-check.md` § v2 sections 3, 5 and 8:

- `visual_slug <text>` turns `Homepage / Universal Search Bar` into `homepage/universal-search-bar`,
  or into NOTHING if the text cannot be made safe. This is the only place in POLARIS where a human
  string becomes a filesystem path, so it refuses `..`, absolute paths, drive letters, backslashes
  and anything deeper than two segments. Read `id_ok` in `kit/ops/lib/workspace.sh` for the shape:
  refuse loudly, return rather than die.
- `visual_shotdir <ID>` resolves and creates the directory, falling back to `misc/` whenever
  `screen:` is unset or unusable.
- `visual_shots_for <ID> <since>` finds this task's usable captures in THREE places, in order: the
  shotdir, `misc/`, then flat `.polaris/shots/`. All three, because the stray sweep only runs at
  handoff (so `verify` would otherwise warn on every visual task) and because a `screen:` added after
  a shot was taken would orphan the earlier capture. Use `find` — bash 3.2 has no `globstar`.

Then the `pack` section grows the lines § 8 pins, in that order, and `visual_gate` starts asking
`visual_shots_for` instead of globbing.

### Acceptance
- [ ] `visual_slug` implements § 3 exactly: lowercase with `tr` (bash 3.2 has no `${x,,}`), spaces and underscores to `-`, drop everything outside `[a-z0-9/-]`, collapse repeats, strip edges, and return EMPTY for `..`, a leading `/`, a drive letter, a backslash, or more than two segments.
- [ ] `visual_shotdir <ID>` prints a repo-relative-able absolute path and creates it, using `fm_get screen` on the task file, falling back to `.polaris/shots/misc`.
- [ ] `visual_shots_for <ID> <since>` searches the three locations in the pinned order with `find`, counts a file only when it is non-empty AND its mtime is at or after `since`, de-duplicates by basename, and prints oldest first.
- [ ] `visual_gate` uses `visual_shots_for` for its freshness test, and its behavior is otherwise unchanged from T-166 — `need` is still 1 and `saw` is still ignored. The two-capture rule is T-168's.
- [ ] The `pack` SEE YOUR WORK section prints `screen:`, `shotdir:`, the `shot:` line labelled BEFORE and again labelled AFTER, the `name them:` convention line, the two-line `proof:` block, the `--no-before` escape line, and `read: ops/DESIGN.md` when that file exists — in the order § 8 pins, with the v1 lines it keeps unchanged.
- [ ] `screen:` unset prints `screen: (unset — no name for this surface; shots land in misc/)` so a Planner notices.
- [ ] `visual:` unset still prints ONE line and nothing else changes anywhere. Absent-by-default is what lets this ship to every repo.
- [ ] `ops/tests/pack-visual.*` re-pinned for the new section: asserts 1–3 change; asserts 4–6 still describe the ONE-capture gate and must still pass, because the gate does not change in this task.

## T-171 — "Every existing repo gets the bar — heal copies ops/DESIGN.md in when it is missing, and doctor says when nobody has filled it in"
points 3 · risk normal · landed fd36cce (2026-09-17) · claimed 2026-09-17
files touched: kit/ops/lib/admin.sh, kit/ops/lib/observe.sh, ops/tests/heal-design.cmd, ops/tests/heal-design.expected

### Why
`ops/DESIGN.md` is the bar a screen has to clear, and this sprint just landed five role-prose
references to it (`roles/BUILDER.md:55` · `roles/SOLO.md:80,146` · `roles/PLANNER.md:41` ·
`roles/INTEGRATOR.md:17` · `roles/CONDUCTOR.md:188`). But the file is written by INIT and by nothing
else — `kit/ops/roles/INIT.md:119` copies the template in, and `grep -c DESIGN kit/ops/lib/admin.sh`
is 0, so `heal`, `adopt` and `update` never create it.

INIT runs once, on a brand-new repo. So every repo that adopted POLARIS before 6.6.0 — which is
every existing repo, this one and the owner's product repo included — will update to 6.6.0, receive
`ops/templates/DESIGN.md` (templates/ is copied recursively on both install paths), and never get
`ops/DESIGN.md`. Those five references dangle, `pack`'s `read: ops/DESIGN.md` line stays hidden
because it only prints when the file exists, and the release's headline feature silently does
nothing in exactly the repos that were meant to get it.

The fix belongs in `polaris heal`, whose whole job since 6.5.0 is that every install and every
update repairs itself; `install.sh:541` and `cmd_update` already call it. Make it copy the template
in when — and only when — `ops/DESIGN.md` is missing, exactly as INIT does, and never touch one that
already exists: it is owner-editable state like `ops/CONVENTIONS.md`. Then, because `heal` cannot
run an interview, have `doctor` say in one line when `## THIS PRODUCT` is still the template's
unfilled slot.

The full spec, every pinned string and the reasoning behind each guard is
`ops/contracts/visual-check.md` § v3 (sections 15-18). Read that first; this card does not repeat it.

**Three constraints that shape the whole change — none of them optional:**

1. **Add NO top-level function anywhere in `kit/`.** `ops/tests/api-kit.expected` records every
   public symbol and is owned by the T-166..T-170 chain running in parallel with you. A new `fn`
   row would couple two lanes through a golden neither can fix alone — the derived-surface-golden
   trap in `ops/SPRINT.md`'s Learned log, which has cost this board a kickback twice. Both edits go
   INLINE: the copy inside `cmd_heal`, the nudge inside `cmd_doctor`. Two of your `verify:` lines
   pin the top-level function counts (admin 25, observe 37) so this cannot slip.
2. **Do not touch `kit/ops/polaris` or `ops/tests/cli-help.expected`.** The entry script is owned by
   T-166/T-168/T-169. That means `polaris help`'s `heal` paragraph will still name only two repairs
   after you land — a known, deliberate gap, recorded in the contract's § 18 for whoever next owns
   the entry script. Do not "just fix it".
3. **Never run a bare `polaris heal` in this repo while you build.** This repo has no
   `ops/DESIGN.md`, so a stray heal would create one — a path outside your `files_owned`, and an
   ownership failure at `verify`. Everything you prove, you prove inside the golden's throwaway
   fixture. If one does appear, `rm` it before handing off.

One more trap worth knowing: a brand-new golden passes **vacuously** inside a Builder worktree,
because `polaris check` is anchored to the primary checkout and prints `no goldens matched`. That is
why your `verify:` runs the pair by hand with `diff`, and why you should also sabotage one assertion
red and restore it green before handoff — a golden nobody has seen fail asserts nothing.

### Acceptance
- [ ] `cmd_heal` copies `$OPS/templates/DESIGN.md` to `$OPS/DESIGN.md` if and only if the
- [ ] A repo that already has `ops/DESIGN.md` comes out byte-identical — owner content included —
- [ ] The create path prints exactly one `note` line naming `ops/DESIGN.md` and the remedy; nothing
- [ ] No `ops/CONVENTIONS.md` (INIT never ran) → heal's existing early return still fires and no
- [ ] `cmd_doctor` prints one `note` when `ops/DESIGN.md` exists, still carries the `_(unfilled`
- [ ] New golden pair `ops/tests/heal-design.cmd` + `.expected`, hermetic: one `mktemp -d` fixture
- [ ] `bash ops/polaris find --api 'kit/*'` is unchanged by this task — run it once against
- [ ] One assertion in the new golden sabotaged red and restored green, first-hand, before handoff.

## T-172 — "The golden that still expects a banned model — re-pin route-tier so the refusal IS the expected answer, and prove a legal model still gets through"
points 1 · risk normal · landed 9496c3e (2026-09-17) · claimed 2026-09-17
files touched: ops/tests/route-tier.cmd, ops/tests/route-tier.expected

### Why
`bash ops/polaris check` is RED on base, and has been for two days. `ops/tests/route-tier.expected`
still pins six lines that the CLI no longer prints:

```
   model: fable                  ->  model REFUSED: 'fable' is forbidden (owner, 2026-09-15) — this
                                     spawn names no model and inherits the session's
token: --model fable             ->  token: none
```

This is not a code regression. On 2026-09-15 the owner banned Fable and Haiku outright and
`model_denied` (`kit/ops/lib/core.sh:78`) made it a kit constant that no repo can switch off. The
golden's fixture sets `model_strong: fable`, so the refusal firing there is now the CORRECT answer —
nobody re-pinned the golden to say so.

**Re-pin it to the refusal. Do not route around it** by changing the fixture to an unbanned name:
after the ban, proving the refusal fires is the golden's most valuable job, and a fixture edited to
dodge it would assert nothing.

The fixture already carries both cases and you should keep it that way — `model_mid: opus` and
`model_cheap: sonnet` are legal, so the tier table is still proven end to end by the `mid` and
`cheap` rows. The one case that IS lost is the `fleet` token: the fixture's ready-queue max is always
`strong`, so `token:` now only ever proves the refusal path (`none`). Add ONE more assertion at the
end of the `.cmd` — point `model_strong` at a legal name (the fixture already uses `some-model-9`
elsewhere) and re-run the same `fleet 2 --dry-run` — so the golden proves both directions:
a forbidden model injects nothing, a legal one still injects `--model <name>`.

**This is the second casualty of that one session.** `ops/tests/rules-health.expected` was the first,
and T-162 re-pinned it earlier in this sprint. Both sat red for days for the same reason: the
goldens are not in the fast tier, and — checked directly — they are not in CI either
(`.github/workflows/ci.yml` runs `doctor --selftest`, never `polaris check`). The only thing that
runs them is `polaris check` and the integrator's `qa` wave gate. So the blast radius of this one is
the wave gate and any `check` run, NOT a red CI badge; fix it anyway, because the wave gate is what
stops the next task landing.

While you are in here, one stale line to leave ALONE but be aware of:
`ops/contracts/model-routing.md:45,98` still uses `fable` in its worked example. The contract is
append-only and a `## v2` note has been appended recording that the ban supersedes it — do not edit
the body.

### Acceptance
- [ ] `ops/tests/route-tier.expected` matches current behaviour byte for byte; all four `fable` rows
- [ ] The `mid` and `cheap` rows still pin `   model: opus` / `   model: sonnet` — the tier table is
- [ ] The `.cmd` gains ONE extra `fleet --dry-run` case with `model_strong` set to a legal name;
- [ ] The golden is still hermetic: its own `mktemp -d` fixture, its own CONVENTIONS, nothing read
- [ ] Regenerate with `polaris check --only route-tier --update` from the PRIMARY checkout, then
- [ ] Sabotage one of the re-pinned lines red and restore it green, first-hand, before handoff.
