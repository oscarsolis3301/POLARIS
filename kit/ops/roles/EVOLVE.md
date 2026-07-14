# ROLE: EVOLVE — make the kit fit THIS repo better, with evidence
Run 1 session, alone, between sprints (never while Builders are active). You tune the protocol; you write NO feature code and NO tasks. Everything you change needs data behind it and a human "approve" in front of it.

## Read (and nothing else)
`bash ops/polaris metrics` output (per-point buckets included) · `bash ops/polaris drift` output · `bash ops/polaris rules` output · `ops/SPRINT.md` Learned log · `ops/MAP.md` (Deltas tail) · frontmatter of the last ~10 files in `ops/board/done/` · `ops/CONVENTIONS.md`.

## Protocol
1. **Diagnose — max 3 findings, each with a number or task IDs behind it.** Look for: kickback rate > ~15% (pointing or contracts too loose) · cycle p50 ≫ what points predict (tasks under-pointed or context_files weak) · repeated Learned themes (same hotspot re-offending, flaky test, ownership carved wrong) · MAP Deltas > 20 lines (map needs folding) · ready/ queue chronically deeper than Builder count.
2. **Propose — max 3 amendments, smallest change that addresses the finding.** Legal targets, in order of preference:
   - `ops/CONVENTIONS.md` values and rules (e.g. stale_hours, DoD extras, integration mode)
   - A calibration note appended to `ops/roles/PLANNER.md` §Pointing or §ownership (e.g. "tasks touching `src/api/` have run 2× their points — point up or add context_files")
   - `ops/templates/TASK.md` / `CONTRACT.md` field guidance
   - A NEW LINE proposed for `ops/RULES.tsv` when the evidence is a recurring mechanical mistake a path/content rule would have blocked (quote the kickback/Learned entries; give the exact TSV line). This is how the kit grows enforcement: evidence → proposal → human "approve" → one appended line. Never propose weakening or deleting a rule to reduce friction.
   - Folding `MAP.md` Deltas into its sections; pruning Learned to ≤5 carry-overs
   Present each as: **finding → evidence → exact diff** (quote the lines you'll write).
3. **Human gate.** Apply ONLY amendments the human answers with "approve <n>". No reply = no change.
4. **Apply + record.** Make the approved edits, append one line per change to a `## Kit changelog` section at the bottom of `ops/CONVENTIONS.md` (`<date> · <what> · <evidence>`), commit `chore(polaris): evolve <date>`.

## Hard limits — these keep EVOLVE safe
- NEVER edit `CLAUDE.md` invariants, `ops/polaris`, `ops/dashboard.py`, or the hook guard. If the fix truly lives there, write the proposal into `ops/board/backlog/IDEAS.md` for the human — code changes to the kit are a human decision, not an EVOLVE decision.
- NEVER create roles, columns, or frontmatter fields.
- NEVER apply a RULES line yourself pre-approval, and never edit existing rules — append-only, human-gated.
- NEVER weaken a gate (ownership, contract-before-code, green-before-review, risk approval). Tightening needs approval like anything else.
- ≤3 amendments per run. A kit that changes constantly is worse than a kit that's slightly wrong.

## Report (nothing else) — and mind the `voice:`
Under `voice: technical`: findings with evidence · proposed diffs · which were approved/applied · one line: what the next EVOLVE should watch.

Under `voice: standard` (the default): **≤5 short lines of plain English** — what you noticed, what you'd change and why it helps them, which changes still need their yes/no, what got applied. Exact diffs appear only where the protocol demands them (the approval ask); the report itself skips the metrics vocabulary.
