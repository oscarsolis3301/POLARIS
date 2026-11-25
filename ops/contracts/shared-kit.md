# CONTRACT: shared-kit — one kit per computer, every project holds only its state   (v1 — 2026-11-24, plan `one-kit`, 6.22.0 + 7.0.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
The owner (2026-11-24): "one POLARIS installation is necessary for ALL projects on the computer using
the same preferences from the POLARIS install" — "Also one shared kit". This contract pins the store
on disk, the launcher a project keeps, the machine update, `join` / `migrate`, zero-touch setup, the
owner-only `--setup`, and the rule that no agent-run path writes Claude Code permission config.
Hooks are `ops/contracts/hook-dispatch.md`. Plan: `plans/one-kit.md` (its "Owner decisions" are the yes).

**Two releases, one plan slug.** 6.22.0 = everything dormant behind detection (store, launcher,
dispatcher, session context, machine update, the wave cut and the backlog fixes): a vendored install
behaves exactly as 6.21.0 except § 13's listed changes. 7.0.0 = the switch (join, migrate, `--setup`,
the permission writers removed, zero-touch). Nothing in 6.22.0 writes a launcher into any repo, so
machine mode is reachable only from a test fixture until 7.0.0's `join` exists.

Cards: W1 T-341 · T-342 · T-343 · T-344 — W2 T-345 · T-346 · T-347 — R1 T-348 (6.22.0) —
W3 T-349 · T-350 · T-351 — R2 T-352 (7.0.0).

## 1. The store (T-344 writes `kit/ops/lib/store.sh`, new; T-347 adds the update path)
```
$POLARIS_HOME/kit/<ver>/          the unpacked release zip, verbatim: ops/ .claude/ CLAUDE.md (+ the zip's own top-level files)
$POLARIS_HOME/kit/<ver>/.stored   one line: <epoch> <sha256 of the zip>   (written last — its presence = complete)
$POLARIS_HOME/kit/current         one line: <ver>            (temp file + mv; never a symlink)
$POLARIS_HOME/kit/next            one line: <ver>            (a staged flip, § 5; absent = none)
```
- `<ver>` is a version token: `^[0-9]+\.[0-9]+\.[0-9]+$` exactly. Anything else in `current`/`next`
  is treated as absent. No symlinks anywhere (Windows).
- Functions (all `_`-prefixed: no api-kit row; module joins the census per module-layout v12):
  `_store_put <zip> <ver> <sha256>` — refuse unless `_sha256 <zip>` equals `<sha256>`
  (`⛔ store: <zip> does not match its sha256 — not installed`, rc 1); unpack into
  `kit/.tmp-<ver>-$$`, then `mv` to `kit/<ver>` (an existing complete `kit/<ver>` is kept, rc 0);
  write `.stored` last. Unpack with python `zipfile` when `python3`/`python` passes `-c pass`, else
  `unzip -q`; neither → `⛔ store: needs python or unzip to unpack the kit`, rc 1.
  `_store_flip <ver>` — `kit/<ver>/.stored` must exist; write `current` (temp + mv); remove `next`
  when it names `<ver>`. `_store_ver` — builtin `read` of `current`, validated; prints the token or
  nothing; zero forks. `_store_prune` — keep `current`, the newest other complete version, and
  `next`; remove any other `kit/<ver>` whose `.stored` epoch is older than 7 days, and any
  `kit/.tmp-*` older than 1 day. `_sha256 <file>` — the first that works of `sha256sum`,
  `shasum -a 256`, python `hashlib`, `certutil -hashfile <f> SHA256`; prints lowercase hex; none →
  rc 1.

## 2. The launcher (T-344 writes the template `kit/ops/launcher`, new; T-349's `join` copies it)
A project's `ops/polaris` in machine mode is a byte-for-byte copy of `kit/ops/launcher`. bash 3.2,
no `$(…)`, no external command on the normal path. Behaviour, in order:
1. `h="${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/polaris"`.
2. `read -r v < "$h/kit/current"`; on failure or an invalid token read ONCE more (a flip in
   progress); still invalid → step 4.
3. `[ -f "$h/kit/$v/ops/polaris" ]` → `POLARIS_LAUNCHER="$0"; export POLARIS_LAUNCHER` and
   `. "$h/kit/$v/ops/polaris" "$@"` (sourced, so the kit locates itself from `BASH_SOURCE`, 6.21.0).
4. When `CI` is `true` or `POLARIS_BOOTSTRAP` is `1`: bootstrap from the tracked pin `ops/KIT`
   (beside the launcher): lines `version: <ver>` · `sha256: <hex>` · optional `url: <zip url>`
   (default `https://github.com/oscarsolis3301/POLARIS/releases/download/v<ver>/polaris-v5.zip`;
   `POLARIS_KIT_SRC=<local zip path>` replaces the download — tests only, the sha256 still binds).
   Download with `curl -fsSL`, check the sha256, unpack into `$h/kit/<ver>`, write `current`, go to
   step 3. No `ops/KIT` → `⛔ POLARIS: this CI run needs a pinned kit — add ops/KIT (version: + sha256:)`
   on stderr, exit 127. A mismatch → `⛔ POLARIS: the downloaded kit does not match ops/KIT's sha256`, exit 127.
5. Otherwise print on stderr, exactly:
   `POLARIS is not installed on this machine — say: install POLARIS from github.com/oscarsolis3301/POLARIS`
   and exit 127.
- The template is ≤ 60 lines, version-free, and its first two lines are
  `#!/usr/bin/env bash` and `# POLARIS launcher — the kit lives once per computer (ops/contracts/shared-kit.md). Do not edit.`
- **Genuine launcher** (hook-dispatch.md § 5): a repo's `ops/polaris` byte-equal to
  `$POLARIS_HOME/kit/<current>/ops/launcher`. The template text is frozen from 6.22.0: changing it is
  a contract v-bump plus a re-join step, because every joined repo's copy stops being genuine.
- `kit/ops/ci/polaris-audit.yml` keeps working for a joined repo: the launcher sees `CI=true`.

## 3. Machine mode inside the kit CLI (T-347, `kit/ops/polaris`)
- Machine mode = `POLARIS_LAUNCHER` non-empty (set by § 2 step 3; zero forks to test). `kit_mode`
  (docs.sh) is unchanged and remains the diagnostic.
- **Lazy per-repo upgrade:** in machine mode, after the globals block and before dispatch, a builtin
  `read` of `$PRIMARY/.polaris/kit-seen` compared to the running kit's version; different or absent →
  run `cmd_upgrade` and `cmd_heal` quietly (stdout to `.polaris/install.log`), then write
  `kit-seen` (temp + mv). Never on `find|show|hops|help|role|doc|router|prefs|version` (the fast and
  read-only verbs). No commit, no park, no network. Vendored mode: never runs, no added fork.
- `update`, `update --auto` in machine mode are MACHINE operations (§ 5): they never touch the
  repo's tree, never commit, never park, and use the machine cache `$POLARIS_HOME/update-cache`
  (same format as `.polaris/update-cache`).

## 4. Integrity — `zip_sha256:` (T-344, `kit/ops/pack.py`)
`python kit/ops/pack.py --dogfood` computes the sha256 of the zip it installs (the published
release) and writes `zip_sha256: <hex>` into ROOT `ops/VERSION` (the channel) after the install,
replacing any earlier `zip_sha256:` line. Nothing else writes it; `kit/ops/VERSION` never carries it.
The machine update (§ 5) reads it from the channel and refuses a zip that does not match. A channel
without the line → `⛔ update: the channel names no zip_sha256 — not installed`, rc 1 (fail closed;
the vendored tarball update is unchanged and does not read it).

## 5. The machine update (T-347 — `_store_update` in store.sh; `cmd_update` / `cmd_update_auto` branch in admin.sh)
`update` (typed) or `update --auto` (SessionStart) with `POLARIS_LAUNCHER` set:
1. Ask the channel (`channel:` of the running kit's VERSION) — typed: always; `--auto`: through the
   machine cache with the 6.19 throttle rules (once a day; re-ask when the cached answer equals the
   installed version and is > 1 h old).
2. Same version → `up to date (<ver>)`; a MAJOR ahead without `--major` → today's major notice, no move.
3. Download the channel's `zip:`, `_store_put` it with the channel's `zip_sha256:` (§ 4).
4. **Quiescence over the machine:** for every registry entry (`$POLARIS_HOME/awake/repos/*`) whose
   path holds a launcher (`ops/polaris` present and `ops/lib/` absent): run
   `(cd <p> && POLARIS_LAUNCHER= bash "<new kit>/ops/polaris" __quiet)` — a hidden verb, rc 0 when
   `board_quiescent inflight` is quiet AND no `.polaris/wt/*/.polaris-beat` (or the beat file the
   kit uses) is younger than `wt_live_minutes`; it prints the first reason. All quiet → `_store_flip
   <new>` and print `kit <old> → <new> — <n> project(s) move with it`. Any busy → write `kit/next`
   and print `kit <new> is ready — it switches when <p> is quiet (<reason>)`. A later `update --auto`
   with a valid `kit/next` re-runs step 4 only.
5. `_store_prune`. Then, when the new kit's trust tier differs from the installed one
   (hook-dispatch.md § 4), ONE line: `⛔ needs you: this kit approves new read-only commands — run in your own terminal: python "<POLARIS_HOME>/kit/<new>/polaris-v5.zip" --setup`
   (the zip path the store keeps beside the unpacked files: `_store_put` copies the zip to
   `kit/<ver>/polaris-v5.zip`).
- No repo commit, no park, no `install.sh` run, no `.claude/` write, in any repo.
- `update --all` (vendored walk, admin.sh, T-341): an entry whose path holds a launcher (no
  `ops/lib/`) is NOT removed: it prints `<p>: machine kit — moves with the machine update` and is
  skipped. (Today's `no ops/VERSION → removed` rule removed it: a joined repo has no `ops/VERSION`.)

## 6. `join` (T-349, new `kit/ops/lib/join.sh`, `cmd_join`)
`bash "<kit>/ops/polaris" join [<dir>]` (default: the git toplevel of cwd). Refuses:
not a git repo (`⛔ join: <dir> is not a git repository`), a linked worktree, `ops/polaris` present
(`⛔ join: <dir> already runs POLARIS (<vendored|machine>)`), the POLARIS repo itself
(`kit/ops/pack.py` present), no complete store version (`⛔ join: this machine has no POLARIS kit — run: python polaris-v5.zip --setup`).
Writes, and nothing else:
- `ops/polaris` = `$POLARIS_HOME/kit/<current>/ops/launcher` (exec bit; `git update-index --chmod=+x` when the index has it).
- `.gitattributes`: the lines install.sh adds today (LF pins for `ops/polaris` and the board set), each once.
- `.gitignore`: the lines install.sh adds today (`.polaris/` …), each once.
- `.git/hooks/commit-msg` from the kit (as install.sh does; an existing non-POLARIS hook is left and
  a note says so).
- the registry entry (`$POLARIS_HOME/awake/repos/<cksum>`, install.sh's exact formula).
- `CLAUDE.md`: the POINTER block (§ 8) — prepended when the file exists, created when not; an
  existing POLARIS block is replaced by the pointer.
- **No `.claude/` file, no settings file, no `ops/VERSION`, no commit.**
Last line printed, exactly: `installed · fresh` when `ops/CONVENTIONS.md` is absent, else
`installed · live-board`. ≤ 2 lines above it (install-parity's quiet-line rule). Never prints the INIT
kickoff phrase.

## 7. `migrate` (T-349, `cmd_migrate`)
`bash ops/polaris migrate` from a VENDORED repo's primary. Refuses (nothing written):
busy board (`board_quiescent inflight` — `⛔ migrate: <reason> — finish or park the work first`) ·
the POLARIS repo (`⛔ migrate: the POLARIS repo stays vendored — its ops/ is the update channel`) ·
no complete store version · the store's current kit older than the repo's `ops/VERSION`
(`⛔ migrate: this machine's kit (<a>) is older than this project's (<b>) — update the machine first`) ·
a dirty tree inside the kit footprint (`_kit_footprint_paths`).
Does, as ONE commit `chore(polaris): migrate to the machine kit (<ver>)` on the current branch:
1. `git rm` every path `_kit_footprint_paths` names EXCEPT state (`ops/CONVENTIONS.md`, `MAP.md`,
   `RULES.tsv`, `SURFACES.tsv`, `SPRINT.md`, `ROADMAP.md`, `DESIGN.md`, `contracts/`, `tests/`,
   `board/`) — kit code, `ops/VERSION`, `ops/KEYS.tsv`, `.claude/skills/{polaris,polaris-install,i-have-adhd}/`,
   `.claude/output-styles/polaris.md`, `.claude/agents/polaris-runner.md`.
2. `ops/polaris` ← the launcher.
3. `.claude/settings.json`: remove every hook entry whose command names `ops/hooks/` and the
   `outputStyle: polaris` key — the SAME sweep `cmd_uninstall` does, through the shared helper
   `_settings_sweep <file>` (T-341 factors it out of `cmd_uninstall`, move-only). Permission rules
   are left alone. A file left as `{}` is kept.
4. `CLAUDE.md`: the managed block → the pointer block (§ 8).
5. Register the repo; write `.polaris/kit-seen`.
Then print, as the owner step: `▶ yours: bash ops/polaris prefs --yield` (machine-prefs § 7).
`git revert <that commit>` restores the vendored project byte for byte (golden join-migrate).

## 8. The pointer block (T-349 writes it; T-346's session context is what makes it enough)
Three lines, version-free, byte-exact:
```
<!-- POLARIS:BEGIN pointer -->
This project runs POLARIS from the kit on this computer; the protocol arrives at session start. Missing? Run `bash ops/polaris router` and follow it.
<!-- POLARIS:END -->
```
The BEGIN line matches install.sh's `BEGIN_TAG` prefix and END is byte-identical to `END_M`, so
`uninstall` and `doctor` still delimit it. In machine mode `heal`/`upgrade` never expand it.

## 9. Zero-touch (T-346 prints the line; T-351 writes the words and keys)
- The dispatcher's SessionStart (hook-dispatch.md § 6) prints ONE line, zero forks, only when: cwd
  is inside a git repo (walk up for a `.git` DIRECTORY with builtins — a `.git` file = linked
  worktree → nothing), the repo has no `ops/polaris`, and `.git/polaris-setup` does not hold `never`.
- Machine keys (preferences file only; KEYS.tsv rows with scope `machine`, T-351):
  `auto_setup: ask | auto | off` (default `ask`) · `owners: <name>[,<name>…]` (default empty;
  `prefs --seed` fills it from the `origin` owners of registered repos, T-350).
- `auto` applies only when `.git/config` has no `[remote "origin"]`, or origin's owner (the path
  segment before the repo name in its url) is in `owners:`; an `[remote "upstream"]` section or an
  existing `ops/` folder downgrades it to `ask`.
- Lines (exact; `<kit>` = `$POLARIS_HOME/kit/<current>/ops/polaris`):
  ask → `POLARIS is not set up in this project. If the owner's request changes it, ask once (here · all my projects · not here); here → bash "<kit>" join · all → also bash ops/polaris prefs --set auto_setup=auto · not here → write never to .git/polaris-setup.`
  auto → `POLARIS is not set up in this project. Before the first change the owner asks for, run bash "<kit>" join, then bash ops/polaris role INIT (entered from a work request).`
  off → nothing.
- INIT § 0 "Entered from a work request" (T-351; first-run v3): `interview --init` shows no QUESTION line → skip
  interaction 1; the request is the goal → skip interaction 2; safety questions stay; step 4 authors
  the request as a task and runs `triage <ID>`.

## 10. `--setup` — the one owner-run writer (T-350, `kit/ops/bootstrap.py`)
`python polaris-v5.zip --setup` (also accepted: `python <store>/kit/<ver>/polaris-v5.zip --setup`).
- Refuses when `CLAUDECODE` is non-empty: `⛔ --setup changes Claude Code's own settings — run it in your own terminal, not through an agent`, rc 2, nothing written.
- Does: today's `--claude-skill` arm (skill, cached zip, output style, ADHD skill, keep-awake, permission
  rules, auto-mode keys — `arm_machine(permissions=True)`), PLUS: store this zip (§ 1, in python),
  write `current`, write the shim and trust tier (hook-dispatch.md § 4), register the dispatcher
  hooks (hook-dispatch.md § 3) in `~/.claude/settings.json`, replacing the user-level model-guard
  registration it folds (by script identity), and leave every other hook entry alone. Idempotent.
- `--claude-skill` keeps its 6.21 behaviour for a human (ci.yml 250-295 pins it).

## 11. No agent-run path writes permission config (T-350; golden `no-self-grant`, T-352)
"Agent-run" = `CLAUDECODE` non-empty. Under it, nothing writes `permissions.allow`, `permissions.defaultMode`,
`skipAutoPermissionPrompt`, `useAutoModeDuringPlan` or any `hooks` entry, in `$CLAUDE_CONFIG_DIR/settings.json`,
`$CLAUDE_CONFIG_DIR/settings.local.json`, or (for join / migrate / machine update / lazy upgrade)
the repo's `.claude/settings.json` and `.claude/settings.local.json`:
- `refresh_machine_kit`'s permission block (admin.sh, the `AUTOMODE` python) is DELETED in both modes.
- `bootstrap.py` under `CLAUDECODE`: `arm_machine(permissions=False)` whatever the flags, plus one line
  `⛔ needs you: python "<zip>" --setup in your own terminal (permissions and hooks are yours to grant)`.
- `model-guard.sh install` and `polaris awake install` under `CLAUDECODE`: refuse with the same line, rc 2.
- INIT.md's `shot:` allow-rule line (6.21 INIT.md ~110-112) is removed (T-351).
- **Kept (assumed, owner-visible in the close):** a VENDORED install/update keeps merging the kit's
  own hook entries and read-only rules into the repo's `.claude/settings.json` — that file is part of
  the vendored kit, ci.yml:497 pins the merge, and "vendored installs keep working untouched" is the
  plan's DONE line. `availableModels` (`_restore_fable_once`) is not permission config.

## 12. Words the CLI prints (new lines only — no existing golden moves except where § 13 says)
`⛔ store: …` (§ 1) · launcher lines (§ 2) · `⛔ update: the channel names no zip_sha256 — not installed` ·
`kit <old> → <new> — <n> project(s) move with it` · `kit <new> is ready — it switches when <p> is quiet (<reason>)` ·
`<p>: machine kit — moves with the machine update` · join/migrate lines (§§ 6-7) · `▶ yours: bash ops/polaris prefs --yield` ·
zero-touch lines (§ 9) · `--setup` lines (§§ 10-11).

## 13. Goldens and drills — who owns what (lesson 3: a card owns every expected file its change moves)
| golden / drill | owner | what |
|---|---|---|
| `wave-fix-claim` (new) | T-341 | safe-landing v2 |
| `update-registry` (+1 case) | T-341 | § 5 last bullet |
| `adopt-stub`, `heal-design` (fixtures only, output byte-identical) | T-341 | § 14 |
| `handover-route`, `handover-stop`, `runner-path` | T-342 | role-handover v6, walk-away v2 |
| `api-kit` | T-343 (W1: the guard renames) · T-346 (W2: CONDUCTOR heading) · T-348 (R1) · T-349 (W3: `cmd_join`, `cmd_migrate`) · T-352 (R2: the install skill's `## Join`/`## Migrate`) | one owner per wave; every other card adds no public function and no kit heading |
| `store-launcher` (new) | T-344 | §§ 1-2, 4 |
| `hook-dispatch`, `hook-budget` (new) | T-345 | hook-dispatch.md |
| `session-context` (new), `doc-server` | T-346 | hook-dispatch.md § 6, doc-server v2 |
| `machine-update` (new) | T-347 | §§ 3, 5 |
| `lib-census`, `startup-budget` | T-347 (W2) · T-349 (W3) | module-layout v12 |
| `join-migrate` (new) | T-349 | §§ 6-8 |
| `machine-armed`, `update-arms`, `perm-tools`, `skill-install` (only if they move) | T-350 | § 11 |
| `cfg-layers`, `keys-drift` | T-351 | § 9 keys |
| `prefs-cli` (`--seed` fills `owners:`) | T-350 | § 9 keys |
| `no-self-grant` (new), `kit-mode` (+join cases), `drill_sharedkit` (selftest, rides CI) | T-352 | § 11, DONE |
| `kit/.claude/skills/polaris-install/SKILL.md` `## Join` / `## Migrate` (first-run v3) | T-352 | § 6-7 words |
`cli-help.expected` is the conductor's (release ritual), never a card's.

## 14. adopt / heal in a state-only repo (T-341 — the IDEAS 2026-11-24 decision)
KEYS.tsv and `templates/DESIGN.md` are KIT data. `cmd_adopt` reads `kit_file KEYS.tsv` and
`cmd_heal` reads `kit_file templates/DESIGN.md` (a repo copy still wins). "No registry" / "no
template" can then only mean an incomplete VENDORED kit; the goldens `adopt-stub` and `heal-design`
keep that case by running a vendored copy of the CLI inside their fixture (copy `kit/ops/polaris`
and `kit/ops/lib/` into the fixture's `ops/`), and every printed line stays byte-identical.

## Invariants
- Vendored install: every existing golden byte-identical except the rows § 13 names; no new fork on
  the vendored startup path (`startup-budget` unchanged).
- One owner of `kit/ops/polaris` per wave (T-347 W2, T-349 W3); one of `admin.sh` per wave
  (T-341 W1, T-347 W2, T-350 W3); one of `api-kit.expected` per wave (§ 13).
- Tests never touch the real `~/.claude`: fake `HOME`/`CLAUDE_CONFIG_DIR` + `POLARIS_PREFS=`; set
  or unset `CLAUDECODE` explicitly per case; `PYTHONIOENCODING=utf-8` for any python that prints.
- No new runtime dependency: git + bash; python or unzip only to unpack a kit.

## Changelog
- v1 2026-11-24: created for plan `one-kit` (T-341 … T-352).
