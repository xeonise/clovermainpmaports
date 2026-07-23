#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DRIVER="$ROOT_DIR/device/testing/device-xiaomi-clover/clover-wifi-driver"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT HUP INT TERM

mkdir -p "$test_dir/bin" "$test_dir/sys" "$test_dir/drivers/icnss-clover" \
	"$test_dir/remoteproc/remoteproc0" "$test_dir/run"
ln -s "$test_dir/drivers/icnss-clover" "$test_dir/sys/driver"
printf 'inactive\n' >"$test_dir/sys/recovery_state"
printf '0\n' >"$test_dir/sys/recovery_generation"
printf '0\n' >"$test_dir/sys/last_error"
printf 'hlos\n' >"$test_dir/sys/msa_owner"
printf '4080000.remoteproc\n' >"$test_dir/remoteproc/remoteproc0/name"
printf 'running\n' >"$test_dir/remoteproc/remoteproc0/state"
: >"$test_dir/modules"
printf 'historical firmware crashed\n' >"$test_dir/dmesg"
: >"$test_dir/qcom-icnss-clover.ko"
: >"$test_dir/wlan.ko"
: >"$test_dir/previous-wlan.ko"

cat >"$test_dir/bin/uname" <<'EOF'
#!/bin/sh
printf '6.19.10-sdm660\n'
EOF
cat >"$test_dir/bin/id" <<'EOF'
#!/bin/sh
printf '0\n'
EOF
cat >"$test_dir/bin/dmesg" <<'EOF'
#!/bin/sh
cat "$TEST_ROOT/dmesg"
EOF
cat >"$test_dir/bin/modinfo" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -k ]; then exit 0; fi
if [ "${1:-}" = -n ]; then printf '%s/previous-wlan.ko\n' "$TEST_ROOT"; exit 0; fi
if [ "${1:-}" = -F ]; then
	case "$2" in
	vermagic) printf '6.19.10-sdm660 SMP preempt mod_unload aarch64\n' ;;
	name)
		case "$3" in *qcom-icnss-clover.ko) printf 'qcom_icnss_clover\n' ;; *) printf 'wlan\n' ;; esac
		;;
	depends) printf 'cfg80211,qcom_icnss_clover\n' ;;
	esac
	exit 0
fi
exit 0
EOF
cat >"$test_dir/bin/modprobe" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$test_dir/bin/insmod" <<'EOF'
#!/bin/sh
case "$1" in
*qcom-icnss-clover.ko)
	printf 'qcom_icnss_clover 1 0 - Live 0x0\n' >>"$TEST_ROOT/modules"
	printf 'firmware-ready\n' >"$TEST_ROOT/sys/recovery_state"
	printf 'wlan\n' >"$TEST_ROOT/sys/msa_owner"
	;;
*wlan.ko)
	printf 'wlan 1 0 - Live 0x0\n' >>"$TEST_ROOT/modules"
	printf 'ready\n' >"$TEST_ROOT/sys/recovery_state"
	;;
esac
EOF
cat >"$test_dir/bin/ip" <<'EOF'
#!/bin/sh
case "$*" in
*'link show wlan0'*) [ "$(cat "$TEST_ROOT/sys/recovery_state")" = ready ] ;;
*'link set wlan0 down'*) exit 0 ;;
*'-4 addr show dev wlan0'*) printf 'inet 192.0.2.2/24\n' ;;
*'route get 1.1.1.1'*) printf '1.1.1.1 dev wlan0\n' ;;
*) exit 0 ;;
esac
EOF
cat >"$test_dir/bin/iw" <<'EOF'
#!/bin/sh
printf 'Connected to redacted\n'
EOF
cat >"$test_dir/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$test_dir/bin/sleep" <<'EOF'
#!/bin/sh
for state in "$TEST_ROOT"/remoteproc/remoteproc*/state; do
	[ -f "$state" ] || continue
	case "$(cat "$state")" in
	stop) printf 'offline\n' >"$state" ;;
	start) printf 'running\n' >"$state" ;;
	esac
done
exit 0
EOF
chmod 755 "$test_dir/bin"/*

run_driver()
{
	TEST_ROOT="$test_dir" \
	PATH="$test_dir/bin:$PATH" \
	CLOVER_WIFI_DEVICE="$test_dir/sys" \
	CLOVER_REMOTEPROC_CLASS="$test_dir/remoteproc" \
	CLOVER_PROC_MODULES="$test_dir/modules" \
	CLOVER_RUN_DIR="$test_dir/run" \
	CLOVER_QCACLD_CONF="$test_dir/qcacld.conf" \
	CLOVER_QCACLD_LOAD="$test_dir/qcacld.load" \
	sh "$DRIVER" "$@"
}

run_driver try-qcacld-modules \
	"$test_dir/qcom-icnss-clover.ko" "$test_dir/wlan.ko"
[ "$(cat "$test_dir/remoteproc/remoteproc0/state")" = running ]
status=$(run_driver status)
printf '%s\n' "$status" | grep -q '^platform_driver=icnss-clover$'
printf '%s\n' "$status" | grep -q '^icnss_state=ready$'

milestones=$(run_driver qcacld-milestones)
printf '%s\n' "$milestones" | grep -q '^firmware_faults_since_attempt=0$'
printf 'WLAN RT: test assert\n' >>"$test_dir/dmesg"
milestones=$(run_driver qcacld-milestones)
printf '%s\n' "$milestones" | grep -q '^firmware_faults_since_attempt=1$'

printf 'clover-wifi-driver tests passed\n'
