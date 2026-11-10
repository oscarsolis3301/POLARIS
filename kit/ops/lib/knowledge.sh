# POLARIS lib/knowledge.sh — sprint reports + the generated brain, sourced by ops/polaris (the lib loader): report/render
# helpers, cmd_report, seal_report_commit, the brain_* writers, cmd_brain, guide_purpose and cmd_where (the root map).

# --------------------------------------------------- sprint reports (T-023)
# `report` renders a management-readable per-sprint markdown file from the board + git history;
# `seal` commits it on the wave so it rides the same merge/PR into base. The report path lives
# OUTSIDE ops/ (default docs/sprints/) — it ships as product history. Contract:
# ops/contracts/sprint-report.md.
report_dir() { # reports directory (CONVENTIONS reports:, default docs/sprints), PRIMARY-anchored
  local d; d="$(cfg reports docs/sprints)"; d="${d%/}"
  printf '%s/%s' "$PRIMARY" "$d"
}
report_file() { printf '%s/sprint-%s.md' "$(report_dir)" "$1"; }         # absolute, for writing
report_rel()  { local d; d="$(cfg reports docs/sprints)"; d="${d%/}"; printf '%s/sprint-%s.md' "$d" "$1"; }  # repo-relative, for printing

sprint_hdr() { # sprint_hdr <n> — the '# SPRINT <n> …' header minus '# SPRINT ', '' if absent
  awk -v n="$1" '
    /^# SPRINT / { h=$0; sub(/^# SPRINT /,"",h); num=h; sub(/[^0-9].*$/,"",num)
                   if (num==n) { sub(/\r$/,"",h); print h; exit } }
  ' "$OPS/SPRINT.md" 2>/dev/null
}
sprint_hdr_num() { # the TOP header's number = the current sprint, '' if absent
  local hdr; hdr="$(sed -n 's/^# SPRINT //p' "$OPS/SPRINT.md" 2>/dev/null | head -1 | tr -d '\r')"
  printf '%s' "${hdr%%[!0-9]*}"
}
all_sprint_numbers() { # every '# SPRINT <n>' number, in file order
  awk '/^# SPRINT /{h=$0; sub(/^# SPRINT /,"",h); sub(/[^0-9].*$/,"",h); if(h!="") print h}' "$OPS/SPRINT.md" 2>/dev/null
}
sprint_goal() { # sprint_goal <n> — the goal text (same trim as seal), '' if the header is absent
  local hdr num; hdr="$(sprint_hdr "$1")"; [ -n "$hdr" ] || return 0
  num="${hdr%%[!0-9]*}"
  printf '%s' "${hdr#"$num"}" | sed -e 's/^[[:space:]]*//' -e 's/^—[[:space:]]*//' -e 's/^-[[:space:]]*//' \
      -e 's/[[:space:]][[:space:]].*$//' -e 's/[[:space:]]*capacity:.*$//' -e 's/[[:space:]]*$//'
}
sprint_dates() { # sprint_dates <n> — the header's 'dates:' value, '' if absent
  sprint_hdr "$1" | sed -n 's/.*[[:space:]]dates:[[:space:]]*//p' | sed 's/[[:space:]]*$//'
}
ts_date() { # ts_date <epoch> — YYYY-MM-DD (local), portable (GNU -d, then BSD -r); '' on failure
  local e="$1" d=""
  case "$e" in ''|*[!0-9]*) return 0;; esac
  d="$(date -d "@$e" +%F 2>/dev/null || date -r "$e" +%F 2>/dev/null || true)"
  printf '%s' "$d"
}
event_ts() { # event_ts <ev> <id> <first|last> — epoch ts of the first/last matching EVENTS line, '' if none
  [ -f "$EVENTS" ] || return 0
  awk -v ev="\"ev\":\"$1\"" -v id="\"id\":\"$2\"" -v which="$3" '
    index($0, ev) && index($0, id) {
      ts=$0; sub(/.*"ts":/,"",ts); sub(/[^0-9].*/,"",ts)
      if (which=="first") { print ts; exit }
      last=ts
    }
    END { if (which!="first" && last!="") print last }
  ' "$EVENTS" 2>/dev/null || true
}

resolve_sprint_ids() { # resolve_sprint_ids <n> — the sprint's task IDs (layered, degrade-not-die),
  # one per line, deduped, ID order. Rule 1: [<ID>] bullets of base first-parent merges
  # 'Sprint <n> — …'. Rule 2: done/ tasks whose landed: sha is in tag sprint/<n> but not sprint/<n-1>.
  # bash expands every word of a `local` line BEFORE it assigns, so `tag`/`prev` must be a
  # SEPARATE `local` after n is bound — a combined decl reads the CALLER's n (empty under
  # `report --all`, which loops with m while its own n=""), silently no-op'ing Rule 2.
  local n="$1"
  local tag="refs/tags/sprint/$n" prev="refs/tags/sprint/$((n-1))" haveprev="" msha f ls
  {
    git -C "$PRIMARY" log --first-parent --format='%H%x09%s' "$BASE" -- 2>/dev/null \
      | awk -F'\t' -v p="Sprint $n — " 'index($2,p)==1 {print $1}' \
      | while IFS= read -r msha; do
          [ -n "$msha" ] || continue
          git -C "$PRIMARY" log -1 --format='%b' "$msha" 2>/dev/null | sed -n 's/.*\[\([^][]*\)\]$/\1/p'
        done
    if git -C "$PRIMARY" rev-parse -q --verify "$tag" >/dev/null 2>&1; then
      git -C "$PRIMARY" rev-parse -q --verify "$prev" >/dev/null 2>&1 && haveprev=1
      for f in "$BOARD"/done/*.md; do
        [ -f "$f" ] || continue
        ls="$(fm_get landed "$f" 2>/dev/null || true)"; [ -n "$ls" ] || continue
        git -C "$PRIMARY" merge-base --is-ancestor "$ls" "$tag" 2>/dev/null || continue
        if [ -n "$haveprev" ] && git -C "$PRIMARY" merge-base --is-ancestor "$ls" "$prev" 2>/dev/null; then continue; fi
        fm_get id "$f"
      done
    fi
  } | grep . | sort -u
}

render_task_section() { # render_task_section <id> <ref> — one '## <ID> — <title>' block on stdout.
  # Every field is best-effort: missing data omits the field, never dies. <ref> is grepped for the
  # landed sha (base for `report`, integrate/<date> for `seal`, when the task carries no stamp).
  local id="$1" ref="$2" tf title="" points="" risk="" lsha="" short="" ldate="" \
        cdate="" ddate="" cts="" dts="" files="" fjoined="" why="" acc="" meta="" cd_part=""
  tf="$(task_file "$id" 2>/dev/null || true)"; [ -n "$tf" ] || return 0
  title="$(fm_get title "$tf" 2>/dev/null || true)"
  points="$(fm_get points "$tf" 2>/dev/null || true)"
  risk="$(fm_get risk "$tf" 2>/dev/null || true)"
  lsha="$(fm_get landed "$tf" 2>/dev/null || true)"
  [ -n "$lsha" ] || lsha="$(landed_sha "$id" "$ref" 2>/dev/null || true)"
  if [ -n "$lsha" ]; then
    short="$(git -C "$PRIMARY" rev-parse --short "$lsha" 2>/dev/null || true)"
    ldate="$(git -C "$PRIMARY" log -1 --date=short --format=%ad "$lsha" 2>/dev/null || true)"
  fi
  cts="$(event_ts claim "$id" first)"; [ -n "$cts" ] && cdate="$(ts_date "$cts")"
  dts="$(event_ts done  "$id" last)";  [ -n "$dts" ] && ddate="$(ts_date "$dts")"
  [ -n "$points" ] && meta="${meta:+$meta · }points $points"
  [ -n "$risk" ]   && meta="${meta:+$meta · }risk $risk"
  [ -n "$short" ]  && meta="${meta:+$meta · }landed $short${ldate:+ ($ldate)}"
  [ -n "$cdate" ]  && cd_part="claimed $cdate"
  [ -n "$ddate" ]  && cd_part="${cd_part:+$cd_part → }done $ddate"
  [ -n "$cd_part" ] && meta="${meta:+$meta · }$cd_part"
  printf '\n## %s — %s\n' "$id" "$title"
  [ -n "$meta" ] && printf '%s\n' "$meta"
  [ -n "$lsha" ] && files="$(git -C "$PRIMARY" diff-tree --no-commit-id --name-only -r "$lsha" 2>/dev/null | grep . || true)"
  [ -n "$files" ] || files="$(fm_list files_owned "$tf" 2>/dev/null | grep . || true)"
  if [ -n "$files" ]; then
    fjoined="$(printf '%s\n' "$files" | awk 'NR>1{printf ", "}{printf "%s",$0}END{if(NR)printf "\n"}')"
    printf 'files touched: %s\n' "$fjoined"
  fi
  why="$(awk '
    /^## Why[ \t\r]*$/ || /^## Why this exists[ \t\r]*$/ { on=1; next }
    on && /^## / { exit }
    on { sub(/\r$/,""); if (!got && $0 ~ /^[ \t]*$/) next; got=1; print }
  ' "$tf")"
  [ -n "$why" ] && printf '\n### Why\n%s\n' "$why"
  acc="$(awk '
    /^## Acceptance/ { on=1; next }
    on && /^## / { on=0 }
    on && /^[ \t]*- \[[ xX]\]/ { sub(/\r$/,""); print }
  ' "$tf")"
  [ -n "$acc" ] && printf '\n### Acceptance\n%s\n' "$acc"
  return 0   # never let a false-y trailing test (no acceptance/why) fail the caller under set -e
}

render_sprint() { # render_sprint <n> <ref> [id…] — the whole sprint report on stdout. Byte-stable
  # given the same inputs (NO generation timestamp). Header goal + dates from the SPRINT.md header.
  local n="$1" ref="$2" goal dates id; shift 2
  goal="$(sprint_goal "$n")"; dates="$(sprint_dates "$n")"
  printf '# Sprint %s' "$n"
  [ -n "$goal" ]  && printf ' — %s' "$goal"
  [ -n "$dates" ] && printf ' (%s)' "$dates"
  printf '\n'
  for id in "$@"; do render_task_section "$id" "$ref"; done
  return 0
}

report_dirty_hint() { # report_dirty_hint <n> — report commits NOTHING and never writes the board
  # (contract sprint-report v1.1). A re-render after `done` adds done-dates the sealed render lacked,
  # so the file can differ from HEAD; left uncommitted it makes the NEXT land/seal die "working tree
  # not clean" with no visible cause. If the written file differs from HEAD, name both remedies.
  local n="$1" rel; rel="$(report_rel "$n")"
  git -C "$PRIMARY" diff --quiet -- "$rel" && return 0
  note "$rel differs from HEAD — report commits nothing. Either commit it as \`docs(sprint-$n): report refresh\`,"
  note "   or discard with \`git checkout -- $rel\`."
}

report_one() { # report_one <n> — resolve IDs, render, write <reports>/sprint-<n>.md whole, print path
  # Writes only. What happens to a file that ends up differing from HEAD — self-commit or hint —
  # is ONE decision over ALL the files an invocation wrote, so cmd_report's tail owns it (v2).
  local n="$1" ids out
  ids="$(resolve_sprint_ids "$n")"
  out="$(report_file "$n")"; mkdir -p "$(dirname "$out")"
  render_sprint "$n" "$BASE" $ids > "$out"
  say "wrote $(report_rel "$n")"
}

cmd_report() { # report [--sprint <n> | --all] — render per-sprint management reports (docs/sprints/
  # by default) from the board + git history. Writes the file(s) WHOLE (idempotent), prints the
  # path(s); the board stays read-only to it. Contract: ops/contracts/sprint-report.md.
  local n="" wrote="" sub=""
  case "${1:-}" in
    --all)
      local nums newest allids="" m ids out f tid orphans=""
      nums="$(all_sprint_numbers)"
      [ -n "$nums" ] || die "no '# SPRINT <n>' headers in ops/SPRINT.md — nothing to report"
      newest="$(printf '%s\n' "$nums" | head -1)"
      for m in $nums; do
        ids="$(resolve_sprint_ids "$m")"
        out="$(report_file "$m")"; mkdir -p "$(dirname "$out")"
        render_sprint "$m" "$BASE" $ids > "$out"
        allids="$allids
$ids"
        say "wrote $(report_rel "$m")"
      done
      # done/ tasks attributable to no sealed sprint → the newest sprint's file, under (unsealed)
      for f in "$BOARD"/done/*.md; do
        [ -f "$f" ] || continue
        tid="$(fm_get id "$f" 2>/dev/null || true)"; [ -n "$tid" ] || continue
        printf '%s\n' "$allids" | grep -qx "$tid" && continue
        orphans="$orphans $tid"
      done
      if [ -n "$orphans" ]; then
        out="$(report_file "$newest")"
        { printf '\n## (unsealed)\n'; for tid in $orphans; do render_task_section "$tid" "$BASE"; done; } >> "$out"
      fi
      wrote="$nums"; sub="docs(sprint): report refresh --all"
      ;;
    --sprint) n="${2:-}"; [ -n "$n" ] || die "usage: polaris report --sprint <n>";;
    "")       n="$(sprint_hdr_num)"; [ -n "$n" ] || die "cannot read the current sprint — ops/SPRINT.md needs a '# SPRINT <n> — <goal>' header";;
    *)        die "usage: polaris report [--sprint <n> | --all]";;
  esac
  [ -n "$sub" ] || { report_one "$n"; wrote="$n"; sub="docs(sprint-$n): report refresh"; }
  # --- the writer commits its own file when it is the only dirt (contract sprint-report v2, T-061)
  # v1.1 only WARNED about this, and a warning is read by exactly one session: a re-render after
  # `done` adds done-dates the sealed render lacked, and the file left dirty makes the NEXT land or
  # seal die "working tree not clean" with no visible cause — session B paying for session A's
  # forgotten hint. So when this runs in the primary checkout, on $BASE, and `status --porcelain`
  # holds NOTHING but the file(s) this invocation just wrote, commit them here and the trap never
  # springs. ANY other dirty path → commit NOTHING and print v1.1's hint verbatim; a human's work in
  # progress is never swept into a docs commit. Seal reaches its report through seal_report_commit
  # (on integrate/<date>, subject `docs(sprint-N): report`) and never through this tail.
  # `-uall`: without it a not-yet-tracked reports/ dir collapses to one `?? docs/sprints/` line that
  # can never equal a file path, and a first render would read as somebody else's dirt.
  local m rels dirty others=""
  rels="$(for m in $wrote; do report_rel "$m"; done)"
  dirty=""
  in_primary && [ "$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || true)" = "$BASE" ] \
    && dirty="$(git -C "$PRIMARY" status --porcelain -uall 2>/dev/null || true)"
  [ -n "$dirty" ] && others="$(printf '%s\n' "$dirty" | cut -c4- | grep -vxF "$rels" || true)"
  if [ -n "$dirty" ] && [ -z "$others" ]; then
    git -C "$PRIMARY" add -- $rels
    git -C "$PRIMARY" diff --cached --quiet -- $rels || {
      git -C "$PRIMARY" commit -q -m "$sub" -- $rels
      say "committed \`$sub\` — the report was the only dirt on $BASE"
    }
  else
    for m in $wrote; do report_dirty_hint "$m"; done   # final on-disk state per file (post-orphan append)
  fi
}

seal_report_commit() { # seal_report_commit <n> <date> — render the sprint report from THIS wave's
  # known subjects (+ prior sealed waves, resolved from base) and commit it on integrate/<date> as
  # docs(sprint-N): report — BEFORE the merge (direct) / the push (pr). No [<ID>] suffix. Idempotent:
  # a re-seal whose render is byte-identical stages nothing and makes no commit.
  local n="$1" date="$2" wave_ids ids out
  wave_ids="$(git -C "$PRIMARY" log --format=%s "$BASE..integrate/$date" 2>/dev/null \
    | grep -v '^chore(board):' | sed -n 's/.*\[\([^][]*\)\]$/\1/p' || true)"
  ids="$( { printf '%s\n' "$wave_ids"; resolve_sprint_ids "$n"; } | grep . | sort -u || true)"
  out="$(report_file "$n")"; mkdir -p "$(dirname "$out")"
  render_sprint "$n" "integrate/$date" $ids > "$out"
  git add -- "$out"
  git diff --cached --quiet -- "$out" || git commit -q -m "docs(sprint-$n): report" -- "$out"
}

cmd_learned() { # learned -m "<bullet>" — sprint-report.md v3 (T-153): ONE lesson onto ops/SPRINT.md
  # § Learned, from any lane, on any branch, from any cwd inside the repo. The Learned log stopped
  # at sprint 11 for the same reason the burndown did: its only writer was the Integrator, and a
  # hand edit of a board file is the one thing a lane standing in a feat/* worktree never does.
  # This is the pen: `- <YYYY-MM-DD> · <bullet>` appended as the section's LAST bullet (the
  # section created at EOF when the file has none), one telemetry line, one board commit
  # (`chore(board): learned`), one sync. Refuses an empty -m, more than one lesson's worth (400
  # chars — the detail belongs in the task's Notes) and a TAB or newline (the file's tables and the
  # index read those as structure). $OPS, $EVENTS and board_commit are all PRIMARY-anchored, so a
  # builder in .polaris/wt/<ID> writes the very file the seal writes — nothing to merge, ever.
  local bullet="" line sf tmp nl='
'
  [ "${1:-}" = "-m" ] && bullet="${2:-}"
  [ -n "$bullet" ] || die "learned needs -m \"<one lesson>\""
  [ "${#bullet}" -le 400 ] || die "learned: keep it to one lesson (≤ 400 chars) — the detail belongs in the task's Notes"
  case "$bullet" in *"$POLARIS_TAB"*|*"$nl"*) die "learned: one line, no TAB — the detail belongs in the task's Notes";; esac
  line="- $(date +%F) · $bullet"
  sf="$OPS/SPRINT.md"
  mutex_on
  [ -f "$sf" ] || : > "$sf"
  tmp="$(mktemp)"
  # One awk pass, plain rules (no awk functions — `find --api` would index `function x() {` as a
  # nested fn): the section runs from '## Learned' to the next heading or EOF. Blank lines inside
  # it are held and re-emitted after the bullet, so the bullet lands right under the last one and
  # the blank line that preceded the next heading stays where it was. ENVIRON, not -v: -v
  # backslash-processes its value, and a lesson may well contain one.
  POLARIS_LEARNED="$line" awk '
      BEGIN { line = ENVIRON["POLARIS_LEARNED"] }
      /^#+[ \t]/ { if (insec) { print line; done = 1; insec = 0 }
                   while (pend) { print ""; pend-- }; print
                   if (!done && /^## Learned/) insec = 1
                   next }
      !insec { print; next }
      /^[ \t\r]*$/ { pend++; next }
      { while (pend) { print ""; pend-- }; print; next }
      END { if (insec) print line; else if (!done) print "\n## Learned\n" line
            while (pend) { print ""; pend-- } }
    ' "$sf" > "$tmp" || { rm -f "$tmp"; die "learned: could not rewrite ops/SPRINT.md — nothing written"; }
  cat "$tmp" > "$sf"; rm -f "$tmp"
  evt learned "" "${bullet:0:60}"
  board_commit "chore(board): learned"
  sync_board
  mutex_off; trap - EXIT
  say "learned: $bullet"
}

# ------------------------------------------- brain — generated knowledge base (T-030)
# ops/contracts/brain.md: .polaris/brain/ (gitignored, any-model-readable) kills cold-start
# re-derivation — a cold agent finds any fact in ≤4 file-opens from INDEX.md. Generation READS
# the repo only: never mutates the board, never touches git refs, never writes outside
# .polaris/brain/ + the two stamp files (.polaris/brain/.stamp · .polaris/board-changed).

board_changed_touch() { # freshness beacon: done/seal call this AFTER their mutation succeeds.
  # Best-effort by contract — a touch failure never fails the caller.
  { mkdir -p "$PRIMARY/.polaris" && date +%s > "$PRIMARY/.polaris/board-changed"; } 2>/dev/null || true
}

brain_refresh_if_present() { # seal/done auto-refresh (ops/contracts/brain.md v1.1): after the
  # caller's board/base mutation succeeds, an EXISTING brain follows the base. No brain dir →
  # feature not opted into → silence. Failure → one ⚠ note, never a caller failure.
  # away.md § 7: whichever refresh runs clears the due marker a skipping seal/done left behind;
  # POLARIS_BRAIN_TRACE (tests only) counts the refreshes that actually run.
  rm -f "$PRIMARY/.polaris/brain-due" 2>/dev/null || true
  [ -d "$PRIMARY/.polaris/brain" ] || return 0
  [ -z "${POLARIS_BRAIN_TRACE:-}" ] || printf 'refresh\n' >> "$POLARIS_BRAIN_TRACE" 2>/dev/null || true
  "$SELF" brain --refresh >/dev/null 2>&1 \
    || note "⚠ brain refresh failed — run by hand: ops/polaris brain --refresh"
  return 0
}

brain_index() { # INDEX.md — routing table + the hop guarantee (≤40 lines)
  cat <<'EOF'
# BRAIN — generated by `ops/polaris brain` (git-ignored; never edit, never git-add)
Hop guarantee: any fact is reachable in ≤4 file-opens — this INDEX (hop 1) → one domain file
below (hop 2) → the repo file it cites by path (hops 3–4). Read this FIRST, repo second.

| looking for | read |
|---|---|
| a SYMBOL — where is X, what does X look like | run `ops/polaris find X` · `show <path>#X` (0 file reads) |
| where code lives · key symbols per directory · hotspot files | code-map.md |
| sprint goal · column counts · active/ready/blocked · recent done | board.md |
| interface contracts between tasks (the seams) | contracts.md |
| polaris CLI commands · effective CONVENTIONS values | commands.md |
| hard-won lessons · planner calibration | gotchas.md |
| house style to MATCH — indent · quotes · naming · test layout | prefs.md |
| which files change together · what came back kicked | learned.md |

stale? refresh: ops/polaris brain --refresh
EOF
}

guide_purpose() { # guide_purpose <dir> [<root>] — the purpose line of <dir>/CLAUDE.md's guide block
  # (ops/contracts/save-hops.md § 0.1): the first non-blank line inside the block, leading `#`s and
  # spaces removed. A guide is a TRACKED <dir>/CLAUDE.md holding a line that is exactly the marker;
  # the root `.` never is one. rc 1 and nothing when there is none. <root> = the tree to read
  # (default the primary; `where` passes the worktree it runs in). CRLF reads like LF.
  # § 12.3: a line that opens with the guide's own folder — `<dir>/ — `, the template's lead — loses
  # that prefix ONCE, byte-exact (LC_ALL=C, ENVIRON: no -v escapes), and only when something non-blank
  # follows, so no reader prints the folder twice. index.py's _hops_purpose applies the same rule.
  local d="${1:-}" root="${2:-$PRIMARY}"
  d="${d%/}"
  case "$d" in ''|.) return 1;; esac
  [ -f "$root/$d/CLAUDE.md" ] || return 1
  git -C "$root" ls-files --error-unmatch -- "$d/CLAUDE.md" >/dev/null 2>&1 || return 1
  POLARIS_GUIDE_LEAD="$d/ — " LC_ALL=C awk 'BEGIN { r = 1; lead = ENVIRON["POLARIS_GUIDE_LEAD"] }
    { sub(/\r$/, "") }
    !g && $0 == "<!-- polaris:guide -->" { g = 1; next }
    g && $0 == "<!-- /polaris:guide -->" { exit }
    g { s = $0; sub(/^[# ]+/, "", s)
        if (index(s, lead) == 1 && substr(s, length(lead) + 1) ~ /[^ \t]/) s = substr(s, length(lead) + 1)
        if (s ~ /[^ \t]/) { print s; r = 0; exit } }
    END { exit r }' "$root/$d/CLAUDE.md"
}

brain_code_map() { # code-map.md — per-DIRECTORY digest (≤15 lines/dir; caller caps 300 total).
  # Scale by summarizing per directory, never by listing files (contract § Hop guarantee).
  # brain v3 / minutes.md § 4.1: ONE pass — one `git ls-files -z`, one symbol grep over every tracked
  # file, one LC_ALL=C awk that prints every folder. A process start costs 30-50 ms on Git Bash, and
  # the old per-folder loop paid a dozen of them per folder. Purposes are the only per-folder work, and
  # only for folders that HAVE a guide or a README. Order is pinned in C bytes, never the locale:
  # folders; extensions by count, ties ascending; the first twelve unique symbols.
  printf '# code map — per-directory digest (files: count · symbols: grepped defs · hotspot: from ops/MAP.md)\n'
  local tmp d p map
  tmp="$(mktemp -d 2>/dev/null)" || return 0
  git -C "$PRIMARY" ls-files -z 2>/dev/null > "$tmp/ls" || true
  tr '\0' '\n' < "$tmp/ls" > "$tmp/ls.nl"
  : > "$tmp/syms"
  if [ -s "$tmp/ls" ]; then
    ( cd "$PRIMARY" && xargs -0 grep -HIE '^(cmd_[A-Za-z0-9_]+\(\)|[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{|function[ \t]|def[ \t]|class[ \t])' \
        < "$tmp/ls" 2>/dev/null ) > "$tmp/syms" || true
  fi
  # purposes: the folder's own guide speaks first (save-hops § 3.3), then its README's first heading
  : > "$tmp/purp"
  while IFS= read -r p; do
    d="${p%/CLAUDE.md}"
    p="$(guide_purpose "$d")" || continue
    printf '%s\t%s\n' "$d" "$p" >> "$tmp/purp"
  done <<GUIDES
$(grep '/CLAUDE\.md$' "$tmp/ls.nl" || true)
GUIDES
  : > "$tmp/rd"
  grep '/README\.md$' "$tmp/ls.nl" | tr '\n' '\0' > "$tmp/readmes" || true
  if [ -s "$tmp/readmes" ]; then
    ( cd "$PRIMARY" && xargs -0 env LC_ALL=C awk 'FNR == 1 { seen = 0 }
        !seen && /^#+[ \t]+/ { s = $0; sub(/\r$/, "", s); sub(/^#+[ \t]+/, "", s)
          d = FILENAME; sub(/\/README\.md$/, "", d); print d "\t" s; seen = 1 }' < "$tmp/readmes" 2>/dev/null ) \
      > "$tmp/rd" || true
  fi
  map="$tmp/nomap"; : > "$map"
  [ -f "$OPS/MAP.md" ] && map="$OPS/MAP.md"
  BCM_PURP="$tmp/purp" BCM_RD="$tmp/rd" BCM_MAP="$map" BCM_LS="$tmp/ls.nl" BCM_SYM="$tmp/syms" LC_ALL=C awk '
    function dirof(p,   i) { i = match(p, /\/[^\/]*$/); return i ? substr(p, 1, i - 1) : "." }
    FILENAME == ENVIRON["BCM_PURP"] || FILENAME == ENVIRON["BCM_RD"] {
      i = index($0, "\t"); if (!i) next
      d = substr($0, 1, i - 1); if (!(d in pur)) pur[d] = substr($0, i + 1)
      next }
    FILENAME == ENVIRON["BCM_MAP"] {
      sub(/\r$/, "")
      if ($0 ~ /^## Hotspot/) { hot = 1; next }
      if ($0 ~ /^## /) hot = 0
      if (!hot) next
      s = $0
      while (match(s, /`[^`]*`/)) {
        t = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
        if (t == "") continue
        h = dirof(t); if (!(h in hs)) hs[h] = t
      }
      next }
    FILENAME == ENVIRON["BCM_LS"] {
      if ($0 == "") next
      d = dirof($0)
      if (!(d in nf)) dirs[++nd] = d
      nf[d]++
      b = $0; sub(/^.*\//, "", b)
      if (match(b, /\.[A-Za-z0-9_]*$/)) {
        e = substr(b, RSTART)
        if (!((d, e) in ec)) { ne[d]++; el[d, ne[d]] = e }
        ec[d, e]++
      }
      next }
    FILENAME == ENVIRON["BCM_SYM"] {
      i = index($0, ":"); if (!i) next
      d = dirof(substr($0, 1, i - 1)); s = substr($0, i + 1); sub(/\r$/, "", s)
      sub(/\(\).*$/, "", s); sub(/^function[ \t]*/, "", s); sub(/^def[ \t]*/, "", s)
      sub(/^class[ \t]*/, "", s); sub(/[ ({:].*$/, "", s)
      if (s == "" || ((d, s) in sy)) next
      sy[d, s] = 1
      n = ns[d] + 0      # the twelve smallest so far, kept sorted: one insertion, never a full sort
      if (n == 12 && (s "") >= (top[d, 12] "")) next
      if (n < 12) n++
      for (j = n; j > 1 && (top[d, j - 1] "") > (s ""); j--) top[d, j] = top[d, j - 1]
      top[d, j] = s; ns[d] = n
      next }
    END {
      for (i = 2; i <= nd; i++) { x = dirs[i]; for (j = i; j > 1 && (dirs[j - 1] "") > (x ""); j--) dirs[j] = dirs[j - 1]; dirs[j] = x }
      for (i = 1; i <= nd; i++) {
        d = dirs[i]
        printf "\n## %s/\n", d
        m = ne[d] + 0
        for (a = 1; a <= m; a++) o[a] = el[d, a]
        for (a = 2; a <= m; a++) {   # count descending, ties by extension ascending
          x = o[a]
          for (j = a; j > 1 && (ec[d, o[j - 1]] < ec[d, x] || (ec[d, o[j - 1]] == ec[d, x] && (o[j - 1] "") > (x ""))); j--) o[j] = o[j - 1]
          o[j] = x
        }
        ex = ""; for (a = 1; a <= m && a <= 3; a++) ex = ex (a > 1 ? " " : "") o[a]
        printf "- files: %d%s\n", nf[d], (ex == "" ? "" : " (" ex ")")
        if (d != "." && (d in pur)) printf "- purpose: %s\n", pur[d]
        sl = ""; for (a = 1; a <= ns[d]; a++) sl = sl (a > 1 ? " " : "") top[d, a]
        if (sl != "") printf "- symbols: %s\n", sl
        if (d in hs) printf "- hotspot: %s — chain edits, never parallel-own (ops/MAP.md)\n", hs[d]
      }
    }' "$tmp/purp" "$tmp/rd" "$map" "$tmp/ls.nl" "$tmp/syms" || true
  rm -rf "$tmp"
  return 0
}

brain_board() { # board.md — live digest (caller caps 80 lines)
  local hdr=""
  [ -f "$OPS/SPRINT.md" ] && hdr="$(grep '^# SPRINT ' "$OPS/SPRINT.md" 2>/dev/null | head -1 | tr -d '\r' || true)"
  printf '%s\n' "${hdr:-# SPRINT ? — no ops/SPRINT.md header}"
  local col n counts=""
  for col in backlog ready active review blocked done; do
    n="$(ls "$BOARD/$col" 2>/dev/null | grep -c '\.md$' || true)"
    counts="$counts$col:$n · "
  done
  printf 'counts: %s\n' "${counts% · }"
  printf '\n## active (id · owner)\n'
  local f id any=0
  for f in "$BOARD/active/"*.md; do
    [ -e "$f" ] || break
    any=1; id="${f##*/}"; id="${id%.md}"
    printf -- '- %s · %s\n' "$id" "$(fm_get owner "$f")"
  done
  [ "$any" -eq 0 ] && printf -- '- (none)\n'
  printf '\n## ready (top 5 by wsjf: id · title · pts)\n'
  { for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
      id="${f##*/}"; printf '%s\t- %s · %s · %spts\n' "$(fm_get wsjf "$f")" "${id%.md}" \
        "$(fm_get title "$f")" "$(fm_get points "$f")"
    done; } | sort -rn | cut -f2- | head -5 | grep . || printf -- '- (none)\n'
  printf '\n## blocked (id · reason)\n'
  any=0
  for f in "$BOARD/blocked/"*.md; do
    [ -e "$f" ] || break
    any=1; id="${f##*/}"; id="${id%.md}"
    printf -- '- %s · %s\n' "$id" \
      "$(grep '⛔' "$f" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*-*[[:space:]]*//' | grep . || echo 'no reason recorded — open the task')"
  done
  [ "$any" -eq 0 ] && printf -- '- (none)\n'
  printf '\n## done (last 10: id · title · landed sha when stamped)\n'
  local lsha
  any=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -e "$f" ] || continue
    any=1; id="${f##*/}"; id="${id%.md}"
    lsha="$(fm_get landed "$f" 2>/dev/null || true)"
    if [ -n "$lsha" ]; then
      printf -- '- %s · %s · landed %.7s\n' "$id" "$(fm_get title "$f")" "$lsha"
    else
      printf -- '- %s · %s\n' "$id" "$(fm_get title "$f")"
    fi
  done <<EOF
$(ls -t "$BOARD/done/"*.md 2>/dev/null | head -10)
EOF
  [ "$any" -eq 0 ] && printf -- '- (none)\n'
  return 0
}

brain_contracts() { # contracts.md — per contract: name + its ## Purpose first paragraph (caller caps 120)
  printf '# contracts — the seams (digest; read the cited file before coding against it)\n'
  local f name any=0
  for f in "$OPS/contracts/"*.md; do
    [ -e "$f" ] || break
    any=1; name="${f##*/}"; name="${name%.md}"
    printf '\n## %s (ops/contracts/%s.md)\n' "$name" "$name"
    awk '/^## Purpose/{f=1;next} f&&/^#/{exit} f&&NF==0{if(p)exit;next} f{print;p=1}' "$f" 2>/dev/null || true
  done
  [ "$any" -eq 0 ] && printf 'none\n'
  return 0
}

brain_commands() { # commands.md — effective CONVENTIONS values FIRST, then polaris help (brain v1.1:
  # caller caps 80 — the cap may cut the help tail, NEVER the values; usage() alone is ~75 lines, so
  # help-first was cutting 5 of the 8 values off the bottom).
  printf '# commands — polaris CLI + effective CONVENTIONS\n\n## effective CONVENTIONS\n'
  printf 'base: %s\nclaim: %s\nintegration: %s\npublish: %s\nexpress: %s\nstale_hours: %s\ntest: %s\nbuild: %s\n' \
    "$BASE" "$CLAIM_MODE" "$(cfg integration '(unset)')" "$(cfg publish direct)" \
    "$(cfg express '(unset)')" "$STALE_H" "$(cfg test '(unset)')" "$(cfg build '(unset)')"
  printf '\n## polaris help\n'
  usage
}

brain_gotchas() { # gotchas.md — SPRINT Learned + CONVENTIONS Planner calibration, verbatim (caller caps 60)
  printf '# gotchas — lessons that already cost tokens (verbatim digests)\n'
  printf '\n## Learned (ops/SPRINT.md)\n'
  { [ -f "$OPS/SPRINT.md" ] && awk '/^## Learned/{f=1;next} /^## /{f=0} f' "$OPS/SPRINT.md"; } | grep . \
    || printf '(none)\n'
  printf '\n## Planner calibration (ops/CONVENTIONS.md)\n'
  { [ -f "$CONV" ] && awk '/^## Planner calibration/{f=1;next} /^## /{f=0} f' "$CONV"; } | grep . \
    || printf '(none)\n'
  return 0
}

brain_prefs() { # prefs.md — house style DETECTED from the repo, never declared (caller caps 40).
  # The point: a Builder writing new code should match what is already there without a human
  # writing a style guide and without a model inferring it from scratch every session. Everything
  # here is counted, and every row prints its evidence — a preference with no majority behind it is
  # reported as "mixed" rather than guessed, because a confident wrong style is worse than none.
  printf '# PREFS — detected from this repo by counting, not declared. Regenerated by `polaris brain`.\n'
  printf 'Match these when you write code: they are what the repo ALREADY does. "mixed" means no\n'
  printf 'majority exists — follow the file you are editing. Evidence is the count behind each call.\n\n'
  printf '| what | detected | evidence |\n|---|---|---|\n'
  # ONE awk pass over a bounded sample of tracked source files. Bounded on purpose: this runs on
  # every brain build, and a 10k-file repo must not pay a full read to learn its indent width.
  # `ops/` and `.claude/` are POLARIS's OWN installed code, not this repo's style. Counting them
  # told a fresh repo its convention was snake_case on the strength of 165 bash functions that
  # shipped with the tool — a confident wrong answer, and the worst kind for this file to give.
  # The `/dev/null` sentinel is LOAD-BEARING, and only on BSD: GNU xargs runs the utility once even
  # when its input is empty (stdin from /dev/null), which is how the END block below got to print
  # its "not detected" row for a repo with no application code. FreeBSD/macOS xargs does NOT run the
  # utility at all on empty input, so awk never ran, prefs.md lost the row entirely, and the brain
  # drill's `^| indent |` gate went red — macOS CI, and only macOS CI, from 5.19.0 to 6.2.1. One
  # extra file argument that is empty by construction fixes it: awk always runs, and it contributes
  # nothing to any count, so every number on every platform is byte-identical to before.
  { git -C "$PRIMARY" ls-files 2>/dev/null \
      | grep -Ev '^(ops|kit/ops|\.claude|kit/\.claude)/' \
      | grep -Ei '\.(py|js|jsx|mjs|cjs|ts|tsx|go|rs|java|kt|c|h|cc|cpp|cs|rb|php|sh|bash|css|scss)$' \
      | head -200
    printf '%s\n' /dev/null
  } \
    | tr '\n' '\0' 2>/dev/null | xargs -0 awk '
      # Length and quotes are counted on EVERY line, BEFORE the indent rules — those end in `next`,
      # so anything indented used to skip both. Since virtually all code inside a function IS
      # indented, the quote counter only ever saw top-level lines and reported "0 double vs 0
      # single | mixed" for a repo full of double quotes. gsub runs after the length read because
      # it mutates $0; it only strips quote characters, so leading whitespace survives for the
      # indent rules below.
      { if (length($0)>maxl) maxl=length($0) }
      { dq+=gsub(/"/,""); sq+=gsub(/'"'"'/,"") }
      /^\t/            { tab++;  next }
      /^ +[^ ]/        { n=match($0,/[^ ]/)-1; if (n==2) sp2++; else if (n==4) sp4++; next }
      END {
        tot=tab+sp2+sp4
        # An EMPTY sample must say so, not report zeros as if they were measurements. In a repo
        # whose only code is POLARIS itself (the kit repo, or a board installed before any app code
        # exists) the filters above legitimately match nothing, and the old END block still printed
        # "2 spaces | 0 of 1 indented lines" and "0 chars" — three confident rows backed by no data,
        # in the one file whose entire promise is that every row prints its evidence.
        if (tot==0 && maxl==0 && dq+sq==0) {
          print "| indent | not detected | no application code sampled (ops/ is POLARIS itself) |"
          exit
        }
        pick=(tab>sp2 && tab>sp4) ? "tabs" : ((sp2>=sp4) ? "2 spaces" : "4 spaces")
        printf "| indent | %s | %d of %d indented lines |\n", pick, (pick=="tabs"?tab:(pick=="2 spaces"?sp2:sp4)), (tot?tot:1)
        q=(dq>sq*1.2) ? "double" : ((sq>dq*1.2) ? "single" : "mixed")
        printf "| quotes | %s | %d double vs %d single |\n", q, dq, sq
        printf "| longest line seen | %d chars | sampled files |\n", maxl
      }' 2>/dev/null
  # Naming convention comes from the INDEX, not from a re-read: the symbol table already holds
  # every public name we know about, so this costs a query instead of a scan.
  "$SELF" find --api '*' 2>/dev/null | grep -Ev '^(ops|kit/ops|\.claude|kit/\.claude)/' | awk -F'\t' '
      $2=="fn" {
        n=$3
        if (n ~ /^[a-z][a-z0-9]*(_[a-z0-9]+)+$/) snake++
        else if (n ~ /^[a-z][a-zA-Z0-9]*[A-Z]/)  camel++
        else if (n ~ /^[A-Z]/)                    pascal++
        else                                      flat++
      }
      END {
        t=snake+camel+pascal+flat; if (!t) exit
        best="flat"; c=flat
        if (snake>c)  { best="snake_case"; c=snake }
        if (camel>c)  { best="camelCase";  c=camel }
        if (pascal>c) { best="PascalCase"; c=pascal }
        printf "| function naming | %s | %d of %d public fns |\n", best, c, t
      }' 2>/dev/null
  # Test-file convention: whatever pattern the repo's own test files already follow.
  git -C "$PRIMARY" ls-files 2>/dev/null | grep -Ev '^(ops|kit/ops)/' | awk '
      /(^|\/)test_[^\/]*$/            { a++; next }
      /[._](test|spec)\.[a-z]+$/      { b++; next }
      /(^|\/)tests?\//                { c++ }
      END {
        if (a+b+c==0) { print "| test files | none found | add one and this row learns it |"; exit }
        best="tests/ directory"; n=c
        if (a>n) { best="test_<name> prefix"; n=a }
        if (b>n) { best="<name>.test/.spec suffix"; n=b }
        printf "| test files | %s | %d files |\n", best, n
      }' 2>/dev/null
  printf '\nGolden acceptance for this repo lives in `ops/tests/` (`polaris check`). Add a pair there\n'
  printf 'rather than re-checking behavior by hand: `polaris check --scaffold` writes the mechanical half.\n'
}

brain_learned() { # learned.md — what this repo's HISTORY says, distilled (caller caps 60).
  # NOT a copy of the Learned log (gotchas.md already carries that verbatim) and NOT a copy of
  # `metrics`. This file answers the one question neither of those can: which files move TOGETHER.
  # That is the Planner's hardest judgement — files_owned sets must be disjoint, and two files that
  # have always changed in the same commit will not stay in two different tasks.
  printf '# LEARNED — distilled from this repo'"'"'s own history. Regenerated by `polaris brain`.\n\n'
  printf '## Files that change together (co-change, last 300 commits)\n'
  printf 'Carve `files_owned` so a pair here lands in the SAME task, or expect a grant mid-sprint.\n\n'
  git -C "$PRIMARY" log --format='%H' --name-only -n 300 2>/dev/null | awk '
      NF==0 { flush(); next }
      /^[0-9a-f]{40}$/ { flush(); next }
      { f[++k]=$0 }
      function flush(  i,j,a,b) {
        # Commits touching a lot of files are releases and mass-refactors: every pair in them is an
        # accident of timing, and including them drowns the real signal. 15 is the cutoff.
        if (k>1 && k<=15)
          for (i=1;i<k;i++) for (j=i+1;j<=k;j++) {
            a=f[i]; b=f[j]; if (a>b) { t=a; a=b; b=t }
            pair[a"\t"b]++
          }
        k=0; delete f
      }
      END {
        flush()
        n=0
        for (p in pair) if (pair[p]>=3) { out[++n]=pair[p]"\t"p }
        if (!n) { print "(nothing yet — needs a few more commits of history)"; exit }
        # crude descending sort, bounded: n is small by construction
        for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) {
          split(out[i],x,"\t"); split(out[j],y,"\t")
          if (y[1]+0 > x[1]+0) { t=out[i]; out[i]=out[j]; out[j]=t }
        }
        for (i=1;i<=n && i<=12;i++) { split(out[i],x,"\t"); printf "- %sx  %s + %s\n", x[1], x[2], x[3] }
      }' 2>/dev/null
  printf '\n## Kickbacks — what came back, and why\n'
  if [ -s "$EVENTS" ]; then
    awk -F'"' '/"ev":"kickback"/ {
        id=""; note=""
        # With every quote a field separator, a key is its OWN field and its value sits two fields
        # on: id, then the colon, then T-1. The old test hunted a quote no field can ever hold, so
        # this section had never listed a single kickback (T-178). First match wins, so a key
        # spelled inside the text of a note can never overwrite the real one; an escaped quote
        # in a note splits it too, so the pieces are glued back and unescaped.
        for (i=1;i<NF-1;i++) {
          if (id=="" && $i=="id" && $(i+1)==":") id=$(i+2)
          if (note=="" && $i=="note" && $(i+1)==":") {
            note=$(i+2); j=i+3
            while (note ~ /\\$/ && j<=NF) { note=note "\"" $j; j++ }
            gsub(/\\"/, "\"", note)
          }
        }
        n++; printf "- %s — %s\n", id, (note==""?"(no reason recorded)":note)
      }
      END { if (!n) print "None on this board. A kickback here would name the task and the reason." }
    ' "$EVENTS" 2>/dev/null | tail -n 12   # the NEWEST twelve: last month's lesson beats last year's
  else
    printf 'No telemetry yet — runs accumulate it.\n'
  fi
  printf '\nPointing calibration and cycle times: `polaris metrics`. Sprint lessons: gotchas.md.\n'
}

_brain_put() { # _brain_put <file> <cap|-> <cmd…> — brain v3 atomic write (minutes.md § 4.2): <cmd>'s
  # output (its first <cap> lines; `-` = all of it) goes to <file>.tmp.$$ in the same folder, then
  # `mv -f` onto <file>, so a reader never sees half a file. A failed write removes the temp file,
  # leaves the old <file> in place and stops the build. The command's own status is not read: `head`
  # closing the pipe early is how a cap works, not a failure.
  local f="$1" cap="$2" t="$1.tmp.$$"
  shift 2
  if [ "$cap" = "-" ]; then
    "$@" > "$t" || true
  else
    "$@" | head -n "$cap" > "$t" || true
  fi
  # A folder squatting on <file>'s name is a failed write: `mv` would quietly drop the file inside it.
  if [ -f "$t" ] && [ ! -d "$f" ] && mv -f "$t" "$f" 2>/dev/null; then return 0; fi
  rm -f "$t" 2>/dev/null || true
  die "cannot write $f — the old copy is kept"
}

cmd_brain() { # brain [--refresh] — generate .polaris/brain/ (ops/contracts/brain.md).
  # Full build by default. --refresh: cheap files (board/contracts/commands/gotchas + INDEX)
  # always rebuilt; code-map.md ONLY when `git diff --name-only <stamp-sha>..HEAD` is non-empty
  # (unreadable stamp sha degrades to a rebuild). Missing brain → full build. Exit 0 on success.
  local mode="${1:-}"
  { [ -z "$mode" ] || [ "$mode" = "--refresh" ]; } || die "usage: polaris brain [--refresh]"
  local BR="$PRIMARY/.polaris/brain"
  local stamp_sha="" build_map=1 kind=built
  if [ "$mode" = "--refresh" ] && [ -f "$BR/.stamp" ]; then
    kind=refreshed
    stamp_sha="$(awk 'NR==1{print $2}' "$BR/.stamp" 2>/dev/null || true)"
    if [ -n "$stamp_sha" ] && [ -f "$BR/code-map.md" ]; then
      local changed
      changed="$(git -C "$PRIMARY" diff --name-only "$stamp_sha..HEAD" 2>/dev/null || echo stamp-sha-unreadable)"
      [ -z "$changed" ] && build_map=0
    fi
  fi
  mkdir -p "$BR" || die "cannot create $BR"
  _brain_put "$BR/INDEX.md" - brain_index
  if [ "$build_map" -eq 1 ]; then _brain_put "$BR/code-map.md" 300 brain_code_map; fi
  _brain_put "$BR/board.md"     80  brain_board
  _brain_put "$BR/contracts.md" 120 brain_contracts
  _brain_put "$BR/commands.md"  80  brain_commands
  _brain_put "$BR/gotchas.md"   60  brain_gotchas
  # v2 (5.19.0): the two files that make the brain ACCUMULATE rather than just digest. Both are
  # cheap-tier — always rebuilt, never gated on the code-map's changed-files check — because both
  # read history/index rather than the tree, and a stale preference is a wrong preference.
  _brain_put "$BR/prefs.md"     40  brain_prefs
  _brain_put "$BR/learned.md"   60  brain_learned
  local ep sha
  ep="$(date +%s)"
  sha="$(git -C "$PRIMARY" rev-parse --short "refs/heads/$BASE" 2>/dev/null \
      || git -C "$PRIMARY" rev-parse --short HEAD 2>/dev/null || echo none)"
  _brain_put "$BR/.stamp" - printf '%s %s\n' "$ep" "$sha"
  say "brain $kind: .polaris/brain/ (INDEX + code-map$( [ "$build_map" -eq 1 ] || printf ' [unchanged, kept]' ) + board + contracts + commands + gotchas + prefs + learned) · stamp $ep $sha"
}

# ------------------------------------------- where — the root map (ops/contracts/save-hops.md § 0.2, § 3.4)
# "Where things live" in ≤ 15 lines between two markers in the repo-root CLAUDE.md — the one file every
# session already has in context — so a cold agent knows where to look before it searches. A PROJECTION,
# never a second source: the facts live in ops/MAP.md (Entry points · Modules · the Deltas tail) and in
# the folder guides; edit those and the next `where --write` follows (`done` runs it beside a map_delta).
# Writes go through a temp file + mv, as install.sh does for the managed block, and never touch a byte
# outside the markers: head/tail copy the rest of the file, CRLF lines and a missing last newline kept.
_where_items() { # _where_items <root> block|stale [<open> <close>] — the ONE parse of <root>/ops/MAP.md
  # (§ 0.2), shared by `where` and drift's MAP STALE advisory (§ 14.3) so the two never disagree. An
  # item survives only when its path, trailing / dropped, is a TRACKED file of <root> or a folder that
  # holds one (§ 14.2). block → line 1 the survivor count, then the block between <open> and <close>
  # (the 13 cap counts survivors) · stale → each MAP item that rule drops, as MAP writes it (backticks
  # stripped), MAP order, once. The tracked list is ONE `git ls-files` into a temp file the awk reads,
  # never the environment (Windows caps it at ~32 KB); the guided folders come off that same list.
  local root="$1" want="$2" map="$1/ops/MAP.md" trk f p g="" rc=0 nl='
'
  if [ ! -f "$map" ]; then
    if [ "$want" = stale ]; then return 0; fi                # no MAP.md: it lists nothing, so nothing is stale
    map=/dev/null
  fi
  trk="$(mktemp)" || return 1
  git -C "$root" -c core.quotepath=off ls-files > "$trk" 2>/dev/null || true
  if [ "$want" = block ]; then
    # the guided folders (§ 0.1): every tracked <dir>/CLAUDE.md holding the marker → "dir NL purpose NL"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      p="$(guide_purpose "${f%/CLAUDE.md}" "$root")" || continue
      g="$g${f%/CLAUDE.md}$nl$p$nl"
    done <<EOF
$(grep '/CLAUDE\.md$' "$trk" || true)
EOF
  fi
  # ONE awk over MAP.md, in bytes (LC_ALL=C) so every awk counts alike: the 90-character cut walks
  # UTF-8 by hand and never splits a character.
  G="$g" LC_ALL=C awk -v want="$want" -v om="${3:-}" -v cmk="${4:-}" '
      function cut(s,   i, n, c) {   # the first 90 characters, then "…" — continuation bytes do not count
        for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if ((c < "\200" || c > "\277") && ++n > 90) return substr(s, 1, i - 1) "…" }
        return s
      }
      function keep(b, p, q) { if (p != "" && substr(p, 1, 1) != "<") { nb[b]++; P[b, nb[b]] = p; Q[b, nb[b]] = q; O[++no] = b SUBSEP nb[b] } }
      function trow(b, row,   f) {   # | <c1> | <c2> | … → path = c1 minus backticks and spaces, purpose = c2
        split(row, f, "|"); gsub(/[` \t]/, "", f[2]); sub(/^[ \t]+/, "", f[3]); sub(/[ \t]+$/, "", f[3]); keep(b, f[2], f[3])
      }
      function lrow(b, row,   i, p, q) {   # [- ]<path> — <purpose>, a Delta trailing (<ID>, <date>) dropped
        sub(/^- /, "", row); i = index(row, DASH); if (i < 2) return
        p = substr(row, 1, i - 1); if (p ~ /[ \t]/) return
        gsub(/`/, "", p); q = substr(row, i + length(DASH)); sub(TRAILER, "", q); keep(b, p, q)
      }
      function endtable(  x) { if (pend != "") trow(pb, pend); pend = "" }
      function item(p, q, g) { return "- `" p "`" (q != "" ? DASH cut(q) : "") (g ? " · guide" : "") }
      BEGIN {
        DASH = " — "; TRAILER = "[ \t]+\\([A-Za-z0-9._-]+, [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\\)$"
        n = split(ENVIRON["G"], gl, "\n"); for (i = 1; i < n; i += 2) { gd[++gn] = gl[i]; gp[gl[i]] = gl[i + 1] }
        # the tracked tree (§ 14.2): every tracked file and every folder above one. ARGV[1] is read
        # here, then struck from the operands, so the rules below only ever see MAP.md.
        while ((getline t < ARGV[1]) > 0) {
          sub(/\r$/, "", t); if (t == "") continue
          T[t] = 1; nt++; while (sub("/[^/]*$", "", t) && !(t in T)) T[t] = 1
        }
        close(ARGV[1]); ARGV[1] = ""; if (nt) T["."] = 1
      }
      { sub(/\r$/, "") }
      /^## / { endtable(); h = tolower(substr($0, 4)); sec = ""
               if (index(h, "entry points") == 1) sec = "E"; else if (index(h, "modules") == 1) sec = "M"
               else if (index(h, "deltas") == 1) sec = "D"
               next }
      /^# / { endtable(); sec = ""; next }
      (sec == "E" || sec == "M") && /^\|/ {
        if ($0 ~ /^\|[-:| \t]*$/ && $0 ~ /-/) { pend = ""; next }   # the delimiter row: the line above was the header
        endtable(); pend = $0; pb = sec; next
      }
      { endtable() }
      sec == "E" || sec == "M" { lrow(sec, $0); next }
      sec == "D" || $0 ~ TRAILER { lrow("D", $0) }   # a Delta done appended below a later heading counts too
      END {
        endtable()
        if (want == "stale") {                                 # MAP order (O), once per path
          for (i = 1; i <= no; i++) {
            p = P[O[i]]; key = p; sub(/\/$/, "", key)
            if (!(key in T) && !(key in told)) { told[key] = 1; print p }
          }
        } else {
          for (bi = 1; bi <= 3; bi++) {
            b = substr("EMD", bi, 1)
            for (j = 1; j <= nb[b]; j++) {
              p = P[b, j]; key = p; sub(/\/$/, "", key); if (key in seen) continue
              seen[key] = 1; if (!(key in T)) continue          # gone from the tree: no item (§ 14.2)
              q = Q[b, j]; if (q == "" && (key in gp)) q = gp[key]
              out[++k] = item(p, q, key in gp)
            }
          }
          for (i = 1; i <= gn; i++) if (!(gd[i] in seen)) { seen[gd[i]] = 1; out[++k] = item(gd[i] "/", gp[gd[i]], 1) }
          print k + 0; print om; print "## Where things live"
          print "_Generated by `ops/polaris where` from ops/MAP.md and the folder guides — edit those, not this._"
          for (i = 1; i <= k && i <= 13; i++) {
            if (k > 13 && i == 13) print "- … " (k - 12) " more in ops/MAP.md"; else print out[i]
          }
          print cmk
        }
      }' "$trk" "$map" || rc=$?
  rm -f "$trk"
  return "$rc"
}

cmd_where() { # where [--write | --strip] — print the root map · write it below the POLARIS block · take it out
  local mode="${1:-}"
  case "$#:$mode" in 0:|1:--write|1:--strip) ;; *) die "usage: polaris where [--write | --strip]";; esac
  # WHICH tree — check's test: inside a task worktree it is THAT tree (the layout pass writes its map
  # on its own branch); anywhere else, the primary.
  local root="$PRIMARY" wt
  case "$PWD" in */.polaris/wt/*) wt="${PWD##*/.polaris/wt/}"; wt="${wt%%/*}"
    [ -n "$wt" ] && [ -d "$PRIMARY/.polaris/wt/$wt" ] && root="$PRIMARY/.polaris/wt/$wt";; esac
  local cm="$root/CLAUDE.md" om='<!-- polaris:where -->' cmk='<!-- /polaris:where -->' block="" k=0
  if [ "$mode" = "--write" ] && [ ! -f "$cm" ]; then note "where: no CLAUDE.md here — nothing to write"; return 1; fi
  if [ "$mode" != "--strip" ]; then
    # Line 1 out is the item count, then the block.
    block="$(_where_items "$root" block "$om" "$cmk")" || { note "where: cannot read ops/MAP.md"; return 1; }
    k="${block%%[!0-9]*}"; block="${block#$k}"; block="${block#?}"
    if [ -z "$mode" ]; then printf '%s\n' "$block"; return 0; fi
  fi
  [ -f "$cm" ] || return 0                                   # --strip with no CLAUDE.md: nothing to take out
  # Locate in ONE read: our block (s..t; sb = a blank line right above it), the managed block's END
  # line (e) and the line count (n).
  local pos s t e n sb cr="" crc first="" tmp="$cm.polaris-tmp" l nonl=0
  pos="$(awk -v om="$om" -v cmk="$cmk" -v em='<!-- POLARIS:END -->' '
      { sub(/\r$/, "") }
      !s && $0 == om { s = NR; sb = (NR > 1 && prev ~ /^[ \t]*$/) }
      s && !t && NR > s && $0 == cmk { t = NR }
      !e && index($0, em) == 1 { e = NR }
      { prev = $0 }
      END { print s + 0, t + 0, e + 0, NR + 0, sb + 0 }' "$cm")" || { note "where: cannot read CLAUDE.md"; return 1; }
  set -- $pos; s="$1" t="$2" e="$3" n="$4" sb="$5"
  if [ "$s" -gt 0 ] && [ "$t" -eq 0 ]; then
    note "where: CLAUDE.md has $om but no $cmk below it — mend it by hand; nothing changed"; return 1
  fi
  if [ "$mode" = "--strip" ]; then
    [ "$s" -gt 0 ] || return 0                               # no root map: silence
    if [ "$sb" -eq 1 ]; then s=$((s - 1)); fi              # and ONE blank line directly above it
    { if [ "$s" -gt 1 ]; then head -n "$((s - 1))" "$cm"; fi; tail -n +"$((t + 1))" "$cm"; } > "$tmp" \
      && mv -f "$tmp" "$cm" || { rm -f "$tmp"; note "where: could not rewrite CLAUDE.md — nothing changed"; return 1; }
    printf 'where: root map removed\n'; return 0
  fi
  if [ "$s" -gt 0 ] && [ "$(sed -n "${s},${t}p" "$cm" | tr -d '\r')" = "$block" ]; then
    printf 'where: root map unchanged\n'; return 0           # and the file is not rewritten
  fi
  # The block is written in the file's own line ending, read off line 1 by bash itself: on Git Bash
  # awk, grep and sed drop the CR before a script sees it — only a builtin read (or head/tail) keeps it.
  crc="$(printf '\r')"; { IFS= read -r first || true; } < "$cm"
  case "$first" in *"$crc") cr="$crc";; esac
  if [ -n "$(tail -c 1 "$cm")" ]; then nonl=1; fi           # the last line has no newline of its own
  {
    if [ "$s" -gt 0 ]; then                                  # replace it where it sits
      if [ "$s" -gt 1 ]; then head -n "$((s - 1))" "$cm"; fi
    else                                                     # first write: below END (none → at EOF), one blank line above
      if [ "$e" -gt 0 ]; then head -n "$e" "$cm"; else cat "$cm"; fi
      if [ "$nonl" -eq 1 ] && { [ "$e" -eq 0 ] || [ "$e" -eq "$n" ]; }; then printf '%s\n' "$cr"; fi
      printf '%s\n' "$cr"
    fi
    while IFS= read -r l; do printf '%s%s\n' "$l" "$cr"; done <<EOF
$block
EOF
    if [ "$s" -gt 0 ]; then tail -n +"$((t + 1))" "$cm"; elif [ "$e" -gt 0 ]; then tail -n +"$((e + 1))" "$cm"; fi
  } > "$tmp" && mv -f "$tmp" "$cm" || { rm -f "$tmp"; note "where: could not rewrite CLAUDE.md — nothing changed"; return 1; }
  printf 'where: root map written to CLAUDE.md (%s items)\n' "$k"
}
