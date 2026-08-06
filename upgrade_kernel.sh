#!/bin/bash
# upgrade_kernel.sh - Packages new kernel files into a boot.img with Host mode patched
# Usage: sudo ./upgrade_kernel.sh [a|b|both]

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

# Determine which slot(s) to target based on argument or active slot detection
USER_ARG="${1:-}"
if [ -z "$USER_ARG" ]; then
    DETECTED_SLOT=$(grep -o 'androidboot.slot_suffix=_[a-b]' /proc/cmdline | cut -d'_' -f2)
    [ -z "$DETECTED_SLOT" ] && DETECTED_SLOT="a"
    TARGET_SLOTS=("$DETECTED_SLOT")
    echo "==> No slot specified. Defaulting to active slot: $DETECTED_SLOT"
elif [ "$USER_ARG" = "both" ]; then
    TARGET_SLOTS=("a" "b")
    echo "==> Target set to BOTH slots (a and b)."
elif [ "$USER_ARG" = "a" ] || [ "$USER_ARG" = "b" ]; then
    TARGET_SLOTS=("$USER_ARG")
    echo "==> Target explicitly set to slot: $USER_ARG"
else
    echo "Error: Invalid argument '$USER_ARG'. Use 'a', 'b', or 'both'."
    exit 1
fi

WORKDIR=$(mktemp -d)
echo "==> Working in temp directory: $WORKDIR"
cd "$WORKDIR"

echo "==> Pulling active kernel command line from system..."
CMDLINE=$(cat /proc/cmdline)

# 1. Strip all 'androidboot.*' arguments (the bootloader dynamically adds these anyway, they shouldn't be baked in)
CMDLINE=$(echo "$CMDLINE" | sed 's/androidboot\.[^ ]*//g')

# 2. Remove duplicate 'dr_mode=host' strings if they got stacked up
CMDLINE=$(echo "$CMDLINE" | sed 's/dr_mode=host//g')
CMDLINE="$CMDLINE dr_mode=host"

# 3. Clean up extra spaces to save characters
CMDLINE=$(echo "$CMDLINE" | tr -s ' ' | sed 's/^ *//;s/ *$//')

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

# Build target partition list strings
PART_LIST=""
for s in "${TARGET_SLOTS[@]}"; do
    PART_LIST="$PART_LIST /dev/disk/by-partlabel/boot_$s"
done

read -p "Do you want to flash it to target slot(s) ($USER_ARG) right now? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    for s in "${TARGET_SLOTS[@]}"; do
        BOOT_PART="/dev/disk/by-partlabel/boot_$s"
        [ ! -b "$BOOT_PART" ] && { echo "Error: Partition $BOOT_PART not found!"; exit 1; }
        echo "==> Flashing to $BOOT_PART..."
        dd if=new_boot.img of="$BOOT_PART" bs=4M status=progress
    done
    echo "==> Done! All target slots successfully updated. You are ready to reboot."
else
    echo "==> Skipping flash. File is safely stored at $WORKDIR/new_boot.img"
fi
