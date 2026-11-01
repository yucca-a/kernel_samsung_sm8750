#!/usr/bin/env bash
#
# apply_features.sh -- apply the YuccaA feature set onto the clean sm8750 base.
#
# LKM-only feature preparation. CACHE controls downloaded independent sources;
# WILD_PIN pins the retained Unicode and Droidspaces fixes.
set -euo pipefail
KROOT="$(pwd)"
MODE="${MODE:-lkm}"
CACHE="${CACHE:-$KROOT/.build_cache}"
WILD_PIN="${WILD_PIN:-5a5d5d834706497bf60aa4ba77742727cb64cf14}"
WILD_URL=https://github.com/WildKernels/kernel_patches.git
BBG_SETUP=https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
[[ "$MODE" == lkm ]] || { echo "ERROR: Only lkm is maintained." >&2; exit 2; }
[[ ${APPLY_SUSFS:-0} == 0 && ${APPLY_ZEROMOUNT:-0} == 0 ]] || { echo "ERROR: Built-in root features have been retired." >&2; exit 2; }
python3 "$HERE/../scripts/check_lkm.py" source "$KROOT"
mkdir -p "$CACHE"

log(){ echo "[features:$MODE] $*"; }
die(){ log "ERROR: $*" >&2; exit 1; }

clone_pin(){ # url pin destdir
  local url="$1" pin="$2" dst="$3"
  if [ ! -d "$dst/.git" ]; then git clone --quiet "$url" "$dst" || return 1; fi
  git -C "$dst" fetch --quiet origin "$pin" || return 1
  git -C "$dst" checkout --quiet "$pin" || return 1
}

run_setup(){ # url label [arguments...]
  local url="$1" label="$2" setup
  shift 2
  setup=$(mktemp "$CACHE/${label}.XXXXXX.sh") || return 1
  # Do not execute a partially downloaded script; retain failures for diagnosis.
  curl -fLSs --retry 3 -o "$setup" "$url" || return 1
  ( export PATH="/usr/bin:/bin:$PATH"; bash "$setup" "$@" ) || return 1
  rm -f -- "$setup"
}

require_patch(){ # patchfile label
  [ -f "$1" ] || die "Missing required patch: $2 ($1)"
  if /usr/bin/patch -p1 -R --forward --dry-run --batch --fuzz=3 <"$1" >/dev/null 2>&1; then
    log "=already $2"
  elif /usr/bin/patch -p1 --forward --batch --fuzz=3 --no-backup-if-mismatch <"$1"; then
    log "+ok $2"
  else
    # Keep rejects and backups. Never erase evidence of a partial application.
    die "Required patch failed: $2; retain .rej files and use a clean build worktree"
  fi
}

############################################################
log "1/5 Baseband-guard"
run_setup "$BBG_SETUP" baseband-guard || die "Baseband-guard setup failed"
[ -f security/baseband-guard/Kconfig ] || die "Baseband-guard sources missing"
grep -q 'security/baseband-guard/Kconfig' security/Kconfig || die "Baseband-guard Kconfig is not wired"
grep -Fq 'obj-$(CONFIG_BBG) += baseband-guard/' security/Makefile || die "Baseband-guard Makefile is not wired"
log "  bbg ok"

log "2/5 retained Unicode/Droidspaces patches @ $WILD_PIN"
clone_pin "$WILD_URL" "$WILD_PIN" "$CACHE/wild"
W="$CACHE/wild/common"


log "3/5 unicode + droidspaces + NTSync"
require_patch "$W/unicode_bypass_fix_6.1+.patch" unicode
require_patch "$W/droidspaces/fix_sysvipc_kabi_6_7_8.patch" droidspaces_kabi
# NTSync: vendored upstream driver (build/features/ntsync) -- no external fetch.
cp -f "$HERE/features/ntsync/ntsync.c" drivers/misc/ntsync.c
cp -f "$HERE/features/ntsync/ntsync.h" include/uapi/linux/ntsync.h
python3 - <<'PY'
import pathlib
kc = pathlib.Path('drivers/misc/Kconfig'); s = kc.read_text()
if 'config NTSYNC' not in s:
    stanza = ('config NTSYNC\n\ttristate "NT synchronization primitive emulation"\n'
              '\tdefault\tm\n\thelp\n'
              '\t  Kernel support for Windows NT synchronization primitive\n'
              '\t  emulation (Wine/Proton). If unsure, say N.\n\n')
    i = s.rfind('\nendmenu')
    kc.write_text((s + '\n' + stanza) if i < 0 else (s[:i+1] + stanza + s[i+1:]))
    print('  ntsync: Kconfig stanza inserted')
mk = pathlib.Path('drivers/misc/Makefile'); m = mk.read_text()
if 'CONFIG_NTSYNC)' not in m:
    mk.write_text(m + '\nobj-$(CONFIG_NTSYNC)\t+= ntsync.o\n')
    print('  ntsync: Makefile wired')
PY
log "  ntsync.c (vendored): $([ -f drivers/misc/ntsync.c ] && echo yes || echo no)"

log "4/5 Re:Kernel (vendored)"
mkdir -p drivers/rekernel
cp -a "$HERE/features/rekernel/." drivers/rekernel/
grep -q 'drivers/rekernel/Kconfig' drivers/Kconfig || sed -i '/^endmenu/i source "drivers/rekernel/Kconfig"' drivers/Kconfig
grep -q 'rekernel/' drivers/Makefile || printf '\nobj-$(CONFIG_REKERNEL) += rekernel/\n' >> drivers/Makefile
log "  rekernel wired: $(ls drivers/rekernel | tr '\n' ' ')"

log "5/5 IPv6 NAT hide (config_data scrubs CONFIG_IP6_NF_NAT=y so /proc/config.gz hides it)"
python3 - <<'PY'
import pathlib
p=pathlib.Path('kernel/Makefile'); s=p.read_text()
if 'IP6_NF_NAT_FIX_MARKER' not in s:
    blk='\n# IP6_NF_NAT_FIX_MARKER\ndefine config_fix\n\tif grep -q \'^CONFIG_IP6_NF_NAT=y\' $@; then sed -i \'s/^CONFIG_IP6_NF_NAT=y$$/CONFIG_IP6_NF_NAT=n/\' $@; fi\nendef\n'
    n='filechk_cat = cat $<\n'; i=s.find(n)
    if i < 0:
        raise SystemExit('config_data helper not found')
    if i>=0:
        s=s[:i+len(n)]+blk+s[i+len(n):]
        r='$(obj)/config_data: arch/arm64/configs/stock_gki_defconfig FORCE\n\t$(call filechk,cat)\n'
        if r not in s:
            raise SystemExit('config_data target not found')
        s=s.replace(r, r+'\t$(Q)$(config_fix)\n',1)
        p.write_text(s); print('[features] ipv6 hide applied')
PY
log "feature application complete"
