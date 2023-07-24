#!/bin/bash
# Script to make the Linux From Scratch Live ISO
if [[ ! -f /usr/bin/mksquashfs ]]; then
  echo "ERROR: Squashfs-tools not found"
  echo "Please build them from: https://github.com/plougher/squashfs-tools"
fi
if [[ ! -f /usr/bin/mmd ]]; then
  echo "ERROR: mtools not found"
  echo "Please build them from: https://www.gnu.org/software/mtools/"
fi
# Change these
# LFS Chroot
ROOT="/media/EXSTOR/lfs-iso/chroot"
# Where most of the temporary work will be done
TEMP_DIR="/media/EXSTOR/lfs-iso"

FIRMWARE_VERSION="20230625"

KERNEL_VER=6.4.4
cd $TEMP_DIR
# Install Linux Firmware
wget https://cdn.kernel.org/pub/linux/kernel/firmware/linux-firmware-20230625.tar.xz
tar -xvf linux-firmware-$FIRMWARE_VERSION.tar.xz
cd linux-firmware-$FIRMWARE_VERSION
# Install the compressed firmware files (needs support in kernel)
sudo make DESTDIR=$ROOT FIRMWAREDIR=/usr/lib/firmware install-xz

# Install mkinitramfs and make the initrd
cat > $ROOT/usr/sbin/mkinitramfs << "EOF"
#!/bin/bash
# This file based in part on the mkinitramfs script for the LFS LiveCD
# written by Alexander E. Patrakov and Jeremy Huntwork.

copy()
{
  local file

  if [ "$2" = "lib" ]; then
    file=$(PATH=/usr/lib type -p $1)
  else
    file=$(type -p $1)
  fi

  if [ -n "$file" ] ; then
    cp $file $WDIR/usr/$2
  else
    echo "Missing required file: $1 for directory $2"
    rm -rf $WDIR
    exit 1
  fi
}

if [ -z $1 ] ; then
  INITRAMFS_FILE=initrd.img-no-kmods
else
  KERNEL_VERSION=$1
  INITRAMFS_FILE=initrd.img-$KERNEL_VERSION
fi

if [ -n "$KERNEL_VERSION" ] && [ ! -d "/usr/lib/modules/$1" ] ; then
  echo "No modules directory named $1"
  exit 1
fi

printf "Creating $INITRAMFS_FILE... "

binfiles="sh cat cp dd killall ls mkdir mknod mount "
binfiles="$binfiles umount sed sleep ln rm uname"
binfiles="$binfiles readlink basename"

# Systemd installs udevadm in /bin. Other udev implementations have it in /sbin
if [ -x /usr/bin/udevadm ] ; then binfiles="$binfiles udevadm"; fi

sbinfiles="modprobe blkid switch_root"

# Optional files and locations
for f in mdadm mdmon udevd udevadm; do
  if [ -x /usr/sbin/$f ] ; then sbinfiles="$sbinfiles $f"; fi
done

# Add lvm if present (cannot be done with the others because it
# also needs dmsetup
if [ -x /usr/sbin/lvm ] ; then sbinfiles="$sbinfiles lvm dmsetup"; fi

unsorted=$(mktemp /tmp/unsorted.XXXXXXXXXX)

DATADIR=/usr/share/mkinitramfs
INITIN=init.in

# Create a temporary working directory
WDIR=$(mktemp -d /tmp/initrd-work.XXXXXXXXXX)

# Create base directory structure
mkdir -p $WDIR/{dev,run,sys,proc,usr/{bin,lib/{firmware,modules},sbin}}
mkdir -p $WDIR/etc/{modprobe.d,udev/rules.d}
touch $WDIR/etc/modprobe.d/modprobe.conf
ln -s usr/bin  $WDIR/bin
ln -s usr/lib  $WDIR/lib
ln -s usr/sbin $WDIR/sbin
ln -s lib      $WDIR/lib64

# Create necessary device nodes
mknod -m 640 $WDIR/dev/console c 5 1
mknod -m 664 $WDIR/dev/null    c 1 3

# Install the udev configuration files
if [ -f /etc/udev/udev.conf ]; then
  cp /etc/udev/udev.conf $WDIR/etc/udev/udev.conf
fi

for file in $(find /etc/udev/rules.d/ -type f) ; do
  cp $file $WDIR/etc/udev/rules.d
done

# Install any firmware present
cp -a /usr/lib/firmware $WDIR/usr/lib

# Copy the RAID configuration file if present
if [ -f /etc/mdadm.conf ] ; then
  cp /etc/mdadm.conf $WDIR/etc
fi

# Install the init file
install -m0755 $DATADIR/$INITIN $WDIR/init

if [  -n "$KERNEL_VERSION" ] ; then
  if [ -x /usr/bin/kmod ] ; then
    binfiles="$binfiles kmod"
  else
    binfiles="$binfiles lsmod"
    sbinfiles="$sbinfiles insmod"
  fi
fi

# Install basic binaries
for f in $binfiles ; do
  ldd /usr/bin/$f | sed "s/\t//" | cut -d " " -f1 >> $unsorted
  copy /usr/bin/$f bin
done

for f in $sbinfiles ; do
  ldd /usr/sbin/$f | sed "s/\t//" | cut -d " " -f1 >> $unsorted
  copy $f sbin
done

# Add udevd libraries if not in /usr/sbin
if [ -x /usr/lib/udev/udevd ] ; then
  ldd /usr/lib/udev/udevd | sed "s/\t//" | cut -d " " -f1 >> $unsorted
elif [ -x /usr/lib/systemd/systemd-udevd ] ; then
  ldd /usr/lib/systemd/systemd-udevd | sed "s/\t//" | cut -d " " -f1 >> $unsorted
fi

# Add module symlinks if appropriate
if [ -n "$KERNEL_VERSION" ] && [ -x /usr/bin/kmod ] ; then
  ln -s kmod $WDIR/usr/bin/lsmod
  ln -s kmod $WDIR/usr/bin/insmod
fi

# Add lvm symlinks if appropriate
# Also copy the lvm.conf file
if  [ -x /usr/sbin/lvm ] ; then
  ln -s lvm $WDIR/usr/sbin/lvchange
  ln -s lvm $WDIR/usr/sbin/lvrename
  ln -s lvm $WDIR/usr/sbin/lvextend
  ln -s lvm $WDIR/usr/sbin/lvcreate
  ln -s lvm $WDIR/usr/sbin/lvdisplay
  ln -s lvm $WDIR/usr/sbin/lvscan

  ln -s lvm $WDIR/usr/sbin/pvchange
  ln -s lvm $WDIR/usr/sbin/pvck
  ln -s lvm $WDIR/usr/sbin/pvcreate
  ln -s lvm $WDIR/usr/sbin/pvdisplay
  ln -s lvm $WDIR/usr/sbin/pvscan

  ln -s lvm $WDIR/usr/sbin/vgchange
  ln -s lvm $WDIR/usr/sbin/vgcreate
  ln -s lvm $WDIR/usr/sbin/vgscan
  ln -s lvm $WDIR/usr/sbin/vgrename
  ln -s lvm $WDIR/usr/sbin/vgck
  # Conf file(s)
  cp -a /etc/lvm $WDIR/etc
fi

# Install libraries
sort $unsorted | uniq | while read library ; do
# linux-vdso and linux-gate are pseudo libraries and do not correspond to a file
# libsystemd-shared is in /lib/systemd, so it is not found by copy, and
# it is copied below anyway
  if [[ "$library" == linux-vdso.so.1 ]] ||
     [[ "$library" == linux-gate.so.1 ]] ||
     [[ "$library" == libsystemd-shared* ]]; then
    continue
  fi

  copy $library lib
done

if [ -d /usr/lib/udev ]; then
  cp -a /usr/lib/udev $WDIR/usr/lib
fi
if [ -d /usr/lib/systemd ]; then
  cp -a /usr/lib/systemd $WDIR/usr/lib
fi
if [ -d /usr/lib/elogind ]; then
  cp -a /usr/lib/elogind $WDIR/usr/lib
fi

# Install the kernel modules if requested
if [ -n "$KERNEL_VERSION" ]; then
  find \
     /usr/lib/modules/$KERNEL_VERSION/kernel/{crypto,fs,lib}                      \
     /usr/lib/modules/$KERNEL_VERSION/kernel/drivers/{block,ata,nvme,md,firewire} \
     /usr/lib/modules/$KERNEL_VERSION/kernel/drivers/{scsi,message,pcmcia,virtio} \
     /usr/lib/modules/$KERNEL_VERSION/kernel/drivers/usb/{host,storage}           \
     -type f 2> /dev/null | cpio --make-directories -p --quiet $WDIR

  cp /usr/lib/modules/$KERNEL_VERSION/modules.{builtin,order} \
            $WDIR/usr/lib/modules/$KERNEL_VERSION
  if [ -f /usr/lib/modules/$KERNEL_VERSION/modules.builtin.modinfo ]; then
    cp /usr/lib/modules/$KERNEL_VERSION/modules.builtin.modinfo \
            $WDIR/usr/lib/modules/$KERNEL_VERSION
  fi

  depmod -b $WDIR $KERNEL_VERSION
fi

( cd $WDIR ; find . | cpio -o -H newc --quiet | gzip -9 ) > $INITRAMFS_FILE

# Prepare early loading of microcode if available
if ls /usr/lib/firmware/intel-ucode/* >/dev/null 2>&1 ||
   ls /usr/lib/firmware/amd-ucode/*   >/dev/null 2>&1; then

# first empty WDIR to reuse it
  rm -r $WDIR/*

  DSTDIR=$WDIR/kernel/x86/microcode
  mkdir -p $DSTDIR

  if [ -d /usr/lib/firmware/amd-ucode ]; then
    cat /usr/lib/firmware/amd-ucode/microcode_amd*.bin > $DSTDIR/AuthenticAMD.bin
  fi

  if [ -d /usr/lib/firmware/intel-ucode ]; then
    cat /usr/lib/firmware/intel-ucode/* > $DSTDIR/GenuineIntel.bin
  fi

  ( cd $WDIR; find . | cpio -o -H newc --quiet ) > microcode.img
  cat microcode.img $INITRAMFS_FILE > tmpfile
  mv tmpfile $INITRAMFS_FILE
  rm microcode.img
fi

# Remove the temporary directories and files
rm -rf $WDIR $unsorted
printf "done.\n"

EOF


mkdir -p $ROOT/usr/share/mkinitramfs
cat > $ROOT/usr/share/mkinitramfs/init.in<< "EOF" 
#!/bin/sh

PATH=/usr/bin:/usr/sbin
export PATH

problem()
{
   printf "Encountered a problem!\n\nDropping you to a shell.\n\n"
   sh
}

no_device()
{
   printf "The device %s, which is supposed to contain the\n" $1
   printf "root file system, does not exist.\n"
   printf "Please fix this problem and exit this shell.\n\n"
}

no_mount()
{
   printf "Could not mount device %s\n" $1
   printf "Sleeping forever. Please reboot and fix the kernel command line.\n\n"
   printf "Maybe the device is formatted with an unsupported file system?\n\n"
   printf "Or maybe filesystem type autodetection went wrong, in which case\n"
   printf "you should add the rootfstype=... parameter to the kernel command line.\n\n"
   printf "Available partitions:\n"
}

do_mount_root()
{
   # Make Temporary Directories
   mkdir /.root
   mkdir -p /mnt
   mkdir -p /squash
   # Make the loopback interface for the squashfs mount
   mknod /dev/loop0 b 7 0
   device="/dev/disk/by-label/lfs"
   # Mount Rootfs
   echo "Mounting USB Container Drive"
   # Mount the actual drive to mount the squashfs
   mount $device /mnt
   echo "Mounting squashfs as overlay"
   # Cow = Copy on Write, really just a name
   mkdir -p /cow
   # Create a ram tmpfs on the entire folder
   mount -t tmpfs tmpfs /cow
   # This is where the changes are stored
   mkdir -p /cow/mod
   # Overlayfs needs a buffer directory
   mkdir -p /cow/buffer

   mount /mnt/boot/lfs.squashfs /squash -t squashfs -o loop
   mount -t overlay -o lowerdir=/squash,upperdir=/cow/mod,workdir=/cow/buffer overlay /.root
   # Expose the changes directory and the carrier drive to the user
   mkdir -p /.root/mnt/changes
   mkdir -p /.root/mnt/container
   mount --bind /cow/mod /.root/mnt/changes
   mount --bind /mnt /.root/mnt/container
}

do_try_resume()
{
   case "$resume" in
      UUID=* ) eval $resume; resume="/dev/disk/by-uuid/$UUID"  ;;
      LABEL=*) eval $resume; resume="/dev/disk/by-label/$LABEL" ;;
   esac

   if $noresume || ! [ -b "$resume" ]; then return; fi

   ls -lH "$resume" | ( read x x x x maj min x
       echo -n ${maj%,}:$min > /sys/power/resume )
}

init=/sbin/init
root=
rootdelay=
rootfstype=auto
ro="ro"
rootflags=
device=
resume=
noresume=false

mount -n -t devtmpfs devtmpfs /dev
mount -n -t proc     proc     /proc
mount -n -t sysfs    sysfs    /sys
mount -n -t tmpfs    tmpfs    /run

read -r cmdline < /proc/cmdline

for param in $cmdline ; do
  case $param in
    init=*      ) init=${param#init=}             ;;
    root=*      ) root=${param#root=}             ;;
    rootdelay=* ) rootdelay=${param#rootdelay=}   ;;
    rootfstype=*) rootfstype=${param#rootfstype=} ;;
    rootflags=* ) rootflags=${param#rootflags=}   ;;
    resume=*    ) resume=${param#resume=}         ;;
    noresume    ) noresume=true                   ;;
    ro          ) ro="ro"                         ;;
    rw          ) ro="rw"                         ;;
  esac
done

# udevd location depends on version
if [ -x /sbin/udevd ]; then
  UDEVD=/sbin/udevd
elif [ -x /lib/udev/udevd ]; then
  UDEVD=/lib/udev/udevd
elif [ -x /lib/systemd/systemd-udevd ]; then
  UDEVD=/lib/systemd/systemd-udevd
else
  echo "Cannot find udevd nor systemd-udevd"
  problem
fi

${UDEVD} --daemon --resolve-names=never
udevadm trigger
udevadm settle

if [ -f /etc/mdadm.conf ] ; then mdadm -As                       ; fi
if [ -x /sbin/vgchange  ] ; then /sbin/vgchange -a y > /dev/null ; fi
if [ -n "$rootdelay"    ] ; then sleep "$rootdelay"              ; fi

do_try_resume # This function will not return if resuming from disk
do_mount_root

killall -w ${UDEVD##*/}

exec switch_root /.root "$init" "$@"
EOF
chmod 0755 $ROOT/usr/sbin/mkinitramfs


# Make the ISO directory structure
cd $TEMP_DIR
mkdir -p ISO
cd ISO
mkdir -p boot/grub buffer mod isolinux unmod

# Setup ISOLinux for Legacy BIOS booting
cd $TEMP_DIR

wget https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/Testing/6.04/syslinux-6.04-pre1.tar.xz
tar -xvf syslinux-6.04-pre1.tar.xz
cd syslinux-6.04-pre1

# Copy files from syslinux archive to the ISOLinux directory
# https://wiki.syslinux.org/wiki/index.php?title=ISOLINUX
cp bios/com32/elflink/ldlinux/ldlinux.c32 $TEMP_DIR/ISO/isolinux/
cp bios/core/isolinux.bin $TEMP_DIR/ISO/isolinux/
cp bios/com32/elflink/ldlinux/ldlinux.elf $TEMP_DIR/ISO/isolinux/
cp bios/mbr/isohdpfx.bin $TEMP_DIR/ISO/isolinux/

# Make a ISOLinux configuration file
cat > $TEMP_DIR/ISO/isolinux/isolinux.cfg << "EOF"
menu hshift 4
menu width 70
menu title Linux From Scratch GNU/Linux Live Boot (Legacy Boot)
DEFAULT Linux From Scratch GNU/Linux
LABEL Linux From Scratch GNU/Linux
  SAY "Linux From Scratch"
  linux /boot/vmlinuz-KERNEL_VER
  APPEND initrd=/boot/initrd.img-KERNEL_VER
EOF
# Replace Kernel Ver
sed -i "s/KERNEL_VER/$KERNEL_VER/g" $TEMP_DIR/ISO/isolinux/isolinux.cfg

# EFI Boot Setup
cd $TEMP_DIR/ISO/boot/grub
# Copy the EFI modules
mkdir -p x86_64-efi
cp -rpv $ROOT/usr/lib/grub/x86_64-efi/*.mod x86_64-efi/
# Copy the EFI Font
mkdir -p fonts
cp -pv $ROOT/usr/share/grub/unicode.pf2 fonts/
# Make a configuration file
# The rootdelay kernel parameter is to give the kernel a chance to load the USB driver and recognnize the flash drive before the initrd attempts to mount the drive
cat > $TEMP_DIR/ISO/boot/grub/grub.cfg << "EOF"
set default=0
set timeout=5
insmod ext2
insmod iso9660
set loop=(cd0)

insmod efi_gop
insmod efi_uga
insmod font


search --no-floppy --label lfs --set root
set prefix=($root)/boot/grub

if loadfont ${prefix}/unicode.pf2
then
insmod gfxterm
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm
fi

menuentry --hotkey=l 'Linux From Scratch' {
   echo   'Loading /boot/vmlinuz-KERNEL_VER ...'
   linux  /boot/vmlinuz-KERNEL_VER           console=tty0           rw rootdelay=5
   echo   'Loading /boot/initrd.img-KERNEL_VER ...'
   initrd /boot/initrd.img-KERNEL_VER
}
menuentry --hotkey=r 'Reboot' {
   reboot
}
EOF
# Change Kernel Version
sed -i "s/KERNEL_VER/$KERNEL_VER/g" $TEMP_DIR/ISO/boot/grub/grub.cfg
# Setup the efi.img file
cd $TEMP_DIR/ISO
# Generate a .efi file with a preconfigured grub embeded into it
# (Once it finds the drive it will load the config off the drive itself)
grub-mkstandalone \
    --format=x86_64-efi \
    --output=$TEMP_DIR/bootx64.efi \
    --locales="" \
    --fonts="" \
    --compress xz \
    boot/grub/grub.cfg
# Wrap that into a clean fat formatted efi.img file (xorriso will take care of the rest if it knows where it is)
cd $TEMP_DIR
# Make a clean img file
dd if=/dev/zero of=efi.img bs=512 count=2880
# Make a filesystem
mkfs.msdos -F 12 -n 'LFS' efi.img
# Use mtools to inject the bootx64.efi into the img and mark the img as bootable/efi compliant 
# Make directories
mmd -i efi.img ::EFI
mmd -i efi.img ::EFI/BOOT
mcopy -i efi.img $TEMP_DIR/bootx64.efi ::EFI/BOOT/bootx64.efi
# Copy the efi.img into the boot/grub directory
cp efi.img $TEMP_DIR/ISO/boot/grub

# Generate the initramfs
# Mount Temporary File Systems
if [[ ! $(mount | grep "$ROOT/proc") ]]; then
# Only mount the minimum amount of filesystems needed 
 mount --bind /dev $ROOT/dev
 mount --bind /dev/pts $ROOT/dev/pts
 mount --bind /proc $ROOT/proc
 mount --bind /sys $ROOT/sys
fi

chroot "$ROOT" /usr/bin/env -i   \
    HOME=/root                  \
    PATH=/usr/bin:/usr/sbin     \
    /bin/bash -c "cd / && mkinitramfs $KERNEL_VER"
# Copy the kernel and initrd from the chroot to the ISO
cp $ROOT/boot/vmlinuz-* $TEMP_DIR/ISO/boot/
cp $ROOT/initrd* $TEMP_DIR/ISO/boot

# Unmount temporary file systems and prepare for compression
umount $ROOT/dev/pts
umount $ROOT/dev
umount $ROOT/proc
umount $ROOT/sys

cd $TEMP_DIR
sudo mksquashfs $ROOT lfs.squashfs

# Copy the squashfs file to the boot directory
cp lfs.squashfs $TEMP_DIR/ISO/boot/
cd $TEMP_DIR/ISO
# Use Xorriso to generate the final iso
xorriso -as mkisofs \
  -isohybrid-mbr $TEMP_DIR/ISO/isolinux/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o lfs.iso -V lfs \
  .
cp lfs.iso $TEMP_DIR
readlink -f $TEMP_DIR/lfs.iso
