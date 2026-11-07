# hops-due: `polaris hops --due` — is ONE layout pass worth running now? (ops/contracts/save-hops.md
# § 1.7, § 0.5). Five steps in order, each final: `hops: off` · under 20 tracked files · POLARIS's own
# source (kit/ops/pack.py tracked) · under 30 changes since the last pass (the newest commit on main
# touching ops/LAYOUT.tsv) · else due when the moves `--propose` prints (whole features, at most 25
# files — § 12.4) cut folders per change by 15% or more, or 3+ folders of 5+ files have no guide.
# Due prints ONE line, rc 0; not due is silent, rc 1; and EVERY run rewrites .polaris/hops-due —
# the only thing `next`, `triage` and the update hint ever read, because `next` runs on the anchor
# hook's 10 s clock and can never afford hops itself.
#
# The ground is the practice shop (hops_fixture, § 8.2): four features scattered over five folders
# each, four folders of 5+ files without a guide — due for both reasons. Then each reason is taken
# away in turn: guides (the saving alone is left), keep rows (what a pass whose every move failed
# leaves behind — the saving goes with them, so the verdict cannot fire again and again), the
# cooldown, the switch, the self-hosting tell, a tiny repo. Every verdict is checked against the
# cache it wrote: ONE LF line, `<main's sha now><TAB><0|1><TAB><the line, or ->`, built here
# independently and compared with cmp — never grep (a CR, a stale sha or a stray field reds it).
# Last, the whole chain for real: heal writes the cache through the CLI, then the REAL `next` and
# `triage` read it in the shop — `tidy` once per session, then their usual answer.
#
# HERMETIC (the keys-drift pattern): throwaway repos under mktemp -d. THE ENGINE TRAP (§ 8.4): the
# kit's code is reached as `POLARIS_ROOT=<fixture> python kit/ops/index.py hops --due` — `bash "$KIT"
# hops` in a fixture finds no engine — and heal, a bash caller, gets POLARIS_INDEX_BIN pointed at a
# wrapper that execs this kit's index.py.
KIT="$(pwd)/kit/ops/polaris"
PY="$(pwd)/kit/ops/index.py"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/shop"
bash -c '. kit/ops/lib/selftest/hops.sh; hops_fixture "$1"' _ "$R" >/dev/null 2>&1
TAB="$(printf '\t')"
D() { # D <repo> — the verdict (rc · its one line, or silence), then its cache held to § 0.5 byte for byte
  out="$( POLARIS_ROOT="$1" python "$PY" hops --due 2>&1 )"; rc=$?
  out="${out//$'\r'/}"
  printf -- '--due rc=%s · %s\n' "$rc" "${out:-(silent)}"
  if [ "$rc" = 0 ]; then v="0$TAB$out"; else v="1$TAB-"; fi
  printf '%s\t%s\n' "$(git -C "$1" rev-parse --verify -q main)" "$v" > "$FIX/want"
  if cmp -s "$FIX/want" "$1/.polaris/hops-due"; then echo 'cache: one LF line — main sha · verdict · that line'
  else echo 'cache: WRONG'; fi
}
ec() { # ec <n> — n changes with no files on main, in ONE git process: the cooldown counts every change
  i=0
  { while [ "$i" -lt "$1" ]; do i=$((i + 1))
      printf 'commit refs/heads/main\ncommitter Fixture Shop <shop@fixture-shop.test> %s +0000\ndata 6\nempty\n' "$((1767225600 + i))"
      [ "$i" -gt 1 ] || printf 'from refs/heads/main^0\n'
      printf '\n'
    done; printf 'done\n'; } | git -C "$R" fast-import --quiet --done
}

# 1. The shop as built: due for both reasons, and the cache says so, keyed on main's sha (shown here
#    once as <main sha>; every other case proves the same bytes with cmp).
echo '--- 1. the practice shop as built'
D "$R"
LINE="$out"
sed "s/^$(git -C "$R" rev-parse main)/<main sha>/" "$R/.polaris/hops-due"

# 2. A guide in each of those four folders (staged: a guide is a TRACKED CLAUDE.md with the marker).
#    No folder lacks one now, so the saving alone keeps it due.
echo '--- 2. every folder of 5+ files guided'
for g in src/components tests src/hooks src/services; do
  printf '<!-- polaris:guide -->\n# %s/ — the shop'"'"'s %s\n<!-- /polaris:guide -->\n' "$g" "${g##*/}" > "$R/$g/CLAUDE.md"
done
git -C "$R" add -A
D "$R"

# 3. Keep rows, as a pass whose every move failed leaves them (path = the file that was to move,
#    why = the failure). The saving is measured only after keep rows are out, so it goes with them,
#    and with every folder guided nothing else makes it due — silent, rc 1, cache `1 -`.
echo '--- 3. a keep row for every file a MOVE row would move'
POLARIS_ROOT="$R" python "$PY" hops --tsv 2>/dev/null | tr -d '\r' \
  | awk -F'\t' '$1 == "MOVE" { print $2 "\tkeep\tproof failed: logic changed" }' >> "$R/ops/LAYOUT.tsv"
printf 'keep rows: %s\n' "$(grep -c 'proof failed' "$R/ops/LAYOUT.tsv")"
D "$R"

# 4. The cooldown. Guides and keep rows go; the last pass LANDS — a commit on main touching
#    ops/LAYOUT.tsv (a `moved` row) — and the compute that says due is never reached for 29 changes.
#    The 30th change since that commit makes it due again, with the very line of case 1.
echo '--- 4. the 30-change cooldown after the last pass'
( cd "$R" && git reset -q --hard \
  && printf 'src/old/cart.ts\tmoved\t→ src/checkout/cart.ts · hops-6.12.0\n' >> ops/LAYOUT.tsv \
  && GIT_AUTHOR_DATE='2025-12-31T00:00:00Z' GIT_COMMITTER_DATE='2025-12-31T00:00:00Z' git commit -qam 'layout: the last pass' ) >/dev/null 2>&1
A="$(git -C "$R" rev-parse main)"
since() { printf 'changes since the last pass: %s\n' "$(git -C "$R" rev-list --count --no-merges "$A..main")"; }
since; D "$R"
ec 29 >/dev/null 2>&1
since; D "$R"
ec 1 >/dev/null 2>&1
since; D "$R"
[ "$out" = "$LINE" ] && echo 'after the cooldown: the line of case 1'

# 5. `hops: off` — exactly that value — silences it, and the cache that said due a moment ago is
#    rewritten to not due.
echo '--- 5. hops: off'
printf 'hops: off\n' >> "$R/ops/CONVENTIONS.md"
D "$R"
git -C "$R" checkout -q -- ops/CONVENTIONS.md

# 6. POLARIS's own source never offers itself the pass — the tell is a tracked kit/ops/pack.py, the
#    same one `update --auto` skips itself on — while bare `hops` still reports there.
echo '--- 6. the self-hosting kit repo'
( cd "$R" && mkdir -p kit/ops && printf '# the kit packer\n' > kit/ops/pack.py && git add kit/ops/pack.py ) >/dev/null 2>&1
D "$R"
POLARIS_ROOT="$R" python "$PY" hops 2>&1 | tr -d '\r' | sed -n 1p
( cd "$R" && git rm -q --cached kit/ops/pack.py && rm -rf kit ) >/dev/null 2>&1

# 7. Under 20 tracked files: silent, rc 1 — and that repo's own cache, keyed on its own main.
echo '--- 7. a repo of 2 tracked files'
T="$FIX/tiny"
( git init -q -b main "$T" 2>/dev/null || { git init -q "$T"; git -C "$T" symbolic-ref HEAD refs/heads/main; }
  cd "$T" && printf 'a\n' > a.txt && printf 'b\n' > b.txt && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm tiny ) >/dev/null 2>&1
D "$T"

# 8. --questions in the shop: every scattered file already has a MOVE row and no folder looks
#    framework-routed, so the run's up-front round has nothing to add — silent, rc 1.
echo '--- 8. nothing to ask up front'
POLARIS_ROOT="$R" python "$PY" hops --questions 2>&1 | tr -d '\r'; echo "questions rc=${PIPESTATUS[0]}"

# 9. For real. The board goes in (its commit is not a pass: ops/LAYOUT.tsv untouched), the cache
#    goes, and heal — run on every update and every live-board install — writes it back through the
#    CLI. A brain folder is already there, so heal spends nothing building one (heal-design owns
#    that). Then the REAL `next` and `triage` read the cache: `tidy` once per session, its notes
#    carrying the cached reasons; the second ask in the same session gets the usual answer.
echo '--- 9. heal writes the cache; the real next and triage read it'
printf '#!/usr/bin/env bash\nexec python "%s" "$@"\n' "$PY" > "$FIX/engine"; chmod +x "$FIX/engine"
( cd "$R" && bash "$KIT" init-board && git add -A && git commit -qm 'chore: the board' ) >/dev/null 2>&1
rm -f "$R/.polaris/hops-due"; mkdir -p "$R/.polaris/brain"
( cd "$R" && POLARIS_INDEX_BIN="$FIX/engine" bash "$KIT" heal ) >/dev/null 2>&1
printf '%s\t0\t%s\n' "$(git -C "$R" rev-parse --verify -q main)" "$LINE" > "$FIX/want"
if cmp -s "$FIX/want" "$R/.polaris/hops-due"; then echo "heal's cache: one LF line — main sha · 0 · the line of case 1"
else echo "heal's cache: WRONG"; fi
( cd "$R" && CLAUDE_CODE_SESSION_ID=hd-1 bash "$KIT" next 2>&1 )
( cd "$R" && CLAUDE_CODE_SESSION_ID=hd-1 bash "$KIT" next 2>&1 )
( cd "$R" && CLAUDE_CODE_SESSION_ID=hd-2 bash "$KIT" triage 2>&1 )
( cd "$R" && CLAUDE_CODE_SESSION_ID=hd-2 bash "$KIT" triage 2>&1 )
