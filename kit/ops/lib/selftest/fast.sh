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
  local ft_t0 ft_t1 ft_red=0 ft_n=0 ft_k ft_tf ft_conv ft_rules ft_nl ft_cr
  ft_nl=$'\n'; ft_cr=$'\r'
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

  # ---- verdict
  while IFS= read -r ft_k; do ft_n=$((ft_n + ft_k)); done < "$FT_TMP/n"
  ft_t1="$(date +%s)"
  [ "$ft_red" -eq 0 ] || return 1
  printf '✅ fast tier passed — %s checks in %ss\n' "$ft_n" "$((ft_t1 - ft_t0))"
  return 0
}
