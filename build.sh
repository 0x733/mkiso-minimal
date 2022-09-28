#!/bin/bash
set -e
#### Check root
if [[ ! $UID -eq 0 ]] ; then
    echo -e "\033[31;1mYou must be root!\033[:0m"
    exit 1
fi
#### Remove all environmental variable
for e in $(env | sed "s/=.*//g") ; do
    unset "$e" &>/dev/null
done

#### Set environmental variables
export PATH=/bin:/usr/bin:/sbin:/usr/sbin
export LANG=C
export SHELL=/bin/bash
export TERM=linux
export DEBIAN_FRONTEND=noninteractive

#### Install dependencies
if which apt &>/dev/null && [[ -d /var/lib/dpkg && -d /etc/apt ]] ; then
    apt-get update
    apt-get install curl mtools squashfs-tools grub-pc-bin grub-efi xorriso debootstrap binutils -y
fi

set -ex
#### Chroot create
mkdir chroot || true

#### For devuan
debootstrap --variant=minbase --no-check-gpg --no-merged-usr --exclude=usrmerge --arch=amd64 testing chroot https://pkgmaster.devuan.org/merged
echo "deb https://pkgmaster.devuan.org/merged testing main contrib non-free" > chroot/etc/apt/sources.list

#### Set root password
pass="live"
echo -e "$pass\n$pass\n" | chroot chroot passwd

#### Fix apt & bind
# apt sandbox user root
echo "APT::Sandbox::User root;" > chroot/etc/apt/apt.conf.d/99sandboxroot
for i in dev dev/pts proc sys; do mount -o bind /$i chroot/$i; done
chroot chroot apt-get install gnupg --no-install-recommends  -y

##### Devuan only
chroot chroot apt-get install devuan-keyring --no-install-recommends -y

#### Debjaro repository (optional)
echo "deb https://debjaro.github.io/repo/stable stable main" > chroot/etc/apt/sources.list.d/debjaro.list
curl https://debjaro.github.io/repo/stable/dists/stable/Release.key | chroot chroot apt-key add -
chroot chroot apt-get update -y
chroot chroot apt-get full-upgrade -y


#### live packages for debian/devuan
chroot chroot apt-get install live-config live-boot --no-install-recommends  -y
echo "DISABLE_DM_VERITY=true" >> chroot/etc/live/boot.conf

#### Configure system
cat > chroot/etc/apt/apt.conf.d/01norecommend << EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

# Set sh as bash inside of dash (optional)
rm -f chroot/bin/sh
ln -s bash chroot/bin/sh

#### Remove bloat files after dpkg invoke (optional)
cat > chroot/etc/apt/apt.conf.d/02antibloat << EOF
DPkg::Post-Invoke {"rm -rf /usr/share/locale || true";};
DPkg::Post-Invoke {"rm -rf /usr/share/man || true";};
DPkg::Post-Invoke {"rm -rf /usr/share/help || true";};
DPkg::Post-Invoke {"rm -rf /usr/share/doc || true";};
DPkg::Post-Invoke {"rm -rf /usr/share/info || true";};
DPkg::Post-Invoke {"rm -rf /usr/share/i18n || true";};
EOF


#### liquorix kernel
curl https://liquorix.net/liquorix-keyring.gpg | chroot chroot apt-key add -
echo "deb http://liquorix.net/debian testing main" > chroot/etc/apt/sources.list.d/liquorix.list
chroot chroot apt-get update -y
chroot chroot apt-get install linux-image-liquorix-amd64 -y
#chroot chroot apt-get install linux-headers-liquorix-amd64 -y


##### Usefull stuff
chroot chroot apt-get install network-manager debootstrap -y

#### usbcore stuff (for initramfs)
echo "#!/bin/sh" > chroot/etc/initramfs-tools/scripts/init-top/usbcore.sh
echo "echo Y > /sys/module/usbcore/parameters/old_scheme_first" >> chroot/etc/initramfs-tools/scripts/init-top/usbcore.sh
chmod +x chroot/etc/initramfs-tools/scripts/init-top/usbcore.sh

### remove unused modules (optional)
rm -rf  chroot/lib/modules/*/kernel/drivers/media
rm -rf  chroot/lib/modules/*/kernel/drivers/gpu
rm -rf  chroot/lib/modules/*/kernel/sound
find chroot/lib/modules/*/ -iname "*.ko" -exec strip --strip-unneeded {} \;
chroot chroot depmod -a $(ls chroot/lib/modules)
chroot chroot update-initramfs -u -k all

### Remove sudo (optional)
chroot chroot apt purge sudo -y
chroot chroot apt autoremove -y

#### Clear logs and history
chroot chroot apt-get clean
rm -f chroot/root/.bash_history
rm -rf chroot/var/lib/apt/lists/*
find chroot/var/log/ -type f | xargs rm -f

### Create iso template
mkdir -p debjaro/boot || true
mkdir -p debjaro/live || true
ln -s live debjaro/casper || true

#### Copy kernel and initramfs (Debian/Devuan)
cp -pf chroot/boot/initrd.img-* debjaro/boot/initrd.img
cp -pf chroot/boot/vmlinuz-* debjaro/boot/vmlinuz

#### remove vmlinuz and initrd for minimize iso size (optional)
rm -rf chroot/boot/initrd.img-*
rm -rf chroot/boot/vmlinuz-*

#### Create squashfs
for dir in dev dev/pts proc sys ; do
    while umount -lf -R chroot/$dir 2>/dev/null ; do true; done
done
# For better installation time
#mksquashfs chroot filesystem.squashfs -comp gzip -wildcards
# For better compress ratio
mksquashfs chroot filesystem.squashfs -comp xz -wildcards

### Move squashfs file into iso template
mv filesystem.squashfs debjaro/live/filesystem.squashfs

#### Write grub.cfg
mkdir -p debjaro/boot/grub/
echo 'menuentry "Start Debjaro GNU/Linux 64-bit" --class debjaro {' > debjaro/boot/grub/grub.cfg
echo '    linux /boot/vmlinuz boot=live live-config quiet --' >> debjaro/boot/grub/grub.cfg
echo '    initrd /boot/initrd.img' >> debjaro/boot/grub/grub.cfg
echo '}' >> debjaro/boot/grub/grub.cfg

#### Create iso
grub-mkrescue debjaro -o debjaro-gnulinux-$(date +%s).iso
