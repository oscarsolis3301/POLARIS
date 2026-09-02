# The capture step (ops/contracts/visual-check.md) is ABSENT BY DEFAULT and driven entirely by four
# CONVENTIONS keys, which is the exact shape of behavior that rots invisibly: a repo that sets no
# `visual:` must see nothing change, a repo that sets it must see the section with ITS OWN port, and
# `handoff` must refuse a visual change that ships without a fresh capture. None of that is reachable
# from this repo — the kit sets no `visual:` key — so without a fixture the whole feature is code that
# only OTHER people's repos ever run, and the first they hear of a regression is a broken page.
#
# HERMETIC by construction (the triage-lane / keys-drift pattern): ONE throwaway repo under mktemp -d
# carrying its own CONVENTIONS, its own board and its own tasks, with the CLI run from INSIDE it so
# polaris anchors to the fixture as PRIMARY. Nothing here reads the live board, config, registry or
# shots dir, so it is byte-identical on a second run from any board state. `landing: integrator` is
# deliberate and load-bearing: under the default `landing: self` the PASSING handoff of assert 5 would
# go on to take the integration lease and land, and this golden would be exercising the integrator
# instead of the gate it was written for.
#
# RUNTIME ~28s (measured), over the <10s house target, and kept there on purpose: asserts 4-6 ARE three real
# `handoff` runs against a real claimed worktree, and each pays a full CLI start plus a git worktree.
# `check` pays it once per run; a mocked gate would prove nothing about the gate.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src web; echo x > src/b.txt; echo y > web/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  # The fixture config from the contract's § executable check, verbatim. All four capture keys set,
  # so every branch below is chosen by the DATA, not by a code path this golden had to reach for.
  printf 'base: main\nvisual: web/*\nshot: snap {ID} {PORT}\nserve: dev {PORT}\nport_base: 4000\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  # T-207 owns a visual path, T-300 does not. `risk: normal` on both: handoff refuses to hand off a
  # task with no risk declared, and the refusal it must print here is the CAPTURE one.
  printf -- '---\nid: T-207\ntitle: visual task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - web/a.txt\nverify: []\n---\n' > ops/board/ready/T-207.md
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
H() { out="$( cd "$WT" && bash "$KIT" handoff 2>&1 )"; rc=$?; printf '%s\n' "$out" | N; printf 'rc %s\n' "$rc"; }
# Where the task actually sits. The refusal must leave it in active/ — the gate fires BEFORE the
# board write, and a refusal that still moved the task would strand a builder's work in review/.
C() { ( cd "$R/ops/board"
  printf 'active:'; for f in active/*.md; do [ -e "$f" ] && printf ' %s' "${f#active/}"; done; printf '\n'
  printf 'review:'; for f in review/*.md; do [ -e "$f" ] && printf ' %s' "${f#review/}"; done; printf '\n' ); }

echo '== 1. a task that touches a visual: path sees the whole section, on ITS port =='
# port = port_base + (numeric tail mod 100) ⇒ 4000 + 7. The per-task port is the whole reason parallel
# builders can each start a dev server; a shared literal port is builders fighting over one socket.
S T-207

echo '== 2. a task that does not touch it still sees the section — with touches it: no =='
# Printed, not hidden: knowing the repo HAS a visual surface you did not touch is the useful fact.
# T-300 also pins the `mod 100`: a naive port_base+tail would say 4300 here, not 4000.
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
mkdir -p "$R/.polaris/shots"; : > "$R/.polaris/shots/T-207-home.png"
H

echo '== 6. a non-empty capture newer than the branch base passes: rc 0, T-207 in review/ =='
# Existence and freshness only. Whether anyone LOOKED is prose (the saw: line, the Integrator opening
# the png) — this half is mechanical on purpose, and must never grow an opinion about the pixels.
printf 'PNG\n' > "$R/.polaris/shots/T-207-home.png"
H
C
