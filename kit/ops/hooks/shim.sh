#!/usr/bin/env bash
# POLARIS hook shim — `--setup` copies this file to <POLARIS_HOME>/hook (ops/contracts/hook-dispatch.md
# § 4) and registers `bash "<POLARIS_HOME>/hook" <event>` once per event. Do not edit the copy.
# It finds the kit this computer runs (kit/current, a plain version token) with builtins only — no
# process — and sources that kit's dispatcher. No valid kit: nothing at all, exit 0 (fail open).
# The read-only allow comes from the trust tier only --setup writes, never from an updated kit.
_sh_h="${BASH_SOURCE[0]//\\//}"
_sh_d=.
case "$_sh_h" in */*) _sh_d="${_sh_h%/*}";; esac
_sh_re='^[0-9]+\.[0-9]+\.[0-9]+$'
for _sh_t in 1 2; do
  _sh_v=''
  { read -r _sh_v < "$_sh_d/kit/current"; } 2>/dev/null
  _sh_v="${_sh_v%$'\r'}"
  if [[ $_sh_v =~ $_sh_re ]]; then break; fi
  _sh_v=''
done
if [ -n "$_sh_v" ] && [ -f "$_sh_d/kit/$_sh_v/ops/hooks/dispatch.sh" ]; then
  DP_TRUST="$_sh_d/trust/readonly-allow.sh"
  . "$_sh_d/kit/$_sh_v/ops/hooks/dispatch.sh" "$@"
fi
exit 0
