# lib/selftest/brain.sh — selftest drills: brain. Bodies verbatim from the pre-split spine;
# spine state reaches them by bash dynamic scoping — NO local declarations in these functions.
drill_brain() {
    # ==================== T-030 brain drills (ops/contracts/brain.md) ====================
    # generator: all 7 layout files, gitignored · INDEX routes to all 5 domain files · board
    # digest names the landed task T-1 · staleness round-trip: board-changed newer → doctor
    # warns → refresh clears. (Seal auto-refresh + the refresh-failure note ride the
    # second-seal drill below.)
    "$SELF" help | grep -q 'brain' || { echo "USAGE FAIL: brain missing from help"; exit 1; }
    "$SELF" brain >/dev/null || { echo "BRAIN BUILD FAIL"; exit 1; }
    # brain.md v2 (5.19.0): 9 entries — 8 .md files + .stamp. prefs/learned are the accumulating half.
    for bf in INDEX.md code-map.md board.md contracts.md commands.md gotchas.md prefs.md learned.md .stamp; do
      [ -f ".polaris/brain/$bf" ] || { echo "BRAIN FILE FAIL ($bf missing)"; exit 1; }
    done
    git status --porcelain | grep -q 'brain' && { echo "BRAIN GITIGNORE FAIL (no brain path may reach git status)"; exit 1; }
    for bf in code-map.md board.md contracts.md commands.md gotchas.md prefs.md learned.md; do
      grep -q "$bf" .polaris/brain/INDEX.md || { echo "BRAIN INDEX FAIL ($bf not routed)"; exit 1; }
    done
    # v2 content gates: a generated file that exists but says nothing is worse than a missing one,
    # because the drill above would go green forever while the brain taught the next agent nothing.
    grep -q '^| indent |' .polaris/brain/prefs.md \
      || { echo "BRAIN PREFS FAIL (no indent row — detection produced nothing)"; exit 1; }
    grep -q 'change together' .polaris/brain/learned.md \
      || { echo "BRAIN LEARNED FAIL (co-change section missing)"; exit 1; }
    # find/show must be routed from hop 1 as a COMMAND — the 5.19.0 wiring that makes the index
    # reachable at all. Without this row the index is built, correct, and never used by anyone.
    grep -q 'polaris find' .polaris/brain/INDEX.md \
      || { echo "BRAIN INDEX FIND FAIL (symbol lookup not routed to polaris find)"; exit 1; }
    grep -q 'T-1' .polaris/brain/board.md || { echo "BRAIN BOARD FAIL (landed task T-1 missing from the digest)"; exit 1; }
    # T-038 (brain v1.1): all 8 effective-CONVENTIONS keys survive the head-80 cap — values print
    # BEFORE the ~75-line help dump, so the cap only ever cuts the help tail.
    for bk in base claim integration publish express stale_hours test build; do
      grep -q "^$bk:" .polaris/brain/commands.md || { echo "BRAIN COMMANDS KEYS FAIL ($bk: cut by the cap)"; exit 1; }
    done
    "$SELF" doctor 2>/dev/null | grep -q 'brain is stale' && { echo "BRAIN FRESH FAIL (a just-built brain must not warn)"; exit 1; }
    sleep 1; date +%s > .polaris/board-changed    # sleep: -nt needs strictly-newer mtime on 1s-resolution filesystems
    "$SELF" doctor 2>/dev/null | grep -q 'brain is stale' || { echo "BRAIN STALE FAIL (board-changed newer than .stamp must warn)"; exit 1; }
    "$SELF" brain --refresh >/dev/null || { echo "BRAIN REFRESH FAIL"; exit 1; }
    "$SELF" doctor 2>/dev/null | grep -q 'brain is stale' && { echo "BRAIN REFRESH STALE FAIL (refresh must clear the warn)"; exit 1; }
}
