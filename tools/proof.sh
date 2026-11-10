#!/usr/bin/env bash
# tools/proof.sh — one command proves ONE commit, HEAD (ops/contracts/minutes.md § 2).
# This repo's own tool: it never ships in the kit.
#
#   bash tools/proof.sh                 CI judges the self-test on Linux while the goldens run here
#   bash tools/proof.sh --await <job>   wait for one more job of the recorded run
#   bash tools/proof.sh --report        one line per job of the recorded run
#
# Seams (the golden proof-ci uses every one): PROOF_GH (default gh) · PROOF_GOLDENS (the command that
# runs ONE golden, given its name; default: one `bash kit/ops/polaris check` for all) · PROOF_SELFTEST (the
# no-CI self-test command) · PROOF_POLL (job poll, default 15 s) · PROOF_FIND_POLL (run-id poll,
# default 5 s). bash 3.2-safe: no arrays, no `case` inside $(...), no ${v,,}, no wait -n.
GH="${PROOF_GH:-gh}"
POLL="${PROOF_POLL:-15}"
FIND_POLL="${PROOF_FIND_POLL:-5}"
FIND_MAX=90
JOB_MAX=1200

top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "⛔ proof: not inside a git repo"; exit 1; }
cd "$top" || exit 1
sha="$(git rev-parse HEAD)" || exit 1
s7="${sha:0:7}"
br="proof/${sha:0:12}"
STATE=".polaris/ci-proof"

# run_id: the newest CI run for this commit, or nothing
run_id() {
  local id
  id="$("$GH" run list --workflow ci.yml --commit "$sha" --json databaseId --jq '.[0].databaseId' 2>/dev/null | tr -d ' \r\n')"
  case "$id" in ''|null|*[!0-9]*) return 1;; esac
  printf '%s\n' "$id"
}

# job_state <id> <job>: "<status> <conclusion>" of that job, or nothing
job_state() {
  "$GH" run view "$1" --json jobs --jq ".jobs[] | select(.name==\"$2\") | \"\(.status) \(.conclusion)\"" 2>/dev/null | tr -d '\r' | head -1
}

# await_job <id> <job>: 0 green · 1 red · 3 no answer in time
await_job() {
  local st end=$((SECONDS + JOB_MAX))
  while :; do
    st="$(job_state "$1" "$2")"
    case "$st" in
      "completed success") return 0;;
      completed*) return 1;;
    esac
    [ "$SECONDS" -ge "$end" ] && return 3
    sleep "$POLL"
  done
}

# recorded_id: the run id of .polaris/ci-proof when it names HEAD
recorded_id() {
  local s i
  [ -f "$STATE" ] || return 1
  read -r s i < "$STATE" || [ -n "$s" ] || return 1
  [ "$s" = "$sha" ] && [ -n "$i" ] || return 1
  printf '%s\n' "$i"
}

no_record() { echo "⛔ proof: no recorded run for $s7 — run tools/proof.sh first"; exit 1; }

case "${1:-}" in
  --await)
    job="${2:-}"; [ -n "$job" ] || { echo "usage: bash tools/proof.sh [--await <job> | --report]"; exit 2; }
    id="$(recorded_id)" || no_record
    await_job "$id" "$job"; r=$?
    if [ "$r" -eq 0 ]; then echo "proof: $job — green"; exit 0; fi
    if [ "$r" -eq 1 ]; then echo "proof: $job — RED"; exit 1; fi
    echo "proof: $job — no answer after 20 minutes"; exit 1;;
  --report)
    id="$(recorded_id)" || no_record
    "$GH" run view "$id" --json jobs --jq '.jobs[] | "\(.name): \(.status) \(.conclusion)"' 2>/dev/null | tr -d '\r'
    exit 0;;
  '') ;;
  *) echo "usage: bash tools/proof.sh [--await <job> | --report]"; exit 2;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- CI half: find or start -------------------------------------------------------------------
why=""
id=""
if ! command -v "$GH" >/dev/null 2>&1; then why="gh not found"
elif ! "$GH" auth status >/dev/null 2>&1; then why="gh not signed in"
elif ! git remote get-url origin >/dev/null 2>&1; then why="no origin remote"
elif id="$(run_id)"; then echo "proof: $s7 — CI run $id (found)"
else
  id=""
  for ref in $(git ls-remote --heads origin 'proof/*' 2>/dev/null | awk '{print $2}'); do
    name="${ref#refs/heads/}"
    [ "$name" = "$br" ] && continue
    # Another lane may be proving right now: a proof branch goes only once ITS run has finished.
    # Deleted earlier, that lane's CI jobs fail at checkout and its proof reads red for nothing.
    ost="$("$GH" run list --workflow ci.yml --branch "$name" --limit 1 --json status --jq '.[0].status' 2>/dev/null || true)"
    [ "$ost" = "completed" ] || continue
    git push -q origin --delete "$name" >/dev/null 2>&1 || true
  done
  if ! git push -q origin "$sha:refs/heads/$br" >/dev/null 2>&1; then why="the push failed"
  elif ! "$GH" workflow run ci.yml --ref "$br" >/dev/null 2>&1; then why="the dispatch failed"
  else
    end=$((SECONDS + FIND_MAX))
    while :; do
      id="$(run_id)" && break
      id=""
      [ "$SECONDS" -ge "$end" ] && break
      sleep "$FIND_POLL"
    done
    if [ -n "$id" ]; then echo "proof: $s7 — CI run $id (started)"; else why="no run id after 90 s"; fi
  fi
fi

if [ -n "$why" ]; then
  echo "proof: no CI here ($why) — running the self-test on this machine"
  ( eval "${PROOF_SELFTEST:-bash kit/ops/polaris doctor --selftest --parallel 3}" > "$TMP/selftest.out" 2>&1
    echo $? > "$TMP/selftest.rc" ) &
  stpid=$!
fi

# ---- goldens half, meanwhile ------------------------------------------------------------------
# Default: ONE `check` call runs them side by side (minutes.md § 6); its ⛔ lines name the red ones.
# PROOF_GOLDENS (the seam) still runs one golden per call, 12 at a time.
mkdir -p "$TMP/g"
names=""
for f in ops/tests/*.cmd; do
  [ -e "$f" ] || break
  n="${f##*/}"; names="$names ${n%.cmd}"
done
total=0; red=0; rednames=""
if [ -z "${PROOF_GOLDENS:-}" ]; then
  bash kit/ops/polaris check > "$TMP/g/check.out" 2>&1; crc=$?
  for n in $names; do total=$((total + 1)); done
  rednames="$(awk '/^⛔ [^ ]+ — / { printf " %s", $2 }' "$TMP/g/check.out")"
  for n in $rednames; do red=$((red + 1)); done
  [ "$crc" -ne 0 ] && [ "$red" -eq 0 ] && { red=1; rednames=" check"; }
  for n in $rednames; do
    awk -v n="$n" '/^(✅|⛔) / { on = ($2 == n) } /^⛔ check: / { on = 0 } on' "$TMP/g/check.out" > "$TMP/g/$n.out"
  done
else
  export P_RUN="$PROOF_GOLDENS" P_DIR="$TMP/g"
  [ -n "$names" ] && printf '%s\n' $names | xargs -n 1 -P 12 bash -c \
    'eval "$P_RUN \"\$1\"" > "$P_DIR/$1.out" 2>&1; echo $? > "$P_DIR/$1.rc"' _
  for n in $names; do
    total=$((total + 1))
    rc="$(cat "$TMP/g/$n.rc" 2>/dev/null)"
    [ "$rc" = "0" ] || { red=$((red + 1)); rednames="$rednames $n"; }
  done
fi
ok=1
if [ "$red" -eq 0 ]; then echo "proof: goldens — $total green"
else
  ok=0
  echo "proof: goldens — $red red:$rednames"
  for n in $rednames; do cat "$TMP/g/$n.out" 2>/dev/null; done
fi

# ---- wait for the first half ------------------------------------------------------------------
if [ -n "$why" ]; then
  wait "$stpid"
  if [ "$(cat "$TMP/selftest.rc" 2>/dev/null)" = "0" ]; then echo "proof: self-test — green"
  else ok=0; echo "proof: self-test — RED"; tail -n 40 "$TMP/selftest.out"; fi
else
  await_job "$id" ubuntu-latest; r=$?
  if [ "$r" -eq 0 ]; then echo "proof: linux — green"
  elif [ "$r" -eq 1 ]; then
    ok=0; echo "proof: linux — RED"
    "$GH" run view "$id" --log-failed 2>/dev/null | tail -n 40
  else ok=0; echo "proof: linux — no answer after 20 minutes"; fi
  mkdir -p .polaris
  echo "$sha $id" > "$STATE"
fi

if [ "$ok" -eq 1 ]; then echo "✅ proof: $s7 green"; exit 0; fi
echo "⛔ proof: $s7 red"; exit 1
