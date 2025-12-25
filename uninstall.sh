#!/bin/bash
#
# Cloudflare Tunnel Service Uninstaller
# Run with: sudo ./uninstall.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

echo ""
log_warn "This will remove the Cloudflare Tunnel service from this system."
echo ""
read -p "Continue? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Stop and disable service
log_info "Stopping and disabling service..."
systemctl stop cf-tunnel.service 2>/dev/null || true
systemctl disable cf-tunnel.service 2>/dev/null || true

# Remove systemd service file
log_info "Removing systemd service..."
rm -f /etc/systemd/system/cf-tunnel.service
systemctl daemon-reload

# Remove provisioner script
log_info "Removing provisioner script..."
rm -f /usr/local/bin/cf-tunnel-provisioner.sh

# Ask about configuration
echo ""
read -p "Remove configuration files? (y/n): " REMOVE_CONFIG
if [[ "$REMOVE_CONFIG" =~ ^[Yy]$ ]]; then
    rm -rf /etc/cf-tunnel
    log_info "Configuration removed"
else
    log_info "Configuration preserved at /etc/cf-tunnel/"
fi

# Ask about state
read -p "Remove state files (tunnel info)? (y/n): " REMOVE_STATE
if [[ "$REMOVE_STATE" =~ ^[Yy]$ ]]; then
    rm -rf /var/lib/cf-tunnel
    log_info "State files removed"
else
    log_info "State files preserved at /var/lib/cf-tunnel/"
fi

# Ask about cloudflared binary
echo ""
read -p "Remove cloudflared binary? (y/n): " REMOVE_CLOUDFLARED
if [[ "$REMOVE_CLOUDFLARED" =~ ^[Yy]$ ]]; then
    rm -f /usr/local/bin/cloudflared
    log_info "cloudflared removed"
else
    log_info "cloudflared binary preserved"
fi

echo ""
log_info "Uninstallation complete!"
echo ""
log_warn "Note: The tunnel and DNS records still exist in Cloudflare."
echo "To fully remove them, delete the tunnel from the Cloudflare Dashboard:"
echo "  Zero Trust > Networks > Tunnels"
echo ""
