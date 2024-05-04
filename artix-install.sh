#!/bin/bash
# ------------------------------------------------------------------
# [Melnikov M.A.] Artix-OpenRC installation script
# 1) Пришлось создать разделдиска самостоятельно
# 2) По-умолчанию пользователь не root
# ------------------------------------------------------------------

# --- Global -------------------------------------------------------
VERSION=0.1.0
SUBJECT=$0

# Choose logging level (1 - errors, 2 - warnings, 3 - info, 4 - debug)
LOGGING_LEVEL=4
# ------------------------------------------------------------------

# --- Utils --------------------------------------------------------
show_help() {
    echo "Usage: . ./$0.sh [-h] [-v]"
    echo ""
    echo "Options:"
    echo "-h                Напечатать эту справку"
    echo "-v                Напечатать версию программы"
}

check_error() {
    local error="$1"
    local msg="$error"

    case "$error" in
        "mainOpt")
            msg="Choose the only one main option"
        ;;
        "root")
            msg="Use this option as root"
        ;;
    esac

    return "$msg"
}

show_logs() {
    logging=$1
    msg="$2"

    case $logging in
        "1")
            if [ $LOGGING_LEVEL -ge "$logging" ]; then
                msg=$(check_error "$msg")
                echo "\e[31m[ERROR]\e[0m $msg" >&2
            fi
            exit 1
        ;;
        "2")
            if [ $LOGGING_LEVEL -ge "$logging" ]; then
                echo "\e[33m[WARNING]\e[0m $msg"
            fi
        ;;
        "3")
            if [ $LOGGING_LEVEL -ge "$logging" ]; then
                echo "\e[32m[INFO]\e[0m $msg"
            fi
        ;;
        "4")
            if [ $LOGGING_LEVEL -ge "$logging" ]; then
                echo "\e[34m[DEBUG]\e[0m $msg"
            fi
        ;;
    esac
}
# ------------------------------------------------------------------

# --- Functions ----------------------------------------------------
partition_disk() {
    check_names() {
        if [ ! -b "$disk_name" ]; then
            show_logs 1 "Disk $disk_name not found."
        fi

        if vgdisplay "$group_name" &> /dev/null; then
            show_logs 1 "Volume group $group_name already exists."
        fi
    }

    check_free_space() {
        local total_disk_space
        local used_disk_space
        local available_disk_space
        local required_space

        total_disk_space=$(blockdev --getsize64 "$disk_name")
        used_disk_space=$(vgdisplay --units b --options vg_free --nosuffix "$disk_name" | sed '1d')
        available_disk_space=$((total_disk_space - used_disk_space))
        required_space=$(vgs --units b --options vg_extent_size --nosuffix | awk 'NR==2{print $1}')
        
        if [ "$available_disk_space" -lt "$required_space" ]; then
            show_logs 1 "Insufficient space on disk $disk_name."
        fi
    }

    add_swap_part() {
        lvcreate -n swap -L4G "$group_name"
        mkswap -L swap /dev/"$group_name"/swap 
        swapon /dev/"$group_name"/swap
    }
    
    local disk_name="$1"
    local group_name="$2"
    local swap="${3:-0}"

    check_names
    #check_free_space

    pvcreate "$disk_name"

    vgcreate "$group_name" "$disk_name"

    lvcreate -n usr -L10G "$group_name"
    lvcreate -n var -L5G "$group_name"
    lvcreate -n tmp -L1G "$group_name"
    lvcreate -n home -L14G "$group_name"
    lvcreate -n root -L20G "$group_name"

    mkfs.ext4 -L usr /dev/"$group_name"/usr
    mkfs.ext4 -L var /dev/"$group_name"/var
    mkfs.ext2 -L tmp /dev/"$group_name"/tmp
    mkfs.ext4 -L home /dev/"$group_name"/home
    mkfs.ext4 -L root /dev/"$group_name"/root

    if [ "$swap" -eq 1 ]; then
        add_swap_part
    fi
}

mount_parts() {
    local disk_name="$1"
    local group_name="$2"

    mount /dev/"$group_name"/root /mnt

    mkdir -p /mnt/home /mnt/usr /mnt/var /mnt/tmp

    mount /dev/"$group_name"/home /mnt/home
    mount /dev/"$group_name"/usr /mnt/usr
    mount /dev/"$group_name"/var /mnt/var
    mount /dev/"$group_name"/tmp /mnt/tmp
}

configure_network() {
    local interface="$1"
    local ssid="$2"
    local password="$3"
    local config="/etc/wpa_supplicant/wpa_supplicant.conf"
    
    rfkill unblock all
    ip link set "$interface" up

    {
        echo -e "ctrl_interface=/run/wpa_supplicant"; 
        echo -e "update_config=1"; 
        echo -e ""; 
        echo -e "network={"; 
        echo -e "\tssid=$ssid"; 
        echo -e "\tpsk=$password"; 
        echo -e "}"; 
    } >> "$config"

    rc-service wpa_supplicant restart
    dhclient wlan0
}

configure_user() {
    local username="$1"

    passwd

    useradd -m "$username"
    passwd "$username"
    usermod -aG wheel,audio,video,storage,scanner "$username"
}

configure_host() {
    local hostname="$1"

    touch /etc/hostname
    echo "$hostname" > /etc/hostname

    {
        echo -e "127.0.0.1\tlocalhost"; 
        echo -e "::1\t\t\tlocalhost"; 
        echo -e "127.0.1.1\t$hostname.localdomain\t$hostname";  
    } >> /etc/hosts
}
# ------------------------------------------------------------------


# --- Options processing -------------------------------------------
if [ $# == 0 ] ; then
    show_help
    exit 1;
fi

main_option=""

while getopts ":vhp:m:n:u:H:" option
do
	case "$option" in
		"v")
            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi

			echo "Version $VERSION"
			exit 0;
		;;
		"h")
            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi

			echo "$USAGE"
			exit 0;
		;;
        "p")
			arg1="$OPTARG"

            shift $((OPTIND - 1))
            if [[ $1 == -* ]]; then
                show_logs 1 "Option -p requires 3 arguments"
            fi
            arg2="$1"

            shift $((OPTIND - 1))
            if [[ $2 == -* ]]; then
                show_logs 1 "Option -p requires 3 arguments"
            fi
            arg3="$2"

            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi
		;;
        "m")
            arg1="$OPTARG"

            shift $((OPTIND - 1))
            if [[ $1 == -* ]]; then
                show_logs 1 "Option -p requires 3 arguments"
            fi
            arg2="$1"

            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi
        ;;
        "n")
            arg1="$OPTARG"

            shift $((OPTIND - 1))
            if [[ $1 == -* ]]; then
                show_logs 1 "Option -p requires 3 arguments"
            fi
            arg2="$1"

            shift $((OPTIND - 1))
            if [[ $2 == -* ]]; then
                show_logs 1 "Option -p requires 3 arguments"
            fi
            arg3="$2"

            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi
        ;;
        "u")
            arg1="$OPTARG"
            
            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi
        ;;
        "H")
            arg1="$OPTARG"
            
            if [ "$main_option" == "" ]; then
                main_option="$option"
            else
                show_logs 1 "mainOpt"
            fi
        ;;
		"?")
			echo "Unknown option $OPTARG"
			exit 0;
		;;
		":")
			echo "No argument value for option $OPTARG"
			exit 0;
		;;
		*)
			echo "Unknown error while processing options"
			exit 0;
		;;
	esac
done

shift $((OPTIND - 1))
# ------------------------------------------------------------------

# --- Locks --------------------------------------------------------
LOCK_FILE=/tmp/$SUBJECT.lock
if [ -f "$LOCK_FILE" ]; then
	echo "Script is already running"
	exit
fi

trap 'rm -f $LOCK_FILE' EXIT
touch "$LOCK_FILE"
# ------------------------------------------------------------------

# --- Body ---------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    show_logs 1 "root"
fi

case "$main_option" in
    "p")
        partition_disk "$arg1" "$arg2" "$arg3"
    ;;
    "m")
        mount_parts "$arg1" "$arg2"
    ;;
    "n")
        configure_network "$arg1" "$arg2" "$arg3"
    ;;
    "u")
        configure_user "$arg1"
    ;;
    "H")
        configure_host "$arg1"
    ;;
esac
# ------------------------------------------------------------------
