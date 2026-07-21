# POLARIS lib/core.sh — shared plumbing sourced by ops/polaris (the lib loader): die/say, cfg,
# telemetry, frontmatter parsing, board mutex/commit/sync, locks, worktree helpers.

die() { printf '⛔ %s\n' "$*" >&2; exit 1; }
say() { printf '✅ %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

cfg() { # cfg <key> <default>  — reads "key: value" from CONVENTIONS.md, strips " # comment".
  # A blank key with only a trailing comment ("lint:   # none") must read as EMPTY, not as the
  # comment text — hence the leading s/^#.*$// (the space-anchored strip can't see it).
  local v=""
  [ -f "$CONV" ] && v="$(sed -n "s/^$1:[[:space:]]*//p" "$CONV" | head -1 \
      | sed -e 's/^#.*$//' -e 's/[[:space:]]#.*$//' | tr -d '\r' | sed -e 's/[[:space:]]*$//')"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}

# ------------------------------------------------------------------ telemetry
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r'; }
evt() { # evt <ev> <id> [note] [pts] — append one ndjson line. Call INSIDE the board
  # mutex, BEFORE board_commit, so the line rides the same board commit.
  # EVENTS.ndjson is append-only and union-merged (.gitattributes) so parallel
  # machines never conflict on it. Never edit it by hand.
  # v5: claim/done lines carry "pts" so `metrics` can calibrate per point bucket.
  local pts="${4:-}"; case "$pts" in ''|*[!0-9.]*) pts="";; esac
  printf '{"ts":%s,"ev":"%s","id":"%s","who":"%s","note":"%s"%s}\n' \
    "$(date +%s)" "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$WHO")" "$(jesc "${3:-}")" \
    "${pts:+,\"pts\":$pts}" >> "$EVENTS"
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
rules_lines() { # normalized RULES.tsv: comments/blank/CR stripped
  [ -f "$RULES" ] || return 0
  tr -d '\r' < "$RULES" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' || true
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
mutex_off() { rm -rf "$MUTEX" 2>/dev/null || true; }
on_die() {  # EXIT trap while a claim/board op is in flight
  mutex_off
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
      local e age; e="$(cat "$MUTEX/epoch" 2>/dev/null)"; e="${e:-$(date +%s)}"
      age=$(( $(date +%s) - e ))
      if [ "$age" -gt 120 ]; then note "stealing stale board mutex (${age}s)"; rm -rf "$MUTEX"; continue; fi
    fi
    [ "$i" -gt 150 ] && die "board mutex timeout — is another session stuck? rm -rf '$MUTEX'"
    sleep 0.2
  done
  date +%s > "$MUTEX/epoch"
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
    git -C "$PRIMARY" push -q origin "$BOARD_REF:$BOARD_REF" 2>/dev/null && return 0
    git -C "$PRIMARY" fetch -q origin "$BOARD_REF" 2>/dev/null || true
    rtip="$(git -C "$PRIMARY" rev-parse -q --verify FETCH_HEAD 2>/dev/null || true)"
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

# --------------------------------------------------------------- lock helpers
lock_take() { # lock_take <ID> — atomic; returns 1 if already taken
  mkdir -p "$LOCKS"
  mkdir "$LOCKS/$1" 2>/dev/null || return 1
  { date +%s; echo "$WHO"; echo "$1"; } > "$LOCKS/$1/meta"
}
lock_drop() { rm -rf "${LOCKS:?}/$1" 2>/dev/null || true; }
lock_age() { # seconds since lock creation; 0 if no meta
  local e; e="$(sed -n 1p "$LOCKS/$1/meta" 2>/dev/null | tr -d '\r')"; e="${e:-$(date +%s)}"
  echo $(( $(date +%s) - e ))
}
claim_branch_take() { # multi-machine claim: unique commit via plumbing + push guarded by empty lease
  local id="$1" sha
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
