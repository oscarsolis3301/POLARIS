# update-registry — T-316 (ops/contracts/smooth.md § 6): the channel is asked when it matters, and the
# machine registry walk tidies what it reads.
# The channel: update_latest writes `epoch: <unix seconds>` beside `checked:` and `latest:`; `update
# --auto` re-asks a same-day cache whose latest IS the installed version once that answer is an hour
# old (or carries no epoch — a 6.18 cache), and never otherwise; a typed `update --all` runs every child
# with POLARIS_UPDATE_FORCE=1, so it asks the channel even over a fresh same-day answer.
# The walk, per entry in this order: gone → removed · the same folder as an earlier entry once case and
# slashes are folded → removed, naming the first · a worktree (`.git` is a file) → skipped · no
# ops/VERSION → removed · self-hosting → skipped · else the update.
#
# HERMETIC: throwaway folders under ONE mktemp -d, a fake HOME/USERPROFILE, a registry under
# POLARIS_AWAKE_HOME and a file:// channel (curl on Windows needs file:///C:/…, hence cygpath -m). The
# project is at 0.0.1 with a card in active/, so a newer channel answer prints `skipped: active: 1`
# and never installs anything: that line is the proof the channel was asked. Epochs are set relative
# to now with a wide margin; the folder prints as <fix>.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT POLARIS_UPDATE_FORCE POLARIS_AWAKE_HOME
U="$FIX"; command -v cygpath >/dev/null 2>&1 && U="/$(cygpath -m "$FIX")"
mkdir -p "$FIX/chan"; printf 'version: 0.0.2\n' > "$FIX/chan/VERSION"
P="$FIX/proj"
( set -e
  git init -q -b main "$P" 2>/dev/null || { git init -q "$P"; git -C "$P" symbolic-ref HEAD refs/heads/main; }
  cd "$P"
  git config user.email t@t; git config user.name t
  mkdir -p ops/lib; printf '.polaris/\n' > .gitignore; printf '# the kit, as installed\n' > ops/polaris
  printf 'version: 0.0.1\nchannel: file://%s/chan/VERSION\ntarball: file://%s/no-such.tgz\n' "$U" "$U" > ops/VERSION
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  git worktree add -q "$FIX/proj-wt" -b lane
) >/dev/null 2>&1
cd "$P"
printf -- '---\nid: T-A1\npoints: 1\nstatus: active\n---\n' > ops/board/active/T-A1.md
NOW="$(date +%s)"; TODAY="$(date +%Y-%m-%d)"
C=.polaris/update-cache
M() { sed "s#$FIX#<fix>#g"; }
CACHE() { # CACHE <latest> [epoch|-] — a same-day cache; `-` writes no epoch line (a 6.18 cache)
  mkdir -p .polaris
  { printf 'checked: %s\nlatest: %s\n' "$TODAY" "$1"; [ "${2:--}" = - ] || printf 'epoch: %s\n' "$2"; } > "$C"
}
AUTO() { # AUTO <label> — one `update --auto --say`, then what the cache says now
  out="$(bash "$KIT" update --auto --say 2>&1)"
  printf '%s\n   said:  %s\n   cache: %s\n' "$1" "${out:-(silent)}" \
    "$(awk -v n="$NOW" '/^latest:/ { l = $2 } /^epoch:/ { e = ($2 >= n - 5 && $2 <= n + 600) ? "epoch now" : "epoch old" }
         END { print "latest " l " · " (e == "" ? "no epoch" : e) }' "$C")"
}

echo '--- 1. the channel: when --auto asks again'
CACHE 0.0.1 "$NOW";                  AUTO 'same version, asked a minute ago: the cache answers'
CACHE 0.0.1 "$(( NOW - 7200 ))";     AUTO 'same version, asked two hours ago: asked again'
CACHE 0.0.1 -;                       AUTO 'same version, no epoch (a 6.18 cache): asked again'
CACHE 0.0.0 "$(( NOW - 7200 ))";     AUTO 'another version, two hours old: the cache answers'
rm -f "$C"; bash "$KIT" update --auto >/dev/null 2>&1
awk '{ sub(/:.*/, "") } { k = k " " $0 } END { print "a fresh write holds:" k }' "$C"

echo '--- 2. the walk: a typed update --all asks the channel itself, and tidies the registry'
R="$FIX/awake/repos"; mkdir -p "$R" "$FIX/empty" "$FIX/self/kit/ops" "$FIX/self/ops"
: > "$FIX/self/kit/ops/pack.py"; printf 'version: 0.0.1\n' > "$FIX/self/ops/VERSION"
[ -d "$FIX/PROJ" ] || ln -s proj "$FIX/PROJ"      # a case-sensitive disk: the second spelling made real
printf '%s\n' "$P"           > "$R/1-proj"
printf '%s\r\n' "$FIX/PROJ"  > "$R/2-dup"          # a CR from a Windows editor is tolerated
printf '%s\n' "$FIX/proj-wt" > "$R/3-wt"
printf '%s\n' "$FIX/empty"   > "$R/4-empty"
printf '%s\n' "$FIX/gone"    > "$R/5-gone"
printf '%s\n' "$FIX/self"    > "$R/6-self"
CACHE 0.0.1 "$NOW"
POLARIS_AWAKE_HOME="$FIX/awake" bash "$KIT" update --all 2>&1 | M
echo "registry now: $(ls "$R" | tr '\n' ' ')"
echo '--- 3. the same walk again: nothing left to tidy'
POLARIS_AWAKE_HOME="$FIX/awake" bash "$KIT" update --all 2>&1 | M
