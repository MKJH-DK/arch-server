#!/bin/bash
# ============================================================================
# TPM AUTO-UNLOCK SETUP v5.1
# Automatic TPM PCR 7 enrollment with PIN
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Must run as root"

cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║   TPM AUTO-UNLOCK SETUP v5.1                                ║
║   PCR 7 Only (Firmware-Update Safe)                         ║
╚══════════════════════════════════════════════════════════════╝
EOF

# Check TPM
if [[ ! -c /dev/tpm0 ]] && [[ ! -c /dev/tpmrm0 ]]; then
    error "No TPM 2.0 device found!"
fi

success "TPM 2.0 detected"

# Detect virtualization
VIRT_TYPE="none"
if command -v systemd-detect-virt &>/dev/null; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
fi

if [[ "$VIRT_TYPE" == "oracle" ]]; then
    log "VirtualBox detected - TPM support may be limited"
    log "Ensure TPM 2.0 is enabled in VM settings: Settings → System → TPM"
fi

# Verify Secure Boot status before PCR 7 binding
log "Checking Secure Boot status..."

SB_ENABLED=false
if command -v sbctl &>/dev/null; then
    if sbctl status 2>/dev/null | grep -qi "secure boot.*enabled"; then
        SB_ENABLED=true
    fi
elif [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]] 2>/dev/null; then
    SB_STATE=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | awk '{print $NF}')
    if [[ "$SB_STATE" == "1" ]]; then
        SB_ENABLED=true
    fi
fi

if [[ "$SB_ENABLED" != "true" ]]; then
    echo ""
    echo -e "${RED}WARNING: Secure Boot is NOT enabled!${NC}"
    echo ""
    echo "  PCR 7 measures Secure Boot state. Without Secure Boot enabled,"
    echo "  PCR 7 values will change unpredictably and TPM auto-unlock will FAIL."
    echo ""
    echo "  Options:"
    echo "    1. Enable Secure Boot first: /root/arch/scripts/setup-secure-boot.sh"
    echo "    2. Continue anyway (TPM unlock may not work reliably)"
    echo "    3. Abort"
    echo ""
    read -r -p "Continue without Secure Boot? (yes/NO): " CONTINUE_NO_SB
    if [[ "$CONTINUE_NO_SB" != "yes" ]]; then
        error "Aborting: Enable Secure Boot first, then re-run this script"
    fi
    echo ""
    log "Continuing without Secure Boot - TPM unlock may be unreliable"
fi

# Find LUKS device
LUKS_DEV=$(lsblk -o NAME,FSTYPE | grep crypto_LUKS | awk '{print "/dev/" $1}' | head -1)

if [[ -z "$LUKS_DEV" ]]; then
    error "No LUKS device found!"
fi

log "LUKS device: $LUKS_DEV"

# Check if already enrolled
if cryptsetup luksDump "$LUKS_DEV" | grep -q "systemd-tpm2"; then
    log "TPM already enrolled - re-enrolling..."
    systemd-cryptenroll "$LUKS_DEV" --wipe-slot=tpm2
fi

# Generate PIN if not set
TPM_PIN="${TPM_PIN:-$(head -c 3 /dev/urandom | od -An -tu2 | tr -d ' ')}"

log "TPM PIN will be: $TPM_PIN"
log "SAVE THIS PIN SECURELY!"

# Enroll TPM with PCR 7 only + PIN
log "Enrolling TPM (PCR 7 + PIN)..."

systemd-cryptenroll "$LUKS_DEV" \
    --tpm2-device=auto \
    --tpm2-pcrs=7 \
    --tpm2-with-pin=yes

success "TPM enrollment complete!"

# Update mkinitcpio hooks
log "Updating initramfs hooks..."

if ! grep -q "sd-encrypt" /etc/mkinitcpio.conf; then
    sed -i 's/HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    success "Initramfs updated"
fi

# Save PIN
echo "$TPM_PIN" > /root/.tpm-pin
chmod 600 /root/.tpm-pin

cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ TPM AUTO-UNLOCK CONFIGURED!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TPM PIN: $TPM_PIN (saved to /root/.tpm-pin)

IMPORTANT:
1. System will auto-unlock on normal boot
2. If firmware changes, you'll need the PIN
3. Keep a recovery password available!

Next boot will use TPM unlock automatically.
EOF
