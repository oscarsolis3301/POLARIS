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

# --- SPEED: why this file no longer starts python on every write --------------
# Traced 2026-07-26 with `PS4='+ $EPOCHREALTIME ' bash -x`, sorting the deltas. The hook cost
# 4,045ms per Edit, of which only 537ms was the actual gate:
#     python3 -c pass  probe   559ms      <- the Windows Store stub failing slowly
#     python  -c pass  probe   920ms      <- a real interpreter booting just to prove it exists
#     the parse run itself   ~1,400ms
#     polaris _guard           537ms      <- the only line doing work
# Two fixes, no gate weakened:
#   1. CACHE the interpreter answer, exactly as ops/lib/search.sh::index_engine already does for
#      the index (.polaris/index-engine). The probe cost is real and it is paid once, not per write.
#   2. Do not start python AT ALL unless a CONTENT rule could actually match. path-kind rules and
#      the ownership gate need only file_path + cwd, which bash parses safely below; the write
#      PAYLOAD is needed solely to scan added lines against content-rule patterns. This repo's
#      RULES.tsv is 14 path rules and zero content rules, so the common case now forks no python.
# A hook that is slow is not merely annoying: at 2x this cost it exceeded its 10s timeout under
# parallel builders, got killed, and FAILED OPEN — silently dropping the ownership gate entirely.

# --- pure-bash JSON string read (same contract as ops/hooks/readonly-allow.sh) --
# Returns 1 on ANY irregularity so the caller falls back to python rather than guessing. The
# closing-quote-must-be-followed-by-,-or-} check is what makes a truncated read impossible.
jstr() {
  local key="$1" s="$2" rest ch out='' i=0 len after
  rest="${s#*\"$key\"}"
  [ "$rest" = "$s" ] && return 1
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = ":" ] || return 1
  rest="${rest:1}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = '"' ] || return 1
  rest="${rest:1}"; len=${#rest}
  while [ "$i" -lt "$len" ]; do
    ch="${rest:i:1}"
    if [ "$ch" = '\' ]; then
      i=$((i + 1)); ch="${rest:i:1}"
      case "$ch" in
        n) out="$out
";;
        t) out="$out	";;
        r) ;;
        '"'|'\'|/) out="$out$ch";;
        *) return 1;;
      esac
      i=$((i + 1)); continue
    fi
    if [ "$ch" = '"' ]; then
      after="${rest:i+1}"; after="${after#"${after%%[![:space:]]*}"}"
      case "${after:0:1}" in ','|'}') REPLY="$out"; return 0;; *) return 1;; esac
    fi
    out="$out$ch"; i=$((i + 1))
  done
  return 1
}

# --- does any CONTENT rule exist? decides whether python is needed at all ------
# Field 2 of RULES.tsv is the kind. No content rule anywhere → the payload cannot matter.
# Unreadable RULES → assume yes and take the slow, safe path.
GUARD_TOP0="$(git rev-parse --show-toplevel 2>/dev/null || true)"
NEED_BODY=1
if [ -n "$GUARD_TOP0" ] && [ -f "$GUARD_TOP0/ops/RULES.tsv" ]; then
  awk -F'\t' '!/^#/ && NF>=2 && $2=="content" {found=1; exit} END{exit !found}' \
      "$GUARD_TOP0/ops/RULES.tsv" 2>/dev/null || NEED_BODY=0
fi

FILE=""; CWD=""; BODY=""
if [ "$NEED_BODY" -eq 0 ]; then
  # Fast path: bash only. If either read is irregular we fall through to python below.
  if jstr file_path "$IN"; then FILE="$REPLY"
  elif jstr notebook_path "$IN"; then FILE="$REPLY"; fi
  jstr cwd "$IN" && CWD="$REPLY"
  [ -n "$FILE" ] && PARSED_OK=1 || PARSED_OK=0
else
  PARSED_OK=0
fi

if [ "$PARSED_OK" -eq 0 ]; then
# --- parse stdin JSON: path + cwd + write payload (schema-tolerant) ----------
# Payload = every string value in tool_input EXCEPT path fields and old_string
# (old_string is existing file text; scanning it would block edits that REMOVE
# a forbidden pattern). Covers Write.content, Edit.new_string, NotebookEdit.
# new_source and MultiEdit edits[].new_string today, and survives field renames.
# `-c pass` proves a REAL interpreter — the Windows Store python3 alias stub
# passes `command -v` but cannot run code, which would silently fail this guard open.
# The answer is CACHED: the two probes cost 1.5s together and never change between writes.
PY=""
PYCACHE=""
[ -n "$GUARD_TOP0" ] && PYCACHE="$GUARD_TOP0/.polaris/guard-py"
if [ -n "$PYCACHE" ] && [ -s "$PYCACHE" ] && [ "${POLARIS_GUARD_TEST_NOPY:-}" != "1" ]; then
  PY="$(cat "$PYCACHE" 2>/dev/null)"
  command -v "$PY" >/dev/null 2>&1 || PY=""      # uninstalled since — re-probe, never trust blindly
fi
if [ -z "$PY" ]; then
  python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; }
  [ -n "$PY" ] && [ -n "$PYCACHE" ] && {
    mkdir -p "$(dirname "$PYCACHE")" 2>/dev/null
    printf '%s' "$PY" > "$PYCACHE" 2>/dev/null || true; }
fi
[ "${POLARIS_GUARD_TEST_NOPY:-}" = "1" ] && PY=""
if [ -z "$PY" ]; then
  # Degrade, do not disappear. Without python we cannot read the write PAYLOAD, so content rules
  # cannot be scanned — but file_path/cwd may still have parsed in bash above, and the path and
  # ownership gates are the ones that stop a Builder writing outside its lane. Run what we can.
  # (Previously this exited 0 and dropped ALL THREE gates on any python-less machine.)
  if [ -z "$FILE" ]; then
    jstr file_path "$IN" && FILE="$REPLY"
    [ -n "$FILE" ] || { jstr notebook_path "$IN" && FILE="$REPLY"; }
    jstr cwd "$IN" && CWD="$REPLY"
  fi
  if [ -z "$FILE" ]; then
    echo "polaris-guard: no python and the payload did not parse — write-guard skipped (verify/handoff still enforces ownership + rules)" >&2
    exit 0
  fi
  echo "polaris-guard: no python — path + ownership gates ENFORCED, content rules not scanned (verify/handoff still scans them)" >&2
  BODY=""
else
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
fi
fi
cleanup() { [ -n "$BODY" ] && rm -f "$BODY" 2>/dev/null; }
trap cleanup EXIT
[ -n "$FILE" ] || exit 0                       # nothing path-like to police
[ -n "$CWD" ] || CWD="$(pwd)"

# --- normalize (best effort for Windows-style paths) -------------------------
# REPLY-returning, not stdout-returning, and pure bash: `x="$(norm "$x")"` forks a subshell even
# for a shell function, and a fork is ~80ms here. Six of them were 480ms of every write. Same
# reason `lc` no longer pipes to tr. Bash 3.2 (macOS default) has no ${v,,}, hence the char loop —
# it is O(path length) of in-process string ops, which is free next to one fork.
lc() { # -> REPLY
  local s="$1" out='' c i
  local up='ABCDEFGHIJKLMNOPQRSTUVWXYZ' lo='abcdefghijklmnopqrstuvwxyz'
  while [ -n "$s" ]; do
    c="${s:0:1}"; s="${s:1}"
    i="${up%%"$c"*}"
    [ "$i" != "$up" ] && c="${lo:${#i}:1}"
    out="$out$c"
  done
  REPLY="$out"
}
norm() { # -> REPLY
  local s="${1//\\//}"
  case "$s" in [A-Za-z]:/*) lc "${s:0:1}"; s="/$REPLY${s:2}";; esac
  REPLY="$s"
}
norm "$FILE"; FILE="$REPLY"
norm "$CWD";  CWD="$REPLY"

# --- repo + repo-relative path ------------------------------------------------
# Git on Windows prints toplevel/worktree as `C:/...` while FILE/CWD normalize
# to `/c/...` — norm() BOTH sides or every in-repo path looks "outside the repo".
# ONE rev-parse fetches BOTH values it needs; splitting the two lines in bash is free, whereas a
# second `git rev-parse` would be another fork on every single write. See the SPEED note above:
# at 2x the budget this hook was killed at its timeout and FAILED OPEN, dropping the gate silently.
GITINFO="$(git -C "$CWD" rev-parse --show-toplevel --git-common-dir 2>/dev/null)" || exit 0
TOP="${GITINFO%%$'\n'*}"
GCD="${GITINFO#*$'\n'}"
[ "$GCD" = "$TOP" ] && GCD=""                  # one-line output (git too old for --git-common-dir)
norm "$TOP"; TOP="$REPLY"
norm "$GCD"; GCD="$REPLY"
# --git-common-dir prints RELATIVE to $CWD inside the primary (".git", "../.git") and absolute from
# a linked worktree. Anchor the relative form; leftover `..` segments are fine for the -d tests.
case "$GCD" in ''|/*) ;; *) GCD="$CWD/$GCD";; esac
[ -x "$TOP/ops/polaris" ] || exit 0            # not a POLARIS repo — stand down
# WHERE ARE WE? Pure string ops. The worktree layout .polaris/wt/<ID> spells out BOTH the task ID
# and the primary checkout, so neither answer needs `git worktree list` (~460ms).
WT_ID=""; PRIMARY=""
case "$TOP" in
  */.polaris/wt/*) WT_ID="${TOP##*/}"; PRIMARY="${TOP%/.polaris/wt/*}";;
  *) PRIMARY="$TOP";;
esac
[ -n "$WT_ID" ] && : 2>/dev/null > "$PRIMARY/.git/worktrees/$WT_ID/polaris-beat" || true
[ -n "$PRIMARY" ] && [ -x "$PRIMARY/ops/polaris" ] || PRIMARY=""   # odd layout → resolve it lazily
BR="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
case "$FILE" in /*) ABS="$FILE";; *) ABS="$CWD/$FILE";; esac
# Prefix-match case-INSENSITIVELY (Windows + macOS default are case-insensitive filesystems, and
# Claude Code may hand us a cwd/path whose segments differ in case from git's toplevel). Compare on
# lowercased copies, but slice REL from the ORIGINAL-case ABS so files_owned matching stays exact.
REL=""; lc "$ABS"; ABS_LC="$REPLY"; lc "$TOP"; TOP_LC="$REPLY"
case "$ABS_LC" in
  "$TOP_LC"/*) REL="${ABS:$((${#TOP}+1))}";;
  *)
    # LAZY: `git worktree list` costs ~460ms and only matters when the write is NOT under this
    # worktree's own toplevel — i.e. a Builder in .polaris/wt/<ID> touching the primary checkout.
    # Resolving it eagerly taxed every ordinary write to answer a question they never ask.
    # Usually free now: the .polaris/wt/<ID> toplevel already named the primary above.
    if [ -z "$PRIMARY" ]; then
      PRIMARY="$(git -C "$CWD" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
      [ -n "$PRIMARY" ] && { norm "$PRIMARY"; PRIMARY="$REPLY"; }
    fi
    if [ -n "$PRIMARY" ]; then
      lc "$PRIMARY"
      case "$ABS_LC" in "$REPLY"/*) REL="${ABS:$((${#PRIMARY}+1))}";; esac
    fi;;
esac
if [ -z "$REL" ]; then
  case "$BR" in feat/*) ;; *) exit 0;; esac    # non-Builder sessions may write outside the repo
  echo "polaris-guard BLOCKED: $ABS is outside this repo. Task ${BR#feat/} may only write its files_owned." >&2
  exit 2
fi

# --- the primary checkout is not a lane ---------------------------------------
# The ownership gate below keys off the CURRENT DIRECTORY's branch, so a session that never
# entered its worktree sits in the primary on `main` with the ownership system fully disengaged —
# the exact state five colliding sessions were in. Contract: ops/contracts/shared-checkout.md § v2.2.
# Three conditions, cheapest first: (a) cwd is the primary worktree, (b) HEAD is not feat/*,
# (c) at least one task lock dir exists under <git-common-dir>/polaris-locks (a builder is live).
# The allowlist is checked FIRST and the answer to every unknown is ALLOW: PLANNER, INTEGRATOR,
# CONDUCTOR and EVOLVE legitimately write in the primary, and a gate that blocks them is worse than
# the bug it fixes. This NEVER returns the ownership rc — anything it does not deny falls through
# to today's exact behavior. No locks (INIT, a lone PLANNER, an empty board) = no gate: an accepted
# trade, recorded in the contract. Costs zero forks unless a write is already a deny candidate.
# rc 0 = allow / not our business · rc 2 = deny.
primary_gate() {
  [ -n "$WT_ID" ] && return 0                  # inside .polaris/wt/<ID> — the branch gate owns this
  case "$BR" in feat/*) return 0;; esac        # a feat/* HEAD is the branch gate's business
  case "$REL" in                               # primary-role surfaces, checked FIRST
    ops/board/*|ops/contracts/*|.polaris/*) return 0;;
    ops/*.md) case "${REL#ops/}" in */*) ;; *) return 0;; esac;;   # top-level ops docs only
  esac
  [ -n "$GCD" ] || return 0
  local d hit=""
  for d in "$GCD"/polaris-locks/*/; do
    [ -d "$d" ] || continue                    # no match — bash leaves the pattern verbatim
    case "${d%/}" in */.int-lease|*/.board-mutex) continue;; esac
    hit=1; break
  done
  [ -n "$hit" ] || return 0                    # nobody is building — nothing to collide with
  git -C "$TOP" ls-files --error-unmatch -- "$REL" >/dev/null 2>&1 || return 0   # untracked scratch
  { echo "polaris-guard BLOCKED: '$REL' is tracked source in the SHARED primary checkout, and a task lock is live."
    echo 'builders never edit the shared primary — claim a task and work in its worktree: bash ops/polaris claim, then cd .polaris/wt/<ID>'
    echo "Already claimed one? Then you are simply in the wrong directory: cd .polaris/wt/<ID> and re-run there."
    echo "Primary-role surfaces stay open: ops/board/ · ops/contracts/ · ops/*.md · .polaris/ · anything untracked."
  } >&2
  return 2
}
primary_gate || exit 2

# --- both gates in ONE polaris startup ----------------------------------------
# RULES (every session, every branch) then OWNERSHIP (only inside a Builder worktree, feat/<ID>).
# Same checks, same order as the old two-call form — but one process. Each polaris startup is
# ~3.8s on Windows/Git Bash, so two calls put a Builder's write at ~7.6s against this hook's
# timeout; at the ceiling the hook is killed and FAILS OPEN, dropping the ownership gate silently.
# rc: 0 clean · 1 a rule denies · 3 not in files_owned.
case "$BR" in feat/*) ID="${BR#feat/}";; *) ID="-";; esac
MSG="$("$TOP/ops/polaris" _guard "$REL" "$ID" "$BODY" 2>&1 >/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && exit 0
if [ "$RC" -eq 1 ]; then
  { printf '%s\n' "$MSG"
    echo "polaris-guard BLOCKED by ops/RULES.tsv. Rules bind even inside files_owned."
    # Pinned verbatim by ops/contracts/ask-approval.md § Pinned phrasing — single-quoted so the
    # backticks stay literal. An `ask` rule denies exactly like `path` until the approval is on the
    # task, so the cheapest correct outcome is naming it before the heavier "the rule is wrong".
    echo 'If a human has already approved this, it belongs on the task: `polaris approve <ID> <scope> -m "why"` — a Builder cannot run it.'
    echo "If the rule is wrong, that is a HUMAN decision: propose the change, do not work around it."
  } >&2
  exit 2
fi
{
  echo "polaris-guard BLOCKED: '$REL' is NOT in task $ID's files_owned."
  echo "Allowed: files_owned patterns · ops/board/active/$ID.md (Notes) · ops/board/backlog/IDEAS.md."
  echo "If you truly need this file: STOP and hand back — bash ops/polaris release $ID --to blocked -m \"needs <path>\""
} >&2
exit 2
