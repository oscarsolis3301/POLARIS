# ONE YES at the plan gate (ops/contracts/one-yes.md sections 1-2): `approve --plan <slug> -m` records the
# owner's approval on every task of the plan, and ONE predicate, plan_covers, reads those entries
# back. HERMETIC: the whole drill runs in a throwaway repo built with mktemp -d; the live board is
# never touched, so running it twice from any board state is byte-identical.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  printf '# fixture contract\n' > ops/contracts/fix.md
  mk() { # mk <id> <risk> <plan> <needs-line>
    printf -- '---\nid: %s\ntitle: fixture\ntype: feature\npoints: 1\nwsjf: 5\nrisk: %s\nplan: %s\n%sowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\napproved: []\nverify: []\n---\n' "$1" "$2" "$3" "$4" "$1" > "ops/board/ready/$1.md"
  }
  mk T-1 high  p ''
  mk T-2 normal p 'needs: [schema]
'
  mk T-3 normal p 'needs: [bogus]
'
  mk T-4 normal q ''
  printf -- '---\nid: T-5\ntitle: noapproved\ntype: feature\npoints: 1\nrisk: normal\nplan: p\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nneeds: [delete]\nfiles_owned:\n  - src/T-5.txt\nverify: []\n---\n' > ops/board/ready/T-5.md
  printf 'autonomy: trusted\n' > ops/CONVENTIONS.md
) >/dev/null 2>&1
cd "$R"
snap() { { find ops/board -type f | sort | xargs cat; git rev-parse refs/heads/polaris/board 2>/dev/null || echo noref; } | cksum; }
norm() { sed -E 's/, [0-9]{4}-[0-9]{2}-[0-9]{2}: plan/, DATE: plan/; s/ — [^,]+, DATE/ — WHO, DATE/'; }
cov() { # cov <label> <ID> — rc + the one reason line
  out="$(bash "$KIT" _plan_covers "$2" 2>&1)"; rc=$?
  printf '%s %s rc=%s %s\n' "$1" "$2" "$rc" "$out"
}
refuse() { # refuse <label> <args…> — the refusal text, rc, and whether the board moved
  local before after out rc=0
  before="$(snap)"
  out="$(bash "$KIT" approve "${@:2}" 2>&1)" || rc=$?
  after="$(snap)"
  printf '%s: rc=%s %s | board %s\n' "$1" "$rc" "$(printf '%s' "$out" | sed 's/ — .*//' | head -1)" "$([ "$before" = "$after" ] && echo identical || echo CHANGED)"
}
echo "== before approval"
cov unapproved T-1
cov unapproved T-2
cov plain T-4
echo "== refusals mutate nothing"
refuse no-m --plan p
refuse unknown-slug --plan nope -m why
refuse positional --plan p T-1 merge -m why
git checkout -q -b feat/T-9
refuse feat-branch --plan p -m why
git checkout -q main
echo "== approve --plan p"
bash "$KIT" approve --plan p -m "the plan, approved" 2>&1 | sed 's/^[^a]*approved plan/approved plan/' | grep -E 'approved plan|skipped'
echo "== after approval"
cov covered T-1
cov covered T-2
cov unknown-needs T-3
cov other-plan T-4
cov needs-delete T-5
grep -h -A1 '^approved:' ops/board/ready/T-1.md ops/board/ready/T-2.md | grep -v '^--' | norm
git log -1 --format=%s refs/heads/polaris/board
grep -c '"ev":"approve-plan"' ops/board/EVENTS.ndjson
echo "== idempotent re-run"
b="$(snap)"
bash "$KIT" approve --plan p -m "again" 2>&1 | grep 'approved plan' | sed 's/^[^a]*approved plan/approved plan/'
[ "$b" = "$(snap)" ] && echo "board identical" || echo "board CHANGED"
echo "== a hand approval is not a plan entry"
sed -i 's/^approved: \[\]/approved: [src\/T-4.txt — hand, 2026-01-01: by hand]/' ops/board/ready/T-4.md
cov hand T-4
echo "== autonomy: standard keeps the per-merge stop"
printf 'autonomy: standard\n' > ops/CONVENTIONS.md
cov standard T-1
printf 'autonomy: trusted\n' > ops/CONVENTIONS.md
cov trusted T-1
