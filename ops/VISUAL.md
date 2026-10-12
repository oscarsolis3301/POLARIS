# SEEING YOUR WORK — the capture is the proof

## The rule
Changed something a person LOOKS at? Photograph it BEFORE you edit and again AFTER, open both
pictures, and say what you saw. A green suite has shipped a blank page before. Two halves, and
neither replaces the other: `handoff` proves the captures EXIST; your `--saw` line proves somebody
LOOKED.

## The keys (ops/CONVENTIONS.md)
```
visual: web/* src/components/*         # the surface; unset turns this whole step off
shot: python tools/shot.py {ID} {PORT} # {ID} = your task, {PORT} = your port
serve: npm run dev -- --port {PORT}    # optional: how to start this worktree's app
port_base: 4000                        # your port = port_base + (numeric tail of the ID mod 100)
gallery: docs/screens                  # optional: done commits one curated image per screen there
```

## What pack prints
`pack <ID>` prints a SEE YOUR WORK section: the `visual:` globs and whether this task touches them,
the task's `screen:` and the `shotdir` its captures belong in, the `serve:` line, the `shot:` line
TWICE — once before your edit, once after — your port, and the `handoff --saw "…"` line to run when
you are done. No `visual:` key ⇒ one line saying the step is off.

## What handoff checks
Your diff touches a `visual:` path and `shot:` is set ⇒ TWO non-empty captures for your ID, both
newer than your branch base, and a non-empty `--saw "<what the after shot shows, and how it measures
against ops/DESIGN.md>"` — or `handoff` refuses. `verify` only warns. Nothing existed to photograph,
because the screen is brand new? That is the one escape: `--no-before "<why>"` asks for ONE capture
instead, and the reason you give is kept in the caption and shown in the gallery, so a skipped
before-shot is visible rather than silent. Captures live in the repo under `.polaris/shots/<screen>/`
— never `/tmp` — so reading one never asks permission, and `handoff` files strays into the shotdir.

## Doctrine
- One unique filename per capture, carrying the task ID — never overwrite a sibling's shot.
- The capture lock queues you. Wait your turn; never fight it, never kill it.
- A blank image is a failure, not a capture.
- Never build your own capture tool, and never force opacity to fake a paint.
- A screenshot you did not look at proves nothing — and that is now true twice over: READ the before
  and READ the after. The before is what a stakeholder reacts to; it also makes you look at the
  screen you are about to overhaul.
- One `--saw "<what the picture shows>"` line on your handoff. One.
- The gate COUNTS captures and reads their timestamps. It never inspects a filename:
  `<ID>-before-<what>.png` / `<ID>-after-<what>.png` is a naming convention that pairs the two in the
  gallery, not a rule — your repo's `shot:` may not let you choose the name at all.
- Run the tool's own `--help` / `--list-harnesses` ONCE — repo-specific flags come from the tool, not from this doc.

## Adding it to a repo
Set the keys above in `ops/CONVENTIONS.md`, and on Windows write `python`, never `python3`. Then add
the `shot:` command prefix to `.claude/settings.json` under `permissions.allow`, one line:
`readonly-allow.sh` never auto-approves `python …`, so without it every capture stops for a
permission prompt. The Planner gives each visual task a `screen:` — that human name becomes the shot
folder. Set `gallery:` and `done` publishes one curated image and caption per screen there, committed,
so you can show someone. The bar those screens must clear is `ops/DESIGN.md`: INIT writes it and it is
YOURS to edit, so unlike this file it deliberately carries no `ops/RULES.tsv` row. This file is an
installed copy — edit `kit/ops/VISUAL.md` in the kit, which is what its rule row says.
