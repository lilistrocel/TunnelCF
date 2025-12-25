#!/bin/bash
#
# Cloudflare Tunnel Auto-Provisioner for Raspberry Pi
# Automatically creates and manages SSH tunnels based on machine identity
#
# Author: A20Core
# Usage: Run as systemd service or manually: ./cf-tunnel-provisioner.sh
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

CONFIG_FILE="/etc/cf-tunnel/config.env"
STATE_DIR="/var/lib/cf-tunnel"
LOG_TAG="cf-tunnel"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE" | systemd-cat -t "$LOG_TAG" -p err
    exit 1
fi

source "$CONFIG_FILE"

# Validate required variables
REQUIRED_VARS=("CF_API_TOKEN" "CF_ACCOUNT_ID" "CF_ZONE_ID" "CF_DOMAIN")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Missing required variable: $var" | systemd-cat -t "$LOG_TAG" -p err
        exit 1
    fi
done

# Optional configuration with defaults
NODE_PREFIX="${NODE_PREFIX:-node}"
SSH_PORT="${SSH_PORT:-22}"
ADDITIONAL_SERVICES="${ADDITIONAL_SERVICES:-}"  # Format: "hostname1:service1,hostname2:service2"

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | systemd-cat -t "$LOG_TAG" -p info
    echo "[INFO] $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | systemd-cat -t "$LOG_TAG" -p err
    echo "[ERROR] $1" >&2
}

log_warn() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $1" | systemd-cat -t "$LOG_TAG" -p warning
    echo "[WARN] $1"
}

# ============================================================================
# Machine Identity
# ============================================================================

get_machine_id() {
    local machine_id=""
    
    # Try multiple sources for a stable machine ID
    if [[ -f "$STATE_DIR/machine-id" ]]; then
        # Use previously generated ID if exists
        machine_id=$(cat "$STATE_DIR/machine-id")
    elif [[ -f "/etc/machine-id" ]]; then
        # Use systemd machine-id (first 12 chars)
        machine_id=$(cat /etc/machine-id | cut -c1-12)
    elif command -v vcgencmd &> /dev/null; then
        # Raspberry Pi specific: use CPU serial
        machine_id=$(vcgencmd otp_dump | grep 28: | cut -d: -f2 | tr -d ' ' | tail -c 13)
    else
        # Fallback: generate from MAC address
        machine_id=$(ip link show | grep -m1 'link/ether' | awk '{print $2}' | tr -d ':' | cut -c1-12)
    fi
    
    # Persist the machine ID
    mkdir -p "$STATE_DIR"
    echo "$machine_id" > "$STATE_DIR/machine-id"
    
    echo "$machine_id"
}

# ============================================================================
# Cloudflare API Functions
# ============================================================================

cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local url="https://api.cloudflare.com/client/v4${endpoint}"
    local args=(-s -X "$method" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
    
    if [[ -n "$data" ]]; then
        args+=(--data "$data")
    fi
    
    curl "${args[@]}" "$url"
}

get_tunnel_by_name() {
    local tunnel_name="$1"
    local response
    
    response=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${tunnel_name}&is_deleted=false")
    echo "$response" | jq -r '.result[0].id // empty'
}

create_tunnel() {
    local tunnel_name="$1"
    local tunnel_secret
    
    # Generate a secure tunnel secret
    tunnel_secret=$(openssl rand -base64 32)
    
    local response
    response=$(cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
        "{\"name\":\"${tunnel_name}\",\"tunnel_secret\":\"${tunnel_secret}\",\"config_src\":\"cloudflare\"}")
    
    local success
    success=$(echo "$response" | jq -r '.success')
    
    if [[ "$success" != "true" ]]; then
        log_error "Failed to create tunnel: $(echo "$response" | jq -r '.errors')"
        return 1
    fi
    
    echo "$response" | jq -r '.result.id'
}

get_tunnel_token() {
    local tunnel_id="$1"
    local response
    
    response=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/token")
    echo "$response" | jq -r '.result // empty'
}

configure_tunnel() {
    local tunnel_id="$1"
    local hostname="$2"
    
    # Build ingress rules
    local ingress_rules="[{\"hostname\":\"${hostname}\",\"service\":\"ssh://localhost:${SSH_PORT}\"}"
    
    # Add additional services if configured
    if [[ -n "$ADDITIONAL_SERVICES" ]]; then
        IFS=',' read -ra SERVICES <<< "$ADDITIONAL_SERVICES"
        for service in "${SERVICES[@]}"; do
            local svc_hostname=$(echo "$service" | cut -d: -f1)
            local svc_target=$(echo "$service" | cut -d: -f2-)
            ingress_rules+=",{\"hostname\":\"${svc_hostname}\",\"service\":\"${svc_target}\"}"
        done
    fi
    
    # Add catch-all rule
    ingress_rules+=",{\"service\":\"http_status:404\"}]"
    
    local config="{\"config\":{\"ingress\":${ingress_rules}}}"
    
    local response
    response=$(cf_api PUT "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations" "$config")
    
    local success
    success=$(echo "$response" | jq -r '.success')
    
    if [[ "$success" != "true" ]]; then
        log_error "Failed to configure tunnel: $(echo "$response" | jq -r '.errors')"
        return 1
    fi
    
    return 0
}

create_dns_record() {
    local hostname="$1"
    local tunnel_id="$2"
    
    # Check if DNS record already exists
    local existing
    existing=$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?name=${hostname}&type=CNAME")
    local existing_id
    existing_id=$(echo "$existing" | jq -r '.result[0].id // empty')
    
    local record_data="{\"type\":\"CNAME\",\"name\":\"${hostname}\",\"content\":\"${tunnel_id}.cfargotunnel.com\",\"proxied\":true,\"ttl\":1}"
    
    if [[ -n "$existing_id" ]]; then
        log_info "Updating existing DNS record for ${hostname}"
        cf_api PUT "/zones/${CF_ZONE_ID}/dns_records/${existing_id}" "$record_data" > /dev/null
    else
        log_info "Creating DNS record for ${hostname}"
        cf_api POST "/zones/${CF_ZONE_ID}/dns_records" "$record_data" > /dev/null
    fi
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    log_info "Starting Cloudflare Tunnel Provisioner"
    
    # Ensure state directory exists
    mkdir -p "$STATE_DIR"
    
    # Get machine identity
    local machine_id
    machine_id=$(get_machine_id)
    log_info "Machine ID: ${machine_id}"
    
    # Construct tunnel name and hostname
    local tunnel_name="${NODE_PREFIX}-${machine_id}"
    local hostname="${tunnel_name}.${CF_DOMAIN}"
    
    log_info "Tunnel name: ${tunnel_name}"
    log_info "Hostname: ${hostname}"
    
    # Check if tunnel already exists
    local tunnel_id
    tunnel_id=$(get_tunnel_by_name "$tunnel_name")
    
    if [[ -z "$tunnel_id" ]]; then
        log_info "Tunnel does not exist, creating..."
        tunnel_id=$(create_tunnel "$tunnel_name")
        
        if [[ -z "$tunnel_id" ]]; then
            log_error "Failed to create tunnel"
            exit 1
        fi
        
        log_info "Tunnel created with ID: ${tunnel_id}"
        
        # Configure the tunnel
        log_info "Configuring tunnel ingress rules..."
        if ! configure_tunnel "$tunnel_id" "$hostname"; then
            log_error "Failed to configure tunnel"
            exit 1
        fi
        
        # Create DNS record
        log_info "Setting up DNS record..."
        create_dns_record "$hostname" "$tunnel_id"
    else
        log_info "Tunnel already exists with ID: ${tunnel_id}"
        
        # Update configuration in case it changed
        log_info "Updating tunnel configuration..."
        configure_tunnel "$tunnel_id" "$hostname" || true
    fi
    
    # Get tunnel token
    log_info "Retrieving tunnel token..."
    local token
    token=$(get_tunnel_token "$tunnel_id")
    
    if [[ -z "$token" ]]; then
        log_error "Failed to get tunnel token"
        exit 1
    fi
    
    # Save tunnel info for reference
    cat > "$STATE_DIR/tunnel-info.json" << EOF
{
    "tunnel_id": "${tunnel_id}",
    "tunnel_name": "${tunnel_name}",
    "hostname": "${hostname}",
    "machine_id": "${machine_id}",
    "created_at": "$(date -Iseconds)"
}
EOF
    
    log_info "Tunnel provisioned successfully!"
    log_info "SSH Access: cloudflared access ssh --hostname ${hostname}"
    log_info "Starting cloudflared..."
    
    # Run cloudflared (this blocks and keeps running)
    exec cloudflared tunnel run --token "$token"
}

# ============================================================================
# Signal Handling
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    exit 0
}

trap cleanup SIGTERM SIGINT

# Run main
main "$@"
