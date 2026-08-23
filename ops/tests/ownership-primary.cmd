# ownership-guard's primary gate (shared-checkout.md v2 §2): builders never edit the shared
# primary while a task lock is live. The gate needs a live repo, a lock and a tracked path to
# fire, so its BEHAVIOR is drilled (doctor --selftest --only checkoutguard); this golden locks the
# SHAPE hermetically — the pinned one-line refusal, the fn the api-kit surface pins, and the deny
# mechanism: exit 2 + stderr, deliberately NOT checkout-guard's JSON-on-stdout. The two hooks deny
# by different mechanisms and BOTH are correct as shipped (v2.1) — a golden asserting a shared
# shape would fail against correct behavior, so each hook's golden asserts its own.
H=kit/ops/hooks/ownership-guard.sh
printf 'pinned-refusal-lines: %s\n' "$(grep -c 'builders never edit the shared primary — claim a task and work in its worktree: bash ops/polaris claim, then cd .polaris/wt/<ID>' "$H")"
printf 'primary-gate-fn: %s\n' "$(grep -c '^primary_gate()' "$H")"
printf 'primary-gate-exit2: %s\n' "$(grep -c 'primary_gate || exit 2' "$H")"
printf 'json-deny-in-this-hook: %s\n' "$(grep -c 'hookSpecificOutput' "$H")"
