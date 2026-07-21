# POLARIS lib/observe.sh — read-only observers sourced by ops/polaris (the lib loader): notify-gate,
# status/--brief, sweep, doctor, drift, rules, qa, metrics, why, dash, and fleet.

cmd_notify_gate() { # notify-gate <kind> [ID] — fire the notify: hook at a HUMAN GATE, and do
  # nothing else. Conductor calls it when the run starts waiting on a person; it is ADDITIVE to
  # the in-conversation gate, never a substitute. Kinds (ops/contracts/hands-free-knobs.md):
  #   plan          EV=waiting  NOTE=plan-gate         SEVERITY=gate   (no ID)
  #   risk <ID>     EV=waiting  NOTE=risk-approval     SEVERITY=gate
  #   question <ID> EV=waiting  NOTE=builder-question  SEVERITY=gate
  #   done [ID]     EV=run-done NOTE=run-done          SEVERITY=done
  # Observe-only by contract: NEVER calls evt(), appends EVENTS.ndjson, takes the board mutex,
  # moves/edits a board file, or commits. No notify: configured → rc 0, silent.
  local kind="${1:-}" id="${2:-}" ev nt sev
  local u="usage: polaris notify-gate <plan | risk <ID> | question <ID> | done [ID]>"
  case "$kind" in
    plan)     ev="waiting"; nt="plan-gate"; sev="gate"; id="";;
    risk)     [ -n "$id" ] || die "$u"; ev="waiting"; nt="risk-approval"; sev="gate";;
    question) [ -n "$id" ] || die "$u"; ev="waiting"; nt="builder-question"; sev="gate";;
    done)     ev="run-done"; nt="run-done"; sev="done";;
    *)        die "$u";;
  esac
  notify_fire "$ev" "$id" "$nt" "$sev"
}

status_brief() { # `status --brief` — ONE plain-English paragraph, no table (ops/contracts/status-brief.md).
  # voice: standard, no jargon. Grep-stable markers, written VERBATIM: "Last landed:" and "Next up:".
  local done_c active_c review_c ready_c ids f parts lead line2 newest ntitle top nextup n
  done_c=$(ls "$BOARD/done" 2>/dev/null | grep -c '\.md$' || true)
  active_c=$(ls "$BOARD/active" 2>/dev/null | grep -c '\.md$' || true)
  review_c=$(ls "$BOARD/review" 2>/dev/null | grep -c '\.md$' || true)
  ready_c=$(ls "$BOARD/ready" 2>/dev/null | grep -c '\.md$' || true)
  ids=""
  for f in "$BOARD/active/"*.md; do [ -e "$f" ] || break
    ids="${ids:+$ids, }$(basename "$f" .md)"
  done
  # each ·-joined sub-clause is DROPPED when its count is 0 (nothing to say), never zero-padded
  parts=""
  [ "$done_c"   -gt 0 ] && parts="${parts:+$parts · }$done_c done"
  [ "$active_c" -gt 0 ] && parts="${parts:+$parts · }$active_c building${ids:+ ($ids)}"
  [ "$review_c" -gt 0 ] && parts="${parts:+$parts · }$review_c waiting to land"
  [ "$ready_c"  -gt 0 ] && parts="${parts:+$parts · }$ready_c queued"
  [ -n "$parts" ] || parts="Nothing building"
  n="$(sprint_hdr_num)"
  if [ -n "$n" ]; then lead="Sprint $n ($(sprint_goal "$n")):"; else lead="No sprint header —"; fi
  printf '%s %s.\n' "$lead" "$parts"
  # line two: newest done (highest-mtime file) + top-wsjf ready; each dropped when there is none
  line2=""
  newest="$(ls -t "$BOARD/done/"*.md 2>/dev/null | head -1)"
  if [ -n "$newest" ]; then
    ntitle="$(fm_get title "$newest")"
    line2="Last landed: ${ntitle:-$(basename "$newest" .md)}."
  fi
  top="$( { for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
      printf '%s\t%s\n' "$(fm_get wsjf "$f")" "$f"
    done; } | sort -rn | head -1 | cut -f2- )"
  if [ -n "$top" ]; then
    nextup="$(fm_get title "$top")"
    line2="${line2:+$line2 }Next up: ${nextup:-$(basename "$top" .md)}."
  fi
  [ -n "$line2" ] && printf '%s\n' "$line2"
  return 0
}

cmd_status() {
  [ "${1:-}" = "--brief" ] && { status_brief; return; }
  local col n
  printf 'POLARIS board — base: %s · claim: %s\n' "$BASE" "$CLAIM_MODE"
  for col in backlog ready active review blocked done; do
    n=$(ls "$BOARD/$col" 2>/dev/null | grep -c '\.md$' || true)
    printf '  %-8s %s\n' "$col" "$n"
  done
  echo 'active:'
  local f id age
  for f in "$BOARD/active/"*.md; do
    [ -e "$f" ] || { echo '  (none)'; break; }
    id="$(basename "$f" .md)"; age="$(lock_age "$id")"
    printf '  %s · %s · lock age %ss%s\n' "$id" "$(fm_get owner "$f")" "${age:-?}" \
      "$( [ -n "${age:-}" ] && [ "$age" -gt $((STALE_H*3600)) ] && echo " ⚠ STALE — polaris resume $id to take over, or release")"
  done
  echo 'ready (top by wsjf):'
  { for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
      printf '%s\t%s · %spts · wsjf %s\n' "$(fm_get wsjf "$f")" "$(basename "$f" .md)" \
        "$(fm_get points "$f")" "$(fm_get wsjf "$f")"
    done; } | sort -rn | cut -f2- | head -5
  # blocked tasks are owned by no role until drained — surface them WITH the reason so they stop
  # being invisible (Integrator regrooms or escalates them; see INTEGRATOR.md).
  local bf bid any=0
  for bf in "$BOARD/blocked/"*.md; do [ -e "$bf" ] || break
    [ "$any" -eq 0 ] && echo 'blocked (needs regroom/escalation):'
    any=1; bid="$(basename "$bf" .md)"
    printf '  %s · %s\n' "$bid" "$(grep '⛔' "$bf" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*-*[[:space:]]*//' | grep . || echo 'no reason recorded — open the task')"
  done
}

cmd_sweep() { # report orphans + stale + remote strays; --fix removes true orphans and merged strays
  local fix="${1:-}" d id found=0
  for d in "$LOCKS"/*/; do
    [ -e "$d" ] || break
    id="$(basename "$d")"; [ "$id" = ".board-mutex" ] && continue
    if ! task_file "$id" active >/dev/null && ! task_file "$id" review >/dev/null; then
      found=1; printf '⚠ ORPHAN lock: %s (age %sh, no active/review task)\n' "$id" "$(( $(lock_age "$id") / 3600 ))"
      [ "$fix" = "--fix" ] && { lock_drop "$id"; note "removed"; }
    elif task_file "$id" active >/dev/null && [ "$(lock_age "$id")" -gt $((STALE_H*3600)) ]; then
      found=1; printf '⚠ STALE lock: %s (%ss > %sh) — take it over: polaris resume %s · or hand back: polaris release %s --to ready\n' \
        "$id" "$(lock_age "$id")" "$STALE_H" "$id" "$id"
    fi
  done
  # remote hygiene: a landed task should have taken its feat/<ID> branch with it (done does this
  # since 5.11). This pass catches strays from before — or from any path that skipped `done`.
  # Only branches whose task is in done/ are touched; active/review branches are live work.
  if has_remote; then
    local rline rsha rref rid lsha lf
    while IFS= read -r rline; do
      [ -n "$rline" ] || continue
      rsha="${rline%%$'\t'*}"; rref="${rline#*$'\t'}"
      case "$rref" in refs/heads/feat/*) rid="${rref#refs/heads/feat/}";; *) continue;; esac
      [ -f "$BOARD/done/$rid.md" ] || continue
      # deletable iff the remote tip is provably what we landed. Squash landings (polaris land)
      # are never ancestors of $BASE, so the proof is TIP EQUALITY with the squash commit's
      # Landed-from trailer; the ancestor check stays as the legacy proof for hand merges.
      lsha="$(fm_get landed "$BOARD/done/$rid.md" 2>/dev/null || true)"
      [ -n "$lsha" ] || lsha="$(landed_sha "$rid" || true)"
      lf=""
      [ -n "$lsha" ] && lf="$(git -C "$PRIMARY" log -1 --format=%B "$lsha" 2>/dev/null | sed -n 's/^Landed-from: *//p' | head -1 | tr -d ' \r' || true)"
      if [ -n "$lf" ] && [ "$rsha" = "$lf" ]; then
        found=1; printf '⚠ REMOTE stray: feat/%s — task done (landed %.7s), branch still on origin\n' "$rid" "$lsha"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/feat/$rid" && note "deleted"; }
      elif git -C "$PRIMARY" cat-file -e "$rsha" 2>/dev/null \
         && git -C "$PRIMARY" merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
        found=1; printf '⚠ REMOTE stray: feat/%s — task done, branch fully merged, still on origin\n' "$rid"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/feat/$rid" && note "deleted"; }
      else
        found=1; printf '⚠ REMOTE diverged: feat/%s — task done but the remote tip is NOT in %s. Inspect: git fetch origin feat/%s && git log %s..FETCH_HEAD (never auto-deleted)\n' \
          "$rid" "$BASE" "$rid" "$BASE"
      fi
    done <<EOF
$(git -C "$PRIMARY" ls-remote origin 'refs/heads/feat/*' 2>/dev/null)
EOF
    # integrate/<date> branches on origin: a wave whose merge is already in $BASE (tip an ancestor
    # of $BASE) is a stray — seal --sync deletes it in pr mode, but direct-mode seals never owned
    # the push and a skipped --sync leaves it forever. Merged → stray (--fix deletes); tip not in
    # $BASE → diverged, flagged but NEVER auto-deleted. Same style as the feat/* pass above.
    while IFS= read -r rline; do
      [ -n "$rline" ] || continue
      rsha="${rline%%$'\t'*}"; rref="${rline#*$'\t'}"
      case "$rref" in refs/heads/integrate/*) rid="${rref#refs/heads/}";; *) continue;; esac
      if git -C "$PRIMARY" cat-file -e "$rsha" 2>/dev/null \
         && git -C "$PRIMARY" merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
        found=1; printf '⚠ REMOTE stray: %s — wave merged into %s, branch still on origin\n' "$rid" "$BASE"
        [ "$fix" = "--fix" ] && { git -C "$PRIMARY" push -q origin ":refs/heads/$rid" && note "deleted"; }
      else
        found=1; printf '⚠ REMOTE diverged: %s — tip is NOT in %s. Inspect: git fetch origin %s && git log %s..FETCH_HEAD (never auto-deleted)\n' \
          "$rid" "$BASE" "$rid" "$BASE"
      fi
    done <<EOF
$(git -C "$PRIMARY" ls-remote origin 'refs/heads/integrate/*' 2>/dev/null)
EOF
  fi
  if [ $found -eq 0 ]; then say "no orphan or stale locks, no remote strays"; fi
}

cmd_doctor() {
  local gv; gv="$(git --version | sed 's/[^0-9.]*\([0-9][0-9.]*\).*/\1/')"
  say "git $gv · primary: $PRIMARY · locks: $LOCKS"
  awk -v v="$gv" 'BEGIN{split(v,a,"."); exit !(a[1]>2 || (a[1]==2 && a[2]>=5))}' \
    || die "git >= 2.5 required for worktrees"
  git -C "$PRIMARY" show-ref --verify -q "refs/heads/$BASE" || note "⚠ base branch '$BASE' not found — set base: in CONVENTIONS.md"
  board_materialize || true   # fresh clone: ops/board/ missing + polaris/board present → rebuild it
  # CONVENTIONS.md is written by INIT and by nothing else — its absence is THE test for
  # "INIT never ran here". install.sh, CLAUDE.md's role dispatch and INIT.md all use this
  # same file for that question. Never ops/board/: an older installer shipped it empty.
  if [ -f "$CONV" ]; then
    # `update` never rewrites CONVENTIONS.md, so a pre-5.2 board has no voice: line — print the
    # effective value either way, or the knob is undiscoverable for exactly the repos that want it.
    note "voice: $(cfg voice standard) — how agents talk to you (standard | technical; set in CONVENTIONS.md)"
  else
    note "⚠ ops/CONVENTIONS.md missing — INIT has not run in this repo. Say: \"You are INIT.\" (no new session needed)"
  fi
  # v5.13 autonomy knobs (ops/contracts/hands-free-knobs.md). Silence = every default = today's
  # behavior, so print the EFFECTIVE composition only when a knob is set. Precedence per contract:
  # explicit knob > autonomy: trusted > default. Unknown values warn and behave as the default
  # (fail closed to today). `autonomy` composes only the three gate knobs — never drain.
  local a pg bq ea dr ds trusted=0
  a="$(cfg autonomy "")"; pg="$(cfg plan_gate "")"; bq="$(cfg builder_questions "")"
  ea="$(cfg evolve_apply "")"; dr="$(cfg drain "")"; ds="$(cfg drain_slices "")"
  if [ -n "$a$pg$bq$ea$dr$ds" ]; then
    if [ "$a" = "trusted" ]; then trusted=1
    elif [ -n "$a" ] && [ "$a" != "standard" ]; then
      note "⚠ autonomy: '$a' unknown (standard | trusted) — behaving as standard"; a="standard"
    fi
    if [ -n "$pg" ] && [ "$pg" != "confirm" ] && [ "$pg" != "auto" ]; then
      note "⚠ plan_gate: '$pg' unknown (confirm | auto) — behaving as the default"; pg=""
    fi
    if [ -z "$pg" ]; then if [ "$trusted" -eq 1 ]; then pg="auto"; else pg="confirm"; fi; fi
    if [ -n "$bq" ] && [ "$bq" != "ask" ] && [ "$bq" != "default-safe" ]; then
      note "⚠ builder_questions: '$bq' unknown (ask | default-safe) — behaving as the default"; bq=""
    fi
    if [ -z "$bq" ]; then if [ "$trusted" -eq 1 ]; then bq="default-safe"; else bq="ask"; fi; fi
    if [ -n "$ea" ] && [ "$ea" != "confirm" ] && [ "$ea" != "auto-reversible" ]; then
      note "⚠ evolve_apply: '$ea' unknown (confirm | auto-reversible) — behaving as the default"; ea=""
    fi
    if [ -z "$ea" ]; then if [ "$trusted" -eq 1 ]; then ea="auto-reversible"; else ea="confirm"; fi; fi
    note "autonomy: ${a:-standard} → plan_gate=$pg · builder_questions=$bq · evolve_apply=$ea (explicit > autonomy > default)"
    if [ -n "$dr$ds" ]; then
      if [ -n "$dr" ] && [ "$dr" != "queue" ] && [ "$dr" != "plan" ] && [ "$dr" != "backlog" ]; then
        note "⚠ drain: '$dr' unknown (queue | plan | backlog) — behaving as the default"; dr=""
      fi
      case "$ds" in *[!0-9]*) note "⚠ drain_slices: '$ds' not a number — behaving as 2"; ds="";; esac
      note "drain: ${dr:-queue} · drain_slices: ${ds:-2} (autonomy never composes drain)"
    fi
  fi
  mkdir -p "$LOCKS" && [ -w "$LOCKS" ] || die "lock dir not writable: $LOCKS"
  case "$(git -C "$PRIMARY" remote get-url origin 2>/dev/null)" in .*|../*) note "⚠ origin is a RELATIVE path — breaks in worktrees; use an absolute URL";; esac
  case "$CLAIM_MODE" in local-lock|claim-branch) :;; *) die "claim: must be local-lock or claim-branch";; esac
  [ "$CLAIM_MODE" = "claim-branch" ] && ! has_remote && note "⚠ claim-branch set but no origin remote"
  # base-push-rejected stamp (ops/contracts/publish-modes.md): a direct-mode seal that keeps hitting
  # a protected $BASE records each rejection; >=2 → recommend publish: pr. No stamp / <2 → silent.
  local bprc=0
  [ -f "$PRIMARY/.polaris/base-push-rejected" ] && bprc="$(awk 'NR==1{print $2+0}' "$PRIMARY/.polaris/base-push-rejected" 2>/dev/null)"
  [ "${bprc:-0}" -ge 2 ] && note "⚠ origin keeps rejecting pushes to $BASE — protected branch? set publish: pr in ops/CONVENTIONS.md"
  [ -f "$EVENTS" ] && ! grep -q 'EVENTS\.ndjson merge=union' "$PRIMARY/.gitattributes" 2>/dev/null \
    && note "⚠ EVENTS.ndjson exists without its union-merge gitattribute — run: ops/polaris upgrade"
  # `ver` exits 0 with empty output when a key is absent, so || can't catch it — grep can.
  # The kit repo's own VERSION is unstamped on purpose: pack.py stamps the emitted copy.
  [ -f "$VER" ] && note "POLARIS v$(ver version) ($(ver commit | grep . || echo unstamped))"
  # Self-hosting repo only (kit/ops/pack.py is the tell — ops/contracts/self-hosting.md): the one
  # skew that matters here is kit/ops/VERSION ahead of ops/VERSION — a release built but never
  # run, while the channel keeps serving the old kit. CI catches it daily; this shows the human.
  if [ -f "$PRIMARY/kit/ops/pack.py" ]; then
    local kv iv
    kv="$(ver version "$PRIMARY/kit/ops/VERSION" 2>/dev/null || true)"
    iv="$(ver version 2>/dev/null || true)"
    if [ -n "$kv" ] && [ "$kv" = "$iv" ]; then
      say "self-hosting: kit $kv = installed $iv — this repo runs the POLARIS it ships"
    else
      note "⚠ self-hosting: kit/ops/VERSION is ${kv:-missing} but ops/ runs ${iv:-unknown} — that release has NOT been dogfooded. Run: python kit/ops/pack.py --dogfood"
    fi
  fi
  # Self-hosting repo only (kit/ops/pack.py is the tell — ops/contracts/self-hosting.md): the
  # shipped zip going stale is exactly how the last one rotted. Was gated on $OPS/pack.py
  # (ops/pack.py) — a pre-split path that no longer exists post kit/ split, so this warning could
  # never fire. Gate on the same tell every other self-hosting check uses.
  if [ -f "$PRIMARY/kit/ops/pack.py" ] && [ -f "$PRIMARY/polaris-v5.zip" ] && command -v unzip >/dev/null 2>&1; then
    local zsha head
    zsha="$(unzip -p "$PRIMARY/polaris-v5.zip" polaris-v5/ops/VERSION 2>/dev/null | sed -n 's/^commit: *//p' | head -1 || true)"
    head="$(git -C "$PRIMARY" rev-parse --short HEAD 2>/dev/null || true)"
    [ -n "$zsha" ] && [ "$zsha" != "$head" ] \
      && note "⚠ polaris-v5.zip is STALE (built at $zsha, HEAD is $head) — rebuild: python kit/ops/pack.py"
  fi
  # commit-msg hook: the no-AI-fingerprints guarantee (ops/hooks/commit-msg). Self-heal here
  # because clones never carry .git/hooks — without this, every fresh clone silently loses it.
  if [ -f "$OPS/hooks/commit-msg" ]; then
    if [ -n "$(git -C "$PRIMARY" config --get core.hooksPath 2>/dev/null || true)" ]; then
      note "⚠ core.hooksPath is set — wire ops/hooks/commit-msg into your hooks dir by hand (it strips AI attribution from commits)"
    else
      local hk="$GCD/hooks/commit-msg"
      if [ ! -f "$hk" ]; then
        mkdir -p "$GCD/hooks"; cp "$OPS/hooks/commit-msg" "$hk"; chmod +x "$hk" 2>/dev/null || true
        say "commit-msg hook installed — AI attribution is stripped from every commit"
      elif grep -q 'POLARIS commit-msg' "$hk" 2>/dev/null; then
        cp "$OPS/hooks/commit-msg" "$hk"; chmod +x "$hk" 2>/dev/null || true
      else
        note "⚠ a non-POLARIS commit-msg hook is installed — chain ops/hooks/commit-msg into it by hand"
      fi
    fi
  fi
  # brain freshness (ops/contracts/brain.md): board-changed newer than the brain's stamp → the
  # digest lies. No brain dir → the feature was never opted into → stay silent.
  if [ -d "$PRIMARY/.polaris/brain" ] \
     && [ "$PRIMARY/.polaris/board-changed" -nt "$PRIMARY/.polaris/brain/.stamp" ]; then
    note "⚠ brain is stale — refresh it: ops/polaris brain --refresh"
  fi
  say "doctor: OK"
  # --selftest [--only <patterns>] [--parallel <N>] (ops/contracts/verification-tiering.md +
  # ops/contracts/selftest-sharding.md): --only runs the always-on spine + just the labeled drills
  # matching ANY comma-separated shell glob; --parallel shards the selected labels into N child
  # re-invocations. First occurrence of each flag wins; other trailing args stay ignored, exactly
  # as the pre-split parser (which never read past $3) ignored them.
  if [ "${1:-}" = "--selftest" ]; then
    local _only="" _par="" _a
    shift
    case "${1:-}" in
      ""|--only|--only=*|--parallel|--parallel=*) : ;;
      *) die "doctor --selftest: unknown option '$1' (only --only <pattern>)";;
    esac
    while [ $# -gt 0 ]; do
      _a="$1"; shift
      case "$_a" in
        --only)   if [ -z "$_only" ]; then _only="${1:-}"; [ -n "$_only" ] || die "doctor --selftest --only needs a pattern"; shift; fi;;
        --only=*) if [ -z "$_only" ]; then _only="${_a#--only=}"; [ -n "$_only" ] || die "doctor --selftest --only needs a pattern"; fi;;
        --parallel)   if [ -z "$_par" ]; then _par="${1:-}"; case "$_par" in ''|*[!0-9]*) die "--parallel needs an integer >= 2";; esac; [ "$_par" -ge 2 ] || die "--parallel needs an integer >= 2"; shift; fi;;
        --parallel=*) if [ -z "$_par" ]; then _par="${_a#--parallel=}"; case "$_par" in ''|*[!0-9]*) die "--parallel needs an integer >= 2";; esac; [ "$_par" -ge 2 ] || die "--parallel needs an integer >= 2"; fi;;
        *) : ;;
      esac
    done
    selftest "$_only" "$_par"
  fi
}


pat_overlap() { # heuristic: can patterns A and B claim a common path?
  # Proves: identical · exact⊂glob · exact⊂dir/ · dir/⊂dir/ · glob∩glob with nested literal dirs.
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  printf '%s\n' "$b" | owned_match "$a" && return 0   # pattern B matches A taken as a literal path
  printf '%s\n' "$a" | owned_match "$b" && return 0   # pattern A matches B taken as a literal path
  case "$a" in */) case "$b" in "$a"*) return 0;; esac;; esac
  case "$b" in */) case "$a" in "$b"*) return 0;; esac;; esac
  # glob ∩ glob: exact intersection is undecidable, but the collision that bites in practice is
  # two globs whose literal directory prefixes nest (src/api/* vs src/*/handler.js → both can
  # match src/api/handler.js). Flag conservatively — a false "verify this" beats a missed clash.
  case "$a" in *"*"*) case "$b" in *"*"*)
    local la lb
    la="${a%%\**}"; la="${la%/*}"   # dir prefix up to the segment before the first glob
    lb="${b%%\**}"; lb="${lb%/*}"
    [ "$la" = "$lb" ] && return 0
    case "$lb/" in "$la"/*) return 0;; esac
    case "$la/" in "$lb"/*) return 0;; esac
  ;; esac;; esac
  return 1
}

dep_ids() { # dep_ids <taskfile> — depends_on entries as clean ids, handling BOTH block lists
  # ("- T-002") and the inline form ("[T-002, T-003]"). The sed bracket-expression strips [ ] and ,
  # portably — BSD tr (macOS) mishandles a bare '[]' set, so `tr -d '[]'` is NOT portable here.
  fm_list depends_on "$1" 2>/dev/null | sed 's/[][,]/ /g' | tr ' ' '\n' | grep -v '^[[:space:]]*$' || true
}
dep_reaches() { # dep_reaches <cur-id> <target-id> <visited> — 0 if target is reachable from cur via
  # depends_on. A task that reaches ITSELF sits in a cycle and can never satisfy the ready gate.
  local cur="$1" target="$2" visited="$3" f d
  f="$(task_file "$cur")" || return 1
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    [ "$d" = "$target" ] && return 0
    case " $visited " in *" $d "*) continue;; esac
    dep_reaches "$d" "$target" "$visited $d" && return 0
  done <<EOF
$(dep_ids "$f")
EOF
  return 1
}

cmd_drift() { # mechanical hygiene audit — the invariants, machine-checked. --strict: rc 1 on findings
  local strict="${1:-}" n=0 f g id id2 v d
  finding() { n=$((n+1)); printf '⚠ [%d] %s\n' "$n" "$1"; }
  # 1) THE invariant: files_owned disjoint across ready ∪ active (heuristic, see pat_overlap)
  local claimable=""; for d in ready active; do
    for f in "$BOARD/$d/"*.md; do [ -e "$f" ] || break; claimable="$claimable$f
"; done; done
  local seen=""
  while IFS= read -r f; do [ -z "$f" ] && continue
    while IFS= read -r g; do [ -z "$g" ] && continue
      id="$(basename "$f" .md)"; id2="$(basename "$g" .md)"
      local pa pb
      while IFS= read -r pa; do [ -z "$pa" ] && continue
        while IFS= read -r pb; do [ -z "$pb" ] && continue
          if pat_overlap "$pa" "$pb"; then
            finding "OWNERSHIP OVERLAP: $id ∩ $id2 on '$pa' / '$pb' — chain them (depends_on), never parallel"
          fi
        done <<EOF2
$(fm_list files_owned "$g")
EOF2
      done <<EOF1
$(fm_list files_owned "$f")
EOF1
    done <<EOF0
$seen
EOF0
    seen="$seen$f
"
  done <<EOF
$claimable
EOF
  # 2) ready-gate: contract exists · deps all done · ≤5 points
  for f in "$BOARD/ready/"*.md; do [ -e "$f" ] || break
    id="$(basename "$f" .md)"
    v="$(fm_get contract "$f")"
    { [ -z "$v" ] || [ ! -f "$PRIMARY/$v" ]; } && finding "READY GATE: $id contract missing (${v:-unset}) — blocked/, not ready/"
    while IFS= read -r d; do [ -z "$d" ] && continue
      task_file "$d" done >/dev/null || finding "READY GATE: $id depends_on $d which is NOT in done/"
    done <<EOF
$(dep_ids "$f")
EOF
    v="$(fm_get points "$f")"; case "$v" in 8|13) finding "READY GATE: $id is ${v}pts — must be split before ready/";; esac
  done
  # 3) cruft: done tasks whose feat branch survived
  for f in "$BOARD/done/"*.md; do [ -e "$f" ] || break
    id="$(basename "$f" .md)"
    git -C "$PRIMARY" show-ref --verify -q "refs/heads/feat/$id" \
      && finding "CRUFT: feat/$id still exists though $id is done — git branch -D feat/$id"
  done
  # 4) stale forward refs: TODO(T-…) pointing at tasks already done
  local refs; refs="$(grep -RIn 'TODO([A-Za-z][A-Za-z0-9._-]*-[0-9A-Za-z]' "$BOARD" "$OPS/contracts" "$OPS/SPRINT.md" "$OPS/MAP.md" 2>/dev/null || true)"
  while IFS= read -r v; do [ -z "$v" ] && continue
    id="$(printf '%s' "$v" | sed -n 's/.*TODO(\([A-Za-z][A-Za-z0-9._-]*-[0-9A-Za-z][0-9A-Za-z]*\)).*/\1/p')"
    [ -n "$id" ] && task_file "$id" done >/dev/null \
      && finding "STALE REF: $(printf '%s' "$v" | cut -d: -f1,2) — $id is done; update the text"
  done <<EOF
$refs
EOF
  # 5) doc overflow: MAP Deltas tail + Learned log
  v="$(grep -Ec ' \([A-Za-z0-9._-]+, [0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$OPS/MAP.md" 2>/dev/null || true)"
  [ "${v:-0}" -gt 20 ] && finding "MAP: $v delta lines — fold them into the sections (EVOLVE target)"
  v="$(awk '/^##[ \t]*Learned/{on=1;next} on&&/^## /{exit} on&&/^[ \t]*[-*]/{c++} END{print c+0}' "$OPS/SPRINT.md" 2>/dev/null || true)"
  [ "${v:-0}" -gt 8 ] && finding "LEARNED: $v bullets — prune to ≤5 carry-overs (EVOLVE target)"
  # 6) telemetry safety
  [ -f "$EVENTS" ] && ! grep -q 'EVENTS\.ndjson merge=union' "$PRIMARY/.gitattributes" 2>/dev/null \
    && finding "TELEMETRY: EVENTS.ndjson without union-merge gitattribute — run: ops/polaris upgrade"
  # 7) dependency graph across ALL columns: deps that exist nowhere + cycles (a ring never promotes)
  local col2 idf d2
  for col2 in backlog ready active review blocked done; do
    for idf in "$BOARD/$col2/"*.md; do [ -e "$idf" ] || break
      id="$(basename "$idf" .md)"
      while IFS= read -r d2; do [ -z "$d2" ] && continue
        task_file "$d2" >/dev/null || finding "DEP MISSING: $id depends_on $d2 — no task by that id in any column"
      done <<EOF
$(dep_ids "$idf")
EOF
      dep_reaches "$id" "$id" "" && finding "DEP CYCLE: $id sits in a depends_on ring — it can never satisfy the ready gate; break the cycle"
    done
  done
  if [ "$n" -eq 0 ]; then say "drift: board clean (overlap · ready gate · cruft · stale refs · doc overflow · telemetry · deps)"
  else printf '%d finding(s).\n' "$n"; [ "$strict" = "--strict" ] && exit 1; fi
  return 0
}

cmd_rules() { # list + health-check ops/RULES.tsv
  if ! rules_lines | grep -q .; then note "no rules yet — ops/RULES.tsv (INIT seeds danger zones; EVOLVE proposes more)"; return 0; fi
  local scope kind pat msg n=0 bad=0
  printf '%-28s %-8s %-24s %s\n' 'SCOPE' 'KIND' 'PATTERN' 'MESSAGE'
  while IFS="$(printf '\t')" read -r scope kind pat msg; do
    n=$((n+1)); printf '%-28s %-8s %-24s %s\n' "$scope" "$kind" "${pat:--}" "$msg"
    case "$kind" in path|content) :;; *) bad=1; printf '   ⛔ bad kind (want path|content)\n';; esac
    [ -z "$scope" ] && { bad=1; printf '   ⛔ empty scope\n'; }
    if [ "$kind" = "content" ]; then
      { [ -z "$pat" ] || [ "$pat" = "-" ]; } && { bad=1; printf '   ⛔ content rule needs an ERE pattern\n'; }
      local rc=0; grep -E -e "${pat:-x}" /dev/null >/dev/null 2>&1 || rc=$?
      [ "$rc" -eq 2 ] && { bad=1; printf '   ⛔ pattern does not compile (grep -E)\n'; }
    fi
  done <<EOF
$(rules_lines)
EOF
  [ "$bad" -eq 0 ] && say "$n rule(s), all healthy" || die "rules health check failed — fix ops/RULES.tsv"
}

cmd_qa() { # qa — ONE answer to "is everything okay?": the full CONVENTIONS suite (test/lint/
  # typecheck/build, uat if set), then drift --strict, then doctor's env check. Runs EVERY
  # check even after a red — one pass paints the whole picture — and exits 1 if anything was
  # red. The Conductor runs it after integration (a subagent's "green" is never taken on
  # faith), the Integrator runs it before reporting, CI and humans run it whenever.
  local red=0 ran=0 k c out
  local t0 t1
  t0="$(date +%s)"
  out="$(mktemp)"
  for k in test lint typecheck build uat; do
    c="$(cfg "$k" "")"
    [ -z "$c" ] && continue
    ran=$((ran+1))
    if ( cd "$PRIMARY" && bash -c "$c" ) >"$out" 2>&1; then
      say "$k — green"
    else
      printf '⛔ %s — RED: %s\n' "$k" "$c"
      tail -15 "$out" | sed 's/^/     /'
      red=1
    fi
  done
  # T-031 (ops/contracts/verification-tiering.md): stamp how long the suite took — one line,
  # "<seconds> <epoch>", written only when ≥1 suite command actually ran. `land` reads it for
  # the slow-suite hint; purely advisory, never a gate, best-effort write.
  if [ "$ran" -ge 1 ]; then
    t1="$(date +%s)"
    mkdir -p "$PRIMARY/.polaris" 2>/dev/null || true
    printf '%s %s\n' "$((t1 - t0))" "$t1" > "$PRIMARY/.polaris/last-suite-seconds" 2>/dev/null || true
  fi
  [ "$ran" -eq 0 ] && note "no test/lint/typecheck/build/uat in CONVENTIONS.md — only board + env checked"
  # drift --strict exits the script on findings, so both sub-checks run in subshells.
  if ( cmd_drift --strict ) >"$out" 2>&1; then
    say "drift — board clean"
  else
    printf '⛔ drift — board hygiene findings:\n'
    grep '^⚠' "$out" | sed 's/^/     /' || true
    red=1
  fi
  if ( cmd_doctor ) >"$out" 2>&1; then
    say "doctor — env OK"
  else
    printf '⛔ doctor — RED:\n'
    tail -5 "$out" | sed 's/^/     /'
    red=1
  fi
  rm -f "$out"
  [ "$red" -eq 0 ] || die "qa: red — fix the ⛔ lines above before calling the work done"
  say "qa: all green"
}

cmd_metrics() { # cycle time + throughput + kickbacks from EVENTS.ndjson — pure awk
  [ -s "$EVENTS" ] || { note "no telemetry yet (EVENTS.ndjson empty) — runs accumulate it"; return 0; }
  awk -v now="$(date +%s)" '
    function get(k,   m){ m=""; if (match($0, "\""k"\":\"[^\"]*\"")) { m=substr($0,RSTART,RLENGTH); sub("\""k"\":\"","",m); sub("\"$","",m) } return m }
    function num(k,   m){ m=""; if (match($0, "\""k"\":[0-9]+"))     { m=substr($0,RSTART,RLENGTH); sub("\""k"\":","",m) } return m+0 }
    { ts=num("ts"); ev=get("ev"); id=get("id")
      if (ev=="claim"    && !(id in claimed)) { claimed[id]=ts; if (match($0,/"pts":[0-9.]+/)) { m=substr($0,RSTART+6,RLENGTH-6); cpts[id]=m+0 } }
      if (ev=="handoff" && !(id in ho)) ho[id]=ts
      if (ev=="kickback") { kb[id]++; kbt++ ; if (now-ts<7*86400) kb7++ }
      if (ev=="done")    { done[id]=ts; dn++; if (now-ts<7*86400) dn7++ }
    }
    END{
      n=0; for (id in done) if (id in claimed) { c[n++]=done[id]-claimed[id] }
      # insertion sort (tiny n) for p50
      for(i=1;i<n;i++){v=c[i];j=i-1;while(j>=0&&c[j]>v){c[j+1]=c[j];j--}c[j+1]=v}
      # T-032 plain-English summary FIRST, above the byte-identical table — same numbers it computes
      bsum=0; bcnt=0; for (id in ho) if (id in claimed) { bsum+=ho[id]-claimed[id]; bcnt++ }
      isum=0; icnt=0; for (id in done) if (id in ho) { isum+=done[id]-ho[id]; icnt++ }
      p50h = (n>0) ? c[int((n-1)/2)]/3600 : 0
      printf "In plain English: %d tasks done, a typical task takes %.1fh door to door; building averages %.1fh, landing %.1fh; %d bounced.\n", dn+0, p50h, (bcnt?bsum/bcnt/3600:0), (icnt?isum/icnt/3600:0), kbt+0
      printf "done total: %d   done 7d: %d   kickbacks total: %d (7d: %d)\n", dn+0, dn7+0, kbt+0, kb7+0
      if (n>0) { s=0; for(i=0;i<n;i++) s+=c[i]
        printf "cycle claim→done  avg: %.1fh   p50: %.1fh   n=%d\n", s/n/3600, c[int((n-1)/2)]/3600, n }
      # v5 calibration: cycle p50 per point bucket (only for claims that logged pts)
      for (id in done) if (id in claimed && id in cpts) { b=cpts[id]; bc[b, nb[b]++]=done[id]-claimed[id] }
      line=""
      for (b=1; b<=13; b++) if (nb[b]>0) {
        for(i=1;i<nb[b];i++){v=bc[b,i];j=i-1;while(j>=0&&bc[b,j]>v){bc[b,j+1]=bc[b,j];j--}bc[b,j+1]=v}
        line=line sprintf("%s%gpt p50 %.1fh n=%d", (line==""?"":"  ·  "), b, bc[b,int((nb[b]-1)/2)]/3600, nb[b])
      }
      if (line!="") printf "by points (Planner: point UP any bucket whose p50 dwarfs its size)\n  %s\n", line
      if (kbt+0>0 && dn+0>0) printf "kickback rate: %.0f%%  (Planner: read this before pointing)\n", 100*kbt/dn
      # v5.8: where does cycle time go? build (claim→handoff) vs integration wait (handoff→done).
      bs=0; bn=0; for (id in ho) if (id in claimed) { bs+=ho[id]-claimed[id]; bn++ }
      is=0; iN=0; for (id in done) if (id in ho) { is+=done[id]-ho[id]; iN++ }
      if (bn>0 || iN>0) printf "split  build(claim→handoff) avg: %.1fh n=%d   ·   integrate(handoff→done) avg: %.1fh n=%d\n", (bn?bs/bn/3600:0), bn, (iN?is/iN/3600:0), iN
      # oldest task still awaiting integration (handoff logged, no done yet) — is the Integrator behind?
      oldest=0; oid=""; for (id in ho) if (!(id in done)) { dd=now-ho[id]; if (dd>oldest){oldest=dd; oid=id} }
      if (oid!="") printf "oldest awaiting integration: %s waiting %.1fh — run the Integrator if this keeps climbing\n", oid, oldest/3600
    }' "$EVENTS"
  printf 'WIP now: %s active · %s review\n' \
    "$(ls "$BOARD/active" 2>/dev/null | grep -c '\.md$' || true)" \
    "$(ls "$BOARD/review" 2>/dev/null | grep -c '\.md$' || true)"
}

cmd_why() { # why <ID> — the reasons a task bounced or blocked, from telemetry + its own body. The
  # reasons are captured (evt kickback/release, ⛔ lines appended to the task) but no trusted tool
  # surfaced them — you had to hand-open the task or the untested dashboard. This is that tool.
  local id="${1:?usage: polaris why <ID>}" tf out
  tf="$(task_file "$id")" || die "no task file for $id"
  note "why $id — $(fm_get status "$tf" | grep . || echo '?'), currently in $(task_col "$id")/"
  out=""
  if [ -s "$EVENTS" ]; then
    out="$(awk -v id="$id" -v now="$(date +%s)" '
      function g(k,  m){ m=""; if (match($0,"\""k"\":\"[^\"]*\"")){m=substr($0,RSTART,RLENGTH);sub("\""k"\":\"","",m);sub("\"$","",m)} return m }
      function n(k,  m){ m=0; if (match($0,"\""k"\":[0-9]+")){m=substr($0,RSTART,RLENGTH);sub("\""k"\":","",m)} return m+0 }
      { e=g("ev"); if (g("id")==id && (e=="kickback"||e=="release"||e=="blocked")) {
          nt=g("note"); printf "  %5dh ago  %-8s %s\n", int((now-n("ts"))/3600), e, (nt==""?"(no note)":nt) } }
    ' "$EVENTS")"
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  if grep -q '⛔' "$tf" 2>/dev/null; then note "notes on the task file:"; grep '⛔' "$tf" | sed 's/^[[:space:]]*/     /'; fi
  { [ -z "$out" ] && ! grep -q '⛔' "$tf" 2>/dev/null; } && say "$id has a clean record — no kickbacks or releases logged"
  return 0
}

cmd_dash() { # launch the read-only live board (single-file stdlib server)
  local PY=""
  # `-c pass` proves a REAL interpreter — `command -v` alone is fooled by the
  # Windows Store python3 alias stub, which sits on PATH but only prints an ad.
  python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; } || true
  [ -n "$PY" ] || die "dashboard needs python3 (or python) on PATH — everything else in POLARIS runs without it"
  exec "$PY" "$OPS/dashboard.py" --root "$PRIMARY" "$@"
}

find_claude() { # resolve the Claude Code CLI the way it will actually be invoked. On Windows `claude`
  # is usually a .cmd/.exe shim that Git Bash's `command -v claude` misses — so the 5.7.0 "builders
  # beside you" launch silently no-op'd. Probe the shims too. Prints the runnable name, or nothing.
  local c
  for c in claude claude.cmd claude.exe; do
    command -v "$c" >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }
  done
  return 1
}
find_claude_windows() { # pane command wt.exe can actually launch. wt hands its trailing args to
  # Windows CreateProcess, which CANNOT run the extension-less bash shim that `command -v claude`
  # finds first under Git Bash — every 5.8.0 pane died with 0x80070002 "file not found" before a
  # session even started. So resolve a REAL claude.exe/.cmd and print its FULL Windows path (8.3
  # short form, so "C:\Program Files"-style spaces never break wt's arg re-joining); if only the
  # bash shim exists, wrap it in bash.exe -lc. Prints TAB-separated pane tokens, or nothing.
  local c p b
  for c in claude.exe claude.cmd; do
    p="$(command -v "$c" 2>/dev/null)" && [ -n "$p" ] || continue
    if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -ws "$p" 2>/dev/null || cygpath -w "$p" 2>/dev/null || printf '%s' "$p")"; fi
    printf '%s\tstart' "$p"; return 0
  done
  if command -v claude >/dev/null 2>&1 && b="$(command -v bash 2>/dev/null)" && [ -n "$b" ]; then
    if command -v cygpath >/dev/null 2>&1; then b="$(cygpath -ws "$b" 2>/dev/null || cygpath -w "$b" 2>/dev/null || printf '%s' "$b")"; fi
    printf '%s\t-lc\tclaude start' "$b"; return 0
  fi
  return 1
}
cmd_fleet() { # fleet <N> [--loop] [--launch] [--dry-run] — print N Builder kickoffs; --launch opens them
  local n="" loop="" launch="" dry="" i
  while [ $# -gt 0 ]; do
    case "$1" in
      --loop)    loop=" Run in loop mode.";;
      --launch)  launch=1;;
      --dry-run) dry=1;;
      -*)        die "fleet: unknown flag $1";;
      *)         if [ -z "$n" ]; then n="$1"; else die "fleet: unexpected arg '$1'"; fi;;
    esac
    shift
  done
  [ -n "$n" ] || die "usage: polaris fleet <N> [--loop] [--launch] [--dry-run]"
  case "$n" in *[!0-9]*) die "fleet: N must be a number";; esac
  [ "$n" -ge 1 ] || die "fleet: N must be >= 1"

  # The long form on purpose: this printed line is pasted into ANY agent CLI, including ones with no
  # POLARIS skill to route a bare `start`. In Claude Code, `start` alone does the same thing.
  local msg="You are a BUILDER. Claim the top ready task and complete it end to end. Stop at the review handoff.$loop"
  note "kickoff (paste into $n parallel sessions of ANY agent CLI — in Claude Code, \"start\" alone does it):"
  printf '   %s\n' "$msg"

  # Print-only unless the caller asked to open sessions (--launch) or preview that (--dry-run).
  # We NEVER spawn windows a caller didn't ask for — the Planner passes --launch per autolaunch:.
  if [ -z "$launch" ] && [ -z "$dry" ]; then
    note "(add --launch to open $n Builder sessions automatically, or open $n terminals and paste the line above)"
    return 0
  fi

  # Cap auto-launched sessions — screen + cost discipline. The printed kickoff above stays uncapped.
  local cap launch_n; cap="$(cfg autolaunch_max 3)"; case "$cap" in ''|*[!0-9]*) cap=3;; esac
  launch_n="$n"; [ "$launch_n" -gt "$cap" ] && launch_n="$cap"

  local claude_cmd; claude_cmd="$(find_claude || true)"
  local wt_pane=""
  command -v wt.exe >/dev/null 2>&1 && wt_pane="$(find_claude_windows || true)"
  if command -v tmux >/dev/null 2>&1 && [ -n "$claude_cmd" ]; then
    if [ -n "$dry" ]; then
      note "[dry-run] tmux: $launch_n windows, each running: $claude_cmd \"$msg\""
    else
      tmux has-session -t polaris 2>/dev/null || tmux new-session -d -s polaris -c "$PRIMARY"
      for i in $(seq 1 "$launch_n"); do tmux new-window -t polaris -c "$PRIMARY" "$claude_cmd \"$msg\""; done
      say "fleet of $launch_n launched in tmux — attach: tmux attach -t polaris · watch: ops/polaris dash"
    fi
  elif [ -n "$wt_pane" ]; then
    # Windows Terminal: ONE new window with launch_n VERTICAL split panes (side by side), each running
    # `<claude> start` in the repo. The pane command comes from find_claude_windows — a full .exe/.cmd
    # Windows path CreateProcess can start (a bare `claude` resolves to the npm bash shim in Git Bash,
    # which killed every pane with 0x80070002). The repo's polaris skill routes `start` → BUILDER,
    # whose `claim` (no ID) SKIPS locked tasks and takes the next — so launch_n panes land on
    # launch_n distinct tasks, and a pane whose top pick was taken doesn't die.
    # `\;` reaches wt as a LITERAL subcommand separator, never a bash statement separator.
    [ -n "$loop" ] && note "(loop mode isn't applied to Windows Terminal panes — each does one task; say start again for more)"
    local dir="$PRIMARY" pane=()
    command -v cygpath >/dev/null 2>&1 && dir="$(cygpath -w "$PRIMARY" 2>/dev/null || printf '%s' "$PRIMARY")"
    IFS=$'\t' read -r -a pane <<<"$wt_pane"
    local w=( wt.exe -w new new-tab -d "$dir" "${pane[@]}" )
    for i in $(seq 2 "$launch_n"); do w+=( \; split-pane -V -d "$dir" "${pane[@]}" ); done
    if [ -n "$dry" ]; then
      note "[dry-run] would run:"; printf '  '; printf ' %q' "${w[@]}"; printf '\n'
    else
      "${w[@]}" >/dev/null 2>&1 &
      say "fleet of $launch_n launched in Windows Terminal (side-by-side panes) — watch: ops/polaris dash"
    fi
  else
    # Say WHY nothing opened, so a silent no-op never masquerades as "windows opened".
    if { command -v tmux >/dev/null 2>&1 || command -v wt.exe >/dev/null 2>&1; }; then
      note "found a terminal but no launchable 'claude' CLI (need claude, claude.cmd, or claude.exe on PATH). Install/repair the Claude CLI, or open $n terminals and paste the line above."
    else
      note "(auto-launch needs tmux+claude or Windows Terminal+claude on PATH — open $n terminals and paste the line above)"
    fi
    return 0
  fi
  [ "$n" -gt "$launch_n" ] && note "opened $launch_n of $n (cap autolaunch_max=$cap) — the rest stay claimable; say start in another session"
  return 0
}
