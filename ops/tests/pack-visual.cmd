# The capture step (ops/contracts/visual-check.md) is ABSENT BY DEFAULT and driven entirely by four
# CONVENTIONS keys plus the task's own `screen:`, which is the exact shape of behavior that rots
# invisibly: a repo that sets no `visual:` must see nothing change, a repo that sets it must see the
# section with ITS OWN port and ITS OWN shot folder, and `handoff` must refuse a visual change that
# ships without a fresh pair of captures and a word about what they show. None of that is reachable
# from this repo — the kit sets no `visual:` key — so without a fixture the whole feature is code that
# only OTHER people's repos ever run, and the first they hear of a regression is a broken page.
#
# HERMETIC by construction (the triage-lane / keys-drift pattern): ONE throwaway repo under mktemp -d
# carrying its own CONVENTIONS, its own board and its own tasks, with the CLI run from INSIDE it so
# polaris anchors to the fixture as PRIMARY. Nothing here reads the live board, config, registry or
# shots dir, so it is byte-identical on a second run from any board state. `landing: integrator` is
# deliberate and load-bearing: under the default `landing: self` the PASSING handoffs of asserts 9
# and 11 would go on to take the integration lease and land, and this golden would be exercising the
# integrator instead of the gate it was written for.
#
# NOTHING BELOW PINS A CAPTURE'S FILENAME, and that is the whole design: POLARIS ships no capture
# tool, `shot:` is the repo's own command and may be positional with no output flag, so the gate
# counts non-empty captures newer than the branch base and never looks at what they are called. A
# gate that demanded a name POLARIS cannot produce would make every visual task in every 6.2.0-6.5.0
# repo permanently un-handoffable. The before/after names used here are the documented convention
# for pairing pictures in the gallery, and the fixture writes them FLAT — the pre-6.6 way — on
# purpose, to prove a repo whose capture tool predates all of this keeps working.
#
# RUNTIME ~40s (measured), over the <10s house target, and kept there on purpose: asserts 4-11 ARE
# seven real `handoff` runs and one real `verify` against real claimed worktrees, and each pays a full
# CLI start plus a git worktree. `check` pays it once per run; a mocked gate would prove nothing
# about the gate.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src web; echo x > src/b.txt; echo y > web/a.txt; echo z > web/c.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  # The fixture config from the contract's § executable check, verbatim. All four capture keys set,
  # so every branch below is chosen by the DATA, not by a code path this golden had to reach for.
  printf 'base: main\nvisual: web/*\nshot: snap {ID} {PORT}\nserve: dev {PORT}\nport_base: 4000\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  # T-207 and T-208 own a visual path, T-300 does not. `risk: normal` on all three: handoff refuses
  # to hand off a task with no risk declared, and the refusals it must print here are the CAPTURE ones.
  # Only T-207 carries `screen:`, and it carries the contract's own example — so assert 1 pins the
  # whole human-string-to-path rule (spaces, the ` / `, the lowercasing) and assert 2 pins the misc/
  # fallback a task whose Planner named no screen must still get. T-208 is the SECOND visual task,
  # and it exists because a task can only be handed off once: the two-capture pass and the
  # --no-before escape are two different endings and each needs its own lane.
  printf -- '---\nid: T-207\ntitle: visual task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nscreen: Homepage / Universal Search Bar\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - web/a.txt\nverify: []\n---\n' > ops/board/ready/T-207.md
  printf -- '---\nid: T-208\ntitle: second visual task\ntype: feature\npoints: 1\nwsjf: 4\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - web/c.txt\nverify: []\n---\n' > ops/board/ready/T-208.md
  printf -- '---\nid: T-300\ntitle: non-visual task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n' > ops/board/ready/T-300.md
) >/dev/null 2>&1
R="$FIX/repo"; WT="$R/.polaris/wt/T-207"
# The one machine-specific byte any of this could ever emit is the mktemp path. Today nothing pinned
# below carries one — every message the section and the gate print names a REPO-RELATIVE path, which
# is itself part of the contract (a capture lives under the repo, never /tmp) — so N() is a no-op on
# today's output and exists so a future absolute path cannot quietly make this golden machine-bound.
N() { sed -e 's#[^ ]*tmp\.[A-Za-z0-9][A-Za-z0-9]*#<fix>#g'; }
# The SEE YOUR WORK section ONLY, sliced out of pack between its own header and the next `=== `.
# Everything else pack says about a fixture repo (its board, its index, its verify list) is noise
# this golden must not own. `NF` drops the single blank line the NEXT section's header leads with.
# awk, not grep/sed, for the emptiness test — CR-sensitive line matching bites on Windows.
S() { ( cd "$R" && bash "$KIT" pack "$1" 2>/dev/null ) | awk '/^=== SEE YOUR WORK/{on=1;next} on&&/^=== /{on=0} on&&NF{print}' | N; }
# H takes the handoff's own arguments, which is the point: the ID is positional, --saw and
# --no-before each take a value, and they may come in any order around it.
H() { out="$( cd "$WT" && bash "$KIT" handoff "$@" 2>&1 )"; rc=$?; printf '%s\n' "$out" | N; printf 'rc %s\n' "$rc"; }
V() { out="$( cd "$WT" && bash "$KIT" verify 2>&1 )"; rc=$?; printf '%s\n' "$out" | N; printf 'rc %s\n' "$rc"; }
# Where the tasks actually sit. A refusal must leave one in active/ — the gate fires BEFORE the
# board write, and a refusal that still moved the task would strand a builder's work in review/.
C() { ( cd "$R/ops/board"
  printf 'active:'; for f in active/*.md; do [ -e "$f" ] && printf ' %s' "${f#active/}"; done; printf '\n'
  printf 'review:'; for f in review/*.md; do [ -e "$f" ] && printf ' %s' "${f#review/}"; done; printf '\n' ); }
# The caption a human reads beside the pictures, with only its date normalised — every other byte
# of it is the shape the contract pins.
CAP() { sed -e 's#^- date: .*#- date: <date>#' "$1" | N; }
# The whole shots tree, repo-relative and sorted: WHERE the captures ended up is the stray sweep's
# only proof, and the captions have to be sitting next to them. LC_ALL=C so the order is the bytes'
# and not the machine's — a case-sensitive locale and a case-folding one disagree about a bare
# `T-208-page.png` sitting beside `homepage/`.
SH() { ( cd "$R/.polaris/shots" && find . -type f | sed -e 's#^\./##' | LC_ALL=C sort ); }

echo '== 1. a task that touches a visual: path sees the whole section, on ITS port =='
# port = port_base + (numeric tail mod 100) ⇒ 4000 + 7. The per-task port is the whole reason parallel
# builders can each start a dev server; a shared literal port is builders fighting over one socket.
S T-207

echo '== 2. a task that does not touch it still sees the section — with touches it: no =='
# Printed, not hidden: knowing the repo HAS a visual surface you did not touch is the useful fact.
# T-300 also pins the `mod 100`: a naive port_base+tail would say 4300 here, not 4000.
# ops/DESIGN.md is created HERE, between the two, so one fixture pins BOTH sides of the last line's
# condition: assert 1 ran without the file and must not name it, assert 2 runs with it and must.
printf '# THIS PRODUCT\nthe bar\n' > "$R/ops/DESIGN.md"
S T-300

echo '== 3. visual: unset ⇒ ONE line, and nothing else changes anywhere =='
# Absent-by-default is the invariant that lets this ship to every repo. shot:, serve: and port_base:
# stay set below on purpose: unset `visual:` alone must silence the step, whatever else is configured.
printf 'base: main\nshot: snap {ID} {PORT}\nserve: dev {PORT}\nport_base: 4000\nlanding: integrator\n' > "$R/ops/CONVENTIONS.md"
S T-207
printf 'base: main\nvisual: web/*\nshot: snap {ID} {PORT}\nserve: dev {PORT}\nport_base: 4000\nlanding: integrator\n' > "$R/ops/CONVENTIONS.md"

echo '== 4. a committed visual change with NO capture is refused, rc 1, task stays in active/ =='
( cd "$R" && bash "$KIT" claim T-207 ) >/dev/null 2>&1
( cd "$WT" && git config user.email t@t && git config user.name t \
  && echo changed > web/a.txt && git add -A && git commit -qm 'visual change' ) >/dev/null 2>&1
H
C

echo '== 5. an EMPTY png is not a capture — a blank image is a failure (VISUAL.md doctrine) =='
# The gate tests -s, not -e. Relaxing it to "the file exists" would let `: > shot.png` buy a handoff,
# which is precisely the shape of green that shipped a broken page.
mkdir -p "$R/.polaris/shots"; : > "$R/.polaris/shots/T-207-before-search.png"
H

echo '== 6. ONE capture is no longer enough: rc 1 where 6.5.0 said 0 =='
# THE FLIP. Before and after are both required, because the before-shot is what makes an agent LOOK
# at the screen it is about to overhaul, and it is the half a stakeholder actually reacts to.
printf 'PNG\n' > "$R/.polaris/shots/T-207-before-search.png"
H

echo '== 7. mid-flight verify only WARNS — the same sentence, no refusal, rc 0 =='
# The unpinned twin. A Builder may verify before the shots are taken, so verify says the same thing
# behind a warning mark and returns 0; only handoff refuses. Nothing else pins this wording, which is
# exactly why it is pinned here.
V

echo '== 8. two captures, and still nobody said what they show: the --saw refusal, rc 1 =='
# The second capture is written FLAT, the pre-6.6 way, and it counts. What it is CALLED is never
# tested; that it is non-empty and newer than the branch base is.
printf 'PNG\n' > "$R/.polaris/shots/T-207-after-search.png"
H
C

echo '== 9. two captures and one --saw line: rc 0, review/, strays filed, caption written =='
# --saw is validated as NON-EMPTY and nothing else — no length floor, no PASS/WEAK/FAIL vocabulary
# check. No validator can tell whether anyone looked; the words are for the human reading them beside
# the picture. The ID comes from the branch here, which is the near-universal form.
H --saw 'the search bar now spans the header and the old three-field row is gone — PASS against the bar'
C
CAP "$R/.polaris/shots/homepage/universal-search-bar/T-207.md"

echo '== 10. --no-before drops the bar to ONE capture — it never removes it =='
# The OTHER pinned sentence, the one that reads `no capture` instead of `fewer than 2`. An escape
# hatch that also waived the after-shot would waive the whole feature.
( cd "$R" && bash "$KIT" claim T-208 ) >/dev/null 2>&1
WT="$R/.polaris/wt/T-208"
( cd "$WT" && git config user.email t@t && git config user.name t \
  && echo changed > web/c.txt && git add -A && git commit -qm 'new page' ) >/dev/null 2>&1
H --no-before 'this page did not exist before the task' T-208 --saw 'a brand-new results page, one column and no chrome — PASS'
C

echo '== 11. nothing existed to photograph: one capture passes, and the caption says why =='
# Flags before AND after the ID, with the ID in the middle, because that is the promise: the first
# non-flag argument is the ID and the flags may come in any order. T-208 carries no `screen:`, so its
# picture and its caption land in misc/ — the folder every unnamed surface still gets. The skipped
# before-shot is RECORDED rather than silent, which is the only reason the escape hatch is safe.
# The sweep NEVER overwrites and NEVER deletes, so the shotdir already holds a file by this name and
# a stray by the same name is written beside it. The one that was already filed is the one that
# survives, and the stray is left exactly where it lies: the only thing worse than a scattered
# capture is a lost one.
mkdir -p "$R/.polaris/shots/misc"
printf 'KEPT\n' > "$R/.polaris/shots/misc/T-208-page.png"
printf 'STRAY\n' > "$R/.polaris/shots/T-208-page.png"
H --no-before 'this page did not exist before the task' T-208 --saw 'a brand-new results page, one column and no chrome — PASS'
C
CAP "$R/.polaris/shots/misc/T-208.md"
SH
cat "$R/.polaris/shots/misc/T-208-page.png"
