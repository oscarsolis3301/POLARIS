# next-own-folder: `next` answers for the caller's FOLDER (ops/contracts/smooth.md § 5.5) and a stale
# verdict is recomputed once (§ 5.6). Builder subagents share their conductor's session id, so a lock
# whose line 4 is "mine" used to send the conductor — standing in the primary — to "resume T-1130".
# `claim` and `resume` now write the card's worktree on lock meta line 6, and row 0 says resume only from
# inside it. A lock without line 6 keeps today's answer.
# HERMETIC, the handover-route pattern: a throwaway repo, its own board, the CLI run from INSIDE it.
# Paths print as <FIX>; nothing printed carries a sha, a time or a user name.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt; echo y > src/b.txt; echo z > src/c.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  printf '# fixture contract\n' > ops/contracts/fix.md
) >/dev/null 2>&1
cd "$FIX/repo"
export CLAUDE_CODE_SESSION_ID=nof-sid
L="$(git rev-parse --git-common-dir)/polaris-locks"
mk() { # mk <column> <id> <owned path>
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify: []\n---\n## Notes\n' \
    "$2" "$2" "$1" "$3" > "ops/board/$1/$2.md"
}
# at <dir> — `next`'s line 1 from <dir>, with $PWD in the shape a shell in a real repo gives it: git names
# folders C:/…, msys shells /c/… — the fold makes them one. (A mktemp /tmp would print /tmp/… instead,
# a mount alias no real repo has, so the shell's PWD is handed over explicitly.)
at() {
  local p="$1"
  case "$p" in [A-Za-z]:/*) p="/$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')/${p#?:/}";; esac
  ( cd "$1" && PWD="$p" bash "$KIT" next 2>&1 | sed -n 1p )
}

echo '--- 1. claim writes the worktree on lock meta line 6'
mk ready T-N1 src/a.txt
bash "$KIT" claim T-N1 2>&1 | grep -c '^✅ claimed T-N1'
printf 'meta lines: %s · line 6: %s\n' "$(wc -l < "$L/T-N1/meta" | tr -d ' ')" "$(sed -n 6p "$L/T-N1/meta" | sed 's#.*/repo/#<FIX>/repo/#')"
WT="$(sed -n 6p "$L/T-N1/meta")"
PR="${WT%/.polaris/wt/T-N1}"

echo '--- 2. the same session id: from the primary no resume, from the worktree (and below it) resume'
printf 'primary: %s\n' "$(at "$PR")"
printf 'worktree: %s\n' "$(at "$WT")"
mkdir -p "$WT/src/deep"
printf 'below it: %s\n' "$(at "$WT/src/deep")"
mkdir -p "$WT-x"
printf 'a sibling folder with the same prefix: %s\n' "$(at "$WT-x")"
rmdir "$WT-x"

echo '--- 3. line 6 folded: backslashes and another letter case still name the same folder'
w6="$(sed -n 6p "$L/T-N1/meta" | tr 'a-z' 'A-Z')"; w6="${w6//\//\\}"
{ sed -n 1,5p "$L/T-N1/meta"; printf '%s\n' "$w6"; } > "$L/T-N1/meta.new" && mv "$L/T-N1/meta.new" "$L/T-N1/meta"
printf 'worktree: %s · primary: %s\n' "$(at "$WT")" "$(at "$PR")"

echo '--- 4. a lock without line 6 (an older claim): today'"'"'s answer, from anywhere'
sed -n 1,5p "$L/T-N1/meta" > "$L/T-N1/meta.new" && mv "$L/T-N1/meta.new" "$L/T-N1/meta"
printf 'primary: %s\n' "$(at "$PR")"

echo '--- 5. resume rewrites the lock with line 6 again'
( cd "$WT" && bash "$KIT" resume T-N1 >/dev/null 2>&1 )
printf 'meta lines: %s · primary: %s · worktree: %s\n' "$(wc -l < "$L/T-N1/meta" | tr -d ' ')" "$(at "$PR")" "$(at "$WT")"

echo '--- 6. a stale verdict on a quiet board: next and bare triage recompute it once and answer from the fresh one'
bash "$KIT" release T-N1 --to ready >/dev/null 2>&1
mkdir -p .polaris
B="$(git rev-parse main)"; OLD="$(git rev-parse main~1)"
fresh() { # what the refresh left: does field 1 name the base now, and field 2 (0 = due, 1 = not)
  printf 'tune-due names the base: %s · due field: %s\n' \
    "$([ "$(cut -f1 .polaris/tune-due | tr -d '\r')" = "$B" ] && echo yes || echo no)" "$(cut -f2 .polaris/tune-due | tr -d '\r')"
}
stale() { printf '%s\t%s\t%s\t%s\n' "$OLD" "$1" "$2" "$3" > .polaris/tune-due; rm -f .polaris/hops-due; }
# a stale DUE verdict for the old base, the fresh one not due: the usual answer
stale 0 2 cards,layout
printf 'next: %s\n' "$(CLAUDE_CODE_SESSION_ID=nof-s1 bash "$KIT" next 2>&1 | sed -n 1p)"
fresh
stale 0 2 cards,layout
printf 'triage: %s\n' "$(CLAUDE_CODE_SESSION_ID=nof-s2 bash "$KIT" triage 2>&1 | sed -n 1p)"
fresh
# a chain of two waiting cards is what tune calls due (tune.md § 1, "cards"): a stale NOT-due verdict
# for the old base is recomputed, and the fresh, due one sends the session to the tune-up
mkc() { # mkc <id> <depends_on> <owned path>
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nplan: ch\nowner: null\nbranch: null\nstatus: backlog\ncontract: ops/contracts/fix.md\ndepends_on: [%s]\nfiles_owned:\n  - %s\nverify: []\n---\n## Notes\n' \
    "$1" "$1" "$2" "$3" > "ops/board/backlog/$1.md"
}
mkc T-C1 "" src/b.txt; mkc T-C2 T-C1 src/c.txt
stale 1 0 -
printf 'next: %s\n' "$(CLAUDE_CODE_SESSION_ID=nof-s5 bash "$KIT" next 2>&1 | sed -n 1,2p | tr '\n' '|')"
fresh
stale 1 0 -
printf 'triage: %s\n' "$(CLAUDE_CODE_SESSION_ID=nof-s6 bash "$KIT" triage 2>&1 | sed -n 1,2p | tr '\n' '|')"
fresh

echo '--- 7. --brief, or a card in flight: the stale verdict is left alone'
stale 0 2 cards,layout
CLAUDE_CODE_SESSION_ID=nof-s3 bash "$KIT" next --brief >/dev/null 2>&1
printf 'after --brief: %s\n' "$([ "$(cut -f1 .polaris/tune-due)" = "$OLD" ] && echo untouched || echo REWRITTEN)"
bash "$KIT" claim T-N1 >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID=nof-s4 bash "$KIT" next >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID=nof-s4 bash "$KIT" triage >/dev/null 2>&1
printf 'with a card active: %s\n' "$([ "$(cut -f1 .polaris/tune-due)" = "$OLD" ] && echo untouched || echo REWRITTEN)"
