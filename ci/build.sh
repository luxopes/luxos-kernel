#!/bin/bash
# Build linux-luxos inside an archlinux:base-devel container (run by .github/workflows/kernel.yml).
#
#   ci/build.sh VERSION        repository mounted at /work, scratch space at /build, output in /work/out
#
# 1. installs the build dependencies, 2. fetches Arch Linux's current kernel config (recorded in
# out/build-info.txt), 3. builds the packages with makepkg (kernel.org signature checked),
# 4. boots the result in QEMU (ci/boot-test.sh).
set -Eeuo pipefail
VERSION=${1:?usage: build.sh VERSION}
WORK=/work
BUILD=/build
OUT=$WORK/out
ARCH_CONFIG_URL=https://gitlab.archlinux.org/archlinux/packaging/packages/linux/-/raw/main/config.x86_64
ARCH_REPO_API=https://gitlab.archlinux.org/api/v4/projects/archlinux%2Fpackaging%2Fpackages%2Flinux/repository/commits/main

step() { printf '\n==> %s\n' "$*"; }

step "Build dependencies"
pacman -Syu --noconfirm --needed bc cpio gettext libelf pahole perl python rust rust-bindgen rust-src \
    tar xxhash xz zlib zstd git curl gnupg file qemu-base busybox kmod >/dev/null
useradd -m builder 2>/dev/null || true
mkdir -p "$BUILD" "$OUT"
chown builder: "$BUILD"
install -d -o builder "$BUILD/pkg"

step "Recipe and Arch Linux base config"
rm -rf "$BUILD/linux-luxos"
cp -r "$WORK/recipe" "$BUILD/linux-luxos"
curl -fsSL --retry 3 "$ARCH_CONFIG_URL" -o "$BUILD/linux-luxos/config.arch"
arch_commit=$(curl -fsSL --retry 3 "$ARCH_REPO_API" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' || echo unknown)
grep -q '^CONFIG_X86_64=y' "$BUILD/linux-luxos/config.arch" || { echo "Arch config looks wrong" >&2; exit 1; }
chown -R builder: "$BUILD/linux-luxos"

step "kernel.org signing keys (Linus Torvalds, Greg Kroah-Hartman)"
# makepkg checks the fingerprints against validpgpkeys in the PKGBUILD
sudo -u builder gpg --batch --quiet --auto-key-locate clear,wkd --locate-keys \
    torvalds@kernel.org gregkh@kernel.org

step "Building linux-luxos $VERSION"
nproc
df -h "$BUILD"
cd "$BUILD/linux-luxos"
start=$(date +%s)
set +e
sudo -u builder env LUXOS_KVER="$VERSION" MAKEFLAGS="-j$(nproc)" PKGDEST="$BUILD/pkg" \
    makepkg --noconfirm --nodeps --cleanbuild 2>&1 | tee "$OUT/build.log" | grep --line-buffered -E '^(==>|  ->)'
rc=${PIPESTATUS[0]}
set -e
((rc == 0)) || { echo "makepkg failed ($rc)" >&2; tail -80 "$OUT/build.log" >&2; exit 1; }
end=$(date +%s)
cp "$BUILD"/pkg/*.pkg.tar.zst "$OUT/"
cp "$BUILD/linux-luxos/src/linux-$VERSION/.config" "$OUT/config"
df -h "$BUILD"

step "Boot test"
bash "$WORK/ci/boot-test.sh" "$OUT"/linux-luxos-[0-9]*.pkg.tar.zst

cd "$OUT"
sha256sum ./*.pkg.tar.zst config > SHA256SUMS
{
    echo "kernel:          $VERSION (https://cdn.kernel.org, signature verified by makepkg)"
    echo "recipe pkgrel:   $(cat "$WORK/recipe/pkgrel")"
    echo "recipe commit:   ${GITHUB_SHA:-local}"
    echo "arch config:     $ARCH_CONFIG_URL"
    echo "arch commit:     $arch_commit"
    echo "build time:      $(( (end - start) / 60 )) min on $(nproc) CPUs"
    echo "compiler:        $(gcc --version | head -1)"
    echo "rust:            $(rustc --version)"
} > build-info.txt
cat build-info.txt
