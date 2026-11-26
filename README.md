# luxos-kernel

The kernel of [LuxOS](https://lsl.lux-ai.cz/luxos/) (`linux-luxos`), built automatically.

- **Code:** <https://git.lux-ai.cz/LuxAI/luxos-kernel> – push changes here. The `main` branch is copied to
  GitHub (<https://github.com/luxopes/luxos-kernel>) within a minute, fast-forward only
  (`luxos-kernel-sync.timer` on the LuxOS server, write deploy key for that one repository); GitHub runs
  the CI and holds the releases. Do not push to GitHub directly: the copy would stop (no force push).

- **Source:** vanilla stable Linux from kernel.org, signature checked against Linus Torvalds' and
  Greg Kroah-Hartman's keys. No out-of-tree patches, so every new release builds unattended.
- **Compiler:** clang with ThinLTO (`LLVM=1`, `CONFIG_LTO_CLANG_THIN`): the whole kernel is optimised
  across source files at link time, like CachyOS. DKMS builds out-of-tree modules (NVIDIA) with clang too,
  so `linux-luxos-headers` depends on clang, lld and llvm. Cost: no Rust in the kernel (Linux 7.3 does
  not allow Rust together with LTO and BTF; BTF is needed by sched_ext), so no Rust Binder (Waydroid) and
  no QR code on the panic screen.
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
