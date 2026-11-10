# POLARIS lib/author.sh — `polaris new`: drafts written from ops/templates/TASK.md become board tasks —
# IDs, checks, the ready gate with review/ counted, and ONE board commit (ops/contracts/task-author.md).

cmd_new() { # new <draft.md> [<draft.md>…] — every check first (a refusal writes nothing), then IDs,
  # placement and ONE board commit. Drafts are read, never modified, moved or deleted; ops/SPRINT.md is
  # never touched (the sprint header stays the Planner's own board commit).
  [ $# -gt 0 ] || die "usage: polaris new <draft.md> [<draft.md>…]"
  # Invariant 8: a Builder's idea goes to IDEAS.md, never onto the board it is building from.
  local br; br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*) die "new: run it from the primary checkout — a builder never files work for itself";; esac
  local n=0 i=0 top=0 nb=0 a f v ids=""
  # per-draft and per-board-task arrays, plus the helpers' out-values — the _new_* helpers fill these
  # by dynamic scope, so nothing outlives the call
  local _np _nid _npts _nown _ndep _ncol _nout _nplan _bid _bcol _bown _NV _NO _NM
  # The checks read the board and § 4 numbers it, so both run under the mutex, after the pull: a second
  # `new` racing this one can neither take a preset id between our check and our write, nor hand out
  # the same next number.
  mutex_on
  board_pull
  for a in "$@"; do _new_check "$n" "$a"; n=$((n+1)); done
  # § 4: next free = 1 + the highest number on the board or already taken by this call. The checks took
  # every preset id, so an assigned one can never land on a later draft's preset.
  for f in "$BOARD"/*/T-*.md; do [ -e "$f" ] || continue; v="${f##*/T-}"; _new_top "${v%.md}"; done
  while [ "$i" -lt "$n" ]; do _new_top "${_nid[$i]#T-}"; i=$((i+1)); done
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ -z "${_nid[$i]}" ]; then
      top=$((top+1))
      case "${#top}" in 1) _nid[$i]="T-00$top";; 2) _nid[$i]="T-0$top";; *) _nid[$i]="T-$top";; esac
    fi
    i=$((i+1))
  done
  # § 5 places every draft against ready/ active/ review/ AS THIS CALL FOUND THEM (read once, here, before
  # the first write) plus the drafts placed before it — so no draft is ever counted twice.
  for v in ready active review; do
    for f in "$BOARD/$v/"*.md; do [ -e "$f" ] || break
      a=""; IFS= read -r a < "$f" || true
      [ "${a%$'\r'}" = "---" ] || continue
      a="${f##*/}"; _bid[$nb]="${a%.md}"; _bcol[$nb]="$v"
      _new_own "$f"; _bown[$nb]="$_NO"; nb=$((nb+1))
    done
  done
  i=0
  while [ "$i" -lt "$n" ]; do _new_place "$i"; ids="$ids ${_nid[$i]}"; i=$((i+1)); done
  # the moved set carries EVENTS.ndjson, so every `evt new` rides this one commit
  board_commit "chore(board): new${ids}"
  # The lines go out once the commit holds the tasks, BEFORE the push: if sync_board then gives up, the
  # caller still learns the IDs it filed — re-running `new` on the same drafts would file them twice.
  i=0
  while [ "$i" -lt "$n" ]; do printf '%s\n' "${_nout[$i]}"; i=$((i+1)); done
  # away.md § 4: a task filed in this session after the plan's approval is that plan's — bind its slug
  # to the approval on record (none on record ⇒ nothing; builtins only, no output).
  i=0
  while [ "$i" -lt "$n" ]; do _presence_bind "${_nplan[$i]}"; i=$((i+1)); done
  sync_board
  mutex_off; trap - EXIT
}

_new_check() { # _new_check <i> <arg> — § 3 for ONE draft, in the contract's order; the first failure dies
  # (under the mutex: on_die releases it, and nothing has been written yet). Records what § 4-§ 6 need.
  local a="$2" p v x dl=""
  case "$a" in
    /*|[A-Za-z]:[\\/]*) p="$a";;
    *) if [ -f "$a" ]; then p="$PWD/$a"; else p="$PRIMARY/$a"; fi;;
  esac
  [ -f "$p" ] || die "new: $a: no such file"
  # a string test, not a path compare: $PWD (/c/…) and $PRIMARY (C:/…) spell one folder two ways on Git Bash
  case "/$p" in *[\\/]ops[\\/]board[\\/]*) die "new: $a: is inside ops/board/ — a draft lives outside the board";; esac
  v=""; IFS= read -r v < "$p" || true
  [ "${v%$'\r'}" = "---" ] || die "new: $a: no frontmatter — the first line must be ---"
  _new_val title "$p"; [ -n "$_NV" ] || die "new: $a: title: is empty"
  _new_val points "$p"
  case "$_NV" in [1-5]) ;; *) die "new: $a: points: must be 1-5 (got $_NV) — split anything bigger";; esac
  _npts[$1]="$_NV"
  _new_val plan "$p"; [ -n "$_NV" ] || die "new: $a: plan: is empty — every task names the plan it belongs to"
  _nplan[$1]="$_NV"
  _new_val risk "$p"
  case "$_NV" in normal|high) ;; *) die "new: $a: risk: must be normal or high (got $_NV)";; esac
  _new_own "$p"; [ -n "$_NO" ] || die "new: $a: files_owned: lists nothing"
  _new_val contract "$p"
  [ -z "$_NV" ] || [ -f "$PRIMARY/$_NV" ] || die "new: $a: contract: $_NV does not exist"
  _new_val id "$p"; v="$_NV"; x="${v#T-}"
  case "$v" in
    ''|XXX-000) v="";;
    T-*) case "$x" in ''|*[!0-9]*) die "new: $a: id: $v is not T-<number>";; esac;;
    *) die "new: $a: id: $v is not T-<number>";;
  esac
  if [ -n "$v" ]; then
    if task_file "$v" >/dev/null || _new_held "$v" "$1"; then die "new: $a: id: $v is taken"; fi
  fi
  while IFS= read -r x; do [ -n "$x" ] || continue
    task_file "$x" >/dev/null || _new_held "$x" "$1" || die "new: $a: depends_on: $x is no task on the board"
    dl="$dl${dl:+ }$x"
  done <<EOF
$(dep_ids "$p")
EOF
  _np[$1]="$p"; _nid[$1]="$v"; _nown[$1]="$_NO"; _ndep[$1]="$dl"
  return 0
}

_new_place() { # _new_place <i> — § 5 + § 6 for draft <i>: a shared file joins depends_on, then the ready
  # gate (Invariant 2 plus review/), the task file, its event and its line. Drafts before it are on disk.
  local i="$1" k=0 d c x ask="" dw="" aw="" add="" f
  local id="${_nid[$1]}"
  local own="${_nown[$1]}"
  local deps="${_ndep[$1]}"
  while [ "$k" -lt "$nb" ]; do _new_add "${_bid[$k]}" "${_bcol[$k]}" "${_bown[$k]}"; k=$((k+1)); done
  k=0
  while [ "$k" -lt "$i" ]; do _new_add "${_nid[$k]}" "${_ncol[$k]}" "${_nown[$k]}"; k=$((k+1)); done
  for d in $deps; do
    [ -f "$BOARD/done/$d.md" ] && continue
    c=""; for x in active review ready blocked backlog; do [ -f "$BOARD/$x/$d.md" ] && { c="$x"; break; }; done
    dw="${dw:+$dw, }$d ($c)"
  done
  # The ask gate, strictest first: with no task (`-`) no approval counts, so a clear answer there is the
  # answer. Only a hit is asked again with the ID, once the file is on the board — rules_gate reads the
  # task's own approved: entries from there, and an entry the draft carried may settle the question.
  _new_ask "$own" -
  c=ready; if [ -n "$dw$aw$ask" ]; then c=backlog; fi
  f="$BOARD/$c/$id.md"
  cp "${_np[$i]}" "$f"
  fm_stamp id "$id" "$f"; fm_stamp status "$c" "$f"
  if [ -n "$add" ]; then x="$deps${deps:+ }$add"; _new_deps "[${x// /, }]" "$f"; fi
  _new_wsjf "${_np[$i]}" "${_npts[$i]}"
  if [ -n "$_NV" ]; then fm_stamp wsjf "$_NV" "$f"; fi
  if [ -n "$ask" ]; then
    _new_ask "$own" "$id"
    if [ -z "$dw$aw$ask" ]; then mv "$f" "$BOARD/ready/$id.md"; set_fm status ready "$BOARD/ready/$id.md"; c=ready; fi
  fi
  _ncol[$i]="$c"
  evt new "$id" "$c" "${_npts[$i]}"
  x="$dw${dw:+${aw:+, }}$aw"
  if [ "$c" = ready ]; then x="nothing to wait for"
  else
    x="${x:+waits on $x}"
    if [ -n "$ask" ]; then x="${x:+$x; }needs a human's yes for $ask first"; fi
  fi
  _nout[$i]="$id $c — $x"
  return 0
}

_new_add() { # _new_add <ID> <column> <patterns> — § 5: a task sharing a file with the draft joins its
  # depends_on, once, in the order found. Reads and extends _new_place's own/deps/add/aw.
  case " $deps $add " in *" $1 "*) return 0;; esac
  _new_meet "$own" "$3" || return 0
  add="$add${add:+ }$1"; aw="${aw:+$aw, }$1 ($2, shares $_NM)"
  return 0
}

_new_ask() { # _new_ask <patterns> <ID|-> — _new_place's `ask` = the scope of the first `ask` rule one of
  # the patterns hits that <ID> holds no approval for (rules_gate: `path` rules never decide placement)
  local p
  ask=""
  while IFS= read -r p; do [ -n "$p" ] || continue
    if rules_gate "$p" "$2" && [ "$RULES_GATE" = "ask" ]; then ask="$RULES_GATE_SCOPE"; return 0; fi
  done <<EOF
$1
EOF
  return 0
}

_new_meet() { # _new_meet <patterns> <patterns> — rc 0 when pat_overlap says one of A's can meet one of
  # B's; _NM = the FIRST of A's that does (the pattern a waits-on line names).
  local pa pb
  _NM=""
  while IFS= read -r pa; do [ -n "$pa" ] || continue
    while IFS= read -r pb; do [ -n "$pb" ] || continue
      if pat_overlap "$pa" "$pb"; then _NM="$pa"; return 0; fi
    done <<EOF_B
$2
EOF_B
  done <<EOF_A
$1
EOF_A
  return 1
}

_new_val() { # _new_val <key> <file> — fm_get into _NV, except that a #-led value reads empty: TASK.md
  # ships unset keys as `points:   # 1,2,3,5 …`, and fm_get keeps a comment that starts the value.
  _NV="$(fm_get "$1" "$2")"
  case "$_NV" in '#'*) _NV="";; esac
  return 0
}

_new_own() { # _new_own <file> — files_owned as patterns into _NO (newline list); a blank item or a #-led
  # one (TASK.md's comments, which fm_list keeps) is no pattern.
  local x
  _NO=""
  while IFS= read -r x; do
    case "$x" in ''|'#'*) ;; *) _NO="$_NO$x
";; esac
  done <<EOF
$(fm_list files_owned "$1")
EOF
  return 0
}

_new_held() { # _new_held <ID> <n> — rc 0 when one of the first <n> drafts of this call holds <ID>
  local j=0
  while [ "$j" -lt "$2" ]; do [ "${_nid[$j]}" = "$1" ] && return 0; j=$((j+1)); done
  return 1
}

_new_top() { # _new_top <digits> — raise cmd_new's `top` to this number (leading zeros read as base 10)
  case "$1" in ''|*[!0-9]*) return 0;; esac
  if [ $((10#$1)) -gt "$top" ]; then top=$((10#$1)); fi
  return 0
}

_new_wsjf() { # _new_wsjf <draft> <points> — § 6: the wsjf to stamp into _NV, or "" when the draft set
  # one already or value / time_criticality / risk_opportunity is not a number
  local s="" k
  _new_val wsjf "$1"; [ -z "$_NV" ] || { _NV=""; return 0; }
  for k in value time_criticality risk_opportunity; do
    _new_val "$k" "$1"
    case "$_NV" in ''|.|*[!0-9.]*|*.*.*) _NV=""; return 0;; esac
    s="$s${s:++}$_NV"
  done
  _NV="$(LC_ALL=C awk "BEGIN { printf \"%.2f\", ($s) / $2 }")"   # C: a decimal point, never a comma
  return 0
}

_new_deps() { # _new_deps <[A, B]> <file> — § 6: depends_on as ONE inline line, the block items under it
  # dropped (fm_list's block: item lines until the next top-level key); added before the closing ---.
  local tmp="$2.tmp.$$"
  awk -v v="$1" '
    /^---[\r]?$/ { fs++; if (fs==2 && !hit) { print "depends_on: " v; hit=1 } on=0; print; next }
    fs==1 && index($0, "depends_on:")==1 { print "depends_on: " v; hit=1; on=1; next }
    on && /^[ \t]*-([ \t\r]|$)/ { next }
    on && /^[A-Za-z_]/ { on=0 }
    { print }' "$2" > "$tmp" && mv "$tmp" "$2"
}
