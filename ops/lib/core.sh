# POLARIS lib/core.sh — shared plumbing sourced by ops/polaris (the lib loader): die/say, cfg,
# telemetry, frontmatter parsing, board mutex/commit/sync, locks, worktree helpers.

die() { printf '⛔ %s\n' "$*" >&2; exit 1; }
say() { printf '✅ %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

cfg() { # cfg <key> <default>  — reads "key: value" from CONVENTIONS.md, strips " # comment".
  # ONE awk, never a pipeline. The old shape was sed|head|sed|tr|sed — five forks per call, and on
  # Windows/Git Bash a fork costs ~240ms, so every cfg read took ~1.2s. The globals block calls cfg
  # 4+ times on EVERY polaris invocation, and the PreToolUse write-guard invokes polaris TWICE per
  # edit: that alone was ~8s per write against a 10s hook timeout, i.e. the guard was on the edge of
  # failing OPEN and silently dropping the ownership gate. One fork instead of five fixes it.
  # Semantics are byte-identical to the pipeline, including the two edge cases it existed for:
  #   - first match wins  (was `head -1`, now `exit`)
  #   - a blank key carrying only a trailing comment ("lint:   # none") reads EMPTY, not the comment
  #     text (was the leading `s/^#.*$//`, now the `s ~ /^#/` test after left-trimming)
  local v=""
  [ -f "$CONV" ] && v="$(awk -v k="$1" '
    index($0, k":")==1 {
      s=substr($0, length(k)+2)
      sub(/\r$/,"",s); sub(/^[ \t]*/,"",s)
      if (s ~ /^#/) s=""; else sub(/[ \t]#.*$/,"",s)
      sub(/[ \t]*$/,"",s)
      print s; exit
    }' "$CONV")"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}

cfg_boot() { # the three keys the globals block needs, in ONE awk pass — emits shell assignments.
  # Traced 2026-07-25 (Windows/Git Bash): `cfg base` 683ms + `cfg claim` 95ms + `cfg stale_hours`
  # 67ms = 845ms paid by EVERY polaris invocation, including the write-guard on every edit. cfg is
  # already one fork per call (see above); this is one fork for all three. Same first-match-wins and
  # blank-key-with-comment semantics as cfg, so the values are byte-identical to three cfg calls.
  # Values are single-quoted for eval and any embedded quote is stripped: CONVENTIONS.md is repo
  # data, and repo data must never be able to inject shell into the startup path.
  if [ ! -f "$CONV" ]; then
    printf "BASE='main'; CLAIM_MODE='local-lock'; STALE_H='4'\n"; return
  fi
  awk '
    function val(s) {
      sub(/\r$/, "", s); sub(/^[ \t]*/, "", s)
      if (s ~ /^#/) return ""
      sub(/[ \t]#.*$/, "", s); sub(/[ \t]*$/, "", s)
      gsub(/'\''/, "", s)
      return s
    }
    index($0, "base:")        == 1 && b == "" { b = val(substr($0, 6))  }
    index($0, "claim:")       == 1 && c == "" { c = val(substr($0, 7))  }
    index($0, "stale_hours:") == 1 && s == "" { s = val(substr($0, 13)) }
    END {
      printf "BASE='\''%s'\''; CLAIM_MODE='\''%s'\''; STALE_H='\''%s'\''\n",
             (b == "" ? "main" : b), (c == "" ? "local-lock" : c), (s == "" ? "4" : s)
    }
  ' "$CONV"
}

who() { # memoize the actor id — `hostname` costs ~524ms on Windows/Git Bash.
  # It used to be computed eagerly in the globals block, so every `find`, every `check` and every
  # write-guard invocation paid half a second for a string only the MUTATION paths ever read
  # (evt, lock_take, claim_branch, set_fm owner, the release note). Call who() before using $WHO.
  [ -n "${WHO:-}" ] || WHO="${USER:-${USERNAME:-unknown}}@$(hostname 2>/dev/null || echo host)"
}

# ------------------------------------------------------------- model routing
tier_for() { # tier_for <points> <risk> — echo exactly ONE tier word (ops/contracts/model-routing.md):
  # risk ≠ normal → strong (risk dominates points) · points ≥5 → strong · ≤1 → cheap · else mid.
  # Empty or non-numeric points → mid, NEVER an error — callers pass frontmatter as-is. Pure bash,
  # zero forks: core.sh rides the write-guard's hot path.
  local p="${1:-}" r="${2:-normal}"
  [ "$r" = "normal" ] || { printf 'strong'; return 0; }
  case "$p" in ''|*[!0-9]*) printf 'mid'; return 0;; esac
  if [ "$p" -ge 5 ]; then printf 'strong'
  elif [ "$p" -le 1 ]; then printf 'cheap'
  else printf 'mid'; fi
  return 0
}
model_denied() { # model_denied <name> — rc 0 when <name> is a FORBIDDEN model.
  # OWNER DECISION 2026-09-15, absolute: POLARIS never selects Fable or Haiku, in any repo, on any
  # machine. Fable bills against a SEPARATE and much smaller weekly limit — one day of routing
  # `strong` to it took that limit to 87% on work the owner never asked to run there. Haiku was
  # already refused for this repo's bash/board work (owner, 2026-08-02) and was simply never enforced.
  # This list is a KIT CONSTANT on purpose: no CONVENTIONS key reads it, so no repo can widen, weaken
  # or switch it off, and updating the kit on ANY machine carries the ban with it. That is the whole
  # point — a knob would have drifted back exactly like the prose that caused this.
  # Substring, with the realistic capitalisations spelled out rather than lowercasing: matching costs
  # ZERO forks and core.sh rides the write-guard's hot path. Catches claude-fable-5, claude-fable-5-1,
  # claude-haiku-4-5-20251001 and whatever either family is named next.
  case "${1:-}" in
    '') return 1;;
    *fable*|*Fable*|*FABLE*|*haiku*|*Haiku*|*HAIKU*) return 0;;
  esac
  return 1
}
model_for_tier() { # model_for_tier <tier> — the matching CONVENTIONS knob's value (model_strong: /
  # model_mid: / model_cheap:), or nothing when unset. cfg already strips the knobs' trailing `#`
  # owner comments. Unknown tier → nothing: an unset mapping must change NOTHING downstream.
  # A FORBIDDEN value (model_denied) is NEVER returned: MODEL_DENIED carries the refused name so
  # cmd_route can say why, and the empty result is not a new code path — the contract already defines
  # absent → the caller omits the spawn's model param and the platform default runs. So a repo still
  # naming fable/haiku degrades to exactly "unset", loudly, instead of spending the owner's quota.
  local m=""
  MODEL_DENIED=""
  case "${1:-}" in
    strong) m="$(cfg model_strong "")";;
    mid)    m="$(cfg model_mid "")";;
    cheap)  m="$(cfg model_cheap "")";;
  esac
  if model_denied "$m"; then MODEL_DENIED="$m"; return 0; fi
  printf '%s' "$m"
  return 0
}

# ------------------------------------------------------------------ telemetry
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r'; }
evt() { # evt <ev> <id> [note] [pts] — append one ndjson line. Call INSIDE the board
  # mutex, BEFORE board_commit, so the line rides the same board commit.
  # EVENTS.ndjson is append-only and union-merged (.gitattributes) so parallel
  # machines never conflict on it. Never edit it by hand.
  # v5: claim/done lines carry "pts" so `metrics` can calibrate per point bucket.
  local pts="${4:-}"; case "$pts" in ''|*[!0-9.]*) pts="";; esac
  who
  local ts; ts="$(date +%s)"
  printf '{"ts":%s,"ev":"%s","id":"%s","who":"%s","note":"%s"%s}\n' \
    "$ts" "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$WHO")" "$(jesc "${3:-}")" \
    "${pts:+,\"pts\":$pts}" >> "$EVENTS"
  # session state (ops/contracts/role-handover.md § session state): the handover hook and
  # `polaris next` read .polaris/handover/<sid>/last-event to decide whether this session's turn
  # should hop into the next role, and `avoid` to stop it re-taking what it just put down. Per
  # checkout, gitignored, never the board. Every line best-effort — telemetry that cannot be
  # written must never fail a board mutation. No session id (a plain shell, CI) ⇒ nothing written.
  local hs
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    hs="$PRIMARY/.polaris/handover/$CLAUDE_CODE_SESSION_ID"
    mkdir -p "$hs" 2>/dev/null || true
    printf '%s %s %s\n' "$ts" "$1" "$2" > "$hs/last-event" 2>/dev/null || true
    [ -e "$hs/started" ] || printf '%s\n' "$ts" > "$hs/started" 2>/dev/null || true
    case "$1" in
      release|blocked|kickback) printf '%s\n' "$2" >> "$hs/avoid" 2>/dev/null || true;;
    esac
  fi
  # optional notify hook: CONVENTIONS `notify: <cmd>` — background, output discarded,
  # failures ignored. It observes the board; it must never be able to stall or fail it.
  # v2 (ops/contracts/hands-free-knobs.md): POLARIS_SEVERITY rides along — ev "blocked"
  # means the run waits on a human (gate); every other board event is FYI (info).
  local sev="info"; [ "$1" = "blocked" ] && sev="gate"
  notify_fire "$1" "$2" "${3:-}" "$sev"
  return 0
}
notify_fire() { # notify_fire <ev> <id> <note> <severity> — invoke the CONVENTIONS `notify: <cmd>`
  # hook: background subshell, output discarded, failures ignored, rc 0 always. Shared by evt()
  # and cmd_notify_gate so the shim invokes the hook EXACTLY as board events do. Pure observation:
  # writes nothing, takes no lock, can never stall a run. No notify: configured → silent no-op.
  local ncmd; ncmd="$(cfg notify "")"
  [ -n "$ncmd" ] && ( POLARIS_EV="$1" POLARIS_ID="$2" POLARIS_NOTE="$3" POLARIS_SEVERITY="$4" \
      bash -c "$ncmd" ) >/dev/null 2>&1 &
  return 0
}
# RULES.tsv is TAB-separated and every reader loops it with `while IFS="$TAB" read ...`. Written
# inline as `IFS="$(printf '\t')"` that substitution sits in the WHILE CONDITION, so it re-forks
# ONCE PER RULE LINE — 42 rules ≈ 42 forks ≈ 1s, on the write-guard's path, on every single edit.
# Resolve it once per process instead.
POLARIS_TAB="$(printf '\t')"

_RULES_CACHE=""
_RULES_CACHED=""
# ops/SURFACES.tsv (ops/contracts/test-surfaces.md) memoizes the same way, on its OWN pair: the
# startup-budget golden counts the RULES sentinel's lines and must keep finding exactly three.
_SURFACES_CACHE=""
_SURFACES_CACHED=""
rules_lines() { # normalized RULES.tsv: comments/blank/CR stripped. Memoized: check_rules alone
  # called this 4x (each 3 forks), and RULES.tsv cannot change mid-process.
  if [ -z "$_RULES_CACHED" ]; then
    _RULES_CACHED=1
    if [ -f "$RULES" ]; then
      _RULES_CACHE="$(tr -d '\r' < "$RULES" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' || true)"
    fi
  fi
  [ -n "$_RULES_CACHE" ] && printf '%s\n' "$_RULES_CACHE"
  return 0
}

# ------------------------------------------------ surfaces: which tests cover which source paths
# ops/SURFACES.tsv is repo data like RULES.tsv — surface<TAB>tests<TAB>cmd<TAB>note, one row per
# (surface, tests) pair (ops/contracts/test-surfaces.md § 1). Two readers share it: the stale-tests
# gate (a mapped surface changed, its tests did not) and change-scoped selection (run only what a
# change can break). Everything below is pure enough for the fast tier — no polaris re-invocation;
# surface_change_set alone runs git. Rows are written ONLY by `polaris done` from a task's
# `surface:` list; nothing here writes a row.
surfaces_lines() { # normalized SURFACES.tsv: comments/blank/CR stripped. Absent file → prints
  # nothing, rc 0. Memoized per process; reset with _SURFACES_CACHED="" ALONE between fixtures —
  # the reload clears the text too, so a reset that lands on an absent file replays nothing stale.
  if [ -z "$_SURFACES_CACHED" ]; then
    _SURFACES_CACHED=1; _SURFACES_CACHE=""
    if [ -f "${SURFACES:-}" ]; then
      _SURFACES_CACHE="$(tr -d '\r' < "$SURFACES" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' || true)"
    fi
  fi
  [ -n "$_SURFACES_CACHE" ] && printf '%s\n' "$_SURFACES_CACHE"
  return 0
}
surfaces_seed() { # surfaces_seed [<path>] — write the header iff <path> (default $SURFACES) does
  # not exist; rc 0 always, never rewrites an existing file. init-board seeds fresh repos, `done`
  # seeds before its first row. Comment lines only: a header-only file is zero rows everywhere.
  local f="${1:-${SURFACES:-}}"
  [ -n "$f" ] && [ ! -f "$f" ] || return 0
  { cat <<'SRF'
# POLARIS SURFACES — which tests cover which source paths, as data. TAB-separated:
#   surface<TAB>tests<TAB>cmd<TAB>note
#   surface  glob of source paths, files_owned semantics: exact path · dir/ prefix · glob
#   tests    glob of the test paths covering that surface — a changed surface must change these too
#   cmd      the COMPLETE shell command that exercises just this surface (repo root), or `-` =
#            derive from ops/CONVENTIONS.md test_select: ({tests} becomes this row's tests glob)
#   note     plain English: what this surface is [the task that mapped it]
# Read at verify/handoff/audit/land (the stale-tests gate) and by qa / land --express (which tests a
# change can break). Written ONLY by `polaris done`, from a task's `surface:` list — never by hand: a
# row you could delete when it blocked you would guard nothing. Health: ops/polaris surfaces
SRF
  } > "$f" 2>/dev/null || true
  return 0
}
surface_row_matches() { # surface_row_matches <path> <row> — rc 0 when the row's column 1 (a
  # files_owned-style pattern: exact · dir/ prefix · glob) matches <path>. Column 1 by expansion,
  # match_one with ARGS — no pipe, no fork: this runs per (changed path × row) inside the gates.
  local s="${2:-}"; s="${s%%$POLARIS_TAB*}"
  [ -n "$s" ] || return 1
  match_one "$1" "$s"
}
surface_rows_for() { # surface_rows_for <path> — every row (whole TSV line) whose surface matches
  # <path>, in file order; rc 0 when ≥1, else rc 1 and prints nothing.
  local p="${1:-}" row hit=1
  while IFS= read -r row; do
    surface_row_matches "$p" "$row" || continue
    printf '%s\n' "$row"; hit=0
  done <<EOF
$(surfaces_lines)
EOF
  return $hit
}
surface_row_from_item() { # surface_row_from_item <item> <ID> <title> — one `surface:` frontmatter
  # item (ops/contracts/test-surfaces.md § 3) → ONE TSV row on stdout, rc 0:
  #   <surface> tests: <glob> [cmd: <complete command | ->] [note: <plain English>]
  # first token = the surface · `tests:` required, ONE token · `cmd:` = everything up to ` note:`
  # or the end, empty → `-` · `note:` = the rest, absent → the task's title (quotes stripped). The
  # row's note carries the task: `<note> [<ID>]`. Malformed → rc 1 + ONE reason line on stdout:
  # `needs 'tests: <glob>'` · `empty surface` · `a TAB in the item` · `surface or tests glob is
  # not one token`. Builtins only — drift runs this per ready task, `done` per item.
  local item="${1:-}" id="${2:-}" title="${3:-}" surface="" rest="" tests="" cmd="" note=""
  case "$item" in *"$POLARIS_TAB"*) printf 'a TAB in the item\n'; return 1;; esac
  read -r surface rest <<EOF
$item
EOF
  case "$surface" in ''|tests:|cmd:|note:) printf 'empty surface\n'; return 1;; esac
  case "$rest" in
    'tests: '*)   rest="${rest#tests: }";;
    *' tests: '*) printf 'surface or tests glob is not one token\n'; return 1;;
    *)            printf "needs 'tests: <glob>'\n"; return 1;;
  esac
  read -r tests rest <<EOF
$rest
EOF
  case "$tests" in ''|cmd:|note:) printf "needs 'tests: <glob>'\n"; return 1;; esac
  case "$rest" in
    '') ;;
    cmd:*)  rest="${rest#cmd:}"
            case "$rest" in
              *' note:'*) cmd="${rest%% note:*}"; note="${rest#* note:}";;
              *)          cmd="$rest";;
            esac;;
    note:*) note="${rest#note:}";;
    *)      printf 'surface or tests glob is not one token\n'; return 1;;
  esac
  cmd="${cmd#"${cmd%%[! ]*}"}";   cmd="${cmd%"${cmd##*[! ]}"}"
  note="${note#"${note%%[! ]*}"}"; note="${note%"${note##*[! ]}"}"
  [ -n "$cmd" ] || cmd="-"
  if [ -z "$note" ]; then
    note="$title"
    case "$note" in \"*\") note="${note#\"}"; note="${note%\"}";; esac
  fi
  printf '%s\t%s\t%s\t%s [%s]\n' "$surface" "$tests" "$cmd" "$note" "$id"
  return 0
}
surface_change_set() { # surface_change_set [--force] — the paths a verdict is about, one per
  # line; rc 0 = BOUNDED. $PRIMARY HEAD off $BASE (a feat/ or integrate/ branch) → the branch's
  # own diff, `git diff --name-only $BASE...HEAD`, the stamp never consulted. On $BASE → the suite
  # stamp's sha when it is an ancestor of HEAD: `git diff --name-only <sha> HEAD`, and
  # SURFACE_BASELINE=<sha> SURFACE_BASELINE_SCOPE=<its scope> for the caller. --force, no stamp,
  # or a non-ancestor sha → rc 1, prints nothing: UNBOUNDED, the caller runs everything. Both
  # cases drop the board-noise paths — the reports dir, ops/MAP.md, ops/SURFACES.tsv — exactly the
  # three suite_stamp_carry allows to change after a suite ran.
  local force=0 cur="" list="" p rel sha="" junk="" stamp
  [ "${1:-}" = "--force" ] && force=1
  SURFACE_BASELINE=""; SURFACE_BASELINE_SCOPE=""
  cur="$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ "$cur" = "$BASE" ]; then
    [ "$force" -eq 0 ] || return 1
    stamp="$PRIMARY/.polaris/suite-stamp"
    [ -s "$stamp" ] || return 1
    read -r sha junk < "$stamp" || true
    [ -n "$sha" ] || return 1
    git -C "$PRIMARY" merge-base --is-ancestor "$sha" HEAD 2>/dev/null || return 1
    list="$(git -C "$PRIMARY" diff --name-only "$sha" HEAD 2>/dev/null)" || return 1
    SURFACE_BASELINE="$sha"; SURFACE_BASELINE_SCOPE="$(suite_stamp_scope "$stamp" || true)"
  else
    list="$(git -C "$PRIMARY" diff --name-only "$BASE...HEAD" 2>/dev/null)" || return 1
  fi
  rel="$(cfg reports docs/sprints)"; rel="${rel%/}"; [ -n "$rel" ] || rel="docs/sprints"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in "$rel/"*|ops/MAP.md|ops/SURFACES.tsv) continue;; esac
    printf '%s\n' "$p"
  done <<EOF
$list
EOF
  return 0
}
surface_select_cmd() { # surface_select_cmd <paths-file> — rc 0: the commands to run INSTEAD of
  # test:, one per line — every distinct non-`-` cmd of the rows the changed paths match
  # (first-appearance order), then, if any matched row is `-`, ONE line = test_select with every
  # {tests} replaced by the space-joined distinct tests globs of those rows. rc 1 + ONE reason on
  # stdout, and the caller runs test: verbatim: `test_select unset` · `no rows` · `no changed
  # paths` · `unmapped: <first path with no row> (+<n> more)`. ALL-OR-NOTHING: one unmapped changed
  # path ⇒ the whole suite (D3 — never a gate whose cheapest satisfying move is silence).
  local file="${1:-}" tpl lines p row rest tests cmd hit n=0 first="" more=0 cmds="" globs="" nl
  nl=$'\n'
  tpl="$(cfg test_select "")"
  [ -n "$tpl" ] || { printf 'test_select unset\n'; return 1; }
  lines="$(surfaces_lines)"
  [ -n "$lines" ] || { printf 'no rows\n'; return 1; }
  [ -f "$file" ] || file=/dev/null
  while IFS= read -r p || [ -n "$p" ]; do
    [ -z "$p" ] && continue
    n=$((n+1)); hit=0
    while IFS= read -r row; do
      surface_row_matches "$p" "$row" || continue
      rest="${row#*$POLARIS_TAB}"; [ "$rest" != "$row" ] || rest=""
      tests="${rest%%$POLARIS_TAB*}"
      [ -n "$tests" ] || continue                       # a row without a tests glob maps nothing
      case "$rest" in *"$POLARIS_TAB"*) cmd="${rest#*$POLARIS_TAB}"; cmd="${cmd%%$POLARIS_TAB*}";; *) cmd="";; esac
      hit=1
      if [ -n "$cmd" ] && [ "$cmd" != "-" ]; then
        case "$nl$cmds$nl" in *"$nl$cmd$nl"*) ;; *) cmds="${cmds:+$cmds$nl}$cmd";; esac
      else
        case " $globs " in *" $tests "*) ;; *) globs="${globs:+$globs }$tests";; esac
      fi
    done <<EOF
$lines
EOF
    if [ "$hit" -eq 0 ]; then
      if [ -z "$first" ]; then first="$p"; else more=$((more+1)); fi
    fi
  done < "$file"
  [ "$n" -gt 0 ] || { printf 'no changed paths\n'; return 1; }
  if [ -n "$first" ]; then
    if [ "$more" -gt 0 ]; then printf 'unmapped: %s (+%s more)\n' "$first" "$more"
    else printf 'unmapped: %s\n' "$first"; fi
    return 1
  fi
  [ -z "$cmds" ] || printf '%s\n' "$cmds"
  # bash 5.2 turns patsub_replacement ON: an unquoted replacement would expand `&` — quote it.
  [ -z "$globs" ] || printf '%s\n' "${tpl//"{tests}"/"$globs"}"
  return 0
}
suite_stamp_scope() { # suite_stamp_scope [<file>] — field 3 of the suite stamp (default
  # $PRIMARY/.polaris/suite-stamp): `full` | `scoped`. A 2-field (pre-6.4) stamp → `full` — every
  # pre-6.4 writer ran everything. Missing/empty file → prints nothing, rc 1.
  local f="${1:-${PRIMARY:-}/.polaris/suite-stamp}" sha="" epoch="" scope=""
  [ -s "$f" ] || return 1
  read -r sha epoch scope < "$f" || true
  [ -n "$sha" ] || return 1
  scope="${scope%%[!a-z]*}"
  case "$scope" in scoped) printf 'scoped\n';; *) printf 'full\n';; esac
  return 0
}

# ------------------------------------------------------- frontmatter parsing
fm_get() { # fm_get <key> <file> — scalar value; strips trailing " # comment" and \r
  awk -v k="$1" '
    /^---[\r]?$/ { fs++; next }
    fs==1 && index($0, k":")==1 {
      s=substr($0, length(k)+2)
      sub(/^[ \t]*/,"",s); sub(/[ \t]#.*$/,"",s); sub(/[ \t\r]*$/,"",s)
      print s; exit
    }' "$2"
}
fm_list() { # fm_list <key> <file> — items of a "- x" block list, an inline "[a, b]" flow list, "[]",
  # or an inline scalar; comment/\r stripped. Shapes + edge cases: ops/contracts/frontmatter-lists.md
  awk -v k="$1" '
    function emit(s,   n, i, parts, item) {
      if (s == "") return
      if (s ~ /^\[.*\]$/) {                 # inline flow list: strip [ ], split on ",", trim, drop empties
        s = substr(s, 2, length(s) - 2)
        n = split(s, parts, ",")
        for (i = 1; i <= n; i++) {
          item = parts[i]
          sub(/^[ \t]*/,"",item); sub(/[ \t]*$/,"",item)
          if (item != "") print item
        }
        return
      }
      print s                               # inline scalar — one item
    }
    /^---[\r]?$/ { fs++; next }
    fs!=1 { next }
    index($0, k":")==1 {
      on=1; s=substr($0, length(k)+2)
      sub(/^[ \t]*/,"",s); sub(/[ \t]#.*$/,"",s); sub(/[ \t\r]*$/,"",s)
      emit(s)
      next
    }
    on && /^[ \t]*-[ \t]/ {
      s=$0; sub(/^[ \t]*-[ \t]+/,"",s); sub(/[ \t]#.*$/,"",s); sub(/[ \t\r]*$/,"",s)
      if (s!="") print s
      next
    }
    on && /^[A-Za-z_]/ { on=0 }' "$2"
}
task_file() { # task_file <ID> [column] — path of the task file, searched or scoped
  local id="$1" col="${2:-}" f
  if [ -n "$col" ]; then f="$BOARD/$col/$id.md"; [ -f "$f" ] && printf '%s' "$f"; return; fi
  for col in active ready review blocked backlog done; do
    f="$BOARD/$col/$id.md"; [ -f "$f" ] && { printf '%s' "$f"; return; }
  done
  return 1
}
task_col() { task_file "$1" >/dev/null || return 1; dirname "$(task_file "$1")" | xargs basename; }

# --------------------------------------------------- board mutex + commit ops
mutex_off() { # release the board mutex if OURS (the $MUTEX/pid mutex_on wrote matches this
  # process); foreign, missing or unreadable pid → silent no-op, exactly as int_off treats a lease
  # that is not ours. T-057 armed `trap on_die EXIT` for the whole int_on lease lifetime, so an
  # unconditional `rm -rf "$MUTEX"` at exit could delete a mutex a DIFFERENT session legitimately
  # holds and un-serialize two board mutations mid-flight. Removing our OWN mutex is byte-identical
  # to before. Crashed/legacy (pid-less) mutexes are NOT this function's job: the staleness steal in
  # mutex_on remains the one recovery path — and since 6.2.0 it reads this same pid, so a pid-less
  # or dead holder still goes at 120s while a live one keeps it to the 20-minute backstop.
  if [ -d "$MUTEX" ] && [ "$(cat "$MUTEX/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$MUTEX" 2>/dev/null || true
  fi
  return 0
}
on_die() {  # EXIT trap while a claim/board op is in flight
  mutex_off
  # T-057: release the integration lease when this process holds it — a crashed holder must not
  # cost integration_stale_minutes of staleness. ${INT_HELD:-}-guarded on purpose: the 2-module
  # guard path (core+ownership — no workspace.sh, so no int_off) never sets it and never notices.
  [ -n "${INT_HELD:-}" ] && int_off || true
  if [ -n "$FAIL_LOCK_ID" ]; then
    lock_drop "$FAIL_LOCK_ID"
    [ "$CLAIM_MODE" = "claim-branch" ] && claim_branch_drop "$FAIL_LOCK_ID" || true
  fi
}
mutex_on() {
  mkdir -p "$LOCKS"
  local i=0
  until mkdir "$MUTEX" 2>/dev/null; do
    i=$((i+1))
    if [ -f "$MUTEX/epoch" ]; then
      # The steal is pid-aware since 6.2.0 (ops/contracts/worktree-liveness.md § steals). Age alone
      # stole the mutex out from under a holder that was merely slow — a board push over a bad
      # network outlives 120s — and two sessions then mutated the board at once. A holder whose pid
      # still answers keeps it until the 20-minute backstop; a dead or pid-less one goes at 120s,
      # so a crashed holder is still recovered without anyone reaching for rm -rf.
      local e age hp; e="$(cat "$MUTEX/epoch" 2>/dev/null)"; e="${e:-$(date +%s)}"
      age=$(( $(date +%s) - e ))
      hp="$(cat "$MUTEX/pid" 2>/dev/null || true)"; case "$hp" in ''|*[!0-9]*) hp="";; esac
      if [ "$age" -gt 1200 ] || { [ "$age" -gt 120 ] && { [ -z "$hp" ] || ! kill -0 "$hp" 2>/dev/null; }; }; then
        note "stealing stale board mutex (${age}s)"; rm -rf "$MUTEX"; continue
      fi
    fi
    [ "$i" -gt 150 ] && die "board mutex timeout — is another session stuck? rm -rf '$MUTEX'"
    sleep 0.2
  done
  date +%s > "$MUTEX/epoch"
  # Ownership, beside the epoch: mutex_off removes the mutex only when this pid wrote it. The steal
  # branch above never reads it on purpose — a crashed holder must stay stealable by age alone.
  printf '%s\n' "$$" > "$MUTEX/pid"
  trap on_die EXIT
}
has_remote() { git -C "$PRIMARY" remote get-url origin >/dev/null 2>&1; }
# publish: direct | pr (ops/contracts/publish-modes.md) — HOW a sealed wave reaches origin's $BASE.
# Read via cfg at command runtime, never cached; unknown value warns ONCE per invocation (stderr,
# so command substitutions never swallow it) and behaves as direct. Sets $PUB — no command
# substitution on purpose (bash 3.2: no `case` inside `$(...)`).
publish_resolve() {
  local p; p="$(cfg publish direct)"
  case "$p" in
    direct|pr) PUB="$p";;
    *) [ -z "$PUBLISH_WARNED" ] && { printf "   ⚠ publish: '%s' unknown (direct | pr) — behaving as direct\n" "$p" >&2; PUBLISH_WARNED=1; }
       PUB="direct";;
  esac
  return 0
}
# publish: direct base-push-rejected stamp (ops/contracts/publish-modes.md). A protected $BASE keeps
# refusing seal's push; the stamp records date + a running count so doctor can recommend publish: pr
# after >=2 rejections. A successful base push clears it. Lives under $PRIMARY/.polaris (gitignored).
base_push_reject() {
  local f="$PRIMARY/.polaris/base-push-rejected" c=0
  [ -f "$f" ] && c="$(awk 'NR==1{print $2+0}' "$f" 2>/dev/null)"
  mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
  printf '%s %s\n' "$(date +%F)" "$(( ${c:-0} + 1 ))" > "$f"
}
base_push_clear() { rm -f "$PRIMARY/.polaris/base-push-rejected" 2>/dev/null || true; }
pr_create_url() { # pr_create_url <origin-url> <date> <dest> — Bitbucket PR-create URL on stdout
  # (ssh or https origin); non-Bitbucket or unparseable → prints nothing, never dies.
  local url="$1" date="$2" dest="$3" path=""
  case "$url" in
    *bitbucket.org*)
      path="${url#*bitbucket.org}"
      path="${path#:}"; path="${path#/}"
      path="${path%/}"
      case "$path" in *.git) path="${path%.git}";; esac
      case "$path" in
        */*) printf 'https://bitbucket.org/%s/pull-requests/new?source=integrate/%s&dest=%s\n' "$path" "$date" "$dest";;
      esac;;
  esac
  return 0
}
# Board history lives on its own ref so $BASE first-parent stays clean product history
# (ops/contracts/quiet-board.md). The moved set — ops/board/** + ops/SPRINT.md — is gitignored on
# base and committed here via secondary-index plumbing: no second worktree, no branch switch.
board_paths() { # the moved set as it exists ON DISK, repo-relative
  ( cd "$PRIMARY" || exit 0
    [ -f ops/SPRINT.md ] && printf 'ops/SPRINT.md\n'
    [ -d ops/board ] && find ops/board -type f
    exit 0 )
}
board_ref_commit() { # board_ref_commit <msg> <parent|""> <idx> — commit the on-disk moved set via a
  # SECONDARY index; prints the new sha. read-tree --empty + update-index --add per path rebuilds
  # the tree from disk every time, so a plain `mv` between columns needs no remove call and the
  # branch's tree always mirrors disk exactly (ONLY the moved set, at on-disk paths). GIT_INDEX_FILE
  # keeps the primary index and working tree untouched, and update-index bypasses gitignore —
  # required, the moved set is ignored on base. Empty <parent> = the parentless (orphan) first commit.
  local msg="$1" parent="$2" idx="$3" tree
  rm -f "$idx"
  GIT_INDEX_FILE="$idx" git -C "$PRIMARY" read-tree --empty || return 1
  # 2>/dev/null: autocrlf's "LF will be replaced by CRLF" advice is per-file noise on Windows
  # (the old `git add` path silenced it the same way); real failures still return 1 and die upstream.
  board_paths | GIT_INDEX_FILE="$idx" git -C "$PRIMARY" update-index --add --stdin 2>/dev/null || return 1
  tree="$(GIT_INDEX_FILE="$idx" git -C "$PRIMARY" write-tree)" || return 1
  if [ -n "$parent" ]; then git -C "$PRIMARY" commit-tree "$tree" -p "$parent" -m "$msg"
  else git -C "$PRIMARY" commit-tree "$tree" -m "$msg"; fi
}
sync_board() { # push polaris/board (NEVER $BASE), bounded retry. A rejection means another machine
  # pushed first: fetch its tip, union-append any EVENTS.ndjson lines it has that we lack into the
  # on-disk file (append-only telemetry — no line is ever lost to a push race), re-commit local
  # state re-parented on the fetched tip, retry. Every other board file: local wins — same-machine
  # writers are mutex-serialized. No remote, or no board ref yet → no-op.
  has_remote || return 0
  git -C "$PRIMARY" rev-parse -q --verify "$BOARD_REF" >/dev/null || return 0
  local i rtip ltip subj new idx line
  for i in 1 2 3 4 5; do
    # Five push/fetch/re-commit rounds over a slow network can outlast the mutex's 120s steal
    # window, and the holder that looks abandoned is us. Re-stamp the epoch each pass — only when
    # the mutex is still ours, so we never refresh someone else's.
    if [ "$(cat "$MUTEX/pid" 2>/dev/null)" = "$$" ]; then date +%s > "$MUTEX/epoch" 2>/dev/null || true; fi
    git -C "$PRIMARY" push -q origin "$BOARD_REF:$BOARD_REF" 2>/dev/null && return 0
    git -C "$PRIMARY" fetch -q origin "$BOARD_REF" 2>/dev/null || true
    # The remote tip BY NAME. FETCH_HEAD is a single shared file: any concurrent fetch of another
    # ref (a sibling session pulling feat/*) overwrites it, and we would re-parent the board onto
    # whatever that was. ls-remote answers for this ref and nothing else.
    rtip="$(git -C "$PRIMARY" ls-remote origin refs/heads/polaris/board 2>/dev/null | cut -f1)"
    [ -n "$rtip" ] || { sleep 0.3; continue; }
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -qxF -- "$line" "$EVENTS" 2>/dev/null || printf '%s\n' "$line" >> "$EVENTS"
    done <<EOF
$(git -C "$PRIMARY" show "$rtip:ops/board/EVENTS.ndjson" 2>/dev/null || true)
EOF
    ltip="$(git -C "$PRIMARY" rev-parse -q --verify "$BOARD_REF" 2>/dev/null || true)"
    subj="$(git -C "$PRIMARY" log -1 --format=%s "$ltip" 2>/dev/null | grep . || echo 'chore(board): sync')"
    idx="$(mktemp)"
    if new="$(board_ref_commit "$subj" "$rtip" "$idx")" && [ -n "$new" ]; then
      git -C "$PRIMARY" update-ref "$BOARD_REF" "$new" 2>/dev/null || true
    fi
    rm -f "$idx"
  done
  die "could not push polaris/board to origin after 5 attempts"
}
board_commit() { # board_commit <msg> — ONE commit of the moved set on refs/heads/polaris/board.
  # Subjects unchanged (chore(board): …). Contention retry kept: the ref advances by
  # compare-and-swap (update-ref <new> <old>), so a racing writer costs one loop iteration,
  # never a lost commit. Working tree, primary index and $BASE gain nothing.
  local msg="$1" i idx tip new
  idx="$(mktemp)"
  for i in 1 2 3 4 5 6 7; do
    tip="$(git -C "$PRIMARY" rev-parse -q --verify "$BOARD_REF" 2>/dev/null || true)"
    if new="$(board_ref_commit "$msg" "$tip" "$idx")" && [ -n "$new" ] \
       && git -C "$PRIMARY" update-ref "$BOARD_REF" "$new" "${tip:-}" 2>/dev/null; then
      rm -f "$idx"; return 0
    fi
    sleep 0.3
  done
  rm -f "$idx"
  die "board commit failed: $msg (could not advance $BOARD_REF — another writer stuck?)"
}
board_materialize() { # fresh clone: the moved set is ignored on base, so a clone's working tree has
  # no ops/board/ — its state lives on polaris/board (ops/contracts/quiet-board.md). When the dir
  # is missing and the ref exists (local, else origin — the local ref is created from origin's),
  # write the set's files into the working tree via plumbing: read-tree into a SECONDARY index +
  # checkout-index. NEVER a branch switch; primary index and checked-out branch untouched.
  # rc 0 = materialized (and said so) · rc 1 = nothing to do (board on disk, or no ref anywhere).
  [ -d "$BOARD" ] && return 1
  if ! git -C "$PRIMARY" rev-parse -q --verify "$BOARD_REF" >/dev/null; then
    git -C "$PRIMARY" rev-parse -q --verify refs/remotes/origin/polaris/board >/dev/null || return 1
    git -C "$PRIMARY" update-ref "$BOARD_REF" \
      "$(git -C "$PRIMARY" rev-parse refs/remotes/origin/polaris/board)" || return 1
  fi
  local idx; idx="$(mktemp)"
  if ! GIT_INDEX_FILE="$idx" git -C "$PRIMARY" read-tree "$BOARD_REF" \
     || ! GIT_INDEX_FILE="$idx" git -C "$PRIMARY" checkout-index -a -f --prefix="$PRIMARY/"; then
    rm -f "$idx"; return 1
  fi
  rm -f "$idx"
  say "materialized ops/board/ + ops/SPRINT.md from polaris/board (fresh clone — board state lives on that ref)"
}

# The READ side of claim: claim-branch (ops/contracts/first-run.md § 5). sync_board pushes the board
# ref after every mutation, but nothing fetched it, so a second machine read ops/board/ frozen at its
# last clone. board_pull fast-forwards the local ref to origin's and writes ONLY the paths that differ
# between the two tips (git diff --no-renames: a task moved between columns is unlinked at its old
# path and written at its new one — never shown twice), through board_materialize's plumbing — a
# SECONDARY index + checkout-index --prefix; never a branch switch, never the primary index. A path
# unchanged between the tips is not touched, so an in-flight task file whose Notes this machine has
# appended but not yet committed survives the pull. Writes land before unlinks and the ref moves LAST
# (compare-and-swap): a failure midway leaves a duplicate at worst, never a task missing from the next
# board commit — which rebuilds its tree from disk anyway: disk is the truth, the ref is its history.
# Both lines go to stderr: this is the first statement of board-fm (a parsed TSV) and next (line 1 is
# the verb), so stdout is not ours to write on. The throttle stamp holds the epoch of the last attempt
# — read back with a builtin, because `find -mmin`/`stat` disagree between GNU and BSD.
board_pull() { # rc 0 always. local-lock · no remote · POLARIS_BOARD_PULL=0 · an attempt <60s ago → nothing, no fork
  [ "$CLAIM_MODE" = "claim-branch" ] && [ "${POLARIS_BOARD_PULL:-1}" != "0" ] || return 0
  has_remote || return 0
  local stamp="$PRIMARY/.polaris/board-pulled" now last="" ltip rtip n idx p
  now="$(date +%s)"
  [ -f "$stamp" ] && { IFS= read -r last < "$stamp" || true; }
  case "$last" in ''|*[!0-9]*) last=0;; esac
  [ $(( now - last )) -ge 60 ] || return 0
  { mkdir -p "$PRIMARY/.polaris" && printf '%s\n' "$now" > "$stamp"; } 2>/dev/null || true   # touched on EVERY attempt
  ltip="$(git -C "$PRIMARY" rev-parse -q --verify "$BOARD_REF" 2>/dev/null)" || return 0    # no local ref: board_materialize's job
  git -C "$PRIMARY" fetch -q origin "$BOARD_REF" 2>/dev/null || return 0
  # the remote tip BY NAME (sync_board's lesson): ls-remote answers for this ref and nothing else
  rtip="$(git -C "$PRIMARY" ls-remote origin refs/heads/polaris/board 2>/dev/null | cut -f1)"
  [ -n "$rtip" ] && [ "$rtip" != "$ltip" ] || return 0
  git -C "$PRIMARY" cat-file -e "$rtip^{commit}" 2>/dev/null || return 0                   # pushed between fetch and ls-remote: next time
  if git -C "$PRIMARY" merge-base --is-ancestor "$ltip" "$rtip" 2>/dev/null; then
    n="$(git -C "$PRIMARY" rev-list --count "$ltip..$rtip" 2>/dev/null || echo '?')"
    idx="$(mktemp)"
    GIT_INDEX_FILE="$idx" git -C "$PRIMARY" read-tree "$rtip" 2>/dev/null \
      && git -C "$PRIMARY" diff -z --no-renames --name-only --diff-filter=d "$ltip" "$rtip" \
         | GIT_INDEX_FILE="$idx" git -C "$PRIMARY" checkout-index -z -q -f --prefix="$PRIMARY/" --stdin 2>/dev/null \
      || { rm -f "$idx"; note "⚠ board pull could not write ops/board/ — left exactly as it was" >&2; return 0; }
    rm -f "$idx"
    git -C "$PRIMARY" diff -z --no-renames --name-only --diff-filter=D "$ltip" "$rtip" 2>/dev/null \
      | while IFS= read -r -d '' p; do [ -n "$p" ] && rm -f "$PRIMARY/$p"; done || true
    git -C "$PRIMARY" update-ref "$BOARD_REF" "$rtip" "$ltip" 2>/dev/null || true             # a local writer raced in: disk is truth, its commit re-parents
    say "board pulled: $n commit(s) from origin (claim-branch)" >&2
  elif ! git -C "$PRIMARY" merge-base --is-ancestor "$rtip" "$ltip" 2>/dev/null; then
    note "⚠ board diverged from origin — local board commits were never pushed; run: ops/polaris sweep" >&2
  fi   # else: local is ahead — the next mutation's sync_board pushes it
  return 0
}

# --------------------------------------------------------------- lock helpers
lock_take() { # lock_take <ID> — atomic; returns 1 if already taken
  # meta is 5 lines since 6.2.0 (ops/contracts/worktree-liveness.md § lock meta): epoch · who · id ·
  # session id · harness pid. Both env vars are exported into every Bash-tool environment and stay
  # put for the whole session, unlike $$, which changes with every command. They decide NOTHING
  # about liveness — the beat file does that — they only let `resume` recognise its own task after a
  # compaction, `sweep` say whether the session is still around, and `next` name whose lock it is.
  # Absent (a plain shell, CI) ⇒ "-". Readers of lines 1-3 are untouched; a missing line reads "-".
  mkdir -p "$LOCKS"
  mkdir "$LOCKS/$1" 2>/dev/null || return 1
  who; { date +%s; echo "$WHO"; echo "$1"; echo "${CLAUDE_CODE_SESSION_ID:--}"; echo "${CLAUDE_PID:--}"; } > "$LOCKS/$1/meta"
}
lock_drop() { rm -rf "${LOCKS:?}/$1" 2>/dev/null || true; }
lock_age() { # seconds since lock creation; 0 if no meta
  local e; e="$(sed -n 1p "$LOCKS/$1/meta" 2>/dev/null | tr -d '\r')"; e="${e:-$(date +%s)}"
  echo $(( $(date +%s) - e ))
}
claim_branch_take() { # multi-machine claim: unique commit via plumbing + push guarded by empty lease
  local id="$1" sha
  who
  sha="$(git -C "$PRIMARY" commit-tree "$BASE^{tree}" -p "$BASE" -m "polaris claim $id by $WHO")" \
    || die "commit-tree failed"
  git -C "$PRIMARY" push -q origin "$sha:refs/heads/claim/$id" \
    --force-with-lease="refs/heads/claim/$id:" 2>/dev/null
}
claim_branch_drop() { git -C "$PRIMARY" push -q origin ":refs/heads/claim/$1" 2>/dev/null || true; }

# ----------------------------------------------------------- worktree helpers
wt_path() { printf '%s/.polaris/wt/%s' "$PRIMARY" "$1"; }
current_task_id() { # infer <ID> from feat/<ID> branch of CWD
  local b; b="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  case "$b" in feat/*) printf '%s' "${b#feat/}";; *) return 1;; esac
}
set_fm() { # set_fm <key> <value> <file> — replace scalar frontmatter line, portable (no sed -i)
  local tmp="$3.tmp.$$"
  awk -v k="$1" -v v="$2" '
    /^---[\r]?$/ { fs++ }
    fs==1 && index($0, k":")==1 { print k": "v; next }
    { print }' "$3" > "$tmp" && mv "$tmp" "$3"
}
fm_stamp() { # fm_stamp <key> <value> <file> — set_fm that also ADDS the line (before the closing
  # ---) when the key is absent. set_fm only replaces; `done` stamps landed:, a key no task has.
  local tmp="$3.tmp.$$"
  awk -v k="$1" -v v="$2" '
    /^---[\r]?$/ { fs++; if (fs==2 && !hit) { print k": "v; hit=1 } print; next }
    fs==1 && index($0, k":")==1 { print k": "v; hit=1; next }
    { print }' "$3" > "$tmp" && mv "$tmp" "$3"
}
