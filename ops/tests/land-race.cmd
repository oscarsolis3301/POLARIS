# land-race — four lanes land themselves at the same moment, and none of them gets lost
# (ops/contracts/safe-landing.md § 8 as corrected by v1.1 § A).
#
# The reported failure: about four lanes self-landed within two minutes and some tasks ended in done/
# with their code absent from main. This drives exactly that path — four disjoint tasks claimed one by
# one, one commit each, then all four `handoff` calls released together (a start gate) under
# `landing: self`, so every lane runs self_land's real tail (land, then seal and done for whoever is
# last out). The .cmd never changes when the landing path is fixed; only the actual output moves.
# Pinned (the GREEN outcome): each task is in done/ and main's file byte-equals its feat tip (the tip
# blob recorded before any done can delete the branch) · exactly one wave was opened · nothing is left
# unsealed. RED before safe-landing B/C is expected and written into the contract.
#
# HERMETIC (the self-land-finish pattern): ONE throwaway repo under mktemp -d, no remote, no session
# id, HOME and USERPROFILE faked together, the CLI run from INSIDE the fixture, a sprint header (the
# self-land refuses without one), test_select unset, and an ancestor suite stamp. Output carries no
# sha, path, time or user.
unset CLAUDE_CODE_SESSION_ID
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home" "$FIX/out"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
IDS="T-1 T-2 T-3 T-4"
fof() { echo "src/$(echo "$1" | tr -d 'T-').txt"; }   # T-3 → src/3.txt
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src
  for id in $IDS; do echo x > "$(fof "$id")"; done
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: self\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf '# SPRINT 1 — race  capacity: 20\n' > ops/SPRINT.md
  for id in $IDS; do
    f="$(fof "$id")"
    printf -- '---\nid: %s\ntitle: lane %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify:\n  - grep -q y %s\n---\n## Why\nlane %s.\n' \
      "$id" "$id" "$f" "$f" "$id" > "ops/board/ready/$id.md"
  done
  git add -A; git commit -qm board
  mkdir -p .polaris
  printf '%s %s full\n' "$(git rev-parse HEAD)" "$(date +%s)" > .polaris/suite-stamp
) >/dev/null 2>&1
cd "$R"
col() { for c in backlog ready active review done blocked; do [ -f "ops/board/$c/$1.md" ] && { echo "$c"; return; }; done; echo none; }
BASEMERGES="$(git rev-list --merges --first-parent --count main 2>/dev/null || echo 0)"

# Claim one by one, one commit per worktree, and record each feat tip's blob before anything lands.
for id in $IDS; do
  f="$(fof "$id")"
  bash "$KIT" claim "$id" >/dev/null 2>&1
  ( cd "$R/.polaris/wt/$id" && echo y > "$f" && git commit -qam "feat: $id the edit" ) >/dev/null 2>&1
  git rev-parse "feat/$id:$f" > "$FIX/out/$id.tip" 2>/dev/null
done

# The start gate: every lane waits on one file, so all four handoffs begin together.
for id in $IDS; do
  ( while [ ! -f "$FIX/go" ]; do sleep 0.1 2>/dev/null || sleep 1; done
    cd "$R/.polaris/wt/$id" && bash "$KIT" handoff "$id" > "$FIX/out/$id.log" 2>&1 ) &
done
sleep 1
: > "$FIX/go"
wait

# Facts only.
for id in $IDS; do
  f="$(fof "$id")"
  tip="$(cat "$FIX/out/$id.tip" 2>/dev/null)"
  got="$(git rev-parse -q --verify "main:$f" 2>/dev/null || true)"
  if [ -n "$tip" ] && [ "$tip" = "$got" ]; then v=OK; else v=LOST; fi
  echo "$id $(col "$id") $v"
done
SEALED=$(( $(git rev-list --merges --first-parent --count main 2>/dev/null || echo 0) - BASEMERGES ))
OPEN=0
for br in $(git for-each-ref --format='%(refname:short)' 'refs/heads/integrate/*'); do
  git merge-base --is-ancestor "$br" main 2>/dev/null || OPEN=$((OPEN+1))
done
echo "waves: $((SEALED + OPEN))"
echo "leftover-unsealed: $OPEN"
