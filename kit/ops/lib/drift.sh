# POLARIS lib/drift.sh — board hygiene, sourced by ops/polaris (the lib loader): the ready-gate
# overlap test, the dependency walk, drift, rules, and surfaces health. Moved out of observe.sh
# unchanged (ops/contracts/minutes.md § 3).

pat_overlap() { # heuristic: can patterns A and B claim a common path?
  # Proves: identical · exact⊂glob · exact⊂dir/ · dir/⊂dir/ · glob∩glob with nested literal dirs.
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  # match_one (lib/ownership.sh), NOT `printf | owned_match`: with exactly one pattern the pipeline
  # reduced to precisely this call, and a pipeline is a fork PER DIRECTION — two per comparison. The
  # sweep above is O(tasks x patterns squared): measured over 600 comparisons (a 5-lane board's full
  # sweep), 18.4s of forking became 0.053s of `case`. cmd_drift runs that sweep, cmd_qa runs drift
  # --strict and cmd_finish runs cmd_qa — the fork tax was on every finish. Semantics are identical:
  # owned_match skips empty patterns, and both-empty already returned above.
  match_one "$a" "$b" && return 0   # pattern B matches A taken as a literal path
  match_one "$b" "$a" && return 0   # pattern A matches B taken as a literal path
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

rules_gate() { # rules_gate <owned-pattern> <ID|-> — does RULES gate this owned pattern, and WHY?
  # rc 0 = gated, with RULES_GATE (path|ask) and RULES_GATE_SCOPE naming the rule; rc 1 = clear.
  # cmd_triage and cmd_drift need the KIND behind a deny — rule_scan_path's rc deliberately carries
  # only yes/no and its contract is unchanged (ask-approval.md § 4) — so the classification lives
  # here, beside its two plan-gate callers. Matching is pat_overlap, BOTH directions: files_owned
  # entries and rule scopes are both patterns, so a task owning src/db/ intersects a scope
  # src/db/schema.py even though scope-matches-path alone would miss it. `path` dominates `ask`:
  # a pattern under both gets the wall's answer, because no approval can lift a `path` rule.
  # An `ask` scope covered by <ID>'s approved: list does not gate — the question is settled
  # (ask-approval.md § 5). `content` rules never gate planning: they judge diffs, not ownership.
  local p="$1" id="${2:--}" scope kind pat msg ask_scope=""
  RULES_GATE=""; RULES_GATE_SCOPE=""
  # Read the memo in THIS shell: `$(rules_lines)` filled it inside a subshell and threw it away, so
  # every call re-ran tr|grep|grep — each owned pattern of each ready task paid it, in drift and triage.
  rules_lines >/dev/null
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    case "$kind" in path|ask) ;; *) continue;; esac
    pat_overlap "$p" "$scope" || continue
    if [ "$kind" = "path" ]; then RULES_GATE=path; RULES_GATE_SCOPE="$scope"; return 0; fi
    [ -n "$ask_scope" ] && continue
    ask_approval_covers "$p" "$id" || ask_scope="$scope"
  done <<EOF
$_RULES_CACHE
EOF
  [ -n "$ask_scope" ] && { RULES_GATE=ask; RULES_GATE_SCOPE="$ask_scope"; return 0; }
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
  local strict="${1:-}" n=0 f g id id2 v d p s t hk hn hs hr
  finding() { n=$((n+1)); printf '⚠ [%d] %s\n' "$n" "$1"; }
  # Warm both per-process memos in THIS shell: their readers call them as $(…), a subshell that
  # fills the memo and discards it, so every rules/surfaces read below paid three forks again.
  rules_lines >/dev/null; surfaces_lines >/dev/null
  # 1) THE invariant: files_owned disjoint across ready ∪ active (heuristic, see pat_overlap)
  local claimable="" nready=0; set --
  for d in ready active; do
    for f in "$BOARD/$d/"*.md; do [ -e "$f" ] || break; claimable="$claimable$f
"; set -- "$@" "$f"; done
    if [ "$d" = ready ]; then nready=$#; fi
  done
  # ONE frontmatter pass over ready ∪ active — the only columns § 1 and § 2 read (speed.md § 3).
  # Every key is read exactly as its reader reads it: contract/points/title as fm_get (first match),
  # files_owned/surface as fm_list, depends_on as dep_ids — tagged <pos><TAB><key><TAB><value>,
  # <pos> being the file's 0-based place in $claimable (ready first, then active, glob order).
  # The per-key, per-pair awk starts this replaces were most of what drift still cost once § 7
  # became one pass. Kept in fcon/fpts/fttl (scalars) and fown/fsrf/fdep (newline lists).
  local nl='
' fx fk fv fmx fcon fpts fttl fown fsrf fdep
  if [ $# -gt 0 ]; then
    fmx="$(awk '
  function out(x, k, s) { printf "%d\t%s\t%s\n", x, k, s }
  function item(x, k, s,   n, j, p) {
    if (k != "depends_on") { out(x, k, s); return }
    gsub(/\[/, " ", s); gsub(/\]/, " ", s); gsub(/,/, " ", s)
    n = split(s, p, "[ ]")
    for (j = 1; j <= n; j++) if (p[j] !~ /^[[:space:]]*$/) out(x, k, p[j])
  }
  function emit(x, k, s,   n, j, p, it) {
    if (s == "") return
    if (s ~ /^\[.*\]$/) {
      s = substr(s, 2, length(s) - 2); n = split(s, p, ",")
      for (j = 1; j <= n; j++) {
        it = p[j]; sub(/^[ \t]*/, "", it); sub(/[ \t]*$/, "", it)
        if (it != "") item(x, k, it)
      }
      return
    }
    item(x, k, s)
  }
  BEGIN {
    ns = split("contract points title", sk, " "); nk = split("files_owned surface depends_on", lk, " ")
    for (i = 1; i < ARGC; i++) {
      path = ARGV[i]; x = i - 1; fs = 0; on = ""
      while ((getline line < path) > 0) {
        if (line ~ /^---[\r]?$/) { if (++fs > 1) break; continue }
        if (fs != 1) continue
        for (j = 1; j <= ns; j++) if (!((x, sk[j]) in got) && index(line, sk[j] ":") == 1) {
          s = substr(line, length(sk[j]) + 2)
          sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          out(x, sk[j], s); got[x, sk[j]] = 1
        }
        hit = 0
        for (j = 1; j <= nk; j++) if (index(line, lk[j] ":") == 1) {
          on = lk[j]; hit = 1; s = substr(line, length(on) + 2)
          sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          emit(x, on, s)
        }
        if (hit) continue
        if (on != "" && line ~ /^[ \t]*-[ \t]/) {
          s = line; sub(/^[ \t]*-[ \t]+/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          if (s != "") item(x, on, s)
          continue
        }
        if (on != "" && line ~ /^[A-Za-z_]/) on = ""
      }
      close(path)
    }
    exit
  }' "$@" 2>/dev/null || true)"
    while IFS= read -r v; do [ -z "$v" ] && continue
      fx="${v%%$POLARIS_TAB*}"; v="${v#*$POLARIS_TAB}"; fk="${v%%$POLARIS_TAB*}"; fv="${v#*$POLARIS_TAB}"
      case "$fk" in
        contract) fcon[$fx]="$fv";;
        points) fpts[$fx]="$fv";;
        title) fttl[$fx]="$fv";;
        files_owned) fown[$fx]="${fown[$fx]:-}$fv$nl";;
        surface) fsrf[$fx]="${fsrf[$fx]:-}$fv$nl";;
        depends_on) fdep[$fx]="${fdep[$fx]:-}$fv$nl";;
      esac
    done <<EOF
$fmx
EOF
  fi
  # The pairwise walk: each task's list comes from the pass above and is kept in oid[]/opat[], so
  # the walk itself forks nothing — pat_overlap is pure `case`. Same pairs, same order, same lines.
  local pa pb fo j k=0 oid opat
  while IFS= read -r f; do [ -z "$f" ] && continue
    id="${f##*/}"; id="${id%.md}"
    fo="${fown[$k]:-}"
    j=0
    while [ "$j" -lt "$k" ]; do
      id2="${oid[$j]}"
      while IFS= read -r pa; do [ -z "$pa" ] && continue
        while IFS= read -r pb; do [ -z "$pb" ] && continue
          if pat_overlap "$pa" "$pb"; then
            finding "OWNERSHIP OVERLAP: $id ∩ $id2 on '$pa' / '$pb' — chain them (depends_on), never parallel"
          fi
        done <<EOF2
${opat[$j]}
EOF2
      done <<EOF1
$fo
EOF1
      j=$((j+1))
    done
    oid[$k]="$id"; opat[$k]="$fo"; k=$((k+1))
  done <<EOF
$claimable
EOF
  # 2) ready-gate: contract exists · deps all done · ≤5 points — the ready files are positions
  # 0..nready-1 of the same list, so every key below comes from the one pass above.
  k=0
  for f in "$@"; do
    [ "$k" -lt "$nready" ] || break
    id="${f##*/}"; id="${id%.md}"
    v="${fcon[$k]:-}"
    # NAMED but MISSING only — an unset contract is legal (handover.sh next_promote, builder.sh pack).
    [ -n "$v" ] && [ ! -f "$PRIMARY/$v" ] && finding "READY GATE: $id contract missing ($v) — blocked/, not ready/"
    while IFS= read -r d; do [ -z "$d" ] && continue
      task_file "$d" done >/dev/null || finding "READY GATE: $id depends_on $d which is NOT in done/"
    done <<EOF
${fdep[$k]:-}
EOF
    v="${fpts[$k]:-}"; case "$v" in 8|13) finding "READY GATE: $id is ${v}pts — must be split before ready/";; esac
    # ask gate (ask-approval.md § 5): a ready task owning anything under an `ask` scope with no
    # covering approved: entry would spawn a Builder only to die on its first write — the ARC
    # sequence, stopped here at step 1. The asking belongs at the plan gate, where a human is
    # present and it is cheap. A covered scope is a settled question and no finding at all.
    while IFS= read -r p; do [ -z "$p" ] && continue
      if rules_gate "$p" "$id" && [ "$RULES_GATE" = "ask" ]; then
        finding "READY GATE: $id owns '$p' under ask scope '$RULES_GATE_SCOPE' with no covering approved: entry — get the human's yes (polaris approve $id $RULES_GATE_SCOPE -m \"why\") or blocked/, not ready/"
      fi
    done <<EOF
${fown[$k]:-}
EOF
    # surface: items (test-surfaces.md § 3, § 7): `done` writes each one as an ops/SURFACES.tsv row
    # and merely skips a malformed one with a ⚠ — so the typo is caught HERE, at the plan gate, and
    # never discovered at done. A tests glob covering its own surface is the one row shape the
    # whole map cannot survive (D6), so it is refused before any builder claims the task.
    v="${fttl[$k]:-}"
    while IFS= read -r p; do [ -z "$p" ] && continue
      if d="$(surface_row_from_item "$p" "$id" "$v")"; then
        s="${d%%$POLARIS_TAB*}"; t="${d#*$POLARIS_TAB}"; t="${t%%$POLARIS_TAB*}"
        match_one "$s" "$t" && finding "READY GATE: $id surface: '$p' — tests glob covers its own surface — fix the item before a builder claims it"
      else
        finding "READY GATE: $id surface: '$p' — $d — fix the item before a builder claims it"
      fi
    done <<EOF
${fsrf[$k]:-}
EOF
    k=$((k+1))
  done
  # 3) cruft: a done task's feat branch survived — THREE classes, not one (ops/contracts/
  # worktree-liveness.md § v2). Under `landing: self` a lane leaves its OWN branch behind by design
  # (v1.2: never remove the ground you are standing on), so the flat "the branch exists" finding
  # fired on every self-landed wave — after `qa` had already paid the suite, which withheld the
  # stamp and made the next `finish` pay it all over again for a nit clearable in a second. A
  # branch is a finding only once nobody is standing in its worktree, and DELETABLE only with proof
  # its tip is already in $BASE. ONE ref read, and the loop walks the BRANCHES, never done/ (speed.md
  # § 3): a handful of refs instead of every task ever finished, with zero process starts per step.
  # A branch whose name matches NO task in any column is an ADVISORY, never a finding: it may hold
  # unmerged work, so nothing may clear it, and a new red class would red `qa` in every install that
  # carries a legacy stray the moment it updates. It is printed so the stray is seen — nothing more.
  local crefs; crefs="$(git -C "$PRIMARY" for-each-ref --format='%(refname)' 'refs/heads/feat/*' 2>/dev/null || true)"
  for f in $crefs; do
    id="${f#refs/heads/feat/}"
    if [ -f "$BOARD/done/$id.md" ]; then
      if ! feat_tip_landed "$id"; then
        finding "CRUFT diverged: feat/$id carries commits not in $BASE — inspect: git log $BASE..feat/$id (never auto-deleted)"
      elif [ -d "$GCD/worktrees/$id" ] && beat_live "$id"; then
        : # waiting — the lane that landed it is still inside its own worktree; `sweep` lists the LIVE worktree and drift says nothing
      else
        finding "CRUFT: feat/$id still exists though $id is done — bash ops/polaris qa or sweep --fix clears it"
      fi
    elif ! task_file "$id" >/dev/null; then
      note "advisory: orphan branch feat/$id — no task in any column (may hold unmerged work; never auto-cleared)"
    fi
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
  # 5) doc overflow: MAP Deltas tail + Learned log — ADVISORY (minutes.md § 7), the class of 9)/10):
  # printed, never counted, never red under --strict, qa or finish, never withholding the suite stamp.
  v="$(grep -Ec ' \([A-Za-z0-9._-]+, [0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$OPS/MAP.md" 2>/dev/null || true)"
  if [ "${v:-0}" -gt 20 ]; then note "advisory: MAP: $v delta lines — fold them into the sections (EVOLVE target)"; fi
  v="$(awk '/^##[ \t]*Learned/{on=1;next} on&&/^## /{exit} on&&/^[ \t]*[-*]/{c++} END{print c+0}' "$OPS/SPRINT.md" 2>/dev/null || true)"
  if [ "${v:-0}" -gt 8 ]; then note "advisory: LEARNED: $v bullets — prune to ≤5 carry-overs (EVOLVE target)"; fi
  # 6) telemetry safety
  [ -f "$EVENTS" ] && ! grep -q 'EVENTS\.ndjson merge=union' "$PRIMARY/.gitattributes" 2>/dev/null \
    && finding "TELEMETRY: EVENTS.ndjson without union-merge gitattribute — run: ops/polaris upgrade"
  # 7) dependency graph across ALL columns: deps that exist nowhere + cycles (a ring never promotes).
  # ONE inline awk pass over every column (speed.md § 3). The per-task walk it replaces re-read the
  # whole board once per dependency, done/ included, and was ~94% of drift's wall time. Same verdicts
  # in the same order: files in backlog ready active review blocked done order, glob order inside a
  # column · a dependency is read exactly as dep_ids reads it (fm_list's block and flow shapes, then
  # split on [ ] , and space) · an id resolves to the file task_file would pick (active first, done
  # last) · a task is a DEP CYCLE iff it can reach itself. Files are read with getline, so one that
  # another lane moves mid-pass reads as empty instead of killing the pass.
  local col2 idf dout
  set --
  for col2 in backlog ready active review blocked done; do
    for idf in "$BOARD/$col2/"*.md; do [ -e "$idf" ] || break; set -- "$@" "$idf"; done
  done
  if [ $# -gt 0 ]; then
    dout="$(awk '
  function add(i, s,   n, k, p) {
    gsub(/\[/, " ", s); gsub(/\]/, " ", s); gsub(/,/, " ", s)
    n = split(s, p, "[ ]")
    for (k = 1; k <= n; k++) if (p[k] !~ /^[[:space:]]*$/) { nd[i]++; dep[i, nd[i]] = p[k] }
  }
  function emit(i, s,   n, k, p, item) {
    if (s == "") return
    if (s ~ /^\[.*\]$/) {
      s = substr(s, 2, length(s) - 2); n = split(s, p, ",")
      for (k = 1; k <= n; k++) {
        item = p[k]; sub(/^[ \t]*/, "", item); sub(/[ \t]*$/, "", item)
        if (item != "") add(i, item)
      }
      return
    }
    add(i, s)
  }
  function reaches(s,   q, h, t, u, b, k) {
    stamp++; h = 1; t = 0; b = best[s]
    for (k = 1; k <= nd[b]; k++) q[++t] = dep[b, k]
    while (h <= t) {
      u = q[h++]
      if (u == s) return 1
      if (!(u in best) || vis[u] == stamp) continue
      vis[u] = stamp; b = best[u]
      for (k = 1; k <= nd[b]; k++) q[++t] = dep[b, k]
    }
    return 0
  }
  BEGIN {
    split("active ready review blocked backlog done", c, " ")
    for (k = 1; k <= 6; k++) rank[c[k]] = k
    nf = ARGC - 1
    for (i = 1; i <= nf; i++) {
      path = ARGV[i]; n = split(path, seg, "/")
      id = seg[n]; sub(/\.md$/, "", id); fid[i] = id
      r = (n > 1 && (seg[n-1] in rank)) ? rank[seg[n-1]] : 9
      if (!(id in best) || r < brank[id]) { best[id] = i; brank[id] = r }
      fs = 0; on = 0
      while ((getline line < path) > 0) {
        if (line ~ /^---[\r]?$/) { if (++fs > 1) break; continue }
        if (fs != 1) continue
        if (index(line, "depends_on:") == 1) {
          on = 1; s = substr(line, 12)
          sub(/^[ \t]*/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          emit(i, s); continue
        }
        if (on && line ~ /^[ \t]*-[ \t]/) {
          s = line; sub(/^[ \t]*-[ \t]+/, "", s); sub(/[ \t]#.*$/, "", s); sub(/[ \t\r]*$/, "", s)
          if (s != "") add(i, s)
          continue
        }
        if (on && line ~ /^[A-Za-z_]/) on = 0
      }
      close(path)
    }
    for (i = 1; i <= nf; i++) {
      for (k = 1; k <= nd[i]; k++)
        if (!(dep[i, k] in best)) printf "DEP MISSING: %s depends_on %s — no task by that id in any column\n", fid[i], dep[i, k]
      if (!(fid[i] in cyc)) cyc[fid[i]] = reaches(fid[i])
      if (cyc[fid[i]]) printf "DEP CYCLE: %s sits in a depends_on ring — it can never satisfy the ready gate; break the cycle\n", fid[i]
    }
    exit
  }' "$@" 2>/dev/null || true)"
    while IFS= read -r v; do if [ -n "$v" ]; then finding "$v"; fi; done <<EOF
$dout
EOF
  fi
  # 8) surfaces (test-surfaces.md § 7): a row that would make change-scoped selection lie — the E
  # lines of surfaces_health. Its warnings (a glob in a rename window, an unarmed guard) never red
  # a wave gate; `ops/polaris surfaces` shows them.
  while IFS="$POLARIS_TAB" read -r hk hn hs hr; do
    [ "$hk" = E ] || continue
    finding "SURFACES: row $hn '$hs' — $hr (ops/polaris surfaces)"
  done <<EOF
$(surfaces_health || true)
EOF
  # 9) stale folder guides (ops/contracts/save-hops.md § 6): ADVISORY, the orphan-branch class of § 3
  # — printed, never counted, never red under --strict, qa or finish, because a stale guide must
  # never stop a run. What counts as a citation is hops' rule alone; drift only prints its rows.
  # rc 1 (none) · rc 3 (no python) · an engine older than hops · `hops: off` → silence.
  local srows sg sp
  srows=""
  if [ "$(cfg hops on)" != off ]; then srows="$("$SELF" hops --stale 2>/dev/null)" || srows=""; fi
  while IFS="$POLARIS_TAB" read -r v sg sp; do
    sp="${sp%$'\r'}"
    if [ "$v" = STALE ] && [ -n "$sg" ] && [ -n "$sp" ]; then note "advisory: GUIDE STALE: $sg cites $sp (missing)"; fi
  done <<EOF
$srows
EOF
  # 10) stale MAP rows (save-hops.md § 14.3): ADVISORY, as 9) — each item the root map reads from
  # ops/MAP.md that `where` drops because its path is no longer tracked, MAP order, once each. The
  # parse is where's own (_where_items, knowledge.sh), never a copy. Builders never edit MAP.md
  # (Invariant 1); the next EVOLVE pass retires the row. No ops/MAP.md → silence.
  while IFS= read -r sp; do
    if [ -n "$sp" ]; then note "advisory: MAP STALE: ops/MAP.md lists $sp (missing)"; fi
  done <<EOF
$(_where_items "$PRIMARY" stale 2>/dev/null || true)
EOF
  if [ "$n" -eq 0 ]; then say "drift: board clean (overlap · ready gate · cruft · stale refs · doc overflow · telemetry · deps)"
  else printf '%d finding(s).\n' "$n"; [ "$strict" = "--strict" ] && exit 1; fi
  return 0
}

cmd_rules() { # list + health-check ops/RULES.tsv
  if ! rules_lines | grep -q .; then note "no rules yet — ops/RULES.tsv (INIT seeds danger zones; EVOLVE proposes more)"; return 0; fi
  local scope kind pat msg n=0 bad=0
  printf '%-28s %-8s %-24s %s\n' 'SCOPE' 'KIND' 'PATTERN' 'MESSAGE'
  while IFS="$POLARIS_TAB" read -r scope kind pat msg; do
    n=$((n+1)); printf '%-28s %-8s %-24s %s\n' "$scope" "$kind" "${pat:--}" "$msg"
    # `ask` is a first-class kind (ask-approval.md § 1): pattern column `-`, exactly as for path —
    # no ERE is demanded for either. Only `content` carries a pattern that must compile.
    case "$kind" in path|content|ask) :;; *) bad=1; printf '   ⛔ bad kind (want path|content|ask)\n';; esac
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

surfaces_health() { # surfaces_health — ops/SURFACES.tsv health as DATA, one line per problem:
  # E|W<TAB><row#>|0<TAB><surface>|-<TAB><reason>; rc = the number of E lines (0 = healthy). Row
  # numbers are 1-based over surfaces_lines, row 0 = repo-level. cmd_surfaces renders these; drift
  # turns the E lines into findings and never the W lines — a glob in a rename window must not red
  # every wave gate (test-surfaces.md § 7). Selection fails UNSAFE (D6): a wrong tests glob skips
  # coverage while reporting green, so the one row shape that would make the whole map lie — a
  # tests glob covering its own surface, the tests pattern applied as a files_owned matcher to the
  # surface taken as a path — is an E; a glob matching nothing or far too much is a W. No rows ⇒
  # prints nothing, rc 0, no fork. ONE `git ls-files` fork, then match_one per file (builtins).
  local lines row n=0 e=0 surface tests cmd rest tracked f cs ct tpl
  lines="$(surfaces_lines)"
  [ -n "$lines" ] || return 0
  tracked="$(git -C "$PRIMARY" ls-files 2>/dev/null || true)"
  tpl="$(cfg test_select "")"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    n=$((n + 1))
    surface="${row%%$POLARIS_TAB*}"
    rest=""; case "$row" in *"$POLARIS_TAB"*) rest="${row#*$POLARIS_TAB}";; esac
    tests="${rest%%$POLARIS_TAB*}"
    cmd=""; case "$rest" in *"$POLARIS_TAB"*) cmd="${rest#*$POLARIS_TAB}"; cmd="${cmd%%$POLARIS_TAB*}";; esac
    if [ -z "$surface" ] || [ -z "$tests" ]; then
      e=$((e + 1)); printf 'E\t%s\t%s\t%s\n' "$n" "${surface:--}" "fewer than 2 columns"; continue
    fi
    if match_one "$surface" "$tests"; then
      e=$((e + 1)); printf 'E\t%s\t%s\t%s\n' "$n" "$surface" "tests glob covers its own surface"
    fi
    cs=0; ct=0
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      match_one "$f" "$surface" && cs=$((cs + 1))
      match_one "$f" "$tests" && ct=$((ct + 1))
    done <<EOF
$tracked
EOF
    [ "$cs" -eq 0 ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "surface matches 0 tracked files"
    [ "$cs" -gt 200 ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "surface matches $cs tracked files (>200 — too broad to select anything)"
    [ "$ct" -eq 0 ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "tests matches 0 tracked files"
    [ "$cmd" = "-" ] && [ -z "$tpl" ] && printf 'W\t%s\t%s\t%s\n' "$n" "$surface" "cmd is - but test_select: is unset"
  done <<EOF
$lines
EOF
  # Repo-level: the file is meant to be written only by `done`. Without a RULES `path` rule over
  # it, a row anyone could delete when it blocked them guards nothing (D2).
  if rules_gate ops/SURFACES.tsv - && [ "$RULES_GATE" = "path" ]; then :; else
    printf 'W\t0\t-\t%s\n' "ops/SURFACES.tsv is not RULES-guarded — arm a path rule so only done writes it"
  fi
  return "$e"
}

cmd_surfaces() { # surfaces [--scaffold [--apply]] — list + health-check ops/SURFACES.tsv (test-surfaces.md
  # § 7); rc 1 iff any ⛔. Mirrors cmd_rules: the table, each row's problems indented beneath it,
  # the repo-level warnings after the table, then ONE tail line carrying the counts.
  # --scaffold (v2 § 14) PROPOSES rows from the stack's own layout — the engine in surfaces.sh
  # decides, this renders: the runner it found, the rows it would write, every pairing it skipped
  # and why — and writes nothing, ever. --scaffold --apply writes exactly those rows (tagged
  # [scaffold]) and sets test_select: where the repo never set it, on $BASE only, and commits
  # nothing: the diff is the review. D6 is the rule here — an unmapped surface runs the whole suite
  # (safe); a MIS-mapped one skips real coverage while reporting green, and in a repo nobody is
  # watching nobody would notice — so the ambiguous pairings are said aloud as skips, never guessed.
  # The `git ls-files` below is the caller's ONE fork, handed to the engine as a file, never a pipe.
  local u="usage: polaris surfaces [--scaffold [--apply]]" mode=""
  if [ $# -gt 0 ]; then
    [ "$1" = --scaffold ] || die "$u"
    case "$#:${2:-}" in 1:) mode=scaffold;; 2:--apply) mode=apply;; *) die "$u";; esac
  fi
  if [ -n "$mode" ]; then
    local ls prop kind what why cmd rest n=0 s=0 rc=0
    if [ "$mode" = apply ]; then
      # feat/* is where Builders live, and a Builder never writes a row (D1: a row buys R1's savings
      # and arms R2 against you). From a task, rows are surface: items and `done` writes them.
      what="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      case "$what" in feat/*) die "surfaces --scaffold --apply runs on $BASE only — from a task, rows are surface: items (polaris done writes them)";; esac
      [ -f "$CONV" ] || die "no ops/CONVENTIONS.md — run INIT first; the scaffold sets test_select: in it"
    fi
    ls="$(mktemp)"; prop="$(mktemp)"
    git -C "$PRIMARY" ls-files > "$ls" 2>/dev/null || true
    if [ -f "$SURFACES" ]; then surfaces_proposal "$ls" "$SURFACES" > "$prop"; else surfaces_proposal "$ls" > "$prop"; fi
    rm -f "$ls"
    while IFS="$POLARIS_TAB" read -r kind what why cmd rest; do
      case "$kind" in
        NORUNNER) note "$what. Map rows by hand: a task's surface: items (ops/roles/PLANNER.md step 5b)"; rm -f "$prop"; return 0;;
        RUNNER)   note "runner: $what — test_select: $why"; printf '%-28s %-28s %s\n' SURFACE TESTS CMD;;
        ROW)      n=$((n + 1)); printf '%-28s %-28s %s\n' "$what" "$why" "$cmd";;
        SKIP)     s=$((s + 1)); printf '   ⚠ skipped: %s — %s\n' "$what" "$why";;
      esac
    done < "$prop"
    if [ "$n" -eq 0 ]; then
      if [ "$s" -ge 1 ]; then note "nothing to propose — $s pairing(s) skipped, listed above"
      else note "nothing to propose — no pairing the layout makes unambiguous (map rows by hand: surface: items)"; fi
      rm -f "$prop"; return 0
    fi
    if [ "$mode" = scaffold ]; then
      say "$n row(s) proposed · $s skipped — write them: ops/polaris surfaces --scaffold --apply"
      rm -f "$prop"; return 0
    fi
    surfaces_apply "$prop" || rc=$?
    rm -f "$prop"
    return "$rc"
  fi
  if ! surfaces_lines | grep -q .; then
    note "no surfaces yet — ops/SURFACES.tsv (init-board seeds the header; rows arrive from a task's surface: list when done lands it — never by hand)"
    return 0
  fi
  local health surface tests cmd msg n=0 e=0 w=0 kind rn surf reason
  health="$(surfaces_health || true)"   # the verdict is in the lines; the rc is recounted below
  printf '%-28s %-28s %-32s %s\n' 'SURFACE' 'TESTS' 'CMD' 'NOTE'
  while IFS="$POLARIS_TAB" read -r surface tests cmd msg; do
    [ -n "$surface$tests$cmd$msg" ] || continue
    n=$((n + 1)); printf '%-28s %-28s %-32s %s\n' "$surface" "${tests:--}" "${cmd:--}" "$msg"
    while IFS="$POLARIS_TAB" read -r kind rn surf reason; do
      [ "$rn" = "$n" ] || continue
      case "$kind" in E) printf '   ⛔ %s\n' "$reason";; W) printf '   ⚠ %s\n' "$reason";; esac
    done <<EOF2
$health
EOF2
  done <<EOF
$(surfaces_lines)
EOF
  while IFS="$POLARIS_TAB" read -r kind rn surf reason; do
    case "$kind" in E) e=$((e + 1));; W) w=$((w + 1));; *) continue;; esac
    [ "$rn" = 0 ] && printf '   ⚠ %s\n' "$reason"
  done <<EOF
$health
EOF
  [ "$e" -eq 0 ] || die "$n surface row(s), $e unhealthy"
  [ "$w" -eq 0 ] || { say "$n surface row(s), all healthy · $w warning(s)"; return 0; }
  say "$n surface row(s), all healthy"
}

surfaces_apply() { # surfaces_apply <proposal-file> — the SECOND sanctioned writer of ops/SURFACES.tsv
  # (test-surfaces.md v2 § 14 · § 16; the first is `done`). Seeds the header when the file is
  # absent, appends every ROW of the proposal as `<surface><TAB><tests><TAB><cmd><TAB><note> [scaffold]`
  # by shell redirect — the RULES path guard sees Edit/Write tools and feat-branch diffs, never
  # this, and still denies every hand edit — then test_select: in CONVENTIONS.md, ONLY where the
  # repo never set it: a LIVE line (any value, even empty) is the human's and is kept; a
  # `# test_select:` stub (adopt's "known and deliberately unset") is replaced in place; neither ⇒
  # the line is appended at the end after one blank line. Temp file + mv, LF kept, never sed -i.
  # Says exactly what it wrote and commits nothing: rows a human never sees written are rows nobody
  # checks, and D6 makes an unchecked row the one thing this file must not hold. rc 0.
  local prop="${1:-}" kind surface tests cmd rest tpl="" n=0 ts="" tmp line
  surfaces_seed
  while IFS="$POLARIS_TAB" read -r kind surface tests cmd rest; do
    case "$kind" in
      RUNNER) tpl="$tests";;
      ROW)    printf '%s\n' "$surface$POLARIS_TAB$tests$POLARIS_TAB$cmd$POLARIS_TAB$rest [scaffold]" >> "$SURFACES"
              n=$((n + 1));;
    esac
  done < "$prop"
  if grep -q '^test_select:' "$CONV" 2>/dev/null; then
    ts="kept (already set here)"
  else
    line="test_select: $tpl   # set by surfaces --scaffold --apply: {tests} = the changed rows' tests globs; delete this line to run the whole test: suite on every change"
    tmp="$(mktemp)"
    if grep -qE '^#[[:space:]]*test_select:' "$CONV" 2>/dev/null; then
      awk -v rep="$line" 'BEGIN { hit = 0 } !hit && /^#[ \t]*test_select:/ { print rep; hit = 1; next } { print }' "$CONV" > "$tmp"
    else
      { cat "$CONV"; printf '\n%s\n' "$line"; } > "$tmp"
    fi
    mv "$tmp" "$CONV"
    ts=set
  fi
  say "$n row(s) written to ops/SURFACES.tsv · test_select: $ts"
  note "review, then commit ops/SURFACES.tsv ops/CONVENTIONS.md — nothing was committed for you"
  return 0
}
