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

require_grep 'SUPER_BUILDERS_URL=.*Enginex0/Super-Builders' "$APPLY" \
  "apply_features.sh must fetch Super-Builders for ZeroMount patches"
require_grep '60_zeromount-android15-6\.6\.patch' "$APPLY" \
  "resukisu mode must apply the ZeroMount kernel patch"
require_grep 'fix_zeromount_task_mmu' "$APPLY" \
  "ZeroMount integration must fix task_mmu metadata hook placement"
require_grep 'fix_zeromount_runtime_guards' "$APPLY" \
  "ZeroMount integration must keep disabled ZeroMount out of boot-critical paths"
require_grep 'buf\.current_dir' "$APPLY" \
  "ZeroMount readdir injection must append after real directory entries"
reject_grep '51_enhanced_susfs-android15-6\.6\.patch' "$APPLY" \
  "apply_features.sh must not force Super-Builders enhanced SUSFS over ShirkNeko SUSFS tip"
require_grep 'ZeroMount skipped \(lkm: pure kernel\)' "$APPLY" \
  "lkm mode must explicitly skip ZeroMount"

require_grep 'ZEROMOUNT' "$BUILD" \
  "build.sh must enable/report CONFIG_ZEROMOUNT in resukisu mode"
require_grep '\-d KSU \-d KSU_SUSFS \-d ZEROMOUNT' "$BUILD" \
  "build.sh must explicitly disable CONFIG_ZEROMOUNT in lkm mode"
require_grep 'git rev-parse --short=7 HEAD' "$BUILD" \
  "build.sh must derive the default build id from the source commit"
require_grep 'YuccaA-\$\{BUILD_ID\}-4k' "$BUILD" \
  "kernel localversion must use the short commit build id"
reject_grep 'shuf -i|abogki' "$BUILD" \
  "build.sh must not use random abogki build numbers"

reject_grep 'fake_status.*NULL|ksu_selinux_hide_enabled\\).*&& 0|!ksu_selinux_hide_running/1|initialize_fake_status\\(\\);/\\(void\\)0' "$APPLY" \
  "apply_features.sh must not neutralise ReSukiSU/SUSFS SELinux hide"


# Performance tuning must not be reintroduced through the build-time patch list.
reject_grep 'apply_wild_perf|APPLY_WILD_PERF|for p in silence_irq_cpu_logspam' "$APPLY" \
  "Wild performance injection is removed"
require_grep 'RESUKISU_REF' "$APPLY" \
  "ReSukiSU sources must use a fixed revision"

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
require_grep 'resukisu-susfs-2.3.patch' "$APPLY" \
  "SUSFS 2.3 must be adapted to the pinned ReSukiSU exec hook API"
[ -s "$ROOT/build/features/resukisu-susfs-2.3.patch" ] || fail "missing ReSukiSU compatibility patch"

require_grep '/usr/bin/patch -p1 -R --forward --dry-run --batch --fuzz=0' "$APPLY" \
  "compatibility reverse checks must not auto-switch to forward application"

echo "feature integration checks passed"
