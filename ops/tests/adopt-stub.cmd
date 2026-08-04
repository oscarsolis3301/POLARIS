# `adopt` is the DISCOVERY half of the key registry (ops/contracts/key-registry.md § 3): it may
# append COMMENTED stubs to the END of ops/CONVENTIONS.md and do NOTHING else — never edit an
# existing line, never uncomment, never reorder, never write a live value. This golden pins that
# whole promise byte-for-byte: the two dies name their remedies, the first run appends marker +
# stubs in KEYS.tsv order, a pre-existing live value and a pre-existing stub survive untouched,
# and a second run is a byte-identical no-op.
#
# HERMETIC BY CONSTRUCTION (the T-062 pattern, same as route-tier/triage-lane): a fixture repo
# with a fixture ops/KEYS.tsv of FAKE keys and FAKE since-versions, run from INSIDE it — polaris
# anchors to the worktree-list primary, which becomes the fixture. So the REAL registry can grow,
# and real kit versions can move, without ever redding this file.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  echo x > a.txt; git add -A; git commit -qm init
  mkdir -p ops
) >/dev/null 2>&1
A() { ( cd "$FIX/repo" && bash "$KIT" adopt 2>&1 ); printf 'rc %s\n' "$?"; }

echo '== no ops/KEYS.tsv: die names the remedy =='
A

printf 'fake_live\t0.1\tmain\ta live value already set here\n' >  "$FIX/repo/ops/KEYS.tsv"
printf 'fake_stub\t0.2\toff\ta stub already written here\n'   >> "$FIX/repo/ops/KEYS.tsv"
printf '# comment rows and blank rows are ignored\n\n'        >> "$FIX/repo/ops/KEYS.tsv"
printf 'fake_alpha\t0.3\ton\tfirst absent fake key\n'         >> "$FIX/repo/ops/KEYS.tsv"
printf 'fake_beta\t0.4\t7\tsecond absent fake key\n'          >> "$FIX/repo/ops/KEYS.tsv"

echo '== no ops/CONVENTIONS.md: die points at INIT, never creates the file =='
A

printf 'fake_live: main   # the human set this\n'                  >  "$FIX/repo/ops/CONVENTIONS.md"
printf '# fake_stub: off   # known and deliberately unset\n'       >> "$FIX/repo/ops/CONVENTIONS.md"
printf 'prose the human wrote below the keys stays put\n'          >> "$FIX/repo/ops/CONVENTIONS.md"

echo '== first run: one stub per absent key, KEYS.tsv order =='
A

echo '== the file after: marker once at the end, live value + stub byte-untouched =='
cat "$FIX/repo/ops/CONVENTIONS.md"

cp "$FIX/repo/ops/CONVENTIONS.md" "$FIX/after-first"
echo '== second run: nothing to adopt =='
A
if cmp -s "$FIX/after-first" "$FIX/repo/ops/CONVENTIONS.md"; then
  echo 'file byte-identical after second run'
else
  echo 'FILE CHANGED ON SECOND RUN'
fi
