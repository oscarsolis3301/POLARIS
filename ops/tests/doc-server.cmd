# doc-server — `role`, `doc`, `router` serve the kit's own documents (ops/contracts/doc-server.md § 4,
# "Executable checks"): a small file byte-identical · a CONDUCTOR-sized file in pages cut at `## `
# lines outside fences (footers, --page 2, out of range, one oversized section left whole) · doc
# sections (hit, miss, a heading inside a fence ignored) · doc unknown · router with and without the
# POLARIS markers · a repo copy wins over the kit's · a kit-only file is served when the repo has none
# · doc --where (machine vs vendored) · v2: the real router ≤ 8,000 bytes with every heading kept, each
# PROTOCOL section it names served and holding the text moved out of it, every role CONDUCTOR page
# ≤ 28,000 bytes with `## Protocol` unchanged.
# HERMETIC: a fixture KIT (the real polaris + core.sh + docs.sh beside FAKE documents) and a fixture
# repo, both under mktemp -d, so the live roles growing never moves this golden. One real-kit line
# at the end, numbers masked.
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
unset CLAUDECODE
W="$(pwd)"
K="$F/kit/ops"
mkdir -p "$K/lib" "$K/roles" "$K/templates"
cp kit/ops/polaris "$K/polaris"
cp kit/ops/lib/core.sh kit/ops/lib/docs.sh "$K/lib/"
R="$F/repo"
( git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
P() { ( cd "$R" && bash "$K/polaris" "$@" 2>&1; echo "rc=$?" ) | sed "s#$F#<F>#g"; }
# filler <n> <tag> — n lines of 99 chars + newline (100 bytes each)
filler() { awk -v n="$1" -v t="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%s line %04d %s\n", t, i, substr(sprintf("%099d", 0), 1, 99 - length(t) - 11) }'; }

printf '# ROLE: BUILDER — fixture\nsmall file, no trailing newline' > "$K/roles/BUILDER.md"
printf '# ROLE: TIDY — fixture from the kit\n' > "$K/roles/TIDY.md"
{ echo '# ROLE: CONDUCTOR — fixture'; filler 19 pre
  echo '## A first'; filler 99 a
  echo '## B with a fence'; filler 40 b; echo '```'; echo '## not a cut — inside a fence'; echo '```'; filler 56 b
  echo '## C third'; filler 119 c
  echo '## D fourth'; filler 29 d
  echo '## E oversized'; filler 300 e
} > "$K/roles/CONDUCTOR.md"

echo '== 1. role: a small file is byte-identical =='
( cd "$R" && bash "$K/polaris" role builder ) > "$F/out"
cmp -s "$F/out" "$K/roles/BUILDER.md" && echo 'role builder: byte-identical' || echo 'role builder: DIFFERS'
P role Builder | tail -1

echo '== 2. role: paged at ## outside fences =='
echo "fixture bytes: $(wc -c < "$K/roles/CONDUCTOR.md" | tr -d ' ')"
: > "$F/joined"
for p in 1 2 3; do
  ( cd "$R" && bash "$K/polaris" role CONDUCTOR --page "$p" ) > "$F/p$p"
  echo "page $p: first '$(head -1 "$F/p$p")' · bytes before the footer $(sed '$d' "$F/p$p" | wc -c | tr -d ' ')"
  tail -1 "$F/p$p"
  sed '$d' "$F/p$p" >> "$F/joined"
done
cmp -s "$F/joined" "$K/roles/CONDUCTOR.md" && echo 'pages joined: byte-identical' || echo 'pages joined: DIFFERS'
( cd "$R" && bash "$K/polaris" role CONDUCTOR ) | tail -1
grep -c '^## not a cut' "$F/p1"
P role CONDUCTOR --page 4
P role CONDUCTOR --page x | tail -2
P role BUILDER --page 2
P role nope

echo '== 3. doc: sections =='
{ echo '# PROTOCOL fixture'; echo 'intro'
  echo '```'; echo '## THE TOOL — a fake heading inside a fence'; echo '```'
  echo '## THE TOOL — real'; echo 'tool body'; echo '### a sub heading stays'; echo 'sub body'
  echo '```'; echo '## still the tool — fenced'; echo '```'
  echo '## NEXT section'; echo 'next body'
} > "$K/PROTOCOL.md"
P doc PROTOCOL "the tool"
P doc PROTOCOL "sub heading"
P doc PROTOCOL "no such thing"
( cd "$R" && bash "$K/polaris" doc PROTOCOL ) | cmp -s - "$K/PROTOCOL.md" && echo 'doc PROTOCOL: byte-identical'
printf 'k\t1\t-\t-\t\trepo\n' > "$K/KEYS.tsv"; P doc KEYS
printf '# TASK template\n' > "$K/templates/TASK.md"; P doc templates/TASK
P doc roles/tidy | head -1
P doc roles/TIDY

echo '== 4. doc: unknown and refused =='
P doc nope
P doc ../polaris
P doc templates/../../x
P doc /etc/passwd
P doc MANUAL

echo '== 5. router: with and without markers =='
printf '# kit router — no markers\nline two\n' > "$F/kit/CLAUDE.md"
P router
printf 'user text above\n<!-- POLARIS:BEGIN v5 -->\n# inside\nline\n<!-- POLARIS:END -->\nuser text below\n' > "$F/kit/CLAUDE.md"
P router
P router --page 2
rm -f "$F/kit/CLAUDE.md"
P router

echo '== 6. a repo copy wins · a kit-only file is served =='
mkdir -p "$R/ops/roles"
printf '# ROLE: BUILDER — the REPO copy\n' > "$R/ops/roles/BUILDER.md"
P role BUILDER
P role TIDY
P role nope | head -1

echo '== 7. doc --where =='
P doc --where
mkdir -p "$R/ops/lib"; cp "$K/polaris" "$R/ops/polaris"; cp "$K/lib/"*.sh "$R/ops/lib/"
( cd "$R" && bash ops/polaris doc --where 2>&1 ) | sed "s#$F#<F>#g"

echo '== 8. the real kit: CONDUCTOR comes in pages =='
R2="$F/empty"
( git init -q "$R2" && cd "$R2" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i ) >/dev/null 2>&1
# a checkout may carry CRLF role files (git autocrlf): compare the text, not the line ending
( cd "$R2" && bash "$W/kit/ops/polaris" role CONDUCTOR ) | tail -1 | tr -d '\r' | sed 's/of [0-9][0-9]*/of <n>/'
( cd "$R2" && bash "$W/kit/ops/polaris" role builder ) | head -1 | tr -d '\r'

echo '== 9. the real kit: the router fits a session hook, CONDUCTOR pages fit the harness (doc-server v2) =='
( cd "$R2" && bash "$W/kit/ops/polaris" router ) | tr -d '\r' > "$F/router"
[ "$(wc -c < "$F/router")" -le 8000 ] && echo 'router ≤ 8000: yes' || echo "router ≤ 8000: NO ($(wc -c < "$F/router" | tr -d ' '))"
tr -d '\r' < "$W/kit/CLAUDE.md" | grep -E '^#{1,4} ' | sed 's/^/router heading: /'
# every section the router names is served, and the explanations it moved out are in them
grep -o 'bash ops/polaris doc PROTOCOL "[^"]*"' "$F/router" | sed 's/.*"\(.*\)"/\1/' | LC_ALL=C sort -u | while IFS= read -r s; do
  ( cd "$R2" && bash "$W/kit/ops/polaris" doc PROTOCOL "$s" ) > "$F/sec" 2>&1; rc=$?
  echo "doc PROTOCOL \"$s\": rc=$rc · $(head -1 "$F/sec" | tr -d '\r')"
done
for m in 'LANES|The kickoff rules, in full' 'LANES|Never a menu of execution strategies' 'STATE = THE BOARD|RULES.tsv, in full' 'N CHATS, ONE REPO|Do NOT rely on runtime self-organization'; do
  ( cd "$R2" && bash "$W/kit/ops/polaris" doc PROTOCOL "${m%%|*}" ) | grep -qF "${m#*|}" && echo "moved: ${m#*|} → ${m%%|*}" || echo "MISSING: ${m#*|} in ${m%%|*}"
done
n=$( ( cd "$R2" && bash "$W/kit/ops/polaris" role CONDUCTOR ) | tail -1 | tr -d '\r' | sed -n 's/.* of \([0-9][0-9]*\) .*/\1/p')
echo "role CONDUCTOR: ${n:-1} page(s)"
for p in $(seq 1 "${n:-1}"); do
  b=$( ( cd "$R2" && bash "$W/kit/ops/polaris" role CONDUCTOR --page "$p" ) | sed '$d' | wc -c | tr -d ' ')
  [ "$b" -le 28000 ] && echo "page $p ≤ 28000: yes" || echo "page $p ≤ 28000: NO ($b)"
done
tr -d '\r' < "$W/kit/ops/roles/CONDUCTOR.md" | grep -c '^## Protocol$'
