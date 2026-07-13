---
name: polaris-install
description: Install, update, or remove the POLARIS parallel-sprint protocol in the current repo. TRIGGER when the user asks to install/add/set up POLARIS, points at a polaris-v5.zip file, or asks to update or uninstall POLARIS. DO NOT TRIGGER inside a repo that already has ops/board/ and a working ops/polaris — there, POLARIS is already installed and the project's own protocol governs.
---

# Installing POLARIS into this repo

POLARIS is a protocol for running N coding agents in parallel on one repo with zero merge
conflicts. The whole kit ships as **one file**, `polaris-v5.zip`, which is a Python zipapp — so
installing is one command and needs no unzip step.

## First: is it already installed?

If `ops/board/` and `ops/polaris` both exist, POLARIS is already here. Do **not** reinstall.
Run `bash ops/polaris version` to report which version, and stop.

## Install

The repo must be a git repo (POLARIS is built on git worktrees, branches and locks). If it isn't,
ask the user before running `git init` — never initialise a repo they didn't ask you to.

**If `polaris-v5.zip` is already in the repo root** (the user dragged it in):

```bash
python polaris-v5.zip
```

**If it isn't**, fetch the latest release first — the repo is public, no auth needed:

```bash
curl -fsSLO https://github.com/oscarsolis3301/POLARIS/releases/latest/download/polaris-v5.zip
python polaris-v5.zip
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

## Update

`bash ops/polaris update` — fetches the latest kit, refreshes kit code only, never touches the
board, and commits nothing. It refuses on a dirty worktree. Never update while a sprint is running.

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
