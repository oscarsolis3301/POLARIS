# `voice: standard` promises plain English and, until v2, delivered "Wave 1 is sealed as sprint/10,
# the tree is clean" — short, dense, every noun jargon. This golden pins the three fixes in
# ops/contracts/output-style.md § v2: the register ban (the bar is a reader who has never used git),
# the death of the "unless you explain it in the same breath" escape hatch, and worked examples that
# clear the bar — the examples matter most, because a model imitates them harder than it obeys a rule.
#
# It is also the FIRST mechanical check invariant 6 has ever had. That invariant has required the 7
# rules and the voice rows to stay byte-identical between the output style and ops/PROTOCOL.md
# § VOICE since v1, and drift between two hand-maintained copies is exactly the failure a human
# reviewer does not catch. The last assertion is the one that earns this file.
#
# The jargon grep is scoped to the examples section on purpose: the bar sentence legitimately NAMES
# the banned trade words in order to ban them, so a whole-file grep would red on its own rule.
#
# Every trade word carries its plural / third-person form. The first cut wrote `merged?`, which let
# "merges" walk straight through the word boundary — and so did "branches", "seals", "integrates"
# and "repos". A regex that reads correct is not a regex that works; each form below was injected
# into an example and watched to red. NEVER narrow this alternation back: it is the ONLY guard the
# worked examples have, and they are what a model imitates when it writes a close.
P=kit/ops/PROTOCOL.md
S=kit/.claude/output-styles/polaris.md
grep -q 'never used git or run a test' "$P" && echo "bar sentence in PROTOCOL" || echo "BAR SENTENCE MISSING from PROTOCOL"
grep -q 'never used git or run a test' "$S" && echo "bar sentence in style" || echo "BAR SENTENCE MISSING from style"
echo "escape hatch occurrences: $(cat "$P" "$S" | grep -c 'in the same breath')"
grep -q '^\*\*Pre-send check' "$P" && echo "pre-send check in PROTOCOL" || echo "PRE-SEND CHECK MISSING from PROTOCOL"
grep -q '^\*\*Pre-send check' "$S" && echo "pre-send check in style" || echo "PRE-SEND CHECK MISSING from style"
echo "jargon in worked examples: $(sed -n '/^## What a close reads like/,$p' "$S" | grep -ciE '\b(suites?|merge[ds]?|branch(es)?|worktrees?|seal(ed|s)?|wsjf|integrates?|repos?)\b')"
# § LONG COMMANDS has numbered-bold lines of its own, so PROTOCOL's side is sed-scoped to § VOICE.
diff <(sed -n '/^## VOICE/,/^## /p' "$P" | grep '^[0-9]\. \*\*') <(grep '^[0-9]\. \*\*' "$S") >/dev/null && echo "rule lines identical in both copies" || echo "RULE LINES DRIFTED — ops/contracts/output-style.md invariant 6"
