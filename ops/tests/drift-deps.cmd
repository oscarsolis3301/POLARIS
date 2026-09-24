# drift's dependency pass and branch checks (ops/contracts/speed.md § 3, T-177).
#
# HERMETIC: a throwaway repo under mktemp -d, the CLI run from INSIDE it — polaris anchors to the
# fixture's own primary — so no live-board write can ever red this golden. Pins, byte for byte and
# in section order, the § 3 lines: CRUFT · CRUFT diverged (the branch walk) and DEP MISSING ·
# DEP CYCLE (the one-pass awk), plus the ADVISORY orphan line that drift prints but never counts.
# Then the orphan alone: the verdict stays "board clean" and --strict stays rc 0.
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
  git add -A; git commit -qm board
  # T-1 depends on a task that exists nowhere (flow list); T-2 and T-3 depend on each other (block
  # lists) — a ring neither can ever leave.
  printf -- '---\nid: T-1\npoints: 1\nstatus: backlog\ndepends_on: [T-404]\n---\n' > ops/board/backlog/T-1.md
  printf -- '---\nid: T-2\npoints: 1\nstatus: backlog\ndepends_on:\n  - T-3\n---\n' > ops/board/backlog/T-2.md
  printf -- '---\nid: T-3\npoints: 1\nstatus: backlog\ndepends_on:\n  - T-2\n---\n' > ops/board/backlog/T-3.md
  # T-8 is done and its branch tip IS its squash's Landed-from trailer: clearable CRUFT. Plumbing
  # only — the landed commit carries main's own tree, so the working tree never moves.
  tree="$(git rev-parse 'main^{tree}')"
  c8="$(git commit-tree "$tree" -p main -m 'feat: T-8 work')"
  git branch -f feat/T-8 "$c8"
  l8="$(printf 'feat(src): drift drill [T-8]\n\nLanded-from: %s\n' "$c8" | git commit-tree "$tree" -p main)"
  git update-ref refs/heads/main "$l8"
  printf -- '---\nid: T-8\npoints: 1\nstatus: done\nlanded: %s\n---\n' "$l8" > ops/board/done/T-8.md
  # T-9 is done but its branch carries a commit nobody merged: CRUFT diverged.
  git branch -f feat/T-9 "$(git commit-tree "$tree" -p main -m 'feat: T-9 unlanded')"
  printf -- '---\nid: T-9\npoints: 1\nstatus: done\n---\n' > ops/board/done/T-9.md
  # feat/T-1's task is on the board, so it is live work and never a line; feat/stray matches no
  # task in any column: the advisory.
  git branch -f feat/T-1 main
  git branch -f feat/stray main
) >/dev/null 2>&1
( cd "$FIX/repo" && bash "$KIT" drift 2>/dev/null )
( cd "$FIX/repo" && bash "$KIT" drift --strict >/dev/null 2>&1 ); echo "strict-rc=$?"
# The orphan alone: printed, never counted — same clean verdict, same rc 0.
rm -f "$FIX/repo/ops/board/backlog/T-1.md" "$FIX/repo/ops/board/backlog/T-2.md" "$FIX/repo/ops/board/backlog/T-3.md" \
      "$FIX/repo/ops/board/done/T-8.md" "$FIX/repo/ops/board/done/T-9.md"
git -C "$FIX/repo" branch -q -D feat/T-1 feat/T-8 feat/T-9 >/dev/null 2>&1
( cd "$FIX/repo" && bash "$KIT" drift 2>/dev/null )
( cd "$FIX/repo" && bash "$KIT" drift --strict >/dev/null 2>&1 ); echo "strict-rc=$?"
