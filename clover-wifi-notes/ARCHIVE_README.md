# Xiaomi Mi Pad 4 Wi-Fi sources

The current QCACLD/ICNSS implementation is documented in `FIX.MD`.

The source packages are under:

- `device/testing/linux-postmarketos-qcom-sdm660/`
- `device/testing/device-xiaomi-clover/`
- `device/testing/firmware-xiaomi-clover/`

The kernel package contains exactly two Wi-Fi patches: one for Clover ICNSS
platform integration and one for the Xiaomi QCACLD Linux 6.19 port. Generated
APKs, kernel images, modules, archives, and logs are intentionally excluded
from Git and should be rebuilt from these package recipes.
