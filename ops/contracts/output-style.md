# CONTRACT: output-style            (v1 — 2026-07-27)
Owned by the installer. Roles and agents code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Make POLARIS's output discipline and its closing `# 🎉 Complete!` arrive **without anyone typing
anything**, in every repo where POLARIS is installed or updated.

Before 5.23.0 both layers that were supposed to deliver it missed:

- the vendored `i-have-adhd` skill carries `disable-model-invocation: true` in its **upstream**
  frontmatter, so it fires only when a human types `/i-have-adhd`. POLARIS may not edit it
  (`.claude/skills/i-have-adhd/SOURCE.md`; `ops/tests/adhd-skill-installed` locks the flag);
- its stated fallback, `ops/PROTOCOL.md` § VOICE, sits in a file `CLAUDE.md` explicitly tells
  sessions they probably need not open ("most sessions need one section or none").

So the "always-on" layer was, in practice, neither. A Claude Code **output style** is the one
mechanism that binds the main conversation's own operating instructions with no invocation.

## Interface — the file
```
kit/.claude/output-styles/polaris.md   →   <target>/.claude/output-styles/polaris.md
```
Frontmatter, all three keys load-bearing:
```yaml
name: POLARIS                      # matches the filename stem, so the outputStyle string resolves either way
description: …                     # rendered only in the /config picker
keep-coding-instructions: true     # SAFETY — see below
```

**`keep-coding-instructions: true` is not decoration.** A custom output style **excludes Claude
Code's built-in software-engineering instructions** — how to scope changes, write comments and
verify work — unless that key is `true`. Without it the harness keeps POLARIS's voice and forgets
how to engineer, a failure invisible in review and expensive in use. It therefore carries three
independent guards: this contract, `ops/tests/output-style-installed`, and a `doctor` check.

Body sections: scope guard (says, never writes to disk) · Voice · the 7 output-discipline rules ·
How a session ends · two worked examples. The 7 rules and the voice rows are **copied verbatim**
from `ops/PROTOCOL.md` § VOICE; if the two copies ever drift, the drift is a bug and is greppable.

## Interface — selection
| Case | Mechanism |
|---|---|
| No `.claude/settings.json` | the kit's copy is installed wholesale and already contains `"outputStyle": "polaris"` |
| Existing `settings.json` | `tgt.setdefault("outputStyle", "polaris")` in install.sh's python merge |

**Set-if-absent, never forced**, matching the `includeCoAuthoredBy` precedent. Forcing would rewrite
a committed value on every update — and would not even win, because `/config` writes the human's
choice to `.claude/settings.local.json`, which outranks `settings.json`. POLARIS never fights for a
key it would lose; `doctor` reports the effective style instead.

**`settings.local.json` is never written.** It is personal config. A human who picks another style
keeps it, and losing there is correct behavior, not a defect.

## Interface — scope, and why two layers remain
| Layer | Reaches | Carries |
|---|---|---|
| `.claude/output-styles/polaris.md` | the MAIN conversation only | voice · the 7 rules · caveats · edge cases · examples — **the shape** |
| `kit/CLAUDE.md` § PROGRESS FORMAT | every session **and every subagent** | the `finish` trigger · what exit 0 licenses · the subagent ban — **the behavior** |
| `ops/PROTOCOL.md` § VOICE | role files and subagents | the same 7 rules, for where a style never applies |

Output styles do not apply to subagents. That is why the CLAUDE.md lines were kept rather than
replaced by a pointer, and it is what makes these complementary rather than duplicative. Neither
restates the other.

## Executable check
- `ops/tests/output-style-installed` — ships · name matches the stem · **`keep-coding-instructions:
  true`** · confetti rule present · install.sh copies it · install.sh seeds the key · the kit's
  settings.json selects it · uninstall removes it · CLAUDE.md still carries the subagent layer.
- `kit/ops/selftest-install.sh` § `drill_fresh` — the file lands in a real target, with the flag, and
  `outputStyle` survives a **merge** into a pre-existing settings.json.
- `kit/ops/selftest-install.sh` § `drill_uninstall` — our file and our key are gone; a foreign style
  and a foreign hook are kept.
- `polaris doctor` — missing file · lost flag · a `settings.local.json` naming another style ·
  `settings.json` not selecting it.

## Invariants
1. **`keep-coding-instructions: true` is never removed.** Anything else in the file is editable.
2. The style governs what an agent **says**, never what it **writes to disk**. Task frontmatter,
   contracts, `ops/MAP.md`, commit messages and code stay terse and machine-precise.
3. POLARIS writes `.claude/settings.json`, never `.claude/settings.local.json`.
4. `outputStyle` is seeded set-if-absent and removed on uninstall **only when its value is ours**.
5. The style is project-level only. It is never written to `~/.claude/output-styles/`, which would
   impose POLARIS discipline on every unrelated repo on the machine.
6. The 7 rules and the voice rows stay byte-identical to `ops/PROTOCOL.md` § VOICE.
7. The installer prints no new stdout line for any of this. Installer stdout is a contract: CI counts
   the quiet lines above the `▶ NEXT` epilogue (≤2), which is why the settings merge is silent.
8. Known, accepted wart: deleting `outputStyle` is indistinguishable from a fresh install, so a
   deletion returns on the next update. The remedy is to set a different value, not to delete it.

## v2 — radically plain standard (2026-08-04)
v1 shipped the mechanism; the words it delivered stayed technical. The owner's complaint, verified:
under `voice: standard` a real close read "Wave 1 is sealed as sprint/10, the tree is clean, and
waves 2–5 sit on the board with their dependencies satisfied" — short, dense, every noun jargon.
Three root causes, all in the v1 texts themselves: the `standard` row banned only POLARIS jargon and
its "unless you explain it in the same breath" escape hatch **licensed** jargon; the 7 OUTPUT
DISCIPLINE rules optimize volume, not simplicity; and the style's own worked examples — the model's
imitation target — said "Full suite is green on `main`". v2 replaces the words. Mechanism, keys,
installer behavior, and every v1 invariant are untouched.

### The register ban — the new `standard` row
The escape hatch is dead: zero occurrences of "in the same breath" anywhere in either file. The row
below goes into `kit/ops/PROTOCOL.md` § VOICE as ONE physical table-row line, and the same sentences,
unwrapped from the table, become the opening paragraph of the style's § Voice. Byte-exact sentences:

> Warm, friendly, everyday English — the bar: someone who has never used git or run a test
> understands every sentence. No POLARIS jargon, and no trade words either — never "branch",
> "merge", "suite", "green", "CI", "worktree", "seal", "commit". Don't explain a technical word —
> drop it and say the outcome instead: merged → "saved into the main copy" · suite green → "every
> check passed" · branch → "a separate working copy" · parked/blocked → "set aside", plus why.
> Commands you tell them to run stay verbatim. Lead with what happened and what it means for them;
> leave out detail they didn't ask for.

`voice: technical` is untouched — row and behavior.

### The 7 rules, re-cut (count deliberately unchanged — the pin expects exactly 7)
Byte-identical in both files, still exactly 7 numbered-bold lines, no other `^[0-9]\. \*\*` line
anywhere in the style file:

1. **Lead with the action**, not the context. Answer first, explain only if asked.
2. **Number multi-step work; cap every list at 5.** More than five is a dump, not a report.
3. **End with ONE concrete next step**, doable in under two minutes. Not three options.
4. **No preamble, no recap, no closing pleasantry.** Start at the answer, stop when it ends.
5. **Restate where things stand, every message** — "3 of 5 done, 2 to go", never "good progress".
6. **Give time in real units** — "about 15 minutes", never "some work" or "almost there".
7. **State trouble flat — what broke, the fix.** Tangents → one line in `ops/board/backlog/IDEAS.md`.

### The Pre-send check — joins invariant 6
The one simplicity tool the vendored `i-have-adhd` skill had that v1's adaptation dropped. It goes
in BOTH files, identical, as a bold-led paragraph with DASH bullets under an EXISTING heading —
never a new heading (`api-kit` pins every kit heading) and never a numbered-bold list (the style
pin counts those). **Invariant 6 now covers three things: the 7 rules, the voice rows, and the
Pre-send check — all byte-identical between the style and PROTOCOL § VOICE.** Byte-exact text:

> **Pre-send check — run it on every reply.** Before sending, delete:
> - the first sentence, if it announces what you are about to do;
> - the last sentence, if it recaps what just happened or asks "anything else?";
> - any "by the way" sidebar;
> - any hedge that carries no real doubt ("perhaps", "might possibly") — keep one that does;
> - any idiom or figure of speech ("circle back", "up and running") — say the literal thing.
>
> Then read only your first line and your last line. Together they must say what happened and what
> to do next. If they don't, rewrite. If they do, send.

### The worked examples ARE the bar
The model imitates the examples harder than it obeys the rules, so the examples under the style's
existing `## What a close reads like` heading (heading byte-identical, `# 🎉 Complete!` literal
kept) are replaced with closes that pass the register ban. Byte-exact:

Complete: "The export button works now — it saves a real spreadsheet file instead of the
placeholder, and the file name carries today's date. Every check passed, and the change is saved
into the main copy of the project. One thing I set aside: the PDF export still needs your call on
page size." / "Next: open the app and hit Export on a report with more than 1,000 rows. Takes
about a minute."

Not complete: "Two of the three changes are in — login now sends you to the right page, and idle
sessions log out on time. Both are checked and saved. The password-reset change is finished but
not yet folded in, so I'm not calling this done." / "Next: `bash ops/polaris land T-014` — that
folds it in. About a minute."

### Executable check — `ops/tests/plain-voice`
The first mechanical pin invariant 6 has ever had. Seven assertions (golden files LF per
`ops/contracts/golden-eol.md`):
1. the bar sentence ("never used git") present in `kit/ops/PROTOCOL.md`;
2. the bar sentence present in `kit/.claude/output-styles/polaris.md`;
3. zero occurrences of "in the same breath" across both files — the escape hatch stays dead;
4. "Pre-send check" present in `kit/ops/PROTOCOL.md`;
5. "Pre-send check" present in the style file;
6. jargon grep scoped to the examples section ONLY (`sed -n '/^## What a close reads like/,$p'`,
   then case-insensitive word-boundary grep over `suite|merged?|branch|worktree|seal(ed)?|wsjf|integrate|repo`)
   returns zero — the bar sentence itself legitimately names trade words, which is why the scope
   is the examples, not the whole file;
7. the two copies' `^[0-9]\. \*\*` rule lines compared IDENTICAL — extract PROTOCOL's with sed
   scoped to § VOICE (§ LONG COMMANDS legitimately has its own numbered-bold lines), diff against
   the style file's; empty diff or fail.
The golden's owner owns every file feeding it (the derived-surface rule from the Learned log), and
the golden must be proven to FAIL under sabotage before it is trusted.

### What v2 does NOT change
Voice changes wording, never content or behavior (v1 § Invariants item 2 stands verbatim). The
frontmatter keys, install/uninstall/merge behavior, selection rules, and the two-layer scope table
are all v1, untouched. `ops/tests/output-style-installed`'s pins — exactly 7 numbered-bold lines,
`^name: POLARIS$`, `^keep-coding-instructions: true$`, `🎉 Complete!` (style AND kit/CLAUDE.md),
`subagent never ends a run` (kit/CLAUDE.md) — all still hold by construction.
