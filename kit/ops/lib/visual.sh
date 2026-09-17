# lib/visual.sh — SEEING YOUR WORK: the pack section that names the capture step, and the
# capture gate both cmd_verify and cmd_handoff run (ops/contracts/visual-check.md).

visual_pack() { # visual_pack <ID> <owned> — pack's SEE YOUR WORK section, the owned patterns as ARG 2.
  # (ops/contracts/visual-check.md § cmd_pack): the capture step, driven by real
  # cfg reads of visual:/shot:/serve:/port_base: so each repo plugs in its own tool. Absent by
  # default — no visual: ⇒ one line and nothing else changes. `touches it` = any files_owned
  # pattern vs any visual: glob, both directions (pat_overlap, the claim gate's matcher); the globs
  # are read through a here-doc, never a bare $vis, which the shell would expand against the cwd.
  # Per-task port = port_base + (numeric tail of the ID mod 100): T-207 ⇒ +7, no digits ⇒
  # port_base, no port_base ⇒ {PORT} stays literal.
  local id="${1:-}"
  local owned="${2:-}"
  pack_section "SEE YOUR WORK — capture before handoff (ops/VISUAL.md)"
  local vis vshot vserve vbase vport vnum vhit
  local p d
  vis="$(cfg visual "")"
  if [ -z "$vis" ]; then
    printf '(visual: unset — no capture step; ops/VISUAL.md explains how to add one)\n'
  else
    vshot="$(cfg shot "")"; vserve="$(cfg serve "")"; vbase="$(cfg port_base "")"
    vhit=no
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        if [ "$vhit" = no ] && pat_overlap "$p" "$d"; then vhit=yes; fi
      done <<EOF_VIS
$(printf '%s\n' "$vis" | tr ' ' '\n')
EOF_VIS
    done <<EOF_OWN
$owned
EOF_OWN
    vnum="${id##*[!0-9]}"
    vport=""
    case "$vbase" in ''|*[!0-9]*) ;; *)
      vport="$vbase"; if [ -n "$vnum" ]; then vport=$(( vbase + 10#$vnum % 100 )); fi;;
    esac
    printf 'visual: %s · this task touches it: %s\n' "$vis" "$vhit"
    if [ -n "$vserve" ]; then
      if [ -n "$vport" ]; then vserve="${vserve//\{PORT\}/$vport}"; fi
      printf 'serve: %s\n' "$vserve"
    fi
    if [ -n "$vshot" ]; then
      vshot="${vshot//\{ID\}/$id}"
      if [ -n "$vport" ]; then vshot="${vshot//\{PORT\}/$vport}"; fi
      printf 'shot: %s\n' "$vshot"
    else
      printf 'shot: (unset — set shot: in ops/CONVENTIONS.md; ops/VISUAL.md)\n'
    fi
    if [ -n "$vport" ]; then printf 'port: %s\n' "$vport"; else printf 'port: (port_base unset — {PORT} stays literal)\n'; fi
    printf 'proof: .polaris/shots/%s-*.png — then READ it and write one "saw: <what it shows>" line in your handoff\n' "$id"
    printf 'read: ops/VISUAL.md\n'
  fi
}

visual_gate() { # visual_gate <ID> <mode> <need> <saw> — the capture gate, ONE body, both callers.
  # capture-exists gate (ops/contracts/visual-check.md § cmd_handoff): a diff that touches a visual:
  # path ships with a capture or not at all. Fires only when BOTH visual: and shot: are set (absent by
  # default) AND the branch's diff has a path matching a visual: glob; then ONE non-empty
  # .polaris/shots/<ID>-*.png in the PRIMARY must be newer than the branch base (the merge-base
  # commit's time), else the handoff dies HERE — before any board write, so the task stays in
  # active/. Existence and freshness only: LOOKING at it is prose (the saw: line, the Integrator
  # opening the png).
  # `mode` alone decides the git anchor AND the ending, and they are the ONLY differences: `die`
  # (cmd_handoff) reads the PRIMARY's $BASE...feat/<ID> and refuses; `warn` (cmd_verify) reads the
  # worktree's $BASE...HEAD and prints the SAME sentence behind `⚠ ` instead of
  # `⛔ handoff refused: ` — mid-flight it only warns, because a Builder may verify before the shot
  # is taken. `need` and `saw` are accepted here and used from T-168; today `need` is 1 and `saw` is
  # ignored, so the shipped behaviour is v1's.
  local id="${1:-}"
  local mode="${2:-die}"
  local need="${3:-1}"
  local saw="${4:-}"
  local vdir vhead
  local vis shot vf vhit vbase vshot vmt vok vmsg
  if [ "$mode" = die ]; then vdir="$PRIMARY"; vhead="feat/$id"; else vdir="."; vhead=HEAD; fi
  vis="$(cfg visual "")"; shot="$(cfg shot "")"
  if [ -n "$vis" ] && [ -n "$shot" ]; then
    vhit=0
    while IFS= read -r vf; do
      [ -n "$vf" ] || continue
      if printf '%s\n' "$vis" | tr ' ' '\n' | owned_match "$vf"; then vhit=1; break; fi
    done <<EOF
$(git -C "$vdir" diff --name-only --no-renames "$BASE...$vhead")
EOF
    if [ "$vhit" -eq 1 ]; then
      vbase="$(git -C "$vdir" log -1 --format=%ct "$(git -C "$vdir" merge-base "$BASE" "$vhead")" 2>/dev/null || echo 0)"
      vok=0
      for vshot in "$PRIMARY/.polaris/shots/$id-"*.png; do
        [ -s "$vshot" ] || continue
        vmt="$(stat -c %Y "$vshot" 2>/dev/null || stat -f %m "$vshot" 2>/dev/null || echo 0)"
        if [ "${vmt:-0}" -ge "${vbase:-0}" ]; then vok=1; break; fi
      done
      if [ "$vok" -ne 1 ]; then
        vmsg="$id changed a visual: path but .polaris/shots/$id-*.png has no capture newer than the branch base — run the shot: line from pack, LOOK at the image, then hand off"
        if [ "$mode" = die ]; then die "handoff refused: $vmsg"; else note "⚠ $vmsg"; fi
      fi
    fi
  fi
}
