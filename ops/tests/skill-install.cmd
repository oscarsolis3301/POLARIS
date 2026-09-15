# `install.sh` and `uninstall` make one promise to a skill they did not write: it is the REPO'S, and
# it survives both untouched (ops/contracts/self-skills.md § 8, Invariant 5). A POLARIS-written
# skill (`metadata.polaris`) is knowledge `skill propose` distilled FROM this repo's own history —
# what keeps going wrong on a surface, its public API, the tests that cover it — so an install that
# swept `.claude/skills/` or an uninstall that took the whole dir would delete the repo's memory
# of itself with the kit. The two dirs the kit does own (polaris, i-have-adhd) are asserted the
# other way round: present after install, gone after uninstall — "exactly those two" is the pin.
# A human's own skill with no metadata at all (plain-y) rides along: the promise covers everything
# the kit did not write, whatever its frontmatter says.
#
# HERMETIC: a throwaway repo, install.sh --quiet INTO it, the installed ops/polaris run from inside
# it, and a throwaway keep-awake home so the fixture never registers in the owner's ~/.claude.
# Installer and uninstaller stdout both carry the version and the fixture path, so neither reaches
# this golden — only rc, `cmp` verdicts, presence tests and the two preview lines that name what
# stays. No path, timestamp, user or version below.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src .claude/skills/know-x .claude/skills/plain-y; echo x > src/a.txt
  printf -- '---\nname: know-x\ndescription: TRIGGER when a task owns src/x/; DO NOT TRIGGER elsewhere.\ndisable-model-invocation: false\nmetadata:\n  polaris: { paths: [src/x/], since: 2026-09-14, tier: 1, evidence: "6/80 tasks · 0 kickbacks" }\n---\n# src/x/ — what POLARIS already knows\n\n## What it is\n(no brain — run: ops/polaris brain)\n' > .claude/skills/know-x/SKILL.md
  printf -- '---\nname: plain-y\ndescription: A skill the human wrote by hand, with no metadata at all.\n---\n# plain-y\nTheirs.\n' > .claude/skills/plain-y/SKILL.md
  git add -A; git commit -qm init
) >/dev/null 2>&1
cp "$R/.claude/skills/know-x/SKILL.md" "$FIX/kx.snap"
cp "$R/.claude/skills/plain-y/SKILL.md" "$FIX/py.snap"
same() { # same <name> <stage> — the byte verdict, never the bytes
  cmp -s "$R/.claude/skills/$1/SKILL.md" "$FIX/$2" && echo "$1 byte-identical after $3" || echo "$1 CHANGED BY $3"
}
bash "$KIT_DIR/ops/install.sh" --quiet "$R" >/dev/null 2>&1; echo "install rc=$?"
for d in polaris i-have-adhd; do [ -f "$R/.claude/skills/$d/SKILL.md" ] && echo "install wrote $d" || echo "INSTALL MISSED $d"; done
same know-x kx.snap install
same plain-y py.snap install
echo "--- the uninstall preview names what stays (identity: metadata.polaris — plain-y is not POLARIS-written, and stays anyway)"
OUT="$(cd "$R" && bash ops/polaris uninstall 2>&1)"; echo "preview rc=$?"
printf '%s\n' "$OUT" | grep -c 'skill(s) POLARIS wrote stay'
printf '%s\n' "$OUT" | sed -n 's/^ *\(1 skill(s) POLARIS wrote stay.*\)$/\1/p;s/^ \{20,\}\(know-x\)$/named: \1/p'
[ -d "$R/ops" ] && echo "preview removed nothing" || echo "PREVIEW REMOVED ops/"
( cd "$R" && bash ops/polaris uninstall --yes ) >/dev/null 2>&1; echo "uninstall rc=$?"
for d in polaris i-have-adhd; do [ -e "$R/.claude/skills/$d" ] && echo "UNINSTALL LEAKED $d" || echo "uninstall removed $d"; done
[ -e "$R/ops" ] && echo "UNINSTALL LEAKED ops/" || echo "uninstall removed ops/"
[ -d "$R/.claude/skills/know-x" ] && echo "know-x dir present" || echo "KNOW-X DIR GONE"
same know-x kx.snap uninstall
same plain-y py.snap uninstall
