# update-pending — T-316 (ops/contracts/smooth.md § 6): the kit's own pending update never holds the next.
# A `publish: pr` project never commits an update itself, so the files the update wrote used to read as
# "uncommitted edits inside the kit" and froze every later update. Now an update whose self-commit did
# not happen records .polaris/kit-pending — one LF line `<git hash-object or -><TAB><path>` per kit
# path it made dirty, LC_ALL=C sorted — and both dirt checks drop a recorded path while it still hashes
# the same (a folder git shows collapsed, `?? d/`, goes when every file in it does). Byte-equality: a
# kit file a person edits after the record is dirt again and holds the update exactly as before.
#
# HERMETIC: one mktemp -d holds the project, a fake HOME/USERPROFILE/POLARIS_AWAKE_HOME, a stand-in
# index engine (nothing is computed), and a file:// channel + tarball built from the kit under test
# (curl on Windows needs file:///C:/…, hence cygpath -m); each release is that kit stamped 0.0.2,
# 0.0.3, 0.0.4, with a line in ops/PROTOCOL.md naming the release so that file changes every time.
# The project starts as a set-up board at 0.0.1 with no kit code committed — the first update writes
# all of it, uncommitted, the way a publish: pr project holds it. `--repo-only` and no repo: line, so
# neither the machine cache nor git ls-remote is reached. Counts move with every release: verdicts only.
# RUNTIME ~2.5 min beside busy lanes (two real updates and a setup; Windows/Git Bash, measured).
KIT_DIR="$(pwd)/kit"
KIT="$KIT_DIR/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake" POLARIS_UPDATE_NO_FANOUT=1
export POLARIS_INDEX_BIN="$FIX/engine"
mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT POLARIS_UPDATE_FORCE
printf '#!/bin/sh\nexit 1\n' > "$FIX/engine"; chmod +x "$FIX/engine"
U="$FIX"; command -v cygpath >/dev/null 2>&1 && U="/$(cygpath -m "$FIX")"
STAMP() { printf 'version: %s\nchannel: file://%s/chan/VERSION\ntarball: file://%s/kit.tgz\n' "$1" "$U" "$U"; }
RELEASE() { # RELEASE <version> — the channel and its tarball now offer the kit under test as <version>
  rm -rf "$FIX/polaris-v5" "$FIX/kit.tgz"; mkdir -p "$FIX/polaris-v5" "$FIX/chan"
  cp -R "$KIT_DIR/ops" "$FIX/polaris-v5/ops"; cp -R "$KIT_DIR/.claude" "$FIX/polaris-v5/.claude"
  cp "$KIT_DIR/CLAUDE.md" "$FIX/polaris-v5/CLAUDE.md"
  printf '\n<!-- release %s -->\n' "$1" >> "$FIX/polaris-v5/ops/PROTOCOL.md"
  STAMP "$1" > "$FIX/polaris-v5/ops/VERSION"; printf 'version: %s\n' "$1" > "$FIX/chan/VERSION"
  tar -czf "$FIX/kit.tgz" -C "$FIX" polaris-v5
}
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  echo x > a.txt; printf '.polaris/\n' > .gitignore
  mkdir -p ops/lib .polaris/brain; printf '# the kit, before its first update\n' > ops/polaris
  STAMP 0.0.1 > ops/VERSION
  bash "$KIT" init-board
  printf 'voice: plain\npublish: pr\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm 'a set-up board at 0.0.1'
) >/dev/null 2>&1
cd "$R"
V() { sed -n 's/^version: *//p' ops/VERSION | tr -d ' \r'; }
FOOT() { grep -v -e '^ops/board/' -e '^ops/contracts/' -e '^ops/tests/' -e '^ops/CONVENTIONS\.md$' -e '^ops/MAP\.md$' -e '^ops/SPRINT\.md$' \
           -e '^ops/RULES\.tsv$' -e '^ops/LAYOUT\.tsv$' -e '^ops/ROADMAP\.md$' \
         | grep -e '^ops/' -e '^\.claude/settings\.json$' -e '^\.claude/skills/polaris/' -e '^\.claude/skills/i-have-adhd/' \
           -e '^\.claude/output-styles/polaris\.md$' -e '^CLAUDE\.md$' -e '^\.gitignore$' -e '^\.gitattributes$'; }
REC() { # REC — what the record holds against the tree, as verdicts
  f=.polaris/kit-pending
  [ -s "$f" ] || { echo "   record: none"; return; }
  git status --porcelain -uall | cut -c4- | FOOT | LC_ALL=C sort > "$FIX/dirty"
  cut -f2 "$f" | LC_ALL=C sort > "$FIX/recorded"
  bad=0; while IFS="$(printf '\t')" read -r h p; do
    [ "$h" = "$(git hash-object -- "$p" 2>/dev/null)" ] || bad=$((bad + 1))
  done < "$f"
  echo "   record: sorted $(LC_ALL=C sort -c "$f" 2>/dev/null && echo yes || echo NO)" \
    "· every line <hash><TAB><path> $(awk -F'\t' 'NF != 2 || $1 !~ /^[0-9a-f]+$/ { b++ } END { print (b ? "NO" : "yes") }' "$f")" \
    "· every hash is the file's now $( [ "$bad" = 0 ] && echo yes || echo "NO ($bad)")"
  echo "   record = the kit's dirty files exactly: $(cmp -s "$FIX/recorded" "$FIX/dirty" && echo yes || echo NO)" \
    "· names ops/polaris $(grep -qx 'ops/polaris' "$FIX/recorded" && echo yes || echo NO)" \
    "· names ops/PROTOCOL.md $(grep -qx 'ops/PROTOCOL.md' "$FIX/recorded" && echo yes || echo NO)" \
    "· names .claude/settings.json $(grep -qx '.claude/settings.json' "$FIX/recorded" && echo yes || echo NO)"
}

echo '--- 1. publish: pr, a typed update: installed, not committed, and what it wrote is recorded'
RELEASE 0.0.2
bash "$KIT" update --repo-only > "$FIX/u1" 2>&1; echo "   rc=$? · version $(V) · commits on main: $(git rev-list --count HEAD)"
grep -xF '   not committed: publish: pr — the change goes through a pull request' "$FIX/u1" | sed 's/^ */   said: /'
REC

echo '--- 2. the next release, at session start'
RELEASE 0.0.3; rm -f .polaris/update-cache
mv .polaris/kit-pending "$FIX/kp.bak"
echo "   without the record (6.18): $(bash "$KIT" update --auto --say --repo-only 2>&1) · version $(V)"
mv "$FIX/kp.bak" .polaris/kit-pending
echo "   with it: $(bash "$KIT" update --auto --say --repo-only 2>&1)"
echo "   version $(V) · commits on main: $(git rev-list --count HEAD)"
REC

echo '--- 3. a person edits one recorded kit file: that is dirt again, and the update holds'
printf '# a hand edit\n' >> ops/PROTOCOL.md
RELEASE 0.0.4; rm -f .polaris/update-cache
echo "   said: $(bash "$KIT" update --auto --say --repo-only 2>&1) · version $(V) · the edit still there: $(grep -c '^# a hand edit$' ops/PROTOCOL.md)"
REC
