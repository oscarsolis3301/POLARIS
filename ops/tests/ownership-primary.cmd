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
# T-174 (ops/contracts/speed.md § 1) — the fast path. Shape: ONE rev-parse answers toplevel, common
# dir and branch; the RULES prefilter uses the lib's own match_one; a non-Builder write no rule
# scopes exits before the CLI starts.
printf 'one-rev-parse: %s\n' "$(grep -cF 'git -C "$CWD" rev-parse --show-toplevel --git-common-dir --abbrev-ref HEAD' "$H")"
printf 'prefilter-matcher: %s\n' "$(grep -cF 'match_one "$REL" "$R_SCOPE"' "$H")"
printf 'fast-exit: %s\n' "$(grep -cF '[ "$ID" = "-" ] && [ "$HIT" -eq 0 ] && exit 0' "$H")"
# Behavior, hermetically: a throwaway repo whose ops/polaris is a STUB that logs each call and its
# payload, then allows. Verdicts are guard-denies' job; this pins WHICH writes still reach `_guard`
# and with what payload, plus how many git processes each route starts (a git shim counts them).
# Every rule kind must reach the CLI, and so must a feat/* branch; only a content rule with a
# pattern carries the payload; a write no rule scopes must not start the CLI; and with the lib's
# matcher gone nothing may skip it. `\u` is the one escape jstr refuses: python decodes it.
HK="$PWD/$H"; F="$(mktemp -d)"; R="$F/r"; REALGIT="$(command -v git)"
git init -q "$R"; mkdir -p "$R/ops/lib" "$R/src" "$F/bin"
cp kit/ops/lib/core.sh kit/ops/lib/ownership.sh "$R/ops/lib/"
printf 'secret/\tpath\t-\tno secrets\ngated/\task\t-\ta human decides\nsrc/*.cfg\tcontent\t^bad\tno bad lines\ndocs/\tcontent\t-\tno pattern, no payload\n' > "$R/ops/RULES.tsv"
printf '#!/usr/bin/env bash\nb=""; [ -n "${4:-}" ] && [ -f "$4" ] && b="$(tr -d "\\r" < "$4" | tr "\\n" "|")"\nprintf "%%s %%s %%s body=[%%s]\\n" "$1" "$2" "$3" "$b" >> "$STUB_LOG"\n' > "$R/ops/polaris"
printf '#!/usr/bin/env bash\necho x >> "$GIT_COUNT"\nexec "%s" "$@"\n' "$REALGIT" > "$F/bin/git"
chmod +x "$R/ops/polaris" "$F/bin/git"
echo x > "$R/src/a.txt"; git -C "$R" -c core.autocrlf=false add -A; git -C "$R" -c user.email=t@t -c user.name=t commit -qm init
RT="$(git -C "$R" rev-parse --show-toplevel)"
og() { # og <label> <tool> <repo-relative path> <payload key> <payload JSON string>
  : > "$F/calls"; : > "$F/gits"
  ( cd "$R" && printf '{"cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s/%s","%s":"%s"}}' "$RT" "$2" "$RT" "$3" "$4" "$5" \
      | PATH="$F/bin:$PATH" STUB_LOG="$F/calls" GIT_COUNT="$F/gits" bash "$HK" >/dev/null 2>&1 ); rc=$?
  c="$(cat "$F/calls")"; printf '%s: rc=%s git=%s %s\n' "$1" "$rc" "$(grep -c x "$F/gits")" "${c:-no-cli}"
}
og plain Edit src/a.txt new_string 'ok'
og path-rule Edit secret/k.txt new_string 'ok'
og ask-rule Edit gated/g.txt new_string 'ok'
og content-rule Edit src/x.cfg new_string 'bad\nline'
og content-rule-write Write src/x.cfg content 'fine'
og content-no-pattern Edit docs/d.md new_string 'bad'
og content-unicode Write src/x.cfg content "$(printf '\134u0062ad')"   # \134 = backslash
git -C "$R" checkout -q -b feat/T-9
og feat-branch Edit src/a.txt new_string 'ok'
git -C "$R" checkout -q -
rm "$R/ops/lib/ownership.sh"
og no-matcher Edit src/a.txt new_string 'ok'
rm -rf "$F"
