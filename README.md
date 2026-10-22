# Talos 1.14 for Mixtile Blade 3

[English](README.md) · [Русский](README.ru.md)

This repository builds a Talos Linux `v1.14.4` ARM64 SBC overlay and bootable
images for the Mixtile Blade 3 (RK3588), including blades installed in a
Mixtile Cluster Box.

Image build and eMMC flashing stay here. Cozystack bootstrap, storage classes,
and UI access scripts belong in the separate `cozystack-box-mixtile` project.

## Hardware and who this is for

The **Mixtile Cluster Box** is a small chassis for four **Mixtile Blade 3**
boards. Inside it:

* a management controller (BMC): MediaTek MT7620A (MIPS) with OpenWrt. It
  switches the blades on and off, resets them, gives access to their
  serial consoles and is the PCIe root complex of the box;
* an ASMedia ASM2824 PCIe Gen3 switch: a Gen3 x2 link to each blade slot
  and a Gen1 x1 uplink to the BMC.

The **Mixtile Blade 3** is a compute board with the Rockchip RK3588
(4× Cortex-A76 + 4× Cortex-A55), eMMC and an M.2 NVMe slot. Its PCIe 3.0
x4 controller is split in two: lanes 0-1 go to the Cluster Box switch,
lanes 2-3 to the NVMe. A Blade 3 also works on its own, without a
Cluster Box.

Mixtile ships the box with its own BMC firmware and its own blade
network driver (MIOP). The **OpenMIOP Stack** is an independent open
replacement for people who own a Cluster Box with Blade 3 boards (or a
single Blade 3) and want:

| You want | Repository |
| --- | --- |
| Ethernet between the blades over the PCIe switch (`omi0`, 7-8 Gbit/s per flow, ~25 Gbit/s with four senders) | [pcie-ep-net](https://github.com/roysbike/pcie-ep-net) |
| Talos Linux (Kubernetes) on Blade 3, in a Cluster Box or on its own | [mixtile-talos](https://github.com/roysbike/mixtile-talos) (this repository) |
| Current OpenWrt on the BMC: blade power and consoles, firmware updates, the BMC side of OpenMIOP | [mixtile-clusterbox-mt7620a-openwrt](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt) |

Plan to make this an official Talos image (overlay in siderolabs/sbc-rockchip,
openmiop as a signed extension): [docs/upstream.md](docs/upstream.md).

## OpenMIOP Stack v0.6.1

This repository's release **v0.6.1** is the Blade OS of the OpenMIOP
Stack v0.6.1: Talos with **openmiop**, Ethernet (`omi0`) between the blades of a
Mixtile Cluster Box over its PCIe switch, built into the installer image.

```
        Cluster Box BMC (MT7620A, OpenWrt)  — omi-rc module or openmiop-rc, omi0 10.20.0.1
                       |
                    ASM2824 PCIe switch
                       |
                  PCIe fabric (Gen3 x2 per blade)
              /      /        \       \
           B1      B2          B3      B4     Mixtile Blade 3 (RK3588)
                                              Talos + openmiop, omi0 10.20.0.x
```

| OpenMIOP Stack v0.6.1 | |
| --- | --- |
| Protocol | OpenMIOP v4 framing + per-connection features (RX doorbell, multiqueue, checksum offload), push mode, gateway pull and zero-copy to the BMC |
| Blade driver, BMC module | [pcie-ep-net v0.6.1](https://github.com/roysbike/pcie-ep-net/releases/tag/v0.6.1) (driver as v0.6.0, plus the Blade 3 board modules) |
| Blade OS | [mixtile-talos v0.6.1](https://github.com/roysbike/mixtile-talos/releases/tag/v0.6.1) (this repository) |
| ClusterBox BMC | [mixtile-clusterbox-mt7620a-openwrt v0.4.0](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt/releases/tag/v0.4.0) (OpenWrt 25.12; v0.3.0 works the same, v0.2.0 without zero-copy, v0.1.x without gateway pull) |

v0.6.1 moves to Talos v1.14.4 (Linux 6.18.57) and builds openmiop and the
Blade 3 board modules from one pcie-ep-net release, the way Talos builds
out-of-tree modules; the driver and its speed are those of v0.6.0 (one
blade-to-blade flow 7.8-8.0 Gbit/s, LAN -> blade through the BMC
~275 Mbit/s). Previous: OpenMIOP Stack v0.6.0 (mixtile-talos v0.6.0),
v0.5.0, v0.4.0, v0.3.1.

The [release page](https://github.com/roysbike/mixtile-talos/releases/tag/v0.6.1)
lists the installer image digest, the disk image, DTB, U-Boot, module and
checksums. What changed: [CHANGELOG.md](CHANGELOG.md). Details of the
openmiop integration: [docs/openmiop.md](docs/openmiop.md).

### Install or upgrade a Blade 3 node

Installer for v0.6.1 (immutable digest; the tag
`ghcr.io/roysbike/mixtile-talos-installer:v0.6.1` resolves to it):

```
ghcr.io/roysbike/mixtile-talos-installer@sha256:c0fe6ec4eb157ab8d993477b7b85abc982dc1ecbd7a9fb3cc0bcb054159fda8e
```

1. Add the openmiop documents to the machine configuration (one address
   per blade; 10.20.0.1 is the BMC) and apply them without reboot:

   ```yaml
   # omi.yaml
   machine:
     kernel:
       modules:
         - name: openmiop_ep
   ---
   apiVersion: v1alpha1
   kind: LinkAliasConfig
   name: omi0
   selector:
     match: link.driver == "openmiop-ep"
   ---
   apiVersion: v1alpha1
   kind: LinkConfig
   name: omi0
   up: true
   mtu: 9000
   addresses:
     - address: 10.20.0.<last octet of the management address>/24
   ```

   ```sh
   talosctl -n <node> patch mc --mode no-reboot -p @omi.yaml
   ```

2. Upgrade (one node at a time; mind etcd quorum; wait until DRBD and
   the databases are healthy again before the next node):

   ```sh
   talosctl -n <node> upgrade --image ghcr.io/roysbike/mixtile-talos-installer@sha256:c0fe6ec4eb157ab8d993477b7b85abc982dc1ecbd7a9fb3cc0bcb054159fda8e --stage
   ```

   Keep the default drain. A roll with `--drain=false` left DRBD replicas
   of a running database in different states and corrupted its ext4
   (2026-10-12, Cozystack on DRBD 9.3.4).

   Always pass `--image`, and set `machine.install.image` in the machine
   configuration to the same reference: `talosctl upgrade` without
   `--image` installs whatever that field still names. Do not set
   `machine.install.grubUseUKICmdline: false`; with an old image in
   `machine.install.image` this booted a kernel that rejected the
   openmiop module (no `omi0`).

   New nodes: write `openmiop-0.6.1-blade3-talos-1.14.4-arm64.raw.xz` **from this release** (see
   [Install from macOS](#install-from-macos)); check that the console
   shows `enabling system extension openmiop`. Then apply the machine
   configuration with `machine.install.image` set to the same reference
   and `machine.install.disk: /dev/mmcblk0`. Applying a configuration to a
   node that booted an older raw image does **not** reinstall it
   (`install sequence: 0 phase(s)`): run `talosctl upgrade --image ...` on
   it afterwards.

   A new control-plane node cannot join etcd while the cluster still lists
   a dead member (`error adding member: etcdserver: unhealthy cluster`):
   remove that member first (`talosctl etcd remove-member <id>`, after an
   `etcd snapshot`).

3. Verify:

   ```sh
   talosctl -n <node> read /proc/cmdline       # no module.sig_enforce
   talosctl -n <node> get extensions           # openmiop 0.6.1-v1.14.4
   talosctl -n <node> dmesg | grep openmiop    # link up, node N, peer M up
   talosctl -n <node> get links | grep omi0    # alias omi0 on enx<mac>, up
   ping -c3 -M do -s 8972 10.20.0.<node>       # from another fabric member
   ```

Rollback: `talosctl -n <node> rollback`.

Known limitations: one flow uses one queue (7-8 Gbit/s per flow), no
TSO/GSO, the BMC gateway is management-grade, a BMC reboot
resets every blade link (blades reconnect after ~12 s and recover the
NVMe); see [pcie-ep-net](https://github.com/roysbike/pcie-ep-net#known-limitations)
and [CHANGELOG.md](CHANGELOG.md).

## Source baseline

- Talos and imager: `v1.14.4`
- Talos packages: `v1.14.0-44-g2ec10eb`
- Linux: `6.18.57-talos`, the Talos ARM64 kernel configuration (rebuilt at the
  same PKGS commit so the openmiop module matches its ABI)
- U-Boot: `v2026.07`
- Board DTS and U-Boot configuration: Armbian mainline Blade 3 port
- TF-A: `lts-v2.14.6`
- Rockchip DDR training binary: rkbin commit `74213af1`

The overlay follows the same package and installer API as the official
[`siderolabs/sbc-rockchip`](https://github.com/siderolabs/sbc-rockchip)
Turing RK1 support. It adds the Blade 3-specific DTB, U-Boot and install
offset; it does not treat the Turing RK1 DTB as interchangeable with Blade 3.

## What is built

`sbc-mixtile-blade3` contains:

- `u-boot-rockchip.bin`, written at sector 64;
- `rk3588-mixtile-blade3.dtb`;
- the Talos 1.14 overlay installer;
- the raw-image profile.

The final images use the Talos v1.14.4 kernel (6.18.57-talos) and include:

- `ghcr.io/siderolabs/drbd:9.3.4-v1.14.4`
- `ghcr.io/siderolabs/zfs:2.4.4-v1.14.4`
- `ghcr.io/siderolabs/iscsi-tools:v0.2.0`
- `ghcr.io/siderolabs/panfrost:20260916-v1.14.4`
- `ghcr.io/siderolabs/rockchip-rknn:v1.14.4`
- openmiop `0.6.1-v1.14.4` (built by this repository)
- `blade3-nvme-recover` and `blade3-leds` modules in the openmiop extension, built from the same pcie-ep-net release (`drivers/blade3`) (NVMe back after a Cluster Box PERST#, port LEDs)

DRBD and ZFS therefore match the running official Talos kernel release,
module ABI and signing key.

## Build

Requirements:

- Docker with Buildx;
- access to an OCI registry visible to the build host and Talos imager;
- authenticated push access to the selected namespace.

```bash
docker login ghcr.io
USERNAME=<github-user-or-org> ./build.sh all
```

Useful individual steps:

```bash
USERNAME=<namespace> ./build.sh overlay
USERNAME=<namespace> ./build.sh image
```

Artifacts are written to `_out/`. Set `OUTPUT_DIR`, `REGISTRY`, `IMAGE_TAG`
or `TALOS_VERSION` to override their defaults.

### macOS

Docker Desktop must be running and ARM64 emulation enabled. The checked-in
Makefile is compatible with the GNU Make 3.81 shipped by macOS and does not
require GNU sed.

Cross-building and running the privileged ARM64 imager through Docker Desktop
is significantly slower than Linux. For repeatable builds, use the included
GitHub Actions workflow.

### GitHub Actions

Pushes to `claude/**` branches and `v*` tags run the workflow on a native
arm64 runner. It:

1. builds the overlay and the openmiop extension and pushes them to the
   repository owner's GHCR namespace;
2. builds installer and raw metal images and pushes the installer;
3. inspects the installer (`scripts/verify-installer.sh`) and checks
   `BUILD-INFO.txt` (commit, clean tree) and `SHA256SUMS`;
4. uploads `_out/` as a workflow artifact for 14 days;
5. on a `v*` tag, publishes the GitHub release
   (`scripts/publish-release.sh`, notes from `docs/release-notes/<tag>.md`).

No personal registry token is needed: the workflow uses `GITHUB_TOKEN` with
`packages: write`.

## Kernel configuration audit

Run:

```bash
./scripts/verify-kernel-config.sh
```

The audit checks the exact `config-arm64` from the Talos 1.14.4 package
commit and verifies that modular storage, NVMe, VFIO and Realtek drivers are
listed in the Talos ARM64 initramfs manifest.

Talos builds several drivers as modules (`m`) instead of built-ins (`y`):
NBD, NVMe, VFIO, DM thin/multipath and R8169. This is intentional and
functionally equivalent after Talos loads the modules from initramfs.

Linux 6.18/Talos uses iptables over nftables. The legacy-only
`CONFIG_IP_NF_FILTER` and `CONFIG_IP_NF_NAT` are disabled, while
`NF_TABLES`, `NFT_NAT`, `NF_NAT`, `NETFILTER_XT_NAT` and
`NETFILTER_XT_TARGET_MASQUERADE` are enabled. Enabling the legacy tables is
not required by current Kube-OVN and would require maintaining a custom
kernel plus matching DRBD/ZFS builds.

## Install from macOS

The build produces `_out/metal-arm64.raw.xz`, matching the filename used by
the [Mixtile installation guide](https://www.mixtile.com/docs/installing-talos-on-mixtile-blade-3/).
Verify and decompress the artifact before writing it:

```bash
brew install xz
xz --test _out/metal-arm64.raw.xz
xz --decompress --keep _out/metal-arm64.raw.xz
shasum -a 256 _out/metal-arm64.raw.xz
```

### microSD

Identify the target carefully. The following operation destroys all data on
the selected disk:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=_out/metal-arm64.raw of=/dev/rdiskN bs=4m
sync
diskutil eject /dev/diskN
```

Replace `diskN` with the whole microSD device, not a partition such as
`diskN1`. On macOS, press `Ctrl-T` while `dd` is running to print progress.

### eMMC over USB

Install `rkdeveloptool` from a third-party Homebrew tap:

```bash
brew tap IgorKha/rkdeveloptool
brew trust --formula IgorKha/rkdeveloptool/rkdeveloptool
brew install rkdeveloptool
```

Alternatively, build the
[official Rockchip source](https://github.com/rockchip-linux/rkdeveloptool):

```bash
brew install automake autoconf libusb pkg-config
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool
autoreconf -i
./configure
make
sudo install -m 0755 rkdeveloptool /usr/local/bin/rkdeveloptool
```

Put the Blade 3 into Rockchip Loader/Maskrom mode and confirm that it is
visible:

```bash
rkdeveloptool ld
```

The temporary `rk3588_spl_loader_*.bin` used by `rkdeveloptool db` is not
generated by this repository. Obtain the Blade 3-compatible loader described
in the Mixtile guide; do not substitute an arbitrary RK3588 loader. Save it
as `rk3588_spl_loader_v1.08.111.bin` in the repository root, set DIP switch 4
to ON, power-cycle the board, and run:

```bash
./scripts/flash-blade3-macos.sh
```

The script validates the compressed image and its RKNS U-Boot signature,
waits for exactly one Blade 3 in MaskROM mode, asks for
destructive-operation confirmation, loads the temporary SPL, and writes the
full image to eMMC. Run it with `--help` to override the image or loader
paths.

The raw image already contains the project-built U-Boot at sector 64. The SPL
loader above is only used temporarily for USB access to eMMC.

Each Blade 3 in a Cluster Box is flashed separately.

## First boot

U-Boot tries microSD, NVMe and then eMMC. Serial console is UART2 at
1,500,000 baud.

Before replacing a working installation:

1. Keep a copy of the currently bootable image.
2. Test the new image from removable media.
3. Capture the full UART log.
4. In Talos maintenance mode verify eMMC, NVMe and both Ethernet ports.
5. Only then install to eMMC/NVMe.

After boot:

```bash
talosctl -n <node> version
talosctl -n <node> read /proc/config.gz | gzip -dc
talosctl -n <node> get extensions
talosctl -n <node> get kernelmodulestatus
```

Hardware runtime verification—KVM guests, Geneve traffic, DRBD replication
and ZFS import—requires a physical Blade 3 and is not replaced by a
successful cross-build.

## Known risk

The Blade 3 mainline support is newer and less mature than the vendor 6.1
tree. U-Boot 2026.07 includes the Armbian FUSB302/USB-C PD description so PD
negotiation happens before Linux starts. For the first boot, use UART and a
known-good power source, and do not overwrite the working boot medium until
PCIe, NVMe and Ethernet have been observed.

Cluster Box endpoint support comes from the open `openmiop` driver
(<https://github.com/roysbike/pcie-ep-net>), packaged here as a system
extension together with the device tree changes it needs. See
[docs/openmiop.md](docs/openmiop.md) for what changes, the build, the
canary procedure and rollback.
