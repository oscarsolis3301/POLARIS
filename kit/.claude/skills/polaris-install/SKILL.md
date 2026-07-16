---
name: polaris-install
description: Install, update, upgrade, or remove the POLARIS parallel-sprint protocol. TRIGGER when the user asks to install/add/set up POLARIS, points at a polaris-v5.zip file, or asks to update/upgrade/uninstall POLARIS or check what version it is on — including inside a repo that already runs POLARIS, because that is the only place update and uninstall can happen. DO NOT TRIGGER for ordinary board work in an installed repo (claiming, building, planning, integrating tasks) — the project's own `polaris` skill governs that.
---

# Installing POLARIS

POLARIS runs N coding agents in parallel on one repo with zero merge conflicts. The whole kit is
one file — `polaris-v5.zip`, a Python zipapp — so installing is one command and needs no unzip.

**Installing is not the job. Getting them to a ready board is the job.** You install, then you
interview them, then you plan their first sprint — all in THIS session. Do not stop halfway and
tell them to open a new chat. See § After the install, which is the important half of this file.

## First: what are they actually asking for?

`ops/polaris` exists → the kit is already here. Never reinstall over it. Which job is it?

| They said | Do |
|---|---|
| "update POLARIS" · "upgrade POLARIS" · "is there a new version" | **§ Update.** `upgrade` and `update` are one letter apart and unrelated — `update` fetches a newer kit, `upgrade` only migrates an old board and downloads nothing. They almost always mean **`update`**. |
| "install POLARIS" (already installed) | `bash ops/polaris version`, report it in one line, stop. |
| "uninstall / remove POLARIS" | **§ Uninstall.** |
| anything about tasks, the board, planning, building | **Not your job** — the project's own `polaris` skill governs. Stand down. |

`ops/polaris` does **not** exist → **§ Install.**

One more check, because it decides what you say next: **`ops/CONVENTIONS.md` is the only test for
whether INIT has run.** INIT writes it; nothing else does. Kit installed but that file missing →
the repo is installed-but-unconfigured → go straight to § After the install and set it up now.
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

A marker line whose last token is your routing instruction:

| Line | Means | You do |
|---|---|---|
| `POLARIS <version> installed · fresh` | new repo | § After the install — interview + plan |
| `POLARIS <version> installed · live-board` | INIT already ran here | `bash ops/polaris upgrade`, report in one line, **never re-run INIT** |

On `fresh`, the installer also prints a "▶ NEXT" epilogue telling the running agent to execute
INIT in the same chat. That is the fallback for a machine's first-ever install, where no skill is
loaded yet — for you it is redundant: this file's § After the install is the authoritative flow.

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

```bash
bash ops/polaris update
```

One command. It fetches the latest kit, refreshes **kit code only** (board, `RULES.tsv`,
`CONVENTIONS.md`, `MAP.md` and `SPRINT.md` are never touched), **and re-caches the new kit into
`~/.claude/`** so the next repo you install into on this machine gets it too. It refuses on a dirty
worktree and commits nothing — the user reviews the diff. Never update mid-sprint.

Report the result in **one line** (`updated 5.3.0 → 5.4.0`). Do not paste the changelog, list the
refreshed files, or explain the managed block. If they want to know what changed, they'll ask.

Two traps worth knowing, because both have already caused a bad install:

- **`upgrade` is not `update`.** `ops/polaris upgrade` migrates an old v3/v4 *board* to v5 and
  downloads nothing. Someone saying "upgrade POLARIS" almost always means `update`. Running
  `upgrade` prints a wall of green and leaves them on the old kit.
- **Do not trust `version`'s "up to date" alone if you have reason to doubt it.** It compares
  `version:` on `main`, and `raw.githubusercontent` caches for ~5 minutes. If a newer kit is
  genuinely expected, check `git ls-remote` or the releases API rather than assuming.

`--repo-only` updates the repo without touching `~/.claude` — only if they ask for it.

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
