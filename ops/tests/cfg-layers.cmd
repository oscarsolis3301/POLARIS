# cfg-layers — `cfg` reads a repo's ops/CONVENTIONS.md line, else this computer's preferences file,
# else the code default, for the allowlisted person-level keys only (ops/contracts/machine-prefs.md
# § 2-3, "Executable checks"). Sourced straight from kit/ops/lib/core.sh, on throwaway files:
#   1. repo > machine > default, and a blank repo line falls through to the machine line
#   2. the autonomy mask: a repo `autonomy: standard` hides a machine `plan_gate: auto` — also with a
#      blank `plan_gate:` line ABOVE the autonomy line; a key outside the trio is not masked
#   3. a machine line for a `repo` key (base, test) is ignored
#   4. a CRLF machine file; a machine path holding a backslash (the Windows form) through ARGV
#   5. POLARIS_PREFS= (set, empty) = the layer is off; no CONVENTIONS + a machine file → the machine value
#   6. POLARIS_PREFS unset → $POLARIS_HOME/preferences, which honours CLAUDE_CONFIG_DIR
# HERMETIC: every machine file is a fixture under mktemp -d; HOME is faked before core.sh is sourced,
# so the owner's real ~/.claude/polaris/preferences is never read.
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
export HOME="$F/home" USERPROFILE="$F/home"
unset CLAUDE_CONFIG_DIR
. kit/ops/lib/core.sh
c() { printf '%s = %s\n' "$1" "$(cfg "$1" "$2")"; }
printf 'voice: technical\nlanding:   # blank, falls through\nbase: trunk\n' > "$F/conv"
printf '# machine fixture\nvoice: standard\nlanding: integrator\ndrain: on\nplan_gate: auto\nbase: elsewhere\ntest: echo machine\n' > "$F/prefs"
export POLARIS_PREFS="$F/prefs" CONV="$F/conv"

echo '== 1. repo > machine > default =='
c voice standard
c landing self
c drain off
c run_max_tasks 7

echo '== 2. the autonomy mask =='
c plan_gate ask
printf 'autonomy: standard\nvoice: technical\n' > "$F/conv"
c plan_gate ask
c drain off
printf 'plan_gate:\nautonomy: standard\n' > "$F/conv"
c plan_gate ask
printf 'autonomy:   # blank, no mask\n' > "$F/conv"
c plan_gate ask

echo '== 3. a machine line for a repo key is ignored =='
printf 'voice: technical\n' > "$F/conv"
c base main
c test none

echo '== 4. CRLF machine file · a backslash path =='
awk '{ printf "%s\r\n", $0 }' "$F/prefs" > "$F/prefs-crlf"
POLARIS_PREFS="$F/prefs-crlf" c landing self
POLARIS_PREFS="$F/prefs-crlf" c drain off
W="$(cygpath -w "$F/prefs" 2>/dev/null)" || W=""
if [ -z "$W" ]; then mkdir -p "$F/t\\tab"; cp "$F/prefs" "$F/t\\tab/prefs"; W="$F/t\\tab/prefs"; fi
case "$W" in *\\*) echo 'the path holds a backslash: yes';; *) echo 'the path holds a backslash: no';; esac
POLARIS_PREFS="$W" c drain off

echo '== 5. the layer off · no CONVENTIONS =='
POLARIS_PREFS= c drain off
POLARIS_PREFS= c voice standard
CONV="$F/no-such-conv" c drain off
CONV="$F/no-such-conv" c base main
POLARIS_PREFS= CONV="$F/no-such-conv" c drain off

echo '== 6. POLARIS_PREFS unset → POLARIS_HOME =='
mkdir -p "$F/home/.claude/polaris" "$F/cfgdir/polaris"
printf 'drain: home\n' > "$F/home/.claude/polaris/preferences"
printf 'drain: configdir\n' > "$F/cfgdir/polaris/preferences"
( unset POLARIS_PREFS; . kit/ops/lib/core.sh; c drain off )
( unset POLARIS_PREFS; export CLAUDE_CONFIG_DIR="$F/cfgdir"; . kit/ops/lib/core.sh; c drain off )

echo '== 7. kit_file: the repo copy first, else the kit beside the CLI =='
export OPS="$F/repo-ops" OPS_DIR="$(pwd)/kit/ops"
mkdir -p "$OPS"
w() { case "$(kit_file "$1")" in "$OPS/$1") echo "$1: repo";; "$OPS_DIR/$1") echo "$1: kit";; *) echo "$1: ?";; esac; }
w KEYS.tsv; w roles
mkdir -p "$OPS/roles"; printf 'k\t1\t-\t-\t\tmachine\n' > "$OPS/KEYS.tsv"
w KEYS.tsv; w roles; w no-such-file
rm -rf "$OPS/roles" "$OPS/KEYS.tsv"

echo '== 8. prefs_put =='
P="$F/home/.claude/polaris/put/preferences"
show() { tr -d '\r' < "$P" | sed 's/^/   | /'; }
r() { "$@" && echo "rc=0" || echo "rc=$?"; }
POLARIS_PREFS= r prefs_put voice technical
export POLARIS_PREFS="$P"
r prefs_put base trunk
r prefs_put no_such_key x
echo "a file after refusals: $([ -e "$P" ] && echo yes || echo no)"
r prefs_put voice technical
show
printf 'drain: off   # my note\nvoice: standard' > "$P"
r prefs_put drain on
r prefs_put voice 'C:\x'
r prefs_put claim claim-branch
show
CONV="$F/no-such-conv" c drain off
echo "temp files left: $(ls -a "${P%/*}" | grep -c polaris-tmp || true)"

echo '== 9. the allowlist literal == KEYS.tsv machine rows =='
sed -n 's/^ *ok = index(" \(.*\) ", " " k " ")$/\1/p' kit/ops/lib/core.sh | tr ' ' '\n' | LC_ALL=C sort > "$F/lit"
awk -F'\t' '!/^#/ && NF > 0 && $6 == "machine" { print $1 }' kit/ops/KEYS.tsv | LC_ALL=C sort > "$F/rows"
echo "literal: $(grep -c . "$F/lit") · machine rows: $(grep -c . "$F/rows") · same: $(cmp -s "$F/lit" "$F/rows" && echo yes || echo no)"
echo "seed rows: $(awk -F'\t' '!/^#/ && NF > 0 && $6 == "seed" { printf "%s%s", sep, $1; sep = " " }' kit/ops/KEYS.tsv)"
echo "rows not 6 fields: $(awk -F'\t' '!/^#/ && NF > 0 && NF != 6' kit/ops/KEYS.tsv | grep -c . || true)"

echo '== 10. the zero-touch keys (shared-kit.md § 9) ride the machine layer =='
printf 'auto_setup: auto\nowners: me,them\n' > "$F/zt"
printf 'voice: technical\n' > "$F/conv"
POLARIS_PREFS="$F/zt" CONV="$F/conv" c auto_setup ask
POLARIS_PREFS="$F/zt" CONV="$F/conv" c owners ''
POLARIS_PREFS= CONV="$F/conv" c auto_setup ask
