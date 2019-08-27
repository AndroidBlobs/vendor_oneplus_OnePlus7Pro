#! /vendor/bin/sh

function configure_memplus_parameters() {
    bootmode=`getprop ro.vendor.factory.mode`
    if [ "$bootmode" == "ftm" ] || [ "$bootmode" == "wlan" ] || [ "$bootmode" == "rf" ];then
        return
    fi
    # wait post_boot config to be done
    while :
    do
        postboot_running=`getprop vendor.sys.memplus.postboot`
        if [ "$postboot_running" == "2" ]; then
            setprop vendor.sys.memplus.postboot 3
            exit 0
        elif [ "$postboot_running" == "3" ]; then
            break
        fi
        sleep 1
    done
    memplus=`getprop persist.sys.memplus.enable`
    case "$memplus"	in
        "false")
            # use original settings
            # remove swapfile to reclaim storage space
            # runtime disable, we don't remove swap
            # rm /data/vendor/swap/swapfile
            # swapoff /dev/block/zram0
            echo 2 > /sys/module/memplus_core/parameters/memory_plus_enabled
            ;;
        *)
            fsize=`stat -c%s /data/vendor/swap/swapfile`
            if [ $? -eq 0 ] && [ $fsize -ne 2147483648 ]; then
                # if swapfile size is wrong, remove it
                rm /data/vendor/swap/swapfile
            fi
            # Create Swap disk - 2GB size
            if [ ! -f /data/vendor/swap/swapfile ]; then
                #dd if=/dev/zero of=/data/vendor/swap/swapfile bs=1m count=2048
                skip=0
                count=2
                while [ $skip -lt 1024 ];
                do
                    seek=$(($skip*$count))
                    ((skip++))
                    dd if=/dev/zero of=/data/vendor/swap/swapfile seek=$seek bs=1m count=$count
                    if [ $? -ne 0 ]; then
                        # not enough space - remove swap file
                        rm -f /data/vendor/swap/swapfile
                        break
                    fi
                    sleep 0.05
                done

            fi
            # enable swapspace
            if [ -f /data/vendor/swap/swapfile ]; then
                mkswap /data/vendor/swap/swapfile
                swapon /data/vendor/swap/swapfile

                # raise the bar from 200,600,800 -> 600,750,850
                # echo "18432,23040,27648,150256,187296,217600" > /sys/module/lowmemorykiller/parameters/minfree
                if [ $? -eq 0 ]; then
                    echo 1 > /sys/module/memplus_core/parameters/memory_plus_enabled
                fi
            fi
            # reset zram swapspace
            swapoff /dev/block/zram0
            echo 1 > /sys/block/zram0/reset
            echo 2202009600 > /sys/block/zram0/disksize
            echo 742M > /sys/block/zram0/mem_limit
            mkswap /dev/block/zram0
            swapon /dev/block/zram0 -p 32758
            if [ $? -eq 0 ]; then
                echo 1 > /sys/module/memplus_core/parameters/memory_plus_enabled
            fi
            ;;
    esac

    # final check for consistency
    memplus_now=`getprop persist.sys.memplus.enable`
    if [ "$memplus" == "$memplus_now" ]; then
        retry=0
    fi
}
retry=1
while :
do
    if [ "$retry" == "1" ]; then
        configure_memplus_parameters
    else
        break
    fi
done
