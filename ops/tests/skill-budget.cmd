# `skill budget` is the SHELF and `skill promote` is the one gate onto it. A tier-1 skill's
# name+description ride every session's prompt in the repo, so the two numbers `budget` prints are
# what every future context in this repo pays — and the refusals below are what keep an agent from
# spending that on its own: a promoted skill is a cost the owner kept in their own hands
# (ops/contracts/self-skills.md § 0 OPEN-3/4), so a `promote` that lets a TODO description, an
# over-cap description or a shelf crossing through is the dangerous failure of this seam, not a
# crash. This pair pins the constants, the shelf arithmetic, the § 3 output shapes and every
# refusal at the cost of a subprocess, forever.
#
# HERMETIC (the triage-lane pattern): a throwaway repo, the CLI run from INSIDE it — polaris anchors
# PRIMARY to the fixture — so the live repo's own skills can never red it. Fixtures carry
# `metadata.polaris` because that KEY is the identity every subcommand hides behind (never a name
# prefix). Names from § 9; every number is the running code's, not the contract's arithmetic:
#   fx-hidden  flag true,  a description still TODO(src/x)         → 0 B injected, tier 0
#   fx-small   flag false, 300 B (15 for the name line, 285 for the description line, +1 per line)
#   fx-big     flag false, 827 B — the description FOLDS onto a second line, and a folded line is a
#              prompt line, so it counts (13 + 714 + 100)
# The three top out at 1127 B, and a candidate under the 320-B cap cannot cross 1600 from there, so
# fx-wide (200 B, tier 1) lifts the shelf to 1327 first and fx-ready (300 B, hidden, a written
# description) is the candidate the shelf refuses. Nothing printed carries a path, a timestamp, a
# user or a version: `list` prints globs and counts, and the fixture's own paths stay off stdout.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # nothing here may register in the owner's ~/.claude
pad() { # pad <n> — n bytes of filler, so a description's byte count is exact by construction
  local s="" i=0; while [ "$i" -lt "$1" ]; do s="${s}x"; i=$((i+1)); done; printf '%s' "$s"
}
mk() { # mk <name> <flag> <tier> <description> [<folded second line>]
  mkdir -p "$FIX/repo/.claude/skills/$1"
  { printf -- '---\nname: %s\ndescription: %s\n' "$1" "$4"
    [ -z "${5:-}" ] || printf '  %s\n' "$5"
    printf 'disable-model-invocation: %s\nmetadata:\n  polaris: { paths: [src/%s/], since: 2026-09-14, tier: %s, evidence: "fixture" }\n---\n# %s\n' "$2" "$1" "$3" "$1"
  } > "$FIX/repo/.claude/skills/$1/SKILL.md"
}
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
mk fx-hidden true  0 "TODO(src/x) — ≤ 290 chars: TRIGGER when …; DO NOT TRIGGER when … $(pad 200)"
mk fx-small  false 1 "$(pad 271)"
mk fx-big    false 1 "$(pad 700)" "$(pad 97)"
cd "$FIX/repo"
skill() { bash "$KIT" skill "$@" 2>&1; echo "rc=$?"; }
echo "--- budget: the constants line, then the shelf line (Σ tier-1 = small + big); rc 0 under 1600"
skill budget
echo "--- list: one line per POLARIS-written skill in name order, then ONE summary line"
skill list
echo "--- propose --write refuses a reserved name FIRST, before the threshold or the branch (nothing written)"
skill propose src/x --name polaris --write
skill propose src/x --name polaris-x --write
ls .claude/skills
echo "--- promote refuses a TODO description (nothing written)"
cp .claude/skills/fx-hidden/SKILL.md "$FIX/h.snap"
skill promote fx-hidden
cmp -s .claude/skills/fx-hidden/SKILL.md "$FIX/h.snap" && echo "fx-hidden unchanged" || echo "FX-HIDDEN CHANGED BY A REFUSAL"
echo "--- promote refuses a description over the per-skill cap: 400 B > 320 (nothing written)"
mk fx-fat true 0 "TRIGGER when the fat one is needed $(pad 338)"
cp .claude/skills/fx-fat/SKILL.md "$FIX/f.snap"
skill promote fx-fat
cmp -s .claude/skills/fx-fat/SKILL.md "$FIX/f.snap" && echo "fx-fat unchanged" || echo "FX-FAT CHANGED BY A REFUSAL"
echo "--- promote refuses a shelf crossing: 1327 + 300 > 1600, and names what to demote (nothing written)"
mk fx-wide  false 1 "$(pad 172)"
mk fx-ready true  0 "$(pad 271)"
cp .claude/skills/fx-ready/SKILL.md "$FIX/r.snap"
skill promote fx-ready
cmp -s .claude/skills/fx-ready/SKILL.md "$FIX/r.snap" && echo "fx-ready unchanged" || echo "FX-READY CHANGED BY A REFUSAL"
echo "--- budget over 1600: rc 1 and the demotion candidate (fewest hits, then the most bytes)"
mk fx-over false 1 "$(pad 272)"
skill budget
echo "--- demote is the free reverse: the shelf is under again, and a second demote is a no-op"
skill demote fx-big
skill budget
skill demote fx-big
echo "--- the same candidate promotes once the shelf has room: flag false, tier 1, on the shelf"
skill promote fx-ready
grep -c '^disable-model-invocation: false$' .claude/skills/fx-ready/SKILL.md
grep -c 'tier: 1' .claude/skills/fx-ready/SKILL.md
