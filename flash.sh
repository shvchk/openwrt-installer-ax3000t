#! /usr/bin/env bash

set -euo pipefail

platform="mediatek/filogic"
device="xiaomi_mi-router-ax3000t"
dependencies=( "curl" "find" "fzf" "jq" "ping" "sed" "ssh" "tar" )


# text decoration utilities
# shellcheck disable=SC2015
{
  normal=$(tput sgr0 ||:)
  bold=$(tput bold ||:)
  info_msg="$(tput setab 33 && tput setaf 231 ||:)$bold" # blue bg, white text
  warn_msg="$(tput setab 220 && tput setaf 16 ||:)$bold" # yellow bg, black text
  err_msg="$(tput setab 160 && tput setaf 231 ||:)$bold" # red bg, white text
  accent="$(tput setab 238 && tput setaf 231 ||:)$bold" # gray bg, white text
}

_echo() {
  # unset formatting after output
  echo -e "$* $normal"
}

die() {
  _echo "${err_msg} $*"
  exit 1
}

ask() {
  while echo; do
    # `< /dev/tty` is required to be able to run via pipe: cat x.sh | bash
    read -rp "${warn_msg} $* ${accent} +/empty or - ${normal} " response < /dev/tty || { echo "No tty"; exit 1; }
    case "$response" in
      ""|"+") return 0 ;;
      "-") return 1 ;;
    esac
  done
}

check_dependencies() {
  for i in "$@"; do
    command -v "$i" &> /dev/null || {
      _echo >&2 "${accent} $i ${err_msg} required"
      exit 1
    }
  done
}

warn_flashing_wait() {
  _echo "\n${warn_msg} Do not power off your device!"
  _echo   "${warn_msg} Process will finish when LED stops blinking and turns solid blue"
  _echo "\n Waiting for router to finish flashing"
  _echo   " If it takes more than 3 minutes and LED on your router is solid blue,"
  _echo   " just reconnect Ethernet or replug the Ethernet cable"
}

wait_host() {
  until ping -c 1 -W 1 "$1" &> /dev/null; do
    echo -n ' .'
    sleep 3
  done
  echo
}

check_dependencies "${dependencies[@]}"

# TODO: Option to download images
#openwrt_dl_url="https://downloads.openwrt.org"
#openwrt_version="$(curl -sSL "$openwrt_dl_url/.versions.json" | jq -r '.stable_version')"
#openwrt_info="$(curl -sSL "$openwrt_dl_url/releases/$openwrt_version/targets/$platform/profiles.json" \
#                | jq -r --arg device "$device" '.profiles.[$device]')"


if ! (ls -- *initramfs-factory.ubi && ls -- *sysupgrade.bin) &> /dev/null; then
  _echo "\n${warn_msg} Download OpenWRT firmware"
  _echo "\n Please make sure that you have ${accent} initramfs-factory ${normal} and ${accent} sysupgrade ${normal} images"
  _echo " You can download images here: ${accent} https://firmware-selector.openwrt.org/?target=$platform&id=$device"
  _echo
  read -rsp "${warn_msg} Press Enter to continue ${normal}" < /dev/tty; echo
fi

stock_ip=192.168.31.1
openwrt_ip=192.168.1.1
docs_url="https://openwrt.org/inbox/toh/xiaomi/ax3000t"
_fzf="fzf +m --no-info --reverse --header-first --header"


_echo "\n${info_msg} Get SSH access"; echo

_echo " To get SSH access, you first need to get access to your router admin interface"
_echo " Please do initial router configuration at ${accent} http://$stock_ip ${normal} including setting a password"
_echo " then go to ${accent} http://$stock_ip ${normal} again, login and copy the URL of the page"
_echo " e.g. http://$stock_ip/cgi-bin/luci/;stok=167de48fc949c66d9befb78194bdd7e9/web/home"
_echo
read -rp "${warn_msg} Enter the admin page URL: ${normal} " admin_url < /dev/tty; echo

stok="$(sed -E 's/.*;stok=([^/]+).*/\1/' <<< "$admin_url")"

[ -z "$stok" ] && die "Bad stok"

rce_api_sel_header=$(printf "%s\n" "${warn_msg} Select API to exploit to get SSH access ${normal}" \
                                   " see ${docs_url}#api_rce_support_status")

rce_api="$($_fzf "$rce_api_sel_header" <<< $'xqsystem\nmisystem')"
api_url="http://${stock_ip}/cgi-bin/luci/;stok=${stok}/api"
serial_num=$(curl -sSL "$api_url/misystem" | jq -r '.hardware.sn' | tr / -)
backup_dir="backup/$serial_num"

[ -d "$backup_dir" ] || mkdir -p "$backup_dir"

case "$rce_api" in
  misystem)
    api_url="$api_url/misystem/arn_switch"
    api_pre="open=1&model=1&level="
    api_suf=""
    ;;

  xqsystem)
    api_url="$api_url/xqsystem/start_binding"
    api_pre="uid=1234&key=1234'"
    api_suf="'"
    ;;

  *) die "Unknown API" ;;
esac

api_queries=(
  "%0Anvram%20set%20ssh_en%3D1%0A"
  "%0Anvram%20commit%0A"
  "%0Ased%20-i%20's%2Fchannel%3D.*%2Fchannel%3D%22debug%22%2Fg'%20%2Fetc%2Finit.d%2Fdropbear%0A"
  "%0A%2Fetc%2Finit.d%2Fdropbear%20start%0A"
  "%0Apasswd%20-d%20root%0A"
)

for i in "${!api_queries[@]}"; do
  [[ $i -gt 0 ]] && sleep 1
  curl -X POST "$api_url" -d "${api_pre}${api_queries[$i]}${api_suf}"
done


_echo "\n\n${info_msg} Backup"; echo

ssh_cmd="ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa root@$stock_ip -- "
firmware="$($ssh_cmd "sed -E 's/.*firmware=(\S).*/\1/' /proc/cmdline")"

partitions=(
  [1]=BL2
  [2]=Nvram
  [3]=Bdata
  [4]=Factory
  [5]=FIP
  [8]=ubi
  [12]=KF
)

for i in "${!partitions[@]}"; do
  _echo "${accent} ${partitions[$i]}"
  $ssh_cmd nanddump /dev/mtd$i > "${backup_dir}/${partitions[$i]}.bin"
done

while ping -c 3 -W 1 $openwrt_ip &> /dev/null; do
  _echo "\n${warn_msg} Your router will use IP $openwrt_ip"
  _echo   "${warn_msg} However, some device on this network already uses IP $openwrt_ip"
  _echo   "${warn_msg} This could lead to flashing the wrong device and potentially bricking it"
  _echo "\n${warn_msg} To fix this, you could either disconnect from this network,"
  _echo   "${warn_msg} or disconnect device with IP $openwrt_ip from it"
  _echo
  read -rsp "${warn_msg} Press Enter to continue ${normal}" < /dev/tty; echo
done


_echo "\n${info_msg} Flash initramfs image"; echo

initramfs_img="$(find -- *initramfs-factory.ubi | $_fzf "${warn_msg} Select initramfs image ${normal}")"

ubi_partition=/dev/mtd9
rootfs_partition=1

if (( firmware == 1 )); then
  ubi_partition=/dev/mtd8
  rootfs_partition=0
fi

tar -cf - "$initramfs_img" | $ssh_cmd tar -C /tmp -xf -
$ssh_cmd ubiformat $ubi_partition -y -f "'/tmp/$initramfs_img'"
$ssh_cmd nvram set boot_wait=on
$ssh_cmd nvram set uart_en=1
$ssh_cmd nvram set flag_boot_rootfs=$rootfs_partition
$ssh_cmd nvram set flag_last_success=$rootfs_partition
$ssh_cmd nvram set flag_boot_success=1
$ssh_cmd nvram set flag_try_sys1_failed=0
$ssh_cmd nvram set flag_try_sys2_failed=0
$ssh_cmd nvram commit
$ssh_cmd reboot

warn_flashing_wait
wait_host $openwrt_ip


_echo "\n${info_msg} Flash sysupgrade image"; echo

ssh_cmd="ssh -o StrictHostKeyChecking=no root@$openwrt_ip -- "
sysupgrade_img="$(find -- *sysupgrade.bin | $_fzf "${warn_msg} Select sysupgrade image ${normal}")"

tar -cf - "$sysupgrade_img" | $ssh_cmd tar -C /tmp -xf -
$ssh_cmd sysupgrade -n "'/tmp/$sysupgrade_img'" || :

# Above command returns error, but firmware seems to be installed correctly:
# Command failed: ubus call system sysupgrade { "prefix": "\/tmp\/root", "path": "\/tmp\/openwrt-24.10.1-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin", "command": "\/lib\/upgrade\/do_stage2", "options": { "save_partitions": 1 } } (Connection failed)

warn_flashing_wait
sleep 40
wait_host $openwrt_ip


_echo "\n${info_msg} Installation complete"; echo

_echo " You can configure your router: ${accent} http://$openwrt_ip"
_echo " see also ${accent} https://openwrt.org/docs/guide-user/base-system/start"
