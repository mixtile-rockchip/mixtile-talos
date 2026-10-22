# openmiop on Talos: Ethernet over the Cluster Box PCIe fabric

`omi0` connects the blades of a Mixtile Cluster Box (and the Cluster Box
BMC) over the internal PCIe switch. Blade-to-blade frames are DMA writes
from one RK3588 straight into another's memory through the ASM2824; the
BMC only publishes a peer table and carries a slow management path.
Driver and design: <https://github.com/roysbike/pcie-ep-net>
(`docs/architecture.md`, `docs/talos-port.md`).

## What the image changes

| Change | Where | Why |
| --- | --- | --- |
| `openmiop` system extension (`openmiop-ep.ko` in `extras/`) | `artifacts/openmiop`, `build.sh` | the driver |
| Talos kernel tree rebuilt for module builds | `artifacts/talos-kernel` | Talos publishes no build tree |
| `-module.sig_enforce` | `build.sh` (imager `--extra-kernel-arg`) | the official module key is discarded after each kernel build; the module is unsigned |
| PCIe3 PHY split into two x2, refclk mode off | DTS `&pcie30phy` | lanes 0-1 go to the Cluster Box, 2-3 to the M.2 slot; separate reference clocks |
| `pcie3x4` host off, `pcie3x4_ep` on (`openmiop,rk3588-pcie-ep`) | DTS | fe150000 becomes the endpoint |
| NVMe on `pcie3x2` with PERST | DTS | as on the vendor kernel; the NVMe trains 8 GT/s x2 instead of 2.5 GT/s |
| `mmu600_pcie` disabled | DTS | endpoint traffic carries stream IDs no device owns; PCIe devices DMA untranslated |
| panfrost, rockchip-rknn extensions | `build.sh` | the running nodes have them |

The NVMe moves from PCI domain 0000 to 0001. Pools and disks found by
serial/WWID are unaffected.

## Build

CI (`.github/workflows/build-talos.yaml`) builds on native arm64 runners
for every push to a `claude/**` branch and publishes:

* `ghcr.io/<owner>/sbc-mixtile-blade3-ci:<tag>` (overlay)
* `ghcr.io/<owner>/openmiop:<openmiop_version>` (extension)
* `ghcr.io/<owner>/mixtile-talos-installer:<tag>` (installer for
  `talosctl upgrade`; the digest is in `_out/installer-image.txt` of the
  workflow artifact)

Locally: `USERNAME=<ns> ./build.sh all` (Docker with Buildx; on an
x86 host the kernel stage runs under emulation and takes hours).
`OPENMIOP=0` builds the image without the driver and keeps
`module.sig_enforce`.

## Machine configuration

udev names the interface `enx<MAC>` (Talos predictable names), so a
`LinkAliasConfig` gives it the name `omi0` by driver:

```yaml
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
  - address: 10.20.0.<last octet of the node's management address>/24
```

The BMC is `10.20.0.1`. Pod and service CIDRs of the cluster
(10.244.0.0/16, 10.96.0.0/16) do not overlap.

## Canary procedure (one node at a time)

1. `talosctl -n <node> etcd status` and `etcd members`: all members
   healthy; the node being upgraded is one of three.
2. Record the current state: `talosctl -n <node> version`,
   `get extensions`, the installer image in the machine config.
3. Apply the configuration above (`talosctl -n <node> patch mc --mode no-reboot -p @omi.yaml`).
4. `talosctl -n <node> upgrade --image ghcr.io/<owner>/mixtile-talos-installer:<tag>`.
   On the Cluster Box nodes (2026-10-06) the drain failed and the
   reboot then hung unmounting CSI volumes whose backing NVMe had
   failed. What worked: `--drain=false` (the node stays cordoned from
   the failed drain), and when the sequence hung in `unmountPodMounts`,
   a hardware reset from the BMC (`nodectl reset -n <slot>`); the new
   image was already installed and booted. Uncordon afterwards.
5. On the Cluster Box: the third endpoint appears; if the bridge windows
   are too small, `openmiop-rc` re-enumerates the switch (all P2P traffic
   pauses for ~1.5 s).
6. Verify: `talosctl -n <node> read /proc/cmdline` (no
   `module.sig_enforce`), `get extensions` (openmiop), `dmesg | grep
   openmiop` (link up, node index, peers up), NVMe on `0001:11:00.0` at
   8 GT/s, `get links | grep omi0`, ping and `talosctl -n 10.20.0.<x> version`
   over the fabric, management network unchanged.

## Rollback

* `talosctl -n <node> rollback` boots the previous slot. The DTB and
  U-Boot written by the overlay installer are shared by both slots, so
  the endpoint DTB stays; without the module the endpoint is simply not
  bound and the node runs as before (NVMe now on pcie3x2).
* Full revert: `talosctl upgrade --image <previous installer>` and
  remove the `openmiop_ep` module and the `omi0` LinkConfig.
* A node that does not boot: serial console on the BMC
  (`nodectl console -n <slot>`), choose the previous entry in GRUB.
