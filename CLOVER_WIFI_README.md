# Xiaomi Clover QCACLD Wi-Fi port

This repository carries the postmarketOS package changes used to run Xiaomi's
QCACLD 5.2 driver with WCN3990 on Xiaomi Mi Pad 4 (`clover`) and Linux 6.19.
It is based on the upstream postmarketOS pmaports tree.

The main source changes are in:

- `device/testing/linux-postmarketos-qcom-sdm660/` — ICNSS integration and the
  QCACLD Linux 6.19 port;
- `device/testing/device-xiaomi-clover/` — Clover boot selection, firmware
  configuration, NetworkManager defaults, MAC handling, and driver loading;
- `device/testing/firmware-xiaomi-clover/` — Clover WLAN firmware packaging.

`clover-wifi-notes/FIX.MD` contains the development and hardware-test handoff.
`clover-wifi-tools/` contains the retained test and build helpers.

Compiled kernels, APKs, images, archives, object files, and build logs are
deliberately excluded through `.gitignore`. Rebuild them locally from the
package recipes instead of committing generated artifacts.

The hardware-tested state automatically joins the configured 5 GHz network,
supports scanning and Internet traffic, and accepts SSH immediately after a
cold boot. Clover's firmware-assisted roaming is restricted to the currently
connected band so a fixed 5 GHz profile does not move to 2.4 GHz after a scan.
