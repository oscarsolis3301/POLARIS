# A folder named like the base branch must not blind the landed-work lookups (T-184).
#
# A real install had a `main/` folder. git then refuses a BARE branch argument — "ambiguous
# argument 'main': both revision and filename", rc 128 — and every lookup hides stderr, so each one
# quietly came back empty and POLARIS silently missed work that had landed. The fix is a trailing
# ` --` after the ref. This fixture has a `main` branch AND a tracked `main/` folder, and each probe
# below goes blind on its own if its ONE lookup loses the ` --`:
#   history           the plain first-parent log of base            (integrate.sh cmd_history)
#   history --tasks 1 the OLDEST "Sprint 1 — " wave, so both waves  (integrate.sh cmd_history)
#                     show — blind, it starts at the tag: wave two only
#   report T-2 listed T-2 has no landed: stamp, so only the sprint  (knowledge.sh resolve_sprint_ids)
#                     merge bullets can name it
#   report T-2 landed its sha and files come from the [T-2] subject (integrate.sh landed_sha)
#                     lookup — blind, they fall back to files_owned
# T-1 carries a landed: stamp, so it is the control: it reads the same either way.
#
# HERMETIC: a throwaway repo under mktemp -d, the CLI run from INSIDE it — polaris anchors to the
# fixture's own primary — so no live-board write can ever red this golden. Fixture dates are pinned;
# shas are masked, so nothing printed carries a sha, a path, a time or a user.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  export GIT_AUTHOR_DATE='2026-01-01T12:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T12:00:00 +0000'
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src main; echo x > src/a.txt; echo x > main/keep.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  # Two waves of sprint 1, each a first-parent merge whose body bullet names its task; the tag marks
  # the LATEST wave, as seal leaves it.
  git checkout -q -b integrate/a
  echo one > src/one.txt; git add -A; git commit -qm 'feat(src): one [T-1]'
  git checkout -q main --
  git merge -q --no-ff --no-edit integrate/a
  git commit -q --amend -m 'Sprint 1 — wave one' -m '- one [T-1]'
  git checkout -q -b integrate/b
  echo two > src/two.txt; git add -A; git commit -qm 'feat(src): two [T-2]'
  git checkout -q main --
  git merge -q --no-ff --no-edit integrate/b
  git commit -q --amend -m 'Sprint 1 — wave two' -m '- two [T-2]'
  git tag sprint/1
  git branch -q -D integrate/a integrate/b
  printf '# SPRINT 1 — fixture\n' > ops/SPRINT.md
  printf -- '---\nid: T-1\ntitle: one\npoints: 1\nrisk: normal\nstatus: done\nlanded: %s\nfiles_owned:\n  - src/one.txt\n---\n' \
    "$(git rev-parse 'main^1^2')" > ops/board/done/T-1.md
  # T-2's files_owned names a file it never touched: only the landed-commit lookup finds src/two.txt.
  printf -- '---\nid: T-2\ntitle: two\npoints: 1\nrisk: normal\nstatus: done\nfiles_owned:\n  - src/planned.txt\n---\n' \
    > ops/board/done/T-2.md
) >/dev/null 2>&1
mask() { sed -E 's/^[0-9a-f]{7,40} /<sha> /; s/landed [0-9a-f]{7,40}/landed <sha>/'; }   # no \b: BSD sed lacks it
cd "$FIX/repo"
echo "== history"
bash "$KIT" history 2>/dev/null | mask
echo "== history --tasks 1"
bash "$KIT" history --tasks 1 2>/dev/null | mask
echo "== report --sprint 1"
bash "$KIT" report --sprint 1 >/dev/null 2>&1
mask < docs/sprints/sprint-1.md
