#!/usr/bin/env bash
# POLARIS v5 — one-command install into any repo.
#   bash ops/install.sh <target-repo>
# Fresh target: copies CLAUDE.md + ops/ + .claude/, sets exec bits, pins LF.
# Existing CLAUDE.md: POLARIS content is PREPENDED (constraints early = adherence).
# Existing .claude/settings.json: the hooks block is MERGED (python stdlib).
# Existing live board: board state and INIT artifacts are never touched — kit
# code files are refreshed and you finish with `bash ops/polaris upgrade`.
# Idempotent: safe to re-run.
set -eu

die() { printf '⛔ %s\n' "$*" >&2; exit 1; }
say() { printf '✅ %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: bash ops/install.sh <target-repo>}"
[ -d "$TARGET" ] || die "no such directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$KIT" ] || die "target is the kit itself"
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$TARGET is not a git repo — run: git -C \"$TARGET\" init"

# `-c pass` proves a REAL interpreter (the Windows Store python3 stub passes command -v).
PY=""; python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; } || true

# --- ops/ ---------------------------------------------------------------------
KIT_CODE="polaris dashboard.py MANUAL.md PROMPTS.md install.sh"   # + roles/ templates/ hooks/ ci/
if [ -d "$TARGET/ops/board" ]; then
  note "live board detected — refreshing kit code only (board, RULES, CONVENTIONS, MAP, SPRINT untouched)"
  for f in $KIT_CODE; do cp "$KIT/ops/$f" "$TARGET/ops/$f"; done
  for d in roles templates hooks ci; do mkdir -p "$TARGET/ops/$d"; cp "$KIT/ops/$d/"* "$TARGET/ops/$d/"; done
  UPGRADE=1
else
  mkdir -p "$TARGET/ops"
  cp "$KIT"/ops/*.md "$KIT/ops/polaris" "$KIT/ops/dashboard.py" "$KIT/ops/install.sh" "$TARGET/ops/"
  for d in roles templates hooks ci board contracts; do
    mkdir -p "$TARGET/ops/$d"
    cp -R "$KIT/ops/$d/." "$TARGET/ops/$d/"
  done
  UPGRADE=0
fi
chmod +x "$TARGET/ops/polaris" "$TARGET/ops/hooks/ownership-guard.sh" "$TARGET/ops/install.sh" 2>/dev/null || true
say "ops/ installed"

# --- CLAUDE.md ------------------------------------------------------------------
MARK="POLARIS v5 — Parallel Sprint Protocol"
if [ ! -f "$TARGET/CLAUDE.md" ]; then
  cp "$KIT/CLAUDE.md" "$TARGET/CLAUDE.md"; say "CLAUDE.md installed"
elif grep -q "$MARK" "$TARGET/CLAUDE.md"; then
  note "CLAUDE.md already carries POLARIS — left as is"
else
  TMP="$TARGET/CLAUDE.md.polaris-tmp"
  { cat "$KIT/CLAUDE.md"; printf '\n---\n\n'; cat "$TARGET/CLAUDE.md"; } > "$TMP"
  mv "$TMP" "$TARGET/CLAUDE.md"
  say "CLAUDE.md: POLARIS prepended above existing content"
fi

# --- .claude/ (skill + PreToolUse write-guard) ----------------------------------
mkdir -p "$TARGET/.claude/skills/polaris"
cp "$KIT/.claude/skills/polaris/SKILL.md" "$TARGET/.claude/skills/polaris/SKILL.md"
SJ="$TARGET/.claude/settings.json"
if [ ! -f "$SJ" ]; then
  cp "$KIT/.claude/settings.json" "$SJ"; say ".claude/ installed (skill + write-guard hook)"
elif grep -q "ownership-guard.sh" "$SJ"; then
  note ".claude/settings.json already wires the guard — left as is"
elif [ -n "$PY" ]; then
  "$PY" - "$SJ" "$KIT/.claude/settings.json" <<'EOF'
import json, sys
tgt_p, kit_p = sys.argv[1], sys.argv[2]
tgt, kit = json.load(open(tgt_p)), json.load(open(kit_p))
entry = kit["hooks"]["PreToolUse"][0]
tgt.setdefault("hooks", {}).setdefault("PreToolUse", []).append(entry)
open(tgt_p, "w").write(json.dumps(tgt, indent=2) + "\n")
EOF
  say ".claude/settings.json: guard hook merged into existing hooks"
else
  note "⚠ .claude/settings.json exists and python is unavailable — merge by hand:"
  note "  add the hooks.PreToolUse entry from $KIT/.claude/settings.json"
fi

# --- .gitattributes: LF-pin scripts (autocrlf=true clones break CRLF bash) ------
GA="$TARGET/.gitattributes"
grep -q '^ops/polaris text eol=lf' "$GA" 2>/dev/null || {
  { echo 'ops/polaris text eol=lf'; echo '*.sh text eol=lf'; } >> "$GA"
  say ".gitattributes: kit scripts pinned to LF"
}

# --- next steps -----------------------------------------------------------------
say "POLARIS installed into $TARGET"
if [ "$UPGRADE" = 1 ]; then
  note "live board: finish with  cd \"$TARGET\" && bash ops/polaris upgrade"
else
  note "commit, then open a session with:  \"You are INIT.\""
fi
note "Claude Code will ask to trust the project hook on first use — that is the write-guard (read ops/hooks/ownership-guard.sh first)."
