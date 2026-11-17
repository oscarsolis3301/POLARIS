# speed-plan — T-302 (ops/contracts/hour.md § 5): `polaris speed --plan <slug> [<draft.md>…]` prices a
# plan. Cards = board tasks carrying `plan: <slug>` outside done/, plus every draft named; W = the longest
# depends_on chain inside that set; L = the `lanes:` answer of § 4 (else min(C, 5)), capped at C; B and D
# = this project's medians from EVENTS (else 30 + 15); minutes = max(W, ceil(C / L)) x (B + D) against
# target_minutes (default 60, non-numeric → 60). Read-only: no git walk, repo byte-identical after.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  printf '.polaris/\n' > .gitignore; echo v1 > a.dat
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  card() { # card <column> <id> <plan> <depends_on>
    printf -- '---\nid: %s\ntitle: "card %s"\nplan: %s   # the slug\npoints: 2\ndepends_on: %s\n---\n## Why\nfixture\n' \
      "$2" "$2" "$3" "$4" > "ops/board/$1/$2.md"
  }
  # plan hour: a 3-link chain T-1 ← T-2 ← T-3 (T-3 in the block-list form), three loose cards, one of
  # them waiting on a done/ card (adds 0). T-9 (plan other) and T-10 (done/) are not cards of hour.
  card review  T-1 hour '[T-10]'
  card active  T-2 hour '[T-1]'
  printf -- '---\nid: T-3\nplan: "hour"\ndepends_on:\n  - T-2\n  - T-10\n---\n' > ops/board/backlog/T-3.md
  card ready   T-4 hour '[]'
  card blocked T-5 hour '[T-10, T-9]'
  card backlog T-6 hour '[]'
  card ready   T-9 other '[]'
  card done    T-10 hour '[]'
  card ready   T-11 solo '[]'
  # EVENTS: three solo builds of 10 min, then three pairs built side by side (2 lanes) of 15 min; every
  # card waits 5 min to land. 1 lane: 6.0 cards an hour; 2 lanes: 8.0 → lanes: 2, B = 15, D = 5.
  awk 'BEGIN { t = 100000
    for (i = 1; i <= 3; i++) { printf "{\"ts\":%d,\"ev\":\"claim\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"handoff\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"done\",\"id\":\"E-%d\"}\n", t, i, t + 600, i, t + 900, i; t += 3600 }
    for (i = 4; i <= 9; i += 2) { for (k = 0; k < 2; k++) printf "{\"ts\":%d,\"ev\":\"claim\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"handoff\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"done\",\"id\":\"E-%d\"}\n", t + k * 30, i + k, t + k * 30 + 900, i + k, t + k * 30 + 1200, i + k; t += 3600 }
  }' > ops/board/EVENTS.ndjson
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
snap() { { git status --porcelain; git rev-parse HEAD; find . -path ./.git -prune -o -type f -print | sort | xargs cksum 2>/dev/null; } | cksum; }
BEFORE="$(snap)"
echo "lanes-from-the-log:"; bash "$KIT" speed 2>&1 | grep -e '^build by lanes' -e '^lanes:'
echo "plan:"; bash "$KIT" speed --plan hour 2>&1; echo "  rc=$?"
echo "capped-at-cards:"; bash "$KIT" speed --plan solo 2>&1; echo "  rc=$?"
printf -- '---\nid: T-12\nplan: elsewhere\ndepends_on: [T-3]\n---\n' > "$FIX/d1.md"
printf -- '---\nid: T-13\ndepends_on:\n  - T-12\n---\n' > "$FIX/d2.md"
echo "drafts:"; bash "$KIT" speed --plan hour "$FIX/d1.md" "$FIX/d2.md" 2>&1; echo "  rc=$?"
echo "unknown-slug:"; bash "$KIT" speed --plan nope 2>&1; echo "  rc=$?"
[ "$BEFORE" = "$(snap)" ] && echo "read-only: repo byte-identical after" || echo "read-only: REPO CHANGED"
printf 'target_minutes: 10\n' >> ops/CONVENTIONS.md
echo "over-target:"; bash "$KIT" speed --plan hour 2>&1; echo "  rc=$?"
sed -i 's/^target_minutes: 10$/target_minutes: soon/' ops/CONVENTIONS.md
echo "non-numeric-target:"; bash "$KIT" speed --plan hour 2>&1 | sed -n 3p
mv ops/board/EVENTS.ndjson "$FIX/events.bak"
echo "no-history:"; bash "$KIT" speed --plan hour 2>&1; echo "  rc=$?"
mv "$FIX/events.bak" ops/board/EVENTS.ndjson
