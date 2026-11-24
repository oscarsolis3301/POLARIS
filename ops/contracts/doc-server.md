# CONTRACT: doc-server — the CLI finds its own code and serves its own documents   (v1 — 2026-11-24, plan `prefs`, 6.21.0)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Groundwork for one shared kit per computer (Phase 4, `one-kit`, 7.0.0) with NO change for today's
vendored installs: the CLI locates its code from its own path, reads kit files through one lookup,
finds the machine home through one variable, and serves role files and kit documents as commands, so
prose can say `bash ops/polaris role BUILDER` instead of a path that will not exist in a repo once the
kit lives outside it. Cards: T-333 (core helpers, W1) · T-334 (hooks, W1) · T-335 (prose, W1) ·
T-336 (printed strings, W1) · T-337 (CLI + docs.sh + kit/CLAUDE.md, W2) · T-338 (admin + installer, W2) ·
T-339 (lib readers, W2) · T-340 (doc-refs, kit-mode drill, release, W3).

## 1. The entry script (kit/ops/polaris — T-337 is its ONLY owner this plan)
- Line 8 becomes, verbatim:
  `case "${BASH_SOURCE[0]}" in "$0") OPS_DIR="$(cd "$(dirname "$0")" && pwd)";; *) OPS_DIR="${BASH_SOURCE[0]%/*}";; esac`
- `SELF="$OPS_DIR/${BASH_SOURCE[0]##*/}"`.
- `VER` without a fork: `VER="$OPS/VERSION"; [ -f "$VER" ] || VER="$OPS_DIR/VERSION"` (same answer as
  `kit_file VERSION`; a `$(…)` in the globals block would cost a fork on every start).
- Loader rows (literal lists, module-layout v11): `role|doc|router) _mods="core docs"` ·
  `prefs) _mods="core ownership prefs"` · `doctor` = today's full list + `docs prefs` before the
  selftest modules · every other command: today's list, unchanged (docs/prefs are need-scoped).
- Dispatch, no `update_check_maybe` on any of them (read-only and hot, like `route`):
  `role) shift; cmd_role "$@";;` · `doc) shift; cmd_doc "$@";;` · `router) shift; cmd_router "$@";;` ·
  `prefs) shift; cmd_prefs "$@";;`
- `usage` gains one entry per verb (cli-help re-pin is the conductor's release ritual, not a card's).
- `kit_mode` (docs.sh, lazy — never in the globals block): prints `vendored` when
  `$(cd "$OPS" 2>/dev/null && pwd -P)` equals `$(cd "$OPS_DIR" && pwd -P)`, else `machine`. Nothing
  in 6.21.0 branches on it; `doc --where` prints it and the kit-mode drill asserts it.

## 2. Kit files through one lookup — `kit_file <rel>` (core.sh, T-333; spec machine-prefs.md § 6)
Every read of a KIT file through the repo state dir (`$OPS/VERSION`, `$OPS/KEYS.tsv`,
`$OPS/roles/…`, `$OPS/PROTOCOL.md`, `$OPS/templates/…`, `$OPS/index.py`, `$OPS/hooks/…`,
`$OPS/dashboard.py`, `$OPS/install.sh`, `$PRIMARY/ops/…` in hooks) becomes `kit_file <rel>` (lib) or
the inline hook form `[ -e "$P/ops/<rel>" ] && f="$P/ops/<rel>" || f="${BASH_SOURCE[0]%/*}/../<rel>"`.
STATE files stay on `$OPS` (board, CONVENTIONS, MAP, contracts, RULES, SURFACES, SPRINT, tests).
Sites (6.19.0 line numbers — re-find them): polaris:425 (VER, § 1) · admin.sh 66-67, 685, 919,
1001-1023, 1324, 1353, 1505-1506, 1541, 1563, 1586, 1743, 1762, 1907 (T-338) · observe.sh 513, 529,
668-677, 710-716, 727-759, 977 · search.sh 32, 36 · awake.sh 12, 44, 119 (T-339) ·
hooks/ownership-guard.sh 220, 229, 314-315, 369 · hooks/update-hook.sh 81, 86, 96 (T-334).
In a vendored repo `$OPS/<rel>` exists, so every answer is byte-identical to today.

## 3. One machine home — `POLARIS_HOME` (core.sh variable, T-333)
`POLARIS_HOME="${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/polaris"`. Every `$HOME/.claude/polaris`
literal in kit code becomes `$POLARIS_HOME` (lib) or the inline expansion (hooks, install.sh):
admin.sh 260, 2059 (T-338) · install.sh 128, 576 (T-338) · awake.sh 12-14, 43-46, 118-120 ·
observe.sh 773 · presence.sh 15 · route.sh 249 · workspace.sh 344 (T-339) · handover-hook 171 ·
awake-hook 65-69, 318 · model-guard 82, 144 · permission-hook 91 · presence-guard 59 (T-334).
Explicit overrides keep precedence (`POLARIS_AWAKE_HOME`, `POLARIS_HEAVY_DIR`). With
`CLAUDE_CONFIG_DIR` unset every path is byte-identical to today. `claude_home()` (admin.sh) stays.
Comments and `bench.sh` may keep the literal.

## 4. The verbs (new `kit/ops/lib/docs.sh`, T-337; api-kit rows `cmd_role`, `cmd_doc`, `cmd_router`, `kit_mode`)
`PAGE_MAX = 28000` bytes (the harness inlines ~30,000 characters; CONDUCTOR.md is ~37k).
- `role <NAME> [--page <n>]` — NAME case-insensitive, served as `kit_file roles/<NAME-uppercased>.md`.
  Unknown → `⛔ role: no role <NAME> — roles: BUILDER · CONDUCTOR · …` (the roles dir, sorted), rc 1.
- `doc <NAME> ["<section>"] [--page <n>]` — NAME `PROTOCOL` · `MANUAL` · `PROMPTS` · `VISUAL` ·
  `KEYS` (→ `KEYS.tsv`) · `templates/<T>` · `roles/<R>`; a NAME without an extension gets `.md`; `..`
  or a leading `/` is refused. Unknown → `⛔ doc: no kit document <NAME> — documents: MANUAL · PROMPTS · PROTOCOL · VISUAL · KEYS · templates/<T> …`, rc 1.
  With `<section>`: the first heading (`#`–`######` + space, OUTSIDE fenced code blocks) whose text
  contains `<section>` case-insensitively, through the line before the next heading of the same or
  higher level outside fences; printed whole, never paged. No match →
  `⛔ doc: no section "<section>" in <file> — whole file: bash ops/polaris doc <NAME>`, rc 1.
- `doc --where` — two lines: `kit: <OPS_DIR>` · `mode: <kit_mode>`.
- `router` — the kit's protocol text: source `$OPS_DIR/../CLAUDE.md`; when it carries the
  `<!-- POLARIS:BEGIN` / `<!-- POLARIS:END -->` markers, only the lines strictly between them, else
  the whole file. Missing → `⛔ router: no CLAUDE.md beside this kit (<path>)`, rc 1.
- Paging (role, doc without section, router): size ≤ PAGE_MAX → the file byte-identical, no footer.
  Larger → pages cut only at lines starting `## ` (outside fences): greedy, each page ≤ PAGE_MAX
  unless one section alone is larger (then that section is a page, unsplit); the text before the
  first `## ` belongs to page 1. After each page one footer line:
  `— page <i> of <n> · next: bash ops/polaris <verb> <NAME> --page <i+1>` (`router` has no NAME), and on
  the last page `— page <n> of <n> (end)`. `--page` out of range → `⛔ <verb>: <NAME> has <n> page(s)`, rc 1.
- All read-only: no board write, no network, no git call beyond the globals block. Both layouts:
  a repo copy wins (`kit_file`), else the kit's own.
- `kit/ops/hooks/readonly-allow.sh` `polaris_ok` (T-334) approves `role …`, `doc …`, `router` and a
  bare `prefs` — never `prefs --set|--unset|--seed|--yield`.

## 5. Prose — every kit doc path becomes the command form (T-335 · T-337 kit/CLAUDE.md · INIT.md with first-run v2 § B)
Pattern (golden `doc-refs`): `ops/(roles/|PROTOCOL\.md|MANUAL\.md|PROMPTS\.md|VISUAL\.md|templates/)`.
Files: `kit/CLAUDE.md` (T-337) · `kit/ops/roles/*.md` (T-335, INIT.md included) ·
`kit/ops/{PROTOCOL,MANUAL,PROMPTS,VISUAL}.md` · `kit/ops/templates/*.md` ·
`kit/.claude/skills/polaris/SKILL.md` · `kit/.claude/output-styles/polaris.md` (T-335) ·
`kit/ops/KEYS.tsv` (T-333 — keeps none). `kit/.claude/skills/polaris-install/` is installer prose
about the vendored files and is OUT of scope.
Rules: `ops/roles/<R>.md` → `bash ops/polaris role <R>`, and the verb before it "read/open" → "run" ·
`ops/<DOC>.md § <S>` → `bash ops/polaris doc <DOC> "<S>"` · bare `ops/<DOC>.md` →
`bash ops/polaris doc <DOC>` · `ops/templates/<T>.md` → `bash ops/polaris doc templates/<T>` (a
copy-it instruction becomes `bash ops/polaris doc templates/<T> > <dest>`) · inside `MANUAL.md`
(read by an agent that cannot run the CLI) a reference names the bare file in the kit instead:
`` `PROTOCOL.md` in the POLARIS kit `` · kit/CLAUDE.md's no-shell line becomes, verbatim:
`(Cannot execute commands? Read the kit's MANUAL.md — beside ops/polaris — and follow it literally.)`
**Headings stay byte-identical** (index.py reads them, and lines starting `# ` inside fenced blocks,
as api-kit rows) — except kit/CLAUDE.md's `## READ THIS WHEN YOU NEED IT — `ops/PROTOCOL.md``, which
T-337 (W2 api-kit owner) rewrites to `## READ THIS WHEN YOU NEED IT — `bash ops/polaris doc PROTOCOL``.
Prose growth stays under drift's doc-overflow limits (run `drift`).

## 6. Printed strings — pinned renderings (each re-pins its own goldens)
| site | today | becomes | owner · goldens |
|---|---|---|---|
| handover.sh ~:445 | `read ops/roles/TIDY.md — one context, it lands at most one task; then bash ops/polaris next` | `run bash ops/polaris role TIDY — one context, it lands at most one task; then bash ops/polaris next` | T-336 · handover-route, tune-hop, hops-due |
| route.sh ~:105 | `read ops/roles/TIDY.md — one context, no subagents` | `run bash ops/polaris role TIDY — one context, no subagents` | T-336 · triage-lane, tune-hop, hops-due |
| handover.sh ~:561 | `read ops/roles/%s.md if this context lost it` | `run bash ops/polaris role %s if this context lost it` | T-336 |
| index.py ~:2381 | `· ops/roles/TIDY.md runs the pass` | `· bash ops/polaris role TIDY runs the pass` | T-336 · hops-map |
| drift.sh ~:529 | `(ops/roles/PLANNER.md step 5b)` | `(bash ops/polaris role PLANNER, step 5b)` | T-336 · surfaces-scaffold |
| ownership.sh ~:88 | `See ops/roles/PLANNER.md "NEVER put…` | `See bash ops/polaris role PLANNER, "NEVER put…` | T-336 |
| builder.sh ~:483 | `(ops/MANUAL.md …` | `(bash ops/polaris doc MANUAL …` | T-336 · seal-fallback |
| tune.sh ~:208 | `fix: the layout pass — read ops/roles/TIDY.md` | `fix: the layout pass — run bash ops/polaris role TIDY` | T-339 · tune-report |
| admin.sh ~:1163 + install.sh ~:665 | `▶ NEXT — tune-up (%s): read ops/roles/TIDY.md and run it now` | `▶ NEXT — tune-up (%s): run bash ops/polaris role TIDY and follow it now` | T-338 · install-update, selftest/fast.sh asserts |
| admin.sh ~:1358 | `…; read ops/roles/INIT.md first` | `…; run bash ops/polaris role INIT first` | T-338 · adopt-stub |
| admin.sh ~:1618 | `(ops/roles/INIT.md)` | `(bash ops/polaris role INIT)` | T-338 · interview |
| admin.sh ~:956 | `Read ops/roles/INIT.md and execute it now` | `Run bash ops/polaris role INIT and execute it now` | T-338 |
| handover-hook.sh ~:349 | `You are TIDY (hop $n): read ops/roles/TIDY.md and run it now` | `You are TIDY (hop $n): run bash ops/polaris role TIDY and follow it now` | T-334 · handover-stop |
| polaris usage ~:190, ~:260 | `ops/roles/TIDY.md runs the pass…` · `(ops/roles/TIDY.md)` | `bash ops/polaris role TIDY runs the pass…` · `(bash ops/polaris role TIDY)` | T-337 · cli-help (conductor) |
KEPT, verbatim: install.sh's `read ops/roles/INIT.md` epilogue (ci.yml:331 and
selftest-install.sh:184/293 grep it). Comments may keep paths.

## Executable checks
- `ops/tests/doc-server.{cmd,expected}` (T-337): role whole (small file byte-identical) · role paged
  (CONDUCTOR-sized fixture: footers, `--page 2`, out of range) · doc section hit / miss / heading in a
  fence ignored · doc unknown · router with and without markers · vendored copy wins over the kit's ·
  kit-only file served when the repo has none.
- `ops/tests/kit-mode.{cmd,expected}` (T-340, joined tree): a fixture repo whose `ops/` holds only
  STATE (board, CONVENTIONS — no `lib/`, no `polaris`, no `roles/`, no `VERSION`), the CLI run as
  `bash <kit>/ops/polaris` from inside it: `version`, `status`, `role BUILDER`, `doc PROTOCOL "THE TOOL"`,
  `router`, `prefs`, `interview --init`, `doc --where` (`mode: machine`) all succeed; the same from a vendored copy says
  `mode: vendored`.
- `ops/tests/doc-refs.{cmd,expected}` (T-340): the § 5 pattern over the § 5 files prints nothing and
  `doc-refs: 0`; the printed-string sweep over `kit/ops/polaris kit/ops/lib/*.sh kit/ops/hooks/*.sh
  kit/ops/index.py kit/ops/install.sh` (non-comment lines, selftest excluded) finds only install.sh's
  kept epilogue.

## Invariants
- Vendored install: every existing golden byte-identical except the § 6 re-pins and the cli-help
  re-pin; no new fork on startup (startup-budget unchanged).
- One owner of `kit/ops/polaris` in this plan (T-337). `ops/tests/api-kit.expected` and
  `kit/ops/KEYS.tsv` have one owner per wave (key-registry.md § 10).

## Changelog
- v1 2026-11-24: created for plan `prefs` (T-333 … T-340).

## § 6 addendum — v1.1 (2026-11-24, T-340, conductor decision: render with § 5's rules)
The joined-tree sweep (`doc-refs`) found eight printed kit doc paths § 6 did not list. Pinned renderings:
| site | today | becomes | goldens |
|---|---|---|---|
| builder.sh ~:921 | `add the empty field from ops/templates/TASK.md first` | `add the empty field from bash ops/polaris doc templates/TASK first` | — |
| route.sh ~:381 | `… lint and typecheck are the whole check — ops/VISUAL.md` | `… — bash ops/polaris doc VISUAL` | depth-ui, express-ui, qa-parallel |
| visual.sh ~:113 | `SEE YOUR WORK — capture before handoff (ops/VISUAL.md)` | `… (bash ops/polaris doc VISUAL)` | shots-gallery |
| visual.sh ~:119 | `(visual: unset — no capture step; ops/VISUAL.md explains how to add one)` | `…; bash ops/polaris doc VISUAL explains how to add one)` | pack-visual, shots-gallery |
| visual.sh ~:164 | `shot: (unset — set shot: in ops/CONVENTIONS.md; ops/VISUAL.md)` | `…; bash ops/polaris doc VISUAL)` | — |
| visual.sh ~:170 | `read: ops/VISUAL.md` | `read: bash ops/polaris doc VISUAL` | pack-visual, shots-gallery |
| handover-hook.sh ~:350 | `Read ops/roles/BUILDER.md if this context no longer has it` | `Run bash ops/polaris role BUILDER if this context no longer has it` | — |
| handover-hook.sh ~:354 | `Read ops/roles/INTEGRATOR.md if this context no longer has it` | `Run bash ops/polaris role INTEGRATOR if this context no longer has it` | — |
`ops/CONVENTIONS.md` mentions stay (repo state, not a kit file). Also: `lib/presence.sh` resolves the
machine home as `${POLARIS_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/polaris}`, so it works sourced
alone under `set -eu` (presence-guard), byte-identical whenever core.sh has set `POLARIS_HOME`.
