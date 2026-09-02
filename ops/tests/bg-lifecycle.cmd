# `bg` is how a session survives the harness's 600s tool cap (ops/contracts/bg-jobs.md): run
# detached, keep working, collect in bounded chunks. Its PUBLIC contract is the exit code — 0 green
# · 1 red · 2 running · 3 unknown — because every caller branches on it blind, inside compound
# commands, with nobody reading the prose. A verdict that silently flips is a builder handing off
# red work, so the rc of every form is asserted here, not the wording alone.
#
# HERMETIC BY CONSTRUCTION (the T-062 pattern): fixture repo, CLI run from INSIDE it, so the job
# registry created below lives under the FIXTURE's .polaris/bg — never this repo's. FAST COMMANDS
# ONLY (true/false/echo/sleep 8, small --max): a golden that runs on every `check` may never wait
# on a real suite. Total runtime is seconds; `sleep 8` is the one deliberate wait, and it is 8 and
# not 3 on purpose — the rc-2 and duplicate-refusal probes each pay a fresh CLI startup (~0.7s,
# more on a loaded box), and a job that finishes early turns rc 2 into rc 0 and reds this golden
# forever. Margin is cheaper than a flake.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
# Pids, wall-clock durations and the registry's absolute path are the only machine-specific bytes
# bg emits; everything else is contract. Normalize exactly those three and diff the rest verbatim,
# so the ⛔/✅ markers, the remedy commands and the three-space notes all stay locked.
N() { sed -e 's#[^ ]*/\.polaris/bg/#<reg>/#g' -e 's/pid [0-9][0-9]*/pid <pid>/g' -e 's/ in [0-9][0-9]*[smh]/ in <dur>/g' -e 's/ · [0-9][0-9]*[smh] · / · <age> · /g'; }
B() {
  printf 'bg %s\n' "$*"
  out="$( cd "$FIX/repo" && bash "$KIT" bg "$@" 2>&1 )"; rc=$?
  if [ -n "$out" ]; then printf '%s\n' "$out" | N; else echo '(no output)'; fi
  printf 'rc %s\n' "$rc"
}

echo '== an empty registry is silent, never an error =='
B status

echo '== green: run · wait · status · tail =='
B run ok -- echo hello-bg
B wait ok --max 30
B status ok
B tail ok

echo '== red is HONEST: the job rc propagates to wait and status =='
B run nope -- false
B wait nope --max 30
B status nope

echo '== running: rc 2, and a same-name run REFUSES instead of racing =='
B run slow -- sleep 8
B status slow
B run slow -- true
B wait slow --max 30

echo '== rotation ARCHIVES the finished run into its ONE .prev slot =='
B run ok -- echo second-run
test -d "$FIX/repo/.polaris/bg/ok.prev" && echo 'ok.prev exists: yes' || echo 'ok.prev exists: NO'
printf 'ok.prev/cmd: '; cat "$FIX/repo/.polaris/bg/ok.prev/cmd"
printf 'ok/cmd:      '; cat "$FIX/repo/.polaris/bg/ok/cmd"
B wait ok --max 30

echo '== unknown: no rc file and a dead pid is rc 3, never a fabricated verdict =='
# A REAPED child's pid is dead by construction — the honest way to stage the case bg cannot solve,
# only order around (rc-file-first). No sleeping, no guessed pid number.
( exit 0 ) & GHOST=$!
wait "$GHOST" 2>/dev/null || true
mkdir -p "$FIX/repo/.polaris/bg/ghost"
printf '%s\n' "$GHOST" > "$FIX/repo/.polaris/bg/ghost/pid"
printf 'true\n'        > "$FIX/repo/.polaris/bg/ghost/cmd"
date +%s               > "$FIX/repo/.polaris/bg/ghost/start"
: > "$FIX/repo/.polaris/bg/ghost/log"
B status ghost

echo '== the bare listing: one line per live job, .prev archives skipped =='
( cd "$FIX/repo" && bash "$KIT" bg status 2>&1 ) \
  | awk -F'\t' 'NF==3 { printf "%s\t%s\t<age>\n", $1, $2; next } { print }'

echo '== refusals: the name grammar, and a job that was never started =='
B run bad/name -- true
B status never-ran
B tail ok -n 1

echo '== a same-name job from ANOTHER cwd is refused, --force included =='
# The exact case v1 got wrong: repo/src and repo resolve to the SAME primary, so both sessions see
# ONE registry — and the second `bg run own` used to rotate the live job away, with --force killing
# a pid Windows may already have handed to somebody else. Ownership is the job's cwd (bg-jobs.md
# v2), so from the repo root the subdir's live job is untouchable, --force included. $FIX is the
# fourth machine-specific byte bg emits here (the owner's cwd), so it normalizes like the others.
printf 'bg run own -- sleep 8   [started from repo/src]\n'
out="$( cd "$FIX/repo/src" && bash "$KIT" bg run own -- sleep 8 2>&1 )"; rc=$?
printf '%s\n' "$out" | N
printf 'rc %s\n' "$rc"
B run own -- true         | sed "s#$FIX#<fix>#g"
B run own --force -- true | sed "s#$FIX#<fix>#g"
B wait own --max 30

echo '== a third run archives the old .prev instead of deleting it =='
B run ok -- echo third-run
printf 'archived ok-*: '; ls "$FIX/repo/.polaris/bg/.archive" | grep -c '^ok-'
printf 'ok.prev/cmd: '; cat "$FIX/repo/.polaris/bg/ok.prev/cmd"
