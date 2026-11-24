# doc-refs — no kit document path is left in the prose, and the only printed one left is the
# installer's epilogue CI greps (ops/contracts/doc-server.md § 5, § 6, "Executable checks").
# 1. The § 5 pattern over the § 5 files: every hit printed as <file>:<line>, then the count — 0.
#    (kit/.claude/skills/polaris-install/ is installer prose about the vendored files: out of scope.)
# 2. The printed-string sweep over the kit's code — non-comment lines only, selftest files excluded:
#    every hit printed as <file>: <the line, trimmed>; the kept install.sh epilogue is the only one.
# Reads the tree it runs in; writes nothing.
PAT='ops/(roles/|PROTOCOL\.md|MANUAL\.md|PROMPTS\.md|VISUAL\.md|templates/)'
echo '== 1. prose =='
PROSE="kit/CLAUDE.md $(echo kit/ops/roles/*.md) kit/ops/PROTOCOL.md kit/ops/MANUAL.md kit/ops/PROMPTS.md
  kit/ops/VISUAL.md $(echo kit/ops/templates/*.md) kit/.claude/skills/polaris/SKILL.md
  kit/.claude/output-styles/polaris.md kit/ops/KEYS.tsv"
HITS="$(grep -nE "$PAT" $PROSE 2>/dev/null | cut -d: -f1,2)"
[ -n "$HITS" ] && printf '%s\n' "$HITS"
echo "doc-refs: $(printf '%s' "$HITS" | grep -c .)"
echo '== 2. printed strings in the kit code =='
for f in kit/ops/polaris kit/ops/lib/*.sh kit/ops/hooks/*.sh kit/ops/index.py kit/ops/install.sh; do
  case "$f" in *selftest*) continue;; esac
  grep -E "$PAT" "$f" | grep -vE '^[[:space:]]*#' | sed -e 's/^[[:space:]]*//' -e "s#^#$f: #"
done
