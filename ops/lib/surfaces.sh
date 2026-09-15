# POLARIS lib/surfaces.sh — the scaffold ENGINE sourced by ops/polaris (the lib loader): proposes
# ops/SURFACES.tsv rows from a repo's own layout (ops/contracts/test-surfaces.md v2 § 13). Pure by
# contract: it reads the manifests under $PRIMARY and a tracked-file LIST it is handed — never git,
# never $SURFACES (the caller passes the map), never the network — so the fast tier proves it in
# milliseconds and a golden pins every byte. Conservative BY CONSTRUCTION (D6: a mis-mapped row skips
# real coverage while reporting green, and nobody watching the repo would notice): a row appears only
# where the stack's own convention makes the pairing unambiguous, a doubtful one over-selects, and
# everything else is a SKIP line — a decision said aloud, as data. Three top-level fns and no nested
# helpers (api-kit records every definition line); the per-path bookkeeping is one POSIX awk pass
# under LC_ALL=C, the decisions are bash builtins + match_one with ARGS. Bash 3.2: no case inside
# $(...), no mapfile, no assoc arrays.

surfaces_runner() { # surfaces_runner <ls-file> — ONE line `<runner><TAB><template>` rc 0, or nothing rc 1
  # (no runner this kit can PROVE takes path arguments). Detection ORDER, first match wins, over
  # the list + the manifests it names: node by grep on package.json (the "test" script naming
  # vitest, then jest; else a "vitest" key, then a "jest" key; else NOT node — fall through) →
  # pytest by its five tells → go by go.mod (go takes PACKAGE paths, never test files: its template
  # is the whole suite, over-selection by design, and every scaffolded go row carries a COMPLETE
  # cmd). mocha · cargo · dotnet · rspec · make · a bare `npm test` with an unknown script ⇒ rc 1:
  # each filters by NAME, not path, or cannot be proven to take one, so the command says NORUNNER
  # instead of guessing. grep only, no python.
  local ls="${1:-}" m="" v=""
  if grep -qxF 'package.json' "$ls" 2>/dev/null; then
    m="$PRIMARY/package.json"
    v="$(grep -oE '"test"[[:space:]]*:[[:space:]]*"[^"]*"' "$m" 2>/dev/null || true)"
    case "$v" in
      *vitest*) printf 'vitest\tnpx vitest run {tests}\n'; return 0;;
      *jest*)   printf 'jest\tnpx jest {tests}\n'; return 0;;
    esac
    if grep -qE '"vitest"[[:space:]]*:' "$m" 2>/dev/null; then printf 'vitest\tnpx vitest run {tests}\n'; return 0; fi
    if grep -qE '"jest"[[:space:]]*:' "$m" 2>/dev/null; then printf 'jest\tnpx jest {tests}\n'; return 0; fi
  fi
  if grep -qxF 'pytest.ini' "$ls" 2>/dev/null \
    || grep -qE '(^|/)conftest\.py$' "$ls" 2>/dev/null \
    || { grep -qxF 'pyproject.toml' "$ls" 2>/dev/null && grep -q '\[tool\.pytest' "$PRIMARY/pyproject.toml" 2>/dev/null; } \
    || { grep -qxF 'setup.cfg' "$ls" 2>/dev/null && grep -q '\[tool:pytest\]' "$PRIMARY/setup.cfg" 2>/dev/null; } \
    || grep -qE '^(tests?/|.*/tests?/).*test_[^/]*\.py$' "$ls" 2>/dev/null; then
    printf 'pytest\tpytest {tests}\n'; return 0
  fi
  if grep -qxF 'go.mod' "$ls" 2>/dev/null; then printf 'go\tgo test ./...\n'; return 0; fi
  return 1
}

surfaces_pairs() { # surfaces_pairs <runner> <ls-file> — candidate rows `<surface><TAB><tests><TAB><cmd><TAB><note>`
  # sorted by surface (LC_ALL=C), then the SKIP lines (`SKIP<TAB><what><TAB><reason>`), rc 0 always.
  # A row appears ONLY where the stack's own convention implies it (§ 13 pairing rules); `<name>`
  # is used verbatim (no case-folding, no plural guessing), the repo root is never a surface. A
  # "source dir" holds ≥ 1 tracked path of its own, has ≤ 3 components, and none of them is
  # `tests test __tests__ spec __mocks__ node_modules` (that is what "outside the tests tree" means
  # here — a dir under node_modules/ or spec/ pairs with nothing).
  #   pytest  (a) tests/<name>/ · test/<name>/ ↔ EXACTLY ONE source dir of basename <name>
  #           (b) tests/…/test_<name>.py ↔ EXACTLY ONE path **/<name>.py outside the tests tree
  #           (c) in-package <dir>/tests/ ↔ its parent source dir
  #   jest · vitest  (a) <dir>/__tests__/ ↔ its parent source dir; (b) tests|test|__tests__/<name>/
  #           as pytest (a); (c) co-located: every source dir with a *.test.<ext> (*.spec.<ext>)
  #           beneath it, outside any test dir — the tests glob crosses slashes, like the gate's
  #   go      every dir holding a *_test.go, with a COMPLETE `go test ./<dir>/...`
  # The awk pass emits the per-stack candidates with a sort key (`1<TAB><surface><TAB><rank>…`, so
  # one LC_ALL=C sort orders them by surface, then by the rule that made them, broadest cmd first)
  # and the AMBIGUITY skips (`0<TAB>…`). Then the shared filters, in order: 1. ambiguity (0 or ≥ 2
  # matches ⇒ no row) · 2. breadth (a surface over 200 paths is dropped; its descendants may
  # qualify alone) · 3. ancestor: a candidate is folded when an EMITTED row's surface is a prefix
  # of its surface AND that row's cmd runs the candidate's tests dir too — a fold that dropped
  # tests the survivor never runs (src/api/ ↔ tests/api/ swallowing src/api/ ↔ src/api/tests/)
  # would be D6's silent skip, so such pairs stay as two rows and `qa` runs both. Every emitted
  # surface and tests glob matches ≥ 1 list path by construction.
  local runner="${1:-}" ls="${2:-}" run="" tab nl out="" line="" rest="" surface="" tests="" scope="" n=""
  local rows="" askips="" bskips="" emitted="" es="" esc="" f="" folded=0
  tab="$POLARIS_TAB"; nl=$'\n'
  case "$runner" in
    jest)      run="npx jest";;
    vitest)    run="npx vitest run";;
    pytest|go) ;;
    *)         return 0;;
  esac
  out="$(LC_ALL=C awk -v runner="$runner" -v run="$run" '
    BEGIN { nex = split("tests test __tests__ spec __mocks__ node_modules", ex, " ")
            for (i = 1; i <= nex; i++) EX[ex[i]] = 1
            node = (runner == "jest" || runner == "vitest"); pyt = (runner == "pytest"); go = (runner == "go") }
    { p = $0; sub(/\r$/, "", p); sub(/^\.\//, "", p)
      if (p == "") next
      np++; P[np] = p
      nc = split(p, c, "/"); d = ""; bad = 0
      for (i = 1; i < nc; i++) {
        d = (i == 1) ? c[i] : d "/" c[i]
        if (c[i] in EX) bad = 1
        if (!(d in cnt)) { nd++; D[nd] = d; depth[d] = i; base[d] = c[i]; clean[d] = !bad
                           par[d] = (i == 1) ? "" : substr(d, 1, length(d) - length(c[i]) - 1) }
        cnt[d]++
      }
      if (nc > 1) direct[d]++
      b = c[nc]
      if (!bad) { cb[b]++; lb[b] = (b in lb) ? (lb[b] SUBSEP p) : p } }
    END {
      for (k = 1; k <= nd; k++) { d = D[k]
        if ((d in direct) && depth[d] <= 3 && clean[d]) { src[d] = 1; b = base[d]; cs[b]++; ls[b] = (b in ls) ? (ls[b] SUBSEP d) : d } }
      # --- the EXACTLY-ONE queries: pytest (a) (b) · jest (b) ---
      for (k = 1; k <= nd; k++) { d = D[k]
        if (depth[d] != 2 || !(pyt || node)) continue
        r = par[d]
        if (r != "tests" && r != "test" && !(node && r == "__tests__")) continue
        nq++; QW[nq] = d "/"; QN[nq] = base[d]; QK[nq] = 1; QR[nq] = pyt ? 1 : 3
        QC[nq] = pyt ? ("pytest " d "/") : (run " " d); QT[nq] = base[d] " tests" }
      if (pyt) for (k = 1; k <= np; k++) { p = P[k]
        if (p !~ /^tests?\/(.*\/)?test_[^\/]+\.py$/) continue
        n = p; sub(/.*\//, "", n); sub(/^test_/, "", n); sub(/\.py$/, "", n)
        nq++; QW[nq] = p; QN[nq] = n; QK[nq] = 2; QR[nq] = 2; QC[nq] = "pytest " p; QT[nq] = n }
      for (q = 1; q <= nq; q++) {
        if (QK[q] == 1) { m = (QN[q] in cs) ? cs[QN[q]] : 0; if (m) split(ls[QN[q]], M, SUBSEP) }
        else { b = QN[q] ".py"; m = (b in cb) ? cb[b] : 0; if (m) split(lb[b], M, SUBSEP) }
        if (m == 1) { s = (QK[q] == 1) ? (M[1] "/") : M[1]
          print "1\t" s "\t" QR[q] "\t" ((QK[q] == 1) ? cnt[M[1]] : 1) "\t" QW[q] "\t" QC[q] "\t" QT[q]; continue }
        lst = ""
        if (m > 1) {
          for (i = 2; i <= m; i++) { v = M[i]; for (j = i - 1; j >= 1 && (M[j] "") > (v ""); j--) M[j + 1] = M[j]; M[j + 1] = v }
          lst = " (" M[1]; for (i = 2; i <= m; i++) lst = lst " " M[i]; lst = lst ")" }
        print "0\t" QW[q] "\tambiguous: " QN[q] " matches " m " dirs" lst }
      # --- pytest (c): in-package <dir>/tests/ ---
      if (pyt) for (k = 1; k <= nd; k++) { d = D[k]
        if (base[d] != "tests" || par[d] == "" || !(par[d] in src)) continue
        print "1\t" par[d] "/\t3\t" cnt[par[d]] "\t" d "/\tpytest " d "/\t" base[par[d]] " tests" }
      if (node) {
        # --- jest (a): <dir>/__tests__/ ---
        for (k = 1; k <= nd; k++) { d = D[k]
          if (base[d] != "__tests__" || par[d] == "" || !(par[d] in src)) continue
          print "1\t" par[d] "/\t2\t" cnt[par[d]] "\t" d "/\t" run " " d "\t" base[par[d]] " tests" }
        # --- jest (c): co-located, every source-dir ancestor of a *.test.<ext> / *.spec.<ext> ---
        for (k = 1; k <= np; k++) { p = P[k]
          if (p !~ /\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs)$/) continue
          kind = (p ~ /\.spec\.(js|jsx|ts|tsx|mjs|cjs)$/) ? "spec" : "test"
          nc = split(p, c, "/"); if (nc == 1) continue
          d = substr(p, 1, length(p) - length(c[nc]) - 1)
          if (!clean[d]) continue
          d = ""
          for (i = 1; i < nc; i++) { d = (i == 1) ? c[i] : d "/" c[i]
            if ((d in src) && !((d, kind) in co)) { co[d, kind] = 1
              print "1\t" d "/\t1\t" cnt[d] "\t" d "/*." kind ".*\t" run " " d "\t" base[d] " co-located tests" } } } }
      # --- go: every dir holding a *_test.go ---
      if (go) for (k = 1; k <= np; k++) { p = P[k]
        if (p !~ /_test\.go$/) continue
        nc = split(p, c, "/"); if (nc == 1) continue
        d = substr(p, 1, length(p) - length(c[nc]) - 1)
        if (d in gd) continue
        gd[d] = 1
        print "1\t" d "/\t1\t" cnt[d] "\t" d "/*_test.go\tgo test ./" d "/...\t" base[d] " package tests" }
    }' "$ls" 2>/dev/null | LC_ALL=C sort)" || out=""
  while IFS= read -r line; do
    case "$line" in
      "")         continue;;
      "0$tab"*)   askips="$askips${nl}SKIP$tab${line#0$tab}"; continue;;
    esac
    line="${line#1$tab}"
    surface="${line%%$tab*}"; rest="${line#*$tab}"
    rest="${rest#*$tab}"                                    # the rank did its work in the sort
    n="${rest%%$tab*}"; rest="${rest#*$tab}"                # rest = tests<TAB>cmd<TAB>note
    tests="${rest%%$tab*}"; scope="${tests%%\**}"           # what the cmd runs: the glob up to its first *
    if [ "$n" -gt 200 ]; then
      bskips="$bskips${nl}SKIP$tab$surface${tab}surface matches $n paths (>200)"; continue
    fi
    f=""
    while IFS="$tab" read -r es esc; do
      [ -n "$es" ] || continue
      case "$es" in "$surface") ;; */) case "$surface" in "$es"*) ;; *) continue;; esac;; *) continue;; esac
      case "$esc" in "$scope") f=1; break;; */) case "$scope" in "$esc"*) f=1; break;; esac;; esac
    done <<EOF
$emitted
EOF
    if [ -n "$f" ]; then folded=$((folded + 1)); continue; fi
    emitted="$emitted$nl$surface$tab$scope"
    rows="$rows$nl$surface$tab$rest"
  done <<EOF
$out
EOF
  [ -z "$rows" ] || printf '%s\n' "${rows#"$nl"}"
  [ -z "$askips" ] || printf '%s\n' "${askips#"$nl"}"
  [ -z "$bskips" ] || printf '%s\n' "${bskips#"$nl"}"
  [ "$folded" -eq 0 ] || printf 'SKIP\t%s narrower pairing(s)\tcovered by an emitted ancestor row\n' "$folded"
  return 0
}

surfaces_proposal() { # surfaces_proposal <ls-file> [<map-file>] — the whole decision as DATA, rc 0 always,
  # lines in this order: `RUNNER<TAB><runner><TAB><template>` · `ROW<TAB><surface><TAB><tests><TAB><cmd><TAB><note>`
  # (survivors, sorted) · `SKIP<TAB><what><TAB><reason>` (one per dropped pairing) — or, as the ONLY
  # line, `NORUNNER<TAB>no test runner this kit can scope (…) — seen: <manifests>`. On top of
  # surfaces_pairs it drops a pair already in <map-file> (`already mapped to <tests>`) and a
  # self-covering one (`match_one <surface> <tests>` — surfaces_health's exact test: the one row
  # shape that would make the whole map lie). Deterministic over (manifests, list, map): same
  # input, same bytes — it is goldened. <map-file> is the caller's $SURFACES when it exists.
  local ls="${1:-}" map="${2:-}" tab nl rp="" runner="" seen="" mapped="" out="" line="" rest=""
  local surface="" tests="" rskips="" pskips=""
  tab="$POLARIS_TAB"; nl=$'\n'
  if ! rp="$(surfaces_runner "$ls")"; then
    seen="$(LC_ALL=C awk 'BEGIN { n = split("package.json pyproject.toml setup.cfg pytest.ini go.mod Cargo.toml Makefile Gemfile", m, " ") }
      { p = $0; sub(/\r$/, "", p); seen[p] = 1 }
      END { s = ""; for (i = 1; i <= n; i++) if (m[i] in seen) s = s (s == "" ? "" : " ") m[i]; print s }' "$ls" 2>/dev/null || true)"
    printf 'NORUNNER\tno test runner this kit can scope (pytest · jest · vitest · go) — seen: %s\n' "${seen:-no manifest}"
    return 0
  fi
  printf 'RUNNER\t%s\n' "$rp"
  runner="${rp%%$tab*}"
  if [ -n "$map" ] && [ -f "$map" ]; then
    mapped="$(awk -F "$tab" '/^[[:space:]]*#/ || /^[[:space:]]*$/ { next } { sub(/\r$/, ""); print $1 "\t" $2 }' "$map" 2>/dev/null || true)"
  fi
  out="$(surfaces_pairs "$runner" "$ls")"
  while IFS= read -r line; do
    case "$line" in
      "")           continue;;
      "SKIP$tab"*)  pskips="$pskips$nl$line"; continue;;
    esac
    surface="${line%%$tab*}"; rest="${line#*$tab}"; tests="${rest%%$tab*}"
    case "$nl$mapped$nl" in
      *"$nl$surface$tab$tests$nl"*) rskips="$rskips${nl}SKIP$tab$surface${tab}already mapped to $tests"; continue;;
    esac
    if match_one "$surface" "$tests"; then
      rskips="$rskips${nl}SKIP$tab$surface${tab}tests glob covers its own surface"; continue
    fi
    printf 'ROW\t%s\n' "$line"
  done <<EOF
$out
EOF
  [ -z "$rskips" ] || printf '%s\n' "${rskips#"$nl"}"
  [ -z "$pskips" ] || printf '%s\n' "${pskips#"$nl"}"
  return 0
}
