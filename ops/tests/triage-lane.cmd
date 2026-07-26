# `triage` is now the ROUTER: CLAUDE.md sends every `start` and every unprompted work request
# through it and takes line 1 as the lane. That makes its output load-bearing in a way it was not
# when it was advisory — a crash, an extra line, or a changed first word silently misroutes every
# session in the repo. Nothing tested it before 5.21.0.
#
# ONE invocation, reused. The first draft called `polaris triage` three times and `help` once:
# ~2.8s of startup to assert four things about the same output. Shipping that inside a release
# about not wasting calls would have been its own counter-example.
OUT="$(bash kit/ops/polaris triage 2>&1)"
# Line 1 must be EXACTLY one bare word, always — reasons go on `   ` note lines below it, so a
# caller can branch on line 1 without parsing.
printf '%s\n' "$OUT" | sed -n '1p'
printf '%s\n' "$OUT" | sed -n '1p' | grep -cE '^(solo|express|full)$'
printf '%s\n' "$OUT" | sed -n '2,$p' | grep -c '^   '
# The SOLO envelope. 5.21.0 widened it 2 -> 3 points because the gates were never the expense, the
# CONTEXTS were: a 3-point task in `express` opens three cold starts to land work one context
# finishes. This asserts the threshold ITSELF, not the help text — a revert to 2 reds here.
grep -c 'pts" -le 3 \]' kit/ops/lib/observe.sh
# ...and the help text must agree with it. cli-docs-parity: one fact, one home — a threshold that
# disagrees with its own documentation is how an agent talks itself back into the wrong lane.
bash kit/ops/polaris help | grep -c '1 task ≤3pts'
