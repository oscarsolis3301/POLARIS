# model-guard v2 (ops/contracts/speed.md § 2, T-173): the model ban reads a one-line state file per
# session, checks every spawn at the door, refuses a switch, flags a subagent that still ran on a
# forbidden model — and every fail-open path still exits 0. Each verdict is printed as its rc plus the
# exact words the hook sent back, so a reworded refusal reds this golden as surely as a wrong rc.
#
# HERMETIC: HOME and POLARIS_AWAKE_HOME point into this run's mktemp -d, so the real
# ~/.claude/polaris/model-state is never read or written, and no real transcript is ever opened.
H="$(pwd)/kit/ops/hooks/model-guard.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"
mkdir -p "$HOME" "$FIX/tx"
ST="$HOME/.claude/polaris/model-state"
OPUS=claude-opus-5-5; HAIKU=claude-haiku-4-5; FABLE=claude-fable-1
# J <session_id> <transcript> <event> <tool> <tool_input JSON> [extra top-level fields] — into $IJ.
# Builders fill $IJ and R feeds it on stdin from a file: no pipeline, so no subshell per case (forks
# are the whole cost of a golden on Windows).
J() { printf -v IJ '{"session_id":"%s","transcript_path":"%s","cwd":"/work","hook_event_name":"%s","tool_name":"%s"%s,"tool_input":%s}' \
        "$1" "$2" "$3" "$4" "${6:-}" "$5"; }
# R <label> — run the hook on $IJ; print rc, then stderr and stdout, one prefixed line each when set
R() {
  printf '%s' "$IJ" > "$FIX/in"
  bash "$H" < "$FIX/in" > "$FIX/out" 2> "$FIX/err"; rc=$?
  printf '%-58s rc %s\n' "$1" "$rc"
  while IFS= read -r l; do printf '    stderr: %s\n' "$l"; done < "$FIX/err"
  while IFS= read -r l; do printf '    stdout: %s\n' "$l"; done < "$FIX/out"
  return 0
}
line() { printf '{"type":"assistant","message":{"model":"%s","content":[{"type":"text","text":"ok"}]}}\n' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":"%s"}}\n' "$1"; }
READ='{"file_path":"/work/a.txt"}'

echo '== the common path: a state file, and the transcript is never opened =='
line "$HAIKU" > "$FIX/tx/s1.jsonl"            # a transcript that WOULD refuse, were it read
mkdir -p "$ST"; printf '%s\n' "$OPUS" > "$ST/s1"
J s1 "$FIX/tx/s1.jsonl" PreToolUse Read "$READ"; R 'state says an allowed model (transcript says haiku)'
printf '%s\n' "$FABLE" > "$ST/s1"
J s1 "$FIX/tx/s1.jsonl" PreToolUse Read "$READ"; R 'state says fable'
rm -f "$ST/s1"

echo '== the fallback: five transcript tail shapes, v1 last-model loop vs v2 grep =='
# The v1 algorithm, kept here as the reference the grep must agree with: the LAST "model":" value in
# the 64 KB tail, found by a pure-bash loop.
v1() {
  local t m='' r
  t="$(tail -c 65536 "$1")"; r="$t"
  while :; do case "$r" in *'"model":"'*) r="${r#*\"model\":\"}"; m="${r%%\"*}";; *) break;; esac; done
  case "$m" in *fable*|*Fable*|*FABLE*|*haiku*|*Haiku*|*HAIKU*) echo refuse;; *) echo allow;; esac
}
PAD="$(head -c 61440 /dev/zero | tr '\0' 'x')"
{ user hi; line "$OPUS"; }                                    > "$FIX/tx/a.jsonl"
{ line "$HAIKU"; line "$HAIKU"; user switched; line "$OPUS"; } > "$FIX/tx/b.jsonl"
{ line "$OPUS"; user switched; line "$FABLE"; }               > "$FIX/tx/c.jsonl"
{ line "$OPUS"
  printf '{"type":"assistant","message":{"model":"%s","content":[{"type":"tool_use","name":"Workflow","input":{"script":"%s"}}]}}\n' "$HAIKU" "$PAD"
} > "$FIX/tx/d.jsonl"
{ line "$HAIKU"; for i in 1 2 3 4 5 6 7 8 9; do user "$PAD"; done; } > "$FIX/tx/e.jsonl"
for s in a:plain-allowed b:switched-away-from-haiku c:switched-to-fable d:64KB-Workflow-line-model-60KB-back e:model-only-beyond-the-64KB-tail; do
  f="$FIX/tx/${s%%:*}.jsonl"
  J nostate "$f" PreToolUse Read "$READ"; printf '%s' "$IJ" > "$FIX/in"; bash "$H" < "$FIX/in" 2>/dev/null; rc=$?
  case "$rc" in 0) v2=allow;; 2) v2=refuse;; *) v2="rc$rc";; esac
  printf 'shape %-40s v1 %-6s v2 %-6s %s\n' "${s#*:}" "$(v1 "$f")" "$v2" "$( [ "$(v1 "$f")" = "$v2" ] && echo same || echo DIFFERENT)"
done

echo '== spawns are checked at the door =='
J s1 "$FIX/tx/a.jsonl" PreToolUse Agent '{"description":"d","prompt":"p","subagent_type":"claude-code-guide"}'; R 'Agent subagent_type claude-code-guide'
J s1 "$FIX/tx/a.jsonl" PreToolUse Task '{"description":"d","prompt":"p","subagent_type":"claude-code-guide"}'; R 'Task subagent_type claude-code-guide'
J s1 "$FIX/tx/a.jsonl" PreToolUse Agent '{"description":"d","prompt":"p","model":"haiku"}'; R 'Agent model haiku'
J s1 "$FIX/tx/a.jsonl" PreToolUse Agent '{"description":"d","prompt":"p","model":"fable"}'; R 'Agent model fable'
J s1 "$FIX/tx/a.jsonl" PreToolUse Task '{"description":"d","prompt":"p","model":"claude-haiku-4-5"}'; R 'Task model claude-haiku-4-5'
J s1 "$FIX/tx/a.jsonl" PreToolUse Workflow '{"script":"export default async () => agent({prompt: \"p\", model: \"haiku\"})"}'; R 'Workflow script argument model: "haiku"'
J s1 "$FIX/tx/a.jsonl" PreToolUse Workflow '{"script":"run()","args":{"model":"claude-fable-1"}}'; R 'Workflow "model" key claude-fable-1'
J s1 "$FIX/tx/a.jsonl" PreToolUse Workflow "{\"script\":\"agent({agentType: 'claude-code-guide'})\"}"; R 'Workflow agentType claude-code-guide'
J s1 "$FIX/tx/a.jsonl" PreToolUse Agent '{"description":"d","prompt":"p","subagent_type":"general-purpose"}'; R 'Agent with no model'
J s1 "$FIX/tx/a.jsonl" PreToolUse Agent '{"description":"d","prompt":"p","model":"sonnet"}'; R 'Agent model sonnet'
J s1 "$FIX/tx/a.jsonl" PreToolUse Agent '{"description":"d","prompt":"never set model: \"haiku\" nor spawn claude-code-guide"}'; R 'Agent whose PROSE names both (not a request)'
J s1 "$FIX/tx/a.jsonl" PreToolUse Workflow '{"script":"agent({prompt: \"p\", model: \"opus\"})"}'; R 'Workflow on an allowed model'

echo '== a subagent is judged by ITS OWN transcript, never the parent =='
P="$FIX/tx/parent.jsonl"; line "$OPUS" > "$P"; printf '%s\n' "$OPUS" > "$ST/par"
mkdir -p "$FIX/tx/parent/subagents/workflows/wf1"
line "$HAIKU" > "$FIX/tx/parent/subagents/agent-a1.jsonl"
line "$FABLE" > "$FIX/tx/parent/subagents/workflows/wf1/agent-w1.jsonl"
line "$OPUS"  > "$FIX/tx/parent/subagents/agent-a2.jsonl"
J par "$P" PreToolUse Read "$READ" ',"agent_id":"a1","agent_type":"general-purpose"'; R 'agent a1 on haiku (parent opus in state + transcript)'
J par "$P" PreToolUse Read "$READ" ',"agent_id":"w1"'; R 'workflow agent w1 on fable'
printf '%s\n' "$HAIKU" > "$ST/par"; line "$HAIKU" > "$P"
J par "$P" PreToolUse Read "$READ" ',"agent_id":"a2"'; R 'agent a2 on opus (parent haiku in state + transcript)'
J par "$P" PreToolUse Read "$READ"; R 'the parent itself, same state'
J par "$P" PreToolUse Read "$READ" ',"agent_id":"a404"'; R 'agent with no transcript anywhere (fail open)'

echo '== the switch: refused before, recorded after =='
MS() { printf -v IJ '{"session_id":"%s","transcript_path":"%s","hook_event_name":"%s"%s}' "$1" "$FIX/tx/a.jsonl" "$2" "$3"; }
MS sw PreModelSwitch ',"from_model":"claude-opus-5-5","to_model":"claude-haiku-4-5"'; R 'PreModelSwitch to haiku'
MS sw PreModelSwitch ',"from_model":"claude-opus-5-5","to_model":"fable"'; R 'PreModelSwitch to fable'
MS sw PreModelSwitch ',"from_model":"claude-haiku-4-5","to_model":"opus"'; R 'PreModelSwitch to opus'
MS sw PreModelSwitch ',"to_model":"claude-sonnet-4-6"'; R 'PreModelSwitch to sonnet'
MS sw SessionStart ',"source":"startup","model":"claude-opus-5-5"'; R 'SessionStart with a model'
printf '    state sw: %s\n' "$(cat "$ST/sw")"
MS sw PostModelSwitch ',"from_model":"claude-opus-5-5","to_model":"claude-sonnet-4-6"'; R 'PostModelSwitch to sonnet'
printf '    state sw: %s\n' "$(cat "$ST/sw")"
MS ss SessionStart ',"source":"startup"'; R 'SessionStart with no model field'
MS 'a/b' SessionStart ',"model":"x-slash"'; R 'SessionStart, session_id with /'
MS 'a\\b' PostModelSwitch ',"to_model":"x-backslash"'; R 'PostModelSwitch, session_id with \'
MS '..' SessionStart ',"model":"x-dotdot"'; R 'SessionStart, session_id ..'
printf 'state files now: %s\n' "$(cd "$ST" && ls | LC_ALL=C sort | tr '\n' ' ')"
printf 'anything written outside model-state: %s\n' "$( (cd "$HOME" && find . -type f | grep -v '^\./\.claude/polaris/model-state/') | wc -l | tr -d ' ')"

echo '== PostToolUse on Agent: a forbidden resolved model is flagged, never blocked =='
PT() { printf -v IJ '{"session_id":"s1","transcript_path":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"prompt":"p"},"tool_response":%s}' "$FIX/tx/a.jsonl" "$1" "$2"; }
PT Agent '{"status":"completed","resolvedModel":"claude-haiku-4-5","content":[{"type":"text","text":"done"}]}'; R 'resolvedModel haiku'
PT Agent '{"status":"completed","usage":{"model":"claude-opus-5-5"},"meta":{"model":"claude-fable-1"}}'; R 'no resolvedModel, last "model" is fable'
PT Agent '{"status":"completed","resolvedModel":"claude-opus-5-5"}'; R 'resolvedModel opus'
PT Agent '{"status":"completed","content":"no model anywhere"}'; R 'nothing found'
PT Bash '{"stdout":"","resolvedModel":"claude-haiku-4-5"}'; R 'not an Agent call'

echo '== every fail-open path still exits 0 =='
: | bash "$H"; printf '%-58s rc %s\n' 'no stdin at all' "$?"
IJ='{}'; R 'an empty object'
IJ='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{}}'; R 'no session_id, no transcript_path'
J nostate "$FIX/tx/missing.jsonl" PreToolUse Read "$READ"; R 'transcript does not exist'
mkdir -p "$FIX/tx/dir.jsonl"
J nostate "$FIX/tx/dir.jsonl" PreToolUse Read "$READ"; R 'transcript unreadable (a directory)'
user 'no model line yet' > "$FIX/tx/nomodel.jsonl"
J nostate "$FIX/tx/nomodel.jsonl" PreToolUse Read "$READ"; R 'transcript with no model line'
MS s1 Stop ',"stop_hook_active":false'; R 'an event it was never registered for'

echo '== the install branch: five entries, merged, never clobbering, idempotent =='
SJ="$HOME/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"mine.sh"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"mine-too.sh"}]}]}}\n' > "$SJ"
# python prints CRLF on Windows and every .expected is LF (.gitattributes): \r goes on the way out
bash "$H" install | tr -d '\r' | sed "s#written to .*#written to <settings>#"
bash "$H" install | tr -d '\r' | sed "s#written to .*#written to <settings>#"
python - "$SJ" <<'PY' | tr -d '\r'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
for ev in ("PreToolUse", "PreModelSwitch", "SessionStart", "PostModelSwitch", "PostToolUse"):
    row = []
    for e in d.get(ev, []):
        c = " ".join(h.get("command", "") for h in e.get("hooks", []))
        who = "model-guard" if "polaris/model-guard.sh" in c.replace("\\", "/") else c
        row.append("%s[%s]" % (who, e.get("matcher", "-")))
    print("  %-16s %s" % (ev, " · ".join(row)))
PY
