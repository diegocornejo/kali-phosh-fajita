#!/bin/bash
# sync_slots.sh - Clones one boot slot to the other dynamically
# Usage: sudo ./sync_slots.sh [a|b]

set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root. Use sudo."
    exit 1
fi

echo "==> Detecting partition paths..."

# Mainline Linux uses /dev/disk/by-partlabel/ ; Android/TWRP uses /dev/block/by-name/
if [ -e "/dev/disk/by-partlabel/boot_a" ]; then
    BOOT_A="/dev/disk/by-partlabel/boot_a"
    BOOT_B="/dev/disk/by-partlabel/boot_b"
elif [ -e "/dev/block/by-name/boot_a" ]; then
    BOOT_A="/dev/block/by-name/boot_a"
    BOOT_B="/dev/block/by-name/boot_b"
else
    echo "Error: Could not locate boot partitions."
    exit 1
fi

# Determine Source Slot based on argument or active running slot detection
USER_ARG="${1:-}"
if [ -z "$USER_ARG" ]; then
    SRC_SLOT=$(grep -o 'androidboot.slot_suffix=_[a-b]' /proc/cmdline | cut -d'_' -f2)
    [ -z "$SRC_SLOT" ] && SRC_SLOT="a"
    echo "==> No source specified. Auto-detected active running slot: $SRC_SLOT"
elif [ "$USER_ARG" = "a" ] || [ "$USER_ARG" = "b" ]; then
    SRC_SLOT="$USER_ARG"
    echo "==> Source explicitly set to slot: $SRC_SLOT"
else
    echo "Error: Invalid argument '$USER_ARG'. Use 'a' or 'b'."
    exit 1
fi

# Set Source and Target paths based on the chosen source slot
if [ "$SRC_SLOT" = "a" ]; then
    SRC_PART="$BOOT_A"
    TGT_PART="$BOOT_B"
    TGT_SLOT="b"
else
    SRC_PART="$BOOT_B"
    TGT_PART="$BOOT_A"
    TGT_SLOT="a"
fi

echo "----------------------------------------------------"
echo "WARNING: This will completely overwrite Slot $TGT_SLOT"
echo "with the boot image currently on Slot $SRC_SLOT."
echo "Source ($SRC_SLOT): $SRC_PART"
echo "Target ($TGT_SLOT): $TGT_PART"
echo "----------------------------------------------------"

read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation aborted."
    exit 1
fi

echo "==> Cloning Slot $SRC_SLOT to Slot $TGT_SLOT..."
dd if="$SRC_PART" of="$TGT_PART" bs=4M status=progress

echo "==> Flushing data to storage..."
sync

echo "==> Success! Slot $TGT_SLOT is now an exact clone of Slot $SRC_SLOT."
