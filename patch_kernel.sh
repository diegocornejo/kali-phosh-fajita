#!/bin/bash
# upgrade_kernel.sh - Unpacks, patches DTB/cmdline, and repacks boot.img with the NEW kernel

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

echo "==> Detecting boot partition..."
if [ -e "/dev/disk/by-partlabel/boot_a" ]; then
    BOOT_DIR="/dev/disk/by-partlabel"
elif [ -e "/dev/block/by-name/boot_a" ]; then
    BOOT_DIR="/dev/block/by-name"
else
    echo "Error: Could not locate boot partitions."
    exit 1
fi

ACTIVE_SLOT=$(grep -o 'androidboot.slot_suffix=_[a-b]' /proc/cmdline | cut -d'_' -f2)
[ -z "$ACTIVE_SLOT" ] && ACTIVE_SLOT="a"
BOOT_PART="${BOOT_DIR}/boot_${ACTIVE_SLOT}"
echo "==> Active boot partition: $BOOT_PART"

WORKSPACE=$(mktemp -d)
echo "==> Working in $WORKSPACE"
cd "$WORKSPACE"

echo "==> Dumping current boot image..."
dd if="$BOOT_PART" of=boot.img status=none

echo "==> Unpacking boot image..."
mkdir unpacked
unpackbootimg -i boot.img -o unpacked

echo "==> Cleaning and formatting kernel command line..."
CMDLINE=$(cat unpacked/boot.img-cmdline)

# Strip androidboot.* arguments (these are injected by the bootloader dynamically)
CMDLINE=$(echo "$CMDLINE" | sed 's/androidboot\.[^ ]*//g')
# Remove any duplicate dr_mode=host arguments
CMDLINE=$(echo "$CMDLINE" | sed 's/dr_mode=host//g')
# Append exactly one dr_mode=host cleanly
CMDLINE="$CMDLINE dr_mode=host"
# Clean up extra whitespaces to save character space
CMDLINE=$(echo "$CMDLINE" | tr -s ' ' | sed 's/^ *//;s/ *$//')

echo "==> New cmdline length: ${#CMDLINE} (must be under 1535)"

echo "==> Preserving original DTB..."
if [ -s unpacked/boot.img-dtb ]; then
    DTB_ARG="--dtb unpacked/boot.img-dtb"
else
    DTB_ARG=""
fi

echo "==> Repacking new_boot.img with NEW kernel..."
NEW_KERNEL=$(ls -v /boot/vmlinuz-* | tail -n 1)
if [ ! -f "$NEW_KERNEL" ]; then
    echo "Error: $NEW_KERNEL not found. Ensure apt install was successful."
    exit 1
fi

echo "==> Gathering original boot image metadata..."
EXTRA_ARGS=""
for arg in header_version kernel_offset ramdisk_offset tags_offset dtb_offset; do
    if [ -f "unpacked/boot.img-${arg}" ]; then
        EXTRA_ARGS="$EXTRA_ARGS --${arg} $(cat unpacked/boot.img-${arg})"
    fi
done

echo "==> Repacking new_boot.img with NEW kernel and preserved headers..."
mkbootimg \
    --kernel "$NEW_KERNEL" \
    --ramdisk unpacked/boot.img-ramdisk.gz \
    --cmdline "$CMDLINE" \
    --base "$(cat unpacked/boot.img-base)" \
    --pagesize "$(cat unpacked/boot.img-pagesize)" \
    --os_version "$(cat unpacked/boot.img-osversion)" \
    --os_patch_level "$(cat unpacked/boot.img-oslevel)" \
    $DTB_ARG \
    $EXTRA_ARGS \
    -o new_boot.img

echo "==> Success! Boot image created."

# Automatically copy it to the user's home folder and fix permissions
SUDO_USER_HOME=$(eval echo ~$SUDO_USER)
cp new_boot.img "$SUDO_USER_HOME/patched_boot.img"
chown $SUDO_USER:$SUDO_USER "$SUDO_USER_HOME/patched_boot.img"

echo "--------------------------------------------------------"
echo "A ready-to-flash copy has been saved to your home folder:"
echo "   $SUDO_USER_HOME/patched_boot.img"
echo "--------------------------------------------------------"
echo "Transfer this file to your PC and flash via Fastboot:"
echo "   fastboot flash boot_a patched_boot.img"
echo "   fastboot flash boot_b patched_boot.img"
echo "   fastboot reboot"