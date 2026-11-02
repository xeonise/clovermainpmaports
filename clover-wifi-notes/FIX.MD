# Xiaomi Mi Pad 4 (clover) Wi-Fi and USB OTG fixes

This document describes QCACLD/ICNSS Wi-Fi and PM660 Type-C USB OTG on
Xiaomi Mi Pad 4. The r6 baseline below was hardware-tested. The r7 freeze
hardening is a new revision and needs a fresh cold-boot and endurance test;
earlier hardware results do not validate the new revision.

## Current implementation

- Kernel package: `linux-postmarketos-qcom-sdm660` `6.19.10-r7`.
- Device package: `device-xiaomi-clover` `11-r4`.
- Xiaomi WLAN source commit:
  `728ac0be7512264ecdc3bf885a19c581c6890c17`.
- Firmware package: `firmware-xiaomi-clover` `2-r1`, based on the current
  `setotau` source commit `c850ad5d11315e690df8244670241e3d5a8436dc`.
- The firmware package retains the QCACLD `bdwlan.bin` extraction and includes
  `goodix_9110_cfg.bin` in the initramfs file list.
- QCACLD is the default Wi-Fi driver for Clover.
- The tested installation does not load the ath10k driver.
- `wlan.ko.zst` depends on `qcom-icnss-clover.ko.zst`.
- USB OTG uses the PM660 Type-C state machine, DWC3 role switching, and the
  PM660 5 V VBUS boost regulator.

The kernel package carries these Wi-Fi patches (0003 is the existing OTG fix):

1. `0001-clover-icnss-platform-integration.patch`
   - adds the Clover device-tree integration;
   - provides the ICNSS compatibility ABI and platform backend;
   - integrates the WLFW QMI service;
   - handles board data, calibration, MSA setup, recovery, and module wiring.
2. `0002-xiaomi-qcacld-linux-6.19-port.patch`
   - ports Xiaomi QCACLD/QDF to Linux 6.19;
   - adapts timers, refcounts, cfg80211, netdev, crypto, SMMU, and DMA APIs;
    - includes the runtime fixes required on Clover.
3. `0004-clover-icnss-irq-safe-lookup-and-lifecycle.patch`
   - removes sleeping lookups from CE hard IRQs and noirq PM callbacks;
   - serializes client callbacks, unregister, firmware work and modem SSR;
   - fixes power voting, teardown order, duplicate service discovery and
     unsafe MSA fallback/ownership assumptions;
   - removes the unit-specific MAC from the shared device tree.
4. `0005-qcacld-dump-station-report-bssid.patch`
   - returns the associated AP's BSSID, rather than the tablet's own MAC.
5. `0006-qcacld-production-assertions-and-build-checks.patch`
   - decouples vendor BUG assertions from CONFIG_SLUB_DEBUG;
   - checks register availability before CE interrupt/tasklet MMIO;
   - keeps incompatible pointer types fatal and fixes current-clang builds.

## r7 freeze investigation and hardening

The last recorded boot stopped logging at 2026-11-02 11:39:14 EET after
about 18 hours. No panic or firmware crash was preserved. That does **not**
prove a particular cause: journald may lose buffered entries, CPU0 also
handles storage, and a long power-button reset need not retain ramoops RAM.
An earlier boot captured a CPU5 hard lockup after a GPU debugfs read, but
that is not evidence that the most recent freeze had the same cause.

The ICNSS lookup bug is concrete: the CE hard IRQ handler calls
`pld_get_ce_id()` -> `icnss_get_ce_id()` -> `icnss_from_dev()`, which used
to take `icnss_global_lock`, a mutex. The new lookup uses acquire/release
publication without sleeping. The module dependency pins the backend while
qcacld is loaded; manual sysfs unbind is suppressed, and client removal and
`free_irq()` finish before the backend pointer is cleared. This is a strong
freeze candidate, not a demonstrated explanation of the last incident.

Firmware callbacks run on the ordered workqueue and are serialized against
client unregister. Modem BEFORE_SHUTDOWN now reports FW_DOWN before WLFW's
late QMI deletion callback. CE dispatch tests target availability before the
MMIO write that disables a CE interrupt; a queued tasklet also checks it
before servicing the engine. These reduce the shutdown-access window; SSR,
suspend/resume and firmware recovery still need hardware stress testing.
Power-on is voted before WLFW setup, and failure paths keep power and MSA
ownership intact while a client is probed. Missing reserved MSA memory now
fails probe rather than passing a DMA-IOMMU IOVA to SCM as a physical address.
SCM `-EINVAL` is no longer assumed to mean successful ownership transfer.

The device package also:

- sets explicit FATAL/ERROR/WARN trace masks (`14`) and disables unsolicited
  firmware diagnostic multicast when no cnss_diag listener is present;
- fixes `cfd_trace_enable_txrx` to `qdf_trace_enable_txrx` and removes duplicate
  legacy INI keys, preserving the **first** entry, which `find_cfg_item()` uses;
  `65535` is an unset sentinel, not an explicit all-level override;
- removes `ignore_loglevel` without removing kernel messages from pstore;
- preserves administrative IFF_UP during factory MAC setup, even without carrier;
- leaves the old NetworkManager reset dispatcher as a no-op so upgrades replace
  the unsafe forced-down/up handler, including on intentional rfkill/suspend;
- refuses driver handoff when the previous modules cannot be unloaded;
- sets panic-on-oops and panic-on-soft/hard-lockup, with a 120-second reboot
  delay, and reduces journald's sync interval to 5 seconds. This cannot recover
  a SoC-wide bus stall that prevents the watchdog detectors from running.

### Hardware watchdog and deployment

The running tablet has ramoops at `0x9fe00000`, but no `/dev/watchdog*` or
watchdog platform device. `CONFIG_QCOM_WDT=m` alone is not sufficient.
This revision does **not** invent a watchdog DT register address or enable
systemd's hardware watchdog on unverified hardware. A hardware watchdog node
and reset/pretimeout behaviour must be validated separately. Only after that
should an administrator enable `RuntimeWatchdogSec=30s` in a local systemd
manager drop-in. Without that validation, a total freeze can still need a
manual reset.

Rebuild the kernel and device package, install them together and cold-boot
with local/USB recovery access. Do not replace these modules over the sole
Wi-Fi SSH connection, and do not read powered-down GPU debugfs register dumps.
Check the following after boot:

```sh
uname -a
sudo clover-wifi-driver qcacld-milestones
iw dev wlan0 link
iw dev wlan0 station dump
sysctl kernel.panic kernel.panic_on_oops kernel.softlockup_panic kernel.hardlockup_panic
sudo journalctl -b -k
sudo ls -l /sys/fs/pstore /var/lib/systemd/pstore
```

In STA mode, `station dump` must name the connected AP, not wlan0's own MAC.
Validate cold boot, immediate SSH, scanning, reconnect, rfkill, suspend/resume,
and at least a 24-48 hour idle-while-charging run. Save the previous boot's
journal and archived pstore on the first reboot after any failure. The original
skcipher allocation-failure handling and idle-shutdown design are not claimed
as root causes or silently rewritten by this revision; they remain separate
follow-up work if failures point there.

### Local regression checks

```sh
sh clover-wifi-tools/test-clover-wifi-driver.sh
sh clover-wifi-tools/test-clover-wifi-mac.sh
git diff --check
```

Patch application, source checksums and compiler checks are necessary, but do
not substitute for the hardware endurance and recovery tests above.

## Functional fixes

### Linux 6.19 compatibility

The QCACLD/QDF code uses the current kernel timer, reference-counting,
cfg80211, netdev, crypto, SMMU, and DMA interfaces. The receive and firmware
integration paths compile and link as separate QCACLD and ICNSS modules.

### ICNSS and firmware startup

The ICNSS backend implements the interfaces required by QCACLD and connects
the driver to WLFW. It covers firmware startup, board-data selection,
calibration, MSA allocation, and recovery. The RTNL lock remains held until
HDD initialization is complete so NetworkManager cannot act on a partially
initialized interface.

### 32-bit HTT DMA

HTT uses DMA addresses in the form expected by this WCN3990 firmware. This
prevents invalid address handling in data-path operation.

### Crypto teardown

The skcipher path uses allocated bounce storage rather than a scatterlist
backed by invalid static or module memory. This keeps the buffer valid for the
entire crypto operation and prevents teardown-time memory corruption.

### Receive path and boot-time SSH

QCACLD uses a dummy NAPI object in its Rx-thread mode. `GRO_NORMAL` packets
could remain on that object's `rx_list`: the tablet had working Internet after
an automatic boot connection, but new inbound SSH connections did not reach
the host until Wi-Fi was manually reconnected.

The final receive callback keeps `napi_gro_flush()` for aggregated packets,
then sends the remaining `rx_list` through the exported
`netif_receive_skb_list()` API and resets the queued-packet count. Packets are
therefore delivered immediately after the automatic boot connection.

### Stable 5 GHz roaming

The Clover QCACLD configuration sets:

```ini
gRoamIntraBand=1
```

This restricts firmware roaming to the current frequency band. A scan can no
longer move the connection from 5 GHz to a 2.4 GHz BSSID, while roaming
between 5 GHz access points remains available. The trade-off is that the
driver will not automatically fall back from 5 GHz to 2.4 GHz when the 5 GHz
signal becomes weak.

## USB OTG fix

Kernel `6.19.10-r5` was the first installed OTG test. Its VBUS boost path
worked, and a `13fe:4300 USB DISK 2.0` device enumerated briefly, but its role
detection was wrong. GPIO 58 is a Type-C/CC signal on Clover, not a micro-USB
ID signal: an empty port entered host mode with VBUS enabled, while inserting
the OTG adapter switched back to device mode. Repeated role changes ended in a
hard reset. There was no pstore panic record and the previous journal ended
without a normal shutdown, consistent with a power reset rather than a kernel
oops.

Kernel `6.19.10-r6` removes that GPIO workaround and uses PM660's Type-C state
machine instead. The `type-c-change` IRQ reads `TYPE_C_STATUS_4`: no CC attach
selects no role, attached DFP selects host, and attached UFP selects device.
The PM660 driver enables its 5 V boost only after a Type-C sink has been
negotiated, then starts DWC3 host mode. On removal it stops the host before
disabling VBUS. Current is ramped from 250 mA to 1.5 A during soft start.

The complete r6 build, module dependency check, and decompiled DTB inspection
passed. It was then installed and cold-booted on the tablet. Live hardware
validation passed the complete role cycle:

- a charging cable selected device mode with VBUS output disabled;
- removing it produced the PM660 no-CC state and stopped USB host mode;
- an empty OTG adapter produced `TYPE_C_STATUS_4 = 0x91`, selected host mode,
  enabled VBUS, and started both xHCI buses;
- a `13fe:4300 Wilk USB DISK 2.0` enumerated as `/dev/sda` with both partitions;
- a wireless USB receiver enumerated successfully and both its mouse and
  keyboard worked;
- removing the flash drive and adapter stopped xHCI and disabled VBUS;
- no hard reset, kernel oops, call trace, Type-C error, or OTG soft-start error
  occurred.

When PM660 reports no attached cable, the driver records the logical role as
`none`. The DWC3 sysfs role reads `device` because
`role-switch-default-mode = "peripheral"`; this is the intended safe fallback
and VBUS remains disabled.

## Baseline hardware validation (before r7)

Baseline validation was performed on a Xiaomi Mi Pad 4 running:

```text
6.19.10-sdm660 #5-aarch64
```

Cold-boot results:

- QCACLD and ICNSS loaded automatically.
- NetworkManager automatically joined the 5 GHz network.
- Connected BSSID: `A6:A4:6B:1F:62:48` at `5180 MHz`.
- Tablet address: `192.168.0.31`.
- The first Wi-Fi SSH connection worked without reconnecting Wi-Fi.
- Five additional independent SSH logins passed.
- Internet ping testing completed with 0% packet loss.
- After a forced `nmcli dev wifi rescan` and a 40-second wait, the tablet
  remained on the same 5 GHz BSSID and frequency.
- Three additional SSH logins after the scan passed.
- No firmware assertion, SMMU fault, kernel oops, or call trace appeared in
  the final cold-boot tests.
- The `clover-wifi-driver` test suite passed.
- Full kernel and device-package builds passed.

## Verified package artifacts

| Package | SHA-256 |
| --- | --- |
| `linux-postmarketos-qcom-sdm660-6.19.10-r4.apk` | `4744524782b553287159d72d1eec76d1c0c48b434dfd2d7edb2f7381f88729ac` |
| `linux-postmarketos-qcom-sdm660-6.19.10-r5.apk` (unsafe GPIO OTG test) | `e2f285516b16403a881e7712a86ecdd0a5cee4dd2eec8afd23ec89d28f3a6ad0` |
| `linux-postmarketos-qcom-sdm660-6.19.10-r6.apk` (hardware-tested PM660 Type-C OTG build) | `2e186732e4296b658c6254be0c1aa4fe0595cc8c1b0ce293fbd1cca290d04738` |
| `device-xiaomi-clover-11-r2.apk` | `79ce57cb3e468cf17d194d134150f5a640023a164ede6e8e547e5d657e10fed6` |
| `device-xiaomi-clover-11-r3.apk` | `e7cf0a25871c05250743894c7e1b9b64f15bfdc5eb7351fb406f8e6581301564` |
| `firmware-xiaomi-clover-2-r1.apk` | `a53211d94d055e51528697002f8fa9d8e9231c49e5ec96640a98ae6c65d05745` |

The `r2` device package is the hardware-tested functional package. Device
package `r3` changes comments and package metadata only and has the same
runtime configuration. Firmware `2-r1` passed checksum, package-build, APK
content, installation, and cold-boot hardware validation. Its `board-2.bin`
payload is byte-identical to the previous hardware-tested revision.

## Known limitations

- Hot module replacement is not reliable. Unloading ICNSS and QCACLD and then
  loading them again during the same boot may fail to remap Copy Engine IRQs
  with `-ENXIO`. Test kernel or module changes after a reboot.
- AP teardown while clients remain associated has not received complete
  stress coverage. Do not treat the current validation as exhaustive AP-mode
  testing.
