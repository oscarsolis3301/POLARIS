# A chain card (ops/contracts/hour.md § 6) is up to 13 points built as 2-5 steps, one commit each, and
# its Builder hears the steps from `pack` — right after the verify list, the last thing read before
# the first edit. A card with no `steps:` must see NOTHING new: every existing pack is byte-identical.
#
# HERMETIC (the pack-guides pattern): one throwaway repo under mktemp -d with its own board and
# tasks, the CLI run from inside it. Only the tail of pack is pinned — from the WHAT PROVES IT
# header to the end — because everything above it (the brain, the index) is other goldens' business.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo a > src/a.txt; echo b > src/b.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
  # T-701: the contract's own 13-point example, block-list steps, with a comment on one item.
  printf -- '---\nid: T-701\ntitle: a chain card\ntype: feature\npoints: 13\nsteps:\n  - 5 the push key and the handoff gate\n  - 5 seal and done under push: end   # the middle link\n  - 3 finish makes the one push\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\nfiles_owned:\n  - src/a.txt\nverify:\n  - bash -n src/a.txt\n---\n## Why\nfixture\n' > ops/board/backlog/T-701.md
  # T-702: an ordinary card — no steps:, so no section.
  printf -- '---\nid: T-702\ntitle: a plain card\ntype: feature\npoints: 2\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\nfiles_owned:\n  - src/b.txt\nverify:\n  - bash -n src/b.txt\n---\n## Why\nfixture\n' > ops/board/backlog/T-702.md
  # T-703: the flow-list form of steps: reads the same.
  printf -- '---\nid: T-703\ntitle: a flow-list chain\ntype: feature\npoints: 8\nsteps: [4 first half, 4 second half]\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: backlog\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n## Why\nfixture\n' > ops/board/backlog/T-703.md
) >/dev/null 2>&1
R="$FIX/repo"
P() { ( cd "$R" && bash "$KIT" pack "$1" 2>/dev/null ) | awk '/^=== WHAT PROVES IT/{on=1} on{print}'; }

echo '== 1. a 13-point chain card: the STEPS section, right after the verify list =='
P T-701
echo '== 2. a card without steps: no section, the pack ends as it always did =='
P T-702
echo '== 3. the flow-list form of steps: =='
P T-703
