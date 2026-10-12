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
# The running session's own effort must never leak in: every effort case below sets CLAUDE_EFFORT on
# its own call (E= on R), and the cases above the effort section run with none at all.
unset CLAUDE_EFFORT
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

echo '== the effort ceiling: a spawn never asks for more than its caller has (effort-ceiling.md § 2) =='
# E <level|-> <label> — R with CLAUDE_EFFORT set to <level> for that one call only ('-' = unset).
E() { if [ "$1" = - ]; then R "$2"; else CLAUDE_EFFORT="$1" R "$2"; fi; }
cei() { local v='(none)'; [ -f "$ST/$1.effort" ] && { IFS= read -r v < "$ST/$1.effort"; }; printf '    ceiling %s: %s\n' "$1" "$v"; }
TX="$FIX/tx/a.jsonl"
SUB=',"agent_id":"sa1","agent_type":"general-purpose"'
AGT() { J e1 "$TX" PreToolUse Agent "{\"description\":\"d\",\"prompt\":\"p\"$1}" "${2:-}"; }
J e1 "$TX" PreToolUse Read "$READ"; E high 'main call on high records the ceiling'; cei e1
AGT ',"subagent_type":"general-purpose","effort":"max"'; E high 'Agent effort max, chat high'
AGT ',"subagent_type":"general-purpose","effort":"high"'; E high 'Agent effort high, chat high'
AGT ',"effort":"low"'; E high 'Agent effort low, chat high'
J e1 "$TX" PreToolUse Task '{"description":"d","prompt":"p","effort":"xhigh"}'; E high 'Task effort xhigh, chat high'
AGT ',"subagent_type":"general-purpose"'; E high 'Agent with no effort (nothing requested)'
AGT ',"effort":"turbo"'; E high 'Agent effort turbo (unknown word)'
AGT ',"prompt2":"never ask for \"effort\":\"max\" here"'; E high 'Agent whose PROSE names effort max (not a request)'
AGT ',"effort":"high"' "$SUB"; E medium 'nested spawn at high, caller subagent on medium'
AGT ',"effort":"medium"' "$SUB"; E medium 'nested spawn at medium, caller subagent on medium'
cei e1
echo '-- an agent definition asks, only for a type that is not built in --'
mkdir -p "$HOME/.claude/agents" "$FIX/work/.claude/agents" "$HOME/.claude/plugins/marketplaces/mk/plugins/sec/agents"
printf -- '---\nname: deep\nmodel: inherit\neffort: xhigh\n---\nbody effort: low\n' > "$HOME/.claude/agents/deep.md"
printf -- '---\r\nname: Explore\r\neffort: max\r\n---\r\n' > "$HOME/.claude/agents/Explore.md"
printf -- '---\nname: proj\neffort: "max"\n---\n' > "$FIX/work/.claude/agents/proj.md"
printf -- '---\nname: scan\ndescription: x\neffort: xhigh\n---\n' > "$HOME/.claude/plugins/marketplaces/mk/plugins/sec/agents/scan.md"
printf -- '---\nname: calm\neffort: medium\n---\n' > "$HOME/.claude/agents/calm.md"
AGT ',"subagent_type":"deep"'; E high 'definition deep (effort: xhigh), chat high'
AGT ',"subagent_type":"deep","effort":"high"'; E high 'definition deep, explicit effort high'
AGT ',"subagent_type":"sec:scan"'; E high 'plugin definition sec:scan (effort: xhigh), chat high'
AGT ',"subagent_type":"calm"'; E high 'definition calm (effort: medium), chat high'
AGT ',"subagent_type":"Explore"'; E high 'built-in Explore (a same-named file asks max)'
AGT ',"subagent_type":"nowhere"'; E high 'definition that exists nowhere'
printf -v IJ '{"session_id":"e1","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"p","subagent_type":"proj"}}' "$TX" "$FIX/work"
E high 'definition proj in <cwd>/.claude/agents (effort: "max")'
echo '-- a Workflow: every per-agent effort option --'
J e1 "$TX" PreToolUse Workflow "{\"script\":\"agent({prompt: \\\"p\\\", effort: 'max'})\"}"; E high "Workflow effort:'max', chat high"
J e1 "$TX" PreToolUse Workflow '{"script":"agent({prompt: \"a\", effort: \"low\"}); agent({prompt: \"b\", effort: \"xhigh\"})"}'; E high 'Workflow low then xhigh, chat high'
J e1 "$TX" PreToolUse Workflow "{\"script\":\"agent({prompt: \\\"p\\\", effort: 'medium'})\"}"; E high "Workflow effort:'medium', chat high"
echo '-- unknown on both sides, and the payload fallback --'
J e2 "$TX" PreToolUse Agent '{"description":"d","prompt":"p","effort":"max"}'; E - 'no caller effort, no ceiling, effort max'
cei e2
J e3 "$TX" PreToolUse Read "$READ" ',"effort":{"level":"medium"}'; E - 'payload effort.level medium, env unset'; cei e3
J e3 "$TX" PreToolUse Agent '{"description":"d","prompt":"p","effort":"high"}' ',"effort":{"level":"medium"}'; E - 'Agent effort high, payload says medium'
printf -v IJ '{"session_id":"e4","transcript_path":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"p"},"tool_response":{"status":"completed"}}' "$TX"
E low 'main PostToolUse on low records the ceiling'; cei e4
echo '-- the ceiling is the MAIN chat only, and is written only on a change --'
J e1 "$TX" PreToolUse Read "$READ" "$SUB"; E low 'a subagent call on low'; cei e1
MS e1 UserPromptSubmit ',"prompt":"hi"'; E max 'UserPromptSubmit with a leaked CLAUDE_EFFORT=max'
MS e1 SessionStart ',"source":"startup"'; E max 'SessionStart with a leaked CLAUDE_EFFORT=max'
cei e1
touch -t 200001010000 "$ST/e1.effort"; touch -t 200101010000 "$FIX/ref"
J e1 "$TX" PreToolUse Read "$READ"; E high 'main call, same level'
printf '    rewritten when unchanged: %s\n' "$( [ "$ST/e1.effort" -nt "$FIX/ref" ] && echo yes || echo no)"
echo '== mid-run: a pinned subagent left above a lowered chat is told about, never blocked =='
PIN=',"agent_id":"pin1","agent_type":"general-purpose"'; INH=',"agent_id":"inh1","agent_type":"general-purpose"'
OV="$ST/e1.over"
pend() { local n=0 l; [ -f "$OV/.pending" ] && while IFS= read -r l; do n=$((n + 1)); done < "$OV/.pending"; printf '    pending lines: %s\n' "$n"; }
J e1 "$TX" PreToolUse Read "$READ"; E medium 'the chat drops high -> medium'; cei e1
J e1 "$TX" PreToolUse Bash '{"command":"ls"}' "$PIN"; E xhigh 'pinned subagent on xhigh, ceiling medium'
printf '    marker pin1: %s\n' "$(cat "$OV/pin1")"; pend
J e1 "$TX" PreToolUse Bash '{"command":"ls"}' "$PIN"; E xhigh 'its next call'; pend
J e1 "$TX" PreToolUse Bash '{"command":"ls"}' "$INH"; E medium 'inheriting subagent, followed to medium'
printf '    marker inh1: %s\n' "$( [ -f "$OV/inh1" ] && echo written || echo none)"
printf -v IJ '{"session_id":"e1","transcript_path":"%s","agent_id":"pin1","agent_type":"general-purpose","effort":{"level":"xhigh"},"hook_event_name":"SubagentStop","stop_hook_active":false}' "$TX"
E xhigh 'SubagentStop with a note pending'
J e1 "$TX" PreToolUse Read "$READ"; E medium 'the main session next PreToolUse'
printf '    .pending after: %s\n' "$( [ -f "$OV/.pending" ] && echo present || echo removed)"
J e1 "$TX" PreToolUse Read "$READ"; E medium 'the main call after'
J e1 "$TX" PreToolUse Read "$READ"; E low 'the chat drops medium -> low'
J e1 "$TX" PreToolUse Bash '{"command":"ls"}' "$PIN"; E xhigh 'pinned subagent again, ceiling now low'
printf '    marker pin1: %s\n' "$(cat "$OV/pin1")"; pend
AGT ',"effort":"max"'; E low 'a refused main spawn while a note is pending'
printf '    .pending after: %s\n' "$( [ -f "$OV/.pending" ] && echo present || echo removed)"
J e1 "$TX" PreToolUse Read "$READ"; E low 'the next allowed main PreToolUse'
printf '    .pending after: %s\n' "$( [ -f "$OV/.pending" ] && echo present || echo removed)"

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
