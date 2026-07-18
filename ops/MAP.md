# MAP — POLARIS            (updated: 2026-07-18, by EVOLVE)

## Stack
Bash (>= 3.2 — macOS default; no mapfile, no assoc arrays) + Python 3 stdlib only.
No package manager, no dependencies, no build step beyond zipping. Runs on Linux, macOS and
Windows/Git Bash; CI proves all three on every push.

## The one thing to understand
The repo is BOTH the product and a user of it. `kit/` is what ships. `ops/` is a real POLARIS
installation running this repo's board. Never hand-edit `ops/` — see ops/CONVENTIONS.md § THE SPLIT.

## Entry points
| Path | What it is |
|---|---|
| kit/ops/polaris | THE CLI. ~1180 lines of bash. Every board mechanic incl. clean-history (task-commit-msg · land · seal · history · rollback — 5.12.0-unreleased). `cmd_*` per subcommand; dispatch at the bottom. |
| kit/ops/install.sh | Installs the kit into any repo. Two paths: fresh vs live-board (test = target has ops/CONVENTIONS.md). |
| kit/ops/bootstrap.py | The zipapp entry — packed to the archive ROOT as `__main__.py`, so `python polaris-v5.zip` just works. Also arms the machine (~/.claude skill + cached kit + permission rules). |
| kit/ops/pack.py | Kit-repo tool, never shipped. Builds polaris-v5.zip from `git ls-files` run inside kit/. `--dogfood` installs the published release here. |
| kit/ops/dashboard.py | `polaris dash` — read-only live board on 127.0.0.1:7373. stdlib http.server. |
| kit/ops/hooks/ownership-guard.sh | Claude Code PreToolUse guard. Two gates: RULES (every session) + files_owned (feat/<ID> only). Fails OPEN by design. |

## Modules
| Path | Purpose | Notes |
|---|---|---|
| kit/CLAUDE.md | The protocol. Installed as a MARKED, managed block in the target's CLAUDE.md. | Source of truth for the invariants. |
| kit/ops/roles/ | INIT · PLANNER · BUILDER · INTEGRATOR · EVOLVE — one file each, read by the agent playing that role. | |
| kit/ops/templates/ | TASK.md, CONTRACT.md — what the Planner instantiates. | |
| kit/ops/MANUAL.md | Fallback git recipes for environments that cannot execute the CLI. | Must mirror the CLI's behaviour. |
| kit/ops/PROMPTS.md | Copy-paste kickoffs for every role. | |
| kit/ops/VERSION | version + the four URLs (channel/tarball/repo/zip) that installed kits poll. | **Human-only.** A bump is a release act. |
| kit/ops/ci/ | polaris-audit.yml — the OPTIONAL board gate shipped to users. Not our CI. | |
| kit/ops/selftest-install.sh | Local install drill: fresh · old-client · live-board · zip purity · uninstall. | The `test:` for any install.sh change. |
| kit/ops/selftest-dashboard.sh | Dashboard smoke drill: start · GET / + /state · kill. | |
| kit/.claude/ | settings.json (wires the guard) + skills/polaris (project) + skills/polaris-install (user-level, cached to ~/.claude at install). | |
| .github/workflows/ | OUR CI. ci.yml = 3-OS drills + "one version, everywhere". release.yml = tag → publish the zip. | Danger zone: agents may not edit their own tests. |

## How a release reaches a user (know this before touching install/update)
- **fresh install** → the published `polaris-v5.zip`. Contains only `kit/`'s files, remapped to `polaris-v5/…`.
- **`polaris update`** → the branch **tarball** of `main`, and it runs `<root>/ops/install.sh` — the
  INSTANCE, not `kit/`. That is why the instance must stay committed and in sync: it is the
  compatibility surface for every kit installed before the `kit/` split. Refreshing it is `--dogfood`.
- **the update notice** → `raw.githubusercontent.com/…/main/ops/VERSION` — again the instance.

## Danger zones — agents NEVER edit these (machine-enforced, ops/RULES.tsv)
| Path | Why |
|---|---|
| ops/polaris, ops/install.sh, ops/dashboard.py, ops/VERSION, ops/MANUAL.md, ops/PROMPTS.md, ops/roles/, ops/hooks/, ops/templates/, ops/ci/ | Installed copies. Edit `kit/ops/…` instead — the installed one is overwritten on the next release install, so the work is lost. |
| kit/ops/VERSION | A bump tells every installed kit in the world that a new POLARIS exists. Human only. |
| .github/ | The CI drills are the last gate between a bad kit and every user. |

`ops/board/`, `ops/contracts/`, `ops/CONVENTIONS.md`, `ops/MAP.md`, `ops/SPRINT.md` are board STATE,
not installed code — they are written normally, by the board scripts and by the Planner/Integrator.

## Generated / vendored — never edit, never read
`.polaris/` (worktrees + update cache, gitignored) · `polaris-v5.zip` (build output, gitignored) ·
`archive/` (retired files, kept for history — never ships) · `__pycache__/`

## Hotspot files (conflict magnets — Planner must chain these, never parallel-own)
- `kit/ops/polaris` — one file, every command. Two tasks both editing it WILL collide. Chain them.
- `kit/CLAUDE.md` — the protocol. Same problem.
- `kit/ops/install.sh` — fresh path and live-board path are ~40 lines apart.

## Unverified
- Whether anyone outside this machine has POLARIS installed. The `kit/` split keeps the old
  tarball/raw-channel paths working regardless, so this is untested-in-the-wild, not unsafe.

## Deltas


- templates/ gains ROADMAP.md — human-authored standing-goal skeleton (P3, 5.13.0-unreleased)  (T-016, 2026-07-18)
