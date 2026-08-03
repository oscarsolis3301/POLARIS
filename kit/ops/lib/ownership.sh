# POLARIS lib/ownership.sh — files_owned matching + RULES policy enforcement sourced by ops/polaris
# (the lib loader): owned_match/check_ownership, the verify: runner, map_delta hint, the RULES scanners, and the guard entrypoints (_match/_rules).

# ------------------------------------------------------------------ ownership
match_one() { # match_one <changed-path> <pattern> — THE matcher: exact | dir/ prefix | glob.
  # Extracted so a single-pattern caller does not have to build a pipe to reach it (a pipe is a
  # subshell, and rule_scan_path built one PER RULE — ~14 forks per guarded write).
  case "$2" in
    */) case "$1" in "$2"*) return 0;; esac ;;
    *)  case "$1" in $2) return 0;; esac ;;      # unquoted: glob; * crosses slashes
  esac
  return 1
}
owned_match() { # owned_match <changed-path> [pattern...] — patterns as args, or on stdin if none
  local f="$1" pat
  shift
  if [ $# -gt 0 ]; then
    for pat in "$@"; do [ -z "$pat" ] && continue; match_one "$f" "$pat" && return 0; done
    return 1
  fi
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    match_one "$f" "$pat" && return 0
  done
  return 1
}
check_ownership() { # check_ownership <taskfile> <ref> — diff BASE...ref ⊆ files_owned
  # HEAD must resolve in the CALLER'S worktree; named refs resolve in the shared repo.
  local tf="$1" ref="$2" owned bad="" f list gen
  owned="$(fm_list files_owned "$tf")"
  [ -n "$owned" ] || die "task has empty files_owned — planning bug"
  # generated: git-tracked build output the Builder can't help dirtying (it runs `build`) and doesn't
  # own. Excluded from the ownership diff so it never false-rejects a handoff. Opt-in via CONVENTIONS.
  gen="$(cfg generated "" | tr ' ' '\n')"
  # --no-renames: git's default rename detection reports only a rename's DESTINATION, so
  # `git mv non-owned owned/` would show one owned path and hide the non-owned source's deletion
  # — an ownership + stop-and-ask violation slipping past the gate. Off, both sides are checked.
  if [ "$ref" = "HEAD" ]; then list="$(git diff --name-only --no-renames "$BASE...HEAD")"
  else list="$(git -C "$PRIMARY" diff --name-only --no-renames "$BASE...$ref")"; fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -n "$gen" ] && printf '%s\n' "$gen" | owned_match "$f" && continue   # tracked build output — excluded
    printf '%s\n' "$owned" | owned_match "$f" || bad="$bad$f\n"
  done <<EOF
$list
EOF
  if [ -n "$bad" ]; then
    printf '⛔ ownership violation — changed but NOT in files_owned:\n' >&2
    printf '%b' "$bad" | sed 's/^/     /' >&2   # %b: interpret our \n separators, but never treat a filename's % as a format spec
    return 1
  fi
  say "ownership clean: diff ⊆ files_owned"
}
_norm_cmd() { printf '%s' "$1" | tr -s ' \t' ' ' | sed -e 's/^ //' -e 's/ $//'; }

run_verify_cmds() { # run_verify_cmds <taskfile> — execute verify: list in CWD
  # REFUSES a bare full-suite command. `verify:` runs 2-3x per task (builder `verify`, `handoff`,
  # integrator `run-verify`) ON TOP of the wave gate that already runs the suite once — so a suite
  # command here is paid 2-3x per task for nothing. On this repo that is 805s x 3.
  # PLANNER.md has said so in prose since 5.15.0, and the 2026-07-25 audit found 24 of 46 landed
  # tasks doing it anyway: that is where most of the board's wall-clock went. A rule half the board
  # violates is not a rule, so it is now mechanical. `test_fast:` is deliberately NOT refused —
  # a fast tier in verify: is the whole point.
  local tf="$1" c n=0 nc suite_t suite_b
  suite_t="$(_norm_cmd "$(cfg test "")")"
  suite_b="$(_norm_cmd "$(cfg build "")")"
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    nc="$(_norm_cmd "$c")"
    if { [ -n "$suite_t" ] && [ "$nc" = "$suite_t" ]; } || { [ -n "$suite_b" ] && [ "$nc" = "$suite_b" ]; }; then
      printf '⛔ verify: carries the full suite — "%s"\n' "$c" >&2
      printf '   That command is the WAVE gate (`polaris qa`), which already runs it once. In verify: it is\n' >&2
      printf '   paid again on verify, on handoff and on the integrator run-verify — 3x per task, for nothing.\n' >&2
      printf '   Fix the task: replace it with the narrow check this task actually needs (or `test_fast:`),\n' >&2
      printf '   then re-run. See ops/roles/PLANNER.md "NEVER put a bare full-suite command in verify:".\n' >&2
      return 1
    fi
    n=$((n+1)); note "verify[$n]: $c"
    bash -c "$c" || { printf '⛔ verify command failed: %s\n' "$c" >&2; return 1; }
  done <<EOF
$(fm_list verify "$tf")
EOF
  [ "$n" -eq 0 ] && note "no verify: commands on task (acceptance is manual)" || say "all $n verify commands green"
}
map_delta_hint() { # map_delta_hint <taskfile> <ref> — warn (never block) when a handoff introduces a
  # new top-level path but map_delta is blank. MAP.md is the token-discipline substitute for reading
  # the repo; when it silently rots the cost compounds every future sprint. Cheap heuristic, not a gate.
  local tf="$1" ref="$2" md added f top new=""
  md="$(fm_list map_delta "$tf" 2>/dev/null || true)"
  [ -n "$md" ] && return 0                              # author already declared a delta
  if [ "$ref" = "HEAD" ]; then added="$(git diff --name-only --no-renames --diff-filter=A "$BASE...HEAD")"
  else added="$(git -C "$PRIMARY" diff --name-only --no-renames --diff-filter=A "$BASE...$ref")"; fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    top="${f%%/*}"
    grep -qF "$top" "$OPS/MAP.md" 2>/dev/null || case " $new " in *" $top "*) :;; *) new="$new $top";; esac
  done <<EOF
$added
EOF
  [ -n "$new" ] && note "⚠ map_delta is blank but this adds new top-level path(s):$new — if it changes the map, set map_delta on the task so MAP.md stays current (polaris done applies it)"
  return 0
}

# --------------------------------------------------------------------- rules
# ops/RULES.tsv — repo policy as data, one rule per line, TAB-separated:
#   <scope pattern> <TAB> path|content|ask <TAB> <ERE or -> <TAB> <message>
# scope uses the SAME semantics as files_owned (exact · dir/ · glob).
#   path    = the scope itself is forbidden to write — even inside files_owned.
#   content = added lines under scope must not match the ERE.
#   ask     = forbidden EXACTLY as path, unless the claimed task carries a human
#             approval covering the scope (`polaris approve`, the task's
#             `approved:` list). Pattern column is `-`, as for path.
#             ops/contracts/ask-approval.md is the spec.
# `ask` exists because a message like "human decision, stop-and-ask" was being
# enforced as a wall: in the field a human approved a change at the plan gate and
# the Builder still died on its first write, with the decision already made.
# The approval is per-task and per-scope and expires with the task; it NEVER
# weakens path or content, which are unchanged and consult no approval at all.
# Enforced three-deep: write-time guard (Claude Code) → verify/handoff (any
# model) → audit (Integrator). Deny-only by design: on PreToolUse, exit-0
# stdout is debug-log-only, so an advisory the model can't see must not exist.

# --- ask: approval lookup -------------------------------------------------
# _ASK_ID/_ASK_LIST memoize ONE task's approved: entries. The read happens at most once per process
# AND only after an `ask` rule has actually matched, because this is the write-guard's hot path
# (every Edit/Write, against a 10s hook timeout, ~3.8s of which is startup): a repo with no `ask`
# rules — the normal case — must pay nothing at all for this feature.
_ASK_ID=""
_ASK_LIST=""
POLARIS_ASK_APPROVAL=""    # the approved: entry that cleared the last covered path
POLARIS_ASK_CLEARED=""     # accumulated "<path> …" lines, one per cleared rule, for check_rules
ask_approvals_load() { # ask_approvals_load <ID|-> — cache <ID>'s approved: entries in _ASK_LIST
  [ "$_ASK_ID" = "$1" ] && return 0
  _ASK_ID="$1"; _ASK_LIST=""
  case "$1" in ""|-) return 0;; esac
  local tf
  tf="$(task_file "$1" active)" || tf="$(task_file "$1")" || return 0
  _ASK_LIST="$(fm_list approved "$tf" 2>/dev/null || true)"
  return 0
}
ask_approval_covers() { # ask_approval_covers <repo-relative-path> <ID|-> — 0 when one of <ID>'s
  # approved: entries covers <path>; sets POLARIS_ASK_APPROVAL to that entry.
  # The scope is the entry's LEADING whitespace-delimited token; everything after it (conventionally
  # " — <who>, <date>: <why>") is provenance for humans and is never parsed. Coverage runs through
  # the ordinary files_owned matcher, so `src/db/` covers `src/db/models.py` — scope-for-scope
  # equality is NOT required. No ID, no such task, no entries → 1. Fail closed: a session with
  # nothing to carry an approval has no approval.
  POLARIS_ASK_APPROVAL=""
  local rel="$1" id="${2:--}" entry scope
  case "$id" in ""|-) return 1;; esac
  ask_approvals_load "$id"
  [ -n "$_ASK_LIST" ] || return 1
  while IFS= read -r entry; do
    scope="${entry%%[[:space:]]*}"
    [ -n "$scope" ] || continue
    if owned_match "$rel" "$scope"; then POLARIS_ASK_APPROVAL="$entry"; return 0; fi
  done <<EOF
$_ASK_LIST
EOF
  return 1
}
ask_rule_matches() { # ask_rule_matches <scope-or-path> — 0 when it matches at least one `ask` rule.
  # `polaris approve` calls this for its no-op precondition: approving something no `ask` rule gates
  # must SAY so rather than silently write an approval line. Exported plainly instead of inlined at
  # the call site so both readers of RULES agree on what "gated" means.
  local rel="$1" scope kind pat msg
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    [ "$kind" = "ask" ] || continue
    owned_match "$rel" "$scope" && return 0
  done <<EOF
$(rules_lines)
EOF
  return 1
}

rule_scan_path() { # rule_scan_path <repo-relative-path> [<ID>|-] — exit 1 + stderr msg on deny
  # The optional ID is the claimed task, and it exists for `ask` alone — the only kind that can be
  # cleared, and only by an approval recorded on that task. `path` never consults it: its behaviour
  # here is byte-for-byte what it was. Omitted or `-` → every `ask` rule denies.
  local rel="$1" id="${2:--}" scope kind pat msg
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    case "$kind" in path|ask) ;; *) continue;; esac
    owned_match "$rel" "$scope" || continue
    if [ "$kind" = "ask" ] && ask_approval_covers "$rel" "$id"; then
      POLARIS_ASK_CLEARED="$POLARIS_ASK_CLEARED$rel — ask scope '$scope' cleared by approved: $POLARIS_ASK_APPROVAL
"
      continue
    fi
    printf '⛔ RULES deny: %s — %s\n' "$rel" "${msg:-forbidden path}" >&2
    [ "$kind" = "ask" ] && printf '   this is an `ask` rule: a human clears it with  polaris approve <ID> %s -m "why"  — never by editing the rule\n' "$scope" >&2
    return 1
  done <<EOF
$(rules_lines)
EOF
  return 0
}
rule_scan_content_file() { # rule_scan_content_file <rel> <file-with-payload>
  local rel="$1" body="$2" scope kind pat msg
  [ -s "$body" ] || return 0
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    [ "$kind" = "content" ] && [ -n "$pat" ] && [ "$pat" != "-" ] || continue
    owned_match "$rel" "$scope" || continue
    if grep -E -q -e "$pat" "$body" 2>/dev/null; then
      printf '⛔ RULES deny in %s: /%s/ — %s\n' "$rel" "$pat" "${msg:-forbidden content}" >&2
      return 1
    fi
  done <<EOF
$(rules_lines)
EOF
  return 0
}
check_rules() { # check_rules <ref> [<ID>] — every changed path + its ADDED lines vs RULES
  # HEAD resolves in the caller's worktree; named refs in the shared repo (as check_ownership).
  # <ID> is the claimed task, forwarded to `ask` rules so an approval recorded on it can clear one.
  # Omitted → `-` → no approvals apply and every `ask` rule denies.
  [ -f "$RULES" ] || return 0
  rules_lines | grep -q . || return 0
  local ref="$1" id="${2:--}" f bad=0 tmp list ln; tmp="$(mktemp)"
  POLARIS_ASK_CLEARED=""
  gdiff() { if [ "$ref" = "HEAD" ]; then git "$@"; else git -C "$PRIMARY" "$@"; fi; }
  list="$(gdiff diff --name-only "$BASE...$ref" 2>/dev/null)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rule_scan_path "$f" "$id" || bad=1
    gdiff diff -U0 "$BASE...$ref" -- "$f" 2>/dev/null \
      | grep '^+' | grep -v '^+++' | cut -c2- > "$tmp" || : > "$tmp"
    rule_scan_content_file "$f" "$tmp" || bad=1
  done <<EOF
$list
EOF
  rm -f "$tmp"
  # A check that passes BECAUSE of an approval must say which one. Silence would hide the exception
  # at exactly the moment a human is meant to see it — this line rides the handoff report to the
  # Integrator, who is the human gate for anything an `ask` rule was guarding.
  while IFS= read -r ln; do
    [ -n "$ln" ] && note "⚠ RULES exception used — $ln"
  done <<EOF
$POLARIS_ASK_CLEARED
EOF
  [ "$bad" -eq 0 ] && { rules_lines | grep -q . && say "rules clean: $(rules_lines | grep -c .) rule(s) checked"; return 0; }
  printf '⛔ RULES violation — see lines above. These block even inside files_owned.\n' >&2
  return 1
}

cmd_match() { # _match <repo-relative-path> <ID> — internal: hook guard + tooling share
  # the ONE ownership matcher. Exit 0 = allowed for this task, 1 = not.
  local rel="${1:?}" id="${2:?}" tf
  tf="$(task_file "$id" active)" || tf="$(task_file "$id")" || exit 1
  case "$rel" in
    "ops/board/active/$id.md"|"ops/board/backlog/IDEAS.md") exit 0;;   # Notes + ideas are always writable
  esac
  fm_list files_owned "$tf" | owned_match "$rel" && exit 0 || exit 1
}

cmd_guard() { # _guard <repo-relative-path> <ID|-> [payload-file] — internal: BOTH gates in ONE
  # process. The write-guard fires on every Edit/Write; calling `_rules` then `_match` meant two
  # full polaris startups per write, and on Windows/Git Bash each is ~3.8s (forks dominate), so a
  # Builder's write cost ~7.6s against a 10s hook timeout — close enough to the ceiling that under
  # parallel lanes the hook timed out and FAILED OPEN, silently dropping the ownership gate.
  # Same two checks, same order, same exit codes, one startup. `-` for ID = rules gate only
  # (non-Builder session). rc 0 clean · 1 rules deny · 3 ownership deny (distinct so the guard
  # prints the right remedy without re-running anything).
  local rel="${1:?}" id="${2:--}" body="${3:-}"
  rule_scan_path "$rel" "$id" || exit 1     # the ID it already has is what an `ask` rule needs
  [ -n "$body" ] && [ -f "$body" ] && { rule_scan_content_file "$rel" "$body" || exit 1; }
  [ "$id" = "-" ] && exit 0
  local tf
  tf="$(task_file "$id" active)" || tf="$(task_file "$id")" || exit 3
  case "$rel" in
    "ops/board/active/$id.md"|"ops/board/backlog/IDEAS.md") exit 0;;
  esac
  fm_list files_owned "$tf" | owned_match "$rel" && exit 0 || exit 3
}

cmd_rules_check() { # _rules <repo-relative-path> [payload-file] — internal: guard's policy gate.
  # Exit 0 = clean. Exit 1 = a rule denies (message on stderr). Payload file, when
  # given, holds the text about to be written (guard extracts it from tool_input).
  # No ID reaches here and none can — `_rules` is the ID-less gate — so `ask` rules deny. That is
  # the fail-closed default, and it is what keeps this entrypoint honest.
  local rel="${1:?}" body="${2:-}"
  rule_scan_path "$rel" "-" || exit 1
  [ -n "$body" ] && [ -f "$body" ] && { rule_scan_content_file "$rel" "$body" || exit 1; }
  exit 0
}
