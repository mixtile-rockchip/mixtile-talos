# Blade 3 в Cluster Box как официальный образ Talos

[English version](upstream.md)

Цель: ставить Talos на Blade 3 в Mixtile Cluster Box из
[Image Factory](https://factory.talos.dev) с работающей PCIe-фабрикой, а
не из этого репозитория. Статус: план, ничего не отправлено.

## Как Talos поставляет платы и драйверы

| Часть | Официальное место | Собирает и подписывает |
| --- | --- | --- |
| Overlay: U-Boot, DTB, аргументы ядра, installer | [siderolabs/sbc-rockchip](https://github.com/siderolabs/sbc-rockchip) (плата `mixtile-blade3`) | Siderolabs; список в [siderolabs/overlays](https://github.com/siderolabs/overlays) |
| Внешний модуль ядра | [siderolabs/pkgs](https://github.com/siderolabs/pkgs) (`<name>-pkg`, собирается вместе с ядром Talos и подписывается его ключом) | Siderolabs |
| System extension вокруг модуля | [siderolabs/extensions](https://github.com/siderolabs/extensions) (`drivers/<name>`) | Siderolabs |
| Инструкция по установке | [siderolabs/docs](https://github.com/siderolabs/docs) (`single-board-computers/<board>.mdx`) | |

Прецеденты: `turingrk1` (плата на RK3588 со своей сборкой DTB) в
sbc-rockchip; `xdma-driver` и `gasket-driver` (внешние модули) в pkgs +
extensions; drbd и zfs, которые кластер уже использует.

Узел Cluster Box из Image Factory тогда — это схема «overlay
`mixtile-blade3` + extensions `openmiop`, `drbd`, `zfs`, …».

## Что меняется для нас

| Сейчас (этот репозиторий) | Официально |
| --- | --- |
| openmiop-ep.ko собирается здесь против дерева ядра Talos (`artifacts/talos-kernel`, `KERNEL_IMAGE`) | собирается в pkgs вместе с ядром |
| модуль не подписан: образ убирает `module.sig_enforce` | подписан ключом сборки Talos: `module.sig_enforce` остаётся включённым |
| теги extensions закрепляет `pin_extensions` | Image Factory сам собирает всё под одну версию Talos |
| свой installer, обновление по digest | `factory.talos.dev/installer/<schematic>:<talos>` |

## Соответствие

Overlay (overlay для Cluster Box в этом репозитории уже устроен как в
sbc-rockchip):

| Здесь | sbc-rockchip | Стадия |
| --- | --- | --- |
| `installers/blade3/` | `installers/mixtile-blade3/` | `mixtile-blade3` |
| `artifacts/blade3/u-boot/` | `artifacts/mixtile-blade3/u-boot/` | `u-boot-mixtile-blade3` |
| `artifacts/dtb/blade3/` | `artifacts/dtb/mixtile-blade3/` | `dtb-mixtile-blade3` |
| `profiles/blade3/blade3.yaml` | `profiles/mixtile-blade3/mixtile-blade3.yaml` | |
| `installers/pkg.yaml` | записи в их `installers/pkg.yaml` | |
| `artifacts/arm-trusted-firmware/rk3588`, `artifacts/rkbin/rk3588` | уже есть там, те же имена стадий | |

Модуль и extension:

| Здесь | Официально |
| --- | --- |
| `artifacts/openmiop/pkg.yaml` | pkgs: `openmiop/pkg.yaml` (`openmiop-pkg`), зависимости `kernel-build` + LLVM, проверка подписи как в `xdma-driver/pkg.yaml`; `openmiop_ref` и хеши в их `Pkgfile` |
| `artifacts/openmiop/manifest.yaml` | extensions: `drivers/openmiop/` (`pkg.yaml`, `manifest.yaml.tmpl`, `vars.yaml`, `README.md`) |
| `artifacts/openmiop/blade3-leds`, `blade3-nvme-recover` | перенести в pcie-ep-net (один архив исходников на релиз) |

## Моменты с PCIe, о которых спросят ревьюеры

Для каждого нужна короткая понятная причина в комментариях DTS и в pull
request (большинство уже есть в `artifacts/dtb/blade3/rk3588-mixtile-blade3.dts`):

1. **PCIe3 x4 — endpoint** (`pcie3x4_ep`, 2 линии, compatible
   `openmiop,rk3588-pcie-ep`, host `pcie3x4` выключен). Не mainline
   `rockchip,rk3588-pcie-ep`: подходящего EPC function driver в ядре Talos
   нет, openmiop сам управляет контроллером (DBI, iATU, eDMA). Без
   extension openmiop у узла просто нет драйвера.
2. **Разделение PHY** `data-lanes = <1 1 2 2>`: линии 0-1 к коммутатору
   ASM2824, линии 2-3 к M.2 NVMe на backplane (`pcie3x2`).
3. **Без общего refclk** (`rockchip,rx-common-refclk-mode = <0 0 0 0>`): у
   коробки и blade разные опорные частоты.
4. **Нет `reset-gpios` у pcie3x2**: PERST# у NVMe — это единственный
   PERST# разъёма U.2, им управляет Cluster Box; `blade3-nvme-recover`
   возвращает NVMe после сброса коробки.
5. **PCIe SMMU выключен** (`mmu600_pcie` disabled): входящий трафик
   endpoint и чтения eDMA несут stream ID, которыми не владеет ни одно
   устройство Linux.
6. **Сторона BMC**: openmiop требует, чтобы BMC Cluster Box выполнял роль
   RC (`omi-rc`, наша прошивка OpenWrt). Со штатной прошивкой Mixtile
   blades грузятся и работают, но без `omi0`. Эту зависимость нужно
   описать в README extension.
7. **Аргументы ядра**: убрать `console=ttyFIQ0` (только для ядер
   вендора); оставить `console=ttyS2,1500000n8`, `cma=128MB` и остальное,
   как у других плат sbc-rockchip.

## Порядок работы

1. pcie-ep-net: перенести blade3-leds и blade3-nvme-recover в
   репозиторий, выпустить тег (GPL; `MODULE_LICENSE("GPL")` уже есть).
2. Здесь, как репетиция: переписать `artifacts/openmiop/pkg.yaml` так, как
   pkgs собирает модули (стадия `kernel-build`, `modules_install` в
   `extras`), и раскатать сначала на .108, потом на кластер (обычные
   правила: по digest, с drain, по одному узлу, etcd 3/3, DRBD out-of-sync
   0, CNPG healthy). Здесь модуль остаётся неподписанным: ключ подписи
   Talos существует только внутри сборки ядра в pkgs, поэтому включённый
   `module.sig_enforce` впервые проверяется на образе, собранном из pull
   request в pkgs.
3. sbc-rockchip: плата `mixtile-blade3` (overlay выше).
4. pkgs: `openmiop-pkg`; затем extensions: `drivers/openmiop`.
5. docs: страница установки Blade 3 в Cluster Box (прошивка BMC, запись
   образа, NVMe, PCIe-фабрика).
6. Когда всё выпущено: один узел с installer из Image Factory на .108,
   потом остальные.

В репозиториях Siderolabs есть
[AI policy](https://github.com/siderolabs/overlays/blob/main/AI_POLICY.md):
всё, что туда отправляется (код, сообщения коммитов, описания, ответы на
ревью), должно быть работой автора, написанной его словами, понятой и
проверенной им самим. Pull request открывает и ведёт лично мейнтейнер
этого репозитория.
