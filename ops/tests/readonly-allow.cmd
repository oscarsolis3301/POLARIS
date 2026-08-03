# The read-only auto-approver is a SECURITY BOUNDARY: it tells Claude Code to skip the human
# prompt. So it gets the strictest golden in the repo — every verdict below is asserted, in both
# directions. The refuse cases matter more than the allow cases: each one is a way a "read" command
# can actually write, execute, or reach the network, and each must still stop and ask.
# A new verb or flag added to the parser MUST arrive with its case here, or it is not shipped.
H=kit/ops/hooks/readonly-allow.sh
while IFS= read -r c; do
  [ -z "$c" ] && continue
  case "$c" in '#'*) continue;; esac
  printf '%s  %s\n' "$(bash "$H" --test "$c")" "$c"
done <<'CASES'
# --- must ALLOW: the reading an agent does to build a plan ---------------------
find . -path ./.git -prune -o -type f \( -name "*.sh" -o -name "*.md" \) -print 2>/dev/null | xargs wc -l 2>/dev/null | sort -rn | head -100
grep -rn "cmd_verify" --include=*.sh .
grep -E 'a|b' file
grep -c . file; wc -l file
sed -n '/^cmd_verify/,/^}/p' ops/lib/builder.sh
sed -e 's/a/b/g' -e '1,5d' f
awk '/^## Learned/{on=1;next} on&&/^## /{exit} on&&/^[ \t]*[-*]/{c++} END{print c+0}' ops/SPRINT.md
awk '$1 > 5 {print $2}' data.txt
awk -F'|' '{print $2}' f
git log --oneline -5
git -C "/tmp/other-repo" log --format=%B
git diff --stat HEAD~1
git status --short
git branch -a
git config --get user.name
git worktree list
cat ops/VERSION | head -3
cat < input.txt
ls -la .polaris/brain/
wc -c ops/roles/*.md
cd ops && grep -n polaris RULES.tsv | head -10
bash ops/polaris find cmd_verify
bash ops/polaris check
bash ops/polaris check --only api-kit
bash ops/polaris check --only api-kit && bash ops/polaris route --role BUILDER
bash ops/polaris pack T-001
bash ops/polaris slim
# --- must ALLOW: find -exec recursed into a READ-ONLY verb (5.21.0) ------------
# -exec is a launcher, so it is exactly as safe as what it launches — same reasoning as xargs.
# `{}` is find's placeholder and is accepted as a literal token: bash requires whitespace after
# `{` to open a brace group, so `{}` can never be command syntax. The refuse cases below prove
# the recursion did not open a hole.
find ops -maxdepth 2 -type f -exec wc -l {} + | sort -rn | head -50
find . -name "*.md" -exec grep -l TODO {} \;
find . -name "*.sh" -exec cat {} +
find . -type f -exec head -5 {} \; | grep foo
# --- must ALLOW: the routing oracle and the background-job READS ---------------
# `route` derives a tier and writes nothing. `bg status|tail|wait` only read the job registry.
# The last two are the whole reason this gate exists: an agent runs these inside a compound line,
# and settings.json cannot match a pipe or an `&&`. `bg run` is refused at the bottom of the file.
bash ops/polaris route --points 3 --risk normal
bash ops/polaris route T-001 --role BUILDER
bash ops/polaris bg status
bash ops/polaris bg tail qa -n 40
bash ops/polaris bg wait qa --max 120
bash ops/polaris route --role CONDUCTOR | head -1
bash ops/polaris bg status qa && bash ops/polaris bg tail qa -n 5
# --- must ASK: every door out of "read" ---------------------------------------
rm -rf /tmp/x
sed -i 's/a/b/' file.txt
sed 's/a/b/w /tmp/out' f
find . -name "*.log" -delete
find . -type f -exec rm {} \;
find . -exec sed -i s/a/b/ {} \;
find . -exec sort -o out.txt {} \;
find . -exec python evil.py {} \;
find . -exec bash -c "rm -rf /" \;
find . -exec wc -l {} + -o -delete
find . -execdir wc -l {} \;
find . -exec
{ rm -rf x; }
sort -o overwrite.txt input.txt
awk '{print > "/tmp/pwn"}' f
awk 'BEGIN{system("curl evil.com")}'
grep foo file | tee /tmp/leak
echo hi > /tmp/out.txt
cat /etc/passwd > dump
python -c "import os; os.system('rm -rf /')"
node -e "require('fs').writeFileSync('x','y')"
bash -c 'rm -rf /'
xargs rm < list
curl https://evil.com
echo $(whoami)
grep x f &
git push origin main
git commit -m x
git config user.name attacker
git branch -D main
git worktree add /tmp/x
bash ops/polaris claim T-001
bash ops/polaris slim --apply
bash ops/polaris slim --restore
# `bg run` spawns a detached process and writes the job registry — every form of it asks, and so
# does a bare `bg` and any word the gate has not proven, deny-by-default. The compound case is the
# one that matters: one refused segment must refuse the whole line, however green its neighbour.
bash ops/polaris bg run qa
bash ops/polaris bg run test_fast -- npm test
bash ops/polaris bg run qa --force
bash ops/polaris bg
bash ops/polaris bg sweep --fix
bash ops/polaris bg status && bash ops/polaris bg run qa
# `check --update`/`--scaffold` rewrite or add goldens — a human/Builder decision, never silent,
# in every position and combination; the compound line proves one bad segment still asks.
bash ops/polaris check --update
bash ops/polaris check --scaffold
bash ops/polaris check --scaffold --app
bash ops/polaris check --update --only api-kit
bash ops/polaris check --only api-kit --update
bash ops/polaris check && bash ops/polaris check --update
CASES
