# luxos-kernel

The kernel of [LuxOS](https://lsl.lux-ai.cz/luxos/) (`linux-luxos`), built automatically.

- **Code:** <https://git.lux-ai.cz/LuxAI/luxos-kernel> – push changes here. The `main` branch is copied to
  GitHub (<https://github.com/luxopes/luxos-kernel>) within a minute, fast-forward only
  (`luxos-kernel-sync.timer` on the LuxOS server, write deploy key for that one repository); GitHub runs
  the CI and holds the releases. Do not push to GitHub directly: the copy would stop (no force push).

- **Source:** stable Linux from kernel.org, signature checked against Linus Torvalds' and
  Greg Kroah-Hartman's keys, plus the LuxOS patch set of the series in
  [`recipe/patches/<series>/`](recipe/patches) (applied in file name order, exactly, without fuzz).
- **Patches** ([`SOURCES`](recipe/patches/7.3/SOURCES) lists each one and where it comes from):
  - from [CachyOS](https://github.com/CachyOS/linux) (branches `7.3/cachy`, `7.3/sched`, `7.3/zram` and
    `kernel-patches`): BORE scheduler (used whenever scx_lavd is not running), CachyOS desktop tunables
    (`CONFIG_CACHY`: EEVDF slices for interactivity, lru-gen protects the working set on low memory, no
    proactive compaction / watermark boosting, bigger readahead, no swap-in readahead for zram), `-O3`,
    newer zram (separate read/write streams), EEVDF fixes, TSC fixes after sleep, Intel RST "RAID" mode
    NVMe drives (laptops shipped with Windows), evdev, AMD idle and colour management, a sysctl to turn off
    unprivileged user namespaces, Rust together with LTO;
  - own LuxOS patches (`luxos` in SOURCES): rebased versions where the CachyOS commit does not apply to
    the stable release, LLVM loop pipelining also at ThinLTO link time, DKMS modules (written for gcc)
    build without clang's unused-argument error.
  - Left out on purpose: PCIe ACS override (weakens IOMMU isolation), BBRv3 (renames `bbr`), ADIOS,
    Apple T2, out-of-tree modules.
- **New series** (e.g. 7.4): [`ci/pick-version.py`](ci/pick-version.py) takes a series only when
  `recipe/patches/<series>/` exists; until then the current series keeps getting point releases. To add
  one: take the same commits from CachyOS's `<series>/*` branches, rebase what does not apply, and check
  that every option in `config-luxos` still ends up in `.config` (the build checks it too).
- **Compiler:** clang with ThinLTO (`LLVM=1`, `CONFIG_LTO_CLANG_THIN`): the whole kernel is optimised
  across source files at link time, like CachyOS. DKMS builds out-of-tree modules (NVIDIA) with clang too,
  so `linux-luxos-headers` depends on clang, lld and llvm. Rust stays thanks to the CachyOS patch that
  allows Rust with LTO and BTF (BTF is needed by sched_ext); no x32 ABI with LLVM.
- **Configuration:** Arch Linux's kernel config as the base (every driver as a module, so any PC works
  out of the box) plus the LuxOS changes in [`recipe/config-luxos`](recipe/config-luxos). The build fails
  if a LuxOS option stops applying to a new kernel.
- **Which version:** [`ci/pick-version.py`](ci/pick-version.py) – as new as possible, but stable. A new
  stable series is taken from its `.3` point release on. Until then the current series keeps getting its
  newest point release, and there is never a downgrade to an older series. Mainline `-rc` kernels are
  never used.
- **Automation:** [`.github/workflows/kernel.yml`](.github/workflows/kernel.yml) checks kernel.org every
  6 hours. It builds in an Arch Linux container and boot-tests the result in QEMU, loading storage, USB,
  graphics, Wi-Fi, Bluetooth, sound and file system drivers. It then publishes a release with the packages,
  `SHA256SUMS`, the final `.config`, `build-info.txt` and a build provenance attestation. A failed build
  opens an issue.
- **Distribution:** the LuxOS repository server verifies each release's attestation and checksums, signs
  the packages with the LuxOS key and publishes them. LuxOS keeps a fallback kernel installed.

Packages: `linux-luxos` (kernel and modules) and `linux-luxos-headers` (for DKMS drivers such as NVIDIA).
Raise `recipe/pkgrel` whenever the recipe changes.
