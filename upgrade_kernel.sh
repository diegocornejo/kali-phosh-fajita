#!/bin/bash
# upgrade_kernel.sh - Packages new kernel files into a boot.img with Host mode patched

set -e

# Target version (Must match what is in /boot/)
KVER="6.12.37-qcom"
NEW_KERNEL="/boot/vmlinuz-$KVER"
NEW_INITRD="/boot/initrd.img-$KVER"

echo "==> Verifying new kernel files exist..."
[ ! -f "$NEW_KERNEL" ] && { echo "Error: Kernel $NEW_KERNEL not found"; exit 1; }
[ ! -f "$NEW_INITRD" ] && { echo "Error: Initramfs $NEW_INITRD not found"; exit 1; }

# Locate the DTB for the new kernel
NEW_DTB=$(find /usr/lib/linux-image-$KVER -name "sdm845-oneplus-fajita.dtb" 2>/dev/null | head -n 1)
if [ -z "$NEW_DTB" ]; then
    NEW_DTB=$(find /boot/dtbs*/$KVER -name "sdm845-oneplus-fajita.dtb" 2>/dev/null | head -n 1)
fi
[ ! -f "$NEW_DTB" ] && { echo "Error: sdm845-oneplus-fajita.dtb not found for $KVER"; exit 1; }

# Find active boot partition slot (a or b)
SLOT=$(grep -o 'androidboot.slot_suffix=_[a-b]' /proc/cmdline | cut -d'_' -f2)
[ -z "$SLOT" ] && { echo "Warning: Could not detect active slot. Defaulting to a."; SLOT="a"; }
BOOT_PART="/dev/disk/by-partlabel/boot_$SLOT"
[ ! -b "$BOOT_PART" ] && { echo "Error: Could not find $BOOT_PART"; exit 1; }

WORKDIR=$(mktemp -d)
echo "==> Working in temp directory: $WORKDIR"
cd "$WORKDIR"

echo "==> Backing up current running boot partition..."
dd if="$BOOT_PART" of=current_boot.img bs=4M 2>/dev/null

echo "==> Unpacking current boot.img to extract hardware parameters..."
unpack_bootimg --boot_img current_boot.img --out extracted/ > /dev/null

CMDLINE=$(cat extracted/cmdline)
PAGESIZE=$(cat extracted/pagesize)
OS_VER=$(cat extracted/os_version)
OS_PATCH=$(cat extracted/os_patch_level)
HEADER_VER=$(cat extracted/header_version)

echo "==> Decompiling new 6.12.37 DTB..."
dtc -I dtb -O dts -o fajita.dts "$NEW_DTB" 2>/dev/null

echo "==> Patching DTB for USB Host Mode..."
sed -i 's/dr_mode = "peripheral";/dr_mode = "host";/g' fajita.dts
sed -i 's/dr_mode = "otg";/dr_mode = "host";/g' fajita.dts

echo "==> Recompiling patched DTB..."
dtc -I dts -O dtb -o patched_fajita.dtb fajita.dts 2>/dev/null

echo "==> Packing new boot.img with 6.12.37 kernel..."
mkbootimg --kernel "$NEW_KERNEL" \
          --ramdisk "$NEW_INITRD" \
          --dtb patched_fajita.dtb \
          --cmdline "$CMDLINE" \
          --os_version "$OS_VER" \
          --os_patch_level "$OS_PATCH" \
          --header_version "$HEADER_VER" \
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
