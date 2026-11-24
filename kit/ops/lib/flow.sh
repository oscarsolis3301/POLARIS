# POLARIS lib/flow.sh — one call in, one call out for a small change (ops/contracts/minutes.md § 9).
# `begin` and `wrap` only run the existing commands in order: no gate of their own, no copied logic.
# Every step runs in a subshell, so a step that `die`s or `exit`s ends only that step, and its rc is
# the rc this command exits with.

cmd_begin() { # begin <draft.md> | - — new → triage → claim → pack. A lane other than solo stops at rc 3.
  # walk-away § 7: `-` reads the draft from stdin into a file under .polaris/, removed once new has
  # read it; and the reach list new printed is not computed again by pack (POLARIS_BEGIN=1).
  [ $# -eq 1 ] || die "usage: polaris begin <draft.md> | -   (- reads the draft from stdin)"
  local out="" rc=0 id lane dr="$1" tmp=""
  if [ "$dr" = "-" ]; then
    mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
    tmp="$PRIMARY/.polaris/begin-draft-$$.md"
    cat > "$tmp" || { rm -f "$tmp"; die "begin: could not read the draft from stdin"; }
    dr="$tmp"
  fi
  out="$( cmd_new "$dr" )" || rc=$?
  [ -z "$tmp" ] || rm -f "$tmp"
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
  ( POLARIS_BEGIN=1; export POLARIS_BEGIN; cmd_pack "$id" ) || exit $?
}

_wrap_wip() { # _wrap_wip <ID> — walk-away § 7: on feat/<ID>, commit the card's OWN uncommitted owned
  # files (tracked edits, deletions, new files) as `feat(<plan>): wip <ID>` — and nothing else: a path
  # off files_owned stays as it is, for handoff to judge. `land` squashes and takes the task's message.
  # Off the card's branch, or nothing of its own to commit → nothing happens.
  local id="$1" tf top pats p plan
  [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)" = "feat/$id" ] || return 0
  tf="$(task_file "$id")" || return 0
  pats="$(fm_list files_owned "$tf" 2>/dev/null || true)"
  [ -n "$pats" ] || return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  set --
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if printf '%s\n' "$pats" | owned_match "$p"; then set -- "$@" "$p"; fi
  done <<EOF
$( { git -C "$top" -c core.quotepath=off diff --name-only --no-renames HEAD -- 2>/dev/null
     git -C "$top" -c core.quotepath=off ls-files -o --exclude-standard 2>/dev/null; } | sort -u )
EOF
  [ $# -gt 0 ] || return 0
  plan="$(fm_get plan "$tf" 2>/dev/null || true)"
  if git --literal-pathspecs -C "$top" add -A -- "$@" \
     && git --literal-pathspecs -C "$top" commit -q -m "feat${plan:+($plan)}: wip $id" -- "$@"; then
    say "wrap: committed $# owned file(s) on feat/$id"
  else
    note "⚠ wrap: could not commit $id's own files — commit them on feat/$id, then wrap again"
  fi
}

cmd_wrap() { # wrap [ID] [handoff flags] — the card's own files committed (_wrap_wip) → handoff → land --express (landing: integrator, solo task) →
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
  _wrap_wip "$id"
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
