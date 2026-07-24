#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PKG_SRC="$ROOT_DIR/device/testing/linux-postmarketos-qcom-sdm660"
PMB_BIN="${PMB_BIN:-$HOME/.local/bin/pmbootstrap}"
PMB_ROOT_DIR="${PMB_ROOT_DIR:-$HOME/.local/var/pmbootstrap}"
PKG_DST="$PMB_ROOT_DIR/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sdm660"
LOG_FILE="$ROOT_DIR/qcacld-r5-build.log"
STATUS_FILE="$ROOT_DIR/qcacld-r5-build.status"
ARTIFACT="$ROOT_DIR/linux-postmarketos-qcom-sdm660-6.19.10-r5.apk"

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
config-postmarketos-qcom-sdm660.aarch64
0001-clover-icnss-platform-integration.patch
0002-xiaomi-qcacld-linux-6.19-port.patch
0003-clover-usb-otg.patch
'

for file_name in $files; do
	test -f "$PKG_SRC/$file_name" || {
		echo "missing package source: $PKG_SRC/$file_name"
		fail
	}
	cp "$PKG_SRC/$file_name" "$PKG_DST/$file_name" || fail
done

"$PMB_BIN" --as-root checksum linux-postmarketos-qcom-sdm660 || fail

"$PMB_BIN" --as-root --details-to-stdout build --force \
	linux-postmarketos-qcom-sdm660 || fail

apk_path=$(find "$PMB_ROOT_DIR/packages" -type f \
	-name 'linux-postmarketos-qcom-sdm660-6.19.10-r5.apk' \
	-print | head -n 1)
test -n "$apk_path" || {
	echo "r5 APK was not found after a successful build"
	fail
}

cp "$apk_path" "$ARTIFACT" || fail
tar -xOf "$ARTIFACT" \
	'lib/modules/6.19.10-sdm660/modules.dep' | \
	grep -F \
		'kernel/drivers/staging/qcacld-3.0/wlan.ko.zst: kernel/drivers/staging/qcom_icnss_clover/qcom-icnss-clover.ko.zst' \
	>/dev/null || {
	echo "modules.dep does not link wlan to qcom-icnss-clover"
	fail
}

for module_path in \
	'lib/modules/6.19.10-sdm660/kernel/drivers/power/supply/qcom_smbx.ko.zst' \
	'lib/modules/6.19.10-sdm660/kernel/drivers/usb/common/usb-conn-gpio.ko.zst'
do
	tar --warning=no-unknown-keyword -tf "$ARTIFACT" 2>/dev/null | \
		grep -Fx "$module_path" >/dev/null || {
		echo "missing OTG module: $module_path"
		fail
	}
done

dtb_path='boot/dtbs/6.19.10-sdm660/qcom/sda660-xiaomi-clover.dtb'
dtb_file=$(mktemp)
tar --warning=no-unknown-keyword -xOf "$ARTIFACT" "$dtb_path" >"$dtb_file" || {
	rm -f "$dtb_file"
	echo "missing Clover DTB"
	fail
}
for property in usb-role-switch role-switch-default-mode id-gpios usb-vbus-regulator
do
	strings "$dtb_file" | grep -Fx "$property" >/dev/null || {
		rm -f "$dtb_file"
		echo "Clover DTB is missing OTG property: $property"
		fail
	}
done
rm -f "$dtb_file"
sha256sum "$ARTIFACT"
printf '%s\n' BUILD_OK >"$STATUS_FILE"
echo "artifact: $ARTIFACT"
