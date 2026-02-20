#!/bin/bash
# ============================================================================
# ARCH SERVER v5.1 - CONFIGURATION VALIDATOR
# Validates config.env before installation
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

# Files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# Validation results
ERRORS=0
WARNINGS=0

log() { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; ((ERRORS++)); }
info() { echo -e "${CYAN}ℹ${NC} $1"; }

# Load configuration if it exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Configuration file not found: $CONFIG_FILE"
    error "Run ./config-setup.sh first to create configuration"
    exit 1
fi

# Source the config file safely
set +u  # Temporarily disable strict mode for sourcing
source "$CONFIG_FILE"
set -u  # Re-enable strict mode

echo
echo -e "${BOLD}🔍 ARCH SERVER v5.1 - CONFIGURATION VALIDATION${NC}"
echo "=================================================="
echo

# ============================================================================
# REQUIRED SETTINGS VALIDATION
# ============================================================================

log "Checking required settings..."

# Hostname validation
if [[ -z "${HOSTNAME:-}" ]]; then
    error "HOSTNAME is required but not set"
elif [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] || [[ ${#HOSTNAME} -gt 63 ]]; then
    error "HOSTNAME '$HOSTNAME' is not a valid hostname"
else
    success "HOSTNAME: $HOSTNAME"
fi

# Username validation
if [[ -z "${USERNAME:-}" ]]; then
    error "USERNAME is required but not set"
elif [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || [[ ${#USERNAME} -lt 2 ]]; then
    error "USERNAME '$USERNAME' contains invalid characters or is too short"
else
    success "USERNAME: $USERNAME"
fi

# Timezone validation
if [[ -z "${TIMEZONE:-}" ]]; then
    error "TIMEZONE is required but not set"
elif ! timedatectl list-timezones 2>/dev/null | grep -q "^${TIMEZONE}$"; then
    warning "TIMEZONE '$TIMEZONE' may not be valid (cannot verify on this system)"
else
    success "TIMEZONE: $TIMEZONE"
fi

# ============================================================================
# PASSWORD VALIDATION
# ============================================================================

log "Checking password settings..."

# Check for weak/default passwords
check_password() {
    local var_name="$1"
    local password="${!var_name:-}"

    if [[ -z "$password" ]]; then
        info "$var_name: Will be auto-generated (recommended)"
    elif [[ "$password" == "1234" ]] || [[ "$password" == "password" ]] || [[ "$password" == "admin" ]]; then
        error "$var_name: Using default/weak password '$password'"
    elif [[ ${#password} -lt 8 ]]; then
        warning "$var_name: Password is very short (${#password} chars)"
    else
        success "$var_name: Set (length: ${#password})"
    fi
}

check_password "ROOT_PASSWORD"
check_password "USER_PASSWORD"
check_password "LUKS_PASSWORD"

# ============================================================================
# SSH CONFIGURATION
# ============================================================================

log "Checking SSH configuration..."

if [[ -n "${SSH_KEY_FILE:-}" ]]; then
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        error "SSH_KEY_FILE '$SSH_KEY_FILE' does not exist"
    elif ! ssh-keygen -l -f "$SSH_KEY_FILE" &>/dev/null; then
        error "SSH_KEY_FILE '$SSH_KEY_FILE' is not a valid SSH public key"
    else
        success "SSH_KEY_FILE: Valid public key found"
    fi
else
    warning "SSH_KEY_FILE not set - password authentication will be enabled"
fi

# ============================================================================
# KERNEL VALIDATION
# ============================================================================

log "Checking kernel settings..."

valid_kernels=("hardened" "lts" "default" "zen")
if [[ ! " ${valid_kernels[*]} " =~ " ${KERNEL_TYPE:-} " ]]; then
    warning "KERNEL_TYPE '$KERNEL_TYPE' may not be valid"
else
    success "KERNEL_TYPE: $KERNEL_TYPE"
fi

# ============================================================================
# NETWORK VALIDATION
# ============================================================================

log "Checking network settings..."

if [[ "${ENABLE_WIFI:-false}" == "true" ]]; then
    if [[ -z "${WIFI_SSID:-}" ]]; then
        error "ENABLE_WIFI=true but WIFI_SSID is not set"
    fi
    if [[ -z "${WIFI_PASSWORD:-}" ]]; then
        error "ENABLE_WIFI=true but WIFI_PASSWORD is not set"
    fi
fi

if [[ "${ENABLE_WIFI:-false}" == "true" ]] && [[ -n "${WIFI_SSID:-}" ]]; then
    success "WiFi: SSID '$WIFI_SSID' configured"
fi

# ============================================================================
# DOMAIN VALIDATION
# ============================================================================

log "Checking domain settings..."

if [[ -n "${DOMAIN:-}" ]]; then
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        error "DOMAIN '$DOMAIN' is not a valid domain name"
    else
        success "DOMAIN: $DOMAIN"
        if [[ -z "${DOMAIN_EMAIL:-}" ]]; then
            warning "DOMAIN set but DOMAIN_EMAIL not set - Let's Encrypt will fail"
        fi
    fi
fi

# ============================================================================
# DISK VALIDATION
# ============================================================================

log "Checking disk settings..."

if [[ -n "${TARGET_DISK:-}" ]]; then
    # Normalize disk path for validation
    if [[ "$TARGET_DISK" =~ ^/dev/ ]]; then
        DISK_PATH="$TARGET_DISK"
    else
        DISK_PATH="/dev/$TARGET_DISK"
    fi

    # Check if disk exists or if it's a valid disk name pattern
    if [[ -b "$DISK_PATH" ]]; then
        success "TARGET_DISK: $TARGET_DISK ($DISK_PATH exists)"
    elif [[ "$TARGET_DISK" =~ ^(sd|nvme|vd)[a-z0-9]+$ ]] || [[ "$TARGET_DISK" =~ ^/dev/(sd|nvme|vd)[a-z0-9]+$ ]]; then
        success "TARGET_DISK: $TARGET_DISK (valid format, disk may not be present)"
    else
        error "TARGET_DISK '$TARGET_DISK' is not a valid block device name"
    fi
else
    info "TARGET_DISK: Will prompt during installation"
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo
echo -e "${BOLD}📊 VALIDATION SUMMARY${NC}"
echo "======================"

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ Configuration is valid!${NC}"
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ No warnings${NC}"
    else
        echo -e "${YELLOW}⚠ $WARNINGS warning(s) found (review recommended)${NC}"
    fi
    echo
    info "Ready to proceed with installation"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}⚠ $WARNINGS warning(s) also found${NC}"
    fi
    echo
    error "Fix the errors above before proceeding with installation"
    exit 1
fi