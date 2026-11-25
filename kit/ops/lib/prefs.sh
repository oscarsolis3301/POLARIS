# POLARIS lib/prefs.sh — `polaris prefs`: your preferences, once per computer
# (ops/contracts/machine-prefs.md § 7). One file per computer ($POLARIS_HOME/preferences, or
# POLARIS_PREFS; set-but-empty = the layer is off) sits UNDER every repo's ops/CONVENTIONS.md:
#   prefs                       every key: the value that wins here, where it came from, its scope
#   prefs --set <k>=<v> …       write keys into the machine file — all-or-nothing, person keys only
#   prefs --unset <k> …         take keys out of it
#   prefs --seed                owner command: create it from this repo's lines, once per computer
#   prefs --yield               owner command: comment out this repo's lines that equal it
# No agent ever sets the autonomy dial: under CLAUDECODE=1 the four dial keys are refused, skipped,
# or (for --yield) the whole command is. Loaded ONLY for `prefs` and doctor (module-layout v11).

PREFS_DIAL=" autonomy plan_gate builder_questions evolve_apply "

_prefs_path() { printf '%s' "${POLARIS_PREFS-$POLARIS_HOME/preferences}"; }
_prefs_dial() { case "$PREFS_DIAL" in *" $1 "*) return 0;; esac; return 1; }
_prefs_agent() { [ "${CLAUDECODE:-}" = 1 ]; }
_prefs_dial_refuse() { # _prefs_dial_refuse <key> <the command's tail for a person to run>
  die "prefs: $1 is the autonomy dial — no agent may set the dial; set it yourself from a terminal outside Claude Code: bash ops/polaris prefs $2"
}
_prefs_off_refuse() { [ -n "$(_prefs_path)" ] || die "prefs: the machine layer is off (POLARIS_PREFS is empty) — nothing written"; }

# The value reader every awk below shares — cfg's val(), byte for byte (core.sh).
_PREFS_VAL='function val(s) { sub(/\r$/,"",s); sub(/^[ \t]*/,"",s); if (s ~ /^#/) return ""
                      sub(/[ \t]#.*$/,"",s); sub(/[ \t]*$/,"",s); return s }'

_prefs_show() { # ONE awk over KEYS.tsv + CONVENTIONS + the machine file — never a fork per key
  local keys m c="" mf="" last
  keys="$(kit_file KEYS.tsv)"; m="$(_prefs_path)"
  [ -f "$CONV" ] && c="$CONV"
  if [ -z "$m" ]; then last="machine file: off (POLARIS_PREFS is empty)"
  elif [ -f "$m" ]; then mf="$m"; last="machine file: $m"
  else last="machine file: none — bash ops/polaris prefs --seed creates it from this repo"; fi
  [ -f "$keys" ] || die "prefs: no KEYS.tsv in this kit ($keys)"
  awk -v hc="${c:+1}" -v hm="${mf:+1}" "$_PREFS_VAL"'
    BEGIN { FS = "\t"; cf = hc ? ARGV[2] : ""; mfn = hm ? ARGV[ARGC-1] : ""
            trio = " plan_gate builder_questions evolve_apply " }
    FILENAME == ARGV[1] { sub(/\r$/, "")
      if ($0 ~ /^#/ || $0 ~ /^[ \t]*$/) next
      n++; K[n] = $1; D[$1] = $3; S[$1] = (NF >= 6 && $6 != "") ? $6 : "repo"; next }
    { line = $0; c = index(line, ":"); if (c < 2) next; k = substr(line, 1, c - 1)
      if (k ~ /[^A-Za-z0-9_]/) next; v = val(substr(line, c + 1)) }
    mfn != "" && FILENAME == mfn { if (!(k in M) && v != "") M[k] = v; next }
    cf != "" && FILENAME == cf {
      if (k == "autonomy" && v != "") mask = 1
      if (!(k in R)) R[k] = v
      next }
    END {
      print "key\tvalue\tsource\tscope"
      for (i = 1; i <= n; i++) {
        k = K[i]
        if (R[k] != "") { val_ = R[k]; src = "repo" }
        else if (S[k] == "machine" && M[k] != "" && !(mask && index(trio, " " k " "))) { val_ = M[k]; src = "machine" }
        else { val_ = D[k]; src = "default"; if (val_ == "" || val_ ~ /^</) val_ = "-" }
        print k "\t" val_ "\t" src "\t" S[k]
      }
    }' "$keys" ${c:+"$c"} ${mf:+"$mf"}
  printf '%s\n' "$last"
}

_prefs_row() { # _prefs_row <key> — two lines: the key's scope (empty = no such key), its ask values
  awk -F'\t' -v k="$1" '{ sub(/\r$/, "") } !/^#/ && $1 == k {
    o = ""; n = split($5, a, "|")
    for (i = 2; i <= n; i++) { v = a[i]; sub(/^.*=/, "", v); o = o (o == "" ? "" : " | ") v }
    print ((NF >= 6 && $6 != "") ? $6 : "repo"); print o; f = 1; exit }
    END { if (!f) { print ""; print "" } }' "$(kit_file KEYS.tsv)"
}

_prefs_set() { # --set <k>=<v> … — every pair validated before any write
  local pair k v sc opts scope kind pat msg todo=""
  _prefs_off_refuse
  [ $# -gt 0 ] || die "prefs: --set takes <key>=<value> [<key>=<value> …]"
  for pair in "$@"; do
    case "$pair" in *=*) ;; *) die "prefs: --set takes <key>=<value>, not '$pair'";; esac
    k="${pair%%=*}"; v="${pair#*=}"
    { read -r sc || sc=""; read -r opts || opts=""; } <<EOF
$(_prefs_row "$k")
EOF
    [ -n "$sc" ] || die "prefs: $k is not a key POLARIS reads — the list: bash ops/polaris doc KEYS"
    [ "$sc" = repo ] && die "prefs: $k is per-project — set it in ops/CONVENTIONS.md"
    case "$v" in *"$POLARIS_TAB"*|*'#'*|*'
'*) die "prefs: $k: a value cannot hold a tab, a line break or '#'";; esac
    [ -n "$v" ] || die "prefs: $k needs a value — to clear it: bash ops/polaris prefs --unset $k"
    if [ -n "$opts" ]; then
      case " | $opts | " in *" | $v | "*) ;; *) die "prefs: $k takes $opts, not '$v'";; esac
    fi
    # the job runner may be Haiku (walk-away § 3.4, _model_runner_ok); its RULES line still binds
    case "$k" in model_runner) ;; model_*) model_denied "$v" && die "prefs: $k: '$v' is a forbidden model — POLARIS never selects Fable or Haiku (core.sh model_denied)";; esac
    while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
      [ "$kind" = content ] && [ -n "$pat" ] && [ "$pat" != - ] || continue
      owned_match ops/CONVENTIONS.md "$scope" || continue
      printf '%s: %s\n' "$k" "$v" | grep -Eq -e "$pat" 2>/dev/null && die "prefs: $k: $msg"
    done <<EOF
$(rules_lines)
EOF
    _prefs_agent && _prefs_dial "$k" && _prefs_dial_refuse "$k" "--set $k=$v"
    todo="$todo$k=$v
"
  done
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    k="${pair%%=*}"; v="${pair#*=}"
    prefs_put "$k" "$v" || die "prefs: could not write $k into $(_prefs_path)"
    say "prefs: $k = $v (every project on this computer, unless its ops/CONVENTIONS.md says otherwise)"
  done <<EOF
$todo
EOF
}

_prefs_unset() { # --unset <k> … — remove each key's live line(s); temp file + mv
  local k m tmp
  _prefs_off_refuse
  [ $# -gt 0 ] || die "prefs: --unset takes <key> [<key> …]"
  if _prefs_agent; then for k in "$@"; do _prefs_dial "$k" && _prefs_dial_refuse "$k" "--unset $k"; done; fi
  m="$(_prefs_path)"
  for k in "$@"; do
    if [ ! -f "$m" ] || ! awk -v k="$k" 'index($0, k":") == 1 { f = 1; exit } END { exit !f }' "$m"; then
      note "prefs: $k was not set here"; continue
    fi
    tmp="$m.polaris-tmp.$$"
    if awk -v k="$k" 'index($0, k":") != 1' "$m" > "$tmp" && mv -f "$tmp" "$m"; then
      say "prefs: $k unset on this computer — each project's ops/CONVENTIONS.md line, else the default"
    else rm -f "$tmp"; die "prefs: could not rewrite $m"; fi
  done
}

_prefs_owners() { # the `origin` owners of the registered projects, comma-joined, first seen first
  # (shared-kit.md § 9). Owner = the url's path segment before the repo name, for both
  # https://host/<owner>/<repo>(.git) and git@host:<owner>/<repo>(.git). The registry is
  # $POLARIS_HOME/awake/repos/* (POLARIS_AWAKE_HOME is the drills' seam), one project path per file.
  local reg="${POLARIS_AWAKE_HOME:-$POLARIS_HOME/awake}/repos" f p u o list=","
  for f in "$reg"/*; do
    [ -f "$f" ] || continue
    p=""; { read -r p < "$f" || :; } 2>/dev/null; p="${p%$'\r'}"
    [ -n "$p" ] && [ -d "$p" ] || continue
    u="$(git -C "$p" config --get remote.origin.url 2>/dev/null)" || continue
    u="${u%$'\r'}"; u="${u%/}"; u="${u%.git}"; u="${u//:/\/}"
    case "$u" in */*/*) ;; *) continue;; esac
    o="${u%/*}"; o="${o##*/}"
    case "$o" in ''|*[!A-Za-z0-9._-]*) continue;; esac
    case "$list" in *",$o,"*) ;; *) list="$list$o,";; esac
  done
  list="${list#,}"; printf '%s' "${list%,}"
}

_prefs_seed() { # --seed — create the machine file from this repo's machine/seed lines; `owners:` from
  # the registered projects' origins when the repo's lines left it unset (shared-kit.md § 9)
  local m k v n=0 skipped="" own=""
  _prefs_off_refuse
  m="$(_prefs_path)"
  [ -e "$m" ] && die "prefs: $m exists — --seed only creates it; change one key with --set"
  [ -f "$CONV" ] || die "prefs: no ops/CONVENTIONS.md here to seed from"
  while IFS="$POLARIS_TAB" read -r k v; do
    [ -n "$k" ] || continue
    if _prefs_agent && _prefs_dial "$k"; then skipped="$skipped${skipped:+ · }$k"; continue; fi
    prefs_put "$k" "$v" || die "prefs: could not write $k into $m"
    n=$((n + 1)); [ "$k" = owners ] && own=1
  done <<EOF
$(awk "$_PREFS_VAL"'
  FILENAME == ARGV[1] { sub(/\r$/, ""); if ($0 ~ /^#/) next
    n = split($0, f, "\t"); if (n >= 6 && (f[6] == "machine" || f[6] == "seed")) { O[++c] = f[1]; E[f[1]] = 1 }; next }
  { p = index($0, ":"); if (p < 2) next; k = substr($0, 1, p - 1)
    if ((k in E) && !(k in R)) R[k] = val(substr($0, p + 1)) }
  END { for (i = 1; i <= c; i++) if (R[O[i]] != "") print O[i] "\t" R[O[i]] }' "$(kit_file KEYS.tsv)" "$CONV")
EOF
  # prefs_put refuses a key KEYS.tsv has no machine row for, so a kit without `owners` writes nothing
  if [ -z "$own" ]; then
    v="$(_prefs_owners)"
    [ -n "$v" ] && prefs_put owners "$v" && n=$((n + 1))
  fi
  [ -n "$skipped" ] && note "prefs: skipped the autonomy dial ($skipped) — no agent may set it; set it yourself from a terminal outside Claude Code"
  say "prefs: seeded $n key(s) into $m"
}

_prefs_yield() { # --yield — comment out this repo's machine-scope lines equal to the machine file's
  local m tmp rep
  _prefs_agent && die "prefs: --yield is an owner command — run it yourself from a terminal outside Claude Code"
  _prefs_off_refuse
  m="$(_prefs_path)"
  [ -f "$m" ] || die "prefs: no machine file at $m — bash ops/polaris prefs --seed creates it from this repo"
  [ -f "$CONV" ] || die "prefs: no ops/CONVENTIONS.md here"
  tmp="$CONV.polaris-tmp.$$"; rep="$tmp.report"
  PREFS_REP="$rep" awk -v dial="$PREFS_DIAL" "$_PREFS_VAL"'
    FILENAME == ARGV[1] { sub(/\r$/, ""); if ($0 ~ /^#/) next
      n = split($0, f, "\t"); if (n >= 6 && f[6] == "machine" && !index(dial, " " f[1] " ")) E[f[1]] = 1; next }
    { p = index($0, ":"); k = (p > 1) ? substr($0, 1, p - 1) : ""; v = (k != "") ? val(substr($0, p + 1)) : "" }
    FILENAME == ARGV[2] { if ((k in E) && !(k in M) && v != "") M[k] = v; next }
    (k in E) && !(k in seen) { seen[k] = 1
      if (v != "" && (k in M)) {
        if (v == M[k]) { print "# " $0; Y = Y (Y == "" ? "" : " · ") k; next }
        D = D "differs: " k " (here " v " · machine " M[k] ")\n" } }
    { print }
    END { r = ENVIRON["PREFS_REP"]; printf "%s\n%s", Y, D > r }' "$(kit_file KEYS.tsv)" "$m" "$CONV" > "$tmp" \
    || { rm -f "$tmp" "$rep"; die "prefs: could not read $CONV"; }
  if [ -n "$(head -1 "$rep")" ]; then
    mv -f "$tmp" "$CONV" || { rm -f "$tmp" "$rep"; die "prefs: could not rewrite $CONV"; }
    printf 'yielded: %s\n' "$(head -1 "$rep")"
  else rm -f "$tmp"; note "prefs: nothing to yield"; fi
  sed '1d' "$rep"; rm -f "$rep"
}

cmd_prefs() { # prefs [--set <k>=<v>… | --unset <k>… | --seed | --yield] — machine-prefs.md § 7
  case "${1:-}" in
    '')      _prefs_show;;
    --set)   shift; _prefs_set "$@";;
    --unset) shift; _prefs_unset "$@";;
    --seed)  _prefs_seed;;
    --yield) _prefs_yield;;
    *) die "prefs: unknown form '$1' — prefs [--set <key>=<value>… | --unset <key>… | --seed | --yield]";;
  esac
}
