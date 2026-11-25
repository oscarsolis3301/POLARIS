# store-launcher — the kit store and the project launcher (ops/contracts/shared-kit.md § 1, § 2).
# store.sh: put (sha256 checked, unpacked with the polaris-v5/ folder hoisted, the zip kept beside,
# `.stored` last), an existing complete version kept, a tampered zip refused, the unzip fallback,
# neither unpacker, flip, ver (a bad `current` reads as nothing), prune. The launcher: its two first
# lines, no `$(`/backtick/pipe in its code, the real kit run through it from a state-only repo
# (`version`), a stub kit with PATH emptied (it still dispatches: builtins only), a bad `current`,
# no store (exit 127 + the exact line), CLAUDE_CONFIG_DIR wins over HOME, and CI with and without
# ops/KIT (POLARIS_KIT_SRC stands in for the download; the sha256 still binds).
# HERMETIC: everything under one mktemp -d; HOME, USERPROFILE and CLAUDE_CONFIG_DIR are fakes, CI and
# POLARIS_BOOTSTRAP set or unset per case (GitHub Actions exports CI=true to every step). Fixture
# zips are built here with python zipfile; nothing touches the network or the real ~/.claude.
W="$(pwd)"
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
export HOME="$F/home" USERPROFILE="$F/home" PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
unset CLAUDE_CONFIG_DIR CLAUDECODE POLARIS_ROOT POLARIS_LAUNCHER POLARIS_KIT_SRC CI POLARIS_BOOTSTRAP
mkdir -p "$HOME"
PH="$HOME/.claude/polaris"
K="$PH/kit"
B="$BASH"

# fixture zips: real.zip = this tree's kit/ in the release shape (polaris-v5/<path> + __main__.py);
# stub-<v>.zip = a stub CLI that says who ran it, plus the real store.sh (the CI bootstrap sources it)
python - "$W/kit" "$F" <<'PY'
import os, sys, zipfile
kit, out = sys.argv[1], sys.argv[2]
def add(z, name, blob, mode=0o644):
    i = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    i.create_system = 3
    i.external_attr = (0o100000 | mode) << 16
    z.writestr(i, blob)
with zipfile.ZipFile(os.path.join(out, "real.zip"), "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(kit):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for f in files:
            p = os.path.join(root, f)
            rel = os.path.relpath(p, kit).replace(os.sep, "/")
            add(z, "polaris-v5/" + rel, open(p, "rb").read().replace(b"\r\n", b"\n"),
                0o755 if rel in ("ops/polaris", "ops/install.sh") else 0o644)
    add(z, "__main__.py", open(os.path.join(kit, "ops", "bootstrap.py"), "rb").read())
store = open(os.path.join(kit, "ops", "lib", "store.sh"), "rb").read().replace(b"\r\n", b"\n")
for v in ("1.0.0", "1.1.0", "2.0.0"):
    stub = ("printf 'stub kit %s ran: %%s\\n' \"$*\"\n"
            "printf '   launcher: %%s\\n' \"${POLARIS_LAUNCHER:-<unset>}\"\n"
            "case \"${BASH_SOURCE[0]}\" in \"$0\") echo '   sourced: no' ;; *) echo '   sourced: yes' ;; esac\n") % v
    with zipfile.ZipFile(os.path.join(out, "stub-%s.zip" % v), "w") as z:
        add(z, "polaris-v5/ops/polaris", stub.encode(), 0o755)
        add(z, "polaris-v5/ops/lib/store.sh", store)
        add(z, "polaris-v5/.claude/settings.json", b"{}\n")
        add(z, "polaris-v5/CLAUDE.md", b"# stub\n")
        add(z, "__main__.py", b"print('stub')\n")
PY
cp "$F/stub-1.0.0.zip" "$F/tampered.zip"; printf 'x' >> "$F/tampered.zip"

# ST '<shell code>' — store.sh sourced into a fresh bash with the fake POLARIS_HOME; rc printed
ST() { POLARIS_HOME="$PH" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; $1" 2>&1; echo "   rc=$?"; }
SHA() { POLARIS_HOME="$PH" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; _sha256 \"\$1\"" _ "$1"; }
S10="$(SHA "$F/stub-1.0.0.zip")" S11="$(SHA "$F/stub-1.1.0.zip")" S20="$(SHA "$F/stub-2.0.0.zip")" SR="$(SHA "$F/real.zip")"
lsk() { ( cd "$K" 2>/dev/null && find . -mindepth 1 -maxdepth 1 | sed 's#^\./##' | LC_ALL=C sort | sed 's/^/   kit\//' ); }

echo '== _sha256: every tool that answers agrees =='
WANT="$(python -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$F/stub-1.0.0.zip")"
[ "$S10" = "$WANT" ] && echo '   default = python hashlib: yes' || echo '   default = python hashlib: NO'
G="$(POLARIS_HOME="$PH" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; sha256sum() { return 1; }; shasum() { return 1; }; _sha256 \"\$1\"" _ "$F/stub-1.0.0.zip")"
[ "$G" = "$WANT" ] && echo '   with sha256sum + shasum gone: same: yes' || echo '   with sha256sum + shasum gone: same: NO'

echo '== _store_put: a tampered zip is refused =='
ST "_store_put '$F/tampered.zip' 1.0.0 $S10" | sed "s#$F#<F>#"
[ -d "$K/1.0.0" ] && echo '   kit/1.0.0 exists: YES' || echo '   kit/1.0.0 exists: no'
echo '== _store_put: a bad version token is refused =='
ST "_store_put '$F/stub-1.0.0.zip' 1.0 $S10"
echo '== _store_put 1.0.0 =='
ST "_store_put '$F/stub-1.0.0.zip' 1.0.0 $S10"
( cd "$K/1.0.0" && find . -mindepth 1 | sed 's#^\./##' | LC_ALL=C sort | sed 's/^/   kit\/1.0.0\//' )
read -r e s < "$K/1.0.0/.stored"
case "$e" in ''|*[!0-9]*) echo '   .stored epoch: NO' ;; *) echo '   .stored epoch: a number' ;; esac
[ "$s" = "$S10" ] && echo '   .stored sha256 = the zip: yes' || echo '   .stored sha256 = the zip: NO'
cmp -s "$K/1.0.0/polaris-v5.zip" "$F/stub-1.0.0.zip" && echo '   zip kept beside, byte-equal: yes' || echo '   zip kept beside, byte-equal: NO'
echo '== _store_put again: the complete kit/1.0.0 is kept =='
echo 'marker' > "$K/1.0.0/keep-me"
ST "_store_put '$F/stub-1.0.0.zip' 1.0.0 $S10"
[ -f "$K/1.0.0/keep-me" ] && echo '   kept untouched: yes' || echo '   kept untouched: NO'
rm -f "$K/1.0.0/keep-me"
echo '== _store_put 1.1.0 with no python: unzip unpacks it =='
ST "python3() { return 1; }; python() { return 1; }; _store_put '$F/stub-1.1.0.zip' 1.1.0 $S11"
[ -f "$K/1.1.0/ops/polaris" ] && [ -f "$K/1.1.0/.stored" ] && echo '   kit/1.1.0 complete: yes' || echo '   kit/1.1.0 complete: NO'
echo '== _store_put 2.0.0 with neither python nor unzip =='
ST "python3() { return 1; }; python() { return 1; }; unzip() { return 127; }; _store_put '$F/stub-2.0.0.zip' 2.0.0 $S20"
lsk

echo '== _store_ver / _store_flip =='
ST 'printf "   ver: <%s> (nothing flipped yet)" "$(_store_ver)"; echo'
ST "_store_flip 2.0.0"
ST "echo 1.1.0 > '$K/next'; _store_flip 1.1.0; echo \"   ver: \$(_store_ver)\""
cat "$K/current" | sed 's/^/   current: /'
[ -f "$K/next" ] && echo '   next left: YES' || echo '   next left: no (it named 1.1.0)'
for bad in '1.1' '1.1.0.0' 'v1.1.0' '../1.1.0' '1..0' ' 1.1.0'; do
  printf '%s\n' "$bad" > "$K/current"
  printf '   current "%s" → ver: <%s>\n' "$bad" "$(POLARIS_HOME="$PH" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; _store_ver")"
done
printf '1.1.0\r\n' > "$K/current"
printf '   current "1.1.0<CR>" → ver: <%s>\n' "$(POLARIS_HOME="$PH" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; _store_ver")"
rm -f "$K/current"
printf '   no current → ver: <%s>\n' "$(POLARIS_HOME="$PH" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; _store_ver")"

echo '== _store_prune =='
P="$F/prune/.claude/polaris/kit"; mkdir -p "$P"
OLD=$(( $(date +%s) - 8 * 86400 )) NEW=$(( $(date +%s) - 86400 ))
for v in 1.1.0:$OLD 0.10.0:$OLD 0.9.0:$OLD 0.8.0:$NEW 0.7.0:$OLD; do
  mkdir -p "$P/${v%%:*}/ops"; printf '%s abc\n' "${v#*:}" > "$P/${v%%:*}/.stored"
done
mkdir -p "$P/0.6.0/ops" "$P/.tmp-0.5.0-1" "$P/.tmp-0.5.0-2"   # 0.6.0: no .stored, so no age
touch -t 202001010000 "$P/.tmp-0.5.0-1"
echo 1.1.0 > "$P/current"; echo 0.7.0 > "$P/next"
POLARIS_HOME="$F/prune/.claude/polaris" "$B" -c ". \"$W/kit/ops/lib/store.sh\"; _store_prune"; echo "   rc=$?"
( cd "$P" && find . -mindepth 1 -maxdepth 1 | sed 's#^\./##' | LC_ALL=C sort | sed 's/^/   kit\//' )

echo '== the launcher: its first two lines, no $( / backtick / pipe in its code, <= 60 lines =='
sed -n '1,2p' "$W/kit/ops/launcher" | sed 's/^/   /'
printf '   lines: %s\n' "$(wc -l < "$W/kit/ops/launcher" | tr -d ' ')"
printf '   code lines with $( or a backtick or a pipe: %s\n' "$(grep -v '^[[:space:]]*#' "$W/kit/ops/launcher" | grep -cE '\$\(|`| \| ')"

mkrepo() {
  ( git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main; }
    cd "$1" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
}
R="$F/repo"; mkrepo "$R"
for c in backlog ready active review done blocked; do mkdir -p "$R/ops/board/$c"; done
printf 'base: main\n' > "$R/ops/CONVENTIONS.md"
cp "$W/kit/ops/launcher" "$R/ops/polaris"
# L <cmd…> — the repo's launcher, run with bash; stdout+stderr kept in $F/out, rc printed
L() { ( cd "$R" && "$B" ops/polaris "$@" ) > "$F/out" 2>&1; echo "rc=$?"; }

echo '== the real kit through the launcher: version, from a state-only repo =='
KV="$(sed -n 's/^version: *//p' "$W/kit/ops/VERSION" | head -n 1)"
ST "_store_put '$F/real.zip' $KV $SR && _store_flip $KV"
L version
if head -1 "$F/out" | grep -q "POLARIS v$KV "; then echo "   version = the kit's VERSION: yes"; else echo "   version = the kit's VERSION: NO"; head -3 "$F/out"; fi
( cd "$R/ops" && ls -A ) | sed 's/^/   ops\//'

echo '== a stub kit, PATH emptied: the launcher still dispatches (builtins only) =='
ST "_store_flip 1.0.0"
( cd "$R" && PATH= "$B" ops/polaris status --x ) 2>&1; echo "rc=$?"
echo '== CLAUDE_CONFIG_DIR wins over HOME =='
mkdir -p "$F/cfg/polaris"; cp -R "$K" "$F/cfg/polaris/"; echo 1.1.0 > "$F/cfg/polaris/kit/current"
( cd "$R" && CLAUDE_CONFIG_DIR="$F/cfg" "$B" ops/polaris one ) > "$F/out" 2>&1; echo "rc=$?"; head -1 "$F/out"

echo '== a bad current, CI unset: the not-installed line =='
echo '1.0' > "$K/current"
L status; sed 's/^/   /' "$F/out"
echo '== no store at all =='
mv "$PH" "$F/away"
L status; sed 's/^/   /' "$F/out"
echo '== CI=true, no store, no ops/KIT =='
( cd "$R" && CI=true "$B" ops/polaris status ) > "$F/out" 2>&1; echo "rc=$?"; sed 's/^/   /' "$F/out"
echo '== CI=true, ops/KIT names a different sha256 =='
printf 'version: 2.0.0\nsha256: %s\n' "$S10" > "$R/ops/KIT"
( cd "$R" && CI=true POLARIS_KIT_SRC="$F/stub-2.0.0.zip" "$B" ops/polaris status ) > "$F/out" 2>&1; echo "rc=$?"; sed 's/^/   /' "$F/out"
[ -d "$K/2.0.0" ] && echo '   kit/2.0.0 exists: YES' || echo '   kit/2.0.0 exists: no'
echo '== CI=true, ops/KIT pins 2.0.0: bootstrapped into the store, then dispatched =='
printf '# the kit this repo runs in CI\r\nversion: 2.0.0\r\nsha256: %s\r\nurl: https://example.invalid/never-fetched.zip\r\n' "$S20" > "$R/ops/KIT"
( cd "$R" && CI=true POLARIS_KIT_SRC="$F/stub-2.0.0.zip" "$B" ops/polaris status ) > "$F/out" 2>&1; echo "rc=$?"; sed 's/^/   /' "$F/out"
lsk
cat "$K/current" | sed 's/^/   current: /'
echo '== POLARIS_BOOTSTRAP=1, CI unset, the store already holds the pin: no fetch needed =='
( cd "$R" && POLARIS_BOOTSTRAP=1 POLARIS_KIT_SRC="$F/none.zip" "$B" ops/polaris again ) > "$F/out" 2>&1; echo "rc=$?"; head -1 "$F/out"
