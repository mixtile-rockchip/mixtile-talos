#!/usr/bin/env bash
# Check what is inside a built Talos installer image, not what the build
# asked for: kernel release and command line of the UKI, the system
# extensions in its initramfs, the openmiop module and the Blade 3 DTB.
#
#   scripts/verify-installer.sh [OUTPUT_DIR]     (default: _out)
#
# Needs: python3, zstd, unsquashfs (squashfs-tools), dtc.
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${1:-"${ROOT}/_out"}
KERNEL=$(awk '/^  linux_version:/{print $2}' "${ROOT}/Pkgfile")-talos
OPENMIOP_VERSION=$(awk '/^  openmiop_version:/{print $2}' "${ROOT}/Pkgfile")
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

[[ -f "${OUT}/installer-arm64.tar" ]] || fail "${OUT}/installer-arm64.tar missing"

# Unpack the image layers (docker-archive or OCI layout inside the tar).
mkdir -p "${WORK}/img" "${WORK}/fs"
tar -xf "${OUT}/installer-arm64.tar" -C "${WORK}/img"
python3 - "${WORK}/img" "${WORK}/fs" <<'EOF'
import json, os, sys, tarfile
img, fs = sys.argv[1:]
layers = json.load(open(os.path.join(img, "manifest.json")))[0]["Layers"]
for layer in layers:
    with tarfile.open(os.path.join(img, layer)) as t:
        for m in t.getmembers():
            if os.path.basename(m.name).startswith(".wh.") or m.isdev():
                continue
            t.extract(m, fs, set_attrs=False, filter="fully_trusted")
EOF

UKI=${WORK}/fs/usr/install/arm64/vmlinuz.efi
[[ -f "${UKI}" ]] || fail "no usr/install/arm64/vmlinuz.efi in the installer"

# UKI sections: .uname, the first .cmdline, .initrd.
python3 - "${UKI}" "${WORK}" <<'EOF'
import struct, sys
f = open(sys.argv[1], "rb").read(); work = sys.argv[2]
pe = struct.unpack_from("<I", f, 0x3c)[0]
nsec = struct.unpack_from("<H", f, pe + 6)[0]
off = pe + 24 + struct.unpack_from("<H", f, pe + 20)[0]
seen = set()
for _ in range(nsec):
    name = f[off:off + 8].rstrip(b"\0").decode(errors="replace")
    vsize, _, _, rawptr = struct.unpack_from("<IIII", f, off + 8)
    data = f[rawptr:rawptr + vsize]
    if name in (".uname", ".cmdline", ".initrd") and name not in seen:
        seen.add(name)
        open(f"{work}/sec-{name[1:]}", "wb").write(data.rstrip(b"\0") if name != ".initrd" else data)
    off += 40
EOF

uname=$(cat "${WORK}/sec-uname")
[[ "${uname}" == "${KERNEL}" ]] || fail "UKI kernel ${uname}, expected ${KERNEL}"
ok "kernel ${uname}"

cmdline=$(cat "${WORK}/sec-cmdline")
[[ "${cmdline}" != *module.sig_enforce=1* ]] || fail "cmdline still has module.sig_enforce=1: ${cmdline}"
ok "cmdline without module.sig_enforce: ${cmdline}"

# The initramfs is a chain of newc archives; keep the extension images,
# the generated modules.dep image and extensions.yaml.
mkdir -p "${WORK}/initrd"
zstd -dqc "${WORK}/sec-initrd" > "${WORK}/initrd.cpio"
python3 - "${WORK}/initrd.cpio" "${WORK}/initrd" <<'EOF'
import sys
d = open(sys.argv[1], "rb").read(); out = sys.argv[2]; i = 0
while True:
    j = d.find(b"070701", i)
    if j < 0:
        break
    h = d[j:j + 110]
    try:
        namesize = int(h[94:102], 16); filesize = int(h[54:62], 16)
    except ValueError:
        i = j + 6; continue
    name = d[j + 110:j + 110 + namesize - 1].decode(errors="replace")
    p = (j + 110 + namesize + 3) & ~3
    if (name.endswith(".sqsh") and name != "rootfs.sqsh") or name == "extensions.yaml":
        open(f"{out}/{name.replace('/', '_')}", "wb").write(d[p:p + filesize])
    i = (p + filesize + 3) & ~3 if filesize else j + 6
EOF

[[ -f "${WORK}/initrd/extensions.yaml" ]] || fail "no extensions.yaml in the initramfs"
python3 - "${WORK}/initrd/extensions.yaml" "${OPENMIOP_VERSION}" <<'EOF' || fail "openmiop ${OPENMIOP_VERSION} not listed in extensions.yaml"
import re, sys
text = open(sys.argv[1]).read()
ext = re.findall(r"^\s+name: (\S+)\n\s+version: (\S+)$", text, re.M)
print("extensions:", ", ".join(f"{n} {v}" for n, v in ext))
sys.exit(0 if ("openmiop", sys.argv[2]) in ext else 1)
EOF
ok "extension openmiop ${OPENMIOP_VERSION} in the initramfs"

ko=
for sq in "${WORK}"/initrd/*.sqsh; do
    d=${sq%.sqsh}.d
    unsquashfs -q -n -d "${d}" "${sq}" >/dev/null 2>&1 || continue
    f=$(find "${d}" -name openmiop-ep.ko -print -quit)
    [[ -n "${f}" ]] && ko=${f}
done
[[ -n "${ko}" ]] || fail "openmiop-ep.ko not found in any extension image"
[[ "${ko}" == */usr/lib/modules/${KERNEL}/extras/openmiop-ep.ko ]] || fail "openmiop-ep.ko at unexpected path ${ko#"${WORK}"/initrd/}"
if [[ -f "${OUT}/openmiop-ep.ko" ]]; then
    [[ "$(sha256sum < "${ko}")" == "$(sha256sum < "${OUT}/openmiop-ep.ko")" ]] ||
        fail "openmiop-ep.ko in the installer differs from ${OUT}/openmiop-ep.ko"
fi
vermagic=$(strings "${ko}" | sed -n 's/^vermagic=//p')
[[ "${vermagic}" == "${KERNEL} "* ]] || fail "openmiop-ep.ko vermagic '${vermagic}'"
ok "openmiop-ep.ko $(sha256sum < "${ko}" | cut -c1-16)…, vermagic ${vermagic}"

grep -rqs "extras/openmiop-ep.ko" "${WORK}"/initrd/*.d/usr/lib/modules/*/modules.dep ||
    fail "openmiop-ep.ko not in the generated modules.dep"
grep -rqs "openmiop,rk3588-pcie-ep" "${WORK}"/initrd/*.d/usr/lib/modules/*/modules.alias ||
    fail "openmiop DT alias not in the generated modules.alias"
ok "openmiop in modules.dep and modules.alias"
grep -rqs "extras/blade3-leds.ko" "${WORK}"/initrd/*.d/usr/lib/modules/*/modules.dep ||
    fail "blade3-leds.ko not in the generated modules.dep"
grep -rqs "pci:v000010ECd00008125.* blade3_leds" "${WORK}"/initrd/*.d/usr/lib/modules/*/modules.alias ||
    fail "blade3-leds has no RTL8125 alias"
ok "blade3-leds in modules.dep and modules.alias"

dtb=$(find "${WORK}/fs" -name rk3588-mixtile-blade3.dtb -print -quit)
[[ -n "${dtb}" ]] || fail "rk3588-mixtile-blade3.dtb not in the installer"
if [[ -f "${OUT}/rk3588-mixtile-blade3.dtb" ]]; then
    cmp -s "${dtb}" "${OUT}/rk3588-mixtile-blade3.dtb" || fail "installer DTB differs from ${OUT}/rk3588-mixtile-blade3.dtb"
fi
dtc -q -I dtb -O dts "${dtb}" > "${WORK}/blade3.dts"
python3 - "${WORK}/blade3.dts" <<'EOF' || fail "DTB content check"
import re, sys
dts = open(sys.argv[1]).read()
def node(label):
    m = re.search(r"\n(\t*)" + re.escape(label) + r" \{\n(.*?)\n\1\};", dts, re.S)
    return m.group(2) if m else ""
checks = {
    "pcie@fe150000 (endpoint) is openmiop and okay":
        lambda: any('"openmiop,rk3588-pcie-ep"' in b and 'status = "okay"' in b
                    for b in re.findall(r"pcie-ep@fe150000 \{(.*?)\n\t\};", dts, re.S)),
    "pcie@fe150000 host disabled":
        lambda: 'status = "disabled"' in node("pcie@fe150000"),
    "pcie@fe160000 (NVMe host) okay":
        lambda: 'status = "okay"' in node("pcie@fe160000"),
    "PCIe SMMU iommu@fc900000 disabled":
        lambda: 'status = "disabled"' in node("iommu@fc900000"),
    "PCIe3 PHY bifurcated (data-lanes 1 1 2 2)":
        lambda: "data-lanes = <0x01 0x01 0x02 0x02>" in node("phy@fee80000"),
    "NPU core 0 enabled":
        lambda: 'status = "okay"' in node("npu@fdab0000"),
}
bad = [k for k, f in checks.items() if not f()]
for k in checks:
    print(("ok: " if k not in bad else "FAIL: ") + k)
sys.exit(1 if bad else 0)
EOF
ok "DTB $(sha256sum < "${dtb}" | cut -c1-16)…"
echo "installer verified"
