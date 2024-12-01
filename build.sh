#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
    echo "You must be root to run this script."
    exit 1
fi

for e in $(env | sed "s/=.*//g"); do
    unset "$e" &>/dev/null
done

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
export LANG=C
export SHELL=/bin/bash
export TERM=linux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl mtools squashfs-tools grub-pc-bin grub-efi-amd64-bin \
    grub2-common xorriso debootstrap binutils ca-certificates --no-install-recommends

mkdir -p chroot

debootstrap --variant=minbase --no-check-gpg --arch=amd64 bookworm chroot http://deb.debian.org/debian
echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" > chroot/etc/apt/sources.list

echo -e "live\nlive\n" | chroot chroot passwd

echo "APT::Sandbox::User root;" > chroot/etc/apt/apt.conf.d/99sandboxroot
for dir in dev dev/pts proc sys; do mount --bind /$dir chroot/$dir; done

chroot chroot apt-get install -y gnupg network-manager live-config live-boot curl --no-install-recommends

curl -s 'https://liquorix.net/install-liquorix.sh' | chroot chroot bash

chroot chroot apt-get install -y task-gnome-desktop gnome-terminal gnome-tweaks

fallocate -l 8G chroot/swapfile
chmod 600 chroot/swapfile
mkswap chroot/swapfile
echo "/swapfile none swap sw 0 0" >> chroot/etc/fstab

chroot chroot update-initramfs -u -k all

rm -f chroot/etc/apt/apt.conf.d/01norecommend

chroot chroot apt-get clean
rm -rf chroot/var/lib/apt/lists/*
find chroot/var/log/ -type f -exec rm -f {} \;

mkdir -p iso/boot iso/live
cp -pf chroot/boot/vmlinuz-* iso/boot/vmlinuz
cp -pf chroot/boot/initrd.img-* iso/boot/initrd.img

for dir in dev dev/pts proc sys; do
    umount -lf chroot/$dir 2>/dev/null || true
done

mksquashfs chroot iso/live/filesystem.squashfs -comp xz -wildcards

mkdir -p iso/boot/grub/
cat > iso/boot/grub/grub.cfg << EOF
menuentry "Start GNOME Debian GNU/Linux with Liquorix Kernel (Debian 12)" {
    linux /boot/vmlinuz boot=live quiet
    initrd /boot/initrd.img
}
EOF

ISO_NAME="gnome-liquorix-debian12-$(date +%Y%m%d).iso"
grub-mkrescue iso -o "$ISO_NAME"

rm -rf chroot iso
echo "GNOME Liquorix Kernel Debian 12 ISO created: $ISO_NAME"