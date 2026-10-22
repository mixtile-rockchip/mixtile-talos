# Changelog

All notable changes to this project are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.6.1] - 2026-10-21

Blade OS of OpenMIOP Stack v0.6.1: Talos v1.14.4, and openmiop with the
Blade 3 board modules from one pcie-ep-net release. Same DTB and U-Boot as
0.6.0; the openmiop driver is unchanged.

### Changed

- Talos v1.14.4 (PKGS v1.14.0-44-g2ec10eb, TOOLS v1.14.0-9-g6b71647):
  Linux 6.18.57-talos; the kernel tree for openmiop follows siderolabs/pkgs
  2ec10eb (config, patches: the tun and libceph fixes are upstream now).
  Extensions drbd 9.3.4, zfs 2.4.4, panfrost, rockchip-rknn for v1.14.4,
  iscsi-tools v0.2.0, pinned to the digests Talos released.
- openmiop 0.6.1-v1.14.4 from pcie-ep-net v0.6.1 (`a368e65`): the Blade 3
  board modules (blade3-leds, blade3-nvme-recover) come from that release
  (`drivers/blade3`) instead of copies here. The extension is built the way
  siderolabs/pkgs builds out-of-tree modules (`modules_install` into
  `extras`, stripped, signed by `CONFIG_MODULE_SIG_ALL`; here with the
  kernel tree's throw-away key, so the image still drops
  `module.sig_enforce`).
- Kernel arguments: `console=ttyFIQ0` removed (only vendor kernels have
  it), as on the sbc-rockchip boards.

### Tested

- The PR build (installer `sha256:24a6f518…`) rolled with drain on the lab
  Cluster Box: .108 on 2026-10-20, .204/.133/.201 on 2026-10-21 (CNPG
  primaries moved off by cordon first). `scripts/openmiop-verify.sh` ok on
  .108; on every node openmiop 0.6.1 loaded, peers up with checksum
  offload, NVMe Gen3 x2; etcd 3/3, CNPG healthy, ZFS clean, DRBD in sync
  afterwards. BMC on firmware v0.4.0.

## [0.6.0] - 2026-10-20

Blade OS of OpenMIOP Stack v0.6.0. Same Talos v1.14.2 kernel, DTB, U-Boot
and extensions as 0.5.0; openmiop changes.

### Added

- openmiop 0.6.0-v1.14.2 from roysbike/pcie-ep-net `9cdd03f` (tag v0.6.0):
  TX threads and eDMA interrupts on the Cortex-A76 (`tx_cpus`), and TCP/UDP
  checksum offload between blades (`OMI_FEAT_CSUM`, `p2p_csum`), negotiated
  per pair. One blade-to-blade TCP flow 7.8-8.0 Gbit/s (5.0-5.5 with 0.5.0).

### Fixed

- `build.sh` pins the Sidero extensions (drbd, zfs, iscsi-tools, panfrost,
  rockchip-rknn) to the digests of `ghcr.io/siderolabs/extensions:v1.14.2`.
  Sidero re-pushed `drbd`/`zfs:...-v1.14.2` built for kernel 6.18.56 under
  the same tags, and the imager failed ("copying kernel modules ...
  6.18.54-talos: no such file"). `PIN_EXTENSIONS=0` keeps the tags.

### Tested

- The same driver without the last tx_build hardening (test image ci-61,
  openmiop 0.5.3-dev.1) on .108 and .201, v0.5.0 on .133/.204: 1 flow
  7.82-7.98 Gbit/s between the test pair, integrity over TCP/UDP,
  IPv4/IPv6, Kube-OVN Geneve and the BMC gateway identical, 1 h soak
  clean. Upgrade with drain, DRBD and CNPG fine.

## [0.5.0] - 2026-10-14

Blade OS of OpenMIOP Stack v0.5.0. Same Talos v1.14.2 kernel, DTB, U-Boot
and extensions as 0.4.0; only openmiop changes.

### Added

- openmiop 0.5.0-v1.14.2 from roysbike/pcie-ep-net `6fbcff1` (tag v0.5.0):
  gateway zero-copy. With ClusterBox firmware v0.3.0 the blade reads
  unicast frames from the BMC's stack straight from the BMC's buffers;
  LAN -> blade through the BMC 196-198 -> 275-281 Mbit/s. Module parameter
  `gw_zc`, counter `rx_gw_zc`. Works with older BMC firmware (copy path).

### Tested

- The same driver (test image ci-57, openmiop 0.5.0-dev.1) on .108 with
  the v0.5.0 `omi-rc` on the BMC: SHA-256 of 512 MB 3/3, 16 stress rounds
  clean, no BMC memory leak; v0.4.0 blades alongside on the copy path.

## [0.4.0] - 2026-10-13

Blade OS of OpenMIOP Stack v0.4.0 (stable). Same Talos v1.14.2 kernel, DTB,
U-Boot and extensions as 0.3.0; openmiop 0.4.0-v1.14.2 from
roysbike/pcie-ep-net `c607b86` (tag v0.4.0; driver code identical to
0.4.0-rc.2). Sums up 0.4.0-rc.1 and 0.4.0-rc.2.

### Changed

- Gateway pull: with ClusterBox firmware v0.2.0 (or any `omi-rc` from
  pcie-ep-net v0.4.0) the blade reads LAN and internet traffic from BMC
  memory with an eDMA read channel; LAN -> blade through the BMC
  92 -> 193-198 Mbit/s.

### Fixed

- False peer stalls under load and the gateway v2 reconnect deadlock that
  could cut a blade off the Cluster Box gateway (0.4.0-rc.2).

### Tested

- 0.4.0-rc.2 (same driver) on all four blades since 2026-10-13 16:46Z,
  BMC on firmware v0.2.0-rc.2: gateway stress clean on .108 and .133,
  BMC reboot (firmware flash) recovered with NVMe live and gateway pull on
  all blades.

## [0.4.0-rc.2] - 2026-10-13

Blade OS of OpenMIOP Stack v0.4.0-rc.2. Same Talos v1.14.2 kernel, DTB,
U-Boot and extensions as 0.4.0-rc.1; only openmiop changes.

### Fixed

- openmiop 0.4.0-rc.2-v1.14.2 from roysbike/pcie-ep-net `11c8e53` (tag
  v0.4.0-rc.2). Under long blade -> LAN uploads (Cluster Box CPU at
  99 %) a blade on 0.4.0-rc.1 could lose the gateway for good (no LAN,
  internet, DNS, NTP over omi0) until the BMC's `omi-rc` was reloaded:
  false peer stalls (progress was measured between two reads of one
  pass, while the TX thread also picks up credit) and then a reconnect
  to the BMC that left its ring looking full forever. The same false
  stalls hit P2P peers (hundreds of stalls and reconnects under load).

### Tested

- The same driver source (test image ci-52, openmiop 0.4.0-dev.3,
  pcie-ep-net 668278c) on .108: 21 stress rounds (3 parallel 300 MB
  blade -> LAN uploads plus a 300 MB download through the BMC, BMC CPU
  99 %), the last 15 during 240 s of P2P load at 8.7 Gbit/s: gateway up
  throughout, 0 stalls, 0 reconnects, 0 late drops, 0 eDMA errors.
  The 0.4.0-rc.1 driver lost the gateway in round 4 of the same test.

## [0.4.0-rc.1] - 2026-10-13

Blade OS of OpenMIOP Stack v0.4.0-rc.1. Same Talos v1.14.2 kernel, DTB,
U-Boot and extensions as 0.3.0; only openmiop changes.

### Changed

- openmiop 0.4.0-rc.1-v1.14.2 from roysbike/pcie-ep-net `35884c8` (tag
  v0.4.0-rc.1): gateway pull. With ClusterBox firmware v0.2.0-rc.1 (or
  any `omi-rc` from pcie-ep-net v0.4.0-rc.1) the blade reads LAN and
  internet traffic from BMC memory with an eDMA read channel instead of
  the BMC writing it into the blade's BAR: ~1.5x faster. Module
  parameter `gw_pull`, counters `rx_gw_pulls` / `rx_gw_pull_errors`.
- Upgrade instructions: keep the default drain (no `--drain=false`).

### Tested

- The same driver source (test image ci-48-0269dbaa, openmiop
  0.4.0-dev.1, pcie-ep-net 26441d4) on .108, BMC with the v0.4.0-rc.1
  `omi-rc` code loaded by hand: LAN -> blade 141-145 Mbit/s (v0.3.0
  blade at the same time: 92-95), internet -> blade 152-155 (97-106),
  BMC -> blade 204 (130); 444 158 frames pulled, 0 errors; P2P to the
  v0.3.0 blades unchanged (4 queues, doorbell), NVMe live.

## [0.3.0] - 2026-10-12

First stable release of the OpenMIOP Stack v0.3.0 Blade OS. Same
kernel, DTB, modules and openmiop driver source as 0.3.0-rc.1.

### Changed

- openmiop 0.3.0-v1.14.2 from roysbike/pcie-ep-net `a4bc7ef` (tag
  v0.3.0). The blade driver is unchanged since v0.3.0-rc.1; v0.3.0-rc.2
  only fixed the Cluster Box module `omi-rc`.

### Tested

- v0.3.0-rc.1 on all four lab blades with ClusterBox firmware
  v0.1.0-rc.6 (`omi-rc` loaded at boot): blades active 1.6 s after the
  module loads, NVMe live after the BMC reboot, a `nodectl reset` of a
  blade back in 14.5 s (node Ready in ~46 s), iperf3 25.0 Gbit/s with
  four senders at once.

## [0.3.0-rc.1] - 2026-10-11

openmiop v0.3 (push mode, blades reconnect without the Cluster Box) and
the Blade 3 NVMe recovery after a Cluster Box reboot. Part of OpenMIOP
Stack v0.3.0-rc.1. Official Talos v1.14.2 kernel (6.18.54-talos) and
modules, as in 0.2.0-rc.1.

### Changed

- openmiop 0.3.0-rc.1-v1.14.2 from roysbike/pcie-ep-net `544f138`
  (tag v0.3.0-rc.1): push mode (the Cluster Box never reads a blade),
  P2P reconnect without the Cluster Box after a fabric reset, and a
  peer that stalls right after it connects is connected again after
  2 s instead of being dropped until it is reset. Works with the BMC
  helper and with the `omi-rc` module. See the pcie-ep-net changelog.

### Added

- `blade3-nvme-recover` module in the openmiop extension (loaded with
  nvme): brings the M.2 NVMe back after the Cluster Box pulsed PERST#
  (shared with the blade's endpoint link), with the official kernel.
  On a link down it restarts the LTSSM; once the link is stable it
  restores the Root Port and NVMe config space saved at load time, asks
  for 8 GT/s again and resets the NVMe with `pci_reset_function()`, so
  nvme re-initialises the controller and retries the waiting I/O.
  Must finish within the nvme I/O timeout (30 s).
- DTB: no `reset-gpios` on pcie3x2 (the shared PERST#), as in the vendor
  U-Boot.
- `blade3-leds` module in the openmiop extension: the Blade 3 RTL8125
  port LEDs now light at any link speed and blink on activity (from
  reset they only show 10/100/1000 Mbit/s activity on the wired LEDs, so
  a 2.5G port stayed dark after boot). Loaded with r8169 by PCI ID;
  `mode=` sets the LED selector.

### Removed

- The own kernel and DTB change from PR #10 (NVMe PERST# recovery in
  the kernel). The installer replaced only vmlinuz and kept the official
  modules; the kernel rejects them (`failed to validate module [sdhci]
  BTF: -22`), so there is no eMMC, NVMe or end0 and Talos boots into
  maintenance mode. Never released; do not install development images
  built between PR #10 and PR #11 (e.g. `ci-35-eacfee9f`).

### Tested

- Four Blade 3 (three control planes, one worker) on development builds
  with the same kernel, DTB, extensions and driver source as this
  release (`ci-41-be59ad07`), staged upgrades one node at a time.
- NVMe recovery: hot resets (secondary bus reset pulse) under `dd` load
  on one blade: NVMe back in ~1.6 s, no I/O error, zpool ONLINE, 8 GT/s.
  A Cluster Box reboot with all four blades on it (2026-10-11): NVMe
  back on every blade ~6 s after PERST#, no I/O or ZFS errors, DRBD and
  etcd fine, P2P back by itself.
- Push mode: `omi-rc` loaded on the BMC instead of the helper, all four
  blades active in 1.6 s without P2P interruption; a blade reset by
  `nodectl` with release first came back and its peers reconnected.

## [0.2.0-rc.1] - 2026-10-08

openmiop v0.2: interrupts and multiqueue. Part of OpenMIOP Stack
v0.2.0-rc.1. Kernel, DTB, U-Boot and the other extensions are unchanged.

### Changed

- openmiop 0.2.0-rc.1-v1.14.2 from roysbike/pcie-ep-net `665d208` (tag
  v0.2.0-rc.1): TX completion interrupts, RX doorbell through the GIC
  ITS, 4 queue pairs over both eDMA channels (RSS), negotiated per
  connection; works with 0.1 blades and the BMC helper. See the
  pcie-ep-net changelog.
- Build: the Talos kernel tree is built once as an image
  (`ghcr.io/<owner>/talos-kernel-build:<linux>-<input hash>`) and reused
  by the openmiop stage; a build without kernel changes takes ~10 min
  instead of ~60. buildx also imports/exports a registry layer cache.
- CI actions moved to their Node 24 majors.

### Tested

- Four Blade 3 (three control planes, one worker) on development builds
  with the same kernel, DTB and openmiop driver source as this release,
  installed with staged upgrades one node at a time: every pair up with
  4 queues and doorbells; 7.9-8.4 Gbit/s per pair with 4 TCP flows,
  22.2 Gbit/s for four blades sending at once; BMC reboot and hard
  resets of all four blades recovered. This release build is inspected
  in CI (`scripts/verify-installer.sh`).

### Documentation

- Upgrades: `talosctl upgrade --stage --drain=false` avoids two problems
  seen on the lab cluster: the client-side drain never finishes on nodes
  with CNPG primaries (their PDBs allow no eviction), and a reboot can
  hang in pod unmounts when storage is stuck.

## [0.1.0-rc.2] - 2026-10-06

Driver fix release. Part of OpenMIOP Stack v0.1.0-rc.2 (protocol v4,
unchanged). Kernel, DTB, U-Boot and the other extensions are unchanged.

### Changed

- openmiop 0.1.0-rc.2-v1.14.2 from roysbike/pcie-ep-net `8134fde` (driver
  source identical to tag v0.1.0-rc.2, `f9de420`, which only adds
  packaging).
- Release assets renamed: `openmiop-<version>-blade3-talos-<talos>-arm64.raw.xz`,
  `…-boot-files.tar.gz` (DTB, U-Boot, module, extension manifest),
  `BUILD-INFO.txt`, `SHA256SUMS`; the installer stays
  `ghcr.io/roysbike/mixtile-talos-installer:<tag>` (use the digest).

### Fixed

- openmiop: peers could stay "connecting" after the BMC re-enumerated the
  fabric and BAR addresses moved (blades removed or added); acks now wait
  for a window to the peer's current BAR and senders retry with a new
  token after 2 s. See the pcie-ep-net changelog.

### Documentation

- New nodes: a configuration applied to a node that booted an older raw
  image does not reinstall it; `talosctl upgrade` does.
- A new control plane cannot join etcd while a dead member is listed;
  remove it first.
- `talosctl get links omi0` does not resolve aliases; use
  `talosctl get links | grep omi0`.

## [0.1.0-rc.1] - 2026-10-06

First release candidate of Talos for the Mixtile Blade 3 with Cluster Box
PCIe fabric networking (openmiop). Part of OpenMIOP Stack v0.1.0-rc.1
(protocol v4). The installer image contains everything; nothing has to be
built to install it.

### Versions

| Component | Version |
| --- | --- |
| Talos | v1.14.2 (installer-base v1.14.2, imager v1.14.2) |
| Linux kernel | 6.18.54-talos: the official Talos kernel configuration, rebuilt at PKGS v1.14.0-37-g6c312e4 with the Talos LLVM 22.1.8 toolchain so external modules match its ABI (symbol CRCs checked against the official modules) |
| Kubernetes | not pinned by the image; tested with v1.34.3 (Talos v1.14.2 default: 1.37.1) |
| openmiop | 0.1.0-rc.1-v1.14.2 from roysbike/pcie-ep-net `922389d` (tag v0.1.0-rc.1; driver source identical to the hardware-tested `a7a8177`) |
| U-Boot | 2026.07 (Blade 3 board support from this repository) |
| TF-A | lts-v2.14.6 |
| rkbin (DDR init) | 74213af1 |
| System extensions | drbd 9.3.4-v1.14.2, zfs 2.4.4-v1.14.2, iscsi-tools v0.2.0, panfrost 20260916-v1.14.2, rockchip-rknn v1.14.2, openmiop 0.1.0-rc.1-v1.14.2 |

### Added

- openmiop system extension: `openmiop-ep.ko` built against the exact
  Talos kernel tree, installed to `/usr/lib/modules/6.18.54-talos/extras`,
  listed in the generated `modules.dep`/`modules.alias` (autoloads by DT
  modalias; `machine.kernel.modules` loads it explicitly).
- PCIe endpoint mode on the Cluster Box connector: `pcie3x4_ep`
  (`fe150000`) enabled as `openmiop,rk3588-pcie-ep`, x2, no reset GPIO;
  the host controller on the same port disabled. The blade appears behind
  the ASM2824 as `1d87:4f4d`, link Gen3 x2.
- `omi0` network: OpenMIOP protocol v4 multi-peer L2 (full mesh between
  blades, broadcast/multicast, ARP, IPv4, IPv6 ND), jumbo frames (MTU
  9000). Documented machine configuration: `LinkAliasConfig`
  (`link.driver == "openmiop-ep"` → `omi0`; udev would name it
  `enx<mac>`) and `LinkConfig` (address, MTU).
- Release pipeline: tag builds push the overlay, the openmiop extension
  and the installer to GHCR, inspect the installer image
  (`scripts/verify-installer.sh`: kernel release, command line, extension
  list, module path/hash/vermagic, modules.dep/alias, DTB nodes) and
  publish a GitHub release whose notes carry the image digests from
  `BUILD-INFO.txt`.
- `BUILD-INFO.txt` (commit, clean tree, Talos/PKGS/TOOLS, kernel,
  openmiop version and source commit, image digests, module vermagic) and
  `SHA256SUMS` next to the images.
- `scripts/openmiop-verify.sh`: read-only checks on a node after install.
- Native arm64 GitHub Actions build (the kernel tree build is too slow
  under QEMU).

### Changed

- Device tree for the Cluster Box (compared with installer v0.3.2 by
  decompiling both DTBs; no other node changed):
  - `pcie30phy`: `data-lanes = <1 1 2 2>` — two x2 halves: lanes 0-1 to
    the Cluster Box connector, lanes 2-3 to the M.2 slot;
    `rockchip,rx-common-refclk-mode = <0 0 0 0>` (separate reference
    clocks).
  - `pcie3x2` (`fe160000`) enabled for the NVMe with PERST (GPIO4_B6):
    the local NVMe is kept, now at Gen3 x2 (8 GT/s; previously 2.5 GT/s
    on the aggregated PHY), PCI domain `0001`.
  - PCIe SMMU (`mmu600_pcie`, `iommu@fc900000`) disabled: inbound BAR
    traffic from other blades and the endpoint eDMA carry stream IDs no
    Linux device owns. PCIe devices (NVMe, RTL8125) DMA without IOMMU
    translation; PCIe passthrough with vfio-pci is not available.
  - NPU: the three RKNN cores, their IOMMUs and the NPU power-domain
    supply stay enabled as in installer v0.3.2.
- Kernel command line: `module.sig_enforce=1` removed (imager
  `--extra-kernel-arg -module.sig_enforce`). Talos signs its modules
  with a key discarded after each kernel build, so no other module can
  be signed for it; the kernel is tainted by the unsigned module.
- Image package names are configurable (`OVERLAY_NAME`, `OPENMIOP_NAME`,
  `INSTALLER_IMAGE`); CI publishes `sbc-mixtile-blade3-ci`, `openmiop` and
  `mixtile-talos-installer`.

### Tested

Cluster Box with four Blade 3: two Debian 12 (vendor 6.1.99) and two
Talos v1.14.2 control-plane nodes (canary one node at a time), plus the
BMC. The Talos nodes ran CI build ci-6 of this repository: same kernel,
DTB, extensions and openmiop driver source as this release.

| Test | Result |
| --- | --- |
| Upgrade, boot, etcd rejoin, extensions, command line | OK on both Talos nodes |
| NVMe | 8 GT/s x2 (was 2.5 GT/s); ZFS pool ONLINE on both nodes |
| Endpoint | link 8 GT/s x2, activated by the BMC, peers up; module autoloaded |
| Five-member matrix | ping + jumbo between all members, TCP to apid over the fabric, IPv6 `ff02::1` |
| Debian → Talos / Talos → Debian TCP | 6.4-6.6 / 7.4-7.5 Gbit/s |
| Talos ↔ Talos TCP | 6.48 / 6.73 Gbit/s, bidirectional 4.45 + 4.51 |
| SHA-256 integrity | 1 GiB Debian→Talos, 512 MiB Talos→Debian, 512 MiB Talos→Talos: identical |
| Release image | inspected in CI (`verify-installer.sh`); the same check passes on ci-6 |
| Release installer on hardware (after tagging) | `talosctl upgrade` of .201 and .204 to `sha256:8f8ff824…`: etcd, kubelet, openmiop peers up, `omi0` up, NVMe 8 GT/s x2, ZFS ONLINE, ping/jumbo from Debian blades and BMC |

### Known limitations

- openmiop RX is polled by a kernel thread; interrupt-driven RX is not
  implemented or tested. No multiqueue.
- Talos receives ~20 % slower than Debian in these tests (6.4 vs 8.0
  Gbit/s); not investigated.
- BMC root-port re-enumeration pauses all fabric traffic ~1-2 s when a
  blade appears without a BAR address; an endpoint that disappears
  without the leave handshake (crash, power loss) can race a BMC read and
  wedge the fabric until the BMC reboots.
- Upgrading a node whose pods hold volumes on failed storage: the drain
  can fail and the reboot can hang unmounting; `--drain=false` and a BMC
  hardware reset (`nodectl reset`) were needed.
- Not hardware-tested: installing from the raw disk image of this build, NPU/GPU workloads (`rocket` and `panthor` load), VFIO, more
  than four blades.

[0.3.0-rc.1]: https://github.com/roysbike/mixtile-talos/releases/tag/v0.3.0-rc.1
[0.2.0-rc.1]: https://github.com/roysbike/mixtile-talos/releases/tag/v0.2.0-rc.1
[0.1.0-rc.2]: https://github.com/roysbike/mixtile-talos/releases/tag/v0.1.0-rc.2
[0.1.0-rc.1]: https://github.com/roysbike/mixtile-talos/releases/tag/v0.1.0-rc.1
