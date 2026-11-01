# SM8750 Linux 6.6.161 LTS integration (2026-11-01)

Status: **local build and scoped vendor ABI validation passed**.
Merged locally into `codex/build-reliability-netlink-permissions`; published maintenance branch: `main`.
The integration branch is `codex/lts-6.6.161-candidate`. LKM-only maintenance
and the pre-existing local feature/build changes are preserved.

## Source and compatibility

Applied kernel.org incremental patches from 6.6.156 to 6.6.161 using three-way
merges against pristine upstream files. SHA-256 checksums were verified;
OpenPGP signatures were not verified. Exact source URLs and hashes are in
`Documentation/lts-sources-20261101.json`.

Core-owned state uses private allocations or Android KABI reserve slots.
Legacy exports and callback signatures use typed adapters where necessary.
Symbol CRCs are generated normally; module version checks stay enabled.
Implementation details and encoding/lifetime limits are in
`build/LTS_ABI_20261101.txt`.

The upstream NVMEM device-bus layout conversion is deferred. The baseline Samsung NVMEM framework, layout hooks and module-ownership model remain. This is an explicit exception to vanilla Linux 6.6.161.

This Samsung/Android tree is not byte-identical to vanilla Linux, and these
results do not establish complete upstream CVE coverage.

## Validation results

- Independent fresh worktree, production arm64 defconfig and configured Samsung
  toolchain, `./build.sh lkm`, `PACK=0 ZIP_AFTER=0 USE_CCACHE=0`: **passed**.
- Pre-update local snapshot rebuilt with the corresponding LKM configuration.
- Union of available Android/Galaxy/QCOM symbol lists, restricted to exports
  present in that baseline: **0 differing/missing CRCs of 2730 symbols**.
- Explicit `build/vendor_abi_types.txt` profile: **0 layout changes across
  81 types** (size, old member offsets and bitfield widths).
- Two feature-preparation runs after the successful build: both passed and
  neither changed the built source fingerprint.
- Root-source guard, shell syntax and `git diff --check`: passed.
- Complete-image inventory still contains 69 changed/missing types
  and 188 differing/missing CRCs of 16676 exports outside the
  selected symbol gate. These are recorded, not hidden or treated as a global
  ABI guarantee. Internal types can change independently of the KMI profile.

The checker does not prove every C member type or runtime behavior. Actual
vendor-module binaries, device boot, storage/display/radio, suspend/resume,
other architectures and allmodconfig were not tested. No AnyKernel package
was produced and no phone was flashed. Compiler/configuration warnings remain
in the complete logs; the build is successful, not claimed warning-free.

## Reproduction and retained evidence

Baseline snapshot: `9e6032096c03ff85aba2990e0f62aabfb2f1654c`
(`refs/codex/lts-merge-20261101/sm8750`), including earlier local LKM work.
Validated source snapshot: `957d8f91befdc991702876433a57ffc250d4bf0d`;
source tree: `3fec0bf37701b1a96e94146db29d52d8a98d54b6`. That ABI validation predates the README/release metadata update. Release builds are independently rebuilt from the published source commit; see the Release build/ABI manifests.

Artifacts and logs: `/home/yucca/kernels/local-build/lts-merge-20261101`.
Final build: `sm8750-final-build.json` and `sm8750-final-build.log`.
ABI gate: `sm8750-final-vendor-validation.json` (commands and artifact hashes).
Feature stability: `sm8750-final-features.json`.
Whole-image inventory: `sm8750-final-abi-inventory.json`.
Image: `/home/yucca/kernels/local-build/lts-merge-20261101/sm8750-final/out/lkm/arch/arm64/boot/Image`.
The Image's generated version suffix identifies the validated source snapshot.

```sh
./build.sh --check
MODE=lkm PACK=0 ZIP_AFTER=0 USE_CCACHE=0 ./build.sh lkm
symbols=()
for f in android/abi_gki_aarch64 android/abi_gki_aarch64_galaxy \
         android/abi_gki_aarch64_galaxy_grey \
         android/abi_gki_aarch64_galaxy_presubmit android/abi_gki_aarch64_qcom; do
    [ ! -f "$f" ] || symbols+=("$f")
done
python3 build/check_vendor_abi.py BASELINE_OUT CURRENT_OUT \
  --types-file build/vendor_abi_types.txt --symbols "${symbols[@]}"
```

Reproduction requires the same feature-cache revisions and toolchain as the
retained final worktree. The feature-prepared build worktree is separate from
the clean source committed to the maintenance branch.

## Publication identity

The three unpublished integration commits were re-attributed to `yucca-a`
using the account-linked GitHub noreply address before publication. Their
source trees are unchanged. Original validation snapshot IDs remain local
evidence; the baseline commit above is the corresponding published tree.
