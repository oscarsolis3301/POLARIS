# Vendored, not authored

`SKILL.md` in this directory is a VERBATIM copy of a third-party skill. POLARIS ships it; POLARIS
did not write it, and must not edit it.

| | |
|---|---|
| upstream | https://github.com/ayghri/i-have-adhd |
| file | `skills/i-have-adhd/SKILL.md` |
| author | Ayoub Ghriss |
| licence | MIT — full text in `LICENSE` beside this file |
| vendored | 2026-07-26, for POLARIS 5.23.0 |

## Why it ships with the kit

The upstream install path is `claude plugin marketplace add ayghri/i-have-adhd` followed by
`claude plugin install`. That is a manual step on every machine, and a step nobody runs is a feature
nobody has. Vendoring it means `/i-have-adhd` works the moment POLARIS is installed, in every repo,
with no network call and no per-user setup — the same reason the write-guard ships inside the kit
rather than as instructions to configure one.

`ops/tests/adhd-skill-installed.cmd` asserts it actually landed, so a broken install is caught by
`polaris check` for zero tokens rather than by a human noticing the slash command is missing.

## The important detail: it is NOT auto-invoked

Its frontmatter carries `disable-model-invocation: true`, so the skill fires only when a human types
`/i-have-adhd`. On its own it would sit unused in most sessions.

That is why POLARIS also carries the same discipline elsewhere, with no invocation at all. Three
layers, deliberate and not redundant — each reaches somewhere the others cannot:

- **this skill** — the full ten rules, opt-in, session-persistent, for the human who wants them everywhere;
- **the output style** (`.claude/output-styles/polaris.md`) — the seven rules plus the closing
  contract, auto-selected by the installer, binding the MAIN conversation in every POLARIS repo.
  Output styles never reach subagents, which is why the next layer still exists;
- **PROTOCOL VOICE** — the seven rules that survive compression, always on, for every POLARIS role
  and every subagent.

Until 5.23.0 there were only the first and last, and the middle one is the reason this file used to
overstate its case: the skill never fires by itself, and PROTOCOL is a section `CLAUDE.md` tells
sessions they probably need not open. The always-on layer was, in practice, neither.

If you update the vendored copy, re-fetch it from upstream verbatim and bump the vendored date
above. Do not hand-edit `SKILL.md` — a locally-patched copy that still claims to be upstream is
worse than no copy.

## Modifications

None. `SKILL.md` is byte-for-byte upstream.
