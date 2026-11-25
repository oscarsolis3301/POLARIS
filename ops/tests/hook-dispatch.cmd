# kit/ops/hooks/dispatch.sh is the ONE hook (ops/contracts/hook-dispatch.md § 2). Guards fail open, so
# a dispatcher bug would switch every guard off at once: this golden is the gate (§ 7).
# (a) REPLAY — each guard battery runs from a temp copy of its .cmd in which every `bash "$<guard>"`
#     call becomes `bash "<that dir>/dispatch.sh" --as <guard>`, inside a machine-project fixture
#     (CLAUDE_PROJECT_DIR = a dir whose ops/polaris is the launcher, no ops/lib/); its output must
#     equal the battery's own .expected byte for byte. The batteries themselves are never edited.
# (b) MERGE — the full dispatcher against the deny > ask > allow composition of the separate scripts.
# (c) STAND-DOWN — vendored and non-POLARIS dirs: model-guard's verdict and nothing else.
# (d) NAME HYGIENE — the four guards and the dispatcher share one shell with no collision.
# (e) SessionStart — dispatch-session.sh is sourced when it is there, and nothing is printed when not.
# HERMETIC: (b)-(e) fake HOME / USERPROFILE / CLAUDE_CONFIG_DIR / POLARIS_AWAKE_HOME under one mktemp -d;
# POLARIS_PREFS= ; CLAUDECODE set; no path, time or pid is printed.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/mp/ops" "$T/vend/ops/lib" "$T/none" "$T/fake/ops" "$T/home"
cp kit/ops/launcher "$T/mp/ops/polaris"; cp kit/ops/launcher "$T/vend/ops/polaris"
{ cat kit/ops/launcher; printf '#'; } > "$T/fake/ops/polaris"        # one byte more than the launcher
mkdir -p "$T/mp/sub/ops" "$T/mp/gsub/ops" "$T/mp/plain"           # nested: a fake copy, a genuine one, none
cp "$T/fake/ops/polaris" "$T/mp/sub/ops/polaris"; cp kit/ops/launcher "$T/mp/gsub/ops/polaris"
unset DP_TRUST CLAUDE_EFFORT

echo '== (a) replay: every guard battery through dispatch.sh --as <guard> =='
rp() { # rp <battery> <the battery's guard variable> <guard>
  sed -e "s#bash \"\\\$$2\"#bash \"\${$2%/*}/dispatch.sh\" --as $3#g" \
      -e "s#cp \"\\\$H\" \"\\\$HK\";#cp \"\$H\" \"\$HK\"; cp kit/ops/hooks/dispatch.sh \"\${HK%/*}/\";#" \
      "ops/tests/$1.cmd" > "$T/$1.cmd"
  n="$(grep -c -- "--as $3" "$T/$1.cmd")"
  got="$(CLAUDE_PROJECT_DIR="$T/mp" POLARIS_PREFS= bash -c "$(cat "$T/$1.cmd")" 2>/dev/null)"; rc=$?
  want=0; [ -f "ops/tests/$1.rc" ] && want="$(tr -d ' \r\n' < "ops/tests/$1.rc")"
  if [ "$n" -gt 0 ] && [ "$rc" = "$want" ] && printf '%s\n' "$got" | diff -q - "ops/tests/$1.expected" >/dev/null 2>&1; then
    echo "$1: identical"
  else
    echo "$1: DIFFERS (calls rewritten: $n, rc $rc)"; printf '%s\n' "$got" | diff "ops/tests/$1.expected" - | head -20
  fi
}
rp readonly-allow H readonly-allow
rp checkout-guard-denies H checkout-guard
rp presence-guard H presence-guard
rp model-guard-v2 H model-guard
rp ownership-primary HK ownership-guard
rp permission-hook H permission-hook
rp handover-stop HOOK handover-hook

export HOME="$T/home" USERPROFILE="$T/home" POLARIS_AWAKE_HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude"
export POLARIS_PREFS= CLAUDECODE=1 PYTHONIOENCODING=utf-8
ST="$CLAUDE_CONFIG_DIR/polaris/model-state"; mkdir -p "$ST"
printf 'claude-opus-5-5\n' > "$ST/op"; printf 'claude-haiku-4-5\n' > "$ST/hk"; printf 'claude-opus-5-5\n' > "$ST/aw"
printf 'auto\n' > "$ST/aw.mode"; printf '1\n' > "$ST/aw.approved"
HK="$PWD/kit/ops/hooks"; DP="$HK/dispatch.sh"
# A trust tier that approves everything — proves the dispatcher asks the trust copy, and lets a
# checkout deny meet a real allow (the shipped guards never both fire on one command).
printf '%s\n' '_ra_hook() { printf -v HOUT "%s\n" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\",\"permissionDecisionReason\":\"stub\"}}"; HERR=""; HRC=0; }' \
  'case "${BASH_SOURCE[0]}" in "$0") _ra_hook; printf "%s" "$HOUT";; esac' > "$T/allow-all.sh"
pj() { # pj <sid> <dir> <tool> [command] — a PreToolUse payload
  printf '{"session_id":"%s","permission_mode":"auto","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":{"command":"%s"}}' "$1" "$T/$2" "$3" "${4:-}"
}
word() { # word <rc> <stdout> — the verdict Claude Code reads
  [ "$1" = 2 ] && { echo deny-exit2; return; }
  case "$2" in
    *'"permissionDecision":"deny"'*) echo deny;; *'"permissionDecision":"ask"'*) echo ask;;
    *'"permissionDecision":"allow"'*) echo allow;; '') echo none;; *) echo other;;
  esac
}
solo() { # solo <payload> <read-only script> — the four separate scripts, composed deny > ask > allow
  printf '%s' "$1" | bash "$HK/model-guard.sh" >/dev/null 2>&1
  [ $? = 2 ] && { echo deny-exit2; return; }
  best=none
  for g in "$HK/presence-guard.sh" "$HK/checkout-guard.sh" "$2"; do
    w="$(word 0 "$(printf '%s' "$1" | bash "$g" 2>/dev/null)")"
    case "$w" in deny) echo deny; return;; ask) best=ask;; allow) [ "$best" = none ] && best=allow;; esac
  done
  echo "$best"
}
dsp() { # dsp <project dir> <event> <payload> [trust] → DO (stdout), DR (rc). Run FROM that dir: the
  # project test also reads the cwd (a task worktree names its primary), so the golden's own cwd must not leak in.
  DO="$(cd "$T/$1" && printf '%s' "$3" | CLAUDE_PROJECT_DIR="$T/$1" DP_TRUST="${4:-}" bash "$DP" "$2" 2>/dev/null)"; DR=$?
}
mx() { # mx <label> <project dir> <payload> [trust]
  dsp "$2" PreToolUse "$3" "${4:-}"
  printf '%-44s dispatcher=%-10s separate=%s\n' "$1" "$(word "$DR" "$DO")" "$(solo "$3" "${4:-$HK/readonly-allow.sh}")"
}
echo '== (b) merge: the dispatcher vs the separate scripts (deny > ask > allow) =='
mx 'presence deny (away, the question tool)' mp "$(pj aw mp AskUserQuestion)"
mx 'presence away + read-only allow' mp "$(pj aw mp Bash 'git status')"
mx 'checkout deny + allow (trust tier allows all)' mp "$(pj op mp Bash 'git switch main')" "$T/allow-all.sh"
mx 'checkout deny alone' mp "$(pj op mp Bash 'git switch main')"
mx 'model deny + read-only allow' mp "$(pj hk mp Bash 'git status')"
mx 'read-only allow' mp "$(pj op mp Bash 'git status')"
mx 'genuine launcher + ops/polaris allow' mp "$(pj op mp Bash 'bash ops/polaris find x')"
mx 'not-genuine launcher + ops/polaris allow' fake "$(pj op fake Bash 'bash ops/polaris find x')"
mx 'not-genuine launcher + other allow' fake "$(pj op fake Bash 'git log -1')"
mx 'not-genuine launcher + mixed allow' fake "$(pj op fake Bash 'git log -1 && bash ops/polaris status')"
mx 'nothing' mp "$(pj op mp Bash 'rm x')"
mx 'trust tier consulted (allows rm)' mp "$(pj op mp Bash 'rm x')" "$T/allow-all.sh"
mx 'trust tier missing: the kit copy' mp "$(pj op mp Bash 'rm x')" "$T/no-such-trust.sh"
# A `cd` moves where a relative `bash ops/polaris` lands: every target's copy must be genuine too (§ 5).
mx 'cd into a nested fake launcher' mp "$(pj op mp Bash 'cd sub && bash ops/polaris find x')"
mx 'subshell cd into a nested fake launcher' mp "$(pj op mp Bash '(cd sub && bash ops/polaris status)')"
mx 'pushd into a nested fake launcher' mp "$(pj op mp Bash 'pushd sub && bash ops/polaris status')"
mx 'second line cd into a nested fake' mp "$(pj op mp Bash 'git log -1\ncd sub && bash ops/polaris find x')"
mx 'cd then cd into a nested fake' mp "$(pj op mp Bash 'cd plain && cd ../sub && bash ops/polaris find x')"
mx 'cd into a nested genuine launcher' mp "$(pj op mp Bash 'cd gsub && bash ops/polaris find x')"
mx 'cd into a dir with no launcher' mp "$(pj op mp Bash 'cd plain && bash ops/polaris find x')"
mx 'cd target unresolvable (quoted)' mp "$(pj op mp Bash 'cd \"gsub\" && bash ops/polaris find x')"
mx 'cd target unresolvable (dash)' mp "$(pj op mp Bash 'cd - && bash ops/polaris find x')"
mx 'bare cd' mp "$(pj op mp Bash 'cd && bash ops/polaris find x')"
mx 'cd into a nested fake + other allow' mp "$(pj op mp Bash 'cd sub && git log -1')"
dsp fake PreToolUse "$(pj op fake Bash 'bash ops/polaris find x')"
r="${DO#*permissionDecisionReason\":\"}"; echo "ask reason: ${r%%\"*}"
# model-guard's pending effort note rides INSIDE the one verdict object (two objects would not parse)
mkdir -p "$ST/op.over"; printf '%s\n' "pin9 xhigh medium" > "$ST/op.over/.pending"; printf 'medium\n' > "$ST/op.effort"
dsp mp PreToolUse "$(pj op mp Bash 'git status')"
printf 'note + allow: %s · objects: %s\n' "$(word "$DR" "$DO")" \
  "$(printf '%s' "$DO" | python -c 'import json,sys; d=json.loads(sys.stdin.read()); h=d["hookSpecificOutput"]; print("1, decision %s, context %s" % (h.get("permissionDecision"), "yes" if h.get("additionalContext") else "no"))' 2>&1 | tr -d '\r')"
sm() { # sm <label> <event> <payload> <the separate hook commands, ;-joined> — same bytes and rc?
  dsp mp "$2" "$3"; a="$DO|$DR"
  b="$(cd "$T/mp" && printf '%s' "$3" | CLAUDE_PROJECT_DIR="$T/mp" bash -c "$4" 2>/dev/null)|$?"
  [ "$a" = "$b" ] && echo "$1: same" || printf '%s: DIFFERS\n  dispatcher %s\n  separate   %s\n' "$1" "$a" "$b"
}
EJ="$(printf '{"session_id":"op","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/a.txt","old_string":"a","new_string":"b"}}' "$T/mp" "$T/mp")"
sm 'Edit → ownership-guard' PreToolUse "$EJ" "bash $HK/ownership-guard.sh"
XJ="$(printf '{"session_id":"aw","permission_mode":"auto","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"ExitPlanMode","tool_input":{}}' "$T/mp")"
sm 'PostToolUse ExitPlanMode → presence' PostToolUse "$XJ" "bash $HK/presence-guard.sh"
UJ="$(printf '{"session_id":"op","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"hi"}' "$T/mp")"
sm 'UserPromptSubmit → handover prompt, presence' UserPromptSubmit "$UJ" "IN=\$(cat); printf '%s' \"\$IN\" | bash $HK/handover-hook.sh prompt; printf '%s' \"\$IN\" | bash $HK/presence-guard.sh"
SJ="$(printf '{"session_id":"op","hook_event_name":"Stop","cwd":"%s","stop_hook_active":false}' "$T/mp")"
sm 'Stop → handover stop' Stop "$SJ" "bash $HK/handover-hook.sh stop"
sm 'SubagentStop → handover substop' SubagentStop "$SJ" "bash $HK/handover-hook.sh substop"
PJ="$(printf '{"session_id":"aw","permission_mode":"auto","hook_event_name":"PermissionRequest","cwd":"%s","tool_name":"Bash","tool_input":{"command":"rm x"}}' "$T/mp")"
sm 'PermissionRequest → permission-hook request' PermissionRequest "$PJ" "bash $HK/permission-hook.sh request"
sm 'PermissionDenied → permission-hook denied' PermissionDenied "$PJ" "bash $HK/permission-hook.sh denied"
dsp mp PreModelSwitch '{"session_id":"op","hook_event_name":"PreModelSwitch","to_model":"claude-haiku-4-5"}'
echo "PreModelSwitch to Haiku: $(word "$DR" "$DO")"
dsp mp Bogus '{}'; echo "an unknown event: $(word "$DR" "$DO") rc $DR"

echo '== (c) stand-down: vendored and non-POLARIS dirs → model-guard only =='
for d in vend none; do
  for c in "op Bash git switch main" "op AskUserQuestion" "aw AskUserQuestion" "hk Read" "op Read"; do
    set -- $c; s="$1" t="$2"; shift 2
    dsp "$d" PreToolUse "$(pj "$s" "$d" "$t" "$*")"
    printf '%-5s %-28s %s\n' "$d" "$s $t $*" "$(word "$DR" "$DO")"
  done
  for e in Stop PermissionRequest UserPromptSubmit; do dsp "$d" "$e" "$PJ"; printf '%-5s %-28s %s\n' "$d" "$e" "$(word "$DR" "$DO")"; done
  dsp "$d" PreToolUse "$EJ"; printf '%-5s %-28s %s rc %s\n' "$d" 'Edit' "$(word "$DR" "$DO")" "$DR"
done

echo '== (d) name hygiene =='
for g in model-guard presence-guard checkout-guard readonly-allow; do bash -c ". $HK/$g.sh; declare -F" < /dev/null; done \
  | sed 's/^declare -f //' | LC_ALL=C sort > "$T/fns"
echo "functions defined by the four guards: $(grep -c . "$T/fns") · duplicates: $(uniq -d "$T/fns" | grep -c .)"
bash -c ". $HK/model-guard.sh; . $HK/presence-guard.sh; . $HK/checkout-guard.sh; . $HK/readonly-allow.sh; declare -F" < /dev/null \
  | sed 's/^declare -f //' | LC_ALL=C sort > "$T/one"
cmp -s "$T/fns" "$T/one" && echo "sourced into one shell: the same set" || echo "sourced into one shell: DIFFERENT"
grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$DP" | tr -d '()' | LC_ALL=C sort > "$T/dpf"
echo "dispatcher functions: $(grep -c . "$T/dpf") · not _dp_*: $(grep -vc '^_dp_' "$T/dpf") · shared with a guard: $(LC_ALL=C comm -12 "$T/dpf" "$T/fns" | grep -c .)"

echo '== (e) SessionStart =='
K="$T/kit/ops/hooks"; mkdir -p "$K"; cp "$DP" "$HK/model-guard.sh" "$K/"
SS="$(printf '{"session_id":"ss","hook_event_name":"SessionStart","source":"startup","model":"claude-opus-5-5","cwd":"%s"}' "$T/mp")"
o="$(cd "$T/mp" && printf '%s' "$SS" | CLAUDE_PROJECT_DIR="$T/mp" bash "$K/dispatch.sh" SessionStart)"; r=$?
echo "no dispatch-session.sh: [${o}] rc $r · model recorded: $(cat "$ST/ss" 2>/dev/null)"
# T-346's interface: _ds_session <machine|plain|vendored|auto> <dir> <model-guard text>; it sets HOUT.
printf '%s\n' '_ds_session() { printf -v HOUT "session: %s %s [%s] seed-rc=%s\n" "$1" "${2##*/}" "$3" "$HRC"; }' > "$K/dispatch-session.sh"
for d in mp vend none; do
  ( cd "$T/$d" && printf '%s' "$SS" | CLAUDE_PROJECT_DIR="$T/$d" bash "$K/dispatch.sh" SessionStart ); echo "  ($d) rc $?"
done
printf 'syntax ((( error\n' > "$K/dispatch-session.sh"
o="$(cd "$T/mp" && printf '%s' "$SS" | CLAUDE_PROJECT_DIR="$T/mp" bash "$K/dispatch.sh" SessionStart 2>/dev/null)"; echo "a broken dispatch-session.sh: [${o}] rc $?"
