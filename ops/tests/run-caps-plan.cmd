# T-230: run caps count only work OUTSIDE the recorded plan (.polaris/handover/<sid>/plan).
# Hook side: a cap already reached still lets plan work through, and still stops foreign work.
# Router side: `next` names build for a plan task past the cap, and stop for a foreign one.
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

printf "handover: auto
run_max_tasks: 1
" > "$P/ops/CONVENTIONS.md"
printf "%s\n" "compat-plan" > "$D/plan"
printf "%s\n" 1 > "$D/hops"
tr_text "done"
mk() { printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nplan: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' "$1" "$1" "$2" > "$P/ops/board/ready/$1.md"; }
capcase() { rm -f "$D/hopped-event"; printf '%s\n' 1 > "$D/hops"; printf "%s" "$J" | POLARIS_HANDOVER_NEXT="build $1" bash "$HOOK" --test stop; printf 'hops=%s\n' "$(cat "$D/hops")"; }
printf "%s\n" "plan" > "$D/plan"
mk T-SQ1 plan
mk T-SQ2 other
capcase T-SQ1
capcase T-SQ2
# router: past the cap, plan work still builds, foreign work stops
cd "$P"
git add -A >/dev/null 2>&1; git commit -qm fx >/dev/null 2>&1
rm -f ops/board/ready/T-SQ2.md
bash "$KIT" next 2>&1 | sed -n 1p
printf "drain: queue
" >> "$P/ops/CONVENTIONS.md"; mk T-SQ2 other; rm -f ops/board/ready/T-SQ1.md
bash "$KIT" next 2>&1 | sed -n 1p
