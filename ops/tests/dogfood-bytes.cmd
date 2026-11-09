# dogfood-bytes: the release check proves the published kit is THIS commit's kit, byte for byte,
# before it installs anything, then runs the quick check (ops/contracts/minutes.md § 1.3).
#
# HERMETIC: a clone of the tree this golden runs in (its HEAD — so it tests the pack.py being
# built, never a fixed path), under ONE mktemp -d. HOME and USERPROFILE both point inside it —
# Python's expanduser reads USERPROFILE on Windows, so a HOME-only fake would still reach the real
# ~/.claude. The clone packs its own zip; each case then dogfoods it in its own copy of the clone,
# with POLARIS_DOGFOOD_ZIP pointing at a file:// url, so nothing touches the network or this tree.
# Only verdicts reach the golden: rc, the pinned lines (version swapped for <version>), yes/no.
#
# SPEED: an install's heal builds a brain (~20 s) unless `.polaris/brain/` already exists, so each
# copy gets one by hand, and POLARIS_INDEX_BIN points at a stub engine that answers nothing. Each
# copy is a local clone of the first (hardlinked objects, ~3 s; `cp -r` was ~7 s), and the three
# cases run side by side. One dogfood measured ~50 s as-is and ~30 s with both (Windows/Git Bash).
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake" PYTHONDONTWRITEBYTECODE=1
mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT POLARIS_DOGFOOD_ZIP
printf '#!/usr/bin/env bash\nexit 1\n' > "$FIX/engine"; chmod +x "$FIX/engine"
export POLARIS_INDEX_BIN="$FIX/engine"
C="$FIX/clone"
( set -e
  git -c core.autocrlf=false clone -q "$PWD" "$C"
  git -C "$C" config core.autocrlf false
  git -C "$C" config user.email t@t; git -C "$C" config user.name t
  cd "$C"; python kit/ops/pack.py
  mv "$C/polaris-v5.zip" "$FIX/kit.zip"
) >/dev/null 2>&1 || { echo "setup failed: the clone did not pack"; exit 1; }
WANT="$(sed -n 's/^version: *//p' "$C/kit/ops/VERSION" | head -n 1)"
URI() { python -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$1"; }

# case 2's zip: the kit as built, with ONE byte changed in ops/install.sh
python - "$FIX/kit.zip" "$FIX/bad.zip" <<'PY'
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as a, zipfile.ZipFile(dst, "w") as b:
    b.comment = a.comment
    for info in a.infolist():
        blob = a.read(info)
        if info.filename == "polaris-v5/ops/install.sh":
            blob = blob[:10] + bytes([blob[10] ^ 1]) + blob[11:]
        b.writestr(info, blob)
PY

DOG() { # DOG <n> <zip> — a fresh copy n of the clone, dogfooded from that zip; output kept, rc in <n>.rc
  ( git -c core.autocrlf=false clone -q "$C" "$FIX/c$1" && cd "$FIX/c$1" && mkdir -p .polaris/brain &&
    git config core.autocrlf false && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  # case 3: one more commit, touching only a file outside kit/ — the stamp now names an older commit
  [ "$1" = 3 ] && ( cd "$FIX/c3" && echo extra > outside-kit.txt && git add outside-kit.txt &&
    git commit -qm extra ) >/dev/null 2>&1
  ( cd "$FIX/c$1" && POLARIS_DOGFOOD_ZIP="$(URI "$2")" python kit/ops/pack.py --dogfood \
      > "$FIX/$1.out" 2>&1; echo $? > "$FIX/$1.rc" )
}
DOG 1 "$FIX/kit.zip" & DOG 2 "$FIX/bad.zip" & DOG 3 "$FIX/kit.zip" &
wait

CLOSE() { sed -n 's/^✅ POLARIS [^ ]* installed/✅ POLARIS <version> installed/p' "$FIX/$1.out"; }
printf 'case 1 · the kit as built: rc %s\n' "$(cat "$FIX/1.rc")"
grep -c '^   proving the bytes:  the published kit against this commit$' "$FIX/1.out" | sed 's/^/   bytes line: /'
grep -c '^   proving the board still works:  ops/polaris doctor --fast$' "$FIX/1.out" | sed 's/^/   quick-check line: /'
CLOSE 1 | sed 's/^/   /'
GOT="$(sed -n 's/^version: *//p' "$FIX/c1/ops/VERSION" | head -n 1)"
if [ "$GOT" = "$WANT" ]; then echo "   ops/VERSION now = kit/ops/VERSION: yes"; else echo "   ops/VERSION now = kit/ops/VERSION: NO"; fi

printf 'case 2 · one byte changed in ops/install.sh: rc %s\n' "$(cat "$FIX/2.rc")"
grep -e '^⛔ ' -e '^   Dogfood from' "$FIX/2.out" | sed 's/^/   /'
grep -c '^   installing ' "$FIX/2.out" | sed 's/^/   install lines: /'
if [ -z "$(git -C "$FIX/c2" status --porcelain)" ]; then echo "   repo untouched: yes"; else echo "   repo untouched: NO"; fi

printf 'case 3 · one more commit outside kit/: rc %s\n' "$(cat "$FIX/3.rc")"
CLOSE 3 | sed 's/^/   /'
