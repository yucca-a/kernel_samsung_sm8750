<a id="中文"></a>

**简体中文** · [English ↓](#english)

# kernel_samsung_sm8750

> 面向骁龙 8 Elite（SM8750）三星 Galaxy S25 的自定义 Android GKI 内核，基于 Google ACK 真实合并基线。

![SoC](https://img.shields.io/badge/SoC-Snapdragon_8_Elite-0a7bbb)
![Android](https://img.shields.io/badge/Android-15-3ddc84)
![Kernel](https://img.shields.io/badge/Linux-6.6.138-f6a500)
![KMI](https://img.shields.io/badge/KMI-android15--8-9aa0a6)
![Base](https://img.shields.io/badge/Base-Google_ACK-4285f4)
![Root](https://img.shields.io/badge/Root-ReSukiSU%20%2B%20SUSFS%20%2B%20ZeroMount-c2185b)
![License](https://img.shields.io/badge/License-GPL--2.0-2962ff)

面向 **Galaxy S25**（以及 S25 Edge）的自定义内核，基于 **Google ACK `android15-6.6`**、叠加三星 vendor 源，并前向合并至最新 6.6.x LTS，搭载 Android 15（KMI generation 8）。

> **定位**：本树主要面向 **Samsung 设备**，也只在 Samsung 机型上测试与发布。因为合并了上游 LTS，它理论上也能跑在同 SoC 的其他设备上，但这一点不作保证。

本树是 **ACK-rebased** 的：通过为三星 vendor 包重建一个真实的 Google ACK 合并基线、再把 `android15-6.6` LTS `git merge` 进去得到（基线是真正的合并结果，而非重新 diff 的 tarball）。每个新的 LTS（6.6.139、6.6.140…）都在独立的 ACK 工作区里继续前向合并、再导出到这里。

构建是 **mode-driven** 的：git 树是干净基线，**不**提交任何 KSU / SUSFS / ZeroMount / Wild 补丁；`build/build.sh` 在编译期抓取并应用它们，同一份基线既能产出内置 root 版、也能产出纯净版，并保持对 ACK 的可持续前向合并。

---

## ✨ 特性亮点

> 三仓（sm8550 / sm8650 / sm8750）共享同一套特性集，下面这些是开箱即得的核心能力。

- 🔓 **内置 Root** — ReSukiSU（KernelSU）直接编译进内核（`resukisu` 模式），刷完即 root；另有 `lkm` 纯净模式，root 留到刷入时再注入。
- 🫥 **SUSFS 隐藏** — 把 root、挂载、路径从各类检测中隐藏起来。
- 🧭 **ZeroMount** — 配合 SUSFS 进一步收敛挂载检测面。
- 📡 **Baseband-guard** — LSM 级保护 modem / vbmeta / dtbo，任何 root 用户都改不动。
- 🔔 **Re:Kernel** — 内置，提供前后台 / 网络事件通知，便于省电与后台管控。
- ⚡ **Wild 全套性能补丁** — F2FS/ext4 调优、内存与调度优化、唤醒/功耗优化、日志降噪一整套。
- 🎮 **NTSync** — Windows NT 风格同步原语，跑 Wine / Proton 游戏更顺。
- 📦 **Droidspaces 容器** — SYSVIPC / 命名空间 / netfilter 开关，可在 Android 里跑 Linux 容器、chroot。
- 💾 **NTFS3 读写** — OTG 上的 NTFS 盘可读写（含 LZX/XPRESS 压缩）。
- 🗜️ **zram lz4 + BBR** — zram 默认换 lz4，TCP 默认 FQ + BBR。
- 📁 **完整 tmpfs** — POSIX ACL / XATTR / INODE64 全开。
- 🕸️ **完整 ipset** — 内置整套 IP set（bitmap/hash/list）。
- 🕵️ **IPv6 NAT 隐藏** — 构建期抹掉 `/proc/config.gz` 里的痕迹，绕过基于配置的 root 检测。
- 🛡️ **三星安全栈禁用** — 关闭 UH / RKP / KDP / DEFEX / INTEGRITY / FIVE 等反 root 机制。
- 🚀 **ccache 加速** — 增量编译提速约 60–80%。

### 🔱 SM8750 独有

- 🧬 **ACK-rebased 基线** — 真实的 ACK↔三星 `git merge` 基线（而非重新 diff 的快照），LTS 前向合并干净、可持续。
- 🗄️ **FUSE passthrough 修复** — `fs/fuse/inode.c` 用的是**三星版**（FUSE passthrough / `backing_inode`），不是 ACK 版。LTS 合并最初取了 ACK 的 `inode.c`，没有初始化三星 `fuse_i.h` / `dir.c` / `file.c` 依赖的 passthrough 机制，导致 `/storage/emulated/0` FUSE 挂载异常：内部存储显示 **0 字节**、截图/下载保存失败。源自同一 vendor 包、但没打这个修复的树很可能都受影响。

---

## 📱 支持设备

面向 **Galaxy S25 系列**（骁龙 8 Elite / SM8750）。GKI 内核镜像与具体机型无关，实际覆盖范围由 AnyKernel3 的 `device.name` 列表决定。

| 设备 | 说明 |
|---|---|
| Galaxy S25 系列 | SM8750 通用 GKI 镜像 |
| Galaxy S25 Edge | `psq`（SM-S9370）—— 打包时显式加入设备名 |

---

## 🌿 分支与模式

| 模式 | 说明 |
|---|---|
| `resukisu`（默认） | 内置 ReSukiSU + SUSFS + ZeroMount + 全套特性。 |
| `lkm` | 纯净内核，不含 KSU/SUSFS/ZeroMount；root 在刷入时由管理器给 `init_boot` 打补丁注入。 |

> `lkm` 模式产出的 `Image` 是真正干净的（零 `ksu_` 字符串）；KernelSU 管理器在刷入时打补丁，运行时用 kprobes/kallsyms 注入未改动的 vmlinux。

---

## 🧩 完整特性一览

| 特性 | resukisu | lkm | 来源 |
|---|:---:|:---:|---|
| ReSukiSU（KernelSU） | 内置 | 刷入时注入 | [ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) |
| SUSFS | ✅ | ❌¹ | [ShirkNeko/susfs4ksu](https://github.com/ShirkNeko/susfs4ksu)（`gki-android15-6.6`） |
| ZeroMount | ✅ | ❌¹ | [Enginex0/Super-Builders](https://github.com/Enginex0/Super-Builders)（`android15-6.6/ReSukiSU`） |
| Baseband-guard | ✅ | ✅ | [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) |
| Re:Kernel | ✅ | ✅ | 内置 `build/features/rekernel` |
| Wild 性能补丁 | ✅ | ✅ | [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) |
| NTSync（Wine/Proton） | ✅ | ✅ | Linux mainline ² |
| Droidspaces（容器） | ✅ | ✅ | mainline 配置 + KABI 补丁 ² |
| Unicode 绕过修复 | ✅ | ✅ | WildKernels |
| NTFS3（+LZX/XPRESS） | ✅ | ✅ | mainline |
| zram 默认 lz4 | ✅ | ✅ | config |
| FQ + BBR | ✅ | ✅ | config |
| 完整 tmpfs（ACL/XATTR/INODE64） | ✅ | ✅ | config |
| 完整 ipset | ✅ | ✅ | config |
| IPv6 NAT 隐藏 | ✅ | ✅ | 内置 `config_data` 钩子 |
| 三星安全栈禁用 | ✅ | ✅ | 构建期 `scripts/config` 覆盖 |

¹ `lkm` 模式关闭 SUSFS：`fs/susfs.c` 引用了仅在 `CONFIG_KSU=y` 时才链接的 `ksu_*` 符号。
² 标 mainline/upstream 的特性源自 Linux 上游，并非 Wild 首创；构建时我们从 [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) 取**已适配到本 GKI 版本**的 backport，省去自行回合的工作。真正属于 Wild 的是上面「Wild 性能补丁」那一行（其自有的性能/降噪调优集）。

---

## 🚀 编译

```bash
# resukisu（默认）：内置 ReSukiSU + SUSFS + ZeroMount + 全套特性
build/build.sh
build/build.sh resukisu

# lkm：纯净内核（KSU 刷入时注入）
build/build.sh lkm

# 额外打包 AnyKernel3 zip
PACK=1 build/build.sh
```

前置：

- 三星 `clang-r510928` prebuilts。`TOOLCHAIN_DIR` 默认指向 `../toolchain_samsung_sm8750/kernel_platform/prebuilts`。
- 首次编译需联网（抓取下方钉住的特性源）。
- ccache 存在时自动启用。

产物：

```
out/arch/arm64/boot/Image                 # 当前模式产出的内核镜像
../SM8750_<tag>_<版本>_<MMDD>.zip          # PACK=1 时
```

Release tag 形如 `sm8750-resukisu-d4985ff`；zip 产物仍保持
`SM8750_resukisu_6.6.138_0614.zip` 这类命名。内核版本号形如
`6.6.138-android15-8-YuccaA-d4985ff-4k`，其中 `d4985ff` 是源码短 commit。

---

## ⚙️ 构建开关（环境变量）

构建是 mode-driven 的：特性默认全开，只有 `resukisu` / `lkm` 这一个参数决定 KSU / SUSFS / ZeroMount 是否编入。

| 变量 | 默认 | 作用 |
|---|---|---|
| `TOOLCHAIN_DIR` | `../toolchain_samsung_sm8750/kernel_platform/prebuilts` | clang-r510928 prebuilts 目录 |
| `JOBS` | `nproc` | 并行编译任务数 |
| `PACK` | `0` | 设 `1` 打包 AnyKernel3 zip（需 `ANYKERNEL_DIR`） |
| `ANYKERNEL_DIR` | `../AnyKernel3_s25` | AnyKernel3 模板目录 |
| `BUILD_ID` | 当前源码短 commit | 固定版本号里的构建代号（`BUILD_NUM` 是兼容旧 CI 的别名） |
| `SUSFS_PIN` | 见脚本 | 覆盖 susfs4ksu 的 commit |
| `SUPER_BUILDERS_PIN` | 见脚本 | 覆盖 Super-Builders 的 ZeroMount patch commit |
| `WILD_PIN` | `5a5d5d8` | 覆盖 WildKernels/kernel_patches 的 commit |
| `CCACHE_DIR` / `CCACHE_MAXSIZE` | `.ccache` / `2G` | ccache 缓存目录与上限 |

---

## 🔐 安全与硬化

- `build/build.sh` 会**禁用**三星安全栈（UH / RKP / KDP / DEFEX / INTEGRITY / FIVE）以及 `TRIM_UNUSED_KSYMS`，否则它们会对抗内核级 root 或挡住模块导出符号。当前两个模式都会应用这组构建期覆盖。
- SUSFS / Unicode 修复 / IPv6 NAT 隐藏共同压制常见的 root 检测面。

---

## 📦 刷入

从 S25 的 Recovery（TWRP/OrangeFox）刷入 zip；或用 magiskboot 把裸 `Image` 塞进 stock `boot.img`。DTB/dtbo 取自设备现有分区，本树不重新生成。

---

## 📜 血统与许可

GPL-2.0。本树派生自：

- **Google ACK** `android15-6.6`（`android.googlesource.com/kernel/common`）。
- **三星** 为 Galaxy S25（SM8750）发布的开源内核 —— 全部三星驱动/HAL 版权归三星所有，GPL-2.0。
- **ReSukiSU / KernelSU**、**SUSFS**（ShirkNeko）、**ZeroMount**（Super-Builders）、**WildKernels** 补丁集、**Baseband-guard**（vc-teahouse）、**Re:Kernel** —— 各自遵循其许可。

本仓库自身的贡献是 ACK↔三星合并基线的重建、LTS 前向合并的冲突解决、FUSE 修复以及 mode-driven 构建系统。原始的 ACK "submitting patches" 指南保留为 [`README.ACK.md`](README.ACK.md)。

---
---

<a id="english"></a>

[简体中文 ↑](#中文) · **English**

# kernel_samsung_sm8750

> Custom Android GKI kernel for the Snapdragon 8 Elite (SM8750) Galaxy S25, on a real Google ACK merge base.

A custom kernel for **Galaxy S25** (and S25 Edge), built on **Google ACK `android15-6.6`** with Samsung's vendor sources layered on top and merged forward to the latest 6.6.x LTS — Android 15, KMI generation 8.

> **Scope:** primarily for **Samsung devices**, and tested/released on Samsung models only. Because it merges upstream LTS it can in principle run on other same-SoC devices too, but that is not guaranteed.

This tree is **ACK-rebased**: it was produced by reconstructing a real Google ACK merge-base for the Samsung vendor drop and `git merge`-ing `android15-6.6` LTS into it (so the base is a true merge result, not a re-diffed tarball). Each new LTS (6.6.139, 6.6.140, …) is merged forward in a separate ACK workbench and re-exported here.

The build is **mode-driven**: the git tree is a clean base with **no** KSU / SUSFS / ZeroMount / Wild patches committed; `build/build.sh` fetches and applies them at build time, so one base produces either variant and stays easy to forward-merge against ACK.

## ✨ Highlights

> All three trees (sm8550 / sm8650 / sm8750) share one feature set — available out of the box.

- 🔓 **Built-in root** — ReSukiSU (KernelSU) compiled in (`resukisu`); or a clean `lkm` mode where root is injected at flash time.
- 🫥 **SUSFS hiding** · 🧭 **ZeroMount** · 📡 **Baseband-guard** · 🔔 **Re:Kernel**
- ⚡ **Full Wild performance patch set** — F2FS/ext4 tuning, mm & scheduler tweaks, wakeup/power optimizations, logspam silencing.
- 🎮 **NTSync** (Wine/Proton) · 📦 **Droidspaces** (Linux containers) · 💾 **NTFS3** (+LZX/XPRESS)
- 🗜️ **zram lz4 + FQ/BBR** · 📁 **Full tmpfs** (ACL/XATTR/INODE64) · 🕸️ **Full ipset suite**
- 🕵️ **IPv6 NAT hidden** from `/proc/config.gz` · 🛡️ **Samsung security stack disabled** · 🚀 **ccache**

**SM8750-only:** **ACK-rebased** clean merge base for sustainable LTS forward-merges; **FUSE passthrough fix** — `fs/fuse/inode.c` is the **Samsung** version (passthrough / `backing_inode`), not the ACK one. Taking ACK's `inode.c` broke the `/storage/emulated/0` FUSE mount (internal storage reported **0 bytes**; screenshots/downloads failed to save). Snapshots from the same vendor drop without this fix are likely affected.

## 📱 Supported devices

Targets the **Galaxy S25 series** (Snapdragon 8 Elite / SM8750). A GKI image is device-agnostic; actual coverage is set by the AnyKernel3 `device.name` list.

| Device | Notes |
|---|---|
| Galaxy S25 series | generic SM8750 GKI image |
| Galaxy S25 Edge | `psq` (SM-S9370) — added to device names at packaging |

## 🌿 Modes

- `resukisu` (default): built-in ReSukiSU + SUSFS + ZeroMount + full set.
- `lkm`: pure kernel (no KSU/SUSFS/ZeroMount); root injected at flash time via the manager patching `init_boot`. The `Image` is genuinely vanilla (zero `ksu_` strings).

## 🧩 Feature matrix

| Feature | resukisu | lkm | Source |
|---|:---:|:---:|---|
| ReSukiSU (KernelSU) | built-in | flash-time | ReSukiSU/ReSukiSU |
| SUSFS | ✅ | ❌¹ | ShirkNeko/susfs4ksu (`gki-android15-6.6`) |
| ZeroMount | ✅ | ❌¹ | Enginex0/Super-Builders (`android15-6.6/ReSukiSU`) |
| Baseband-guard | ✅ | ✅ | vc-teahouse/Baseband-guard |
| Re:Kernel | ✅ | ✅ | vendored `build/features/rekernel` |
| Wild perf patches | ✅ | ✅ | WildKernels/kernel_patches |
| NTSync | ✅ | ✅ | Linux mainline ² |
| Droidspaces | ✅ | ✅ | mainline configs + KABI shim ² |
| Unicode bypass fix | ✅ | ✅ | WildKernels |
| NTFS3 (+LZX/XPRESS) | ✅ | ✅ | mainline |
| zram default lz4 / FQ+BBR | ✅ | ✅ | config |
| Full tmpfs (ACL/XATTR/INODE64) | ✅ | ✅ | config |
| Full ipset suite | ✅ | ✅ | config |
| IPv6 NAT hidden | ✅ | ✅ | in-tree `config_data` hook |
| Samsung security stack disabled | ✅ | ✅ | `scripts/config` overrides |

¹ SUSFS is off in `lkm`: `fs/susfs.c` references `ksu_*` symbols that only link with `CONFIG_KSU=y`.
² Features marked mainline/upstream originate in upstream Linux, not Wild. At build time we fetch versions **already backported to this GKI tree** from [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) to avoid re-doing the backport. What is genuinely Wild's is the "Wild perf patches" row (their curated performance/logspam set).

## 🚀 Build

```bash
build/build.sh            # resukisu (default)
build/build.sh lkm        # pure kernel
PACK=1 build/build.sh     # also pack an AnyKernel3 zip
```

Output: `out/arch/arm64/boot/Image` from the selected mode and, with `PACK=1`, `../SM8750_<tag>_<ver>_<MMDD>.zip`. Release tag example: `sm8750-resukisu-d4985ff`. Kernel release string example: `6.6.138-android15-8-YuccaA-d4985ff-4k`. Requires the Samsung `clang-r510928` prebuilts (`TOOLCHAIN_DIR` defaults to `../toolchain_samsung_sm8750/kernel_platform/prebuilts`) and network on first build; ccache is used automatically when present.

## ⚙️ Build switches

Mode-driven — features are all on; the single `resukisu`/`lkm` arg gates KSU/SUSFS/ZeroMount. Env: `TOOLCHAIN_DIR`, `JOBS`, `PACK`, `ANYKERNEL_DIR`, `BUILD_ID`, `SUSFS_PIN`, `SUPER_BUILDERS_PIN`, `WILD_PIN`, `CCACHE_DIR`, `CCACHE_MAXSIZE`.

## 🔐 Security & hardening

`build/build.sh` disables Samsung's security stack (UH / RKP / KDP / DEFEX / INTEGRITY / FIVE) plus `TRIM_UNUSED_KSYMS` in both modes. SUSFS / Unicode fix / IPv6-NAT hiding reduce the common root-detection surface.

## 📦 Flashing

Flash the zip from an S25 recovery (TWRP/OrangeFox), or drop the raw `Image` into your stock `boot.img` with magiskboot. DTB/dtbo come from existing partitions.

## 📜 Lineage & license

GPL-2.0, derived from **Google ACK** `android15-6.6`, Samsung's open-source Galaxy S25 (SM8750) kernel, plus ReSukiSU/KernelSU, SUSFS (ShirkNeko), ZeroMount (Super-Builders), WildKernels, Baseband-guard (vc-teahouse) and Re:Kernel — each under its own license. This repo's own contribution is the ACK↔Samsung merge-base reconstruction, the LTS forward-merge conflict resolution, the FUSE fix, and the mode-driven build system. The original ACK "submitting patches" guide is preserved as [`README.ACK.md`](README.ACK.md).
