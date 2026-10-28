# ONE YES, the callers (ops/contracts/one-yes.md section 2): `next` and `land --express` ask the SAME
# predicate, plan_covers, that self_land asks. A plan-approved risk: high task is landable and passes
# the express gate; the same task unapproved is the human lane and express refuses; autonomy: standard
# refuses even with the approval. HERMETIC: a throwaway repo built with mktemp -d; the live board is
# never touched. Express is proved to have PASSED the gate by `express: off` speaking next (the knob
# is checked right after plan_covers), so nothing is ever landed.
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
  mk() { # mk <id> <risk> <plan>
    printf -- '---\nid: %s\ntitle: fixture\ntype: feature\npoints: 1\nwsjf: 5\nrisk: %s\nplan: %s\nowner: null\nbranch: null\nstatus: review\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\napproved: []\nverify: []\n---\n' "$1" "$2" "$3" "$1" > "ops/board/review/$1.md"
  }
  mk T-1 high p
  printf 'autonomy: trusted\nexpress: off\n' > ops/CONVENTIONS.md
) >/dev/null 2>&1
cd "$R"
export CLAUDE_CODE_SESSION_ID=gates-sid
nx() { bash "$KIT" next 2>&1 | sed -n '1,3p'; }
ex() { bash "$KIT" land --express T-1 2>&1 | sed 's/^[^a-z]*//' | sed -n 1p | sed 's/ — .*//'; }
echo "== unapproved: human lane, express refuses"
nx
ex
echo "== approve --plan p"
bash "$KIT" approve --plan p -m "the plan, approved" >/dev/null 2>&1
echo "== approved: landable, express passes the gate (the knob speaks next)"
nx
ex
echo "== autonomy: standard refuses even with the approval"
printf 'autonomy: standard\nexpress: off\n' > ops/CONVENTIONS.md
nx
ex
