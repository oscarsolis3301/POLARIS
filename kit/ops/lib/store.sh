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
