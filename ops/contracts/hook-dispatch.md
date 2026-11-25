# CONTRACT: hook-dispatch — one hook process per tool call, the protocol at session start   (v1 — 2026-11-24, plan `one-kit`, 6.22.0 + 7.0.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Today a Bash call in a POLARIS repo starts four hook processes (readonly-allow, checkout-guard,
presence-guard, and the machine-level model-guard), and each hook is registered per repo. 7.0.0
registers ONE user-level dispatcher per event (written only by the owner's `--setup`,
shared-kit.md § 10) that folds the four pure-bash guards in-process and `exec`s the rest, stands down
outside POLARIS projects and in vendored ones, and injects the protocol at session start in joined
projects. **Guards fail open, so a dispatcher bug disables every guard at once** — the equivalence
golden on the fold card is the gate. Cards: T-343 (function forms, W1) · T-345 (dispatcher +
shim, W2) · T-346 (session context, W2) · T-350 (registration via `--setup`, W3). All `risk: high`
except T-346.

## 1. Function form (T-343: model-guard.sh, presence-guard.sh, checkout-guard.sh, readonly-allow.sh)
Each of the four scripts stays a standalone hook with byte-identical stdout, stderr, exit code and
side effects (every existing golden and drill unchanged), and also becomes SOURCEABLE:
- All top-level logic moves into one entry function: `_mg_hook` · `_pg_hook` · `_cg_hook` · `_ra_hook`.
  It reads the hook JSON from the variable `IN` (the caller has read stdin) and its argv as today's
  `$@` (`--test …` included). It never prints, never `exit`s, never `read`s stdin; it sets:
  `HOUT` (the exact stdout bytes) · `HERR` (the exact stderr bytes) · `HRC` (the exit code).
- Standalone face, at the end of each file:
  `case "${BASH_SOURCE[0]}" in "$0") IN=''; IFS= read -r -d '' IN 2>/dev/null; <fn> "$@"; printf '%s' "$HOUT"; [ -z "$HERR" ] || printf '%s' "$HERR" >&2; exit "$HRC";; esac`
  (a `--test` path that never read stdin keeps not reading it).
- Name hygiene: when the four are sourced into one shell, no function or top-level variable may
  collide. model-guard (`mg_`/`MG_`) and presence-guard (`pg_`/`PG_`) already comply — nothing public is
  renamed there. checkout-guard's `deny jstr mutating_git mutating_other` become `cg_deny
  cg_jstr cg_mutating_git cg_mutating_other`, readonly-allow's unprefixed helpers (`jstr find_ok sed_ok
  awk_ok git_ok polaris_ok xargs_ok verb_ok check_segment scan ps_lc` and any other) → `ra_<name>`, and
  their top-level globals (`HIT` …) → `CG_`/`RA_`. Shared on purpose: `IN`, `HOUT`, `HERR`, `HRC`.
  T-343 is the W1 owner of `ops/tests/api-kit.expected` for exactly these renames (one card owns all
  four guards: the SURFACES `ops/tests/<x>.*` globs `new` adds would chain two guard cards anyway).
- `set -e`/`-u` behaviour: a sourced entry function must be safe under the caller's `set -u`; it
  restores any shell option it changes.

## 2. The dispatcher — `kit/ops/hooks/dispatch.sh <event>` (T-345, new)
bash 3.2. Reads stdin ONCE into `IN`, then:
1. **Model ban + effort bookkeeping** (`_mg_hook`), on every event model-guard handles today
   (PreToolUse `*`, PostToolUse `Agent`, SessionStart, PreModelSwitch, PostModelSwitch). A deny →
   emit its `HOUT`/`HERR`/`HRC` and stop.
2. **Project test** (builtins only): POLARIS project = cwd matches `*/.polaris/wt/*`, or walking up
   from `CLAUDE_PROJECT_DIR` (else cwd) finds `ops/polaris`. `ops/lib/` present beside it ⇒
   VENDORED ⇒ the repo's own project hooks do the rest: **stand down** (emit step 1's output, if any).
   Not a POLARIS project → stand down (SessionStart still runs § 6's zero-touch line).
3. Machine project, by event:
   - PreToolUse `Edit|Write|MultiEdit|NotebookEdit` → `exec bash "<kit>/ops/hooks/ownership-guard.sh" <<<"$IN"`.
   - PreToolUse `Bash|PowerShell|AskUserQuestion` → in order, in-process: presence (`_pg_hook`) →
     checkout deny (`_cg_hook`, Bash|PowerShell) → genuine-launcher check (§ 5) → read-only allow
     (`_ra_hook` from the TRUST TIER, § 4). First deny wins; else an `ask`; else an allow; else
     nothing. Emitted: the winning guard's `HOUT` verbatim (one JSON object) — the same verdict Claude
     Code reaches today from the separate hooks (deny > ask > allow).
   - PostToolUse `ExitPlanMode` → `_pg_hook`. UserPromptSubmit → `handover-hook.sh prompt` then
     `_pg_hook` (outputs concatenated in that order, as two hooks print today).
   - Stop / SubagentStop / StopFailure → `exec … handover-hook.sh stop|substop|stopfail`.
   - PermissionRequest / PermissionDenied → `exec … permission-hook.sh request|denied`.
   - SessionStart → § 6.
4. `<kit>` = the directory dispatch.sh lives in (`${BASH_SOURCE[0]%/*}/../..`) — the versioned store copy.
5. Fail open: any internal error → exit 0 with no output (today's guard behaviour), EXCEPT a model
   deny already decided.
6. `--as <guard> [args…]` (tests only): behave exactly as `<guard>.sh [args…]` standalone, through
   the dispatcher's own sourcing and project test — the hook-dispatch replay uses it.

## 3. Registration (written ONLY by `--setup`, T-350)
`~/.claude/settings.json` gains one entry per event, command `bash "<POLARIS_HOME>/hook" <event>`:
PreToolUse matcher `*` · PostToolUse `Agent|ExitPlanMode` · SessionStart (no matcher) ·
PreModelSwitch · PostModelSwitch · UserPromptSubmit · Stop · SubagentStop · StopFailure ·
PermissionRequest · PermissionDenied. The user-level model-guard entries it folds are removed by
script identity; keep-awake's entries and every non-POLARIS entry are untouched. Timeouts: the
largest of today's per-event timeouts (PreToolUse 20, SessionStart 120, Stop 30, others 10).

## 4. Shim and trust tier (T-345 writes the files' source; T-350's `--setup` copies them)
- `kit/ops/hooks/shim.sh` → copied to `$POLARIS_HOME/hook`. ≤ 30 lines, zero forks: builtin `read`
  of `$POLARIS_HOME/kit/current` (token-validated, shared-kit § 1); no valid store → exit 0 silently;
  else `DP_TRUST="$POLARIS_HOME/trust/readonly-allow.sh"` and
  `. "$POLARIS_HOME/kit/<v>/ops/hooks/dispatch.sh" "$@"`.
- Trust tier = `$POLARIS_HOME/trust/readonly-allow.sh`, a copy of the kit's `readonly-allow.sh`
  made by `--setup` and by nothing else. dispatch.sh sources `_ra_hook` from `DP_TRUST` when that
  file exists, else from its own kit (a test fixture without a shim). So an auto-update changes
  denies and context, never what is auto-approved.
- "Trust tier differs" (shared-kit § 5 step 5) = the trust copy is not byte-equal to the new kit's
  `ops/hooks/readonly-allow.sh`.

## 5. Genuine launcher (T-345)
In a MACHINE project, a Bash/PowerShell command that `_ra_hook` would allow because it runs
`ops/polaris` (its `ra_polaris_ok` path) is answered `ask` instead when `<root>/ops/polaris` is not
byte-equal to `<kit>/ops/launcher` (compared with builtin reads, no fork), reason:
`ops/polaris in this project is not the POLARIS launcher — approve this run yourself`.
(A cloned repo cannot ride the pre-approved `Bash(bash ops/polaris:*)` rule.) Vendored projects are
the repo's own hooks' business (step 2), unchanged.

## 6. Session context (T-346 — `kit/ops/hooks/dispatch-session.sh`, new, sourced by dispatch.sh; `_ds_session`)
SessionStart, every source (startup | resume | clear | compact):
- **Machine project:** ONE JSON object, `hookSpecificOutput.additionalContext` = in order:
  (a) `bash "<kit>/ops/polaris" router` (the trimmed kit/CLAUDE.md, ≤ 8,000 bytes — T-346 trims it);
  (b) the voice block: `voice: <value> (<repo|machine|default>) — <rule>` where value = the repo's
  `voice:` line, else the machine preferences file's (`POLARIS_PREFS` seam), else `standard`; rule:
  standard → `everyday words, no git or test vocabulary; ✅ lines while working, 🎉 only after finish exits 0` ·
  technical → `terse and dense`;
  (c) when `adhd` resolves `on` (same precedence): `adhd: on — shape every reply for a reader with ADHD (the /i-have-adhd skill has the rules). The five facts:`
  followed by the five numbered "facts" lines of `kit/.claude/skills/i-have-adhd/SKILL.md` verbatim;
  (d) startup only: then step 1's model-guard SessionStart text, then `update-hook.sh`'s output;
  compact|resume: then `handover-hook.sh anchor`'s text. Total ≤ 9,000 bytes for (a)-(c) (golden).
- **Git repo without POLARIS:** the zero-touch line (shared-kit § 9), and nothing else.
- **Vendored / elsewhere:** nothing beyond step 1.
- No SubagentStart hook. The CLAUDE.md pointer block (shared-kit § 8) is the fallback.

## 7. Executable checks
- `ops/tests/hook-dispatch.{cmd,expected}` (T-345) — (a) REPLAY: each battery `readonly-allow`,
  `checkout-guard-denies`, `presence-guard`, `model-guard-v2`, `ownership-primary`, `permission-hook`,
  `handover-stop` is run from a temp copy of its `.cmd` in which every invocation of
  `kit/ops/hooks/<guard>.sh` becomes `kit/ops/hooks/dispatch.sh --as <guard>`, inside a machine-project
  fixture (launcher, no `ops/lib/`); its output must equal the battery's `.expected` → prints
  `<battery>: identical`. (b) MERGE: a matrix through the full dispatcher (presence deny + read-only
  allow · checkout deny + allow · model deny + allow · not-genuine launcher + allow → ask · nothing →
  no output) equals the deny > ask > allow composition of the four standalone scripts. (c) STAND-DOWN:
  vendored fixture and non-POLARIS dir → only model-guard's verdict. (d) name hygiene: sourcing the
  four guards defines no duplicate function (`declare -F | uniq -d` empty).
- `ops/tests/hook-budget.{cmd,expected}` (T-345) — with `PATH` set to an empty directory, the
  dispatcher gives the same verdict as with the real PATH for: a non-POLARIS dir (Read, Bash), a vendored
  dir (Bash), a machine project with a `Read`/`Grep` tool call — proving no external command; and the
  shim + dispatch.sh lines on that path contain no `$(`, backtick or `|` (a scoped grep). One harness
  process per Bash call is the registration in § 3.
- `ops/tests/session-context.{cmd,expected}` (T-346) — machine-project fixture: the three blocks,
  voice from repo / machine / default, adhd on/off, total bytes ≤ 9,000 printed as `≤ 9000: yes`;
  `router | wc -c` ≤ 8,000; the zero-touch line for ask / auto / off / `never` / linked worktree /
  `upstream` remote; vendored fixture → no context.

## Invariants
- Vendored repos: project hooks unchanged; the dispatcher adds nothing but today's user-level model-guard verdict.
- Every existing hook golden and drill byte-identical (T-343/T-343 change no output).
- Tests: fake `HOME` / `CLAUDE_CONFIG_DIR`, `POLARIS_PREFS=`, explicit `CLAUDECODE`, `PYTHONIOENCODING=utf-8`.

## Changelog
- v1 2026-11-24: created for plan `one-kit` (T-343, T-343, T-345, T-346, T-350).
