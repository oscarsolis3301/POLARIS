# Changelog

Versions here are the **kit version** (`ops/VERSION`), not the board protocol version.
A bump in `version:` is what notifies every installed kit on its next daily check — routine
commits to `main` deliberately do not.

## 5.1.0 — 2026-07-13

Portable kit. POLARIS now moves between projects as a single zip with no `.git` attached.

- **`CLAUDE.md` is now a managed block** (`<!-- POLARIS:BEGIN -->` … `<!-- POLARIS:END -->`), and
  `update` replaces exactly that block. **This fixes a real bug:** installs used to bail with
  *"already carries POLARIS — left as is"*, so the protocol document froze at install time — every
  kit file was refreshable *except* the protocol itself, and no CLAUDE.md change could ever reach an
  installed repo. Put your own rules below the END marker; they survive every update. A legacy
  unmarked block is left alone rather than guessed at.
- **`polaris uninstall --yes`** — removes `ops/`, the managed block, the guard hook and the POLARIS
  gitignore lines, while keeping your own `CLAUDE.md` content and your other hooks. Refuses while
  work sits in `active/` or `review/`. Re-execs from a temp copy first, because it is about to
  delete the script bash is currently reading — and on Windows you cannot unlink an open file.
- **`--claude-skill`** — `python polaris-v5.zip --claude-skill` installs a user-level Claude Code
  skill, after which "install POLARIS" works in any repo and Claude fetches the release itself.
  The *project* skill can't do this: it only exists after POLARIS is installed.
- **CI on Linux, macOS and Windows** — the kit had never run outside one Windows box. The macOS job
  pins `/bin/bash` (3.2) and asserts the version, because GitHub's image puts a newer Homebrew bash
  first on `PATH` and a bare `bash` would silently test bash 5 and prove nothing. Exec bits are
  asserted against the mode *stored in the archive*, not the extracted file — Git Bash fakes
  `test -x` on Windows, so an extraction check would pass vacuously and let a dead kit ship.
- **Drag-and-run** — `polaris-v5.zip` is a Python zipapp (`__main__.py` at the archive root),
  so installing is one command with no unzip step: drop the zip in a project and run
  `python polaris-v5.zip`. It self-extracts to a temp dir, restores the exec bits the archive
  carries, and hands off to `ops/install.sh`. The target is resolved from your working
  directory, and it `git init`s only a directory you explicitly named.
  On Windows it locates Git Bash from git's own install root and probes it before use —
  `shutil.which("bash")` from native Python finds `System32\bash.exe`, which is WSL's launcher
  and dies instantly with no distro installed. That bug broke drag-and-run on every Windows box.
- **`ops/pack.py`** — builds `polaris-v5.zip` from `git ls-files`. Written in Python because
  Git Bash ships no `zip` and PowerShell's `Compress-Archive` cannot store unix permissions:
  three kit files are mode `100755` (`ops/polaris`, `ops/install.sh`,
  `ops/hooks/ownership-guard.sh`) and an archive that drops the exec bit delivers a dead kit.
  Bytes are normalised to LF, so an `autocrlf=true` checkout can't poison the archive.
  Reproducible — the same commit packs to the same bytes.
- **`ops/install.sh`** — zero-arg mode installs into the git repo the kit was unzipped inside.
  Naming a target explicitly `git init`s it if needed (greenfield); zero-arg mode never will,
  so unzipping on your Desktop can't turn the Desktop into a repo. Adds `polaris-v5/` to the
  target's `.gitignore`, so a leftover kit folder can't be committed.
- **`ops/VERSION` + `polaris version`** — every installed kit knows which POLARIS it runs
  (version, commit, build date) and what the latest is.
- **`polaris update`** — fetches the latest kit from the public channel and refreshes kit code
  only; board, RULES, CONVENTIONS, MAP and SPRINT are untouched. Manual and explicit: POLARIS
  never updates itself under a running sprint.
- **Update notices** — the network check is throttled to once a day; the notice prints on every
  command until you act on it. Fails open: offline, no curl, or a bad response → silent.
  Never runs inside the write-guard, which fires on every edit.
- **`polaris doctor`** — warns when `polaris-v5.zip` lags `HEAD`. This is the exact rot that
  left the previous zip shipping pre-CRLF-fix code.

## 5.0.0

POLARIS v5 protocol: `RULES.tsv` policy engine (danger zones + content guards), `drift`
board-hygiene audit, per-point cycle calibration in `metrics`, dashboard points/drift rails.
