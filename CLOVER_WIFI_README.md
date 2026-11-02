# Xiaomi Clover postmarketOS Wi-Fi and USB OTG fixes

This repository carries the hardware-tested postmarketOS fixes for Wi-Fi and
USB OTG on Xiaomi Mi Pad 4 (`clover`) with Linux 6.19. Wi-Fi uses Xiaomi's
QCACLD 5.2 driver with WCN3990, while OTG uses PM660 Type-C role detection and
VBUS control. The repository is based on the upstream postmarketOS pmaports
tree.

Kernel `6.19.10-r7` / device `11-r4` add freeze hardening (IRQ-safe ICNSS
lookups, serialized recovery/teardown, BSSID statistics and quieter logging).
These changes require new cold-boot and endurance validation; the previous
hardware results apply to the r6 baseline. See `clover-wifi-notes/FIX.MD`
for deployment checks and the separate, still-unvalidated hardware watchdog.

The main source changes are in:

- `device/testing/linux-postmarketos-qcom-sdm660/` — ICNSS integration and the
  QCACLD Linux 6.19 port;
- `device/testing/device-xiaomi-clover/` — Clover boot selection, firmware
  configuration, NetworkManager defaults, MAC handling, and driver loading;
- `device/testing/firmware-xiaomi-clover/` — Clover WLAN firmware packaging.

`clover-wifi-notes/FIX.MD` documents the final implementation and validation.
`clover-wifi-tools/` contains the retained test and build helpers.

Compiled kernels, APKs, images, archives, object files, and build logs are
deliberately excluded through `.gitignore`. Rebuild them locally from the
package recipes instead of committing generated artifacts.

The hardware-tested state automatically joins the configured 5 GHz network,
supports scanning and Internet traffic, and accepts SSH immediately after a
cold boot. Clover's firmware-assisted roaming is restricted to the currently
connected band so a fixed 5 GHz profile does not move to 2.4 GHz after a scan.
USB OTG automatically switches between charging/device, disconnected, and
host roles. VBUS shuts down after adapter removal; a USB flash drive and a
wireless mouse/keyboard receiver were validated successfully.
