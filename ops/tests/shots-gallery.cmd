# The shots tree, the before/after gate, the generated index and the committed gallery
# (ops/contracts/visual-check.md § v2) are four waves of code that THIS repo never runs: POLARIS sets
# no `visual:` key and no `gallery:` key, so every line of it is code only OTHER people's repos
# execute, and the first they would hear of a regression is a broken page and an index full of dead
# image links. `ops/tests/pack-visual.*` proves the section and the gate; this golden walks the rest
# of the path end to end — a human name becoming a folder, a capture being counted, filed, captioned,
# indexed, and finally published as a committed picture somebody can be shown.
#
# HERMETIC by construction (the pack-visual / keys-drift pattern): ONE throwaway repo under
# mktemp -d carrying its own CONVENTIONS, its own board and its own tasks, with the CLI run from
# INSIDE it so polaris anchors to the fixture as PRIMARY. Nothing here reads the live board, config,
# registry, shots dir or gallery, so it is byte-identical on a second run from any board state.
# `landing: integrator` is load-bearing: under the default `landing: self` the passing handoffs below
# would go on to take the integration lease and land, and this golden would be exercising the
# integrator instead of the gate and the gallery it was written for. The one fixture is reused across
# every state — a CLI start is about 0.7s of real money and this file pays it twenty times already.
#
# NOTHING BELOW PINS A CAPTURE'S FILENAME, and the names are deliberately conventionless
# (`T-207-1.png` … `T-207-4.png`, `T-208-only.png`): POLARIS ships no capture tool, `shot:` is the
# repo's own command and may be positional with no output flag, so the gate counts NON-EMPTY captures
# NEWER THAN THE BRANCH BASE and never looks at what they are called. The documented
# `-before-`/`-after-` convention is for pairing pictures in the gallery; a gate that tested it would
# make every visual task in every 6.2.0-6.5.0 repo permanently un-handoffable. Which picture is the
# BEFORE is therefore decided by the clock, which is why the four captures below carry four DIFFERENT
# mtimes — two fixed stamps in the past to prove the freshness half, and a `sleep 1` to keep the two
# fresh ones apart on a filesystem with one-second resolution.
#
# RUNTIME ~55s (measured), well over the <10s house target and kept there on purpose: the asserts ARE
# real `pack`, `handoff`, `shots` and `done` runs against real claimed worktrees and a real base
# branch. `check` pays it once per run; a mocked gate and a mocked publish would prove nothing about
# either.
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
  # The fixture config from the contract's § 13. `gallery:` is deliberately ABSENT here and appears
  # only at assert 8: absent-by-default is the invariant that lets all of this ship to every repo,
  # and the only honest way to prove it is to run the whole publish path with the key unset first.
  printf 'base: main\nvisual: web/*\nshot: snap {ID} {PORT}\nport_base: 4000\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf '# THE BAR — what a screen must clear\n## THIS PRODUCT\nthe fixture bar\n' > ops/DESIGN.md
  # T <ID> <title> <extra-frontmatter> <owned> <column>
  T() { printf -- '---\nid: %s\ntitle: %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\n%sowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify: []\n---\n' "$1" "$2" "$3" "$4" > "ops/board/$5/$1.md"; }
  # The two lanes. T-207 carries the contract's own example `screen:` and walks the full path; T-208
  # carries none, so it is the misc/ lane and the --no-before escape hatch. A task can only be handed
  # off once, so two endings need two lanes.
  T T-207 'visual task' 'screen: Homepage / Universal Search Bar
' web/a.txt ready
  T T-208 'second visual task' '' web/c.txt ready
  # The slug probes live in backlog/, not ready/: `pack` finds a task in any column, and a probe in
  # ready/ would quietly change the "N ready task(s) still queued" line the handoffs below pin.
  T T-401 'probe traversal' 'screen: ../../etc/passwd
' web/p1.txt backlog
  T T-402 'probe absolute' 'screen: /etc/passwd
' web/p2.txt backlog
  T T-403 'probe drive letter' 'screen: C:\Windows\Temp
' web/p3.txt backlog
  T T-404 'probe too deep' 'screen: App / Settings / Billing
' web/p4.txt backlog
) >/dev/null 2>&1
R="$FIX/repo"; WT="$R/.polaris/wt/T-207"
# The machine-specific bytes this golden could emit are the mktemp path and the age of a worktree's
# last beat. Today nothing pinned below carries a mktemp path — every message names a REPO-RELATIVE
# path, which is itself part of the contract (a capture lives under the repo, never /tmp) — so the
# first rule is a no-op on today's output and exists so a future absolute path cannot quietly make
# this golden machine-bound. The beat rule is NOT a no-op: `done` reports a live worktree's age.
N() { sed -e 's#[^ ]*tmp\.[A-Za-z0-9][A-Za-z0-9]*#<fix>#g' -e 's#(beat [^)]*)#(beat <t> ago)#g'; }
# The slug, as the only thing that matters about it: the folder a human string became. `pack`'s full
# section is pinned by pack-visual; what is pinned HERE is the two lines that carry the path rule.
D() { printf -- '--- %s\n' "$1"; ( cd "$R" && bash "$KIT" pack "$1" 2>/dev/null ) \
        | awk '/^=== SEE YOUR WORK/{on=1;next} on&&/^=== /{on=0} on&&/^screen:|^shotdir:/{print}' | N; }
# H takes the handoff's own arguments, which is the point: the ID is positional, --saw and
# --no-before each take a value, and they may come in any order around it.
H() { out="$( cd "$WT" && bash "$KIT" handoff "$@" 2>&1 )"; rc=$?; printf '%s\n' "$out" | N; printf 'rc %s\n' "$rc"; }
# Where the tasks actually sit. A refusal must leave one in active/ — the gate fires BEFORE the board
# write, and a refusal that still moved the task would strand a builder's work in review/.
C() { ( cd "$R/ops/board"
  printf 'active:'; for f in active/*.md; do [ -e "$f" ] && printf ' %s' "${f#active/}"; done; printf '\n'
  printf 'review:'; for f in review/*.md; do [ -e "$f" ] && printf ' %s' "${f#review/}"; done; printf '\n'
  printf 'done:'; for f in done/*.md; do [ -e "$f" ] && printf ' %s' "${f#done/}"; done; printf '\n' ); }
# The caption a human reads beside the pictures, with only its date normalised — every other byte of
# it is the shape the contract pins.
CAP() { sed -e 's#^- date: .*#- date: <date>#' "$1" | N; }
# WHERE things ended up, repo-relative and sorted. LC_ALL=C so the order is the bytes' and not the
# machine's — a case-sensitive locale and a case-folding one disagree about a bare `T-208-only.png`
# sitting beside `homepage/`. `find | sort`, never a shell glob, for the same reason.
TREE() { ( cd "$R/$1" && find . -type "$2" | sed -e 's#^\./##' -e '/^\.$/d' | LC_ALL=C sort ); }
# A landed task, without the Integrator. `done` requires the work to be in $BASE and finds it by the
# `[<ID>]` subject suffix `land` writes; this is that commit, made by hand and pathspec-limited so
# the dirty fixture tree stays out of it. Taking the real integration lease here is exactly what
# `landing: integrator` above exists to prevent — this golden is about `done`, not about landing.
LAND() { ( cd "$R" && git show "feat/$1:$2" > "$2" && git add -- "$2" \
           && git commit -q -m "feat: $1 the change [$1]" -- "$2" ); }

echo '== 1. a repo that has captured nothing: two header lines, and the gallery key is unset =='
# `shots` is ONE bare arm with no subcommands — `index` is what it already does, `open` is useless to
# an agent, and publishing happens by itself at `done`. The unset line is the absent-by-default half:
# a repo that never opted in is told how to, and nothing is committed anywhere.
( cd "$R" && bash "$KIT" shots 2>&1 ) | N
cat "$R/.polaris/shots/INDEX.md"

echo '== 2. one human name becomes one folder — and every unsafe name falls back to misc/ =='
# The ONLY place in POLARIS where a human string becomes a filesystem path, so it is the only place a
# traversal can be introduced. The refusals are tested against the RAW text, BEFORE the transform,
# because the transform itself LAUNDERS an attack: `../../etc/passwd` loses its dots to the character
# filter and would come back out as the perfectly innocent `etc/passwd` — a folder that does not
# escape the repo but does put a made-up path where a screen name belongs. That laundering case is
# T-401 and it is the reason this assert exists at all.
D T-207
D T-208
D T-401
D T-402
D T-403
D T-404
# The proof that none of the six wrote outside the shots tree: every directory `pack` created, and
# nothing else. An `etc/` here, in any form, is the failure.
echo '-- directories under .polaris/shots --'
TREE .polaris/shots d

echo '== 3. captures older than the branch base do not count: rc 1, task stays in active/ =='
# Two non-empty captures exist and the gate still refuses, because freshness is half of it: a picture
# taken before the branch started is a picture of the OLD screen. Fixed past stamps, never `date`
# arithmetic — `date -d` is GNU-only and this file has to be byte-identical on macOS too.
( cd "$R" && bash "$KIT" claim T-207 ) >/dev/null 2>&1
( cd "$WT" && git config user.email t@t && git config user.name t \
  && echo changed > web/a.txt && git add -A && git commit -qm 'visual change' ) >/dev/null 2>&1
mkdir -p "$R/.polaris/shots"
# Each capture carries its own bytes. Identical stand-in pictures would make "publishes the NEWEST
# capture" unfalsifiable at assert 9 — every copy would look right whichever one had been chosen.
printf 'PNG T-207-1\n' > "$R/.polaris/shots/T-207-1.png"; touch -t 200001010000 "$R/.polaris/shots/T-207-1.png"
printf 'PNG T-207-2\n' > "$R/.polaris/shots/T-207-2.png"; touch -t 200001020000 "$R/.polaris/shots/T-207-2.png"
H
C

echo '== 4. ONE fresh capture is not enough — before AND after, or neither =='
# THE FLIP from 6.5.0, where one capture passed. The before-shot is the point, not a formality: it
# makes the agent LOOK at the screen it is about to overhaul, and it is the half a stakeholder
# actually reacts to. This one lands in misc/ — the second of visual_shots_for's three locations, and
# the one a task WITH a screen: reaches only because a capture can be taken before its folder exists.
printf 'PNG T-207-3\n' > "$R/.polaris/shots/misc/T-207-3.png"
H

echo '== 5. two fresh captures, and still nobody said what they show =='
# The third location: FLAT, the pre-6.6 way, which POLARIS can never require a repo to stop doing.
# The sleep keeps this capture's mtime clear of the last one's, so which picture is the BEFORE is
# decided by the clock and not by the order `find` happened to walk the directory.
sleep 1
printf 'PNG T-207-4\n' > "$R/.polaris/shots/T-207-4.png"
H

echo '== 6. two captures and one --saw line: rc 0, review/, strays filed, caption written =='
# --saw is validated as NON-EMPTY and nothing else — no length floor, no PASS/WEAK/FAIL vocabulary
# check. No validator can tell whether anyone looked; the words are for the human reading them beside
# the picture. Then the sweep: all four captures, from all three locations, are filed into the task's
# own shotdir. The two stale ones move too — the sweep tidies, it does not judge — and the caption
# still names the OLDEST of them as the before, because the caption's window is every capture ever
# taken while the gate's window starts at the branch base. Two windows, on purpose.
H --saw 'the search bar now spans the header and the old three-field row is gone — PASS against the bar'
C
CAP "$R/.polaris/shots/homepage/universal-search-bar/T-207.md"
echo '-- files under .polaris/shots --'
TREE .polaris/shots f

echo '== 7. gallery: unset ⇒ done publishes nothing, commits nothing, and creates no docs/ =='
# Absent-by-default, at the one place it costs a commit if it is wrong. The subjects on $BASE before
# and after `done` must be the same list: a repo that never opted in must not discover a docs/
# directory in its history because it landed a task that happened to carry a screenshot.
( cd "$R" && bash "$KIT" claim T-208 ) >/dev/null 2>&1
WT="$R/.polaris/wt/T-208"
( cd "$WT" && git config user.email t@t && git config user.name t \
  && echo changed > web/c.txt && git add -A && git commit -qm 'new page' ) >/dev/null 2>&1
# --no-before drops the bar to ONE capture; it never removes it. An escape hatch that also waived the
# after-shot would waive the whole feature. Flags before AND after the ID, because that is the
# promise: the first non-flag argument is the ID and the flags may come in any order around it.
H --no-before 'this page did not exist before the task' T-208 --saw 'a brand-new results page, one column and no chrome — PASS'
# Written straight into the task's own shotdir — the FIRST of visual_shots_for's three locations,
# which is what a repo whose capture tool takes an output path does, and the one place the stray
# sweep must then find nothing to do.
printf 'PNG T-208-only\n' > "$R/.polaris/shots/misc/T-208-only.png"
H --no-before 'this page did not exist before the task' T-208 --saw 'a brand-new results page, one column and no chrome — PASS'
CAP "$R/.polaris/shots/misc/T-208.md"
LAND T-208 web/c.txt >/dev/null 2>&1
echo '-- base subjects before done --'
( cd "$R" && git log --format='%s' main )
( cd "$R" && bash "$KIT" done T-208 2>&1 ) | N
echo '-- base subjects after done --'
( cd "$R" && git log --format='%s' main )
printf -- '-- docs/ exists: %s --\n' "$( [ -e "$R/docs" ] && echo yes || echo no )"

echo '== 8. the index: a screen read back as words, the builder words, before beside after =='
# The ONE file the owner opens. Links are RELATIVE to .polaris/shots/ so VS Code's preview renders
# them — an absolute path shows a broken image, and the image IS the product. `legacy/dashboard` is a
# screen folder with a picture and NO caption: it is still listed, with `(no caption recorded)`,
# because dropping it would hide exactly what the reader came for. The skipped before-shot shows its
# REASON in the table cell rather than quietly showing one picture.
printf 'base: main\nvisual: web/*\nshot: snap {ID} {PORT}\nport_base: 4000\nlanding: integrator\ngallery: docs/screens\n' > "$R/ops/CONVENTIONS.md"
mkdir -p "$R/.polaris/shots/legacy/dashboard"
printf 'PNG T-999-old\n' > "$R/.polaris/shots/legacy/dashboard/T-999-old.png"
( cd "$R" && bash "$KIT" shots 2>&1 ) | N
cat "$R/.polaris/shots/INDEX.md"

echo '== 9. done publishes the curated gallery on the commit it already makes =='
# One image per screen, replaced in place, so the repo carries one picture per screen forever rather
# than every picture ever taken — the churn stays local and the git weight stays bounded. It rides
# the EXISTING pathspec-limited commit: no map_delta and no surface rows on this task, so the subject
# becomes `docs(screens): <ID> <screen>` and the commit carries the gallery paths and nothing else.
# `misc.png` and `legacy/dashboard.png` are there because the gallery indexes the REPO's screens, not
# the task's — the reader wants the product, not this sprint.
LAND T-207 web/a.txt >/dev/null 2>&1
( cd "$R" && bash "$KIT" done T-207 2>&1 ) | N
echo '-- base subjects --'
( cd "$R" && git log --format='%s' main )
echo '-- paths in that commit --'
( cd "$R" && git show --name-only --format='' HEAD ) | LC_ALL=C sort
echo '-- files under docs/ --'
TREE docs f
echo '-- the bytes each screen published: the NEWEST capture, never the first --'
( cd "$R/docs/screens" && find . -type f -name '*.png' | sed -e 's#^\./##' | LC_ALL=C sort \
  | while IFS= read -r f; do printf '%s <- %s\n' "$f" "$(cat "$f")"; done )
echo '-- the curated caption --'
CAP "$R/docs/screens/homepage/universal-search-bar.md"
echo '-- the committed index --'
cat "$R/docs/screens/INDEX.md"
C
