# cli-docs-parity: every daily command must appear in `polaris help`.
bash kit/ops/polaris help | grep -cE '^  (find|show|check|board-fm|claim|verify|handoff|qa) '
