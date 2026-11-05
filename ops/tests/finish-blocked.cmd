# finish-blocked — save-hops.md § 2.4 (T-237). `finish` has always counted what sits in blocked/,
# but only as IDs, so a close could say THAT work was set aside and never WHY. The caveat now carries
# each ID's reason: the note of its NEWEST "ev":"blocked" event, whitespace collapsed, cut at 80
# characters with `…`, and `no reason recorded` when there is none. It is still a caveat and never a
# gate — rc 0 and "run complete" with five, then six, tasks parked.
#
# HERMETIC (the triage-lane pattern): a throwaway repo under mktemp -d, the CLI run from INSIDE it,
# no session id, and no test: key — finish must not need a suite here. T-1 is parked by the REAL
# release path, so the writer → reader round trip runs on the escapes evt really writes (a quote, a
# backslash, a tab, a double space). Every other event is a planted line in evt's exact shape, each
# pinning one rule: the newest wins over line order (EVENTS.ndjson is union-merged) · another event
# kind and a look-alike ID never count · a tie on the clock goes to the later line · exactly 80
# characters is never cut and 81 is — counted in characters, not bytes, so the dashes and arrows
# before the cut must not shorten it · a blank note and no event both read `no reason recorded` ·
# past five the list ends `… +N more`, the fin_ids shape (PROTOCOL.md § VOICE).
unset CLAUDE_CODE_SESSION_ID
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  printf -- '---\nid: T-1\ntitle: fixture task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' > ops/board/ready/T-1.md
  bash "$KIT" claim T-1
  Q='"'; B='\'; TB="$(printf '\t')"
  bash "$KIT" release T-1 --to blocked -m "waits on the owner's ${Q}yes${Q} for C:${B}data${TB}and  more"
) >/dev/null 2>&1
R="$FIX/repo"
EV="$R/ops/board/EVENTS.ndjson"
P() { printf -- '---\nid: %s\npoints: 1\nstatus: blocked\n---\n' "$1" > "$R/ops/board/blocked/$1.md"; }
P T-2; P T-3; P T-4; P T-5
{ printf '{"ts":200,"ev":"blocked","id":"T-2","who":"t","note":"→ blocked: the newest reason wins, even when an older line comes after it"}\n'
  printf '{"ts":100,"ev":"blocked","id":"T-2","who":"t","note":"→ blocked: an older reason, appended later by a union merge"}\n'
  printf '{"ts":300,"ev":"release","id":"T-2","who":"t","note":"→ ready: a release is not a block"}\n'
  printf '{"ts":400,"ev":"blocked","id":"T-22","who":"t","note":"→ blocked: a look-alike ID, never T-2"}\n'
  printf '{"ts":500,"ev":"blocked","id":"T-3","who":"t","note":"→ blocked: same second, earlier line — not this one"}\n'
  printf '{"ts":500,"ev":"blocked","id":"T-3","who":"t","note":"→ blocked: exactly eighty characters — shown in full, never cut, and no ellipsis"}\n'
  printf '{"ts":600,"ev":"blocked","id":"T-4","who":"t","note":" \t  "}\n'
  printf '{"ts":700,"ev":"blocked","id":"T-5","who":"t","note":"→ blocked: the owner picks a layout — flat · by feature · by layer — before a file moves; until then the pass skips src/"}\n'
  printf '{"ts":800,"ev":"blocked","id":"T-7","who":"t","note":"→ blocked: one character over eighty — the cut keeps eighty and adds one ellipsis"}\n'
} >> "$EV"
F() { OUT="$(cd "$R" && bash "$KIT" finish 2>&1)"; RC=$?
  echo "rc=$RC"
  printf '%s\n' "$OUT" | grep -oE 'finish: (run complete|not done)'
  printf '%s\n' "$OUT" | grep -c '^⛔ pending' || true
  printf '%s\n' "$OUT" | grep '^   caveat: [0-9]* blocked — '
}
echo "== five parked: the real release, newest-wins, a tie at exactly 80, a blank note, a long one =="
F
echo "== six parked: no event at all, 81 characters, and the sixth folds into … +1 more =="
rm -f "$R/ops/board/blocked/T-1.md" "$R/ops/board/blocked/T-2.md"
P T-6; P T-7; P T-8
F
