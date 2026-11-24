# finish-parked — walk-away § 5 (T-324). An ARMED away run ends in one of two shapes: `finish: parked -
# <n> waiting on you` (rc 1) with one `⛔ waiting on you:` line per human-gated item, or rc 0 — and
# both end on the `run:` line and remove the armed file. Unarmed, every line is 6.19.0's.
#
# Cases: 1 unarmed with a deferred row → today's rc 0, no run: line · 2 armed with a risk: high card
# of ANOTHER plan in review/ → today's `not done` (not human-gated for this run), armed file kept ·
# 3 armed, only human-gated items (3 deferred, 1 denied, the armed plan's risk: high card, an ask
# scope a blocked card hits, the stalled marker = 7) → parked, 5 lines + `… and 2 more`, rc 1,
# unknown.parked written, armed gone, run: line last · 4 re-armed 2h ago, every row older than the
# epoch → rc 0, run: line last (bg registry + .archive + decisions.ndjson), armed gone · 5 off base:
# unarmed → today's pending line; armed + clean + merged → switched back, rc 0; armed + unmerged →
# today's pending line.
#
# HERMETIC: a throwaway repo under mktemp -d, fake HOME/USERPROFILE, the heavy-slot dir inside the
# fixture, no session id, no test: key. Epochs are planted relative to `date +%s` so no time prints.
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_HEAVY_DIR="$FIX/heavy" POLARIS_AWAKE_HOME="$FIX/awake"
mkdir -p "$HOME"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'src/vault/\task\t-\tthe vault needs a yes\n' >> ops/RULES.tsv
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
RUN=.polaris/run
NOW="$(date +%s)"
mkdir -p "$RUN"
card() { # card <column> <ID> <plan> <risk> <owned>
  printf -- '---\nid: %s\ntitle: t\npoints: 1\nplan: %s\nrisk: %s\nstatus: %s\napproved: []\nfiles_owned:\n  - %s\n---\n' "$2" "$3" "$4" "$1" "$5" > "ops/board/$1/$2.md"
}
arm() { printf '%s\nwalk\nreentries 0\n' "$1" > "$RUN/s1.armed"; }
F() { OUT="$(bash "$KIT" finish 2>&1)"; RC=$?
  echo "rc=$RC"
  printf '%s\n' "$OUT" | grep -E '^(⛔ |   … |   switched|run: |✅ finish: )' \
    | sed -E 's/^run: [0-9]+[smh] - /run: <total> - /; s/ - [0-9]+s in checks/ - <s> in checks/'
  echo "last: $(printf '%s\n' "$OUT" | tail -1 | sed -E 's/^run: .*/run: …/; s/^✅ .*/✅ …/')"
  echo "armed: $(ls "$RUN"/*.armed 2>/dev/null | wc -l | tr -d ' ') · parked: $(ls "$RUN"/*.parked 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')"
}

echo "== 1. unarmed, a deferred row — today's ending, byte for byte =="
printf '%s\tpush needs a token\tgit push origin main\n' "$NOW" > "$RUN/deferred.tsv"
F

echo "== 2. armed, a risk: high card of another plan waits to land — today's not done =="
arm "$NOW"
card review T-5 other high src/b.txt
F
rm -f ops/board/review/T-5.md

echo "== 3. armed, only human-gated items — parked =="
printf '%s\tdeploy needed a person\tbash deploy.sh\n' "$NOW" >> "$RUN/deferred.tsv"
printf '%s\tdeploy needed a person\tbash deploy.sh\n' "$NOW" >> "$RUN/deferred.tsv"   # a repeat folds
printf '%s\tthe release tag\tgit tag v1\n' "$NOW" >> "$RUN/deferred.tsv"
printf '%s\tBash\trm -rf build\n' "$NOW" > "$RUN/denied.tsv"
card review T-6 walk high src/c.txt
card blocked T-7 walk normal src/vault/key.txt
card blocked T-8 elsewhere normal src/vault/other.txt          # another plan: not this run's
printf '%s\tno beat for 20m\n' "$NOW" > "$RUN/stalled"
F
echo "parked file:"; sed 's/^/  /' "$RUN/unknown.parked"

echo "== 4. re-armed 2h ago, every row older than the epoch — rc 0, the run: line =="
rm -f ops/board/review/T-6.md ops/board/blocked/T-7.md ops/board/blocked/T-8.md "$RUN/unknown.parked"
E=$(( NOW - 7200 ))
for f in deferred.tsv denied.tsv stalled; do sed -E "s/^[0-9]+/$(( E - 60 ))/" "$RUN/$f" > "$RUN/$f.t" && mv "$RUN/$f.t" "$RUN/$f"; done
arm "$E"
B=.polaris/bg
mkdir -p "$B/chk" "$B/.archive/hang-1" "$B/old"
printf '%s\n' $(( E + 10 )) > "$B/chk/start"; printf '%s\n' $(( E + 310 )) > "$B/chk/end"; echo 0 > "$B/chk/rc"
printf 'integration lane busy — x holds it (1m); waited 30s\nintegration lane busy — x holds it (1m); waited 60s\nheavy: waited 2m for y — running without the slot\n' > "$B/chk/log"
printf '%s\n' $(( E + 400 )) > "$B/.archive/hang-1/start"; printf '%s\n' $(( E + 460 )) > "$B/.archive/hang-1/end"
echo 124 > "$B/.archive/hang-1/rc"; printf '2\t2\n' > "$B/.archive/hang-1/overrun"; : > "$B/.archive/hang-1/log"
printf '%s\n' $(( E - 900 )) > "$B/old/start"; printf '%s\n' $(( E - 10 )) > "$B/old/end"; echo 0 > "$B/old/rc"   # before the epoch
{ printf '{"ts":%s,"kind":"test_depth","depth":"full","secs":200,"rc":0}\n' $(( E + 100 ))    # inside chk: counted once
  printf '{"ts":%s,"kind":"test_depth","depth":"full","secs":120,"rc":0}\n' $(( E + 1000 ))
  printf '{"ts":%s,"kind":"test_depth","depth":"full","secs":9000,"rc":0}\n' $(( E - 100 ))
} > .polaris/decisions.ndjson
F

echo "== 5a. unarmed, off base on a merged branch — today's pending line =="
git switch -q -c side
F
echo "== 5b. armed, clean, merged — switched back, rc 0 =="
arm "$NOW"
F
echo "branch: $(git rev-parse --abbrev-ref HEAD)"
echo "== 5c. armed, a branch with a commit main does not have — today's pending line =="
git switch -q -c ahead; echo y > src/a.txt; git commit -qam ahead
arm "$NOW"
F
echo "branch: $(git rev-parse --abbrev-ref HEAD)"

echo "== 6. notify-gate stall and parked fire the notify: hook; the usage names both =="
printf 'notify: echo "$POLARIS_EV $POLARIS_NOTE $POLARIS_SEVERITY" >> "%s/notified"\n' "$FIX" >> ops/CONVENTIONS.md
bash "$KIT" notify-gate stall; echo "stall rc=$?"
bash "$KIT" notify-gate parked; echo "parked rc=$?"
i=0; while [ "$(cat "$FIX/notified" 2>/dev/null | wc -l | tr -d ' ')" -lt 2 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$(( i + 1 )); done
sort "$FIX/notified" 2>/dev/null
bash "$KIT" notify-gate bogus 2>&1; echo "bogus rc=$?"
