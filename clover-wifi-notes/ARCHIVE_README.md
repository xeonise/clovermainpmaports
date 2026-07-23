# Mi Pad 4 Wi-Fi workspace

Start with the final validation section in `FIX.MD`. The PR source is under
`pmaports-clover-rootfix/` and contains the current kernel, Clover device, and
firmware packages. The kernel package uses only the two squashed ICNSS and
QCACLD patches.

The current validated artifacts are:

- `linux-postmarketos-qcom-sdm660-6.19.10-r2.apk`
- `device-xiaomi-clover-11-r1.apk`
- `device-xiaomi-clover-kernel-clover-11-r1.apk`
- `firmware-xiaomi-clover-1-r1.apk`

Kernel r2 fixes the QCACLD skcipher compatibility wrapper so AP teardown can
encrypt static module data through a linear bounce buffer instead of passing
the module address directly to a scatterlist. See the final r2 section in
`FIX.MD` for the failure signature and hardware validation status.

`tests/` contains the retained driver-helper test. The build wrappers and logs
remain for reproduction and verification. Files with r52, r12, or r13 in
their names, plus the kernel r1 APK, are historical artifacts and are not the
current PR builds.

The `.git` file inside `pmaports-clover-rootfix/` points to a removed parent
checkout. Repair the Git metadata before committing or pushing; the package
source files themselves are complete and build successfully.
