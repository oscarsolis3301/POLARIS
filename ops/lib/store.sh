# POLARIS lib/store.sh — the kit store: one unpacked release per version under $POLARIS_HOME/kit/,
# and a one-line `current` naming the version every joined project runs (ops/contracts/shared-kit.md § 1).
# Every function is private (`_`): no api-kit row. Self-contained on purpose — the launcher's CI
# bootstrap sources this file straight out of a verified zip, before any other module exists.
# No symlinks anywhere (Windows): `current` and `next` are plain one-line files, written temp + mv.

_store_tok() { # _store_tok <s> — rc 0 when <s> is a version token, ^[0-9]+\.[0-9]+\.[0-9]+$ exactly. Zero forks.
  case "${1:-}" in *[!0-9.]*|.*|*.|*..*|*.*.*.*) return 1 ;; *.*.*) return 0 ;; *) return 1 ;; esac
}

_store_newer() { # _store_newer <a> <b> — rc 0 when version token <a> sorts above <b>. Zero forks.
  local a="$1" b="$2" a1 a2 a3 b1 b2 b3
  a1="${a%%.*}"; a="${a#*.}"; a2="${a%%.*}"; a3="${a#*.}"
  b1="${b%%.*}"; b="${b#*.}"; b2="${b%%.*}"; b3="${b#*.}"
  [ $((10#$a1)) -ne $((10#$b1)) ] && { [ $((10#$a1)) -gt $((10#$b1)) ]; return; }
  [ $((10#$a2)) -ne $((10#$b2)) ] && { [ $((10#$a2)) -gt $((10#$b2)) ]; return; }
  [ $((10#$a3)) -gt $((10#$b3)) ]
}

_sha256_ok() { # _sha256_ok <s> — rc 0 when <s> is 64 lowercase hex digits.
  case "${1:-}" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#1}" -eq 64 ]
}

_store_py() { # _store_py — print the first python that really runs (`-c pass`: the Windows Store stub fails it); none → rc 1
  local p
  for p in python3 python; do
    if "$p" -c pass >/dev/null 2>&1; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

_sha256() { # _sha256 <file> — its sha256 as lowercase hex: the first that works of sha256sum,
  # shasum -a 256, python hashlib, certutil. Read through stdin where the tool allows, so no file
  # name ever reaches the output. None works → rc 1, nothing printed.
  local f="${1:-}" o py w
  [ -f "$f" ] || return 1
  o="$(sha256sum < "$f" 2>/dev/null)" && o="${o%% *}" && _sha256_ok "$o" && { printf '%s\n' "$o"; return 0; }
  o="$(shasum -a 256 < "$f" 2>/dev/null)" && o="${o%% *}" && _sha256_ok "$o" && { printf '%s\n' "$o"; return 0; }
  if py="$(_store_py)"; then
    o="$("$py" -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$f" 2>/dev/null)"
    o="${o%$'\r'}"
    _sha256_ok "$o" && { printf '%s\n' "$o"; return 0; }
  fi
  w="$f"; w="$(cygpath -w "$f" 2>/dev/null)" || w="$f"
  o="$(certutil -hashfile "$w" SHA256 2>/dev/null)" || return 1
  o="$(printf '%s\n' "$o" | sed -n 2p | tr -d ' \r' | tr 'A-F' 'a-f')"
  _sha256_ok "$o" && { printf '%s\n' "$o"; return 0; }
  return 1
}

_store_unpack() { # _store_unpack <zip> <dir> — the zip verbatim into <dir>, then its polaris-v5/ folder
  # hoisted one level, so <dir>/ops/polaris is the kit's CLI and the zip's own top-level files
  # (__main__.py) sit beside it. python zipfile (modes kept) when python runs, else unzip -q.
  local z="$1" d="$2" py e
  if py="$(_store_py)"; then
    "$py" -c '
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as a:
    for i in a.infolist():
        p = a.extract(i, sys.argv[2])
        m = (i.external_attr >> 16) & 0o777
        if m and not i.is_dir():
            os.chmod(p, m)
' "$z" "$d" || return 1
  elif unzip -v >/dev/null 2>&1; then
    unzip -q "$z" -d "$d" || return 1
  else
    printf '⛔ store: needs python or unzip to unpack the kit\n' >&2; return 2
  fi
  if [ -d "$d/polaris-v5" ]; then
    for e in "$d/polaris-v5"/* "$d/polaris-v5"/.[!.]* "$d/polaris-v5"/..?*; do
      [ -e "$e" ] || continue
      mv "$e" "$d/" || return 1
    done
    rmdir "$d/polaris-v5" || return 1
  fi
}

_store_put() { # _store_put <zip> <ver> <sha256> — install a release zip as kit/<ver> (shared-kit § 1).
  # Refused unless the zip's sha256 is <sha256>. Unpacked into kit/.tmp-<ver>-$$, the zip copied
  # beside it as polaris-v5.zip (the --setup line names it), moved to kit/<ver>, then `.stored`
  # written LAST — its presence is what "complete" means. An existing complete kit/<ver> is kept.
  local z="${1:-}" v="${2:-}" want="${3:-}" k="$POLARIS_HOME/kit" got t rc
  _store_tok "$v" || { printf '⛔ store: %s is not a version — not installed\n' "${v:-<empty>}" >&2; return 1; }
  case "$want" in *[A-F]*) want="$(printf '%s' "$want" | tr 'A-F' 'a-f')" ;; esac
  got="$(_sha256 "$z")" || got=""
  if [ -z "$got" ] || [ "$got" != "$want" ]; then
    printf '⛔ store: %s does not match its sha256 — not installed\n' "$z" >&2; return 1
  fi
  [ -f "$k/$v/.stored" ] && return 0
  t="$k/.tmp-$v-$$"
  rm -rf "$t"; mkdir -p "$t" || return 1
  _store_unpack "$z" "$t"; rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -rf "$t"
    [ "$rc" -eq 2 ] || printf '⛔ store: %s did not unpack — not installed\n' "$z" >&2
    return 1
  fi
  cp "$z" "$t/polaris-v5.zip" || { rm -rf "$t"; return 1; }
  if [ -d "$k/$v" ]; then
    if [ -f "$k/$v/.stored" ]; then rm -rf "$t"; return 0; fi
    rm -rf "$k/$v"                       # an incomplete one: a put that died before `.stored`
  fi
  mv "$t" "$k/$v" || { rm -rf "$t"; printf '⛔ store: could not place kit %s — not installed\n' "$v" >&2; return 1; }
  if [ -d "$k/$v/${t##*/}" ]; then       # another put won the race and mv nested ours inside it
    rm -rf "$k/$v/${t##*/}"
    [ -f "$k/$v/.stored" ] && return 0
  fi
  printf '%s %s\n' "$(date +%s)" "$got" > "$k/$v/.stored-$$" && mv -f "$k/$v/.stored-$$" "$k/$v/.stored"
}

_store_flip() { # _store_flip <ver> — make complete kit <ver> the one every project runs: `current`
  # written temp + mv; a `next` naming <ver> is spent, so it goes.
  local v="${1:-}" k="$POLARIS_HOME/kit" n=""
  if ! _store_tok "$v" || [ ! -f "$k/$v/.stored" ]; then
    printf '⛔ store: kit %s is not complete here — not switched\n' "${v:-<empty>}" >&2; return 1
  fi
  printf '%s\n' "$v" > "$k/.current-$$" && mv -f "$k/.current-$$" "$k/current" || return 1
  read -r n 2>/dev/null < "$k/next" || :
  [ "$n" = "$v" ] && rm -f "$k/next"
  return 0
}

_store_ver() { # _store_ver — the version `current` names, or nothing (absent / not a token). Builtins only: zero forks.
  local v=""
  read -r v 2>/dev/null < "$POLARIS_HOME/kit/current" || :
  _store_tok "$v" && printf '%s\n' "$v"
  return 0
}

_store_prune() { # _store_prune — keep `current`, the newest other complete version and `next`;
  # remove any other kit/<ver> whose `.stored` epoch is over 7 days old, and any kit/.tmp-* over a
  # day old. A version dir with no `.stored` has no age and is left for the next put to replace.
  local k="$POLARIS_HOME/kit" cur nxt="" best="" d v e now
  [ -d "$k" ] || return 0
  cur="$(_store_ver)"
  read -r nxt 2>/dev/null < "$k/next" || :
  _store_tok "$nxt" || nxt=""
  for d in "$k"/*/; do
    v="${d%/}"; v="${v##*/}"
    _store_tok "$v" && [ -f "$k/$v/.stored" ] && [ "$v" != "$cur" ] || continue
    if [ -z "$best" ] || _store_newer "$v" "$best"; then best="$v"; fi
  done
  now="$(date +%s)"
  for d in "$k"/*/; do
    v="${d%/}"; v="${v##*/}"
    _store_tok "$v" && [ -f "$k/$v/.stored" ] || continue
    [ "$v" = "$cur" ] || [ "$v" = "$best" ] || [ "$v" = "$nxt" ] && continue
    e=""; read -r e _ 2>/dev/null < "$k/$v/.stored" || :
    case "$e" in ''|*[!0-9]*) continue ;; esac
    [ $(( now - e )) -gt $(( 7 * 86400 )) ] && rm -rf "$k/$v"
  done
  find "$k" -mindepth 1 -maxdepth 1 -name '.tmp-*' -mmin +1440 -exec rm -rf {} + 2>/dev/null
  return 0
}

# ------------------------------------------------------------------ the machine update (shared-kit § 5)
# Below this line the store is driven by the full CLI (lib loader rows `update` and `__quiet`): these
# functions call cfg, ver, board_quiescent and beat_live, so the launcher's CI bootstrap never reaches
# them — it sources this file only for _store_put and _store_flip above.

_store_quiet() { # _store_quiet — the hidden `__quiet` verb, run INSIDE one joined project by the NEW
  # kit: rc 0 when nothing is in flight there (board_quiescent inflight) and no task worktree has a
  # live beat (younger than wt_live_minutes); else the first reason on stdout, rc 1. A project with
  # no board yet has nothing in flight, so it is quiet. Reads only; writes nothing anywhere.
  local d id
  if ! board_quiescent inflight; then printf '%s\n' "$QUIET_WHY"; return 1; fi
  for d in "$PRIMARY/.polaris/wt"/*/; do
    [ -d "$d" ] || continue
    id="${d%/}"; id="${id##*/}"
    if beat_live "$id"; then printf 'worktree live: %s\n' "$id"; return 1; fi
  done
  return 0
}

_store_switch() { # _store_switch <old> <new> — step 4: ask every registered joined project (a
  # registry entry whose path holds a launcher: ops/polaris present, ops/lib/ absent) whether it is
  # quiet, with the NEW kit's `__quiet`, one child per project, launcher mode off in the child. All
  # quiet → flip `current`; the first busy one → stage `kit/next` and name it. rc 0 either way.
  local old="$1" new="$2" k="$POLARIS_HOME/kit" reg f p n=0 out why
  reg="${POLARIS_AWAKE_HOME:-$POLARIS_HOME/awake}/repos"
  for f in "$reg"/*; do
    [ -f "$f" ] || continue
    p=""; IFS= read -r p < "$f" 2>/dev/null || :
    p="${p%$'\r'}"
    [ -n "$p" ] && [ -f "$p/ops/polaris" ] && [ ! -d "$p/ops/lib" ] || continue
    n=$((n + 1))
    if ! out="$(cd "$p" 2>/dev/null && POLARIS_LAUNCHER='' POLARIS_LAZY='' bash "$k/$new/ops/polaris" __quiet 2>/dev/null)"; then
      why="${out%%$'\n'*}"; why="${why%$'\r'}"
      { printf '%s\n' "$new" > "$k/.next-$$" && mv -f "$k/.next-$$" "$k/next"; } 2>/dev/null || :
      printf 'kit %s is ready — it switches when %s is quiet (%s)\n' "$new" "$p" "${why:-it did not answer}"
      return 0
    fi
  done
  _store_flip "$new" || return 1
  printf 'kit %s → %s — %s project(s) move with it\n' "$old" "$new" "$n"
}

_store_trust() { # _store_trust <ver> — step 5's needs-you line: the trust tier --setup installed
  # ($POLARIS_HOME/trust/readonly-allow.sh) is not byte-equal to kit <ver>'s (hook-dispatch.md § 4).
  # No trust tier on this machine → nothing to compare, nothing said. An update never copies it.
  local t="$POLARIS_HOME/trust/readonly-allow.sh" n="$POLARIS_HOME/kit/$1/ops/hooks/readonly-allow.sh"
  [ -f "$t" ] && [ -f "$n" ] || return 0
  cmp -s "$t" "$n" && return 0
  printf '⛔ needs you: this kit approves new read-only commands — run in your own terminal: python "%s/kit/%s/polaris-v5.zip" --setup\n' "$POLARIS_HOME" "$1"
}

_store_update() { # _store_update <auto> <say> <major> — `update` / `update --auto` in machine mode
  # (shared-kit.md § 5, auto-update.md v6). A MACHINE operation: ask the channel the running kit
  # names (--auto: through $POLARIS_HOME/update-cache, the 6.19 throttle), fetch its `zip:`, put it in
  # the store only when it matches the channel's `zip_sha256:`, flip `current` once every joined
  # project is quiet (else stage `kit/next`), prune. No repo commit, no park, no install.sh, no
  # settings file, no hook registration, in any repo or in Claude Code's own config. rc 1 on a
  # refusal of the typed form; --auto is the session-start path and returns 0 whatever happens.
  local auto="${1:-0}" say_="${2:-0}" major="${3:-0}" k="$POLARIS_HOME/kit" vf="$OPS_DIR/VERSION"
  local cur nxt chan cache today now prev ce txt latest="" zurl="" zsha="" a b z fail=1
  [ "$auto" = 1 ] && fail=0
  cur="$(_store_ver)"; [ -n "$cur" ] || cur="$(ver version "$vf" 2>/dev/null || true)"
  # --auto with a staged kit/next: re-run step 4 only — no channel, no download.
  if [ "$auto" = 1 ]; then
    nxt=""; read -r nxt 2>/dev/null < "$k/next" || :
    nxt="${nxt%$'\r'}"
    if _store_tok "$nxt" && [ -f "$k/$nxt/.stored" ] && [ "$nxt" != "$cur" ]; then
      _store_switch "$cur" "$nxt" || :
      _store_prune || :
      _store_trust "$nxt" || :
      return 0
    fi
    case "$(cfg auto_update on)" in
      on) ;;
      *) [ "$say_" = 1 ] && printf 'skipped: auto_update is not on\n'; return 0 ;;
    esac
  fi
  # 1. the channel — typed: always asked; --auto: once a day, again when a same-day answer equal to
  #    the installed version is over an hour old (6.19). The cache is the machine's, one per computer.
  chan="$(ver channel "$vf" 2>/dev/null || true)"
  if [ -z "$chan" ]; then
    if [ "$auto" = 1 ]; then [ "$say_" = 1 ] && printf 'skipped: this kit names no channel\n'; return 0; fi
    printf '⛔ update: this kit names no channel — nothing changed\n'; return 1
  fi
  cache="$POLARIS_HOME/update-cache"; today="$(date +%Y-%m-%d)"; now="$(date +%s)"
  if [ "$auto" = 1 ] && [ "$(ver checked "$cache" 2>/dev/null || true)" = "$today" ]; then
    prev="$(ver latest "$cache" 2>/dev/null || true)"; ce="$(ver epoch "$cache" 2>/dev/null || true)"
    case "$ce" in ''|*[!0-9]*) ce=0 ;; esac
    if ! _store_tok "$prev" || ! _store_newer "$prev" "$cur"; then
      if [ "$prev" != "$cur" ] || [ $((now - ce)) -lt 3600 ]; then
        [ "$say_" = 1 ] && printf 'skipped: up to date (%s)\n' "$cur"
        return 0
      fi
    fi
  fi
  txt="$(curl -fsS --max-time 10 "$chan" 2>/dev/null || true)"
  while read -r a b _; do
    b="${b%$'\r'}"
    case "$a" in
      version:) [ -n "$latest" ] || latest="$b" ;;
      zip:) [ -n "$zurl" ] || zurl="$b" ;;
      zip_sha256:) [ -n "$zsha" ] || zsha="$b" ;;
    esac
  done <<EOF_CHAN
$txt
EOF_CHAN
  _store_tok "$latest" || latest=""
  if [ -z "$latest" ]; then
    if [ "$auto" = 1 ]; then [ "$say_" = 1 ] && printf 'skipped: the channel did not answer\n'; return 0; fi
    printf '⛔ update: the channel did not answer (%s) — nothing changed\n' "$chan"; return 1
  fi
  { mkdir -p "$POLARIS_HOME" && printf 'checked: %s\nlatest: %s\nepoch: %s\n' "$today" "$latest" "$now" > "$cache"; } 2>/dev/null || :
  # 2. nothing newer · a MAJOR asks unless --major
  if [ -z "$cur" ] || ! _store_newer "$latest" "$cur"; then
    if [ "$auto" = 0 ]; then printf 'up to date (%s)\n' "$cur"
    elif [ "$say_" = 1 ]; then printf 'skipped: up to date (%s)\n' "$cur"; fi
    return 0
  fi
  if [ "$major" != 1 ] && [ $((10#${latest%%.*})) -gt $((10#${cur%%.*})) ]; then
    printf '⬆ POLARIS %s is a MAJOR update (you have %s) — it will not apply itself; when you want it: bash ops/polaris update --major\n' "$latest" "$cur"
    return 0
  fi
  # 3. fetch and check — fail closed: no zip_sha256 on the channel, nothing is installed
  if [ ! -f "$k/$latest/.stored" ]; then
    case "$zsha" in *[A-F]*) zsha="$(printf '%s' "$zsha" | tr 'A-F' 'a-f')" ;; esac
    if ! _sha256_ok "$zsha"; then
      printf '⛔ update: the channel names no zip_sha256 — not installed\n'; return "$fail"
    fi
    [ -n "$zurl" ] || zurl="$(ver zip "$vf" 2>/dev/null || true)"
    mkdir -p "$k" 2>/dev/null || :
    z="$k/.tmp-dl-$latest-$$.zip"
    if [ -z "$zurl" ] || ! curl -fsSL --max-time 120 "$zurl" -o "$z" 2>/dev/null; then
      rm -f "$z"; printf '⛔ update: could not download kit %s (%s) — not installed\n' "$latest" "${zurl:-no zip: line}"; return "$fail"
    fi
    if ! _store_put "$z" "$latest" "$zsha" 2>&1; then rm -f "$z"; return "$fail"; fi
    rm -f "$z"
  fi
  # 4. quiescence over the machine → flip or stage · 5. prune, the trust-tier line
  _store_switch "$cur" "$latest" || :
  _store_prune || :
  _store_trust "$latest" || :
  return 0
}
