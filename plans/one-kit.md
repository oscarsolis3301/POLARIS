# One kit for the whole machine (kit 7.0.0) — plan slug `one-kit`

Phase 4 of the owner-approved program (approved 2026-11-24; full text:
`C:\Users\oscar\.claude\plans\i-d-like-for-you-iterative-stearns-of-92029365-0619-40e8-8939-d1581417c574.md`).
6.20.0 (`walk-away`) and 6.21.0 (`prefs`) shipped 2026-11-24. 6.21.0 already gives: the machine
preferences layer, `kit_file`, `POLARIS_HOME`, a CLI that locates its own code (`OPS_DIR` from
`BASH_SOURCE`, `kit_mode`), and the doc server (`role`/`doc`/`router`) with no kit paths left in
prose; the `kit-mode` golden runs the CLI from the kit against a state-only repo.

## The owner's words (2026-11-24)
"one POLARIS installation is necessary for ALL projects on the computer using the same preferences
from the POLARIS install" — chosen explicitly: "Also one shared kit". And: "hop less if possible and
run commands for us".

## Owner decisions recorded with the approval (the plan's yes — do not re-ask)
- Only the setup command the OWNER runs (`--setup`, in their own terminal) writes Claude Code
  permission rules, auto mode or hooks. Install, update, join, migrate and INIT write none. A golden
  proves an agent-run install/update/join leaves both settings files byte-identical. A kit version
  that needs a new permission asks the owner for one click.
- The read-only approver is two-tier: a human-installed shim + trust tier written only by `--setup`;
  the versioned dispatcher (denies and context) auto-updates. The dispatcher answers `ask` when
  `ops/polaris` is not the genuine launcher (a cloned repo cannot ride the pre-approved rule).
- Each project keeps a 3-line, version-free pointer block in CLAUDE.md; no machine-wide output style.
- `auto_setup: ask | auto | off`, default ask; answering "all my projects" writes auto.
- 7.0.0 is a MAJOR (installs on other machines ask before moving).
- Migrate none of the owner's projects until the owner names one. The POLARIS repo itself stays
  vendored (its root `ops/` is the update channel).
- "Human only" write-routing rows (`kit/CLAUDE.md`, `kit/ops/polaris`, `kit/ops/hooks/*`) are in scope.
- WON'T touch: `.github/` (new proofs ride `doctor --selftest` legs on all three CI systems) · `ops/`
  by hand · RULES lines (new ones allowed with a who/why comment) · CONVENTIONS values · other
  projects · Windows security settings · no new runtime dependency.

## Design (from the 2026-11-24 design study; line numbers as of 6.19.0 — re-find them)
1. **Store:** `<POLARIS_HOME>/kit/<ver>/` = the unpacked release zip verbatim
   (`{ops,.claude,CLAUDE.md}`), a one-line `current` pointer (temp + mv; launcher accepts only a
   version token, retries once), keep current+previous, prune older after 7 days. No symlinks.
2. **Launcher:** a ~15-line tracked `ops/polaris` (bash 3.2, zero forks: builtin `read v < current`,
   validate, `. "$h/kit/$v/ops/polaris"`). The kit locates itself (6.21.0). Other machines: one line
   "POLARIS is not installed on this machine — say: install POLARIS from github.com/oscarsolis3301/POLARIS",
   exit 127. Under `CI=true` or `POLARIS_BOOTSTRAP=1` it fetches the version + sha256 pinned in an
   optional tracked `ops/KIT` and fails loudly without a pin (keeps `kit/ops/ci/polaris-audit.yml`
   working).
3. **Hooks:** one user-level dispatcher per event, registered once by `--setup`. Fold in-process the
   four pure-bash guards (model-guard, presence-guard, checkout-guard, readonly-allow; refactor each
   to function form, keep the standalone script and its `--test` face); `exec` ownership-guard,
   handover-hook, update-hook, permission-hook. Order: model ban → effort bookkeeping → presence →
   checkout deny → readonly allow → one JSON object (= today's deny > allow). Project test with
   builtins only (`*/.polaris/wt/*`, or walk up for `ops/polaris`; `ops/lib/` present ⇒ vendored ⇒
   dispatcher stands down). Bash call 4 processes → 1. `hook-dispatch` golden replays every existing
   guard battery through the dispatcher with identical verdicts; `hook-budget` pins zero forks on
   the common path.
4. **Session context:** the dispatcher's SessionStart (startup|resume|clear|compact) injects, only in
   POLARIS projects, a trimmed router (≤ 9,000 chars; today's block is 11,095, over the 10,000 hook
   cap), the voice block (repo then machine) and the five ADHD lines when adhd is on. No SubagentStart
   hook. The CLAUDE.md pointer block is the one-hop fallback; drill it on a testbed before removing the
   managed block.
5. **Updates:** a machine update fetches, verifies, unpacks `kit/<new>/` beside the old, flips
   `current` when no registered repo has in-flight work (`board_quiescent inflight` over the registry
   + live worktree beats), else stages `kit/next`. Per-repo `upgrade`/`heal` run lazily at the first
   CLI call after a version change (`.polaris/kit-seen`, builtin read). `update`/`update --auto` are
   machine operations with a machine daily cache: no repo commit, no park. `update --all` walks
   vendored repos only and must stop pruning machine-mode registry entries (`admin.sh:1324`).
   `refresh_machine_kit`'s permission block (`admin.sh:310-368`) is DELETED in both modes; so are the
   other agent-run permission writers (`install.sh:304-438` allow/hook merge for machine mode,
   `INIT.md:110-112`'s shot: allow line). Integrity: `pack.py --dogfood` stamps `zip_sha256:` into
   root `ops/VERSION` (the channel); updaters compare.
6. **join / migrate:** `join` writes the launcher, attribute + ignore lines, the commit-msg hook, the
   registry entry and the pointer block — no `.claude/`; prints `installed · fresh`. `migrate` is one
   commit (kit files out, launcher in, POLARIS hook entries + `outputStyle` swept from the repo's
   `.claude/settings.json` reusing `cmd_uninstall`'s sweep at `admin.sh:1992-2025`, permission rules
   left alone, CLAUDE.md block → pointer, then `prefs --yield` printed as an owner step); refuses on a
   busy board, in the POLARIS repo, or when the machine kit is older than the repo's. `migrate` then
   `git revert` restores a vendored project byte for byte. `python polaris-v5.zip <repo>` stays
   vendored in 7.0 (ci.yml pins it at 254, 331, 334, 339, 497).
7. **Zero-touch (Stage 2):** the dispatcher's SessionStart prints ONE line, zero forks, only when cwd
   is a git repo without `ops/polaris` (not in a linked worktree, not when `.git/polaris-setup` says
   `never`). `auto_setup` decides: `auto` applies when `.git/config` has no origin or the origin's
   owner is in machine `owners:` (seeded from registered repos); downgrades to ask with an `upstream`
   remote or an existing `ops/` folder. INIT § 0b "entered from a work request": `interview --init`
   shows nothing pending → skip interaction 1; the request is the goal → skip interaction 2; safety
   questions stay; step 4 authors the request as a task and `triage <ID>`. Skill `polaris-install`
   § Join; rung 1 becomes join.

## Also in this release (backlog from the last two runs — IDEAS.md 2026-11-24)
- EVOLVE walk-away finding 3: a wave-red fix card whose files the open wave changed is cut from the
  wave (`_wave_cut <ID>` in core.sh; `wt_add` records `branch.feat/<ID>.polaris-cut`; ownership.sh's
  five `$BASE...` diffs use the cut). Golden `wave-fix-claim`.
- The Stop hook tells a conductor "You are the INTEGRATOR — land …" while lanes still build under
  `landing: self` (`next_route` row 1 prints `integrate` under both landing modes; `hh_stop`
  ~:346). Under `landing: self` with live lanes, `next` says `wait`.
- `role CONDUCTOR --page 2` is ~32 KB (one section over the 28,000-byte pager): split that section.
- adopt's KEYS.tsv and heal's DESIGN.md reads stay on `$OPS` (adopt-stub, heal-design): decide what
  "no registry"/"no template" means in a state-only repo.
- contract walk-away § 3.1 `bg wait --max 240` vs BUILDER.md `--max 120`: measure and reconcile.

## DONE looks like
- A throwaway project `join`ed on this machine holds only the launcher and its state; every
  `bash ops/polaris …` works; `role`/`doc` serve from the store; the hooks fire through the dispatcher.
- `migrate` then revert restores a vendored project byte for byte; vendored installs keep working
  untouched beside machine installs; every existing golden byte-identical in vendored mode.
- No agent-run path changes either settings file (`no-self-grant`); `hook-dispatch` and
  `hook-budget` green; `session-context` under 9,000 chars.
- One update moves two test projects with no commit in either; the sha256 check refuses a tampered zip.
- `finish` exit 0; release ritual complete (7.0.0 everywhere); the owner then runs `--setup` once.
