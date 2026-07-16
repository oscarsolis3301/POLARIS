# Changelog

Versions here are the **kit version** (`kit/ops/VERSION`), not the board protocol version.
A bump in `version:` is what notifies every installed kit on its next daily check — routine
commits to `main` deliberately do not.

## 5.9.0 — 2026-07-16

**One chat, the whole loop.** Until now every phase needed a fresh chat: plan, then open a window per
builder, then another for integration. The new **CONDUCTOR** role runs the entire loop in the one
conversation you already have — it interviews you until it truly understands, proves it with a brief,
plans, builds in parallel, integrates, and reports — each phase a fresh subagent, so context never
degrades and token discipline holds.

- **The Conductor.** In a subagent-capable CLI (Claude Code), a work request or `start` now runs
  interview → brief → plan gate → parallel builders → integration → report, hands-free after the one
  plan approval. The conductor acts as NO role itself — every role runs in its own subagent with its
  classic minimal context, so invariant 5 (one role per session) holds by construction. Live
  plain-language one-liners as each lane lands; snags surface immediately (decisions go to you, red
  work gets one fresh-builder retry, then parks in `blocked/`); `risk: high` still never merges
  without your literal approval. Lanes capped by `autolaunch_max`. New `builders:` convention key
  (`subagents` default · `panes` keeps the terminal-pane flow); CLIs without subagents fall back to
  the classic dispatch automatically. `kit/ops/roles/CONDUCTOR.md` + dispatch in `kit/CLAUDE.md`,
  `kit/.claude/skills/polaris/SKILL.md`, subagent notes in `BUILDER.md`/`INTEGRATOR.md`/`PLANNER.md`.
- **Planning that proves it understood.** The Planner's interview is no longer capped at 2 rounds: it
  lists every decision that would change the carving and asks until one more answer wouldn't change
  it — zero questions for a concrete request, several rounds for "improve the UI/UX" — always as
  concrete pick-one options in your chosen voice. Then a **brief gate**: "here's what I WILL change,
  what I WON'T touch, and what DONE looks like" — confirmed by you before a single task exists. A
  wrong brief costs one message; a wrong sprint costs every builder. `kit/ops/roles/PLANNER.md`.
- **Windows panes actually open.** 5.8.0's `fleet --launch` resolved `claude` to the npm bash shim,
  which Windows Terminal's process launcher cannot start — every pane died with `0x80070002 "file
  not found"`. The launcher now resolves a real `claude.exe`/`claude.cmd` to its full (8.3, space-safe)
  Windows path, falls back to a `bash -lc` wrapper for bash-only shims, and `--dry-run` prints the
  exact resolved command. `kit/ops/polaris`.

## 5.8.0 — 2026-07-15

**The gates hold, the loop closes.** This sprint makes POLARIS's core promise — many builders, zero
collisions, machine-enforced — true where it used to lean on a careful Planner or plain luck; clears
the snags that made a fresh sprint fail before a line of code; and gives the human real visibility
into a running board.

- **Harder gates.** `verify`/`audit` now diff with `--no-renames`, so a `git mv` can no longer smuggle
  a non-owned file's deletion past the ownership check. `drift` catches nested-glob overlaps it used to
  call "undecidable", and the Planner re-runs `drift` on the plan it just wrote before fanning out — an
  overlap now costs nothing instead of surfacing as an Integrator merge conflict two builds later.
  `kit/ops/roles/PLANNER.md`, `kit/ops/polaris`.
- **`claim` fans out for real.** With no ID, `claim` now skips a locked task and takes the next, so a
  fleet of Builder panes lands on distinct work instead of all grabbing the top one and N-1 dying; the
  worktree-add step retries under concurrency. Also fixes a hard `claim` parse error on macOS's stock
  `/bin/bash` 3.2. `kit/ops/polaris`.
- **A fresh sprint reaches green.** New `bootstrap:` convention installs deps in each Builder's worktree
  on claim; a blank `map_delta` warns at handoff so `ops/MAP.md` stops silently rotting; and `generated:`
  keeps git-tracked build output from failing a handoff. `kit/ops/roles/INIT.md`, `kit/ops/polaris`.
- **See what the board is doing.** `polaris why <ID>` shows why a task bounced or blocked; `polaris
  resume` takes over a crashed Builder's task; blocked tasks surface in `status` with their reason;
  `drift` flags dependency cycles and dangling deps; `metrics` splits build time from integration wait
  and names the oldest task awaiting integration; and the Integrator rules out a pre-existing flake
  before kicking good work back. `kit/ops/polaris`, `kit/ops/roles/INTEGRATOR.md`.
- **Windows launch actually fires.** `fleet --launch` resolves the `claude` `.cmd`/`.exe` shim that Git
  Bash's `command -v` misses, and says so plainly when it truly cannot open panes. The write-guard no
  longer false-blocks a legitimate edit when the path's case differs from git's.
  `kit/ops/polaris`, `kit/ops/hooks/ownership-guard.sh`.
- **Orientation back in the box.** The zip ships a `README.md` again; `pack.py --dogfood` refuses on a
  version mismatch instead of installing the old artifact and calling it new; the two install paths copy
  identically. `kit/README.md`, `kit/ops/pack.py`, `kit/ops/install.sh`.
- **Self-hosting honesty.** `doctor` reports when `kit/ops/VERSION` is ahead of the installed `ops/` —
  a release built but never dogfooded — and `update` refuses to run in the repo that builds POLARIS,
  where it would install `ops/` over itself. `kit/ops/polaris`.
- **An install drill a Builder can run.** `kit/ops/selftest-install.sh` exercises the fresh /
  live-board / old-client / uninstall paths end to end — the one path CI covered but a Builder could
  not is now testable by hand.

## 5.7.0 — 2026-07-15

**POLARIS takes the wheel.** Describe what you want in plain English and POLARIS routes it to the
Planner itself, asks a few simple questions to get it right, then opens a Builder per task in
side-by-side terminal panes — no "which role?" detour, no pasted kickoffs.

- **Auto-route.** A work request ("improve the settings page") with no role and no `start` word now
  becomes a PLANNER run. A guard keeps questions ("what does auth do?") and operational commands
  ("start the dev server") as ordinary chat — the discriminant is intent to *change* the repo vs. to
  *understand or operate* it. `kit/.claude/skills/polaris/SKILL.md` + `kit/CLAUDE.md`.
- **Clarify before carving.** The Planner asks bounded, voice-appropriate questions up front
  (≤2 rounds of ≤4) so the sprint's accuracy is bought once; a Builder may ask a single question when
  a spec detail is genuinely ambiguous, while structural blocks still hard-stop to the failure path.
- **Auto-launch.** New `autolaunch:` convention key (`wt` | `ask` | `off`, default `ask`). After
  planning, the Planner fans out builders per that setting: on Windows, side-by-side Windows Terminal
  panes each running `claude start`, capped at `autolaunch_max` (default 3). `polaris fleet <N>` gains
  `--launch` and `--dry-run`; the tmux path is unchanged and it falls back to printing the kickoff
  where neither tmux nor Windows Terminal is present.

## 5.6.0 — 2026-07-14

**POLARIS now builds POLARIS.** The kit runs its own board — parallel Builders, the write-guard, the
lot — which it could not do before without shipping its own board to every user.

The blocker was that the kit source and a POLARIS installation both wanted the same directory,
`ops/`. Installing here would have made our `CONVENTIONS.md`, `MAP.md`, `SPRINT.md`, `RULES.tsv` and
`board/` git-tracked *inside the product*. `pack.py` packs whatever `git ls-files` returns, so all of
it would have shipped — and a repo that has a `CONVENTIONS.md` **is** a live board by the installer's
own test, so every fresh install would have arrived pre-initialized and locked INIT out of the repo it
had just been installed into. Uninstalling would have deleted the product.

- **The product moved to `kit/`.** `kit/CLAUDE.md` + `kit/ops/` + `kit/.claude/` are everything that
  ships. The repo root is now an ordinary POLARIS installation like any other. `pack.py` runs
  `git ls-files` *inside* `kit/`, so the board is excluded structurally — not by a blacklist somebody
  has to remember to extend. The zip's internal layout is unchanged; `.github/` and `archive/` stop
  shipping as a bonus.
- **`pack.py --dogfood`** — downloads the zip **from the published release**, installs it here, and
  runs the board's selftest. It is the release's acceptance test: the only one that walks the path a
  stranger walks. A release that cannot run our own board is not a release, and CI's daily job now
  goes red if this repo lags the newest published version — *"we shipped something we never ran."*
- **`install.sh` no longer copies `ops/*.md` by glob.** Named list. A glob run from a self-hosting
  checkout — which is exactly what `polaris update` does, since it installs from the branch tarball's
  root — would have raked our `CONVENTIONS.md`/`MAP.md`/`SPRINT.md` into a stranger's repo.
- **`emit_block` unwraps a managed source.** Our root `CLAUDE.md` is now itself a managed block, and
  it is the file `update` reads. Cat it raw and every update nested one more marker pair inside the
  last, until `uninstall` — which stops at the first marker it meets — could no longer delimit the
  block it exists to remove. It now emits what lies *between* the markers, which also makes the whole
  operation idempotent, as it always claimed to be.
- **`uninstall` takes the installation and leaves the product.** In this repo `rm -rf ops/` is one
  keystroke from deleting POLARIS itself. CI clones the repo, uninstalls, and asserts `kit/` still
  builds a working kit.
- **Already-installed kits keep working.** They poll `main/ops/VERSION` and install from the tarball's
  `<root>/ops/install.sh` — both of which still resolve, because the installation committed at the
  root *is* that layout. They now serve the last **published** release rather than an unreleased tip,
  which makes the whole "bumped but never tagged" class of skew structurally impossible.

## 5.5.1 — 2026-07-14

**`update`'s success message could lie about what it had just cached.** Caught within minutes of
shipping 5.5.0, by running the thing rather than trusting it.

`refresh_machine_kit` announced *"every new install on this box now gets X"* — where X was **the
repo's** new version, not the version of the zip it had actually downloaded. `releases/latest` takes
about a minute to start serving a freshly tagged release, so an `update` run right after a release
caches the **previous** kit. A real run proved it: the repo went to 5.5.0, the message said
*"now gets 5.5.0"*, and the bytes on disk were 5.4.0. That is precisely the silent version skew this
whole feature exists to eliminate, reintroduced by the feature itself.

- **It now reads the version back out of the bytes it downloaded** and reports *that*. If the
  release hasn't propagated yet it says so plainly, names the version you actually got, and tells
  you to re-run — instead of quietly leaving the next repo on the old kit.
- **A download is validated before it becomes the cache.** `curl -f` rejects 4xx/5xx, but a
  truncated fetch is still a file, and a corrupt cached kit is worse than a stale one: every future
  install on the machine copies from it. Anything that isn't a real POLARIS kit is discarded and
  the existing cache is left exactly as it was.
- CI now asserts the report matches the bytes: whatever version `update` claims to have cached must
  be the version actually inside the cached zip.

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
