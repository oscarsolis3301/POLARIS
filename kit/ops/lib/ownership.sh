# POLARIS lib/ownership.sh — files_owned matching + RULES policy enforcement sourced by ops/polaris
# (the lib loader): owned_match/check_ownership, the verify: runner, map_delta hint, the RULES scanners, and the guard entrypoints (_match/_rules).

# ------------------------------------------------------------------ ownership
owned_match() { # owned_match <changed-path> ; patterns on stdin. exact | dir/ prefix | glob
  local f="$1" pat
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
      */) case "$f" in "$pat"*) return 0;; esac ;;
      *)  case "$f" in $pat) return 0;; esac ;;   # unquoted: glob; * crosses slashes
    esac
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
run_verify_cmds() { # run_verify_cmds <taskfile> — execute verify: list in CWD
  local tf="$1" c n=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
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
#   <scope pattern> <TAB> path|content <TAB> <ERE or -> <TAB> <message>
# scope uses the SAME semantics as files_owned (exact · dir/ · glob).
#   path    = the scope itself is forbidden to write — even inside files_owned.
#   content = added lines under scope must not match the ERE.
# Enforced three-deep: write-time guard (Claude Code) → verify/handoff (any
# model) → audit (Integrator). Deny-only by design: on PreToolUse, exit-0
# stdout is debug-log-only, so an advisory the model can't see must not exist.
rule_scan_path() { # rule_scan_path <repo-relative-path> — exit 1 + stderr msg on deny
  local rel="$1" scope kind pat msg
  while IFS="$(printf '\t')" read -r scope kind pat msg; do
    [ "$kind" = "path" ] || continue
    if printf '%s\n' "$scope" | owned_match "$rel"; then
      printf '⛔ RULES deny: %s — %s\n' "$rel" "${msg:-forbidden path}" >&2
      return 1
    fi
  done <<EOF
$(rules_lines)
EOF
  return 0
}
rule_scan_content_file() { # rule_scan_content_file <rel> <file-with-payload>
  local rel="$1" body="$2" scope kind pat msg
  [ -s "$body" ] || return 0
  while IFS="$(printf '\t')" read -r scope kind pat msg; do
    [ "$kind" = "content" ] && [ -n "$pat" ] && [ "$pat" != "-" ] || continue
    printf '%s\n' "$scope" | owned_match "$rel" || continue
    if grep -E -q -e "$pat" "$body" 2>/dev/null; then
      printf '⛔ RULES deny in %s: /%s/ — %s\n' "$rel" "$pat" "${msg:-forbidden content}" >&2
      return 1
    fi
  done <<EOF
$(rules_lines)
EOF
  return 0
}
check_rules() { # check_rules <ref> — every changed path + its ADDED lines vs RULES
  # HEAD resolves in the caller's worktree; named refs in the shared repo (as check_ownership).
  [ -f "$RULES" ] || return 0
  rules_lines | grep -q . || return 0
  local ref="$1" f bad=0 tmp list; tmp="$(mktemp)"
  gdiff() { if [ "$ref" = "HEAD" ]; then git "$@"; else git -C "$PRIMARY" "$@"; fi; }
  list="$(gdiff diff --name-only "$BASE...$ref" 2>/dev/null)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rule_scan_path "$f" || bad=1
    gdiff diff -U0 "$BASE...$ref" -- "$f" 2>/dev/null \
      | grep '^+' | grep -v '^+++' | cut -c2- > "$tmp" || : > "$tmp"
    rule_scan_content_file "$f" "$tmp" || bad=1
  done <<EOF
$list
EOF
  rm -f "$tmp"
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

cmd_rules_check() { # _rules <repo-relative-path> [payload-file] — internal: guard's policy gate.
  # Exit 0 = clean. Exit 1 = a rule denies (message on stderr). Payload file, when
  # given, holds the text about to be written (guard extracts it from tool_input).
  local rel="${1:?}" body="${2:-}"
  rule_scan_path "$rel" || exit 1
  [ -n "$body" ] && [ -f "$body" ] && { rule_scan_content_file "$rel" "$body" || exit 1; }
  exit 0
}
