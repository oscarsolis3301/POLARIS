# `doctor` is the only thing that ever says a repo's CONFIG has fallen behind its kit. `update`
# refreshes kit code and deliberately never rewrites CONVENTIONS.md, so a feature gated on a new key
# ships DORMANT — measured: a repo running byte-identical 5.24.0 code against a config missing 19
# keys, called healthy by every command. This golden pins the line that ends that silence, both when
# it fires and when it must stay quiet: a drift report that cries wolf gets scrolled past, and one
# that goes silent when it should fire is the bug it was written to kill.
#
# HERMETIC by construction (the triage-lane pattern): a throwaway repo carrying its OWN ops/KEYS.tsv
# of FAKE keys. The real registry grows every release and the real CONVENTIONS.md gains keys as
# sprints land — anchor to either and this golden reds on work that is perfectly correct. Nothing
# here reads the live board, the live config or the live registry, so it is byte-identical on a
# second run from any board state.
#
# ONE fixture repo, five states (the 5.21.0 lesson): ~0.7s of CLI startup per call is real money in
# a suite that runs on every check.
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
) >/dev/null 2>&1
R="$FIX/repo"
# A comment line and a blank line lead the file on purpose: both must be ignored, so the pinned
# "<n> of 8" below is itself the proof that only real rows are counted.
printf '# fixture registry — FAKE keys, never the real ones\n\nk_one\t9.9.9\tone\tcost one\nk_two\t9.9.9\ttwo\tcost two\nk_three\t9.9.9\tthree\tcost three\nk_four\t9.9.9\tfour\tcost four\nk_five\t9.9.9\tfive\tcost five\nk_six\t9.9.9\tsix\tcost six\nk_seven\t9.9.9\tseven\tcost seven\nk_eight\t9.9.9\teight\tcost eight\n' > "$R/ops/KEYS.tsv"
# The drift line only, stripped of note()'s three-space indent — everything else doctor says about a
# fixture repo (missing hooks, missing CLAUDE.md block) is noise this golden must not own.
D() { ( cd "$R" && bash "$KIT" doctor 2>/dev/null ) | sed -n 's/^   \(⚠ CONVENTIONS\.md lacks.*\)$/\1/p'; }

# 0. No CONVENTIONS.md at all — INIT never ran. Silent: the line directly above this check in doctor
#    already says the one useful thing, and "lacks 8 of 8" stacked on top of it is the warning storm
#    this check exists to avoid.
rm -f "$R/ops/CONVENTIONS.md"
printf '%s\n' "$(D | grep -c .)"

# 1. A real config that knows none of them: all 8 absent, so the first SIX are named in KEYS.tsv
#    order and the rest collapse into the tail. Six names is the whole budget — one line, not a storm.
printf 'voice: standard\n' > "$R/ops/CONVENTIONS.md"
D
# ...and NEVER a kit version number in it. Goldening a derived surface that carries one means every
# release reds a test that found no defect (the trap that cost sprint 9 a kickback).
printf '%s\n' "$(D | grep -c '[0-9]\.[0-9]')"

# 2. Three known here — a live value, a `# k_three:` STUB, and a live-but-EMPTY key. All three count
#    as present: a stub means "known and deliberately unset", which is how `polaris adopt` silences
#    this line without changing one behavior, and an empty value is a human's explicit choice. That
#    leaves 5 absent — at or under six, so no `+<r> more` tail.
printf 'voice: standard\nk_one: alive\n# k_three: stubbed by adopt\nk_six:\n' > "$R/ops/CONVENTIONS.md"
D

# 3. Every key present or stubbed → this check says NOTHING AT ALL. Silence is the reward for a
#    config that has caught up; a "0 missing" line would just be another thing to scroll past.
printf 'voice: standard\nk_one: a\n# k_two: s\nk_three: c\n# k_four: s\nk_five: e\n# k_six: s\nk_seven: g\n# k_eight: s\n' > "$R/ops/CONVENTIONS.md"
printf '%s\n' "$(D | grep -c .)"

# 4. No ops/KEYS.tsv — a copy installed before 6.0, whose next `update` delivers the registry. The
#    config is now missing all 8 again, and doctor still says nothing: with no registry there is no
#    question to answer, and inventing one would nag every repo that has not updated yet.
printf 'voice: standard\n' > "$R/ops/CONVENTIONS.md"
rm -f "$R/ops/KEYS.tsv"
printf '%s\n' "$(D | grep -c .)"
