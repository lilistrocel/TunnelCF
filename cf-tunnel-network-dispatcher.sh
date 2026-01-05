#!/bin/bash
#
# NetworkManager Dispatcher Script for Cloudflare Tunnel
# Restarts the tunnel service when network connectivity changes
#
# Install location: /etc/NetworkManager/dispatcher.d/99-cf-tunnel
# Alternative: /etc/network/if-up.d/cf-tunnel (for systems without NetworkManager)
#

LOG_TAG="cf-tunnel-network"

log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [NETWORK] $1" | systemd-cat -t "$LOG_TAG" -p info
}

# NetworkManager passes interface as $1 and action as $2
INTERFACE="$1"
ACTION="$2"

# Only act on relevant network events
case "$ACTION" in
    up|dhcp4-change|dhcp6-change|connectivity-change)
        # Check if cf-tunnel service exists and is enabled
        if systemctl is-enabled cf-tunnel.service &>/dev/null; then
            log_event "Network event '$ACTION' on interface '$INTERFACE' - restarting cf-tunnel"

            # Give the network a moment to stabilize
            sleep 2

            # Restart the tunnel service
            systemctl restart cf-tunnel.service

            log_event "cf-tunnel restart triggered due to network change"
        fi
        ;;
    down)
        log_event "Network interface '$INTERFACE' went down - tunnel will reconnect when network returns"
        ;;
    *)
        # Ignore other events (pre-up, post-down, etc.)
        ;;
esac

exit 0
