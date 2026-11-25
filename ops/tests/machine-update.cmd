# machine-update — `update` in a joined project is a MACHINE operation (ops/contracts/shared-kit.md
# §§ 3, 5; auto-update.md v6). A fake machine: a store at 0.0.1, two joined fixture projects (a
# launcher, no ops/lib/) plus a vendored and a gone registry entry, a file:// channel whose zip and
# zip_sha256 it names. Proves: one `update` flips `current` and both projects move with no commit
# and no dirty path · each project's next command upgrades it once (kit-seen) and `version` reads the
# new kit · a busy project stages kit/next (a board card, then a live worktree beat), a later
# `--auto` re-asks the projects only (the channel is gone by then) and flips once they are quiet,
# with the trust-tier line · a tampered zip and a channel with no zip_sha256 are refused, `current`
# unchanged · a MAJOR only asks · prune keeps current + previous · the lazy upgrade never runs for
# the read-only verbs, nor in a vendored install · `__quiet` is not in help · an AGENT-RUN update
# (CLAUDECODE=1) leaves every settings file byte-identical: no permission rule, no auto-mode key, no
# hook entry, in Claude Code's own config or in either project.
# HERMETIC: one mktemp -d; HOME, USERPROFILE and CLAUDE_CONFIG_DIR are fakes, POLARIS_PREFS= (machine
# layer off), CLAUDECODE=1 set on purpose. Fixture zips are this tree's kit/ in the release shape,
# built with python zipfile; curl reads file:// (Windows: file:///C:/…, hence cygpath -m).
W="$(pwd)"
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
export HOME="$F/home" USERPROFILE="$F/home" CLAUDE_CONFIG_DIR="$F/cfg" POLARIS_PREFS= CLAUDECODE=1
export PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1 POLARIS_UPDATE_NO_FANOUT=1
unset POLARIS_LAUNCHER POLARIS_LAZY POLARIS_ROOT POLARIS_AWAKE_HOME CI POLARIS_BOOTSTRAP POLARIS_KIT_SRC
unset POLARIS_UPDATE_REEXEC POLARIS_UPDATE_FORCE
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
PH="$CLAUDE_CONFIG_DIR/polaris"
K="$PH/kit"
U="$F"; command -v cygpath >/dev/null 2>&1 && U="/$(cygpath -m "$F")"

# k-<v>.zip = this tree's kit/, its ops/VERSION stamped <v> and pointed at the fixture channel
python - "$W/kit" "$F" "file://$U/chan/VERSION" <<'PY'
import os, sys, zipfile
kit, out, chan = sys.argv[1], sys.argv[2], sys.argv[3]
def add(z, name, blob, mode=0o644):
    i = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    i.create_system = 3
    i.external_attr = (0o100000 | mode) << 16
    z.writestr(i, blob)
files = []
for root, dirs, fs in os.walk(kit):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for f in fs:
        p = os.path.join(root, f)
        files.append((os.path.relpath(p, kit).replace(os.sep, "/"), open(p, "rb").read().replace(b"\r\n", b"\n")))
for v in ("0.0.1", "0.0.2", "0.0.3", "0.0.4"):
    with zipfile.ZipFile(os.path.join(out, "k-%s.zip" % v), "w", zipfile.ZIP_DEFLATED) as z:
        for rel, blob in files:
            if rel == "ops/VERSION":
                blob = ("version: %s\nchannel: %s\nchangelog: none\n" % (v, chan)).encode()
            add(z, "polaris-v5/" + rel, blob, 0o755 if rel in ("ops/polaris", "ops/install.sh") else 0o644)
        add(z, "__main__.py", b"print('fixture')\n")
PY
cp "$F/k-0.0.4.zip" "$F/tampered.zip"; printf 'x' >> "$F/tampered.zip"
SHA() { POLARIS_HOME="$PH" bash -c ". \"$W/kit/ops/lib/store.sh\"; _sha256 \"\$1\"" _ "$1"; }
# CHAN <ver> <zip> [nosha] — the channel file: version, zip:, and the sha of k-<ver>.zip (unless nosha)
CHAN() { mkdir -p "$F/chan"
  { printf 'version: %s\nzip: file://%s/%s\n' "$1" "$U" "$2"
    [ "${3:-}" = nosha ] || printf 'zip_sha256: %s\n' "$(SHA "$F/k-$1.zip")"; } > "$F/chan/VERSION"; }
lsk() { ( cd "$K" && find . -mindepth 1 -maxdepth 1 | sed 's#^\./##' | LC_ALL=C sort | tr '\n' ' ' ); echo; }
OUT() { sed -e "s#$F#<F>#g" -e 's#\.tmp-dl-\([0-9.]*\)-[0-9]*\.zip#.tmp-dl-\1-<pid>.zip#' "$F/out" | sed 's/^/   /'; }
# L <dir> <cmd…> — the project's launcher, output in $F/out, rc printed
L() { local d="$1"; shift; ( cd "$d" && bash ops/polaris "$@" ) > "$F/out" 2>&1; echo "   rc=$?"; }

# ---- the machine: kit 0.0.1 current, an 8-day-old 0.0.0, a trust tier, the registry
POLARIS_HOME="$PH" bash -c ". \"$W/kit/ops/lib/store.sh\"; _store_put \"\$1\" 0.0.1 \"\$2\" && _store_flip 0.0.1" _ "$F/k-0.0.1.zip" "$(SHA "$F/k-0.0.1.zip")"
OLD=$(( $(date +%s) - 8 * 86400 ))
read -r _e s1 < "$K/0.0.1/.stored"; printf '%s %s\n' "$OLD" "$s1" > "$K/0.0.1/.stored"
mkdir -p "$K/0.0.0/ops"; printf '%s abc\n' "$OLD" > "$K/0.0.0/.stored"
mkdir -p "$PH/trust"; cp "$K/0.0.1/ops/hooks/readonly-allow.sh" "$PH/trust/readonly-allow.sh"
printf '{\n  "theme": "dark"\n}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
printf '{\n  "permissions": {\n    "allow": []\n  }\n}\n' > "$CLAUDE_CONFIG_DIR/settings.local.json"

mkrepo() {
  ( git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main; }
    cd "$1" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
}
A="$F/a" B="$F/b" V="$F/v"
for p in "$A" "$B"; do
  mkrepo "$p"
  mkdir -p "$p/ops" "$p/.claude" "$p/.polaris/brain"     # brain present: heal never spends 10 s building one
  printf '.polaris/\nops/board/\nops/SPRINT.md\n' > "$p/.gitignore"
  printf 'base: main\n' > "$p/ops/CONVENTIONS.md"
  cp "$W/kit/ops/launcher" "$p/ops/polaris"
  printf '{\n  "outputStyle": "default"\n}\n' > "$p/.claude/settings.json"
  printf '{\n  "permissions": {\n    "allow": ["Bash(ls:*)"]\n  }\n}\n' > "$p/.claude/settings.local.json"
  printf '<!-- POLARIS:BEGIN pointer -->\nThis project runs POLARIS from the kit on this computer.\n<!-- POLARIS:END -->\n' > "$p/CLAUDE.md"
done
mkrepo "$V"; mkdir -p "$V/ops"; cp -R "$W/kit/ops/lib" "$W/kit/ops/polaris" "$W/kit/ops/VERSION" "$V/ops/"; printf 'base: main\n' > "$V/ops/CONVENTIONS.md"
for c in backlog ready active review done blocked; do mkdir -p "$V/ops/board/$c"; done
mkdir -p "$PH/awake/repos"
printf '%s\n' "$A" > "$PH/awake/repos/1"; printf '%s\n' "$B" > "$PH/awake/repos/2"
printf '%s\n' "$V" > "$PH/awake/repos/3"; printf '%s\n' "$F/gone" > "$PH/awake/repos/4"

echo '== each joined project, first command on kit 0.0.1: upgraded once, then committed as its owner would =='
for p in "$A" "$B"; do
  L "$p" board-fm
  printf '   kit-seen: %s\n' "$(cat "$p/.polaris/kit-seen" 2>/dev/null || echo none)"
  ( cd "$p" && git add -A && git commit -qm 'joined' ) >/dev/null 2>&1
done
HA="$(git -C "$A" rev-parse HEAD)" HB="$(git -C "$B" rev-parse HEAD)"
mkdir -p "$F/snap"
for f in settings.json settings.local.json; do
  cp "$CLAUDE_CONFIG_DIR/$f" "$F/snap/cfg-$f"; cp "$A/.claude/$f" "$F/snap/a-$f"; cp "$B/.claude/$f" "$F/snap/b-$f"
done
clean() { # clean — both projects: HEAD where the owner left it, nothing dirty
  for p in "$A:$HA" "$B:$HB"; do
    d="${p%:*}"; [ "$(git -C "$d" rev-parse HEAD)" = "${p##*:}" ] && c='no new commit' || c='A NEW COMMIT'
    n="$(git -C "$d" status --porcelain | wc -l | tr -d ' ')"
    printf '   %s: %s · dirty paths: %s\n' "${d##*/}" "$c" "$n"
  done
}

echo '== update 0.0.1 → 0.0.2: every project quiet, current flips =='
CHAN 0.0.2 k-0.0.2.zip
L "$A" update; OUT
printf '   current: %s\n' "$(cat "$K/current")"
printf '   kit/: '; lsk
clean
for p in "$A" "$B"; do printf '   %s kit-seen before its next command: %s\n' "${p##*/}" "$(cat "$p/.polaris/kit-seen")"; done
echo '== each project catches up at its next command, once =='
for p in "$A" "$B"; do
  L "$p" board-fm
  printf '   %s kit-seen: %s · install.log: %s\n' "${p##*/}" "$(cat "$p/.polaris/kit-seen")" "$([ -s "$p/.polaris/install.log" ] && echo written || echo none)"
  rm -f "$p/.polaris/install.log"
  L "$p" board-fm
  printf '   %s again: install.log %s\n' "${p##*/}" "$([ -e "$p/.polaris/install.log" ] && echo 'WRITTEN AGAIN' || echo 'not written (no second upgrade)')"
  L "$p" version; printf '   %s version: %s\n' "${p##*/}" "$(head -1 "$F/out" | sed 's/  ·.*//')"
done
clean
echo '== update again: up to date =='
L "$A" update; OUT

echo '== 0.0.3 while b has a card in flight: staged in kit/next =='
CHAN 0.0.3 k-0.0.3.zip
mkdir -p "$B/ops/board/active"; : > "$B/ops/board/active/T-1.md"
L "$A" update; OUT
printf '   current: %s · next: %s\n' "$(cat "$K/current")" "$(cat "$K/next" 2>/dev/null || echo none)"
echo '== --auto with the channel gone: only the projects are asked again =='
rm -f "$F/chan/VERSION"
L "$A" update --auto; OUT
echo '== the card lands, but b has a live task worktree =='
rm -f "$B/ops/board/active/T-1.md"
mkdir -p "$B/.polaris/wt/T-9" "$B/.git/worktrees/T-9"; date +%s > "$B/.git/worktrees/T-9/polaris-beat"
L "$A" update --auto; OUT
echo '== b quiet, the trust tier no longer matches: --auto flips, prunes, and names the owner step =='
rm -rf "$B/.polaris/wt/T-9" "$B/.git/worktrees/T-9"
printf '# an older trust tier\n' > "$PH/trust/readonly-allow.sh"
L "$A" update --auto; OUT
printf '   current: %s · next: %s\n' "$(cat "$K/current")" "$(cat "$K/next" 2>/dev/null || echo none)"
printf '   kit/: '; lsk
cp "$K/0.0.3/ops/hooks/readonly-allow.sh" "$PH/trust/readonly-allow.sh"
clean

echo '== a tampered zip: refused, nothing stored, current unchanged =='
CHAN 0.0.4 tampered.zip   # the sha256 of the real k-0.0.4.zip, the bytes of the tampered copy
L "$A" update; OUT
printf '   current: %s\n' "$(cat "$K/current")"
printf '   kit/: '; lsk
echo '== a channel with no zip_sha256: refused =='
CHAN 0.0.4 k-0.0.4.zip nosha
L "$A" update; OUT
printf '   current: %s\n' "$(cat "$K/current")"
echo '== a MAJOR on the channel: asks, never moves =='
CHAN 1.0.0 k-0.0.4.zip nosha
L "$A" update; OUT
printf '   current: %s\n' "$(cat "$K/current")"

echo '== the lazy upgrade never runs for the read-only verbs =='
rm -f "$A/.polaris/kit-seen"
for c in version 'role BUILDER' 'doc PROTOCOL' router prefs help 'find board' 'show a:1' 'hops --due'; do
  # shellcheck disable=SC2086
  ( cd "$A" && bash ops/polaris $c ) >/dev/null 2>&1
  [ -e "$A/.polaris/kit-seen" ] && printf '   %s: UPGRADED\n' "$c" && rm -f "$A/.polaris/kit-seen"
done
printf '   after version role doc router prefs help find show hops: kit-seen %s\n' "$([ -e "$A/.polaris/kit-seen" ] && echo WRITTEN || echo absent)"
L "$A" board-fm; printf '   after board-fm: kit-seen %s\n' "$(cat "$A/.polaris/kit-seen" 2>/dev/null || echo absent)"
echo '== a vendored install never takes it =='
L "$V" board-fm; printf '   vendored kit-seen: %s\n' "$([ -e "$V/.polaris/kit-seen" ] && echo WRITTEN || echo absent)"
echo '== __quiet is hidden =='
printf '   help lines naming __quiet: %s\n' "$(bash "$W/kit/ops/polaris" help | grep -c '__quiet' | tr -d ' ')"

echo '== an agent-run update wrote no settings anywhere =='
clean
for f in settings.json settings.local.json; do
  cmp -s "$CLAUDE_CONFIG_DIR/$f" "$F/snap/cfg-$f" && echo "   Claude Code $f: byte-identical" || echo "   Claude Code $f: CHANGED"
  cmp -s "$A/.claude/$f" "$F/snap/a-$f" && cmp -s "$B/.claude/$f" "$F/snap/b-$f" && echo "   projects' .claude/$f: byte-identical" || echo "   projects' .claude/$f: CHANGED"
done
printf '   %s/.claude: %s\n' '$HOME' "$([ -e "$HOME/.claude" ] && echo CREATED || echo absent)"
