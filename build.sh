#!/bin/bash


# Convert DiePI image to TVBOX S90X
# Dietpi OdroidC4 have 1 partion inn ext4
# TVBOX based on s905x - s905x3 need fat on part1 to boot linux
# This srcipt makes new image file : part 1 fat  , part 2 Dietpi ext4

# SETUP
# cd DIR DietPi_OdroidC4-ARMv8 IMGFILE
# sudo su
# bash dietpi_img_maker_s90X.sh DietPi_OdroidC4-ARMv8.XXXXXXXX.img


if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


pkgs='e2fsprogs mount parted util-linux dosfstools'
if ! dpkg -s $pkgs >/dev/null 2>&1; then
  sudo apt install $pkgs -y
fi


# Exit on error
set -e



echo " Convert $1 to S90X TVBOX image"

DIETPI_IMG="$1"

# DIETPI_IMG="DietPi_OdroidC4-ARMv8-Bullseye.img"

if [  -z "$DIETPI_IMG" ] ; then
echo -e " No DietPi_OdroidC4.img found " ; exit 1
fi

echo $DIETPI_IMG

# Mount IMG
#DIETPI_MOUNT_DEV=$(losetup --show -Pf DietPi_OdroidC4-ARMv8-Bullseye.img)
DIETPI_MOUNT_DEV=$(losetup --show -Pf $DIETPI_IMG)
echo $DIETPI_MOUNT_DEV


# Copy part1 to img file
dd if=${DIETPI_MOUNT_DEV}p1 of=DietPi_PART1.img status=progress

# Size MB 
#DIETPI_SIZE=$(du -m $DIETPI_IMG | awk '{ print $1}')
DIETPI_SIZE=$(lsblk -fn ${DIETPI_MOUNT_DEV}p1 -o size | grep -o '[0-9]' |  tr -d '\n')

#dd if=/dev/zero of=DietPi_PART1.img bs=1M count=200 seek=$DIETPI_SIZE

# ADD + 200MB more then DIETPI_IMG
S90X_IMG_SIZE=$(( DIETPI_SIZE + 210 ))

S90X_IMG="S90Xx_TVBOX_${DIETPI_IMG}"

# MAKE S90X_TVBOX_DietPi_OdroidC4-ARMv8-Bullseye.img file
dd if=/dev/zero of=${S90X_IMG} bs=4k iflag=fullblock,count_bytes count=${S90X_IMG_SIZE}M



#MOUNT
S90X_IMG_LOOP_DEV=$(losetup --show -Pf $S90X_IMG)

parted -s $S90X_IMG_LOOP_DEV mklabel msdos 
parted -s $S90X_IMG_LOOP_DEV mkpart primary fat32 4M 99M
parted -s $S90X_IMG_LOOP_DEV mkpart primary ext4 100M 97%
parted -s $S90X_IMG_LOOP_DEV mkpart primary fat16 98% 100%


mkfs.vfat -n "BOOT_DIETPI" ${S90X_IMG_LOOP_DEV}p1 
mke2fs -F -q -t ext4 -L "ROOT_DIETPI" -m 0 ${S90X_IMG_LOOP_DEV}p2
mkfs.vfat -n "DIETPISETUP" ${S90X_IMG_LOOP_DEV}p3 

# DD part 1 to part2 S90X_IMG
dd if=DietPi_PART1.img of=${S90X_IMG_LOOP_DEV}p2



#parted ${S90X_IMG_LOOP_DEV} unit s print # part infor
#parted ${S90X_IMG_LOOP_DEV} resizepart 2 yes -- -1s # resize part2
#e2fsck -fyv -C 0 ${S90X_IMG_LOOP_DEV}p2
#resize2fs -py  ${S90X_IMG_LOOP_DEV}p2


# resize ROOTFS 
e2fsck -fyv -C 0 ${S90X_IMG_LOOP_DEV}p2
partprobe ${S90X_IMG_LOOP_DEV}p2
resize2fs ${S90X_IMG_LOOP_DEV}p2


mkdir -p ./S90X_IMG/{BOOT_DIETPI,ROOT_DIETPI,DIETPISETUP_IMG,DIETPISETUP}

mount  ${S90X_IMG_LOOP_DEV}p1 ./S90X_IMG/BOOT_DIETPI
mount  ${S90X_IMG_LOOP_DEV}p2 ./S90X_IMG/ROOT_DIETPI

mount  ${DIETPI_MOUNT_DEV}p2 ./S90X_IMG/DIETPISETUP_IMG
mount  ${S90X_IMG_LOOP_DEV}p3 ./S90X_IMG/DIETPISETUP

# COPY DIETPISETUP FILES
cp -v -r ./S90X_IMG/DIETPISETUP_IMG/* ./S90X_IMG/DIETPISETUP/

# COPY AML BOOT FILES
cp -v -r ./BOOT_PART1_FAT32_SDCARD/* ./S90X_IMG/BOOT_DIETPI/
cp -v -r ./arm9xxx_dtb ./S90X_IMG/ROOT_DIETPI/boot/
cp -v -r ./BOOT_EMMC ./S90X_IMG/ROOT_DIETPI/boot/


ROOT_UUID=$(findmnt -n -o UUID ./S90X_IMG/ROOT_DIETPI)


#sed -e '/rootdev/ s/^#*/#/' ./S90X_IMG/ROOT_DIETPI/boot/dietpiEnv.txt
#sed -e "/UUID/ s/.*./rootdev=UUID=$ROOT_UUID/" ./S90X_IMG/ROOT_DIETPI/boot/dietpiEnv.txt
while ! cat ./S90X_IMG/ROOT_DIETPI/boot/dietpiEnv.txt &>/dev/null; do sleep 1 ; done

##### ADD DTB
echo " Update /boot/dietpiEnv.txt"

echo "# DTB tvbox folder /boot/dtb
# Default boot s905x  
# s905x
fdtfile=amlogic/meson-gxl-s905x-p212.dtb
# s905w  
#fdtfile=amlogic/meson-gxl-s905w-p281.dtb
# S912
#fdtfile=amlogic/meson-gxm-q200.dtb
# s905x3
#fdtfile=amlogic/meson-sm1-x96-air.dtb
# More dtb to test inn folder /boot/arm9xxx_dtb
# fdtfile=../arm9xxx_dtb/meson-sm1-x96-max-plus.dtb
# USB
# https://leo.leung.xyz/wiki/How_to_disable_USB_Attached_Storage_(UAS)
# lsusb
#usbstoragequirks=2109:0711:u
# BLACKLIST modules
#extraargs='usb-storage.quirks=2109:0711:u net.ifnames=0 modprobe.blacklist=88x2cs modprobe.blacklist=cfg80211 modprobe.blacklist=iTCO_wdt modprobe.blacklist=iTCO_vendor_support'
" | tee -a ./S90X_IMG/ROOT_DIETPI/boot/dietpiEnv.txt

# Write new dietpiEnv.txt to DIETPISETUP
cp -f -v -r ./S90X_IMG/ROOT_DIETPI/boot/dietpiEnv.txt ./S90X_IMG/DIETPISETUP

echo "
Burn S90Xx_TVBOX_DietPi_OdroidC4-ARMv8 img to sdcard
Default setup to boot s905x
Edit /boot/dietpiEnv.txt ON EXT4 part to change dtb used
Change fdtfile=amlogic/..........  <--- DTB name from folder /boot/dtb
u-boot.ext ON fat part
Rename to  u-boot.ext (default u-boot.ext for s905x s905w s912 )
Rename u-boot-s905x2-s922.mnj ---> u-boot.ext for S905x2 s905x3 
First boot
1. Innsert sdcard and press button inn A/V port  connect power
2. Release button after 5sec" | tee -a ./S90X_IMG/BOOT_DIETPI/TVBOX_SETUP.txt


sleep 1

while ! umount -v ./S90X_IMG/BOOT_DIETPI ; do sleep 1 ; done
while ! umount -v ./S90X_IMG/ROOT_DIETPI ; do sleep 1 ; done
while ! umount -v ./S90X_IMG/DIETPISETUP_IMG ; do sleep 1 ; done
while ! umount -v ./S90X_IMG/DIETPISETUP ; do sleep 1 ; done


# UNMOUNT
# losetup -D DietPi_OdroidC4-ARMv8-Bullseye.img
# losetup -D S90Xx_TVBOX_DietPi_OdroidC4-ARMv8-Bullseye.img
losetup -d $DIETPI_MOUNT_DEV
losetup -d $S90X_IMG_LOOP_DEV
losetup -D S90Xx_TVBOX_DietPi*  &>/dev/null

rm ./DietPi_PART1.img


