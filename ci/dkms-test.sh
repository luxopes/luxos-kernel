#!/bin/bash
# Build the NVIDIA DKMS drivers that LuxOS ships against the new linux-luxos-headers (run by ci/build.sh
# after the boot test). The kernel is built with clang, so DKMS builds the modules with LLVM=1 as on a
# LuxOS computer.
#
#   ci/dkms-test.sh HEADERS_PACKAGE RESULTS_FILE
#
# - nvidia-open-dkms (Arch Linux [extra]) and nvidia-580xx (LuxOS [luxos]): a failure stops the release.
# - nvidia-470xx (LuxOS [luxos], optional, community-patched): a failure is only reported.
# The 580xx and 470xx sources come from the LuxOS-Arch repository (packages/nvidia-*-utils, the same
# recipes the [luxos] repository is built from); makepkg checks their checksums and applies their patches.
# Packages are unpacked without pacman hooks so that only the builds below run.
set -Eeuo pipefail
HEADERS=${1:?usage: dkms-test.sh HEADERS_PACKAGE RESULTS_FILE}
RESULTS=${2:?usage: dkms-test.sh HEADERS_PACKAGE RESULTS_FILE}
LUXOS_REPO=https://github.com/luxopes/LuxOS-Arch.git
SCRATCH=/build/dkms
step() { printf '\n==> %s\n' "$*"; }
unpack() { bsdtar -xpf "$1" -C / --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL; }

step "DKMS and kernel headers"
pacman -S --noconfirm --needed dkms libarchive >/dev/null
unpack "$HEADERS"
kver=$(ls /usr/lib/modules | head -1)
[[ -e /usr/lib/modules/$kver/build/Makefile ]] || { echo "no headers in /usr/lib/modules/$kver" >&2; exit 1; }
grep -q '^CONFIG_CC_IS_CLANG=y' "/usr/lib/modules/$kver/build/.config"
echo "kernel $kver (clang)"
rm -rf "$SCRATCH" && install -d -o builder "$SCRATCH"

step "Driver sources"
# nvidia-open-dkms: the package from [extra], unpacked
pacman -Sw --noconfirm --cachedir "$SCRATCH" nvidia-open-dkms >/dev/null
pkg=$(ls "$SCRATCH"/nvidia-open-dkms-*.pkg.tar.zst | head -1)
unpack "$pkg"
open_ver=$(bsdtar -xOf "$pkg" .PKGINFO | awk '$1 == "pkgver" {sub(/-.*/, "", $3); print $3}')
drivers=("nvidia-open $open_ver 1")
# 580xx and 470xx: the module sources after prepare() of the LuxOS recipes
sudo -u builder git clone -q --depth 1 --filter=blob:none --sparse "$LUXOS_REPO" "$SCRATCH/luxos"
sudo -u builder git -C "$SCRATCH/luxos" sparse-checkout set packages/nvidia-580xx-utils packages/nvidia-470xx-utils
echo "LuxOS-Arch $(git -C "$SCRATCH/luxos" rev-parse --short HEAD)"
for branch in 580xx 470xx; do
    dir=$SCRATCH/luxos/packages/nvidia-$branch-utils
    (cd "$dir" && sudo -u builder makepkg --nobuild --nodeps --noconfirm >"$SCRATCH/prepare-$branch.log" 2>&1) || {
        tail -40 "$SCRATCH/prepare-$branch.log" >&2; echo "prepare of nvidia-$branch failed" >&2; exit 1; }
    ver=$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD")
    rm -rf "/usr/src/nvidia-$ver"
    cp -r "$dir/src/NVIDIA-Linux-x86_64-$ver/kernel" "/usr/src/nvidia-$ver"
    drivers+=("nvidia-$branch $ver $([[ $branch == 470xx ]] && echo 0 || echo 1)")
done

step "Building the modules for $kver"
failed_required=0
: > "$RESULTS"
for d in "${drivers[@]}"; do
    read -r name ver required <<<"$d"
    [[ -e /usr/src/nvidia-$ver/dkms.conf ]] || { echo "no dkms.conf for $name $ver" >&2; exit 1; }
    start=$(date +%s)
    dkms add -m nvidia -v "$ver" >/dev/null 2>&1 || true
    if dkms build -m nvidia -v "$ver" -k "$kver" >"$SCRATCH/dkms-$ver.log" 2>&1; then
        result=ok
    else
        result=FAILED
        log=$(ls /var/lib/dkms/nvidia/"$ver"/build/make.log 2>/dev/null || true)
        echo "--- $name $ver failed:" >&2
        grep -E 'error|Error' "${log:-$SCRATCH/dkms-$ver.log}" | head -30 >&2 || tail -40 "$SCRATCH/dkms-$ver.log" >&2
        ((required)) && failed_required=1
    fi
    printf '%-13s %-12s %s (%d s)%s\n' "$name" "$ver" "$result" $(( $(date +%s) - start )) \
        "$( ((required)) || echo ', optional')" | tee -a "$RESULTS"
done
((failed_required == 0)) || { echo "a required NVIDIA driver does not build against $kver" >&2; exit 1; }
