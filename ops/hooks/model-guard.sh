#!/usr/bin/env bash
# kit/ops/hooks/model-guard.sh — PreToolUse. Refuse EVERY tool call while the session is running a
# FORBIDDEN model (Fable, Haiku). Owner decision 2026-09-15, absolute, on every machine.
#
# Exit 2 = block (stderr goes back to Claude, exactly like ownership-guard.sh). Exit 0 = allow.
#
# WHY THIS EXISTS. `model_strong: fable` plus `route` returning `strong` for every planner/integrator/
# evolve role sent ~12 subagents to Fable in ONE day, several over 300k tokens. Fable bills a
# SEPARATE, much smaller weekly limit and reached 87% on work nobody asked to run there. core.sh's
# model_denied stops POLARIS ever NAMING those models; this stops a session that is already ON one
# from spending anything. A blocked session can still talk — it just cannot read, write, run or spawn.
#
# ===== IT MUST FAIL OPEN. =====
# No stdin · no transcript_path · unreadable file · no "model" line · anything unexpected ⇒ exit 0.
# This runs before EVERY tool call on the machine, so a guard that failed closed on a detection miss
# would brick every session in every project — far worse than the problem it solves. Every `exit 0`
# below is deliberate. Test the failing-open paths harder than the blocking one.
#
# SPEED. Same discipline as ownership-guard.sh: it runs on every tool call, so no python, and the
# common case is bash builtins plus ONE fork (`tail`). Nothing is cached — a session can switch model
# mid-flight with /model, and a cached verdict would keep blocking someone who already complied.

# --- the ban, mirrored from kit/ops/lib/core.sh model_denied ------------------
# DUPLICATED ON PURPOSE: sourcing core.sh would drag its whole env setup into every tool call. The
# selftest asserts these two lists stay identical — if you edit one, edit both.
mg_denied() {
  case "${1:-}" in
    '') return 1;;
    *fable*|*Fable*|*FABLE*|*haiku*|*Haiku*|*HAIKU*) return 0;;
  esac
  return 1
}

# --- install: register this script machine-wide ------------------------------
# Mirrors awake-hook.sh's ah_install BY SCRIPT IDENTITY — an entry running our path is ours and is
# replaced wholesale; every other one is the human's and is left as found. Machine-level on purpose:
# the ban has to cover projects that have never heard of POLARIS.
#
# TWO deliberate differences from the keep-awake entry, and both are load-bearing:
#   matcher "*"  — every tool, not a subset. A forbidden session must not be able to do ANYTHING.
#   no `2>/dev/null || true` — keep-awake is advisory so it swallows its own failures; this hook
#                  BLOCKS by exiting 2 with a reason on stderr, and `|| true` would discard exactly
#                  that. Swallowing it would leave a guard that looks installed and enforces nothing.
if [ "${1:-}" = "install" ]; then
  mg_sj="${HOME:-.}/.claude/settings.json"; mg_b="$(command -v bash 2>/dev/null)" || mg_b=bash
  mg_py=''
  python -c pass >/dev/null 2>&1 && mg_py=python || { python3 -c pass >/dev/null 2>&1 && mg_py=python3; } || true
  [ -n "$mg_py" ] || { printf 'model-guard: no python — add the PreToolUse entry to %s by hand\n' "$mg_sj"; exit 0; }
  mkdir -p "${mg_sj%/*}" 2>/dev/null || true
  "$mg_py" - "$mg_sj" "$mg_b" "${HOME:-.}/.claude/polaris/model-guard.sh" <<'PYEOF'
import json, os, re, sys
p, sh, hk = sys.argv[1], sys.argv[2], sys.argv[3]
ent = {"matcher": "*", "hooks": [{"type": "command", "timeout": 5,
       "command": '"%s" "%s"' % (sh, hk)}]}
ours = re.compile(r"polaris/model-guard\.sh")
mine = lambda e: isinstance(e, dict) and any(isinstance(h, dict) and ours.search(
    str(h.get("command", "")).replace("\\", "/")) for h in (e.get("hooks") or []))
def bail(why):                                 # fails OPEN: print it, rewrite nothing
    print("model-guard: %s %s — add this by hand:" % (p, why))
    print("  PreToolUse: %s" % json.dumps(ent))
    raise SystemExit(0)
try: d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
except (OSError, ValueError) as exc: bail("is unreadable (%s)" % exc)
if not isinstance(d, dict): bail("is not a JSON object")
hooks = d.setdefault("hooks", {})
if not isinstance(hooks, dict): bail('has a non-object "hooks"')
have = hooks.setdefault("PreToolUse", [])
if not isinstance(have, list): bail('has a non-list "PreToolUse"')
at = [i for i, e in enumerate(have) if mine(e)]
n = 0
if not at: have.insert(0, ent); n = 1          # FIRST: refuse before any other guard spends time
elif have[at[0]] != ent: have[at[0]] = ent; n = 1
try:                                           # tmp + os.replace: never a truncated settings.json
    open(p + ".polaris-tmp", "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
    os.replace(p + ".polaris-tmp", p)
except OSError as exc: bail("could not be written (%s)" % exc)
print("model-guard: %d entry written to %s" % (n, p))
PYEOF
  exit 0
fi

# --- read the hook JSON (builtin; no fork) -----------------------------------
IN=''
IFS= read -r -d '' IN 2>/dev/null
[ -n "$IN" ] || exit 0                       # no stdin at all → allow

# --- transcript_path, by pure-bash string surgery ----------------------------
case "$IN" in
  *'"transcript_path":"'*) : ;;
  *) exit 0 ;;                               # field absent → allow
esac
TP="${IN#*\"transcript_path\":\"}"
TP="${TP%%\"*}"
[ -n "$TP" ] || exit 0
TP="${TP//\\\\/\\}"                          # JSON escapes Windows separators
[ -f "$TP" ] || exit 0                       # not a readable file → allow
[ -r "$TP" ] || exit 0

# --- the LAST model recorded in the transcript tail --------------------------
# Last, not any: a session that has just switched away from a denied model must stop being blocked
# immediately, and its earlier lines still name the old one. 64KB covers many turns and bounds cost.
TAIL="$(tail -c 65536 "$TP" 2>/dev/null)" || exit 0
[ -n "$TAIL" ] || exit 0

MG_M=''
mg_rest="$TAIL"
while [ -n "$mg_rest" ]; do
  case "$mg_rest" in
    *'"model":"'*)
      mg_rest="${mg_rest#*\"model\":\"}"
      MG_M="${mg_rest%%\"*}"
      ;;
    *) break ;;
  esac
done
[ -n "$MG_M" ] || exit 0                     # no model recorded yet → allow

mg_denied "$MG_M" || exit 0                  # an allowed model → allow, silently

# --- block -------------------------------------------------------------------
# One line, plain, actionable. It repeats on every tool call by design: the session cannot proceed
# until the human switches, and a single missable warning is what let this cost 87% of a weekly limit.
printf '%s\n' "polaris: this session is running '$MG_M', which is FORBIDDEN (owner, 2026-09-15). Fable bills a separate weekly limit and Haiku is too weak for this work — neither may be used in any project. Switch with /model (Opus or Sonnet), then retry. Nothing has been read, written or run." >&2
exit 2
