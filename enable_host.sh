# Step 1: Create a temporary directory and copy the DTB file
mkdir -p /tmp
cp /lib/linux-image-$(uname -r)/qcom/sdm845-oneplus-fajita.dtb  /tmp/

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

# Step 10: Check if sudo privileges are active and set a root password if needed
if ! sudo -v; then
    echo "Set a root password via: sudo passwd root"
    exit 1
fi

# Step 11: Create a copy of the boot partition
# Make sure the partition path is correct for your device
dd if=/dev/disk/by-partlabel/boot_b of=/tmp/boot.img

# Step 12: Install abootimg for editing boot images
apt install -y abootimg

# Step 13: Update the boot.img with the new kernel-dtb
abootimg -u /tmp/boot.img -k /tmp/kernel-dtb

# Step 14: Remove the temporary kernel-dtb file
rm /tmp/kernel-dtb

# Step 15: Rename the updated boot image
mv /tmp/boot.img /tmp/host_boot.img

# Step 16: Write the new boot image back to the boot partition
# Make sure the partition path is correct before running this!
dd if=/tmp/host_boot.img of=/dev/disk/by-partlabel/boot_b

# Step 17: Sync to ensure all changes are written to disk
sync

# Step 18: Reboot the system
reboot
