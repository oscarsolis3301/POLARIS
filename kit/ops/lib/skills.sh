# POLARIS lib/skills.sh — skills POLARIS writes for itself (ops/contracts/self-skills.md, 6.5.0).
# A surface the board keeps returning to (the api-kit golden, the role files, observe.sh) gets a
# `.claude/skills/<name>/SKILL.md`: what keeps going wrong there, its public surface, the tests that
# cover it — delivered WHOLE, not one grep line at a time. The cost side is the whole design: a
# model-invocable skill's name+description rides every session's prompt in the repo (the tax
# admin.sh::slim measures). Two measured facts (plans/self-skills.md) make it safe: a hidden skill
# (`disable-model-invocation: true`) costs ZERO prompt bytes, and a repo skill loads only in that
# repo. So every skill is born hidden (tier 0), a byte-budgeted shelf (tier 1) is promoted on
# evidence, eviction is data over EVENTS.ndjson, and nothing runs uninvited (no hook, no auto-write,
# no CONVENTIONS key; `claim`'s `skill-hit` event in builder.sh is the only telemetry).
# ASYMMETRIC BY DESIGN (owner, 2026-09-14; § 0 OPEN-3/4): `promote` spends every future session's
# budget here, so EVOLVE PROPOSES it and a human runs it — never an agent on its own initiative, under
# ANY autonomy setting; `demote` frees budget, is a one-line flip back and cannot break a session, so
# it MAY sit in EVOLVE's auto-reversible allowlist. Filing that asymmetry as a bug is reading it right.
# The twin (`.claude/rules/<name>.md`, § 6) is PROBE-GATED at build time (T-150 measured `probe:
# rules-paths-fires-on-read: yes`), and its measured limit stands: it loads when a session READS a
# matching file, not on a Write or a new file, so a lane that only CREATES files there never sees
# it — `pack`'s SKILLS section (T-156) reaches that lane. Every writer refuses on feat/* (the
# `interview --set` precedent) and commits nothing. Fourteen top-level fns, no nested helpers (the
# index records nested definitions too), no top-level assignments (module-layout).

cmd_skill() { # skill <sub> [args…] — dispatch (self-skills.md § 1); each writer refuses feat/* inside its fn
  local u='usage: polaris skill list | gaps | budget | propose <glob> [--name N] [--write] [--force] | promote <name> | demote <name> | prune [--apply] | restore <name>'
  case "${1:-}" in
    list)    [ $# -eq 1 ] || die "$u"; skill_list;;
    gaps)    [ $# -eq 1 ] || die "$u"; skill_gaps;;
    budget)  [ $# -eq 1 ] || die "$u"; skill_budget;;
    propose) shift; [ $# -ge 1 ] || die "$u"; skill_propose "$@";;
    promote) [ $# -eq 2 ] || die "$u"; skill_promote "$2";;
    demote)  [ $# -eq 2 ] || die "$u"; skill_demote "$2";;
    prune)   [ $# -eq 1 ] || { [ $# -eq 2 ] && [ "$2" = --apply ]; } || die "$u"; skill_prune "${2:-}";;
    restore) [ $# -eq 2 ] || die "$u"; skill_restore "$2";;
    *)       die "$u";;
  esac
}

skill_consts() { # the five constants (§ 2): builtins, idempotent, never a CONVENTIONS key — called at the top of every fn that reads them (module-layout forbids top-level assignments)
  SKILL_FM_MAX=320; SKILLS_SHELF_MAX=1600; SKILLS_WINDOW=40; SKILLS_GAP_MIN=5; SKILLS_T0_WARN=24
}

skill_bytes() { # skill_bytes <SKILL.md> — injected bytes by slim's rule; 0 when the frontmatter hides it.
  # The SAME awk as admin.sh::slim_scan (name:/description: lines +1 each, folded continuation lines
  # included) plus ONE clause: `disable-model-invocation: true` ⇒ 0. The fast tier proves the two
  # counters agree on the same fixtures (§ 9) — change one, change both.
  [ -f "${1:-}" ] || { printf '0\n'; return 0; }
  awk '!done_fm { if (FNR==1 && $0 ~ /^---/) { fm=1; next }
                  if (fm && $0 ~ /^---/)     { done_fm=1; next }
                  if (fm && $0 ~ /^disable-model-invocation:[ \t]*true[ \t\r]*$/) { hidden=1 }
                  if (fm && $0 ~ /^(name|description):/) { p=1; b += length($0)+1; next }
                  if (fm && p && $0 ~ /^[A-Za-z_-]+:/)   { p=0 }
                  if (fm && p)                           { b += length($0)+1 } }
       END { print (hidden ? 0 : b+0) }' "$1"
}

skill_paths() { # skill_paths <name> — metadata.polaris.paths, one per line (flow [a, b] and block lists both parse);
  # nothing + rc 1 without metadata.polaris — THE "is it POLARIS-written?" test (identity is the key, never a prefix)
  local f="$PRIMARY/.claude/skills/${1:-}/SKILL.md"
  [ -n "${1:-}" ] && [ -f "$f" ] || return 1
  awk '
    function emit(s,   n, i, p, t) {                 # one flow list "[a, b]" → items, quotes stripped
      sub(/^[ \t]*\[/, "", s); sub(/\][ \t]*$/, "", s); n = split(s, p, ",")
      for (i = 1; i <= n; i++) { t = p[i]; gsub(/^[ \t"'\'']+|[ \t"'\'']+$/, "", t); if (t != "") print t }
    }
    /^---[\r]?$/ { fs++; next }
    fs != 1 { next }
    { sub(/\r$/, "") }
    /^[^ \t]/ { meta = ($0 ~ /^metadata:/); pol = 0; lst = 0; next }
    meta && !pol && /^[ \t]+polaris:/ {
      found = 1; ind = match($0, /[^ \t]/); s = $0; sub(/^[ \t]+polaris:[ \t]*/, "", s)
      if (s ~ /^\{/) { if (match(s, /paths:[ \t]*\[[^]]*\]/)) emit(substr(s, RSTART + 6, RLENGTH - 6)) } else pol = 1
      next
    }
    pol {
      if (match($0, /[^ \t]/) <= ind) { pol = 0; lst = 0; next }
      if ($0 ~ /^[ \t]+paths:/) { s = $0; sub(/^[ \t]+paths:[ \t]*/, "", s); if (s ~ /^\[/) emit(s); else lst = 1; next }
      if (lst && $0 ~ /^[ \t]+-[ \t]/) { s = $0; sub(/^[ \t]+-[ \t]+/, "", s); gsub(/^[ \t"'\'']+|[ \t"'\'']+$/, "", s); if (s != "") print s; next }
      lst = 0
    }
    END { exit found ? 0 : 1 }' "$f"
}

skill_tier() { # skill_tier <name> — 0 when the flag is `true`, else 1: the FLAG is the truth, tier: mirrors it
  local f="$PRIMARY/.claude/skills/${1:-}/SKILL.md"
  [ -f "$f" ] || { printf '1\n'; return 0; }
  awk '/^---[\r]?$/ { fs++; next }  fs==1 && /^disable-model-invocation:[ \t]*true[ \t\r]*$/ { h=1 }  fs>=2 { exit }  END { print (h ? 0 : 1) }' "$f"
}

skill_hits() { # skill_hits <name> <events> — "<count> <last task ID|->": the skill-hit lines for <name> whose
  # ts is ≥ the ts of the <events>-th most recent done line (fewer done lines than that ⇒ all history)
  [ -f "${EVENTS:-}" ] || { printf '0 -\n'; return 0; }
  awk -v id="\"id\":\"$1\"" -v n="${2:-40}" '
    function ts_of(l) { sub(/.*"ts":/, "", l); sub(/[^0-9].*/, "", l); return l + 0 }
    index($0, "\"ev\":\"done\"") { d[++nd] = ts_of($0); next }
    index($0, "\"ev\":\"skill-hit\"") && index($0, id) { t[++nh] = ts_of($0); l = $0; sub(/.*"note":"/, "", l); sub(/".*/, "", l); nt[nh] = l }
    END {
      cut = (nd >= n) ? d[nd - n + 1] : 0
      for (i = 1; i <= nh; i++) if (t[i] >= cut) { c++; last = nt[i] }
      print c + 0, (last == "" ? "-" : last)
    }' "$EVENTS"
}

skill_list() { # list — one line per POLARIS-written skill (name order), then ONE summary line; rc 0 always
  skill_consts
  local dir="$PRIMARY/.claude/skills" d name t b h last paths twin sum=0 n=0 n0=0
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    name="${d%/}"; name="${name##*/}"
    paths="$(skill_paths "$name")" || continue          # not POLARIS-written: invisible here
    t="$(skill_tier "$name")"; b="$(skill_bytes "$d/SKILL.md")"
    set -- $(skill_hits "$name" "$SKILLS_WINDOW"); h="${1:-0}"; last="${2:--}"
    paths="$(printf '%s\n' "$paths" | grep . | tr '\n' ',' | sed 's/,$//')"
    twin="-"; [ ! -f "$PRIMARY/.claude/rules/$name.md" ] || twin=yes
    printf '%s  tier %s · %s B · %s/%s hits · last %s · paths %s · twin %s\n' "$name" "$t" "$b" "$h" "$SKILLS_WINDOW" "$last" "${paths:--}" "$twin"
    n=$((n + 1)); if [ "$t" = 0 ]; then n0=$((n0 + 1)); else sum=$((sum + b)); fi
  done
  [ "$n" -gt 0 ] || { printf 'no POLARIS-written skills here — find candidates: ops/polaris skill gaps\n'; return 0; }
  printf '%s skill(s) · shelf %s/%s B · tier 0: %s\n' "$n" "$sum" "$SKILLS_SHELF_MAX" "$n0"
  [ "$n0" -le "$SKILLS_T0_WARN" ] || printf '⚠ tier 0 count %s > %s — archive the dead ones: ops/polaris skill prune\n' "$n0" "$SKILLS_T0_WARN"
}

skill_gaps() { # gaps — the surfaces the board keeps returning to with no skill (§ 3); rc 0 always.
  # `--for <glob>` (internal: propose's threshold read) prints "<n> <k> <ID,ID,…>" for ONE surface.
  # n = done tasks among the last 2W whose files_owned overlap it (pat_overlap, both ways); k = those
  # tasks' kickback events + their `- ⛔` Notes lines naming a path under it (a kickback's `⛔ kicked
  # back by` echo IS that kickback: skipped). Candidates: every owned pattern as written, every
  # SURFACES.tsv surface, and the parent directory of sub-threshold patterns when ≥2 fold into it; a
  # directory yields to a kept directory under it, and a file whose hits are ≥3/4 of its kept
  # directory's folds into it (roles: 7/7/6 of 7 → ONE candidate, not six; api-kit 18 of ops/tests/'s
  # 31 stays its own). One awk reads the window (80 fm_list forks cost ~11s here); the loop is bash.
  skill_consts
  local w2=$((SKILLS_WINDOW * 2)) one="" tmp ids id f files="" rows stops kbs spaths cands c d n k key idl
  local rid pat x line kind table="" folds="" min="$SKILLS_GAP_MIN" tab="$POLARIS_TAB" nl='
'
  [ "${1:-}" = --for ] && one="${2:-}"
  ids=""
  [ -f "${EVENTS:-}" ] && ids="$(awk '/"ev":"done"/ { l=$0; sub(/.*"id":"/, "", l); sub(/".*/, "", l); print l }' "$EVENTS" \
    | tail -n "$w2" | awk '{ a[NR]=$0 } END { for (i=NR; i>=1; i--) if (!s[a[i]]++) print a[i] }')"
  for id in $ids; do f="$(task_file "$id" done)" || f="$(task_file "$id")" || continue; files="$files$f$nl"; done
  tmp="$(mktemp)" || die "mktemp failed"
  if [ -n "$files" ]; then
    x="$IFS"; IFS="$nl"; set -- $files; IFS="$x"                 # newline-split: a path may hold a space
    awk '
      FNR == 1 { fs = 0; on = 0; id = FILENAME; sub(/.*\//, "", id); sub(/\.md$/, "", id) }
      /^---[\r]?$/ { fs++; next }
      { sub(/\r$/, "") }
      fs >= 2 && /^- ⛔/ && !/kicked back by/ { print "stop\t" id "\t" $0; next }
      fs != 1 { next }
      index($0, "files_owned:") == 1 {
        on = 1; s = substr($0, 13); sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t]*$/, "", s)
        if (s ~ /^\[/) { on = 0; sub(/^\[/, "", s); sub(/\]$/, "", s); n = split(s, p, ",")
          for (i = 1; i <= n; i++) { t = p[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); if (t != "") print "own\t" id "\t" t } }
        next }
      on && /^[ \t]*-[ \t]/ { s = $0; sub(/^[ \t]*-[ \t]+/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t]*$/, "", s); if (s != "") print "own\t" id "\t" s; next }
      on && /^[A-Za-z_]/ { on = 0 }' "$@" > "$tmp"
  else : > "$tmp"; fi
  rows="$(awk -F'\t' '$1=="own" { print $2 "\t" $3 }' "$tmp")"
  stops="$(awk -F'\t' '$1=="stop" { print $2 "\t" $3 }' "$tmp")"
  rm -f "$tmp"
  kbs=" "; [ ! -f "${EVENTS:-}" ] || kbs=" $(awk '/"ev":"kickback"/ { l=$0; sub(/.*"id":"/, "", l); sub(/".*/, "", l); c[l]++ }
    END { for (k in c) printf "%s:%d ", k, c[k] }' "$EVENTS")"
  if [ -n "$one" ]; then cands="pat$tab$one"
  else
    cands="$(printf '%s\n' "$rows" | cut -f2 | grep . | sort -u | sed 's/^/pat\t/'; surfaces_lines | cut -f1 | sed 's/^/row\t/')"
    for pat in $(printf '%s\n' "$rows" | cut -f2 | sort -u); do   # every parent directory: the fold targets
      d="${pat%/}"; case "$d" in *\**) d="${d%%\**}"; d="${d%/*}";; *) d="${d%/*}";; esac
      [ -n "$d" ] && [ "$d" != "${pat%/}" ] && cands="$cands${nl}dir$tab$d/"
    done
    cands="$(printf '%s\n' "$cands" | awk -F'\t' '$2 != "" && !s[$2]++')"   # a dir also owned as written is judged as written
  fi
  while IFS="$tab" read -r kind c; do
    [ -n "$c" ] || continue
    n=0; k=0; idl=","; key="${c%%\**}"
    while IFS="$tab" read -r rid pat; do
      [ -n "$rid" ] || continue
      case "$idl" in *",$rid,"*) continue;; esac
      pat_overlap "$c" "$pat" || continue
      idl="$idl$rid,"; n=$((n + 1))
      x="${kbs#* $rid:}"; [ "$x" = "$kbs" ] || { x="${x%% *}"; k=$((k + x)); }
    done <<EOF
$rows
EOF
    [ -z "$key" ] || while IFS="$tab" read -r rid line; do
      [ -n "$rid" ] || continue
      case "$idl" in *",$rid,"*) case "$line" in *"$key"*) k=$((k + 1));; esac;; esac
    done <<EOF
$stops
EOF
    if [ -n "$one" ]; then idl="${idl#,}"; printf '%s %s %s\n' "$n" "$k" "${idl%,}"; return 0; fi
    table="${table}cand$tab$c$tab$n$tab$k$tab$kind$nl"
    if [ "$kind" = pat ] && [ "$n" -lt "$min" ]; then   # below the threshold: it folds into its parent
      d="${c%/}"; case "$d" in *\**) d="${d%%\**}"; d="${d%/*}";; *) d="${d%/*}";; esac
      [ -n "$d" ] && [ "$d" != "${c%/}" ] && folds="${folds}fold$tab$d/$nl"
    fi
  done <<EOF
$cands
EOF
  spaths=""
  for d in "$PRIMARY/.claude/skills"/*/; do
    [ -d "$d" ] || continue; x="${d%/}"; x="${x##*/}"
    pat="$(skill_paths "$x" 2>/dev/null || true)"; [ -z "$pat" ] || spaths="$spaths$pat$nl"
  done
  cands="$(printf '%s%s' "$table" "$folds" | awk -F'\t' -v min="$min" '
    $1 == "fold" { fc[$2]++; next }
    $1 == "cand" { N++; c[N] = $2; n[N] = $3; k[N] = $4; kd[N] = $5; dr[N] = ($2 ~ /\/$/) }
    END {   # judged HERE, once every fold row is in — a directory born of folding needs ≥2 of them
      for (i = 1; i <= N; i++) keep[i] = (n[i] >= min && (kd[i] != "dir" || fc[c[i]] >= 2))
      for (i = 1; i <= N; i++) if (keep[i] && dr[i])
        for (j = 1; j <= N; j++) if (i != j && keep[j] && dr[j] && index(c[j], c[i]) == 1) { keep[i] = 0; break }
      for (i = 1; i <= N; i++) if (keep[i] && !dr[i])
        for (j = 1; j <= N; j++) if (keep[j] && dr[j] && index(c[i], c[j]) == 1 && n[i] * 4 >= n[j] * 3) { keep[i] = 0; break }
      for (i = 1; i <= N; i++) if (keep[i]) printf "%d\t%s\t%d\t%d\n", n[i] * (1 + k[i]), c[i], n[i], k[i]
    }')"
  table=""
  while IFS="$tab" read -r x c n k; do
    [ -n "$c" ] || continue
    for pat in $spaths; do pat_overlap "$c" "$pat" && continue 2; done   # covered: a skill already owns it
    table="$table$x$tab$c$tab$n$tab$k$nl"
  done <<EOF
$cands
EOF
  if [ -z "$table" ]; then printf 'no surface reaches %s/%s done tasks — nothing worth a skill yet\n' "$min" "$w2"; return 0; fi
  printf '%s' "$table" | LC_ALL=C sort -t "$tab" -k1,1nr -k2,2 \
    | awk -F'\t' -v w2="$w2" '{ printf "%s  %d/%d tasks · %d kickbacks · skill: none\n", $2, $3, w2, $4 }'
}

skill_budget() { # budget — the constants line + the shelf line; rc 1 and a third line when the shelf is over
  skill_consts
  local dir="$PRIMARY/.claude/skills" d name t b h sum=0 n1=0 n0=0 worst="" wh=-1 wb=0
  printf 'SKILL_FM_MAX=%s SKILLS_SHELF_MAX=%s SKILLS_WINDOW=%s SKILLS_GAP_MIN=%s SKILLS_T0_WARN=%s\n' \
    "$SKILL_FM_MAX" "$SKILLS_SHELF_MAX" "$SKILLS_WINDOW" "$SKILLS_GAP_MIN" "$SKILLS_T0_WARN"
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    name="${d%/}"; name="${name##*/}"
    skill_paths "$name" >/dev/null 2>&1 || continue
    t="$(skill_tier "$name")"
    if [ "$t" = 0 ]; then n0=$((n0 + 1)); continue; fi
    b="$(skill_bytes "$d/SKILL.md")"; sum=$((sum + b)); n1=$((n1 + 1))
    set -- $(skill_hits "$name" "$SKILLS_WINDOW"); h="${1:-0}"
    # the demotion candidate when over: fewest hits in the window, then the most bytes, then name order
    if [ -z "$worst" ] || [ "$h" -lt "$wh" ] || { [ "$h" -eq "$wh" ] && [ "$b" -gt "$wb" ]; }; then worst="$name"; wh="$h"; wb="$b"; fi
  done
  printf 'shelf: %s B of %s (%s tier-1 skill(s)) · tier 0: %s (0 B injected)\n' "$sum" "$SKILLS_SHELF_MAX" "$n1" "$n0"
  [ "$sum" -gt "$SKILLS_SHELF_MAX" ] || return 0
  printf '⛔ shelf over budget by %s B — demote one: ops/polaris skill demote %s\n' "$((sum - SKILLS_SHELF_MAX))" "$worst"
  return 1
}

skill_propose() { # propose <glob> [--name N] [--write] [--force] — the deterministic SKELETON (§ 5) + --write (§ 5, § 6):
  # `pack`'s producers over a SURFACE instead of a task (code-map entry · find --api · WHOLE brain
  # bullets · co-change pairs · SURFACES rows + verify: lines · the last done tasks). The description is
  # NEVER generated (a made-up trigger is a lie about when to fire; `promote` refuses a `TODO(`); `since:` is the only non-deterministic byte.
  skill_consts
  local glob="${1:-}" name="" write=0 force=0 w2=$((SKILLS_WINDOW * 2)) n k idl ev br dst tmp key d x out id tf
  local brain="$PRIMARY/.polaris/brain" tab="$POLARIS_TAB" u='usage: polaris skill propose <glob> [--name N] [--write] [--force]'
  [ -n "$glob" ] || die "$u"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)  [ -n "${2:-}" ] || die "$u"; name="$2"; shift 2;;
      --write) write=1; shift;;
      --force) force=1; shift;;
      *)       die "$u";;
    esac
  done
  if [ -z "$name" ]; then   # the glob's last path component, kebab-cased, extension dot → -
    name="${glob%/}"; name="${name##*/}"
    name="$(printf '%s' "$name" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
  fi
  [ -n "$name" ] || die "cannot derive a skill name from '$glob' — pass --name"
  # refusals in THIS order (§ 5) — the name checks first, so a feat/* lane can still prove them
  case "$name" in polaris|polaris-install|i-have-adhd|polaris-*)
    die "$name is reserved — polaris, polaris-install, i-have-adhd and polaris-* are managed by update";; esac
  [ ! -d "$(claude_home)/skills/$name" ] || die "$name exists under ~/.claude/skills/ — a repo skill of that name would be shadowed and never fire"
  set -- $(skill_gaps --for "$glob"); n="${1:-0}"; k="${2:-0}"; idl="${3:-}"
  ev="$n/$w2 tasks · $k kickbacks"
  if [ "$n" -lt "$SKILLS_GAP_MIN" ]; then
    [ "$force" = 1 ] || die "$glob is owned by $n/$w2 recent done tasks — below $SKILLS_GAP_MIN; one task's lesson belongs in Learned, not a skill (--force overrides, recorded in evidence:)"
    ev="$ev · --force"
  fi
  dst="$PRIMARY/.claude/skills/$name"
  if [ "$write" = 1 ]; then
    br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$br" in feat/*) die "skill propose runs on $BASE — a skill is repo knowledge, not a task's diff";; esac
    [ ! -e "$dst" ] || die ".claude/skills/$name/ exists — never overwritten"
  fi
  key="${glob%%\**}"; idl="${idl//,/ }"
  case "$key" in */) d="$key";; */*) d="${key%/*}/";; *) d="./";; esac
  tmp="$(mktemp)" || die "mktemp failed"
  {
    printf -- '---\nname: %s\ndescription: TODO(%s) — ≤ 290 chars: TRIGGER when …; DO NOT TRIGGER when …\n' "$name" "$glob"
    printf 'disable-model-invocation: true\nmetadata:\n  polaris: { paths: [%s], since: %s, tier: 0, evidence: "%s" }\n---\n' "$glob" "$(date +%F)" "$ev"
    printf '# %s — what POLARIS already knows\n\n## What it is\n' "$glob"
    if [ ! -d "$brain" ]; then printf '(no brain — run: ops/polaris brain)\n'
    else
      out="$(awk -v d="## $d" '$0==d{on=1;print;next} on&&/^## /{exit} on{print}' "$brain/code-map.md" 2>/dev/null | grep . | head -15 || true)"
      printf '%s\n' "${out:-(no code-map entry for $d — run: ops/polaris brain)}"
    fi
    surfaces_lines | while IFS="$tab" read -r sx st sc sn; do
      [ -n "$sx" ] && pat_overlap "$glob" "$sx" && printf -- '- %s (ops/SURFACES.tsv: %s → %s)\n' "${sn:-no note}" "$sx" "$st"
    done | head -5
    printf '\n## Public surface\n'
    out="$("$SELF" find --api "$glob" 2>/dev/null | tr -d '\r' | grep "$tab" | head -25 || true)"
    printf '%s\n' "${out:-(nothing indexed for $glob — new files, or run: ops/polaris brain)}"
    printf '\n## What keeps going wrong\n'
    if [ ! -d "$brain" ]; then printf '(no brain — run: ops/polaris brain)\n'
    else   # WHOLE bullets (paragraph mode over `- ` items, emitted when any line names the surface), ≤ 8 / 40 lines
      out="$({ [ -f "$brain/gotchas.md" ] && awk -v key="$key" '
          function flush(   i) { if (hit && nb < 8) { for (i = 1; i <= n && nl < 40; i++) { print buf[i]; nl++ } nb++ } n = 0; hit = 0 }
          /^- / { flush(); buf[++n] = $0; if (index($0, key)) hit = 1; next }
          n && /^[ \t]+[^ \t]/ { buf[++n] = $0; if (index($0, key)) hit = 1; next }
          { flush() }
          END { flush() }' "$brain/gotchas.md"
        [ -f "$EVENTS" ] && awk -v ids=" $idl " '/"ev":"kickback"/ {
          id = $0; sub(/.*"id":"/, "", id); sub(/".*/, "", id)
          note = $0; sub(/.*"note":"/, "", note); sub(/"(,"pts":[0-9.]*)?}[ \r]*$/, "", note)
          if (index(ids, " " id " ")) printf "- %s kicked back: %s\n", id, (note == "" ? "(no reason recorded)" : note) }' "$EVENTS"
      } | head -40 || true)"
      printf '%s\n' "${out:-(none recorded for $glob)}"
    fi
    printf '\n## Files that move together\n'
    if [ ! -d "$brain" ]; then printf '(no brain — run: ops/polaris brain)\n'
    else
      out="$(grep -E '^- [0-9]+x ' "$brain/learned.md" 2>/dev/null | grep -F -- "$key" | head -12 || true)"
      printf '%s\n' "${out:-(none recorded)}"
    fi
    printf '\n## Tests that cover it\n'
    out="$({ surfaces_lines | while IFS="$tab" read -r sx st sc sn; do
          [ -n "$sx" ] && pat_overlap "$glob" "$sx" && printf '%s → %s  (%s)  — %s\n' "$sx" "$st" "${sc:--}" "$sn"
        done
        x=0
        for id in $idl; do   # the verify: lines of the last 3 done tasks here
          [ "$x" -lt 3 ] || break; x=$((x + 1))
          tf="$(task_file "$id" 2>/dev/null || true)"; [ -n "$tf" ] || continue
          fm_list verify "$tf" 2>/dev/null | grep . | sed "s/^/- $id: /"
        done
      } | head -30 || true)"
    printf '%s\n' "${out:-(none recorded — no SURFACES row and no done task here yet)}"
    printf '\n## Last worked\n'
    out="$(x=0; for id in $idl; do
        [ "$x" -lt 5 ] || break; x=$((x + 1))
        tf="$(task_file "$id" 2>/dev/null || true)"; [ -n "$tf" ] || continue
        printf -- '- %s — %s\n' "$id" "$(fm_get title "$tf" | sed -e 's/^"//' -e 's/"$//')"
      done)"
    printf '%s\n' "${out:-(none yet)}"
  } > "$tmp"
  if [ "$write" = 0 ]; then cat "$tmp"; rm -f "$tmp"; return 0; fi
  mkdir -p "$dst" && mv -f "$tmp" "$dst/SKILL.md" || { rm -f "$tmp"; die "could not write $dst/SKILL.md"; }
  say "wrote .claude/skills/$name/SKILL.md (tier 0 · $(wc -l < "$dst/SKILL.md" | tr -d ' ') lines · description is TODO — EVOLVE writes it)"
  # the twin (§ 6): same globs, same lifecycle, zero standing cost — and the limit the header names
  if [ -f "$PRIMARY/.claude/rules/$name.md" ]; then note "⚠ .claude/rules/$name.md exists — left as it is"
  else
    mkdir -p "$PRIMARY/.claude/rules"
    printf -- '---\npaths:\n  - "%s"\n---\nThis surface has a POLARIS skill: `.claude/skills/%s/SKILL.md` — read it before you change these files.\nIt records what keeps going wrong here, the public surface and the tests that cover it (`/%s` loads it too).\n' \
      "$glob" "$name" "$name" > "$PRIMARY/.claude/rules/$name.md"
    note "twin: .claude/rules/$name.md — fires when a session READS a file under $glob; not on a Write or a new file, so a lane that only creates files here never sees it (pack's SKILLS section covers that lane)"
  fi
  note "review, then commit .claude/skills/$name/ and .claude/rules/$name.md — nothing was committed for you"
}

skill_promote() { # promote <name> — flip the flag visible; refusals in § 3's order, nothing written on any of them.
  skill_consts   # EVOLVE proposes this, a human runs it: it spends every future session's budget in this repo
  local name="${1:-}" f="$PRIMARY/.claude/skills/${1:-}/SKILL.md" desc b sum br tmp
  skill_paths "$name" >/dev/null 2>&1 || die "no POLARIS-written skill named $name"
  if [ "$(skill_tier "$name")" = 1 ]; then printf '%s is already tier 1\n' "$name"; return 0; fi
  desc="$(awk '/^---[\r]?$/{fs++;next} fs==1&&/^description:/{p=1;print;next} fs==1&&p&&/^[A-Za-z_-]+:/{p=0} fs==1&&p{print} fs>=2{exit}' "$f")"
  case "$desc" in *"TODO("*) desc="${desc#*TODO(}"; die "description still TODO(${desc%%)*}) — write the trigger sentence first (≤ 290 chars)";; esac
  tmp="$f.polaris-tmp"
  sed 's/^disable-model-invocation: true[[:space:]]*$/disable-model-invocation: false/' "$f" > "$tmp"   # the bytes AS promoted
  b="$(skill_bytes "$tmp")"; rm -f "$tmp"
  [ "$b" -le "$SKILL_FM_MAX" ] || die "$name frontmatter is $b B — the per-skill cap is $SKILL_FM_MAX"
  sum="$(skill_budget | sed -n 's/^shelf: \([0-9]*\) B.*/\1/p')"
  if [ $((sum + b)) -gt "$SKILLS_SHELF_MAX" ]; then
    printf '⛔ shelf would be %s B — over %s; demote one first:\n' "$((sum + b))" "$SKILLS_SHELF_MAX" >&2
    skill_list; return 1
  fi
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*) die "skill promote runs on $BASE — a skill is repo knowledge, not a task's diff";; esac
  # the flag line STAYS (demote is a one-line flip back); metadata.polaris gains/sets tier: 1 in either
  # form: flow `{ …, tier: 0, … }` in place, block `tier:` in place or added at the end of the block
  awk -v flag=false -v t=1 '
    /^---[\r]?$/ { fs++; if (fs == 2 && pend) { print pad "tier: " t; pend = 0 } print; next }
    fs != 1 { print; next }
    /^disable-model-invocation:/ { print "disable-model-invocation: " flag; next }
    /^[^ \t]/ { if (pend) { print pad "tier: " t; pend = 0 } meta = ($0 ~ /^metadata:/); pol = 0 }
    meta && !pol && /^[ \t]+polaris:/ {
      if ($0 ~ /tier:[ \t]*[0-9]/) sub(/tier:[ \t]*[0-9]+/, "tier: " t)
      else if ($0 ~ /\}[ \t\r]*$/) sub(/[ \t]*\}[ \t\r]*$/, ", tier: " t " }")
      else { pol = 1; pend = 1; ind = match($0, /[^ \t]/); pad = substr($0, 1, ind - 1) "  " }
      print; next }
    pol && match($0, /[^ \t]/) <= ind { if (pend) { print pad "tier: " t; pend = 0 } pol = 0 }
    pol && /^[ \t]+tier:/ { sub(/tier:[ \t]*[0-9]+/, "tier: " t); pend = 0 }
    { print }' "$f" > "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; die "could not write $f"; }
  say "promoted $name — $b B now rides every session in this repo (shelf $((sum + b))/$SKILLS_SHELF_MAX)"
  note "review, then commit .claude/skills/$name/SKILL.md — nothing was committed for you"
}

skill_demote() { # demote <name> — the free reverse: the flag back to true, tier: 0; 0 B injected, /<name> still loads it.
  skill_consts   # byte-reversible and inert, which is why it MAY sit in EVOLVE's auto-reversible allowlist (§ 0)
  local name="${1:-}" f="$PRIMARY/.claude/skills/${1:-}/SKILL.md" br tmp
  skill_paths "$name" >/dev/null 2>&1 || die "no POLARIS-written skill named $name"
  if [ "$(skill_tier "$name")" = 0 ]; then printf '%s is already tier 0\n' "$name"; return 0; fi
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*) die "skill demote runs on $BASE — a skill is repo knowledge, not a task's diff";; esac
  tmp="$f.polaris-tmp"
  # promote's awk with the values reversed, plus the one case only demote meets: a skill written by hand
  # with NO flag line is visible, so the line is ADDED before the closing --- to hide it
  awk -v flag=true -v t=0 '
    /^---[\r]?$/ { fs++; if (fs == 2 && pend) { print pad "tier: " t; pend = 0 }
                   if (fs == 2 && !seen) print "disable-model-invocation: " flag; print; next }
    fs != 1 { print; next }
    /^disable-model-invocation:/ { print "disable-model-invocation: " flag; seen = 1; next }
    /^[^ \t]/ { if (pend) { print pad "tier: " t; pend = 0 } meta = ($0 ~ /^metadata:/); pol = 0 }
    meta && !pol && /^[ \t]+polaris:/ {
      if ($0 ~ /tier:[ \t]*[0-9]/) sub(/tier:[ \t]*[0-9]+/, "tier: " t)
      else if ($0 ~ /\}[ \t\r]*$/) sub(/[ \t]*\}[ \t\r]*$/, ", tier: " t " }")
      else { pol = 1; pend = 1; ind = match($0, /[^ \t]/); pad = substr($0, 1, ind - 1) "  " }
      print; next }
    pol && match($0, /[^ \t]/) <= ind { if (pend) { print pad "tier: " t; pend = 0 } pol = 0 }
    pol && /^[ \t]+tier:/ { sub(/tier:[ \t]*[0-9]+/, "tier: " t); pend = 0 }
    { print }' "$f" > "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; die "could not write $f"; }
  say "demoted $name — 0 B injected; /$name still loads it"
  note "review, then commit .claude/skills/$name/SKILL.md — nothing was committed for you"
}

skill_prune() { # prune [--apply] — the eviction verdicts over EVENTS.ndjson (§ 4); rc 1 when any is due.
  #   young := fewer than W done events dated on/after since: (never judged before W) · demote := tier 1 ∧
  #   ¬young ∧ hits(W)=0 (the flag back to true) · archive := tier 0 ∧ ¬young ∧ hits(2W)=0 (the dir moved)
  # Done events track work; calendar tracks nothing. since: becomes ONE epoch per skill (never a
  # ts_date fork per event); an unreadable since: counts as today, i.e. young — never an eviction.
  skill_consts
  local apply=0 dir="$PRIMARY/.claude/skills" arc="$PRIMARY/.polaris/skills-archived" d name t since ep dn h h2 due=0 br
  local w="$SKILLS_WINDOW" w2=$((SKILLS_WINDOW * 2))
  case "${1:-}" in --apply) apply=1;; '') ;; *) die "usage: polaris skill prune [--apply]";; esac
  if [ "$apply" = 1 ]; then
    br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$br" in feat/*) die "skill prune runs on $BASE — a skill is repo knowledge, not a task's diff";; esac
  fi
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    name="${d%/}"; name="${name##*/}"
    skill_paths "$name" >/dev/null 2>&1 || continue
    t="$(skill_tier "$name")"
    since="$(awk '/^---[\r]?$/{fs++;next} fs==1 && match($0, /since:[ \t]*[0-9][0-9-]*/) { s=substr($0, RSTART+6, RLENGTH-6); sub(/^[ \t]*/, "", s); print s; exit } fs>=2{exit}' "$d/SKILL.md")"
    ep="$(date -d "$since" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$since 00:00:00" +%s 2>/dev/null || true)"
    case "$ep" in ''|*[!0-9]*) ep="";; esac
    dn=0; [ -z "$ep" ] || [ ! -f "${EVENTS:-}" ] || dn="$(awk -v e="$ep" '/"ev":"done"/ { l=$0; sub(/.*"ts":/,"",l); sub(/[^0-9].*/,"",l); if (l+0 >= e) c++ } END { print c+0 }' "$EVENTS")"
    if [ "$dn" -lt "$w" ]; then printf 'young %s · %s/%s done since %s\n' "$name" "$dn" "$w" "${since:--}"; continue; fi
    set -- $(skill_hits "$name" "$w"); h="${1:-0}"
    if [ "$t" = 1 ]; then
      if [ "$h" != 0 ]; then printf 'keep %s · %s/%s\n' "$name" "$h" "$w"; continue; fi
      printf 'demote %s · 0/%s\n' "$name" "$w"; due=1
      [ "$apply" = 0 ] || skill_demote "$name"
      continue
    fi
    set -- $(skill_hits "$name" "$w2"); h2="${1:-0}"
    if [ "$h2" != 0 ]; then printf 'keep %s · %s/%s\n' "$name" "$h" "$w"; continue; fi
    printf 'archive %s · 0/%s\n' "$name" "$w2"; due=1
    [ "$apply" = 1 ] || continue
    # archive = a MOVE the human commits: the dir under .polaris/ (gitignored, mirrors the path), its index
    # entries dropped, the twin beside it, one RESTORE.md (slim --apply's shape). Never a delete.
    mkdir -p "$arc" && mv "$dir/$name" "$arc/$name" || die "could not move .claude/skills/$name/ to $arc/ — nothing else was changed"
    git -C "$PRIMARY" rm -r -q --cached -- ".claude/skills/$name" 2>/dev/null || true
    if [ -f "$PRIMARY/.claude/rules/$name.md" ]; then
      mv "$PRIMARY/.claude/rules/$name.md" "$arc/$name.rule.md"
      git -C "$PRIMARY" rm -q --cached -- ".claude/rules/$name.md" 2>/dev/null || true
    fi
    cat > "$arc/RESTORE.md" <<EOF
# POLARIS skills archive — evicted by \`polaris skill prune --apply\`
Each directory here is a skill POLARIS wrote for this repo that earned 0 hits in $w2 done tasks, exactly as it
was under .claude/skills/; a \`<name>.rule.md\` beside it is its .claude/rules/ twin. Nothing was deleted, and
git history holds every one too. Put one back (the archive when present, else git history):  bash ops/polaris skill restore <name>
EOF
    say "archived .claude/skills/$name/ → .polaris/skills-archived/$name/"
    note "nothing was committed for you — review, then: git commit -m \"chore(skills): archive $name — 0 hits in $w2 done\""
  done
  [ "$due" = 0 ]
}

skill_restore() { # restore <name> — the archive dir first, git history second (§ 4); refuses when the dir exists.
  local name="${1:-}" dst="$PRIMARY/.claude/skills/${1:-}" arc="$PRIMARY/.polaris/skills-archived" br sha from
  [ -n "$name" ] || die "usage: polaris skill restore <name>"
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$br" in feat/*) die "skill restore runs on $BASE — a skill is repo knowledge, not a task's diff";; esac
  [ ! -e "$dst" ] || die ".claude/skills/$name/ exists — nothing to restore"
  if [ -d "$arc/$name" ]; then
    mkdir -p "$PRIMARY/.claude/skills" && mv "$arc/$name" "$dst" || die "could not move $arc/$name back"
    [ ! -f "$arc/$name.rule.md" ] || { mkdir -p "$PRIMARY/.claude/rules" && mv "$arc/$name.rule.md" "$PRIMARY/.claude/rules/$name.md"; }
    git -C "$PRIMARY" add -- ".claude/skills/$name" 2>/dev/null || true
    [ ! -f "$PRIMARY/.claude/rules/$name.md" ] || git -C "$PRIMARY" add -- ".claude/rules/$name.md" 2>/dev/null || true; from=archive
  else   # a second machine never held the archive: the commit that deleted the skill still has its parent
    sha="$(git -C "$PRIMARY" log --all --diff-filter=D --format=%H -- ".claude/skills/$name/SKILL.md" 2>/dev/null | head -1)"
    [ -n "$sha" ] || die "no archive under .polaris/skills-archived/$name/ and no deletion of .claude/skills/$name/ in git history — nothing to restore"
    git -C "$PRIMARY" checkout -q "$sha^" -- ".claude/skills/$name/" || die "git checkout $sha^ -- .claude/skills/$name/ failed — nothing was changed"
    git -C "$PRIMARY" checkout -q "$sha^" -- ".claude/rules/$name.md" 2>/dev/null || true
    from="git $(printf '%.7s' "$sha")"
  fi
  skill_demote "$name" >/dev/null 2>&1 || true   # a restored skill re-earns its place: the shelf never grows by a restore
  say "restored .claude/skills/$name/ (from $from) — tier 0, hidden; promote when it earns it"
  note "review, then commit .claude/skills/$name/ — nothing was committed for you"
}
