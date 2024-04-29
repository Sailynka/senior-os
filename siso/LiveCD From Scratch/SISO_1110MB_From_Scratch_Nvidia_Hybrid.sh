#!/bin/bash

#  !!!  DISCLAIMER !!!
    # 1. SCRIPT MUST BE RUN AS A ROOT USER OR BY USER IN SUDO GROUP
    # 2. THE CONNECTED USB DRIVE HAS TO BE EMPTY, WITHOUT ANY DISK PARTITION
    # 3. ADD EXACUTABLE RIGHTS FOR THE SCRIPT

# CURRENT .ISO SIZE - METHOD FROM SCRATCH - 1,1 GB with Nvidia proprietary drivers

#----------------------------------------VARIABLES------------------------------------>
work_folder="SCRIPT"                                        # Live system work directory
output_dir="/home/student"                                  # Location of the generated .ISO image file
iso_name="siso-debian-from-scratch-1110"                    # Live system ISO name

file_dir="/home/student/Documents"                          # Storage directory for palemoon.tar.xz, PDF files, splash images
    palemoon="palemoon-32.4.0.linux-x86_64-gtk2.tar.xz"
    pdf="OS_*"
    splash="splash-FS-640-480.png"

username_live="root"                                        # Live system username and password
password_live="student"

disk_partition="/dev/sdd"                                   # Removable storage medium name
disk_write_speed="7M"                                       # Removable storage medium speed
disk_partition_password="storage"                           # Password for removable storage medium

#----------------------------------------PACKAGES------------------------------------->
    # HOST SYSTEM REQUIREMENTS
apt-get install \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-efi \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-ia32-bin \
    mtools \
    dosfstools

        # HOME FOLDER - LIVE CD FROM SCRATCH
mkdir -p "${HOME}/${work_folder}"
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    stable \
    "${HOME}/${work_folder}/chroot" \
    http://ftp.cz.debian.org/debian/


        # LIVE CD SYSTEM REQUIREMENTS (KERNEL, INIT)
chroot "${HOME}/${work_folder}/chroot" << EOF
apt-get update && \
apt-get install -y --no-install-recommends \
    linux-image-amd64 \
    linux-headers-amd64 \
    live-boot \
    systemd-sysv
EOF

chroot "${HOME}/${work_folder}/chroot" << EOF
apt-get install -y --no-install-recommends \
    curl \
    network-manager \
    net-tools \
    xserver-xorg-core \
    xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev \
    libasound2 \
    libdbus-glib-1-2 \
    libgtk2.0-0 \
    ca-certificates \
    console-setup \
    locales \
    cryptsetup \
    cryptsetup-initramfs \
    cryptsetup-run \
    xpdf \
    xinit \
    nano \
    xz-utils
EOF

#-----------------------------NVIDIA-PROPRIETARY-DRIVERS------------------------------>
# NVIDIA HYBRID GPU SUPPORT (+310MB TO THE LIVE SYSTEM)
    # ONE OF THE PREREQUISITES: INSTALLED linux-headers-amd64
    # MIRROR ADD FOR PROPRIETARY NVIDIA DRIVERS AVAILABLE FROM non-free PACKAGES
echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" >> "${HOME}/${work_folder}/chroot/etc/apt/sources.list"
chroot "${HOME}/${work_folder}/chroot" apt update
chroot "${HOME}/${work_folder}/chroot" apt-get install -y --no-install-recommends nvidia-driver

#------------------------------LIVE-SYSTEM-CUSTOMIZATION------------------------------>
    # HOSTNAME
echo "debian-live" | tee "${HOME}/${work_folder}/chroot/etc/hostname"

    # PASSWORD
echo -e "$password_live\n$password_live" | chroot "${HOME}/${work_folder}/chroot" passwd "$username_live"

    # KEYBOARD
tee "${HOME}/${work_folder}/chroot/etc/default/keyboard" << EOF
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="cz"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
EOF
    # LOCALE
tee "${HOME}/${work_folder}/chroot/etc/default/locale" << EOF
#  File generated by update-locale

LANG="en_US.UTF-8"
LC_NUMERIC="cs_CZ.UTF-8"
LC_TIME="cs_CZ.UTF-8"
LC_MONETARY="cs_CZ.UTF-8"
LC_PAPER="cs_CZ.UTF-8"
LC_NAME="cs_CZ.UTF-8"
LC_ADDRESS="cs_CZ.UTF-8"
LC_TELEPHONE="cs_CZ.UTF-8"
LC_MEASUREMENT="cs_CZ.UTF-8"
LC_IDENTIFICATION="cs_CZ.UTF-8"
EOF

# AUTOLOGIN
	# TTY NUMBER DECREASE
chroot "${HOME}/${work_folder}/chroot" sed -i 's/^#NAutoVTs=.*/NAutoVTs=1/g' "/etc/systemd/logind.conf"
    # CREATE NEW SERVICE
chroot "${HOME}/${work_folder}/chroot" mkdir -p "/etc/systemd/system/getty@tty1.service.d/"

tee "${HOME}/${work_folder}/chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

# PERMIT LOAD dm-crypt KERNEL MODULE
echo "CRYPTSETUP=y" | tee -a "${HOME}/${work_folder}/chroot/etc/cryptsetup-initramfs/conf-hook"
        # UPDATE INITRAMFS
chroot "${HOME}/${work_folder}/chroot" update-initramfs -k all -u

# PALEMOON
cp ${file_dir}/${palemoon} ${HOME}/${work_folder}/chroot
chroot "${HOME}/${work_folder}/chroot" tar xvf "/${palemoon}" -C /
chroot "${HOME}/${work_folder}/chroot" ln -s /palemoon/palemoon /usr/bin/palemoon
chroot "${HOME}/${work_folder}/chroot" rm -rf "/${palemoon}"

chroot "${HOME}/${work_folder}/chroot" mkdir -p /root/PDF
cp "${file_dir}/"${pdf} "${HOME}/${work_folder}/chroot/root/PDF/"

mkdir -p "${HOME}/${work_folder}"/{staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live},tmp}

	# COMPRESSION OF THE ALTERED CHROOT ENVIRONMENT
mksquashfs \
    "${HOME}/${work_folder}/chroot" \
    "${HOME}/${work_folder}/staging/live/filesystem.squashfs" \
    -e boot

	# COPPY OF THE KERNEL AND INITRAMFS
cp "${HOME}/${work_folder}/chroot/boot"/vmlinuz-* \
    "${HOME}/${work_folder}/staging/live/vmlinuz" && \
cp "${HOME}/${work_folder}/chroot/boot"/initrd.img-* \
    "${HOME}/${work_folder}/staging/live/initrd"

#--------------------------------------BOOTLOADERS----------------------------------->
    # ISOLINUX (SYSLINUX)
tee "${HOME}/${work_folder}/staging/isolinux/isolinux.cfg" << EOF
UI vesamenu.c32

MENU BACKGROUND splash.png

DEFAULT linux

MENU COLOR title         * #FFFFFFFF *
MENU COLOR border        * #00000000 #00000000 none

MENU COLOR sel           * #ffffffff #76a1d0ff *
MENU COLOR hotsel        1;7;37;40 #ffffffff #76a1d0ff *

MENU COLOR tabmsg	     * #ffffffff #00000000 *
MENU COLOR help          37;40 #ffdddd00 #00000000 none

MENU VSHIFT 12
MENU HSHIFT 25
MENU WIDTH 45

MENU cmdlinerow 16
MENU tabmsgrow 18
MENU tabmsg Press ENTER to boot or TAB to edit a menu entry

LABEL linux
  MENU LABEL Debian Live

  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live persistence persistence-encryption=luks silent noeject
EOF

	### ISOLINUX SPLASH IMG
cp ${file_dir}/${splash} ${HOME}/${work_folder}/staging/isolinux/splash.png

# BOOTLOADERS
    # GRUB (EFI/UEFI MODE)
tee "${HOME}/${work_folder}/staging/boot/grub/grub.cfg" << EOF
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

insmod all_video
insmod font

insmod png
insmod gfxmenu

set gfxmode=auto
set gfxpayload=keep
set distributor=""

set default="0"
set timeout=30

terminal_input console
terminal_output gfxterm

set theme=/boot/grub/theme.txt

# If X has issues finding screens, experiment with/without nomodeset.

menuentry "Debian Live [EFI/GRUB]" {
    search --no-floppy --set=root --label DebianLive
    linux (\$root)/live/vmlinuz boot=live persistence persistence-encryption=luks silent noeject
    initrd (\$root)/live/initrd
}

play 0 0 0
EOF

tee "${HOME}/${work_folder}/staging/boot/grub/theme.txt" << EOF
desktop-image: "/boot/grub/splash-FS-640-480.png"
title-text: ""

message-font: "Unifont Regular 16"
terminal-font: "Unifont Regular 16"

#help bar at the bottom
+ label {
    top = 100%-50
    left = 0
    width = 100%
    height = 20
    text = "@KEYMAP_SHORT@"
    align = "center"
    color = "#ffffff"
	font = "DejaVu Sans Bold 14"
}

#boot menu
+ boot_menu {
    left = 50%
    width = 40%
    top = 50%
    height = 48%-80
    item_color = "#a8a8a8"
	item_font = "DejaVu Sans Bold 14"
    selected_item_color= "#ffffff"
	selected_item_font = "DejaVu Sans Bold 14"
    item_height = 16
    item_padding = 0
    item_spacing = 4
	icon_width = 0
	icon_heigh = 0
	item_icon_space = 0
}
EOF

    ### GRUB splash IMG
cp ${file_dir}/${splash} ${HOME}/${work_folder}/staging/boot/grub/${splash}

# COPY GRUP DEPENDENCIES INTO EFI BOOT DIRECTORY
cp "${HOME}/${work_folder}/staging/boot/grub/"{grub.cfg,theme.txt,${splash}} "${HOME}/${work_folder}/staging/EFI/BOOT/"


	# CONFIG - FIND ROOT AND LOAD THE GRUB CONFIG
tee "${HOME}/${work_folder}/tmp/grub-embed.cfg" << EOF
if ! [ -d "\$cmdpath" ]; then
    # On some firmware, GRUB has a wrong cmdpath when booted from an optical disc.
    # https://gitlab.archlinux.org/archlinux/archiso/-/issues/183

    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "\$cmdpath"; then
        cmdpath="\${isodevice}/EFI/BOOT"
    fi
fi
configfile "\${cmdpath}/grub.cfg"
EOF

	# PREPARE BOOT LOADER FILES	(BIOS/LEGACY)
cp /usr/lib/ISOLINUX/isolinux.bin "${HOME}/${work_folder}/staging/isolinux/" && \
cp /usr/lib/syslinux/modules/bios/* "${HOME}/${work_folder}/staging/isolinux/"


	# (EFI/MODERN)
cp -r /usr/lib/grub/x86_64-efi/* "${HOME}/${work_folder}/staging/boot/grub/x86_64-efi/"

#-------------------------------STANDALONE-GRUB-GENERATION---------------------------->
# EFI bootable from GRUB x32
grub-mkstandalone -O i386-efi \
    --modules="part_gpt part_msdos fat iso9660 ls png gfxmenu" \
    --locales="" \
    --themes="" \
    --fonts="" \
    --output="${HOME}/${work_folder}/staging/EFI/BOOT/BOOTIA32.EFI" \
    "/boot/grub/grub.cfg=${HOME}/${work_folder}/tmp/grub-embed.cfg" \
    "/boot/grub/theme.txt=${HOME}/${work_folder}/staging/boot/grub/theme.txt" \
    "/boot/grub/${splash}=${HOME}/${work_folder}/staging/boot/grub/${splash}"

	# EFI bootable from GRUB x64
grub-mkstandalone -O x86_64-efi \
    --modules="part_gpt part_msdos fat iso9660 ls png gfxmenu" \
    --locales="" \
    --themes="" \
    --fonts="" \
    --output="${HOME}/${work_folder}/staging/EFI/BOOT/BOOTx64.EFI" \
    "/boot/grub/grub.cfg=${HOME}/${work_folder}/tmp/grub-embed.cfg" \
    "/boot/grub/theme.txt=${HOME}/${work_folder}/staging/boot/grub/theme.txt" \
    "/boot/grub/${splash}=${HOME}/${work_folder}/staging/boot/grub/${splash}"

	# FAT16 UEFI containing EFI
(cd "${HOME}/${work_folder}/staging" && \
    dd if=/dev/zero of=efiboot.img bs=1M count=20 && \
    mkfs.vfat efiboot.img && \
    mmd -i efiboot.img ::/EFI ::/EFI/BOOT && \
    mcopy -vi efiboot.img \
        "${HOME}/${work_folder}/staging/EFI/BOOT/BOOTIA32.EFI" \
        "${HOME}/${work_folder}/staging/EFI/BOOT/BOOTx64.EFI" \
        "${HOME}/${work_folder}/staging/EFI/BOOT/grub.cfg" \
        "${HOME}/${work_folder}/staging/EFI/BOOT/theme.txt" \
        "${HOME}/${work_folder}/staging/EFI/BOOT/${splash}" \
        ::/EFI/BOOT/
)

#--------------------------------------ISO-CREATION----------------------------------->
	# CREATE A BOOTABLE ISO
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "${output_dir}/${iso_name}.iso" \
    -full-iso9660-filenames \
    -volid "DebianLive" \
    -publisher "Lada Struziakova" \
    -preparer "241110@vutbr.cz" \
    -appid "DEBIANLIVE" \
    --mbr-force-bootable -partition_offset 16 \
    -joliet -joliet-long -rational-rock \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot \
        isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e --interval:appended_partition_2:all:: \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B ${HOME}/${work_folder}/staging/efiboot.img \
    "${HOME}/${work_folder}/staging"

#--------------------------------ENCRYPTED-PERSISTENCE-------------------------------->
    # COPY LIVE SYSTEM TO THE USB FLASH DRIVE
dd bs=${disk_write_speed} if=${output_dir}/${iso_name}.iso of=${disk_partition} oflag=sync

    # CREATE NEW PRIMARY PARTITION NUMBER 3
echo -e "n\np\n3\n\n\nw" | sudo fdisk -w never "${disk_partition}" > /dev/null 2>&1

    # INFORM KERNEL WITH PARTITION TABLE CHANGES
partprobe ${disk_partition}

    # CREATE ENCRYPTED PARTITION
echo -n "${disk_partition_password}" | sudo cryptsetup luksFormat ${disk_partition}3 -
    # OPEN ENCRYPTED PARTITION
echo -e "${disk_partition_password}" | sudo cryptsetup luksOpen ${disk_partition}3 live
    # FORMATE A CREATED PARTITION WITH FILESYSTEM TO ENABLE PERSISTENCE
mkfs.ext4 -L persistence /dev/mapper/live

    # CREATE A TEMPORARY MOUNT FOLDER, IF NOT EXISTS
mkdir -p /mnt/persistence
    # MOUNT DISK PARTITION INTO TEMPORARY FOLDER
mount /dev/mapper/live /mnt/persistence
    # WRITE PERSISTENCE CONDITION INTO PERSISTENCE.CONF FILE
echo "/home" > /mnt/persistence/persistence.conf
    # UMOUNT DISK PARTITION
umount /mnt/persistence

    # CLOSE ENCRYPTED PARTITION
cryptsetup luksClose live