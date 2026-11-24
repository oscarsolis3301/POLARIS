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
# walk-away § 8.3 (6.20.0): the 🚩 rule is the SAME two lines in every kit home — the heal block that
# writes it into a project's CLAUDE.md, PROTOCOL § TOKEN DISCIPLINE, this style, CONDUCTOR — and the
# style carries the parked ending and the away run's last line. Line ends stripped: kit prose may be CRLF.
N1='- **Long, mechanical, no judgement in it?** Run it yourself, detached: one command per line in a file, then'
N2='  `bash ops/polaris bg run <name> --steps <file>` and collect once. 🚩 only what needs a person, only while they are here.'
n=0
for f in kit/ops/PROTOCOL.md "$O" kit/ops/roles/CONDUCTOR.md; do
  tr -d '\r' < "$f" | grep -qxF -e "$N1" && tr -d '\r' < "$f" | grep -qxF -e "$N2" && n=$((n+1))
done
grep -qF "local n1='$N1'" kit/ops/lib/admin.sh && grep -qF "local n2='$N2'" kit/ops/lib/admin.sh && n=$((n+1))
echo "the 🚩 rule, word for word: $n of 4 homes"
grep -q 'finish: parked - <n> waiting on you' "$O" && echo "parked ending present" || echo "PARKED ENDING MISSING"
grep -q '^waiting, <n> timeouts`\|`run: <total> - ' "$O" && echo "away run's last line present" || echo "RUN LINE MISSING"
