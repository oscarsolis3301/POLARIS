# POLARIS lib/tune.sh — the tune-up (ops/contracts/tune.md). `polaris tune` reads what a project
# already has and prints one line per thing that slows it, each with the one step that fixes it, then
# writes the verdict cache the routers read for free. `polaris fold` turns a chain of waiting cards into
# ONE chain card in one board commit. Both mechanical and model-free; neither ever edits
# ops/CONVENTIONS.md, ops/RULES.tsv or anything under ~/.claude — settings come back as proposals.

_tune_rows() { # _tune_rows <task.md…> — ONE awk over the frontmatter: per card file one row
  # id TAB plan TAB points TAB steps(0|1) TAB risk TAB contract TAB deps (space-led). Scalars read as
  # fm_get reads them (first match, " #" comment stripped) with one pair of quotes dropped; deps as
  # dep_ids gives them. A file with no frontmatter (IDEAS.md) has no row.
  [ $# -gt 0 ] || return 0
  awk -v q="'" '
    function val(s,   c) {
      sub(/[ \t]#.*$/, "", s); sub(/^[ \t]*/, "", s); sub(/[ \t\r]*$/, "", s)
      c = substr(s, 1, 1)
      if (length(s) > 1 && (c == "\"" || c == q) && substr(s, length(s), 1) == c) s = substr(s, 2, length(s) - 2)
      return s
    }
    function dep(s,   n, j, p) {
      sub(/[ \t]#.*$/, "", s); gsub(/\[/, " ", s); gsub(/\]/, " ", s); gsub(/[,\t\r"]/, " ", s); gsub(q, " ", s)
      n = split(s, p, " ")
      for (j = 1; j <= n; j++) if (p[j] != "") dl = dl " " p[j]
    }
    function flush(   id) {
      if (fn == "" || fs < 1) return
      id = fn; sub(/.*[\/\\]/, "", id); sub(/\.md$/, "", id)
      printf "%s\t%s\t%s\t%d\t%s\t%s\t%s\n", id, v["plan"], v["points"], st, v["risk"], v["contract"], dl
    }
    BEGIN { split("plan points risk contract", sk, " ") }
    FNR == 1 { flush(); fn = FILENAME; fs = 0; on = ""; dl = ""; st = 0; split("", v); split("", got) }
    /^---[\r]?$/ { fs++; next }
    fs != 1 { next }
    {
      for (j = 1; j <= 4; j++) if (!(sk[j] in got) && index($0, sk[j] ":") == 1) {
        v[sk[j]] = val(substr($0, length(sk[j]) + 2)); got[sk[j]] = 1
      }
      if (index($0, "depends_on:") == 1) { on = "d"; dep(substr($0, 12)); next }
      if (index($0, "steps:") == 1) {
        on = "s"; s = val(substr($0, 7)); if (s != "" && s != "[]") st = 1
        next
      }
      if (on != "" && $0 ~ /^[ \t]*-[ \t]/) {
        if (on == "d") { s = $0; sub(/^[ \t]*-[ \t]*/, "", s); dep(s) } else st = 1
        next
      }
      if (on != "" && $0 ~ /^[A-Za-z_]/) on = ""
    }
    END { flush() }' "$@" 2>/dev/null || true
}

_tune_chains() { # _tune_chains <done-ids, space-led and -trailed> — stdin = _tune_rows of the OPEN cards.
  # tune.md § 1's foldable chains (depends_on only): Ci-1 → Ci when both have points 1–5 and no steps:,
  # one plan, one risk, one contract; Ci depends on Ci-1 and on no other non-done card; Ci-1 is depended
  # on by no open card but Ci. Cut greedily from the head at a 13-point sum; a single card is no chain.
  # Prints, plans in LC_ALL=C order: `P<TAB>plan<TAB>open cards<TAB>members<TAB>chains`, then one
  # `C<TAB><ID> <ID>…` line per chain of that plan, in head order.
  awk -F'\t' -v done="$1" '
    function ok(i,   p) { p = pt[i]; return (p ~ /^[0-9]+$/ && p + 0 >= 1 && p + 0 <= 5 && st[i] == 0) }
    function emit(pl, s, len) {
      if (len < 2) return
      if (!(pl in nch)) { np++; pls[np] = pl }
      nch[pl]++; ch[pl, nch[pl]] = s; mem[pl] += len
    }
    {
      n++; id[n] = $1; pln[n] = $2; pt[n] = $3; st[n] = $4; rk[n] = $5; ct[n] = $6; dp[n] = $7
      at[$1] = n; if ($2 != "") open_[$2]++
    }
    END {
      for (i = 1; i <= n; i++) {
        k = split(dp[i], p, " "); nd[i] = 0
        for (j = 1; j <= k; j++) {
          if (index(done, " " p[j] " ")) continue
          nd[i]++; dk[i] = p[j]
          if (p[j] in at) { by[p[j]]++; last[p[j]] = i }
        }
      }
      for (i = 1; i <= n; i++) {
        if (nd[i] != 1 || !(dk[i] in at)) continue
        x = at[dk[i]]
        if (by[id[x]] != 1 || last[id[x]] != i) continue
        if (!ok(x) || !ok(i) || pln[x] == "" || pln[x] != pln[i] || rk[x] != rk[i] || ct[x] != ct[i]) continue
        nx[x] = i; hasp[i] = 1
      }
      for (i = 1; i <= n; i++) {
        if (hasp[i] || !(i in nx)) continue
        s = ""; len = 0; sum = 0; c = i; guard = 0
        while (c != "" && guard++ < n) {
          if (len > 0 && sum + pt[c] > 13) { emit(pln[i], s, len); s = ""; len = 0; sum = 0 }
          s = s (s == "" ? "" : " ") id[c]; len++; sum += pt[c]
          c = (c in nx) ? nx[c] : ""
        }
        emit(pln[i], s, len)
      }
      for (i = 2; i <= np; i++) { x = pls[i]; j = i - 1; while (j > 0 && pls[j] > x) { pls[j + 1] = pls[j]; j-- } pls[j + 1] = x }
      for (i = 1; i <= np; i++) {
        pl = pls[i]; printf "P\t%s\t%d\t%d\t%d\n", pl, open_[pl], mem[pl], nch[pl]
        for (j = 1; j <= nch[pl]; j++) printf "C\t%s\n", ch[pl, j]
      }
    }'
}

_tune_open() { # _tune_open — the OPEN card files (ready/ + backlog/, no lock under $LOCKS/<ID>), one per
  # line. Builtins only: a glob and a directory test per file, never a fork per card.
  local f id
  for f in "$BOARD/ready"/*.md "$BOARD/backlog"/*.md; do
    [ -f "$f" ] || continue
    id="${f##*/}"; id="${id%.md}"
    [ -d "$LOCKS/$id" ] && continue
    printf '%s\n' "$f"
  done
}

_tune_done() { # _tune_done — the IDs in done/, space-led and space-trailed (for an index() membership test)
  local f id s=" "
  for f in "$BOARD/done"/*.md; do [ -f "$f" ] || continue; id="${f##*/}"; s="$s${id%.md} "; done
  printf '%s' "$s"
}

_tune_review_days() { # _tune_review_days — whole days since the oldest review/ card's last `handoff`, ≥ 0
  local f id ids=" "
  for f in "$BOARD/review"/*.md; do [ -f "$f" ] || continue; id="${f##*/}"; ids="$ids${id%.md} "; done
  [ -f "$EVENTS" ] || { printf '0'; return 0; }
  awk -v ids="$ids" -v now="$(date +%s)" '
    index($0, "\"ev\":\"handoff\"") {
      if (!match($0, /"id":"[^"]*"/)) next
      i = substr($0, RSTART + 6, RLENGTH - 7); if (!index(ids, " " i " ")) next
      if (!match($0, /"ts":[0-9]+/)) next
      t = substr($0, RSTART + 5, RLENGTH - 5) + 0; if (t > h[i]) h[i] = t
    }
    END { m = -1; for (i in h) if (m < 0 || h[i] < m) m = h[i]
          d = (m < 0) ? 0 : int((now - m) / 86400); if (d < 0) d = 0; printf "%d", d }' "$EVENTS" 2>/dev/null || printf '0'
}

_tune_behind() { # _tune_behind — tune.md § 5: TUNE_WHY + TUNE_STEP, the first reason an install has not updated
  local n
  if ! board_quiescent inflight; then
    case "$QUIET_WHY" in
      "active: "*) TUNE_WHY="${QUIET_WHY#active: } card(s) still building"
                   TUNE_STEP="it updates when they land — nothing to do";;
      "review: "*) n="${QUIET_WHY#review: }"
                   TUNE_WHY="$n card(s) wait to land, the oldest for $(_tune_review_days) day(s)"
                   TUNE_STEP="land them or kick them back: bash ops/polaris next";;
      "lock: "*)   n="${QUIET_WHY#lock: }"
                   TUNE_WHY="a claim on $n is still held"
                   TUNE_STEP="finish it, or: bash ops/polaris release $n";;
      "bg job running: "*) TUNE_WHY="a background job is running (${QUIET_WHY#bg job running: })"
                   TUNE_STEP="it updates when the job ends";;
      *)           TUNE_WHY="the landing lane is held"
                   TUNE_STEP="it frees itself after integration_stale_minutes";;
    esac
  elif git -C "$PRIMARY" status --porcelain 2>/dev/null | update_dirt_overlaps_kit; then
    TUNE_WHY="uncommitted edits inside the kit's own files"
    TUNE_STEP="commit or stash them, then: bash ops/polaris update"
  else
    TUNE_WHY="nothing holds it"; TUNE_STEP="bash ops/polaris update"
  fi
}

cmd_tune() { # tune — tune.md § 1: one line per thing that slows this project, each with its fix line(s).
  # rc 0 = nothing (one line) · rc 1 = findings · rc 2 = usage (cache untouched). Read-only on the
  # board, the repo and config; its ONE write is .polaris/tune-due (§ 2), on every rc 0/1 run.
  if [ $# -gt 0 ]; then printf 'usage: polaris tune\n' >&2; return 2; fi
  local sha kinds="" nk=0 due=1 rows done_ chains tag a b c d e T
  local hf="$PRIMARY/.polaris/hops-due" hs="" hv="" hm="" v ev e1 e2 e3 e4 e5 e6 e7 e8 er
  local s="" nopen=0 t cur latest sb
  sha="$(git -C "$PRIMARY" rev-parse --verify -q "$BASE" 2>/dev/null || true)"
  _tk() { kinds="$kinds${kinds:+,}$1"; nk=$((nk + 1)); }

  # cards — the open cards, ONE awk for their frontmatter, ONE for the chains
  local f
  set --
  while IFS= read -r f; do [ -n "$f" ] && set -- "$@" "$f"; done <<EOF
$(_tune_open)
EOF
  rows="$(_tune_rows "$@")"
  [ -n "$rows" ] && nopen="$(printf '%s\n' "$rows" | awk 'END { print NR }')"
  if [ -n "$rows" ]; then
    done_="$(_tune_done)"
    chains="$(printf '%s\n' "$rows" | _tune_chains "$done_")"
    if [ -n "$chains" ]; then
      _tk cards; due=0
      while IFS="$POLARIS_TAB" read -r tag a b c d; do
        case "$tag" in
          P) T="$(_speed_plan "$a" 2>/dev/null | sed -n 's/^projected: about \(.*\) (target.*/\1/p' || true)"
             printf 'cards: plan %s — %s open cards, projected about %s; %s of them fold into %s chain card(s)\n' \
               "$a" "$b" "${T:-?}" "$c" "$d";;
          C) printf '   fix: bash ops/polaris fold %s\n' "$a";;
        esac
      done <<EOF
$chains
EOF
    fi
  fi

  # layout — the hops verdict cache, read exactly as save-hops.md § 0.5 says. A missing cache, or one
  # naming a commit other than the base's now (the update's own commit moves the base right after heal
  # wrote it), is refreshed ONCE first — silently, never failing tune (tune.md § 2, 2026-11-17 note).
  if [ -n "$sha" ] && [ "$(cfg hops on)" != off ]; then
    hs=""; [ -f "$hf" ] && { IFS="$POLARIS_TAB" read -r hs hv hm < "$hf" 2>/dev/null || true; }
    [ "${hs%$'\r'}" = "$sha" ] || "$SELF" hops --due >/dev/null 2>&1 || true
    hs="" hv="" hm=""
  fi
  if [ -f "$hf" ]; then
    IFS="$POLARIS_TAB" read -r hs hv hm < "$hf" 2>/dev/null || true
    hs="${hs%$'\r'}"; hv="${hv%$'\r'}"; hm="${hm%$'\r'}"
    if [ "$hv" = 0 ] && [ -n "$hs" ] && [ "$hs" = "$sha" ] && [ "$(cfg hops on)" != off ]; then
      _tk layout; due=0
      printf 'layout: %s\n   fix: the layout pass — run bash ops/polaris role TIDY\n' "${hm#layout pass due — }"
    fi
  fi

  # lanes — autolaunch_max above the lane count that lands the most cards per hour here
  v="$(cfg autolaunch_max "")"
  case "$v" in
    ''|*[!0-9]*) ;;
    *) ev="$(_speed_ev plan)"
       read -r e1 e2 e3 e4 e5 e6 e7 e8 er <<EOF || true
$ev
EOF
       if [ -n "${e8:-}" ] && [ "${e3:-0}" -gt 0 ] 2>/dev/null && [ "$e3" -lt "$v" ]; then
         _tk lanes
         printf 'lanes: autolaunch_max: %s, but %s lanes is the most cards per hour here\n' "$v" "$e3"
         printf '   fix: proposal — set autolaunch_max: %s in ops/CONVENTIONS.md\n' "$e3"
       fi;;
  esac

  # landing + checks — both priced with the last full run (.polaris/last-suite-seconds)
  if [ -f "$PRIMARY/.polaris/last-suite-seconds" ]; then
    read -r s t < "$PRIMARY/.polaris/last-suite-seconds" 2>/dev/null || true
    s="${s%$'\r'}"; case "$s" in ''|*[!0-9]*) s="";; esac
  fi
  if [ -n "$s" ] && [ "$s" -gt 120 ] && [ "$nopen" -ge 1 ] && [ "$(cfg integration "")" = paranoid ]; then
    _tk landing
    printf 'landing: integration: paranoid runs the whole suite on every card — about %s min across %s open cards\n' \
      "$(( (nopen * s + 30) / 60 ))" "$nopen"
    printf '   fix: proposal — set integration: batch in ops/CONVENTIONS.md\n'
  fi
  if [ -n "$s" ] && [ "$s" -gt 180 ] && [ -z "$(cfg test_fast "")" ]; then
    if [ "$s" -lt 60 ]; then t="${s}s"; else t="$(( (s + 30) / 60 ))m"; fi
    _tk checks
    printf 'checks: no test_fast: and the whole suite takes %s\n' "$t"
    printf '   fix: proposal — set test_fast: to a command that finishes in under a minute\n'
  fi

  # behind — a newer kit on the channel (the cached daily answer), and why it has not arrived
  if [ ! -f "$PRIMARY/kit/ops/pack.py" ]; then
    cur="$(ver version 2>/dev/null || true)"
    if [ -n "$cur" ]; then
      latest="$(update_latest 2>/dev/null || true)"
      if [ -n "$latest" ] && semver_gt "$latest" "$cur"; then
        TUNE_WHY=""; TUNE_STEP=""; _tune_behind
        _tk behind
        printf 'behind: kit %s, channel %s — %s\n   fix: %s\n' "$cur" "$latest" "$TUNE_WHY" "$TUNE_STEP"
      fi
    fi
  fi

  # context — slim's report (nothing moved): the machinery every context pays for
  sb="$( (cmd_slim) 2>/dev/null | awk '/MACHINERY — archived by --apply/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }' || true)"
  if [ -n "$sb" ] && [ "$sb" -gt 8192 ]; then
    _tk context
    printf 'context: %s bytes of unused definitions under ~/.claude, paid by every context\n' "$sb"
    printf '   fix: proposal — bash ops/polaris slim --apply\n'
  fi

  mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' "$sha" "$due" "$nk" "${kinds:--}" > "$PRIMARY/.polaris/tune-due" 2>/dev/null || true
  if [ "$nk" -eq 0 ]; then printf 'tune: nothing to slow this project down\n'; return 0; fi
  return 1
}

_tune_lists() { # _tune_lists <key,key…> <task.md…> — ONE awk: per list item `id US key US item` (US = \037),
  # items read exactly as fm_list reads them (block list, inline flow list, [], or an inline scalar).
  local ks="$1"; shift
  [ $# -gt 0 ] || return 0
  awk -v ks="$ks" '
    function out(s,   n, i, p, it) {
      if (s == "") return
      if (s ~ /^\[.*\]$/) {
        s = substr(s, 2, length(s) - 2); n = split(s, p, ",")
        for (i = 1; i <= n; i++) { it = p[i]; sub(/^[ \t]*/, "", it); sub(/[ \t]*$/, "", it); if (it != "") printf "%s\037%s\037%s\n", id, on, it }
        return
      }
      printf "%s\037%s\037%s\n", id, on, s
    }
    BEGIN { nk = split(ks, kk, ",") }
    FNR == 1 { fs = 0; on = ""; id = FILENAME; sub(/.*[\/\\]/, "", id); sub(/\.md$/, "", id) }
    /^---[\r]?$/ { fs++; on = ""; next }
    fs != 1 { next }
    /^[A-Za-z_]/ {
      on = ""
      for (j = 1; j <= nk; j++) if (index($0, kk[j] ":") == 1) {
        on = kk[j]; s = substr($0, length(on) + 2)
        sub(/[ \t]#.*$/, "", s); sub(/^[ \t]*/, "", s); sub(/[ \t\r]*$/, "", s); out(s)
      }
      next
    }
    on != "" && /^[ \t]*-[ \t]/ {
      s = $0; sub(/[ \t]#.*$/, "", s); sub(/^[ \t]*-[ \t]*/, "", s); sub(/[ \t\r]*$/, "", s)
      if (s != "") printf "%s\037%s\037%s\n", id, on, s
    }' "$@" 2>/dev/null || true
}

_fold_pick() { # _fold_pick <key> <lists> — the items of <key> in first-appearance order, de-duplicated
  printf '%s\n' "$2" | awk -F'\037' -v k="$1" '$2 == k && !seen[$3]++ { print $3 }'
}

_fold_items() { # _fold_items <ID> <key> <lists> — one card's items of <key>, in order
  printf '%s\n' "$3" | awk -F'\037' -v i="$1" -v k="$2" '$1 == i && $2 == k { print $3 }'
}

_fold_write() { # _fold_write <blocks-file> <task.md> — rewrite the frontmatter keys the blocks file names
  # (`@@<key>` then that key's lines), each in place where the card has it, the rest before the closing
  # ---; a replaced key's own continuation lines (its list items) go with it. The body is untouched.
  local tmp="$2.tmp.$$"
  awk '
    FNR == NR { if (index($0, "@@") == 1) { k = substr($0, 3); nk++; ord[nk] = k; b[k] = ""; next }
                b[k] = b[k] $0 "\n"; next }
    /^---[\r]?$/ { fs++
      if (fs == 2) for (i = 1; i <= nk; i++) if (!(ord[i] in hit)) printf "%s", b[ord[i]]
      skip = 0; print; next }
    fs == 1 && /^[A-Za-z_]/ {
      skip = 0
      for (i = 1; i <= nk; i++) if (index($0, ord[i] ":") == 1) { printf "%s", b[ord[i]]; hit[ord[i]] = 1; skip = 1; break }
      if (skip) next
    }
    fs == 1 && skip && /^[ \t]/ { next }
    { print }' "$1" "$2" > "$tmp" && mv "$tmp" "$2"
}

_fold_block() { # _fold_block <key> <items, one per line> — one key as a block list (`key: []` when empty)
  local x
  if [ -z "$2" ]; then printf '@@%s\n%s: []\n' "$1" "$1"; return 0; fi
  printf '@@%s\n%s:\n' "$1" "$1"
  while IFS= read -r x; do [ -n "$x" ] && printf '  - %s\n' "$x"; done <<EOF
$2
EOF
  return 0
}

_fold_sect() { # _fold_sect <task.md> — the body's `## Why` and `## Acceptance criteria` text, verbatim,
  # each under a `#### <name>` line (a step block sits under the survivor's own `##` sections)
  awk '
    /^---[\r]?$/ && fs < 2 { fs++; next }
    fs < 2 { next }
    /^## / { on = 0; h = $0; sub(/[ \t\r]*$/, "", h)
             if (h == "## Why" || index(h, "## Acceptance criteria") == 1) { on = 1; print "#### " substr(h, 4); next } }
    on { print }' "$1"
}

_fold_cycle() { # _fold_cycle <ids, space-led and -trailed> — stdin = _tune_rows of the board. Prints the first
  # card outside the group that depends on a member Cj AND is depended on by a later member, as a reason.
  awk -F'\t' -v ids="$1" '
    { d[$1] = $7 }
    END {
      n = split(ids, m, " "); for (i = 1; i <= n; i++) pos[m[i]] = i
      for (l = 1; l <= n; l++) {
        k = split(d[m[l]], p, " ")
        for (a = 1; a <= k; a++) {
          o = p[a]; if ((o in pos) || !(o in d)) continue
          z = split(d[o], q, " ")
          for (b = 1; b <= z; b++) if ((q[b] in pos) && pos[q[b]] < l) { print o " depends on " q[b] " and " m[l] " depends on " o; exit }
        }
      }
    }'
}

_fold_rewire() { # _fold_rewire <ids> <folded, space-led and -trailed> <survivor> — stdin = _tune_rows of the
  # board. Per card outside the group that names a folded ID: `id TAB new deps` (the survivor once).
  awk -F'\t' -v ids="$1" -v fd="$2" -v c1="$3" '
    index(ids, " " $1 " ") { next }
    { k = split($7, p, " "); hit = 0; s = ""; split("", seen)
      for (a = 1; a <= k; a++) {
        o = p[a]; if (index(fd, " " o " ")) { o = c1; hit = 1 }
        if (!(o in seen)) { seen[o] = 1; s = s (s == "" ? "" : ", ") o }
      }
      if (hit) printf "%s\t%s\n", $1, s }'
}

cmd_fold() { # fold <ID> <ID>… — tune.md § 4: a chain of waiting cards becomes ONE chain card, C1 in place.
  # Every check runs before anything is written (a refusal writes nothing, rc 1). ONE board commit holds
  # it all, so one `git revert` of that commit puts every card back.
  local u='usage: polaris fold <ID> <ID>…'
  [ $# -ge 2 ] || die "$u"
  local ids=" " id f col n=0 i j sum=0 x y rows lists all owned deps="" tmp folded="" t w s3="" okn=1
  local -a F I PL PT ST RK CT DP TT
  for id in "$@"; do
    case "$ids" in *" $id "*) die "fold refused: $id is named twice";; esac
    ids="$ids$id "
    f=""; for col in ready backlog; do [ -f "$BOARD/$col/$id.md" ] && f="$BOARD/$col/$id.md"; done
    [ -n "$f" ] || die "fold refused: $id is not in ready/ or backlog/ (state: $(task_col "$id" || echo unknown))"
    [ -d "$LOCKS/$id" ] && die "fold refused: $id is claimed — its lock is held"
    F[n]="$f"; I[n]="$id"; n=$((n + 1))
  done
  rows="$(_tune_rows "${F[@]}" | tr '\t' '\037')"
  i=0
  while IFS=$'\037' read -r x PL[i] PT[i] ST[i] RK[i] CT[i] DP[i]; do
    [ -n "$x" ] && i=$((i + 1))
  done <<EOF
$rows
EOF
  [ "$i" -eq "$n" ] || die "fold refused: a card named has no frontmatter"
  i=0
  while [ "$i" -lt "$n" ]; do
    case "${PT[i]}" in [1-5]) ;; *) die "fold refused: ${I[i]} has points: ${PT[i]:-none} — only 1-5 point cards fold";; esac
    [ "${ST[i]}" = 0 ] || die "fold refused: ${I[i]} already has steps: — a chain card does not fold again"
    [ "${PL[i]}" = "${PL[0]}" ] || die "fold refused: ${I[i]} is plan '${PL[i]}', ${I[0]} is plan '${PL[0]}' — one plan per fold"
    [ "${RK[i]}" = "${RK[0]}" ] || die "fold refused: ${I[i]} is risk '${RK[i]}', ${I[0]} is risk '${RK[0]}' — one risk per fold"
    [ "${CT[i]}" = "${CT[0]}" ] || die "fold refused: ${I[i]} names contract '${CT[i]}', ${I[0]} names '${CT[0]}' — one contract per fold"
    sum=$((sum + PT[i])); i=$((i + 1))
  done
  [ "$sum" -le 13 ] || die "fold refused: the cards add up to $sum points — a chain card holds at most 13"
  lists="$(_tune_lists files_owned,context_files,verify,surface,needs,approved "${F[@]}")"
  i=1
  while [ "$i" -lt "$n" ]; do
    j=$((i - 1))
    case "${DP[i]} " in *" ${I[j]} "*) i=$((i + 1)); continue;; esac
    _new_meet "$(_fold_items "${I[j]}" files_owned "$lists")" "$(_fold_items "${I[i]}" files_owned "$lists")" \
      || die "fold refused: ${I[i]} neither depends on ${I[j]} nor shares a file with it"
    for x in ${DP[i]}; do
      case "$ids" in *" $x "*) die "fold refused: ${I[i]} shares a file with ${I[j]} but depends on $x — order the IDs along depends_on";; esac
    done
    i=$((i + 1))
  done
  set --
  for col in active review ready backlog blocked; do
    for f in "$BOARD/$col"/*.md; do [ -f "$f" ] && set -- "$@" "$f"; done
  done
  all="$(_tune_rows "$@")"
  x="$(printf '%s\n' "$all" | _fold_cycle "$ids")"
  [ -z "$x" ] || die "fold refused: $x — folding would make the chain wait on itself"

  # --- the survivor's new frontmatter, built in a temp file: the board changes only under the mutex
  i=0
  while [ "$i" -lt "$n" ]; do
    for x in ${DP[i]}; do
      case "$ids" in *" $x "*) continue;; esac
      case " $deps " in *" $x "*) ;; *) deps="$deps${deps:+ }$x";; esac
    done
    t="$(fm_get title "${F[i]}")"; t="${t#\"}"; t="${t%\"}"; TT[i]="$t"
    i=$((i + 1))
  done
  tmp="$(mktemp)"
  {
    printf '@@points\npoints: %s\n@@steps\nsteps:\n' "$sum"
    i=0; while [ "$i" -lt "$n" ]; do printf '  - %s %s: %s\n' "${PT[i]}" "${I[i]}" "${TT[i]}"; i=$((i + 1)); done
    for x in files_owned context_files verify surface needs approved; do
      y="$(_fold_pick "$x" "$lists")"
      if [ -n "$y" ] || grep -q "^$x:" "${F[0]}" 2>/dev/null; then _fold_block "$x" "$y"; fi
    done
    printf '@@depends_on\ndepends_on: [%s]\n' "${deps// /, }"
  } > "$tmp"
  for x in value time_criticality risk_opportunity; do
    w=""
    i=0
    while [ "$i" -lt "$n" ]; do
      _new_val "$x" "${F[i]}"
      case "$_NV" in
        ''|.|*[!0-9.]*|*.*.*) ;;
        *) if [ -z "$w" ] || LC_ALL=C awk "BEGIN { exit !($_NV > $w) }"; then w="$_NV"; fi;;
      esac
      i=$((i + 1))
    done
    if [ -n "$w" ]; then printf '@@%s\n%s: %s\n' "$x" "$x" "$w" >> "$tmp"; s3="$s3${s3:++}$w"; else okn=0; fi
  done
  [ "$okn" = 1 ] && printf '@@wsjf\nwsjf: %s\n' "$(LC_ALL=C awk "BEGIN { printf \"%.2f\", ($s3) / $sum }")" >> "$tmp"
  # the column `new`'s ready gate answers: every depends_on in done/, no shared file outside the group
  col=ready
  for x in $deps; do [ -f "$BOARD/done/$x.md" ] || { col=backlog; break; }; done
  if [ "$col" = ready ]; then
    set --
    for y in ready active review; do
      for f in "$BOARD/$y"/*.md; do
        [ -f "$f" ] || continue
        x="${f##*/}"; x="${x%.md}"; case "$ids" in *" $x "*) continue;; esac
        set -- "$@" "$f"
      done
    done
    owned="$(_fold_pick files_owned "$lists")"
    x="$(_tune_lists files_owned "$@" | awk -F'\037' '{ print $3 }')"
    if [ -n "$x" ] && [ -n "$owned" ] && _new_meet "$owned" "$x"; then col=backlog; fi
  fi
  printf '@@status\nstatus: %s\n' "$col" >> "$tmp"
  for x in "${I[@]:1}"; do folded="$folded${folded:+ }$x"; done

  mutex_on
  _fold_write "$tmp" "${F[0]}"
  rm -f "$tmp"
  i=1
  while [ "$i" -lt "$n" ]; do
    { printf '\n### Step %s — %s: %s\n' "$((i + 1))" "${I[i]}" "${TT[i]}"; _fold_sect "${F[i]}"; } >> "${F[0]}"
    rm -f "${F[i]}"
    i=$((i + 1))
  done
  f="$BOARD/$col/${I[0]}.md"
  [ "${F[0]}" = "$f" ] || mv "${F[0]}" "$f"
  while IFS="$POLARIS_TAB" read -r x y; do
    [ -n "$x" ] || continue
    for t in ready backlog blocked; do [ -f "$BOARD/$t/$x.md" ] && _new_deps "[$y]" "$BOARD/$t/$x.md"; done
  done <<EOF
$(printf '%s\n' "$all" | _fold_rewire "$ids" " $folded " "${I[0]}")
EOF
  evt fold "${I[0]}" "$folded"
  board_commit "chore(board): fold $folded → ${I[0]}"
  sync_board
  mutex_off; trap - EXIT
  "$SELF" tune >/dev/null 2>&1 || true
  say "folded $folded into ${I[0]} — $n cards → 1, $sum points, $col/"
}
