#!/bin/bash
# ============================================================================
# SECURE BOOT SETUP v5.1
# Custom key generation and systemd-boot signing
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Must run as root"

cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║   SECURE BOOT SETUP v5.1                                    ║
║   Custom Keys + Auto-Signing                                ║
╚══════════════════════════════════════════════════════════════╝
EOF

# Check UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    error "Not in UEFI mode!"
fi

# Install sbctl
if ! command -v sbctl &>/dev/null; then
    log "Installing sbctl..."
    pacman -S --noconfirm sbctl
fi

# Check Secure Boot status
SB_STATUS=$(sbctl status 2>&1 | grep "Secure Boot" | awk '{print $NF}')

log "Current Secure Boot status: $SB_STATUS"

if [[ "$SB_STATUS" == "Enabled" ]]; then
    warning "Secure Boot already enabled - re-configuring keys..."
fi

# Create custom keys
if [[ ! -f /usr/share/secureboot/keys/db/db.key ]]; then
    log "Creating custom Secure Boot keys..."
    sbctl create-keys
    success "Keys created"
fi

# Enroll keys
log "Enrolling keys to firmware..."
sbctl enroll-keys --microsoft

success "Keys enrolled"

# Sign bootloader and kernel
log "Signing bootloader and kernels..."

sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi

for kernel in /boot/EFI/Linux/*.efi; do
    if [[ -f "$kernel" ]]; then
        sbctl sign -s "$kernel"
        success "Signed: $(basename "$kernel")"
    fi
done

# Enable auto-signing hook
log "Setting up automatic signing..."

cat > /etc/pacman.d/hooks/999-sign_for_secureboot.hook << 'HOOKEOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux*
Target = systemd

[Action]
Description = Signing kernels and bootloader for Secure Boot
When = PostTransaction
Exec = /usr/bin/sbctl sign-all
HOOKEOF

success "Auto-signing hook installed"

# Verify
log "Verifying signatures..."
sbctl verify

cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ SECURE BOOT CONFIGURED!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Status:
  ✓ Custom keys generated
  ✓ Keys enrolled to firmware
  ✓ Bootloader and kernels signed
  ✓ Auto-signing enabled

Next steps:
1. Reboot
2. Enter firmware setup
3. Enable Secure Boot
4. System will boot only signed code

Your system is now protected against bootkit attacks!
EOF
