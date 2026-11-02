#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEVICE="$ROOT_DIR/device/testing/device-xiaomi-clover"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT HUP INT TERM

mkdir -p "$test_dir/bin" "$test_dir/persist/wlan_bt" "$test_dir/net/wlan0"
cat >"$test_dir/bin/ip" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$TEST_ROOT/ip.log"
EOF
cat >"$test_dir/bin/logger" <<'EOF'
#!/bin/sh
cat >/dev/null
EOF
chmod 755 "$test_dir/bin"/*
export TEST_ROOT="$test_dir"
export PATH="$test_dir/bin:$PATH"
export PERSIST="$test_dir/persist"
export SYSFS_NET="$test_dir/net"
export IFACE=wlan0

factory=00:11:22:33:44:55
printf '%s\n' "$factory" >"$PERSIST/wlan_bt/wlan.mac"

# IFF_UP without carrier: preserve administrative UP, not "state UP".
printf '02:00:00:00:00:01\n' >"$SYSFS_NET/wlan0/address"
printf '0x1003\n' >"$SYSFS_NET/wlan0/flags"
sh "$DEVICE/wifi-macaddr.sh"
printf 'link set dev wlan0 down\nlink set dev wlan0 address %s\nlink set dev wlan0 up\n' \
	"$factory" >"$test_dir/expected"
cmp "$test_dir/expected" "$test_dir/ip.log"

# An administratively DOWN interface must stay down.
: >"$test_dir/ip.log"
printf '0x1002\n' >"$SYSFS_NET/wlan0/flags"
sh "$DEVICE/wifi-macaddr.sh"
printf 'link set dev wlan0 down\nlink set dev wlan0 address %s\n' \
	"$factory" >"$test_dir/expected"
cmp "$test_dir/expected" "$test_dir/ip.log"

# Already-correct factory MAC must not interrupt a running link.
: >"$test_dir/ip.log"
printf '%s\n' "$factory" >"$SYSFS_NET/wlan0/address"
sh "$DEVICE/wifi-macaddr.sh"
[ ! -s "$test_dir/ip.log" ]

# Dispatcher events must not resurrect a link during intentional teardown.
for action in down up pre-down; do
	sh "$DEVICE/xiaomi-clover-wlan-reset" wlan0 "$action"
done
[ ! -s "$test_dir/ip.log" ]
printf 'clover Wi-Fi MAC and dispatcher tests passed\n'
