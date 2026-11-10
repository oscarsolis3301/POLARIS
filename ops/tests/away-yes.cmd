# away-yes — away, the approved plan's yes is the yes (ops/contracts/away.md § 4, § Executable checks B3).
# HERMETIC: a throwaway repo under mktemp -d with the kit INSTALLED in it, so every command runs the
# fixture's own ops/polaris; default landing (self). HOME, USERPROFILE and POLARIS_AWAKE_HOME are faked
# together and the golden writes the two state files itself to play "away" and "here". A plan is bound
# two ways: `approve --plan <slug>` in the session after the approval, and `new` filing a task of the
# plan in the session after the approval (§ 4). The first cases file their tasks from ANOTHER session,
# so `approve --plan` alone binds there. Pinned: away + a bound risk: high task ⇒ its handoff writes the
# `merge` entry ending `approved plan, owner away`, prints the `away:` line, records one away-yes event
# and self-lands (plan_covers passed) · `default` mode ⇒ no entry, today's refusal · a slug never bound
# ⇒ no entry · a hand entry on the task ⇒ no entry · `autonomy: standard` ⇒ no entry · `claim` never
# binds · `new` binds: a task filed after the approval with no `approve --plan` at all is covered, one
# filed before the approval is not.
# No sha, path or time is printed: the entry's actor and date are masked.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT
export CLAUDE_CODE_SESSION_ID=away-yes-sid
ST="$HOME/.claude/polaris/model-state/$CLAUDE_CODE_SESSION_ID"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT_DIR/ops/install.sh" "$R"
  bash ops/polaris init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  printf '# SPRINT 1 — x\n' > ops/SPRINT.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  mkdir -p .polaris/brain
  git add -A; git commit -qm board
  D=.polaris/drafts; mkdir -p "$D"
  for s in seed a b c d e; do
    ap="[]"; pl=a; rk=high
    [ "$s" = d ] && ap="
  - merge — owner, 2026-01-01: I decide this one myself"
    [ "$s" = b ] && pl=b
    [ "$s" = seed ] && rk=normal
    printf -- '---\ntitle: change %s\nplan: %s\npoints: 1\nrisk: %s\nfiles_owned:\n  - src/%s.txt\ndepends_on: []\ncontract: ops/contracts/fix.md\napproved: %s\nverify: []\n---\n## Why\nfixture\n' "$s" "$pl" "$rk" "$s" "$ap" > "$D/$s.md"
  done
) >/dev/null 2>&1
cd "$R"
mkdir -p "${ST%/*}"
mask() { sed -e 's/— [^,]*, [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]:/— WHO, DATE:/'; }
entries() { # entries <ID> — the task's approved: entries, wherever it sits now
  f="$(ls ops/board/*/"$1".md 2>/dev/null | head -1)"
  awk '/^---/{n++; next} n==1 && /^approved:/{a=1; sub(/^approved:[ ]*/,""); if ($0!="") print "  " $0; next} n==1 && a && /^[ \t]*- /{print "  " $0; next} n==1 && a{a=0}' "$f" | mask
}
ship() { # ship <ID> — claim, one commit in the worktree, handoff from inside it
  bash ops/polaris claim "$1" >/dev/null 2>&1
  ( cd ".polaris/wt/$1" && echo y > "src/$2.txt" && git add -A && git commit -qm "change $2" ) >/dev/null 2>&1
  out="$(cd ".polaris/wt/$1" && bash ops/polaris handoff "$1" 2>&1)"; echo "handoff rc=$?"
  echo "away line: $(printf '%s\n' "$out" | grep -c '^away: ')"
  printf '%s\n' "$out" | grep '^away: ' | sed 's/^/  /'
  echo "refusal: $(printf '%s\n' "$out" | grep -c 'risk: high never self-lands — a human must approve the merge; task stays in review/')"
  echo "self-land: $(printf '%s\n' "$out" | grep -c 'landing: self — continuing into land')"
  echo "landed: $(printf '%s\n' "$out" | grep -c "$1 landed on the wave")"
  echo "entries:"; entries "$1"
}
echo "installed: $([ -f ops/polaris ] && echo yes || echo no)"
echo "== the plan is approved in this session, and approve --plan a binds its slug"
printf 'auto\n' > "$ST.mode"
printf '1\n' > "$ST.approved"
CLAUDE_CODE_SESSION_ID=away-yes-other bash ops/polaris new .polaris/drafts/seed.md 2>&1 | sed 's/^/  /'
bash ops/polaris approve --plan a -m "the plan, approved" 2>&1 | sed 's/^/  /'
echo "== a c d e (plan a) and b (plan b, never approved) filed after it"
CLAUDE_CODE_SESSION_ID=away-yes-other bash ops/polaris new .polaris/drafts/a.md .polaris/drafts/b.md .polaris/drafts/c.md .polaris/drafts/d.md .polaris/drafts/e.md 2>&1 | sed 's/^/  /'
echo "bound slugs:"; sed -n '2,$p' "$ST.approved" | sed 's/^/  /'
echo "presence: $(bash ops/polaris presence | head -1)"
echo "== away, plan a bound: the plan's yes is the yes"
ship T-002 a
echo "events: $(grep -c '"away-yes"' ops/board/EVENTS.ndjson 2>/dev/null)"
echo "== here (default mode), plan a bound: today's refusal"
printf 'default\n' > "$ST.mode"
ship T-004 c
printf 'auto\n' > "$ST.mode"
echo "== away, plan b never bound: today's refusal"
ship T-003 b
echo "== away, d carries a hand entry: today's refusal"
ship T-005 d
echo "== away, autonomy: standard: today's refusal"
printf 'test: true\nautonomy: standard\n' > ops/CONVENTIONS.md
ship T-006 e
echo "events: $(grep -c '"away-yes"' ops/board/EVENTS.ndjson 2>/dev/null)"
echo "== claim never binds: still only the approved plan"
echo "bound slugs:"; sed -n '2,$p' "$ST.approved" | sed 's/^/  /'
echo "== new binds: f filed before the approval, g after it, no approve --plan at all"
printf 'test: true\n' > ops/CONVENTIONS.md
rm -f "$ST.approved"
for s in f g; do
  printf -- '---\ntitle: change %s\nplan: %s\npoints: 1\nrisk: high\nfiles_owned:\n  - src/%s.txt\ndepends_on: []\ncontract: ops/contracts/fix.md\napproved: []\nverify: []\n---\n## Why\nfixture\n' "$s" "$s" "$s" > ".polaris/drafts/$s.md"
done
bash ops/polaris new .polaris/drafts/f.md 2>&1 | sed 's/^/  /'
printf '1\n' > "$ST.approved"
bash ops/polaris new .polaris/drafts/g.md 2>&1 | sed 's/^/  /'
echo "bound slugs:"; sed -n '2,$p' "$ST.approved" | sed 's/^/  /'
echo "presence: $(bash ops/polaris presence | head -1)"
echo "== away, g bound by new: the plan's yes is the yes"
ship T-008 g
echo "events: $(grep -c '"away-yes"' ops/board/EVENTS.ndjson 2>/dev/null)"
echo "== away, f filed before the approval: today's refusal"
ship T-007 f
echo "== away, g bound, h has no approved: line at all (one-yes.md v1.1): it gains one and lands"
grep -v '^approved:' .polaris/drafts/g.md | sed 's/change g/change h/; s#src/g.txt#src/h.txt#' > .polaris/drafts/h.md
bash ops/polaris new .polaris/drafts/h.md 2>&1 | sed 's/^/  /'
echo "approved line before: $(grep -c '^approved:' ops/board/ready/T-009.md)"
ship T-009 h
