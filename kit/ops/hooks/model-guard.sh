#!/usr/bin/env bash
# kit/ops/hooks/model-guard.sh — the machine-wide model ban. Fable and Haiku are FORBIDDEN (owner
# decision 2026-09-15, absolute, on every machine). v2 (ops/contracts/speed.md § 2) is ONE script
# that branches on the hook's `hook_event_name`:
#   SessionStart · PostModelSwitch  record the session's model in a one-line state file (always exit 0)
#   PreModelSwitch                   refuse a switch TO a forbidden model
#   PreToolUse (matcher "*")         refuse a forbidden spawn at the door, then refuse EVERY call while
#                                    the session — or the subagent making the call — runs one
#   PostToolUse (matcher "Agent")    a subagent that still ran on one → the parent is told to discard it
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
# below is deliberate. Test the failing-open paths harder than the blocking one. The ONLY exits 2
# are the explicit denies of speed.md § 2 — there is no other fail-closed path.
#
# SPEED (v2). v1 scanned the last 64 KB of the transcript in a pure-bash loop on EVERY call: 0.5-2.3 s,
# which piled up past the hook's 5 s timeout whenever a conductor started several agents at once — and
# a timed-out hook lets the call through, so the ban lapsed exactly when it mattered most. Now:
#   - the common path is builtins plus ONE small file read: $HOME/.claude/polaris/model-state/<sid>,
#     written by SessionStart and PostModelSwitch, so a /model switch is seen on the very next call
#     (the reason v1 refused to cache anything at all);
#   - only a missing state file (or a subagent's call) reads a transcript, and then with one grep;
#   - `${IN#*pat}` / `${IN%%pat*}` cost O(position x length) in bash — 18 s on a 200 KB Write. Every
#     field is read by a linear `=~` from the HEAD of the payload (everything before tool_input), and
#     the one cut that makes that head sits a few hundred bytes in.

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
# the ban has to cover projects that have never heard of POLARIS. Five entries, one per event this
# script answers (speed.md § 2); a second run writes nothing.
#
# TWO deliberate differences from the keep-awake entries, and both are load-bearing:
#   matcher "*"  — every tool, not a subset. A forbidden session must not be able to do ANYTHING.
#   no `2>/dev/null || true` — keep-awake is advisory so it swallows its own failures; this hook
#                  BLOCKS by exiting 2 with a reason on stderr, and `|| true` would discard exactly
#                  that. Swallowing it would leave a guard that looks installed and enforces nothing.
if [ "${1:-}" = "install" ]; then
  mg_sj="${HOME:-.}/.claude/settings.json"; mg_b="$(command -v bash 2>/dev/null)" || mg_b=bash
  mg_py=''
  python -c pass >/dev/null 2>&1 && mg_py=python || { python3 -c pass >/dev/null 2>&1 && mg_py=python3; } || true
  [ -n "$mg_py" ] || { printf 'model-guard: no python — add the five hook entries to %s by hand (speed.md § 2)\n' "$mg_sj"; exit 0; }
  mkdir -p "${mg_sj%/*}" 2>/dev/null || true
  "$mg_py" - "$mg_sj" "$mg_b" "${HOME:-.}/.claude/polaris/model-guard.sh" <<'PYEOF'
import json, os, re, sys
p, sh, hk = sys.argv[1], sys.argv[2], sys.argv[3]
cmd = [{"type": "command", "timeout": 5, "command": '"%s" "%s"' % (sh, hk)}]
# (event, matcher, first). The two refusing entries go FIRST: refuse before any other guard spends time.
EV = (("PreToolUse", "*", True), ("PreModelSwitch", None, True), ("SessionStart", None, False),
      ("PostModelSwitch", None, False), ("PostToolUse", "Agent", False))
ents = [(ev, {"matcher": m, "hooks": cmd} if m else {"hooks": cmd}, first) for ev, m, first in EV]
ours = re.compile(r"polaris/model-guard\.sh")
mine = lambda e: isinstance(e, dict) and any(isinstance(h, dict) and ours.search(
    str(h.get("command", "")).replace("\\", "/")) for h in (e.get("hooks") or []))
def bail(why):                                 # fails OPEN: print them, rewrite nothing
    print("model-guard: %s %s — add these by hand:" % (p, why))
    for ev, e, _ in ents: print("  %s: %s" % (ev, json.dumps(e)))
    raise SystemExit(0)
try: d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
except (OSError, ValueError) as exc: bail("is unreadable (%s)" % exc)
if not isinstance(d, dict): bail("is not a JSON object")
hooks = d.setdefault("hooks", {})
if not isinstance(hooks, dict): bail('has a non-object "hooks"')
n = 0
for ev, ent, first in ents:
    have = hooks.setdefault(ev, [])
    if not isinstance(have, list): bail('has a non-list "%s"' % ev)
    at = [i for i, e in enumerate(have) if mine(e)]
    if not at: have.insert(0, ent) if first else have.append(ent); n += 1
    elif have[at[0]] != ent: have[at[0]] = ent; n += 1
if n:
    try:                                       # tmp + os.replace: never a truncated settings.json
        open(p + ".polaris-tmp", "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
        os.replace(p + ".polaris-tmp", p)
    except OSError as exc: bail("could not be written (%s)" % exc)
print("model-guard: %d of %d hook entries written to %s" % (n, len(ents), p))
PYEOF
  exit 0
fi

# Bytes, not characters: every match below is on JSON keys and model ids, and a multibyte locale only
# makes bash's matcher slower and lets a stray invalid byte defeat a match. Exported for tail/grep too.
export LC_ALL=C

# --- read the hook JSON (builtin; no fork) -----------------------------------
IN=''
IFS= read -r -d '' IN 2>/dev/null
[ -n "$IN" ] || exit 0                       # no stdin at all → allow

# --- the top-level fields, from the HEAD of the payload ----------------------
# Every top-level field Claude Code sends precedes tool_input, and tool_input is the part that can be
# huge (a Write's whole file). One cut isolates the head; `=~` reads each field from it in linear time.
MG_H="$IN"
case "$IN" in *'"tool_input":'*) MG_H="${IN%%\"tool_input\":*}";; esac
MG_EV=''; MG_SID=''; MG_TP=''; MG_TOOL=''; MG_AID=''
mg_re='"hook_event_name":"([^"]*)"'; [[ $MG_H =~ $mg_re ]] && MG_EV="${BASH_REMATCH[1]}"
mg_re='"session_id":"([^"]*)"';      [[ $MG_H =~ $mg_re ]] && MG_SID="${BASH_REMATCH[1]}"
mg_re='"transcript_path":"([^"]*)"'; [[ $MG_H =~ $mg_re ]] && MG_TP="${BASH_REMATCH[1]}"
mg_re='"tool_name":"([^"]*)"';       [[ $MG_H =~ $mg_re ]] && MG_TOOL="${BASH_REMATCH[1]}"
mg_re='"agent_id":"([^"]*)"'
if [[ $MG_H =~ $mg_re ]]; then MG_AID="${BASH_REMATCH[1]}"
else case "$IN" in *'"agent_id":"'*) [[ $IN =~ $mg_re ]] && MG_AID="${BASH_REMATCH[1]}";; esac; fi
MG_TP="${MG_TP//\\\\/\\}"                    # JSON escapes Windows separators ...
MG_TP="${MG_TP//\\//}"                       # ... and forward slashes are what bash globs safely
# <session_id> names a file, so it must be a plain name: `/`, `\` or `..` in it → no state at all.
case "$MG_SID" in ''|*[!A-Za-z0-9_-]*) MG_SF='';; *) MG_SF="${HOME:+$HOME/.claude/polaris/model-state/$MG_SID}";; esac

case "$MG_EV" in
  # --- SessionStart · PostModelSwitch: record the model, never block ---------
  SessionStart|PostModelSwitch)
    mg_re='"model":"([^"]*)"'
    [ "$MG_EV" = PostModelSwitch ] && mg_re='"to_model":"([^"]*)"'
    [[ $MG_H =~ $mg_re ]] || exit 0            # no model field → nothing to record
    MG_M="${BASH_REMATCH[1]}"
    [ -n "$MG_M" ] && [ -n "$MG_SF" ] || exit 0
    [ -d "${MG_SF%/*}" ] || mkdir -p "${MG_SF%/*}" 2>/dev/null || exit 0
    { printf '%s\n' "$MG_M" > "$MG_SF"; } 2>/dev/null
    exit 0;;

  # --- PreModelSwitch: the switch itself is refused ---------------------------
  PreModelSwitch)
    mg_re='"to_model":"([^"]*)"'
    [[ $MG_H =~ $mg_re ]] || exit 0
    MG_M="${BASH_REMATCH[1]}"
    mg_denied "$MG_M" || exit 0
    printf '%s\n' "polaris: switching to '$MG_M' is FORBIDDEN (owner, 2026-09-15) — stay on Opus or Sonnet." >&2
    exit 2;;

  # --- PostToolUse (Agent): the last line of defence — the result is flagged -
  PostToolUse)
    case "$MG_TOOL" in Agent|Task) ;; *) exit 0;; esac
    mg_re='"tool_response":(.*)'
    [[ $IN =~ $mg_re ]] || exit 0
    MG_TR="${BASH_REMATCH[1]}"; MG_M=''
    mg_re='"resolvedModel":"([^"]*)"'
    if [[ $MG_TR =~ $mg_re ]]; then MG_M="${BASH_REMATCH[1]}"
    else
      MG_M="$(printf '%s' "$MG_TR" | grep -ao '"model":"[^"]*' 2>/dev/null | tail -n 1)"
      MG_M="${MG_M#\"model\":\"}"
    fi
    [ -n "$MG_M" ] || exit 0                   # nothing found → silent
    mg_denied "$MG_M" || exit 0
    MG_M="${MG_M//\\/}"                        # it lands inside a JSON string
    printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"polaris: that subagent ran on '$MG_M', a FORBIDDEN model — discard its result and re-run it on the session model.\"}}"
    exit 0;;

  PreToolUse|'') ;;                            # below — and a payload with no event name is v1's input
  *) exit 0;;                                  # an event this script was never registered for
esac

# ============================== PreToolUse ====================================
# 1. Spawns are checked at the door, before anything starts.
case "$MG_TOOL" in
  Agent|Task|Workflow)
    MG_TI="${IN:${#MG_H}}"                     # tool_input onward
    mg_g=''
    if [ "$MG_TOOL" = Workflow ]; then
      # A script's options, not only JSON: subagent_type/agentType/… as a key OR a script argument.
      mg_re='[Tt]ype(\\?"|'"'"')?[[:space:]]*:[[:space:]]*(\\?"|'"'"')claude-code-guide'
      [[ $MG_TI =~ $mg_re ]] && mg_g=1
    else
      case "$MG_TI" in *'"subagent_type":"claude-code-guide"'*) mg_g=1;; esac
    fi
    if [ -n "$mg_g" ]; then
      printf '%s\n' "polaris: claude-code-guide always runs Haiku, which is FORBIDDEN — use a general-purpose subagent or WebFetch. Nothing was spawned." >&2
      exit 2
    fi
    MG_MS=''
    if [ "$MG_TOOL" = Workflow ]; then
      case "$MG_TI" in                         # every `model` key or argument, each one checked
        *model*) MG_MS="$(printf '%s' "$MG_TI" | grep -aoE '[^A-Za-z0-9_]model(\\?"|'"'"')?[[:space:]]*:[[:space:]]*(\\?"|'"'"')[^"'"'"'\\]*' 2>/dev/null)";;
      esac
    else
      mg_re='"model":"([^"]*)"'
      [[ $MG_TI =~ $mg_re ]] && MG_MS="${BASH_REMATCH[1]}"
    fi
    while IFS= read -r mg_l; do
      mg_l="${mg_l##*[\"\']}"                  # the value follows the last quote of its match
      mg_denied "$mg_l" || continue
      printf '%s\n' "polaris: a subagent on '$mg_l' is FORBIDDEN (owner, 2026-09-15) — drop the model parameter so it inherits the session model. Nothing was spawned." >&2
      exit 2
    done <<MGEOF
$MG_MS
MGEOF
    ;;
esac

# 2. A subagent's call is judged by ITS OWN transcript — never the parent's state or transcript.
MG_M=''; MG_T=''
if [ -n "$MG_AID" ]; then
  case "$MG_AID" in *[!A-Za-z0-9_-]*) exit 0;; esac   # not a plain name → cannot be located → allow
  [ -n "$MG_TP" ] || exit 0
  mg_b="${MG_TP%.jsonl}"
  if [ -f "$mg_b/subagents/agent-$MG_AID.jsonl" ]; then
    MG_T="$mg_b/subagents/agent-$MG_AID.jsonl"
  else
    for mg_f in "$mg_b"/subagents/workflows/*/"agent-$MG_AID.jsonl"; do
      [ -f "$mg_f" ] && { MG_T="$mg_f"; break; }
    done
  fi
  [ -n "$MG_T" ] || exit 0                     # neither exists → allow
else
  # 3. The session's own call: the state file — one line, one builtin read.
  [ -n "$MG_SF" ] && { IFS= read -r MG_M < "$MG_SF"; } 2>/dev/null
  MG_M="${MG_M%$'\r'}"
  if [ -z "$MG_M" ]; then                      # absent → the transcript fallback
    [ -n "$MG_TP" ] || exit 0                  # field absent → allow
    MG_T="$MG_TP"
  fi
fi

# 4. A transcript read is grep-only: the LAST model in the 64 KB tail. Last, not any — a session that
#    just switched away from a denied model must stop being blocked at once, and its earlier lines
#    still name the old one. No 4 KB-first hybrid: it is slower on a 64 KB Workflow line.
if [ -n "$MG_T" ]; then
  [ -f "$MG_T" ] || exit 0                     # not a readable file → allow
  [ -r "$MG_T" ] || exit 0
  MG_M="$(tail -c 65536 "$MG_T" 2>/dev/null | grep -ao '"model":"[^"]*' 2>/dev/null | tail -n 1)"
  MG_M="${MG_M#\"model\":\"}"
fi
[ -n "$MG_M" ] || exit 0                       # no model recorded yet → allow

mg_denied "$MG_M" || exit 0                    # an allowed model → allow, silently

# --- block -------------------------------------------------------------------
# One line, plain, actionable. It repeats on every tool call by design: the session cannot proceed
# until the human switches, and a single missable warning is what let this cost 87% of a weekly limit.
printf '%s\n' "polaris: this session is running '$MG_M', which is FORBIDDEN (owner, 2026-09-15). Fable bills a separate weekly limit and Haiku is too weak for this work — neither may be used in any project. Switch with /model (Opus or Sonnet), then retry. Nothing has been read, written or run." >&2
exit 2
