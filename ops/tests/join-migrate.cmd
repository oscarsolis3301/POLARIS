# join-migrate — a project joins this computer's kit, and a vendored one migrates to it
# (ops/contracts/shared-kit.md §§ 6-8). A fake machine: this tree's kit/ unpacked into a fixture
# store (LF, as the release zip carries it), `current` naming it. Proves:
#   join  — in a fresh repo it writes exactly the § 6 set (launcher, .gitattributes/.gitignore lines,
#           commit-msg hook, registry entry, the pointer in CLAUDE.md) and nothing under .claude/, no
#           settings file anywhere, no commit, no install.sh run; its last line is `installed · fresh`
#           (`installed · live-board` over a CONVENTIONS.md) with ≤ 2 lines above it and no INIT
#           kickoff phrase; version · status · role BUILDER · doc PROTOCOL work through the launcher;
#           an existing POLARIS block becomes the pointer; every refusal prints its pinned line and
#           writes nothing.
#   migrate — a vendored fixture (this tree's install.sh, plus state and a foreign hook) becomes ONE
#           commit with the § 7 content: kit files out, launcher in, POLARIS's hook entries and output
#           style swept (permission rules and the foreign hook kept), block → pointer, registered,
#           kit-seen; `git revert` of it → `git diff <before> HEAD` empty and the index identical;
#           every refusal (busy board, the POLARIS repo, no kit, an older kit, kit dirt, a staged
#           index, already joined) pinned, nothing written.
# HERMETIC: one mktemp -d; HOME, USERPROFILE and CLAUDE_CONFIG_DIR are fakes, POLARIS_PREFS= (machine
# layer off), CLAUDECODE=1 set on purpose (an agent runs these), PYTHONIOENCODING=utf-8. Paths, the
# version and commit hashes are masked; only verdicts, counts and pinned lines reach this file.
W="$(pwd)"
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
export HOME="$F/home" USERPROFILE="$F/home" CLAUDE_CONFIG_DIR="$F/cfg" POLARIS_PREFS= CLAUDECODE=1
export PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
unset POLARIS_LAUNCHER POLARIS_LAZY POLARIS_ROOT POLARIS_AWAKE_HOME CI POLARIS_BOOTSTRAP POLARIS_KIT_SRC POLARIS_MIGRATE_REEXEC
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
FM="$(cd "$F" && pwd -W 2>/dev/null || pwd)"
KV="$(sed -n 's/^version: *//p' "$W/kit/ops/VERSION" | head -n 1)"
ST="$CLAUDE_CONFIG_DIR/polaris/kit"
# the store: this tree's kit/, verbatim but LF — the release zip's bytes (pack.py builds it from git)
python - "$W/kit" "$ST/$KV" <<'PY'
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
printf '0 fixture\n' > "$ST/$KV/.stored"
printf '%s\n' "$KV" > "$ST/current"
mkrepo() {
  ( git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main; }
    cd "$1" && git config user.email t@t && git config user.name t && git config core.autocrlf false \
      && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
}
mask() { sed -e "s#$FM#<F>#g" -e "s#$F#<F>#g" -e "s#$KV#<ver>#g" -e 's#\([( ]\)[0-9a-f]\{7,\}\([);]\|$\)#\1<sha>\2#g' -e 's#\(git revert \)[0-9a-f]\{7,\}#\1<sha>#g'; }
# SNAP <dir> — every file under <dir> (its .git/ only for hooks/commit-msg) with its hash, sorted
SNAP() { python - "$1" <<'PY'
import hashlib, os, sys
r = sys.argv[1]
out = []
for root, dirs, fs in os.walk(r):
    rel = os.path.relpath(root, r).replace(os.sep, "/")
    if rel == ".git" or rel.startswith(".git/"):
        if rel == ".git": dirs[:] = [d for d in dirs if d == "hooks"]
        fs = [f for f in fs if rel == ".git/hooks" and f == "commit-msg"]
    for f in fs:
        p = os.path.join(root, f)
        q = os.path.relpath(p, r).replace(os.sep, "/")
        out.append("%s ./%s" % (hashlib.sha1(open(p, "rb").read()).hexdigest(), q))
sys.stdout.buffer.write("".join(l + chr(10) for l in sorted(out)).encode("utf-8"))
PY
}
# CHANGED <before> <after> — the paths that appeared or changed
CHANGED() { LC_ALL=C comm -13 "$1" "$2" | sed 's/^[^ ]* \.\///' | LC_ALL=C sort | sed 's/^/   + /'; }
JR() { ( cd "${2:-$PWD}" && bash "$W/kit/ops/polaris" join ${1:+"$1"} ); }
J() { JR "$@" > "$F/out" 2>&1; echo "   rc=$?"; }
# REFUSE <label> <dir-to-snapshot> <cmd…> — rc, the line, and whether anything was written
REFUSE() {
  local l="$1" d="$2"; shift 2
  SNAP "$d" > "$F/r0"; SNAP "$CLAUDE_CONFIG_DIR" > "$F/c0"
  "$@" > "$F/out" 2>&1; echo "-- $l: rc=$?"
  mask < "$F/out" | sed 's/^/   /'
  SNAP "$d" > "$F/r1"; SNAP "$CLAUDE_CONFIG_DIR" > "$F/c1"
  if cmp -s "$F/r0" "$F/r1" && cmp -s "$F/c0" "$F/c1"; then echo '   wrote nothing: yes'; else echo '   wrote nothing: NO'; CHANGED "$F/r0" "$F/r1"; fi
}

echo '== join: a fresh repo (a CLAUDE.md of its own, a .gitignore with no last newline) =='
R="$F/fresh"; mkrepo "$R"
printf '# mine\n\nmy rule\n' > "$R/CLAUDE.md"; printf 'node_modules/' > "$R/.gitignore"
( cd "$R" && git add -A && git commit -qm own ) >/dev/null 2>&1
H0="$(git -C "$R" rev-parse HEAD)"
SNAP "$R" > "$F/r0"; SNAP "$CLAUDE_CONFIG_DIR" > "$F/c0"
J "" "$R"
mask < "$F/out" | sed 's/^/   /'
echo "   lines: $(wc -l < "$F/out" | tr -d ' ') · last: $(tail -n 1 "$F/out")"
grep -qiE 'You are INIT|say INIT' "$F/out" && echo '   INIT kickoff phrase: PRINTED' || echo '   INIT kickoff phrase: none'
echo '   repo files written:'; SNAP "$R" > "$F/r1"; CHANGED "$F/r0" "$F/r1"
echo '   machine files written:'; SNAP "$CLAUDE_CONFIG_DIR" > "$F/c1"; CHANGED "$F/c0" "$F/c1" | sed 's#repos/[0-9]*$#repos/<cksum>#'
k="$(printf '%s' "$(git -C "$R" rev-parse --show-toplevel)" | cksum)"; k="${k%% *}"
[ "$(cat "$CLAUDE_CONFIG_DIR/polaris/awake/repos/$k" 2>/dev/null)" = "$(git -C "$R" rev-parse --show-toplevel)" ] && echo '   registry entry: install.sh formula, names the repo'
[ -e "$R/.claude" ] && echo '   .claude/: PRESENT' || echo '   .claude/: none'
[ "$(git -C "$R" rev-parse HEAD)" = "$H0" ] && echo '   commit: none'
cmp -s "$R/ops/polaris" "$ST/$KV/ops/launcher" && echo '   ops/polaris = the store kit'"'"'s launcher, byte-identical'
[ -x "$R/ops/polaris" ] && echo '   ops/polaris: executable'
grep -c 'POLARIS commit-msg' "$R/.git/hooks/commit-msg" | sed 's/^/   commit-msg hook is POLARIS'"'"'s: /'
echo '   CLAUDE.md:'; sed 's/^/   | /' "$R/CLAUDE.md"
echo '   .gitattributes:'; sed 's/^/   | /' "$R/.gitattributes"
echo '   .gitignore:'; sed 's/^/   | /' "$R/.gitignore"
grep -qF 'install.sh' "$F/out" && echo '   install.sh: named' || echo '   install.sh: never run'

echo '== join: the launcher answers =='
for c in version status "role BUILDER" "doc PROTOCOL"; do
  ( cd "$R" && bash ops/polaris $c ) > "$F/out" 2>&1; printf '   %s: rc=%s · ' "$c" "$?"; head -n 1 "$F/out" | mask
done
( cd "$R" && bash ops/polaris role BUILDER ) > "$F/out" 2>&1
cmp -s "$F/out" "$ST/$KV/ops/roles/BUILDER.md" && echo '   role BUILDER = the store kit'"'"'s roles/BUILDER.md, byte-identical'
[ -e "$R/.claude" ] && echo '   .claude/ after the launcher ran: PRESENT' || echo '   .claude/ after the launcher ran: none'
echo "   settings files outside the kit store: $(find "$F" -name 'settings*.json' ! -path "$ST/*" | wc -l | tr -d ' ')"

echo '== join: a live board, a CLAUDE.md that carries a POLARIS block =='
L="$F/live"; mkrepo "$L"
mkdir -p "$L/ops"; printf 'base: main\n' > "$L/ops/CONVENTIONS.md"
printf 'top\n<!-- POLARIS:BEGIN — managed block [kit 6.0.0] -->\nold protocol\n<!-- POLARIS:END -->\nbelow\n' > "$L/CLAUDE.md"
J "$L" "$F"
mask < "$F/out" | sed 's/^/   /'
sed 's/^/   | /' "$L/CLAUDE.md"

echo '== join: refusals =='
mkdir -p "$F/plain"
REFUSE 'not a git repository' "$F/plain" JR "$F/plain" "$F"
git -C "$R" worktree add -q "$F/linked" -b side >/dev/null 2>&1
REFUSE 'a linked worktree' "$F/linked" JR "" "$F/linked"
REFUSE 'already joined' "$R" JR "$R" "$F"
V0="$F/vend0"; mkrepo "$V0"; mkdir -p "$V0/ops/lib"; : > "$V0/ops/polaris"
REFUSE 'already vendored' "$V0" JR "$V0" "$F"
P="$F/polaris"; mkrepo "$P"; mkdir -p "$P/kit/ops"; : > "$P/kit/ops/pack.py"
REFUSE 'the POLARIS repo' "$P" JR "$P" "$F"
N="$F/nokit"; mkrepo "$N"
REFUSE 'no kit on this machine' "$N" env CLAUDE_CONFIG_DIR="$F/empty" bash -c 'cd "$1" && bash "$2/kit/ops/polaris" join' _ "$N" "$W"

echo '== migrate: the vendored fixture =='
V="$F/vend"; mkrepo "$V"
printf '# mine\n\nmy rule\n' > "$V/CLAUDE.md"
( cd "$V" && git add -A && git commit -qm own ) >/dev/null 2>&1
bash "$W/kit/ops/install.sh" --quiet "$V" > "$F/inst" 2>&1; echo "   install rc=$?"
mkdir -p "$V/ops/contracts" "$V/ops/tests" "$V/.claude/skills/mine" "$V/.claude/skills/polaris-install"
printf 'base: main\n' > "$V/ops/CONVENTIONS.md"
printf '# map\n' > "$V/ops/MAP.md"; printf 'x\tpath\tsecret/*\t# fixture\n' > "$V/ops/RULES.tsv"
printf 'a\tb\tc\td\n' > "$V/ops/SURFACES.tsv"; printf '# design\n' > "$V/ops/DESIGN.md"; printf '# roadmap\n' > "$V/ops/ROADMAP.md"
printf '# c\n' > "$V/ops/contracts/c.md"; printf 'echo t\n' > "$V/ops/tests/t.cmd"
printf 'mine\n' > "$V/.claude/skills/mine/SKILL.md"; printf 'kit\n' > "$V/.claude/skills/polaris-install/SKILL.md"
python - "$V/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d.setdefault("hooks", {}).setdefault("PreToolUse", []).append({"matcher": "Bash", "hooks": [{"type": "command", "command": "bash tools/my-hook.sh"}]})
d.setdefault("permissions", {}).setdefault("allow", []).append("Bash(make:*)")
open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(d, indent=2) + "\n")
PY
( cd "$V" && git add -A && git commit -qm vendored ) >/dev/null 2>&1
B="$(git -C "$V" rev-parse HEAD)"
cp "$V/.claude/settings.json" "$F/sj0"
python - "$F/sj0" <<'PY' | sed 's/^/   before: /'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
h = [str(c.get("command", "")) for v in d.get("hooks", {}).values() for e in v for c in e.get("hooks", [])]
print("POLARIS hook entries: %s · outputStyle: %s · foreign hook: %s · Bash(make:*) allowed: %s" % (
    "yes" if any(re.search(r"ops/hooks/", x.replace(chr(92), "/")) for x in h) else "none",
    d.get("outputStyle"), "yes" if "bash tools/my-hook.sh" in h else "no",
    "yes" if "Bash(make:*)" in d.get("permissions", {}).get("allow", []) else "no"))
PY
for p in ops/lib/core.sh ops/hooks/ownership-guard.sh ops/VERSION ops/KEYS.tsv .claude/skills/polaris/SKILL.md .claude/output-styles/polaris.md; do
  git -C "$V" ls-files --error-unmatch "$p" >/dev/null 2>&1 && echo "   tracked before: $p"
done
M() { ( cd "$V" && bash ops/polaris migrate ); }

echo '== migrate: refusals =='
mkdir -p "$V/ops/board/active"; printf -- '---\nid: T-1\n---\n' > "$V/ops/board/active/T-1.md"
REFUSE 'a busy board' "$V" M
rm -rf "$V/ops/board/active"
mkdir -p "$V/kit/ops"; : > "$V/kit/ops/pack.py"
REFUSE 'the POLARIS repo' "$V" M
rm -rf "$V/kit"
REFUSE 'no kit on this machine' "$V" env CLAUDE_CONFIG_DIR="$F/empty" bash -c 'cd "$1" && bash ops/polaris migrate' _ "$V"
OS="$F/oldcfg/polaris/kit"; mkdir -p "$OS"; cp -R "$ST/$KV" "$OS/0.0.1"; printf '0.0.1\n' > "$OS/current"
REFUSE 'an older kit' "$V" env CLAUDE_CONFIG_DIR="$F/oldcfg" bash -c 'cd "$1" && bash ops/polaris migrate' _ "$V"
printf '\n# edited\n' >> "$V/ops/PROTOCOL.md"
REFUSE 'kit files with uncommitted changes' "$V" M
git -C "$V" checkout -q -- ops/PROTOCOL.md
printf 'y\n' > "$V/b"; git -C "$V" add b
REFUSE 'a staged index' "$V" M
git -C "$V" rm -q --cached b; rm -f "$V/b"
[ "$(git -C "$V" rev-parse HEAD)" = "$B" ] && [ -z "$(git -C "$V" status --porcelain)" ] && echo '   after every refusal: HEAD unchanged, tree clean'

echo '== migrate =='
SNAP "$CLAUDE_CONFIG_DIR" > "$F/c0"
M > "$F/out" 2>&1; echo "   rc=$?"
mask < "$F/out" | sed 's/^/   /'
echo "   new commits: $(git -C "$V" rev-list --count "$B..HEAD") · subject: $(git -C "$V" log -1 --format=%s | mask)"
[ -z "$(git -C "$V" status --porcelain)" ] && echo '   tree: clean'
echo '   tracked after:'; git -C "$V" ls-files | sed 's/^/   | /'
cmp -s "$V/ops/polaris" "$ST/$KV/ops/launcher" && echo '   ops/polaris = the store kit'"'"'s launcher, byte-identical'
git -C "$V" ls-files -s ops/polaris | cut -c1-6 | sed 's/^/   ops\/polaris mode: /'
python - "$F/sj0" "$V/.claude/settings.json" <<'PY' | sed 's/^/   after: /'
import json, re, sys
d0 = json.load(open(sys.argv[1], encoding="utf-8"))
d = json.load(open(sys.argv[2], encoding="utf-8"))
h = [str(c.get("command", "")) for v in d.get("hooks", {}).values() for e in v for c in e.get("hooks", [])]
print("POLARIS hook entries: %s · outputStyle: %s · hooks left: %s" % (
    "yes" if any(re.search(r"ops/hooks/", x.replace(chr(92), "/")) for x in h) else "none", d.get("outputStyle"), ", ".join(h)))
print("permissions: " + ("the same as before" if d.get("permissions") == d0.get("permissions") else "CHANGED"))
rest = lambda x: {k: v for k, v in x.items() if k not in ("hooks", "outputStyle")}
print("every other key: " + ("as before" if rest(d) == rest(d0) else "CHANGED"))
PY
echo '   CLAUDE.md:'; sed 's/^/   | /' "$V/CLAUDE.md"
echo "   kit-seen: $(mask < "$V/.polaris/kit-seen")"
echo '   machine files written:'; SNAP "$CLAUDE_CONFIG_DIR" > "$F/c1"; CHANGED "$F/c0" "$F/c1" | sed 's#repos/[0-9]*$#repos/<cksum>#'
k="$(printf '%s' "$(git -C "$V" rev-parse --show-toplevel)" | cksum)"; k="${k%% *}"
[ "$(cat "$CLAUDE_CONFIG_DIR/polaris/awake/repos/$k" 2>/dev/null)" = "$(git -C "$V" rev-parse --show-toplevel)" ] && echo '   registry entry: present, names the repo'
( cd "$V" && bash ops/polaris version ) > "$F/out" 2>&1; printf '   version through the launcher: rc=%s · ' "$?"; head -n 1 "$F/out" | mask
REFUSE 'already joined' "$V" M

echo '== git revert of the migrate commit =='
git -C "$V" ls-files -s > "$F/i0.after"
git -C "$V" revert --no-edit HEAD > "$F/out" 2>&1; echo "   revert rc=$?"
[ -z "$(git -C "$V" diff "$B" HEAD)" ] && echo "   git diff <before> HEAD: empty" || echo "   git diff <before> HEAD: NOT EMPTY"
[ "$(git -C "$V" rev-parse "$B^{tree}")" = "$(git -C "$V" rev-parse 'HEAD^{tree}')" ] && echo '   tree: identical to <before>'
git -C "$V" ls-tree -r "$B" > "$F/t0"; git -C "$V" ls-files -s | awk '{print $1, $2}' > "$F/i1"
awk '{print $1, $3}' "$F/t0" | cmp -s - "$F/i1" && echo '   index: every mode and blob as before'
[ -z "$(git -C "$V" status --porcelain)" ] && echo '   tree: clean'
git -C "$V" diff --quiet "$B" -- && echo '   every tracked file on disk: the <before> bytes' || echo '   tracked files on disk: DIFFER from <before>'
