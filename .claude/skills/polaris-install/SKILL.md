---
name: polaris-install
description: Install, update, or remove the POLARIS parallel-sprint protocol in the current repo. TRIGGER when the user asks to install/add/set up POLARIS, points at a polaris-v5.zip file, or asks to update or uninstall POLARIS. DO NOT TRIGGER inside a repo that already has a working ops/polaris — there, POLARIS is already installed and the project's own protocol governs.
---

# Installing POLARIS

POLARIS runs N coding agents in parallel on one repo with zero merge conflicts. The whole kit is
one file — `polaris-v5.zip`, a Python zipapp — so installing is one command and needs no unzip.

**Installing is not the job. Getting them to a ready board is the job.** You install, then you
interview them, then you plan their first sprint — all in THIS session. Do not stop halfway and
tell them to open a new chat. See § After the install, which is the important half of this file.

## First: is it already installed?

`ops/polaris` exists → the kit is here. Do **not** reinstall. Run `bash ops/polaris version`,
report the version in one line, stop.

Then one more check, because it decides what you say next: **`ops/CONVENTIONS.md` is the only test
for whether INIT has run.** INIT writes it; nothing else does. Kit installed but that file missing
→ the repo is installed-but-unconfigured → go straight to § After the install and set it up now.
Never test `ops/board/` for this: older installers shipped the six empty columns, so `ops/board/`
can exist in a repo where INIT never ran.

## Install

Needs a git repo (POLARIS is built on worktrees, branches and locks). Not a repo? Ask before
running `git init` — never initialise a repo they didn't ask for.

Work down this ladder, stop at the first rung that applies:

**1. Cached kit** — `~/.claude/skills/polaris-install/polaris-v5.zip`. The normal path on any
machine that has installed POLARIS even once. Local file, no network:

```bash
cp ~/.claude/skills/polaris-install/polaris-v5.zip . && python polaris-v5.zip
```

**2. `polaris-v5.zip` already in the repo root** (they dragged it in): `python polaris-v5.zip`

**3. Neither** — the kit must be downloaded, and this is the one rung that can get blocked. **Do
not just run `curl`.** Claude Code's permission classifier denies fetching code from a source the
user never named, so a silent download dies half-way and looks like a broken installer. Ask in one
line and let them name it:

> POLARIS ships from `github.com/oscarsolis3301/POLARIS`. Want me to grab it?

Then:

```bash
curl -fsSLO https://github.com/oscarsolis3301/POLARIS/releases/latest/download/polaris-v5.zip
python polaris-v5.zip
```

This rung only ever runs **once per machine**: a normal install also arms the machine (caches the
kit into `~/.claude/skills/polaris-install/` and pre-authorizes the commands in
`~/.claude/settings.json`), so every install after this one takes rung 1 — offline, no prompt.
`--no-machine-setup` opts out; `--verbose` prints the full install log instead of the result.

No `python`? Fall back to `unzip polaris-v5.zip && bash polaris-v5/ops/install.sh`.

**If a permission denial happens anyway**, do not hand-roll an install or work around the guard.
Report it plainly and prescribe the cure: `python polaris-v5.zip --claude-skill`.

### What the installer prints

Exactly one line, and its last token is your routing instruction:

| Line | Means | You do |
|---|---|---|
| `POLARIS 5.4.0 installed · fresh` | new repo | § After the install — interview + plan |
| `POLARIS 5.4.0 installed · live-board` | INIT already ran here | `bash ops/polaris upgrade`, report in one line, **never re-run INIT** |

Full detail is in `.polaris/install.log` (gitignored). Read it only if the install failed.

The install is safe on a 10k-file repo and idempotent: an existing `CLAUDE.md` is **prepended to**,
never overwritten; an existing `.claude/settings.json` gets the guard hook **merged into** its hooks
block; a live board keeps its board, `RULES.tsv`, `CONVENTIONS.md`, `MAP.md` and `SPRINT.md`.
Nothing is committed — INIT does that.

## After the install — DO NOT STOP HERE

Read `ops/roles/INIT.md` and execute it, **in this session, now.** INIT interviews them, maps the
repo, arms the board, and chains into the PLANNER so they end up with a planned first sprint.

**There is no session restart. Do not ask for one.** It used to be in this file and it was never a
technical requirement — future-you will be tempted to "helpfully" put it back, so here is why it is
wrong:

- The PreToolUse write-guard only enforces ownership on `feat/*` branches. INIT and PLANNER run on
  the base branch, so it is a no-op for them. They lose nothing.
- `.claude/settings.json` — hooks and permissions — hot-reloads mid-session.
- `CLAUDE.md` is not re-read mid-session, and does not need to be: it is only a routing table, and
  you already know your role. The protocol lives in `ops/roles/*.md`, which you can just read.

### Say exactly this, and nothing else

On a fresh install, the **only** thing you say before INIT's first question is:

> POLARIS is installed 🎉 Let's get you set up — a few quick questions.

Then start INIT's interview immediately.

**Do not:**

- narrate the install, list the files it touched, or explain the managed `CLAUDE.md` block, the
  gitignore lines, the LF pinning, or the write-guard;
- paste or summarise the installer's output;
- explain what POLARIS is, unless they ask;
- use the words `files_owned`, `wsjf`, `worktree`, `local-lock`, `paranoid`, `claim-branch`, or
  `handoff` in anything you say to them — INIT sets `voice:` and it defaults to plain English;
- mention the hook-trust prompt unless it actually appears.

They typed four words. Everything above is you talking to yourself.

## Update

`bash ops/polaris update` — fetches the latest kit, refreshes kit code only, never touches the
board, commits nothing. Refuses on a dirty worktree. Never update mid-sprint.

The cached kit does **not** auto-refresh — it is whatever zip last ran an install on this machine.
To refresh it, run a newer zip once.

## Uninstall

`bash ops/polaris uninstall --yes` — removes `ops/`, the managed `CLAUDE.md` block, the guard hook
and the POLARIS gitignore lines; keeps their own `CLAUDE.md` content and their other hooks. Refuses
if any task is in `active/` or `review/`. Warn them it is destructive; `git checkout -- .` is the undo.

## Do not

- Do not hand-copy files out of the zip or hand-roll an install. `install.sh` handles the CLAUDE.md
  merge, the settings.json merge, exec bits, LF pinning and gitignore lines. Copying by hand
  silently loses the exec bit on `ops/polaris` and delivers a kit that does not run.
- Do not commit `polaris-v5.zip` — the installer gitignores it.
- Do not run the installer in a non-git directory without asking first.
