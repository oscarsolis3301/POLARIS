# POLARIS lib/search.sh — `find` / `show`: the 1-hop answer to "where is X".
# A SHIM on purpose (ops/contracts/code-index.md + module-layout.md v2): every line of indexing
# logic lives in ops/index.py, which the grand-total band does not count. Keeping this thin is what
# lets a native engine drop in later behind the same interface.
#
# This module is the ONE the entry point sources BEFORE resolving the environment, because `find` is
# the hot path an agent calls ten times a task and needs none of that environment. A traced run
# (2026-07-25, Windows/Git Bash) spent 1.9s of a 3.6s `find` on globals it never reads: git-common-dir
# 0.47s, three cfg reads 1.0s, hostname 0.07s. So every function here is SELF-CONTAINED — no cfg, no
# die/say/note, no $OPS/$PRIMARY/$BASE. Adding a core.sh dependency here silently re-adds that 1.9s.

index_root() { # the PRIMARY checkout — a Builder in .polaris/wt/<ID> must query the primary's index.
  # ONE git call. `--show-toplevel` would resolve to the WORKTREE, which has no .polaris/index.db.
  git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p'
}

index_engine() { # index_engine <root> — resolve the engine; the ONE seam a native builder replaces.
  # Order: explicit override · cached answer · a native binary if one was ever shipped · python.
  # `-c pass` defeats the Windows Store python stub exactly as ops/hooks/ownership-guard.sh does —
  # it costs ~0.19s, which is why the answer is CACHED in .polaris/index-engine after the first run.
  # Overrides bypass the cache so a test that forces an engine is never answered from disk.
  local root="${1:-}" cache="" p="" eng="" first=""
  [ -n "${POLARIS_INDEX_BIN:-}" ] && [ -x "${POLARIS_INDEX_BIN}" ] && { printf '%s' "$POLARIS_INDEX_BIN"; return 0; }
  [ "${POLARIS_INDEX_TEST_NOPY:-}" = "1" ] && return 1
  [ -n "$root" ] && cache="$root/.polaris/index-engine"
  if [ -n "$cache" ] && [ -s "$cache" ]; then
    # Trust a cached line only while its first token still resolves — an uninstalled python or a
    # deleted binary must fall back to a fresh probe, never to a confident wrong answer.
    first="$(cut -d' ' -f1 < "$cache")"
    if [ -x "$first" ] || command -v "$first" >/dev/null 2>&1; then cat "$cache"; return 0; fi
  fi
  if [ -n "$root" ] && [ -x "$root/ops/polaris-index" ]; then eng="$root/ops/polaris-index"
  else
    python3 -c pass >/dev/null 2>&1 && p=python3 || { python -c pass >/dev/null 2>&1 && p=python; }
    [ -n "$p" ] || return 1
    eng="$p ${root:-.}/ops/index.py"
  fi
  [ -n "$cache" ] && { mkdir -p "$root/.polaris" 2>/dev/null; printf '%s' "$eng" > "$cache" 2>/dev/null || true; }
  printf '%s' "$eng"
}

index_fast() { # index_fast find|show <args…> — the WHOLE command. Always exits; never returns.
  #   find <symbol> | -f <glob> | -t <text> | --importers <p> | --imports <p> [-n N]
  #   show <path>#<symbol> | <path>:<line>   — print JUST that symbol's body
  # One line per hit, `path:line` first so it is click-through and cheap to read.
  # rc 0 hits · 1 none · 2 usage · 3 engine unavailable.
  local cmd="$1" root eng; shift
  [ "$cmd" = "show" ] && [ -z "${1:-}" ] && {
    printf '⛔ usage: polaris show <path>#<symbol> | <path>:<line>\n' >&2; exit 1; }
  # NEVER die on a missing engine: an agent's fallback is Grep, and a hard ⛔ would read as a repo
  # error rather than a missing optional accelerator. Same text/rc the pre-5.19 slow path printed.
  root="$(index_root)"
  [ -n "$root" ] || { printf '   not inside a git worktree — use Grep/Glob for this one\n'; exit 3; }
  eng="$(index_engine "$root")" || {
    printf "   no python3 — 'find' is unavailable; use Grep/Glob for this one (everything else works)\n"
    exit 3; }
  # POLARIS_ROOT is index.py's documented override (index.py:625), so it needs no git call of its own.
  POLARIS_ROOT="$root" exec $eng "$cmd" "$@"
}
