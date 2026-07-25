# cli-docs-parity: every daily command must appear in `polaris help`.
# Counts DISTINCT commands, not matching lines. `grep -c` counted lines, so when `check` gained a
# second usage form (`check --scaffold`) in 5.19.0 this went 8 -> 9 and reddened on an addition that
# broke nothing. The assertion was always "all 8 are documented"; this measures that directly, and
# still reds the moment any one of them disappears from help.
bash kit/ops/polaris help | grep -oE '^  (find|show|check|board-fm|claim|verify|handoff|qa) ' \
  | awk '{print $1}' | sort -u | wc -l | tr -d ' '
