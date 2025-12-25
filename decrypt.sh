#!/bin/bash
#
# Decrypt config.env.age to /etc/cf-tunnel/config.env
# Requires: age installed, private key available
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCRYPTED_FILE="${SCRIPT_DIR}/config.env.age"
OUTPUT_FILE="/etc/cf-tunnel/config.env"

# Key locations to search (in order)
KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "${HOME}/.age/key.txt"
    "${HOME}/.config/age/key.txt"
    "/etc/cf-tunnel/age-key.txt"
    "${SCRIPT_DIR}/.age-key.txt"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if age is installed
if ! command -v age &> /dev/null; then
    log_error "age is not installed"
    echo ""
    echo "Install with:"
    echo "  Ubuntu/Debian: sudo apt install age"
    echo "  macOS: brew install age"
    exit 1
fi

# Check encrypted file exists
if [[ ! -f "$ENCRYPTED_FILE" ]]; then
    log_error "Encrypted config not found: $ENCRYPTED_FILE"
    echo ""
    echo "Make sure config.env.age exists in the same directory as this script."
    echo "Or create it with: age -R .age-recipients -o config.env.age config.env"
    exit 1
fi

# Find the age key
AGE_KEY=""
for key_path in "${KEY_LOCATIONS[@]}"; do
    if [[ -n "$key_path" && -f "$key_path" ]]; then
        AGE_KEY="$key_path"
        break
    fi
done

if [[ -z "$AGE_KEY" ]]; then
    log_error "No age private key found!"
    echo ""
    echo "Searched locations:"
    for loc in "${KEY_LOCATIONS[@]}"; do
        [[ -n "$loc" ]] && echo "  - $loc"
    done
    echo ""
    echo "Either:"
    echo "  1. Copy your key to one of the above locations"
    echo "  2. Set AGE_KEY_FILE environment variable"
    echo ""
    echo "Generate a new key with: age-keygen -o ~/.age/key.txt"
    exit 1
fi

log_info "Using key: $AGE_KEY"

# Create output directory if needed
sudo mkdir -p "$(dirname "$OUTPUT_FILE")"

# Decrypt
log_info "Decrypting $ENCRYPTED_FILE..."

DECRYPT_ERROR=$(sudo age -d -i "$AGE_KEY" -o "$OUTPUT_FILE" "$ENCRYPTED_FILE" 2>&1)
if [[ $? -eq 0 ]]; then
    sudo chmod 600 "$OUTPUT_FILE"
    log_info "Successfully decrypted to $OUTPUT_FILE"
else
    log_error "Decryption failed!"
    echo ""
    if [[ -n "$DECRYPT_ERROR" ]]; then
        echo "age error: $DECRYPT_ERROR"
        echo ""
    fi
    echo "Possible causes:"
    echo "  - Wrong private key (doesn't match public key used to encrypt)"
    echo "  - Corrupted encrypted file"
    echo "  - File was encrypted for different recipient"
    exit 1
fi

# Validate the decrypted file has expected variables
REQUIRED_VARS=("CF_API_TOKEN" "CF_ACCOUNT_ID" "CF_ZONE_ID" "CF_DOMAIN")
MISSING=()

for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" "$OUTPUT_FILE" 2>/dev/null; then
        MISSING+=("$var")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log_warn "Config may be incomplete. Missing variables:"
    for var in "${MISSING[@]}"; do
        echo "  - $var"
    done
fi

log_info "Done! You can now start/restart the cf-tunnel service."
