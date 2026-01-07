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
# Logging Functions (Enhanced)
# ============================================================================

LOG_FILE="/var/lib/cf-tunnel/tunnel.log"
MAX_LOG_SIZE=5242880  # 5MB

rotate_log() {
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

log_info() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
    echo "$msg" | systemd-cat -t "$LOG_TAG" -p info
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "[INFO] $1"
}

log_error() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1"
    echo "$msg" | systemd-cat -t "$LOG_TAG" -p err
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "[ERROR] $1" >&2
}

log_warn() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [WARN] $1"
    echo "$msg" | systemd-cat -t "$LOG_TAG" -p warning
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "[WARN] $1"
}

log_debug() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $1"
    echo "$msg" | systemd-cat -t "$LOG_TAG" -p debug
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_network_status() {
    log_debug "=== Network Status ==="
    log_debug "Default route: $(ip route show default 2>/dev/null | head -1 || echo 'none')"
    log_debug "DNS resolvers: $(grep nameserver /etc/resolv.conf 2>/dev/null | head -2 | tr '\n' ' ' || echo 'none')"
    log_debug "External IP: $(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo 'unknown')"
    log_debug "===================="
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

    # Store secret for credentials file (needed for local config)
    echo "$tunnel_secret" > "$STATE_DIR/tunnel-secret.tmp"

    local response
    # Note: Do NOT set config_src - leaving it unset defaults to "local" config mode
    # This is required for cloudflared access ssh/tcp commands to work
    response=$(cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
        "{\"name\":\"${tunnel_name}\",\"tunnel_secret\":\"${tunnel_secret}\"}")

    local success
    success=$(echo "$response" | jq -r '.success')

    if [[ "$success" != "true" ]]; then
        log_error "Failed to create tunnel: $(echo "$response" | jq -r '.errors')"
        rm -f "$STATE_DIR/tunnel-secret.tmp"
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

# Create local credentials file for tunnel (required for local config mode)
create_credentials_file() {
    local tunnel_id="$1"
    local tunnel_secret="$2"
    local creds_file="/etc/cloudflared/${tunnel_id}.json"

    # Log to stderr so it doesn't get captured in command substitution
    log_info "Creating credentials file: $creds_file" >&2

    mkdir -p /etc/cloudflared

    cat > "$creds_file" << EOF
{
  "AccountTag": "${CF_ACCOUNT_ID}",
  "TunnelID": "${tunnel_id}",
  "TunnelSecret": "${tunnel_secret}"
}
EOF

    chmod 600 "$creds_file"
    log_info "Credentials file created successfully" >&2

    # Only output the path to stdout (for capture)
    echo "$creds_file"
}

# Create local config.yml file for tunnel (required for local config mode)
create_config_file() {
    local tunnel_id="$1"
    local hostname="$2"
    local creds_file="$3"
    local config_file="/etc/cloudflared/config.yml"

    log_info "Creating config file: $config_file"

    # Start config file
    cat > "$config_file" << EOF
tunnel: ${tunnel_id}
credentials-file: ${creds_file}

ingress:
  - hostname: ${hostname}
    service: ssh://localhost:${SSH_PORT}
EOF

    # Add additional services if configured
    if [[ -n "$ADDITIONAL_SERVICES" ]]; then
        IFS=',' read -ra SERVICES <<< "$ADDITIONAL_SERVICES"
        for service in "${SERVICES[@]}"; do
            local svc_hostname=$(echo "$service" | cut -d: -f1)
            local svc_target=$(echo "$service" | cut -d: -f2-)
            cat >> "$config_file" << EOF
  - hostname: ${svc_hostname}
    service: ${svc_target}
EOF
        done
    fi

    # Add catch-all rule
    cat >> "$config_file" << EOF
  - service: http_status:404
EOF

    chmod 644 "$config_file"
    log_info "Config file created successfully"
}

# Get existing tunnel secret from token (for existing tunnels)
get_tunnel_secret_from_token() {
    local tunnel_id="$1"
    local token

    token=$(get_tunnel_token "$tunnel_id")
    if [[ -z "$token" ]]; then
        return 1
    fi

    # Token is base64 encoded JSON with {a: accountId, t: tunnelId, s: secret}
    echo "$token" | base64 -d 2>/dev/null | jq -r '.s // empty'
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
# Network Connectivity & Health Check Functions
# ============================================================================

HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"  # seconds
CONNECTIVITY_TIMEOUT="${CONNECTIVITY_TIMEOUT:-10}"     # seconds
MAX_RECONNECT_ATTEMPTS="${MAX_RECONNECT_ATTEMPTS:-5}"

# Check if we have basic internet connectivity
check_internet_connectivity() {
    local endpoints=(
        "https://cloudflare.com/cdn-cgi/trace"
        "https://1.1.1.1/cdn-cgi/trace"
        "https://api.cloudflare.com"
    )

    for endpoint in "${endpoints[@]}"; do
        if curl -sf --max-time "$CONNECTIVITY_TIMEOUT" "$endpoint" > /dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Check if Cloudflare Tunnel infrastructure is reachable
check_cloudflare_tunnel_connectivity() {
    # Check if we can reach Cloudflare's tunnel endpoints
    if curl -sf --max-time "$CONNECTIVITY_TIMEOUT" "https://region1.argotunnel.com" > /dev/null 2>&1; then
        return 0
    fi

    # Fallback check
    if curl -sf --max-time "$CONNECTIVITY_TIMEOUT" "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Wait for network connectivity with retries
wait_for_network() {
    local max_attempts=60
    local attempt=1
    local wait_time=5

    log_info "Waiting for network connectivity..."

    while [[ $attempt -le $max_attempts ]]; do
        if check_internet_connectivity; then
            log_info "Network connectivity established (attempt $attempt)"
            log_network_status
            return 0
        fi

        log_warn "No network connectivity (attempt $attempt/$max_attempts), waiting ${wait_time}s..."
        sleep $wait_time
        ((attempt++))
    done

    log_error "Failed to establish network connectivity after $max_attempts attempts"
    return 1
}

# Monitor cloudflared process and restart if needed
run_with_health_monitoring() {
    local tunnel_id="$1"
    local reconnect_attempts=0
    local cloudflared_pid=""

    while true; do
        # Pre-flight connectivity check
        if ! check_cloudflare_tunnel_connectivity; then
            log_warn "Cloudflare tunnel infrastructure not reachable, waiting for connectivity..."
            if ! wait_for_network; then
                log_error "Cannot establish connectivity, will retry in 30s"
                sleep 30
                continue
            fi
        fi

        log_info "Starting cloudflared daemon (attempt $((reconnect_attempts + 1)))"

        # Record the start time and current IP for debugging
        local start_time=$(date '+%Y-%m-%d %H:%M:%S')
        local start_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
        log_debug "Tunnel starting at $start_time from IP: $start_ip"

        # Start cloudflared with LOCAL config (not token-based)
        # This uses /etc/cloudflared/config.yml and credentials file
        cloudflared tunnel run "$tunnel_id" &
        cloudflared_pid=$!

        log_info "cloudflared started with PID: $cloudflared_pid"

        # Save PID for external monitoring
        echo "$cloudflared_pid" > "$STATE_DIR/cloudflared.pid"

        # Monitor the process
        local health_check_counter=0
        while kill -0 "$cloudflared_pid" 2>/dev/null; do
            sleep "$HEALTH_CHECK_INTERVAL"
            health_check_counter=$((health_check_counter + 1))

            # Periodic health logging (every 10 checks = ~5 minutes with default interval)
            if [[ $((health_check_counter % 10)) -eq 0 ]]; then
                local current_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
                local uptime_mins=$((health_check_counter * HEALTH_CHECK_INTERVAL / 60))
                log_debug "Health check: tunnel running for ${uptime_mins}m, IP: $current_ip"

                # Check if IP changed
                if [[ "$current_ip" != "$start_ip" ]] && [[ "$current_ip" != "unknown" ]] && [[ "$start_ip" != "unknown" ]]; then
                    log_warn "IP address changed from $start_ip to $current_ip"
                    start_ip="$current_ip"
                fi
            fi

            # Check if we still have connectivity (every 2 checks)
            if [[ $((health_check_counter % 2)) -eq 0 ]]; then
                if ! check_internet_connectivity; then
                    log_warn "Lost internet connectivity, cloudflared may disconnect soon"
                fi
            fi
        done

        # Process exited - determine why
        wait "$cloudflared_pid"
        local exit_code=$?

        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        local end_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")

        log_warn "cloudflared exited with code $exit_code at $end_time"
        log_debug "Exit details: started=$start_time, ended=$end_time, start_ip=$start_ip, end_ip=$end_ip"
        log_network_status

        rm -f "$STATE_DIR/cloudflared.pid"

        # Check if this was a clean shutdown (SIGTERM/SIGINT)
        if [[ $exit_code -eq 143 ]] || [[ $exit_code -eq 130 ]]; then
            log_info "cloudflared received shutdown signal, exiting health monitor"
            return 0
        fi

        reconnect_attempts=$((reconnect_attempts + 1))

        if [[ $reconnect_attempts -ge $MAX_RECONNECT_ATTEMPTS ]]; then
            log_error "Max reconnection attempts ($MAX_RECONNECT_ATTEMPTS) reached, exiting for systemd restart"
            return 1
        fi

        # Exponential backoff: 5s, 10s, 20s, 40s, 60s (capped)
        local backoff=$((5 * (2 ** (reconnect_attempts - 1))))
        [[ $backoff -gt 60 ]] && backoff=60

        log_warn "Will attempt reconnection in ${backoff}s (attempt $reconnect_attempts/$MAX_RECONNECT_ATTEMPTS)"
        sleep $backoff

        # Wait for network before retrying
        wait_for_network || true
    done
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    log_info "Starting Cloudflare Tunnel Provisioner"
    rotate_log

    # Ensure state directory exists
    mkdir -p "$STATE_DIR"

    # Wait for network before proceeding
    log_info "Checking network connectivity..."
    if ! wait_for_network; then
        log_error "No network connectivity available, cannot proceed"
        exit 1
    fi

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
    local tunnel_secret=""
    local is_new_tunnel=false

    tunnel_id=$(get_tunnel_by_name "$tunnel_name")

    if [[ -z "$tunnel_id" ]]; then
        log_info "Tunnel does not exist, creating..."
        is_new_tunnel=true
        tunnel_id=$(create_tunnel "$tunnel_name")

        if [[ -z "$tunnel_id" ]]; then
            log_error "Failed to create tunnel"
            exit 1
        fi

        log_info "Tunnel created with ID: ${tunnel_id}"

        # Get the secret we stored during creation
        if [[ -f "$STATE_DIR/tunnel-secret.tmp" ]]; then
            tunnel_secret=$(cat "$STATE_DIR/tunnel-secret.tmp")
            rm -f "$STATE_DIR/tunnel-secret.tmp"
        fi

        # Create DNS record
        log_info "Setting up DNS record..."
        create_dns_record "$hostname" "$tunnel_id"
    else
        log_info "Tunnel already exists with ID: ${tunnel_id}"

        # Get tunnel secret from API token (for existing tunnels)
        log_info "Retrieving tunnel credentials..."
        tunnel_secret=$(get_tunnel_secret_from_token "$tunnel_id")

        if [[ -z "$tunnel_secret" ]]; then
            log_error "Failed to get tunnel secret - tunnel may need to be recreated"
            exit 1
        fi
    fi

    # Create local credentials file
    log_info "Setting up local credentials..."
    local creds_file
    creds_file=$(create_credentials_file "$tunnel_id" "$tunnel_secret")

    # Create local config.yml file
    log_info "Creating local config file..."
    create_config_file "$tunnel_id" "$hostname" "$creds_file"

    # Save tunnel info for reference
    cat > "$STATE_DIR/tunnel-info.json" << EOF
{
    "tunnel_id": "${tunnel_id}",
    "tunnel_name": "${tunnel_name}",
    "hostname": "${hostname}",
    "machine_id": "${machine_id}",
    "config_mode": "local",
    "credentials_file": "${creds_file}",
    "created_at": "$(date -Iseconds)"
}
EOF

    log_info "Tunnel provisioned successfully!"
    log_info "SSH Access: cloudflared access tcp --hostname ${hostname} --url localhost:2222"
    log_info "Then: ssh -p 2222 user@localhost"
    log_info "Starting cloudflared with health monitoring..."

    # Run cloudflared with health monitoring using local config (not token)
    run_with_health_monitoring "$tunnel_id"
}

# ============================================================================
# Signal Handling
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."

    # Kill cloudflared if running
    if [[ -f "$STATE_DIR/cloudflared.pid" ]]; then
        local pid=$(cat "$STATE_DIR/cloudflared.pid")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping cloudflared (PID: $pid)..."
            kill -TERM "$pid" 2>/dev/null || true
            # Wait up to 10 seconds for graceful shutdown
            for i in {1..10}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "cloudflared did not stop gracefully, force killing..."
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$STATE_DIR/cloudflared.pid"
    fi

    log_info "Cleanup complete"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# Run main
main "$@"
