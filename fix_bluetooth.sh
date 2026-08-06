cp /lib/firmware/updates/qca/oneplus6/crnv21.bin /lib/firmware/qca/
systemctl start bluetooth
systemctl enable bluetooth
echo "Bluetooth enabled"
