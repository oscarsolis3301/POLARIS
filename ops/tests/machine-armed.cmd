# Arming a MACHINE must include the VOICE, not just the installer.
#
# arm_machine() taught a computer how to INSTALL POLARIS — the skill, the cached kit, the
# permission rules, keep-awake — and nothing about how to TALK. The output style (the warm plain
# voice, and the 🎉 that `finish` earns) and the vendored /i-have-adhd skill were copied by
# install.sh into <repo>/.claude and nowhere else. So on a second computer, or in any repo where
# the installer never ran, there is no style to select and no skill to invoke: the human gets bare
# harness voice, never a completion celebration, and no way to tell which half is missing. That is
# the confetti gap, and it is invisible from inside the repo that has them.
#
# Hermetic: builds the zip with the repo's own `build:` and installs into a throwaway HOME.
# HOME *and* USERPROFILE, exactly as .github/workflows/ci.yml does — ntpath.expanduser reads
# USERPROFILE and ignores HOME outright, so a HOME-only fake would silently test the real profile
# on Windows and prove nothing at all.
#
# Two NON-goals are asserted as hard as the goals (ops/contracts/first-run.md § 3), because both
# are the kind of helpful-looking change a later reader would make on purpose:
#   - the machine copy of i-have-adhd keeps `disable-model-invocation: true`. That flag is the only
#     thing keeping the skill out of every session on the box; the opt-in is a REPO preference
#     (`adhd:`), applied to the repo's copy by install.sh.
#   - no ~/.claude/settings.json is created. A machine-wide outputStyle would restyle every
#     non-POLARIS repo on the machine; selection stays per repo or per session.
python kit/ops/pack.py --allow-dirty >/dev/null 2>&1 || echo "PACK FAILED — nothing below proves anything"
FIX="$(mktemp -d)"
C="$FIX/.claude"
HOME="$FIX" USERPROFILE="$FIX" python polaris-v5.zip --claude-skill --no-permissions >/dev/null 2>&1
for f in skills/polaris-install/SKILL.md skills/polaris-install/polaris-v5.zip \
         output-styles/polaris.md \
         skills/i-have-adhd/SKILL.md skills/i-have-adhd/LICENSE skills/i-have-adhd/SOURCE.md; do
  [ -f "$C/$f" ] && echo "armed $f" || echo "MISSING $f"
done
grep -q '^name: POLARIS$' "$C/output-styles/polaris.md" 2>/dev/null \
  && echo "the style is the POLARIS one" || echo "OUTPUT STYLE IS NOT OURS"
grep -q '^disable-model-invocation: true$' "$C/skills/i-have-adhd/SKILL.md" 2>/dev/null \
  && echo "machine copy stays opt-in" || echo "OPT-IN FLAG FLIPPED MACHINE-WIDE"
[ -f "$C/settings.json" ] \
  && echo "MACHINE settings.json WRITTEN — that restyles every non-POLARIS repo" \
  || echo "no machine settings.json written"
[ -f "$C/polaris/fable-restored" ] \
  && echo "FABLE MARKER WRITTEN under --no-permissions — that flag promises nothing is" \
  || echo "no Fable marker written"
cp -R "$C" "$FIX/first"
HOME="$FIX" USERPROFILE="$FIX" python polaris-v5.zip --claude-skill --no-permissions >/dev/null 2>&1
diff -r "$FIX/first" "$C" >/dev/null 2>&1 \
  && echo "a second run rewrites nothing" || echo "SECOND RUN REWROTE FILES — the machine-armed line will nag forever"
rm -rf "$FIX"

# ---- the model guard on an ARMED machine (ops/contracts/speed.md § 2 and § 2b) ----------------
# The run above proves what --no-permissions must NOT write. This one arms for real — permissions on
# — and pins what it MUST write: model-guard's five entries (PreToolUse "*" plus SessionStart,
# PreModelSwitch, PostModelSwitch and PostToolUse "Agent"), merged, idempotent, never clobbering a
# human's own hooks. availableModels is the HUMAN's list (§ 2b, owner 2026-11-09): kit code never
# creates it, strips it or adds to it, except ONE restore. Older kits took Fable out on every arm, so
# the first arm that finds no ~/.claude/polaris/fable-restored gives "fable" back to a list without
# it, then writes that marker whatever the key held. The restore runs once; after it the list is
# untouched, whatever its owner does to it. Same fixture discipline: HOME, USERPROFILE and
# POLARIS_AWAKE_HOME all point into the mktemp -d, so the real ~/.claude is never read or written.
FIX="$(mktemp -d)"
SJ="$FIX/.claude/settings.json"; MK="$FIX/.claude/polaris/fable-restored"
arm() { HOME="$FIX" USERPROFILE="$FIX" POLARIS_AWAKE_HOME="$FIX/awake" python polaris-v5.zip --claude-skill "$@" 2>/dev/null; }
# The ✅ line the restore prints under --verbose, its path made portable; nothing at all when it is silent.
said() { tr -d '\r' | grep -a '^✅ availableModels:' | sed 's# in .* — # in <settings> — #'; }
show() { # python prints CRLF on Windows; every .expected is LF
  python - "$SJ" <<'PY' | tr -d '\r'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("  availableModels: %s" % (json.dumps(d["availableModels"]) if "availableModels" in d else "(no key: every model is offered)"))
for ev in ("PreToolUse", "SessionStart", "PreModelSwitch", "PostModelSwitch", "PostToolUse"):
    ours, other = [], 0
    for e in d.get("hooks", {}).get(ev, []):
        cmds = " ".join(str(h.get("command", "")) for h in e.get("hooks", [])).replace("\\", "/")
        if "polaris/model-guard.sh" in cmds: ours.append(e.get("matcher", "-"))
        else: other += 1
    print("  %-16s model-guard x%d %s · %d other entr%s" % (ev, len(ours), ours, other, "y" if other == 1 else "ies"))
PY
}
mark() { if [ -f "$MK" ]; then echo "  fable-restored marker: written"; else echo "  fable-restored marker: none"; fi; }
# setlist <json> — set availableModels to <json> in place, nothing else touched. Written exactly the
# way an arm writes the file (indent 2, the platform's own line ends): the keep-awake install rewrites
# it on every arm, so any other byte layout would read as a change nobody made. The value rides the
# environment, never argv: a Windows argv mangles the quotes in it.
setlist() {
  AM="$1" python - "$SJ" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["availableModels"] = json.loads(os.environ["AM"])
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
PY
}
same() { if cmp -s "$FIX/first.json" "$SJ"; then echo "$1"; else echo "$2"; fi; }

echo "== a fresh machine, armed: no list is created, and the restore is marked done =="
arm >/dev/null; show; mark
echo "== a machine an older kit armed: --no-permissions writes nothing, a real arm gives Fable back =="
rm -f "$MK"
printf '%s\n' '{"availableModels": ["opus", "sonnet", "haiku"], "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "mine.sh"}]}], "PostToolUse": [{"matcher": "Agent", "hooks": [{"type": "command", "command": "mine-too.sh"}]}]}}' > "$SJ"
cp "$SJ" "$FIX/first.json"
arm --no-permissions >/dev/null
same "  --no-permissions: settings.json byte-identical" "  --NO-PERMISSIONS REWROTE settings.json"; mark
arm --verbose | said
show; mark
echo "== the owner takes Fable out again: every later arm leaves their list alone =="
setlist '["opus", "sonnet"]'
cp "$SJ" "$FIX/first.json"
arm --verbose | said
same "  re-armed: settings.json byte-identical — their Fable-free list kept as found" \
     "  RE-ARMING CHANGED settings.json — the merge is not idempotent, or it overrode a human's list"
echo "== no marker yet and nothing to restore: each value is left as found, and the marker is written =="
for v in '["opus", "claude-fable-5"]' '"opus"' 'null'; do
  rm -f "$MK"; setlist "$v"; cp "$SJ" "$FIX/first.json"
  arm --verbose | said
  printf '  %-26s %s · %s\n' "$v" "$(same 'left as found' 'CHANGED')" "$(mark | sed 's/^  //')"
done
echo "== unreadable settings: never rewritten, and no marker, so the restore waits for a readable file =="
rm -f "$MK"; printf 'this is not json' > "$SJ"; cp "$SJ" "$FIX/first.json"
arm --verbose | said
same "  settings.json: left as found" "  settings.json: REWRITTEN"; mark
rm -rf "$FIX"
