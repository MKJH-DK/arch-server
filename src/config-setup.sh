#!/bin/bash
# ============================================================================
# ARCH SERVER v5.1 - CONFIGURATION SETUP
# Interactive setup for basic/advanced configuration
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

# Files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASIC_CONFIG="$SCRIPT_DIR/config.env.basic"
ADVANCED_CONFIG="$SCRIPT_DIR/config.env.advanced"
FINAL_CONFIG="$SCRIPT_DIR/config.env"

log() { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${CYAN}ℹ${NC} $1"; }

# Check if files exist
if [[ ! -f "$BASIC_CONFIG" ]]; then
    error "config.env.basic not found!"
fi

if [[ ! -f "$ADVANCED_CONFIG" ]]; then
    error "config.env.advanced not found!"
fi

echo
echo -e "${BOLD}🏗️  ARCH SERVER v5.1 - CONFIGURATION SETUP${NC}"
echo "=============================================="
echo
info "This tool helps you set up your configuration."
echo
info "Choose your configuration level:"
echo "  1) ${BOLD}Basic${NC} - Essential settings only (recommended for new users)"
echo "  2) ${BOLD}Advanced${NC} - Full configuration with all options"
echo "  3) ${BOLD}Custom${NC} - Start with basic and add advanced options"
echo

read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        log "Setting up basic configuration..."
        cp "$BASIC_CONFIG" "$FINAL_CONFIG"
        success "Basic configuration created at $FINAL_CONFIG"
        echo
        info "Next steps:"
        echo "  1. Edit $FINAL_CONFIG with your basic settings"
        echo "  2. Run: chmod +x src/install.sh && ./src/install.sh"
        ;;

    2)
        log "Setting up advanced configuration..."
        cp "$ADVANCED_CONFIG" "$FINAL_CONFIG"
        success "Advanced configuration created at $FINAL_CONFIG"
        echo
        warning "Advanced config has many options - review carefully!"
        echo
        info "Next steps:"
        echo "  1. Edit $FINAL_CONFIG with your settings"
        echo "  2. Run: chmod +x src/install.sh && ./src/install.sh"
        ;;

    3)
        log "Setting up custom configuration..."
        cp "$BASIC_CONFIG" "$FINAL_CONFIG"

        echo
        info "Basic configuration created. Adding advanced sections..."
        echo

        # Add advanced sections with comments
        {
            echo
            echo "# ============================================================================"
            echo "# ADVANCED OPTIONS (added by config-setup.sh)"
            echo "# Uncomment and configure as needed"
            echo "# ============================================================================"
            echo
            grep -E "^#( INSTALLATION MODE|KERNEL|TPM|BTRFS|SNAPSHOTS|ANSIBLE|CONTAINER|WEB SERVER|SECURITY|MONITORING|HARDENING|POST-INSTALL|BACKUP)" "$ADVANCED_CONFIG" | head -20
            echo "# ... (see config.env.advanced for all advanced options)"
        } >> "$FINAL_CONFIG"

        success "Custom configuration created at $FINAL_CONFIG"
        echo
        info "Next steps:"
        echo "  1. Edit $FINAL_CONFIG - basic settings are active"
        echo "  2. Uncomment advanced options as needed"
        echo "  3. Run: chmod +x src/install.sh && ./src/install.sh"
        ;;

    *)
        error "Invalid choice. Please run again and choose 1, 2, or 3."
        ;;
esac

echo
echo -e "${BOLD}Configuration files:${NC}"
echo "  Basic:    $BASIC_CONFIG"
echo "  Advanced: $ADVANCED_CONFIG"
echo "  Final:    $FINAL_CONFIG"
echo
info "Remember to review and customize your configuration before installing!"