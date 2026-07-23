# Xiaomi Mi Pad 4

> **CURRENT STATE -- READ BEFORE MAKING CHANGES (2026-07-22):** The Xiaomi
> QCACLD/WCN3990 stack is the Clover default. Kernel r3 is installed on the
> tablet over USB, while the currently running kernel remains the previous
> build until the next reboot. The remaining boot-only TCP/SSH fault is
> addressed in source by the RTNL startup-order fix documented at the end.

## 2026-07-11 r30 live failure and r32 attempt

- Live r30 five-cycle reconnect validation failed on cycle 1 with a firmware `wal_concurrenc` assertion while deleting the still-up station vdev. The vdev-recreation approach is rejected.
- r32 instead retains the firmware station vdev through local disconnect and suppresses duplicate down/stop/start/up commands while mirroring retained state in `ath10k_vif`.
- The first generated r32 patch had incorrect disassociation control flow because it was based on the r28 skip-down source. The transformation and APKBUILD patch references were corrected before build.


## 2026-07-11 r31 kernel hardening update

- Promoted the r30 station-vdev recreation experiment to package revision `r31` after auditing it against upstream `ath10k_add_interface()`.
- Abort recreation when `ath10k_vdev_delete_sync()` fails; never create over a partially deleted firmware vdev.
- Guarantee at least one NSS during restoration.
- Restore station power-save and firmware keepalive-disable configuration after recreation.
- Runtime build/install/reconnect validation remains pending while tablet USB networking is unavailable. Wi-Fi (`xiaomi-clover`) — текущий Wi-Fi workaround/fix

## Что было сломано

На postmarketOS / mainline Linux Wi-Fi через WCN3990 (`ath10k_snoc`) нестабилен:

- `wlan0` иногда есть, но не может подготовиться к подключению;
- NetworkManager выдаёт `The device could not be readied for configuration`;
- при roaming/переходах между BSSID и 5 GHz firmware падает;
- в `dmesg` есть `ath10k_snoc ... firmware crashed!`;
- после crash появляются WMI ошибки `-108`;
- драйвер пишет `invalid MAC address; choosing random`.

Дополнительно в `persist` был найден пустой MAC-файл:

```txt
/persist/wlan_bt/wlan.mac = 0 bytes
```

При этом родной MAC сохранился в других файлах этого же устройства:

```txt
/persist/wlan_mac.clover:
Intf0MacAddress=<redacted-device-factory-mac>
END
```

и:

```txt
/persist/wlan_mac.bin:
d8 32 e3 06 a5 d7 ...
```

Родной Wi-Fi MAC:

```txt
<redacted-mac>
```

## Что было сделано

### 1. Сначала сделан backup persist

Перед любыми правками был сохранён raw backup раздела persist:

```txt
/root/wifi-debug-20260706-142733/persist.img
/root/wifi-debug-20260706-142733/persist.img.sha256
```

Также сделан файловый backup:

```txt
/root/wifi-debug-20260706-142733/persist-files-backup/
```

Раздел persist:

```txt
/dev/disk/by-partlabel/persist
/dev/mmcblk1p48
TYPE=ext4
```

`fsck.ext4 -fn` показал, что файловая система persist без явных ошибок.

### 2. Восстановлен пустой файл `/persist/wlan_bt/wlan.mac`

После backup persist был временно смонтирован rw, и в файл был записан MAC из родного `/persist/wlan_mac.clover`:

```txt
<redacted-mac>
```

После reboot файл доступен через mount msm-firmware-loader:

```txt
/run/msm-firmware-loader/mnt/persist/wlan_bt/wlan.mac
```

Содержимое:

```txt
00000000  64 38 3a 33 32 3a 65 33  3a 30 36 3a 61 35 3a 64  |d8:32:e3:06:a5:d|
00000010  37 0a                                             |7.|
```

Важно: эта правка НЕ убрала полностью сообщение:

```txt
ath10k_snoc 18800000.wifi: invalid MAC address; choosing random
```

То есть текущий kernel/postmarketOS всё ещё не использует этот файл как hardware MAC source. Но файл в persist теперь не пустой и восстановлен из данных этого же устройства.

### 3. Создан стабильный NetworkManager workaround-профиль

Главное, что реально позволило подключиться к Wi-Fi и получить интернет: был создан отдельный профиль NetworkManager, жёстко привязанный к рабочему 2.4 GHz BSSID.

Профиль:

```txt
Yabloko-24-fixed
```

Параметры:

```txt
SSID: Yabloko
BSSID: <redacted-mac>
Band: 2.4 GHz / bg
Security: WPA2
Password: <redacted-wifi-password>
Autoconnect: yes
```

Старые профили, которые провоцировали roaming/5GHz, были отключены от autoconnect:

```txt
Yabloko      autoconnect no
Yabloko 5Ghz autoconnect no
```

Команды по смыслу были такие:

```sh
sudo nmcli con add type wifi ifname wlan0 con-name Yabloko-24-fixed ssid Yabloko
sudo nmcli con modify Yabloko-24-fixed \
  802-11-wireless.bssid <redacted-mac> \
  802-11-wireless.band bg \
  802-11-wireless.powersave 2 \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk '<redacted-wifi-password>' \
  connection.autoconnect yes \
  connection.autoconnect-priority 100
sudo nmcli con modify "Yabloko" connection.autoconnect no
sudo nmcli con modify "Yabloko 5Ghz" connection.autoconnect no
sudo nmcli con up Yabloko-24-fixed ifname wlan0
```

## Что именно пофиксило подключение

Подключение пофиксила НЕ правка `wlan.mac` сама по себе, а комбинация:

1. отключение автоподключения к старым roaming/5GHz профилям;
2. создание отдельного профиля `Yabloko-24-fixed`;
3. жёсткая привязка к одному 2.4 GHz BSSID `<redacted-mac>`;
4. запрет NetworkManager выбирать между несколькими BSSID/5GHz точками.

Раньше crash часто происходил при переходах между BSSID, например:

```txt
...62:45
...62:48
```

А рабочий workaround удерживает устройство на одном известном 2.4 GHz AP:

```txt
<redacted-mac>
```

Именно это дало рабочее подключение.

## Проверка результата

После поднятия профиля `Yabloko-24-fixed`:

```txt
DEVICE         TYPE      STATE      CONNECTION
wlan0          wifi      connected  Yabloko-24-fixed
```

Пинг прошёл успешно:

```txt
PING google.com (2a00:1450:400d:80f::200e): 56 data bytes
64 bytes from 2a00:1450:400d:80f::200e: seq=0 ttl=115 time=50.519 ms
64 bytes from 2a00:1450:400d:80f::200e: seq=1 ttl=115 time=47.786 ms
64 bytes from 2a00:1450:400d:80f::200e: seq=2 ttl=115 time=47.129 ms

3 packets transmitted, 3 packets received, 0% packet loss
```

## Что НЕ пофиксено окончательно

Это не полноценный kernel/firmware fix.

В логах всё ещё остаются признаки проблем ниже NetworkManager:

```txt
ath10k_snoc 18800000.wifi: invalid MAC address; choosing random
ath10k_snoc 18800000.wifi: firmware crashed!
qcom-q6v5-mss 4080000.remoteproc: fatal error received: err_qdi.c:459:EX:wlan_process:1
failed to set 2g txpower 40: -108
failed to setup powersave: -108
failed to start hw scan: -108
```

Также подозрительно:

```txt
failed to fetch board data for bus=snoc,qmi-board-id=0,qmi-chip-id=0 from ath10k/WCN3990/hw1.0/board-2.bin
```

При этом установленный `board-2.bin` содержит `qmi-board-id=ff`, но lookup иногда идёт на `qmi-board-id=0`.

## Вывод

Текущий рабочий fix — это безопасный workaround:

```txt
использовать только профиль Yabloko-24-fixed, привязанный к 2.4 GHz BSSID <redacted-mac>
```

Он позволяет подключиться к Wi-Fi и получить интернет.

Полная причина, скорее всего, ниже NetworkManager:

- WCN3990 firmware / `ath10k_snoc`;
- board data / `board-2.bin` / `qmi-board-id` fallback;
- MAC/NV/calibration loading из persist;
- recovery path после crash Qualcomm remoteproc.

Для полноценного исправления нужен source-level fix в postmarketOS/pmaports/kernel/device package, а не только nmcli workaround.

---

# Kernel-level root-fix ideas after r20/r23

Этот раздел фиксирует именно идеи для полного kernel-level фикса, без NetworkManager dispatcher, без userspace watchdog/reset и без намеренного firmware crash/recovery как механизма лечения.

## Текущая картина

Рабочий пакетный workaround уже есть: kernel/device package удерживает Wi-Fi в рабочем состоянии через MAC/NM/dispatcher-логику. Но это не root fix.

По логам r21/r23 проблема выглядит так:

- после local disconnect `wlan0` драйвер и firmware формально остаются в `ATH10K_STATE_ON`;
- дальше часть WMI-команд начинает возвращать `-EAGAIN`;
- видны ошибки на `PEER_DELETE`, `VDEV_SET_PARAM`, `PEER_CREATE`, иногда `MGMT_TX_SEND`;
- scan может стартовать, но reconnect ломается на peer/vdev/auth стадии;
- `ip link down/up` помогает потому, что проходит другой путь teardown/recreate, но он может привести к `wal_concurrenc` assert и firmware crash;
- r23 детектор зависания WMI сработал, но вызов `ath10k_core_start_recovery()` из `sta_state` дал crash loop и `failed to start hw scan: -108`, поэтому этот подход отклонен.

Главный вывод: это не просто случайный вылет. Больше похоже на kernel/ath10k state machine bug после STA disconnect, где WMI/HTC control path застревает, а userspace reset только маскирует зависшее состояние.

## Гипотеза 1: WMI/HTC credit starvation

Самая сильная гипотеза: после local STA disconnect firmware/HTC перестает возвращать credits для WMI control endpoint, либо драйвер неправильно работает с synthetic credit mode на WCN3990/SNOC.

Почему это похоже на правду:

- `-EAGAIN` в WMI уходит в `ath10k_htc_consume_credit()`;
- состояние драйвера при этом `ON`, pending recovery нет;
- WCN3990 в `hw_params` использует `.use_fw_tx_credits = false`;
- при таком режиме ath10k выставляет `total_transmit_credits = 1`;
- если этот единственный WMI credit теряется после disconnect, peer/vdev команды начинают стабильно падать с `-EAGAIN`.

Идея фикса:

- сначала сделать r24 instrumentation, а не сразу лечить;
- логировать WMI `cmd_id`, endpoint id, `tx_credits`, required credits, credit reports, `is_up`, `is_started`, sta/vdev state;
- если подтвердится credit starvation, сделать clover-only quirk для WCN3990/SNOC:
  - либо отключить HTC credit flow только для WMI control endpoint на clover;
  - либо безопасно изменить synthetic WMI credit budget для clover/WCN3990;
  - не вызывать `ath10k_core_start_recovery()` как обычный путь.

Условие принятия: reconnect после `nmcli con down/up` работает без dispatcher, без `firmware crashed`, без `wal_concurrenc`, без WMI `-EAGAIN` storm.

## Гипотеза 2: STA vdev lifecycle bug

Если credits окажутся не причиной, второй логичный путь: после local disconnect WMI STA vdev остается в плохом firmware-side состоянии. Normal disconnect переиспользует тот же vdev, а `ip link down/up` пересоздает interface/vdev и поэтому оживляет Wi-Fi.

Идея фикса:

- не использовать full firmware recovery;
- после local STA disassoc помечать STA vdev как dirty;
- после `vdev_stop` и unassign chanctx выполнить чистый clover-only recreate WMI STA vdev:
  - `vdev_delete` с ожиданием ответа;
  - host-side cleanup peer/vdev state;
  - `vdev_create` с тем же `vdev_id`;
  - повторно применить post-create config из `ath10k_add_interface`;
  - не менять userspace-visible interface и MAC.

Если `vdev_delete/create` сам вызывает `wal_concurrenc` assert, этот путь надо отклонить как не upstream-clean.

## Гипотеза 3: DTS / board data / calibration

Это вторичный трек, потому что одни board-data попытки раньше reconnect не починили, но его нельзя игнорировать.

Что проверить:

- оставить `vdd-3.3-ch1-supply` в clover DTS, потому что binding и `ath10k_snoc` знают этот regulator;
- сравнить stock DTB/DTBO/vendor_boot с mainline DTS для `wifi@18800000`;
- проверить supplies, IOMMU/MSA, host-cap quirks, calibration properties;
- декодировать `board-2.bin` и сверить с lookup:
  - `bus=snoc,qmi-board-id=0,qmi-chip-id=0`;
  - если board file содержит только `qmi-board-id=ff`, добавить корректный board-data path или calibration variant.

Этот трек должен идти после WMI/HTC и vdev проверки, а не вместо них.

## Практический порядок релизов

- r24: instrumentation only, без dispatcher как условия теста.
- r25: WMI/HTC credit quirk candidate, если r24 подтвердит credit starvation.
- r26: STA vdev lifecycle recreate candidate, только если r25 не решит проблему.
- От r23 recovery path отказаться: он доказал детектор, но не дал чистого фикса.

## Тесты для настоящего root fix

Dispatcher должен быть отключен на время теста. Успешный kernel fix обязан проходить:

```sh
nmcli con up Yabloko-r3-test
ping -c 10 8.8.8.8

for i in 1 2 3 4 5; do
  nmcli con down Yabloko-r3-test
  sleep 5
  nmcli con up Yabloko-r3-test
  ping -c 10 8.8.8.8
done
```

В `dmesg` не должно быть:

```txt
firmware crashed
wal_concurrenc
failed to start hw scan: -108
wmi command timeout
PEER_CREATE ret=-11 loop
VDEV_SET_PARAM ret=-11 loop
```

Если reconnect работает только с dispatcher или после `ip link down/up`, это не root fix.

## Что считать финальным результатом

Финальный фикс должен быть маленьким и объяснимым:

- clover/WCN3990-specific kernel quirk или DTS/board-data исправление;
- без userspace reset;
- без намеренного firmware crash;
- без постоянного hardware recovery на обычный disconnect;
- с воспроизводимым циклическим reconnect test;
- с rollback на текущий рабочий r9/r4 workaround package, если экспериментальный kernel снова ломает Wi-Fi.

## Что сейчас стоит на планшете

Текущее рабочее состояние на Xiaomi Mi Pad 4 (`xiaomi-clover`) такое:

```txt
device-xiaomi-clover-11-r4
linux-postmarketos-qcom-sdm660-6.19.10-r9
device-xiaomi-clover-kernel-clover-11-r2
```

Wi-Fi сейчас поднимается и подключается так:

```txt
wlan0:wifi:connected:Yabloko-r3-test
```

Родной Wi-Fi MAC:

```txt
<redacted-mac>
```

Рабочий локальный APK с device-package workaround:

```txt
D:\general\postm\device-xiaomi-clover-11-r4.apk
SHA256: 7e923cdc46c345a39e093631f1d2c12f2f600869809c53cdab5b38296c57cd92
```

Важно: это именно текущий рабочий practical workaround, а не финальный kernel-level root fix. Он держит Wi-Fi за счет device/kernel package правок и dispatcher reset на падение `wlan0`. Для экспериментов с r24/r25/r26 этот rollback надо сохранить, чтобы можно было быстро вернуться к рабочему состоянию.


  # Current handoff: kernel-level Wi-Fi fix for Xiaomi Mi Pad 4

  Updated: 2026-07-11

  ## Objective

  Fix the Xiaomi Mi Pad 4 (`xiaomi-clover`) Wi-Fi reconnect failure inside the
  kernel/ath10k driver.

  Do not use NetworkManager dispatcher scripts, interface reset scripts, or other
  userspace recovery as the final solution.

  The fix is not complete until the new kernel is built, installed, and passes
  repeated disconnect/reconnect tests with the dispatcher disabled.

  ## Device and access

  Expected SSH connection over USB:

  - Host: `172.16.42.1`
  - User: `zxk`
  - Password: `<redacted-tablet-password>`
  - SSH helper path: `<local-sshpass-path>`

  Example:

  ```powershell
  & <local-sshpass-path> -p <tablet-password> ssh `
    -o StrictHostKeyChecking=no `
    -o ConnectTimeout=8 `
    zxk@172.16.42.1 "uname -a"

  The device was unreachable during the most recent attempt. It may simply be
  asleep or disconnected, so retry before concluding that SSH is broken.

  ## Known working rollback

  The known usable fallback is:

  - linux-postmarketos-qcom-sdm660-6.19.10-r9.apk
  - device-xiaomi-clover-11-r4.apk
  - NetworkManager profile: Yabloko-r3-test
  - Dispatcher workaround:
    /usr/lib/NetworkManager/dispatcher.d/xiaomi-clover-wlan-reset

  The dispatcher workaround must remain available for rollback, but it must be
  disabled during validation of the kernel fix.

  Local kernel APKs from r9 through r23 are stored in:

  D:\general\postm

  ## Confirmed failure behavior

  After a normal NetworkManager disconnect, later ath10k WMI commands may fail
  with:

  -EAGAIN
  ret=-11

  The ath10k device can still appear to be in the ON state, and no recovery is
  pending:

  pending_recovery=0

  A low-level ip link down/up cycle restores operation. This is why the
  userspace dispatcher workaround works, but it is not the desired solution.

  The failure is therefore not merely NetworkManager configuration. The likely
  fault is in the ath10k HTC/WMI transport state after disconnect.

  ## Rejected r23 approach

  r23 detected the stuck WMI path and forced ath10k firmware recovery.

  This was rejected because it produced firmware crash/recovery loops and errors
  such as:

  firmware crashed
  wal_concurrenc...
  failed to start hw scan: -108

  Do not restore the forced-firmware-crash recovery patch as the final fix.

  ## Current root-cause hypothesis

  For WCN3990:

  .use_fw_tx_credits = false

  ath10k consequently synthesizes only one HTC transmit credit. That single
  credit is used by the WMI control endpoint.

  After a station disconnect, the sole WMI control credit appears to stop being
  returned. The device remains nominally ON, but later WMI commands cannot be
  sent and return -EAGAIN.

  The current r24 experiment disables HTC credit-flow control only for the WMI
  control endpoint on Xiaomi clover WCN3990 SNOC devices.

  This is intentionally narrower than disabling credit flow globally.

  ## Source trees

  pmaports worktree:

  D:\general\postm\pmaports-clover-rootfix

  Branch:

  clover-wifi-rootfix

  Kernel source used for inspection:

  D:\general\postm\linux-v6.19.10-sdm660

  Both trees may contain unrelated existing modifications. Do not reset, clean,
  or revert them wholesale.

  ## Current r24 changes

  Kernel package:

  pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660/APKBUILD

  Current intended package revision:

  pkgrel=24

  ### Clover hardware helper

  Patch:

  pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660/0002-ath10k-add-xiaomi-clover-wcn3990-snoc-
  helper.patch

  It defines:

  bool ath10k_is_xiaomi_clover_wcn3990_snoc(struct ath10k *ar);

  The helper is now global to the ath10k module, implemented in core.c and
  declared in core.h, so it can be used from mac.c and htc.c.

  It scopes behavior to:

  - WCN3990
  - SNOC bus
  - Xiaomi clover device-tree compatibles:
      - xiaomi,clover-wifi
      - xiaomi,clover-lte
      - xiaomi,clover-plus

  ### WMI credit-flow patch

  Active patch:

  pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660/0007-ath10k-disable-wmi-credit-flow-on-xiaomi-
  clover.patch

  It changes ath10k_htc_connect_service() in htc.c.

  For the WMI control service, when running on clover WCN3990 SNOC and firmware
  TX credits are not used, it sets:

  ATH10K_HTC_CONN_FLAGS_DISABLE_CREDIT_FLOW_CTRL

  It also disables host endpoint credit accounting and should print:

  clover WMI HTC credit flow disabled on eid %d

  This patch does not deliberately crash or restart firmware.

  ## Critical source issue to fix before building

  In the current 0007 patch, this local variable may be uninitialized:

  bool clover_wmi_no_credit_flow;

  The reserved control-service path can jump to setup before assigning it.

  Change it to:

  bool clover_wmi_no_credit_flow = false;

  Do this before building r24.

  After changing the patch:

  1. Recalculate its SHA-512.
  2. Update the corresponding checksum in APKBUILD.
  3. Sync the updated patch and APKBUILD into the pmbootstrap pmaports checkout.

  ## Obsolete patch file

  An older untracked file may still exist:

  0007-ath10k-recover-clover-stuck-wmi-after-sta-disconnect.patch

  It is the rejected forced-recovery implementation.

  It must not be referenced by APKBUILD. Remove it only if safe; otherwise leave
  it untracked and clearly unused.

  ## Checksums recorded before the required initialization fix

  The currently recorded checksums are:

  0002:
  bc1181e8aedece12d3832dc0c24aa6ca9388a93caeb3fce9cb74cbb66406defc819cda4b2379e6d8405fbc05269c6bf23ce067bbad6727beef3b16
  f6aabd112f

  0007:
  5c456eaf66e265ccc634a965018a958721df04d6cc2982ad855cffcb995543e32631b8ee0c39a67850d43b588a2cfdb8be42a9a64a970b324eb636
  db919b93b4

  The 0007 checksum will change after initializing
  clover_wmi_no_credit_flow.

  ## pmbootstrap environment

  pmbootstrap is available inside WSL:

  pmbootstrap 3.10.1
  channel: systemd-edge
  device: xiaomi-clover

  Its pmaports checkout is:

  /home/xeonise/.local/var/pmbootstrap/cache_git/pmaports

  The relevant files were copied there from the Windows worktree, but they must
  be synced again after correcting the 0007 variable initialization.

  Previous commands run from the normal WSL user reached sudo and hung waiting
  for authentication.

  Find the exact WSL distribution name and run the build as its root user, for
  example:

  wsl.exe --list --verbose
  wsl.exe -d <DISTRO_NAME> -u root -e sh -lc `
    'export HOME=/home/xeonise; /home/xeonise/.local/bin/pmbootstrap --as-root checksum linux-postmarketos-qcom-sdm660'

  If --as-root is unnecessary or tries to invoke sudo even when already root,
  run pmbootstrap directly as root without that option.

  Build command:

  pmbootstrap --as-root build --force linux-postmarketos-qcom-sdm660

  Expected APK:

  linux-postmarketos-qcom-sdm660-6.19.10-r24.apk

  Search for it under:

  /home/xeonise/.local/var/pmbootstrap/packages

  Copy the completed APK back to:

  D:\general\postm

  ## Required validation procedure

  ### 1. Preserve rollback

  Before installing r24, verify that the r9 APK and dispatcher workaround are
  still available.

  ### 2. Disable the dispatcher

  Disable, rename, or remove the executable bit from:

  /usr/lib/NetworkManager/dispatcher.d/xiaomi-clover-wlan-reset

  Do not delete it permanently until the kernel fix is proven.

  Confirm that it cannot run during the test.

  ### 3. Install r24

  Copy the APK to the tablet and install it:

  sudo apk add --allow-untrusted --force-overwrite \
    /tmp/linux-postmarketos-qcom-sdm660-6.19.10-r24.apk
  sudo reboot

  ### 4. Confirm the correct kernel booted

  Check:

  uname -a
  apk list -I | grep linux-postmarketos-qcom-sdm660
  dmesg | grep -F "clover WMI HTC credit flow disabled"

  Because postmarketOS uses KBUILD_BUILD_VERSION=pkgrel+1, r24 may appear as:

  #25-postmarketos-qcom-sdm660

  The dmesg marker proves that the clover-specific path was selected.

  ### 5. Test reconnect without userspace recovery

  Run at least five complete cycles:

  nmcli con down Yabloko-r3-test
  sleep 5
  nmcli con up Yabloko-r3-test
  ping -c 10 8.8.8.8

  Each cycle must reconnect successfully and pass traffic without running the
  dispatcher or manually cycling the interface.

  ### 6. Collect diagnostics

  Save dmesg and NetworkManager logs locally, preferably under:

  D:\general\postm\diag-r24

  Check specifically for:

  firmware crashed
  failed to start hw scan: -108
  ret=-11
  -EAGAIN
  authentication timeout
  WMI command failures
  recovery loop

  ## Success criteria

  The kernel fix is successful only if all of the following are true:

  1. r24 builds and installs.
  2. The clover-specific dmesg marker appears.
  3. The dispatcher is disabled.
  4. At least five NetworkManager down/up reconnect cycles succeed.
  5. Traffic works after every reconnect.
  6. There is no firmware crash/recovery loop.
  7. There is no repeated WMI -EAGAIN failure.

  Do not describe r24 as fixed until this live test passes.

  ## Failure and rollback

  If r24 fails:

  1. Capture dmesg and NetworkManager logs before changing anything.
  2. Reinstall:
     linux-postmarketos-qcom-sdm660-6.19.10-r9.apk

  3. Re-enable:
     /usr/lib/NetworkManager/dispatcher.d/xiaomi-clover-wlan-reset

  4. Reboot and verify Wi-Fi is usable again.
  5. Document exactly whether r24 failed to boot, failed to connect, lost WMI
     commands, or caused firmware recovery.

  ## Immediate next actions (SUPERSEDED by session update below)

  Historical handoff pointed at r24 credit-flow disable. That path was already
  superseded by later builds. See "Session update 2026-07-11" below.

---

# Session update 2026-07-11 — kernel-level progress

## What is on the tablet right now

Last successful install attempted:

```txt
linux-postmarketos-qcom-sdm660-6.19.10-r28.apk
```

Flashed via `apk add` + mkinitfs/boot-deploy, then `reboot`.

After that reboot:

- ICMP to `172.16.42.1` answers (USB gadget IP is alive)
- TCP port 22 is closed / SSH banner refused
- No adb, no other common ports open

So either userspace is hung mid-boot, sshd never started, or the tablet needs a
hard power cycle / USB re-plug. **SSH was healthy on r26 and r27 before r28.**

## Verified results

### r26 (credit restore only) — tested live

Package: `linux-postmarketos-qcom-sdm660-6.19.10-r26`  
Kernel marker: `#27-postmarketos-qcom-sdm660`  
Dispatcher: `xiaomi-clover-wlan-reset.disabled-r25` (disabled)

Boot marker present:

```txt
clover WMI credit restored from CE completion on eid 2
```

5x `nmcli con down/up Yabloko-r3-test` + ping: **PASS=5 FAIL=0**

But every disconnect:

```txt
wlan0: deauthenticating ... by local choice
qcom-q6v5-mss ... fatal error ... WLAN RT:...:PC=b00c7394
ath10k_snoc ... firmware crashed!
```

Then remoteproc recovers, ath10k restarts, reconnect works.

Logs: `D:\general\postm\diag-r26\`

**Verdict:** reconnect works without dispatcher, but only because disconnect
triggers firmware crash/recovery. **Not a clean root fix.**

### r27 (credit restore + DTS factory MAC) — tested live

Package: `linux-postmarketos-qcom-sdm660-6.19.10-r27`  
Kernel marker: `#28-postmarketos-qcom-sdm660`

Improvements:

- DT has `local-mac-address = <redacted-mac>`
- **No more** `invalid MAC address; choosing random`
- Factory MAC on wlan0 from boot

5x reconnect: **PASS=5 FAIL=0**, but still **firmware_crash_count=5**
Same PC=`b00c7394` on every deauth.

Logs: `D:\general\postm\diag-r27\`

**Verdict:** MAC mismatch theory alone does **not** fix teardown crash.
Reconnect still relies on crash recovery.

### r28 (skip vdev_down + credit restore + DTS MAC) — built, install attempted

Hypothesis:

1. Crash is caused by `WMI_VDEV_DOWN` on clover (exactly what patch 0006 documents)
2. Skipping vdev_down alone used to leave WMI stuck (-EAGAIN) — credit restore
   should fix that second half

Patches in APKBUILD `pkgrel=28`:

```txt
0001 honor no-p2p
0002 clover WCN3990 SNOC helper
0003 force passive scans on clover
0004 skip unsupported WMI runtime params
0005 DTS vdd-3.3-ch1-supply
0006 skip clover vdev_down on STA disassoc   <-- re-enabled
0007 restore clover WMI credit on CE completion
0008 DTS local-mac-address
```

APK:

```txt
D:\general\postm\linux-postmarketos-qcom-sdm660-6.19.10-r28.apk
```

Worktree:

```txt
D:\general\postm\pmaports-clover-rootfix
branch: clover-wifi-rootfix
```

**Install status:** apk upgraded r27→r28, boot reflash OK, reboot issued.
Afterwards SSH not available (ping only). Needs hard reboot or recovery.

## Success criteria for r28 (when SSH returns)

Dispatcher must stay disabled. Run:

```sh
# /tmp/tablet-r27-reconnect-test.sh adapted, or:
for i in 1 2 3 4 5; do
  nmcli con down Yabloko-r3-test
  sleep 5
  nmcli con up Yabloko-r3-test ifname wlan0
  ping -c 10 -W 2 8.8.8.8
done
```

Must see:

1. PASS on all 5 cycles
2. **zero** `firmware crashed`
3. **zero** `PC=b00c7394` / remoteproc fatal on disconnect
4. **zero** repeated `ret=-11` / WMI -EAGAIN storm
5. dmesg still has credit restore marker at boot

If reconnect fails without crash → credit path still insufficient.
If crash still happens → vdev_down skip not the only teardown trigger.

## Recovery if tablet stays unreachable

1. Hard power cycle (hold Power 10–20s), unplug/replug USB.
2. Retry SSH as zxk@172.16.42.1.
3. If SSH returns but Wi-Fi/kernel bad, roll back:

```sh
# copy r9 or r27 first, then:
sudo apk add --allow-untrusted --force-overwrite \
  /tmp/linux-postmarketos-qcom-sdm660-6.19.10-r27.apk
# or known good:
# /tmp/linux-postmarketos-qcom-sdm660-6.19.10-r9.apk
sudo reboot
```

4. If SSH never returns: boot to fastboot (VolDown+Power on clover), flash a
   known-good boot image. Kernel APK alone has `vmlinuz`/`vmlinuz.efi` + dtbs,
   not a ready `boot.img`; preferred path is restore from a previously working
   device after SSH, or rebuild boot on-device from r27 APK.

Rollback packages on host:

```txt
D:\general\postm\linux-postmarketos-qcom-sdm660-6.19.10-r9.apk
D:\general\postm\linux-postmarketos-qcom-sdm660-6.19.10-r27.apk
D:\general\postm\device-xiaomi-clover-11-r4.apk
```

## Rejected / incomplete approaches (updated)

| Rev | Approach | Result |
|-----|----------|--------|
| r20 | force recovery after skip vdev_down | crash loop, rejected |
| r23 | detect stuck WMI → start_recovery | crash loop, rejected |
| r24–r25 | earlier credit experiments | superseded |
| r26 | CE completion restores synthetic WMI credit | reconnect OK via crash recovery |
| r27 | r26 + DTS MAC | kills random MAC; crash on deauth remains |
| r28 | r27 + skip WMI_VDEV_DOWN | installed; SSH pending validation |

## Immediate next actions

1. ~~Restore tablet access~~ done (user hard reboot).
2. ~~Confirm r28~~ `#29-postmarketos-qcom-sdm660`, package r28.
3. ~~Dispatcher disabled~~ still `.disabled-r25`.
4. ~~5-cycle test~~ PASS=5 but **not clean**.
5. Analyze r28 logs and design r29 without crash-as-recovery.

### r28 live result (2026-07-11)

```txt
PASS=5 FAIL=0
firmware_crash_count=5
```

Crash type **changed** vs r26/r27:

| Kernel | On disconnect assert |
|--------|----------------------|
| r26/r27 (vdev_down runs) | `WLAN RT:...:PC=b00c7394` |
| r28 (skip vdev_down) | `Asserted in wal_concurrenc` |

Interpretation:

- Skipping `WMI_VDEV_DOWN` avoids the `PC=b00c7394` path.
- Host still sets `arvif->is_up = false`, then next `ath10k_bss_assoc()` calls
  `ath10k_wmi_vdev_up()` while firmware still considers the vdev up →
  `wal_concurrenc` assert.
- Reconnect still “works” only via remoteproc recovery after crash.
- Cycle 3 even showed `ping: Network unreachable` once (script still counted PASS
  because of pipe exit status); treat functional quality as fragile.

Logs: `D:\general\postm\diag-r28\`

**Verdict: r28 is not a root fix.** skip-vdev_down alone desyncs host/FW.

### Next hypothesis for r29

Need a **synced** teardown or recreate, not just skip down:

Option A — **safe dual command**: on clover STA disassoc, skip raw `vdev_down`,
but before next assoc explicitly run a known-good order (peer cleanup +
`vdev_stop`/`vdev_down` with delay, or only down if peer is already gone).

Option B — **vdev recreate** (FIX.MD hyp. 2): after STA disassoc on clover,
`vdev_delete` + host cleanup + `vdev_create` with same id + reapply post-create
config. If that hits `wal_concurrenc`, reject.

Option C — **instrumentation-only r29**: log every WMI cmd id + ret around
disassoc/assoc with timestamps to see the exact command before
`PC=b00c7394` when vdev_down is re-enabled (r27 path).

Recommended order: short **C** (or careful A) rather than more blind skips.

Rollback still available: r9+dispatcher, r27 APK.

---

# Session update 2026-07-20 - r34 ordered STA teardown

The retained-vdev r32 approach has been replaced with a small ath10k state
ordering fix. On Xiaomi Clover station teardown, ath10k now performs:

```txt
VDEV_STOP -> PEER_DELETE -> VDEV_DOWN
```

`VDEV_STOP` runs from the AP peer's `NONE -> NOTEXIST` transition while the
peer still exists. The normal mac80211 disassociation callback then issues
`VDEV_DOWN`, and channel-context unassignment skips the already-completed
stop. Connection setup is unchanged; no firmware vdev is retained or reused.

Package and validation:

```txt
linux-postmarketos-qcom-sdm660-6.19.10-r34.apk
SHA256 e80d22d1c1adc7fa7093c2d58d91a8d2158a6124903c7b517f7ff819fb29e373
checkpatch: 0 errors, 0 warnings
pmbootstrap clean build: BUILD_OK
```

Host entrypoint:

```powershell
.\run-clover-wifi-r34.ps1 `
  -PrimaryConnection Yabloko-r3-test `
  -SecondaryConnection <existing-5GHz-NetworkManager-profile>
```

The runner reuses the verified APK unless package inputs change, restores
`boot-r27-known-good.img` through fastboot when explicitly confirmed, installs
r34, disables the NetworkManager recovery dispatcher, runs five proof cycles,
then runs the 20-transition 2.4/5 GHz/BSSID and suspend test.

Live status: not installed or tested yet. At handoff the tablet answered
neither SSH nor fastboot, so it must be placed in fastboot physically with
Volume Down + Power before the runner can continue. Do not call r34 fixed until
the live test reports zero firmware crashes, `wal_concurrenc`, `PC=b00c7394`,
WMI `-EAGAIN`, and teardown timeouts.

## r34 live result and rollback (2026-07-20)

r34 was installed entirely from the running r27 system over USB SSH. No
fastboot command was used. The on-device sequence was:

```txt
scp r34.apk -> apk add -> mkinitfs -> boot-deploy -> on-device boot flash
```

The first r34 APK omitted
`/usr/share/kernel/postmarketos-qcom-sdm660/kernel.release`, so its automatic
`postmarketos-mkinitfs` trigger failed safely before reboot. The missing file
was restored with the exact release `6.19.10-sdm660`, `mkinitfs` and
`boot-deploy` then completed, and the tablet booted:

```txt
Linux xiaomi-clover 6.19.10-sdm660 #35-aarch64
linux-postmarketos-qcom-sdm660-6.19.10-r34
```

The package recipe now installs that metadata file. The corrected rebuilt APK
is:

```txt
linux-postmarketos-qcom-sdm660-6.19.10-r34.apk
SHA256 a380a64f21ffa02bce7c4fe5e62eae33950684931521403662281831c23b3726
```

The live reconnect proof rejected the driver change:

```txt
primary reconnects with dispatcher disabled: 4/5 functional
firmware crashes: 5
assert: PC=b00c7394
fifth activation: "device could not be readied for configuration"
```

Each local deauthentication was followed roughly 160-190 ms later by the same
firmware fatal assertion. Thus sending `VDEV_STOP` before peer deletion did not
avoid the crashing firmware path. The repeated remoteproc recoveries eventually
caused ath10k to shut the driver down after consecutive failures.

Diagnostics:

```txt
D:\general\postm\diag-r34-install-proof\
```

r27 was then restored through `apk add` + automatic `mkinitfs`/`boot-deploy`
and an on-device reboot, again without fastboot. Verified final tablet state:

```txt
Linux xiaomi-clover 6.19.10-sdm660 #28-postmarketos-qcom-sdm660
linux-postmarketos-qcom-sdm660-6.19.10-r27
wlan0 connected to Yabloko-r3-test
```

**Verdict: r34 installs and boots, but is not the Wi-Fi root fix. Do not use it
as a stable kernel.**

---

# Qualcomm 5.1 qcacld bring-up on Linux 6.19 (started 2026-07-20)

> The chronological r35/r36 checkpoints in this chapter are retained as a
> build record. This source attribution was corrected after hardware testing:
> the r35-r44 driver is Qualcomm/CAF qcacld 5.1.1, **not Xiaomi's published
> 5.2 driver**. The authoritative state and next-port instructions are in
> **Authoritative handoff after r44 (2026-07-21)** at the end of this file.

## Goal and non-goal

The goal is to replace the Clover WCN3990 `ath10k_snoc` control path with the
same Qualcomm driver family Xiaomi used: the SNOC `qcacld-3.0` WLAN module
with ICNSS handling firmware startup, copy-engine IRQs, power, memory mapping,
and subsystem recovery.

The target remains postmarketOS Linux `6.19.10-sdm660`; this cannot be a
byte-identical Android 4.4 kernel.  "1:1" means that the Xiaomi-era
firmware-facing qcacld WMI/WMA/MLME/HIF behavior and configuration are the
baseline.  The kernel-facing ICNSS, DMA/IOMMU, QMI and cfg80211 glue must be
adapted to Linux 6.19.

Do **not** use more ath10k command-order experiments as a root fix. r34 proved
that changing `VDEV_STOP`, peer-delete and `VDEV_DOWN` ordering still reaches
the same `PC=b00c7394` firmware assertion.

## Historical Qualcomm 5.1 source manifest (not Xiaomi-exact)

These were the three CAF-derived inputs used for r35-r44. They were initially
assumed to represent Xiaomi Clover's matching WLAN release. That assumption
was wrong: the resulting qcacld reports version `5.1.1.28U`, while Xiaomi's
published same-generation SDM660 WLAN tree reports `5.2.03.13E`. The checksums
below remain useful for reproducing the historical r44 build; they must not be
described as Xiaomi's exact WLAN sources.

| Component | Commit | Archive SHA-512 |
|---|---|---|
| Xiaomi kernel reference | `2bfc48656a37ba6fbc380425ea98b4c445ad2315` | source reference only |
| CAF qcacld-3.0 5.1.1.28U | `fe68324678b317ebf9a697328691f9a006402ae8` | `0c3f7d2717e263617a38aca0f717388711f11f60bf7e2d1633e33c294baefbbf163ae16c5608cab77b34710e8ef0d61d66c18fdcc0856942f883fe95a9f2bc39` |
| qca-wifi-host-cmn | `0cf2f732b0dec50aba4266ee42de7637b42a0fd2` | `0f2329eb4f2c485b2dec028068307cf6b46565bae9a127899e8c39e61532b241523b0a2edebced0777e54375d6c48d400502fe095a74cc3cbba6995fdbc8eecc` |
| fw-api | `b87a08f721ee111ff6da6e59a0b95b34ca97c8e5` | `44882ae58c0ab203caff63aef0f0bdb33a5e725b78ea21470acdd1adbaa4eae7732c4f478aec15df931708e75934038b621299099d747abd582ebb8d8b7ceaac` |

At the r35 checkpoint the workspace did not contain the matching
`WCNSS_qcom_cfg.ini`. That gap is closed in device package r9 with the Xiaomi
SDM660-common Lineage 16 configuration from commit
`d292a85ea71f9feb85267c21f1f59057018ffd5a`; r37 `wlan.ko` itself confirms
that it requests `wlan/qca_cld/WCNSS_qcom_cfg.ini`. A separately preserved
stock MIUI image would still be useful for byte-for-byte provenance, but is
not required for the implemented kernel backend.

## Historical r35 foundation (superseded)

The kernel package was changed from failed r34 behavior back to the r27
ath10k fallback patch set:

```txt
0001..0005 unchanged
0007-ath10k-restore-clover-wmi-credit-on-ce-completion.patch
0008 factory MAC patch
```

The failed r34 teardown-order and recovery patches are deliberately no longer
in the package `source=` list. Their files remain in the workspace as history.

The package now imports the three exact CAF source trees into
`drivers/staging/` during `prepare()`. It adds:

```txt
include/soc/qcom/icnss.h
drivers/staging/qcom_icnss_clover/
```

`CONFIG_ICNSS=y` currently builds only a **fail-closed ABI scaffold**. It
exports the legacy `icnss_*` symbols qcacld expects, records one client, and
returns `-ENODEV`/`-EOPNOTSUPP` for hardware operations. It has no DT match and
does not bind `qcom,wcn3990-wifi`; therefore it cannot steal the device from
ath10k or change r27 boot behavior. `CONFIG_QCA_CLD_WLAN` is intentionally not
set until the real WCN3990 QMI/CE backend exists.

This is an intentional safety boundary, **not a functioning qcacld driver**.
The next implementation layer must move the validated Linux 6.19 WCN3990 QMI,
firmware service, CE IRQ, regulator/clock and DMA/IOMMU ownership from the
ath10k SNOC platform path into this ICNSS backend. Only then can `wlan.ko` be
compiled and tested.

## Module ownership and rollback design

The target runtime sequence is:

```txt
qcom_q6v5_wcss -> ICNSS compatibility backend -> qcacld wlan.ko -> wlan0
```

There must never be two drivers bound to WCN3990. `ath10k_snoc` remains the
default during development. A new `clover-wifi-driver` tool has these modes:

```txt
status       report available and active modules
try-qcacld   transiently unload ath10k, load wlan.ko, restore ath10k on error
use-qcacld   persistently blacklist ath10k only after a successful transient test
use-ath10k   remove the qcacld selection and restore the r27 fallback
```

At r35, `try-qcacld` safely refuses because `wlan.ko` is not enabled yet. This
is deliberate: no unproven module selection is installed on the tablet.

Normal deployment stays no-fastboot:

```txt
scp APK -> apk add -> mkinitfs -> boot-deploy -> reboot
```

Fastboot is emergency-only if the tablet cannot boot back to SSH. Keep
`linux-postmarketos-qcom-sdm660-6.19.10-r27.apk` and
`boot-r27-known-good.img` unchanged until qcacld passes the full suite.

## Build and validation ledger

| Time | Revision | Action | Result |
|---|---|---|---|
| 2026-07-20 | r35 | Applied ICNSS/qcacld scaffold patch against clean 6.19.10 tree | `git apply --check`: PASS |
| 2026-07-20 | r35 | Shell-checked `APKBUILD` and `clover-wifi-driver` | PASS |
| 2026-07-20 | r35 | Cross-compiled the full arm64 kernel in pmbootstrap | PASS; the ICNSS compatibility object compiled and the package was created |
| 2026-07-20 | r35 | Inspected built APK contents | PASS; `ath10k_core.ko.zst` and `ath10k_snoc.ko.zst` present, no `wlan.ko` enabled |
| 2026-07-20 | r35 | Recorded artifact integrity | `linux-postmarketos-qcom-sdm660-6.19.10-r35.apk`, SHA-256 `9ceee03450b947a74f439dee459199729ab5cd8ba3e0ae6a524465a88c38de74` |
| 2026-07-20 | device r5 | Rebuilt the device package after syncing the actual recipe into pmbootstrap's cached pmaports tree | PASS; `/usr/sbin/clover-wifi-driver` is present and guards the driver switch |
| 2026-07-20 | device r5 | Recorded artifact integrity | `device-xiaomi-clover-11-r5.apk`, SHA-256 `94919f6000c2475d944833e9420f8eed050d2bd24b212925b718a5b061e8ad7d` |

The local WSL host has no ARM cross compiler, so compile validation was
executed inside the same pmbootstrap cross-native environment used for r27/r34.
`qcacld_wlan` deliberately remains disabled: the compatibility scaffold has no
QMI/CE hardware backend yet and therefore cannot be permitted to claim the
WCN3990. The r35 APK is safe to boot only as an ath10k regression check; it is
not a qcacld trial image.

### Reproducible local build entry points

pmbootstrap is configured to build from
`~/.local/var/pmbootstrap/cache_git/pmaports`, not directly from the checked-out
`pmaports-clover-rootfix` directory. Building by only changing directory can
silently test an older cached recipe. The two wrappers deliberately copy the
listed, checksummed package files into that cache before invoking pmbootstrap:

```sh
wsl.exe -e sh /mnt/d/general/postm/wsl-build-qcacld-r35.sh
wsl.exe -e sh /mnt/d/general/postm/wsl-build-clover-device-r5.sh
```

Their status files must read `BUILD_OK`. The first produces the conservative
ath10k r35 kernel; the second produces the guarded device r5 package. Neither
installs anything onto the tablet.

## Historical pre-0025 backend boundary (superseded)

> This section records the boundary before patches `0025` and `0026` were
> written. It is not the current state. The implemented backend and current
> validation status are documented in **r36 real ICNSS backend result** below.

The original Xiaomi implementation is not a small `wlan.ko` shim. At source
commit `2bfc48656a37ba6fbc380425ea98b4c445ad2315`, its ICNSS layer consists of:

| Xiaomi 4.9 source | Size | Responsibility | Linux 6.19 replacement source |
|---|---:|---|---|
| `drivers/soc/qcom/icnss.c` | 3,832 lines | platform ownership, regulators, CE IRQs, QMI lifecycle, MSA/DMA, recovery | split between `ath10k/snoc.c` and `ath10k/qmi.c` |
| `drivers/soc/qcom/wlan_firmware_service_v01.[ch]` | 2,531 lines | WLFW QMI protocol encoding | `ath10k/qmi_wlfw_v01.[ch]` |
| `include/soc/qcom/icnss.h` | 148 lines | ABI consumed by `qcacld-3.0/core/pld/src/pld_snoc.c` | r35 compatibility header |

The 4.9 ICNSS source also calls Qualcomm-only infrastructure that does not
exist in mainline (`msm_qmi_interface`, subsystem restart/service notifier,
secure-buffer, QPNP ADC and legacy DMA-IOMMU APIs). It cannot be copied into
6.19 and expected to run. Conversely, Linux 6.19's WCN3990 QMI implementation
is deliberately private to ath10k and uses ath10k-specific state, so qcacld
cannot call it directly.

The real next patch must factor the following **generic** transport operations
out of the 6.19 ath10k implementation, then implement the ICNSS ABI on top of
them: bind `qcom,wcn3990-wifi`; map `membase`; allocate all 12 CE IRQs; reserve
and map the MSA region; run the WLFW QMI server-arrival/`msa_ready`/`fw_ready`
state machine; send qcacld's target/service/shadow-register configuration and
mission/off modes; and forward firmware-down/recovery events to qcacld's PLD
callbacks. Only then may `CONFIG_QCA_CLD_WLAN=m` be enabled and ath10k
blacklisted for a one-boot trial.

Until that patch builds and passes the acceptance sequence below, a new
platform driver must not bind `qcom,wcn3990-wifi`: it would steal the sole
WCN3990 device from the known-good ath10k fallback without being able to boot
the firmware.

## Hardware acceptance sequence (still required)

1. Boot r35 with ath10k still default and verify r27-style fallback connectivity.
2. Use `clover-wifi-driver try-qcacld`; require `wlan0`, factory MAC, scan,
   association, DHCP and traffic without touching persistent module policy.
3. Require 100 local disconnect/reconnect cycles with zero firmware asserts,
   remoteproc recovery, WMI `-EAGAIN` storms, kernel warnings or dispatcher use.
4. Require 2.4/5 GHz changes, two-BSSID transitions, suspend/resume, AP, P2P,
   roaming, regulatory and Bluetooth-coexistence tests before making qcacld the
   permanent driver.

## Historical r36 compile checkpoint through 0020 (superseded)

> The statements below describe the build at patch `0020`. The final r36
> package now applies through `0047`, passes clean modpost, and contains both
> modules. See the current result below.

Revision r36 is the experimental compile port. It enables
`CONFIG_QCA_CLD_WLAN=m`, but it is **not installable as a working Wi-Fi
driver yet**: the ICNSS compatibility implementation remains fail-closed and
does not have the QMI/CE/MSA backend described above. The known-good r35 APK
and ath10k fallback remain the only boot-testable artifacts.

The compile port is intentionally split into reviewable patches:

| Patch | Ported boundary |
|---|---|
| `0010` | Adds the selected CAF qcacld 5.1 source to the staging build and produces a `wlan.ko` target. |
| `0011` | Converts old global `EXTRA_CFLAGS` usage to directory-scoped Kbuild flags and makes source/output-tree paths explicit. |
| `0012` | Replaces libc `stdarg`, downstream DMA-IOMMU mapping and legacy IOVA translation APIs. |
| `0013` | Ports QDF string and boot/monotonic timekeeping APIs. |
| `0014` | Preserves QDF timer callback/argument semantics with a modern `timer_list` wrapper; ports skb refcounts, IRQ-context checks and the removed ARM cache helper; fixes the malformed no-TDLS fallback. |
| `0015` | Fixes a critical include-order bug: `-Iinclude/linux` caused Qualcomm's quoted `wmi.h` to select Linux ACPI WMI. It now qualifies the one bare module/kallsyms include, ports procfs to `proc_ops`, and removes an unused downstream subsystem-restart include. |
| `0016` | Qualifies all active bare kernel standard headers (`stdarg`, `string`, `msg`, and `netdevice`). |
| `0017` | Adds an exact `strlcpy` compatibility implementation and ports the first cfg80211/netdev changes: MLO link-zero roam/BSS fields, VHT segment names, netlink extack arguments, sched-scan request IDs, channel-switch link ID, RX timestamp removal and TX queue timestamp signature. |
| `0018` | Declares qcacld's private Wireless Extensions ABI dependencies with Kconfig `select WIRELESS_EXT` and `select WEXT_PRIV`; placing the hidden symbols directly in the config fragment does not survive `olddefconfig`. |
| `0019` | Ports `ndo_tx_timeout`, `ndo_select_queue` and `priv_destructor` to the Linux 6.19 netdev ABI; enables the CAF tree's MCC-to-SCC build define so its unguarded hostapd users and guarded config/state definitions agree; ports AP-stop, class creation and module-parameter callbacks. |
| `0020` | Adapts legacy and already-modern `nla_parse`/`nla_parse_nested` calls through one QDF macro dispatcher, maps `nla_strlcpy`, ports the last HDD boottime users, and enables the CAF tree's channel-avoid feature so its feature-bit definitions are visible. |

Verified milestones from successive full builds:

1. The pinned historical CAF qcacld, qca-wifi-host-cmn and fw-api archives are
   copied into the 6.19 staging tree and their Kbuild is entered.
2. Compilation progressed from missing qcacld headers into QDF, then HDD and
   cfg80211 translation units.
3. The large unknown-`wmi_*` type cascade was eliminated by fixing header
   selection, not by inventing replacement firmware structs. The dependency
   file proved the wrong header was `include/linux/wmi.h`; after `0015`, the
   pinned CAF `fw-api/fw/wmi_unified.h` is selected.
4. The r36 build still fails in the upper HDD/cfg80211 compatibility layer.
   The next mechanical batch is: remaining `nla_parse(..., NULL)` conversions,
   `timespec`/boottime conversions in extended scan, readonly `dev_addr`
   updates, modern `cfg80211_ops` callback wrappers and netdev callback
   signatures. Qualcomm feature constants/guards must be reconciled from the
   pinned Kbuild rather than replaced with guessed values.
   Patch `0018` was verified in generated `autoconf.h`; it removed the complete
   `iw_handler_def`/`wireless_handlers` error cluster.
   Patch `0019` removed the complete main/hostapd netdev, MCC, work-item,
   callback-registration, class and module-parameter cluster. Patch `0020`
   removed all legacy netlink-parse arity errors, both final timespec users,
   `nla_strlcpy`, and the missing Android feature-bit cluster.
   The first remaining compile boundary is now: removed
   `WIPHY_FLAG_DFS_OFFLOAD`/`WIPHY_FLAG_SUPPORTS_SCHED_SCAN`, read-only
   `dev_addr` writes, one removed gratuitous-ARP/unsolicited-NA classifier,
   epping's TX-timeout signature, optional nl80211 testmode, and the modern
   `cfg80211_ops` callback signatures (MLO link IDs, AP update and interface
   callback changes).
5. After `wlan.ko` links, unresolved-symbol/modpost inspection comes before
   implementing the generic ICNSS backend. A linked module alone is not proof
   that firmware can boot or that the module is safe to install.

Current r36 build inputs are
`pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660/`
and the reproducible wrapper is `wsl-build-qcacld-r36.sh`. Each wrapper run
writes `qcacld-r36-build.log` and an atomic `qcacld-r36-build.status`.

## Historical r37 real ICNSS backend result (2026-07-21; superseded)

This section was authoritative before r38-r44 hardware testing. It supersedes
only the earlier compile checkpoints. The final handoff section supersedes it.

The historical CAF qcacld source, kernel integration and packages reached a
complete build: qcacld links as `wlan.ko` against a real WCN3990 ICNSS/WLFW
platform backend, and both modules pass a clean kernel build and modpost. This
proved that the backend was implemented and installable. Later hardware tests
proved scan operation but failed association because firmware asserted.

### Meaning of “Xiaomi 1:1” on Linux 6.19

The port preserves the historical CAF qcacld, qca-wifi-host-cmn and fw-api
source revisions selected for r35-r44 and restores an SDM660 feature profile.
It does **not** preserve Xiaomi's exact WLAN source; that earlier claim was
disproved by version comparison and hardware testing.
It also implements the ICNSS ABI and WLFW protocol sequence consumed by that
driver. It is not a textual copy of Android's Linux 4.9 `icnss.c`: that file
depends on removed `msm_qmi_interface`, legacy ARM DMA-IOMMU, subsystem/PDR
notifiers, QPNP ADC and secure-buffer interfaces. The 6.19 backend expresses
the same hardware contract with current QMI/QRTR, DMA/IOMMU, regulator, clock
and SCM APIs.

Frozen inputs:

| Component | Revision |
|---|---|
| CAF qcacld-3.0 5.1.1.28U (historical, wrong final generation) | `fe68324678b317ebf9a697328691f9a006402ae8` |
| qca-wifi-host-cmn | `0cf2f732b0dec50aba4266ee42de7637b42a0fd2` |
| Qualcomm fw-api | `b87a08f721ee111ff6da6e59a0b95b34ca97c8e5` |
| Xiaomi 4.9 kernel used as ICNSS reference | `2bfc48656a37ba6fbc380425ea98b4c445ad2315` |
| Xiaomi SDM660-common WLAN INI | Lineage 16 commit `d292a85ea71f9feb85267c21f1f59057018ffd5a` |

The runtime ownership chain is:

```text
wlan.ko (historical CAF qcacld 5.1.1.28U)
  -> pld_snoc
  -> exported ICNSS ABI
  -> qcom-icnss-clover.ko
  -> QMI/QRTR WLFW + regulators/clocks + MSA/SCM + 12 CE IRQs
  -> WCN3990
```

### Implemented firmware lifecycle

1. `qcom-icnss-clover.ko` explicitly binds `qcom,wcn3990-wifi` only during a
   guarded qcacld trial. It maps `membase`, obtains all twelve CE IRQs, five
   regulators, optional clocks, the reserved MSA region and the device's
   existing IOMMU domain.
2. It finds WLFW service `0x45`, version 1 over QRTR and registers firmware
   and MSA indications.
3. It powers WCN3990, sends indication registration and host capabilities,
   publishes MSA, validates firmware-returned subregions, assigns the regions
   to MSS/WLAN/WLAN_CE with SCM, sends MSA-ready, and reads target, board, SoC
   and firmware capabilities.
4. On FW-ready it restores power and invokes qcacld `probe`. qcacld supplies
   Xiaomi's CE target/service/shadow-register tables; ICNSS sends WLAN config
   and the requested mission/FTM/epping/test mode.
5. CE interrupt request/free/enable/disable, capability information, factory
   MAC, unsafe channels, DFS NOL, firmware logging, power, SMMU resource maps
   and ATHDIAG reads/writes are backed by real kernel or WLFW operations.
6. On WLFW loss it reports FW-down, returns MSA permissions to HLOS and marks
   recovery. On reconnection it always rebuilds host-capability and MSA/SCM
   state, calls qcacld `shutdown`, restores power, calls `reinit`, and reports
   FW-ready. System suspend/resume, noirq suspend/resume and platform shutdown
   are forwarded to qcacld.

Explicit `icnss_trigger_recovery()` can quiesce qcacld and request WLFW OFF,
but mainline has no equivalent of Xiaomi's downstream
`service_notif_pd_restart()`. Service-loss/reconnect recovery is implemented;
host-triggered PDR equivalence remains a hardware-observed limitation and must
not be treated as proven until an actual firmware assert/restart succeeds.

### Patch ledger

| Patches | Result |
|---|---|
| `0009`-`0024` | Add the ICNSS ABI and port the historical CAF qcacld/QDF/HDD/cfg80211 code to current kernel APIs. |
| `0025` | Replace the fail-closed scaffold with the WCN3990 platform, WLFW QMI, power, MSA/SCM, CE IRQ and client-lifecycle backend. |
| `0026`-`0027` | Implement ATHDIAG QMI transactions and keep ICNSS explicit-load-only so ath10k remains the safe boot default. |
| `0028`-`0037` | Complete time, logging, feature-gating, HIF/NAPI, packet-fate and module-aware SNOC/ICNSS integration. |
| `0038` | Restore the selected SDM660/QCA_WIFI_3_0 feature profile, including LFR, TDLS, FILS, 11w, NAN/NDP, spectral, fastpath, NAPI, flow control and coexistence gates. |
| `0039`-`0046` | Port modern skb, cfg80211 MLO/link, TDLS, NAPI, CPU-hotplug, procfs and DMA-direction APIs. |
| `0047` | Pass the real platform device to qcacld's crash callback. |
| `0048` | Match Xiaomi recovery ordering, never skip MSA/SCM rebuild on reconnect, and forward shutdown plus PM lifecycle callbacks. |

### Reproducible build evidence

Run `wsl-build-qcacld-r37.sh`. It copies the complete declared source list to
the pmbootstrap cache, performs a forced clean package build, writes
`qcacld-r37-build.log`, and atomically finishes
`qcacld-r37-build.status` as `BUILD_OK`.

Final kernel package:

```text
linux-postmarketos-qcom-sdm660-6.19.10-r37.apk
SHA256 be02b64b769124441cfdfa0597225de6873adb4bf9b378b5a2ac6f3c35e23c92
```

The log contains clean modpost and final link/install/compression records for:

```text
drivers/staging/qcom_icnss_clover/qcom-icnss-clover.ko
drivers/staging/qcacld-3.0/wlan.ko
```

The only modpost warning is the pre-existing, unrelated missing description
on `drivers/iio/common/qcom_smgr/qmi/sns_smgr.o`. Final packaged metadata was
inspected directly:

```text
wlan: depends=qcom-icnss-clover,cfg80211
wlan: vermagic=6.19.10-sdm660 SMP preempt mod_unload aarch64
qcom_icnss_clover: depends=qmi_helpers
qcom_icnss_clover: vermagic=6.19.10-sdm660 SMP preempt mod_unload aarch64
```

`nm -u wlan.ko` shows 21 real ICNSS imports, including registration,
configuration/mode, CE IRQ, power, SMMU, ATHDIAG and recovery calls. Patch
`0027` deliberately removes the backend's OF module alias; it cannot coldplug
and race ath10k. The device switcher explicitly loads the backend before
`wlan`, so it does not rely on a pre-install `modules.dep` file.

The matching device package is built reproducibly with
`wsl-build-clover-device-r9.sh`. It installs Xiaomi's configuration at the
exact path embedded in `wlan.ko`,
`/lib/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini`. Its
`clover-wifi-driver try-qcacld` operation
stops NetworkManager, unloads ath10k, explicitly loads ICNSS then qcacld, waits
up to 30 seconds for the async WLFW path, verifies platform ownership and
`wlan0`, and automatically restores ath10k on every failure path.

The packaged LF-normalized INI has SHA256
`b131dbbd20a315b4442c0bd0c019f184f117818f707c204a565fbaac468183fa`;
its settings are unchanged from the pinned Xiaomi SDM660-common source.

```text
device-xiaomi-clover-11-r9.apk
SHA256 ab1a3836d58ab5d4a3e8a62d6c931d25613ec84a861ae38e98a3e86de87fb1d5
```

### Install and one-boot trial without fastboot

Do this only after SSH to `172.16.42.1` is available:

```sh
scp linux-postmarketos-qcom-sdm660-6.19.10-r37.apk \
    device-xiaomi-clover-11-r9.apk zxk@172.16.42.1:/tmp/
ssh zxk@172.16.42.1 \
  'sudo apk add --allow-untrusted /tmp/linux-postmarketos-qcom-sdm660-6.19.10-r37.apk /tmp/device-xiaomi-clover-11-r9.apk && sudo reboot'
```

After SSH returns, confirm the new kernel and start the reversible trial:

```sh
ssh zxk@172.16.42.1 'sudo clover-wifi-driver status'
ssh zxk@172.16.42.1 'sudo clover-wifi-driver try-qcacld'
```

`try-qcacld` changes nothing persistent. Do not run `use-qcacld` until all
acceptance tests pass.

### Hardware proof required

On the tablet, capture all of the following after `try-qcacld`:

```sh
readlink -f /sys/bus/platform/devices/18800000.wifi/driver
ip -details link show wlan0
iw dev wlan0 scan
nmcli device wifi list
dmesg | grep -Ei 'icnss|wlan|wlfw|qmi|remoteproc|firmware|assert|BUG|WARNING'
```

Success requires the `icnss-clover` platform owner, factory MAC, scan,
association, DHCP and bidirectional traffic. Before making qcacld permanent,
also require 100 disconnect/reconnect cycles, 2.4 and 5 GHz, multiple BSSIDs,
suspend/resume, AP, P2P, roam, regulatory and Bluetooth coexistence, with no
firmware assert, kernel warning or recovery loop.

### Rollback

While the tablet still boots, no fastboot is needed:

```sh
sudo clover-wifi-driver use-ath10k
```

If r37 itself regresses boot but SSH still works, reinstall the known-good
`linux-postmarketos-qcom-sdm660-6.19.10-r35.apk` (SHA256
`9ceee03450b947a74f439dee459199729ab5cd8ba3e0ae6a524465a88c38de74`)
and reboot. `boot-r27-known-good.img` is only the emergency fastboot fallback
when the system no longer boots or exposes SSH.

Historical note: at the time r37 was documented, the tablet was not visible
over SSH, ADB or fastboot, so runtime success was not yet proven. This is no
longer the current device status; see the authoritative r44 handoff below.

---

# Authoritative handoff after r44 (2026-07-21)

This section supersedes every earlier statement about the current driver,
runtime status, source provenance, and next steps. Earlier sections are kept
only as a chronological engineering record.

## Read this first

The project is **not finished**. Do not enable qcacld persistently and do not
claim that Wi-Fi works under qcacld. Kernel r44 proves that the Linux 6.19
ICNSS/platform foundation can boot WCN3990 and scan, but its CAF qcacld
5.1.1.28U host stack makes the WLAN firmware assert during association. The
tablet is intentionally back on the working `ath10k_snoc` fallback.

The next task is not to discard the whole port. Keep the Linux 6.19 ICNSS and
hardware integration, but replace the three mutually coupled WLAN trees with
Xiaomi's published 5.2 source set and adapt the existing compatibility work to
that set:

```text
KEEP / ADAPT                         REPLACE AS ONE MATCHED SET
---------------------------------    -----------------------------------
qcom-icnss-clover Linux 6.19 glue    qcacld-3.0 5.1.1 -> Xiaomi 5.2.03.13E
WLFW QMI over QRTR                   qca-wifi-host-cmn from old CAF input
regulators, clocks, MSA and SCM      fw-api from old CAF input
CE IRQ handling and SMMU plumbing   source-specific 5.1 compatibility hunks
package, switcher and rollback
```

Never mix qcacld, qca-wifi-host-cmn, or fw-api revisions. Their WMI/QDF/HIF
interfaces form one source-level and firmware-facing unit.

## What r38-r44 established on real Clover hardware

The r37 package booted but revealed several modern-kernel compatibility bugs.
Each later package fixed one observed failure:

| Package | Change and observed result | APK SHA-256 |
|---|---|---|
| r38 | Treat non-negative `qmi_txn_wait()` returns as successful decoded lengths. | `1d5a4932567a35c39712e21b386c53e7a7dc4969d146ac840fc5ab8fd8737d73` |
| r39 | Treat positive `qmi_txn_init()` transaction IDs as success. | `9206397ac0be4ae38673607d0479d7a0701274e333d3b0a76adc52fa0d61095a` |
| r40 | Give legacy QCA vendor commands a policy so Linux 6.19 permits `wiphy_register()`. | `44b8b1dfe8fd5b977b4e023ec652ea11c799fd701eaf62aabdd44248705c3c17` |
| r41 | Use `eth_hw_addr_set()` instead of writing `dev_addr`; netdevice address warnings disappear. | `36805f5b20c97b84ed5973a233344f8df207c0f4fd4020a851e6c9d549d53dd6` |
| r42 | First zero-maxattr vendor-policy attempt; rejected with `Unknown attribute type`. | `9399193590a2a8e29231e124d786db174071003737c0a77e8a9afa0665073e4f` |
| r43 | Typed Wi-Fi configuration policy; registration advanced, but trigger-scan still rejected nested data. | `04c30b5082b70a1e56a7cffc237e11c3c943dae147f2a2e77846b8b3111044ae` |
| r44 | Complete scan policy and assign it to QCA trigger-scan. Repeated real 2.4 and 5 GHz scans pass. | `87f982e0e1a1a8490c98e663ed424a9f1e3a7f95c8ddbfb6b1d54d8feb760465` |

Current acceptance status:

| Requirement | r44 result |
|---|---|
| Kernel boots; ICNSS and `wlan.ko` load | PASS |
| ICNSS owns `18800000.wifi` during guarded trial | PASS |
| `wlan0` appears with factory-derived MAC | PASS |
| Repeated 2.4 GHz and 5 GHz scans | PASS |
| Associate to AP | PARTIAL: reaches association and WPA four-way handshake |
| Stable firmware after association | FAIL: modem/WLAN remoteproc asserts in `whal_tracer.c` |
| DHCP and bidirectional traffic | FAIL because firmware has asserted |
| Recovery after firmware assertion | FAIL/incomplete; WMA requests time out and scans remain pending |
| Safe default after reboot | PASS: `ath10k_snoc`, not qcacld |

One known r44 cfg80211 issue remains independently of the firmware assertion:
QCA vendor subcommand 145, `QCA_NL80211_VENDOR_SUBCMD_ABORT_SCAN`, still uses
the raw compatibility policy and can fail with `-EINVAL` for nested data. It
uses the same scan attributes as trigger-scan and should receive the typed
`scan_policy` while porting the Xiaomi 5.2 tree.

## Why the source correction is necessary

The r44 source manifest identifies three separate CAF mirror commits:

```text
qcacld-3.0:        fe68324678b317ebf9a697328691f9a006402ae8
qca-wifi-host-cmn: 0cf2f732b0dec50aba4266ee42de7637b42a0fd2
fw-api:            b87a08f721ee111ff6da6e59a0b95b34ca97c8e5
driver version:    5.1.1.28U
```

Those inputs were useful for building the Linux 6.19 scaffold, but they are
not Xiaomi's published WLAN implementation. Xiaomi publishes WLAN separately
at `https://github.com/MiCode/vendor_qcom_opensource_wlan`. There is no known
public `clover` branch in that repository. The nearest published Xiaomi
SDM660/WCN3990 generation found is `jasmine-q-oss`, already cloned locally as
`xiaomi-wlan-jasmine-q-oss/`:

```text
repository:     MiCode/vendor_qcom_opensource_wlan
branch/source:  jasmine-q-oss
commit:         728ac0be7512264ecdc3bf885a19c581c6890c17
contents:       qcacld-3.0 + qca-wifi-host-cmn + fw-api in one matched tree
driver version: 5.2.03.13E
```

Calling this tree “byte-for-byte Clover source” would also be inaccurate. It
is Xiaomi's closest publicly available same-SoC/same-WLAN-generation source
and is the correct next reconstruction baseline unless an actual Clover WLAN
source release is found. Keep that distinction explicit in package comments,
commit messages, and future documentation.

The failure boundary supports this correction: r44 successfully completes
platform startup and scans, then the firmware asserts immediately around the
join/WPA path. That is consistent with a host/WMI generation mismatch, though
it is not absolute proof; DMA/IOMMU or another porting defect must remain in
the differential diagnosis until Xiaomi 5.2 completes association.

## Stock Clover files recovered from the tablet

The original Android partitions are intact and mounted read-only:

```text
/run/msm-firmware-loader/mnt/vendor   (original vendor partition)
/run/msm-firmware-loader/mnt/persist  (original persist partition)
```

The non-private configuration reference is retained in `stock-clover-wifi/`.
The two device-unique MAC backups were inspected and hashed during diagnosis,
then deliberately removed before preparing the shareable project archive:

| File | Original source | SHA-256 |
|---|---|---|
| `stock-WCNSS_qcom_cfg.ini` | `/vendor/etc/wifi/WCNSS_qcom_cfg.ini` | `2c94fbfebed16c622ea7cf29462575bd1c0b9baf5a40c68cb8e8ad995a57a333` |
| `stock-wlan_mac.clover` (not retained) | `/persist/wlan_mac.clover` | `c875f87670b36c257c70278be9e214ce5f9f62c9fa8e64d020a2dbe98a208c33` |
| `stock-wlan_mac.bin` (not retained) | `/persist/wlan_mac.bin` | `dd548e7b803a6cb86e16f43d65ba60078566ae4fcccf491c0017e6f28cbd45be` |

The MAC files are unique to this physical tablet. They are diagnostic backups,
not redistributable package payloads. A device package must reference the
mounted persist file at runtime; it must never embed these copied MAC files.

The stock INI differs significantly from the earlier generic SDM660 INI. With
the old 5.1 driver, the exact stock INI triggers an early kernel oops through
`wlan_hdd_init_chan_info()` / `sme_set_chan_info_callback()` when
`gEnableSNRMonitoring=1`, because the old path uses an unready `hHal`. Changing
only that setting to `0` allows r44 to load and scan, but association still
causes the firmware assertion. Xiaomi 5.2 initializes the feature through its
newer MAC-handle/lifecycle path, another concrete reason to port the matched
tree. Retest the unmodified stock value `gEnableSNRMonitoring=1` only after the
5.2 initialization path has been built and reviewed.

## Current tablet and workspace state

At this handoff the tablet runs package r44 and reports kernel
`6.19.10-sdm660 #45-aarch64`, but the active/default Wi-Fi driver is the safe
`ath10k_snoc` path. NetworkManager has `wlan0` connected to the saved
`Yabloko-r3-test` profile. The live qcacld configuration file is the stock INI
with only `gEnableSNRMonitoring=0`, and `wlan_mac.bin` is linked to the mounted
persist source. These live filesystem changes have not yet been reproduced in
the device package.

Important workspace paths:

```text
pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660/
    current historical r44 APKBUILD and patches 0009-0053
pmaports-clover-rootfix/device/testing/device-xiaomi-clover/
    driver switcher and device firmware/config packaging
xiaomi-wlan-jasmine-q-oss/
    clean Xiaomi 5.2.03.13E source candidate
_r40_qcacld/
    expanded historical 5.1 source useful for comparisons
stock-clover-wifi/
    stock INI reference only; private device MAC copies were removed
```

## Exact next implementation sequence

1. Preserve r44 as the known scanning checkpoint. Do not overwrite its APK or
   renumber/reinterpret patches 0009-0053.
2. In a separate scratch kernel tree, replace qcacld-3.0,
   qca-wifi-host-cmn, and fw-api together with the three directories from
   Xiaomi commit `728ac0be7512264ecdc3bf885a19c581c6890c17`.
3. Reapply concepts, not patches blindly. Start with build integration and the
   existing `qcom-icnss-clover` ABI; then port only Linux 6.19 API adaptations
   that the Xiaomi source actually needs. Several old hunks will already be
   implemented differently in 5.2.
4. Preserve the SDM660 `QCA_WIFI_3_0` feature profile, but compare every
   feature define against Xiaomi 5.2's own Android makefiles/Kbuild rather than
   copying the historical 5.1 define list unchanged.
5. Port typed Linux 6.19 cfg80211 vendor policies, including both trigger-scan
   and abort-scan. Never solve registration by accepting unbounded arbitrary
   netlink data.
6. Build cleanly, inspect module dependencies/vermagic/unresolved symbols, and
   package it as a new revision. Keep ath10k as boot default.
7. Use only `clover-wifi-driver try-qcacld` for the first hardware run. Confirm
   ownership, factory MAC, repeated scans, association, WPA completion, DHCP,
   traffic, and a clean dmesg before any persistence test.
8. If firmware still asserts, capture the first assertion and preceding WMI
   commands before experimenting. Compare target/host capability exchange,
   service-ready parsing, CE configuration, DMA mappings, and stock Xiaomi
   feature flags. Do not hide or automatically retry the first failure.
9. Only after basic connectivity passes, test firmware recovery, 100 reconnect
   cycles, both bands, suspend/resume, roam, regulatory behavior, AP/P2P, and
   Bluetooth coexistence.
10. `use-qcacld` is forbidden until all acceptance tests pass without firmware
    assertions, kernel warnings, or recovery loops. On every failed guarded
    trial, restore `use-ath10k`, restore NetworkManager autoconnect, and reboot
    if the remoteproc asserted.

## Definition of done

The goal is not done merely because the module compiles, loads, produces
`wlan0`, or scans. It is done only when the Xiaomi 5.2-based port completes
normal encrypted association, DHCP and bidirectional traffic; survives the
stability matrix above; recovers cleanly from a controlled firmware restart;
boots with a reversible fallback; and the package reproduces all required
configuration without containing device-private MAC data.

# Authoritative r45 Xiaomi 5.2 port checkpoint (2026-07-21)

This section supersedes the **current-state and next-command portions** of the
r44 handoff above. The r44 hardware history and its acceptance results remain
valid. This is the exact stopping point for transfer to a new agent.

## Executive status

The project is **not complete** and r45 does **not** exist as a successful APK.
Do not install, advertise, or persist qcacld yet.

The real Clover ICNSS backend is already implemented in the kernel package by
patches `0025`, `0026`, `0047`, `0048`, `0049`, and `0050`. It is not a stub:
r44 exercised its WLFW QMI/QRTR startup, regulators/clocks, MSA, SCM, CE IRQ,
SMMU, athdiag, crash callback, recovery/PM lifecycle, and ownership of
`18800000.wifi` on the physical tablet. With the historical CAF 5.1 host tree,
it created `wlan0` and repeatedly scanned both bands. The remaining work is to
compile and integrate the **matched Xiaomi 5.2 host stack** against that real
backend, then prove association and stability on hardware.

Last verified safe tablet state (not re-queried while writing this handoff):

- kernel/APK r44, `6.19.10-sdm660 #45-aarch64`;
- default and active driver: `ath10k_snoc`;
- NetworkManager Wi-Fi working through the saved test profile;
- qcacld is not persistent;
- no r45 code has been installed on the tablet.

If the tablet state is uncertain in a later session, inspect it before doing
anything. Never infer that qcacld is active merely because r44 is installed.
Do not store SSH passwords, AP passwords, or a device-unique MAC in this file.

## Source and artifact checkpoint

The exact Xiaomi input remains the closest published same-SoC/same-WLAN
generation, not a byte-for-byte public Clover release:

```text
repository:       MiCode/vendor_qcom_opensource_wlan
published branch: jasmine-q-oss
base commit:      728ac0be7512264ecdc3bf885a19c581c6890c17
driver version:   5.2.03.13E
matched trees:    qcacld-3.0 + qca-wifi-host-cmn + fw-api
```

Important local artifacts:

| Artifact | Meaning | SHA-256 |
|---|---|---|
| `xiaomi-wlan-728ac0be7512264ecdc3bf885a19c581c6890c17.tar.gz` | Immutable Xiaomi source archive used by APKBUILD. | `ff63781263ee4c4f30b160f5f5392e53b4898960bd0bf6d15d226cddfb23a921` |
| `xiaomi52-linux-6.19-port-wip.patch` | Snapshot of every current dirty Xiaomi source edit, with paths rooted at `drivers/staging/`. | `15827e1e2ed4f3cf2700366305c4b98aa4c918fe2ab83d3a11377e23625a4d49` |
| `linux-postmarketos-qcom-sdm660-6.19.10-r44.apk` | Known scan-capable rollback/checkpoint kernel. | `87f982e0e1a1a8490c98e663ed424a9f1e3a7f95c8ddbfb6b1d54d8feb760465` |
| `incremental-qcacld-build.sh` | Fast compile-loop script for `wlan.o`. | `3e166e1f8f3cc062e24b5b520de5d162c98bb4f7b8b7ef8c5f3db1e5c47eb2f3` |
| `wsl-build-qcacld-r45.sh` | Full-package wrapper; currently incomplete because it only copies patch `0054`. | `865c5e75c02e05275ffc6960dda1d9aff74cd899e94e043d827371f945612942` |

The working checkout `xiaomi-wlan-jasmine-q-oss/` is deliberately dirty at
the base commit above. It contains 27 modified files, currently 297 insertions
and 93 deletions. Do not reset, clean, re-clone over, or bulk-normalize it.
Windows Git may print LF-to-CRLF warnings; do not mistake those warnings for
source changes.

The standalone WIP patch is a safety copy. This check succeeds against the
current dirty checkout and proves that the patch represents its contents:

```powershell
git -C xiaomi-wlan-jasmine-q-oss apply --check --reverse -p3 `
    ..\xiaomi52-linux-6.19-port-wip.patch
```

To reconstruct the edits in a **clean source-only checkout** at the named
commit, apply it with `-p3`:

```powershell
git -C xiaomi-wlan-jasmine-q-oss apply -p3 `
    ..\xiaomi52-linux-6.19-port-wip.patch
```

When applying it at a **Linux kernel root** after copying the three source
directories under `drivers/staging/`, do not strip path components:

```sh
git apply /path/to/xiaomi52-linux-6.19-port-wip.patch
```

## r45 package state

`pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660/APKBUILD`
is at `pkgrel=45` and now downloads the one matched Xiaomi archive instead of
the three old CAF inputs. `prepare()` copies all three matched WLAN trees into
`drivers/staging/` before `default_prepare` applies kernel patches.

The r45 source list intentionally retains the proven hardware foundation and
only the source-independent integration patches:

```text
0001 0002 0003 0004 0005 0007 0008
0009 0010 0018
0025 0026 0027
0047 0048 0049 0050
0054 (temporary/incomplete; see warning below)
```

Old CAF-5.1 compatibility patches still exist physically in the package
directory for history, but are no longer in APKBUILD's `source=` list. Do not
blindly re-enable them.

`0054-xiaomi52-fix-in-tree-kbuild-paths.patch` was the first Kbuild bootstrap.
It is now stale: its final hunk uses `subdir-ccflags-y`, which did not propagate
the Xiaomi feature definitions to every object in this composite module. The
current checkout correctly uses `ccflags-y += $(cppflags-y)` and also contains
the necessary local `CONFIG_ICNSS=m` normalization. Therefore:

- do not apply `0054` and the WIP patch together because their Kbuild hunks
  overlap;
- replace `0054` in APKBUILD with a finalized patch generated from the current
  WIP diff (for example `0055-xiaomi52-port-linux-6.19.patch`);
- update `wsl-build-qcacld-r45.sh` to copy the finalized patch;
- run `pmbootstrap checksum` before the clean package build.

`qcacld-r45-build.status` currently says `BUILD_FAILED`. The large
`qcacld-r45-build.log` is the earlier full-package attempt and predates most of
the incremental fixes below. There is no `linux-...-r45.apk`; success must not
be inferred from the wrapper's presence.

## Exact Linux 6.19 port work already present

All edits below are in both the dirty Xiaomi checkout and the WIP patch.

### Kbuild and exact Xiaomi/ICNSS feature profile

- Resolve `WLAN_ROOT` and the Linux include root through `$(srctree)` so an
  `O=out` build can find the Xiaomi profile and headers.
- Keep vendor warnings visible but non-fatal with `-Wno-error`.
- Propagate `cppflags-y` with `ccflags-y`, not kernel-global
  `KBUILD_CPPFLAGS` and not `subdir-ccflags-y`.
- The generated kernel configuration contains `CONFIG_ICNSS=m` and
  `CONFIG_QCA_CLD_WLAN=m`. Xiaomi's makefile tested ICNSS only as `y`, which
  silently omitted `pld_snoc.o`, `CONFIG_PLD_SNOC_ICNSS`, `QCA_WIFI_3_0`, and
  `WLAN_FEATURE_11W`. Kbuild now normalizes only its **local** view of
  `CONFIG_ICNSS` from `m` to `y`. `CONFIG_QCA_CLD_WLAN` remains `m`, so
  `qcom-icnss-clover.ko` and `wlan.ko` remain separate modules.
- A verbose compile confirmed the intended Xiaomi definitions, including
  `CONFIG_PLD_SNOC_ICNSS`, `QCA_WIFI_3_0`, Adrastea, MCL, PMO, P2P, TDLS,
  spectral, NAPI, FILS, SAE, roam, 11r, and `WLAN_FEATURE_11W`.

### QDF and core-kernel API adaptations

- Replace seven users of libc `<stdarg.h>` with `<linux/stdarg.h>` in QDF,
  DP, and MAC headers.
- Remove the obsolete `<asm/dma-iommu.h>` include; Xiaomi 5.2 already uses the
  current IOMMU-domain path in that function.
- Port boot/monotonic time to `ktime_get_boottime_ns()` and `ktime_get_ns()`.
- Preserve the Xiaomi Adrastea QTIMER tick semantics with the exported
  `arch_timer_read_counter()` from `<clocksource/arm_arch_timer.h>`; do not
  replace it with unrelated wall-clock nanoseconds.
- Replace `in_irq()` with `in_hardirq()`, `FIELD_SIZEOF` with `sizeof_field`,
  and the removed timer APIs with `timer_container_of`, `timer_delete`,
  `timer_delete_sync`, and `timer_destroy_on_stack`.
- Implement a `strlcpy` compatibility helper that preserves the historical
  source-length return and NUL-truncation behavior; use `strscpy` for QDF's
  own copy wrapper.
- Add narrow aliases needed by this vendor generation:
  `__ieee80211_get_channel`, `netif_rx_ni`, and
  `WLAN_EID_VHT_TX_POWER_ENVELOPE`.

### cfg80211, netlink, and netdev adaptations

- Port scan/BSS timestamps to exact nanosecond boottime APIs.
- Use `eth_hw_addr_set()` for station, AP, and generated hotspot addresses so
  modern netdev address lists remain synchronized.
- Store roam results in `cfg80211_roam_info.links[0].bss`.
- Replace removed `cfg80211_assoc_timeout()` with
  `cfg80211_assoc_failure()` and an explicit timeout structure.
- Add Linux 6.19 signature wrappers for change-beacon/AP update, stop AP,
  add/get/delete/default keys, wiphy parameters, TX power, default management
  key, TDLS management, AP channel width, and monitor channel. These wrappers
  compiled in the completed passes but still require final clean-build and
  runtime review.
- Port `cfg80211_ch_switch_notify(..., 0)`, use `wdev_chandef(wdev, 0)`, and
  use `wdev->links[0].client.current_bss` for connected scan state.
- Replace `nla_strlcpy` with truncation-aware `nla_strscpy` handling.
- Put FILS connection BSSID/BSS in `connect_resp.links[0]`.
- Replace removed `cfg80211_ap_stopped()` with `cfg80211_stop_iface()` and
  port `class_create()` to its one-argument form.
- Port `.ndo_tx_timeout` to accept the TX queue and `.ndo_select_queue` to the
  current three-argument form.
- Remove the unused Android-only `soc/qcom/subsystem_restart.h` include.
- The latest, **not yet recompiled**, edit includes `<net/gro.h>` so the
  current inline `napi_gro_flush()` is visible and changes
  `txq_trans_update(txq)` to `txq_trans_update(dev, txq)`.

### Files currently modified

```text
qca-wifi-host-cmn/dp/wifi3.0/dp_internal.h
qca-wifi-host-cmn/qdf/inc/qdf_trace.h
qca-wifi-host-cmn/qdf/inc/qdf_types.h
qca-wifi-host-cmn/qdf/linux/src/i_qdf_lock.h
qca-wifi-host-cmn/qdf/linux/src/i_qdf_mem.h
qca-wifi-host-cmn/qdf/linux/src/i_qdf_nbuf.h
qca-wifi-host-cmn/qdf/linux/src/i_qdf_str.h
qca-wifi-host-cmn/qdf/linux/src/i_qdf_time.h
qca-wifi-host-cmn/qdf/linux/src/i_qdf_timer.h
qcacld-3.0/Kbuild
qcacld-3.0/core/cds/src/cds_api.c
qcacld-3.0/core/dp/txrx/ol_txrx_internal.h
qcacld-3.0/core/hdd/inc/wlan_hdd_softap_tx_rx.h
qcacld-3.0/core/hdd/inc/wlan_hdd_tx_rx.h
qcacld-3.0/core/hdd/inc/wlan_hdd_wmm.h
qcacld-3.0/core/hdd/src/wlan_hdd_assoc.c
qcacld-3.0/core/hdd/src/wlan_hdd_cfg80211.c
qcacld-3.0/core/hdd/src/wlan_hdd_ext_scan.c
qcacld-3.0/core/hdd/src/wlan_hdd_hostapd.c
qcacld-3.0/core/hdd/src/wlan_hdd_main.c
qcacld-3.0/core/hdd/src/wlan_hdd_scan.c
qcacld-3.0/core/hdd/src/wlan_hdd_softap_tx_rx.c
qcacld-3.0/core/hdd/src/wlan_hdd_tx_rx.c
qcacld-3.0/core/hdd/src/wlan_hdd_wmm.c
qcacld-3.0/core/mac/src/include/parser_api.h
qcacld-3.0/core/mac/src/include/utils_api.h
qcacld-3.0/core/mac/src/sys/legacy/src/utils/inc/utils_parser.h
```

## Exact compiler frontier

The incremental build is inside the pmbootstrap native chroot:

```text
host-visible tree:
/home/xeonise/.local/var/pmbootstrap/chroot_native/home/pmos/build/src/linux-6.19.10-sdm660

inside native chroot:
/home/pmos/build/src/linux-6.19.10-sdm660

pmbootstrap log:
/home/xeonise/.local/var/pmbootstrap/log.txt
```

The last **completed** incremental pass reached
`core/hdd/src/wlan_hdd_tx_rx.c`. It reported only these new hard errors at its
frontier:

```text
napi_gro_flush: implicit declaration
txq_trans_update: expected (dev, txq), received (txq)
```

Both are fixed in the working source as described above, but the follow-up
compile was interrupted before producing a result. Therefore the next agent's
first action is to sync the current dirty files and rerun the incremental
build. Do not spend time re-fixing older errors still visible in cumulative
`pmbootstrap/log.txt`; those came from earlier passes and are already fixed.

From PowerShell in `D:\general\postm`, use:

```powershell
wsl -e sh -lc 'set -eu; HOST=$HOME/.local/var/pmbootstrap; SRC=/mnt/d/general/postm/xiaomi-wlan-jasmine-q-oss; TREE=$HOST/chroot_native/home/pmos/build/src/linux-6.19.10-sdm660; cd "$SRC"; git diff --name-only | while read f; do case "$f" in qcacld-3.0/*|qca-wifi-host-cmn/*|fw-api/*) sudo cp "$SRC/$f" "$TREE/drivers/staging/$f";; esac; done; sudo cp /mnt/d/general/postm/incremental-qcacld-build.sh "$HOST/chroot_native/tmp/incremental-qcacld-build.sh"; sudo chmod 755 "$HOST/chroot_native/tmp/incremental-qcacld-build.sh"; ~/.local/bin/pmbootstrap chroot --user --output stdout /tmp/incremental-qcacld-build.sh'
```

The script runs `olddefconfig` and then:

```sh
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-alpine-linux-musl- \
    CC=aarch64-alpine-linux-musl-gcc CFLAGS_MODULE=-fno-pic \
    -j8 drivers/staging/qcacld-3.0/wlan.o
```

Use `pmbootstrap chroot`; do not invoke raw `sudo chroot`, because the required
`/dev` and related mounts are not prepared by a raw chroot.

## Required continuation order

1. Run the exact incremental command above. Fix current Linux API errors in
   the Xiaomi checkout with small semantic changes, sync, and repeat until
   `drivers/staging/qcacld-3.0/wlan.o` succeeds.
2. Do not silence implicit declarations, incompatible pointers, missing
   objects, or modpost symbols with casts or blanket warning flags. Verify the
   modern API's semantics in the Linux 6.19 headers.
3. Regenerate `xiaomi52-linux-6.19-port-wip.patch` after meaningful edits so
   the standalone checkpoint stays current. Its paths must remain rooted at
   `drivers/staging/`.
4. Replace package patch `0054` with the consolidated final 5.2 port patch,
   update APKBUILD/wrapper/checksums, and run a **clean** r45 package build.
   An incremental `wlan.o` success is not package proof.
5. Inspect the built modules with `modinfo`, `readelf`/`nm`, and modpost output.
   Verify matching vermagic, no unresolved non-kernel symbols, and that
   `wlan.ko` uses the real `qcom-icnss-clover.ko` API. Verify that both remain
   modules and ath10k remains the boot default.
6. Update the Clover device package to ship the exact stock
   `stock-WCNSS_qcom_cfg.ini` and reference the mounted persist MAC at runtime.
   Never package a copied device-unique MAC. Retest stock
   `gEnableSNRMonitoring=1` only with the Xiaomi 5.2 initialization path.
7. Only after all build/static gates pass, install with the existing reversible
   package/switcher flow and use `clover-wifi-driver try-qcacld`. Never switch
   directly to persistent `use-qcacld` for the first trial.
8. Hardware gates are: real ICNSS ownership of `18800000.wifi`, factory MAC,
   repeated scans on both bands, encrypted association, WPA completion, DHCP,
   bidirectional traffic, clean dmesg, recovery from a controlled firmware
   restart, reconnect stress, suspend/resume, regulatory behavior, AP/P2P, and
   Bluetooth coexistence. Preserve the first firmware assertion if one occurs.
9. On any failed trial restore ath10k and NetworkManager autoconnect; reboot if
   the WLAN remoteproc asserted. Do not call the goal complete at load or scan.

## Copy-paste prompt for a new agent

```text
Work in D:\general\postm and continue the Xiaomi Mi Pad 4 (clover) WCN3990
kernel Wi-Fi port. Read FIX.MD completely, but treat the final section named
"Authoritative r45 Xiaomi 5.2 port checkpoint (2026-07-21)" as the current
state. Do not restart the design or revert the dirty source checkout.

Goal: finish and verify the real ICNSS-backed Xiaomi qcacld port on Linux
6.19. The kernel-side qcom-icnss-clover backend is already real and was
hardware-proven with r44 through dual-band scans. Preserve patches 0025/0026
and 0047-0050. The host stack is now the matched Xiaomi jasmine-q-oss 5.2.03.13E
tree at commit 728ac0be7512264ecdc3bf885a19c581c6890c17. Be explicit that this
is Xiaomi's closest published same-generation source, not a claimed public
byte-for-byte Clover release.

The working tree xiaomi-wlan-jasmine-q-oss has intentional Linux 6.19 edits.
Do not git reset/clean it. xiaomi52-linux-6.19-port-wip.patch is a safety
snapshot. The last completed incremental build reached wlan_hdd_tx_rx.c and
reported napi_gro_flush visibility plus the new txq_trans_update(dev, txq)
signature; both are already fixed in the current source, but that latest edit
has not yet been compiled. Start by running the exact incremental sync/build
command from the final FIX.MD section, then iterate on the next genuine errors.

When wlan.o succeeds, replace stale package patch 0054 with one consolidated
patch generated from the dirty Xiaomi diff, update APKBUILD,
wsl-build-qcacld-r45.sh, and checksums, then perform a clean package build and
module/modpost inspection. Do not install a partial build.

The tablet's last known safe state is r44 with ath10k_snoc active; no r45 code
is installed. Keep ath10k as default. Only after clean build/static gates use
the reversible clover-wifi-driver try-qcacld flow. Do not persist qcacld until
association, WPA, DHCP, bidirectional traffic, firmware recovery, stress,
suspend/resume, regulatory, AP/P2P, and Bluetooth coexistence tests pass with
no firmware assertion or kernel warning. Never embed the tablet's private MAC
or credentials in files or replies. Continue autonomously from evidence and
keep FIX.MD current as the authoritative handoff.
```

# Authoritative r46 Xiaomi 5.2 port checkpoint (2026-07-21)

This section supersedes the entire preceding r45 checkpoint. The r44 hardware
history remains valid. r46/r10 passed source, package, and module-linkage
gates, but the project is **not complete**: no r46 or r10 package has been
installed and no Xiaomi 5.2 hardware association test has been performed.

## Executive status

The real Clover ICNSS backend remains the hardware-proven implementation from
patches `0025`, `0026`, and `0047` through `0050`. It owns `18800000.wifi`
only during an explicit qcacld trial; `ath10k_snoc` remains the safe boot and
default driver. The last known tablet state is still r44/ath10k, not re-queried
during these package-only checks.

The old r45 APK is rejected as a test candidate. Its BusyBox `depmod` could not
read `.ko.zst`, so its shipped `modules.dep` omitted the real `wlan` to
`qcom-icnss-clover` dependency even though modpost metadata was correct. Do
not install r45. r46 adds `kmod` to the kernel package build dependencies;
the full depmod implementation reads compressed modules correctly. The build
wrapper now rejects an APK without that dependency edge.

## Source checkpoint

```text
repository:       MiCode/vendor_qcom_opensource_wlan
published branch: jasmine-q-oss
base commit:      728ac0be7512264ecdc3bf885a19c581c6890c17
driver version:   5.2.03.13E
matched trees:    qcacld-3.0 + qca-wifi-host-cmn + fw-api
```

This is Xiaomi's closest published same-generation source, not a claimed
byte-for-byte public Clover release. The deliberately dirty
`xiaomi-wlan-jasmine-q-oss/` checkout must not be reset, cleaned, recloned, or
line-ending-normalized. The current safety snapshot is:

| Artifact | Meaning | SHA-256 |
|---|---|---|
| `xiaomi52-linux-6.19-port-wip.patch` | All intentional Linux 6.19 Xiaomi source edits, rooted at `drivers/staging/`. | `93668c6db73d4afdc875be5f453bf8aeceb6ac67e2acbd37bbeca7b05d371b86` |
| `linux-postmarketos-qcom-sdm660-6.19.10-r46.apk` | Clean, uninstalled Xiaomi 5.2 kernel candidate. | `87a9d0e766266176cbde5d695bc60df38e612524293e4dfb426b5a9a7251f8d4` |
| `device-xiaomi-clover-11-r10.apk` | Clean, uninstalled device-package candidate. | `8d7d41d9fcdd2b3c602ca507391bb8b18040375deedb9722b7229ca3506d9c97` |

This reverse-apply check passed at the stated base commit. Git for Windows may
only emit harmless LF-to-CRLF notices:

```powershell
git -C xiaomi-wlan-jasmine-q-oss apply --check --reverse -p3 `
    ..\xiaomi52-linux-6.19-port-wip.patch
```

## Clean r46 kernel package result

`linux-postmarketos-qcom-sdm660/APKBUILD` is now `pkgrel=46`. It retains the
proven ICNSS patches and the consolidated `0055-xiaomi52-port-linux-6.19.patch`;
stale `0054` is not in `source=`. It also retains the exact matched Xiaomi
archive and runs `pmbootstrap checksum` through `wsl-build-qcacld-r45.sh`
(the historical filename now produces r46). `qcacld-r46-build.status` is
`BUILD_OK`; its log is `qcacld-r46-build.log`.

Module inspection of the uninstalled r46 APK passed:

- `wlan.ko` and `qcom-icnss-clover.ko` are separate AArch64 modules with
  matching `6.19.10-sdm660 SMP preempt mod_unload aarch64` vermagic.
- `wlan.ko` declares `cfg80211,qcom-icnss-clover`; `modules.dep` orders
  `qcom-icnss-clover.ko.zst` before `wlan.ko.zst` and also records cfg80211,
  rfkill, and qmi helpers as required.
- `nm -u` shows the expected real ICNSS imports in `wlan.ko`; they resolve to
  exported symbols in `qcom-icnss-clover.ko`. No unresolved non-kernel module
  symbol was reported by modpost.
- `MODPOST Module.symvers` passed. Its only warning is the unrelated existing
  missing `MODULE_DESCRIPTION()` in `drivers/iio/common/qcom_smgr/qmi/sns_smgr.o`.

## Clean r10 device package result

`device-xiaomi-clover/APKBUILD` is now `pkgrel=10` and
`qcacld-r46-device-r10-build.status` is `BUILD_OK`. The packaged
`WCNSS_qcom_cfg.ini` byte-matches the non-private
`stock-clover-wifi/stock-WCNSS_qcom_cfg.ini` reference (SHA-256
`2c94fbfebed16c622ea7cf29462575bd1c0b9baf5a40c68cb8e8ad995a57a333`), including
the stock `gEnableSNRMonitoring=1` setting. The package contains no
device-unique MAC copy: `wifi-macaddr.sh` reads only the mounted persist paths
at runtime and validates the result before applying it. Its checksum is
regenerated by `wsl-build-clover-device-r9.sh` (the historical filename now
produces r10).

## Required next action

Do not treat the build as Wi-Fi success. First inspect the tablet's actual
state and keep ath10k as default. Only then install the complete r46 and r10
APK set through the existing reversible flow and run
`clover-wifi-driver try-qcacld`; never run `use-qcacld` first. Require real
ICNSS ownership, factory MAC from mounted persist, dual-band scans, encrypted
association, WPA completion, DHCP, bidirectional traffic, clean dmesg,
controlled recovery, reconnect stress, suspend/resume, regulatory, AP/P2P,
and Bluetooth-coexistence tests. On any failure restore ath10k and
NetworkManager autoconnect, reboot after a remoteproc assertion, and preserve
the first assertion plus preceding WMI logs. Never add credentials or a
device-unique MAC to source, patches, logs, or this file.

## Installation checkpoint

On 2026-07-21, the complete `linux-postmarketos-qcom-sdm660-6.19.10-r46` and
`device-xiaomi-clover-11-r10` APKs were transferred with verified SHA-256
digests and upgraded together. Package triggers regenerated and flashed the
boot image. After one reboot, the tablet reported
`6.19.10-sdm660 #47-aarch64`; package versions report r46 and r10.

The post-boot driver check passed with `ath10k_snoc` active and default,
qcacld modules merely available, and no qcacld persistence file. No
`clover-wifi-driver try-qcacld` trial has run yet. The next hardware action
must remain that reversible guarded command, followed by the full association,
WPA, DHCP, traffic, recovery, and stability matrix above.

## First r46 guarded trial (failed, recovered)

The first `clover-wifi-driver try-qcacld` run on r46 was attempted only after
the post-install boot check confirmed ath10k as the default driver. It failed
before creating `wlan0`; this is not a scan or association success.

Observed sequence from the redacted previous-boot kernel record:

- The real `qcom-icnss-clover` module registered, but reported WLFW
  initialization status `-121`.
- Xiaomi 5.2 reached firmware service-ready handling, then `wiphy_register()`
  warned and `wlan_hdd_cfg80211_register()` failed. The host startup returned
  `-EIO`; ICNSS reported the qcacld ready callback failure, and the guarded
  script timed out without `wlan0`.
- The ath10k teardown around the guarded handoff also coincided with a WLAN
  remoteproc fatal assertion. In-place ath10k restore could not reacquire its
  IRQ, so the script correctly did not leave a false success state.

Per the recovery rule, the tablet was rebooted immediately. It returned on
r46 (`#47-aarch64`) with `ath10k_snoc` active, ath10k still the default,
NetworkManager connected, qcacld non-persistent, and no second qcacld trial.
The redacted evidence is retained locally in
`qcacld-r46-first-try-redacted.log`; its MAC-literal scan is clear.

Do not repeat `try-qcacld` until the source failure is fixed. Start with the
Linux 6.19 `wiphy_register()` warning/registration invariants in the Xiaomi
cfg80211 path, the preceding WLFW `-121`, and the NAPI teardown warnings seen
during failed startup. Rebuild and repeat all static package gates before one
new guarded trial. Keep the first assertion record; do not mask it with retry
logic or make qcacld persistent.

## Second r46 guarded trial (failed, recovered)

On 2026-07-21 a second explicit `clover-wifi-driver try-qcacld` request was
run from the verified r46 ath10k-safe state. It remained reversible and did
not invoke `use-qcacld`. The switcher reported a segmentation fault during
qcacld startup, declared the qcacld load failed, and attempted its ath10k
restore. At that point neither driver owned a usable `wlan0`; both the qcacld
and ath10k modules were resident, so the normal recovery rule required a
reboot.

The redacted live kernel evidence confirms this is a source failure, not a
test success or an association failure:

- The guarded ath10k handoff triggered a WLAN remoteproc fatal assertion and
  its automatic remoteproc recovery before the ICNSS backend registered.
- `qcom-icnss-clover` again reported WLFW initialization status `-121`.
- During the Xiaomi HDD registration path, Linux 6.19 reported an invalid
  paging access and a `wiphy_register()` warning at `net/wireless/core.c:976`.
  The stack includes `wlan_hdd_cfg80211_register()`, `wlan_hdd_pld_probe()`,
  and `wlan_hdd_register_driver()`; a second kernel paging fault followed
  teardown. This identifies the actual registration invariant/crash path that
  must be fixed before another hardware attempt.

The tablet was rebooted immediately. The post-reboot state is again safe:
`ath10k_snoc` and `ath10k_core` are loaded, qcacld/ICNSS modules are absent,
`wlan0` exists, and NetworkManager is connected. ath10k remains the default;
no qcacld persistence setting was created.

Do not run a third `try-qcacld` attempt on this build. The dirty Xiaomi source
now restores the r44-proven vendor-command bridge: typed policies for Wi-Fi
configuration and trigger-scan, and `VENDOR_CMD_RAW_DATA` for the remaining
legacy handlers. The WIP and package 0055 patches were regenerated together
(SHA-256 `27b975bb8c3a235e6dd03a0d608e01d98df8a63b1a2db9edd8ce4a0076a1ea52`)
and pass the reverse-apply check. This source change is not yet compiled: the
old incremental tree was removed by the clean r46 build. Recreate it through a
clean r47-or-newer package build, inspect module and modpost results, then run
one new guarded trial. The teardown/remoteproc assertion remains a separate
failure to investigate after registration succeeds.

# Authoritative r48 Xiaomi 5.2 port checkpoint (2026-07-21)

This section supersedes the r46 checkpoint for the next implementation step.
The project is **not complete**: r48 reaches association, but not WPA, DHCP,
or traffic. Keep ath10k as the persistent/default driver.

## r47 result

r47 built cleanly from the Xiaomi `jasmine-q-oss` 5.2.03.13E source with the
Linux 6.19 vendor-command policy repair. It passed package, modpost, vermagic,
module-dependency, and real ICNSS import/export checks. Its APK SHA-256 is
`45592bbbed31b2efd1a0a4bcc2b572e98cae70de96977ca7f3b363544b7f8f55`.

The guarded r47 trial passed the prior `wiphy_register()` failure and created
`wlan0`, but the WLAN scheduler faulted in optional pktlog telemetry
(`pktlog_enable()` through `wma_mc_process_handler()`). The tablet was
rebooted to ath10k. Do not retry r47.

## r48 build and static result

r48 sets the Xiaomi established `CONFIG_REMOVE_PKT_LOG := y` profile gate in
`qcacld-3.0/configs/default_defconfig`. It removes pktlog objects and
`pktlog_*` symbols while preserving the normal ICNSS, cfg80211, and data path.
The consolidated WIP and package `0055` patch SHA-256 is
`27b975bb8c3a235e6dd03a0d608e01d98df8a63b1a2db9edd8ce4a0076a1ea52`.

The clean r48 package build is `BUILD_OK`; the APK SHA-256 is
`aaee982ea76b31139158c6d493856deab622c4d150a4cae1895e8162f33bc075`.
`wlan.ko` and `qcom-icnss-clover.ko` are separate AArch64 modules with the
same `6.19.10-sdm660 SMP preempt mod_unload aarch64` vermagic. `modules.dep`
orders the real ICNSS module before wlan and records cfg80211, rfkill, and QMI
helpers. Every `icnss_*` import in wlan resolves to a real ICNSS export;
modpost reported no unresolved module symbol. The only modpost warning remains
the unrelated missing `MODULE_DESCRIPTION()` in qcom_smgr.

## r48 guarded hardware result (failed, recovered)

r48 was installed as a complete kernel package, then rebooted with ath10k
still default. One `clover-wifi-driver try-qcacld` trial transferred ownership
to real `qcom-icnss-clover`, created `wlan0`, and reached association. The
driver exchanged WPA EAPOL M1 and M2, then WCN3990 asserted in
`whal_tracer.c`; remoteproc recovered and ICNSS subsequently reported an MSA
memory-assignment failure. WPA completion, DHCP, and traffic therefore did not
pass. This is not a Wi-Fi success.

The first assertion record is retained in `qcacld-r48-trial-redacted.log` and
contains no credentials or device-unique MAC literal. The tablet was rebooted
after recovery; post-reboot verification shows r48 with `ath10k_snoc` loaded,
ath10k default, and NetworkManager connected. qcacld remains non-persistent.

## Required r49 direction

The generic Xiaomi `default_defconfig` is an Android diagnostic profile in
this standalone build: it enables `BUILD_DEBUG_VERSION`, `BUILD_DIAG_VERSION`,
PTT sockets, the WLAN logging socket, firmware-log parsing, DP/MTRACE trace
recording, and non-user debug features. The r48 trace contains repeated PTT
send failures immediately before the firmware failure. The next change is a
dedicated Clover shipment profile that keeps the matched Xiaomi functional
SNOC/Adrastea settings and pktlog removal, but disables those optional debug
and firmware-telemetry paths through their existing feature gates. Rebuild and
pass all package/static checks before exactly one new guarded hardware trial.

If r49 still asserts after EAPOL M2, do not retry it unchanged. Instrument the
host-side WMI/key-install boundary narrowly, then audit service-ready
capabilities, board/regulatory data, and the Xiaomi-versus-Clover firmware ABI
assumptions one semantic change at a time.

# Authoritative r49 Xiaomi 5.2 port checkpoint (2026-07-21)

r49 is a clean, uninstalled Clover shipment-profile candidate built from the
same matched Xiaomi `jasmine-q-oss` 5.2.03.13E source at
`728ac0be7512264ecdc3bf885a19c581c6890c17`. This refers only to the closest
published vendor WLAN source; it does not change Clover's ICNSS backend,
device tree, firmware/configuration, or ath10k-safe default.

The new `clover_defconfig` keeps the Xiaomi SNOC/Adrastea functional profile
and the r48 pktlog removal, while disabling debug build flags, debug crash
injection, normal WLAN debugfs, firmware-log parsing, PTT and WLAN logging
sockets, trace recording, MTRACE, DP trace, HTC credit history, and related
debug controls. Xiaomi's `BUILD_DIAG_VERSION`, power-stat compile gate, and
internal WMI event logging remain enabled because its always-built station,
EAPOL, sysfs, and WMI objects require their API definitions; they are not the
external PTT/logging transports removed above.

The consolidated WIP and package `0055` patch SHA-256 is
`445df294113958dac4136f459188bb650a62c5729f4b88b4ab45276d721c9d20`.
It reverse-applies cleanly to the Xiaomi base. `APKBUILD` is `pkgrel=49` and
its `0055` SHA-512 is synchronized. `wsl-build-qcacld-r45.sh` produced
`BUILD_OK`; the uninstalled r49 APK SHA-256 is
`68c645fb30d3b42fc9ca8d927b516cdf27149f740ac319f662f627db7b7245ca`.

The r49 APK inspection passed: `wlan.ko` and `qcom-icnss-clover.ko` are
AArch64 and have matching `6.19.10-sdm660 SMP preempt mod_unload aarch64`
vermagic; wlan depends on `cfg80211,qcom-icnss-clover`; `modules.dep` orders
the real Clover ICNSS backend before wlan; and every `icnss_*` wlan import
resolves to a backend export. `MODPOST Module.symvers` has no qcacld/ICNSS
unresolved symbols; its only warning remains the unrelated qcom_smgr missing
`MODULE_DESCRIPTION()`. There are no pktlog, PTT socket, or WLAN logging
socket imports or symbols under their actual symbol prefixes. Identifiers
containing `nopktlog` are normal non-pktlog CE configuration names and are not
pktlog objects.

No r49 package has been installed and no r49 hardware trial has run. The
tablet remains on r48 with ath10k persistent/default and NetworkManager
connected. The next authorized device action is to install the complete r49
kernel package, reboot and verify ath10k-safe state, then run exactly one
reversible `clover-wifi-driver try-qcacld` trial. Require association, WPA
completion, DHCP, bidirectional traffic, controlled recovery, and stability
tests before declaring Wi-Fi functional. Do not use `use-qcacld` or install
partial output.

## r49 installation checkpoint

The verified r49 APK (SHA-256
`68c645fb30d3b42fc9ca8d927b516cdf27149f740ac319f662f627db7b7245ca`)
was fetched directly by the tablet and rechecked locally before installation.
`apk add --allow-untrusted --upgrade` completed from r48 to r49, regenerated
the initramfs, and boot-deploy flashed the new `boot.img`; reboot was then
issued. The package was locally built and therefore required the explicit
local-file `--allow-untrusted` flag after hash verification.

At the time of this checkpoint, the tablet did not return to the network after
the reboot. No post-boot version/driver verification and no r49 qcacld trial
has run. Do not infer boot success, association, WPA, DHCP, or traffic from the
successful package transaction. Once the tablet is reachable, first verify r49
with ath10k as the default driver, then perform only the guarded
`clover-wifi-driver try-qcacld` flow.

## Authoritative r49 guarded trial result

r49 did boot and the post-boot safety gate passed: the installed package is
`linux-postmarketos-qcom-sdm660-6.19.10-r49`, ath10k owned the WLAN interface,
ath10k remained the default selection, and no qcacld persistence file was
present. One and only one guarded `clover-wifi-driver try-qcacld` command was
then run; it reported qcacld active for that boot only.

The hardware result failed. The real `qcom-icnss-clover` backend took driver
ownership, but boolean-only probes found no association, WPA completion, DHCP
lease, or outbound traffic. The firmware-fault probe was positive. This is not
an association or module-load success and r49 must not be retried unchanged.
No network identifiers, credentials, or device-unique MAC data were retained.

Recovery to ath10k and a reboot were requested immediately after the failed
probe. The control session was interrupted before recovery completion could be
confirmed, so the current driver and reboot state must be checked once the
tablet is available; do not assume either outcome. Keep qcacld non-persistent.

The next source work is not another profile toggle. Capture a redacted first
firmware assertion and the narrowly preceding host-side WMI/key-install path,
then audit the Xiaomi-to-Clover firmware ABI, service-ready capabilities, and
board/regulatory assumptions one semantic change at a time. Rebuild and pass
all static gates before one subsequent guarded trial. The objective is a
qcacld session that completes association, WPA, DHCP, traffic, recovery, and
stability without triggering a firmware assertion or requiring a reboot.

## r49 regression note

This is a regression in observed hardware milestones, not a completed Wi-Fi
port. The r44 real-ICNSS build performed dual-band scans, and r48 progressed
through association and WPA EAPOL M1/M2 before its firmware assertion. r49
did reach real ICNSS ownership but produced a firmware-fault indication before
association. Do not describe r49 as preserving the r44/r48 scan or association
path, and do not blame this regression on a package-install failure.

Treat the r49 Clover shipment-profile experiment as the first suspect. The
next source baseline must restore the r48 functional profile while retaining
all Linux 6.19 port fixes, the real Clover ICNSS backend, pktlog removal, and
the preserved `0025`, `0026`, and `0047`-`0050` patches. Then instrument the
r48 WPA M2-to-key-install/WMI boundary narrowly. Do not apply further broad
profile toggles or run another qcacld trial until that baseline builds and
passes the existing static package gates.

# Authoritative r50 recovery/live-test checkpoint (2026-07-22)

r50 implements the next source baseline without repeating r49's broad feature
removal. The consolidated Xiaomi patch restores the r48/default functional
SNOC/Adrastea profile, retains the Linux 6.19 compatibility work and pktlog
removal, and adds EAPOL-only `CLOVER_TX_TRACE` markers at HDD submission, HTT
descriptor creation, TXRX/HTC submission, and firmware completion. The trace
records lengths, IDs, flags, and whether an address needs 64 bits; it does not
record payload bytes, keys, credentials, or full addresses.

Patch `0056-icnss-preserve-msa-across-recovery.patch` fixes the recovery
failure seen after the r48 firmware assertion. The custom ICNSS backend now
keeps successfully assigned MSA regions owned by WLAN across a transient WLFW
service exit, verifies that the recovered firmware advertises the same MSA
layout, and releases ownership only during full module teardown. Assignment
state changes only after successful SCM calls, and a failed reinitialization
does not falsely mark retained memory as HLOS-owned. Read-only ICNSS device
attributes expose `recovery_state`, `recovery_generation`, `last_error`, and
`msa_owner` so the trial helper can distinguish recovery from an unrecoverable
failure.

The device helper now measures firmware faults relative to each attempt rather
than the whole boot. It validates candidate module architecture/name/vermagic
and the wlan-to-ICNSS dependency, waits for remoteproc and ICNSS recovery, and
does not load ath10k alongside qcacld. `try-qcacld-modules` can therefore test
both r50 modules on a running `6.19.10-sdm660` r49 system without installing a
kernel or rebooting. `reload-qcacld` replaces only wlan while retaining the
healthy recovery-aware ICNSS module and preserves the prior wlan module for a
non-firmware-fault rollback. ath10k remains the persistent default unless
`use-qcacld` is explicitly requested.

The local no-reboot workflow is:

1. Run `bash ./wsl-build-qcacld-live-module.sh`. It prepares a versioned
   persistent kernel tree once and writes `qcom-icnss-clover.ko` and `wlan.ko`
   under `qcacld-live-module/`. Subsequent unchanged runs reuse kernel symbol
   state and perform no source recompilation.
2. Copy the r11 helper and both modules to absolute paths on the tablet. Check
   that `uname -r` is exactly `6.19.10-sdm660`, then run
   `clover-wifi-driver try-qcacld-modules /absolute/qcom-icnss-clover.ko
   /absolute/wlan.ko` as root.
3. After NetworkManager has had time to connect, run
   `clover-wifi-driver qcacld-milestones`. Require association, WPA completion,
   an IP address and default route, bidirectional traffic, no new firmware
   fault, and a healthy ICNSS state before considering persistence. Use
   `clover-wifi-driver use-ath10k` to return to the default driver; if the
   helper says reboot is required, do not attempt another live switch.

Static/helper tests and a full package build pass. The resulting uninstalled
kernel APK is `linux-postmarketos-qcom-sdm660-6.19.10-r50.apk` with SHA-256
`5550b0ffebe8aefcdb4119effea8325a6a1f23f89d7492289a21c73327c4d13f`;
the device APK is `device-xiaomi-clover-11-r11.apk` with SHA-256
`8945122b217ebc6b1a5c882bf94e223a2398f6f4eb67428059d75c24cf8f8d46`.
The kernel package contains both AArch64 modules with matching
`6.19.10-sdm660` vermagic, and `modules.dep` links wlan to
qcom-icnss-clover. A second live build performed no source recompilation.

No r50 hardware trial has run because the tablet is not reachable. These
results establish source, module, recovery-workflow, and package correctness;
they do not establish association, WPA, DHCP, traffic, firmware stability, or
successful on-device recovery. Do not install `use-qcacld` persistence until
all of those hardware gates pass.

# Authoritative r52 hardware-fixed handoff (2026-07-22)

This section supersedes every earlier current-state, failure, and next-action
claim in this file.

## Result on real hardware

The Xiaomi qcacld 5.2 stack is working on the Clover tablet. The final clean,
non-DMA-instrumented wlan module was hot-swapped without a reboot and passed:

- association, IPv4 lease, default route, and real Internet traffic;
- an explicit disconnect/reconnect plus real Internet traffic;
- zero new SMMU-fault or firmware-assert signatures;
- three earlier explicit reconnect cycles with the same result.

A fresh scan found 22 access points; after the reconnect cycles it still found
16. There is no evidence of a regression from the previous scan-capable
phase. The tablet was checked again during the final builds and remained
connected with working traffic.

## Proven root cause and decisive fix

This was not a NetworkManager profile bug. In
drivers/staging/qca-wifi-host-cmn/hif/src/snoc/if_snoc.c, the non-IPA SNOC
path forced a 37-bit coherent DMA mask. This build does not enable
CONFIG_64BIT_PADDR, while its WCN3990 HTT fragment descriptors contain only
the low 32 address bits. DMA-IOMMU could therefore give qcacld an IOVA above
4 GiB; firmware received only the low word, faulted at that truncated address,
and asserted during WPA EAPOL M2.

Patch 0085-qcacld-keep-32-bit-dma-with-32-bit-htt-addresses.patch changes
that path to use 37 bits only with CONFIG_64BIT_PADDR and 32 bits otherwise.
With the 32-bit aperture, all observed transmit IOVAs were below 4 GiB and
WPA completed. This is the essential Wi-Fi fix.

## Earlier work that remains necessary

The other fixes were not useless. They removed independent blockers that had
to be solved before the DMA failure could be observed and fixed:

- ICNSS/WLFW boot, board-data transfer, calibration reporting, and
  firmware-ready synchronization now produce a healthy qcacld session.
- Modern DMA-IOMMU domain support and the non-IPA compatibility guard are in
  patches 0080 through 0083.
- Patch 0084 keeps ICNSS at a 32-bit DMA mask and recovers existing GIC IRQ
  mappings from device-tree interrupt specifiers after a live driver handoff.
- The firmware package now extracts the raw board payload for
  bus=snoc,qmi-board-id=ff to bdwlan.bin.

## Safe no-reboot workflow

The Clover helper identifies the WLAN remoteproc by name, not by a fixed
remoteproc number. During an ath10k-to-qcacld trial it loads ICNSS and
restarts only that WLAN remoteproc, preventing custom ICNSS from adopting
ath10k's stale firmware-ready state. The helper test passes:

    wsl sh /mnt/d/general/postm/tests/test-clover-wifi-driver.sh

For a healthy qcacld session, reload-qcacld replaces only wlan and retains
ICNSS. For the initial handoff, try-qcacld-modules accepts absolute paths to
the ICNSS and wlan modules. The helper remains fail-closed after a firmware
fault.

One controlled reboot happened during investigation after an early invalid
IRQ fallback left wlan partially loading; it was not part of the final
workflow. Final validation used module/subsystem-only transitions. No qcacld
autoload or ath10k blacklist was installed: ath10k_snoc remains the persistent
boot default.

## Final package state

The kernel package at
pmaports-clover-rootfix/device/testing/linux-postmarketos-qcom-sdm660 is at
pkgrel 52. It includes patches 0058 through 0086 with verified checksums.
The clean full build passed, including the wlan-to-ICNSS modules.dep check.

- linux-postmarketos-qcom-sdm660-6.19.10-r52.apk
  SHA-256: de0cf19a0dc440079b8ccd840970046ba34540c3c3a9287454003f9a840e20ad
- device-xiaomi-clover-11-r12.apk
  SHA-256: c984377f74c61c8bb0255b0343af1be400f329ae2c55d1191178b2dfc434c1a5
- firmware-xiaomi-clover-1-r1.apk
  SHA-256: 31d7bc66f72ad1aaeaee67c7ff732db63ba39297ea9e7ad235499c7baf86f09e

The firmware r1 package build passed and contains
lib/firmware/ath10k/WCN3990/hw1.0/bdwlan.bin with the expected 19,152-byte
raw board payload.

## Next safe action

No further debugging is needed to claim the runtime fix. If a reproducible
installation is wanted, install r52 kernel, r12 device, and r1 firmware
together, then perform a guarded one-boot qcacld trial. Do not make qcacld
persistent without explicit user approval. After any install, repeat
association, traffic, and at least three reconnect cycles before changing the
boot default.

# Authoritative r52 QCACLD boot-default validation (2026-07-22)

This section supersedes the preceding claim that ath10k remains the persistent
boot default.

QCACLD is now the Clover boot default. The installed configuration is:

    /etc/modprobe.d/90-xiaomi-clover-qcacld.conf
        blacklist ath10k_snoc

    /etc/modules-load.d/90-xiaomi-clover-qcacld.conf
        wlan

After one controlled USB-connected reboot, the system loaded `wlan` with
`qcom_icnss_clover`; `ath10k_snoc` was absent. `wlan0` came up, automatically
rejoined the saved network, received 192.168.0.31/24, installed the default
route through 192.168.0.1, and passed two ICMP probes to 1.1.1.1 (0% loss,
4.642--7.772 ms). The boot log contains no SMMU-fault, target/firmware-assert,
or fatal signature.

## Important live-handoff caveat

Do not use `clover-wifi-driver use-qcacld` for a live ath10k-to-qcacld switch
on this installed r52 state. The handoff can leave the shared GIC IRQ mapping
in a type-mismatch state, preventing either client from rebinding until a
reboot. That helper did not persist its configuration when it failed. A clean
boot with the two files above avoids the stale handoff state and is the tested
method for enabling QCACLD by default. USB networking remains the recovery
path: remove those two files and reboot to restore ath10k.

## Package-owned default (r13)

The QCACLD boot selection is now shipped by
`device-xiaomi-clover`, not only configured manually on the tablet. Package
revision 13 installs:

- `/etc/modprobe.d/90-xiaomi-clover-qcacld.conf`, which blacklists
  `ath10k_snoc`;
- `/etc/modules-load.d/90-xiaomi-clover-qcacld.conf`, which loads `wlan`.

`device-xiaomi-clover-11-r13.apk` was built successfully and installed on the
tablet. Its SHA-256 is
`8df2e50cd518ec464f2fcab78d1303f07bd0c1569f1c845ab7534cfd25b7a700`.
Because r12 had already placed an equivalent manual configuration file, APK
initially saved r13's package copy as `.apk-new`; that temporary file was then
made the active configuration, leaving the active file exactly matching the
package version. Wi-Fi remained connected throughout this package upgrade.

## Two-patch kernel submission

The former patch stack is now squashed into exactly two source patches, both
authored `Zxk <lineag896@gmail.com>` with explanatory comments:

- `0001-clover-icnss-platform-integration.patch` contains the Clover DTS,
  ICNSS compatibility ABI, WLFW/board-data/calibration/recovery logic, and
  explicit module wiring.
- `0002-xiaomi-qcacld-linux-6.19-port.patch` contains the QDF/QCACLD Linux
  6.19 API port, SMMU compatibility, and 32-bit HTT DMA fix.

All 44 former applied patches were replayed against the pinned kernel and
vendor sources before generating the squash. The clean two-patch stack applies
without whitespace errors and changes the same 64 files as the original
stack. A full kernel package build passed afterward, including the
`wlan.ko.zst` to `qcom-icnss-clover.ko.zst` modules.dep check.

The validated r1 kernel artifact is
`linux-postmarketos-qcom-sdm660-6.19.10-r1.apk`, SHA-256
`06d9d942b99495b61243ffe3d08ab3d9f8506b09699c6d3ff233a184b659901e`.

## PR revision normalization

For a clean source submission, the current APKBUILD recipes use `pkgrel=1` for
the kernel, device, and firmware packages. This changes only future package
version labels; it does not revert or alter any of the Wi-Fi source fixes.
The r52/r13 artifacts above remain the historical, hardware-tested builds
currently installed on the tablet. Fresh build scripts now expect r1 artifact
names.

## Ath10k patch cleanup for the QCACLD default

The r1 kernel recipe no longer applies the obsolete Clover-specific ath10k
driver patches (0001--0004 and 0007). Stale unreferenced ath10k patch files
were removed as well. The Clover WLAN supply and MAC device-tree changes stay,
because they describe the hardware rather than ath10k behavior.

Patch 0078 retains an older `ath10k` word in its filename only. Its actual
diff changes the QCACLD ICNSS backend's power/QMI sequencing and contains no
ath10k driver code, so it remains part of the working QCACLD stack.

# Final two-patch PR validation (2026-07-22)

The comment edits in `0001-clover-icnss-platform-integration.patch` changed
the size of a unified-diff hunk without changing its header. The patch was
recounted and regenerated from the pinned source while preserving those
comments. Both final patches now parse and apply cleanly. There are exactly
two kernel patches, neither has mail-style `From`, `Date`, or `Subject`
headers, and both identify `Zxk <lineag896@gmail.com>` in their leading
comment.

`pmbootstrap --as-root checksum` completed successfully for all three
packages. A separate SHA-512 audit of every local source listed by the
APKBUILD files found zero mismatches. The final patch checksums are:

- `0001-clover-icnss-platform-integration.patch`:
  `0cdb48397e003388fa0a52b8293818992303203f956662c88fbdbb2c4d290362d248b0f9473e9bf5e6cce87460eca9bd58047903dac6bcaa9c5c19fd822f2c25`
- `0002-xiaomi-qcacld-linux-6.19-port.patch`:
  `4a558b9a0d7995f3a3351a4ff9b9add562f85ac930f009aee6234de29671c9c6942b919cdc844e9974274566beb15e3611728e7eadd8a40f46210937933530bd`

Clean package builds passed for the kernel, Clover device package, and
firmware package. The retained r1 artifacts are:

- `linux-postmarketos-qcom-sdm660-6.19.10-r1.apk`:
  `73b1e8f50727f991f17b7adb9e31059a545517eb3d265f7542386b7d6913de3c`
- `device-xiaomi-clover-11-r1.apk`:
  `938ef302b154d3e708bcdc1f69106d769b382140bd382109cd201e51b9a63911`
- `device-xiaomi-clover-kernel-clover-11-r1.apk`:
  `f51132e5eb218489be9b65fb0a80129ff448a61ff8d16d97dea3e8a891b63aab`
- `firmware-xiaomi-clover-1-r1.apk`:
  `3217b61d890209001dd51722efa259a7676f2c9888bd76c82cec66466fb51204`

The kernel package validation also confirmed that `wlan.ko.zst` depends on
`qcom-icnss-clover.ko.zst`. The `clover-wifi-driver` test suite passes. A
case-insensitive scan of the kernel, device, and firmware package trees found
no assistant or tool attribution references.

The package files are valid, but the retained `pmaports-clover-rootfix/.git`
file still points at the removed parent checkout
`D:/general/postm/pmaports/.git/worktrees/pmaports-clover-rootfix`. Restore or
replace that Git metadata before attempting to commit or push from this
directory; it does not affect checksum generation or package builds.

# Final r1 tablet installation (2026-07-22)

Installing the cleaned r1 packages exposed two device-package issues that a
cross-build alone did not catch. `deviceinfo` still used Windows CRLF line
endings, which made `boot-deploy` reject a carriage return while sourcing the
file. It also selected `qcom/sdm660-xiaomi-clover` for the regular Wi-Fi-only
Clover subpackage. The tablet had previously kept the older r2 selector,
which correctly used `qcom/sda660-xiaomi-clover`; this is why the bad source
value had not affected the earlier r52/r13 runtime test.

The final source now keeps `deviceinfo` in LF format and selects:

- regular Clover: `qcom/sda660-xiaomi-clover`;
- Clover Plus: `qcom/sdm660-xiaomi-clover-plus`.

The corrected `deviceinfo` SHA-512 recorded by the device APKBUILD is
`9e9d34d07ee3c403c8a8f4f521c8ca7add30dd969c1706f11f3a3aa9c69af4be4d0ba758cb37786606bec4e5f0d464100de6086927dd28679d610f83c8005021`.
The rebuilt device package passed, `mkinitfs` and `boot-deploy` completed, and
the boot image was flashed with `qcom/sda660-xiaomi-clover` appended.

After reboot, the tablet runs kernel `6.19.10-sdm660 #2-aarch64` with all four
r1 packages installed. `wlan` and `qcom_icnss_clover` are loaded,
`ath10k_snoc` is absent, ICNSS reports `ready`, and QCACLD owns the WLAN MSA.
NetworkManager rejoined the saved network at `192.168.0.31`; three probes to
`1.1.1.1` passed with 0% loss. The boot log has no WLAN firmware assertion,
firmware crash, or SMMU fault. `apk fix --simulate` reports a healthy package
database with zero pending repairs.

# r2 crypto teardown fix (2026-07-22)

Stopping the hotspot after an associated client exposed a separate bug in the
Linux 6.19 crypto compatibility wrapper. The first wrapper passed static QCACLD
module data directly to `sg_init_one()`. On arm64 that address is not
linear-mapped; the skcipher path called `flush_dcache_page()` on an invalid
page, producing an oops in `cds_crypto_cipher_encrypt_one()`. The scheduler
thread then stopped, `stop_ap` timed out, and the stale vdev made later STA
scans fail with `-EINVAL`.

The wrapper now copies each block into a `GFP_ATOMIC` kmalloc bounce buffer,
uses one in-place scatterlist for the synchronous ECB operation, copies the
result back, and clears the temporary buffer before freeing it. Allocation or
encryption failure returns a zeroed output instead of dereferencing an
invalid address. This is included in
`0002-xiaomi-qcacld-linux-6.19-port.patch`; no kernel or vendor source pin was
changed.

The kernel package was incremented to `6.19.10-r2` and built successfully. The
artifact SHA-256 is:

    52f0b66e809dcef48f40dce3fea2da35f0dd82fa9a31318282d071f41cd5cd7d

It was installed on the tablet. The broken pre-r2 module could not be
hot-unloaded after its scheduler thread had oopsed (`/sys/module/wlan/refcnt`
was `-1`), so one reboot was required to load r2. After boot, `wlan` and
`qcom_icnss_clover` loaded normally, the saved STA profile obtained
`192.168.0.31`, scans returned multiple APs, and three pings to `1.1.1.1`
passed with 0% loss.

A hotspot start/stop cycle without a connected client now returned to STA and
restored scanning and Internet traffic without a new WLAN/crypto oops,
stale-peer error, or firmware/SMMU fault. The exact associated-client teardown path still needs
one client connected to `MiPad4-AP` for final hardware coverage. The existing
`cancel_work_sync()` warning from `cds_flush_work()` remains visible during
AP teardown but is independent of the crypto crash and is a separate cleanup
item.

The r2 boot also exposed an unrelated existing mainline issue in
`qcom_smbx`: repeated `systemd-logind` power-supply uevent reads can oops at
`power_supply_get_property()` with a NULL provider (address `0x3a0`). These
traces contain no wlan/QCACLD frames and the WLAN remained connected with
working traffic afterward. The SMBX power-supply bug is outside the ICNSS/
QCACLD patch scope and must be tracked separately.

# Final NetworkManager profile cleanup (2026-07-22)

The boot profile and the manually selected test profile were not equivalent.
Boot selected `Yabloko 5Ghz` on BSSID `A6:A4:6B:1F:62:48`, channel 36, with
the default power-save policy. The working `Yabloko-r3-test` profile used the
2.4 GHz BSSID and explicitly disabled Wi-Fi power saving. `sshd` was already
listening on all addresses before boot Wi-Fi associated, and nftables allowed
TCP port 22, so this was not an sshd startup or firewall problem.

`Yabloko 5Ghz` is now the only retained client Wi-Fi profile. It is configured
with autoconnect enabled at priority 999, band `a`, fixed BSSID
`A6:A4:6B:1F:62:48`, power saving disabled, and the driver-provided MAC
preserved. `Yabloko-r3-test`, `Yabloko-r4-test`, `Yabloko`, and
`Yabloko-24-fixed` were deleted. The separate non-autoconnect `Hotspot` profile
was retained.

After activating the cleaned profile, the tablet associated on channel 36,
kept `192.168.0.31`, passed Internet pings, and accepted SSH over that Wi-Fi
address. The saved autoconnect settings are in place; the boot-specific path
will be confirmed at the next normal reboot.

# Boot-autoconnect TCP server-path regression (2026-07-22)

After a normal reboot with only `Yabloko 5Ghz` retained, the tablet associated
on the correct 5 GHz BSSID and obtained `192.168.0.31`. ICMP to the tablet and
outbound Internet ping worked, but TCP port 22 returned no SSH banner. The
TCP handshake completed and `sshd` logged repeated pre-auth key-exchange resets
from `192.168.0.119`; `sshd` was listening on `0.0.0.0:22` and nftables allowed
TCP/22.

The exact same profile, BSSID, band, MAC policy, and disabled power saving
were then brought down and up over USB. The driver destroyed and recreated
vdev 0; the SSH banner and a complete Wi-Fi SSH login immediately worked, with
the same IP and Internet traffic. This isolates the failure to first-boot
QCACLD vdev/transport initialization, not NetworkManager profile selection,
SSH startup, firewall, or 5 GHz association. A userspace reconnect is a
temporary recovery; the source-level fix should make the initial vdev behave
like the recreated vdev without requiring a reconnect.

# Boot-vdev startup ordering fix (2026-07-22)

The first-vdev failure is caused by a QCACLD HDD startup ordering race. The
driver registered `wlan0` while opening adapters, released RTNL immediately
after `hdd_open_interfaces()`, and only then completed notifier, SAP, idle
power-save, and related startup initialization. NetworkManager could therefore
call `ndo_open` and create vdev 0 before the complete HDD state was visible.
The reconnect path worked because all of this startup work had already
finished.

The source fix is in `0002-xiaomi-qcacld-linux-6.19-port.patch`: RTNL remains
held until the final startup state is initialized, then is released immediately
before the success path. This keeps userspace from opening the newly published
netdev during the incomplete window without adding a reconnect service or a
fixed delay.

Kernel `pkgrel` is now `3`. `pmbootstrap checksum` and a full package build
passed. The resulting artifact is
`linux-postmarketos-qcom-sdm660-6.19.10-r3.apk`, SHA-256
`470f69870ce06490e06210b9c060bd7faa75af8c68e3231f69f7e7ae2f95d3d0`.
The packaged `modules.dep` links `wlan.ko.zst` to
`qcom-icnss-clover.ko.zst`. The r3 package was copied and installed over USB
without rebooting. It is not yet boot-tested; current Wi-Fi access remains on
the previously running kernel.

# Boot RX/GRO fix and r4 hardware result (2026-07-22)

The r3 startup-ordering change did not fix the boot-only TCP failure. On a
cold r3 boot, the tablet associated, obtained `192.168.0.31`, and had outbound
Internet access, but SSH over Wi-Fi still stalled during key exchange while
USB SSH worked. This confirmed that the fault was below sshd, firewall, DHCP,
and NetworkManager profile selection.

QCACLD sends station traffic through a dedicated Rx thread and a dummy NAPI
context. Linux 6.19 keeps `GRO_NORMAL` packets in a separate `gro_node` list;
the vendor callback only called `napi_gro_flush()`, which flushes aggregated
GRO packets but does not deliver that normal list. Small interactive TCP
packets could therefore remain queued until unrelated receive traffic filled
the batch. The r4 source keeps `napi_gro_flush()` and then drains `gro->rx_list`
through the exported `netif_receive_skb_list()` API, resetting `rx_count`.

The first implementation used the kernel-inline `gro_flush_normal()` helper.
The full module build correctly rejected it because that inline calls the
non-exported `netif_receive_skb_list_internal()`. The final implementation has
the same list-drain semantics without referencing a private kernel symbol.

Kernel r4 built successfully after checksum regeneration. The retained APK is
`linux-postmarketos-qcom-sdm660-6.19.10-r4.apk`, SHA-256:

    4744524782b553287159d72d1eec76d1c0c48b434dfd2d7edb2f7381f88729ac

`modules.dep` confirms that `wlan.ko.zst` depends on
`qcom-icnss-clover.ko.zst`, and full modpost/package generation passed.

The package was installed over USB and `boot-deploy` flashed the regenerated
boot image. A reboot was required: unloading the running QCACLD module also
unbound ICNSS, and this platform cannot remap the already-used CE IRQs during
the same boot (`IRQ index 0 not found`, `-ENXIO`). This is a live-reload
limitation, not an r4 cold-boot failure.

After reboot the tablet reported kernel `6.19.10-sdm660 #5-aarch64`, loaded
QCACLD/ICNSS automatically, associated without a manual reconnect, obtained
`192.168.0.31`, and passed three Internet pings with 0% loss. The first Wi-Fi
SSH session completed immediately, followed by five independent SSH logins in
2.9 seconds total. A scan returned both 2.4 and 5 GHz networks; pings to the
gateway and Internet again passed with 0% loss. No WLAN firmware assertion,
SMMU fault, oops, or call trace occurred on the r4 cold boot.

One separate behavior remains: after a forced scan, firmware roaming moved the
link to the same SSID's 2.4 GHz BSSID even though the NetworkManager profile
still specified band `a` and the fixed 5 GHz BSSID. Cycling that profile
restored BSSID `A6:A4:6B:1F:62:48` at 5180 MHz. This does not regress the r4
boot-SSH result but should be investigated separately if strict 5 GHz-only
operation must survive background/forced scans.

# Clover cross-band roaming fix and hardware result (2026-07-22)

The forced-scan transition was confirmed as firmware roaming rather than a
NetworkManager profile error. NetworkManager supplied the configured 5 GHz
BSSID, while QCACLD enabled fast roam and roam-scan offload. The shipped INI
had `gRoamIntraBand=0`, whose documented meaning is roaming across bands.
At the transition time dmesg recorded `csr_process_roam_sync_callback()` and
`WMA_ROAM_OFFLOAD_SYNCH_CNF`; NetworkManager merely restarted DHCP after the
firmware changed BSSID.

The Clover-only device source now sets `gRoamIntraBand=1`. This preserves
firmware roaming within the currently associated band but prevents a 5 GHz
connection from selecting a 2.4 GHz roam candidate. The change is in
`device-xiaomi-clover/WCNSS_qcom_cfg.ini`, not the shared SDM660 kernel.

`device-xiaomi-clover` was incremented to `11-r2`, checksums were regenerated,
and the package build passed. The retained artifact is
`device-xiaomi-clover-11-r2.apk`, SHA-256:

    79ce57cb3e468cf17d194d134150f5a640023a164ede6e8e547e5d657e10fed6

Package inspection confirms it contains `gRoamIntraBand=1` while retaining
`FastRoamEnabled=1` and `gRoamScanOffloadEnabled=1`.

The device APK installed successfully and the live INI reported
`gRoamIntraBand=1`. `apk add --no-network` also consumed several newer cached
base/OpenSSH packages. Some attempted systemd downloads from the stale index
returned 404, but the transaction completed with a consistent installed set.
Connections were briefly reset while the tablet was still rebooting; this was
initially misdiagnosed as a broken sshd. After boot completed, USB and Wi-Fi
SSH both worked normally without console recovery.

The hardware test passed. On a cold boot, Clover automatically associated to
BSSID `A6:A4:6B:1F:62:48` at 5180 MHz. A forced
`sudo nmcli dev wifi rescan` was issued and the link was observed for 40
seconds, longer than the configured five-second firmware roam-scan period.
It remained on the same 5 GHz BSSID and frequency. Three Internet pings passed
with 0% loss, followed by three independent SSH logins over `192.168.0.31`.
dmesg showed no roam-sync event, firmware assertion, SMMU fault, oops, or call
trace. The cross-band roaming regression is fixed while same-band firmware
roaming remains enabled.

The INI was subsequently documented without changing runtime behavior. Its
header now identifies Xiaomi's stock configuration as the base, explains the
postmarketOS firmware path and vendor-ABI nature of the settings, and notes
that unlabeled values remain stock. The `gRoamIntraBand=1` block documents the
two values, the observed Clover failure, and the loss of automatic 5-to-2.4
GHz fallback. Android-only `gVersion` copy semantics are also distinguished
from postmarketOS's direct file loading. The comment-only package is
`device-xiaomi-clover-11-r3.apk`, SHA-256:

    7cee461916be8b35e72939864c4d1310d3a738dc4a273d8c958094f88ebb0655
