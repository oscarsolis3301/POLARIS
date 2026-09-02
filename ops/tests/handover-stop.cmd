# kit/ops/hooks/handover-hook.sh `stop` is the BACKSTOP (ops/contracts/role-handover.md): the loop
# itself lives in role prose, and this fires only for a model that completed a board task and
# stopped anyway. It is the one piece of POLARIS that can trap a chat: a rung that blocks where it
# should allow leaves the human staring at a session that will not end, and a rung that allows where
# it should block silently drops the hop. So every rung of the ladder is pinned here BY ITS WORD, in
# order, in both directions — each case clears the trigger above it, so the word that follows is the
# proof that the rung it just proved has released.
#
# `--test` prints the rung word instead of the output layer and performs the SAME state writes, so
# `hops` is assertable after a block. POLARIS_HANDOVER_NEXT replaces the `next` call for the rail
# cases (the verb ladder is a pure mapping and deserves no CLI startup); POLARIS_HANDOVER_CLI points
# the ONE un-stubbed case at the kit CLI, because the INSTALLED ops/polaris has no `next` until
# 6.2.0 is dogfooded. The fixture repo IS the primary — hh_primary calls any dir with an ops/board a
# primary, which is exactly what lets a mktemp dir stand in for one here.
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
  printf '# fixture contract\n' > ops/contracts/fix.md
) >/dev/null 2>&1
P="$FIX/repo"; D="$P/.polaris/handover/hs-sid"; TR="$FIX/tr/session.jsonl"
mkdir -p "$D" "$FIX/tr"
export CLAUDE_CODE_SESSION_ID=hs-sid
conv() { # conv <handover> <run_max_tasks> — the two keys the ladder reads. init-board writes no
  # CONVENTIONS.md (cfg's defaults carry a fresh board), so this file is entirely ours and hh_cfg's
  # first-match-wins sed has exactly one candidate per key.
  printf 'handover: %s\nrun_max_tasks: %s\n' "$1" "$2" > "$P/ops/CONVENTIONS.md"
}
say_ev() { printf '%s\n' "$1" > "$D/last-event"; }
tr_text() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TR"; }
J="{\"session_id\":\"hs-sid\",\"transcript_path\":\"$TR\",\"cwd\":\"$P\",\"stop_hook_active\":false,\"hook_event_name\":\"Stop\"}"
JT="{\"session_id\":\"hs-sid\",\"transcript_path\":\"$TR\",\"cwd\":\"$P\",\"stop_hook_active\":true,\"hook_event_name\":\"Stop\"}"
hook() { printf '%s' "$J" | bash "$HOOK" --test stop; }
conv auto 0
tr_text "done"
# --- rung 1: ordinary Q&A never wrote a board event, so the ladder ends on pure builtins — no fork,
#     no interpreter, no ops/polaris. This is the rung that pays for all the others. -------------
hook
# --- rung 2: `handover: off` allows BEFORE any fork. The knob is the whole opt-out. ------------
say_ev "100 handoff T-HS1"
conv off 0
hook
# --- rung 3: only a COMPLETION licenses a hop — a claim is not one. ---------------------------
conv auto 0
say_ev "100 claim T-HS1"
hook
# --- rung 4: one event, one hop — by STRING EQUALITY of last-event and hopped-event, never a
#     timestamp comparison, so a clock that moves backwards can never buy a second hop. ---------
say_ev "100 done T-HS1"
# last-event is backdated ONCE here and never rewritten again, so the two mtime rungs below — a
# `finished` stamp newer than the event, a subagent transcript newer than the event — are decided by
# an ordering this file states outright instead of by a sleep racing the filesystem clock.
touch -t 202001010000 "$D/last-event"
printf '100 done T-HS1\n' > "$D/hopped-event"
hook
# --- rung 5: `finish` already ran and stamped the run closed; nothing left to hop into. --------
rm -f "$D/hopped-event"
: > "$D/finished"
hook
# --- rung 6: the harness itself has had enough consecutive blocks. Its cap outranks ours. ------
rm -f "$D/finished"
printf '%s' "$JT" | bash "$HOOK" --test stop
# --- rung 7: our own budget. run_max_tasks reached ⇒ allow, so a run ends where the human said. -
conv auto 2
printf '2\n' > "$D/hops"
hook
# --- rung 8: a subagent's completion lands in the PARENT's state dir, so without this rung a
#     conductor whose builders just handed off would be hopped into BUILDER itself. ------------
printf '1\n' > "$D/hops"
mkdir -p "$FIX/tr/hs-sid/subagents"; : > "$FIX/tr/hs-sid/subagents/x.jsonl"
hook
# --- rung 9: the session stopped to ASK. Hopping over a question is how a chat loses the answer. -
rm -rf "$FIX/tr/hs-sid"
tr_text "which one?"
hook
# --- rung 10: an own landing tail still running blocks to COLLECT it — and consumes nothing, so
#     the event is still there to license the real hop once the tail is in. --------------------
tr_text "done"
rm -f "$D/hops" "$D/hopped-event"
mkdir -p "$P/.polaris/bg/ship-T-HS1"; printf '%s\n' "$P" > "$P/.polaris/bg/ship-T-HS1/cwd"
hook
printf 'hops-after-collect: %s\n' "$(cat "$D/hops" 2>/dev/null || echo none)"
rm -rf "$P/.polaris/bg"
# --- the rails: line 1 of `next` maps to exactly one word, and the four blocking verbs are the
#     only four. An unknown first word is the fail-OPEN default — a router this hook cannot read
#     must never be able to trap the session. ------------------------------------------------
rail() { rm -f "$D/hops" "$D/hopped-event"
  printf '%s' "$J" | POLARIS_HANDOVER_NEXT="$1" bash "$HOOK" --test stop
}
rail "build T-HS1"
rail "integrate"
rail "promote"
rail "finish"
rail "wait"
rail "stop"
rail "resume T-HS1"
rail "banana"
# --- the writes land BEFORE the emit, so one event still buys exactly one hop even on a crash —
#     and re-running the same rail immediately falls to `allow:consumed`. --------------------
rail "finish"
printf 'hops-after-block: %s\n' "$(cat "$D/hops")"
printf 'hopped-event-matches-last: %s\n' "$(cmp -s "$D/hopped-event" "$D/last-event" && echo yes || echo no)"
hook
# --- ONE un-stubbed case: the hook really runs the router against the real board, and the verb it
#     reads back off disk is the verb it blocks with. ---------------------------------------
rm -f "$D/hops" "$D/hopped-event"
printf -- '---\nid: T-HS1\ntitle: fixture T-HS1\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' > "$P/ops/board/ready/T-HS1.md"
printf '%s' "$J" | POLARIS_HANDOVER_CLI="$KIT" bash "$HOOK" --test stop
# --- and ONE raw invocation, no --test: the shipped block shape, verbatim. A top-level `decision`
#     with a `reason` is what the harness reads for a Stop hook; stdout that does not start with `{`
#     is treated as plain text and the decision is silently dropped, so this is load-bearing bytes.
#     `finish` is the reason template that carries no machine-specific path. ------------------
rm -f "$D/hops" "$D/hopped-event"
printf '%s' "$J" | POLARIS_HANDOVER_NEXT=finish bash "$HOOK" stop
# --- the reason templates are pinned prose (contract § Reason templates). Counting the BUILDER one
#     catches a second copy drifting in beside the first — two templates, two behaviours. -------
printf 'pinned-reason-lines: %s\n' "$(grep -c 'You are a BUILDER (hop' "$HOOK")"
