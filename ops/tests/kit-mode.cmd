# kit-mode — the CLI runs from a kit OUTSIDE the repo (ops/contracts/doc-server.md "Executable
# checks", the Phase 4 shape): a fixture repo whose ops/ holds only STATE (board + CONVENTIONS — no
# lib/, no polaris, no roles/, no VERSION, no KEYS.tsv), the CLI run as `bash <kit>/ops/polaris` from
# inside it. version · status · role BUILDER · doc PROTOCOL "THE TOOL" · router · prefs ·
# interview --init · doc --where all succeed, and every kit file is served from the kit. The
# interview asks nothing the fixture machine file answers (voice). Then the same CLI from a
# VENDORED copy (ops/ holds the kit) says `mode: vendored`.
# HERMETIC: fixture repos and HOME under mktemp -d. check runs every golden with POLARIS_PREFS= (the
# layer off), so the machine-file cases set POLARIS_PREFS=<fixture> themselves. Live document text
# never reaches this file: only rc, first lines, keys, and byte-identity verdicts.
W="$(pwd)"
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
export HOME="$F/home" USERPROFILE="$F/home"
unset CLAUDE_CONFIG_DIR CLAUDECODE POLARIS_ROOT
K="$W/kit/ops"
mkrepo() {
  ( git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main; }
    cd "$1" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
}
R="$F/repo"; mkrepo "$R"
for c in backlog ready active review done blocked; do mkdir -p "$R/ops/board/$c"; done
printf 'base: main\n' > "$R/ops/CONVENTIONS.md"
M="$F/machine-prefs"
printf 'voice: technical   # the fixture machine answers voice\n' > "$M"
# P <cmd…> — the kit's CLI from inside the state-only repo; output kept in $F/out, rc printed
P() { ( cd "$R" && bash "$K/polaris" "$@" ) > "$F/out" 2>&1; echo "rc=$?"; }
same() { if cmp -s "$F/out" "$1"; then echo "   byte-identical to the kit's $2"; else echo "   DIFFERS from the kit's $2"; fi; }

echo '== the fixture ops/ holds only state =='
( cd "$R/ops" && ls -A ) | sed 's/^/   /'

echo '== version =='
P version
WANT="$(sed -n 's/^version: *//p' "$K/VERSION" | head -n 1)"
if head -1 "$F/out" | grep -q "POLARIS v$WANT "; then echo "   version = the kit's VERSION: yes"; else echo "   version = the kit's VERSION: NO"; fi

echo '== status =='
P status
head -1 "$F/out" | sed 's/^/   /'

echo '== role BUILDER =='
P role BUILDER
same "$K/roles/BUILDER.md" roles/BUILDER.md

echo '== doc PROTOCOL "THE TOOL" =='
P doc PROTOCOL "THE TOOL"
head -1 "$F/out" | sed 's/^/   /'

echo '== router =='
P router
head -1 "$F/out" | sed 's/^/   /'

echo '== prefs (fixture machine file) =='
( cd "$R" && POLARIS_PREFS="$M" bash "$K/polaris" prefs ) > "$F/out" 2>&1; echo "rc=$?"
awk -F'\t' 'NR == 1 || $1 == "voice" || $1 == "base"' "$F/out" | sed 's/^/   /'

echo '== interview --init (fixture machine file) =='
( cd "$R" && POLARIS_PREFS="$M" bash "$K/polaris" interview --init ) > "$F/out" 2>&1; echo "rc=$?"
grep '^ANSWERED' "$F/out" | sed 's/^/   /'
printf '   questions for voice: %s\n' "$(grep -c "^QUESTION$(printf '\t')voice$(printf '\t')" "$F/out")"
echo '== interview --init (layer off: voice is asked) =='
P interview --init
printf '   questions for voice: %s\n' "$(grep -c "^QUESTION$(printf '\t')voice$(printf '\t')" "$F/out")"

echo '== doc --where =='
P doc --where
sed "s#^kit: .*#kit: <kit>#" "$F/out" | sed 's/^/   /'
KP="$(cd "$K" && pwd -P)"
if [ "$(sed -n 's/^kit: //p' "$F/out")" = "$K" ] || [ "$(cd "$(sed -n 's/^kit: //p' "$F/out")" 2>/dev/null && pwd -P)" = "$KP" ]; then
  echo '   kit = the kit outside the repo: yes'; else echo '   kit = the kit outside the repo: NO'; fi

echo "== the fixture ops/ still holds only state =="
( cd "$R/ops" && ls -A ) | sed 's/^/   /'

echo '== a vendored copy =='
V="$F/vend"; mkrepo "$V"
mkdir -p "$V/ops"
cp -R "$K/." "$V/ops/"
for c in backlog ready active review done blocked; do mkdir -p "$V/ops/board/$c"; done
printf 'base: main\n' > "$V/ops/CONVENTIONS.md"
( cd "$V" && bash ops/polaris doc --where ) > "$F/out" 2>&1; echo "rc=$?"
sed "s#^kit: .*#kit: <kit>#" "$F/out" | sed 's/^/   /'
( cd "$V" && bash ops/polaris role BUILDER ) > "$F/out" 2>&1; echo "rc=$?"
same "$K/roles/BUILDER.md" roles/BUILDER.md
