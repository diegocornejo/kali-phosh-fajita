#!/bin/bash

# Ensure the script is run as root before doing anything
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Run it with sudo."
  exit 1
fi

# Step 0: Read and validate the slot parameter
SLOT=$1

if [[ "$SLOT" != "a" && "$SLOT" != "b" ]]; then
  echo "Error: You must specify a slot (a or b)."
  echo "Usage: $0 [a|b]"
  echo "Example: $0 b"
  exit 1
fi

TARGET_PART="/dev/disk/by-partlabel/boot_${SLOT}"

if [ ! -e "$TARGET_PART" ]; then
  echo "Error: Partition $TARGET_PART does not exist."
  exit 1
fi

echo "========================================"
echo "Targeting Boot Partition: $TARGET_PART"
echo "========================================"

# Step 1: Create a temporary directory and copy the DTB file
mkdir -p /tmp
cp /lib/linux-image-$(uname -r)/qcom/sdm845-oneplus-fajita.dtb /tmp/

# Step 2: Install the device tree compiler
apt install -y device-tree-compiler

# Step 3: Convert the DTB file to DTS format
dtc -o /tmp/a.dts /tmp/sdm845-oneplus-fajita.dtb

# Step 4: Modify the USB driver mode from 'peripheral' to 'host'
sed -i 's/dr_mode = "peripheral"/dr_mode = "host"/g' /tmp/a.dts

# Step 5: Remove the original DTB file
rm /tmp/sdm845-oneplus-fajita.dtb

# Step 6: Convert the modified DTS back to DTB format
dtc -o /tmp/host.dtb /tmp/a.dts

# Step 7: Remove the temporary DTS file
rm /tmp/a.dts

# Step 8: Combine the kernel with the new DTB file
cat /boot/vmlinuz-$(uname -r) /tmp/host.dtb > /tmp/kernel-dtb

# Step 9: Remove the temporary DTB file
rm /tmp/host.dtb

# Step 10: Extract the active boot partition to a file
echo "Extracting current boot image from $TARGET_PART..."
dd if="$TARGET_PART" of=/tmp/boot.img

# Step 11: Install abootimg for editing boot images
apt install -y abootimg

# Step 12: Update the boot.img with the new kernel-dtb
abootimg -u /tmp/boot.img -k /tmp/kernel-dtb

# Step 13: Remove the temporary kernel-dtb file
rm /tmp/kernel-dtb

# Step 14: Rename the updated boot image
mv /tmp/boot.img /tmp/host_boot.img

# Step 15: Write the new boot image back to the target boot partition
echo "Writing patched boot image to $TARGET_PART..."
dd if=/tmp/host_boot.img of="$TARGET_PART"

# Step 16: Sync to ensure all changes are written to disk
sync

echo "Success! The DTB has been patched for Host mode on Slot $SLOT."

# Step 17: Reboot the system
echo "Rebooting in 3 seconds..."
sleep 3
reboot
