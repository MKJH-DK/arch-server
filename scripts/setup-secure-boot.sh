#!/bin/bash
# ============================================================================
# SECURE BOOT SETUP v5.1
# Custom key generation and systemd-boot signing
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
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
    warn "Secure Boot already enabled - re-configuring keys..."
fi

# Create custom keys
if [[ ! -f /usr/share/secureboot/keys/db/db.key ]]; then
    log "Creating custom Secure Boot keys..."
    sbctl create-keys
    success "Keys created"
fi

# Enroll keys
log "Enrolling keys to firmware..."

# Check Setup Mode
SETUP_MODE=$(sbctl status 2>&1 | grep -i "setup mode" | grep -c -i "enabled" || true)
if [[ "$SETUP_MODE" -eq 0 ]]; then
    error "Secure Boot is NOT in Setup Mode!
  → Reboot into UEFI firmware setup (Del/F2 at POST)
  → Find 'Secure Boot' → 'Delete/Clear all Secure Boot keys' (or 'Reset to Setup Mode')
  → Save and reboot back to Arch, then re-run this script"
fi

# Ensure efivarfs is mounted read-write
EFIVAR_DIR="/sys/firmware/efi/efivars"
if mountpoint -q "$EFIVAR_DIR"; then
    if mount | grep -q "efivarfs.*ro"; then
        log "Remounting efivarfs read-write..."
        mount -o remount,rw "$EFIVAR_DIR" || warn "Could not remount efivarfs rw - enrollment may fail"
    fi
else
    error "efivarfs is not mounted at $EFIVAR_DIR - are you in UEFI mode?"
fi

# EFI variables are often marked immutable - remove the flag before enrolling
for var in PK-8be4df61-93ca-11d2-aa0d-00e098032b8c \
           KEK-8be4df61-93ca-11d2-aa0d-00e098032b8c \
           db-d719b2cb-3d3a-4596-a3bc-dad00e67656f; do
    if [[ -f "$EFIVAR_DIR/$var" ]]; then
        chattr -i "$EFIVAR_DIR/$var" 2>/dev/null && \
            log "Removed immutable flag: $var" || \
            warn "Could not remove immutable flag on $var (may be ok)"
    fi
done

sbctl enroll-keys --microsoft

success "Keys enrolled"

# Sign bootloader and kernel
log "Signing bootloader and kernels..."

# Find ESP mount point dynamically
ESP_PATH=$(bootctl --print-esp-path 2>/dev/null || findmnt -n -o TARGET --target /boot/efi 2>/dev/null || findmnt -n -o TARGET --target /boot 2>/dev/null || echo "/boot")
log "ESP detected at: $ESP_PATH"

# Register and sign all EFI binaries found on the ESP
SIGNED_COUNT=0

while IFS= read -r efi_file; do
    sbctl sign -s "$efi_file" && \
        success "Signed: ${efi_file#"$ESP_PATH"/}" || \
        warn "Could not sign: ${efi_file#"$ESP_PATH"/}"
    SIGNED_COUNT=$((SIGNED_COUNT + 1))
done < <(find "$ESP_PATH" \( -name "*.efi" -o -name "*.EFI" \) 2>/dev/null)

if [[ $SIGNED_COUNT -eq 0 ]]; then
    warn "No EFI binaries found under $ESP_PATH - run 'bootctl install' first if systemd-boot is not installed"
fi

# Enable auto-signing hook
log "Setting up automatic signing..."

mkdir -p /etc/pacman.d/hooks
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
