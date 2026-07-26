# The startup path is a BUDGET, and this golden is how it stays one.
#
# Timings cannot be a golden — they flap with machine load. So assert the STRUCTURE that produced
# the timings instead: each line below is a fork that was measured, found expensive, and removed.
# Every one of them is easy to reintroduce by writing the obvious-looking code, which is exactly
# why the check is mechanical. Numbers here are counts, so a regression reads as a diff.
#
# Measured 2026-07-25 (Windows/Git Bash), before -> after:
#   polaris help 2820ms -> 202ms · _guard (per Edit) 2647ms -> 939ms · rules 1822ms -> 689ms
#
# Every count below is over CODE only — comments are stripped first, because these same patterns
# are named in the comments that explain why they were removed, and a check that trips on its own
# documentation is a check people delete.
# `IFS="$(printf '\t')"` in a while-condition re-forks PER LINE READ (42 rules = 42 forks).
printf 'per-iteration-IFS-forks %s\n' "$(cat kit/ops/polaris kit/ops/lib/*.sh | grep -v '^[[:space:]]*#' | grep -c 'IFS="$(printf' | tr -d ' ')"
# `hostname` is ~524ms here and belongs behind core.sh::who(), never in the entry point's globals.
printf 'hostname-in-entrypoint %s\n' "$(grep -v '^[[:space:]]*#' kit/ops/polaris | grep -c 'hostname' | tr -d ' ')"
# The globals block reads base/claim/stale_hours through ONE cfg_boot awk, not three cfg forks.
printf 'cfg-forks-in-globals %s\n' "$(sed -n '/^# ---------------------------------------------------------------- resolve env/,/^EVENTS=/p' kit/ops/polaris | grep -c '$(cfg ' | tr -d ' ')"
# help must answer above the module loader: no modules, no git, no CONVENTIONS.
printf 'help-fast-path %s\n' "$(grep -c "help|-h|--help) usage; exit 0" kit/ops/polaris | tr -d ' ')"
# RULES.tsv is read up to 7x per guarded write; it cannot change mid-process, so it is memoized.
printf 'rules-lines-memoized %s\n' "$(grep -c '_RULES_CACHED' kit/ops/lib/core.sh | tr -d ' ')"
# A single-pattern match must not build a pipe (a pipe is a subshell) — see ownership.sh::match_one.
printf 'per-rule-match-pipes %s\n' "$(grep -c "printf '%s..n' \"\$scope\" | owned_match" kit/ops/lib/ownership.sh | tr -d ' ')"
