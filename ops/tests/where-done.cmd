# where-done: `done` keeps the root map in CLAUDE.md fresh inside the ONE docs(map) commit it already
# makes (ops/contracts/save-hops.md § 4). The root map is a projection of ops/MAP.md, and MAP.md moves
# when a task lands with a map_delta — so that is the moment the map is refreshed, and CLAUDE.md rides
# that same commit: the board still adds no base commit of its own (the spine's QUIET MAP COUNT). What
# is pinned here is the three gates around it, each one a real `done` on a real base branch: a delta was
# applied (none → CLAUDE.md is left alone even when MAP.md has moved under the map), the repo already has
# a root map (none → done never writes one), and nobody has uncommitted edits in CLAUDE.md (then the map
# is not refreshed and CLAUDE.md is never committed — MAP.md still lands alone, in its one commit).
#
# HERMETIC (the shots-gallery pattern, minus the claims): ONE throwaway repo under mktemp -d with its own
# CONVENTIONS, MAP.md, CLAUDE.md and board. A task goes straight into review/ and is "landed" by a commit
# whose subject ends in [<ID>] — the record `done` looks for — so no lease, no worktree, no handoff.
# CLAUDE.md is CRLF on purpose, as a Windows checkout writes it: done's marker test must still find the
# root map, on every platform. Each `done` also refreshes the layout verdict (`hops --due`, § 0.5); this
# fixture has no engine for it — and until `hops --due` ships, no such command — so every line below
# must read the same either way: rc 0, no stray output, nothing extra committed.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p ops src
  printf 'echo app\n' > src/app.sh
  printf 'base: main\n' > ops/CONVENTIONS.md
  printf '# MAP — fixture\n\n## Entry points\n| Path | What it is |\n|---|---|\n| `src/app.sh` | the app — starts everything |\n\n## Deltas\n' > ops/MAP.md
  printf '<!-- POLARIS:BEGIN — managed block [kit fixture] -->\r\n# POLARIS fixture protocol\r\n<!-- POLARIS:END -->\r\n\r\n## Your own rules\r\nKeep it kind.\r\n' > CLAUDE.md
  bash "$KIT" init-board
  bash "$KIT" where --write
  git add -A; git commit -qm fixture
) >/dev/null 2>&1
# T <ID> [<map_delta>]: a task straight into review/ — map_delta: only when one is given — then its
# landed commit on main: one new file, pathspec-limited so a dirty CLAUDE.md stays out of it.
T() { ( cd "$R"
  { printf -- '---\nid: %s\ntitle: task %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: review\n' "$1" "$1"
    if [ -n "${2:-}" ]; then printf 'map_delta: %s\n' "$2"; fi
    printf 'files_owned:\n  - src/%s.sh\nverify: []\n---\n' "$1"; } > "ops/board/review/$1.md"
  printf 'echo %s\n' "$1" > "src/$1.sh"
  git add -- "src/$1.sh" && git commit -q -m "feat: $1 the change [$1]" -- "src/$1.sh" ) >/dev/null 2>&1; }
# D <ID>: the real `done`, then what base gained (subjects, and every path those commits carry), whether
# CLAUDE.md is the same bytes as just before, and what is left uncommitted.
D() {
  cp "$R/CLAUDE.md" "$FIX/claude.before"
  b="$(git -C "$R" rev-parse main)"
  ( cd "$R" && bash "$KIT" done "$1" 2>&1 ); printf 'rc=%s\n' "$?"
  echo '-- what base gained --'
  git -C "$R" log --format=%s "$b..main"
  echo '-- the paths it carries --'
  git -C "$R" diff --name-only "$b" main | LC_ALL=C sort
  if cmp -s "$R/CLAUDE.md" "$FIX/claude.before"; then echo 'CLAUDE.md: the same bytes as before'; else echo 'CLAUDE.md: rewritten'; fi
  s="$(git -C "$R" status --porcelain)"; printf -- '-- left uncommitted --\n%s\n' "${s:-(nothing)}"
}
# M: the root map as it now stands in CLAUDE.md — CRs dropped by tr first, so sed matches on any platform.
M() { echo '-- the root map --'; tr -d '\r' < "$R/CLAUDE.md" | sed -n '/^<!-- polaris:where -->$/,/^<!-- \/polaris:where -->$/p'; }

echo '== 1. a clean CLAUDE.md that holds a root map: done refreshes it inside the ONE docs(map) commit =='
# The delta starts with a path, so the map gains an item. CLAUDE.md is the second path of that same
# commit, so nothing is left behind: one commit, two paths, a clean tree.
T T-1 'src/T-1.sh — the helper the first task adds'
D T-1
M

echo '== 2. edits in CLAUDE.md that nobody has committed: the map is not refreshed, the file is not committed =='
# The person's line stays theirs — still in the file, in no commit — and the map does NOT gain T-2's
# item, though MAP.md does. MAP.md lands exactly as before: alone, in its one docs(map) commit.
printf 'A line I am still writing.\r\n' >> "$R/CLAUDE.md"
T T-2 'src/T-2.sh — the second helper'
D T-2
M

echo '== 3. no map_delta: no base commit at all, and CLAUDE.md is left alone though MAP.md has moved on =='
# The person's draft is put back, so CLAUDE.md is clean again — and its committed map is now one delta
# behind MAP.md (case 2). A done that refreshed the map here would change CLAUDE.md, with no docs(map)
# commit to carry it: it would be left uncommitted, the exact thing this guard exists to prevent.
git -C "$R" checkout -q -- CLAUDE.md
T T-3
D T-3

echo '== 4. a repo without a root map: done never writes one, and CLAUDE.md is not touched at all =='
( cd "$R" && bash "$KIT" where --strip && git commit -qam 'drop the root map' ) >/dev/null 2>&1
T T-4 'src/T-4.sh — the fourth helper'
D T-4
M
