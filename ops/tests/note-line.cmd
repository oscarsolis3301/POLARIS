# note-line — T-308 (ops/contracts/tune.md § 3): `polaris note <ID> -m "<line>"` appends ONE line
# `- <line>` (a leading `- ` is not doubled) to the Notes of a task in active/, in its OWN board commit
# `chore(board): note <ID>`, event `note`, and prints `noted on <ID>: <line>`. Refusals die rc 1 and
# write nothing: no ID / no -m · an unknown flag · a message with a newline · a task not in active/.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it. No sha/time/path.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID POLARIS_ROOT
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  echo v1 > a.dat; git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  printf -- '---\nid: T-1\ntitle: "claimed"\npoints: 1\n---\n## Why\nfixture\n## Notes\n- first\n' > ops/board/active/T-1.md
  printf -- '---\nid: T-2\ntitle: "waiting"\npoints: 1\n---\n## Why\nfixture\n' > ops/board/ready/T-2.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
snap() { { cat ops/board/*/*.md ops/board/EVENTS.ndjson; git rev-parse -q --verify refs/heads/polaris/board; } | cksum; }
try() { # try <label> <args…> — a refusal: its message, its rc, and whether anything was written
  local lb="$1" b out rc; shift; b="$(snap)"
  out="$(bash "$KIT" note "$@" 2>&1)"; rc=$?
  echo "$lb: rc=$rc"; printf '%s\n' "$out" | sed 's/^/  /'
  [ "$b" = "$(snap)" ] && echo "  nothing written" || echo "  WROTE SOMETHING"
}
try no-id
try no-m T-1
try empty-m T-1 -m ""
try unknown-flag T-1 --force -m "x"
try two-lines T-1 -m "one
two"
try not-active T-2 -m "x"
try unknown-id T-9 -m "x"
echo "good:"; bash "$KIT" note T-1 -m "assumed: the safe default" 2>&1; echo "  rc=$?"
echo "  subject: $(git log -1 --format=%s refs/heads/polaris/board)"
echo "  events: $(grep -c '"ev":"note","id":"T-1"' ops/board/EVENTS.ndjson)"
echo "dash-not-doubled:"; bash "$KIT" note T-1 -m "- a finding for the planner" 2>&1; echo "  rc=$?"
echo "  board commits: $(git rev-list --count refs/heads/polaris/board)"
echo "notes now:"; sed -n '/^## Notes/,$p' ops/board/active/T-1.md | sed 's/^/  /'
echo "on the ref: $(git show refs/heads/polaris/board:ops/board/active/T-1.md | tail -1)"
