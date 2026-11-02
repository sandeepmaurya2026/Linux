#!/bin/bash

echo "=================================="
echo " Updating System"
echo "=================================="

sudo apt update

echo "=================================="
echo " Installing Required Packages"
echo "=================================="

sudo apt install -y \
    xrdp \
    wget \
    curl

echo "=================================="
echo " Enabling XRDP"
echo "=================================="

sudo systemctl enable xrdp
sudo systemctl restart xrdp

echo "=================================="
echo " Configuring"
echo "=================================="

# Enable VNC
sudo raspi-config nonint do_vnc 0

# Force X11 instead of Wayland
sudo raspi-config nonint do_wayland W1

echo "=================================="
echo " Configuring Virtual HDMI Display"
echo "=================================="

CMDLINE="/boot/firmware/cmdline.txt"

if ! grep -q "video=HDMI-A-1:1920x1080@60D" "$CMDLINE"; then
    sudo sed -i 's/quiet splash/quiet splash video=HDMI-A-1:1920x1080@60D/' "$CMDLINE"
fi

echo "=================================="
echo " Removing Existing RustDesk"
echo "=================================="
sudo apt purge rustdesk -y
sudo apt remove rustdesk -y
sudo rm -rf /root/.config/rustdesk
sudo rm -rf /home/admin/.config/rustdesk

echo "=================================="
echo " Installing Stable RustDesk"
echo "=================================="

cd /tmp || exit

wget -O rustdesk.deb \
https://github.com/rustdesk/rustdesk/releases/download/1.2.3-2/rustdesk-1.2.3-2-aarch64.deb

sudo apt install -y ./rustdesk.deb

echo "=================================="
echo " Enabling RustDesk"
echo "=================================="

sudo systemctl enable rustdesk
sudo systemctl restart rustdesk

sleep 5

echo "=================================="
echo " Setting RustDesk Password"
echo "=================================="

sudo rustdesk --password "Nep@12345"

echo "=================================="
echo " Installation Completed"
echo "=================================="

echo ""
echo "XRDP Status:"
systemctl is-active xrdp

echo ""
echo "RustDesk Status:"
systemctl is-active rustdesk

echo ""
echo "RustDesk ID:"
sudo rustdesk --get-id
