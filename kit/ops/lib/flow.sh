# POLARIS lib/flow.sh — one call in, one call out for a small change (ops/contracts/minutes.md § 9).
# `begin` and `wrap` only run the existing commands in order: no gate of their own, no copied logic.
# Every step runs in a subshell, so a step that `die`s or `exit`s ends only that step, and its rc is
# the rc this command exits with.

cmd_begin() { # begin <draft.md> — new → triage → claim → pack. A lane other than solo stops at rc 3.
  [ $# -eq 1 ] || die "usage: polaris begin <draft.md>"
  local out="" rc=0 id lane
  out="$( cmd_new "$1" )" || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ "$rc" -eq 0 ] || exit "$rc"
  id="${out%%[ $'\n']*}"
  [ -n "$id" ] || die "begin: new printed no task id"
  out="$( cmd_triage "$id" )" || rc=$?
  [ "$rc" -eq 0 ] || { [ -z "$out" ] || printf '%s\n' "$out"; exit "$rc"; }
  lane="${out%%$'\n'*}"
  if [ "$lane" != "solo" ]; then
    printf '%s\n' "$out"
    printf 'begin: %s needs the %s lane, not solo — it waits in ready/ for the conductor\n' "$id" "$lane"
    exit 3
  fi
  ( cmd_claim "$id" ) || exit $?
  ( cmd_pack "$id" ) || exit $?
}

cmd_wrap() { # wrap [ID] [handoff flags] — handoff → land --express (landing: integrator, solo task) →
  # next; finish when next says finish. Run from the task's worktree; land/next/finish run as child
  # commands from the PRIMARY, the way self_land does, so the caller's directory never changes.
  local id="" a skip="" lane="" out="" rc=0
  for a in "$@"; do
    if [ -n "$skip" ]; then skip=""; continue; fi
    case "$a" in --saw|--no-before) skip=1;; -*) ;; *) [ -n "$id" ] || id="$a";; esac
  done
  [ -n "$id" ] || id="$(current_task_id)" || die "not on a feat/<ID> branch — pass the ID"
  # the lane is read BEFORE handoff: triage only reads tasks in ready/ or active/
  if [ "$(cfg landing self)" = "integrator" ]; then
    lane="$( cmd_triage "$id" 2>/dev/null | sed -n 1p )"
  fi
  if [ -n "$*" ]; then ( cmd_handoff "$@" ) || exit $?
  else ( cmd_handoff "$id" ) || exit $?; fi
  if [ "$lane" = "solo" ]; then
    ( cd "$PRIMARY" && "$SELF" land --express "$id" ) || exit $?
  fi
  out="$( cd "$PRIMARY" && "$SELF" next )" || rc=$?
  [ "$rc" -eq 0 ] || { [ -z "$out" ] || printf '%s\n' "$out"; exit "$rc"; }
  if [ "${out%%$'\n'*}" = "finish" ]; then
    rc=0; ( cd "$PRIMARY" && "$SELF" finish ) || rc=$?
    exit "$rc"
  fi
  printf '%s\n' "$out"
  exit 0
}
