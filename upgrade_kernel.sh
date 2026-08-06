#!/bin/bash
# upgrade_kernel.sh - Packages new kernel files into a boot.img with Host mode patched

set -e

# Target paths for Kali rolling release on OnePlus 6T
KVER="6.12.37-qcom"
NEW_KERNEL="/boot/vmlinuz-6.12-qcom"
NEW_INITRD="/boot/initrd.img-6.12-qcom"
NEW_DTB="/usr/lib/linux-image-6.12-qcom/qcom/sdm845-oneplus-fajita.dtb"

echo "==> Verifying new kernel and DTB files exist..."
[ ! -f "$NEW_KERNEL" ] && { echo "Error: Kernel $NEW_KERNEL not found"; exit 1; }
[ ! -f "$NEW_INITRD" ] && { echo "Error: Initramfs $NEW_INITRD not found"; exit 1; }
[ ! -f "$NEW_DTB" ] && { echo "Error: DTB $NEW_DTB not found"; exit 1; }

# Find active boot partition slot (a or b)
SLOT=$(grep -o 'androidboot.slot_suffix=_[a-b]' /proc/cmdline | cut -d'_' -f2)
[ -z "$SLOT" ] && { echo "Warning: Could not detect active slot. Defaulting to a."; SLOT="a"; }
BOOT_PART="/dev/disk/by-partlabel/boot_$SLOT"
[ ! -b "$BOOT_PART" ] && { echo "Error: Could not find $BOOT_PART"; exit 1; }

WORKDIR=$(mktemp -d)
echo "==> Working in temp directory: $WORKDIR"
cd "$WORKDIR"

echo "==> Pulling active kernel command line from system..."
CMDLINE=$(cat /proc/cmdline)
PAGESIZE="4096"
HEADER_VERSION="2"

echo "==> Decompiling new DTB..."
dtc -I dtb -O dts -o fajita.dts "$NEW_DTB" 2>/dev/null

echo "==> Patching DTB for USB Host Mode..."
sed -i 's/dr_mode = "peripheral";/dr_mode = "host";/g' fajita.dts
sed -i 's/dr_mode = "otg";/dr_mode = "host";/g' fajita.dts

echo "==> Recompiling patched DTB..."
dtc -I dts -O dtb -o patched_fajita.dtb fajita.dts 2>/dev/null

echo "==> Packing new boot.img with 6.12-qcom kernel and patched DTB..."
mkbootimg --kernel "$NEW_KERNEL" \
          --ramdisk "$NEW_INITRD" \
          --dtb patched_fajita.dtb \
          --cmdline "$CMDLINE" \
          --header_version "$HEADER_VERSION" \
          --pagesize "$PAGESIZE" \
          -o new_boot.img

echo "==> SUCCESS! New boot image generated: $WORKDIR/new_boot.img"

read -p "Do you want to flash it to $BOOT_PART right now? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    echo "==> Flashing..."
    dd if=new_boot.img of="$BOOT_PART" bs=4M status=progress
    echo "==> Done! You are ready to reboot."
else
    echo "==> Skipping flash. File is at $WORKDIR/new_boot.img"
fi
