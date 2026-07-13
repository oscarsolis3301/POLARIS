# Changelog

Versions here are the **kit version** (`ops/VERSION`), not the board protocol version.
A bump in `version:` is what notifies every installed kit on its next daily check — routine
commits to `main` deliberately do not.

## 5.1.0 — 2026-07-13

Portable kit. POLARIS now moves between projects as a single zip with no `.git` attached.

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
