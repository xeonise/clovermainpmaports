# Xiaomi Mi Pad 4 (clover) QCACLD Wi-Fi fix

This document describes only the final QCACLD/ICNSS implementation used for
Wi-Fi on Xiaomi Mi Pad 4. It intentionally omits the obsolete development and
driver-experiment history.

## Current implementation

- Kernel package: `linux-postmarketos-qcom-sdm660` `6.19.10-r4`.
- Xiaomi WLAN source commit:
  `728ac0be7512264ecdc3bf885a19c581c6890c17`.
- QCACLD is the default Wi-Fi driver for Clover.
- The tested installation does not load the ath10k driver.
- `wlan.ko.zst` depends on `qcom-icnss-clover.ko.zst`.

The kernel package carries exactly two Wi-Fi patches:

1. `0001-clover-icnss-platform-integration.patch`
   - adds the Clover device-tree integration;
   - provides the ICNSS compatibility ABI and platform backend;
   - integrates the WLFW QMI service;
   - handles board data, calibration, MSA setup, recovery, and module wiring.
2. `0002-xiaomi-qcacld-linux-6.19-port.patch`
   - ports Xiaomi QCACLD/QDF to Linux 6.19;
   - adapts timers, refcounts, cfg80211, netdev, crypto, SMMU, and DMA APIs;
   - includes the runtime fixes required on Clover.

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

## Hardware validation

Final validation was performed on a Xiaomi Mi Pad 4 running:

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
| `device-xiaomi-clover-11-r2.apk` | `79ce57cb3e468cf17d194d134150f5a640023a164ede6e8e547e5d657e10fed6` |
| `device-xiaomi-clover-11-r3.apk` | `7cee461916be8b35e72939864c4d1310d3a738dc4a273d8c958094f88ebb0655` |
| `firmware-xiaomi-clover-1-r1.apk` | `3217b61d890209001dd51722efa259a7676f2c9888bd76c82cec66466fb51204` |

The `r2` device package is the hardware-tested functional package. Device
package `r3` changes comments only and has the same runtime configuration.

## Known limitations

- Hot module replacement is not reliable. Unloading ICNSS and QCACLD and then
  loading them again during the same boot may fail to remap Copy Engine IRQs
  with `-ENXIO`. Test kernel or module changes after a reboot.
- AP teardown while clients remain associated has not received complete
  stress coverage. Do not treat the current validation as exhaustive AP-mode
  testing.
