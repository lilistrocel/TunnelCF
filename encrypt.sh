#!/bin/bash
#
# Encrypt config.env using age
# Run this before committing to git
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-${SCRIPT_DIR}/config.env}"
OUTPUT_FILE="${SCRIPT_DIR}/config.env.age"
RECIPIENTS_FILE="${SCRIPT_DIR}/.age-recipients"

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

# Check input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    log_error "Input file not found: $INPUT_FILE"
    echo ""
    echo "Usage: $0 [path-to-config.env]"
    echo ""
    echo "Make sure your config.env exists, or specify the path."
    exit 1
fi

# Determine encryption method
if [[ -f "$RECIPIENTS_FILE" ]]; then
    # Use recipients file (for team use)
    RECIPIENT_COUNT=$(grep -v '^#' "$RECIPIENTS_FILE" | grep -v '^$' | wc -l)
    log_info "Using recipients file with $RECIPIENT_COUNT recipient(s)"
    
    age -R "$RECIPIENTS_FILE" -o "$OUTPUT_FILE" "$INPUT_FILE"
    
elif [[ -f "${HOME}/.age/key.txt" ]]; then
    # Use personal key
    log_info "Using personal key from ~/.age/key.txt"
    
    PUBLIC_KEY=$(grep "public key:" "${HOME}/.age/key.txt" | cut -d: -f2 | tr -d ' ')
    age -r "$PUBLIC_KEY" -o "$OUTPUT_FILE" "$INPUT_FILE"
    
else
    log_error "No encryption key found!"
    echo ""
    echo "Either:"
    echo "  1. Create .age-recipients file with public keys"
    echo "  2. Generate a personal key: age-keygen -o ~/.age/key.txt"
    echo ""
    echo "Example .age-recipients file:"
    echo "  # My laptop"
    echo "  age1abc123..."
    echo "  # Deploy server"
    echo "  age1xyz789..."
    exit 1
fi

log_info "Encrypted: $INPUT_FILE -> $OUTPUT_FILE"

# Verify the encryption
if file "$OUTPUT_FILE" | grep -q "ASCII text"; then
    log_error "WARNING: Output file appears to be plaintext!"
    exit 1
fi

# Show git status hint
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo ""
    log_info "Ready to commit:"
    echo "  git add config.env.age"
    echo "  git commit -m 'Update encrypted config'"
fi

# Remind about .gitignore
if git rev-parse --git-dir > /dev/null 2>&1; then
    if ! grep -q "^config\.env$" .gitignore 2>/dev/null; then
        log_warn "Make sure config.env is in .gitignore!"
    fi
fi
