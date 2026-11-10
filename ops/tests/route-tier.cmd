# `route` is the model ORACLE: ops/contracts/model-routing.md has the CONDUCTOR call it before
# EVERY spawn and `fleet` inject its answer into every pane. That makes its output load-bearing in
# exactly the way triage's is — line 1 is parsed BLIND, so a changed word, an extra line, or a
# wrong `   model:` / `   effort:` note silently re-prices every helper in the repo. Since 6.14.0
# (minutes.md § 8) both notes always follow, from defaults in code, unless a knob says `inherit`.
#
# The effort note is clamped to the chat's own level, read from $HOME/.claude/polaris/model-state.
# So HOME and USERPROFILE are faked for the whole golden and CLAUDE_CODE_SESSION_ID is unset (the
# real ~/.claude is never read), except in the clamp case, which points both at a fixture of its own.
#
# HERMETIC BY CONSTRUCTION (the T-062 pattern, same as triage-lane): this builds its own fixture
# repo with KNOWN knobs and KNOWN tasks and runs the CLI from INSIDE it — polaris anchors to the
# worktree-list primary, which becomes the fixture. So this repo's live board and its future
# model_strong/mid/cheap edits can never red it, and running it twice from ANY board state is
# byte-identical. The knobs asserted below are the FIXTURE's, never this repo's.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
unset CLAUDE_CODE_SESSION_ID
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
  # Four ready tasks pin every branch of the ID path: derived tier · tier-word override · literal
  # model name · a forbidden literal. T-1 is 5 points, so the fleet MAX over ready/ is `strong`
  # whatever else is queued.
  printf -- '---\nid: T-1\ntitle: derived strong\ntype: feature\npoints: 5\nwsjf: 9\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' > ops/board/ready/T-1.md
  printf -- '---\nid: T-2\ntitle: tier-word override\ntype: feature\npoints: 3\nwsjf: 5\nrisk: normal\nmodel: cheap\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n' > ops/board/ready/T-2.md
  printf -- '---\nid: T-3\ntitle: literal model name\ntype: feature\npoints: 1\nwsjf: 1\nrisk: normal\nmodel: some-model-9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/c.txt\nverify: []\n---\n' > ops/board/ready/T-3.md
  # T-4 names a FORBIDDEN literal: its model note is dropped, never swapped for the default.
  printf -- '---\nid: T-4\ntitle: forbidden literal\ntype: feature\npoints: 1\nwsjf: 1\nrisk: normal\nmodel: claude-haiku-9\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/d.txt\nverify: []\n---\n' > ops/board/ready/T-4.md
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

echo '== knobs UNSET: the defaults in code =='
R --points 5 --risk normal
R --points 3 --risk normal
R --points 1 --risk normal
R T-3
R T-4

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

echo '== effort knobs: an override, inherit drops a note, an unknown word reads as unset =='
grep -v '^model_mid:' "$FIX/repo/ops/CONVENTIONS.md" > "$FIX/conv.tmp"
printf 'model_mid: inherit\neffort_strong: max\neffort_mid: inherit\neffort_cheap: turbo\n' >> "$FIX/conv.tmp"
mv "$FIX/conv.tmp" "$FIX/repo/ops/CONVENTIONS.md"
R --points 5 --risk normal
R --points 3 --risk normal
R --points 1 --risk normal
grep -v '^model_mid:\|^effort_' "$FIX/repo/ops/CONVENTIONS.md" > "$FIX/conv.tmp"
printf 'model_mid: opus\n' >> "$FIX/conv.tmp"
mv "$FIX/conv.tmp" "$FIX/repo/ops/CONVENTIONS.md"

echo '== the clamp: never above the chat own level =='
# The only case with a session id, and its own HOME, so the file below is the only one route sees.
# The file is written with a CRLF ending on purpose: the guard runs on Windows.
mkdir -p "$FIX/chat/.claude/polaris/model-state"
C() { printf 'chat %s · route --points %s\n' "$1" "$2"
  if [ "$1" = none ]; then rm -f "$FIX/chat/.claude/polaris/model-state/sess-1.effort"
  else printf '%s\r\n' "$1" > "$FIX/chat/.claude/polaris/model-state/sess-1.effort"; fi
  ( cd "$FIX/repo" && HOME="$FIX/chat" USERPROFILE="$FIX/chat" CLAUDE_CODE_SESSION_ID=sess-1 bash "$KIT" route --points "$2" 2>&1 )
  printf 'rc %s\n' "$?"; }
C medium 5
C high 1
C nonsense 5
C none 5

echo '== fleet carries the ready queue max tier =='
# The dry-run line names the resolved claude path, which is machine-specific — so lift the token
# only. `none` when no token was injected keeps a silent regression from reading as a pass.
# ONE helper, run TWICE, because `token:` only means anything as a PAIR. The fixture's ready max is
# always `strong` (T-1 is 5 points), so model_strong is the knob that moves — and it is `fable`
# here, banned outright since 2026-09-15, so this first run proves the refusal reaches the pane
# launcher: a forbidden name injects NOTHING.
FLEET() { ( cd "$FIX/repo" && PATH="$FIX/bin:$PATH" bash "$KIT" fleet 2 --dry-run 2>&1 ) \
  | awk '/\[dry-run\]/ { if (match($0, / --model [^ ]+/)) print "token:" substr($0, RSTART, RLENGTH); else print "token: none"; found=1 } END { if (!found) print "token: NO DRY-RUN LINE" }'; }
FLEET

echo '== fleet with a LEGAL strong: the token still goes in =='
# Same queue, same command, one knob repointed at a name that is NOT banned. Without this second
# run `token:` would only ever exercise the refusal path, and a regression that killed injection
# outright — for every repo, legal names included — would read here as a pass.
grep -v '^model_strong:' "$FIX/repo/ops/CONVENTIONS.md" > "$FIX/conv.tmp"
printf 'model_strong: some-model-9\n' >> "$FIX/conv.tmp"
mv "$FIX/conv.tmp" "$FIX/repo/ops/CONVENTIONS.md"
FLEET
