#!/usr/bin/env bash
# POLARIS v5 — one-command install into any repo.
#   bash ops/install.sh [--quiet] <target-repo>
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
#
# --quiet: the agent-driven path. Everything below is still written to
# <target>/.polaris/install.log; stdout gets ONE line, and the last token on it —
# `fresh` or `live-board` — is how the caller routes (fresh → run INIT; live-board →
# run `polaris upgrade`, never INIT). An installer that narrates twenty ✅ lines at a
# human who only said "install polaris" is noise, and the agent relays every word of it.
set -eu

LOG=""
QUIET=0

die() {
  printf '⛔ %s\n' "$*" >&2
  # A quiet install that fails must not ALSO be a silent one.
  [ -n "$LOG" ] && [ -s "$LOG" ] && { printf -- '--- install log ---\n' >&2; cat "$LOG" >&2; }
  exit 1
}
log()  { [ -n "$LOG" ] && printf '%s\n' "$*" >>"$LOG"; return 0; }
say()  { log "✅ $*"; [ "$QUIET" = 1 ] || printf '✅ %s\n' "$*"; }
note() { log "   $*"; [ "$QUIET" = 1 ] || printf '   %s\n' "$*"; }

KIT="$(cd "$(dirname "$0")/.." && pwd)"

TARGET_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1;;
    -*)      die "unknown flag: $1   (usage: bash ops/install.sh [--quiet] [target-repo])";;
    *)       [ -z "$TARGET_ARG" ] || die "too many arguments: $1"; TARGET_ARG="$1";;
  esac
  shift
done

LOG="$(mktemp)" || LOG=""

# Target resolution.
#   arg given → that directory; `git init` it if it isn't a repo yet (greenfield).
#   no arg    → the git repo the kit was unzipped inside.
# The asymmetry is deliberate: zero-arg mode NEVER runs `git init`. A kit unzipped on the
# Desktop and run with no arg would otherwise turn the whole Desktop into a git repo.
if [ -n "$TARGET_ARG" ]; then
  TARGET="$TARGET_ARG"
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
  for d in roles templates hooks ci; do mkdir -p "$TARGET/ops/$d"; cp -R "$KIT/ops/$d/." "$TARGET/ops/$d/"; done   # -R + /. : recursive, dotfile-safe — MATCH the fresh path below, or update silently omits new subdirs/dotfiles
  UPGRADE=1
else
  mkdir -p "$TARGET/ops"
  # NAMED, never `ops/*.md`. The kit repo self-hosts POLARIS, so ITS ops/ is a live board carrying
  # CONVENTIONS.md, MAP.md and SPRINT.md — and a glob run from that checkout (or from the branch
  # tarball, whose root ops/ is that same instance) would copy POLARIS's own board files into a
  # stranger's project. A target that has a CONVENTIONS.md IS a live board by definition (see
  # header), so the leak would also lock INIT out of the repo it was just installed into.
  for f in $KIT_CODE; do cp "$KIT/ops/$f" "$TARGET/ops/$f"; done
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

# The protocol text, wrapped in fresh markers. The SOURCE may itself already be a managed block:
# the kit repo self-hosts POLARIS, so its root CLAUDE.md is a wrapped copy — and that is the file
# `$KIT/CLAUDE.md` resolves to on the branch-tarball path that `polaris update` uses. Cat it raw and
# every update would nest one more pair of markers inside the last, until `uninstall` (which stops at
# the FIRST marker it meets) could no longer delimit the block it is supposed to remove. So: if the
# source carries markers, emit only what is BETWEEN them; otherwise emit the whole file. Unwrapping
# before re-wrapping also makes the whole operation idempotent, which is what it always claimed to be.
protocol_text() {
  if grep -qF "$END_M" "$KIT/CLAUDE.md" 2>/dev/null; then
    awk -v b="$BEGIN_M" -v e="$END_M" '
      index($0,e)==1 {inside=0; next}
      inside         {print}
      index($0,b)==1 {inside=1}
    ' "$KIT/CLAUDE.md"
  else
    cat "$KIT/CLAUDE.md"
  fi
}
emit_block() { printf '%s\n' "$BEGIN_M"; protocol_text; printf '%s\n' "$END_M"; }

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
# There is deliberately NO "now open a new session and say 'You are INIT'" here any more.
# That instruction was never a technical requirement — the write-guard only binds feat/*
# branches, settings.json hot-reloads, and the installing agent reads ops/roles/INIT.md
# directly rather than waiting for CLAUDE.md to be re-read. It just cost every user a
# second chat. The caller (see .claude/skills/polaris-install/SKILL.md) continues straight
# into INIT in the same session.
note "target: $TARGET"
if [ "$UPGRADE" = 1 ]; then
  note "live board: finish with  cd \"$TARGET\" && bash ops/polaris upgrade  (never re-run INIT)"
fi
# A kit folder sitting INSIDE the target is normally a leftover unzip — say so. But in the POLARIS
# kit repo itself, `kit/` is the product's source tree and the target is the repo that self-hosts it:
# telling that user to `rm -rf` their own source would be catastrophic advice. ops/pack.py is the
# tell — it is a kit-repo tool and is never shipped, so it exists in a source tree and nowhere else.
case "$KIT" in
  "$TARGET"/*)
    if [ -f "$KIT/ops/pack.py" ]; then
      note "installed from this repo's own kit source ($KIT) — that is the product, obviously keep it"
    else
      note "the kit folder is now redundant (updates come from GitHub) — remove it: rm -rf \"$KIT\""
    fi;;
esac
note "Claude Code will ask to trust the project hook on first use — that is the write-guard (read ops/hooks/ownership-guard.sh first)."

# The one line stdout always gets, quiet or not. The trailing token is the routing
# contract: `fresh` → the caller runs INIT · `live-board` → the caller runs `polaris
# upgrade` and NEVER runs INIT. CI asserts on it; do not reword it casually.
STATE=fresh; [ "$UPGRADE" = 1 ] && STATE=live-board
if [ -n "$LOG" ]; then
  mkdir -p "$TARGET/.polaris" 2>/dev/null && cp "$LOG" "$TARGET/.polaris/install.log" 2>/dev/null || true
  rm -f "$LOG" 2>/dev/null || true
fi
printf 'POLARIS %s installed · %s\n' "$(sed -n 's/^version: *//p' "$V" | head -1)" "$STATE"
