#!/usr/bin/env bash
#
# build.sh -- build the Samsung sm8750 (Galaxy S25) GKI kernel.
#
# Usage:
#   ./build.sh [lkm] [--pack] [--check] [--jobs N]
#
# Mode: lkm only; root is provided by a separately installed KernelSU module.
#
# Environment overrides:
#   TOOLCHAIN_DIR  prebuilts dir (default: ../toolchain_samsung_sm8750/kernel_platform/prebuilts)
#   JOBS           parallel jobs (default: 16)
#   PACK           1 to pack an AnyKernel3 zip (needs ANYKERNEL_DIR)
#   ANYKERNEL_DIR  path to an AnyKernel3 tree (default: ../AnyKernel3_s25)
#   BUILD_ID       override the short commit build id in the kernel name
#   BUILD_NUM      legacy alias for BUILD_ID
#
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/build_entry.sh"
kernel_entry_init "$@"

KROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KROOT"
HERE="$KROOT/build"
OUT="$OUT_DIR"
JOBS="${JOBS:-$(nproc)}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$KROOT/../toolchain_samsung_sm8750/kernel_platform/prebuilts}"
CLANG_BIN="$TOOLCHAIN_DIR/clang/host/linux-x86/$BUILD_CLANG/bin"
ANYKERNEL_DIR="${ANYKERNEL_DIR:-$KROOT/../AnyKernel3_s25}"
KMI_GEN=8   # android15-6.6 == KMI generation 8

[ -d "$CLANG_BIN" ] || { echo "ERROR: toolchain not found at $CLANG_BIN
Set TOOLCHAIN_DIR to your Samsung clang-r510928 prebuilts dir."; exit 1; }

echo "=== sm8750 build: MODE=$MODE  JOBS=$JOBS ==="
echo "    $(grep -m1 '^VERSION' Makefile | tr -d ' ') $(grep -m1 '^PATCHLEVEL' Makefile | tr -d ' ') $(grep -m1 '^SUBLEVEL' Makefile | tr -d ' ')"

# ---- toolchain env ----
export PATH="$TOOLCHAIN_DIR/build-tools/linux-x86/bin:$TOOLCHAIN_DIR/build-tools/path/linux-x86:$CLANG_BIN:$TOOLCHAIN_DIR/kernel-build-tools/linux-x86/bin:$PATH"
sysroot="--sysroot=$TOOLCHAIN_DIR/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot"
export LD_LIBRARY_PATH="$TOOLCHAIN_DIR/kernel-build-tools/linux-x86/lib64"
export HOSTCFLAGS="$sysroot -I$TOOLCHAIN_DIR/kernel-build-tools/linux-x86/include"
export HOSTLDFLAGS="$sysroot -L $TOOLCHAIN_DIR/kernel-build-tools/linux-x86/lib64 -fuse-ld=lld --rtlib=compiler-rt"
# ccache (big speedup on rebuilds; no-op if ccache absent). Masquerade a clang
# symlink at the front of PATH so the string-based "CC=clang" routes through
# ccache, which then finds the real clang further down PATH (CLANG_BIN).
# Honours CCACHE_DIR / CCACHE_MAXSIZE exported by the CI (cached across runs).
if [[ ${USE_CCACHE:-1} == 1 ]] && command -v ccache >/dev/null 2>&1; then
  export CCACHE_DIR="${CCACHE_DIR:-$KROOT/.ccache}"
  export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"
  mkdir -p "$CCACHE_DIR" "$OUT/.ccache_bin"
  ln -sf "$(command -v ccache)" "$OUT/.ccache_bin/clang"
  export PATH="$OUT/.ccache_bin:$PATH"
  echo "    ccache: on (dir=$CCACHE_DIR max=$CCACHE_MAXSIZE)"
fi
MAKE_ARGS="CC=clang ARCH=arm64 LLVM=1 LLVM_IAS=1"

# ---- apply Root-independent features ----
MODE="$MODE" CACHE="$KROOT/.build_cache" bash "$HERE/apply_features.sh"

# ---- configure ----
echo "=== configure ==="
make -j"$JOBS" O="$OUT" $MAKE_ARGS "$BUILD_DEFCONFIG" >/dev/null
BUILD_ID="${BUILD_ID:-${BUILD_NUM:-$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)}}"
rm -f localversion

# common: drop Samsung security stack that conflicts with custom kernels
COMMON_DISABLE="-d UH -d RKP -d KDP -d SECURITY_DEFEX -d INTEGRITY -d FIVE -d TRIM_UNUSED_KSYMS -d REKERNEL_LEGACY_NETLINK"
# common features (KSU-independent): NTFS3, zram-lz4, FQ+BBR, NTSync, IPv6 NAT, Re:Kernel, sysvipc/mqueue
COMMON_ENABLE="-e NTFS3_FS -e NTFS3_LZX_XPRESS -e ZRAM_DEF_COMP_LZ4 --set-str ZRAM_DEF_COMP lz4 \
  -e NET_SCH_FQ -e TCP_CONG_BBR -e DEFAULT_BBR -e NTSYNC -e IP6_NF_NAT -e REKERNEL \
  -e SYSVIPC -e POSIX_MQUEUE -e IPC_NS -e PID_NS -e DEVTMPFS \
  -e NETFILTER_XT_MATCH_ADDRTYPE -e NETFILTER_XT_MATCH_RECENT \
  -e TMPFS -e TMPFS_POSIX_ACL -e TMPFS_XATTR -e TMPFS_INODE64 \
  -e NETFILTER_XT_TARGET_HL -e NETFILTER_XT_SET \
  -e IP_SET -e IP_SET_BITMAP_IP -e IP_SET_BITMAP_IPMAC -e IP_SET_BITMAP_PORT \
  -e IP_SET_HASH_IP -e IP_SET_HASH_IPMARK -e IP_SET_HASH_IPPORT -e IP_SET_HASH_IPPORTIP \
  -e IP_SET_HASH_IPPORTNET -e IP_SET_HASH_IPMAC -e IP_SET_HASH_MAC -e IP_SET_HASH_NET \
  -e IP_SET_HASH_NETNET -e IP_SET_HASH_NETPORT -e IP_SET_HASH_NETPORTNET \
  -e IP_SET_HASH_NETIFACE -e IP_SET_LIST_SET"

# The kernel carries no root implementation; a matching official LKM is installed separately.
./scripts/config --file "$OUT_DIR/.config" \
  -e MODULES -e KPROBES -e KALLSYMS -e KALLSYMS_ALL -e EXT4_FS \
  -d KSU -d KSU_SUSFS -d ZEROMOUNT -d KPM \
  -d MODULE_SIG_FORCE -d MODULE_SIG_PROTECT -d TRIM_UNUSED_KSYMS

# shellcheck disable=SC2086
./scripts/config --file "$OUT/.config" $COMMON_DISABLE $COMMON_ENABLE \
  -d LOCALVERSION_AUTO --set-str LOCALVERSION "-android15-${KMI_GEN}-YuccaA-${BUILD_ID}-4k"

# baseband_guard LSM
if grep -q '^CONFIG_LSM="' "$OUT/.config" && ! grep -q baseband_guard "$OUT/.config"; then
  sed -i 's/^\(CONFIG_LSM="[^"]*\)"$/\1,baseband_guard"/' "$OUT/.config"
fi
make -j"$JOBS" O="$OUT" $MAKE_ARGS olddefconfig >/dev/null
python3 "$KROOT/scripts/check_lkm.py" config "$OUT_DIR/.config"

# IP_SET without XT_SET cannot be consumed by iptables' -m set match.
if ! grep -q '^CONFIG_NETFILTER_XT_SET=y$' "$OUT/.config"; then
  echo "ERROR: IP_SET requires built-in NETFILTER_XT_SET support" >&2
  exit 1
fi

# Match the official Re:Kernel module's Generic Netlink transport.
if ! grep -q '^CONFIG_REKERNEL=y$' "$OUT/.config" || \
   grep -q '^CONFIG_REKERNEL_LEGACY_NETLINK=y$' "$OUT/.config"; then
  echo "ERROR: ReKernel must be built in with Generic Netlink" >&2
  exit 1
fi

echo "=== config summary ==="
for c in MODULES KPROBES KALLSYMS NTFS3_FS ZRAM_DEF_COMP_LZ4 TCP_CONG_BBR NTSYNC IP6_NF_NAT IP_SET NETFILTER_XT_SET REKERNEL REKERNEL_LEGACY_NETLINK POSIX_MQUEUE; do
  printf '    %-20s %s\n' "$c" "$(grep -q "^CONFIG_$c=y" "$OUT/.config" && echo y || echo n)"
done
printf '    %-20s %s\n' "baseband_guard" "$(grep -q baseband_guard "$OUT/.config" && echo y || echo n)"

# ---- build (retry once: kbuild fixdep occasionally races on a parallel build) ----
echo "=== build Image ==="
if ! make -j"$JOBS" O="$OUT" $MAKE_ARGS Image; then
  echo "=== first pass failed; retrying incrementally (fixdep race guard) ==="
  make -j"$JOBS" O="$OUT" $MAKE_ARGS Image
fi
IMG="$OUT/arch/arm64/boot/Image"
REL="$(cat "$OUT/include/config/kernel.release")"
echo "    Image: $(stat -c%s "$IMG") bytes   release: $REL"

# ---- pack (optional) ----
if [ "${PACK:-0}" = "1" ]; then
  [ -d "$ANYKERNEL_DIR" ] || { echo "ANYKERNEL_DIR not found: $ANYKERNEL_DIR"; exit 1; }
  tag="LKM"
  ZIP="$OUT/SM8750_${tag}_${REL%%-*}_$(date +%m%d).zip"
  WORK="$(mktemp -d "$OUT/anykernel.XXXXXX")"
  trap 'rm -rf -- "$WORK"' EXIT
  cp -a "$ANYKERNEL_DIR/." "$WORK/"
  rm -f "$WORK"/*.zip "$WORK/zImage" "$WORK/Image"
  cp -f "$IMG" "$WORK/zImage"
  # Accept the S25 Edge (codename psq, SM-S9370) too: same SM8750 GKI kernel,
  # one zip for the whole S25 family. ak3 update-binary matches any
  # device.name*= value against ro.product.device, so the index is arbitrary.
  ak="$WORK/anykernel.sh"
  if [ -f "$ak" ] && ! grep -qE '^device\.name[0-9]*=psq$' "$ak"; then
    sed -i "/^do.devicecheck=/a device.name4=psq" "$ak"
  fi
  [ -f "$ak" ] && echo "    AnyKernel devices: $(grep -oE '^device.name[0-9]+=[a-z0-9]+' "$ak" | cut -d= -f2 | tr '\n' ' ')"
  rm -f "$ZIP"
  ( cd "$WORK" && zip -r9 "$ZIP" . -x '*.git*' '*.zip' >/dev/null )
  kernel_publish_zip "$ZIP"
  echo "=== packed: $ZIP ($(du -h "$ZIP" | cut -f1)) ==="
fi
echo "=== DONE ($MODE): $REL ==="
