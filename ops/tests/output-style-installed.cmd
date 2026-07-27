# The output style must SHIP, must be SELECTED, and must keep the one flag that makes it safe.
#
# `keep-coding-instructions: true` is the assertion that matters. Without it a custom output style
# EXCLUDES Claude Code's built-in software-engineering instructions — the harness keeps POLARIS's
# voice and forgets how to scope a change or verify its work. That failure is invisible in review
# and expensive in use, which is exactly the profile of a thing that needs a mechanical check.
#
# The rest mirror ops/tests/adhd-skill-installed: shipping a file is not the same as installing it,
# and installing it is not the same as selecting it. Three separate things, three separate ways to
# lose it silently. See ops/contracts/output-style.md.
O=kit/.claude/output-styles/polaris.md
[ -f "$O" ] && echo "kit has the output style" || echo "MISSING $O"
grep -q '^name: POLARIS$' "$O" && echo "name set" || echo "NAME MISSING"
grep -q '^keep-coding-instructions: true$' "$O" && echo "coding instructions kept" || echo "CODING INSTRUCTIONS EXCLUDED — see ops/contracts/output-style.md"
grep -q '🎉 Complete!' "$O" && echo "confetti rule present" || echo "CONFETTI RULE MISSING"
grep -c '^[0-9]\. \*\*' "$O" | sed 's/^/discipline rules: /'
grep -q 'output-styles' kit/ops/install.sh && echo "install.sh copies it" || echo "install.sh DOES NOT copy it"
grep -q 'setdefault("outputStyle"' kit/ops/install.sh && echo "install.sh seeds outputStyle" || echo "outputStyle NEVER SEEDED"
grep -q '"outputStyle"' kit/.claude/settings.json && echo "fresh settings select it" || echo "fresh install does not select it"
grep -q 'output-styles' kit/ops/lib/admin.sh && echo "uninstall removes it" || echo "uninstall LEAKS it"
# An output style never reaches subagents, so CLAUDE.md must still carry the trigger + the ban.
grep -q '🎉 Complete!' kit/CLAUDE.md && echo "CLAUDE.md carries the subagent layer" || echo "SUBAGENT LAYER MISSING"
grep -q 'subagent never ends a run' kit/CLAUDE.md && echo "subagent ban intact" || echo "SUBAGENT BAN MISSING"
