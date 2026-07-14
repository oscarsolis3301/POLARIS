#!/usr/bin/env bash
# POLARIS v5 — Claude Code PreToolUse guard (Edit|Write|MultiEdit|NotebookEdit).
# Two gates, evaluated at write time, BEFORE the write happens:
#   1. RULES (ops/RULES.tsv) — repo policy, binds EVERY session on any branch:
#      path rules forbid writes to danger zones even inside files_owned;
#      content rules scan the text about to be written.
#   2. OWNERSHIP — only inside feat/<ID> Builder worktrees: the path must be in
#      the claimed task's files_owned (same matcher as `polaris verify`).
# Exit 2 = block (stderr goes back to Claude). Exit 0 = allow.
# This is an early tripwire; `polaris verify`/`handoff` remain the authority, so
# the guard FAILS OPEN (exit 0 + warning) when it cannot parse its input.
set -u

IN="$(cat)"

# --- parse stdin JSON: path + cwd + write payload (schema-tolerant) ----------
# Payload = every string value in tool_input EXCEPT path fields and old_string
# (old_string is existing file text; scanning it would block edits that REMOVE
# a forbidden pattern). Covers Write.content, Edit.new_string, NotebookEdit.
# new_source and MultiEdit edits[].new_string today, and survives field renames.
# `-c pass` proves a REAL interpreter — the Windows Store python3 alias stub
# passes `command -v` but cannot run code, which would silently fail this guard open.
PY=""; python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; }
[ "${POLARIS_GUARD_TEST_NOPY:-}" = "1" ] && PY=""
if [ -z "$PY" ]; then
  echo "polaris-guard: python not found — write-guard skipped (verify/handoff gate still enforces ownership + rules)" >&2
  exit 0
fi
PARSED="$(printf '%s' "$IN" | "$PY" -c '
import json,sys,tempfile
try:
    d=json.load(sys.stdin); ti=d.get("tool_input") or {}
    p=ti.get("file_path") or ti.get("notebook_path") or ""
    skip={"file_path","notebook_path","old_string"}
    parts=[]
    def walk(o):
        if isinstance(o,dict):
            for k,v in o.items():
                if k in skip: continue
                walk(v)
        elif isinstance(o,list):
            for v in o: walk(v)
        elif isinstance(o,str):
            parts.append(o)
    walk(ti)
    body=""
    if parts:
        f=tempfile.NamedTemporaryFile(mode="w",delete=False,prefix="polaris-guard-",suffix=".txt")
        f.write("\n".join(parts)); f.close(); body=f.name
    print(p); print(d.get("cwd") or ""); print(body)
except Exception:
    pass
')" || PARSED=""
FILE="$(printf '%s\n' "$PARSED" | sed -n 1p)"
CWD="$(printf '%s\n' "$PARSED" | sed -n 2p)"
BODY="$(printf '%s\n' "$PARSED" | sed -n 3p)"
cleanup() { [ -n "$BODY" ] && rm -f "$BODY" 2>/dev/null; }
trap cleanup EXIT
[ -n "$FILE" ] || exit 0                       # nothing path-like to police
[ -n "$CWD" ] || CWD="$(pwd)"

# --- normalize (best effort for Windows-style paths) -------------------------
norm() { printf '%s' "$1" | tr '\\' '/' | sed -e 's|^\([A-Za-z]\):/|/\L\1/|'; }
FILE="$(norm "$FILE")"; CWD="$(norm "$CWD")"

# --- repo + repo-relative path ------------------------------------------------
# Git on Windows prints toplevel/worktree as `C:/...` while FILE/CWD normalize
# to `/c/...` — norm() BOTH sides or every in-repo path looks "outside the repo".
TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
TOP="$(norm "$TOP")"
[ -x "$TOP/ops/polaris" ] || exit 0            # not a POLARIS repo — stand down
BR="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
case "$FILE" in /*) ABS="$FILE";; *) ABS="$CWD/$FILE";; esac
PRIMARY="$(git -C "$CWD" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$PRIMARY" ] && PRIMARY="$(norm "$PRIMARY")"
REL=""
case "$ABS" in
  "$TOP"/*) REL="${ABS#"$TOP"/}";;
  *) [ -n "$PRIMARY" ] && case "$ABS" in "$PRIMARY"/*) REL="${ABS#"$PRIMARY"/}";; esac;;
esac
if [ -z "$REL" ]; then
  case "$BR" in feat/*) ;; *) exit 0;; esac    # non-Builder sessions may write outside the repo
  echo "polaris-guard BLOCKED: $ABS is outside this repo. Task ${BR#feat/} may only write its files_owned." >&2
  exit 2
fi

# --- gate 1: RULES — every session, every branch ------------------------------
MSG="$("$TOP/ops/polaris" _rules "$REL" "$BODY" 2>&1 >/dev/null)" || {
  { printf '%s\n' "$MSG"
    echo "polaris-guard BLOCKED by ops/RULES.tsv. Rules bind even inside files_owned."
    echo "If the rule is wrong, that is a HUMAN decision: propose the change, do not work around it."
  } >&2
  exit 2
}

# --- gate 2: OWNERSHIP — only inside a Builder worktree (branch feat/<ID>) ----
case "$BR" in feat/*) ID="${BR#feat/}";; *) exit 0;; esac
if "$TOP/ops/polaris" _match "$REL" "$ID" 2>/dev/null; then
  exit 0
fi
{
  echo "polaris-guard BLOCKED: '$REL' is NOT in task $ID's files_owned."
  echo "Allowed: files_owned patterns · ops/board/active/$ID.md (Notes) · ops/board/backlog/IDEAS.md."
  echo "If you truly need this file: STOP and hand back — bash ops/polaris release $ID --to blocked -m \"needs <path>\""
} >&2
exit 2
