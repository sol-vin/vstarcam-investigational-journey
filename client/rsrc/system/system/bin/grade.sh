#!/bin/sh
#This shell scripts used to update the u-boot linux kernel, root file system image when Linux running
erase_cmd=flash_eraseall
write_cmd=nandwrite
cu_version=`cat /proc/version`
PROG_NAME=`basename $0`
IMAGE_TYPE=
ROOTFS_TYPE=
usage()
{
  echo "  Usage:   $PROG_NAME -[f/k/r/s/h] [filename]"
  echo "Example:   $PROG_NAME -k Hisi-uImage.bin"
  echo "           $PROG_NAME -r Hisi-rootfs.squashfs"
  echo "           $PROG_NAME -s Hisi-system.jffs2"
  echo "           $PROG_NAME -f Hisi-flash.bin"
  echo "           $PROG_NAME -h" 
  exit;
}

burn_image()
{
    partition=$1
    file_name=$2
	MTD=$1
    MTDBLOCK=mtdblock${MTD:3}
#	cmd=`dd if=$file_name of=/dev/$MTDBLOCK`
	echo "partition = $partition, file_name = $file_name, MTDBLOCK = $MTDBLOCK"
#	exit
    if ( ! $erase_cmd /dev/$partition) ; then
        echo "Erase /dev/$partition failure."
        exit
    fi
	#dd if=/mnt/sda0/system.jffs2  of=/dev/mtdblock3  
	if ( ! `dd if=$file_name of=/dev/$partition` ) ; then
		echo "Write $file_name to /dev/$partition failure."
        exit
    fi
	
#    if ( ! $write_cmd -p /dev/$partition $file_name) ; then
#        echo "Write $file_name to /dev/$partition failure."
#        exit
#    fi
}
check_and_umount()
{
    MTD=$1
    MTDBLOCK=mtdblock${MTD:3}
    MOUNT_BLOCK=`cat /proc/mounts | grep $MTDBLOCK|awk -F " " '{print $1}'`
    if [ -n "$MOUNT_BLOCK" ] ; then
        umount /dev/$MTDBLOCK
    else
        echo "No need umount $MTDBLOCK"
    fi
}
check_image_type()
{
    IMAGE_NAME=$1
    if echo $IMAGE_NAME | grep -E "boot|uboot|u-boot|bootloader" > /dev/null ; then
        IMAGE_TYPE=BOOTLOADER
    elif echo $IMAGE_NAME | grep -E "linux|kernel" > /dev/null ; then
        IMAGE_TYPE=KERNEL
    elif  echo $IMAGE_NAME | grep -E "rootfs|jffs2|yaffs2|ubifs|cramfs|ramdisk" > /dev/null ; then
        IMAGE_TYPE=ROOTFS
	elif  echo $IMAGE_NAME | grep -E "system" > /dev/null ; then
        IMAGE_TYPE=SYSTEM
    else
        IMAGE_TYPE=UNKNOW
    fi
}
up_bootloader()
{
    IMAGE_FILE=$1
    echo "Upgrade bootloader image '$IMAGE_FILE'"
    #To-Do: Find the mtd here, only do upgrade if we can find it, or throw error and exit out
    #echo $mtd | grep -E "u-boot|uboot" | awk -F ":" '{print $1}'
    partition=`cat /proc/mtd | grep -E "boot|uboot|u-boot|U-boot|bootloader" | awk -F ":" '{print $1}'`
    if [ -z $partition ] ; then
        echo "Can not find the u-boot partition for update!"
        exit
    fi
    #To-Do: Start to burn the image to corresponding partition here
    burn_image $partition $IMAGE_FILE
}
up_kernel()
{
    IMAGE_FILE=$1
    echo "Upgrade linux kernel image '$IMAGE_FILE'"
    #To-Do: Find the mtd here, only do upgrade if we can find it, or throw error and exit out
    #echo $mtd | grep -E "linux|kernel" | awk -F ":" '{print $1}'
    partition=`cat /proc/mtd | grep -E "linux|kernel" | awk -F ":" '{print $1}'`
    if [ -z $partition ] ; then
        echo "Can not find the kernel partition for update!"
        exit
    fi
    #To-Do: Start to burn the image to corresponding partition here
    burn_image $partition $IMAGE_FILE
}

up_flash()
{
    IMAGE_FILE=$1
########### Upgrade uboot
	partition=`cat /proc/mtd | grep -E "boot|uboot|u-boot|U-boot|bootloader" | awk -F ":" '{print $1}'`
	echo "* Upgrade uboot, partition = '$partition'"
    if [ -z $partition ] ; then
        echo "Can not find the uboot partition for update!"
        exit
    fi
    
	if ( ! $erase_cmd /dev/$partition) ; then
        echo "Erase /dev/$partition failure."
        exit
    fi

	if ( ! `dd if=$IMAGE_FILE bs=1024 skip=0 count=1024 of=/dev/$partition` ) ; then
		echo "Write $file_name to /dev/$partition failure."
        exit
    fi
	echo "* Upgrade uboot succeed!"
	echo
########### Upgrade kernel	
    partition=`cat /proc/mtd | grep -E "linux|kernel" | awk -F ":" '{print $1}'`
	echo "* Upgrade kernel, partition = '$partition'"
    if [ -z $partition ] ; then
        echo "Can not find the kernel partition for update!"
        exit
    fi
    
	if ( ! $erase_cmd /dev/$partition) ; then
        echo "Erase /dev/$partition failure."
        exit
    fi
	
	if ( ! `dd if=$IMAGE_FILE bs=1024 skip=1024 count=3072 of=/dev/$partition` ) ; then
		echo "Write $file_name to /dev/$partition failure."
        exit
    fi
	echo "* Upgrade kernel succeed!"
	echo
########### Upgrade rootfs 
    partition=`cat /proc/mtd | grep -E "rootfs" | awk -F ":" '{print $1}'`
	echo "* Upgrade rootfs, partition = '$partition'"
    if [ -z $partition ] ; then
        echo "Can not find the rootfs partition for update!"
        exit
    fi
    
	if ( ! $erase_cmd /dev/$partition) ; then
        echo "Erase /dev/$partition failure."
        exit
    fi
	
	if ( ! `dd if=$IMAGE_FILE bs=1024 skip=4096 count=7168 of=/dev/$partition` ) ; then
		echo "Write $file_name to /dev/$partition failure."
        exit
    fi
	echo "* Upgrade rootfs succeed!"
	echo
########### Upgrade system	MTDBLOCK=mtdblock${MTD:3}
    partition=`cat /proc/mtd | grep -E "system" | awk -F ":" '{print $1}'`
	MTDBLOCK=mtdblock${partition:3}
	echo "* Upgrade system, partition = '$partition'"
    if [ -z $partition ] ; then
        echo "Can not find the system partition for update!"
        exit
    fi
    
	if ( ! $erase_cmd /dev/$partition) ; then
        echo "Erase /dev/$partition failure."
        exit
    fi
	
	if ( ! `dd if=$IMAGE_FILE bs=1024 skip=11264 count=5120 of=/dev/$partition` ) ; then
		echo "Write $file_name to /dev/$partition failure."
        exit
    fi
	echo "* Upgrade system succeed!"
	echo
}

up_rootfs()
{
    IMAGE_NAME=$1
    ROOTFS_TYPE=${IMAGE_NAME##*.}
    VALID_ROOTFS_TYPE=0
    echo $ROOTFS_TYPE
#    for i in jffs2 yaffs2 ubifs ramdisk cramfs squashfs ; do
#        if [ "$i" = "$ROOTFS_TYPE" ] ; then
#            VALID_ROOTFS_TYPE=1
 #           break;
#        fi
#    done
#    if [ 0 == $VALID_ROOTFS_TYPE ] ; then
 #       echo "============================================================================================"
#        echo "ERROR: Unknow rootfs image '$IMAGE_NAME', suffix/type: .$ROOTFS_TYPE"
#        echo "The suffix of rootfs image file name should be: .ramdisk .yaffs2 .jffs2 .ubifs .cramfs .squashfs"
#        echo "============================================================================================"
#        usage
#    fi
    echo "Upgrade $ROOTFS_TYPE rootfs image '$IMAGE_FILE'"
    #To-Do: Find the mtd here, only do upgrade if we can find it, or throw error and exit out
    MTD=`cat /proc/mtd | grep -E "rootfs" | awk -F ":" '{print $1}'`
    #To-Do: Check this partition already mounted or not, if mounted then umount it first here
    check_and_umount $MTD
    #To-Do: Start to burn the image to corresponding partition here                                                                                                                    
    burn_image $MTD $IMAGE_FILE
}
up_system()
{
    IMAGE_NAME=$1
    ROOTFS_TYPE=${IMAGE_NAME##*.}
    VALID_ROOTFS_TYPE=0
    echo $ROOTFS_TYPE
    for i in jffs2 yaffs2 ubifs ramdisk cramfs squashfs ; do
        if [ "$i" = "$ROOTFS_TYPE" ] ; then
            VALID_ROOTFS_TYPE=1
            break;
        fi
    done
    if [ 0 == $VALID_ROOTFS_TYPE ] ; then
        echo "============================================================================================"
        echo "ERROR: Unknow rootfs image '$IMAGE_NAME', suffix/type: .$ROOTFS_TYPE"
        echo "The suffix of rootfs image file name should be: .ramdisk .yaffs2 .jffs2 .ubifs .cramfs .squashfs"
        echo "============================================================================================"
        usage
    fi
    echo "Upgrade $ROOTFS_TYPE rootfs image '$IMAGE_FILE'"
    #To-Do: Find the mtd here, only do upgrade if we can find it, or throw error and exit out
    MTD=`cat /proc/mtd | grep -E "system" | awk -F ":" '{print $1}'`
    #To-Do: Check this partition already mounted or not, if mounted then umount it first here
    check_and_umount $MTD
    #To-Do: Start to burn the image to corresponding partition here                                                                                                                    
 #   burn_image $MTD $IMAGE_FILE
}
#echo "\$0"=$0 "\$1"=$1 "\$2"=$2
while getopts "fkrush" opt
do
#	echo opt = $opt
   case $opt in
      k)
           IMAGE_TYPE=KERNEL
           shift 1
           break;
           ;;
      r)
           IMAGE_TYPE=ROOTFS
           shift 1
           break;
           ;;
	s)
           IMAGE_TYPE=SYSTEM
           shift 1
           break;
           ;;
	f)
           IMAGE_TYPE=FLASH
           shift 1
           break;
           ;;
      h)
           usage
           ;;
      ?)
           usage
           ;;
   esac
done
#echo "\$0"=$0 "\$1"=$1 "\$2"=$2
IMAGE_FILE=$1
if [ ! -n "$IMAGE_FILE" ] ; then
	echo NULL
    usage
fi
if [ ! -n "$IMAGE_TYPE" ] ; then
	echo check_image_type
    check_image_type  $IMAGE_FILE
fi
if [ $IMAGE_TYPE == KERNEL ] ; then
	echo "**** ungrade KERNEL $IMAGE_FILE ****"
    up_kernel $IMAGE_FILE
elif [ $IMAGE_TYPE == ROOTFS ] ; then
	echo "**** ungrade ROOTFS $IMAGE_FILE ****"
    up_rootfs $IMAGE_FILE
elif [ $IMAGE_TYPE == SYSTEM ] ; then
    echo "**** ungrade SYSTEM $IMAGE_FILE ****"
	up_system $IMAGE_FILE
#    up_rootfs $IMAGE_FILE
elif [ $IMAGE_TYPE == FLASH ] ; then
    echo "**** ungrade FLASH $IMAGE_FILE ****"
	up_flash $IMAGE_FILE
#    up_rootfs $IMAGE_FILE
else
    echo "============================================================================================"
    echo "ERROR: Unknow image type: '$IMAGE_NAME'"
    echo "============================================================================================"
    usage
fi