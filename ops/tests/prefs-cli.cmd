# prefs-cli — `polaris prefs` (ops/contracts/machine-prefs.md § 7, "Executable checks"): show (the
# layer off, no file, a file, the autonomy mask, a KEYS.tsv without column 6), every --set form and
# refusal (all-or-nothing, not a key, per-project, ask options, tab/#, forbidden models, the RULES
# content ban, the autonomy dial under CLAUDECODE=1, the layer off), --unset, --seed (+ owners: from the
# registered projects' origins, shared-kit.md § 9), --yield — and
# the prefs value == the cfg value for every key of the fixture.
# HERMETIC: a fixture repo whose ops/ plants its OWN KEYS.tsv (kit_file: the repo copy wins), RULES
# and CONVENTIONS, and a machine file under mktemp -d — never the owner's real preferences.
# CLAUDECODE is set or unset explicitly on every call.
F="$(mktemp -d)"
trap 'rm -rf "$F"' EXIT
W="$(pwd)"
export HOME="$F/home" USERPROFILE="$F/home"
unset CLAUDE_CONFIG_DIR CLAUDECODE POLARIS_AWAKE_HOME
R="$F/repo"
( git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
mkdir -p "$R/ops"
T="$(printf '\t')"
{ echo '# fixture registry'
  printf 'base\t1\tmain\tcost\t\trepo\n'
  printf 'claim\t1\tlocal-lock\tcost\tOne or several?|One=local-lock|Several=claim-branch\tseed\n'
  printf 'voice\t1\tstandard\tcost\tHow?|Plain=standard|Terse=technical\tmachine\n'
  printf 'landing\t1\tself\tcost\t\tmachine\n'
  printf 'drain\t1\tplan\tcost\t\tmachine\n'
  printf 'autonomy\t1\ttrusted\tcost\t\tmachine\n'
  printf 'plan_gate\t1\tauto\tcost\t\tmachine\n'
  printf 'builder_questions\t1\tdefault-safe\tcost\t\tmachine\n'
  printf 'evolve_apply\t1\tauto-reversible\tcost\t\tmachine\n'
  printf 'model_strong\t1\topus\tcost\t\tmachine\n'
  printf 'model_runner\t1\thaiku\tcost\t\tmachine\n'
  printf 'notify\t1\t<cmd or omit>\tcost\t\tmachine\n'
  printf 'test\t1\t<cmd>\tcost\t\trepo\n'
} > "$R/ops/KEYS.tsv"
printf 'ops/CONVENTIONS.md\tcontent\t^model_runner:.*([Ff]able|[Oo]pus|FABLE|OPUS)\tthe job runner never runs on Fable or Opus (fixture rule)\n' > "$R/ops/RULES.tsv"
printf 'base: trunk\nvoice: technical   # mine\nlanding:   # blank, falls through\ntest: make test\n' > "$R/ops/CONVENTIONS.md"
M="$F/home/.claude/polaris/preferences"
P() { ( cd "$R" && bash "$W/kit/ops/polaris" prefs "$@" 2>&1; echo "rc=$?" ) | sed "s#$F#<F>#g"; }
A() { ( cd "$R" && CLAUDECODE=1 bash "$W/kit/ops/polaris" prefs "$@" 2>&1; echo "rc=$?" ) | sed "s#$F#<F>#g"; }
showm() { if [ -f "$M" ]; then tr -d '\r' < "$M" | sed 's/^/   | /'; else echo '   | (no machine file)'; fi; }
# eq — the prefs value == cfg's, for every key of the fixture (cfg sourced from the same kit)
eq() {
  ( cd "$R" && bash "$W/kit/ops/polaris" prefs 2>/dev/null ) | sed '1d;$d' > "$F/show"
  ( CONV="$R/ops/CONVENTIONS.md"; . "$W/kit/ops/lib/core.sh"
    n=0; same=0
    while IFS="$T" read -r k v src sc; do
      d="$(awk -F'\t' -v k="$k" '$1 == k { print $3 }' "$R/ops/KEYS.tsv")"
      case "$d" in '<'*|'') d=-;; esac
      n=$((n + 1)); [ "$(cfg "$k" "$d")" = "$v" ] && same=$((same + 1)) || echo "   differs: $k prefs '$v' cfg '$(cfg "$k" "$d")'"
    done < "$F/show"
    echo "prefs == cfg: $same of $n keys" )
}

echo '== 1. show: the layer off · no file =='
POLARIS_PREFS= P
export POLARIS_PREFS="$M"
P | tail -2

echo '== 2. --set: every refusal writes nothing =='
P --set
P --set voice
P --set nosuch=1
P --set base=elsewhere
P --set voice=loud
P --set claim=sometimes
P --set "drain=a${T}b"
P --set 'drain=on#x'
P --set drain=
P --set model_strong=claude-haiku-4-5
P --set model_strong=Fable
P --set model_runner=opus
A --set plan_gate=ask
A --set autonomy=standard
A --unset builder_questions
P --set drain=on voice=loud
POLARIS_PREFS= P --set drain=on
showm

echo '== 3. --set: writes =='
P --set drain=on voice=standard
P --set landing=integrator model_runner=haiku claim=claim-branch
P --set plan_gate=ask
A --set drain=off
P --set drain=slices
showm

echo '== 4. show: a file · the mask · prefs == cfg =='
printf 'base: elsewhere\ntest: echo machine\n' >> "$M"
P
eq
awk '{ printf "%s\r\n", $0 }' "$M" > "$F/crlf"; POLARIS_PREFS="$F/crlf" eq
printf 'autonomy: standard\n' >> "$R/ops/CONVENTIONS.md"
P | grep -E '^(autonomy|plan_gate|drain)'
eq
POLARIS_PREFS= eq

echo '== 5. --unset =='
P --unset plan_gate notify
A --unset drain
POLARIS_PREFS= P --unset drain
showm

echo '== 6. --seed =='
P --seed
mv "$M" "$M.kept"
printf 'plan_gate: ask\n' >> "$R/ops/CONVENTIONS.md"
A --seed
showm
rm -f "$M"
P --seed
showm
mv -f "$M.kept" "$M"

echo '== 7. --yield =='
printf 'base: trunk\nvoice: standard   # same as the machine\nlanding: self\ndrain: slices\nplan_gate: ask\n' > "$R/ops/CONVENTIONS.md"
printf 'voice: standard\nlanding: integrator\ndrain: slices\nplan_gate: ask\n' > "$M"
A --yield
P --yield
tr -d '\r' < "$R/ops/CONVENTIONS.md" | sed 's/^/   | /'
P --yield
echo "temp files left: $(ls -a "$R/ops" "${M%/*}" | grep -c polaris-tmp || true)"

echo '== 8. a KEYS.tsv without column 6 · an unknown form =='
awk -F'\t' '/^#/ { print; next } { print $1 "\t" $2 "\t" $3 "\t" $4 }' "$R/ops/KEYS.tsv" > "$F/k5" && mv "$F/k5" "$R/ops/KEYS.tsv"
P | cut -f1,3,4 | head -4
P --set drain=on
P --frobnicate

echo '== 9. --seed fills owners: from the registered projects, and leaves a repo-set one =='
# Its own fixture: a KEYS.tsv WITH an owners machine row (the fixture KEYS.tsv above has none, so cases 1-8
# never see it), and a registry of four projects — https and scp origins, a repeat, one without origin.
R9="$F/r9"; G="$F/reg"; mkdir -p "$R9/ops" "$G/repos"
( git init -q "$R9"; cd "$R9" && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm init ) >/dev/null 2>&1
{ printf 'voice\t1\tstandard\tcost\t\tmachine\n'; printf 'owners\t1\t\tcost\t\tmachine\n'; } > "$R9/ops/KEYS.tsv"
i=0
for u in https://github.com/alice/one.git git@github.com:bob/two.git https://gitlab.example/alice/three ''; do
  i=$((i + 1)); git init -q "$F/p$i"
  [ -z "$u" ] || git -C "$F/p$i" remote add origin "$u"
  printf '%s\n' "$F/p$i" > "$G/repos/$i"
done
printf '%s\n' "$F/gone" > "$G/repos/9"
M9="$F/m9/preferences"
S9() { ( cd "$R9" && POLARIS_PREFS="$M9" POLARIS_AWAKE_HOME="$G" bash "$W/kit/ops/polaris" prefs --seed 2>&1; echo "rc=$?" ) | sed "s#$F#<F>#g"; }
show9() { tr -d '\r' < "$M9" | grep -v '^#' | sed 's/^/   | /'; }
printf 'voice: technical\n' > "$R9/ops/CONVENTIONS.md"
S9; show9
rm -f "$M9"; printf 'voice: technical\nowners: carol\n' > "$R9/ops/CONVENTIONS.md"
S9; show9
