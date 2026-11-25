# POLARIS lib/join.sh — a project joins this computer's kit (ops/contracts/shared-kit.md §§ 6-8).
# `join` sets a git project up against the kit store with only a launcher and its state; `migrate`
# turns a vendored project into a joined one in ONE commit that `git revert` undoes byte for byte.
# Neither writes a permission rule, an auto-mode key or a hook registration anywhere, and neither
# writes under the project's .claude/ — except migrate taking POLARIS's own hook entries and output
# style back out of .claude/settings.json, through the same _settings_sweep `uninstall` uses.

# The pointer block (§ 8): three lines, version-free, byte-exact. BEGIN starts with install.sh's
# BEGIN_TAG and END is its END_M, so `uninstall` and `doctor` still find both ends.
_JOIN_B='<!-- POLARIS:BEGIN pointer -->'
_JOIN_P='This project runs POLARIS from the kit on this computer; the protocol arrives at session start. Missing? Run `bash ops/polaris router` and follow it.'
_JOIN_E='<!-- POLARIS:END -->'

_join_kit() { # _join_kit — the complete store version `current` names, or nothing (rc 1)
  local v; v="$(_store_ver)"
  [ -n "$v" ] && [ -f "$POLARIS_HOME/kit/$v/.stored" ] && [ -f "$POLARIS_HOME/kit/$v/ops/launcher" ] || return 1
  printf '%s\n' "$v"
}

_join_pointer() { # _join_pointer <CLAUDE.md> — the pointer block: replaces a POLARIS block, else is prepended, else is the file
  local cm="$1" t="$1.polaris-tmp"
  if [ ! -f "$cm" ]; then
    printf '%s\n%s\n%s\n' "$_JOIN_B" "$_JOIN_P" "$_JOIN_E" > "$cm"
  elif grep -qF "$_JOIN_E" "$cm"; then
    { awk -v b='<!-- POLARIS:BEGIN' 'index($0,b)==1 {exit} {print}' "$cm"
      printf '%s\n%s\n%s\n' "$_JOIN_B" "$_JOIN_P" "$_JOIN_E"
      awk -v e="$_JOIN_E" 'after {print} index($0,e)==1 {after=1}' "$cm"
    } > "$t" && mv -f "$t" "$cm"
  else
    # install.sh's separator, so `uninstall` strips the pointer and the user's file comes back as it was
    { printf '%s\n%s\n%s\n' "$_JOIN_B" "$_JOIN_P" "$_JOIN_E"; printf '\n---\n\n'; cat "$cm"; } > "$t" && mv -f "$t" "$cm"
  fi
}

_join_line() { # _join_line <file> <line> — append <line> once (exact match), after a newline the file may lack
  [ -f "$1" ] && grep -qxF "$2" "$1" && return 0
  [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ] && printf '\n' >> "$1"
  printf '%s\n' "$2" >> "$1"
}

_join_register() { # _join_register <toplevel> — install.sh's registry entry, its exact cksum formula
  local aw="${POLARIS_AWAKE_HOME:-$POLARIS_HOME/awake}" k
  k="$(printf '%s' "$1" | cksum 2>/dev/null)" || k=""; k="${k%% *}"
  case "$k" in ''|*[!0-9]*) return 0 ;; esac
  { mkdir -p "$aw/repos" && printf '%s\n' "$1" > "$aw/repos/$k"; } 2>/dev/null || true
}

_join_hook() { # _join_hook <toplevel> <kit dir> — install.sh's commit-msg step; prints at most one note line
  local hk
  if [ -n "$(git -C "$1" config --get core.hooksPath || true)" ]; then
    note "⚠ core.hooksPath is set — wire the kit's ops/hooks/commit-msg into your own hooks dir by hand"; return 0
  fi
  hk="$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd)/hooks/commit-msg"
  mkdir -p "${hk%/*}"
  if [ ! -f "$hk" ] || grep -q "POLARIS commit-msg" "$hk"; then
    cp "$2/ops/hooks/commit-msg" "$hk"; chmod +x "$hk" 2>/dev/null || true
  else
    note "⚠ a commit-msg hook already exists (not POLARIS's) — left as is; chain the kit's ops/hooks/commit-msg into it by hand"
  fi
}

cmd_join() { # join [<dir>] — set a git project up against this computer's kit: launcher + state, no .claude/, no commit
  local d="${1:-}" top a b v k p n=""
  [ -n "$d" ] || d="$PWD"
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || top=""
  [ -n "$top" ] || die "join: $d is not a git repository"
  a="$(cd "$top" && cd "$(git rev-parse --git-dir)" && pwd -P)"
  b="$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  [ "$a" = "$b" ] || die "join: $top is a linked worktree — run join in the primary checkout"
  [ ! -f "$top/kit/ops/pack.py" ] || die "join: $top is the POLARIS repo — it stays vendored (its ops/ is the update channel)"
  if [ -e "$top/ops/polaris" ]; then
    if [ -d "$top/ops/lib" ]; then p=vendored; else p=machine; fi
    die "join: $top already runs POLARIS ($p)"
  fi
  v="$(_join_kit)" || die "join: this machine has no POLARIS kit — run: python polaris-v5.zip --setup"
  k="$POLARIS_HOME/kit/$v"

  # --- the writes (§ 6), and nothing else: no .claude/, no settings file, no ops/VERSION, no commit
  mkdir -p "$top/ops"
  cp "$k/ops/launcher" "$top/ops/polaris"; chmod +x "$top/ops/polaris" 2>/dev/null || true
  if git -C "$top" ls-files --error-unmatch ops/polaris >/dev/null 2>&1; then
    git -C "$top" update-index --chmod=+x ops/polaris 2>/dev/null || true
  fi
  for p in 'ops/polaris text eol=lf' 'ops/VERSION text eol=lf' '*.sh text eol=lf' \
           'ops/hooks/commit-msg text eol=lf' 'docs/screens/**/*.png -text'; do
    _join_line "$top/.gitattributes" "$p"
  done
  for p in 'polaris-v5/' 'polaris-v5.zip' '.polaris/'; do _join_line "$top/.gitignore" "$p"; done
  n="$(_join_hook "$top" "$k")"
  _join_register "$top"
  _join_pointer "$top/CLAUDE.md"

  say "joined this computer's POLARIS kit ($v) — the project keeps only ops/polaris and its state"
  [ -z "$n" ] || printf '%s\n' "$n"
  if [ -f "$top/ops/CONVENTIONS.md" ]; then echo 'installed · live-board'; else echo 'installed · fresh'; fi
}

_migrate_paths() { # stdin = `git ls-files`; prints the tracked kit files migrate takes out (§ 7 step 1)
  # _kit_footprint_paths reads porcelain lines, so each path gets a 3-byte status prefix. Kept: the
  # repo's state, the launcher slot (overwritten, not removed), and the files migrate edits in place.
  # .claude/skills/polaris-install/ is not in that footprint (update never wrote it) but is the kit's.
  local p l; l="$(cat)"
  [ -n "$l" ] || return 0
  printf '%s\n' "$l" | grep '^\.claude/skills/polaris-install/' || :
  printf '%s\n' "$l" | sed 's/^/ M /' | _kit_footprint_paths | while IFS= read -r p; do
    case "$p" in
      ops/polaris|ops/SURFACES.tsv|ops/DESIGN.md|ops/SPRINT.md|ops/LAYOUT.tsv) ;;
      .claude/settings.json|CLAUDE.md|.gitignore|.gitattributes) ;;
      *) printf '%s\n' "$p" ;;
    esac
  done
}

cmd_migrate() { # migrate — a vendored project moves to this computer's kit in ONE commit; `git revert` undoes it
  local v rv k sj had=0 t sha
  [ ! -f "$PRIMARY/kit/ops/pack.py" ] || die "migrate: the POLARIS repo stays vendored — its ops/ is the update channel"
  [ -d "$PRIMARY/ops/lib" ] || die "migrate: $PRIMARY already runs the machine kit"
  board_quiescent inflight || die "migrate: $QUIET_WHY — finish or park the work first"
  v="$(_join_kit)" || die "migrate: this machine has no POLARIS kit — run: python polaris-v5.zip --setup"
  rv="$(ver version "$PRIMARY/ops/VERSION")"
  if _store_tok "$rv" && _store_newer "$rv" "$v"; then
    die "migrate: this machine's kit ($v) is older than this project's ($rv) — update the machine first"
  fi
  t="$(git -C "$PRIMARY" status --porcelain | _kit_footprint_paths | head -n 1)"
  [ -z "$t" ] || die "migrate: uncommitted changes inside the kit's files ($t) — commit or park them first"
  git -C "$PRIMARY" diff --cached --quiet || die "migrate: changes are staged in the index — commit or unstage them first"

  # Re-run from a copy before the kit goes: on Windows a script that is open cannot be removed or
  # rewritten under itself, and bash reads its script lazily (cmd_uninstall's reason, same cure).
  if [ "${POLARIS_MIGRATE_REEXEC:-}" != 1 ] && [ "$SELF" -ef "$PRIMARY/ops/polaris" ]; then
    t="$(mktemp -d)"
    cp "$SELF" "$t/polaris"; cp -R "${SELF%/*}/lib" "$t/lib"
    POLARIS_MIGRATE_REEXEC=1 exec bash "$t/polaris" migrate
  fi

  k="$POLARIS_HOME/kit/$v"
  t="$(mktemp)"
  git -C "$PRIMARY" -c core.quotepath=off ls-files | _migrate_paths > "$t"
  # 1. kit files out
  [ ! -s "$t" ] || ( cd "$PRIMARY" && GIT_LITERAL_PATHSPECS=1 git rm -q --pathspec-from-file="$t" ) || { rm -f "$t"; die "migrate: git rm failed — nothing committed; git status shows what moved"; }
  rm -f "$t"
  # 2. the launcher in
  cp "$k/ops/launcher" "$PRIMARY/ops/polaris"; chmod +x "$PRIMARY/ops/polaris" 2>/dev/null || true
  git -C "$PRIMARY" add -- ops/polaris
  git -C "$PRIMARY" update-index --chmod=+x ops/polaris 2>/dev/null || true
  # 3. POLARIS's hook entries and output style out of .claude/settings.json; permission rules stay
  sj="$PRIMARY/.claude/settings.json"
  if [ -f "$sj" ]; then
    had=1
    _settings_sweep "$sj" >/dev/null
    [ -f "$sj" ] || printf '{}\n' > "$sj"           # a file left with nothing is kept, as {}
    if git -C "$PRIMARY" ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1; then
      git -C "$PRIMARY" add -- .claude/settings.json
    fi
  fi
  # 4. the managed block → the pointer
  _join_pointer "$PRIMARY/CLAUDE.md"
  git -C "$PRIMARY" add -- CLAUDE.md
  git -C "$PRIMARY" commit -q -m "chore(polaris): migrate to the machine kit ($v)" \
    || die "migrate: the commit failed — the changes are staged; git status shows them"
  sha="$(git -C "$PRIMARY" rev-parse --short HEAD)"
  # 5. register, and record the kit this project has seen (no lazy upgrade on the next command)
  _join_register "$PRIMARY"
  mkdir -p "$PRIMARY/.polaris"
  { printf '%s\n' "$v" > "$PRIMARY/.polaris/kit-seen.$$" && mv -f "$PRIMARY/.polaris/kit-seen.$$" "$PRIMARY/.polaris/kit-seen"; } 2>/dev/null || :
  say "migrated to this computer's POLARIS kit ($v) — one commit, $sha; undo: git revert $sha"
  [ "$had" = 0 ] || note ".claude/settings.json: POLARIS's hook entries and output style removed (permission rules kept)"
  echo '▶ yours: bash ops/polaris prefs --yield'
  exit 0
}
