#!/usr/bin/env bash
# POLARIS v5 — one-command install into any repo.
#   bash ops/install.sh <target-repo>
# Fresh target: copies CLAUDE.md + ops/ + .claude/, sets exec bits, pins LF.
# Existing CLAUDE.md: POLARIS content is PREPENDED (constraints early = adherence).
# Existing .claude/settings.json: the hooks block is MERGED (python stdlib).
# Existing live board: board state and INIT artifacts are never touched — kit
# code files are refreshed and you finish with `bash ops/polaris upgrade`.
# Idempotent: safe to re-run.
#
# "Live board" means ops/CONVENTIONS.md exists — i.e. INIT has run. It does NOT mean
# ops/board/ exists: this installer used to ship the six empty board columns, so every
# fresh install looked like a live board to itself, to CLAUDE.md's role dispatch and to
# INIT.md's precondition — which then told INIT to refuse the very job it was handed.
# The board is now created by `polaris init-board` (INIT runs it), so its existence is
# once again the truth it was always meant to be.
set -eu

die() { printf '⛔ %s\n' "$*" >&2; exit 1; }
say() { printf '✅ %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

KIT="$(cd "$(dirname "$0")/.." && pwd)"

# Target resolution.
#   arg given → that directory; `git init` it if it isn't a repo yet (greenfield).
#   no arg    → the git repo the kit was unzipped inside.
# The asymmetry is deliberate: zero-arg mode NEVER runs `git init`. A kit unzipped on the
# Desktop and run with no arg would otherwise turn the whole Desktop into a git repo.
if [ $# -ge 1 ]; then
  TARGET="$1"
  [ -d "$TARGET" ] || die "no such directory: $TARGET"
  TARGET="$(cd "$TARGET" && pwd)"
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || {
    git -C "$TARGET" init -q
    say "git repo initialised — POLARIS needs git (worktrees, branches, locks)"
  }
else
  TARGET="$(git -C "$KIT" rev-parse --show-toplevel 2>/dev/null)" || TARGET=""
  [ -n "$TARGET" ] || die "no enclosing git repo — unzip the kit inside your project, or name one: bash ops/install.sh <target-repo>"
  TARGET="$(cd "$TARGET" && pwd)"
fi
[ "$TARGET" != "$KIT" ] || die "target is the kit itself"

# `-c pass` proves a REAL interpreter (the Windows Store python3 stub passes command -v).
PY=""; python3 -c pass >/dev/null 2>&1 && PY=python3 || { python -c pass >/dev/null 2>&1 && PY=python; } || true

# --- ops/ ---------------------------------------------------------------------
KIT_CODE="polaris dashboard.py MANUAL.md PROMPTS.md install.sh VERSION"   # + roles/ templates/ hooks/ ci/
                                                                   # (pack.py stays in the kit — never shipped)
# ops/CONVENTIONS.md is written by INIT and by nothing else — it is THE "has INIT run?" test,
# the same one `polaris doctor` uses. Never test ops/board/ for this (see header).
if [ -f "$TARGET/ops/CONVENTIONS.md" ]; then
  note "live board detected — refreshing kit code only (board, RULES, CONVENTIONS, MAP, SPRINT untouched)"
  for f in $KIT_CODE; do cp "$KIT/ops/$f" "$TARGET/ops/$f"; done
  for d in roles templates hooks ci; do mkdir -p "$TARGET/ops/$d"; cp "$KIT/ops/$d/"* "$TARGET/ops/$d/"; done
  UPGRADE=1
else
  mkdir -p "$TARGET/ops"
  cp "$KIT"/ops/*.md "$KIT/ops/polaris" "$KIT/ops/dashboard.py" "$KIT/ops/install.sh" "$KIT/ops/VERSION" "$TARGET/ops/"
  # board/ and contracts/ are deliberately NOT copied — `polaris init-board` creates them during
  # INIT, together with the lock dir, the .polaris/ gitignore and the EVENTS.ndjson union-merge
  # gitattribute. Shipping them empty is what made a fresh install indistinguishable from a live one.
  for d in roles templates hooks ci; do
    mkdir -p "$TARGET/ops/$d"
    cp -R "$KIT/ops/$d/." "$TARGET/ops/$d/"
  done
  UPGRADE=0
fi
chmod +x "$TARGET/ops/polaris" "$TARGET/ops/hooks/ownership-guard.sh" "$TARGET/ops/install.sh" 2>/dev/null || true
say "ops/ installed"

# --- VERSION provenance ---------------------------------------------------------
# A packed release already carries commit:/built: (ops/pack.py stamps them into the zip).
# Installing straight from the kit's git checkout, nothing has stamped it yet — do it here,
# so every installed kit can answer "which POLARIS am I running" and compare to the channel.
V="$TARGET/ops/VERSION"
if ! grep -q '^commit:' "$V" 2>/dev/null; then
  # POLARIS_SHA: set by `ops/polaris update`, which resolves it with git ls-remote (a branch
  # tarball carries no sha). Otherwise: the kit's own HEAD, when the kit IS a git checkout.
  SHA="${POLARIS_SHA:-}"
  if [ -z "$SHA" ] && [ "$(git -C "$KIT" rev-parse --show-toplevel 2>/dev/null || true)" = "$KIT" ]; then
    SHA="$(git -C "$KIT" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  { printf 'commit: %s\n' "${SHA:-unknown}"; printf 'built: %s\n' "$(date +%Y-%m-%d)"; } >> "$V"
fi

# --- CLAUDE.md --------------------------------------------------------------------
# The POLARIS block is MANAGED: delimited by markers so `polaris update` can replace it in
# place. Without markers the protocol froze at install time — every kit file was refreshable
# except the protocol document itself, so no CLAUDE.md change could ever reach an installed
# repo. The markers are also what make `polaris uninstall` safe: you cannot remove a block
# you cannot delimit.
BEGIN_M='<!-- POLARIS:BEGIN — managed block, replaced by `ops/polaris update`. Put your own rules BELOW the END marker. -->'
END_M='<!-- POLARIS:END -->'
MARK="POLARIS v5 — Parallel Sprint Protocol"
CM="$TARGET/CLAUDE.md"
TMP="$TARGET/CLAUDE.md.polaris-tmp"

emit_block() { printf '%s\n' "$BEGIN_M"; cat "$KIT/CLAUDE.md"; printf '%s\n' "$END_M"; }

if [ ! -f "$CM" ]; then
  emit_block > "$CM"
  say "CLAUDE.md installed (managed block)"
elif grep -qF "$END_M" "$CM"; then
  # Rebuild as: everything before BEGIN + a fresh block + everything after END.
  # Two plain awk passes — no sed -i (BSD needs a backup suffix), no bash 4 features.
  { awk -v b="$BEGIN_M" 'index($0,b)==1 {exit} {print}' "$CM"
    emit_block
    awk -v e="$END_M" 'after {print} index($0,e)==1 {after=1}' "$CM"
  } > "$TMP"
  mv "$TMP" "$CM"
  say "CLAUDE.md: managed POLARIS block refreshed (everything outside it untouched)"
elif grep -qF "$MARK" "$CM"; then
  note "CLAUDE.md carries POLARIS but has no markers (installed before they existed) —"
  note "  left as is. To make it updatable, wrap the POLARIS section by hand in:"
  note "  $BEGIN_M ... $END_M"
else
  { emit_block; printf '\n---\n\n'; cat "$CM"; } > "$TMP"
  mv "$TMP" "$CM"
  say "CLAUDE.md: POLARIS prepended above existing content (managed block)"
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
  # ops/VERSION is parsed by sed in install.sh and ops/polaris — a CRLF clone would feed it \r.
  { echo 'ops/polaris text eol=lf'; echo 'ops/VERSION text eol=lf'; echo '*.sh text eol=lf'; } >> "$GA"
  say ".gitattributes: kit scripts pinned to LF"
}

# --- .gitignore -------------------------------------------------------------------
# polaris-v5/ : a leftover kit folder must never be committable.
# .polaris/   : worktrees + the update cache. init-board arms this too, but the update
#               check can create .polaris/ on the very first `status` — i.e. before INIT
#               has ever run — and untracked cruft is one `git add -A` from the repo.
# polaris-v5.zip : the dragged-in kit archive itself is not part of your project either.
GI="$TARGET/.gitignore"
for p in 'polaris-v5/' 'polaris-v5.zip' '.polaris/'; do
  grep -qx "$p" "$GI" 2>/dev/null || { echo "$p" >> "$GI"; say ".gitignore: $p excluded"; }
done

# --- next steps -----------------------------------------------------------------
say "POLARIS $(sed -n 's/^version: *//p' "$V" | head -1) installed into $TARGET"
if [ "$UPGRADE" = 1 ]; then
  note "live board: finish with  cd \"$TARGET\" && bash ops/polaris upgrade"
else
  note "commit, then open a session with:  \"You are INIT.\""
fi
case "$KIT" in
  "$TARGET"/*) note "the kit folder is now redundant (updates come from GitHub) — remove it: rm -rf \"$KIT\"";;
esac
note "Claude Code will ask to trust the project hook on first use — that is the write-guard (read ops/hooks/ownership-guard.sh first)."
