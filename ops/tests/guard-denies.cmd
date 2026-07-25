# the write-guard must still refuse an installed-copy path and allow an ordinary one.
bash kit/ops/polaris _guard ops/polaris - >/dev/null 2>&1; echo "installed-copy rc=$?"
bash kit/ops/polaris _guard src/ok.txt - >/dev/null 2>&1; echo "ordinary rc=$?"
