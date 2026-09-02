# The keep-awake hook's ONE hard contract is SILENCE. `start busy idle end` run as Claude Code hooks:
# a byte on UserPromptSubmit's stdout is injected into the model's context, and rc 2 on Stop tells the
# harness to keep going. So the live path is asserted the only way that means anything — stdout
# BYTE-COUNTED at zero and the rc printed, for all four. The `--test` twin keeps stdout so a golden
# can read one pinned line per subcommand; those words are what the drill and the humans read, so they
# are pinned here verbatim (ops/contracts/keep-awake.md § `--test`).
#
# HERMETIC AND KEY-PRESS-FREE BY CONSTRUCTION: POLARIS_AWAKE_HOME points at a mktemp registry, so the
# owner's real ~/.claude/polaris/awake is never even created; POLARIS_AWAKE_PRESSER replaces the
# presser wholesale, so no synthetic key ever reaches a real desktop; POLARIS_AWAKE_SPAWN=inline and a
# freshly stamped daemon/beat mean no daemon is ever forked (only `--test tick` runs, and that is one
# verdict pass that never sleeps and never spawns) — the absence is asserted at the end, not assumed.
# CLAUDE_PID is unset so line 3 of every session file is the deterministic `-`; a live pid would be
# the one machine-specific byte the hook writes that carries no contract.
H="$(pwd)/kit/ops/hooks/awake-hook.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/repo" "$FIX/tx"
export POLARIS_AWAKE_HOME="$FIX/awake"
export POLARIS_AWAKE_PRESSER="touch \"$FIX/pressed\""
export POLARIS_AWAKE_SPAWN=inline
export POLARIS_AWAKE_TICK=1
export POLARIS_AWAKE_GRACE=1
unset CLAUDE_PID
A="$FIX/awake"
# The registry root and the fixture root are the only machine-specific bytes in this run. Normalize
# exactly those two and diff everything else verbatim, so the printed words stay locked.
N() { sed -e "s#$FIX/awake#<home>#g" -e "s#$FIX#<fix>#g"; }
J() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s"}' "$1" "$2" "$3" "$4"; }
T() { J s1 "$TP" "$WT" "$1" | bash "$H" --test "$2"; }
S() { # the session file the hook just wrote, one labelled line at a time, the epoch normalized
  { n=0
    while IFS= read -r l; do n=$((n+1)); printf 'sessions/s1 line %s: %s\n' "$n" "$l"; done < "$A/sessions/s1"
  } | sed -e 's/: busy [0-9][0-9]*$/: busy <epoch>/' -e 's/: idle [0-9][0-9]*$/: idle <epoch>/' | N
}
# A cwd under /.polaris/wt/ names its primary fork-free — no git, no repo, still the real code path.
WT="$FIX/repo/.polaris/wt/T-999"
# The transcript_path Claude Code sends on Windows is JSON-escaped: every separator arrives as \\ and
# jstr has to give back single backslashes or the daemon's beat reads a path that does not exist.
TP='C:\\Users\\dev\\.claude\\projects\\demo\\s1.jsonl'

echo '== SessionStart creates the session as idle, and decodes the escaped Windows transcript_path =='
T SessionStart start
S

echo '== UserPromptSubmit marks it busy, rewrites lines 2-4 and registers the repo behind the cwd =='
TP="$FIX/tx/s1.jsonl"; : > "$TP"          # a REAL transcript from here on: its mtime IS the beat
T UserPromptSubmit busy
S
for f in "$A"/repos/*; do
  [ -f "$f" ] || continue
  printf 'repos/%s: %s\n' "${f##*/}" "$(cat "$f")"
done | sed 's#^repos/[0-9][0-9]*:#repos/<cksum>:#' | N

echo '== a second SessionStart (compact, resume) KEEPS the session — it never downgrades busy =='
T SessionStart start

echo '== tick: one verdict pass, at most one press, and the presser word lands in daemon/last-press =='
bash "$H" --test tick
printf 'presser side-effect: %s\n' "$( [ -f "$FIX/pressed" ] && echo yes || echo no )"
printf 'daemon/last-press: %s\n' "$(cat "$A/daemon/last-press")"

echo '== the disabled flag: the verdict is still reached and logged, the press never happens =='
touch "$A/disabled"                        # empty, so the 3600s expiry in ah_tick cannot reap it here
bash "$H" --test tick
printf 'daemon/last-press: %s\n' "$(cat "$A/daemon/last-press")"
rm -f "$A/disabled"

echo '== every session idle and its transcript cold: quiet, and nothing is pressed at all =='
T Stop idle
touch -t 200001010000 "$TP"                # beat older than the idle stamp — the one quiet condition
bash "$H" --test tick

echo '== SessionEnd forgets the session outright =='
T SessionEnd end

echo '== the registry this run built, paths normalized =='
( cd "$A" && find . -mindepth 1 | LC_ALL=C sort ) \
  | sed -e 's#^\./#<home>/#' -e 's#^<home>/repos/[0-9][0-9]*$#<home>/repos/<cksum>#'

echo '== THE LIVE PATH: zero bytes on stdout and rc 0, for every one of the four =='
for s in start busy idle end; do
  date +%s > "$A/daemon/beat"              # fresh: ah_spawn has nothing to do, so `busy` forks nothing
  J s2 "$FIX/tx/s2.jsonl" "$WT" Live | bash "$H" "$s" > "$FIX/live.out" 2>/dev/null; rc=$?
  printf 'live %-5s rc %s  live-stdout-bytes: %s\n' "$s" "$rc" "$(wc -c < "$FIX/live.out" | tr -d ' ')"
done
printf 'daemon/hook.log (the live path stderr sink): %s\n' "$( [ -f "$A/daemon/hook.log" ] && echo present || echo absent )"
printf 'daemon lock: %s\n' "$( [ -d "$A/lock" ] && echo present || echo absent )"
printf 'daemon/pid: %s\n' "$( [ -f "$A/daemon/pid" ] && echo present || echo absent )"
