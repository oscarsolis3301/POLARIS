# depth-stamp — T-198 wires depth_for into qa (ops/contracts/test-depth.md § 4-5): a docs-only or
# CSS-only commit after a green stamp runs NO suite key, the stamp still carries forward (its sha
# moves to the new HEAD, proven none/look), and every qa that actually reached a depth verdict
# appends one decisions.ndjson row carrying every § 5 key.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, run from INSIDE it — polaris anchors to the
# fixture's own primary — so no live board, CONVENTIONS or decisions.ndjson can ever red this
# golden, and running this twice from ANY state is byte-identical.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src docs
  echo 'code v1' > src/a.dat
  echo 'doc v1'  > docs/readme.md
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\nlint: true\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
qa() { # qa <label> — ONE qa run, reported as facts: rc · stamp sha vs HEAD · stamp scope ·
  # how many suite keys actually ran · any `depth:` line qa printed.
  OUT="$(bash "$KIT" qa 2>&1)"; RC=$?
  if [ ! -f .polaris/suite-stamp ]; then STSHA=none; STSC=none
  else
    read -r stsha _ STSC < .polaris/suite-stamp
    if [ "$stsha" = "$(git rev-parse HEAD)" ]; then STSHA=HEAD; else STSHA=other; fi
  fi
  printf '%s: rc=%s stamp=%s scope=%s suite-ran=%s\n' "$1" "$RC" "$STSHA" "${STSC:-none}" \
    "$(printf '%s\n' "$OUT" | grep -cE '(test|lint|typecheck|build|uat) — green')"
  printf '%s\n' "$OUT" | sed -n 's/^ *\(depth: .*\)$/  \1/p'
}
# 1) an unbounded first run (no stamp yet) never consults depth_for — the whole suite runs, exactly
#    as before T-198 — and this establishes the green baseline the next two steps carry forward.
qa baseline
# 2) a docs-only commit ⇒ depth: none — no suite key runs, the stamp still carries to the new HEAD.
echo 'doc v2' > docs/readme.md; git commit -qam 'docs: v2'
qa docs-only
# 3) same HEAD again, clean tree ⇒ the ORDINARY stamp-skip path fires first — no depth line at all,
#    because the gate never runs once the suite is already proven at this exact commit.
qa docs-again
# 4) a CSS-only commit ⇒ depth: look — same no-suite-key behaviour, the stamp field becomes look.
echo 'body{color:red}' > style.css; git add -A; git commit -qm 'style: v1'
qa css-only
# decisions.ndjson (§ 5): one row per qa that reached a depth — steps 2 and 4 only (1 was
# unbounded, 3 never ran the gate) — each row carrying every key the contract names.
echo "decisions rows: $(grep -c . .polaris/decisions.ndjson 2>/dev/null || echo 0)"
for k in ts plan task kind depth why paths secs rc; do
  printf '%s present in every row: %s\n' "$k" \
    "$([ "$(grep -c "\"$k\":" .polaris/decisions.ndjson 2>/dev/null || echo 0)" = "$(grep -c . .polaris/decisions.ndjson 2>/dev/null || echo 0)" ] && echo yes || echo no)"
done
grep -o '"depth":"[a-z]*"' .polaris/decisions.ndjson
