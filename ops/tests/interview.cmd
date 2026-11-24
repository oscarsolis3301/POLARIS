# `interview` is the first-run interview as DATA (ops/contracts/first-run.md § 2): the questions
# live in ops/KEYS.tsv's fifth column, `ask`, so they can never drift from the keys they set, and
# the model asks whatever is still unanswered in ONE round. This golden pins the whole grammar
# byte-for-byte: the QUESTION/OPTION lines for a pending key and the tail with its default · the
# --pending probe (rc 1 + one line; rc 0 + silence once everything is answered) · --set's
# all-or-nothing validation and both die texts · the three write modes (an absent key appended after
# one blank line, a stub replaced in place, a live value changed with its comment kept) · the adhd
# side effect on the REPO's copy of the skill, both directions, and the note when that copy is
# missing · the two refusals (no CONVENTIONS.md, a feat/* branch) · the claim-branch remote check.
# Every write is proven on the file, never on a printed line (T-089).
#
# HERMETIC BY CONSTRUCTION (the adopt-stub pattern): a fixture repo with a fixture ops/KEYS.tsv of
# FAKE keys, run from INSIDE it — polaris anchors to the worktree-list primary, which becomes the
# fixture. So the REAL registry can grow without ever redding this file. One row keeps its real
# name on purpose: `adhd`, because the side effect keys on the KEY NAME, and it is proven on a
# fixture .claude/skills/i-have-adhd/SKILL.md holding just the frontmatter lines — never the kit's
# copy, which ops/tests/adhd-skill-installed pins at `disable-model-invocation: true`.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  echo x > a.txt; git add -A; git commit -qm init
  mkdir -p ops .claude/skills/i-have-adhd
) >/dev/null 2>&1
R="$FIX/repo"
SKILL="$R/.claude/skills/i-have-adhd/SKILL.md"
I() { ( cd "$R" && bash "$KIT" interview "$@" 2>&1 ); printf 'rc %s\n' "$?"; }
FLAG() { grep '^disable-model-invocation:' "$SKILL"; }
SAME() { if cmp -s "$FIX/before" "$R/ops/CONVENTIONS.md"; then echo 'file untouched'; else echo 'FILE CHANGED'; fi; }

# five rows: three carry a question (fk_voice · adhd · fk_claim, in that order, a plain row between
# two of them) and two do not — a comment row and a blank row lead the file so both are proven ignored
printf '# fixture registry — FAKE keys, never the real ones\n\n'                                                                   >  "$R/ops/KEYS.tsv"
printf 'fk_voice\t0.1\twarm\thow the fake agents talk to you\tHow should I talk to you?|Warm=warm|Terse=terse\n'                     >> "$R/ops/KEYS.tsv"
printf 'adhd\t0.2\toff\tfake replies are not shaped for ADHD\tWant replies shaped for ADHD?|Not needed=off|Yes, always=on\n'        >> "$R/ops/KEYS.tsv"
printf 'fk_plain\t0.3\t7\ta plain row asks nothing\n'                                                                                >> "$R/ops/KEYS.tsv"
printf 'fk_claim\t0.4\tone\thow many fake computers\tOne computer or several?|One computer=one|Several computers=many\n'             >> "$R/ops/KEYS.tsv"
printf 'fk_other\t0.5\tno\tanother plain row\n'                                                                                      >> "$R/ops/KEYS.tsv"
printf -- '---\nname: i-have-adhd\ndisable-model-invocation: true\n---\n' > "$SKILL"

echo '== no ops/CONVENTIONS.md: die points at INIT, never creates the file =='
I
[ -f "$R/ops/CONVENTIONS.md" ] && echo 'FILE CREATED' || echo 'no file created'

# fk_voice live (with a comment), fk_claim stubbed by adopt, adhd absent — so exactly one is pending
printf 'fk_voice: warm   # the human set this\n'                          >  "$R/ops/CONVENTIONS.md"
printf '# fk_claim: one   # how many fake computers (since 0.4)\n'        >> "$R/ops/CONVENTIONS.md"
printf 'prose the human wrote below the keys stays put\n'                 >> "$R/ops/CONVENTIONS.md"

echo '== plain: the one pending key as QUESTION/OPTION lines, then the tail with its default filled in =='
I

echo '== --pending: rc 1 + the one line doctor and update print =='
I --pending

cp "$R/ops/CONVENTIONS.md" "$FIX/before"
echo '== --set with a value outside the options: die names them; nothing written =='
I --set fk_voice=x
SAME

echo '== --set with a key that asks no question: die names the interview keys; nothing written =='
I --set nope=1
SAME

echo '== --set is all-or-nothing: one bad pair blocks the good one, and the skill flag stays put =='
I --set adhd=on --set nope=1
SAME; FLAG

echo '== --set from feat/x: refused before anything is written =='
git -C "$R" checkout -q -b feat/x
I --set adhd=on
git -C "$R" checkout -q main
SAME

echo '== --set adhd=on: appended at the end after one blank line, and the repo copy of the skill flips =='
I --set adhd=on
cat "$R/ops/CONVENTIONS.md"; FLAG

echo '== --set fk_claim=many: the stub is replaced in place — same line, now live =='
I --set fk_claim=many
cat "$R/ops/CONVENTIONS.md"

echo '== --set fk_voice=terse: a live value changes and its comment stays =='
I --set fk_voice=terse
grep '^fk_voice:' "$R/ops/CONVENTIONS.md"

echo '== every preference set: --pending is silent with rc 0, plain says there is nothing to ask =='
I --pending
I

echo '== --set adhd=off: the reverse flip on the skill =='
I --set adhd=off
FLAG

echo '== --set adhd=on with no skill copy installed: the preference is written, the note names the fix =='
rm -f "$SKILL"
I --set adhd=on
grep '^adhd:' "$R/ops/CONVENTIONS.md"

echo '== claim=claim-branch with no origin remote: refused, nothing written (the registry gains a real claim row here) =='
printf 'claim\t0.6\tlocal-lock\tfake locks stay on this machine\tOne computer, or several?|One computer=local-lock|Several computers=claim-branch\n' >> "$R/ops/KEYS.tsv"
cp "$R/ops/CONVENTIONS.md" "$FIX/before"
I --set claim=claim-branch
SAME

echo '== claim=local-lock needs no remote: written, and nothing is pending any more =='
I --set claim=local-lock
grep '^claim:' "$R/ops/CONVENTIONS.md"
I --pending

# ---- 6.21.0: setup answers once per computer (ops/contracts/machine-prefs.md § 8, first-run.md v2 § A)
# Every machine-file path here is a fixture under $FIX: the owner's real preferences file is never
# read (check.sh runs this with POLARIS_PREFS= — the layer OFF — and each case below names its own).
PF="$FIX/prefs"
mv "$R/ops/CONVENTIONS.md" "$FIX/conv-kept"

echo '== --init, no CONVENTIONS and no machine file: every ask row is a question, nothing else, rc 0 =='
POLARIS_PREFS="$FIX/no-such-file" I --init
[ -f "$PF" ] && echo 'MACHINE FILE CREATED' || echo 'no machine file created'

echo '== --init, the machine file answers fk_voice: ANSWERED from the machine, questions for the rest =='
printf '# fixture machine file\r\nfk_voice: terse   # said once, on this computer\r\nadhd:\r\n' > "$PF"
POLARIS_PREFS="$PF" I --init

echo '== --init with the layer off (POLARIS_PREFS empty): the file is ignored, every row is asked =='
POLARIS_PREFS= I --init

# --remember writes through prefs_put, which records only machine/seed keys (KEYS.tsv column 6): the
# ask rows become `machine`, the claim row `seed`, exactly as the real registry scopes them
awk 'BEGIN { FS = OFS = "\t" } $1 == "claim" { $6 = "seed" } $1 != "claim" && $5 != "" { $6 = "machine" } { print }' "$R/ops/KEYS.tsv" > "$FIX/keys6"
cp "$FIX/keys6" "$R/ops/KEYS.tsv"
mv "$FIX/conv-kept" "$R/ops/CONVENTIONS.md"

echo '== --remember with the layer off: the repo is written, the machine file is not, and nothing more is said =='
cp "$PF" "$FIX/pf-before"
POLARIS_PREFS= I --set fk_voice=warm --remember
cmp -s "$FIX/pf-before" "$PF" && echo 'machine file untouched' || echo 'MACHINE FILE CHANGED'

echo '== --remember: only the keys the machine file lacks are recorded — its fk_voice line is never overwritten =='
POLARIS_PREFS="$PF" I --set fk_voice=warm --set adhd=on --set claim=local-lock --remember
tr -d '\r' < "$PF"   # the fixture was written CRLF; prefs_put writes its own lines LF

echo '== a machine answer counts as answered: --pending is silent with only the machine file saying fk_claim =='
grep -v '^fk_claim:' "$R/ops/CONVENTIONS.md" > "$FIX/conv-nofk"; cp "$FIX/conv-nofk" "$R/ops/CONVENTIONS.md"
POLARIS_PREFS= I --pending
printf 'fk_claim: one\n' >> "$PF"
POLARIS_PREFS="$PF" I --pending

echo '== --remember without --set: refused =='
POLARIS_PREFS="$PF" I --remember
