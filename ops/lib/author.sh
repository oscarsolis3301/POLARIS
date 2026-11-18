# POLARIS lib/author.sh — `polaris new`: drafts written from ops/templates/TASK.md become board tasks —
# IDs, checks, the ready gate with review/ counted, and ONE board commit (ops/contracts/task-author.md).

cmd_new() { # new [--retire <map>] <draft.md> [<draft.md>…] — every check first (a refusal writes nothing),
  # then IDs, placement and ONE board commit. Drafts are read, never modified, moved or deleted;
  # ops/SPRINT.md is never touched (the sprint header stays the Planner's own board commit).
  local u="usage: polaris new [--retire <map>] <draft.md> [<draft.md>…]" rmap=""
  # smooth.md § 2.3: --retire <map> retires the map's old cards in this same call and commit
  if [ "${1:-}" = "--retire" ]; then rmap="${2:-}"; [ -n "$rmap" ] || die "$u"; shift 2; fi
  [ $# -gt 0 ] || die "$u"
  # Invariant 8: a Builder's idea goes to IDEAS.md, never onto the board it is building from.
  local br; br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*) die "new: run it from the primary checkout — a builder never files work for itself";; esac
  local n=0 i=0 top=0 nb=0 a f v ids=""
  # per-draft and per-board-task arrays, plus the helpers' out-values — the _new_* helpers fill these
  # by dynamic scope, so nothing outlives the call
  local _np _nid _npts _nown _ndep _ncol _nout _nplan _bid _bcol _bown _NV _NO _NM _NX _nxt _nxl _NS _NW
  local _RP="" _RK=0 _RL="" _RS="" _nrw nd
  # smooth.md § 2.3: a draft waiting on another draft's preset id files after it, whatever order they
  # were named in — so a later draft is never refused for a dependency the call itself holds
  _new_sort "$@"; set -- "${_NS[@]}"
  # smooth.md § 1.1: the tracked files, read ONCE — the folder guides a draft gains are looked up here
  local _nls _NL='
'
  [ -z "$rmap" ] || _retire_map "$rmap"
  # The checks read the board and § 4 numbers it, so both run under the mutex, after the pull: a second
  # `new` racing this one can neither take a preset id between our check and our write, nor hand out
  # the same next number.
  mutex_on
  board_pull
  _nls="$(git -C "$PRIMARY" ls-files 2>/dev/null || true)"
  surfaces_lines >/dev/null   # the memo, filled in THIS shell: _new_auto reads it once per draft
  for a in "$@"; do _new_check "$n" "$a"; n=$((n+1)); done
  if [ -n "$_RP" ]; then   # § 2.3: § 2.1's acceptance, a draft's preset id counting as a successor
    v=""; i=0; while [ "$i" -lt "$n" ]; do v="$v ${_nid[$i]}"; i=$((i+1)); done
    _retire_check "$v"; i=0
  fi
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
  # § 2.3: the retire goes BEFORE placement reads the board, so no draft is chained to a card it replaces;
  # a draft that waited on a retired card waits on its successor instead (assumed: the § 2.1 rewiring)
  if [ -n "$_RP" ]; then
    _retire_apply "filed in its place by new --retire"
    i=0
    while [ "$i" -lt "$n" ]; do
      if _retire_deps "${_nid[$i]}" "${_ndep[$i]}"; then _ndep[$i]="$nd"; _nrw[$i]=1; fi
      i=$((i+1))
    done
    i=0
  fi
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
  board_commit "chore(board): new${ids}${_RL:+ · retire$_RL}"
  printf '%s' "$_RS"
  # The lines go out once the commit holds the tasks, BEFORE the push: if sync_board then gives up, the
  # caller still learns the IDs it filed — re-running `new` on the same drafts would file them twice.
  i=0
  while [ "$i" -lt "$n" ]; do
    printf '%s\n' "${_nout[$i]}"
    if [ -n "${_nxl[$i]:-}" ]; then printf '%s' "${_nxl[$i]}" >&2; fi   # § 1.1: stderr, so `check` pins stay put
    i=$((i+1))
  done
  # away.md § 4: a task filed in this session after the plan's approval is that plan's — bind its slug
  # to the approval on record (none on record ⇒ nothing; builtins only, no output).
  i=0
  while [ "$i" -lt "$n" ]; do _presence_bind "${_nplan[$i]}"; i=$((i+1)); done
  sync_board
  mutex_off; trap - EXIT
  # smooth.md § 1.3: advice, read off the filed cards once the board is free again — it never moves one
  _new_reach_block
}

_new_reach_block() { # _new_reach_block — § 1.3: ONE stderr block of what touches cmd_new's filed cards'
  # files without being on them; nothing at all when every card's list is empty
  local i=0 r out=""
  while [ "$i" -lt "$n" ]; do
    r="$(_card_reach "$BOARD/${_ncol[$i]}/${_nid[$i]}.md")"
    if [ -n "$r" ]; then
      out="$out$(printf '%s\n' "$r" | awk -F'\t' -v id="${_nid[$i]}" '
        function say(k, p, nm) {
          if (k == "test" && p ~ /^[0-9]+ test files$/) { sub(/ test files$/, "", p); return "   " id ": " p " test files name " nm }
          if (k == "uses" && p ~ /^[0-9]+ files$/) { sub(/ files$/, "", p); return "   " id ": " p " files use " nm }
          return "   " id ": " p (k == "test" ? " names " : " uses ") nm
        }
        NF >= 3 { print say($1, $2, $3) }')$_NL"
    fi
    i=$((i+1))
  done
  [ -n "$out" ] || return 0
  printf '%s\n%s' "files that touch these cards' files and are not on files_owned — a builder that must change one returns NEEDS PATH in its first minute:" "$out" >&2
  return 0
}

_card_names() { # _card_names <path> — its basename and its stem (minus the last .ext) onto _card_reach's names
  local b="${1##*/}"
  names="$names$b$nl"
  case "$b" in ?*.*) names="$names${b%.*}$nl";; esac
  return 0
}

_card_reach() { # _card_reach <taskfile> — smooth.md § 1.2: what touches a card's files without being on
  # them. LC_ALL=C sorted unique `<kind><TAB><path><TAB><name>` lines, kind `test` (a test file whose text
  # NAMES one of the card's files) or `uses` (a file the index says imports one); rc 0 always. Names = the
  # basename and stem of every exact owned path plus the card's replaces: items, 4 characters or more.
  # One ls-files (cmd_new's own read when it runs inside new), ONE git grep, ONE `find --importers`.
  local tf="$1" x own="" names="" exact="" globs="" s t r one="" nl='
'
  [ -f "$tf" ] || return 0
  own="$(fm_list files_owned "$tf" 2>/dev/null | grep -v '^#' || true)"
  while IFS= read -r x; do
    case "$x" in ''|*/|*'*'*) continue;; esac
    # v1.2: a folder guide the card owns is searched for by no one — every test file says CLAUDE.md somewhere
    case "$x" in CLAUDE.md|*/CLAUDE.md) continue;; esac
    exact="$exact$x$nl"; _card_names "$x"
  done <<EOF
$own
EOF
  # replaces: a path gives its basename and stem, a bare name (no /) itself
  while IFS= read -r x; do
    case "$x" in ''|'#'*) ;; */*) _card_names "$x";; *) names="$names$x$nl";; esac
  done <<EOF
$(fm_list replaces "$tf" 2>/dev/null || true)
EOF
  names="$(printf '%s' "$names" | awk 'length($0) >= 4 && !seen[$0]++')"
  [ -n "$names" ] || return 0
  surfaces_lines >/dev/null
  while IFS="$POLARIS_TAB" read -r s t r; do [ -n "$t" ] && globs="$globs$t$nl"; done <<EOF
$_SURFACES_CACHE
EOF
  # one -e per name, then the pathspecs: a superset of the test files (every rule below names test or
  # spec, plus the SURFACES globs) — the awk keeps the test files themselves
  set --
  while IFS= read -r x; do set -- "$@" -e "$x"; done <<EOF
$names
EOF
  set -- "$@" -- '*test*' '*spec*'
  while IFS= read -r x; do [ -n "$x" ] && set -- "$@" "$x"; done <<EOF
$globs
EOF
  case "$exact" in ?*"$nl"?*) ;; ?*) one="${exact%$nl}";; esac   # one path: find prints its rows unprefixed
  {
    if [ "${_nls+set}" = set ]; then printf '%s\n' "$_nls"; else git -C "$PRIMARY" ls-files 2>/dev/null || true; fi
    printf '/grep\n'   # a git path never starts with /, so the two markers cannot be a file
    git -C "$PRIMARY" -c core.quotepath=off grep -I -o -F "$@" 2>/dev/null || true
    printf '/find\n'
    if [ -n "$exact" ]; then
      # shellcheck disable=SC2086 — owned paths carry no blanks; one word each is the point
      "$SELF" find --importers $exact -n 100000 2>/dev/null || true
    fi
  } | LC_ALL=C awk -v owned="$own" -v globs="$globs" -v one="$one" '
    function g2re(g,   i, c, re) {
      re = "^"
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") re = re ".*"
        else if (c == "?") re = re "."
        else if (index(".^$+(){}|[]\\", c)) re = re "\\" c
        else re = re c
      }
      return re "$"
    }
    function covered(p,   i, o) {
      for (i = 1; i <= no; i++) {
        o = ow[i]
        if (p == o) return 1
        if (substr(o, length(o)) == "/" && index(p, o) == 1) return 1
        if (index(o, "*") && p ~ g2re(o)) return 1
      }
      return 0
    }
    function testy(p,   n, seg, i, b) {
      for (i = 1; i <= ng; i++) if (p ~ gre[i]) return 1
      n = split(p, seg, "/")
      for (i = 1; i <= n; i++) if (seg[i] ~ /^(test|tests|spec|specs|__tests__)$/) return 1
      b = seg[n]
      return (b ~ /^test_/ || b ~ /_test\./ || b ~ /\.test\./ || b ~ /\.spec\./)
    }
    function base(p,   n, seg) { n = split(p, seg, "/"); return seg[n] }
    BEGIN {
      no = split(owned, ow, "\n")
      n = split(globs, gl, "\n"); ng = 0
      for (i = 1; i <= n; i++) if (gl[i] != "") gre[++ng] = g2re(gl[i])
      sec = 0
    }
    $0 == "/grep" { sec = 1; next }
    $0 == "/find" { sec = 2; next }
    sec == 0 { if ($0 != "" && testy($0) && !covered($0)) T[$0] = 1; next }
    sec == 1 {
      i = index($0, ":"); if (!i) next
      p = substr($0, 1, i - 1); nm = substr($0, i + 1)
      if (!(p in T) || ((p SUBSEP nm) in seenT)) next
      seenT[p SUBSEP nm] = 1; tn[nm]++; tl[nm] = tl[nm] p "\n"
      next
    }
    sec == 2 {
      if (one != "") { q = one; rest = $0 } else { i = index($0, "\t"); if (!i) next; q = substr($0, 1, i - 1); rest = substr($0, i + 1) }
      i = index(rest, "\t"); if (!i) next
      loc = substr(rest, 1, i - 1); txt = substr(rest, i + 1)
      if (substr(txt, 1, 8) == "mention ") next
      sub(/:[0-9]+$/, "", loc)
      nm = base(q)
      if (loc in T || testy(loc) || covered(loc) || ((loc SUBSEP nm) in seenU)) next
      seenU[loc SUBSEP nm] = 1; un[nm]++; ul[nm] = ul[nm] loc "\n"
    }
    END {
      for (nm in tn) {
        if (tn[nm] > 25) { print "test\t" tn[nm] " test files\t" nm; continue }
        k = split(tl[nm], L, "\n"); for (i = 1; i < k; i++) print "test\t" L[i] "\t" nm
      }
      for (nm in un) {
        if (un[nm] > 25) { print "uses\t" un[nm] " files\t" nm; continue }
        k = split(ul[nm], L, "\n"); for (i = 1; i < k; i++) print "uses\t" L[i] "\t" nm
      }
    }' | LC_ALL=C sort -u
  return 0
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
  _new_val points "$p"; v="$_NV"
  # hour.md § 6: the one size rule next and drift share — 1-5, or a chain card of up to 13 with steps:
  if ! _card_ok "$v" "$(fm_list steps "$p")"; then
    case "$_CARD" in
      points) die "new: $a: points: must be 1-5, or up to 13 with steps: (got $v) — split anything bigger";;
      count) die "new: $a: steps: a card over 5 points lists its steps (2 or more, each 1-5 points)";;
      step*) die "new: $a: steps: step ${_CARD#step } is not \"<points 1-5> <what>\"";;
      *) die "new: $a: steps: steps add up to ${_CARD#sum }, points: says $v";;
    esac
  fi
  _npts[$1]="$v"
  _new_val plan "$p"; [ -n "$_NV" ] || die "new: $a: plan: is empty — every task names the plan it belongs to"
  _nplan[$1]="$_NV"
  _new_val risk "$p"
  case "$_NV" in normal|high) ;; *) die "new: $a: risk: must be normal or high (got $_NV)";; esac
  _new_own "$p"; [ -n "$_NO" ] || die "new: $a: files_owned: lists nothing"
  _new_auto; _nxt[$1]="$_NX"
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
  _new_xown "$i" "$id" "$f"
  if [ -n "$add" ] || [ -n "${_nrw[$i]:-}" ]; then x="$deps${deps:+${add:+ }}$add"; _new_deps "[${x// /, }]" "$f"; fi
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

_new_auto() { # _new_auto — smooth.md § 1.1 for the draft whose patterns are in _NO: every SURFACES row whose
  # surface can meet one of them adds its tests glob, and every folder it ADDS a file to (an exact path git
  # does not track) adds that folder's CLAUDE.md when git tracks one (never the root's). Extends _NO in place; _NX = one line per addition,
  # `tests<TAB><glob><TAB><surface>` or `guide<TAB><path>`, in that order. Builtins over cmd_new's reads.
  local own="$_NO" s t r x d
  _NX=""
  while IFS="$POLARIS_TAB" read -r s t r; do
    [ -n "$s" ] && [ -n "$t" ] || continue
    _new_meet "$own" "$s" || continue
    if _new_join "$t"; then _NX="$_NX"tests"$POLARIS_TAB$t$POLARIS_TAB$s$_NL"; fi
  done <<EOF
$_SURFACES_CACHE
EOF
  # v1.2: a guide joins only for a file the card ADDS — an exact path git does not track yet; a tracked
  # file, a glob or a dir/ entry adds none, so two cards editing different files of one folder stay apart
  while IFS= read -r x; do
    case "$x" in ''|*'*'*|*/) continue;; */*) d="${x%/*}";; *) continue;; esac
    [ -n "$d" ] || continue
    case "$_NL$_nls$_NL" in *"$_NL$x$_NL"*) continue;; esac
    case "$_NL$_nls$_NL" in *"$_NL$d/CLAUDE.md$_NL"*) ;; *) continue;; esac
    if _new_join "$d/CLAUDE.md"; then _NX="$_NX"guide"$POLARIS_TAB$d/CLAUDE.md$_NL"; fi
  done <<EOF
$own
EOF
  return 0
}

_new_join() { # _new_join <path|glob> — add it to _NO unless an owned pattern is that exact entry or already
  # covers it (owned_match semantics); rc 1 = nothing added
  local q
  while IFS= read -r q; do [ -n "$q" ] || continue
    [ "$q" = "$1" ] && return 1
    match_one "$1" "$q" && return 1
  done <<EOF
$_NO
EOF
  _NO="$_NO$1$_NL"
  return 0
}

_new_xown() { # _new_xown <i> <ID> <board file> — write draft <i>'s § 1.1 additions onto its board file and
  # word their stderr lines into _nxl[<i>]; the draft on disk is never touched
  local k p s
  _nxl[$1]=""
  while IFS="$POLARIS_TAB" read -r k p s; do [ -n "$k" ] || continue
    fm_append_item files_owned "$p" "$3" || die "new: $2: could not add $p to files_owned"
    case "$k" in
      tests) _nxl[$1]="${_nxl[$1]}   $2: owns $p too — ops/SURFACES.tsv maps $s to it$_NL";;
      *)     _nxl[$1]="${_nxl[$1]}   $2: owns $p too — the guide of a folder it adds a file to$_NL";;
    esac
  done <<EOF
${_nxt[$1]:-}
EOF
  return 0
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

_new_sort() { # _new_sort <draft>… — smooth.md § 2.3: the drafts into _NS in a stable dependency order: a
  # draft moves after every draft whose preset id: its depends_on names, otherwise the given order stands.
  # A cycle among them dies before anything is read under the mutex. A draft that cannot be read keeps
  # its place — _new_check refuses it in turn.
  local k=0 m=0 j x p v pick _sa _sid _sdep took=" " cyc seen
  for x in "$@"; do
    case "$x" in
      /*|[A-Za-z]:[\\/]*) p="$x";;
      *) if [ -f "$x" ]; then p="$PWD/$x"; else p="$PRIMARY/$x"; fi;;
    esac
    _sa[$k]="$x"; _sid[$k]=""; _sdep[$k]=""
    if [ -f "$p" ]; then
      _new_val id "$p"; case "$_NV" in T-*) _sid[$k]="$_NV";; esac
      _sdep[$k]="$(dep_ids "$p" | tr '\n' ' ')"
    fi
    k=$((k+1))
  done
  _NS=()
  while [ "$m" -lt "$k" ]; do
    pick=""; j=0
    while [ "$j" -lt "$k" ]; do
      case "$took" in *" $j "*) j=$((j+1)); continue;; esac
      if ! _new_sort_waits "$j"; then pick="$j"; break; fi
      j=$((j+1))
    done
    if [ -z "$pick" ]; then
      # every draft left waits on another one left: walk the first one's waits until one repeats
      j=0; while case "$took" in *" $j "*) true;; *) false;; esac; do j=$((j+1)); done
      seen=" "; cyc=""
      while :; do
        case "$seen" in *" $j "*) break;; esac
        seen="$seen$j "
        _new_sort_waits "$j"; j="$_NW"
      done
      v="$j"; cyc="${_sid[$v]}"
      _new_sort_waits "$v"; j="$_NW"
      while [ "$j" != "$v" ]; do cyc="$cyc → ${_sid[$j]}"; _new_sort_waits "$j"; j="$_NW"; done
      die "new: depends_on cycle among the drafts: $cyc → ${_sid[$v]}"
    fi
    _NS[$m]="${_sa[$pick]}"; took="$took$pick "; m=$((m+1))
  done
  return 0
}

_new_sort_waits() { # _new_sort_waits <j> — rc 0 when draft <j> names in depends_on the preset id of a draft
  # not yet taken (not itself); _NW = the first such draft
  local d i
  _NW=""
  for d in ${_sdep[$1]}; do
    i=0
    while [ "$i" -lt "$k" ]; do
      if [ "$i" != "$1" ] && [ "${_sid[$i]}" = "$d" ]; then
        case "$took" in *" $i "*) ;; *) _NW="$i"; return 0;; esac
      fi
      i=$((i+1))
    done
  done
  return 1
}

cmd_retire() { # retire <ID>… --by <ID> -m "why" | retire --map <file> -m "why" — smooth.md § 2.1: waiting
  # cards move aside to ops/board/retired/ for their successor, every depends_on that named them is
  # rewired, in ONE board commit. Every refusal writes nothing.
  local u='usage: polaris retire <ID>… --by <ID> -m "why"  |  retire --map <file> -m "why"'
  local by="" map="" msg="" olds="" br x _RP="" _RK=0 _RL="" _RS="" _NL='
'
  [ $# -gt 0 ] || die "$u"
  while [ $# -gt 0 ]; do case "$1" in
    --by)  by="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
    --map) map="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
    -m)    msg="${2:-}"; [ $# -ge 2 ] && shift 2 || shift;;
    -*)    die "unknown flag $1 — $u";;
    *)     olds="$olds $1"; shift;;
  esac; done
  { [ -n "$by" ] || [ -n "$map" ]; } && ! { [ -n "$by" ] && [ -n "$map" ]; } || die "$u"
  [ -z "$map" ] || [ -z "$olds" ] || die "$u"
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*) die "retire refused on $br — run it from the primary checkout";; esac
  [ -n "$msg" ] || die "retire refused: -m \"why\" is missing — the why goes on every retired card"
  if [ -n "$map" ]; then _retire_map "$map"
  else for x in $olds; do _RP="$_RP$x$POLARIS_TAB$by$_NL"; done; fi
  [ -n "$_RP" ] || die "retire refused: no card named — name at least one old ID"
  mutex_on
  board_pull
  _retire_check ""
  _retire_apply "$msg"
  if [ -n "$map" ]; then board_commit "chore(board): retire${_RL} (map)"
  else board_commit "chore(board): retire${_RL} → $by"; fi
  printf '%s' "$_RS"
  sync_board
  mutex_off; trap - EXIT
}

_retire_map() { # _retire_map <file> — the § 2.1 map into _RP: one `old<TAB>new` pair per line; blank and
  # # lines skipped, CR stripped. A line that is not exactly two fields refuses, before any write.
  local p x o w ln=0
  case "$1" in
    /*|[A-Za-z]:[\\/]*) p="$1";;
    *) if [ -f "$1" ]; then p="$PWD/$1"; else p="$PRIMARY/$1"; fi;;
  esac
  [ -f "$p" ] || die "retire refused: $1: no such file"
  while IFS= read -r x || [ -n "$x" ]; do
    ln=$((ln+1)); x="${x%$'\r'}"
    case "$x" in ''|'#'*) continue;; esac
    o="${x%%"$POLARIS_TAB"*}"; w="${x#*"$POLARIS_TAB"}"
    if [ "$o" = "$x" ] || [ -z "$o" ] || [ -z "$w" ]; then die "retire refused: $1 line $ln is not old<TAB>new"; fi
    case "$w" in *"$POLARIS_TAB"*) die "retire refused: $1 line $ln is not old<TAB>new";; esac
    _RP="$_RP$o$POLARIS_TAB$w$_NL"
  done < "$p"
  return 0
}

_retire_check() { # _retire_check <draft ids> — § 2.1's acceptance over _RP, every pair, before any write;
  # the first failure dies (under the mutex: on_die releases it). <draft ids>: preset ids of `new
  # --retire`'s drafts, which may stand as successors.
  local o w f c all=" " seen=" "
  while IFS="$POLARIS_TAB" read -r o w; do [ -n "$o" ] && all="$all$o "; done <<EOF
$_RP
EOF
  while IFS="$POLARIS_TAB" read -r o w; do [ -n "$o" ] || continue
    case "$seen" in *" $o "*) die "retire refused: $o is named twice";; esac
    seen="$seen$o "
    [ -d "$LOCKS/$o" ] && die "retire refused: $o is claimed — release it first"
    f="$(task_file "$o")" || die "retire refused: $o is no task on the board"
    c="${f%/*}"; c="${c##*/}"
    case "$c" in
      backlog|ready|blocked) ;;
      active) die "retire refused: $o is claimed — release it first";;
      *) die "retire refused: $o is in $c/ — only waiting cards retire";;
    esac
    case "$all" in *" $w "*) die "retire refused: $w is retired too";; esac
    if ! task_file "$w" >/dev/null; then
      case " $1 " in *" $w "*) ;; *) die "retire refused: $w is no task on the board";; esac
    fi
  done <<EOF
$_RP
EOF
  return 0
}

_retire_apply() { # _retire_apply <why> — § 2.1's effect for every pair of _RP: the move, its stamps, Notes
  # line and event, the empty branch; then the rewiring. Fills _RL (the old IDs, for the subject), _RK
  # (dependents rewired) and _RS (the printed lines). Writes on disk only — the caller commits.
  local o w f d x id nd dd c line
  mkdir -p "$BOARD/retired"
  _RS=""
  while IFS="$POLARIS_TAB" read -r o w; do [ -n "$o" ] || continue
    f="$(task_file "$o")"; d="$BOARD/retired/$o.md"
    mv "$f" "$d"
    fm_stamp status retired "$d"; fm_stamp retired_by "$w" "$d"
    printf -- '- retired: by %s — %s\n' "$w" "$1" >> "$d"
    evt retire "$o" "→ $w"
    _retire_branch "$o"
    _RL="$_RL $o"; _RS="${_RS}retired $o → $w$_NL"
  done <<EOF
$_RP
EOF
  # ONE awk over every waiting and open card: `<file><TAB><its depends_on ids>`, for those that have any
  _RK=0
  while IFS="$POLARIS_TAB" read -r f x; do [ -n "$f" ] || continue
    id="${f##*/}"; _retire_deps "${id%.md}" "$x" || continue
    _RK=$((_RK+1))
    _new_deps "[${nd// /, }]" "$f"
    case "$f" in */ready/*)
      for dd in $nd; do
        if [ ! -f "$BOARD/done/$dd.md" ]; then
          id="${f##*/}"; mv "$f" "$BOARD/backlog/$id"; fm_stamp status backlog "$BOARD/backlog/$id"; break
        fi
      done;;
    esac
  done <<EOF
$(_retire_scan)
EOF
  _RS="$_RS   $_RK dependent(s) rewired$_NL"
  return 0
}

_retire_deps() { # _retire_deps <ID> <ids> — rc 0 when <ids> names an old ID of _RP; nd = the rewired list:
  # each old ID becomes its successor, once, in first-appearance order, and none is the card <ID> itself
  local id="$1" x y hit=1 o w
  nd=""
  for x in $2; do
    y="$x"
    while IFS="$POLARIS_TAB" read -r o w; do
      if [ "$o" = "$x" ]; then y="$w"; hit=0; break; fi
    done <<EOF
$_RP
EOF
    [ "$y" = "$id" ] && continue
    case " $nd " in *" $y "*) continue;; esac
    nd="$nd${nd:+ }$y"
  done
  return "$hit"
}

_retire_scan() { # _retire_scan — `<file><TAB><depends_on ids, space-separated>` for every task file in
  # backlog/ ready/ active/ review/ blocked/ that lists any; ONE awk, fm_list's two list shapes
  local c f
  set --
  for c in backlog ready active review blocked; do
    for f in "$BOARD/$c/"*.md; do [ -e "$f" ] && set -- "$@" "$f"; done
  done
  [ $# -gt 0 ] || return 0
  awk -v tab="$POLARIS_TAB" '
    function flush(dummy) { gsub(/[ \t]+/, " ", d); sub(/^ /, "", d); sub(/ $/, "", d); if (fn != "" && d != "") print fn tab d }
    function ids(s) { sub(/[ \t]#.*$/, "", s); gsub(/[][,\r]/, " ", s); d = d " " s }
    FNR == 1 { flush(0); fn = FILENAME; fs = 0; on = 0; d = "" }
    /^---[\r]?$/ { fs++; on = 0; next }
    fs != 1 { next }
    index($0, "depends_on:") == 1 { on = 1; ids(substr($0, 12)); next }
    on && /^[ \t]*-[ \t]/ { s = $0; sub(/^[ \t]*-/, "", s); ids(s); next }
    on && /^[A-Za-z_]/ { on = 0 }
    END { flush(0) }' "$@"
}

_retire_branch() { # _retire_branch <ID> — delete feat/<ID> when it exists, no worktree has it checked out
  # and it holds no commit past $BASE; any other case keeps it, silently
  local b="refs/heads/feat/$1"
  git -C "$PRIMARY" show-ref -q --verify "$b" 2>/dev/null || return 0
  git -C "$PRIMARY" worktree list --porcelain 2>/dev/null | grep -qxF "branch $b" && return 0
  [ "$(git -C "$PRIMARY" rev-list --count "$BASE..feat/$1" 2>/dev/null || echo x)" = 0 ] || return 0
  git -C "$PRIMARY" branch -D "feat/$1" >/dev/null 2>&1 || true
  return 0
}
