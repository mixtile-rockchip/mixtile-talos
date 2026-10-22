# Talos 1.14 для Mixtile Blade 3

[English](README.md) · [Русский](README.ru.md)

> **Релиз v0.6.1 (OpenMIOP Stack v0.6.1, Talos v1.14.4, протокол v4, push-режим, gateway pull, zero-copy, контрольные суммы между блейдами):**
> образ Talos со встроенным openmiop (Ethernet `omi0` между блейдами
> Cluster Box по PCIe) и восстановлением NVMe Blade 3 после перезагрузки
> Cluster Box. Новое по сравнению с v0.6.0: Talos v1.14.4 (Linux 6.18.57),
> openmiop и модули платы Blade 3 собираются из одного релиза
> pcie-ep-net v0.6.1 так, как Talos собирает внешние модули. Сам драйвер
> и скорость те же, что в v0.6.0: один поток между блейдами 7,8-8,0
> Гбит/с. Установка, обновление по digest, проверка и ограничения — в
> [README.md](README.md#openmiop-stack-v061), [CHANGELOG.md](CHANGELOG.md)
> и на [странице релиза](https://github.com/roysbike/mixtile-talos/releases/tag/v0.6.1). Установщик:
> `ghcr.io/roysbike/mixtile-talos-installer@sha256:c0fe6ec4eb157ab8d993477b7b85abc982dc1ecbd7a9fb3cc0bcb054159fda8e`.
>
> Обновляйте ноды по одной, **с drain** (не `--drain=false`), всегда с
> `--image` и с тем же образом в `machine.install.image`.

Этот репозиторий собирает ARM64 SBC overlay и загрузочные образы Talos Linux
`v1.14.4` для Mixtile Blade 3 (RK3588), в том числе для плат в Mixtile Cluster Box.

Здесь остаются сборка образа и прошивка eMMC. Установка Cozystack, классы
хранения и скрипты доступа к UI живут в отдельном проекте `cozystack-box-mixtile`.

## Оборудование и для кого это

**Mixtile Cluster Box** — компактное шасси на четыре платы **Mixtile
Blade 3**. Внутри:

* управляющий контроллер (BMC): MediaTek MT7620A (MIPS) с OpenWrt. Он
  включает, выключает и перезагружает блейды, даёт доступ к их
  последовательным консолям и служит корневым комплексом PCIe всего шасси;
* PCIe-коммутатор ASMedia ASM2824 (Gen3): линк Gen3 x2 к каждому слоту и
  линк Gen1 x1 к BMC.

**Mixtile Blade 3** — вычислительная плата на Rockchip RK3588
(4× Cortex-A76 + 4× Cortex-A55) с eMMC и слотом M.2 NVMe. Её контроллер
PCIe 3.0 x4 разделён пополам: линии 0-1 идут к коммутатору Cluster Box,
линии 2-3 — к NVMe. Blade 3 работает и сама по себе, без Cluster Box.

Mixtile поставляет шасси со своей прошивкой BMC и своим сетевым
драйвером для блейдов (MIOP). **OpenMIOP Stack** — независимая открытая
замена для владельцев Cluster Box с платами Blade 3 (или отдельной
Blade 3), которым нужно:

| Что нужно | Репозиторий |
| --- | --- |
| Ethernet между блейдами через PCIe-коммутатор (`omi0`, ~5 Гбит/с на поток, ~25 Гбит/с при четырёх отправителях) | [pcie-ep-net](https://github.com/roysbike/pcie-ep-net) |
| Talos Linux (Kubernetes) на Blade 3, в Cluster Box или отдельно | [mixtile-talos](https://github.com/roysbike/mixtile-talos) (этот репозиторий) |
| Свежий OpenWrt на BMC: питание и консоли блейдов, обновление прошивки, сторона OpenMIOP на BMC | [mixtile-clusterbox-mt7620a-openwrt](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt) |

План сделать из этого официальный образ Talos (overlay в siderolabs/sbc-rockchip,
openmiop как подписанный extension): [docs/upstream.ru.md](docs/upstream.ru.md).

## Базовые версии

- Talos и imager: `v1.14.4`
- Пакеты Talos: `v1.14.0-44-g2ec10eb`
- Linux: `6.18.57`, штатное ARM64-ядро Talos без изменений
- U-Boot: `v2026.07`
- DTS платы и конфигурация U-Boot: mainline-порт Blade 3 из Armbian
- TF-A: `lts-v2.14.6`
- Бинарник тренировки DDR Rockchip: rkbin, коммит `74213af1`

Overlay использует тот же API пакетов и установщика, что и официальная
поддержка Turing RK1 в
[`siderolabs/sbc-rockchip`](https://github.com/siderolabs/sbc-rockchip).
Добавлены DTB, U-Boot и смещение установки именно для Blade 3. DTB Turing RK1
не считается взаимозаменяемым с Blade 3.

## Что собирается

`sbc-mixtile-blade3` содержит:

- `u-boot-rockchip.bin`, записывается с сектора 64;
- `rk3588-mixtile-blade3.dtb`;
- overlay-установщик Talos 1.14;
- профиль raw-образа.

Итоговые образы используют официальное ядро Talos 1.14.4 и включают:

- `ghcr.io/siderolabs/drbd:9.3.4-v1.14.4`
- `ghcr.io/siderolabs/zfs:2.4.4-v1.14.4`
- `ghcr.io/siderolabs/iscsi-tools:v0.2.0`

DRBD и ZFS совпадают с релизом ядра, ABI модулей и ключом подписи
официального Talos.

## Сборка

Нужно:

- Docker с Buildx;
- OCI-реестр, видимый и хосту сборки, и Talos imager;
- право push в выбранный namespace.

```bash
docker login ghcr.io
USERNAME=<github-user-or-org> ./build.sh all
```

Отдельные шаги:

```bash
USERNAME=<namespace> ./build.sh overlay
USERNAME=<namespace> ./build.sh image
```

Артефакты пишутся в `_out/`. Значения по умолчанию меняются через
`OUTPUT_DIR`, `REGISTRY`, `IMAGE_TAG` и `TALOS_VERSION`.

Профиль `blade3` собирает `metal-arm64.raw.xz`. После сборки `build.sh`
проверяет, что в секторе 64 сжатого образа есть данные U-Boot.

### macOS

Docker Desktop должен быть запущен, эмуляция ARM64 включена. Makefile в
репозитории совместим с GNU Make 3.81 из macOS и не требует GNU sed.

Кросс-сборка и привилегированный ARM64 imager через Docker Desktop заметно
медленнее, чем на Linux. Для повторяемой сборки используйте GitHub Actions.

### GitHub Actions

Отправьте ветку на GitHub и запустите **Actions → Build Talos for Mixtile Blade 3
→ Run workflow**. Workflow:

1. включает эмуляцию ARM64 и Buildx;
2. публикует временный overlay в GHCR-namespace владельца репозитория;
3. собирает installer и raw metal-образ;
4. выкладывает `_out/` как artifact на 14 дней.

Отдельный токен реестра не нужен: workflow использует `GITHUB_TOKEN` с правом
`packages: write`.

## Проверка конфигурации ядра

```bash
./scripts/verify-kernel-config.sh
```

Проверка берёт точный `config-arm64` из коммита пакетов Talos 1.14.4 и
смотрит, что модульные драйверы storage, NVMe, VFIO и Realtek перечислены в
манифесте initramfs Talos ARM64.

Talos собирает часть драйверов модулями (`m`), а не встроенными (`y`):
NBD, NVMe, VFIO, DM thin/multipath и R8169. Так и задумано: после загрузки
модулей из initramfs поведение то же.

Linux 6.18/Talos использует iptables поверх nftables. Устаревшие
`CONFIG_IP_NF_FILTER` и `CONFIG_IP_NF_NAT` выключены, а `NF_TABLES`,
`NFT_NAT`, `NF_NAT`, `NETFILTER_XT_NAT` и
`NETFILTER_XT_TARGET_MASQUERADE` включены. Включать legacy-таблицы текущему
Kube-OVN не нужно: для этого пришлось бы сопровождать своё ядро и отдельные
сборки DRBD/ZFS.

## Установка с macOS

Сборка даёт `_out/metal-arm64.raw.xz` — то же имя файла, что в
[инструкции Mixtile](https://www.mixtile.com/docs/installing-talos-on-mixtile-blade-3/).
Перед записью проверьте и распакуйте образ:

```bash
brew install xz
xz --test _out/metal-arm64.raw.xz
xz --decompress --keep _out/metal-arm64.raw.xz
shasum -a 256 _out/metal-arm64.raw.xz
```

### microSD

Сначала точно определите диск. Команда ниже уничтожает все данные на нём:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=_out/metal-arm64.raw of=/dev/rdiskN bs=4m
sync
diskutil eject /dev/diskN
```

`diskN` — всё устройство microSD, а не раздел вроде `diskN1`. Во время `dd`
на macOS нажмите `Ctrl-T`, чтобы увидеть прогресс.

### eMMC по USB

Поставьте `rkdeveloptool` из стороннего Homebrew tap:

```bash
brew tap IgorKha/rkdeveloptool
brew trust --formula IgorKha/rkdeveloptool/rkdeveloptool
brew install rkdeveloptool
```

Либо соберите
[официальные исходники Rockchip](https://github.com/rockchip-linux/rkdeveloptool):

```bash
brew install automake autoconf libusb pkg-config
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool
autoreconf -i
./configure
make
sudo install -m 0755 rkdeveloptool /usr/local/bin/rkdeveloptool
```

Переведите Blade 3 в режим Rockchip Loader/Maskrom и проверьте, что плата видна:

```bash
rkdeveloptool ld
```

Временный `rk3588_spl_loader_*.bin` для `rkdeveloptool db` этот репозиторий не
собирает. Возьмите loader, совместимый с Blade 3, из инструкции Mixtile.
Произвольный loader для RK3588 не подходит. Сохраните файл как
`rk3588_spl_loader_v1.08.111.bin` в корне репозитория, включите DIP switch 4,
перезапустите питание и выполните:

```bash
./scripts/flash-blade3-macos.sh
```

Скрипт проверяет сжатый образ и подпись RKNS у U-Boot, ждёт ровно одну Blade 3
в режиме MaskROM, спрашивает подтверждение разрушающей операции, загружает
временный SPL и записывает образ на eMMC. Пути к образу и loader меняются
через `--help`.

В raw-образе уже лежит U-Boot этой сборки, начиная с сектора 64. SPL loader
нужен только как временный USB-доступ к eMMC.

Каждая Blade 3 в Cluster Box прошивается отдельно.

## Первый запуск

U-Boot пробует microSD, затем NVMe, затем eMMC. Последовательная консоль —
UART2, 1 500 000 бод.

Перед заменой рабочей установки:

1. Сохраните копию текущего загрузочного образа.
2. Проверьте новый образ со съёмного носителя.
3. Снимите полный лог UART.
4. В maintenance mode Talos проверьте eMMC, NVMe и оба Ethernet-порта.
5. Только после этого ставьте систему на eMMC или NVMe.

После загрузки:

```bash
talosctl -n <node> version
talosctl -n <node> read /proc/config.gz | gzip -dc
talosctl -n <node> get extensions
talosctl -n <node> get kernelmodulestatus
```

Проверка на живом железе — гостевые KVM, трафик Geneve, репликация DRBD и
импорт ZFS — требует физическую Blade 3. Успешная кросс-сборка её не заменяет.

## Известный риск

Mainline-поддержка Blade 3 моложе и менее обкатана, чем вендорное дерево 6.1.
U-Boot 2026.07 включает описание Armbian FUSB302/USB-C PD, поэтому согласование
PD происходит до старта Linux. На первом запуске используйте UART и заведомо
исправное питание. Не затирайте рабочий носитель, пока не увидите PCIe, NVMe
и Ethernet.

Поддержку endpoint Cluster Box даёт открытый драйвер `openmiop`
(<https://github.com/roysbike/pcie-ep-net>). Здесь он упакован как system
extension вместе с нужными ему изменениями device tree; подробности — в
[docs/openmiop.md](docs/openmiop.md).
