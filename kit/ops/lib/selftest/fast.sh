# lib/selftest/fast.sh — the in-process tier (ops/contracts/fast-tier.md): `polaris doctor --fast`.
# One pass over the kit's PURE functions, already sourced by the loader — zero `polaris`
# re-invocations, no scratch git repo, no `$SELF`. The drills keep proving the real entry point at
# the wave gate and in CI; this tier proves the logic on every change, in seconds. Fork budget: ONE
# `mktemp -d`, TWO `date +%s`, one subshell per section (plus the `$(...)` that captures a function's
# stdout); a fork inside a function under test is that function's, not the tier's. Every fixture
# lives under $FT_TMP, written with builtins; globals are overridden ONLY inside a section's
# subshell, so nothing here can reach the live board or write under $PRIMARY.
# Exactly three top-level functions (v1 rule for extenders: new sections go INSIDE selftest_fast).
# bash 3.2: no mapfile, no `case` inside $(...), no ${var^^}, no `wait -n`.

FT_TMP=""      # the one temp dir; set by selftest_fast, removed by its EXIT trap
FT_SEC=""      # the running section's name — set FIRST inside each section subshell
FT_N=0         # ft_assert calls in this section (per subshell; ft_section hands it to the parent)
FT_RED=0       # 1 once any ft_assert in this section failed

ft_assert() { # ft_assert <label> <cmd…> — run "$@" as a bash command (a function call, never a
  # subprocess), count it, and on non-zero print the contract's red line. A leading `!` inverts:
  # the reserved word is not recognized through "$@", so the inversion is spelled here. Output of
  # the command under test is discarded — id_ok's ⛔ line on a rejection is the EXPECTED noise.
  # Never returns non-zero: the run CONTINUES on red (one pass paints the whole picture), and a
  # non-zero return under the entry script's `set -e` would kill the section's subshell instead.
  local _lbl="$1" _want=0 _got=0
  shift
  if [ "${1:-}" = "!" ]; then _want=1; shift; fi
  FT_N=$((FT_N+1))
  if "$@" >/dev/null 2>&1; then _got=0; else _got=1; fi
  if [ "$_got" -ne "$_want" ]; then
    FT_RED=1
    printf '⛔ FAST %s FAIL (%s)\n' "$(printf '%s' "$FT_SEC" | tr '[:lower:]' '[:upper:]')" "$_lbl"
  fi
  return 0
}

ft_section() { # ft_section <name> — close the section: hand this subshell's assert count to the
  # parent (one appended line, a builtin redirect — no fork), print `✅ fast: <name>` ONLY when no
  # ft_assert in it failed, and return the section's verdict so the parent's `|| ft_red=1` sees it.
  printf '%s\n' "$FT_N" >> "$FT_TMP/n"
  if [ "$FT_RED" -eq 0 ]; then printf '✅ fast: %s\n' "$1"; return 0; fi
  return 1
}

selftest_fast() { # the run — rc 0 all green / rc 1 any red; last line on green:
  # `✅ fast tier passed — <n> checks in <s>s`. Sources NOTHING. Each section is one subshell that
  # sets FT_SEC first, overrides whatever globals it needs, asserts, and ends with ft_section.
  local ft_t0 ft_t1 ft_red=0 ft_n=0 ft_k ft_tf ft_conv ft_rules ft_nl ft_cr ft_tab ft_surf ft_sel ft_sc ft_iv
  ft_nl=$'\n'; ft_cr=$'\r'; ft_tab="$POLARIS_TAB"
  ft_t0="$(date +%s)"
  FT_TMP="$(mktemp -d)"
  trap 'rm -rf "$FT_TMP"' EXIT
  : > "$FT_TMP/n"
  # ---- fixtures: written once, with builtins only (printf > file); every section reads its own
  ft_tf="$FT_TMP/T-9.md"          # a task file — frontmatter AND commit-msg read this one
  printf '%s\n' '---' > "$ft_tf"
  printf 'id: T-9\r\n' >> "$ft_tf"                    # the one CR-terminated line: fm_get must strip it
  printf '%s\n' \
    'title: Hello world   # the title, with a trailing comment' \
    'type: feature' \
    'scope: fast' \
    'files_owned: [ a.sh,b.sh ,  ]' \
    'context_files:' \
    '  - x.md' \
    '  - y.md   # a comment on a block item' \
    'depends_on: []' \
    'tags:   [ ]' \
    'points: 1' \
    '---' \
    '## Why' \
    'Because the tier must see the Why.' \
    '## Acceptance criteria' \
    '- [ ] one box' \
    '## Notes' \
    '- found: a note' \
    'id: T-99' >> "$ft_tf"                            # a body line shaped like a key: fm_get must ignore it
  ft_conv="$FT_TMP/CONVENTIONS.md"
  printf '%s\n' 'voice: technical   # how agents talk' \
    'lint:   # none' \
    'base: main' \
    'voice: standard' > "$ft_conv"
  ft_rules="$FT_TMP/RULES.tsv"
  printf '%s\n' '# a comment line' \
    '' \
    '   ' \
    '   # an indented comment' > "$ft_rules"
  printf 'path\tsecrets/\r\n' >> "$ft_rules"
  printf 'content\tAKIA[0-9A-Z]{16}\n' >> "$ft_rules"
  printf 'ask\t.github/\n' >> "$ft_rules"
  printf 'TICK=30\nOTHER=1\n' > "$FT_TMP/config"    # the keep-awake registry file, at its home root

  # ---- semver
  ( FT_SEC=semver
    ft_assert '6.2.10 > 6.2.9'      semver_gt 6.2.10 6.2.9
    ft_assert '7.0.0 > 6.9.9'       semver_gt 7.0.0 6.9.9
    ft_assert '6.3.0 > 6.2.2'       semver_gt 6.3.0 6.2.2
    ft_assert 'NOT 6.2.2 > 6.2.2'   ! semver_gt 6.2.2 6.2.2
    ft_assert 'NOT 6.2.2 > 6.3.0'   ! semver_gt 6.2.2 6.3.0
    ft_assert '10.0.0 > 9.9.9'      semver_gt 10.0.0 9.9.9
    ft_section semver ) || ft_red=1

  # ---- frontmatter
  ( FT_SEC=frontmatter
    ft_assert 'fm_get scalar, trailing comment stripped' test "$(fm_get title "$ft_tf")" = 'Hello world'
    ft_assert 'fm_get strips \r'                          test "$(fm_get id "$ft_tf")" = 'T-9'
    ft_assert 'fm_get absent key → empty'                test -z "$(fm_get nope "$ft_tf")"
    ft_assert 'fm_list [] → nothing'                     test -z "$(fm_list depends_on "$ft_tf")"
    ft_assert 'fm_list [ ] with spaces → nothing'        test -z "$(fm_list tags "$ft_tf")"
    ft_assert 'fm_list flow list, messy spacing'         test "$(fm_list files_owned "$ft_tf" | tr '\n' ' ')" = 'a.sh b.sh '
    ft_assert 'fm_list block list, item comment stripped' test "$(fm_list context_files "$ft_tf" | tr '\n' ' ')" = 'x.md y.md '
    ft_assert 'fm_list inline scalar → one item'         test "$(fm_list scope "$ft_tf")" = 'fast'
    ft_section frontmatter ) || ft_red=1

  # ---- cfg
  ( FT_SEC=cfg; CONV="$ft_conv"
    ft_assert 'value, comment stripped, first match wins' test "$(cfg voice x)" = 'technical'
    ft_assert 'plain value'                              test "$(cfg base x)" = 'main'
    ft_assert 'absent key → default'                     test "$(cfg nope dflt)" = 'dflt'
    # `lint:   # none` — the value is EMPTY, never the comment text; cfg's own contract (core.sh)
    # then applies the default to an empty value, and `cfg lint ""` is how callers read it as empty.
    ft_assert 'empty value with comment → never the comment text' test "$(cfg lint dflt)" = 'dflt'
    ft_assert 'empty value, empty default → empty'          test -z "$(cfg lint '')"
    CONV="$FT_TMP/no-such-file"
    ft_assert 'no CONVENTIONS file → default'             test "$(cfg voice dflt)" = 'dflt'
    ft_section cfg ) || ft_red=1

  # ---- ownership
  ( FT_SEC=ownership
    ft_assert 'exact'                         match_one src/a.py src/a.py
    ft_assert 'dir/ prefix'                   match_one src/api/x/y.py src/api/
    ft_assert 'glob * crosses /'              match_one src/api/x/util_a.py 'src/*/util_*.py'
    ft_assert 'glob * crosses / (dir depth)'  match_one src/api/x/util_a.py 'src/api/*.py'
    ft_assert 'glob non-match rc 1'           ! match_one src/api/x/other.py 'src/*/util_*.py'
    ft_assert 'dir/ does not match sibling'   ! match_one src/apix/y.py src/api/
    ft_assert 'owned_match: any pattern hits' owned_match src/a.py docs/ '' src/a.py
    ft_assert 'owned_match: none hit rc 1'    ! owned_match src/b.py docs/ src/a.py
    ft_section ownership ) || ft_red=1

  # ---- ids
  ( FT_SEC=ids
    ft_assert 'T-9 accepted'          id_ok T-9
    ft_assert 'empty rejected rc 1'   ! id_ok ''
    ft_assert 'literal feat rejected' ! id_ok feat
    ft_section ids ) || ft_red=1

  # ---- commit-msg
  ( FT_SEC=commit-msg
    ft_msg="$(cmd_task_commit_msg "$ft_tf" 2>/dev/null)" || ft_msg=""
    ft_assert 'line 1 = type(scope): title [ID]' test "${ft_msg%%$ft_nl*}" = 'feat(fast): Hello world [T-9]'
    ft_assert 'body carries the ## Why text'  test "${ft_msg#*Because the tier must see the Why.}" != "$ft_msg"
    ft_assert 'body carries the Notes line'   test "${ft_msg#*- found: a note}" != "$ft_msg"
    ft_assert 'body carries Files:'           test "${ft_msg#*Files: a.sh, b.sh}" != "$ft_msg"
    ft_section commit-msg ) || ft_red=1

  # ---- json
  ( FT_SEC=json
    ft_assert 'escapes " and \'      test "$(jesc 'a"b\c')" = 'a\"b\\c'
    ft_assert 'drops newlines'        test "$(jesc "x${ft_nl}y${ft_cr}${ft_nl}")" = 'xy'
    ft_assert 'plain text untouched'  test "$(jesc 'plain text')" = 'plain text'
    ft_section json ) || ft_red=1

  # ---- rules
  ( FT_SEC=rules; RULES="$ft_rules"; _RULES_CACHED=""; _RULES_CACHE=""
    ft_out="$(rules_lines)" || ft_out=""
    ft_k=0; while IFS= read -r ft_line; do ft_k=$((ft_k+1)); done <<EOF
$ft_out
EOF
    ft_assert 'exactly the three rule lines survive' test "$ft_k" = 3
    ft_assert 'comments dropped'   test "${ft_out#*#}" = "$ft_out"
    ft_assert 'CR dropped'         test "${ft_out#*$ft_cr}" = "$ft_out"
    ft_assert 'path kind survives'    test "${ft_out#*path	secrets/}" != "$ft_out"
    ft_assert 'content kind survives' test "${ft_out#*content	AKIA}" != "$ft_out"
    ft_assert 'ask kind survives'     test "${ft_out#*ask	.github/}" != "$ft_out"
    _RULES_CACHED=""; _RULES_CACHE=""; RULES="$FT_TMP/no-such-file"
    ft_assert 'missing file → empty, rc 0' test -z "$(rules_lines)"
    ft_section rules ) || ft_red=1

  # ---- awake-conf
  ( FT_SEC=awake-conf; POLARIS_AWAKE_HOME="$FT_TMP"; unset POLARIS_AWAKE_TICK
    ft_assert 'config file beats the default' test "$(awake_conf TICK 55)" = '30'
    ft_assert 'absent key → default'          test "$(awake_conf NOPE 9)" = '9'
    POLARIS_AWAKE_TICK=7
    ft_assert 'env beats the config file'     test "$(awake_conf TICK 55)" = '7'
    POLARIS_AWAKE_HOME="$FT_TMP/no-such-dir"; unset POLARIS_AWAKE_TICK
    ft_assert 'no config file → default'      test "$(awake_conf TICK 55)" = '55'
    ft_section awake-conf ) || ft_red=1

  # ---- bg
  ( FT_SEC=bg
    ft_assert '42 → 42s'       test "$(bg_age 42)" = '42s'
    ft_assert '420 → 7m'       test "$(bg_age 420)" = '7m'
    ft_assert '10800 → 3h'     test "$(bg_age 10800)" = '3h'
    ft_assert '0 → 0s'         test "$(bg_age 0)" = '0s'
    ft_assert 'junk → 0s'      test "$(bg_age abc)" = '0s'
    ft_section bg ) || ft_red=1

  # ---- quiescent (auto-update.md § board_quiescent) — the gate that keeps `update --auto` from
  # firing mid-task. One fixture tree per reason, so every case carries exactly ONE reason and the
  # pinned QUIET_WHY is the first (and only) one found; the globals it reads are overridden inside
  # the subshell, one assignment per case. The directories are the tier's one `mkdir -p` (a dir
  # cannot be made with builtins); the files are `: >`. The live pid is this shell's own ($$) —
  # a dead-pid case would be a guess about the pid table, and bg-jobs.md judges rc-file FIRST anyway.
  mkdir -p "$FT_TMP/q/empty/board/ready" "$FT_TMP/q/empty/board/active" "$FT_TMP/q/empty/board/review" \
    "$FT_TMP/q/empty/locks" "$FT_TMP/q/ready/board/ready" "$FT_TMP/q/active/board/active" \
    "$FT_TMP/q/review/board/review" "$FT_TMP/q/lock/locks/T-7" "$FT_TMP/q/lease/locks" \
    "$FT_TMP/q/bgrun/.polaris/bg/j1" "$FT_TMP/q/bgrc/.polaris/bg/j2" "$FT_TMP/q/bgprev/.polaris/bg/j3.prev"
  : > "$FT_TMP/q/ready/board/ready/T-1.md"
  : > "$FT_TMP/q/active/board/active/T-1.md"
  : > "$FT_TMP/q/review/board/review/T-1.md"
  : > "$FT_TMP/q/review/board/review/T-2.md"
  : > "$FT_TMP/q/review/board/review/notes.txt"          # not a .md — never a task
  : > "$FT_TMP/q/lease/locks/.int-lease"
  printf '%s\n' "$$" > "$FT_TMP/q/bgrun/.polaris/bg/j1/pid"
  printf '%s\n' "$$" > "$FT_TMP/q/bgrc/.polaris/bg/j2/pid"
  printf '0\n'       > "$FT_TMP/q/bgrc/.polaris/bg/j2/rc"
  printf '%s\n' "$$" > "$FT_TMP/q/bgprev/.polaris/bg/j3.prev/pid"
  ( FT_SEC=quiescent
    BOARD="$FT_TMP/q/empty/board"; LOCKS="$FT_TMP/q/empty/locks"; PRIMARY="$FT_TMP/q/empty"; QUIET_WHY=x
    ft_assert 'empty dirs → quiet, rc 0'          board_quiescent
    ft_assert 'quiet → QUIET_WHY empty'           test -z "$QUIET_WHY"
    BOARD="$FT_TMP/q/ready/board"
    ft_assert 'a .md in ready/ → busy'            ! board_quiescent
    ft_assert 'QUIET_WHY = ready: 1'              test "$QUIET_WHY" = 'ready: 1'
    BOARD="$FT_TMP/q/active/board"
    ft_assert 'a .md in active/ → busy'           ! board_quiescent
    ft_assert 'QUIET_WHY = active: 1'             test "$QUIET_WHY" = 'active: 1'
    BOARD="$FT_TMP/q/review/board"
    ft_assert 'two .md in review/ → busy'         ! board_quiescent
    ft_assert 'QUIET_WHY = review: 2 (.txt not counted)' test "$QUIET_WHY" = 'review: 2'
    BOARD="$FT_TMP/q/empty/board"; LOCKS="$FT_TMP/q/lock/locks"
    ft_assert 'a task lock dir → busy'            ! board_quiescent
    ft_assert 'QUIET_WHY = lock: T-7'             test "$QUIET_WHY" = 'lock: T-7'
    LOCKS="$FT_TMP/q/lease/locks"
    ft_assert '.int-lease alone → busy'           ! board_quiescent
    ft_assert 'QUIET_WHY = integration lease held' test "$QUIET_WHY" = 'integration lease held'
    LOCKS="$FT_TMP/q/empty/locks"; PRIMARY="$FT_TMP/q/bgrun"
    ft_assert 'bg job: live pid, no rc → busy'    ! board_quiescent
    ft_assert 'QUIET_WHY = bg job running: j1'    test "$QUIET_WHY" = 'bg job running: j1'
    PRIMARY="$FT_TMP/q/bgrc"
    ft_assert 'bg job: rc file present → not running (rc first)' board_quiescent
    PRIMARY="$FT_TMP/q/bgprev"
    ft_assert 'bg job: a .prev dir is never running' board_quiescent
    ft_section quiescent ) || ft_red=1

  # ---- dirt (auto-update.md § update_dirt_overlaps_kit) — stdin is `git status --porcelain`;
  # rc 0 = a dirty path is one install.sh overwrites. Here-strings feed the function: no fork,
  # and the leading space of ` M` survives quoting. The pinned five, then the edges: a rename
  # tests its NEW path, the repo's own state under ops/ never counts, an empty status never overlaps.
  ( FT_SEC=dirt
    ft_assert '?? src/x.py → rc 1'                       ! update_dirt_overlaps_kit <<< '?? src/x.py'
    ft_assert ' M ops/lib/core.sh → rc 0'                  update_dirt_overlaps_kit <<< ' M ops/lib/core.sh'
    ft_assert ' M ops/CONVENTIONS.md → rc 1'             ! update_dirt_overlaps_kit <<< ' M ops/CONVENTIONS.md'
    ft_assert 'R  a.txt -> CLAUDE.md → rc 0 (NEW path)'    update_dirt_overlaps_kit <<< 'R  a.txt -> CLAUDE.md'
    ft_assert '?? ops/board/ready/T-1.md → rc 1'         ! update_dirt_overlaps_kit <<< '?? ops/board/ready/T-1.md'
    ft_assert 'R  CLAUDE.md -> notes.md → rc 1 (OLD path ignored)' ! update_dirt_overlaps_kit <<< 'R  CLAUDE.md -> notes.md'
    ft_assert ' M ops/contracts/x.md → rc 1'             ! update_dirt_overlaps_kit <<< ' M ops/contracts/x.md'
    ft_assert ' M ops/RULES.tsv → rc 1'                  ! update_dirt_overlaps_kit <<< ' M ops/RULES.tsv'
    ft_assert ' M ops/tests/x.expected → rc 1'           ! update_dirt_overlaps_kit <<< ' M ops/tests/x.expected'
    ft_assert ' M ops/polaris → rc 0'                      update_dirt_overlaps_kit <<< ' M ops/polaris'
    ft_assert ' M .claude/settings.json → rc 0'            update_dirt_overlaps_kit <<< ' M .claude/settings.json'
    ft_assert ' M .claude/skills/polaris/SKILL.md → rc 0'  update_dirt_overlaps_kit <<< ' M .claude/skills/polaris/SKILL.md'
    ft_assert ' M .claude/skills/mine/SKILL.md → rc 1'   ! update_dirt_overlaps_kit <<< ' M .claude/skills/mine/SKILL.md'
    ft_assert ' M .gitignore → rc 0'                       update_dirt_overlaps_kit <<< ' M .gitignore'
    ft_assert 'quoted path under ops/lib → rc 0'           update_dirt_overlaps_kit <<< '?? "ops/lib/we ird.sh"'
    ft_assert 'CR-terminated kit path → rc 0'              update_dirt_overlaps_kit <<< " M ops/lib/core.sh${ft_cr}"
    ft_assert 'app dirt then kit dirt → rc 0'              update_dirt_overlaps_kit <<< "?? src/x.py${ft_nl} M ops/lib/core.sh"
    ft_assert 'app dirt only, two lines → rc 1'          ! update_dirt_overlaps_kit <<< "?? src/x.py${ft_nl} M README.md"
    ft_assert 'empty status → rc 1'                      ! update_dirt_overlaps_kit <<< ''
    ft_section dirt ) || ft_red=1


  # ---- surfaces-tsv (test-surfaces.md § 1, § 4) — surfaces_lines over a temp ops/SURFACES.tsv:
  # comments, blank lines and CRs go, rows survive in file order, an absent file is zero rows at
  # rc 0, and the memo holds until _SURFACES_CACHED is reset. The memo is primed by an ft_assert
  # call in the section shell ITSELF — a $(...) primes only its own subshell, which exits with the
  # cache (T-134's lesson) — so the read that follows, through $(...), inherits the primed state.
  # surfaces_seed writes the header iff the path is absent and never rewrites what exists.
  ft_surf="$FT_TMP/SURFACES.tsv"
  printf '%s\n' '# POLARIS SURFACES — a header line' '' '   ' > "$ft_surf"
  printf 'src/api/\ttests/api/\t-\tthe HTTP API [T-9]\r\n' >> "$ft_surf"
  printf '   # an indented comment\n' >> "$ft_surf"
  printf 'kit/ops/lib/integrate.sh\tkit/ops/lib/selftest/history.sh\tbash kit/ops/polaris doctor --selftest --only express,tcm\tthe integrator lane [T-140]\n' >> "$ft_surf"
  printf 'src/*.py\ttests/unit/\t-\tevery python file [T-1]\n' >> "$ft_surf"
  ( FT_SEC=surfaces-tsv; SURFACES="$ft_surf"; _SURFACES_CACHED=""; _SURFACES_CACHE=""
    ft_out="$(surfaces_lines)" || ft_out=""
    ft_k=0; while IFS= read -r ft_line; do ft_k=$((ft_k+1)); done <<EOF
$ft_out
EOF
    ft_assert 'exactly the three rows survive'   test "$ft_k" = 3
    ft_assert 'comments dropped'                 test "${ft_out#*#}" = "$ft_out"
    ft_assert 'CR dropped'                       test "${ft_out#*$ft_cr}" = "$ft_out"
    ft_assert 'file order kept: row 1 first'     test "${ft_out%%$ft_nl*}" = "src/api/${ft_tab}tests/api/${ft_tab}-${ft_tab}the HTTP API [T-9]"
    ft_assert 'a complete cmd column survives'   test "${ft_out#*"--only express,tcm${ft_tab}the integrator lane [T-140]"}" != "$ft_out"
    ft_assert 'primes the memo, rc 0'            surfaces_lines
    printf 'src/db/\ttests/db/\t-\ta late row [T-2]\n' >> "$ft_surf"
    ft_assert 'memoized: an append after priming is not seen' test "$(surfaces_lines)" = "$ft_out"
    _SURFACES_CACHED=""
    ft_assert 'reset re-reads: the late row appears'          test "$(surfaces_lines)" = "${ft_out}${ft_nl}src/db/${ft_tab}tests/db/${ft_tab}-${ft_tab}a late row [T-2]"
    SURFACES="$FT_TMP/no-such-file"; _SURFACES_CACHED=""
    ft_assert 'absent file → rc 0'               surfaces_lines
    ft_assert 'absent file → nothing'            test -z "$(surfaces_lines)"
    ft_assert 'seed writes where absent'         surfaces_seed "$FT_TMP/seed.tsv"
    IFS= read -r ft_line < "$FT_TMP/seed.tsv" || ft_line=""
    ft_assert 'seeded line 1 is the # POLARIS SURFACES header' test "${ft_line#"# POLARIS SURFACES"}" != "$ft_line"
    printf 'keep me\n' > "$FT_TMP/keep.tsv"
    surfaces_seed "$FT_TMP/keep.tsv"
    IFS= read -r ft_line < "$FT_TMP/keep.tsv" || ft_line=""
    ft_assert 'seed never rewrites an existing file' test "$ft_line" = 'keep me'
    SURFACES="$FT_TMP/seed.tsv"; _SURFACES_CACHED=""
    ft_assert 'a seeded file is zero rows'       test -z "$(surfaces_lines)"
    ft_section surfaces-tsv ) || ft_red=1

  # ---- surfaces-match — surface_row_matches (column 1 as a files_owned pattern: exact · dir/
  # prefix · glob, by expansion + match_one, no pipe) and surface_rows_for (every covering row,
  # whole line, file order; rc 1 and nothing printed when none). The tsv fixture above now carries
  # four rows — src/api/util.py is covered by the dir/ row AND the src/*.py glob row, in that order.
  ( FT_SEC=surfaces-match; SURFACES="$ft_surf"; _SURFACES_CACHED=""; _SURFACES_CACHE=""
    ft_assert 'exact surface'                    surface_row_matches src/a.py "src/a.py${ft_tab}tests/${ft_tab}-${ft_tab}n"
    ft_assert 'dir/ prefix'                      surface_row_matches src/api/x/y.py "src/api/${ft_tab}tests/api/${ft_tab}-${ft_tab}n"
    ft_assert 'glob * crosses /'                 surface_row_matches src/api/x/util_a.py "src/*/util_*.py${ft_tab}tests/${ft_tab}-${ft_tab}n"
    ft_assert 'glob non-match rc 1'              ! surface_row_matches src/api/x/other.py "src/*/util_*.py${ft_tab}tests/${ft_tab}-${ft_tab}n"
    ft_assert 'dir/ does not match a sibling'    ! surface_row_matches src/apix/y.py "src/api/${ft_tab}tests/${ft_tab}-${ft_tab}n"
    ft_assert 'empty row rc 1'                   ! surface_row_matches src/a.py ''
    ft_assert 'a one-column row still matches'   surface_row_matches src/a.py src/a.py
    ft_out="$(surface_rows_for src/api/util.py)" || ft_out=""
    ft_k=0; while IFS= read -r ft_line; do ft_k=$((ft_k+1)); done <<EOF
$ft_out
EOF
    ft_assert 'rows_for: both covering rows'     test "$ft_k" = 2
    ft_assert 'rows_for: file order, dir/ row first (whole line)' test "${ft_out%%$ft_nl*}" = "src/api/${ft_tab}tests/api/${ft_tab}-${ft_tab}the HTTP API [T-9]"
    ft_assert 'rows_for: the glob row second (whole line)'        test "${ft_out#*$ft_nl}" = "src/*.py${ft_tab}tests/unit/${ft_tab}-${ft_tab}every python file [T-1]"
    ft_assert 'rows_for: rc 0 when one row covers'  surface_rows_for kit/ops/lib/integrate.sh
    ft_assert 'rows_for: none → rc 1'            ! surface_rows_for docs/x.md
    ft_assert 'rows_for: none → prints nothing'  test -z "$(surface_rows_for docs/x.md)"
    ft_section surfaces-match ) || ft_red=1

  # ---- surfaces-select (test-surfaces.md § 4, § 6) — surface_select_cmd <paths-file>: the commands
  # to run INSTEAD of test:, or ONE reason (test_select unset · no rows · no changed paths ·
  # unmapped: <p> (+n more)). Complete cmds deduped in first-appearance order, then ONE template
  # line with every {tests} = the space-joined distinct tests globs of the matched - rows; a
  # template with no {tests} runs verbatim, once. ALL-OR-NOTHING: one unmapped path is the reason.
  ft_sel="$FT_TMP/SELECT.tsv"
  printf 'src/api/\ttests/api/\t-\tapi [T-9]\n' > "$ft_sel"
  printf 'src/db/\ttests/db/\t-\tdb [T-8]\n' >> "$ft_sel"
  printf 'kit/ops/lib/integrate.sh\tkit/ops/lib/selftest/history.sh\tbash kit/ops/polaris doctor --selftest --only express,tcm\tlane [T-140]\n' >> "$ft_sel"
  printf 'kit/ops/lib/core.sh\tkit/ops/lib/selftest/fast.sh\tbash kit/ops/polaris doctor --selftest --only express,tcm\tsame cmd [T-141]\n' >> "$ft_sel"
  printf 'kit/ops/lib/builder.sh\tkit/ops/lib/selftest/board.sh\tbash kit/ops/polaris doctor --fast\tanother cmd [T-142]\n' >> "$ft_sel"
  printf 'test_select: bash kit/ops/polaris doctor --selftest --only {tests}\n' > "$FT_TMP/CONV-select.md"
  printf 'test_select: a {tests} b {tests}\n' > "$FT_TMP/CONV-twice.md"
  printf 'test_select: run-everything\n' > "$FT_TMP/CONV-verbatim.md"
  printf 'src/api/x.py\n' > "$FT_TMP/p-api"
  printf 'src/api/x.py\nsrc/db/y.py\nsrc/api/z.py\n' > "$FT_TMP/p-two"
  printf 'kit/ops/lib/integrate.sh\nkit/ops/lib/core.sh\nkit/ops/lib/builder.sh\nsrc/api/x.py\n' > "$FT_TMP/p-cmds"
  printf 'docs/x.md\n' > "$FT_TMP/p-unmapped"
  printf 'src/api/x.py\ndocs/x.md\nREADME.md\n' > "$FT_TMP/p-mixed"
  : > "$FT_TMP/p-empty"
  ( FT_SEC=surfaces-select; SURFACES="$ft_sel"; CONV="$ft_conv"; _SURFACES_CACHED=""; _SURFACES_CACHE=""
    ft_assert 'test_select unset → rc 1'         ! surface_select_cmd "$FT_TMP/p-api"
    ft_assert 'test_select unset → the reason'   test "$(surface_select_cmd "$FT_TMP/p-api")" = 'test_select unset'
    CONV="$FT_TMP/CONV-select.md"; SURFACES="$FT_TMP/no-such-file"; _SURFACES_CACHED=""
    ft_assert 'no rows → the reason'             test "$(surface_select_cmd "$FT_TMP/p-api")" = 'no rows'
    SURFACES="$ft_sel"; _SURFACES_CACHED=""
    ft_assert 'no changed paths → the reason'    test "$(surface_select_cmd "$FT_TMP/p-empty")" = 'no changed paths'
    ft_assert 'unmapped path → rc 1'             ! surface_select_cmd "$FT_TMP/p-unmapped"
    ft_assert 'unmapped: names the path'         test "$(surface_select_cmd "$FT_TMP/p-unmapped")" = 'unmapped: docs/x.md'
    ft_assert 'all-or-nothing: one mapped, two unmapped → (+1 more)' test "$(surface_select_cmd "$FT_TMP/p-mixed")" = 'unmapped: docs/x.md (+1 more)'
    ft_assert 'one - row → the template with {tests} = its glob' test "$(surface_select_cmd "$FT_TMP/p-api")" = 'bash kit/ops/polaris doctor --selftest --only tests/api/'
    ft_assert 'two - rows → distinct globs, space-joined, first-appearance order' test "$(surface_select_cmd "$FT_TMP/p-two")" = 'bash kit/ops/polaris doctor --selftest --only tests/api/ tests/db/'
    ft_assert 'complete cmds deduped + ordered, the template LAST' test "$(surface_select_cmd "$FT_TMP/p-cmds")" = "bash kit/ops/polaris doctor --selftest --only express,tcm${ft_nl}bash kit/ops/polaris doctor --fast${ft_nl}bash kit/ops/polaris doctor --selftest --only tests/api/"
    CONV="$FT_TMP/CONV-twice.md"
    ft_assert 'every {tests} is replaced'        test "$(surface_select_cmd "$FT_TMP/p-api")" = 'a tests/api/ b tests/api/'
    CONV="$FT_TMP/CONV-verbatim.md"
    ft_assert 'no {tests} in the template → verbatim, once' test "$(surface_select_cmd "$FT_TMP/p-two")" = 'run-everything'
    ft_section surfaces-select ) || ft_red=1

  # ---- surfaces-item (test-surfaces.md § 3) — surface_row_from_item <item> <ID> <title>: the
  # grammar → ONE TSV row, or rc 1 + ONE reason line. Keywords in the order tests, cmd, note; tests:
  # required and one token; cmd: everything up to note: (trimmed, empty → -); note: the rest,
  # absent → the title with surrounding double quotes stripped; the note carries [ID].
  ( FT_SEC=surfaces-item
    ft_assert 'surface + tests + note'           test "$(surface_row_from_item 'src/api/ tests: tests/api/ note: the HTTP API' T-9 'x')" = "src/api/${ft_tab}tests/api/${ft_tab}-${ft_tab}the HTTP API [T-9]"
    ft_assert 'cmd + note, the cmd kept whole'   test "$(surface_row_from_item 'kit/ops/lib/integrate.sh tests: kit/ops/lib/selftest/history.sh cmd: bash kit/ops/polaris doctor --selftest --only express,tcm note: the integrator lane' T-140 'x')" = "kit/ops/lib/integrate.sh${ft_tab}kit/ops/lib/selftest/history.sh${ft_tab}bash kit/ops/polaris doctor --selftest --only express,tcm${ft_tab}the integrator lane [T-140]"
    ft_assert 'no note → the title'              test "$(surface_row_from_item 'src/ tests: t/' T-1 'Plain title')" = "src/${ft_tab}t/${ft_tab}-${ft_tab}Plain title [T-1]"
    ft_assert 'title quotes stripped'            test "$(surface_row_from_item 'src/ tests: t/' T-1 '"Quoted title"')" = "src/${ft_tab}t/${ft_tab}-${ft_tab}Quoted title [T-1]"
    ft_assert 'cmd without note → the title'     test "$(surface_row_from_item 'src/ tests: t/ cmd: make test' T-1 'T')" = "src/${ft_tab}t/${ft_tab}make test${ft_tab}T [T-1]"
    ft_assert 'empty cmd: → -'                   test "$(surface_row_from_item 'src/ tests: t/ cmd: note: n' T-1 'T')" = "src/${ft_tab}t/${ft_tab}-${ft_tab}n [T-1]"
    ft_assert 'cmd and note padding trimmed'     test "$(surface_row_from_item 'src/ tests: t/ cmd:    make test    note:   n  ' T-1 'T')" = "src/${ft_tab}t/${ft_tab}make test${ft_tab}n [T-1]"
    ft_assert 'missing tests: → rc 1'            ! surface_row_from_item 'src/ note: n' T-1 'T'
    ft_assert "missing tests: → needs 'tests: <glob>'" test "$(surface_row_from_item 'src/ note: n' T-1 'T')" = "needs 'tests: <glob>'"
    ft_assert 'tests: with no glob → rc 1'       ! surface_row_from_item 'src/ tests:' T-1 'T'
    ft_assert 'empty item → empty surface'       test "$(surface_row_from_item '' T-1 'T')" = 'empty surface'
    ft_assert 'a TAB → a TAB in the item'        test "$(surface_row_from_item "src/${ft_tab}tests: t/" T-1 'T')" = 'a TAB in the item'
    ft_assert 'two surface tokens → not one token' test "$(surface_row_from_item 'src/a src/b tests: t/' T-1 'T')" = 'surface or tests glob is not one token'
    ft_assert 'two tests tokens → not one token'   test "$(surface_row_from_item 'src/ tests: t/ u/' T-1 'T')" = 'surface or tests glob is not one token'
    ft_section surfaces-item ) || ft_red=1

  # ---- stamp-scope (test-surfaces.md § 6, stamp v3) — suite_stamp_scope [<file>]: field 3 of
  # `<sha> <epoch> <scope>`; a 2-field pre-6.4 stamp reads full (every pre-6.4 writer ran
  # everything); a CR is not part of the word; missing or empty → nothing, rc 1. The default path
  # is $PRIMARY/.polaris/suite-stamp — the quiescent fixture's bgrc/.polaris/ already exists, so
  # that case borrows it (no extra mkdir fork; board_quiescent never reads a stamp).
  printf 'abc1234 1790000000 scoped\n'   > "$FT_TMP/st-scoped"
  printf 'abc1234 1790000000 full\n'     > "$FT_TMP/st-full"
  printf 'abc1234 1790000000\n'          > "$FT_TMP/st-two"
  printf 'abc1234 1790000000 scoped\r\n' > "$FT_TMP/st-cr"
  : > "$FT_TMP/st-empty"
  printf 'def5678 1790000001 scoped\n'   > "$FT_TMP/q/bgrc/.polaris/suite-stamp"
  ( FT_SEC=stamp-scope
    ft_assert 'scoped'                           test "$(suite_stamp_scope "$FT_TMP/st-scoped")" = scoped
    ft_assert 'full'                             test "$(suite_stamp_scope "$FT_TMP/st-full")" = full
    ft_assert '2-field (pre-6.4) → full'         test "$(suite_stamp_scope "$FT_TMP/st-two")" = full
    ft_assert 'CR-terminated scoped → scoped'    test "$(suite_stamp_scope "$FT_TMP/st-cr")" = scoped
    ft_assert 'missing file → rc 1'              ! suite_stamp_scope "$FT_TMP/no-such-file"
    ft_assert 'missing file → nothing'           test -z "$(suite_stamp_scope "$FT_TMP/no-such-file")"
    ft_assert 'empty file → rc 1'                ! suite_stamp_scope "$FT_TMP/st-empty"
    PRIMARY="$FT_TMP/q/bgrc"
    ft_assert 'default path = $PRIMARY/.polaris/suite-stamp' test "$(suite_stamp_scope)" = scoped
    ft_section stamp-scope ) || ft_red=1

  # ---- fixtures for the activation (test-surfaces.md v2 § 13 · first-run.md § 2): PRIMARY dirs
  # holding only the manifests surfaces_runner greps, hand-written tracked LISTS — one per layout
  # the pairing rules must pair, refuse or fold — two registries (five columns and four) and the
  # CONVENTIONS shapes the interview reads. Every path in a list is a fixture, never a file on disk.
  ft_sc="$FT_TMP/sc"; ft_iv="$FT_TMP/iv"
  mkdir -p "$ft_sc/node" "$ft_sc/py" "$ft_iv/ops5" "$ft_iv/ops4"
  printf '%s\n' pyproject.toml src/api/x.py src/db/y.py src/util.py src/common/a.py lib/common/b.py \
    tests/api/test_x.py tests/db/test_y.py tests/test_util.py tests/common/test_a.py README.md > "$ft_sc/ls-py"
  printf '%s\n' pytest.ini src/api/x.py src/api/tests/test_x.py tests/api/test_y.py > "$ft_sc/ls-pkg"
  printf '%s\n' package.json src/foo/a.ts src/foo/__tests__/a.test.ts src/bar/b.ts src/bar/b.test.ts > "$ft_sc/ls-js"
  printf '%s\n' package.json src/foo/a.ts tests/foo/z.test.ts src/qa/q.spec.ts node_modules/m/m.test.js \
    a/b/c/deep/d.ts tests/deep/e.test.ts > "$ft_sc/ls-js2"
  printf '%s\n' go.mod internal/foo/x.go internal/foo/x_test.go cmd/app/main.go main_test.go > "$ft_sc/ls-go"
  printf '%s\n' Makefile bin/tool.sh > "$ft_sc/ls-mk"
  printf '%s\n' Cargo.toml package.json src/x.js > "$ft_sc/ls-node"
  printf '%s\n' package.json pytest.ini go.mod > "$ft_sc/ls-all"
  printf '%s\n' pkg/conftest.py > "$ft_sc/ls-conftest"
  printf '%s\n' tests/x_test.py > "$ft_sc/ls-xtest"
  printf '%s\n' pkg/tests/test_x.py > "$ft_sc/ls-nested"
  printf '%s\n' pyproject.toml > "$ft_sc/ls-pyproject"
  printf '%s\n' setup.cfg > "$ft_sc/ls-setupcfg"
  : > "$ft_sc/ls-empty"
  printf '%s\n' package.json src/a.js src/a.test.js > "$ft_sc/ls-big"     # + 250 generated files under src/gen/
  ft_k=1; while [ "$ft_k" -le 250 ]; do printf 'src/gen/g%s.js\n' "$ft_k" >> "$ft_sc/ls-big"; ft_k=$((ft_k+1)); done
  printf '# a map header\nsrc/api/\ttests/api/\tpytest tests/api/\tapi tests [scaffold]\r\n\nsrc/db/\ttests/other/\t-\tx\n' > "$ft_sc/map-one"
  printf 'src/api/\ttests/api/\t-\ta\nsrc/common/a.py\ttests/common/test_a.py\t-\tb\nsrc/db/\ttests/db/\t-\tc\nsrc/util.py\ttests/test_util.py\t-\td\n' > "$ft_sc/map-all"
  printf '# registry\n\n' > "$ft_iv/ops5/KEYS.tsv"
  printf 'voice\t5.2.0\tstandard\thow agents talk\tHow should I talk to you?|Plain=standard|Terse=technical\n' >> "$ft_iv/ops5/KEYS.tsv"
  printf 'adhd\t6.4.0\toff\treplies not shaped\tWant ADHD?|Not needed=off|Yes, always=on\r\n' >> "$ft_iv/ops5/KEYS.tsv"
  printf 'plan_gate\t5.0.0\tauto\tno question here\n' >> "$ft_iv/ops5/KEYS.tsv"
  printf 'claim\t5.0.0\tlocal-lock\tlocks stay local\tOne or several?|One computer=local-lock|Several=claim-branch\n' >> "$ft_iv/ops5/KEYS.tsv"
  printf 'voice\t5.2.0\tstandard\thow agents talk\nclaim\t5.0.0\tlocal-lock\tlocks stay local\n' > "$ft_iv/ops4/KEYS.tsv"
  printf 'voice: standard   # c\n' > "$ft_iv/c-live"
  printf 'voice: technical\n# claim: local-lock   # locks stay local (since 5.0.0)\n' > "$ft_iv/c-stub"
  printf 'voice: standard\nadhd: on\nclaim: local-lock\n' > "$ft_iv/c-all"
  : > "$ft_iv/c-empty"
  printf 'adhd is great\n  claim: x\n#voice: y\n' > "$ft_iv/c-body"
  printf 'claim: local-lock\r\nvoice: standard\r\n' > "$ft_iv/c-cr"

  # ---- surfaces-runner (test-surfaces.md v2 § 13) — surfaces_runner <ls-file>: ONE
  # `<runner><TAB><template>` line rc 0, or nothing rc 1. Detection order node → pytest → go over
  # the list + the manifests it names under PRIMARY (a fixture dir here; package.json is rewritten
  # between asserts because the fn greps the file). What it REFUSES is the point: mocha, cargo,
  # make, an unknown npm script — each filters by name or cannot be proven to take a path — is
  # rc 1 and silence, never a guess (D6: a guessed template skips coverage while reporting green).
  ( FT_SEC=surfaces-runner; PRIMARY="$ft_sc/node"
    printf '{"scripts":{"test":"vitest --run"}}\n' > "$ft_sc/node/package.json"
    ft_assert 'a vitest test script → vitest'   test "$(surfaces_runner "$ft_sc/ls-node")" = "vitest${ft_tab}npx vitest run {tests}"
    printf '{"scripts":{"test":"jest --ci"}}\n' > "$ft_sc/node/package.json"
    ft_assert 'a jest test script → jest'       test "$(surfaces_runner "$ft_sc/ls-node")" = "jest${ft_tab}npx jest {tests}"
    printf '{"scripts":{"test":"mocha"}}\n' > "$ft_sc/node/package.json"
    ft_out="$(surfaces_runner "$ft_sc/ls-node")" && ft_rc=0 || ft_rc=1     # one call, two facts: the fn is ~10 greps
    ft_assert 'mocha → rc 1'                    test "$ft_rc" = 1
    ft_assert 'mocha → nothing'                 test -z "$ft_out"
    ft_assert 'an unknown script falls through to the next stack' test "$(surfaces_runner "$ft_sc/ls-all")" = "pytest${ft_tab}pytest {tests}"
    printf '{"scripts":{"test":"mocha"},"jest":{}}\n' > "$ft_sc/node/package.json"
    ft_assert 'unknown script, a jest key → jest'     test "$(surfaces_runner "$ft_sc/ls-node")" = "jest${ft_tab}npx jest {tests}"
    printf '{"scripts":{"test":"mocha"},"vitest":{}}\n' > "$ft_sc/node/package.json"
    ft_assert 'unknown script, a vitest key → vitest' test "$(surfaces_runner "$ft_sc/ls-node")" = "vitest${ft_tab}npx vitest run {tests}"
    printf '{"scripts":{"test":"jest"}}\n' > "$ft_sc/node/package.json"
    ft_assert 'order: node before pytest before go'   test "$(surfaces_runner "$ft_sc/ls-all")" = "jest${ft_tab}npx jest {tests}"
    ft_assert 'go.mod → go, the WHOLE suite as the template' test "$(surfaces_runner "$ft_sc/ls-go")" = "go${ft_tab}go test ./..."
    ft_assert 'a conftest.py anywhere → pytest' surfaces_runner "$ft_sc/ls-conftest"
    ft_assert 'a nested pkg/tests/test_x.py → pytest' surfaces_runner "$ft_sc/ls-nested"
    ft_assert 'tests/x_test.py is not a pytest tell'  ! surfaces_runner "$ft_sc/ls-xtest"
    PRIMARY="$ft_sc/py"
    printf '[tool.black]\n' > "$ft_sc/py/pyproject.toml"
    ft_assert 'pyproject.toml without [tool.pytest → rc 1' ! surfaces_runner "$ft_sc/ls-pyproject"
    printf '[tool.pytest.ini_options]\n' > "$ft_sc/py/pyproject.toml"     # the with-case is the proposal section's RUNNER line
    printf '[tool:pytest]\n' > "$ft_sc/py/setup.cfg"
    ft_assert 'setup.cfg with [tool:pytest] → pytest'      surfaces_runner "$ft_sc/ls-setupcfg"
    ft_section surfaces-runner ) || ft_red=1

  # ---- surfaces-pairs (§ 13 pairing rules + the shared filters) — surfaces_pairs <runner> <ls-file>:
  # candidate rows sorted by surface, then the SKIP decisions, rc 0 always. Pinned from the ENGINE's
  # measured output, never the contract's worked arithmetic (T-140): a test file under
  # <dir>/__tests__/ is rule (a)'s pairing, so the jest layout folds nothing; and the ANCESTOR fold
  # is refused when the ancestor's cmd would not run the candidate's tests dir — folding
  # src/api/ ↔ src/api/tests/ under src/api/ ↔ tests/api/ is D6's exact failure, so both rows stay.
  ( FT_SEC=surfaces-pairs
    ft_out="$(surfaces_pairs pytest "$ft_sc/ls-py")" || ft_out=""
    ft_k=0; while IFS= read -r ft_line; do ft_k=$((ft_k+1)); done <<EOF
$ft_out
EOF
    ft_assert 'pytest: four rows + two skips'   test "$ft_k" = 6
    ft_assert 'pytest (a): tests/api/ ↔ the ONE src/api/, sorted first' test "${ft_out%%$ft_nl*}" = "src/api/${ft_tab}tests/api/${ft_tab}pytest tests/api/${ft_tab}api tests"
    ft_assert 'pytest (b): tests/test_util.py ↔ the ONE util.py'      test "${ft_out#*"src/util.py${ft_tab}tests/test_util.py${ft_tab}pytest tests/test_util.py${ft_tab}util"}" != "$ft_out"
    ft_assert 'pytest (b) under an ambiguous dir stands on its own'  test "${ft_out#*"src/common/a.py${ft_tab}tests/common/test_a.py${ft_tab}pytest tests/common/test_a.py${ft_tab}a"}" != "$ft_out"
    ft_assert 'AMBIGUITY: two common dirs → no row; the skip names both, sorted' test "${ft_out#*"SKIP${ft_tab}tests/common/${ft_tab}ambiguous: common matches 2 dirs (lib/common src/common)"}" != "$ft_out"
    ft_assert 'AMBIGUITY: nothing pairs tests/common/' test "${ft_out#*"${ft_tab}tests/common/${ft_tab}pytest"}" = "$ft_out"
    ft_assert 'ANCESTOR: the per-file pairings under emitted dirs fold into ONE skip line' test "${ft_out##*$ft_nl}" = "SKIP${ft_tab}2 narrower pairing(s)${ft_tab}covered by an emitted ancestor row"
    ft_out="$(surfaces_pairs pytest "$ft_sc/ls-pkg")" || ft_out=""
    ft_assert 'pytest (c): in-package src/api/tests/ ↔ src/api/'      test "${ft_out#*"src/api/${ft_tab}src/api/tests/${ft_tab}pytest src/api/tests/${ft_tab}api tests"}" != "$ft_out"
    ft_assert 'D6: src/api/ ↔ tests/api/ does NOT fold the in-package row its cmd never runs' test "${ft_out%%$ft_nl*}" = "src/api/${ft_tab}tests/api/${ft_tab}pytest tests/api/${ft_tab}api tests"
    ft_assert 'D6: no narrower skip for the refused fold'  test "${ft_out#*narrower}" = "$ft_out"
    ft_assert 'AMBIGUITY 0: a test file with no source twin → matches 0 dirs' test "${ft_out##*$ft_nl}" = "SKIP${ft_tab}tests/api/test_y.py${ft_tab}ambiguous: y matches 0 dirs"
    ft_out="$(surfaces_pairs jest "$ft_sc/ls-js")" || ft_out=""
    ft_assert 'jest (a): <dir>/__tests__/ ↔ its parent, never a co-located row' test "${ft_out##*$ft_nl}" = "src/foo/${ft_tab}src/foo/__tests__/${ft_tab}npx jest src/foo/__tests__${ft_tab}foo tests"
    ft_assert 'jest (c): co-located *.test.* under src/bar/'   test "${ft_out%%$ft_nl*}" = "src/bar/${ft_tab}src/bar/*.test.*${ft_tab}npx jest src/bar${ft_tab}bar co-located tests"
    ft_assert 'jest: the § 17 case-2 layout folds NOTHING (measured)' test "${ft_out#*SKIP}" = "$ft_out"
    ft_out="$(surfaces_pairs vitest "$ft_sc/ls-js2")" || ft_out=""
    ft_assert 'vitest (b): tests/foo/ ↔ the ONE src/foo/, the run form' test "${ft_out%%$ft_nl*}" = "src/foo/${ft_tab}tests/foo/${ft_tab}npx vitest run tests/foo${ft_tab}foo tests"
    ft_assert 'vitest (c): *.spec.* gets its own glob'    test "${ft_out#*"src/qa/${ft_tab}src/qa/*.spec.*${ft_tab}npx vitest run src/qa${ft_tab}qa co-located tests"}" != "$ft_out"
    ft_assert 'node_modules/ is never a source dir'       test "${ft_out#*node_modules}" = "$ft_out"
    ft_assert 'a 4-component dir is never a source dir'   test "${ft_out##*$ft_nl}" = "SKIP${ft_tab}tests/deep/${ft_tab}ambiguous: deep matches 0 dirs"
    ft_assert 'go: one row per dir holding *_test.go, a COMPLETE cmd; the root is never a surface' test "$(surfaces_pairs go "$ft_sc/ls-go")" = "internal/foo/${ft_tab}internal/foo/*_test.go${ft_tab}go test ./internal/foo/...${ft_tab}foo package tests"
    ft_assert 'BREADTH: a surface over 200 paths → no row, and said' test "$(surfaces_pairs vitest "$ft_sc/ls-big")" = "SKIP${ft_tab}src/${ft_tab}surface matches 252 paths (>200)"
    ft_out="$(surfaces_pairs cargo "$ft_sc/ls-py")" && ft_rc=0 || ft_rc=1
    ft_assert 'an unknown runner → nothing'     test -z "$ft_out"
    ft_assert 'an unknown runner → rc 0'        test "$ft_rc" = 0
    ft_section surfaces-pairs ) || ft_red=1

  # ---- surfaces-proposal (§ 13) — surfaces_proposal <ls-file> [<map-file>]: the whole decision as
  # DATA, rc 0 always. NORUNNER as the ONLY line, naming the manifests it saw; else RUNNER first,
  # the ROW survivors, then the SKIPs — a pair already in the map (`already mapped`) ahead of the
  # engine's own, which is why an idempotent re-run counts 6 skips, not 4 (T-142's measured golden).
  ( FT_SEC=surfaces-proposal; PRIMARY="$ft_sc/py"
    ft_out="$(surfaces_proposal "$ft_sc/ls-mk")" && ft_rc=0 || ft_rc=1
    ft_assert 'no runner → rc 0'                test "$ft_rc" = 0
    ft_assert 'no runner → the ONE NORUNNER line, seen: Makefile' test "$ft_out" = "NORUNNER${ft_tab}no test runner this kit can scope (pytest · jest · vitest · go) — seen: Makefile"
    ft_assert 'no runner, an empty list → seen: no manifest'     test "$(surfaces_proposal "$ft_sc/ls-empty")" = "NORUNNER${ft_tab}no test runner this kit can scope (pytest · jest · vitest · go) — seen: no manifest"
    printf '{"scripts":{"test":"mocha"}}\n' > "$ft_sc/node/package.json"; PRIMARY="$ft_sc/node"
    ft_assert 'no runner, mocha + Cargo.toml → both manifests named, kit order' test "$(surfaces_proposal "$ft_sc/ls-node")" = "NORUNNER${ft_tab}no test runner this kit can scope (pytest · jest · vitest · go) — seen: package.json Cargo.toml"
    PRIMARY="$ft_sc/py"
    ft_out="$(surfaces_proposal "$ft_sc/ls-py")" || ft_out=""
    ft_assert 'RUNNER first'                    test "${ft_out%%$ft_nl*}" = "RUNNER${ft_tab}pytest${ft_tab}pytest {tests}"
    ft_assert 'every survivor is a ROW line, sorted' test "${ft_out#*"${ft_nl}ROW${ft_tab}src/api/${ft_tab}tests/api/${ft_tab}pytest tests/api/${ft_tab}api tests${ft_nl}ROW${ft_tab}src/common/a.py"}" != "$ft_out"
    ft_assert 'the engine skips come last'      test "${ft_out##*$ft_nl}" = "SKIP${ft_tab}2 narrower pairing(s)${ft_tab}covered by an emitted ancestor row"
    ft_assert 'deterministic: the same input twice is the same bytes' test "$(surfaces_proposal "$ft_sc/ls-py")" = "$ft_out"
    ft_assert 'an absent map file is no map'    test "$(surfaces_proposal "$ft_sc/ls-py" "$ft_sc/no-such-map")" = "$ft_out"
    ft_out="$(surfaces_proposal "$ft_sc/ls-py" "$ft_sc/map-one")" || ft_out=""
    ft_assert 'a mapped (surface, tests) pair is never a ROW (comment, CR and blank lines ignored)' test "${ft_out#*"ROW${ft_tab}src/api/"}" = "$ft_out"
    ft_assert 'already mapped to <tests>, ahead of the engine skips' test "${ft_out#*"${ft_nl}SKIP${ft_tab}src/api/${ft_tab}already mapped to tests/api/${ft_nl}SKIP${ft_tab}tests/common/"}" != "$ft_out"
    ft_assert 'the same surface mapped to OTHER tests masks nothing' test "${ft_out#*"ROW${ft_tab}src/db/${ft_tab}tests/db/"}" != "$ft_out"
    ft_out="$(surfaces_proposal "$ft_sc/ls-py" "$ft_sc/map-all")" || ft_out=""
    ft_assert 'idempotent re-run: no ROW at all' test "${ft_out#*ROW}" = "$ft_out"
    ft_k=0; while IFS= read -r ft_line; do case "$ft_line" in "SKIP$ft_tab"*) ft_k=$((ft_k+1));; esac; done <<EOF
$ft_out
EOF
    ft_assert 'idempotent re-run: 6 skips (4 mapped + 2 engine), never 4' test "$ft_k" = 6
    ft_section surfaces-proposal ) || ft_red=1

  # ---- interview-pending (first-run.md § 2) — interview_pending over fixture registries, OPS and
  # CONV overridden: an `ask` row (column 5) is pending unless CONV answers it with a live `^key:`
  # line or a `# key:` stub; KEYS.tsv order, ` · `-joined; rc 1 and silence when nothing is. Then
  # interview_set's three write modes, proven on the file (read whole by a builtin, no fork).
  ( FT_SEC=interview-pending; OPS="$ft_iv/ops5"; CONV="$ft_iv/c-live"
    ft_assert 'voice live → adhd · claim pending' test "$(interview_pending)" = 'adhd · claim'
    ft_assert 'pending → rc 0'                  interview_pending
    CONV="$ft_iv/c-stub"
    ft_assert 'a # claim: stub counts as answered' test "$(interview_pending)" = 'adhd'
    CONV="$ft_iv/c-all"
    ft_out="$(interview_pending)" && ft_rc=0 || ft_rc=1
    ft_assert 'all answered → rc 1'             test "$ft_rc" = 1
    ft_assert 'all answered → nothing'          test -z "$ft_out"
    CONV="$ft_iv/c-empty"
    ft_assert 'an empty CONVENTIONS → every ask row, registry order, plain rows never' test "$(interview_pending)" = 'voice · adhd · claim'
    CONV="$ft_iv/c-body"
    ft_assert 'a body mention and an indented key answer nothing; a #key: stub does' test "$(interview_pending)" = 'adhd · claim'
    CONV="$ft_iv/c-cr"
    ft_assert 'CRLF lines answer; the order stays the registry order' test "$(interview_pending)" = 'adhd'
    OPS="$ft_iv/ops4"; CONV="$ft_iv/c-empty"
    ft_assert 'a 4-column registry asks nothing → rc 1' ! interview_pending
    OPS="$ft_iv/none"
    ft_assert 'no KEYS.tsv → rc 1'              ! interview_pending
    OPS="$ft_iv/ops5"; CONV="$ft_iv/no-such"
    ft_assert 'no CONVENTIONS → rc 1 (interview itself is what dies)' ! interview_pending
    printf 'voice: technical\n# claim: local-lock   # locks stay local (since 5.0.0)\n' > "$ft_iv/c-set"; CONV="$ft_iv/c-set"
    ft_assert 'set: an absent key → rc 0'       interview_set adhd on
    IFS= read -r -d '' ft_out < "$CONV" || true
    ft_assert 'set: appended at the END after one blank line, the absent-cost as its comment' test "$ft_out" = "voice: technical${ft_nl}# claim: local-lock   # locks stay local (since 5.0.0)${ft_nl}${ft_nl}adhd: on   # replies not shaped${ft_nl}"
    interview_set claim claim-branch
    IFS= read -r -d '' ft_out < "$CONV" || true
    ft_assert 'set: a stub is replaced IN PLACE by the live line' test "$ft_out" = "voice: technical${ft_nl}claim: claim-branch   # locks stay local${ft_nl}${ft_nl}adhd: on   # replies not shaped${ft_nl}"
    interview_set voice standard
    IFS= read -r -d '' ft_out < "$CONV" || true
    ft_assert 'set: a live value changes in place' test "${ft_out%%$ft_nl*}" = 'voice: standard'
    ft_assert 'set: every key answered → nothing pending' ! interview_pending
    printf 'voice: standard   # c\n' > "$ft_iv/c-set2"; CONV="$ft_iv/c-set2"
    interview_set voice technical
    IFS= read -r -d '' ft_out < "$CONV" || true
    ft_assert 'set: a live line keeps its trailing comment' test "$ft_out" = "voice: technical   # c${ft_nl}"
    ft_section interview-pending ) || ft_red=1

  # ---- amend (ops/contracts/grant.md v2): amend_verify is the PURE list surgery behind cmd_amend.
  # The command's refusals — feat/*, a bare suite — are drilled against the real entry point; what
  # belongs here is the awk: replace keeps the order and the item's indentation, `-` drops, `add`
  # appends, and an out-of-range line (or a file with no verify: at all) returns rc 1 having written
  # nothing. Its own fixture, so a mutation bug cannot reach the other sections' files.
  ( FT_SEC=amend
    ft_av="$FT_TMP/T-AV.md"
    printf '%s\n' '---' 'id: T-AV' 'points: 1' 'verify:' '  - test -f one' '  - test -f two' '  - test -f three' '---' '## Notes' > "$ft_av"
    ft_assert 'replace line 2'                   amend_verify "$ft_av" 2 'test -f TWO'
    ft_assert 'order kept: old-1 / new / old-3'  test "$(fm_list verify "$ft_av" | tr '\n' '|')" = 'test -f one|test -f TWO|test -f three|'
    ft_assert 'drop line 1'                      amend_verify "$ft_av" 1 -
    ft_assert 'two lines left, order kept'       test "$(fm_list verify "$ft_av" | tr '\n' '|')" = 'test -f TWO|test -f three|'
    ft_assert 'add appends'                      amend_verify "$ft_av" add 'test -f four'
    ft_assert 'appended last'                    test "$(fm_list verify "$ft_av" | tr '\n' '|')" = 'test -f TWO|test -f three|test -f four|'
    ft_assert 'the item indentation survives'    grep -qx '  - test -f four' "$ft_av"
    ft_assert 'every other frontmatter byte untouched' test "$(fm_get points "$ft_av")" = '1'
    ft_assert 'out of range → rc 1'              ! amend_verify "$ft_av" 9 'test -f nine'
    ft_assert 'out of range wrote nothing'       test "$(fm_list verify "$ft_av" | tr '\n' '|')" = 'test -f TWO|test -f three|test -f four|'
    ft_assert 'no verify: field → rc 1'          ! amend_verify "$ft_tf" 1 'test -f x'
    ft_assert 'no verify: field wrote nothing'   test "$(fm_list files_owned "$ft_tf" | tr '\n' ' ')" = 'a.sh b.sh '
    ft_section amend ) || ft_red=1

  # ---- verdict
  while IFS= read -r ft_k; do ft_n=$((ft_n + ft_k)); done < "$FT_TMP/n"
  ft_t1="$(date +%s)"
  [ "$ft_red" -eq 0 ] || return 1
  printf '✅ fast tier passed — %s checks in %ss\n' "$ft_n" "$((ft_t1 - ft_t0))"
  return 0
}
