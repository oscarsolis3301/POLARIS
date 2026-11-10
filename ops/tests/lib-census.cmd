# Which public function lives in which module (ops/contracts/minutes.md § 3.4). observe.sh was cut
# into five files, move-only; this pins where every public name landed, so a later change that moves
# one shows up here as a diff. A function is the § 3.3 one: a column-0 `name() {` line through the
# next column-0 `}` (or that line alone when it ends in `; }`). `_private` helpers are not listed,
# so adding one never moves this golden.
cd kit/ops/lib && LC_ALL=C awk '
FNR == 1 { infn = 0 }
infn { if ($0 == "}") infn = 0; next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {
  name = $0; sub(/\(.*/, "", name)
  if (name !~ /^_/) print FILENAME " " name
  if ($0 !~ /; *\} *$/) infn = 1
}' observe.sh drift.sh check.sh route.sh qa.sh
