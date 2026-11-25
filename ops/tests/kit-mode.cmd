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

# == a JOINED project (6.22.0, ops/contracts/shared-kit.md § 1-2, hook-dispatch.md § 2 + § 6): the
# kit unpacked once into a fixture machine store, a repo whose ops/polaris is the launcher, byte for
# byte. `version` runs through the launcher; SessionStart through the store copy's dispatcher comes
# back as ONE JSON object whose context opens with the router. Source `clear`: no update / model tail.
export CLAUDE_CONFIG_DIR="$F/home/.claude" PYTHONIOENCODING=utf-8 POLARIS_PREFS=
KV="$(sed -n 's/^version: *//p' "$K/VERSION" | head -n 1)"
S="$CLAUDE_CONFIG_DIR/polaris/kit"
mkdir -p "$S/$KV"
cp -R "$W/kit/." "$S/$KV/"
printf '0 fixture\n' > "$S/$KV/.stored"
printf '%s\n' "$KV" > "$S/current"
J="$F/joined"; mkrepo "$J"
for c in backlog ready active review done blocked; do mkdir -p "$J/ops/board/$c"; done
printf 'base: main\n' > "$J/ops/CONVENTIONS.md"
cp "$K/launcher" "$J/ops/polaris"

echo '== joined: version through the launcher =='
( cd "$J" && bash ops/polaris version ) > "$F/out" 2>&1; echo "rc=$?"
if head -1 "$F/out" | grep -q "POLARIS v$KV "; then echo "   version = the store's kit: yes"; else echo "   version = the store's kit: NO"; fi
cmp -s "$J/ops/polaris" "$S/$KV/ops/launcher" && echo '   ops/polaris = the store kit'"'"'s launcher, byte-identical'
( cd "$J" && ls -A ops ) | sed 's/^/   /'

echo '== joined: SessionStart through the dispatcher =='
printf '{"session_id":"s1","source":"clear","cwd":"%s","hook_event_name":"SessionStart"}' "$J" |
  ( cd "$J" && CLAUDE_PROJECT_DIR="$J" bash "$S/$KV/ops/hooks/dispatch.sh" SessionStart ) > "$F/raw" 2>"$F/err"; echo "rc=$?"
tr -d '\r' < "$S/$KV/CLAUDE.md" > "$F/router"
python -c '
import json, sys
sys.stdout.reconfigure(newline="\n")
raw = open(sys.argv[1], encoding="utf-8").read()
o = json.loads(raw)
h = o["hookSpecificOutput"]
c = h["additionalContext"]
r = open(sys.argv[2], encoding="utf-8").read().rstrip("\n")
print("   one JSON object: " + ("yes" if list(o) == ["hookSpecificOutput"] and raw.count("\n") == 1 else "NO") + " · event " + h["hookEventName"])
print("   context opens with the router: " + ("yes" if c.startswith(r + "\n") else "NO"))
n = len(c.encode("utf-8"))
print("   context <= 9000 bytes: " + ("yes" if n <= 9000 else "NO (%d)" % n))' "$F/raw" "$F/router"
