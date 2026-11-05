# `ops/DESIGN.md` is the bar a screen has to clear, and until 6.6.0 it was written by INIT and by
# NOTHING else. INIT runs once, when a repo first adopts POLARIS — so every repo that already
# existed updated to 6.6.0, received `ops/templates/DESIGN.md`, and never got the actual file that
# five role documents point at. `heal` now closes that. This golden pins BOTH directions, because a
# test that only proves the happy one would let the single worst bug in this file ship: `ops/DESIGN.md`
# is owner-editable state exactly like `ops/CONVENTIONS.md`, and clobbering somebody's own design bar
# on a routine update is unrecoverable. It also pins the silence — a repair that keeps announcing
# itself on every install is a line nobody reads and a quiet-budget tripwire nobody can satisfy.
#
# 6.12.0 (ops/contracts/save-hops.md § 3.1) adds the first step of the shortcut chain: every role file
# says "read .polaris/brain/ first", and heal — which reaches every installed repo — now builds that
# knowledge base when it is missing, ONCE, with one note; a failed build is silent and never fails
# heal. The same states pin the shorter efficiency section a CLAUDE.md that never had one receives,
# byte for byte, and that a section already there is never rewritten.
#
# HERMETIC by construction (the keys-drift pattern): a throwaway repo carrying its OWN tiny
# `ops/templates/DESIGN.md` — FAKE content with the REAL sentinel. Never the kit's real template,
# which grows every time someone improves the bar and would red this file on perfectly correct work.
# Nothing here reads the live board, the live config or the live template, so it is byte-identical
# on a second run from any board state.
#
# ONE fixture repo, eleven states (the 5.21.0 lesson): ~0.7s of CLI startup per call is real money.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p web; echo x > web/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
R="$FIX/repo"
# `visual:` is what makes this a repo WITH screens — the one key the doctor nudge is gated on. No
# second knob was invented for the same question.
printf 'base: main\nvoice: standard\nvisual: web/*\n' > "$R/ops/CONVENTIONS.md"

# heal, filtered to the ONE thing this golden owns. Everything else heal says about a fixture repo
# (models, CLAUDE.md, its closing say) is noise, and note()'s three-space indent is stripped so the
# expected file reads as the sentence a human sees. The trailing prose is cut on purpose: the
# mechanical half — that a note fired, named this file, and fired exactly once — is what is pinned.
H() { ( cd "$R" && bash "$KIT" heal 2>/dev/null ) | sed -n 's/^   \(healed: ops\/DESIGN\.md\).*$/\1/p'; }
# doctor, same treatment.
D() { ( cd "$R" && bash "$KIT" doctor 2>/dev/null ) | sed -n 's/^   \(ops\/DESIGN\.md is installed.*\)$/\1/p'; }
X() { if [ -f "$R/ops/DESIGN.md" ]; then printf 'file: yes\n'; else printf 'file: no\n'; fi; }
# The fake template: the real `_(unfilled` sentinel, and nothing else that could drift.
TPL() { mkdir -p "$R/ops/templates"; printf '# FIXTURE BAR\n\n## THIS PRODUCT\n_(unfilled — INIT asks once.)_\n\n## The verdict\nPASS · WEAK · FAIL\n' > "$R/ops/templates/DESIGN.md"; }
# heal, RAW: stdout AND stderr into one file, so one CLI call answers several questions, and its rc.
# BL = every line of that run naming the brain, note()'s indent stripped — a failure leaking onto
# stderr would show up here too, so the silence is pinned on both streams, not just the one we print.
HB() { ( cd "$R" && bash "$KIT" heal ) > "$FIX/heal.out" 2>&1; printf 'heal rc: %s\n' "$?"; }
BL() { sed -n 's/^   //; /brain/p' "$FIX/heal.out"; }
B() { if [ -d "$R/.polaris/brain" ]; then printf 'brain: yes\n'; else printf 'brain: no\n'; fi; }

# B0. INIT ran, nothing ever built a brain — and the build CANNOT succeed: a file squats where the
#     folder goes, so even its mkdir fails. heal says nothing about it, builds nothing, and still
#     returns 0. No brain is the status quo, never the thing that fails an install or an update.
mkdir -p "$R/.polaris"; : > "$R/.polaris/brain"
HB
printf '%s\n' "$(BL | grep -c .)"
B
rm -f "$R/.polaris/brain"

# B1. The way is clear → heal builds it and says so ONCE, in the pinned words. The same run meets a
#     CLAUDE.md that never had the efficiency section: the owner's prose stays byte for byte, then
#     ONE blank line, the marker and the 6.12 text (§ 3.1, E5) — shorter, pointing at FEWEST HOPS.
printf '# Fixture project\n\nOur own words — heal never rewrites a byte of them.\n' > "$R/CLAUDE.md"
cp "$R/CLAUDE.md" "$FIX/owner.claude"
HB
BL
B
head -n 3 "$R/CLAUDE.md" > "$FIX/head.claude"
if cmp -s "$FIX/head.claude" "$FIX/owner.claude"; then printf 'owner prose: intact\n'; else printf 'owner prose: CHANGED\n'; fi
tail -n +4 "$R/CLAUDE.md"

# B2. The second heal says NOTHING about the brain — it is there. And a section an older kit
#     appended, edited by its owner since, is never "upgraded" to the new text: the marker alone
#     means hands off. CLAUDE.md then leaves, so states 0-7 run on exactly the fixture they always had.
printf '# Fixture project\n\n<!-- POLARIS:EFFICIENCY -->\n## Token efficiency — the first property\n\nAn older kit wrote this; its owner has edited it since.\n' > "$R/CLAUDE.md"
cp "$R/CLAUDE.md" "$FIX/older.claude"
HB
printf '%s\n' "$(BL | grep -c .)"
if cmp -s "$R/CLAUDE.md" "$FIX/older.claude"; then printf 'older section: untouched\n'; else printf 'older section: REWRITTEN\n'; fi
rm -f "$R/CLAUDE.md"

# 0. A kit installed before 6.6.0 has no `ops/templates/DESIGN.md` yet — its next update delivers
#    one. Until then heal says nothing and creates nothing: there is no bar to install, and a
#    complaint about a file the repo has not been shipped yet would nag every repo still catching up.
printf '%s\n' "$(H | grep -c .)"
X

# 1. The template arrives and the repo has no bar → heal installs it, byte for byte, and says so
#    ONCE. `note`, never `say`: install.sh pipes heal's whole output through its own quiet-gated
#    note, which is what keeps the CI line-budget tripwire above the epilogue unaffected.
TPL
H
X
if cmp -s "$R/ops/DESIGN.md" "$R/ops/templates/DESIGN.md"; then printf 'copy: identical\n'; else printf 'copy: DIFFERS\n'; fi

# 2. Every run after that is SILENT. A repair that re-announces itself on every install and every
#    update is a line people learn to scroll past, and the file is already there.
printf '%s\n' "$(H | grep -c .)"

# 3. heal cannot interview, so the section naming THIS product is still the template's empty slot.
#    This is the only line in POLARIS that ever says so, and it fires here because all three hold:
#    the file exists, the sentinel is still in it, and `visual:` is set.
D
#    ...and NEVER a kit version number in it. Goldening a derived surface that carries one means
#    every release reds a test that found no defect (the trap that cost sprint 9 a kickback).
printf '%s\n' "$(D | grep -c '[0-9]\.[0-9]')"

# 4. The owner writes their sentence. The sentinel is gone, so its absence IS the filled state and
#    the nudge goes quiet for good — no "well done" line, no second reminder.
printf '# FIXTURE BAR\n\n## THIS PRODUCT\nCalm, dense, boring on purpose — like a good spreadsheet.\n\n## The verdict\nPASS · WEAK · FAIL\n' > "$R/ops/DESIGN.md"
cp "$R/ops/DESIGN.md" "$FIX/owner.md"
printf '%s\n' "$(D | grep -c .)"

# 5. THE ONE THAT MATTERS. heal runs again over the owner's own bar — on every install and every
#    update, forever — and must not touch a byte of it or say one word about it. Overwriting this
#    file is the reason install.sh deliberately never copies it on $KIT_CODE.
H | grep -c .
if cmp -s "$R/ops/DESIGN.md" "$FIX/owner.md"; then printf 'owner text: intact\n'; else printf 'owner text: CLOBBERED\n'; fi

# 6. Absent-by-default, still. Sentinel back, `visual:` removed → a repo with no screens has no
#    screen to hold to a bar, so the nudge stays silent even though the section is unfilled. A
#    warning storm in repos that will never have a UI is what this gate exists to prevent.
cp "$R/ops/templates/DESIGN.md" "$R/ops/DESIGN.md"
printf 'base: main\nvoice: standard\n' > "$R/ops/CONVENTIONS.md"
printf '%s\n' "$(D | grep -c .)"

# 7. INIT never ran here — no `ops/CONVENTIONS.md`. heal's existing early return fires before any of
#    this, so nothing is created and INIT stays the path that installs the bar AND fills it from the
#    interview. On a fresh install the two never race: heal no-ops, INIT copies moments later.
#    The brain waits for INIT too — its build sits behind the same guard, so none appears here.
rm -f "$R/ops/CONVENTIONS.md" "$R/ops/DESIGN.md"; rm -rf "$R/.polaris/brain"
printf '%s\n' "$(H | grep -c .)"
X
B
