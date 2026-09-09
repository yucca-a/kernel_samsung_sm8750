# SM8750 6.6.156 vendor ABI repair

Status: local build and targeted ABI checks passed; real-device boot is not
verified. This is a candidate repair for the first-splash / black-screen reboot.
No pstore from the failing device was available to identify its first failure.

## Why this update could fail before Android starts

The 6.6.138 to 6.6.156 import changed interfaces used by prebuilt vendor modules.
For example, device grew from 936 to 952 bytes and its mutex moved from byte
160 to 176. task_struct members and embedded writeback structures also moved.
GPIO entry points kept their names but changed argument lists, and the old
ioremap_prot export disappeared. Matching source versions alone does not make
these changes compatible with Samsung's already-built modules.

The repair keeps 6.6.156, the removal of Wild performance patches, and the
existing feature selections. It does not disable module version checks.

## Compatibility changes

- Use Android KABI reserves for device override state, bus flags, task state,
  Qdisc state, xHCI DMA-mask state, and BPF verifier state.
- Preserve legacy platform/rpmsg driver_override fields and matching behavior.
- Keep writeback switch work in allocator-owned state referenced from a reserve.
- Restore old GPIO, PCI resize and ioremap exports; use distinct new interfaces
  for changed in-tree callers.
- Retain the two-argument link-header parser and add a reserved callback slot
  for the LTS stacked-device fix.
- Preserve network statistics layouts and dispatch reads/writes by stats type.
- Keep RCU action cleanup and connection-tracking creator state outside the
  old vendor-visible allocations; preserve the old helper assignment slot.
- Keep the old BPF index-pair history view while separately maintaining the
  richer LTS precision-tracking history.
- Preserve existing enum values and layout-neutral type metadata where needed.

## Validation

Baseline: cb0d022c9 (6.6.138), built using Samsung clang-r510928 and the current
LKM configuration normalized through olddefconfig. The retained Droidspaces
SYSVIPC reserve adaptation was applied to its task_struct. New feature-only
options unavailable in that baseline are not part of the comparison.

Both LKM and ReSuki Image builds passed locally. For each mode:

- 2730 baseline exports in android/abi_gki_aarch64, _galaxy and _qcom:
  zero missing exports or changed symbol CRCs.
- 26 selected structures: zero changes to size or old member offsets.
- Clean ReSuki feature application: no rejected SUSFS hunks; all files touched
  by this repair match the incrementally built tree after feature application.
- Existing feature integration checks pass.
- Host BPF history tests pass under AddressSanitizer and UndefinedBehaviorSanitizer,
  including growth, same-instruction merging, deep copy, allocation failures,
  empty history, and cleanup.

Run the checks with matching arm64 production configurations:

```sh
python3 build/test_vendor_history.py
bash build/test_feature_integration.sh
# check_vendor_abi.py requires pyelftools.
python3 build/check_vendor_abi.py BASELINE_OUT CURRENT_OUT \
  --types device bus_type platform_device rpmsg_device task_struct \
  bdi_writeback backing_dev_info header_ops net_device mm_struct inode file \
  Qdisc tc_action tcf_block tcf_proto pcpu_dstats ctl_table_header \
  sdhci_host ucsi_connector xhci_hcd genl_multicast_group \
  bpf_verifier_state bpf_verifier_env nf_ct_ext nf_conntrack_expect \
  --symbols android/abi_gki_aarch64 android/abi_gki_aarch64_galaxy \
  android/abi_gki_aarch64_qcom
```

## Limits and device test

This is not a claim of universal GKI compatibility: 266 other baseline exports
still differ in the unfiltered LKM comparison. The targeted symbol lists do not
prove what every firmware/vendor module imports. Debug/lockdep/KCOV configurations
are not covered, and BTF offsets plus CRCs cannot prove runtime behavior.

First test with a known working boot image available for recovery. Record the
exact model, firmware, root mode and ZIP name. Confirm boot, storage/decryption,
USB/charging, Wi-Fi/Bluetooth, sensors and suspend/wake. If boot still fails,
recover pstore/ramoops before another boot overwrites it and compare the exact
vendor modules' imports and version CRCs against this build.
