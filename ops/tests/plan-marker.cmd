# plan-marker — a session's plan marker follows a new plan once the old one has nothing in flight
# (ops/contracts/safe-landing.md v1.1 § D, rider a). Before this, claim wrote
# .polaris/handover/<session>/plan on the FIRST claim only, so a second plan run in the same session
# was held as foreign by `next --do`. Pinned, one `marker: <plan>` line after each of three claims:
# (1) the first claim (an alpha task) writes alpha · (2) a beta claim while an alpha task is still
# active keeps alpha · (3) once the alpha task is in done/, another beta claim writes beta.
#
# HERMETIC: one throwaway repo under mktemp -d, no remote, HOME and USERPROFILE faked together, the
# CLI run from INSIDE the fixture. Nothing printed carries a sha, a path, a date or a user.
unset POLARIS_INT_TOKEN
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  for t in A-1:alpha B-1:beta B-2:beta; do
    id="${t%%:*}"; p="${t#*:}"
    printf -- '---\nid: %s\ntitle: task %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nplan: %s\nfiles_owned:\n  - src/%s.txt\nverify: []\n---\n' "$id" "$id" "$p" "$id" > "ops/board/ready/$id.md"
  done
) >/dev/null 2>&1
cd "$R"
export CLAUDE_CODE_SESSION_ID=pm-sid
M=".polaris/handover/pm-sid/plan"
mark() { printf 'marker: %s\n' "$(tr -d '\r\n' < "$M" 2>/dev/null)"; }

echo '== 1. the first claim writes the marker =='
bash "$KIT" claim A-1 >/dev/null 2>&1; echo "claim rc=$?"
mark
echo '== 2. a beta claim while an alpha task is still active keeps alpha =='
bash "$KIT" claim B-1 >/dev/null 2>&1; echo "claim rc=$?"
mark
echo '== 3. the alpha task is done: another beta claim writes beta =='
mv ops/board/active/A-1.md ops/board/done/A-1.md
bash "$KIT" claim B-2 >/dev/null 2>&1; echo "claim rc=$?"
mark
