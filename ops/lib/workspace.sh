# POLARIS lib/workspace.sh — shared-checkout mechanics sourced by ops/polaris (the lib loader):
# branch-ID hygiene, worktree add, stray-feat repair, the integration lease, wave adoption, park.

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

wt_add() { # wt_add <ID> — shared worktree-add for claim/resume: .polaris/wt/<ID> on feat/<ID>
  # (existing branch reused, else -b from $BASE). stderr is CAPTURED to a temp file — never
  # 2>/dev/null: retry (7 × 0.3s) ONLY when it mentions index.lock (two near-simultaneous claims
  # — exactly a fleet's panes — collide on git's one index.lock, and each adds a DIFFERENT tree,
  # so a brief retry is safe); a stray ref literally named `feat` → ONE stray_feat_repair, then
  # one more try; anything else re-emits the captured stderr verbatim and dies. Prints nothing
  # on success.
  local id="$1"
  local wt; wt="$(wt_path "$id")"
  local errf; errf="$(mktemp)"
  local tries=0
  local repaired=0
  local rc
  mkdir -p "$PRIMARY/.polaris/wt"
  while :; do
    rc=0
    if git -C "$PRIMARY" show-ref --verify -q "refs/heads/feat/$id"; then
      git -C "$PRIMARY" worktree add -q "$wt" "feat/$id" 2>"$errf" || rc=$?
    else
      git -C "$PRIMARY" worktree add -q "$wt" -b "feat/$id" "$BASE" 2>"$errf" || rc=$?
    fi
    if [ "$rc" -eq 0 ]; then rm -f "$errf"; return 0; fi
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

int_on() { # int_on [<why>] — take the integration lease $LOCKS/.int-lease (the board-mutex
  # pattern: atomic mkdir + epoch/who/pid files). Integration is ONE shared lane: whoever holds
  # the lease lands everything; a second session waits briefly or queues. Busy → poll every 2s,
  # progress note ~every 30s naming holder + age; holder epoch older than
  # integration_stale_minutes (default 45) → steal with a note; still busy after
  # integration_wait_minutes (default 10) → print ONE final line beginning `queued: ` + rc 3 —
  # NEVER a question, NEVER a raw die. Re-entrant: already ours (same pid file) → rc 0.
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
  local now e hage holder
  until mkdir "$lease" 2>/dev/null; do
    now="$(date +%s)"
    e="$(cat "$lease/epoch" 2>/dev/null || true)"
    case "$e" in ''|*[!0-9]*) e="$now";; esac
    hage=$(( now - e ))
    holder="$(cat "$lease/who" 2>/dev/null || true)"; holder="${holder:-unknown}"
    if [ "$hage" -gt $(( sm * 60 )) ]; then
      note "stealing stale integration lease held by $holder ($(( hage / 60 ))m > ${sm}m stale limit)"
      rm -rf "$lease"; continue
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
  # named stash polaris/park-<epoch>: a dirty shared checkout is parked, never asked about, and
  # unpark reverses it in one command. Nothing to park → friendly note, rc 0. Stash refused →
  # rc 1 with the tree untouched (the caller falls back to its dirty-tree die).
  local why="${1:-}"
  local epoch; epoch="$(date +%s)"
  local name="polaris/park-$epoch"
  if [ -z "$(git -C "$PRIMARY" status --porcelain 2>/dev/null)" ]; then
    note "nothing to park — the tree is clean"
    return 0
  fi
  git -C "$PRIMARY" stash push -q --include-untracked -m "$name${why:+ — $why}" || return 1
  say "parked as $name — bash ops/polaris unpark returns it"
  return 0
}

unpark() { # pop the NEWEST polaris/park-* stash — the one-command reverse of park. Says what was
  # restored; nothing parked → friendly note, rc 0. A pop conflict preserves the stash and dies
  # honestly with the by-hand remedy.
  local line
  line="$(git -C "$PRIMARY" stash list --format='%gd %gs' 2>/dev/null | grep 'polaris/park-' | head -1 || true)"
  if [ -z "$line" ]; then note "nothing parked"; return 0; fi
  local ref="${line%% *}"
  local what="${line#* }"
  git -C "$PRIMARY" stash pop -q "$ref" \
    || die "unpark failed (conflict?) — the stash is preserved; resolve by hand: git -C \"$PRIMARY\" stash pop $ref"
  say "unparked: restored $what"
  return 0
}

cmd_park() { # polaris park [-m why] — CLI wrapper: park the primary's dirty tree (tracked +
  # untracked) as a named polaris/park-<epoch> stash. Reverse: polaris unpark.
  local why=""
  if [ "${1:-}" = "-m" ]; then why="${2:-}"; fi
  park "$why" || die "park failed — git stash push refused; the tree is untouched"
}

cmd_unpark() { # polaris unpark — CLI wrapper: restore the newest polaris/park-* stash.
  unpark
}
