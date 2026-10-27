# `depth` decides how much testing a change needs (ops/contracts/test-depth.md); nothing calls it
# yet (T-198 wires it into qa/land), so this golden is depth_for/cmd_depth's ONLY proof. Line 1 is
# parsed blind by whoever wires it in next, so a changed word or an extra line silently misroutes
# every caller that trusts it later.
#
# HERMETIC BY CONSTRUCTION (the T-062/triage-lane pattern): a throwaway fixture repo, never the
# live board or this repo's own CONVENTIONS/SURFACES — running this twice from ANY board state is
# byte-identical. Every row of the contract's § 2 table gets its own fixture branch + task, each
# exercised through the real CLI entrypoint (`polaris depth <ID>`), which is also the
# "polaris depth on a fixture branch" box the task asks for — one path proves both.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src docs
  echo 'lib v1' > src/lib.dat
  echo 'u v1'   > src/unmapped.dat
  echo 'doc v1' > docs/readme.md
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  # test_select + ONE mapped surface row, so rule 5/6 (scoped vs full) has something to answer.
  printf 'test_select: echo RUN {tests}\n' > ops/CONVENTIONS.md
  printf '# fixture surfaces\nsrc/lib.dat\ttests/lib.dat\t-\tfixture lib [T-4]\n' > ops/SURFACES.tsv
  git add -A; git commit -qm cfg
) >/dev/null 2>&1

task() { # task <ID> <risk> <test_depth|-> — writes the board task file (not git-tracked)
  local id="$1" risk="$2" td="$3" extra=""
  [ "$td" != "-" ] && extra="test_depth: $td
"
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: 1\nrisk: %s\n%sowner: null\nbranch: null\nstatus: active\nfiles_owned:\n  - src/lib.dat\nverify: []\n---\n' \
    "$id" "$id" "$risk" "$extra" > "$R/ops/board/active/$id.md"
}
mkbranch() { # mkbranch <ID> <path>=<content> [<path>=<content> …] — a feat/<ID> branch off main
  local id="$1" item f v; shift
  ( cd "$R" && git checkout -q -b "feat/$id" main
    for item in "$@"; do
      f="${item%%=*}"; v="${item#*=}"
      mkdir -p "$(dirname "$f")"; printf '%s\n' "$v" > "$f"
    done
    git add -A; git commit -qm "feat: $id fixture"
    git checkout -q main
  ) >/dev/null 2>&1
}
D() { printf 'depth %s\n' "${*:-<no ID>}"; ( cd "$R" && bash "$KIT" depth "$@" 2>&1 ); printf 'rc %s\n' "$?"; }

echo '== rule 3: a docs-only change skips the suite outright =='
mkbranch T-1 "docs/readme.md=doc v2"
task T-1 normal -
D T-1

echo '== rule 4: a css-only change runs the lighter look depth =='
mkbranch T-2 "style.css=css v1"
task T-2 normal -
D T-2

echo '== rule 4: docs + css together — the docs path drops, one look path remains =='
mkbranch T-3 "docs/readme.md=doc v3" "style.css=css v2"
task T-3 normal -
D T-3

echo '== rule 5: a mapped lib file, every code path covered by ops/SURFACES.tsv =='
mkbranch T-4 "src/lib.dat=lib v2"
task T-4 normal -
D T-4

echo '== rule 6: an unmapped lib file — surface_select_cmd names the reason =='
mkbranch T-5 "src/unmapped.dat=u v2"
task T-5 normal -
D T-5

echo '== rule 1: risk: high overrides everything, even a docs-only change =='
mkbranch T-6 "docs/readme.md=doc v4"
task T-6 high -
D T-6

echo '== rule 2: test_depth: full overrides everything, even a docs-only change =='
mkbranch T-7 "docs/readme.md=doc v5"
task T-7 normal full
D T-7

echo '== test_depth: none is a no-op, never a floor — normal resolution still applies =='
mkbranch T-8 "docs/readme.md=doc v6"
task T-8 normal none
D T-8

echo "== test_skip: '-' empties the skip list — the SAME docs-only change now goes full =="
( cd "$R" && printf 'test_skip: -\n' >> ops/CONVENTIONS.md
  git add ops/CONVENTIONS.md; git commit -qm 'fixture: disable test_skip' ) >/dev/null 2>&1
mkbranch T-9 "docs/readme.md=doc v7"
task T-9 normal -
D T-9
