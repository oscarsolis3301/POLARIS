# POLARIS lib/route.sh — choosing the lane, sourced by ops/polaris (the lib loader): triage, route,
# and depth. Moved out of observe.sh unchanged (ops/contracts/minutes.md § 3).

cmd_triage() { # triage [<ID…>] — print the LANE this board's work belongs in: solo | express | full | tidy.
  # The six conditions below were prose in CONDUCTOR.md, which meant a model re-derived them from
  # the board every run — reading task files, weighing points, re-reading CONVENTIONS — and paid
  # tokens to reach an answer the CLI already had. It is data, so it is a command.
  # Line 1 is the lane and nothing else, so a caller can branch on it without parsing.
  #   solo    one context does plan+build+integrate. No subagents at all.
  #   express conductor + ONE builder + ONE integrator, landing through `land --express`.
  #   full    the ordinary loop: planner, N builders, integrator, wave gate.
  #   tidy    the layout pass (ops/roles/TIDY.md), one context — a bare triage on an empty, quiet
  #           board whose cached verdict says the pass is due, once per session (save-hops § 2.3).
  # With ID(s) (stay-on-request.md § 1): ONLY the named tasks count toward the lane — a leftover
  # already sitting in ready/ never drags the run into a bigger lane than the request needs. Each
  # named ID must sit in ready/ or active/, else `die` (rc 1, nothing on stdout). With a session id,
  # the FIRST named task's `plan:` is recorded as this run's scope, overwriting (the request defines
  # the run, not the first claim) — `claim`'s first-claim write (builder.sh) stays the fallback for
  # a bare `start`. No IDs ⇒ every branch below is byte-identical to before.
  local n=0 id="" f base pts risk owned p why="" lane=full k sum big
  local named=0 first_id="" active_n=0 aid
  # publish: pr (publish-modes.md v2): one fetch per run, silent. T-230 owns `next` (handover.sh),
  # so triage — run once per run, first — is the sync point. Direct mode: cmd_sync is a no-op.
  cmd_sync >/dev/null 2>&1 || true
  if [ $# -gt 0 ]; then
    named=1
    for id in "$@"; do
      f="$(task_file "$id" ready)" || f="$(task_file "$id" active)" || \
        die "triage: $id is not in ready/ or active/"
      [ -z "$first_id" ] && first_id="$id"
    done
    n=$#
    if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
      local hs; hs="$PRIMARY/.polaris/handover/$CLAUDE_CODE_SESSION_ID"
      mkdir -p "$hs" 2>/dev/null || true
      f="$(task_file "$first_id")"
      printf '%s\n' "$(fm_get plan "$f" 2>/dev/null || true)" 2>/dev/null > "$hs/plan" || true
    fi
    [ "$n" -eq 1 ] && id="$first_id"
  else
    for f in "$BOARD"/ready/*.md "$BOARD"/active/*.md; do
      [ -e "$f" ] || continue
      base="${f##*/}"; [ "$base" = "IDEAS.md" ] && continue
      n=$((n + 1)); id="${base%.md}"
    done
  fi

  if [ "$n" -eq 0 ]; then
    # tidy (save-hops.md § 2.3): an empty board that is also QUIET — board_quiescent (admin.sh):
    # nothing in review/, no lock, no lease, no live bg job — with the layout pass due sends a bare
    # `start` to the pass instead of to a Planner with nothing to plan, at most once per session:
    # the § 0.6 marker is created in the same call that prints `tidy`. The verdict is READ from the
    # cache `hops --due` writes (§ 0.5), never computed — triage opens every run and stays cheap, so
    # the file test comes first and a repo without the cache pays nothing. Missing, stale (its sha
    # is not $BASE's tip), not-due or `hops: off` → today's two `full` lines, byte for byte. Named
    # IDs never reach this branch (n is then $# > 0), so a named request is never rerouted.
    local hd="$PRIMARY/.polaris/hops-due" hsha="" hv="" hmsg="" hmk="" cr
    if [ -f "$hd" ]; then
      cr="$(printf '\r')"
      IFS="$POLARIS_TAB" read -r hsha hv hmsg < "$hd" || true
      hsha="${hsha%$cr}"; hv="${hv%$cr}"; hmsg="${hmsg%$cr}"
      hmk="$(next_dir)/tidy"
      if [ "$hv" = 0 ] && [ ! -e "$hmk" ] && [ "$(cfg hops on)" != off ] && [ -n "$hsha" ] \
        && [ "$hsha" = "$(git -C "$PRIMARY" rev-parse --verify -q "$BASE" 2>/dev/null)" ] && board_quiescent; then
        mkdir -p "${hmk%/tidy}" 2>/dev/null || true
        date +%s 2>/dev/null > "$hmk" || true
        printf 'tidy\n'
        note "the board is empty and the layout pass is due: ${hmsg#layout pass due — }"
        note "read ops/roles/TIDY.md — one context, no subagents"
        return 0
      fi
    fi
    printf 'full\n'; note "nothing claimable — the board is empty, so a Planner runs first"; return 0
  fi
  if [ "$n" -gt 1 ]; then
    # Several tasks price CONTEXTS, not tasks (test-surfaces.md § 8). A `full` wave for n tasks
    # opens n+3 cold starts — conductor, planner, n builders, integrator — of ~7,300 tokens EACH
    # before any work happens, while four 1-point tasks landed one after another in ONE solo
    # context pay for one. So small-and-few work stays solo, worked one task at a time, and the
    # note states the arithmetic it used so the lane is auditable rather than felt. Rules, in
    # order: a lane already building · any task failing its own gate (first offender, the
    # single-task wording) · the express/publish knobs · the solo budget (≤4 tasks, ≤3 pts each,
    # ≤6 pts in all) · otherwise full.
    k=0
    if [ "$named" -eq 1 ]; then
      for aid in "$@"; do
        [ -f "$BOARD/active/$aid.md" ] && k=$((k + 1))
      done
    else
      for f in "$BOARD"/active/*.md; do
        [ -e "$f" ] || continue
        [ "${f##*/}" = "IDEAS.md" ] && continue
        k=$((k + 1))
      done
    fi
    if [ "$k" -gt 0 ]; then
      printf 'full\n'; note "$k task(s) already active — another lane is building; parallel lanes are the point"; return 0
    fi
    sum=0; big=0
    for id in $( if [ "$named" -eq 1 ]; then
        for aid in "$@"; do [ -f "$BOARD/ready/$aid.md" ] && printf '%s\n' "$aid"; done
      else
        for f in "$BOARD"/ready/*.md; do
          [ -e "$f" ] || continue
          base="${f##*/}"; [ "$base" = "IDEAS.md" ] && continue
          printf '%s\n' "${base%.md}"
        done
      fi ); do
      f="$BOARD/ready/$id.md"
      pts="$(fm_get points "$f")"; pts="${pts:-99}"
      risk="$(fm_get risk "$f")"; risk="${risk:-normal}"
      [ "$risk" = "normal" ] || why="risk: $risk (only a human may approve a merge)"
      case "$pts" in ''|*[!0-9]*) [ -z "$why" ] && why="points '$pts' is not a plain number";; esac
      if [ -z "$why" ]; then
        owned="$(fm_list files_owned "$f")"
        while IFS= read -r p; do
          [ -z "$p" ] && continue
          if rules_gate "$p" "$id"; then
            if [ "$RULES_GATE" = "path" ]; then why="owns '$p' under RULES path scope '$RULES_GATE_SCOPE' — cannot be built as specified"
            else why="owns '$p' under ask scope '$RULES_GATE_SCOPE' — get the human's yes before starting (polaris approve $id $RULES_GATE_SCOPE -m \"why\")"
            fi
            break
          fi
        done <<EOF
$owned
EOF
      fi
      if [ -n "$why" ]; then printf 'full\n'; note "$id: $why"; return 0; fi
      sum=$((sum + pts)); [ "$pts" -gt "$big" ] && big="$pts"
    done
    if [ "$(cfg express auto)" = "off" ]; then printf 'full\n'; note "express: off in CONVENTIONS.md"; return 0; fi
    if [ "$big" -le 3 ] && [ "$n" -le 4 ] && [ "$sum" -le 6 ]; then
      printf 'solo\n'
      note "$n tasks · $sum pts ≤ 6 — one context (~7,300 tokens cold start) beats a full wave's $((n + 3)) contexts (~$(( (n + 3) * 7300 )) tokens); work them one at a time: claim → build → land --express → next"
    else
      printf 'full\n'
      note "$n claimable tasks · $sum pts — over the solo budget (4 tasks / 6 pts / 3 pts each); parallel lanes are the point"
    fi
    return 0
  fi

  f="$(task_file "$id")" || { printf 'full\n'; note "cannot read task $id"; return 0; }
  pts="$(fm_get points "$f")"; pts="${pts:-99}"
  risk="$(fm_get risk "$f")"; risk="${risk:-normal}"

  [ "$risk" = "normal" ] || why="risk: $risk (only a human may approve a merge)"
  case "$pts" in ''|*[!0-9]*) [ -z "$why" ] && why="points '$pts' is not a plain number";; esac
  [ -z "$why" ] && [ "$(cfg express auto)" = "off" ] && why="express: off in CONVENTIONS.md"
  # STOP-AND-ASK, mechanically — three cases, not one (ask-approval.md § 5):
  #   `path` scope       → full: the rule is a wall, no approval can lift it
  #   `ask`, no approval → full: get the human's yes at the plan gate, where asking is cheap
  #   `ask`, approved    → the question is settled — fall through to ordinary points routing
  if [ -z "$why" ]; then
    owned="$(fm_list files_owned "$f")"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if rules_gate "$p" "$id"; then
        if [ "$RULES_GATE" = "path" ]; then why="owns '$p' under RULES path scope '$RULES_GATE_SCOPE' — cannot be built as specified"
        else why="owns '$p' under ask scope '$RULES_GATE_SCOPE' — get the human's yes before starting (polaris approve $id $RULES_GATE_SCOPE -m \"why\")"
        fi
        break
      fi
    done <<EOF
$owned
EOF
  fi

  if [ -n "$why" ]; then
    printf 'full\n'; note "$id: $why"; return 0
  fi
  # SOLO threshold 2 → 3 (2026-07-26, assistant, owner-authorized in the 5.21.0 token-efficiency
  # plan). WHY: the gates were never the expense, the CONTEXTS were — a 3-point task in `express`
  # opens a conductor, a builder and an integrator, three cold starts of ~7,300 tokens of injected
  # skill definitions plus CLAUDE.md and a role file EACH, to land work one context finishes
  # comfortably. Nothing about the checks changes: SOLO still runs verify, the task's verify: list,
  # the full suite once at `land --express`, and qa. Points measure scope and merge risk, and this
  # repo's own calibration records that they do NOT predict wall clock (5pt p50 = 2pt p50 = 0.5h,
  # n=8, 0 kickbacks) — so a 3-pointer is not a longer job, it is a slightly wider one, and width
  # is exactly what a single context handles well. Revert to 2 if solo tasks start kicking back.
  if [ "$pts" -le 3 ]; then lane=solo; else lane=express; fi
  printf '%s\n' "$lane"
  note "$id: $pts point(s), risk normal, express on, publish direct"
  [ "$lane" = express ] && note "over 3 points — worth a fresh builder context, but still ONE task and ONE suite run"
  return 0
}

_route_default() { # _route_default <tier> — the kit's own sizing for a spawn (minutes.md § 8, owner
  # 2026-11-09): small work on Sonnet at low effort, normal work on Opus at medium, big or risky work
  # on Opus at high. DEFAULTS IN CODE on purpose: `update` never rewrites a project's config, so a
  # default that lived in CONVENTIONS would reach no repo that already exists. Sets RD_MODEL and
  # RD_EFFORT (globals, never a subshell — bash 3.2 keeps them). Never names Fable or Haiku.
  case "${1:-}" in
    cheap)  RD_MODEL=sonnet; RD_EFFORT=low;;
    strong) RD_MODEL=opus;   RD_EFFORT=high;;
    *)      RD_MODEL=opus;   RD_EFFORT=medium;;
  esac
}
_route_rank() { # _route_rank <level> — sets RR to the level's place in low < medium < high < xhigh <
  # max (1..5), or 0 for anything else. A case, not a lookup table: zero forks, no arrays.
  case "${1:-}" in
    low) RR=1;; medium) RR=2;; high) RR=3;; xhigh) RR=4;; max) RR=5;; *) RR=0;;
  esac
}
_route_chat_effort() { # sets RC_EFFORT to the chat's own effort level, or empty when it is unknown.
  # The machine guard writes it, one word on one line, to
  # $HOME/.claude/polaris/model-state/$CLAUDE_CODE_SESSION_ID.effort. No session id, no file, or a
  # word that is not a known level → empty, and route does not clamp. Builtins only: no fork.
  local f="" v=""
  RC_EFFORT=""
  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || return 0
  f="$HOME/.claude/polaris/model-state/$CLAUDE_CODE_SESSION_ID.effort"
  [ -f "$f" ] || return 0
  read -r v < "$f" || [ -n "$v" ] || return 0
  v="${v%$'\r'}"
  _route_rank "$v"
  [ "$RR" -gt 0 ] && RC_EFFORT="$v"
  return 0
}

cmd_route() { # route [<ID>] [--role <ROLE>] [--points <N>] [--risk <R>] — which model TIER runs a
  # piece of work, and what a spawn of it should be sized as (ops/contracts/model-routing.md v4,
  # minutes.md § 8). triage answers "which lane"; this answers "which model", with the same shape:
  # line 1 is ALWAYS exactly one bare word — strong | mid | cheap — so callers branch on it blind.
  # Then two notes, `   model: <name>` and `   effort: <level>`, which the CONDUCTOR passes as the
  # spawn's model and effort. Defaults live in _route_default; model_<tier> / effort_<tier> in
  # CONVENTIONS override them, the value `inherit` drops that note (the spawn inherits the chat's),
  # and a task's literal model: name wins for the model note. The effort note is never above the
  # chat's own level (_route_chat_effort). Precedence: explicit --points/--risk (pure, board-free) →
  # --role → <ID>. Routing never blocks work — malformed points and unknown roles fall back to mid,
  # rc 0; only no-args and an unknown ID are errors. Read-only by contract: touches no lock, writes
  # no board file, fires no hook.
  local id="" role="" pts="" rsk="" pts_set="" rsk_set=""
  local tier="" mdl="" ov="" f="" rnote="" rdeny="" rraw="" lit="" eff="" cr=""
  local u="usage: polaris route <ID> | --role <ROLE> | --points <N> [--risk <R>]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --role)   role="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
      --points) pts_set=1; pts="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
      --risk)   rsk_set=1; rsk="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
      -*)       die "$u";;
      *)        if [ -z "$id" ]; then id="$1"; else die "$u"; fi; shift;;
    esac
  done
  if [ -n "$pts_set$rsk_set" ]; then
    # pure mode: board-free. A missing half defaults (--risk normal; --points empty → mid inside
    # tier_for), so a conductor can ask about work that has no task file yet.
    tier="$(tier_for "$pts" "${rsk:-normal}")"
  elif [ -n "$role" ] && [ "$role" != "BUILDER" ]; then
    case "$role" in
      INIT|PLANNER|INTEGRATOR|EVOLVE|CONDUCTOR) tier=strong;;
      SOLO|scout|TIDY) tier=mid;;
      *) tier=mid; rnote="unknown role '$role' — mid (routing never blocks work)";;
    esac
  elif [ "$role" = "BUILDER" ] && [ -z "$id" ]; then
    tier=mid; rnote="BUILDER routes per task — bash ops/polaris route <ID>"
  elif [ -n "$id" ]; then
    f="$(task_file "$id" 2>/dev/null || true)"
    [ -n "$f" ] && [ -f "$f" ] || die "route: no task $id on the board — check: ops/polaris board-fm"
    tier="$(tier_for "$(fm_get points "$f")" "$(fm_get risk "$f")")"
    ov="$(fm_get model "$f" 2>/dev/null || true)"
    case "$ov" in
      strong|mid|cheap) tier="$ov";;                # tier-word override: that tier wins outright
      "") :;;
      *) lit=1; mdl="$ov";;                         # literal model name — line 1 stays the derived
    esac                                            # tier (informational); the note carries it
  else
    die "$u"
  fi
  printf '%s\n' "$tier"
  _route_default "$tier"
  # The model note. Source, in order: the task's literal name → model_<tier> → the kit default.
  # FORBIDDEN models are NEVER named (core.sh model_denied — owner, 2026-09-15: Fable and Haiku, in
  # any repo, on any machine): a denied name from either source drops the note and prints the
  # REFUSED note instead — it is never swapped for the default, so the spawn names no model and
  # inherits the chat's, exactly as before. model_for_tier is not used here: it withholds a denied
  # name inside a command substitution, where its MODEL_DENIED never reaches this scope.
  if [ -z "$lit" ]; then
    rraw="$(cfg "model_$tier" "")"
    if [ -n "$rraw" ]; then mdl="$rraw"; else mdl="$RD_MODEL"; fi
  fi
  [ "$mdl" = inherit ] && mdl=""
  if model_denied "$mdl"; then rdeny="$mdl"; mdl=""; fi
  # The effort note: effort_<tier> → the kit default; `inherit` drops it; a word that is not a known
  # level reads as unset. Then the clamp: never above the chat's own level, when that is known.
  eff="$(cfg "effort_$tier" "")"
  if [ "$eff" != inherit ]; then
    _route_rank "$eff"
    [ "$RR" -gt 0 ] || eff="$RD_EFFORT"
    _route_chat_effort
    if [ -n "$RC_EFFORT" ]; then
      _route_rank "$RC_EFFORT"; cr="$RR"
      _route_rank "$eff"
      [ "$cr" -lt "$RR" ] && eff="$RC_EFFORT"
    fi
  else
    eff=""
  fi
  [ -n "$mdl" ] && note "model: $mdl"
  [ -n "$eff" ] && note "effort: $eff"
  [ -n "$rdeny" ] && note "model REFUSED: '$rdeny' is forbidden (owner, 2026-09-15) — this spawn names no model and inherits the session's"
  [ -n "$rnote" ] && note "$rnote"
  return 0
}

depth_line_say() { # depth_line_say <depth> <why> — change-sized.md § 5: the one depth line every
  # run prints before running. At full it also names the last measured full-suite time.
  local d="$1" w="$2" t="" s=""
  if [ "$d" = full ] && [ -f "$PRIMARY/.polaris/last-suite-seconds" ]; then
    s="$(cut -d' ' -f1 < "$PRIMARY/.polaris/last-suite-seconds" 2>/dev/null || true)"
    case "$s" in
      ''|*[!0-9]*) ;;
      *) if [ "$s" -lt 60 ]; then t="${s}s"; else t="$(( (s + 30) / 60 ))m"; fi;;
    esac
  fi
  if [ -n "$t" ]; then note "depth: $d — $w (last full run $t)"; else note "depth: $d — $w"; fi
}
uat_deferred_say() { note "uat — deferred: runs on full-depth changes, CI and release"; }
cmd_depth() { # depth [<ID>] — read-only verdict: how much testing does this change need, and why
  # (ops/contracts/test-depth.md § 3). Line 1 = the depth word alone; then `   why:` and
  # `   paths:` note lines. With <ID>: paths = git diff --name-only $BASE...feat/<ID>, taskfile =
  # that task's file. No ID: paths = surface_change_set — UNBOUNDED (no proven baseline) prints
  # `full` / `no suite baseline` outright; taskfiles = every `[<ID>]` task-commit subject since the
  # baseline (or $BASE on a branch), plus the current feat/<ID> branch, resolved with `task_file`.
  # Nothing here writes anything — same read-only contract as `triage`/`drift`.
  local id="" tf="" paths="" n=0 skipn=0 line depth why csf p skip_raw sha cur baseline subj sid f tfs commit=""
  local du="usage: polaris depth [<ID> | --commit <sha>]" rp="" k c sel
  tfs=""
  case "${1:-}" in
    --commit) commit="${2:-}"; [ -n "$commit" ] && [ $# -eq 2 ] || { printf '%s\n' "$du"; return 2; };;
    -*)       printf '%s\n' "$du"; return 2;;
    *)        id="${1:-}"; [ $# -le 1 ] || { printf '%s\n' "$du"; return 2; };;
  esac
  if [ -n "$commit" ]; then
    # change-sized.md § 6: what WOULD qa run for this commit — read-only, runs nothing, stamps nothing
    sha="$(git -C "$PRIMARY" rev-parse --verify -q "$commit^{commit}" 2>/dev/null)"       || { printf '⛔ no such commit: %s\n' "$commit"; return 2; }
    if git -C "$PRIMARY" rev-parse --verify -q "$sha^" >/dev/null 2>&1; then rp=""; else rp="--root"; fi
    paths="$(git -C "$PRIMARY" diff-tree --no-commit-id --name-only -r $rp "$sha" 2>/dev/null)"
    subj="$(git -C "$PRIMARY" log -1 --format=%s "$sha" 2>/dev/null)"
    case "$subj" in *'['*']') sid="${subj##*[}"; sid="${sid%]}"; tfs="$(task_file "$sid" 2>/dev/null)" || tfs="";; esac
    tf="$tfs"
  elif [ -n "$id" ]; then
    tf="$(task_file "$id")" || die "depth: $id not found on the board"
    paths="$(git -C "$PRIMARY" diff --name-only "$BASE...feat/$id" 2>/dev/null)"
  else
    csf="$(mktemp)"
    if surface_change_set > "$csf"; then
      paths="$(cat "$csf")"; rm -f "$csf"
    else
      rm -f "$csf"
      printf 'full\n'; note "why: no suite baseline"
      return 0
    fi
    baseline="${SURFACE_BASELINE:-}"
    cur="$(git -C "$PRIMARY" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ -n "$baseline" ] || { [ "$cur" = "$BASE" ] || baseline="$BASE"; }
    if [ -n "$baseline" ]; then
      while IFS= read -r subj; do
        [ -z "$subj" ] && continue
        case "$subj" in *'['*']') sid="${subj##*[}"; sid="${sid%]}";; *) sid="";; esac
        [ -n "$sid" ] || continue
        f="$(task_file "$sid" 2>/dev/null)" || continue
        case " $tfs " in *" $f "*) ;; *) tfs="${tfs:+$tfs }$f";; esac
      done <<EOF
$(git -C "$PRIMARY" log --format=%s "$baseline..HEAD" 2>/dev/null)
EOF
    fi
    case "$cur" in
      feat/*) f="$(task_file "${cur#feat/}" 2>/dev/null)" || f=""
              if [ -n "$f" ]; then case " $tfs " in *" $f "*) ;; *) tfs="${tfs:+$tfs }$f";; esac; fi ;;
    esac
    tf="$tfs"
  fi
  n="$(printf '%s\n' "$paths" | grep -c .)"
  skip_raw="$(cfg test_skip '*.md docs/** *.txt LICENSE*')"
  [ "$skip_raw" = "-" ] && skip_raw=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ -n "$skip_raw" ] && owned_match "$p" $skip_raw && skipn=$((skipn+1))
  done <<EOF
$paths
EOF
  line="$(printf '%s\n' "$paths" | depth_for $tf)"
  depth="${line%%$POLARIS_TAB*}"; why="${line#*$POLARIS_TAB}"
  csf=""
  if [ -n "$commit" ] && [ "$depth" != none ] && [ "$depth" != look ]; then
    # the paths qa would hand test_select_for: the change set minus test_skip
    csf="$(mktemp)"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if [ -n "$skip_raw" ] && owned_match "$p" $skip_raw; then continue; fi
      printf '%s\n' "$p"
    done > "$csf" <<PATHS
$paths
PATHS
    # a full verdict with test_select unset only says "test_select unset": name the first path that
    # has no related tests instead, when there is one (nothing is run to find it)
    if [ "$depth" = full ] && [ "$why" = "test_select unset" ]; then
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        printf '%s\n' "$p" > "$csf.1"
        if sel="$(related_cmds "$csf.1")"; then :; else why="$sel"; break; fi
      done < "$csf"
      rm -f "$csf.1"
    fi
  fi
  printf '%s\n' "$depth"
  note "why: $why"
  note "paths: $n changed ($skipn skipped by test_skip)"
  if [ -n "$commit" ]; then
    if [ -z "$csf" ]; then
      note "would run: nothing"
    else
      for k in test lint typecheck build uat; do
        c="$(cfg "$k" "")"
        [ -z "$c" ] && continue
        if [ "$k" = uat ] && [ "$depth" = scoped ]; then continue; fi
        if [ "$k" = test ] && [ "$depth" != full ] || { [ "$k" = test ] && { [ -n "$(cfg test_select "")" ] || [ "$(cfg test_related "")" != "-" ]; }; }; then
          if sel="$(test_select_for "$csf")"; then
            while IFS= read -r c; do [ -n "$c" ] && note "would run: $c"; done <<CMDS
$sel
CMDS
            continue
          fi
        fi
        note "would run: $c"
      done
      if [ "$depth" = scoped ] && [ -n "$(cfg uat "")" ]; then note "would skip: uat"; fi
    fi
    rm -f "$csf"
  fi
  return 0
}
