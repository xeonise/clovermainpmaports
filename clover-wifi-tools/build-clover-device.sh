#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PKG_SRC="$ROOT_DIR/device/testing/device-xiaomi-clover"
PMB_BIN="${PMB_BIN:-$HOME/.local/bin/pmbootstrap}"
PMB_ROOT_DIR="${PMB_ROOT_DIR:-$HOME/.local/var/pmbootstrap}"
PKG_DST="$PMB_ROOT_DIR/cache_git/pmaports/device/testing/device-xiaomi-clover"
LOG_FILE="$ROOT_DIR/qcacld-r4-device-r3-build.log"
STATUS_FILE="$ROOT_DIR/qcacld-r4-device-r3-build.status"
ARTIFACT="$ROOT_DIR/device-xiaomi-clover-11-r3.apk"

printf '%s\n' BUILD_RUNNING >"$STATUS_FILE"
: >"$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

fail()
{
	printf '%s\n' BUILD_FAILED >"$STATUS_FILE"
	exit 1
}

trap fail HUP INT TERM

test -x "$PMB_BIN" || {
	echo "pmbootstrap not found: $PMB_BIN"
	fail
}
test -d "$PKG_DST" || {
	echo "pmbootstrap pmaports cache not found: $PKG_DST"
	fail
}

files='
APKBUILD
80-xiaomi-clover-wlan-mac.rules
90-xiaomi-clover-wifi.conf
90-xiaomi-clover-qcacld.conf
90-xiaomi-clover-qcacld.modules
WCNSS_qcom_cfg.ini
clover-wifi-driver
deviceinfo
modules-initfs.clover
modules-initfs.cloverplus
wifi-macaddr.sh
xiaomi-clover-wlan-mac.service
xiaomi-clover-wlan-reset
'

for file_name in $files; do
	test -f "$PKG_SRC/$file_name" || {
		echo "missing package source: $PKG_SRC/$file_name"
		fail
	}
cp "$PKG_SRC/$file_name" "$PKG_DST/$file_name" || fail
done

"$PMB_BIN" --as-root checksum device-xiaomi-clover || fail

"$PMB_BIN" --as-root --details-to-stdout build --force \
	device-xiaomi-clover || fail

apk_path=$(find "$PMB_ROOT_DIR/packages" -type f \
	-name 'device-xiaomi-clover-11-r3.apk' -print | head -n 1)
test -n "$apk_path" || {
	echo "r3 APK was not found after a successful build"
	fail
}

cp "$apk_path" "$ARTIFACT" || fail
sha256sum "$ARTIFACT"
printf '%s\n' BUILD_OK >"$STATUS_FILE"
echo "artifact: $ARTIFACT"
