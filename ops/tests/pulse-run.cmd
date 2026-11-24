# pulse-run — the away run's three small verbs (ops/contracts/walk-away.md § 2.2-2.3). `pulse` is what
# a timer-woken session runs: line 1 is ONE word it can branch on blind — ok · act <next line 1> ·
# done · parked — and rc is 0 always. `--reenter` counts and refuses past reentry_max. `preflight`
# lists what needs a person before the run starts; `defer` parks a command for the close.
#
# HERMETIC: one throwaway repo with its own board and no remote, HOME/USERPROFILE faked, the armed file
# written by hand (T-319's presence-guard writes it for real). No sha, time, path or pid is printed.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN POLARIS_HEAVY_TOKEN POLARIS_HEAVY_WAIT
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'cd /; rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home" POLARIS_HEAVY_DIR="$FIX/heavy"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt; echo y > src/b.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
export CLAUDE_CODE_SESSION_ID=pr-sid
RUN="$R/.polaris/run"
mk() { # mk <column> <id> <risk> <owned path> [needs]
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\nplan: fix\npoints: 1\nwsjf: 5\nrisk: %s\nowner: null\nbranch: null\nstatus: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nneeds: [%s]\napproved:\nverify: []\n---\n## Notes\n' \
    "$2" "$2" "$3" "$1" "$4" "${5:-}" > "ops/board/$1/$2.md"
}
arm() { mkdir -p "$RUN"; printf '%s\nfix\nreentries %s\n' "${2:-$(date +%s)}" "${1:-0}" > "$RUN/pr-sid.armed"; }
P() { printf 'pulse%s\n' "${*:+ $*}"; bash "$KIT" pulse "$@" 2>&1; printf 'rc %s\n' "$?"; }

echo '== not armed: ok, and the pulse says why it does nothing =='
P
echo '== armed, an empty board: done =='
arm
P
echo '== armed, a ready card: act + next line 1 =='
mk ready T-P1 normal src/a.txt
P
echo '== armed, a card in another lane: ok, next says wait =='
mv ops/board/ready/T-P1.md ops/board/active/T-P1.md
P
echo '== the stalled marker, then this session parked: parked =='
printf '1700000000\tthree blocks on one line\n' > "$RUN/stalled"
P
rm -f "$RUN/stalled"; : > "$RUN/pr-sid.parked"
P
rm -f "$RUN/pr-sid.parked" "$RUN/pr-sid.armed" ops/board/active/T-P1.md
echo '== the armed file gone after a green finish: done =='
mkdir -p .polaris/handover/pr-sid; : > .polaris/handover/pr-sid/finished
P
rm -rf .polaris/handover/pr-sid

echo '== --reenter counts to reentry_max, then refuses =='
arm 0
P --reenter
P --reenter
P --reenter
printf 'armed line 3: %s\n' "$(sed -n 3p "$RUN/pr-sid.armed" | tr -d '\r')"
P --reenter
echo '== --reenter past reentry_hours, or with nothing armed: refused =='
arm 0 1000
P --reenter
rm -f "$RUN/pr-sid.armed"
P --reenter

echo '== preflight: no remote, a risk: high card with no yes, an unknown needs: value =='
mk ready T-P2 high src/a.txt
mk backlog T-P3 normal src/b.txt telepathy
mk ready T-P4 normal src/b.txt
bash "$KIT" preflight fix 2>&1; echo "rc $?"
echo '== preflight: the plan says yes, a suite time is measured: clear =='
rm -f ops/board/backlog/T-P3.md
sed -i.bak 's/^approved:$/approved: [merge — someone, 2026-11-24: plan fix: go]/' ops/board/ready/T-P2.md; rm -f ops/board/ready/T-P2.md.bak
printf '125 1700000000\n' > .polaris/last-suite-seconds
bash "$KIT" preflight fix 2>&1; echo "rc $?"
bash "$KIT" preflight 2>&1; echo "rc $?"

echo '== defer: usage refusals write nothing; a park writes one line =='
bash "$KIT" defer -- echo hi 2>&1; echo "rc $?"
bash "$KIT" defer -m "why" 2>&1; echo "rc $?"
echo "deferred.tsv exists: $([ -f "$RUN/deferred.tsv" ] && echo yes || echo no)"
bash "$KIT" defer -m "the dashboard needs a sign-in" -- gh auth login --web 2>&1; echo "rc $?"
awk -F'\t' '{ print "row: <epoch> | " $2 " | " $3 " | fields " NF }' "$RUN/deferred.tsv"
