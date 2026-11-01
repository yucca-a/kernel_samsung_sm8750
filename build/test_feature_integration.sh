#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/build/apply_features.sh"
BUILD="$ROOT/build/build.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_grep() {
  local pattern="$1" file="$2" label="$3"
  grep -Eq "$pattern" "$file" || fail "$label"
}

reject_grep() {
  local pattern="$1" file="$2" label="$3"
  ! grep -Eq "$pattern" "$file" || fail "$label"
}

require_grep 'git rev-parse --short=7 HEAD' "$BUILD" \
  "build.sh must derive the default build id from the source commit"
require_grep 'YuccaA-\$\{BUILD_ID\}-4k' "$BUILD" \
  "kernel localversion must use the short commit build id"
reject_grep 'shuf -i|abogki' "$BUILD" \
  "build.sh must not use random abogki build numbers"

# Performance tuning must not be reintroduced through the build-time patch list.
reject_grep 'apply_wild_perf|APPLY_WILD_PERF|for p in silence_irq_cpu_logspam' "$APPLY" \
  "Wild performance injection is removed"

require_grep '\-e NETFILTER_XT_SET' "$BUILD" \
  "both modes must build the iptables set match into the kernel"
require_grep "CONFIG_NETFILTER_XT_SET=y" "$BUILD" \
  "build.sh must reject an incomplete IP_SET configuration"

require_grep '^COMMON_DISABLE=.*-d REKERNEL_LEGACY_NETLINK' "$BUILD" \
  "both modes must explicitly disable legacy ReKernel transport"
reject_grep '\-e REKERNEL_LEGACY_NETLINK' "$BUILD" \
  "build.sh must not force legacy ReKernel transport"
legacy_default=$(sed -n '/^config REKERNEL_LEGACY_NETLINK/,/^endmenu/p' \
  "$ROOT/build/features/rekernel/Kconfig" | grep -E '^[[:space:]]*default ')
[[ "$legacy_default" =~ default[[:space:]]+n$ ]] || fail "ReKernel must default to Generic Netlink"
require_grep 'REKERNEL_MAJOR_VERSION[[:space:]]+"11\.6"' "$ROOT/build/features/rekernel/rekernel.h" \
  "ReKernel must remain pinned to the requested official 11.6 release"
require_grep '^Commit: 5adec4896a549af60fab2ab59441a777551763b9$' "$ROOT/build/features/rekernel/PROVENANCE" \
  "ReKernel provenance must identify the official 11.6 source"
reject_grep 'rekernel_binder_alloc\.o' "$ROOT/build/features/rekernel/Makefile" \
  "ReKernel 11.6 must not link the removed 11.0 buffer helper"
# The build must never stage a root implementation into this source tree.
python3 "$ROOT/scripts/check_lkm.py" source "$ROOT"
if grep -Eq 'ReSukiSU/|susfs4ksu|Super-Builders|fetch_kernelsu.sh' "$APPLY" "$BUILD"; then
  fail "retired root dependency is still reachable from the build"
fi

echo "feature integration checks passed (LKM only)"
