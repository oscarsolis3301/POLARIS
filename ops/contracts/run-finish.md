# CONTRACT: run-finish              (v1 — 2026-07-26)
Owned by the CLI. Roles code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Answers one question mechanically: **is the RUN over?** Not "did this task pass", not "is the suite
green" — is there anything left in flight for the human's request.

The definition already existed as prose at `ops/roles/CONDUCTOR.md` § "The second rule": every planned
task in `done/` or in `blocked/` with the human told · `ready/` drained per `drain:` · `qa` green on
base · EVOLVE's proposals gathered · the close report delivered. Locked in one role file, it could not
be reached by SOLO, by the INTEGRATOR, or by any lane that ends a run without a conductor. This
command makes the mechanizable part of it executable, so every lane inherits the same bar.

It also fixes an under-firing: before this, `notify-gate done` fired only from a pr-mode seal
(`kit/ops/lib/integrate.sh`). Direct-mode seal, `land --express` and SOLO never fired it, so the
"run finished" hook was silent on the most common paths. Every lane now ends at `finish`, which fires
it.

**Why the exit code and not a message.** The visible half of this feature is a markdown H1 —
`# 🎉 Complete!` — in the agent's closing reply. It must be the agent's prose because terminals do not
render markdown: the identical bytes from a command's stdout are flat text. But an agent deciding for
itself that it feels finished is exactly the self-attestation POLARIS exists to replace. So the two
halves are split: the command owns the *verdict*, the reply owns the *signal*, and the exit code is
the only bridge.

## Interface — CLI (`cmd_finish`, in `kit/ops/lib/observe.sh`)
```
polaris finish [--force]      # --force forwards to `qa --force` (re-run the suite, ignore the stamp)
```
Two phases. Phase A is free and never short-circuits — every finding is accumulated, the same reason
`cmd_qa` and `cmd_drift` run every check after a red. Phase B runs only when Phase A found nothing: a
suite run while a lane is still building proves nothing about the finished state.

**Phase 0 — refusal (rc 1, before any check)**

| check | verdict |
|---|---|
| primary checkout (`in_primary`) | `die` — a `.polaris/wt/<ID>` worktree can never end a run |

**Phase A — board + git**

| # | check | verdict |
|---|---|---|
| A1 | HEAD is on `<base>` | pending |
| A2 | `git status --porcelain` empty | pending |
| A3 | `active/` empty | pending, names ≤5 IDs |
| A4 | `review/` empty | pending, names ≤5 IDs |
| A5 | `ready/` empty | `drain: queue`/`backlog` → pending · `drain: plan` → **caveat** |
| A6 | every `integrate/*` is an ancestor of `<base>` | not an ancestor → pending · merged-but-undeleted → caveat |
| A7 | no lock whose task is absent from `active/`+`review/` | pending |
| A8 | board mutex not held | pending |
| A9 | `blocked/` count | **caveat, never a gate** |
| A10 | no `.polaris/wt/<ID>` without an `active`/`review` task | caveat |
| A11 | `<base>` pushed (local ref read — **never a fetch**) | caveat |

**Phase B — `qa`**, in a subshell (`cmd_qa` dies on red), red → pending + the last 6 lines.

`finish` **RUNS** `qa` rather than requiring it: "requiring" means trusting an agent's memory that it
ran, which is the claim this command replaces. It is nearly free — `cmd_qa`'s suite stamp
(`.polaris/suite-stamp`) skips the suite when HEAD has not moved and the tree is clean, and `drift` +
`doctor` are seconds.

**Not checked, deliberately:** EVOLVE's proposals and the close report are not mechanizable. The role
protocols put `finish` AFTER both.

## Interface — exit codes
```
0   the run is COMPLETE
1   something is pending (or a Phase 0 refusal)
```
Nothing else, for four reasons: several things are routinely pending at once and a code-per-reason
forces an arbitrary winner; `die` is the kit's only failure primitive and is hard-wired to `exit 1`;
the reason belongs in stdout, where it is greppable and survives a new check being added; and the
consumer is a language model choosing between two closing messages, for which one bit is far harder
to misread than five codes.

## Interface — frozen stdout tokens
Role prose branches on the exit code; `drill_finish` greps these. Renaming any of them is a v2.

| token | stream | meaning |
|---|---|---|
| `finish: run complete` | stdout (`say`) | rc 0 |
| `done signal fired` | stdout (`say`, same line) | the hook fired on this invocation |
| `done signal already fired` | stdout (`say`, same line) | fire-once suppressed it |
| `⛔ pending: ` | stdout, one line each | one blocking item, named |
| `caveat: ` | stdout (`note`), one line each | must be named in the closing message |
| `board clear — ` | stdout (`say`) | the rc 0 board summary |
| `finish: not done` | **stderr** (`die`) | rc 1 |

## Interface — `.polaris/finish-stamp`
```
<sha> <epoch>        # one line, byte-shape identical to .polaris/suite-stamp
```
`<sha>` is the `<base>` tip at the moment the run was declared complete. Gitignored, best-effort
write (`|| true` throughout — `finish` can never fail the close).

**Why a stamp and not board state.** `notify-gate` is observe-only by contract
(`ops/contracts/hands-free-knobs.md` § notify v2: it may not call `evt()`, append `EVENTS.ndjson`,
take the board mutex, move or edit a board file, or commit). The board therefore carries no record
that the signal fired and cannot be made to without breaking that contract and taking the mutex at
the exact moment the run is trying to end. Deriving is not merely worse — it is prohibited.

**Why keyed on the base tip sha.** Self-clearing with zero cleanup code: the next run lands a commit,
the stamp goes stale, the signal fires again. No expiry, no `--reset`, no session id to plumb through.
It is per-checkout (a second machine finishing the same wave signals again — its `.polaris/` is its
own) and per-finished-state, not per-request. Both are accepted: the signal exists for the human at
that machine, and a second request that lands nothing produced no new finished state.

## Closing-message shape
- **rc 0** → the agent's reply opens with `# 🎉 Complete!`, verbatim, first, alone on its line. Then
  the report, carrying every `caveat:` line. rc 0 means "the run is over", never "nothing was left
  behind".
- **rc 1** → no H1, no `🎉`. Two or three warm sentences per `ops/PROTOCOL.md` § VOICE OUTPUT
  DISCIPLINE: what landed, the ONE pending thing, one next command. A pending run is an ordinary
  state of affairs, not an apology.
- **A subagent never emits the H1, under any exit code.** Nobody reads its reply but the conductor.
  Three layers enforce this: Phase 0 + A1 + A3/A4 make rc 0 mechanically unreachable for a builder or
  a mid-wave integrator; `kit/CLAUDE.md` § PROGRESS FORMAT carries the rule to every subagent (it is
  the only context they all share, which is why those two lines earn their place in the 6-8× file);
  and `BUILDER.md` / `INTEGRATOR.md` state it in role prose.

## Executable check
- `bash ops/polaris doctor --selftest --only finish` → `drill_finish`
  (`kit/ops/lib/selftest/policy.sh`, gated after `drill_qa` in `spine.sh`). Asserts: listed in help ·
  a `review/` occupant is named, rc 1, and does NOT stamp or fire · `drain: queue` gates on `ready/`
  while `drain: plan` demotes the same board to a caveat · a worktree invocation refuses · a clean
  board is rc 0 with the verdict token and a well-formed stamp · the hook fires EXACTLY once per
  finished state and a re-run stays rc 0 with the stamp unmoved.
- `ops/tests/cli-help-parity` — `finish` is a daily command and must appear in `help`
  (`ops/contracts/cli-docs-parity.md`).
- No golden pair: a `finish` golden would run against the live board and invoke `qa` — the flappy and
  huge classes `check --scaffold` already refuses. The hermetic scratch repo is the right tier for a
  stateful verdict command.

## Invariants
1. `finish` never writes the board, never takes the mutex, never commits. Its only write is
   `.polaris/finish-stamp`.
2. The verdict is recomputed on EVERY invocation. Only `notify_fire` is memoised — which is what lets
   an agent re-run `finish` freely while chasing pendings without muting the signal or reading a
   stale answer.
3. `blocked/` is never a gate. `caveat:` lines are never gates, and the closing message must name
   every one of them.
4. A11 reads `refs/remotes/origin/<base>` only. `finish` never fetches.
5. The `# 🎉 Complete!` H1 is emitted by an agent's reply on rc 0 and by nothing else. **No command
   ever prints it** — stdout does not render markdown, which is the entire reason the two halves are
   split.
6. `land --express` and `seal` POINT at `finish` in a `note`; they never call it. A wave is not a run
   (a sprint may seal several times), both run under `set -eu` so a rc 1 would abort a *successful*
   seal, and auto-calling would put the full suite between `git merge --no-ff` and `git push`.
7. Known wart, retained: `cmd_notify_gate done` at the pr-mode seal fires `SEVERITY=done` while the
   run is still waiting on a human to merge the PR — by `hands-free-knobs.md` that state is
   `waiting`/`gate`. `finish` is now the authority and that call is redundant-but-harmless. Retiring
   it means editing `drill_pr-publish` and the spine summary; out of scope for v1.
