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
cp -R "$C" "$FIX/first"
HOME="$FIX" USERPROFILE="$FIX" python polaris-v5.zip --claude-skill --no-permissions >/dev/null 2>&1
diff -r "$FIX/first" "$C" >/dev/null 2>&1 \
  && echo "a second run rewrites nothing" || echo "SECOND RUN REWROTE FILES — the machine-armed line will nag forever"
rm -rf "$FIX"
