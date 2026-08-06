#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Use sudo."
  exit 1
fi

echo "Detecting partition paths..."

# Mainline Linux usually uses /dev/disk/by-partlabel/
# TWRP/Android uses /dev/block/by-name/
if [ -e "/dev/disk/by-partlabel/boot_b" ]; then
    BOOT_B="/dev/disk/by-partlabel/boot_b"
    BOOT_A="/dev/disk/by-partlabel/boot_a"
elif [ -e "/dev/block/by-name/boot_b" ]; then
    BOOT_B="/dev/block/by-name/boot_b"
    BOOT_A="/dev/block/by-name/boot_a"
else
    echo "Error: Could not locate boot partitions."
    exit 1
fi

echo "Source (Slot B): $BOOT_B"
echo "Target (Slot A): $BOOT_A"
echo "----------------------------------------------------"
echo "WARNING: This will completely overwrite Slot A"
echo "with the kernel/boot image currently on Slot B."
echo "----------------------------------------------------"

read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation aborted."
    exit 1
fi

echo "Cloning Slot B to Slot A..."
# bs=4M speeds up the transfer, status=progress shows a live progress bar
dd if="$BOOT_B" of="$BOOT_A" bs=4M status=progress

echo "Flushing data to storage..."
sync

echo "Success! Both slots now have identical boot images."
