# Blade 3 in the Cluster Box as an official Talos image

[Русская версия](upstream.ru.md)

Goal: install Talos on a Blade 3 in a Mixtile Cluster Box from
[Image Factory](https://factory.talos.dev) with the PCIe fabric working,
instead of from this repository. Status: plan, nothing submitted.

## How Talos ships boards and drivers

| Piece | Official home | Built and signed by |
| --- | --- | --- |
| Overlay: U-Boot, DTB, kernel arguments, installer | [siderolabs/sbc-rockchip](https://github.com/siderolabs/sbc-rockchip) (board `mixtile-blade3`) | Siderolabs; listed in [siderolabs/overlays](https://github.com/siderolabs/overlays) |
| Out-of-tree kernel module | [siderolabs/pkgs](https://github.com/siderolabs/pkgs) (`<name>-pkg`, built with the Talos kernel, signed with its key) | Siderolabs |
| System extension around the module | [siderolabs/extensions](https://github.com/siderolabs/extensions) (`drivers/<name>`) | Siderolabs |
| Install guide | [siderolabs/docs](https://github.com/siderolabs/docs) (`single-board-computers/<board>.mdx`) | |

Precedents: `turingrk1` (an RK3588 board with its own DTB build) in
sbc-rockchip; `xdma-driver` and `gasket-driver` (out-of-tree modules) in
pkgs + extensions; drbd and zfs, which the cluster already uses.

A Cluster Box node from Image Factory would then be the schematic
"overlay `mixtile-blade3` + extensions `openmiop`, `drbd`, `zfs`, …".

## What changes for us

| Today (this repository) | Official |
| --- | --- |
| openmiop-ep.ko built here against the Talos kernel tree (`artifacts/talos-kernel`, `KERNEL_IMAGE`) | built in pkgs with the kernel |
| module not signed: the image drops `module.sig_enforce` | signed by the Talos build key: `module.sig_enforce` stays on |
| extension tags pinned by `pin_extensions` | Image Factory resolves everything for one Talos version |
| our installer image, rolled by digest | `factory.talos.dev/installer/<schematic>:<talos>` |

## Mapping

Overlay (the Cluster Box overlay of this repository is already laid out
like sbc-rockchip):

| Here | sbc-rockchip | Stage |
| --- | --- | --- |
| `installers/blade3/` | `installers/mixtile-blade3/` | `mixtile-blade3` |
| `artifacts/blade3/u-boot/` | `artifacts/mixtile-blade3/u-boot/` | `u-boot-mixtile-blade3` |
| `artifacts/dtb/blade3/` | `artifacts/dtb/mixtile-blade3/` | `dtb-mixtile-blade3` |
| `profiles/blade3/blade3.yaml` | `profiles/mixtile-blade3/mixtile-blade3.yaml` | |
| `installers/pkg.yaml` | entries in their `installers/pkg.yaml` | |
| `artifacts/arm-trusted-firmware/rk3588`, `artifacts/rkbin/rk3588` | already there, same stage names | |

Module and extension:

| Here | Official |
| --- | --- |
| `artifacts/openmiop/pkg.yaml` | pkgs: `openmiop/pkg.yaml` (`openmiop-pkg`), dependencies `kernel-build` + LLVM, signature test as in `xdma-driver/pkg.yaml`; `openmiop_ref`/hashes in their `Pkgfile` |
| `artifacts/openmiop/manifest.yaml` | extensions: `drivers/openmiop/` (`pkg.yaml`, `manifest.yaml.tmpl`, `vars.yaml`, `README.md`) |
| `artifacts/openmiop/blade3-leds`, `blade3-nvme-recover` | move into pcie-ep-net (one source tarball per release) |

## The PCIe points reviewers will ask about

Each needs a short, clear reason in the DTS comments and the pull
requests (most are already in `artifacts/dtb/blade3/rk3588-mixtile-blade3.dts`):

1. **PCIe3 x4 is an endpoint** (`pcie3x4_ep`, 2 lanes, compatible
   `openmiop,rk3588-pcie-ep`, `pcie3x4` host disabled). Not the mainline
   `rockchip,rk3588-pcie-ep`: there is no EPC function driver in the Talos
   kernel for this, openmiop drives the controller (DBI, iATU, eDMA)
   itself. Without the openmiop extension the node just has no driver.
2. **PHY split** `data-lanes = <1 1 2 2>`: lanes 0-1 to the ASM2824
   switch, lanes 2-3 to the M.2 NVMe on the backplane (`pcie3x2`).
3. **No common refclk** (`rockchip,rx-common-refclk-mode = <0 0 0 0>`):
   the box and the blade have separate reference clocks.
4. **No `reset-gpios` on pcie3x2**: the NVMe PERST# is the blade's one
   U.2 PERST#, driven by the Cluster Box; `blade3-nvme-recover` brings the
   NVMe back after a box reset.
5. **PCIe SMMU off** (`mmu600_pcie` disabled): inbound endpoint traffic and
   eDMA reads carry stream IDs no Linux device owns.
6. **The BMC side**: openmiop needs the Cluster Box BMC to run the RC side
   (`omi-rc`, our OpenWrt firmware). With Mixtile's stock BMC firmware the
   blades boot and work, without `omi0`. This dependency has to be in the
   extension README.
7. **Kernel arguments**: drop `console=ttyFIQ0` (vendor kernels only);
   keep `console=ttyS2,1500000n8`, `cma=128MB` and the rest as the other
   sbc-rockchip boards.

## Order of work

1. pcie-ep-net: blade3-leds and blade3-nvme-recover into the repository,
   a release tag (GPL; `MODULE_LICENSE("GPL")` is already there).
2. Here, as a rehearsal: write `artifacts/openmiop/pkg.yaml` the way pkgs
   builds modules (`kernel-build` stage, `modules_install` into `extras`)
   and roll it on .108 first, then the cluster (usual rules: by digest,
   drain, one node, etcd 3/3, DRBD out-of-sync 0, CNPG healthy). It stays
   unsigned here: the Talos signing key only exists inside the pkgs
   kernel build, so `module.sig_enforce` on is first tested with an
   image built from the pkgs pull request.
3. sbc-rockchip: board `mixtile-blade3` (the overlay above).
4. pkgs: `openmiop-pkg`; then extensions: `drivers/openmiop`.
5. docs: install page for Blade 3 in the Cluster Box (BMC firmware,
   flashing, NVMe, PCIe fabric).
6. When all are released: one node from an Image Factory installer on
   .108, then the rest.

Siderolabs repositories have an
[AI policy](https://github.com/siderolabs/overlays/blob/main/AI_POLICY.md):
everything submitted there (code, commit messages, descriptions, review
replies) must be the submitter's own work in their own words, understood
and tested by them. The pull requests are opened and answered by the
maintainer of this repository personally.
