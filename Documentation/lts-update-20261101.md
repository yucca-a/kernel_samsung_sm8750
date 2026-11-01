# SM8750 Linux 6.6.161 LTS candidate (2026-11-01)

Status: **candidate only; vendor ABI validation failed; not a flashable release**.
The normal maintenance worktree remains at Linux 6.6.156 with its existing
uncommitted LKM-only changes intact. This candidate is on `codex/lts-6.6.161-candidate`.

## Source

Applied the kernel.org incremental LTS patches from 6.6.156 to 6.6.161
using a three-way merge against the corresponding pristine upstream files.
Downloads were checked against the SHA-256 values published at
<https://cdn.kernel.org/pub/linux/kernel/>. This is checksum verification, not
an assertion that OpenPGP signatures were verified. Exact file hashes are in
`Documentation/lts-sources-20261101.json`.

Existing Samsung/Android differences and LKM-only build policy were retained.
The implementation includes vendor API adaptations in USB, F2FS, memory
management, networking and firmware drivers. It is not byte-identical to the
vanilla Linux release, and no claim of complete CVE coverage is made.

## Validation

- Native `./build.sh lkm`, Samsung toolchain, production defconfig, Image target: passed.
- The pre-update snapshot was rebuilt with the corresponding LKM configuration.
- Root-source guard and feature preparation: passed. Two consecutive feature
  passes produce the same tracked source tree.
- SM8550 ptrace patch was rebased and now checks before applying, fails on a
  mismatch and recognizes an already-applied patch. BBG object registration
  is deduplicated after its setup script.
- Selected Android/Galaxy/QCOM export CRCs: **1644 mismatches among 2730 exports**.
- Selected core-structure layout changes: net_device, Scsi_Host, xhci_hcd.
- Whole-image comparison: 118 changed/missing structures;
  10532 differing/missing CRCs among 16676 exports.

Equal total structure size does not establish compatibility: field offsets and
bit positions also matter. Module version checks remain enabled. CRC values
were not forced to match. Current differences include shared key-management and
TTY type changes, which propagate through many exported interfaces.
The report deliberately retains failing results.

The built-source worktree is `/home/yucca/kernels/local-build/lts-merge-20261101/sm8750-updated`. The review worktree is
`/home/yucca/kernels/kernel_samsung_sm8750_lts` and omits build-time feature modifications. Compiled Image is
`/home/yucca/kernels/local-build/lts-merge-20261101/sm8750-updated/out/lkm/arch/arm64/boot/Image`; it is for analysis only. Feature-script
and documentation cleanup after compilation was checked independently; a fresh
release build is still required after the outstanding ABI repair.

## Remaining work before promotion

Resolve vendor-facing layouts, enum values, exported function/callback
signatures and symbol CRC changes without removing the upstream correctness
fixes. Recheck the exact vendor module set, then perform device boot, storage,
display, radio and suspend tests. Allmodconfig, other architectures, external
modules and actual device boot were not tested. No AnyKernel ZIP was produced,
no device was flashed and no branch was pushed.

## Recovery and reproduction

Original snapshot: `dc111cdbcea4de8c81955889a493f660891047d9` (`refs/codex/lts-merge-20261101/sm8750`).
The original worktree and unified normal build entry continue using the prior
maintenance branch. The full comparison artifacts and build logs are under
`/home/yucca/kernels/local-build/lts-merge-20261101`.

```sh
cd /home/yucca/kernels/kernel_samsung_sm8750_lts
./build.sh --check
./build.sh lkm --no-pack
```

Building this candidate does not imply that the ABI failure has been resolved.

## Vendor compatibility exception

Keep the existing Samsung NVMEM layout framework and its module ownership
model. The upstream device-bus NVMEM layout conversion is not transplanted into
this vendor tree: its expected internals and lifecycle differ. The original
vendor layout hooks and consumers remain intact. This exception must be
reviewed before claiming equivalent upstream security coverage.
