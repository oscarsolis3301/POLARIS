# lib/visual.sh — SEEING YOUR WORK: the path rules that give every task a shot folder a human can
# read, the pack section that names the capture step, and the capture gate both cmd_verify and
# cmd_handoff run (ops/contracts/visual-check.md § v2; where the code lives: module-layout.md § v8).

visual_slug() { # visual_slug <text> — a SAFE relative shot folder, or EMPTY when the text cannot be
  # made safe (ops/contracts/visual-check.md § v2.3). This is the ONLY place in POLARIS where a human
  # string becomes a filesystem path, so it refuses the way `id_ok` refuses (lib/workspace.sh):
  # a return, never a die — the caller's answer to "unsafe" is misc/, not a dead session.
  # The refusals are tested against the RAW text, BEFORE the transform, because the transform itself
  # LAUNDERS an attack: `../../etc/passwd` loses its dots to the character filter and would come back
  # out as the perfectly innocent `etc/passwd`. `*..*` is deliberately broader than "a `..` segment" —
  # over-refusing costs a folder named misc/, under-refusing costs a write outside the repo.
  # bash 3.2: lowercase is `tr`, never `${x,,}`.
  local raw="${1:-}"
  local t
  local s
  t="$(printf '%s' "$raw" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##')"
  case "$t" in
    ''|/*|*..*|*\\*|[A-Za-z]:*) return 0 ;;
  esac
  # spaces and underscores become `-`, everything outside [a-z0-9/-] is dropped, runs of separators
  # collapse (`- / -` collapses to ONE slash, which is what makes `Homepage / Universal Search Bar`
  # come out as `homepage/universal-search-bar`), and the edges are stripped so no segment starts or
  # ends with a separator.
  s="$(printf '%s' "$t" | tr 'A-Z' 'a-z' \
     | sed -e 's#[[:space:]_]#-#g' -e 's#[^a-z0-9/-]##g' \
           -e 's#-*/-*#/#g' -e 's#//*#/#g' -e 's#--*#-#g' \
           -e 's#^[-/]*##' -e 's#[-/]*$##')"
  [ -n "$s" ] || return 0
  case "$s" in */*/*) return 0 ;; esac    # deeper than two segments — that is a tree, not a screen
  printf '%s\n' "$s"
}

visual_shotdir() { # visual_shotdir <ID> — the task's capture directory: always printed (absolute),
  # always created (ops/contracts/visual-check.md § v2.3). The folder is named after the SCREEN, out
  # of the task's `screen:` field, because `.polaris/shots/T-042-home.png` is keyed by an ID that
  # means nothing to a human and browses to nothing. `screen:` unset, unreadable, or slugging to
  # empty falls back to `.polaris/shots/misc` — every task ALWAYS has somewhere to put its pictures.
  local id="${1:-}"
  local tf
  local slug
  local dir
  tf=""
  slug=""
  if [ -n "$id" ]; then tf="$(task_file "$id" 2>/dev/null || true)"; fi
  if [ -n "$tf" ] && [ -r "$tf" ]; then slug="$(visual_slug "$(fm_get screen "$tf" 2>/dev/null || true)")"; fi
  if [ -n "$slug" ]; then dir="$PRIMARY/.polaris/shots/$slug"; else dir="$PRIMARY/.polaris/shots/misc"; fi
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s\n' "$dir"
}

visual_shots_for() { # visual_shots_for <ID> <since-epoch> — this task's USABLE captures, one absolute
  # path per line, oldest first (ops/contracts/visual-check.md § v2.5). Usable = non-empty (`-s`: a
  # blank image is a failure, v1 doctrine) AND mtime at or after <since>.
  # THREE locations, in this pinned order: the task's shotdir · misc/ · flat `.polaris/shots/`. None
  # of them is belt-and-braces. The stray sweep only files captures at handoff, so looking in the
  # shotdir alone would make a mid-flight `verify` warn on every visual task; a `screen:` added AFTER
  # a capture was taken would orphan that capture; and every pre-6.6 repo's `shot:` line still writes
  # flat, which POLARIS can never require it to stop doing — it ships no capture tool.
  # De-duplicated by basename, first location wins. bash 3.2 has no globstar: `find`, never `**`.
  local id="${1:-}"
  local since="${2:-0}"
  local root
  local dir
  local f
  local b
  local mt
  local seen
  local rows
  [ -n "$id" ] || return 0
  case "$since" in ''|*[!0-9]*) since=0 ;; esac
  root="$PRIMARY/.polaris/shots"
  seen=""
  rows=""
  for dir in "$(visual_shotdir "$id")" "$root/misc" "$root"; do
    [ -d "$dir" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -s "$f" ] || continue
      mt="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
      case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
      [ "$mt" -ge "$since" ] || continue
      b="${f##*/}"
      case "$seen" in *"|$b|"*) continue ;; esac
      seen="$seen|$b|"
      rows="$rows$mt $f
"
    done <<EOF_SHOTS
$(find "$dir" -maxdepth 1 -type f -name "$id-*.png" 2>/dev/null)
EOF_SHOTS
  done
  [ -n "$rows" ] || return 0
  # the mtime leads each row precisely so the sort is numeric on ONE field and the path — spaces and
  # all — is simply everything after the first space.
  printf '%s' "$rows" | sort -s -k1,1n | cut -d' ' -f2-
}

visual_pack() { # visual_pack <ID> <owned> — pack's SEE YOUR WORK section, the owned patterns as ARG 2.
  # (ops/contracts/visual-check.md § v2.8, which supersedes v1's § cmd_pack): the capture step, driven
  # by real cfg reads of visual:/shot:/serve:/port_base: so each repo plugs in its own tool. Absent by
  # default — no visual: ⇒ one line and nothing else changes. `touches it` = any files_owned
  # pattern vs any visual: glob, both directions (pat_overlap, the claim gate's matcher); the globs
  # are read through a here-doc, never a bare $vis, which the shell would expand against the cwd.
  # Per-task port = port_base + (numeric tail of the ID mod 100): T-207 ⇒ +7, no digits ⇒
  # port_base, no port_base ⇒ {PORT} stays literal.
  # v2 adds the screen, its folder, and the SAME shot: line printed twice. The before-capture is the
  # point, not a formality: it makes the agent LOOK at the screen it is about to overhaul, and it is
  # the half a stakeholder actually reacts to. The shotdir is PRINTED as information and never
  # substituted into `shot:` — a repo whose capture tool takes an output path can write straight into
  # it, and every repo that cannot has its strays filed at handoff. One mechanism, one thing to test.
  local id="${1:-}"
  local owned="${2:-}"
  pack_section "SEE YOUR WORK — capture before handoff (ops/VISUAL.md)"
  local vis vshot vserve vbase vport vnum vhit
  local vtf vscreen vshotdir
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
    vtf=""
    vscreen=""
    if [ -n "$id" ]; then vtf="$(task_file "$id" 2>/dev/null || true)"; fi
    if [ -n "$vtf" ] && [ -r "$vtf" ]; then vscreen="$(fm_get screen "$vtf" 2>/dev/null || true)"; fi
    # An unset screen: is said out loud rather than silently defaulted, so a Planner notices that this
    # surface has no name and that a stakeholder is being handed a folder called misc/.
    if [ -n "$vscreen" ]; then
      printf 'screen: %s\n' "$vscreen"
    else
      printf 'screen: (unset — no name for this surface; shots land in misc/)\n'
    fi
    vshotdir="$(visual_shotdir "$id")"
    printf 'shotdir: %s\n' "${vshotdir#$PRIMARY/}"
    if [ -n "$vserve" ]; then
      if [ -n "$vport" ]; then vserve="${vserve//\{PORT\}/$vport}"; fi
      printf 'serve: %s\n' "$vserve"
    fi
    if [ -n "$vshot" ]; then
      vshot="${vshot//\{ID\}/$id}"
      if [ -n "$vport" ]; then vshot="${vshot//\{PORT\}/$vport}"; fi
      printf 'shot BEFORE you edit: %s\n' "$vshot"
      printf 'shot AFTER you edit: %s\n' "$vshot"
      printf 'name them: %s-before-<what>.png and %s-after-<what>.png, in the shotdir above\n' "$id" "$id"
    else
      printf 'shot: (unset — set shot: in ops/CONVENTIONS.md; ops/VISUAL.md)\n'
    fi
    if [ -n "$vport" ]; then printf 'port: %s\n' "$vport"; else printf 'port: (port_base unset — {PORT} stays literal)\n'; fi
    printf 'proof: TWO non-empty captures for %s, both newer than your branch base — READ both, then:\n' "$id"
    printf '       bash ops/polaris handoff --saw "<what the after shot shows, and how it measures against ops/DESIGN.md — PASS / WEAK / FAIL>"\n'
    printf 'nothing existed to photograph (a brand-new screen)? bash ops/polaris handoff --no-before "<why>" --saw "…"\n'
    printf 'read: ops/VISUAL.md\n'
    if [ -f "$OPS/DESIGN.md" ]; then printf 'read: ops/DESIGN.md — the bar this screen must clear\n'; fi
  fi
}

visual_gate() { # visual_gate <ID> <mode> <need> <saw> — the capture gate, ONE body, both callers.
  # A diff that touches a visual: path ships with its pictures or not at all
  # (ops/contracts/visual-check.md § v2.6). Fires only when BOTH visual: and shot: are set (absent by
  # default) AND the branch's diff has a path matching a visual: glob; then <need> non-empty captures
  # for <ID> must be newer than the branch base (the merge-base commit's time), else the handoff dies
  # HERE — before any board write, so the task stays in active/.
  # COUNT AND FRESHNESS, never names. POLARIS ships no capture tool: `shot:` is the repo's own command
  # and may be positional with no output flag, so a gate that insisted on a particular FILENAME would
  # make every visual task in every 6.2.0-6.5.0 repo permanently un-handoffable, with no escape. The
  # before/after naming is a convention for pairing pictures in the gallery, and is never tested.
  # WHERE it looks is visual_shots_for's three-location search, so a capture already filed under its
  # screen folder counts exactly as much as one still lying flat from a pre-6.6 shot: line.
  # `mode` alone decides the git anchor AND the ending, and they are the ONLY differences: `die`
  # (cmd_handoff) reads the PRIMARY's $BASE...feat/<ID> and refuses; `warn` (cmd_verify) reads the
  # worktree's $BASE...HEAD, prints the SAME sentence behind the warning mark instead of
  # `⛔ handoff refused: `, ignores <saw> entirely and never refuses — mid-flight the shots may not be
  # taken yet. The two sentences are deliberate near-duplicates and only the handoff one is pinned by
  # a golden, so a careless edit here changes the half nothing is watching.
  # <saw> is checked for EMPTINESS and nothing else — no length floor, no vocabulary check. No
  # validator can tell whether anyone LOOKED, and a refusal a builder satisfies by padding is a
  # compliance ritual that costs tokens and proves nothing. What the text is FOR is the caption a
  # human reads beside the picture, so the bar verdict is ASKED for (pack, ops/DESIGN.md, the role
  # prose) and never enforced by code.
  local id="${1:-}"
  local mode="${2:-die}"
  local need="${3:-2}"
  local saw="${4:-}"
  local vdir vhead
  local vis shot vf vhit vbase vcount vmsg
  if [ "$mode" = die ]; then vdir="$PRIMARY"; vhead="feat/$id"; else vdir="."; vhead=HEAD; fi
  case "$need" in ''|*[!0-9]*) need=2 ;; esac
  vis="$(cfg visual "")"; shot="$(cfg shot "")"
  if [ -n "$vis" ] && [ -n "$shot" ]; then
    vhit=0
    while IFS= read -r vf; do
      [ -n "$vf" ] || continue
      if printf '%s\n' "$vis" | tr ' ' '\n' | owned_match "$vf"; then vhit=1; break; fi
    done <<EOF_VGATE
$(git -C "$vdir" diff --name-only --no-renames "$BASE...$vhead")
EOF_VGATE
    if [ "$vhit" -eq 1 ]; then
      vbase="$(git -C "$vdir" log -1 --format=%ct "$(git -C "$vdir" merge-base "$BASE" "$vhead")" 2>/dev/null || echo 0)"
      vcount="$(visual_shots_for "$id" "${vbase:-0}" | awk 'END{print NR+0}')"
      case "$vcount" in ''|*[!0-9]*) vcount=0 ;; esac
      if [ "$vcount" -lt "$need" ]; then
        if [ "$need" -ge 2 ]; then
          vmsg="$id changed a visual: path but .polaris/shots/ has fewer than 2 captures for $id newer than the branch base — run the shot: line from pack BEFORE and AFTER your edit, LOOK at both, then hand off"
        else
          vmsg="$id changed a visual: path but .polaris/shots/ has no capture for $id newer than the branch base — run the shot: line from pack, LOOK at the image, then hand off"
        fi
        if [ "$mode" = die ]; then die "handoff refused: $vmsg"; else note "⚠ $vmsg"; fi
      fi
      if [ "$mode" = die ] && [ -z "$saw" ]; then
        die "handoff refused: $id changed a visual: path — say what you saw: bash ops/polaris handoff --saw \"<what the after shot shows, and how it measures against ops/DESIGN.md>\""
      fi
    fi
  fi
}

visual_file_strays() { # visual_file_strays <ID> — file the strays (ops/contracts/visual-check.md
  # § v2.6). Every <ID>-*.png lying anywhere under .polaris/shots/ but OUTSIDE this task's shotdir is
  # moved into it, at handoff, after the gate passes and before the board write. This is the whole
  # reason a pre-6.6 repo keeps working: its shot: line writes flat, POLARIS can never require it to
  # stop, so POLARIS tidies up afterwards instead of refusing.
  # It NEVER deletes and NEVER overwrites — a name collision keeps the existing file and leaves the
  # stray exactly where it is, because the only thing worse than a scattered capture is a lost one.
  # Absent-by-default and cheap-by-default: no visual: key, or no shots tree at all, and it returns
  # before visual_shotdir can mkdir anything, so a repo that never captures grows no folders.
  local id="${1:-}"
  local root dir f b
  [ -n "$id" ] || return 0
  [ -n "$(cfg visual "")" ] || return 0
  root="$PRIMARY/.polaris/shots"
  [ -d "$root" ] || return 0
  dir="$(visual_shotdir "$id")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    case "$f" in "$dir"/*) continue ;; esac
    b="${f##*/}"
    if [ -e "$dir/$b" ]; then continue; fi
    mv "$f" "$dir/$b" 2>/dev/null || true
  done <<EOF_STRAYS
$(find "$root" -type f -name "$id-*.png" 2>/dev/null)
EOF_STRAYS
}

visual_caption() { # visual_caption <ID> <saw> <no-before-reason> — the words that go beside the
  # pictures (ops/contracts/visual-check.md § v2.6), written into the shotdir at handoff and
  # overwritten on a re-handoff so the file always describes the CURRENT hand-off.
  # The <saw> text lands VERBATIM. It is the half a gate can never supply: the gate proves the
  # pictures exist, this records what somebody said is in them, and a human reading those words next
  # to the image is what actually closes the loop.
  # A skipped before-shot records its REASON here rather than vanishing, so the gallery shows WHY
  # there is only one picture instead of quietly showing one.
  local id="${1:-}"
  local saw="${2:-}"
  local why="${3:-}"
  local dir tf title screen shots first last
  [ -n "$id" ] || return 0
  [ -n "$saw" ] || return 0
  [ -n "$(cfg visual "")" ] || return 0
  dir="$(visual_shotdir "$id")"
  [ -d "$dir" ] || return 0
  tf="$(task_file "$id" 2>/dev/null || true)"
  title=""
  screen=""
  if [ -n "$tf" ] && [ -r "$tf" ]; then
    title="$(fm_get title "$tf" 2>/dev/null || true)"
    screen="$(fm_get screen "$tf" 2>/dev/null || true)"
  fi
  # oldest first, newest last — visual_shots_for's own order, so which picture is the BEFORE is
  # decided by the clock and never by a filename. One capture plus a reason reads as a skipped one.
  shots="$(visual_shots_for "$id" 0)"
  first="$(printf '%s\n' "$shots" | awk 'NF{print;exit}')"
  last="$(printf '%s\n' "$shots" | awk 'NF{l=$0} END{print l}')"
  {
    printf '# %s — %s\n\n' "$id" "${title:-untitled}"
    printf '%s\n\n' "$saw"
    if [ -n "$screen" ]; then printf -- '- screen: %s\n' "$screen"; else printf -- '- screen: (unset — filed under misc/)\n'; fi
    if [ -n "$why" ]; then printf -- '- before: (skipped — %s)\n' "$why"; else printf -- '- before: %s\n' "${first##*/}"; fi
    printf -- '- after: %s\n' "${last##*/}"
    printf -- '- date: %s\n' "$(date +%Y-%m-%d)"
  } > "$dir/$id.md" 2>/dev/null || true
}

visual_index() { # visual_index <root> <mode> — rewrite <root>/INDEX.md, the ONE file the owner opens
  # (visual-check.md § v2.9). `shots` indexes the local churn — a `##` per screen, a `###` per task
  # newest-first, the builder's own words, before BESIDE after; `gallery` indexes the committed copy,
  # one curated image per screen. Links are RELATIVE to <root> so VS Code's preview renders them: an
  # absolute path shows a broken image, and the image IS the product. Rewritten whole through a temp
  # name in the SAME directory. bash 3.2: no `case` inside $(…), so both searches are chosen up here.
  local root="${1:-}"
  local mode="${2:-shots}"
  local units tmp unit rel slug hname caps cap rows img bimg aimg bcell acell n
  [ -n "$root" ] && [ -d "$root" ] || return 0
  if [ "$mode" = gallery ]; then
    units="$(find "$root" -type f -name '*.png' 2>/dev/null | sort)"
  else
    units="$(find "$root" -mindepth 2 -type f -name '*.png' 2>/dev/null | sed 's#/[^/]*$##' | sort -u)"
  fi
  tmp="$root/.INDEX.md.$$"; n=0
  {
    if [ "$mode" = gallery ]; then
      printf '# SCREENS — what this product looks like now\n'
      printf '<!-- generated by `bash ops/polaris done` — never edit by hand; it is rewritten in place -->\n'
    else
      printf '# SHOTS — what this repo looked like, before and after\n'
      printf '<!-- generated by `bash ops/polaris shots` — never edit by hand; it is rewritten in place -->\n'
    fi
    while IFS= read -r unit; do
      [ -n "$unit" ] || continue
      n=$((n+1))
      rel="${unit#$root/}"
      slug="${rel%.png}"
      hname="$(printf '%s' "$slug" | sed -e 's#-# #g' -e 's#/# / #g')"   # a path is not a heading
      printf '\n## %s\n' "$hname"
      if [ "$mode" = gallery ]; then
        cap="${unit%.png}.md"
        if [ -f "$cap" ]; then
          printf '\n### %s\n' "$(head -1 "$cap" | sed -e 's/^#* *//' -e 's/\r$//')"
          awk 'NR==1{next} /^- screen: /{exit} NF==0&&!s{next} {s=1;print}' "$cap"
        else
          printf '\n(no caption recorded)\n\n'
        fi
        printf '![%s](%s)\n' "$hname" "$rel"
        continue
      fi
      rows=""
      while IFS= read -r cap; do
        [ -n "$cap" ] || continue
        rows="$rows$(stat -c %Y "$cap" 2>/dev/null || stat -f %m "$cap" 2>/dev/null || echo 0) $cap
"
      done <<EOF_CAPS
$(find "$unit" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
EOF_CAPS
      # newest first: the mtime leads each row, so the sort is numeric on ONE field and the path —
      caps="$(printf '%s' "$rows" | sort -s -k1,1nr | cut -d' ' -f2-)"   # spaces and all — follows
      if [ -z "$caps" ]; then
        # a screen whose task handed off without a caption is still SHOWN: dropping it would hide
        printf '\n(no caption recorded)\n\n'                             # what the reader came for
        while IFS= read -r img; do
          [ -n "$img" ] || continue
          printf '![%s](%s/%s)\n' "${img##*/}" "$rel" "${img##*/}"
        done <<EOF_IMGS
$(find "$unit" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)
EOF_IMGS
        continue
      fi
      while IFS= read -r cap; do
        [ -n "$cap" ] || continue
        printf '\n### %s\n' "$(head -1 "$cap" | sed -e 's/^#* *//' -e 's/\r$//')"
        awk 'NR==1{next} /^- screen: /{exit} NF==0&&!s{next} {s=1;print}' "$cap"
        # which picture is the BEFORE is the caption's answer — it recorded the clock order at
        bimg="$(sed -n 's/^- before: //p' "$cap" | head -1 | tr -d '\r')"   # handoff — never a
        aimg="$(sed -n 's/^- after: //p' "$cap" | head -1 | tr -d '\r')"    # filename's.
        acell="_(no after recorded)_"; if [ -n "$aimg" ]; then acell="![after]($rel/$aimg)"; fi
        bcell="_(no before recorded)_"
        case "$bimg" in '') ;; "("*) bcell="_${bimg}_" ;; *) bcell="![before]($rel/$bimg)" ;; esac
        printf '| before | after |\n| --- | --- |\n| %s | %s |\n' "$bcell" "$acell"
      done <<EOF_ONE
$caps
EOF_ONE
    done <<EOF_UNITS
$units
EOF_UNITS
    [ "$n" -gt 0 ] || printf '\n_(nothing captured yet)_\n'
  } > "$tmp" 2>/dev/null
  mv -f "$tmp" "$root/INDEX.md" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
}

visual_publish() { # visual_publish <ID> — the COMMITTED gallery (visual-check.md § v2.11). Per screen
  # the NEWEST capture and its caption are copied to <gallery>/<slug>.png|.md and replaced IN PLACE,
  # so the repo carries one picture per screen forever, not every picture ever taken. Called by
  # cmd_done INSIDE the mutex it ALREADY holds and NEVER behind the integration lease: cmd_done does not hold the
  # integration lease, and taking it here deadlocks the default `landing: self` path. Every write
  # lands on a temp name in the SAME directory and is renamed — a half-copied binary must never be
  # stageable. rc 0 = published, and the caller rides these paths on the commit it already makes.
  local id="${1:-}"
  local gal root out dir slug cap tmpf newest rows f b cid rest any
  gal="$(cfg gallery "")"
  case "$gal" in ''|/*|*..*|*\\*|[A-Za-z]:*) return 1 ;; esac   # visual_slug's refusals, reused
  root="$PRIMARY/.polaris/shots"; [ -d "$root" ] || return 1
  out="$PRIMARY/$gal"; any=0
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    slug="${dir#$root/}"
    rows=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -s "$f" ] || continue
      rows="$rows$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0) $f
"
    done <<EOF_NEW
$(find "$dir" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)
EOF_NEW
    newest="$(printf '%s' "$rows" | sort -s -k1,1n | tail -1 | cut -d' ' -f2-)"
    [ -n "$newest" ] || continue
    mkdir -p "$(dirname "$out/$slug")" 2>/dev/null || true
    tmpf="$out/$slug.png.$$.tmp"
    if cp "$newest" "$tmpf" 2>/dev/null; then mv -f "$tmpf" "$out/$slug.png" 2>/dev/null || rm -f "$tmpf" 2>/dev/null || true; fi
    # the caption BELONGING to that capture: its ID is the first two dash-separated fields
    b="${newest##*/}"; b="${b%.png}"          # (T-042-after-search -> T-042), falling back to the
    cid="${b%%-*}"; rest="${b#*-}"; cid="$cid-${rest%%-*}"    # task being done, which just wrote one
    cap="$dir/$cid.md"
    [ -f "$cap" ] || cap="$dir/$id.md"
    if [ -f "$cap" ]; then
      tmpf="$out/$slug.md.$$.tmp"
      if cp "$cap" "$tmpf" 2>/dev/null; then mv -f "$tmpf" "$out/$slug.md" 2>/dev/null || rm -f "$tmpf" 2>/dev/null || true; fi
    fi
    any=1
  done <<EOF_PUB
$(find "$root" -mindepth 2 -type f -name '*.png' 2>/dev/null | sed 's#/[^/]*$##' | sort -u)
EOF_PUB
  [ "$any" -eq 1 ] || return 1
  visual_index "$out" gallery
  return 0
}

cmd_shots() { # polaris shots — ONE bare arm (visual-check.md § v2.10): rebuild the index and say
  # where the pictures are. `index` is what this already does, `open` is useless to an agent, and
  # publishing happens by itself at `done` — so there is deliberately no subcommand.
  local root gal nscr nshot
  root="$PRIMARY/.polaris/shots"; mkdir -p "$root" 2>/dev/null || true
  visual_index "$root" shots
  nscr="$(find "$root" -mindepth 2 -type f -name '*.png' 2>/dev/null | sed 's#/[^/]*$##' | sort -u | wc -l | tr -d ' ')"
  nshot="$(find "$root" -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
  say "shots: ${nscr:-0} screens · ${nshot:-0} captures"
  note "index: ${root#$PRIMARY/}/INDEX.md — open it in VS Code's Markdown preview; the images render only there"
  gal="$(cfg gallery "")"
  if [ -n "$gal" ]; then
    note "gallery: $gal — one curated image per screen, republished on the commit \`done\` already makes"
  else
    note "gallery: (unset — nothing is committed; set gallery: <dir> in ops/CONVENTIONS.md to publish one image per screen)"
  fi
}
