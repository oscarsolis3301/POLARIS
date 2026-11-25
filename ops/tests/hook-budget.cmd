# hook-budget — the one hook costs one process (ops/contracts/hook-dispatch.md § 4, § 7). Every call
# goes through the setup-installed shim (kit/ops/hooks/shim.sh, copied as <POLARIS_HOME>/hook) into the
# store's dispatch.sh. With PATH set to an EMPTY directory the verdict must not change: proof that the
# stand-down path and a machine project's unguarded tools start no external command. Then a scoped
# grep: no `$(`, backtick or pipe on the shim or between dispatch.sh's HOT PATH markers.
# HERMETIC: fake HOME / USERPROFILE / CLAUDE_CONFIG_DIR / POLARIS_AWAKE_HOME under one mktemp -d;
# POLARIS_PREFS= ; CLAUDECODE set; no path, time or pid is printed.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" USERPROFILE="$T/home" POLARIS_AWAKE_HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude"
export POLARIS_PREFS= CLAUDECODE=1 PYTHONIOENCODING=utf-8
unset DP_TRUST CLAUDE_EFFORT
PH="$T/ph"; mkdir -p "$PH/kit/7.0.0/ops" "$T/empty" "$T/mp/ops" "$T/vend/ops/lib" "$T/none"
cp kit/ops/hooks/shim.sh "$PH/hook"; cp -R kit/ops/hooks "$PH/kit/7.0.0/ops/"; cp kit/ops/launcher "$PH/kit/7.0.0/ops/"
cp kit/ops/launcher "$T/mp/ops/polaris"; cp kit/ops/launcher "$T/vend/ops/polaris"
ST="$CLAUDE_CONFIG_DIR/polaris/model-state"; mkdir -p "$ST"
printf 'claude-opus-5-5\n' > "$ST/op"; printf 'claude-haiku-4-5\n' > "$ST/hk"
SH="$BASH"                                        # by path: an empty PATH cannot find bash
pj() { # pj <sid> <dir> <tool> [command]
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":{"command":"%s"}}' "$1" "$T/$2" "$3" "${4:-}"
}
run() { # run <dir> <PATH> <event> <payload> → "<stdout>|<stderr>|<rc>"
  ( cd "$T/$1" && printf '%s' "$4" > "$T/in" && PATH="$2" CLAUDE_PROJECT_DIR="$T/$1" "$SH" "$PH/hook" "$3" < "$T/in" > "$T/o" 2> "$T/e"; echo "$?" > "$T/rc" )
  R="$(cat "$T/o")|$(cat "$T/e")|$(cat "$T/rc")"
}
word() {
  case "$R" in
    *'|2') echo deny-exit2;; *'"permissionDecision":"deny"'*) echo deny;; *'"permissionDecision":"allow"'*) echo allow;;
    '||0') echo none;; *) echo other;;
  esac
}
bc() { # bc <label> <dir> <payload>
  run "$2" "$PATH" PreToolUse "$3"; a="$R"; w="$(word)"
  run "$2" "$T/empty" PreToolUse "$3"
  [ "$a" = "$R" ] && s=yes || s=NO
  printf '%-34s %-11s empty PATH same: %s\n' "$1" "$w" "$s"
}
printf '7.0.0\n' > "$PH/kit/current"
echo '== through the shim: real PATH vs an empty one =='
bc 'non-POLARIS dir, Read' none "$(pj op none Read)"
bc 'non-POLARIS dir, Bash' none "$(pj op none Bash 'git status')"
bc 'non-POLARIS dir, Haiku session' none "$(pj hk none Read)"
bc 'vendored dir, Bash' vend "$(pj op vend Bash 'git switch main')"
bc 'vendored dir, Haiku session' vend "$(pj hk vend Bash 'git status')"
bc 'machine project, Read' mp "$(pj op mp Read)"
bc 'machine project, Grep' mp "$(pj op mp Grep)"
bc 'machine project, Haiku Grep' mp "$(pj hk mp Grep)"
run none "$T/empty" Stop '{}'; echo "non-POLARIS dir, Stop: $(word)"
echo '== the shim reads kit/current: a usable kit answers (a Haiku session: deny), anything else is silent =='
run mp "$T/empty" PreToolUse "$(pj hk mp Read)"; echo "current [7.0.0]: $(word)"
for v in '' '7.0' '7.0.0.1' '../7.0.0' '9.9.9'; do
  printf '%s\n' "$v" > "$PH/kit/current"; run mp "$T/empty" PreToolUse "$(pj hk mp Read)"; echo "current [$v]: $(word)"
done
rm -f "$PH/kit/current"; run mp "$T/empty" PreToolUse "$(pj hk mp Read)"; echo "no current: $(word)"
printf '7.0.0\r\n' > "$PH/kit/current"; run mp "$T/empty" PreToolUse "$(pj hk mp Read)"; echo "current with CRLF: $(word)"
echo '== no fork on that path: the shim and the HOT PATH regions of dispatch.sh =='
{ sed -n '/^# >>> HOT PATH/,/^# <<< HOT PATH/p' kit/ops/hooks/dispatch.sh; cat kit/ops/hooks/shim.sh; } \
  | grep -v '^[[:space:]]*#' > "$T/hot"
echo "hot path regions: $(grep -c '^# >>> HOT PATH' kit/ops/hooks/dispatch.sh) · lines with \$( or a backtick or a pipe: $(grep -cE '\$\(|`|\|' "$T/hot")"
echo "shim lines: $(wc -l < kit/ops/hooks/shim.sh | tr -d ' ') (≤ 30: $( [ "$(wc -l < kit/ops/hooks/shim.sh)" -le 30 ] && echo yes || echo NO))"
