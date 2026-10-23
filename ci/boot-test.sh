#!/bin/bash
# Boot test of a built linux-luxos package in QEMU (no disk image needed).
#
#   ci/boot-test.sh linux-luxos-VERSION.pkg.tar.zst
#
# Builds a small initramfs (busybox + kmod + all modules of the package), boots the kernel and loads the
# drivers LuxOS needs on typical PCs (storage, USB, graphics, Wi-Fi, Bluetooth, sound, network, file
# systems). Fails when the kernel does not reach userspace or a driver does not load.
set -Eeuo pipefail
PKG=${1:?usage: boot-test.sh linux-luxos.pkg.tar.zst}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
MODULES=(
    # storage and USB
    nvme ahci sd_mod usb_storage uas xhci_pci ehci_pci sdhci_pci mmc_block virtio_blk
    # file systems
    ext4 btrfs xfs vfat exfat ntfs3 f2fs fuse isofs dm_crypt zram
    # graphics
    i915 xe amdgpu radeon nouveau virtio_gpu
    # network
    e1000e r8169 igc iwlwifi iwlmvm ath11k_pci ath10k_pci rtw88_8822ce rtw89_8852be mt7921e virtio_net wireguard
    # bluetooth, sound, input, camera
    btusb snd_hda_intel snd_sof_pci_intel_tgl snd_usb_audio hid_generic hid_multitouch i2c_hid_acpi uvcvideo
    # misc used by LuxOS
    tcp_bbr uinput loop
)

echo "Unpacking $PKG"
mkdir -p "$T/pkg"
bsdtar -xf "$PKG" -C "$T/pkg" 2>/dev/null || tar --zstd -xf "$PKG" -C "$T/pkg"
moddir=$(echo "$T"/pkg/usr/lib/modules/*/)
kver=$(basename "$moddir")
echo "Kernel $kver"

R=$T/root
mkdir -p "$R"/{bin,sbin,proc,sys,dev,tmp,etc,usr/lib/modules}
# same layout as Arch: /lib, /lib64 and /usr/lib64 lead to /usr/lib
ln -s usr/lib "$R/lib"
ln -s usr/lib "$R/lib64"
ln -s lib "$R/usr/lib64"
copy_bin() {   # program and its shared libraries
    local f=$1 lib
    install -Dm755 "$f" "$R$f"
    for lib in $(ldd "$f" 2>/dev/null | grep -oE '/[^ ]+' || true); do
        [[ -e $R$lib ]] || install -Dm755 "$lib" "$R$lib"
    done
}
copy_bin /usr/bin/busybox
copy_bin /usr/bin/kmod
ln -s /usr/bin/busybox "$R/bin/sh"
for n in modprobe insmod lsmod depmod; do ln -s /usr/bin/kmod "$R/sbin/$n"; done
cp -a "$moddir" "$R/usr/lib/modules/"
depmod -b "$R" "$kver"

cat > "$R/init" <<EOF
#!/bin/sh
/usr/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
echo "LUXOS-BOOT kernel \$(uname -r)"
fail=0
for m in ${MODULES[*]}; do
    if /sbin/modprobe "\$m" 2>/tmp/err; then echo "LUXOS-MOD-OK \$m"; else echo "LUXOS-MOD-FAIL \$m: \$(cat /tmp/err)"; fail=1; fi
done
echo "LUXOS-MODULES-LOADED \$(wc -l < /proc/modules)"
[ \$fail = 0 ] && echo LUXOS-BOOT-OK || echo LUXOS-BOOT-FAILED
poweroff -f
EOF
chmod 755 "$R/init"
(cd "$R" && find . | cpio -o -H newc --quiet | zstd -q -T0 -3 > "$T/initramfs.img")
echo "initramfs: $(du -h "$T/initramfs.img" | cut -f1)"

accel=(-accel tcg -cpu max)
[[ -r /dev/kvm && -w /dev/kvm ]] && accel=(-accel kvm -cpu host)
echo "QEMU: ${accel[*]}"
timeout 900 qemu-system-x86_64 "${accel[@]}" -m 3G -smp 2 -nographic -no-reboot \
    -kernel "$moddir/vmlinuz" -initrd "$T/initramfs.img" \
    -append "console=ttyS0 panic=-1 quiet loglevel=3" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 2>&1 | tee "$T/console.log" | grep -E 'LUXOS-' || true

grep -q "LUXOS-BOOT kernel $kver" "$T/console.log" || { echo "Kernel did not reach userspace" >&2; tail -40 "$T/console.log" >&2; exit 1; }
grep -q 'LUXOS-BOOT-OK' "$T/console.log" || { echo "Some drivers did not load" >&2; exit 1; }
echo "Boot test passed"
