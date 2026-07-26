# The kit's public surface. A shape regression here means we changed what ships without meaning to.
#
# Vendored third-party content is EXCLUDED, and deliberately: kit/.claude/skills/i-have-adhd/ is a
# byte-for-byte copy of an upstream MIT skill (see its SOURCE.md). Its markdown headings are not
# POLARIS's API, and by contract that file changes only by being re-fetched from upstream — locking
# it here would red on the one update path we want to stay easy, and would quietly assert that
# someone else's document is part of our interface. Same reasoning as scaffold_dirs() excluding
# vendored and built trees: never lock a tree whose job is to change without us.
# ops/tests/adhd-skill-installed is what guards that file, and it checks the right things — that it
# shipped, kept its licence and attribution, and kept its opt-in frontmatter flag.
bash ops/polaris find --api 'kit/*' | grep -v '^kit/\.claude/skills/i-have-adhd/'
