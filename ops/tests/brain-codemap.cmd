# brain-codemap — the knowledge base's code map, built in one pass (ops/contracts/minutes.md § 4,
# brain.md v3): one file listing, one symbol search and one awk print every folder of the practice
# shop in a pinned order — folders in C byte order, the top three extensions by count with ties
# ascending, the first twelve symbols in C byte order — and every brain file is moved into place
# from a temp file beside it, so none is ever left behind.
# The shop (hops_fixture, sourced read-only from kit/ops/lib/selftest/hops.sh) gets four more
# folders: one with a guide (CLAUDE.md), one with a README, one whose two extensions tie, and one
# with more than twelve symbols. A MAP names two hotspots in lib/many/ (the first one wins) and one
# at the root.
#
# HERMETIC: the shop under mktemp -d with HOME and USERPROFILE faked together; the kit's polaris
# runs from inside it, so no live board or brain is ever read or written.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/shop"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
mkdir -p "$HOME"
bash -c '. kit/ops/lib/selftest/hops.sh; hops_fixture "$1"' _ "$R" >/dev/null 2>&1
( set -e
  cd "$R"
  mkdir -p docs/guide docs/readme tools/tied lib/many
  printf '<!-- polaris:guide -->\n# docs/guide/ — how the shop is laid out\n<!-- /polaris:guide -->\n' > docs/guide/CLAUDE.md
  printf 'notes\n' > docs/guide/notes.txt
  printf 'intro\n\n## The shop readme folder\n\n# a later heading\n' > docs/readme/README.md
  printf 'x\n' > tools/tied/b.yml; printf 'x\n' > tools/tied/a.yml
  printf 'x\n' > tools/tied/c.cfg; printf 'x\n' > tools/tied/d.cfg
  for n in zeta alpha mike delta kilo bravo lima echo juliet charlie india golf hotel foxtrot; do
    printf '%s() {\n  :\n}\n' "$n"
  done > lib/many/funcs.sh
  printf 'def zulu():\n    pass\nclass Yankee:\n    pass\nfunction xray() {\n}\n' > lib/many/more.py
  printf '# MAP\n\n## Hotspots\n- `lib/many/funcs.sh` and `lib/many/more.py`\n- `package.json`\n\n## Deltas\n- `src/App.tsx`\n' > ops/MAP.md
  git add -A
  git commit -qm 'shop: four folders the code map reads'
) >/dev/null 2>&1
cd "$R"
bash "$KIT" brain --refresh >/dev/null 2>&1 || echo "brain --refresh failed"
tr -d '\r' < .polaris/brain/code-map.md
printf 'brain files: %s\n' "$(ls .polaris/brain | grep -c '\.md$')"
printf 'temp files left: %s\n' "$(ls -a .polaris/brain | grep -c '\.tmp\.')"
