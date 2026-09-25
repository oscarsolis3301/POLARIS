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
#
# It indexes the tree it RUNS IN, never the primary checkout. `ops/polaris find` pins POLARIS_ROOT
# to the primary (a Builder's lookups must hit the primary's index), so run from a builder's
# worktree it silently checked the primary's kit and passed no matter what the worktree changed.
# index.py honours POLARIS_ROOT, so calling it direct with $PWD makes this golden true from any
# tree: the primary, a worktree, or CI (T-182, ops/contracts/speed.md § 5-6).
POLARIS_ROOT="$PWD" python ops/index.py find --api 'kit/*' | grep -v '^kit/\.claude/skills/i-have-adhd/'
