# POLARIS lib/docs.sh — the kit serves its own documents (ops/contracts/doc-server.md § 1, § 4):
# `role <NAME>`, `doc <NAME> ["<section>"]`, `doc --where`, `router`, and kit_mode. Prose says
# `bash ops/polaris role BUILDER` instead of a path, so the same sentence works whether the kit is
# vendored in this repo or lives once per computer. Loaded ONLY for role|doc|router and doctor
# (module-layout v11). Everything here is read-only: no board write, no network, no git call.
#
# Paging: the harness inlines about 30,000 characters of a tool result and CONDUCTOR.md is larger,
# so a file past PAGE_MAX bytes is served in pages cut only at `## ` lines (outside fenced code),
# each page ending with the exact command for the next one. A file that fits is printed byte-identical.

PAGE_MAX=28000

kit_mode() { # kit_mode — `vendored` when this repo's ops/ IS the kit running, else `machine`
  local a b
  a="$(cd "$OPS" 2>/dev/null && pwd -P)" || a=""
  b="$(cd "$OPS_DIR" && pwd -P)"
  if [ -n "$a" ] && [ "$a" = "$b" ]; then echo vendored; else echo machine; fi
}

# _docs_page <file> <page|''> <verb> <label|''> [markers] — print <file> (or, with `markers`, only
# the lines strictly between <!-- POLARIS:BEGIN and <!-- POLARIS:END -->) whole when it fits, else
# page <page> of it with its footer. rc 1 + ⛔ on stderr when the page is out of range.
_docs_page() {
  local f="$1" want="${2:-1}" verb="$3" label="$4" mk=0 sz
  [ "${5:-}" = markers ] && mk=1
  if [ "$mk" = 0 ] && [ "$want" = 1 ]; then
    sz="$(wc -c < "$f" | tr -d ' ')"
    if [ "$sz" -le "$PAGE_MAX" ]; then cat "$f"; return 0; fi
  fi
  LC_ALL=C awk -v max="$PAGE_MAX" -v want="$want" -v verb="$verb" -v label="$label" -v mk="$mk" '
    mk && !on { if (index($0, "<!-- POLARIS:BEGIN") == 1) on = 1; next }
    mk && index($0, "<!-- POLARIS:END -->") == 1 { exit }
    { line[++L] = $0 }
    END {
      ns = 1; first[1] = 1; fence = 0; total = 0
      for (i = 1; i <= L; i++) {
        s = line[i]
        if (s ~ /^ ? ? ?(```|~~~)/) fence = !fence
        else if (!fence && i > 1 && substr(s, 1, 3) == "## ") { ns++; first[ns] = i }
        sz[ns] += length(s) + 1; total += length(s) + 1
      }
      first[ns + 1] = L + 1
      np = 1; psz = 0; ps[1] = 1
      for (k = 1; k <= ns; k++) {
        if (psz > 0 && psz + sz[k] > max) { np++; ps[np] = k; psz = 0 }
        psz += sz[k]
      }
      if (total <= max) np = 1
      ps[np + 1] = ns + 1
      if (want < 1 || want > np) {
        printf "⛔ %s: %s has %d page(s)\n", verb, (label == "" ? "CLAUDE.md" : label), np > "/dev/stderr"
        exit 1
      }
      for (i = first[ps[want]]; i < first[ps[want + 1]]; i++) print line[i]
      if (np == 1) exit 0
      cmd = "bash ops/polaris " verb (label == "" ? "" : " " label)
      if (want < np) printf "— page %d of %d · next: %s --page %d\n", want, np, cmd, want + 1
      else printf "— page %d of %d (end)\n", np, np
    }' "$f"
}

# _docs_pageopt <verb> <value> — validate a --page value; dies on anything but a positive integer
_docs_pageopt() {
  case "$2" in ''|*[!0-9]*|0) die "$1: --page takes a page number (1, 2, …)";; esac
}

cmd_role() { # role <NAME> [--page <n>] — serve kit_file roles/<NAME>.md, NAME case-insensitive
  local name="" page="" up f d list=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --page) _docs_pageopt role "${2:-}"; page="$2"; shift 2;;
      --page=*) _docs_pageopt role "${1#--page=}"; page="${1#--page=}"; shift;;
      *) [ -z "$name" ] && name="$1" || die "role: one role at a time — role <NAME> [--page <n>]"; shift;;
    esac
  done
  up="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  case "$up" in ''|*/*|*.*) f="";; *) f="$(kit_file "roles/$up.md")";; esac
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    for d in "$OPS/roles" "$OPS_DIR/roles"; do
      [ -d "$d" ] && for f in "$d"/*.md; do [ -f "$f" ] && list="$list${f##*/}
"; done
    done
    list="$(printf '%s' "$list" | sed 's/\.md$//' | LC_ALL=C sort -u | awk '{ printf "%s%s", (NR > 1 ? " · " : ""), $0 }')"
    die "role: no role ${name:-<NAME>} — roles: $list"
  fi
  _docs_page "$f" "$page" role "$up"
}

cmd_doc() { # doc <NAME> ["<section>"] [--page <n>] | doc --where — serve one kit document
  local name="" sec="" havesec="" page="" rel f
  while [ $# -gt 0 ]; do
    case "$1" in
      --where) printf 'kit: %s\nmode: %s\n' "$OPS_DIR" "$(kit_mode)"; return 0;;
      --page) _docs_pageopt doc "${2:-}"; page="$2"; shift 2;;
      --page=*) _docs_pageopt doc "${1#--page=}"; page="${1#--page=}"; shift;;
      *) if [ -z "$name" ]; then name="$1"; elif [ -z "$havesec" ]; then sec="$1"; havesec=1
         else die "doc: too many words — doc <NAME> [\"<section>\"] [--page <n>]"; fi; shift;;
    esac
  done
  case "$name" in
    PROTOCOL|MANUAL|PROMPTS|VISUAL|protocol|manual|prompts|visual|Protocol|Manual|Prompts|Visual)
      rel="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]').md";;
    PROTOCOL.md|MANUAL.md|PROMPTS.md|VISUAL.md|KEYS.tsv) rel="$name";;
    KEYS|keys|Keys) rel=KEYS.tsv;;
    *..*|/*) rel="";;
    roles/?*) rel="roles/$(printf '%s' "${name#roles/}" | tr '[:lower:]' '[:upper:]')"; case "$rel" in *.MD) rel="${rel%.MD}";; esac; rel="$rel.md";;
    templates/?*) rel="$name"; case "${rel##*/}" in *.*) ;; *) rel="$rel.md";; esac;;
    *) rel="";;
  esac
  [ -n "$rel" ] && f="$(kit_file "$rel")" || f=""
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    die "doc: no kit document ${name:-<NAME>} — documents: MANUAL · PROMPTS · PROTOCOL · VISUAL · KEYS · templates/<T> · roles/<R>"
  fi
  if [ -n "$sec" ]; then
    # the first heading (outside fenced code) holding <section>, through the line before the next
    # heading of the same or a higher level — printed whole, never paged
    DOC_SEC="$sec" awk '
      BEGIN { want = tolower(ENVIRON["DOC_SEC"]) }
      { s = $0; sub(/\r$/, "", s) }
      s ~ /^ ? ? ?(```|~~~)/ { fence = !fence; if (on) print; next }
      !fence && match(s, /^#+ /) && RLENGTH <= 7 {
        lvl = RLENGTH - 1
        if (on && lvl <= top) exit
        if (!on && index(tolower(substr(s, RLENGTH + 1)), want)) { on = 1; top = lvl }
      }
      on { print }
      END { exit (on ? 0 : 3) }' "$f" && return 0
    die "doc: no section \"$sec\" in $rel — whole file: bash ops/polaris doc $name"
  fi
  _docs_page "$f" "$page" doc "$name"
}

cmd_router() { # router [--page <n>] — the kit's protocol text (its CLAUDE.md, between the markers)
  local page="" f="$OPS_DIR/../CLAUDE.md"
  while [ $# -gt 0 ]; do
    case "$1" in
      --page) _docs_pageopt router "${2:-}"; page="$2"; shift 2;;
      --page=*) _docs_pageopt router "${1#--page=}"; page="${1#--page=}"; shift;;
      *) die "router: takes no name — router [--page <n>]";;
    esac
  done
  [ -f "$f" ] || die "router: no CLAUDE.md beside this kit ($f)"
  if grep -q '^<!-- POLARIS:BEGIN' "$f" 2>/dev/null; then _docs_page "$f" "$page" router "" markers
  else _docs_page "$f" "$page" router ""; fi
}
