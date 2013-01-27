#!/sbin/sh

#set -x
#exec >>/multiboot.log 2>&1

checkfresh()
{
    if [ ! -e /turbo/version ]; then
        # delete old settings
        rm -rf /turbo/*
        uname -r > /turbo/version;
        echo "icon=@slot1" > /turbo/slot1.prop
        echo "text=Slot 1" >> /turbo/slot1.prop
        echo "mode=JB-AOSP" > /turbo/slot1mode.prop
        echo "icon=@slot2" > /turbo/slot2.prop
        echo "text=Slot 2" >> /turbo/slot2.prop
        echo "mode=JB-AOSP" > /turbo/slot2mode.prop
        echo "icon=@slot3" > /turbo/slot3.prop
        echo "text=Slot 3" >> /turbo/slot3.prop
        echo "mode=JB-AOSP" > /turbo/slot3mode.prop
        echo "icon=@slot4" > /turbo/slot4.prop
        echo "text=Slot 4" >> /turbo/slot4.prop
        echo "mode=JB-AOSP" > /turbo/slot4mode.prop
        echo "1";
    else
        echo "0";
    fi     
}

clearslot()
{
    echo "icon=@slot$2" > /turbo/slot$2.prop
    echo "text=Slot $2" >> /turbo/slot$2.prop
    echo "custom=true" >> /turbo/slot$2.prop
    echo "mode=JB-AOSP" >> /turbo/slot$2.prop
}

checkslot()
{
    if [ ! -e /turbo/system$2.ext2.img ] && [ ! -e /turbo/userdata$2.ext2.img ]; then 
        echo "1";
    else
        echo "0";
    fi
}

checkdefault()
{
    if   [ -e /turbo/defaultboot_2 ]; then
        rm /turbo/defaultboot_1 >> /dev/null 2>&1
        rm /turbo/defaultboot_3 >> /dev/null 2>&1
        rm /turbo/defaultboot_4 >> /dev/null 2>&1
        echo "2";
    elif [ -e /turbo/defaultboot_3 ]; then
        rm /turbo/defaultboot_1 >> /dev/null 2>&1
        rm /turbo/defaultboot_4 >> /dev/null 2>&1
        echo "3";
    elif [ -e /turbo/defaultboot_4 ]; then
        rm /turbo/defaultboot_1 >> /dev/null 2>&1
        echo "4";
    else
        echo "1";
    fi
}



makeimage()
{
    if   [ "$3" == "system" ]; then
        IMGSIZE=$4
        rm /turbo/system$2.ext2.img
        dd if=/dev/zero of=/turbo/system$2.ext2.img bs=1K count=$IMGSIZE
        mke2fs -b 1024 -I 128 -m 0 -F -E resize=$(( IMGSIZE * 2 )) /turbo/system$2.ext2.img
        tune2fs -C 1 -m 0 -f /turbo/system$2.ext2.img
    elif [ "$3" == "userdata" ]; then
        IMGSIZE=$4
        rm /turbo/userdata$2.ext2.img
        dd if=/dev/zero of=/turbo/userdata$2.ext2.img bs=1K count=$IMGSIZE
        mke2fs -b 1024 -I 128 -m 0 -F -E resize=$(( IMGSIZE * 2 )) /turbo/userdata$2.ext2.img
        tune2fs -C 1 -m 0 -f /turbo/userdata$2.ext2.img
    fi
}

copyimage()
{
    mkdir /dest
    if   [ "$3" == "system" ]; then
        mount -t yaffs2 -o ro /dev/block/mtdblock0 /system
        mount -t ext2 -o rw,loop /turbo/system$2.ext2.img /dest
        cp -a /system/* /dest
        umount /system
    elif [ "$3" == "userdata" ]; then
        mount -t yaffs2 -o ro /dev/block/mtdblock1 /data
        mount -t ext2 -o rw,loop /turbo/userdata$2.ext2.img /dest
        cp -a /data/* /dest
        umount /data
    fi
    umount /dest
    rm -f -R /dest
}

mounter()
{
    echo "About to mount Slot $1..."
    if  [ "$1" == "1" ]; then
        mount -t yaffs2 -o ro,remount                       /dev/block/mtdblock0        /system
        mount -t yaffs2 -o rw,remount,noatime,nosuid,nodev  /dev/block/mtdblock1        /data
    else
        mount /dev/block/mmcblk0p1 /sdcard
        mount -o bind /sdcard/turbo /turbo
        umount -l /sdcard
        rm -rf /sdcard
        losetup /dev/block/loop0 /turbo/system$1.ext2.img
        losetup /dev/block/loop1 /turbo/userdata$1.ext2.img
        umount /system
        umount /data
        mount -t ext2   -o rw                        /dev/block/loop0    /system
        mount -t ext2   -o ro,remount                /dev/block/loop0    /system
        mount -t ext2   -o rw,noatime,nosuid,nodev   /dev/block/loop1    /data
    fi
    
    busybox echo 0 > $BOOTREC_LED_RED
    busybox echo 0 > $BOOTREC_LED_GREEN
    busybox echo 0 > $BOOTREC_LED_BLUE
    
    # TSDX
    if [ -e /data/tsdx/enabled ] && [ -d /data/data ]; then
        # only proceed if data has been populated (i.e. ROM has booted at least once)
        # this is to ensure permissions are not broken
        mount -o rw,remount -t rootfs rootfs /
        if [ ! -d /sd-ext ]; then
            rm -r -f /sd-ext
            mkdir -p /sd-ext
            chmod -R 775 /sd-ext
            chown -R 0:0 /sd-ext
        fi
        chmod 775 /sd-ext
        chown 0:0 /sd-ext
        mount -o ro,remount -t rootfs rootfs /
        umount /sd-ext
        umount /dev/block/mmcblk0p2
        umount /dev/block/vold/179:2
        mount -t ext4 -o noauto_da_alloc,data=ordered,commit=15,barrier=1,nouser_xattr,errors=continue,noatime,nodiratime,nosuid,nodev /dev/block/mmcblk0p2 /sd-ext
        if [ ! -d /sd-ext/data2 ]; then
            # Create data2sd folder for Titanium Backup if needed (to share app data between slots)
            mkdir -p /sd-ext/data2
        fi
        for f in app app_s app-private framework_s lib_s; do
            if [ ! -h /data/$f ]; then
                busybox echo 200 > $BOOTREC_LED_RED
                busybox echo 200 > $BOOTREC_LED_GREEN
                busybox echo 200 > $BOOTREC_LED_BLUE
                # /data/$f not linked yet
                if [ -d /data/$f ]; then
                    # folder exists, move it
                    mv /data/$f /sd-ext/$f
                fi
                busybox echo 0 > $BOOTREC_LED_RED
                busybox echo 0 > $BOOTREC_LED_GREEN
                busybox echo 0 > $BOOTREC_LED_BLUE
                if [ ! -d /sd-ext/$f ]; then
                    # folder not exists yet (empty on internal), create it
                    mkdir -p /sd-ext/$f
                fi
                # link it
                ln -s /sd-ext/$f /data/$f
            fi
        done
        if [ ! -h /data/system ]; then
            # /data/system not linked yet
            if [ -d /data/system ]; then
                # folder exists, move it
                busybox echo 200 > $BOOTREC_LED_RED
                busybox echo 200 > $BOOTREC_LED_GREEN
                busybox echo 200 > $BOOTREC_LED_BLUE
                mv /data/system /sd-ext/system_slot$1
                busybox echo 0 > $BOOTREC_LED_RED
                busybox echo 0 > $BOOTREC_LED_GREEN
                busybox echo 0 > $BOOTREC_LED_BLUE
            fi
            # link it
            ln -s /sd-ext/system_slot$1 /data/system
        fi
    fi
}

mountproc()
{
    source /sbin/bootrec-device
    busybox echo 200 > $BOOTREC_LED_RED
    busybox echo 200 > $BOOTREC_LED_GREEN
    busybox echo 200 > $BOOTREC_LED_BLUE
    echo "Mountproc started..."
    if   [ -e /cache/multiboot1 ]; then
        rm /cache/multiboot1
        mounter 1
    elif [ -e /cache/multiboot2 ]; then
        rm /cache/multiboot2
        mounter 2
    elif [ -e /cache/multiboot3 ]; then
        rm /cache/multiboot3
        mounter 3
    elif [ -e /cache/multiboot4 ]; then
        rm /cache/multiboot4
        mounter 4
    elif [ -e /turbo/defaultboot_2 ]; then
        mounter 2
    elif [ -e /turbo/defaultboot_3 ]; then
        mounter 3
    elif [ -e /turbo/defaultboot_4 ]; then
        mounter 4
    else
        mounter 1
    fi
    
    sync
    
    mkdir /data/dalvik-cache
        chown system:system /data/dalvik-cache
        chmod 0771 /data/dalvik-cache
    mkdir /cache/dalvik-cache
        chown system:system /cache/dalvik-cache
        chmod 0771 /cache/dalvik-cache
    mount -o bind /data/dalvik-cache /cache/dalvik-cache
    
    sync
    
    busybox echo 0 > $BOOTREC_LED_RED
    busybox echo 0 > $BOOTREC_LED_GREEN
    busybox echo 0 > $BOOTREC_LED_BLUE
}

checkfree()
{
    FREE=`df | grep $2 | awk '{print $4}'`
    SPACE=`expr $FREE - 10240`
    INPUT=`expr $3 + $4`
    echo "tmp=`expr $SPACE - $INPUT`" > /tmp/aroma/tmp.prop
}

checkcapacity()
{
    echo "tmp=`cat /proc/partitions | grep $2 | awk '{print $3}'`" > /tmp/aroma/tmp.prop
}

checktsdx()
{
    sync
    umount /data
    if  [ "$2" == "1" ]; then
        mount -t yaffs2 -o rw,noatime,nosuid,nodev  /dev/block/mtdblock1        /data
    else
        losetup /dev/block/loop1 /turbo/userdata$1.ext2.img
        mount -t ext2   -o rw,noatime,nosuid,nodev   /dev/block/loop1    /data
    fi
    
    sync
    
    if [ -e /data/tsdx/enabled ]; then
        echo "task=Remove" > /tmp/tsdxstatus.prop
    else
        echo "task=Install" > /tmp/tsdxstatus.prop
    fi
    
    sync
}

$1 $1 $2 $3 $4
