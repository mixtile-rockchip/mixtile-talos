#!/bin/sh
# Check a Talos node after installing the openmiop image.
#
#   scripts/openmiop-verify.sh <node-ip>
#
# Read-only: uses talosctl get/read/dmesg only.
set -u
N=${1:?usage: $0 <node-ip>}
KREL=$(awk '/^  linux_version:/{print $2}' "$(dirname "$0")/../Pkgfile")-talos
t() { talosctl -n "$N" "$@" 2>&1; }
ok=0
check() { # label, condition-result
	if [ "$2" = 0 ]; then echo "  ok    $1"; else echo "  FAIL  $1"; ok=1; fi
}

echo "== $N"
t version --short | sed 's/^/  /' | grep -E "Tag|SHA" | head -2
cmdline=$(t read /proc/cmdline)
echo "  cmdline: $cmdline"
echo "$cmdline" | grep -q "module.sig_enforce" ; check "module.sig_enforce absent" $((1 - $?))
t read /proc/version | grep -q "$KREL"; check "kernel $KREL" $?

ext=$(t get extensions)
for e in openmiop drbd zfs iscsi-tools panfrost rockchip-rknn; do
	echo "$ext" | grep -qw "$e"; check "extension $e" $?
done

mods=$(t read /proc/modules)
echo "$mods" | grep -q "^openmiop_ep "; check "openmiop_ep loaded" $?
echo "$mods" | grep -q "^blade3_leds "; check "blade3_leds loaded" $?
echo "$mods" | grep -q "^blade3_nvme_recover "; check "blade3_nvme_recover loaded" $?
dmesg=$(t dmesg)
echo "$dmesg" | grep -E "openmiop-ep" | grep -E "phy mode|link up|node index|peer . up|omi0 mac" | tail -6 | sed 's/^/    /'
echo "$dmesg" | grep -q "openmiop-ep.*link up"; check "endpoint link up" $?
echo "$dmesg" | grep -q "openmiop-ep.*node index"; check "activated by the Cluster Box" $?
# "module verification failed" is expected: the module is unsigned.
echo "$dmesg" | grep -iE "openmiop.*(oops|bug|failed|did not)" | grep -qv "module verification failed"; check "no openmiop errors" $((1 - $?))
echo "$dmesg" | grep -qE "rcu: .*stall|soft lockup|Internal error: Oops| BUG: "; check "no stalls/oopses" $((1 - $?))

for f in current_link_speed current_link_width; do
	printf '  nvme %s: %s\n' "$f" "$(t read /sys/bus/pci/devices/0001:11:00.0/$f)"
done
t get disks | grep -q nvme0n1; check "NVMe present" $?
# udev names the link enx<mac>; LinkAliasConfig gives it the alias omi0.
t get links | grep -E " omi0 " | grep -q " up "; check "omi0 link up (alias)" $?
t get addresses | grep -E "10\.20\.0\." | sed 's/^/    /'
t get addresses | grep -E "end0|enP" | head -2 | sed 's/^/    /'
exit $ok
