# update-arms: an UPDATE re-arms what a machine already armed (ops/contracts/speed.md § 2b v1.3).
#
# The OLD updater's code runs an update, so on a machine that only ever updates, the guard it once
# copied to ~/.claude/polaris/model-guard.sh stays the old Fable-blocking one, and the one-time
# Fable restore lives in a bootstrap.py nobody calls. install.sh is the one piece of NEW code an
# update runs, so on the updater path (POLARIS_SHA set) it refreshes a guard that is already there
# and runs bootstrap._restore_fable_once() when the guard is registered. Silent, fail-open, and it
# creates or registers nothing new.
#
# Five cases, the contract's list: (1) an old guard, registered, a list without Fable → the guard's
# bytes become the kit's, the list gains "fable" once, the marker is written · (2) a second run on
# that machine changes nothing · (3) no guard file (and so no hook) → nothing is created · (4) a guard on disk but not
# registered → the script is refreshed, the list is untouched · (5) no POLARIS_SHA (a zip or skill
# install) → nothing happens. Then: the install output gains no line — every first install prints
# the same number of lines whether or not anything was re-armed.
#
# HERMETIC: one mktemp -d. Every case gets its OWN fake home with HOME and USERPROFILE pointed at it
# together (Python's expanduser reads USERPROFILE on Windows, so a HOME-only fake would reach the real
# ~/.claude), and POLARIS_AWAKE_HOME inside it. Repos are plain git repos with no CONVENTIONS.md, so
# heal never runs and no brain is built: what this proves happens before heal. Lanes run side by side
# (one install forks ~60 times on Windows), reports print in case order. RUNTIME ~15 s (measured,
# Windows/Git Bash).
KIT_DIR="$(pwd)/kit"
KG="$KIT_DIR/ops/hooks/model-guard.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT CLAUDE_CONFIG_DIR

home() { # home <n> — case n's machine and repo; its paths in H / MG / SJ / MK / R
  H="$FIX/h$1"; MG="$H/.claude/polaris/model-guard.sh"; SJ="$H/.claude/settings.json"
  MK="$H/.claude/polaris/fable-restored"; R="$FIX/r$1"
  mkdir -p "$H/.claude"
  ( set -e
    git init -q "$R"; cd "$R"; git config user.email t@t; git config user.name t
    echo x > a.txt; git add -A; git commit -qm init
  ) >/dev/null 2>&1
}
OLDGUARD() { mkdir -p "$H/.claude/polaris"; printf '#!/usr/bin/env bash\n# an older kit'"'"'s guard: it still refuses Fable\nexit 0\n' > "$MG"; }
SETTINGS() { # SETTINGS <registered|unregistered> — a list with no Fable, the guard's hook or someone else's
  if [ "$1" = registered ]; then c='bash \"$HOME/.claude/polaris/model-guard.sh\"'; else c='bash \"$HOME/my-own-hook.sh\"'; fi
  printf '{\n  "availableModels": [\n    "opus",\n    "sonnet",\n    "haiku"\n  ],\n  "hooks": {\n    "PreToolUse": [\n      {\n        "matcher": "*",\n        "hooks": [\n          {\n            "type": "command",\n            "command": "%s"\n          }\n        ]\n      }\n    ]\n  }\n}\n' "$c" > "$SJ"
}
I() { # I [VAR=value …] — ONE install, the way an updater runs it; its stdout kept for the line count
  env HOME="$H" USERPROFILE="$H" POLARIS_AWAKE_HOME="$H/awake" "$@" \
    bash "$KIT_DIR/ops/install.sh" "$R" > "$H.out" 2> "$H.err"
  echo "rc $?"
}
GUARD() { if [ ! -e "$MG" ]; then echo 'guard: none on disk'; elif cmp -s "$MG" "$KG"; then echo "guard: the kit's own bytes"; else echo 'guard: NOT the kit copy'; fi; }
MODELS() { python - "$SJ" <<'PY' | tr -d '\r'
import json, sys
try:
    print("availableModels:", json.dumps(json.load(open(sys.argv[1], encoding="utf-8")).get("availableModels")))
except OSError:
    print("availableModels: no settings.json")
PY
}
MARKER() { if [ -f "$MK" ]; then echo 'marker: written'; else echo 'marker: none'; fi; }
ONDISK() { # what this fake machine holds under .claude, sorted
  ( cd "$H/.claude" && find . -type f | sed 's|^\./||' | sort | tr '\n' ' ' ); echo
}

c1() { home 1
  echo '--- 1. an old guard, registered, a list without Fable: refreshed, Fable back once, marker'
  OLDGUARD; SETTINGS registered
  I POLARIS_SHA=x
  GUARD; MODELS; MARKER
  [ -x "$MG" ] && echo 'guard: executable' || echo 'guard: NOT executable'
  cp "$SJ" "$FIX/sj1"; cp "$MG" "$FIX/mg1"
  echo '--- 2. the same machine, updated again: nothing changes'
  I POLARIS_SHA=x
  if cmp -s "$SJ" "$FIX/sj1"; then echo 'settings.json: byte-identical'; else echo 'settings.json: REWRITTEN'; fi
  if cmp -s "$MG" "$FIX/mg1"; then echo 'guard: byte-identical'; else echo 'guard: REWRITTEN'; fi
  MODELS
}
c3() { home 3
  echo '--- 3. a machine the guard never reached (no file, no hook): nothing is created'
  # The realistic shape of "no guard file": a box armed before the guard existed, or with
  # --no-permissions never followed up. Its own hook and a Fable-less list are left exactly alone.
  SETTINGS unregistered
  I POLARIS_SHA=x
  GUARD; MODELS; MARKER
  printf 'on disk: '; ONDISK
}
c4() { home 4
  echo '--- 4. a guard on disk but not registered: the script is refreshed, the list is untouched'
  OLDGUARD; SETTINGS unregistered
  I POLARIS_SHA=x
  GUARD; MODELS; MARKER
}
c5() { home 5
  echo '--- 5. no POLARIS_SHA (a zip or skill install): nothing happens'
  OLDGUARD; SETTINGS registered
  I
  GUARD; MODELS; MARKER
}

for n in 1 3 4 5; do ( "c$n" ) > "$FIX/report$n" 2>/dev/null & done
wait
for n in 1 3 4 5; do cat "$FIX/report$n"; done

echo '--- the install output gains no line'
# Every case's FIRST install met a fresh repo, so each printed the same lines whatever was re-armed:
# case 1 re-armed both, 3 nothing, 4 the guard alone, 5 ran no updater at all. (Case 1's second
# install overwrote its output; case 3 stands in as the nothing-armed baseline.)
n3="$(wc -l < "$FIX/h3.out")"; n4="$(wc -l < "$FIX/h4.out")"; n5="$(wc -l < "$FIX/h5.out")"
[ "$n4" = "$n3" ] && echo 'guard refreshed vs nothing armed: same line count' || echo "LINE COUNT MOVED: $n4 vs $n3"
[ "$n5" = "$n3" ] && echo 'no updater vs updater: same line count' || echo "LINE COUNT MOVED: $n5 vs $n3"
grep -l 'model-guard\|availableModels\|fable' "$FIX"/h*.out "$FIX"/h*.err >/dev/null 2>&1 \
  && echo 'OUTPUT MENTIONS THE GUARD OR THE LIST' || echo 'no output line names the guard or the list'
