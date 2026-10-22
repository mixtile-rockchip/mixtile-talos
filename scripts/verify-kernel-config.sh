#!/usr/bin/env bash
set -Eeuo pipefail

PKGS_REF=${PKGS_REF:-2ec10eb}
TALOS_REF=${TALOS_REF:-v1.14.4}
CONFIG=${1:-}

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

if [[ -z "${CONFIG}" ]]; then
    CONFIG="${tmp}/config-arm64"
    curl -fsSL \
        "https://raw.githubusercontent.com/siderolabs/pkgs/${PKGS_REF}/kernel/build/config-arm64" \
        -o "${CONFIG}"
fi

modules="${tmp}/modules-arm64.txt"
curl -fsSL \
    "https://raw.githubusercontent.com/siderolabs/talos/${TALOS_REF}/hack/modules-arm64.txt" \
    -o "${modules}"

failed=0

require_value() {
    local symbol=$1
    local allowed=$2
    local value

    value=$(awk -F= -v key="CONFIG_${symbol}" '$1 == key { print $2; exit }' "${CONFIG}")
    if [[ -z "${value}" ]] && grep -q "^# CONFIG_${symbol} is not set$" "${CONFIG}"; then
        value=n
    fi
    if [[ -z "${value}" && ",${allowed}," == *",n,"* ]]; then
        # Kconfig omits symbols whose dependencies are disabled.
        value=n
    fi

    if [[ ! ",${allowed}," =~ ,${value}, ]]; then
        printf 'FAIL %-32s expected %-5s got %s\n' "CONFIG_${symbol}" "${allowed}" "${value:-missing}"
        failed=1
    else
        printf 'OK   %-32s %s\n' "CONFIG_${symbol}" "${value}"
    fi
}

require_module() {
    local path=$1

    if ! grep -qx "${path}" "${modules}"; then
        echo "FAIL initramfs module missing: ${path}"
        failed=1
    else
        echo "OK   initramfs module: ${path}"
    fi
}

for symbol in \
    BRIDGE BRIDGE_NETFILTER VETH TUN VXLAN GENEVE \
    NETFILTER NF_CONNTRACK NF_NAT NETFILTER_XTABLES \
    IP_NF_IPTABLES NF_TABLES NFT_NAT NETFILTER_XT_NAT \
    OPENVSWITCH OPENVSWITCH_GENEVE OPENVSWITCH_VXLAN \
    VIRTUALIZATION KVM VHOST VHOST_NET VHOST_VSOCK \
    BLK_DEV_DM SCSI ISCSI_TCP SCSI_ISCSI_ATTRS \
    OVERLAY_FS EXT4_FS XFS_FS; do
    require_value "${symbol}" y
done

# Talos intentionally ships these as modules and includes them in initramfs.
for symbol in \
    VFIO VFIO_PCI VFIO_IOMMU_TYPE1 BLK_DEV_NBD \
    DM_THIN_PROVISIONING DM_MULTIPATH BLK_DEV_NVME R8169; do
    require_value "${symbol}" m
done

for path in \
    kernel/drivers/vfio/vfio.ko \
    kernel/drivers/vfio/pci/vfio-pci.ko \
    kernel/drivers/vfio/vfio_iommu_type1.ko \
    kernel/drivers/block/nbd.ko \
    kernel/drivers/md/dm-thin-pool.ko \
    kernel/drivers/md/dm-multipath.ko \
    kernel/drivers/nvme/host/nvme.ko \
    kernel/drivers/net/ethernet/realtek/r8169.ko; do
    require_module "${path}"
done

# Linux 6.18 keeps these only behind legacy xtables. Talos uses iptables-nft.
require_value NETFILTER_XTABLES_LEGACY n
require_value IP_NF_FILTER n
require_value IP_NF_NAT n

exit "${failed}"
