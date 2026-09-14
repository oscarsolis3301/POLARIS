# CONTRACT: first-run            (v1 — 2026-09-14, Sprint B of plan `spend-less`, 6.4.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Three gaps a repo hits the first time POLARIS runs in it, and every time it moves to another machine
(plans/v3.md § B1 · B2 · B4): (1) nothing asks the human the three preferences the kit cannot derive
— how to be talked to, ADHD-shaped replies, one computer or several — so `voice:` and `claim:` are
guessed and `/i-have-adhd` stays a secret; (2) `arm_machine()` puts only the installer skill in
`~/.claude`, so on a fresh machine the output style and the ADHD skill exist only inside repos where
the installer ran — no style, no 🎉; (3) `sync_board` PUSHES the board ref under `claim-branch`, but
nothing ever fetches it, so a second machine reads a board frozen at its last clone. This contract
pins the interview as DATA (a fifth KEYS.tsv column; `polaris interview` generates the questions), the
machine arming, and `board_pull`. Tasks: T-141 (interview + admin.sh, W2) · T-143 (installers, W1) ·
T-148 (board_pull, W1) · T-144 (tests, W3) · T-145 (prose, W3). The api-kit owner table for the whole
sprint is `ops/contracts/test-surfaces.md` v2 § 18.

## 1. `kit/ops/KEYS.tsv` gains column 5 — `ask` (T-141)
```
key<TAB>since<TAB>default<TAB>absent-cost[<TAB>ask]
```
`ask` is OPTIONAL and empty for every existing row. When present:
`<question>|<label>=<value>|<label>=<value>[|…]` — the question in plain English, then ≥ 2 options;
the FIRST option is the default the interview pre-selects. `|`, `=` and TAB never appear inside a
question or a label. Every reader that splits on TAB keeps working (`doctor`'s awk takes column 1;
`find --api` records column 1); `cmd_adopt` reads a FIFTH variable (`read -r key since def cost ask`)
so a stub never carries the question — its stub line is byte-identical to today (`adopt-stub`,
`drill_adopt` unchanged). Exactly THREE rows carry `ask` in 6.4.0 (one TAB between columns):
```
voice<TAB>5.2.0<TAB>standard<TAB>agents talk to you in plain friendly English; technical makes them dense and terse<TAB>How should I talk to you?|Plain and warm, with a 🎉 when work lands=standard|Technical and terse=technical
adhd<TAB>6.4.0<TAB>off<TAB>replies are not shaped for ADHD unless you type /i-have-adhd — on makes that skill fire on its own in every session here<TAB>Want replies shaped for ADHD — next action first, numbered steps, wins made visible?|Not needed=off|Yes, always=on
claim<TAB>5.0.0<TAB>local-lock<TAB>locks stay on this machine; several machines sharing one repo need claim-branch<TAB>Will you work on this project from one computer, or several?|One computer=local-lock|Several computers (the board follows a shared remote)=claim-branch
```
`adhd` is a NEW row placed directly AFTER `voice` (KEYS.tsv order is the interview's order: voice ·
adhd · claim — `claim` stays where it is). The KEYS.tsv header comment gains one line describing
column 5. Columns 1–4 of `voice` and `claim` are unchanged.

## 2. `polaris interview [--pending | --set <key>=<value> …]` — admin.sh (T-141, W2)
EXACTLY three new top-level fns: `interview_pending` · `interview_set` · `cmd_interview`.
- **answered** = `$CONV` has a LIVE `^<key>:` line OR a stub `^#[[:space:]]*<key>:` line (a stub is
  "known and deliberately unset" — the reading doctor's drift line and `adopt` use; one `adopt` run
  therefore silences the interview too, on purpose). **pending** = an `ask` row that is not answered.
  No `$OPS/KEYS.tsv` ⇒ nothing is ever pending (rc 1, silent). No `$CONV` ⇒ `interview` dies like
  `adopt`: `no ops/CONVENTIONS.md — INIT has never run here; the interview writes into it (ops/roles/INIT.md)`
  (but `interview_pending` itself just answers rc 1).
- **`interview_pending`** — stdout ONE line: the pending keys joined by ` · ` (KEYS.tsv order); rc 0
  when ≥ 1, rc 1 and nothing when none. Pure: one awk over the two files, no fork beyond it.
- **`interview`** (no flag) — the pending questions as DATA the model turns into ONE
  AskUserQuestion, then one plain line. Per pending key, in KEYS.tsv order:
  ```
  QUESTION<TAB><key><TAB><question>
  OPTION<TAB><key><TAB><value><TAB><label>[<TAB>default]
  ```
  (`default` marks the first option). Then
  `note "<n> preference(s) never set here — ask them in ONE round (never more than 4 questions), then: ops/polaris interview --set <k1>=<d1> --set <k2>=<d2> …"`
  with each key's default filled in. Nothing pending ⇒ `say "every preference is set — nothing to ask"`, rc 0.
- **`interview --pending`** — the probe doctor and update use: pending ⇒ prints
  `preferences never set here: <k1> · <k2> — one round of questions: ops/polaris interview` (stdout,
  via `note`), rc 1; none ⇒ silent, rc 0. **Doctor and update render the SAME line themselves** from
  `interview_pending`'s output — `note "preferences never set here: $(interview_pending) — one round of questions: ops/polaris interview"`.
- **`interview --set <key>=<value>`** (repeatable; ALL-OR-NOTHING — every pair is validated before
  any write): `<key>` must carry `ask` (else `die "interview: '<key>' is not an interview key (voice · adhd · claim)"`);
  `<value>` must be one of its option values (else `die "interview: <key> takes <v1> | <v2>, not '<value>'"`).
  Preconditions, in order: on any `feat/*` branch `die "interview --set runs on $BASE only"`;
  `claim=claim-branch` without `has_remote` ⇒ `die "claim-branch needs an origin remote — git remote add origin <url> first; nothing written"`.
  **`interview_set <key> <value>`** writes ONE key into `$CONV`: a live line ⇒ its value replaced,
  any trailing `  # …` comment kept; a stub ⇒ the stub line replaced IN PLACE by
  `<key>: <value>   # <absent-cost>`; neither ⇒ that line appended at the END (after one blank
  line). Temp file + `mv`, LF kept, never `sed -i`.
  **Side effect, after all writes:** `adhd=on` ⇒ in `$PRIMARY/.claude/skills/i-have-adhd/SKILL.md`
  the line `disable-model-invocation: true` becomes `disable-model-invocation: false`; `adhd=off` ⇒
  the reverse; file absent ⇒ `note "⚠ .claude/skills/i-have-adhd/SKILL.md is not installed here — run: bash ops/polaris update"`.
  The KIT copy (`kit/.claude/skills/i-have-adhd/SKILL.md`) is never touched by anything
  (`adhd-skill-installed` pins `true` there). Tail: `say "set <k1>: <v1> · <k2>: <v2>"` then
  `note "review, then commit ops/CONVENTIONS.md — nothing was committed for you"`.
- **Usage entry** (kit/ops/polaris — T-140 writes it in W1, directly AFTER the `adopt` entry;
  between W1 and W2 `polaris interview` names an undefined function — accepted, nothing calls it
  before T-141; verbatim):
  ```
    interview [--pending | --set <key>=<value> …]
                                   the preferences a repo cannot derive — how to be talked to
                                   (voice), ADHD-shaped replies (adhd), one computer or several
                                   (claim) — generated from ops/KEYS.tsv's ask column. Plain =
                                   print what is still unanswered as QUESTION/OPTION lines (ask
                                   them in ONE round); --set writes the answers into
                                   ops/CONVENTIONS.md (a stub is replaced in place) and applies
                                   them (adhd: on lets /i-have-adhd fire on its own); --pending =
                                   rc 1 + one line when anything is unanswered. Never runs from
                                   update --auto
  ```
  Dispatch: `interview)  shift; cmd_interview "$@";;` (no `update_check_maybe`).
- **Where the line is CALLED** — never from `update --auto`, which stays exactly one pinned line:
  - `doctor` (T-142, observe.sh): directly after the surfaces nudge (test-surfaces.md v2 § 15), when
    `$CONV` exists — guarded `command -v interview_pending >/dev/null 2>&1` because T-141 and T-142
    land in the same wave (both present at the wave gate; the guard is what keeps the lane honest
    before it). Proven in `drill_surfaces` step 10 (test-surfaces.md v2 § 17).
  - `update`'s explicit epilogue (T-141, admin.sh): after the `untouched:` line, when `$CONV` exists.
  - `polaris-install` SKILL.md § Update (T-145): `If the update or doctor printed 'preferences never set here', run bash ops/polaris interview, ask its questions in ONE AskUserQuestion, then --set the answers. That is the only question you add to an update.`
- **`install.sh`** (T-143): after the vendored i-have-adhd copy (both install paths reach it), when
  `$TARGET/ops/CONVENTIONS.md` has a live `^adhd:[[:space:]]*on` line, the just-copied
  `$TARGET/.claude/skills/i-have-adhd/SKILL.md` gets `disable-model-invocation: false` (temp file +
  `mv`) — so an update never silently re-arms the opt-in flag on a repo that opted in.
  `kit/ops/selftest-install.sh` (T-143) gains the case: a live-board target whose CONVENTIONS says
  `adhd: on` ⇒ `false` after install; a target without the line ⇒ `true`.
- **Golden `ops/tests/interview.cmd/.expected`** (T-141; hermetic — a throwaway repo with a FAKE
  `ops/KEYS.tsv` of five rows: three with `ask` — `fk_voice`, `adhd` (the one real name, because the
  side effect keys on the KEY NAME `adhd`; its effect is proven on a fixture
  `.claude/skills/i-have-adhd/SKILL.md` holding just the frontmatter lines), `fk_claim` — and two
  without; a CONVENTIONS with `fk_voice` live, `fk_claim` stubbed, `adhd` absent). Pins: the
  QUESTION/OPTION lines for the one pending key · the tail with its default · `--pending` rc 1 +
  line · `--set adhd=on` (file after: appended line, the flag flipped) · `--set fk_voice=x` die
  naming the options · `--set nope=1` die · `--set fk_claim=<v>` replacing the stub in place · every
  preference set ⇒ `--pending` rc 0 silent and plain `interview` says nothing to ask · no
  CONVENTIONS ⇒ die · a run from `feat/x` ⇒ die.

## 3. Machine arming — bootstrap.py `arm_machine` + admin.sh `refresh_machine_kit` (T-143 W1 · T-141 W2)
- **`arm_machine`** lands TWO more things beside the installer skill and the cached kit, from the
  archive: `polaris-v5/.claude/output-styles/polaris.md` → `~/.claude/output-styles/polaris.md`;
  `polaris-v5/.claude/skills/i-have-adhd/{SKILL.md,LICENSE,SOURCE.md}` → `~/.claude/skills/i-have-adhd/`.
  ONE new top-level fn, `arm_file(z, member, dest) -> bool` — write iff the bytes differ (the
  SKILL.md `existing != body` guard, generalized); returns whether it wrote; the results fold into
  `changed` (a byte-identical copy is not a change — the cmp lesson). A missing archive member ⇒ skip
  silently (an older zip). Two `out()` lines: `✅ output style armed:   <dest>` · `✅ ADHD skill armed:     <dest dir>`.
  **Non-goal, pinned:** `outputStyle` in `~/.claude/settings.json` is NEVER written — a machine-wide
  style would restyle every non-POLARIS repo; selection stays per repo (`install.sh` seeds it
  set-if-absent) or per session (`/output-style polaris`). The machine copy of i-have-adhd keeps
  `disable-model-invocation: true` — the opt-in is a REPO preference (`adhd:`), never a machine one.
  `--no-machine-setup` skips all of it; `--no-permissions` is unrelated (these touch no settings file).
- **`refresh_machine_kit`** (admin.sh, T-141): after the skill copy, the same two targets from the
  tarball (`$kitsrc/kit/.claude/…` first, `$kitsrc/.claude/…` fallback), silent, fail-open — "update
  the repo, update the machine", as for the skill and the awake hooks.
- **Golden `ops/tests/machine-armed.cmd/.expected`** (T-143): `python kit/ops/pack.py --allow-dirty >/dev/null 2>&1`
  (the repo's own `build:`; the zip lands gitignored at the root), then, in a temp `$FIX`,
  `HOME="$FIX" USERPROFILE="$FIX" python polaris-v5.zip --claude-skill --no-permissions >/dev/null 2>&1`
  (the recipe CI already uses; Windows python resolves `~` from USERPROFILE, POSIX from HOME).
  Asserts, as lines: the four files exist under `$FIX/.claude/` (`skills/polaris-install/SKILL.md` ·
  `skills/polaris-install/polaris-v5.zip` · `output-styles/polaris.md` · `skills/i-have-adhd/SKILL.md`) ·
  `LICENSE` and `SOURCE.md` beside it · `disable-model-invocation: true` kept · `name: POLARIS` present ·
  NO `$FIX/.claude/settings.json` was created · a second run leaves every file byte-identical.
  `perm-tools` stays green (no new bare tool names); `arm_file` is a python def ⇒ api-kit row (T-140, W1).

## 4. INIT protocol (T-145, W3) — the interview becomes ONE call, generated from data
INIT.md § 2 is rewritten in place. Headings become (api-kit rows — T-145 owns them in W3):
- `### 2a. Interaction 1 — the preferences POLARIS asks for, in ONE call` — body: run
  `bash ops/polaris interview`; it prints QUESTION/OPTION lines for whatever is unanswered (on a
  fresh repo: voice · adhd · claim); ask ALL of them in ONE AskUserQuestion (≤ 4; a numbered list
  where the harness has no choice UI), the voice question FIRST; the voice answer binds from the
  next message on. Never ask a question the CLI did not print; never add one. INIT runs before
  CONVENTIONS exists, so at this point `interview` dies (§ 2) — INIT instead reads the questions
  straight off `ops/KEYS.tsv`'s `ask` column (the installer just copied it) and writes the answers
  in step 3. The hard cap stays 3 interactions, default 2.
- `### 2b. DERIVE — silently, from the survey you already did. Ask none of this.` — unchanged.
- `### 2c. Interactions 2 and 3 — the only things a repo cannot tell you` — heading unchanged; the
  body's question 2 (`claim:`) is REMOVED (it is now part of interaction 1); the rest unchanged.
- § 3: the CONVENTIONS skeleton gains, directly under `voice:`,
  `adhd: off                  # off | on — on lets the vendored /i-have-adhd skill fire in every session here; the output style already keeps replies short and warm`
  and its `voice:`/`claim:` lines carry the answers; after writing the skeleton and running
  `init-board`, INIT runs `bash ops/polaris interview --set voice=<a> --set adhd=<b> --set claim=<c>`
  — idempotent on the values it just wrote, and it is what applies the adhd side effect. (Then the
  scaffold line of test-surfaces.md v2 § 19.)
- § 5's report is unchanged; under `adhd: on` the report is already shaped by the skill.
The `polaris-install` skill's `§ After the install` is unchanged (INIT owns the interview).
`INIT.md` gets NO other heading change; `PLANNER.md`, `PROTOCOL.md` and the install skill get none.

## 5. `board_pull` — core.sh (T-148, W1): the read side of `claim: claim-branch`
`sync_board` pushes `refs/heads/polaris/board` after every mutation; nothing fetches it, so under
`claim-branch` a second machine's `status`, `next`, `board-fm` and `claim` read a board frozen at its
last clone. **`board_pull`** (≤ 45 lines; `sync_board` unchanged):
- Gate: `CLAIM_MODE = claim-branch` AND `has_remote`; otherwise rc 0 instantly, no fork (local-lock
  repos — this one — pay nothing). Throttle: at most one fetch per 60 s per primary (the mtime of
  `$PRIMARY/.polaris/board-pulled`, touched after every attempt); `POLARIS_BOARD_PULL=0` in the
  environment skips it for that call.
- `git -C "$PRIMARY" fetch -q origin "$BOARD_REF" 2>/dev/null` (failure ⇒ silent rc 0). Remote tip
  BY NAME: `git -C "$PRIMARY" ls-remote origin refs/heads/polaris/board | cut -f1` — never FETCH_HEAD
  (sync_board's lesson). Local tip == remote tip, or no remote tip ⇒ nothing. Local tip is an
  ANCESTOR of the remote tip (`git merge-base --is-ancestor`) ⇒ fast-forward: delete the moved-set
  files the LOCAL tip tracks (`git ls-tree -r --name-only <local>`, each unlinked under `$PRIMARY`),
  `update-ref "$BOARD_REF" <remote>`, then `read-tree` into a secondary index + `checkout-index -a -f --prefix="$PRIMARY/"`
  (board_materialize's plumbing over an existing dir; primary index and checked-out branch
  untouched), then `say "board pulled: <n> commit(s) from origin (claim-branch)"`. Diverged (neither
  is an ancestor) ⇒ `note "⚠ board diverged from origin — local board commits were never pushed; run: ops/polaris sweep"`,
  no write. No local ref at all ⇒ `board_materialize` already covers it; `board_pull` does nothing.
- Call sites, FIRST statement in: `cmd_status` and `cmd_board_fm` (observe.sh — these two lines are
  T-148's; observe.sh is otherwise T-142's in W2, which lands on top), `cmd_next` (handover.sh),
  `cmd_claim` (builder.sh, before the wsjf pick). NOT in the guard path, NOT in `_match|_rules`,
  NOT in `doctor` (which already materializes a missing board), NOT in any drill fixture that runs
  under `local-lock` (every existing one).
- **Drill** (`drill_remote`, remote.sh, T-148): with `claim: claim-branch` and the bare origin, clone
  the fixture to a second dir, `claim` a task there (pushes the ref), then in the first dir `status`
  shows the task under active/ and `.polaris/board-pulled` exists; `POLARIS_BOARD_PULL=0 status`
  after a further remote change still shows the stale column; a diverged local ref ⇒ the `⚠ board
  diverged` note and the local files untouched. rc + file state, never prose alone (T-089).
  Restore `claim: local-lock` and remove the clone before the next step.

## Executable check
- `bash kit/ops/polaris check --only interview` · `check --only machine-armed` (the goldens above).
- `bash kit/ops/polaris doctor --fast` — section `interview-pending` (T-144: `interview_pending` over
  fixture KEYS/CONV files, `OPS` and `CONV` overridden inside the section subshell, ≥ 4 asserts).
- `bash kit/ops/polaris doctor --selftest --only remote,adopt,surfaces` (wave gate / CI).

## Invariants
1. `update --auto` prints exactly its one pinned line — no interview, no nudge, ever.
2. A stub counts as answered; the interview never asks a question KEYS.tsv does not carry, and never
   more than the `ask` rows (≤ 4 by construction: three in 6.4.0).
3. `--set` is all-or-nothing, never runs on `feat/*`, and never touches the kit copy of any skill.
4. `arm_machine` never writes `outputStyle` into `~/.claude/settings.json`; the machine copy of
   i-have-adhd keeps `disable-model-invocation: true`.
5. `board_pull` is a no-op under `local-lock`, never fetches more than once per 60 s, and never
   rewrites a diverged board.
6. Bash ≥ 3.2 everywhere; no python in admin.sh's interview path; `cmd_adopt`'s stub format unchanged.

## Example
```
$ bash ops/polaris interview
QUESTION	voice	How should I talk to you?
OPTION	voice	standard	Plain and warm, with a 🎉 when work lands	default
OPTION	voice	technical	Technical and terse
QUESTION	adhd	Want replies shaped for ADHD — next action first, numbered steps, wins made visible?
OPTION	adhd	off	Not needed	default
OPTION	adhd	on	Yes, always
QUESTION	claim	Will you work on this project from one computer, or several?
OPTION	claim	local-lock	One computer	default
OPTION	claim	claim-branch	Several computers (the board follows a shared remote)
   3 preference(s) never set here — ask them in ONE round (never more than 4 questions), then: ops/polaris interview --set voice=standard --set adhd=off --set claim=local-lock
$ bash ops/polaris interview --set voice=standard --set adhd=on --set claim=local-lock
✅ set voice: standard · adhd: on · claim: local-lock
   review, then commit ops/CONVENTIONS.md — nothing was committed for you
$ bash ops/polaris doctor
   …
   preferences never set here: adhd · claim — one round of questions: ops/polaris interview
```

## Changelog
- v1 2026-09-14: created for T-141 · T-143 · T-144 · T-145 · T-148 (plans/v3.md § B1, B2, B4).
