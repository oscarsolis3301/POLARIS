# POLARIS lib/search.sh — `find` / `show`: the 1-hop answer to "where is X".
# A SHIM on purpose (ops/contracts/code-index.md + module-layout.md v2): every line of indexing
# logic lives in ops/index.py, which the grand-total band does not count. Keeping this thin is what
# lets a native engine drop in later behind the same interface.

index_engine() { # resolve the engine — the ONE seam a native builder replaces later.
  # Order: explicit override · a native binary if one was ever shipped · python + index.py.
  # `-c pass` defeats the Windows Store python stub exactly as ops/hooks/ownership-guard.sh does.
  [ -n "${POLARIS_INDEX_BIN:-}" ] && [ -x "${POLARIS_INDEX_BIN}" ] && { printf '%s' "$POLARIS_INDEX_BIN"; return 0; }
  [ -x "$OPS/polaris-index" ] && { printf '%s' "$OPS/polaris-index"; return 0; }
  [ "${POLARIS_INDEX_TEST_NOPY:-}" = "1" ] && return 1
  local p=""
  python3 -c pass >/dev/null 2>&1 && p=python3 || { python -c pass >/dev/null 2>&1 && p=python; }
  [ -n "$p" ] || return 1
  printf '%s %s' "$p" "$OPS/index.py"
}

index_run() { # run the engine, or explain the fallback. NEVER die: an agent's fallback is Grep,
  # and a hard ⛔ would read as a repo error rather than a missing optional accelerator.
  local eng
  eng="$(index_engine)" || {
    note "no python3 — 'find' is unavailable; use Grep/Glob for this one (everything else works)"
    return 3
  }
  ( cd "$PRIMARY" && $eng "$@" )
}

cmd_find() { # find <symbol> | -f <glob> | -t <text> | --importers <p> | --imports <p> [-n N]
  # One line per hit, `path:line` first so it is click-through and cheap to read.
  # rc 0 hits · 1 none · 2 usage · 3 engine unavailable.
  index_run find "$@"
}

cmd_show() { # show <path>#<symbol> | <path>:<line> — print JUST that symbol's body.
  [ -n "${1:-}" ] || die "usage: polaris show <path>#<symbol> | <path>:<line>"
  index_run show "$@"
}
