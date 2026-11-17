# tune-hop: `next` and a bare `triage` send a session to the tune-up (the `tidy` lane, ops/roles/TIDY.md)
# when the CACHED verdict in .polaris/tune-due says due — and nothing is building or waiting to land —
# even with cards waiting in ready/ and backlog/ (ops/contracts/tune.md § 6). Cards merely waiting
# never hold it off: the layout pass keeps off their files (the hops-hold golden). Once per session,
# then the usual answer. An active card, a review card, a live lease or an own live bg job holds the
# hop off, and every such answer is byte-identical to the answer with no verdict on disk at all.
#
# The verdict file is § 2's: ONE LF line `<base sha><TAB><0|1><TAB><n><TAB><kinds>`, written here as a
# fixture — `tune` (T-308) writes the real one; this card only reads it. HERMETIC, the handover-route
# pattern: a throwaway repo, its own board, the CLI run from INSIDE it, every call its own session id.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt; echo y > src/b.txt; echo z > src/c.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  printf '# fixture contract\n' > ops/contracts/fix.md
) >/dev/null 2>&1
cd "$FIX/repo"
L="$(git rev-parse --git-common-dir)/polaris-locks"
mk() { # mk <column> <id> <risk> <owned path>
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: %s\nowner: null\nbranch: null\nstatus: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify: []\n---\n## Notes\n' \
    "$2" "$2" "$3" "$1" "$4" > "ops/board/$1/$2.md"
}
B="$(git rev-parse main)"
mkdir -p .polaris
DUE="$(printf '%s\t0\t2\tcards,layout' "$B")"
N() { CLAUDE_CODE_SESSION_ID="$1" bash "$KIT" next 2>&1; }
T() { CLAUDE_CODE_SESSION_ID="$1" bash "$KIT" triage 2>&1; }
same() { # same <label> <sid> <cmd> — the answer with the due verdict, then proof it is the no-verdict answer
  a="$("$3" "$2-a")"
  mv .polaris/tune-due .polaris/tune-due.off
  b="$("$3" "$2-b")"
  mv .polaris/tune-due.off .polaris/tune-due
  printf '%s: %s · same as with no verdict: %s\n' "$1" "$(printf '%s\n' "$a" | sed -n 1p)" "$([ "$a" = "$b" ] && echo yes || echo NO)"
}

echo '--- 1. a ready card and a backlog card waiting, the verdict due: tidy once per session, then the usual answer'
mk ready T-R1 normal src/a.txt
mk backlog T-B1 normal src/b.txt
printf '%s\n' "$DUE" > .polaris/tune-due
N th-1; N th-1 | sed -n 1p
T th-2; T th-2 | sed -n 1p
printf 'markers: %s\n' "$(ls -d .polaris/handover/*/tidy | sed 's#.*/handover/##' | tr '\n' ' ')"

echo '--- 2. the verdict not due, stale or malformed: silence — the usual answers'
printf '%s\t1\t3\tlanes,landing,checks\n' "$B" > .polaris/tune-due; N th-3 | sed -n 1p; T th-3 | sed -n 1p
printf '%s\t0\t2\tcards,layout\n' "$(git rev-parse main~1)" > .polaris/tune-due; N th-4 | sed -n 1p; T th-4 | sed -n 1p
printf '%s\t0\n' "$B" > .polaris/tune-due; N th-5 | sed -n 1p; T th-5 | sed -n 1p
printf '%s\t0\t2\tcards,layout\r\n' "$B" > .polaris/tune-due; N th-6 | sed -n 2p; T th-6t | sed -n 2p | tr -d '\n'; echo ' (a CRLF verdict reads due, its \r stripped)'

echo '--- 3. what holds it off — each answer byte-identical to the one with no verdict'
printf '%s\n' "$DUE" > .polaris/tune-due
mk active T-A1 normal src/c.txt
same 'an active card · next' h1 N; same 'an active card · triage' h2 T
rm -f ops/board/active/T-A1.md
mk review T-V1 normal src/c.txt
same 'a review card · next' h3 N; same 'a review card · triage' h4 T
rm -f ops/board/review/T-V1.md
mk review T-V2 high src/c.txt
same 'a human-gated review card · next' h5 N; same 'a human-gated review card · triage' h6 T
rm -f ops/board/review/T-V2.md
mkdir -p "$L/.int-lease"; date +%s > "$L/.int-lease/epoch"; echo someone@elsewhere > "$L/.int-lease/who"; echo 1 > "$L/.int-lease/pid"
same 'a live lease · next' h7 N; same 'a live lease · triage' h8 T
rm -rf "$L/.int-lease"
mkdir -p .polaris/bg/fixture-job; echo "$$" > .polaris/bg/fixture-job/pid; pwd > .polaris/bg/fixture-job/cwd
same 'an own live bg job · next' h9 N; same 'an own live bg job · triage' h10 T
rm -rf .polaris/bg/fixture-job

echo '--- 4. with nothing holding it any more, a fresh session hops again'
N th-7 | sed -n 1p; T th-8 | sed -n 1p
