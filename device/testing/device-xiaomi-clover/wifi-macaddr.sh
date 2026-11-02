#!/bin/sh
set -eu

PERSIST=${PERSIST:-/run/msm-firmware-loader/mnt/persist}
IFACE=${IFACE:-wlan0}
SYSFS_NET=${SYSFS_NET:-/sys/class/net}

log() {
	echo "$@" | logger -t "xiaomi-clover-wifi-mac"
}

is_valid_mac() {
	case "$1" in
		00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|"")
			return 1
			;;
	esac

	echo "$1" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1

	first_octet=${1%%:*}
	first_octet=$((0x$first_octet))

	# Reject multicast and locally administered addresses. The factory
	# address must be globally administered.
	[ $((first_octet & 1)) -eq 0 ] && [ $((first_octet & 2)) -eq 0 ]
}

format_mac_hex() {
	echo "$1" | sed 's/../&:/g; s/:$//' | tr 'A-F' 'a-f'
}

read_mac() {
	if [ -r "$PERSIST/wlan_bt/wlan.mac" ]; then
		mac=$(tr -d '\r\n[:space:]' < "$PERSIST/wlan_bt/wlan.mac" | tr 'A-F' 'a-f')
		if is_valid_mac "$mac"; then
			echo "$mac"
			return 0
		fi
	fi

	if [ -r "$PERSIST/wlan_mac.clover" ]; then
		mac=$(sed -n 's/^Intf0MacAddress=\([0-9A-Fa-f]\{12\}\)$/\1/p' \
			"$PERSIST/wlan_mac.clover" | head -n1)
		if [ -n "$mac" ]; then
			mac=$(format_mac_hex "$mac")
			if is_valid_mac "$mac"; then
				echo "$mac"
				return 0
			fi
		fi
	fi

	if [ -r "$PERSIST/wlan_mac.bin" ]; then
		mac=$(od -An -N6 -tx1 "$PERSIST/wlan_mac.bin" | tr -d ' \n')
		if [ -n "$mac" ]; then
			mac=$(format_mac_hex "$mac")
			if is_valid_mac "$mac"; then
				echo "$mac"
				return 0
			fi
		fi
	fi

	return 1
}

timeout=0
while ! mac=$(read_mac); do
	if [ "$timeout" -ge 10 ]; then
		log "no valid factory WLAN MAC found in persist"
		exit 1
	fi

	sleep 1
	timeout=$((timeout + 1))
done

current=$(cat "$SYSFS_NET/$IFACE/address" 2>/dev/null || true)
if [ "$current" = "$mac" ]; then
	log "$IFACE already uses factory MAC $mac"
	exit 0
fi

was_up=0
# Operational state is DOWN while unassociated even when IFF_UP is set.
# Preserve the administrative flag, not the presence of carrier.
flags=$(cat "$SYSFS_NET/$IFACE/flags")
if [ $((flags & 1)) -ne 0 ]; then
	was_up=1
fi

ip link set dev "$IFACE" down
ip link set dev "$IFACE" address "$mac"

if [ "$was_up" -eq 1 ]; then
	ip link set dev "$IFACE" up
fi

log "set $IFACE factory MAC to $mac"
