# lfs-live-iso
Default username:password for the proof of concept is lfs:lfs
Packages installed within the proof of concept are listed in the packages file.  In total 54 packages from BLFS were installed  

  This ISO is compatible with both EFI and BIOS Legacy Bios boot.

**A Live ISO Guide/Build Script for Linux From Scratch**


# Known Problems
For some reason, the initramfs is 343 MB so you might have to give it a minute to load the initrd.  I didn't have time to look further into it but this is on the top of the list 

## Build Instructions: 
**This is a preamble before the full hand built ISO instructions are written**

1) Build an LFS system (sysv or systemd) and continue as far as you want with BLFS in a chroot.  (This can be done with jhalfs or by hand)  

2) Rebuild libffi to work with any x86_64 CPU by running the configure with the march CFLAG.  
` CFLAGS=-march=core2 ./configure --prefix=/usr --disable-static --with-gcc-arch=core2 --disable-exec-static-tramp `

3) Rebuild GMP to work with any CPU by running the commands in the note before building  
` cp -v configfsf.guess config.guess && cp -v configfsf.sub   config.sub `

4) If the system was booted, remove the unique identifiers
   TBD
5) Make sure to build ther kernel, cpio, and grub with EFI support within the chroot

6) Delete /etc/fstab (the initrd will mounting root)

7)  BACKUP the chroot before proceeding

8)  Change the name of the kernel image in /boot to match this format vmlinuz-$KERNEL_VER ie vmlinuz-6.4.4, DO NOT install an initrd. 

9) Change the paths and kernel version in the make-iso.sh script

10) Run the make-iso.sh script

11) Verify that everything went well and attempt to boot the ISO within QEMU.


## Notes: 
#### Necessary Packages from BLFS (on the host):
 - squashfs-tools
 - mtools
 - sudo
 - dosfstools
 - libisoburn  
#### Necessary Packages from BLFS (in chroot):  
 - cpio
 - grub-efi
#### Recommended Packages from BLFS (in chroot)  
 - NetworkManager
 - PAM
 - sudo

# Script things
The script pre-installs linux-firmware onto the system for the best compatibility.  Currently, you still need an internet connection to view and build the book.,
Although you can view the book through lynx or links and copy paste using GPM.
