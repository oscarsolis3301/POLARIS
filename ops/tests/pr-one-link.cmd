# pr-one-link — T-229 (ops/contracts/publish-modes.md § v2 "one link per run").
#
# Under `publish: pr` a whole run now reaches origin as ONE link: tasks claim -> build -> land ->
# done LOCALLY (the seal stages on local main and pushes nothing), and `finish` fast-forwards local
# main to origin's ship/<date>, prints exactly one Bitbucket link and exits 0. This golden walks it:
#   1) a pr-mode board no longer forces the `full` lane (triage answers solo);
#   2) three CHAINED tasks reach done/ with no human step, each seeing the earlier code;
#   3) origin gained nothing yet; `finish` -> rc 0, ONE link, origin gains ONLY ship/<date>;
#   4) the human merges the PR on the host (a merge commit); `triage` then syncs silently;
#   5) a new run ships to a fresh branch; a second, unmerged run FAST-FORWARDS that same branch.
#
# HERMETIC: a throwaway repo + a throwaway bare origin under mktemp -d (its path contains
# bitbucket.org so the remote parses as Bitbucket), run from INSIDE the fixture. The origin's
# pre-receive rejects any push to main unless HOST_MERGE is set, which only the simulated human
# uses. Nothing printed carries a sha, a path, a time or a user.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
OR="$FIX/bitbucket.org/acme/arc.git"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\npublish: pr\n' > ops/CONVENTIONS.md
  printf '# SPRINT 1 - one link  capacity: 5\n' > ops/SPRINT.md
  git add -A; git commit -qm board
  mkdir -p "$OR"; git init -q --bare "$OR"
  git remote add origin "$OR"
  git push -q origin main
  printf '#!/bin/sh\nwhile read old new ref; do\n  if [ "$ref" = "refs/heads/main" ] && [ -z "$HOST_MERGE" ]; then echo "protected branch" >&2; exit 1; fi\ndone\nexit 0\n' > "$OR/hooks/pre-receive"
  chmod +x "$OR/hooks/pre-receive"
) >/dev/null 2>&1
cd "$R"
D="$(date +%F)"
Q() { sed "s#$D#<date>#g"; }
task() { # task <n> <depends|-> — file T-<n> in ready/, owning src/f<n>.txt
  local dep=""; [ "$2" != "-" ] && dep="depends_on:
  - $2
"
  printf -- '---\nid: T-%s\ntitle: chained task %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\n%sfiles_owned:\n  - src/f%s.txt\nverify: []\n---\n' "$1" "$1" "$dep" "$1" > "ops/board/ready/T-$1.md"
}
build() { # build <n> — claim, write the file in the worktree (proving the earlier file is visible), hand off
  bash "$KIT" claim "T-$1" >/dev/null 2>&1
  ( set -e; cd ".polaris/wt/T-$1"
    [ "$1" = 1 ] || ls src/f*.txt >/dev/null
    echo "built $1" > "src/f$1.txt"; git add -A; git commit -qm "feat: T-$1 chained"
    bash "$KIT" handoff "T-$1" >/dev/null 2>&1 ) || true
  printf 'T-%s: done=%s\n' "$1" "$([ -f "ops/board/done/T-$1.md" ] && echo yes || echo no)"
}
refs() { git ls-remote origin 2>/dev/null | awk '{print $2}' | grep -v 'polaris/board' | grep -v 'refs/tags/' | sort | Q; }
printf '# fixture contract\n' > ops/contracts/fix.md; git add -A >/dev/null 2>&1; git commit -qm contract >/dev/null 2>&1
M0="$(git ls-remote origin refs/heads/main | cut -f1)"

echo "== 1 triage under publish: pr =="
task 1 -
bash "$KIT" triage 2>&1 | sed -n 1p

echo "== 2 three chained tasks, no human step =="
build 1
task 2 T-1; build 2
task 3 T-2; build 3
echo "local main moved: $([ "$(git rev-parse main)" != "$M0" ] && echo yes || echo no)"
echo "files on main: $(git ls-tree --name-only main src/ | grep -c 'f[123]\.txt')"
echo "origin so far:"; refs | sed 's/^/  /'

echo "== 3 finish ships one link =="
OUT="$(bash "$KIT" finish 2>&1)"; echo "finish rc=$?"
printf '%s\n' "$OUT" | grep -c 'pull-requests/new'
printf '%s\n' "$OUT" | grep 'pull-requests/new' | Q
echo "origin now:"; refs | sed 's/^/  /'
echo "origin main untouched: $([ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$M0" ] && echo yes || echo no)"
echo "ship == local main: $([ "$(git ls-remote origin "refs/heads/ship/$D" | cut -f1)" = "$(git rev-parse main)" ] && echo yes || echo no)"
echo "ship recorded: $(cat .polaris/ship 2>/dev/null | Q)"

echo "== 4 the human merges, triage syncs =="
git clone -q -b main "$OR" "$FIX/host" >/dev/null 2>&1
( set -e; cd "$FIX/host"; git config user.email h@h; git config user.name h; git fetch -q origin
  git merge -q --no-ff "origin/ship/$D" -m 'Merged in ship (pull request #1)'
  HOST_MERGE=1 git push -q origin main ) >/dev/null 2>&1
bash "$KIT" triage >/dev/null 2>&1
echo "local main == origin main: $([ "$(git rev-parse main)" = "$(git ls-remote origin refs/heads/main | cut -f1)" ] && echo yes || echo no)"
echo "origin now:"; refs | sed 's/^/  /'

echo "== 5 a second run, then a third that is not merged yet =="
task 4 -; build 4
OUT="$(bash "$KIT" finish 2>&1)"; echo "finish rc=$?"
printf '%s\n' "$OUT" | grep -c 'pull-requests/new'
S1="$(git ls-remote origin "refs/heads/ship/$D" | cut -f1)"
task 5 T-4; build 5
OUT="$(bash "$KIT" finish 2>&1)"; echo "finish rc=$?"
printf '%s\n' "$OUT" | grep -c 'pull-requests/new'
S2="$(git ls-remote origin "refs/heads/ship/$D" | cut -f1)"
echo "same branch moved forward: $([ "$S1" != "$S2" ] && git merge-base --is-ancestor "$S1" "$S2" && echo yes || echo no)"
echo "ship branches on origin: $(refs | grep -c 'refs/heads/ship/')"
echo "origin main untouched since the merge: $([ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$(git -C "$FIX/host" rev-parse main)" ] && echo yes || echo no)"
