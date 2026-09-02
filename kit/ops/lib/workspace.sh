# POLARIS lib/workspace.sh — shared-checkout mechanics sourced by ops/polaris (the lib loader):
# branch-ID hygiene, worktree add, stray-feat repair, the worktree beat + wt_remove (the ONE
# removal primitive — never forced, dirty ones archived), the integration lease, wave adoption, park.

id_ok() { # id_ok <ID> — rc 0 = usable as feat/<ID>. rc 1 + ONE ⛔ line: empty, literal `feat`,
  # or anything `git check-ref-format refs/heads/feat/<ID>` refuses. cmd_claim runs this BEFORE
  # lock_take. Returns instead of dying so an auto-pick claim can move to the next candidate.
  local id="${1:-}"
  if [ -z "$id" ]; then
    printf '⛔ %s\n' "empty task ID — nothing to make a feat/<ID> branch from" >&2; return 1
  fi
  if [ "$id" = "feat" ]; then
    printf '⛔ %s\n' "'feat' is not a task ID — a ref literally named feat shadows the feat/<ID> namespace" >&2; return 1
  fi
  if ! git check-ref-format "refs/heads/feat/$id" >/dev/null 2>&1; then
    printf '⛔ %s\n' "invalid task ID '$id' — git check-ref-format refuses refs/heads/feat/$id" >&2; return 1
  fi
  return 0
}

wt_add() { # wt_add <ID> [resume] — shared worktree-add for claim/resume: .polaris/wt/<ID> on feat/<ID>
  # (existing branch reused, else -b from $BASE). stderr is CAPTURED to a temp file — never
  # 2>/dev/null: retry (7 × 0.3s) ONLY when it mentions index.lock (two near-simultaneous claims
  # — exactly a fleet's panes — collide on git's one index.lock, and each adds a DIFFERENT tree,
  # so a brief retry is safe); a stray ref literally named `feat` → ONE stray_feat_repair, then
  # one more try; anything else re-emits the captured stderr verbatim and dies. Prints nothing
  # on success — except `resume` with no local feat/<ID>: the branch is recreated from $BASE and
  # ONE ⚠ note says so (ops/contracts/worktree-liveness.md) — never silently a fresh start.
  local id="$1"
  local mode="${2:-}"
  local wt; wt="$(wt_path "$id")"
  local errf; errf="$(mktemp)"
  local tries=0
  local repaired=0
  local created=0
  local rc
  mkdir -p "$PRIMARY/.polaris/wt"
  while :; do
    rc=0
    if git -C "$PRIMARY" show-ref --verify -q "refs/heads/feat/$id"; then
      git -C "$PRIMARY" worktree add -q "$wt" "feat/$id" 2>"$errf" || rc=$?
    else
      created=1
      git -C "$PRIMARY" worktree add -q "$wt" -b "feat/$id" "$BASE" 2>"$errf" || rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
      rm -f "$errf"
      [ "$created" -eq 1 ] && [ "$mode" = resume ] \
        && note "⚠ feat/$id did not exist — recreated from $BASE; earlier commits, if any, are on origin/feat/$id or were deleted by done/release"
      return 0
    fi
    if grep -q 'index\.lock' "$errf" 2>/dev/null; then
      tries=$((tries+1))
      if [ "$tries" -lt 7 ]; then sleep 0.3; continue; fi
    elif [ "$repaired" -eq 0 ] && git -C "$PRIMARY" show-ref --verify -q refs/heads/feat; then
      repaired=1
      stray_feat_repair
      continue
    fi
    cat "$errf" >&2
    rm -f "$errf"
    die "worktree add failed for feat/$id — git's real error is above, verbatim"
  done
}

stray_feat_repair() { # a ref literally named `feat` is ownerless junk that shadows the feat/<ID>
  # namespace: rename it out of the way (ARCHIVE, never delete). Local branch feat →
  # stray/feat-<sha7>; origin's feat → pushed to stray/feat-<sha7>, then removed from origin —
  # only after the archive push landed. <sha7> = the ref's own short sha. No such ref anywhere →
  # silent rc 0. One note per repaired ref.
  local sha7
  if git -C "$PRIMARY" show-ref --verify -q refs/heads/feat; then
    sha7="$(git -C "$PRIMARY" rev-parse --short=7 refs/heads/feat)"
    if git -C "$PRIMARY" branch -m feat "stray/feat-$sha7" 2>/dev/null \
       || git -C "$PRIMARY" branch -M feat "stray/feat-$sha7" 2>/dev/null; then
      note "stray local branch 'feat' archived as stray/feat-$sha7 (renamed, never deleted)"
    fi
  fi
  if has_remote; then
    local line
    line="$(git -C "$PRIMARY" ls-remote --heads origin feat 2>/dev/null | head -1 || true)"
    if [ -n "$line" ]; then
      local rsha="${line%%[[:space:]]*}"
      local osha7; osha7="$(printf '%.7s' "$rsha")"
      git -C "$PRIMARY" fetch -q origin refs/heads/feat 2>/dev/null || true
      if git -C "$PRIMARY" push -q origin "$rsha:refs/heads/stray/feat-$osha7" 2>/dev/null; then
        git -C "$PRIMARY" push -q origin ":refs/heads/feat" 2>/dev/null || true
        note "stray origin branch 'feat' archived as stray/feat-$osha7 (renamed, never deleted)"
      fi
    fi
  fi
  return 0
}

beat_touch() { # beat_touch <ID> — write epoch seconds to the beat, git's own per-worktree dir:
  # $GCD/worktrees/<ID>/polaris-beat (the liveness signal; it dies with the worktree). Best-effort,
  # rc 0 always — a beat that cannot be written reads as idle, which is the safe side. The
  # 2>/dev/null comes BEFORE the > on purpose: bash applies redirections left to right, so the
  # other order leaks "No such file or directory" when the dir is missing (T-093 found it live).
  mkdir -p "$GCD/worktrees/$1" 2>/dev/null || true
  date +%s 2>/dev/null > "$GCD/worktrees/$1/polaris-beat" || true
  return 0
}

beat_age() { # beat_age <ID> — print seconds since the beat; 999999 when absent/unreadable; rc 0.
  # Content first (beat_touch writes the epoch); empty or non-numeric (the hooks' mtime-only `: >`
  # touches) → the file's mtime, GNU `stat -c %Y` then BSD `stat -f %m`. `echo 1 > <beat>` backdates.
  local f="$GCD/worktrees/$1/polaris-beat" t="" age
  if [ -r "$f" ]; then
    IFS= read -r t < "$f" 2>/dev/null || true
    case "$t" in ''|*[!0-9]*) t="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || true)";; esac
  fi
  case "$t" in ''|*[!0-9]*) printf '999999\n'; return 0;; esac
  age=$(( $(date +%s) - t )); [ "$age" -lt 0 ] && age=0
  printf '%s\n' "$age"
}

beat_live() { # beat_live <ID> — rc 0 iff the beat is younger than wt_live_minutes × 60 (default 15,
  # non-numeric ⇒ 15): the ONE liveness test every remover asks. Liveness is beat-only — the lock's
  # sid/pid lines inform messages, never a removal. Use in a conditional (set -e is on).
  local m; m="$(cfg wt_live_minutes 15)"
  case "$m" in ''|*[!0-9]*) m=15;; esac
  [ "$(beat_age "$1")" -lt $(( m * 60 )) ]
}

wt_remove() { # wt_remove <ID> <done|release|sweep> — THE removal primitive (ops/contracts/
  # worktree-liveness.md, the caller × dirty × live table). rc 0 removed · 1 LEFT · 2 archived.
  # dirty = `git status --porcelain` prints anything (untracked included) · live = beat_live.
  # LIVE + caller done/sweep → LEFT rc 1 whatever the dirt · `release` from OUTSIDE a live+dirty
  # worktree → LEFT (the caller died before any board write; this only refuses) · `release` from
  # INSIDE (own lane — live by definition) ignores the beat. Then clean → `git worktree remove`,
  # never forced, + prune · dirty → mv to .polaris/wt-archive/<ID>-<epoch>, drop its .git pointer
  # (the bytes stay, git forgets it), prune. Any mv/git failure → rc 1 + ONE note, never a die,
  # never partial: the rename is atomic and a refused remove touches nothing. No worktree dir →
  # prune + rc 0, silent (callers need not pre-check -d). Output prefixes are pinned for drills.
  local id="$1" caller="${2:-sweep}"
  local wt; wt="$(wt_path "$id")"
  if [ ! -d "$wt" ]; then git -C "$PRIMARY" worktree prune 2>/dev/null || true; return 0; fi
  local beat="$GCD/worktrees/$id/polaris-beat"
  local own=0 live=0 dirty=0 refuse=0 age
  case "$PWD" in */.polaris/wt/"$id"|*/.polaris/wt/"$id"/*) own=1;; esac
  age="$(beat_age "$id")"; beat_live "$id" && live=1
  [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] && dirty=1
  if [ "$live" -eq 1 ]; then
    [ "$caller" != release ] && refuse=1
    [ "$own" -eq 0 ] && [ "$dirty" -eq 1 ] && refuse=1
  fi
  if [ "$refuse" -eq 1 ]; then
    if [ "$dirty" -eq 1 ]; then
      note "worktree LEFT: .polaris/wt/$id is live (beat ${age}s ago) and DIRTY — uncommitted work inside, nothing removed; if you are sure it is dead: rm \"$beat\" then re-run"
    else
      note "worktree LEFT: .polaris/wt/$id is live (beat ${age}s ago)"
    fi
    return 1
  fi
  local errf; errf="$(mktemp)"
  if [ "$dirty" -eq 0 ]; then
    if git -C "$PRIMARY" worktree remove "$wt" 2>"$errf"; then
      rm -f "$errf"; git -C "$PRIMARY" worktree prune 2>/dev/null || true
      note "worktree removed: .polaris/wt/$id"
      return 0
    fi
    note "worktree LEFT: .polaris/wt/$id — git refused to remove it: $(head -1 "$errf" 2>/dev/null || true)"
    rm -f "$errf"; return 1
  fi
  local epoch; epoch="$(date +%s)"
  local arc="$PRIMARY/.polaris/wt-archive/$id-$epoch"
  mkdir -p "$PRIMARY/.polaris/wt-archive" 2>/dev/null || true
  if ! mv "$wt" "$arc" 2>"$errf"; then
    if [ "$own" -eq 1 ]; then
      note "worktree LEFT: .polaris/wt/$id is dirty and you are standing in it — cd out of .polaris/wt/$id and run: bash ops/polaris sweep --fix"
    else
      note "worktree LEFT: .polaris/wt/$id — could not move it to .polaris/wt-archive/: $(head -1 "$errf" 2>/dev/null || true)"
    fi
    rm -f "$errf"; return 1
  fi
  rm -f "$errf" "$arc/.git" 2>/dev/null || true
  git -C "$PRIMARY" worktree prune 2>/dev/null || true
  note "worktree archived → .polaris/wt-archive/$id-$epoch"
  return 2
}

int_on() { # int_on [<why>] — take the integration lease $LOCKS/.int-lease (the board-mutex
  # pattern: atomic mkdir + epoch/who/pid files). Integration is ONE shared lane: whoever holds
  # the lease lands everything; a second session waits briefly or queues. Busy → poll every 2s,
  # progress note ~every 30s naming holder + age; holder epoch older than
  # integration_stale_minutes (default 45) AND (no pid · pid dead · older than TWICE that) → steal
  # with a note — a slow but ALIVE integrator is never stolen from before 2× stale; still busy
  # after integration_wait_minutes (default 10) → print ONE final line beginning `queued: ` +
  # rc 3 — NEVER a question, NEVER a raw die. Re-entrant: already ours (same pid file) → rc 0.
  # LOCK ORDERING: the lease is OUTERMOST — take it BEFORE any mutex_on, never while holding the
  # board mutex. Sets INT_HELD so core.sh::on_die releases a crashed holder's lease.
  local why="${1:-}"
  local lease="$LOCKS/.int-lease"
  local wm; wm="$(cfg integration_wait_minutes 10)"
  local sm; sm="$(cfg integration_stale_minutes 45)"
  case "$wm" in ''|*[!0-9]*) wm=10;; esac
  case "$sm" in ''|*[!0-9]*) sm=45;; esac
  if [ -d "$lease" ] && [ "$(cat "$lease/pid" 2>/dev/null)" = "$$" ]; then INT_HELD=1; return 0; fi
  mkdir -p "$LOCKS"
  local waited=0
  local told=0
  local now e hage holder hpid dead
  until mkdir "$lease" 2>/dev/null; do
    now="$(date +%s)"
    e="$(cat "$lease/epoch" 2>/dev/null || true)"
    case "$e" in ''|*[!0-9]*) e="$now";; esac
    hage=$(( now - e ))
    holder="$(cat "$lease/who" 2>/dev/null || true)"; holder="${holder:-unknown}"
    if [ "$hage" -gt $(( sm * 60 )) ]; then
      # dead = `kill -0` fails; on Windows (MSYS pids are invisible to kill -0 across runtimes)
      # = absent from the PID column of ONE `ps -W` listing. Only this stale path ever pays for it.
      hpid="$(cat "$lease/pid" 2>/dev/null || true)"; dead=0
      case "$hpid" in ''|*[!0-9]*) dead=1;;
        *) case "${OSTYPE:-}" in
             msys*|cygwin*) ps -W 2>/dev/null | awk -v p="$hpid" '$1==p{f=1} END{exit !f}' || dead=1;;
             *) kill -0 "$hpid" 2>/dev/null || dead=1;;
           esac;;
      esac
      if [ "$dead" -eq 1 ] || [ "$hage" -gt $(( 2 * sm * 60 )) ]; then
        note "stealing stale integration lease held by $holder ($(( hage / 60 ))m > ${sm}m stale limit)"
        rm -rf "$lease"; continue
      fi
    fi
    if [ "$waited" -ge $(( wm * 60 )) ]; then
      printf 'queued: integration lane busy — %s holds it (%sm) — re-run when the lane frees; a conductor polls at wave boundaries\n' "$holder" "$(( hage / 60 ))"
      return 3
    fi
    if [ $(( waited - told )) -ge 30 ]; then
      note "integration lane busy — $holder holds it ($(( hage / 60 ))m); waited ${waited}s"
      told="$waited"
    fi
    sleep 2
    waited=$(( waited + 2 ))
  done
  who
  date +%s > "$lease/epoch"
  printf '%s\n' "$WHO" > "$lease/who"
  printf '%s\n' "$$" > "$lease/pid"
  if [ -n "$why" ]; then printf '%s\n' "$why" > "$lease/why"; fi
  INT_HELD=1
  trap on_die EXIT
  return 0
}

int_off() { # release the integration lease if OURS (same pid file); silent no-op otherwise —
  # another session's lease is invisible to us and stays exactly where it is.
  local lease="$LOCKS/.int-lease"
  if [ -d "$lease" ] && [ "$(cat "$lease/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$lease" 2>/dev/null || true
    INT_HELD=""
  fi
  return 0
}

wave_on() { # wave_on — ensure + check out today's integrate/<date> in the primary.
  # PRECONDITION: the caller HOLDS the integration lease (int_on) — wave_on never takes it.
  # Three outcomes, and it says which: absent → create from $BASE · present and fast-forwardable
  # to $BASE → ff + reuse · present with unsealed lands (NOT ff-able) → ADOPT it as-is and keep
  # landing on top (the "finish that wave by hand first" die is dead — any integrator lands any
  # task; files_owned are disjoint, so the lands compose).
  local d; d="$(date +%F)"
  local br="integrate/$d"
  if ! git -C "$PRIMARY" rev-parse -q --verify "refs/heads/$br" >/dev/null; then
    git -C "$PRIMARY" checkout -q -b "$br" "$BASE" || die "could not create $br from $BASE"
    say "wave: created $br from $BASE"
    return 0
  fi
  git -C "$PRIMARY" checkout -q "$br" || die "could not check out $br"
  if git -C "$PRIMARY" merge-base --is-ancestor "refs/heads/$br" "$BASE" 2>/dev/null; then
    git -C "$PRIMARY" merge -q --ff-only "$BASE" >/dev/null || die "could not fast-forward $br to $BASE"
    say "wave: reusing $br (fast-forwarded to $BASE)"
  else
    say "wave: adopting $br as-is — unsealed lands stay, landing continues on top"
  fi
  return 0
}

park() { # park [<why>] — `git stash push --include-untracked` the PRIMARY's dirty tree under a
  # named stash polaris/park-<epoch>-<sid8|pid> (sid8 = first 8 of $CLAUDE_CODE_SESSION_ID; else
  # the parent shell's pid — two CLI calls never share $$, and the shell that ran both IS "this
  # session" when there is no sid): a dirty shared checkout is parked, never asked about, unpark
  # reverses OUR park in one command, and the stashed paths are printed (three-space indent) so
  # whoever's dirt it was can see it went somewhere. Nothing to park → friendly note, rc 0.
  # Stash refused → rc 1 with the tree untouched (the caller falls back to its dirty-tree die).
  local why="${1:-}"
  local epoch; epoch="$(date +%s)"
  local me="${CLAUDE_CODE_SESSION_ID:-}"; me="${me:+${me:0:8}}"; me="${me:-$PPID}"
  local name="polaris/park-$epoch-$me"
  if [ -z "$(git -C "$PRIMARY" status --porcelain 2>/dev/null)" ]; then
    note "nothing to park — the tree is clean"
    return 0
  fi
  git -C "$PRIMARY" stash push -q --include-untracked -m "$name${why:+ — $why}" || return 1
  say "parked as $name — bash ops/polaris unpark returns it"
  { git -C "$PRIMARY" stash show --name-only --include-untracked 2>/dev/null \
    || git -C "$PRIMARY" stash show --name-only 2>/dev/null || true; } | sed 's/^/   /'
  return 0
}

unpark() { # unpark [--any] — pop OUR newest polaris/park-* stash (name suffix = my sid8|pid), the
  # one-command reverse of park. None of ours → says how many parks other sessions left and names
  # --any, rc 0 with nothing popped · --any pops the newest park of anyone (crash recovery,
  # explicit) · nothing parked at all → friendly note, rc 0. A pop conflict preserves the stash
  # and dies honestly with the by-hand remedy.
  local any=0; [ "${1:-}" = "--any" ] && any=1
  local me="${CLAUDE_CODE_SESSION_ID:-}"; me="${me:+${me:0:8}}"; me="${me:-$PPID}"
  local all line n
  all="$(git -C "$PRIMARY" stash list --format='%gd %gs' 2>/dev/null | grep 'polaris/park-' || true)"
  if [ -z "$all" ]; then note "nothing parked"; return 0; fi
  if [ "$any" -eq 1 ]; then
    line="$(printf '%s\n' "$all" | head -1)"
  else
    line="$(printf '%s\n' "$all" | grep -E "polaris/park-[0-9]+-$me( |\$)" | head -1 || true)"
  fi
  if [ -z "$line" ]; then
    n="$(printf '%s\n' "$all" | grep -c .)"
    note "nothing parked by this session — $n park(s) by other sessions exist; bash ops/polaris unpark --any pops the newest of anyone"
    return 0
  fi
  local ref="${line%% *}"
  local what="${line#* }"
  git -C "$PRIMARY" stash pop -q "$ref" \
    || die "unpark failed (conflict?) — the stash is preserved; resolve by hand: git -C \"$PRIMARY\" stash pop $ref"
  say "unparked: restored $what"
  return 0
}

cmd_park() { # polaris park [-m why] — CLI wrapper: park the primary's dirty tree (tracked +
  # untracked) as a named polaris/park-<epoch>-<sid8|pid> stash. Reverse: polaris unpark.
  local why=""
  if [ "${1:-}" = "-m" ]; then why="${2:-}"; fi
  park "$why" || die "park failed — git stash push refused; the tree is untouched"
}

cmd_unpark() { # polaris unpark [--any] — CLI wrapper: restore OUR newest polaris/park-* stash
  # (--any: the newest of anyone).
  unpark "$@"
}
