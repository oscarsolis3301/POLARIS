# no-self-grant — nothing an agent runs grants itself a permission (ops/contracts/shared-kit.md § 11).
# Every agent-run path runs with CLAUDECODE=1 against a fake machine whose two user settings files
# ($CLAUDE_CONFIG_DIR/settings.json and settings.local.json — HOME/.claude here, so a writer that
# names either root lands on the watched pair) are seeded with a foreign key, a rule and a hook. Each
# path prints one verdict per file: byte-identical, or CHANGED. The paths, the contract's list:
#   vendored  `update` (a file:// tarball) and `update --auto` (a file:// channel one minor ahead)
#   machine   the lazy upgrade (a joined project's first command), the machine `update` (a file://
#             channel and zip with its zip_sha256), `join`, `interview --init`, `migrate` — and for
#             these the PROJECT's .claude/settings.json and settings.local.json too. migrate's sweep
#             is § 7 step 3 (it removes POLARIS's own hook entries and outputStyle), so for that one
#             file the verdict is "nothing granted": every key, rule and hook after was there before.
#   install   a bootstrap install (`python polaris-v5.zip`) and `--setup` (refused, rc 2); the three
#             hook registrations — `awake-hook.sh install`, `model-guard.sh install`, `polaris awake
#             install` — each refused with rc 2 and the needs-you line.
# Then the same bootstrap install WITHOUT CLAUDECODE: the user settings.json CHANGES — proof that this
# golden can see a write at all. Lanes run side by side, each with its own fake machine.
# HERMETIC: one mktemp -d; HOME, USERPROFILE, CLAUDE_CONFIG_DIR and POLARIS_AWAKE_HOME are fakes per
# lane, POLARIS_PREFS= (machine layer off), CLAUDECODE set explicitly per case, PYTHONIOENCODING=utf-8;
# curl reads file:// (Windows: file:///C:/…, hence cygpath -m). No path, version or time is printed.
W="$(pwd)"
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
export POLARIS_PREFS= PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1 POLARIS_UPDATE_NO_FANOUT=1
unset POLARIS_LAUNCHER POLARIS_LAZY POLARIS_ROOT CI POLARIS_BOOTSTRAP POLARIS_KIT_SRC POLARIS_SHA POLARIS_UPDATE_HINTS
unset POLARIS_UPDATE_REEXEC POLARIS_UPDATE_FORCE POLARIS_MIGRATE_REEXEC CLAUDE_PROJECT_DIR
U="$F"; command -v cygpath >/dev/null 2>&1 && U="/$(cygpath -m "$F")"
PY=python; python -c pass >/dev/null 2>&1 || PY=python3
KV="$(sed -n 's/^version: *//p' "$W/kit/ops/VERSION" | head -n 1)"

# this tree's kit/, LF (the release zip's bytes), into $F/kit — every fixture copies from here
"$PY" - "$W/kit" "$F/kit" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
for root, dirs, fs in os.walk(src):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for f in fs:
        p = os.path.join(root, f)
        q = os.path.join(dst, os.path.relpath(p, src))
        os.makedirs(os.path.dirname(q), exist_ok=True)
        b = open(p, "rb").read()
        open(q, "wb").write(b if b"\0" in b else b.replace(b"\r\n", b"\n"))
PY
# ZIP <out> [<ver> <channel>] — the release shape (polaris-v5/… + __main__.py = bootstrap.py); with a
# version, its ops/VERSION is stamped <ver> and pointed at <channel>
ZIP() { "$PY" - "$F/kit" "$@" <<'PY'
import os, sys, zipfile
kit, out = sys.argv[1], sys.argv[2]
ver = sys.argv[3] if len(sys.argv) > 3 else None
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, fs in os.walk(kit):
        for f in fs:
            p = os.path.join(root, f)
            rel = os.path.relpath(p, kit).replace(os.sep, "/")
            blob = open(p, "rb").read()
            if ver and rel == "ops/VERSION":
                blob = ("version: %s\nchannel: %s\nchangelog: none\n" % (ver, sys.argv[4])).encode()
            i = zipfile.ZipInfo("polaris-v5/" + rel, date_time=(2026, 1, 1, 0, 0, 0))
            i.create_system = 3
            i.external_attr = (0o100000 | (0o755 if rel in ("ops/polaris", "ops/install.sh") else 0o644)) << 16
            z.writestr(i, blob)
    i = zipfile.ZipInfo("__main__.py", date_time=(2026, 1, 1, 0, 0, 0))
    z.writestr(i, open(os.path.join(kit, "ops", "bootstrap.py"), "rb").read())
PY
}
ZIP "$F/polaris-v5.zip"

# MACHINE <dir> — a fake machine: HOME = CLAUDE_CONFIG_DIR's parent, both user settings files seeded
MACHINE() {
  export HOME="$1" USERPROFILE="$1" CLAUDE_CONFIG_DIR="$1/.claude" POLARIS_AWAKE_HOME="$1/.claude/polaris/awake"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf '{\n  "theme": "dark",\n  "permissions": {\n    "allow": ["Bash(make:*)"]\n  },\n  "hooks": {\n    "Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}]\n  }\n}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  printf '{\n  "permissions": {\n    "allow": []\n  }\n}\n' > "$CLAUDE_CONFIG_DIR/settings.local.json"
}
mkrepo() {
  ( git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main; }
    cd "$1" && git config user.email t@t && git config user.name t && git config core.autocrlf false \
      && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
}
# REPOSET <repo> — the project's own two settings files, seeded
REPOSET() {
  mkdir -p "$1/.claude"
  printf '{\n  "outputStyle": "default"\n}\n' > "$1/.claude/settings.json"
  printf '{\n  "permissions": {\n    "allow": ["Bash(ls:*)"]\n  }\n}\n' > "$1/.claude/settings.local.json"
}
commit_all() { ( cd "$1" && git add -A && git commit -qm "$2" ) >/dev/null 2>&1; }
# SNAP <tag> [<repo>] — copy the watched files aside; VERDICT <label> <tag> [<repo>] — one line per file
SNAP() {
  mkdir -p "$F/s/$1"
  for f in settings.json settings.local.json; do
    cp "$CLAUDE_CONFIG_DIR/$f" "$F/s/$1/user-$f" 2>/dev/null || : > "$F/s/$1/user-$f.absent"
    [ -z "${2:-}" ] || cp "$2/.claude/$f" "$F/s/$1/repo-$f" 2>/dev/null || : > "$F/s/$1/repo-$f.absent"
  done
}
same() { # same <saved> <live>
  if [ -e "$1.absent" ]; then [ ! -e "$2" ] && echo 'byte-identical (absent)' || echo 'CHANGED (created)'
  elif cmp -s "$1" "$2"; then echo byte-identical; else echo CHANGED; fi
}
VERDICT() {
  for f in settings.json settings.local.json; do
    printf '   %-22s user %-20s %s\n' "$1" "$f:" "$(same "$F/s/$2/user-$f" "$CLAUDE_CONFIG_DIR/$f")"
  done
  [ -n "${3:-}" ] || return 0
  for f in settings.json settings.local.json; do
    printf '   %-22s repo %-20s %s\n' "$1" "$f:" "$(same "$F/s/$2/repo-$f" "$3/.claude/$f")"
  done
}
# GRANTED <before> <after> — "nothing granted" when every key, allow rule and hook command after was there before
GRANTED() { "$PY" - "$1" "$2" <<'PY'
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8")); b = json.load(open(sys.argv[2], encoding="utf-8"))
hooks = lambda d: {str(c.get("command")) for v in (d.get("hooks") or {}).values() for e in v for c in e.get("hooks", [])}
allow = lambda d: set((d.get("permissions") or {}).get("allow") or [])
new = [k for k in b if k not in a] + sorted(allow(b) - allow(a)) + sorted(hooks(b) - hooks(a))
perm = {k: v for k, v in (b.get("permissions") or {}).items() if k != "allow"} == {k: v for k, v in (a.get("permissions") or {}).items() if k != "allow"}
print("nothing granted" if not new and perm else "GRANTED: %s" % new)
PY
}
RC() { "$@" > "$F/o.$$" 2>&1; echo "$?"; }

# ---- lane 1: a vendored project — `update`, then `update --auto` -------------------------------
lane1() {
  MACHINE "$F/h1"; export CLAUDECODE=1
  local R="$F/v1" T="$F/tb1"
  # TGZ <ver> — the tarball `update` fetches: this kit, its VERSION stamped <ver>, the fixture channel
  TGZ() {
    rm -rf "$T"; mkdir -p "$T"; cp -R "$F/kit" "$T/polaris-main"
    printf 'version: %s\nchannel: file://%s/chan1\ntarball: file://%s/kit1.tgz\nchangelog: none\n' "$1" "$U" "$U" > "$T/polaris-main/ops/VERSION"
    tar -czf "$F/kit1.tgz" -C "$T" polaris-main; printf 'version: %s\n' "$1" > "$F/chan1"
  }
  mkrepo "$R"; REPOSET "$R"
  CLAUDECODE=1 bash "$F/kit/ops/install.sh" --quiet "$R" >/dev/null 2>&1
  printf 'version: %s\nchannel: file://%s/chan1\ntarball: file://%s/kit1.tgz\nchangelog: none\n' 7.0.0 "$U" "$U" > "$R/ops/VERSION"
  commit_all "$R" vendored
  echo '== vendored: update (file:// tarball) =='
  TGZ 7.0.1; SNAP u1
  echo "   rc=$(cd "$R" && RC bash ops/polaris update) · now $(sed -n 's/^version: *//p' "$R/ops/VERSION")"
  VERDICT update u1
  commit_all "$R" updated; rm -f "$R/.polaris/update-cache"
  echo '== vendored: update --auto (a channel one minor ahead) =='
  TGZ 7.0.2; SNAP u2
  echo "   rc=$(cd "$R" && RC bash ops/polaris update --auto) · now $(sed -n 's/^version: *//p' "$R/ops/VERSION")"
  VERDICT 'update --auto' u2
}

# ---- lane 2: a joined project — the lazy upgrade, then the machine update ----------------------
lane2() {
  MACHINE "$F/h2"; export CLAUDECODE=1
  local PH="$CLAUDE_CONFIG_DIR/polaris" A="$F/m2"
  ZIP "$F/k-0.0.1.zip" 0.0.1 "file://$U/chan2"; ZIP "$F/k-0.0.2.zip" 0.0.2 "file://$U/chan2"
  sha() { POLARIS_HOME="$PH" bash -c ". \"$F/kit/ops/lib/store.sh\"; _sha256 \"\$1\"" _ "$1"; }
  POLARIS_HOME="$PH" bash -c ". \"$F/kit/ops/lib/store.sh\"; _store_put \"\$1\" 0.0.1 \"\$2\" && _store_flip 0.0.1" _ "$F/k-0.0.1.zip" "$(sha "$F/k-0.0.1.zip")"
  mkrepo "$A"; REPOSET "$A"; mkdir -p "$A/ops" "$A/.polaris/brain"
  cp "$F/kit/ops/launcher" "$A/ops/polaris"; printf 'base: main\n' > "$A/ops/CONVENTIONS.md"
  printf '.polaris/\nops/board/\nops/SPRINT.md\n' > "$A/.gitignore"
  mkdir -p "$PH/awake/repos"; printf '%s\n' "$A" > "$PH/awake/repos/1"
  commit_all "$A" joined
  echo '== machine: the lazy upgrade (a joined project'"'"'s first command) =='
  SNAP l2 "$A"
  echo "   rc=$(cd "$A" && RC bash ops/polaris status) · kit-seen: $([ -s "$A/.polaris/kit-seen" ] && echo written || echo none)"
  VERDICT 'lazy upgrade' l2 "$A"
  commit_all "$A" upgraded
  echo '== machine: update (file:// channel + zip_sha256) =='
  printf 'version: 0.0.2\nzip: file://%s/k-0.0.2.zip\nzip_sha256: %s\n' "$U" "$(sha "$F/k-0.0.2.zip")" > "$F/chan2"
  SNAP m2 "$A"
  echo "   rc=$(cd "$A" && RC bash ops/polaris update) · current: $(cat "$PH/kit/current")"
  VERDICT 'machine update' m2 "$A"
}

# ---- lane 3: join, then interview --init ------------------------------------------------------
lane3() {
  MACHINE "$F/h3"; export CLAUDECODE=1
  local ST="$CLAUDE_CONFIG_DIR/polaris/kit" R="$F/j3"
  mkdir -p "$ST"; cp -R "$F/kit" "$ST/$KV"; printf '0 fixture\n' > "$ST/$KV/.stored"; printf '%s\n' "$KV" > "$ST/current"
  mkrepo "$R"; REPOSET "$R"; commit_all "$R" own
  echo '== machine: join =='
  SNAP j3 "$R"
  echo "   rc=$(cd "$R" && RC bash "$ST/$KV/ops/polaris" join) · launcher: $([ -f "$R/ops/polaris" ] && echo written || echo none)"
  VERDICT join j3 "$R"
  echo '== machine: interview --init (a joined project) =='
  SNAP i3 "$R"
  echo "   rc=$(cd "$R" && RC bash ops/polaris interview --init)"
  VERDICT 'interview --init' i3 "$R"
}

# ---- lane 4: migrate a vendored project -------------------------------------------------------
lane4() {
  MACHINE "$F/h4"; export CLAUDECODE=1
  local ST="$CLAUDE_CONFIG_DIR/polaris/kit" V="$F/g4"
  mkdir -p "$ST"; cp -R "$F/kit" "$ST/$KV"; printf '0 fixture\n' > "$ST/$KV/.stored"; printf '%s\n' "$KV" > "$ST/current"
  mkrepo "$V"; REPOSET "$V"
  bash "$F/kit/ops/install.sh" --quiet "$V" >/dev/null 2>&1
  printf 'base: main\n' > "$V/ops/CONVENTIONS.md"; commit_all "$V" vendored
  echo '== machine: migrate =='
  SNAP g4 "$V"
  echo "   rc=$(cd "$V" && RC bash ops/polaris migrate) · launcher: $(cmp -s "$V/ops/polaris" "$ST/$KV/ops/launcher" && echo in || echo NOT)"
  VERDICT migrate g4
  printf '   %-22s repo %-20s %s\n' migrate settings.json: "$(GRANTED "$F/s/g4/repo-settings.json" "$V/.claude/settings.json")"
  printf '   %-22s repo %-20s %s\n' migrate settings.local.json: "$(same "$F/s/g4/repo-settings.local.json" "$V/.claude/settings.local.json")"
}

# ---- lane 5: the bootstrap install, --setup, the three hook registrations ---------------------
lane5() {
  MACHINE "$F/h5"; export CLAUDECODE=1
  local R="$F/b5" H="$F/b5h" n
  mkrepo "$R"
  echo '== install: python polaris-v5.zip (CLAUDECODE=1) =='
  SNAP b5
  echo "   rc=$(cd "$R" && RC "$PY" "$F/polaris-v5.zip") · ops/polaris: $([ -f "$R/ops/polaris" ] && echo installed || echo none)"
  VERDICT 'bootstrap install' b5
  echo '== install: python polaris-v5.zip --setup (CLAUDECODE=1) =='
  SNAP s5
  echo "   rc=$(cd "$R" && RC "$PY" "$F/polaris-v5.zip" --setup)"
  VERDICT '--setup' s5
  echo '== the hook registrations, run directly (CLAUDECODE=1) =='
  mkdir -p "$CLAUDE_CONFIG_DIR/polaris"
  cp "$F/kit/ops/hooks/awake-hook.sh" "$F/kit/ops/hooks/model-guard.sh" "$CLAUDE_CONFIG_DIR/polaris/"
  for n in awake-hook model-guard; do
    SNAP "$n"
    echo "   $n.sh install: rc=$(RC bash "$CLAUDE_CONFIG_DIR/polaris/$n.sh" install) · $(grep -c '^⛔ needs you: python ".*" --setup in your own terminal' "$F/o.$$") needs-you line"
    VERDICT "$n.sh install" "$n"
  done
  SNAP aw
  echo "   polaris awake install: rc=$(cd "$R" && RC bash ops/polaris awake install) · $(grep -c '^⛔ needs you:' "$F/o.$$") needs-you line"
  VERDICT 'awake install' aw
  echo '== the same install WITHOUT CLAUDECODE: the golden can see a write =='
  MACHINE "$H"; export CLAUDECODE=; mkrepo "$R-h"
  SNAP b5h
  echo "   rc=$(cd "$R-h" && RC "$PY" "$F/polaris-v5.zip")"
  VERDICT 'bootstrap, a human' b5h
}

for n in 1 2 3 4 5; do ( "lane$n" ) > "$F/report$n" 2>&1 & done
wait
for n in 1 2 3 4 5; do sed -e "s#$F#<F>#g" "$F/report$n"; done
