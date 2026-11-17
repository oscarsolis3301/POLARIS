# CONTRACT: the tune-up — every install ends faster than it started   (v1 — 2026-11-17)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/tune.md` (the owner's three asks of 2026-11-17, approved; owner away). Kit release: 6.18.0.
Slug: `tune`. Two cards, ONE wave, side by side: **T-308** (the new commands) and **T-309** (the hop).

## Purpose
Separate what a project is TOLD (T-308: `tune`, `fold`, `note`, their words, the release) from WHEN and
WHERE it is told (T-309: `next` / `triage` / `update` / install / heal / done / seal, the hold rule that
keeps a layout pass off waiting cards' files, and the `find --api` fix). The seam between them is ONE
file, `.polaris/tune-due` (§ 2), plus the command names in § 1 — T-309 never calls code T-308 writes
except through `"$SELF" tune`, which is a silent no-op until T-308 lands.

## § 0 Cross-card rules (both cards)
- **One owner per shared file, this wave.** `kit/ops/polaris` (loader, dispatch, help) and
  `ops/tests/api-kit.expected` belong to **T-308 alone**. T-309 adds NO public name anywhere under
  `kit/`: no new column-0 shell fn without a leading `_`, no new python def/class without `_`, no new
  module-level CAPS constant in index.py, no new markdown heading (any line starting with 1–4 `#`) in
  any kit `.md`, no KEYS row. T-309 still runs `api-kit` in its verify line to prove it.
- `kit/ops/lib/handover.sh` keeps EXACTLY its eight fns; `kit/ops/lib/route.sh` gains no public fn
  (`lib-census` pins it); `update_hops_hint` keeps its NAME (install.sh greps `^update_hops_hint()`).
- Every helper either card writes is `_`-prefixed. An awk `function` takes at least one parameter (or a
  dummy local) — the INSTALLED `ops/index.py` still pins indented definitions until the dogfood.
- No new CONVENTIONS key; `tune` and everything it triggers NEVER edits `ops/CONVENTIONS.md`,
  `ops/RULES.tsv` or anything under `~/.claude`. No new dependency. `.github/` untouched. No repo file
  is deleted (a folded card leaving the BOARD is a board mutation, § 4).
- No `IFS="$(printf` in new code (`startup-budget`); use `$POLARIS_TAB`. bash 3.2: no `case` inside
  `$(...)`, no assoc arrays, no `mapfile`; never one fork per card in a loop over the board.
- Goldens are hermetic (mktemp repos, fake HOME + USERPROFILE), print no sha/time/absolute path, and
  never wait on a fixed `sleep` — poll an observable line. `cli-help` is re-pinned after the dogfood,
  never in a card. No `tools/proof.sh` and no full-suite command in any `verify:`.
- `kit/` is the source; the root `ops/` is the dogfooded copy and no card edits it.

## § 1 `polaris tune` (T-308 — new module `kit/ops/lib/tune.sh`, fn `cmd_tune`)
Read-only on the board, the repo and config; no model; target under 5 s on this repo. Its ONE write is
the verdict cache (§ 2), on every run, both outcomes. Usage: `polaris tune` (no flags).
- rc 0 → exactly one line: `tune: nothing to slow this project down`
- rc 1 → findings, in this order, each kind only when it applies; every finding line is followed by one
  or more fix lines indented three spaces:
  ```
  cards: plan <slug> — <n> open cards, projected about <T>; <k> of them fold into <m> chain card(s)
     fix: bash ops/polaris fold <ID> <ID>…                    (one line per foldable chain)
  layout: <the hops-due message minus its leading "layout pass due — ">
     fix: the layout pass — read ops/roles/TIDY.md
  lanes: autolaunch_max: <v>, but <L> lanes is the most cards per hour here
     fix: proposal — set autolaunch_max: <L> in ops/CONVENTIONS.md
  landing: integration: paranoid runs the whole suite on every card — about <M> min across <n> open cards
     fix: proposal — set integration: batch in ops/CONVENTIONS.md
  checks: no test_fast: and the whole suite takes <t>
     fix: proposal — set test_fast: to a command that finishes in under a minute
  behind: kit <cur>, channel <latest> — <why>                 (§ 5 table)
     fix: <step>                                              (§ 5 table)
  context: <bytes> bytes of unused definitions under ~/.claude, paid by every context
     fix: proposal — bash ops/polaris slim --apply
  ```
- rc 2 → any argument: `usage: polaris tune` on stderr; the cache is NOT written.
- When each applies (data the project already has — nothing is measured fresh):
  - `cards:` one line per `plan:` slug that has ≥ 1 foldable chain among its OPEN cards (ready/ +
    backlog/, no lock under `$LOCKS/<ID>`). `<n>` = that plan's open cards; `<T>` = the text after
    `projected: about ` up to ` (target` in `_speed_plan <slug>`'s output. A **foldable chain** (tune's
    detection, depends_on only): 2+ open cards C1…Ck of that plan, each with points 1–5 and no `steps:`,
    one risk value, one `contract:` value; Ci (i > 1) depends on Ci-1 and on no other non-done card;
    Ci-1 is depended on by no open card but Ci; sum ≤ 13. Chains are cut greedily from the head
    (a card whose next card would push the sum past 13 starts a new chain); a single card is not a
    chain. `fold`'s own acceptance (§ 4) is wider; tune proposes only these.
  - `layout:` `.polaris/hops-due` is due by save-hops.md § 0.5's rule (field 2 `0`, field 1 = `$BASE`'s
    sha now, `hops:` not `off`, `\r` stripped). Read, never recomputed.
  - `lanes:` `cfg autolaunch_max ""` is a number AND `_speed_ev plan`'s best-lanes figure (field 3, only
    when it has ≥ 8 fields) is > 0 and smaller.
  - `landing:` `cfg integration ""` is `paranoid` AND `.polaris/last-suite-seconds` > 120 (the
    threshold `speed` already uses) AND ≥ 1 open card; `<M>` = open cards × suite minutes, rounded.
  - `checks:` `cfg test_fast ""` is empty AND `.polaris/last-suite-seconds` > 180; `<t>` like `speed`.
  - `behind:` NOT self-hosting (`kit/ops/pack.py` absent) AND `update_latest` (its cache, at most the
    one daily network call it already makes) is semver-greater than `ver version`.
  - `context:` the bytes figure on `slim`'s `MACHINERY` row (report mode, nothing moved) > 8192.
- Settings findings (`lanes`, `landing`, `checks`, `context`) are REPORTED, never applied; a reader
  turns them into numbered proposals (TIDY § 6). `cards` and `layout` are the ACTIONABLE kinds.

## § 2 `.polaris/tune-due` — the verdict cache (the seam)
- One LF line: `<base-sha><TAB><0|1><TAB><n><TAB><kinds>`. `<base-sha>` = `git rev-parse --verify -q
  "$BASE"` when tune ran · field 2 `0` = DUE (an actionable finding: `cards` or `layout`), `1` = not
  due · `<n>` = number of finding KINDS printed (0–7) · `<kinds>` = those kind words comma-joined in
  print order (`cards,layout,landing`), or `-` when n = 0. Written ONLY by `tune`, on every rc 0/1 run.
- Due ⇔ the file exists AND field 2 is `0` AND field 1 equals `$BASE`'s sha now. Count ⇔ same sha test,
  then field 3. Readers strip `\r` from every field, inline the check (no new fn), and never run `tune`
  themselves on the anchor hook's clock (`next`, `triage`). Missing / stale / malformed = not due,
  n = 0, silently.
- Refreshed with exactly `"$SELF" tune >/dev/null 2>&1 || true` (T-309): in `heal` right after its
  `hops --due` call, and in `done`, `seal` and `seal --sync` right after theirs. `fold` refreshes it
  itself after its commit (T-308). Never a caller failure.

## § 3 `polaris note` (T-308 — `kit/ops/lib/builder.sh`, fn `cmd_note`, after `cmd_grant`)
- `polaris note <ID> -m "<line>"` — appends ONE line `- <line>` (a leading `- ` in the message is not
  doubled) to the Notes of a task in `active/`, in its OWN board commit `chore(board): note <ID>`,
  event `note`, then `sync_board`; prints `noted on <ID>: <line>`.
- Refusals (die, rc 1, nothing written): no ID or no `-m` → `usage: polaris note <ID> -m "<line>"` ·
  unknown flag → `unknown flag <f> — usage: …` · a message with a newline → `note takes ONE line — call
  it once per line` · not in active/ → `<ID> is not in active/ (state: <col|unknown>) — note writes on
  CLAIMED work only`. The evolve-hour report's diff is the reference body.
- `BUILDER.md` (both `assumed:` spots) and `SOLO.md` (its `assumed:` spot) say to record it with
  `bash ops/polaris note <ID> -m "assumed: <choice>"`; never a hand edit of a board file.

## § 4 `polaris fold <ID> <ID>…` (T-308 — `kit/ops/lib/tune.sh`, fn `cmd_fold`)
Board-only, mechanical, no model, under the board mutex.
- **Accept** only when ALL hold (checked before anything is written; a refusal writes nothing, rc 1,
  `fold refused: <reason>`): 2+ distinct IDs · every one in ready/ or backlog/ with no lock · one
  `plan:` value (empty matches only empty) · each points 1–5 with no `steps:` · sum ≤ 13 · one `risk:`
  value · one `contract:` value · in the order given, each pair (Ci-1, Ci) either has Ci depending on
  Ci-1, or shares ≥ 1 `files_owned` entry (pat_overlap) with Ci depending on no member · no card
  outside the group both depends on a member Cj (j < k) and is depended on by a later member.
- **The survivor is C1**, in place (same file, same ID, same title). It gets: `points:` = the sum ·
  `steps:` = one item per member in order, `- <points> <ID>: <title>` · `files_owned`, `context_files`,
  `verify`, `surface`, `needs`, `approved` = the unions, first appearance order, de-duplicated ·
  `depends_on` = the union minus every member ID · `value`, `time_criticality`, `risk_opportunity` = the
  max over members, `wsjf` recomputed as `new` computes it · its body keeps its own sections, then one
  `### Step <i> — <ID>: <title>` block per folded member holding that card's `## Why` and `## Acceptance
  criteria` text verbatim.
- Every OTHER open card (ready/ backlog/ blocked/) whose `depends_on` names a folded ID names the
  survivor instead (once). The folded card files leave `ops/board/`.
- The survivor's column afterwards = what `new`'s ready gate (task-author.md § 5) answers for it:
  ready/ iff every depends_on is in done/ and its files_owned overlaps nothing in ready/, active/ or
  review/ outside the group; else backlog/.
- ONE board commit for all of it: subject exactly `chore(board): fold <C2> <C3>… → <C1>`; one event
  `fold` on C1 with the folded IDs; `sync_board`; then the § 2 refresh. Prints
  `folded <C2> <C3>… into <C1> — <k> cards → 1, <sum> points, <col>/`. One `git revert` of that board
  commit undoes it.
- Usage error (fewer than two IDs) → `usage: polaris fold <ID> <ID>…`, rc 1.

## § 5 "behind" — why an install has not updated (T-308's `behind:` and T-309's waiting line share it)
First reason that applies; `board_quiescent inflight` gives `QUIET_WHY`, then `update_dirt_overlaps_kit`:
| reason | `<why>` | `<step>` |
|---|---|---|
| `active: <n>` | `<n> card(s) still building` | `it updates when they land — nothing to do` |
| `review: <n>` | `<n> card(s) wait to land, the oldest for <d> day(s)` | `land them or kick them back: bash ops/polaris next` |
| `lock: <ID>` | `a claim on <ID> is still held` | `finish it, or: bash ops/polaris release <ID>` |
| `integration lease held` | `the landing lane is held` | `it frees itself after integration_stale_minutes` |
| `bg job running: <j>` | `a background job is running (<j>)` | `it updates when the job ends` |
| kit dirt | `uncommitted edits inside the kit's own files` | `commit or stash them, then: bash ops/polaris update` |
| nothing | `nothing holds it` | `bash ops/polaris update` |
`<d>` = whole days since the oldest review/ card's `handoff` event (EVENTS), at least 0.

## § 6 Where the tune-up is told and taken (T-309)
- **`next` (handover.sh).** The tidy row moves up: right after row 1 (`integrate`) and BEFORE the
  budget/`build`/`promote` rows. It fires when, in this order (cheap tests first, forks only once a
  cache already says due): the § 0.6 marker `<dir>/tidy` is absent · the verdict is due — § 2's rule on
  `.polaris/tune-due`, OR save-hops § 0.5's rule on `.polaris/hops-due` · no task file in active/ or
  review/ (any review card, human-gated included) · the lease is not `live` · no own live bg job.
  Cards waiting in ready/ or backlog/ NEVER hold it off. Line 1 stays exactly `tidy`; its two notes:
  `   tune-up due: <kinds, or the hops-due message minus its lead>` and
  `   read ops/roles/TIDY.md — one context, it lands at most one task; then bash ops/polaris next`.
  The marker is written in the same call. Every other row is unchanged.
- **`triage` (route.sh).** A BARE triage (no IDs) prints `tidy` with the same gate whatever ready/ and
  backlog/ hold (`board_quiescent inflight` replaces the `n -eq 0` precondition for this branch), with
  notes `   tune-up due: <…>` and `   read ops/roles/TIDY.md — one context, no subagents`. Not due →
  every existing branch byte-identical. Named IDs are never rerouted.
- **Update words (admin.sh `update_hops_hint`, same name).** Reads § 2 first; tune-due missing or stale
  → falls back to hops-due's rule with n = 1. Quiet = `board_quiescent inflight`.
  - `explicit`, n > 0, quiet → `▶ NEXT — tune-up (<n>): read ops/roles/TIDY.md and run it now`
  - `explicit`, n > 0, busy → `▶ NEXT — tune-up due (<n>): it runs when the work in flight lands`
  - `auto` (suffix, leading space, no newline) → ` · tune-up due (<n>)`
  - n = 0 → rc 1, silent (the session-start line stays byte-identical, as today).
  `update --all` needs no change: it prefixes the child's line.
- **`update --auto` stops being silent (admin.sh `cmd_update_auto`, inline).** When it skips at step 5
  (busy) or step 6 (kit dirt) it records `.polaris/update-waiting`, one LF line
  `<epoch-first-seen><TAB><latest>` (rewritten only when absent or naming another version; removed after
  a successful apply). While `now - epoch` ≥ 86400 the skip prints ONE line in both modes (it replaces
  `skipped: …` under `--say`): `⏸ POLARIS <cur> → <latest> has waited <d> day(s): <why> — <step>` (§ 5).
  Under a day: today's behaviour, byte for byte. It still never applies under work in flight.
- **install.sh** (always the NEW code): its updater-too-old hint now covers any updater whose
  pre-install `ops/lib/admin.sh` lacks the string `tune-due`; it prints the `explicit` line above
  (byte-identical, quiet = no task file in active/ or review/) when § 2 gives n > 0, as ITS last line.
  Still exactly one `▶ NEXT` line from install.sh, and a fresh install still ends with the setup
  epilogue. (On a 6.12–6.17 updater its own old `save hops` line may follow; it leads to the same
  TIDY.md, which now starts with the tune-up.)
- **Refresh calls** — § 2's line in heal, done, seal, seal --sync.
- **The hold rule (index.py, `_hops_fixed` rule 10).** Every path named by `files_owned` or
  `context_files` of any task file under `ops/board/{backlog,ready,active,review,blocked}/` on
  `refs/heads/polaris/board` (one `git ls-tree` + one `git cat-file --batch`, never a fork per card) is
  held for the pass — except the tree's own task (`_hops_task`). Patterns match with `_hops_match`. A
  feature whose move set, importer edits or mention edits (what `--owned` would list) touch a held path
  is left out of `--propose` whole, like the 25-file rule; a guide `<dir>/CLAUDE.md` that a held
  pattern matches is not proposed. `hops --remap` and the board are untouched: waiting cards' paths
  never move, so nothing needs remapping. No board ref → nothing held (today's behaviour).
- **`find --api` (index.py).** An INDENTED shell `fn` definition is skipped, exactly the evolve-hour
  report's diff (`_api_nested`); plus one selfcheck fixture case in `selfcheck()` proving a nested
  helper and an awk `function x()` inside a quoted program are not API while a column-0 fn still is.
  The seven rows the report names leave `api-kit.expected` at the post-dogfood re-pin, not in a card.
- **Words.** `kit/ops/roles/TIDY.md`: § Entry gains "`next`/`triage` with cards waiting — the tune-up
  runs first; it never touches a waiting card's files"; § The pass gains a numbered step between
  step 0 (the update commit) and step 1, **the tune-up** — `bash ops/polaris tune`; run every
  `   fix: bash ops/polaris fold …` line it prints, in order (a refusal = one report line, go on); go on to
  the layout steps ONLY when it printed a `layout:` line, else straight to § Report. § Report gains:
  folds made (cards before → after, `speed --plan` projected before → after) and the settings findings
  as numbered proposals `<n>. <finding> — reply "approve <n>"` (never applied). No new heading.
  `kit/ops/roles/INIT.md`'s last step: run `bash ops/polaris tune` and put its lines in INIT's report;
  the pass itself runs at the next `next` (never a second role in INIT's context). `kit/CLAUDE.md`'s
  lane row: `| `tidy` | `ops/roles/TIDY.md` | the tune-up is due — fold waiting chains, run the layout
  pass, propose settings; one context, no subagents |`.

## § 7 T-308's words and release
- `kit/ops/polaris`: loader list gains `tune` after `author` (literal list, module-layout.md v2);
  dispatch `tune) shift 2>/dev/null || true; cmd_tune "$@";;` (no update_check_maybe), `fold) shift;
  cmd_fold "$@";;`, `note) shift; cmd_note "$@";;`; help entries for all three (`note` after `grant`).
- `kit/ops/hooks/readonly-allow.sh`: bare `tune` is read-only-allowed; `fold` and `note` are not.
- `kit/ops/PROTOCOL.md`: command-table rows for `tune`, `fold`, `note`; § SAVE HOPS's "When." says the
  tune-up runs whenever its verdict is due and nothing is building or waiting to land — waiting cards
  included, their files held.
- `kit/ops/MANUAL.md`: by-hand recipes `## Note — …` and `## Fold — …` (the only new headings).
- `kit/ops/roles/CONDUCTOR.md` § 5 Snags gains the NEEDS PATH bullet (evolve-hour report, verbatim
  intent); its TIDY kickoff's `Return:` list gains `folds made · settings proposals`.
  `kit/ops/roles/BUILDER.md` § Failure path gains the NEEDS PATH paragraph.
- `kit/ops/VERSION` → `version: 6.18.0`; `CHANGELOG.md` `## 6.18.0` — measured claims only (the
  evolve-hour numbers, the update table in plans/tune.md), naming both cards' changes.
- `ops/tests/api-kit.expected` gains exactly the new public names: `kit/ops/lib/tune.sh fn cmd_fold`,
  `… cmd_tune`, `kit/ops/lib/builder.sh fn cmd_note`, and the two MANUAL headings (LC_ALL=C order as
  the golden prints).

## Executable checks
- T-308: `ops/tests/tune-report.cmd` (fixture: a 3-card depends_on chain in one plan, a due hops-due,
  `integration: paranoid` + a 300 s last suite → exactly `cards`/`layout`/`landing`, rc 1, the cache
  line compared with cmp; after `fold` → no `cards:` line; empty board → rc 0 line) · `fold-chain.cmd`
  (every refusal of § 4 writes nothing; a good fold's survivor frontmatter, dependents rewired, the one
  commit subject, `git revert` restores) · `note-line.cmd` (§ 3 lines and refusals).
- T-309: `ops/tests/tune-hop.cmd` (fixture board with a ready card and a backlog card waiting plus a
  due tune-due: `next` and bare `triage` print `tidy` once per session, then their usual answer; an
  active card or a review card holds it off) · `hops-hold.cmd` (hops_fixture + a board ref with an open
  card owning one checkout file: `--propose` never names it nor a guide it covers) ·
  `update-waiting.cmd` (fake channel cache + busy board: under a day silent, over a day the § 5 line).

## Appendix — the evolve-hour diffs (reference bodies from the lessons pass of plan `hour`)
The sections above win where they differ: the api-kit re-pin is post-dogfood, `note-line` is a new
golden rather than a grant-drill case, and T-308 (not a separate card) owns the CLI/api-kit rows.

### A.1 `find --api` skips indented shell definitions (T-309)
```diff
--- kit/ops/index.py  (module level, beside the other helpers)
+def _api_nested(root, path, ln, cache):
+    """True when line `ln` (1-based, as the indexer counts) of `path` starts with whitespace."""
+    if path not in cache:
+        try:
+            with open(os.path.join(root, path), encoding="utf-8", errors="replace") as fh:
+                cache[path] = fh.read().splitlines()
+        except OSError:
+            cache[path] = []
+    lines = cache[path]
+    return 0 < ln <= len(lines) and lines[ln - 1][:1] in (" ", "\t")
--- kit/ops/index.py:835 (cmd_find, mode --api)
         hit = False
+        src = {}
         for q in args:
             pat = q.replace("*", "%") if "*" in q else "%" + q + "%"
             seen = set()
             rows = []
-            for path, kind, name in cur.execute(
-                    "SELECT f.path,s.kind,s.name FROM symbols s JOIN files f ON f.id=s.file_id "
+            for path, kind, name, ln, lang in cur.execute(
+                    "SELECT f.path,s.kind,s.name,s.line,f.lang FROM symbols s JOIN files f ON f.id=s.file_id "
                     "WHERE f.path LIKE ?", (pat,)):
                 if name.startswith("_"):
                     continue
+                # An INDENTED shell definition is a helper nested in a function body, or an awk
+                # `function x()` inside a quoted program: neither is callable from outside its file,
+                # so neither is surface (plan hour: T-301, T-302, T-303 each went red on one).
+                if kind == "fn" and lang == "sh" and _api_nested(root, path, ln, src):
+                    continue
--- ops/tests/api-kit.expected  (re-pin with `check --update api-kit` after dogfood; exactly these 7 lines leave)
-kit/ops/bench.sh	fn	ctx_b
-kit/ops/lib/drift.sh	fn	finding
-kit/ops/lib/ownership.sh	fn	gdiff
-kit/ops/lib/qa.sh	fn	fin_caveat
-kit/ops/lib/qa.sh	fn	fin_count
-kit/ops/lib/qa.sh	fn	fin_ids
-kit/ops/lib/qa.sh	fn	fin_pending
```

### A.2 NEEDS PATH — grant, do not release (T-308)
```diff
--- kit/ops/roles/CONDUCTOR.md  (§ 5 Snags, after the "Builder returns RED" bullet, ~line 233)
+   - Builder returns NEEDS PATH (one path no card owns, everything else green, e.g. a derived golden
+     the contract forgot) → `bash ops/polaris grant <ID> <path> -m "<why, naming the contract line>"`
+     from the primary, then resume the SAME builder (SendMessage: "granted <path>; re-pin, re-run
+     verify, hand off"). No release, no Planner resume, no cold start. grant refuses (another
+     ready/active card owns it) → a real carve fault: `release --to blocked` and resume the Planner.
--- kit/ops/roles/BUILDER.md  (§ Failure path, after "A clean hand-back is success, not failure.")
+**Short exactly one path, everything else green?** Conductor-entered: do NOT release — return
+`NEEDS PATH <path> — <why>` with the task still claimed; the conductor grants it and resumes you.
+Alone: release as above, naming the path.
```

### A.3 `note` (T-308)
```diff
--- kit/ops/lib/builder.sh  (after cmd_grant, line 824)
+cmd_note() { # note <ID> -m "<line>" — append ONE Notes line (an `assumed:` default, a finding for the
+  # Planner) to a CLAIMED task in its OWN board commit. Hand-appended lines used to ride whichever lane
+  # committed next (plan hour: T-301/T-302's in "release T-300", T-303's in "claim T-300").
+  local id="${1:-}" msg="" u='usage: polaris note <ID> -m "<line>"'
+  [ -n "$id" ] || die "$u"; shift
+  while [ $# -gt 0 ]; do case "$1" in
+    -m) msg="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
+    *)  die "unknown flag $1 — $u";;
+  esac; done
+  [ -n "$msg" ] || die "$u"
+  case "$msg" in *"
+"*) die "note takes ONE line — call it once per line";; esac
+  local tf; tf="$(task_file "$id" active)" \
+    || die "$id is not in active/ (state: $(task_col "$id" || echo unknown)) — note writes on CLAIMED work only"
+  mutex_on
+  printf -- '- %s\n' "${msg#- }" >> "$tf"
+  evt note "$id" ""
+  board_commit "chore(board): note $id"
+  sync_board
+  mutex_off; trap - EXIT
+  say "noted on $id: ${msg#- }"
+}
--- kit/ops/polaris:428
   grant)      shift; cmd_grant "$@";;
+  note)       shift; cmd_note "$@";;
--- kit/ops/polaris  (help, after the grant entry, line 66)
+  note <ID> -m "<line>"          append ONE Notes line (an assumed: default) to a CLAIMED task, own board commit
--- kit/ops/PROTOCOL.md:32  (command table, after grant)
+| `ops/polaris note <ID> -m "<line>"` | append ONE Notes line to a CLAIMED task in its own board commit — how a Builder records an `assumed:` default |
--- kit/ops/roles/BUILDER.md:47 and :49
-… write it down as an `- assumed: <choice>` Notes line …
+… write it down: `bash ops/polaris note <ID> -m "assumed: <choice>"` …
-… MUST append one Notes line: `- assumed: <choice> (default-safe)`.
+… MUST record it: `bash ops/polaris note <ID> -m "assumed: <choice> (default-safe)"`.
```
