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
