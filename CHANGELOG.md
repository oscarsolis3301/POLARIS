# Changelog

Versions here are the **kit version** (`ops/VERSION`), not the board protocol version.
A bump in `version:` is what notifies every installed kit on its next daily check — routine
commits to `main` deliberately do not.

## 5.5.0 — 2026-07-14

**"Can I just tell any chat to upgrade POLARIS?" Nearly — and the gap was the one that nearly
downgraded a live board this week.**

- **`update` now updates the MACHINE, not just the repo.** It re-caches the new kit into
  `~/.claude/skills/polaris-install/` (and refreshes the skill text, which rides along in the
  tarball it already downloaded — no second request). Before this, you could update ten repos and
  the machine would still hand the *old* kit to the eleventh, because the cache is what every
  future `"install POLARIS"` copies from. That is not hypothetical: a repo ended up with a 5.1.0
  zip in its root while the cache held 5.3.0, and following the install skill literally would have
  installed the older one over the newer. One `update`, in any repo, now makes the whole box
  current. `--repo-only` opts out. The zip is fetched from the new `zip:` key in `ops/VERSION` —
  the same pinned release URL the installer's own permission rule already names. Fails open: a
  cache problem never fails a repo update that already succeeded.
- **Fixed: `update` could execute garbage after overwriting itself.** `install.sh` replaces
  `ops/polaris` — the very file bash is still reading. Bash reads scripts lazily, in chunks, *by
  byte offset*, so a script replaced mid-run resumes at the old offset inside the new bytes:
  `syntax error near unexpected token`, or worse, half a command. This was latent from the day
  `update` was written and only ever survived because the old and new files happened to line up.
  It stopped lining up. `update` now re-execs from a temp copy before touching anything — the same
  guard `uninstall` has always had, for exactly the same reason.
- **`upgrade` is not `update`, and the kit now says so.** They are one letter apart and do
  unrelated jobs: `update` fetches a newer kit; `upgrade` migrates an old v3/v4 *board* to v5 and
  downloads nothing. Someone who says "upgrade POLARIS" almost always means `update` — and would
  get a wall of green ticks and stay on the old kit. `upgrade` now says so when run directly, and
  the CLI help, `CLAUDE.md` and the install skill spell out the difference.
- **Fixed: the install skill's trigger contradicted itself.** It said *"TRIGGER when the user asks
  to update or uninstall POLARIS"* and, in the same sentence, *"DO NOT TRIGGER inside a repo that
  already has a working `ops/polaris`"* — but update and uninstall **only ever happen** in such a
  repo. The file documenting update was instructed never to fire when update was possible. It now
  triggers on install/update/upgrade/uninstall/version anywhere, and stands down only for ordinary
  board work, which the project's own `polaris` skill governs.

Note: an existing kit updates itself using its OWN `update` code, so a repo on 5.4.0 or older will
not refresh the machine cache on the way to 5.5.0 — that lands from 5.5.0 onward. Run
`python polaris-v5.zip --claude-skill` once if you want the cache current immediately.

## 5.4.0 — 2026-07-14

**Installing POLARIS took four steps across three chats, and buried you in output doing it.** Run
the installer, read a wall of ✅ lines, open a *new* chat, say "You are INIT", answer ten questions
written in kit jargon, open *another* chat, say "You are the PLANNER", open *another* chat, say
"You are a BUILDER. Claim the top ready task and complete it end to end." A protocol for going fast
that took a quarter of an hour to switch on.

The centrepiece of this release is a deletion. **The "now start a new session" rule was never a
technical requirement** — it was repeated in seven files and it was wrong in all of them. The
PreToolUse write-guard only enforces ownership on `feat/*` branches, so it is a no-op for INIT and
PLANNER, which run on the base branch. `settings.json` — hooks and permissions — hot-reloads
mid-session. And `CLAUDE.md` never needed re-reading: it is a routing table, and an agent that
already knows its role can just read `ops/roles/INIT.md`. So the whole thing runs in one chat.

- **Say "install POLARIS" and you end up on a ready board.** The install continues straight into
  INIT, which interviews you and then chains into the PLANNER, which fills the board — one session,
  no handoffs. Chaining INIT → PLANNER is now the single sanctioned exception to "never act as two
  roles in one session": it happens once per repo, before any Builder exists, on the base branch,
  and writes zero feature code. Every other session stays strictly single-role.
- **Three questions, not ten.** INIT's survey already reads every package manifest, so it now
  *derives* what it used to interrogate you for: test/lint/typecheck/build from `package.json`
  scripts, Makefile targets, `pyproject.toml`, `Cargo.toml`, `go.mod`; base branch and remote from
  git. It asks only what a repo genuinely cannot answer — how you want to be spoken to, what you
  want to build first, and one batched confirmation (the commands it found · one machine or several
  · re-test every merge or once at the end · what's radioactive, pre-ticked from the survey).
  Suite duration, DoD extras, sprint capacity and past scars are gone from the interview: they are
  derivable, defaultable, or EVOLVE's job once there is real data. Someone who has just typed
  "install polaris" does not yet know their sprint capacity in points.
- **`start`.** Nobody should have to type "You are a BUILDER. Claim the top ready task and complete
  it end to end" to do the obvious thing. `start` (or `start building`, `go`, `let's build`,
  `polaris start`) means *take the next piece of work*: it becomes a BUILDER when tasks are queued
  and a PLANNER when the board is empty, so it always does the right thing instead of erroring. It
  fires only on a bare start phrase — "start the dev server" is an ordinary request, not a kickoff.
- **The installer stopped shouting.** Quiet is now the default: one line, and its last token is a
  routing contract (`POLARIS 5.4.0 installed · fresh` | `· live-board`). The full detail still
  exists, in `.polaris/install.log`, and `--verbose` puts it back on stdout. Failures always print
  in full. This mattered more than it looks: an agent relays whatever the installer prints, so a
  chatty installer *is* a chatty agent — and the role files now carry hard caps on what gets said
  (INIT: one report, ≤8 lines, at the very end; PLANNER: ≤6 under `voice: standard`; the install
  skill: an explicit list of things not to narrate).
- **A normal install now arms the machine** — it caches the kit into
  `~/.claude/skills/polaris-install/` and appends six pinned Bash rules to `permissions.allow`, so
  every install after the first is offline and prompt-free. This was `--claude-skill`, an opt-in
  flag, on the reasoning that writing outside the project must never be implicit. That reasoning
  was wrong in practice: a per-machine setup step nobody knows about is a step nobody runs, and its
  absence surfaced as a *denied install in a different repo weeks later*. You still explicitly
  approve the `python polaris-v5.zip` run that writes them, the curl URL is still pinned in full
  rather than wildcarded, and `--no-machine-setup` opts out. Net effect: on a machine that has
  never heard of POLARIS, name the source once — `install POLARIS from
  github.com/oscarsolis3301/POLARIS` — and never again, in any repo.
- **Fixed: the cached kit was re-copied on every install.** The `samefile` guard added in 5.3.0
  stops the archive truncating itself when run *from* the cache, but it never checked whether the
  cache was already identical — so arming reported "changed" forever. It now compares content.

## 5.3.0 — 2026-07-13

**"Install POLARIS" was getting denied, and it looked like a broken installer.** It was a blocked
one. The skill told the agent to `curl` the kit from a GitHub release and execute it — and Claude
Code's permission classifier refuses, by design, to fetch code from a source the user never named
themselves. Nothing was wrong with the zip, the URL, or `install.sh`. The install simply died on
that rung, in every fresh repo, every time.

The fix is to stop needing the download at all.

- **`--claude-skill` now caches the kit.** It writes `polaris-v5.zip` next to the skill in
  `~/.claude/skills/polaris-install/`. Installing into a repo becomes `cp` + `python
  polaris-v5.zip` — a local file, no network, nothing for the classifier to object to. (Re-running
  `--claude-skill` *from* the cached copy no longer truncates it — there's a `samefile` guard, and
  CI proves it.)
- **`--claude-skill` now pre-authorizes the commands.** Six Bash rules are appended to
  `permissions.allow` in `~/.claude/settings.json` — the `python polaris-v5.zip` run, the pinned
  release URL (in full; never a wildcard), and `ops/polaris`, whose `update` curls a tarball
  internally. A rule in your own settings *is* you naming the source, which is exactly what the
  classifier asks for. Existing settings are preserved — append-if-absent, written through a temp
  file so an interrupted run can't truncate it, and a `settings.json` that won't parse is left
  alone with the rules printed to paste. Opt out with `--no-permissions`.
- **The skill can no longer dead-end.** Its install section is an explicit ladder: zip in the repo
  root → cached kit → *ask the user to name the source, then* download. If a denial happens anyway
  it reports it and prescribes `--claude-skill` instead of hand-rolling an install around the
  guard.
- **Fixed: `releases/latest` served 5.1.0 while `main` advertised 5.2.0.** 5.2.0 was never tagged,
  so every installed kit nagged about an update the release URL couldn't actually deliver, and
  every fresh download got a version-old kit. This release carries the 5.2.0 work below it.

Net effect: `python polaris-v5.zip --claude-skill`, once per machine, and `"install POLARIS"` works
in any repo — offline, no download, no prompts.

## 5.2.0 — 2026-07-13

Two things a real 843-file brownfield install taught us: agents only had one register, and a fresh
install lied to the kit about its own state.

- **`voice:` — pick how agents talk to you.** A new `ops/CONVENTIONS.md` key: `standard` (plain,
  friendly English — the default) or `technical` (dense, terse, what every POLARIS agent sounded like
  until now). INIT asks it **first, alone, before the interview**, then runs the interview itself in
  that voice — so nobody is asked to choose between `paranoid` and `batch` before they've read a word
  of the docs; they're asked whether to re-run the tests after every merge or once at the end, and
  INIT maps the answer. Voice governs **only what an agent says to you** — reports, questions, `✅`
  and `⛔` lines. What gets written to disk (task frontmatter, contracts, MAP, SPRINT, RULES, commit
  messages, code) stays exactly as machine-terse as before, because agents read those. And voice
  changes wording, never content or behavior: a red suite is still reported red, and no gate softens.
  Existing boards need no migration — `update` never rewrites `CONVENTIONS.md`, so they get the
  `standard` default, and `polaris doctor` now prints the effective voice so the knob is findable.
- **Fixed: a fresh install was indistinguishable from a live board, so INIT refused to run.** The kit
  tested "has INIT run?" by asking whether `ops/board/` existed — but `install.sh` *created*
  `ops/board/`, shipping the six empty columns and their `.gitkeep`s. So on every fresh install the
  test was false: `CLAUDE.md`'s role dispatch never offered INIT, `INIT.md`'s precondition told the
  agent to refuse ("never re-initialize over a live board"), and a second `install.sh` run announced
  "live board detected" and sent you to `polaris upgrade`. Agents got through it only by overruling
  their own role file. **`ops/CONVENTIONS.md` is now the single "has INIT run?" test everywhere** —
  it is written by INIT and by nothing else, and it is the test `doctor` already used. The installer
  no longer ships `ops/board/` at all: `polaris init-board` creates it during INIT, so the old test
  is *true* again as well as unused. CI now asserts both (no board before INIT · the installer still
  routes a re-run to INIT), so the predicate cannot rot back.
- **INIT flags git-tracked build output** (`.next/`, `dist/`, `build/`, `*.tsbuildinfo`) during the
  survey. A Builder that runs the build in such a repo dirties hundreds of files it does not own and
  `polaris verify` rejects its handoff — day one, every time. INIT reports it and proposes the
  `git rm -r --cached` + `.gitignore` fix; the human runs it, because deleting files is stop-and-ask.

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
