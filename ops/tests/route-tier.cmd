# `route` is the model ORACLE: ops/contracts/model-routing.md has the CONDUCTOR call it before
# EVERY spawn and `fleet` inject its answer into every pane. That makes its output load-bearing in
# exactly the way triage's is — line 1 is parsed BLIND, so a changed word, an extra line, or a
# `   model:` note that fires when no knob is set silently re-prices every session in the repo.
#
# HERMETIC BY CONSTRUCTION (the T-062 pattern, same as triage-lane): this builds its own fixture
# repo with KNOWN knobs and KNOWN tasks and runs the CLI from INSIDE it — polaris anchors to the
# worktree-list primary, which becomes the fixture. So this repo's live board and its future
# model_strong/mid/cheap edits can never red it, and running it twice from ANY board state is
# byte-identical. The knobs asserted below are the FIXTURE's, never this repo's.
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
  # Phase 1 runs with NO mapping knobs, so strip any the scaffold ever grows: "unset changes
  # NOTHING" is the contract's first invariant and it must be proven against a file that is
  # genuinely silent, not merely assumed to be.
  if [ -f ops/CONVENTIONS.md ]; then grep -v '^model_' ops/CONVENTIONS.md > conv.tmp; mv conv.tmp ops/CONVENTIONS.md; fi
  # Three ready tasks pin every branch of the ID path: derived tier · tier-word override · literal
  # model name. T-1 is 5 points, so the fleet MAX over ready/ is `strong` whatever else is queued.
  printf -- '---\nid: T-1\ntitle: derived strong\ntype: feature\npoints: 5\nwsjf: 9\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' > ops/board/ready/T-1.md
  printf -- '---\nid: T-2\ntitle: tier-word override\ntype: feature\npoints: 3\nwsjf: 5\nrisk: normal\nmodel: cheap\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n' > ops/board/ready/T-2.md
  printf -- '---\nid: T-3\ntitle: literal model name\ntype: feature\npoints: 1\nwsjf: 1\nrisk: normal\nmodel: some-model-9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/c.txt\nverify: []\n---\n' > ops/board/ready/T-3.md
  # A launchable tmux + claude on PATH. Without them `fleet` falls through to "found no terminal"
  # and the token assert below would pass VACUOUSLY on CI while failing on a dev box. Both are
  # stubs — --dry-run never executes them. The bin dir sits under mktemp's /tmp path on purpose:
  # Git Bash splits a PATH entry at the colon, so a C:/… entry becomes two broken ones.
  mkdir -p "$FIX/bin"
  printf '#!/bin/sh\nexit 0\n' > "$FIX/bin/tmux";   chmod +x "$FIX/bin/tmux"
  printf '#!/bin/sh\nexit 0\n' > "$FIX/bin/claude"; chmod +x "$FIX/bin/claude"
) >/dev/null 2>&1
# One helper, one shape: the invocation, then route's own stdout+stderr verbatim, then its rc. The
# printed output IS the assertion — no grep in between, so the three-space note indent, the bare
# line-1 word and the ⛔ usage text are all diffed byte-for-byte against the golden.
R() { printf 'route %s\n' "${*:-<no args>}"; ( cd "$FIX/repo" && bash "$KIT" route "$@" 2>&1 ); printf 'rc %s\n' "$?"; }

echo '== knobs UNSET: tier words only =='
R --points 5 --risk normal
R T-3

printf 'model_strong: fable   # owner comment, stripped by cfg\nmodel_mid: opus\nmodel_cheap: sonnet\n' >> "$FIX/repo/ops/CONVENTIONS.md"

echo '== knobs SET: the tier_for table, board-free =='
R --points 5 --risk normal
R --points 3 --risk normal
R --points 1 --risk normal
R --points 2 --risk high
R --points x --risk normal

echo '== roles =='
R --role PLANNER
R --role SOLO
R --role BUILDER
R --role WIZARD

echo '== by ID: derived · tier-word override · literal name =='
R T-1
R T-2
R T-3

echo '== refusals =='
R
R T-404

echo '== fleet carries the ready queue max tier =='
# The dry-run line names the resolved claude path, which is machine-specific — so lift the token
# only. `none` when no token was injected keeps a silent regression from reading as a pass.
( cd "$FIX/repo" && PATH="$FIX/bin:$PATH" bash "$KIT" fleet 2 --dry-run 2>&1 ) \
  | awk '/\[dry-run\]/ { if (match($0, / --model [^ ]+/)) print "token:" substr($0, RSTART, RLENGTH); else print "token: none"; found=1 } END { if (!found) print "token: NO DRY-RUN LINE" }'
