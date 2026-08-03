# CONTRACT: golden-eol — ops/tests goldens are LF, everywhere            (v1 — 2026-08-03)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates golden-file byte content from platform checkout behavior: `ops/tests/*.expected` and
`ops/tests/*.cmd` are byte-exact LF artifacts on every platform, every checkout, every rewrite.

## Interface
```
.gitattributes
  ops/tests/*.expected  text eol=lf
  ops/tests/*.cmd       text eol=lf
```
The pins guarantee git both stores these LF (index i/lf) and materializes them LF in every working
copy — including Windows with `core.autocrlf=true`. Without them the goldens fall through to
`* text=auto` and any working-copy rewrite lands CRLF.

## Invariants
- LF is the contract because both halves of `cmd_check` (kit/ops/lib/observe.sh:~1170) assume it:
  `.expected` files are byte-diffed against LF stdout (one CR per line makes every line "differ"),
  and `.cmd` files execute via `bash -c "$(cat ...)"`, where CRLF breaks execution outright.
- `polaris check` and `polaris find` are PRIMARY-ANCHORED — they cd to the primary checkout
  (kit/ops/lib/observe.sh:1170, kit/ops/lib/search.sh:12-15). A builder in a worktree therefore
  proves this contract worktree-locally: `git check-attr`, re-materialize (`rm` +
  `git checkout -- ops/tests/`), then a CR-byte scan with awk or od — never grep/sed, which strip
  \r under Git Bash.
- Index content is already LF; the fix is attribute lines only — no renormalize commit. The primary
  working copy's refresh after land is the Integrator's step.

## Executable check
Lives in T-056's `verify:` (check-attr, re-checkout, `git ls-files --eol`, CR-byte scan). The check
IS the contract; prose above is commentary.

## Changelog
- v1 2026-08-03: created for T-056
