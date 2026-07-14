---
name: polaris-install
description: Install, update, or remove the POLARIS parallel-sprint protocol in the current repo. TRIGGER when the user asks to install/add/set up POLARIS, points at a polaris-v5.zip file, or asks to update or uninstall POLARIS. DO NOT TRIGGER inside a repo that already has a working ops/polaris — there, POLARIS is already installed and the project's own protocol governs.
---

# Installing POLARIS into this repo

POLARIS is a protocol for running N coding agents in parallel on one repo with zero merge
conflicts. The whole kit ships as **one file**, `polaris-v5.zip`, which is a Python zipapp — so
installing is one command and needs no unzip step.

## First: is it already installed?

If `ops/polaris` exists, the kit is already here. Do **not** reinstall — run `bash ops/polaris version`
to report which version, and stop.

Then check one more thing, because it decides what you tell them next: **`ops/CONVENTIONS.md` is the
only test for whether INIT has run.** INIT writes it; nothing else does. If the kit is installed but
that file is missing, the repo is installed-but-uninitialized — tell them to open a new session and
say **"You are INIT."** Never use `ops/board/` for this test: older installers shipped the six empty
board columns, so an `ops/board/` can exist in a repo where INIT has never run.

## Install

The repo must be a git repo (POLARIS is built on git worktrees, branches and locks). If it isn't,
ask the user before running `git init` — never initialise a repo they didn't ask you to.

Work down this ladder and stop at the first rung that applies. **Do not skip to the download** —
rungs 1 and 2 need no network, and rung 3 is the one that can get blocked.

**1. `polaris-v5.zip` is already in the repo root** (the user dragged it in):

```bash
python polaris-v5.zip
```

**2. This machine has a cached kit** — `~/.claude/skills/polaris-install/polaris-v5.zip`, put there
by `--claude-skill`. This is the normal path. Copy it in and run it; the installer gitignores it:

```bash
cp ~/.claude/skills/polaris-install/polaris-v5.zip . && python polaris-v5.zip
```

**3. Neither exists** — the kit must be downloaded. **Do not just run `curl`.** Claude Code's
permission classifier denies fetching code from a source the user never named, so a silent download
is denied and the install dies half-way. Tell them in one line where it comes from and let them name
it:

> POLARIS ships from `github.com/oscarsolis3301/POLARIS`. Say the word and I'll pull the latest
> release from there.

Once they confirm:

```bash
curl -fsSLO https://github.com/oscarsolis3301/POLARIS/releases/latest/download/polaris-v5.zip
python polaris-v5.zip
```

**If a permission denial happens anyway**, do not hand-roll an install or work around it. Report it
plainly and give the one-time cure — it caches the kit and pre-authorizes the commands, so no
install on this machine is ever blocked again:

```bash
python polaris-v5.zip --claude-skill
```

If `python` isn't available, fall back to: `unzip polaris-v5.zip && bash polaris-v5/ops/install.sh`.

That is the entire install. It is safe on a large existing repo and idempotent:

- An existing `CLAUDE.md` is **prepended to**, never overwritten — POLARIS goes in a marked block
  and the user's own content is preserved below it.
- An existing `.claude/settings.json` has the write-guard hook **merged into** its hooks block;
  the user's other hooks are untouched.
- A live POLARIS board keeps its board, `RULES.tsv`, `CONVENTIONS.md`, `MAP.md` and `SPRINT.md` —
  only kit code is refreshed.
- Nothing is committed. The user reviews the diff.

## After installing — say this to the user

The install does not take effect in the current session: Claude Code reads `CLAUDE.md` and the
`PreToolUse` hook at **session start**. So tell them, in your own words:

1. Review the diff and commit.
2. Start a **new** session in this project.
3. In that session say: **"You are INIT."** — INIT interviews them, maps the repo, and arms the
   board. From then on the repo's own `CLAUDE.md` routes every session.
4. Claude Code will ask them to trust the project hook on first use. That is the ownership
   write-guard (`ops/hooks/ownership-guard.sh`) — approving it is expected.

## `--claude-skill` — the one-time setup that makes all of this seamless

```bash
python polaris-v5.zip --claude-skill        # add --no-permissions to skip the settings write
```

Run once per machine, from any copy of the zip. It writes three things to `~/.claude/`:

1. **the skill** — `skills/polaris-install/SKILL.md`, this file;
2. **the kit** — `skills/polaris-install/polaris-v5.zip`, so installing is a local copy (rung 2
   above) and never a download;
3. **the permission rules** — appended to `permissions.allow` in `settings.json`, so the install
   commands are pre-authorized and never prompt. Existing settings are preserved; rules are added
   only if absent. If that file can't be parsed it is left alone and the rules are printed to paste.

Recommend it whenever an install gets blocked, or when the user says they'll be installing POLARIS
in more than one repo. After it, `"install POLARIS"` works anywhere with no download and no prompts.

## Update

`bash ops/polaris update` — fetches the latest kit, refreshes kit code only, never touches the
board, and commits nothing. It refuses on a dirty worktree. Never update while a sprint is running.

The cached kit does **not** auto-refresh — it is whatever zip last ran `--claude-skill`. To refresh
it, re-run `--claude-skill` from a newer zip.

## Uninstall

`bash ops/polaris uninstall --yes` — removes `ops/`, the managed `CLAUDE.md` block, the guard hook,
and the POLARIS gitignore lines. Keeps the user's own `CLAUDE.md` content and their other hooks.
It refuses if any task is still in `active/` or `review/`. Warn them it is destructive, and that
`git checkout -- .` is the undo.

## Do not

- Do not hand-copy files out of the zip or hand-roll an install. `install.sh` handles the
  CLAUDE.md merge, the settings.json merge, exec bits, LF pinning and gitignore lines. Copying by
  hand silently loses the exec bit on `ops/polaris` and delivers a kit that does not run.
- Do not commit `polaris-v5.zip` — the installer gitignores it.
- Do not run the installer inside a directory that is not a git repo without asking first.
