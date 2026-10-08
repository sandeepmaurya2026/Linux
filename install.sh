#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Helper Functions & Constants
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root. Run with 'sudo'."
   exit 1
fi

wait_for_apt_lock() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        log_warn "APT is locked by another process. Waiting 5s..."
        sleep 5
    done
}

# Check health of existing installation
check_health() {
    log_info "Checking health of existing installation..."
    
    local rustdesk_installed=0
    local xrdp_installed=0

    dpkg -s rustdesk >/dev/null 2>&1 && rustdesk_installed=1
    dpkg -s xrdp >/dev/null 2>&1 && xrdp_installed=1

    # Not installed
    if [[ $rustdesk_installed -eq 0 && $xrdp_installed -eq 0 ]]; then
        return 2
    fi

    # Check active status and valid ID
    local rustdesk_active=0
    local xrdp_active=0

    systemctl is-active --quiet rustdesk && rustdesk_active=1
    systemctl is-active --quiet xrdp && xrdp_active=1

    local rustdesk_id
    rustdesk_id=$(rustdesk --get-id 2>/dev/null || true)

    if [[ $rustdesk_installed -eq 1 && $xrdp_installed -eq 1 && $rustdesk_active -eq 1 && $xrdp_active -eq 1 && -n "$rustdesk_id" ]]; then
        return 0 # Healthy
    fi

    return 1 # Installed but Errored/Incomplete
}

# Deep cleanup function
purge_all() {
    log_warn "Performing deep cleanup of broken/existing installations..."
    
    systemctl stop rustdesk xrdp 2>/dev/null || true
    systemctl disable rustdesk xrdp 2>/dev/null || true

    wait_for_apt_lock
    apt-get purge -y rustdesk xrdp 2>/dev/null || true
    apt-get autoremove --purge -y

    # Clean legacy directories
    rm -rf /root/.config/rustdesk /etc/xrdp /var/log/xrdp
    for home_dir in /home/*; do
        if [[ -d "$home_dir/.config/rustdesk" ]]; then
            rm -rf "$home_dir/.config/rustdesk"
        fi
    done
    log_info "Cleanup completed successfully."
}

# ==============================================================================
# Health Check Evaluation
# ==============================================================================
HEALTH_STATUS=0
check_health || HEALTH_STATUS=$?

if [[ $HEALTH_STATUS -eq 0 && "${1:-}" != "--force" ]]; then
    log_info "System is already correctly installed and running!"
    echo "RustDesk ID: $(rustdesk --get-id 2>/dev/null)"
    log_warn "To force a complete reinstall anyway, run: sudo ./setup_remote.sh --force"
    exit 0
elif [[ $HEALTH_STATUS -eq 1 || "${1:-}" == "--force" ]]; then
    log_warn "Detected broken, incomplete, or forced state. Resetting environment..."
    purge_all
else
    log_info "Clean environment detected. Proceeding with fresh installation."
fi

# ==============================================================================
# Installation Process
# ==============================================================================
log_info "Updating package repos..."
wait_for_apt_lock
apt-get update -y

log_info "Installing dependencies..."
wait_for_apt_lock
apt-get install -y xrdp wget curl psmisc

if command -v raspi-config >/dev/null 2>&1; then
    log_info "Setting up Raspberry Pi hardware parameters..."
    raspi-config nonint do_vnc 0 || log_warn "VNC parameter skipped."
    raspi-config nonint do_wayland W1 || log_warn "Wayland parameter skipped."
fi

CMDLINE_PATH=""
if [[ -f "/boot/firmware/cmdline.txt" ]]; then
    CMDLINE_PATH="/boot/firmware/cmdline.txt"
elif [[ -f "/boot/cmdline.txt" ]]; then
    CMDLINE_PATH="/boot/cmdline.txt"
fi

if [[ -n "$CMDLINE_PATH" ]]; then
    PARAM="video=HDMI-A-1:1920x1080@60D"
    if ! grep -q "$PARAM" "$CMDLINE_PATH"; then
        log_info "Injecting Virtual HDMI resolution..."
        sed -i "1s/$/ $PARAM/" "$CMDLINE_PATH"
    fi
fi

log_info "Configuring XRDP..."
systemctl enable xrdp
systemctl restart xrdp

log_info "Downloading RustDesk..."
TEMP_DEB="/tmp/rustdesk.deb"
RUSTDESK_URL="https://github.com/rustdesk/rustdesk/releases/download/1.2.3-2/rustdesk-1.2.3-2-aarch64.deb"

rm -f "$TEMP_DEB"
wget --tries=3 --timeout=15 -O "$TEMP_DEB" "$RUSTDESK_URL"

if [[ ! -s "$TEMP_DEB" ]]; then
    log_error "Failed to download RustDesk installer package."
    exit 1
fi

log_info "Installing RustDesk package..."
wait_for_apt_lock
apt-get install -y "$TEMP_DEB"
rm -f "$TEMP_DEB"

log_info "Starting RustDesk daemon..."
systemctl enable rustdesk
systemctl restart rustdesk

for i in {1..15}; do
    if systemctl is-active --quiet rustdesk; then
        break
    fi
    sleep 1
done

sleep 2
rustdesk --password "Nep@12345" || log_warn "Set password completed with non-fatal warning."

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "=================================================="
echo "               INSTALLATION SUMMARY               "
echo "=================================================="
echo "XRDP Status:     $(systemctl is-active xrdp || echo 'inactive')"
echo "RustDesk Status: $(systemctl is-active rustdesk || echo 'inactive')"
echo "RustDesk ID:     $(rustdesk --get-id 2>/dev/null || echo 'Not initialized')"
echo "=================================================="
log_info "Done! Please reboot the device to apply system display modifications."