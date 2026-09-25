# qa's suite stamp when something besides the suite is red (ops/contracts/speed.md § 4, T-179).
#
# A green suite is a fact about a COMMIT. A leftover branch (CRUFT) says nothing about that commit,
# so it keeps the stamp — qa still exits 1 on it, but the next qa at the same HEAD runs no suite key.
# MAP Deltas > 20 and LEARNED > 8 stay HARD gates: rc 1 and no stamp, exactly like a red suite.
#
# HERMETIC: a throwaway repo under mktemp -d, the CLI run from INSIDE it — polaris anchors to the
# fixture's own primary — so no live-board write can ever red this golden. Every qa below runs on a
# CLEAN tree (clean=yes pins it): a dirty tree withholds the stamp on its own, and a no-stamp line
# would then prove nothing. Nothing printed carries a sha, a path, a time or a user.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
  # T-9 is done but its branch carries a commit nobody merged: CRUFT diverged, which qa never
  # clears — so it stays red across both qa runs below. Plumbing only: the tree never moves.
  git branch -f feat/T-9 "$(git commit-tree "$(git rev-parse 'main^{tree}')" -p main -m 'feat: T-9 unlanded')"
  printf -- '---\nid: T-9\npoints: 1\nstatus: done\n---\n' > ops/board/done/T-9.md
) >/dev/null 2>&1
cd "$FIX/repo"
qa() { # qa <label> — ONE qa run, reported as facts: rc · stamp (HEAD | none | other) · how many
  # suite keys ran · whether the suite was skipped · the tree clean · then the ⚠ findings verbatim.
  OUT="$(bash "$KIT" qa 2>&1)"; RC=$?
  if [ ! -f .polaris/suite-stamp ]; then ST=none
  elif [ "$(cut -d' ' -f1 < .polaris/suite-stamp)" = "$(git rev-parse HEAD)" ]; then ST=HEAD
  else ST=other; fi
  printf '%s: rc=%s stamp=%s suite-ran=%s skipped=%s clean=%s\n' "$1" "$RC" "$ST" \
    "$(printf '%s\n' "$OUT" | grep -cE '(test|lint|typecheck|build|uat) — (green|RED)')" \
    "$(printf '%s\n' "$OUT" | grep -c 'suite already green at')" \
    "$( [ -z "$(git status --porcelain)" ] && echo yes || echo no)"
  printf '%s\n' "$OUT" | sed -n 's/^ *\(⚠ \[[0-9]*\] .*\)$/  \1/p' | sed -E 's/[0-9]+ (delta lines|bullets)/N \1/'
}
# 1) suite green, the only other red CRUFT-class → stamp = HEAD, still rc 1.
qa cruft-only
# 2) same HEAD, same CRUFT red → the suite is skipped: no suite key runs at all.
qa cruft-again
# 3) MAP Deltas > 20 is a hard gate: suite green, rc 1, NO stamp. (The CRUFT goes first, so MAP is
#    the only non-suite red.)
git branch -q -D feat/T-9; rm -f ops/board/done/T-9.md .polaris/suite-stamp
i=0; while [ "$i" -lt 21 ]; do i=$((i+1)); printf -- '- delta %s (T-M, 2026-09-24)\n' "$i" >> ops/MAP.md; done
git add -A >/dev/null 2>&1; git commit -qm map >/dev/null 2>&1
qa map-overflow
# 4) LEARNED > 8 the same. SPRINT.md is gitignored on base, so the tree stays clean.
git reset -q --hard HEAD~1; rm -f .polaris/suite-stamp
{ printf '# SPRINT 1 — fixture\n\n## Learned\n'; i=0; while [ "$i" -lt 9 ]; do i=$((i+1)); printf -- '- lesson %s\n' "$i"; done; } > ops/SPRINT.md
qa learned-overflow
# 5) a red suite is never stamped — the one red that no other verdict can outweigh.
rm -f ops/SPRINT.md
printf 'test: false\n' > ops/CONVENTIONS.md; git add -A >/dev/null 2>&1; git commit -qm red >/dev/null 2>&1
qa suite-red
