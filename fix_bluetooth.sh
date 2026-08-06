#!/bin/bash

# Ensure the script is run as root before doing anything
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Run it with sudo."
  exit 1
fi


cp /lib/firmware/updates/qca/oneplus6/crnv21.bin /lib/firmware/qca/
systemctl start bluetooth
systemctl enable bluetooth
echo "Bluetooth enabled"
