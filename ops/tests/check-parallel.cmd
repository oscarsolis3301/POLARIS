# check-parallel — the goldens run side by side, with the same output as one at a time
# (ops/contracts/minutes.md § 6, T-276).
#
# A scratch repo with six tiny goldens: one red, one with a .rc, two slow ones that log their start
# and end and sleep 1 s, two plain ones. `check --jobs 3` and `check --jobs 1` must print the same
# lines; the two slow goldens overlap at 3 and never at 1. Then a seventh golden that goes red only
# while another golden is busy shows the "passed alone" note. .polaris/check-times is seeded before
# each run so the two slow goldens are dealt first, to different workers. TMPDIR points into the
# fixture, so a temp folder left behind is counted.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q "$R"; cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p ops/tests .polaris; echo x > a.txt; git add -A; git commit -qm init
) >/dev/null 2>&1
T="$R/ops/tests"
echo 'echo one'                > "$T/a-red.cmd";   echo 'two'      > "$T/a-red.expected"
echo 'echo three; exit 3'      > "$T/b-rc.cmd";    echo 'three'    > "$T/b-rc.expected"; echo 3 > "$T/b-rc.rc"
for s in c d; do
  printf '%s\n' "touch ../busy.$s; echo \"$s start \$(date +%s)\" >> ../log; sleep 1" \
    "echo \"$s end \$(date +%s)\" >> ../log; rm -f ../busy.$s; echo slow $s" > "$T/$s-slow.cmd"
  echo "slow $s" > "$T/$s-slow.expected"
done
echo 'echo five'               > "$T/e-plain.cmd"; echo 'five'     > "$T/e-plain.expected"
printf 'echo six\necho\n\n'    > "$T/f-plain.cmd"; echo 'six'      > "$T/f-plain.expected"
mkdir -p "$FIX/tmp"
seed() { printf 'c-slow 5\nd-slow 5\ng-shy 4\n' > "$R/.polaris/check-times"; rm -f "$FIX/log"; }
C() { seed; ( cd "$R" && TMPDIR="$FIX/tmp" bash "$KIT" check --jobs "$1" 2>&1; echo "rc=$?" ); }
# overlap: a second start is logged before the first end
ov() { awk '/ start /{if(open)o=1; open++} / end /{open--} END{print (o ? "yes" : "no")}' "$FIX/log"; }

echo '== six goldens, one at a time =='
C 1 > "$FIX/one"; cat "$FIX/one"; o1="$(ov)"
echo '== six goldens, three at a time =='
C 3 > "$FIX/three"; o3="$(ov)"
cmp -s "$FIX/one" "$FIX/three" && echo "same output: yes" || { echo "same output: no"; diff "$FIX/one" "$FIX/three"; }
echo "overlap at 3: $o3"
echo "overlap at 1: $o1"
echo "check-times names: $(awk '{print $1}' "$R/.polaris/check-times" | sort | tr '\n' ' ')"

echo '== a seventh golden, red only while another is busy =='
printf '%s\n' 'sleep 0.5; if ls ../busy.* >/dev/null 2>&1; then echo crowded; else echo alone; fi' > "$T/g-shy.cmd"
echo alone > "$T/g-shy.expected"
C 3
echo '== the same seven, one at a time: no note =='
C 1 | grep -c 'note:'
echo '== --jobs needs a number =='
( cd "$R" && bash "$KIT" check --jobs many 2>&1; echo "rc=$?" )
echo "temp left behind: $(ls -A "$FIX/tmp" | wc -l | tr -d ' ')"
