# tune-report — T-308 (ops/contracts/tune.md § 1-2, § 5): `polaris tune` prints one line per thing that
# slows the project, each followed by its `   fix:` line(s), in the contract's order; rc 0 prints the one
# nothing-to-do line, rc 1 the findings, rc 2 a usage error that writes nothing. Every rc 0/1 run writes
# .polaris/tune-due as ONE LF line `<base-sha> TAB <0|1> TAB <n> TAB <kinds>` (compared with cmp, never
# printed: a sha). It never edits ops/CONVENTIONS.md, ops/RULES.tsv or anything under the home folder.
# Case 1 is the contract's fixture: a 3-card depends_on chain in one plan, a due hops-due, and
# `integration: paranoid` with a 300 s last suite → exactly cards / layout / landing. Case 2 reads the
# settings kinds (lanes from EVENTS, checks, behind from a cached channel answer) and the § 5 reasons;
# case 5 folds the chain tune proposed and the cards: line is gone.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it, a fake HOME with no
# ~/.claude (so `context:` stays silent) and a same-day update cache (so no network is ever asked).
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID POLARIS_ROOT CLAUDE_CONFIG_DIR
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  echo v1 > a.dat; git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\ntest_fast: true\nintegration: paranoid\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  card() { # card <column> <id> <plan> <depends_on> [points]
    printf -- '---\nid: %s\ntitle: "card %s"\nplan: %s\npoints: %s\nrisk: normal\ncontract: ops/contracts/fix.md\ndepends_on: %s\nfiles_owned:\n  - src/%s.txt\n---\n## Why\nfixture %s\n' \
      "$2" "$2" "$3" "${5:-2}" "$4" "$2" "$2" > "ops/board/$1/$2.md"
  }
  card ready   T-1 tune '[]'
  card backlog T-2 tune '[T-1]'
  card backlog T-3 tune '[T-2]'
  git add -A; git commit -qm board
  mkdir -p .polaris
  printf '%s\t0\tlayout pass due — ~40%% fewer folders per change\n' "$(git rev-parse main)" > .polaris/hops-due
  printf '300 2026-01-01\n' > .polaris/last-suite-seconds
) >/dev/null 2>&1
cd "$R"
SHA="$(git rev-parse main)"
guard() { { cat ops/CONVENTIONS.md ops/RULES.tsv; find "$HOME" | sort; git status --porcelain; } | cksum; }
cache() { # cache <due> <n> <kinds> — cmp the verdict line against the one § 2 pins
  printf '%s\t%s\t%s\t%s\n' "$SHA" "$1" "$2" "$3" > "$FIX/want"
  cmp -s "$FIX/want" .polaris/tune-due && echo "  cache: $1 · $2 · $3 (matches)" || { echo "  cache: WRONG"; cat -A .polaris/tune-due; }
}
G="$(guard)"
echo "--- 1. the contract fixture"
bash "$KIT" tune 2>&1; echo "  rc=$?"
cache 0 3 cards,layout,landing
[ "$G" = "$(guard)" ] && echo "  config, rules, home and tree untouched" || echo "  SOMETHING ELSE CHANGED"
echo "--- 2. usage"
rm -f .polaris/tune-due
bash "$KIT" tune --apply 2>&1; echo "  rc=$?"
[ -e .polaris/tune-due ] && echo "  cache WRITTEN" || echo "  cache not written"
echo "--- 3. the settings kinds"
mv ops/board/ready/T-1.md ops/board/active/T-1.md
printf 'test: true\nautolaunch_max: 5\n' > ops/CONVENTIONS.md
rm -f .polaris/hops-due
printf 'version: 6.0.0\nchannel: https://example.invalid/VERSION\n' > ops/VERSION
git add ops/VERSION ops/CONVENTIONS.md; git commit -qm settings; SHA="$(git rev-parse main)"
printf 'checked: %s\nlatest: 9.9.9\n' "$(date +%Y-%m-%d)" > .polaris/update-cache
# three solo builds of 10 min, then three pairs side by side (2 lanes) of 15 min → lanes: 2 is the best
awk 'BEGIN { t = 100000
  for (i = 1; i <= 3; i++) { printf "{\"ts\":%d,\"ev\":\"claim\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"handoff\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"done\",\"id\":\"E-%d\"}\n", t, i, t + 600, i, t + 900, i; t += 3600 }
  for (i = 4; i <= 9; i += 2) { for (k = 0; k < 2; k++) printf "{\"ts\":%d,\"ev\":\"claim\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"handoff\",\"id\":\"E-%d\"}\n{\"ts\":%d,\"ev\":\"done\",\"id\":\"E-%d\"}\n", t + k * 30, i + k, t + k * 30 + 900, i + k, t + k * 30 + 1200, i + k; t += 3600 }
}' > ops/board/EVENTS.ndjson
bash "$KIT" tune 2>&1; echo "  rc=$?"
cache 0 4 cards,lanes,checks,behind
echo "--- 4. why the kit has not updated (§ 5), one reason at a time"
why() { bash "$KIT" tune 2>&1 | sed -n '/^behind:/,/^   fix:/p'; }
mv ops/board/active/T-1.md ops/board/review/T-1.md
printf '{"ts":%d,"ev":"handoff","id":"T-1"}\n' "$(( $(date +%s) - 2 * 86400 - 60 ))" >> ops/board/EVENTS.ndjson
why
mv ops/board/review/T-1.md ops/board/ready/T-1.md
mkdir -p "$(git rev-parse --git-common-dir)/polaris-locks/T-9"
why
rmdir "$(git rev-parse --git-common-dir)/polaris-locks/T-9"
echo stray > ops/stray.sh
why
rm -f ops/stray.sh
why
echo "--- 5. after the fold tune proposed, no cards: line (fold refreshed the cache itself)"
bash "$KIT" fold T-1 T-2 T-3 2>&1; echo "  rc=$?"
cache 1 3 lanes,checks,behind
echo "  cards: lines now: $(bash "$KIT" tune 2>&1 | grep -c '^cards:')"
echo "--- 6. an empty board"
rm -f ops/board/*/T-*.md .polaris/update-cache ops/VERSION .polaris/last-suite-seconds
printf 'test: true\n' > ops/CONVENTIONS.md
bash "$KIT" tune 2>&1; echo "  rc=$?"
cache 1 0 -
