# install-update: what an UPDATE leaves behind (ops/contracts/save-hops.md § 16) — the layout pass
# offered on the first jump from an older POLARIS, and no churn in .claude/settings.json.
#
# Two field reports, one at each end of install.sh. The update that brings a repo onto the layout
# tooling is RUN BY THE OLD UPDATER, which knows nothing about the pass, so the one line naming it
# never appeared on that jump: the new installer now prints it itself, exactly when the updater that
# called it cannot (§ 16.4) — and stops telling an updater to run the `upgrade` it runs anyway
# (§ 16.3). And the update rewrote .claude/settings.json when nothing in it had changed, turning every
# LF into CRLF on Windows: a diff of pure noise in a file the owner is asked to review (§ 16.1).
#
# Nine installs is the whole truth table of § 16.4's five conditions — each one taken away alone,
# once (cases 1, 2, 4, 5, and 6-8: not due · another commit's sha · hops: off) — plus both pinned
# lines (3, 9).
#
# HERMETIC: throwaway repos under ONE mktemp -d. HOME, USERPROFILE and POLARIS_AWAKE_HOME all point
# inside it — Python's expanduser reads USERPROFILE on Windows, so a HOME-only fake would still reach
# the real ~/.claude. `.polaris/brain/` is made by hand so heal never spends ~20 s building one, and
# POLARIS_INDEX_BIN points at a stub engine whose `hops --due` PLANTS the verdict a case names
# (VERDICT=due · not · stale) — nothing is computed. An updater older than 6.12.0 is stood in for by
# OLD, which swaps the fixture's ops/lib/admin.sh for one without update_hops_hint() just before the
# install: the file such an updater runs from. Install output carries the version and the fixture
# path, so only rc, the routing token, counts, cmp verdicts, the settings lines and a sanitized tail
# reach this golden. Line endings are judged in Python, on bytes: Git Bash's awk and grep hide a CR.
#
# SIDE BY SIDE: case 1 builds the set-up repo once; cases 2-9 then each run in their own copy of it,
# all at once, and their reports print in case order. One install forks ~60 times and Windows charges
# ~0.1 s a fork, so nine in a row took two minutes beside busy lanes (measured); this way the wait is
# about three installs. RUNTIME ~25 s quiet, ~40 s beside busy lanes (measured, Windows/Git Bash).
KIT_DIR="$(pwd)/kit"
KSJ="$KIT_DIR/.claude/settings.json"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"
mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT VERDICT
cat > "$FIX/engine" <<'EOF'
#!/usr/bin/env bash
# the stand-in engine: `hops --due` writes the verdict the case asked for; anything else is a miss
[ "${1:-} ${2:-}" = "hops --due" ] || exit 1
s="$(git -C "$POLARIS_ROOT" rev-parse --verify -q main)"
case "${VERDICT:-not}" in
  due)   printf '%s\t0\tlayout pass due — planted\r\n' "$s" ;;   # a CR after the message is tolerated
  stale) printf '%s\t0\tlayout pass due — planted\n' 0000000000000000000000000000000000000000 ;;
  *)     printf '%s\t1\t-\n' "$s" ;;
esac > "$POLARIS_ROOT/.polaris/hops-due"
EOF
chmod +x "$FIX/engine"
export POLARIS_INDEX_BIN="$FIX/engine"
R="$FIX/repo"; SJ="$R/.claude/settings.json"; OUT="$FIX/out"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  echo x > a.txt
  git add -A; git commit -qm init
) >/dev/null 2>&1

# Every helper works on $R / $SJ / $OUT — the shared fixture for case 1, a lane's own copy after it.
I() { # I [VAR=value …] — ONE install: its verdict on one line, its stdout kept in $OUT
  env "$@" bash "$KIT_DIR/ops/install.sh" "$R" > "$OUT" 2> "$OUT.err"; rc=$?
  printf 'rc %s · %s · save-hops lines %s · upgrade lines %s · ▶ NEXT lines %s\n' "$rc" \
    "$(sed -n 's/^POLARIS [^ ]* installed · //p' "$OUT")" \
    "$(grep -c '^▶ NEXT — save hops' "$OUT")" \
    "$(grep -c -e '^   live board: finish it with these two lines (never re-run INIT):$' -e '^     cd ' -e '^     bash ops/polaris upgrade$' "$OUT")" \
    "$(grep -c '^▶ NEXT' "$OUT")"
}
TAIL() { tail -n 3 "$OUT" | sed 's/^POLARIS [^ ]* installed/POLARIS <version> installed/'; }
OLD() { printf '# an older kit'"'"'s admin.sh: it has never heard of the layout pass\n' > "$R/ops/lib/admin.sh"; }
SAID() { sed -n 's/^✅ \(\.claude\/settings\.json: .*\)$/\1/p' "$OUT"; }
SAME() { if cmp -s "$1" "$SJ"; then echo 'settings.json: byte-identical'; else echo 'settings.json: REWRITTEN'; fi; }
WRITE() { # WRITE <indent> <lf|crlf> [rule] [key…] — settings.json = the kit's object, minus its last allow rule / those keys
  python - "$KSJ" "$SJ" "$@" <<'PY'
import json, sys
kit, out, indent, nl, drop = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5:]
d = json.load(open(kit, encoding="utf-8"))
for k in drop:
    if k == "rule":
        d["permissions"]["allow"].pop()
    else:
        d.pop(k)
text = json.dumps(d, indent=indent) + "\n"
open(out, "wb").write(text.replace("\n", "\r\n" if nl == "crlf" else "\n").encode("utf-8"))
PY
}
ENDS() { # ENDS <lf|crlf> — every line's ending, on bytes; then whether the object is the kit's own now
  python - "$SJ" "$KSJ" "$1" <<'PY' | tr -d '\r'
import json, sys
raw = open(sys.argv[1], "rb").read()
lines = raw.split(b"\n")[:-1]
cr = sum(1 for l in lines if l.endswith(b"\r"))
if sys.argv[3] == "crlf":
    ok = len(lines) > 1 and cr == len(lines) and raw.endswith(b"\r\n")
    print("every line ends CRLF" if ok else "NOT every line CRLF: %d of %d" % (cr, len(lines)))
else:
    ok = len(lines) > 1 and b"\r" not in raw and raw.endswith(b"\n")
    print("every line ends LF, no CR anywhere" if ok else "a CR on %d of %d lines" % (cr, len(lines)))
same = json.loads(raw.decode("utf-8")) == json.load(open(sys.argv[2], encoding="utf-8"))
print("the object: the kit's own" if same else "the object: DIFFERS from the kit's")
PY
}

echo '--- 1. a never-set-up repo, updated: setup comes first, the pass waits'
# Everything else the line needs is already true — an updater ran us, no marker, no admin.sh at all
# (so none with update_hops_hint), a due verdict on disk for main's sha. Only "never set up" says no.
mkdir -p "$R/.polaris"
printf '%s\t0\tlayout pass due — planted\n' "$(git -C "$R" rev-parse main)" > "$R/.polaris/hops-due"
I POLARIS_SHA=abc1234
if cmp -s "$KSJ" "$SJ"; then echo "settings.json: the kit's own, copied as it ships"; else echo 'settings.json: NOT the kit copy'; fi
( cd "$R" && bash ops/polaris init-board ) >/dev/null 2>&1
printf 'base: main\nvoice: standard\n' > "$R/ops/CONVENTIONS.md"
mkdir -p "$R/.polaris/brain"

lane() { R="$FIX/r$1"; SJ="$R/.claude/settings.json"; OUT="$FIX/out$1"; cp -R "$FIX/repo" "$R"; }

c2() { lane 2
  echo '--- 2. a zip or skill install (no POLARIS_SHA): the upgrade lines stay; LF settings, nothing to merge'
  # No updater ran this one, so it keeps its three lines, and says nothing about the pass although an
  # older admin.sh and a due verdict are both in place. The settings file is the kit's own object in a
  # formatting json.dumps(indent=2) never writes, LF: nothing to merge → not one byte touched, and the
  # line about it is the one it always printed.
  WRITE 4 lf; cp "$SJ" "$FIX/lf.json"; OLD
  I VERDICT=due
  sed -n 's/^   \(live board: .*\)$/\1/p; s/^     \(bash ops\/polaris upgrade\)$/\1/p; s/^     cd .*$/cd <the repo>/p' "$OUT"
  SAID
  SAME "$FIX/lf.json"
}

c3() { lane 3
  echo '--- 3. an updater older than 6.12.0 (POLARIS_SHA set, here empty), due, a quiet board: the first jump'
  # The line, once, LAST, right after the routing line — and no upgrade lines: that updater runs upgrade
  # itself. The same install meets a CRLF settings file missing one allow rule and both attribution
  # keys: each writer adds what is missing, and every line keeps its CRLF.
  WRITE 2 crlf rule includeCoAuthoredBy attribution; OLD
  I VERDICT=due POLARIS_SHA=
  TAIL
  SAID
  ENDS crlf
  cp "$SJ" "$FIX/crlf.json"
  echo '--- 4. the current updater passes POLARIS_UPDATE_HINTS=1 and prints the line itself: none here'
  # ...and this second install over that CRLF file has nothing left to merge: byte-identical.
  OLD
  I VERDICT=due POLARIS_SHA=abc1234 POLARIS_UPDATE_HINTS=1
  SAME "$FIX/crlf.json"
}

c5() { lane 5
  echo '--- 5. a 6.12.0 updater: its admin.sh defines update_hops_hint() and prints its own line: none here'
  # Every copy holds the admin.sh case 1's install wrote — the kit's own, so this is the real
  # definition. Same install: an LF settings file missing one allow rule gets it back, and stays LF.
  if grep -q '^update_hops_hint()' "$R/ops/lib/admin.sh"; then echo 'admin.sh defines update_hops_hint(): yes'; else echo 'admin.sh defines update_hops_hint(): NO'; fi
  WRITE 2 lf rule
  I VERDICT=due POLARIS_SHA=abc1234
  SAID
  ENDS lf
}

c6() { lane 6; echo '--- 6. not due: no line'; OLD; I VERDICT=not POLARIS_SHA=abc1234; }
c7() { lane 7; echo "--- 7. a due verdict about another commit (not main's sha now): no line"; OLD; I VERDICT=stale POLARIS_SHA=abc1234; }
c8() { lane 8
  echo '--- 8. hops: off, whatever the cache says: no line'
  OLD; printf 'base: main\nvoice: standard\nhops: off\n' > "$R/ops/CONVENTIONS.md"
  I VERDICT=due POLARIS_SHA=abc1234
}
c9() { lane 9
  echo '--- 9. due on a busy board (a task waits in ready/): the other pinned line, once, last'
  OLD; printf -- '---\nid: T-1\n---\n' > "$R/ops/board/ready/T-1.md"
  I VERDICT=due POLARIS_SHA=abc1234
  TAIL
}

for n in 2 3 5 6 7 8 9; do ( "c$n" ) > "$FIX/report$n" 2>/dev/null & done
wait
for n in 2 3 5 6 7 8 9; do cat "$FIX/report$n"; done
