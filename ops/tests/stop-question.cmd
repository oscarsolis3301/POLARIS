# T-230: a closing "?" is bounced ONCE while `next` names work (build|integrate|promote), passes on
# the second attempt (stop_hook_active), and stays allowed when next says finish|wait|stop.
KIT="$(pwd)/kit/ops/polaris"
HOOK="$(pwd)/kit/ops/hooks/handover-hook.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  printf "# fixture contract\n" > ops/contracts/fix.md
) >/dev/null 2>&1
P="$FIX/repo"; D="$P/.polaris/handover/sq-sid"; TR="$FIX/tr/session.jsonl"
mkdir -p "$D" "$FIX/tr"
export CLAUDE_CODE_SESSION_ID=sq-sid
printf "handover: auto\nrun_max_tasks: %s\n" "${CAP:-0}" > "$P/ops/CONVENTIONS.md"
printf "%s\n" "100 done T-SQ1" > "$D/last-event"
tr_text() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TR"; }
J="{\"session_id\":\"sq-sid\",\"transcript_path\":\"$TR\",\"cwd\":\"$P\",\"stop_hook_active\":false,\"hook_event_name\":\"Stop\"}"
JT="{\"session_id\":\"sq-sid\",\"transcript_path\":\"$TR\",\"cwd\":\"$P\",\"stop_hook_active\":true,\"hook_event_name\":\"Stop\"}"
rail() { rm -f "$D/hops" "$D/hopped-event"; printf "%s" "$J" | POLARIS_HANDOVER_NEXT="$1" bash "$HOOK" --test stop; }

tr_text "continue?"
rail "build T-SQ1"
rail "integrate"
rail "promote"
rail "finish"
rail "wait"
rail "stop"
rm -f "$D/hops" "$D/hopped-event"
printf '%s' "$JT" | POLARIS_HANDOVER_NEXT="build T-SQ1" bash "$HOOK" --test stop
tr_text "done"
rail "build T-SQ1"
