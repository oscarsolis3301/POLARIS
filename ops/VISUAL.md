# SEEING YOUR WORK — the capture is the proof

## The rule
Changed something a person LOOKS at? Capture it, open the picture, and say what you saw. A green
suite has shipped a blank page before. Two halves, and neither replaces the other: `handoff` proves
a capture EXISTS; your `saw:` line proves somebody LOOKED.

## The keys (ops/CONVENTIONS.md)
```
visual: web/* src/components/*         # the surface; unset turns this whole step off
shot: python tools/shot.py {ID} {PORT} # {ID} = your task, {PORT} = your port
serve: npm run dev -- --port {PORT}    # optional: how to start this worktree's app
port_base: 4000                        # your port = port_base + (numeric tail of the ID mod 100)
```

## What pack prints
`pack <ID>` prints a SEE YOUR WORK section: the `visual:` globs and whether this task touches them,
the `serve:` and `shot:` lines with `{ID}`/`{PORT}` already substituted, your port, and the proof
path `.polaris/shots/<ID>-*.png`. No `visual:` key ⇒ one line saying the step is off.

## What handoff checks
Your diff touches a `visual:` path and `shot:` is set ⇒ at least one non-empty
`.polaris/shots/<ID>-*.png` newer than your branch base, or `handoff` refuses; `verify` only warns.
Shots live in the repo (`.polaris/` is ignored), so reading one never asks permission.

## Doctrine
- One unique filename per capture, carrying the task ID — never overwrite a sibling's shot.
- The capture lock queues you. Wait your turn; never fight it, never kill it.
- A blank image is a failure, not a capture.
- Never build your own capture tool, and never force opacity to fake a paint.
- A screenshot you did not look at proves nothing — READ the file you just made.
- One `saw: <what the picture shows>` line in your handoff. One.
- Run the tool's own `--help` / `--list-harnesses` ONCE — repo-specific flags come from the tool, not from this doc.

## Adding it to a repo
Set the four keys above in `ops/CONVENTIONS.md` — `visual:` · `shot:` · `serve:` · `port_base:` —
and on Windows write `python`, never `python3`. Then add the `shot:` command prefix to
`.claude/settings.json` under `permissions.allow`, one line: `readonly-allow.sh` never auto-approves
`python …`, so without it every capture stops for a permission prompt.
