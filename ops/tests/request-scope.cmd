# T-192 — `triage <ID…>` and `next`'s foreign rule keep a run on its request
# (ops/contracts/stay-on-request.md § 1-2). Before this, `triage` and `next` always read the WHOLE
# board, so a ready leftover with no `plan:` counted as part of every run's lane and never looked
# foreign to the drain — the FIX-1 incident. HERMETIC, the triage-lane pattern (T-062's lesson): a
# fixture board in a throwaway repo, the CLI run from INSIDE it, so a live-board write can never
# red this. ONE invocation per assertion, each cheap (~0.7s of startup, the 5.21.0 lesson).
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
  git add -A; git commit -qm board
  printf '# fixture contract\n' > ops/contracts/fix.md
  # a leftover already sitting in ready/, no plan: — the thing an unrelated request must never pick up
  printf -- '---\nid: FIX-1\ntitle: old cleanup leftover\ntype: feature\npoints: 1\nwsjf: 9\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/fix1.txt\nverify: []\n---\n' > ops/board/ready/FIX-1.md
  # the request's own task, tagged with the run's plan
  printf -- '---\nid: T-2\ntitle: the actual request\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/t2.txt\nplan: req\nverify: []\n---\n' > ops/board/ready/T-2.md
) >/dev/null 2>&1
cd "$FIX/repo"
# --- triage T-2: only the named task counts, even though FIX-1 also sits in ready/. -------------
OUT="$(bash "$KIT" triage T-2 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | sed -n '2,$p' | grep -c '^   '
printf '%s\n' "$OUT" | grep -c 'FIX-1'
printf '%s\n' "$OUT" | grep -c 'T-2'
# --- an ID that is not in ready/ or active/ is a hard error: rc 1, nothing on stdout. -----------
OUT="$(bash "$KIT" triage T-2 T-999 2>/dev/null)"; RC=$?
printf 'rc=%s out=%s\n' "$RC" "${OUT:-<empty>}"
# --- no IDs at all stays byte-identical: BOTH ready tasks count, so n=2 prices contexts. ---------
bash "$KIT" triage 2>&1 | sed -n 1p
# --- scope recording: with a session id, triage T-2 writes T-2's plan (not FIX-1's, not merged). -
export CLAUDE_CODE_SESSION_ID=rs-sid
bash "$KIT" triage T-2 >/dev/null 2>&1
cat ".polaris/handover/$CLAUDE_CODE_SESSION_ID/plan"
# --- foreign = missing or different plan: once T-2 is out of ready/, FIX-1 (no plan:) is foreign
# under the recorded session plan, so `next` closes the run out rather than hopping into it. -------
rm ops/board/ready/T-2.md
OUT="$(bash "$KIT" next 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | grep -c 'foreign queued (drain: plan): FIX-1'
unset CLAUDE_CODE_SESSION_ID
