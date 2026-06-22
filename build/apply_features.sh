#!/usr/bin/env bash
#
# apply_features.sh -- apply the YuccaA feature set onto the clean sm8750 base.
#
# Runs from the kernel source root. Driven by environment:
#   MODE        resukisu (default) | lkm
#   CACHE       directory for fetched upstream patch sources
#   SUSFS_PIN           susfs4ksu commit to use
#   SUPER_BUILDERS_PIN  Super-Builders commit to use for ZeroMount
#   WILD_PIN            WildKernels/kernel_patches commit to use
#
# resukisu : KSU built-in + SUSFS + ZeroMount + everything else
# lkm      : pure kernel (no KSU/SUSFS/ZeroMount); KSU is injected at flash time
#            by the KSU manager app patching init_boot. SUSFS must be OFF
#            because fs/susfs.c references ksu_* symbols that only link with
#            CONFIG_KSU=y.
set +e
KROOT="$(pwd)"
MODE="${MODE:-resukisu}"
CACHE="${CACHE:-$KROOT/.build_cache}"
SUSFS_PIN="${SUSFS_PIN:-84c8fd6929c0f9a0cdd78f707599b6d76f415d37}"  # susfs4ksu gki-android15-6.6 tip (bumped 2026-06-21)
SUPER_BUILDERS_PIN="${SUPER_BUILDERS_PIN:-c2cb71614868fe742cbffee2b6f3126523432673}" # android15-6.6 ReSukiSU ZeroMount
WILD_PIN="${WILD_PIN:-5a5d5d8}"
SUSFS_URL=https://github.com/ShirkNeko/susfs4ksu.git
SUPER_BUILDERS_URL=https://github.com/Enginex0/Super-Builders.git
WILD_URL=https://github.com/WildKernels/kernel_patches.git
RESUKISU_SETUP=https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh
BBG_SETUP=https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$CACHE"

log(){ echo "[features:$MODE] $*"; }

clone_pin(){ # url pin destdir
  local url="$1" pin="$2" dst="$3"
  if [ ! -d "$dst/.git" ]; then git clone --quiet "$url" "$dst" || return 1; fi
  git -C "$dst" fetch --quiet origin "$pin" 2>/dev/null
  git -C "$dst" checkout --quiet "$pin" 2>/dev/null || git -C "$dst" checkout --quiet "$pin"
}

try_patch(){ # patchfile label
  [ -f "$1" ] || { log "?miss $2"; return; }
  if /usr/bin/patch -p1 -R --dry-run -s -f --no-backup-if-mismatch <"$1" >/dev/null 2>&1; then log "=already $2"
  elif /usr/bin/patch -p1 --forward -F3 -s --no-backup-if-mismatch <"$1" >/dev/null 2>&1; then log "+ok $2"
  else log "!SKIP $2"; fi
  find . -name '*.rej' -delete 2>/dev/null; find . -name '*.orig' -delete 2>/dev/null; }

require_patch(){ # patchfile label
  [ -f "$1" ] || { log "!miss $2"; exit 1; }
  if /usr/bin/patch -p1 -R --dry-run -s -f --no-backup-if-mismatch <"$1" >/dev/null 2>&1; then
    log "=already $2"
  elif /usr/bin/patch -p1 --forward -F3 -s --no-backup-if-mismatch <"$1" >/dev/null 2>&1; then
    log "+ok $2"
  else
    log "!FAIL $2"
    find . -name '*.rej' -print
    exit 1
  fi
  find . -name '*.rej' -delete 2>/dev/null; find . -name '*.orig' -delete 2>/dev/null
}

fix_zeromount_task_mmu(){
  python3 - <<'PY'
import pathlib
import sys

p = pathlib.Path('fs/proc/task_mmu.c')
if not p.exists():
    sys.exit(0)

lines = p.read_text().splitlines(keepends=True)
clean = []
i = 0
while i < len(lines):
    if (
        lines[i].strip() == '#ifdef CONFIG_ZEROMOUNT'
        and i + 2 < len(lines)
        and 'zeromount_spoof_mmap_metadata(inode, &dev, &ino);' in lines[i + 1]
        and lines[i + 2].strip() == '#endif'
    ):
        i += 3
        continue
    clean.append(lines[i])
    i += 1

hook = [
    '#ifdef CONFIG_ZEROMOUNT\n',
    '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n',
    '#endif\n',
]

for start, line in enumerate(clean):
    if line.startswith('\tif (file) {'):
        for end in range(start + 1, len(clean)):
            if clean[end].startswith('\t}'):
                block = ''.join(clean[start:end])
                if (
                    'struct inode *inode' in block
                    and 'dev = inode->i_sb->s_dev;' in block
                    and 'ino = inode->i_ino;' in block
                ):
                    clean[end:end] = hook
                    p.write_text(''.join(clean))
                    sys.exit(0)
                break

raise SystemExit('ZeroMount task_mmu fixup failed: file-backed VMA block not found')
PY
  log "  ZeroMount task_mmu metadata hook fixed"
}

fix_zeromount_runtime_guards(){
  python3 - <<'PY'
import pathlib

def replace_once(path, old, new, label):
    p = pathlib.Path(path)
    s = p.read_text()
    if new in s:
        return False
    if old not in s:
        raise SystemExit(f'ZeroMount runtime guard fixup failed: {label}')
    p.write_text(s.replace(old, new, 1))
    return True

replace_once(
    'fs/zeromount.c',
    '\tif (unlikely(!inode || !inode->i_sb))\n'
    '\t\treturn NULL;\n\n'
    '\tkey = inode->i_ino ^ inode->i_sb->s_dev;\n',
    '\tif (unlikely(!inode || !inode->i_sb) || zeromount_should_skip())\n'
    '\t\treturn NULL;\n\n'
    '\tif (atomic_read(&zeromount_rule_count) == 0)\n'
    '\t\treturn NULL;\n\n'
    '\tkey = inode->i_ino ^ inode->i_sb->s_dev;\n',
    'static vpath must be disabled while ZeroMount is off',
)

replace_once(
    'fs/d_path.c',
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\tif (path->dentry && d_backing_inode(path->dentry)) {\n',
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\tif (!zeromount_should_skip() && path->dentry && d_backing_inode(path->dentry)) {\n',
    'd_path must not enter ZeroMount while disabled',
)

p = pathlib.Path('fs/readdir.c')
s = p.read_text()
s = s.replace(
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\tint initial_count = count;\n'
    '#endif\n',
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\tint initial_count = count;\n'
    '\tbool zm_skip_real_iterate = false;\n'
    '#endif\n',
)
s = s.replace(
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\tif (f.file->f_pos >= ZEROMOUNT_MAGIC_POS) {\n'
    '\t\terror = 0;\n'
    '\t\tgoto skip_real_iterate;\n'
    '\t}\n'
    '#endif\n',
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\tif (!zeromount_should_skip() && f.file->f_pos >= ZEROMOUNT_MAGIC_POS) {\n'
    '\t\terror = 0;\n'
    '\t\tzm_skip_real_iterate = true;\n'
    '\t\tgoto skip_real_iterate;\n'
    '\t}\n'
    '#endif\n',
)
for fn in ('zeromount_inject_dents', 'zeromount_inject_dents64', 'zeromount_inject_dents'):
    old = (
        '#ifdef CONFIG_ZEROMOUNT\n'
        'skip_real_iterate:\n'
        '\tif (error >= 0 && !signal_pending(current)) {\n'
        f'\t\t{fn}(f.file, (void __user **)&dirent, &count, &f.file->f_pos);\n'
        '\t\tif (count != initial_count)\n'
        '\t\t\terror = initial_count - count;\n'
        '\t\tgoto zm_out;\n'
        '\t}\n'
        '#endif\n'
    )
    new = (
        '#ifdef CONFIG_ZEROMOUNT\n'
        'skip_real_iterate:\n'
        '#endif\n'
    )
    if old not in s and new not in s:
        raise SystemExit(f'ZeroMount runtime guard fixup failed: readdir {fn} label')
    s = s.replace(old, new, 1)

marker = '#ifdef CONFIG_ZEROMOUNT\nzm_out:\n#endif\n\tfdput_pos(f);\n'
for fn in ('zeromount_inject_dents', 'zeromount_inject_dents64', 'zeromount_inject_dents'):
    new = (
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\tif (error >= 0 && !signal_pending(current) && !zeromount_should_skip()) {\n'
        '\t\tvoid __user *zm_dirent;\n'
        '\t\tint zm_count;\n'
        '\t\tint zm_original_count;\n\n'
        '\t\tif (zm_skip_real_iterate) {\n'
        '\t\t\tzm_dirent = (void __user *)dirent;\n'
        '\t\t\tzm_count = count;\n'
        '\t\t} else {\n'
        '\t\t\tzm_dirent = (void __user *)buf.current_dir;\n'
        '\t\t\tzm_count = buf.count;\n'
        '\t\t}\n\n'
        '\t\tzm_original_count = zm_count;\n'
        f'\t\t{fn}(f.file, &zm_dirent, &zm_count, &f.file->f_pos);\n'
        '\t\tif (zm_count != zm_original_count)\n'
        '\t\t\terror = initial_count - zm_count;\n'
        '\t}\n'
        '#endif\n'
        '\tfdput_pos(f);\n'
    )
    if marker not in s and new not in s:
        raise SystemExit(f'ZeroMount runtime guard fixup failed: readdir {fn} exit')
    s = s.replace(marker, new, 1)

p.write_text(s)
PY
  log "  ZeroMount runtime guards fixed"
}

zeromount_core_present(){
  [ -f fs/zeromount.c ] &&
    [ -f include/linux/zeromount.h ] &&
    grep -q 'config ZEROMOUNT' fs/Kconfig &&
    grep -q 'CONFIG_ZEROMOUNT' fs/Makefile &&
    grep -q 'zeromount_getname_hook' fs/namei.c &&
    grep -q 'zeromount_inject_dents' fs/readdir.c
}

############################################################
log "1/7 ReSukiSU sources (KSU symlink must resolve at Kconfig time, even in lkm)"
curl -LSs "$RESUKISU_SETUP" | bash -s main >/dev/null 2>&1
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig && log "  KSU sources present"

if [ "$MODE" = "resukisu" ]; then
  log "2/7 SUSFS @ $SUSFS_PIN"
  clone_pin "$SUSFS_URL" "$SUSFS_PIN" "$CACHE/susfs"
  cp -rf "$CACHE/susfs/kernel_patches/fs/." fs/
  cp -rf "$CACHE/susfs/kernel_patches/include/linux/." include/linux/
  /usr/bin/patch -p1 --forward --fuzz=3 < "$CACHE/susfs/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch" >/dev/null 2>&1
  # namespace.c include-area skew: ensure the susfs_def.h include is present (idempotent).
  if ! grep -q "linux/susfs_def.h" fs/namespace.c; then
    perl -0pi -e 's{#include <linux/mnt_idmapping.h>\n}{#include <linux/mnt_idmapping.h>\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif\n}' fs/namespace.c
  fi

  log "  Super-Builders ZeroMount patch @ $SUPER_BUILDERS_PIN"
  clone_pin "$SUPER_BUILDERS_URL" "$SUPER_BUILDERS_PIN" "$CACHE/super_builders" || exit 1
  SB_PATCHES="$CACHE/super_builders/android15-6.6/ReSukiSU/patches"
  if zeromount_core_present; then
    log "=already zeromount"
  else
    require_patch "$SB_PATCHES/60_zeromount-android15-6.6.patch" zeromount
  fi
  fix_zeromount_task_mmu
  fix_zeromount_runtime_guards

  # Keep ReSukiSU/SUSFS SELinux hide intact. ReSukiSU detects the SUSFS
  # manual hook via kernel/tools/susfs_compat.mk and exposes the needed
  # fake_status symbols from feature/selinux_hide.c.
  log "  susfs rejects: $(find . -name '*.rej'|wc -l); setresuid hook: $(grep -c ksu_handle_setresuid kernel/sys.c)"
  find . -name '*.rej' -delete 2>/dev/null; find . -name '*.orig' -delete 2>/dev/null
else
  log "2/7 SUSFS skipped (lkm: pure kernel)"
  log "  ZeroMount skipped (lkm: pure kernel)"
fi

log "3/7 Baseband-guard"
( export PATH="/usr/bin:/bin:$PATH"; curl -fsSL "$BBG_SETUP" | bash >/dev/null 2>&1 ) && log "  bbg ok"

log "4/7 Wild perf patches @ $WILD_PIN"
clone_pin "$WILD_URL" "$WILD_PIN" "$CACHE/wild"
W="$CACHE/wild/common"
for p in silence_irq_cpu_logspam f2fs_enlarge_min_fsync_blocks f2fs_reduce_congestion reduce_gc_thread_sleep_time \
  increase_ext4_default_commit_age clear_page_16bytes_align file_struct_8bytes_align disable_cache_hot_buddy \
  reduce_cache_pressure mem_opt_prefetch optimized_mem_operations int_sqrt add_timeout_wakelocks_globally \
  avoid_extra_s2idle_wake_attempts minimise_wakeup_time reduce_freeze_timeout reduce_pci_pme_wakeups \
  increase_sk_mem_packets force_tcp_nodelay; do try_patch "$W/$p.patch" "$p"; done

log "5/7 unicode + droidspaces + NTSync"
try_patch "$W/unicode_bypass_fix_6.1+.patch" unicode
try_patch "$W/droidspaces/fix_sysvipc_kabi_6_7_8.patch" droidspaces_kabi
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

log "6/7 Re:Kernel (vendored)"
mkdir -p drivers/rekernel
cp -f "$HERE/features/rekernel/." drivers/rekernel/ 2>/dev/null
cp -f "$HERE/features/rekernel/"* drivers/rekernel/
grep -q 'drivers/rekernel/Kconfig' drivers/Kconfig || sed -i '/^endmenu/i source "drivers/rekernel/Kconfig"' drivers/Kconfig
grep -q 'rekernel/' drivers/Makefile || printf '\nobj-$(CONFIG_REKERNEL) += rekernel/\n' >> drivers/Makefile
log "  rekernel wired: $(ls drivers/rekernel | tr '\n' ' ')"

log "7/7 IPv6 NAT hide (config_data scrubs CONFIG_IP6_NF_NAT=y so /proc/config.gz hides it)"
python3 - <<'PY'
import pathlib
p=pathlib.Path('kernel/Makefile'); s=p.read_text()
if 'IP6_NF_NAT_FIX_MARKER' not in s:
    blk='\n# IP6_NF_NAT_FIX_MARKER\ndefine config_fix\n\tif grep -q \'^CONFIG_IP6_NF_NAT=y\' $@; then sed -i \'s/^CONFIG_IP6_NF_NAT=y$$/CONFIG_IP6_NF_NAT=n/\' $@; fi\nendef\n'
    n='filechk_cat = cat $<\n'; i=s.find(n)
    if i>=0:
        s=s[:i+len(n)]+blk+s[i+len(n):]
        r='$(obj)/config_data: arch/arm64/configs/stock_gki_defconfig FORCE\n\t$(call filechk,cat)\n'
        if r in s: s=s.replace(r, r+'\t$(Q)$(config_fix)\n',1)
        p.write_text(s); print('[features] ipv6 hide applied')
PY
log "feature application complete"
