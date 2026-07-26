# The vendored i-have-adhd skill must SHIP and must stay VERBATIM.
#
# "Ensure it works as soon as POLARIS is installed" is only true if something checks. A skill that
# silently stops being copied looks identical to one that works — the slash command just quietly
# isn't there — so this pair costs a subprocess and catches it forever.
#
# Three assertions, in the order they can break:
#   1. the kit carries all three files (a partial vendor is worse than none — no licence, no origin)
#   2. install.sh actually copies them (the manifest edit is the thing most likely to be lost)
#   3. the copy is UNMODIFIED upstream — frontmatter intact, and the opt-in flag still set.
# That last one matters more than it looks: `disable-model-invocation: true` is WHY POLARIS also
# carries the discipline in PROTOCOL.md § VOICE. If someone "helpfully" flips it to auto-invoke,
# the two layers silently become one and the VOICE section looks redundant.
K=kit/.claude/skills/i-have-adhd
for f in SKILL.md LICENSE SOURCE.md; do
  [ -f "$K/$f" ] && echo "kit has $f" || echo "MISSING $K/$f"
done
grep -q 'i-have-adhd' kit/ops/install.sh && echo "install.sh copies it" || echo "install.sh DOES NOT copy it"
grep -q 'i-have-adhd' kit/ops/lib/admin.sh && echo "uninstall removes it" || echo "uninstall LEAKS it"
sed -n '2p' "$K/SKILL.md"
grep -q '^disable-model-invocation: true$' "$K/SKILL.md" && echo "opt-in flag intact" || echo "OPT-IN FLAG CHANGED — see PROTOCOL.md VOICE"
grep -q 'MIT License' "$K/LICENSE" && echo "MIT licence present" || echo "LICENCE MISSING"
grep -q 'Ayoub Ghriss' "$K/LICENSE" && echo "attribution intact" || echo "ATTRIBUTION STRIPPED"
grep -c '^### ' "$K/SKILL.md" | sed 's/^/rules: /'
# PROTOCOL's always-on layer must exist too — the skill alone never auto-fires.
grep -q 'OUTPUT DISCIPLINE' kit/ops/PROTOCOL.md && echo "PROTOCOL carries the always-on layer" || echo "PROTOCOL LAYER MISSING"
