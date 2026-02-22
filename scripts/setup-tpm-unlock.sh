#!/usr/bin/env bash
set -euo pipefail

# TPM AUTO-UNLOCK SETUP
# PCR 7 only (firmware-update safer than broad PCR sets)
# Requires: systemd-cryptenroll, cryptsetup, lsblk

SCRIPT_NAME="$(basename "$0")"

# ---------- Helpers ----------
log() {
    echo "▶ $*"
}

warn() {
    echo "⚠ $*" >&2
}

error() {
    echo "✗ $*" >&2
}

ok() {
    echo "✓ $*"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        error "Required command not found: $1"
        exit 1
    }
}

# ---------- Banner ----------
cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║   TPM AUTO-UNLOCK SETUP v5.2                                ║
║   PCR 7 Only (Firmware-Update Safe)                         ║
╚══════════════════════════════════════════════════════════════╝
EOF

# ---------- Preconditions ----------
if [[ $EUID -ne 0 ]]; then
    error "Run as root"
    exit 1
fi

need_cmd systemd-cryptenroll
need_cmd cryptsetup
need_cmd lsblk
need_cmd awk
need_cmd grep

# TPM device presence check
if [[ ! -e /dev/tpmrm0 && ! -e /dev/tpm0 ]]; then
    error "TPM 2.0 device not detected (/dev/tpmrm0 or /dev/tpm0 missing)"
    exit 1
fi
ok "TPM 2.0 detected"

# Secure Boot status (informational)
log "Checking Secure Boot status..."
if command -v bootctl >/dev/null 2>&1; then
    if bootctl status 2>/dev/null | grep -qi 'Secure Boot: enabled'; then
        ok "Secure Boot is enabled"
    else
        warn "Secure Boot not detected as enabled (continuing anyway)"
    fi
elif command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
        ok "Secure Boot is enabled"
    else
        warn "Secure Boot not detected as enabled (continuing anyway)"
    fi
else
    warn "Could not verify Secure Boot state (bootctl/mokutil not found)"
fi

# ---------- Find LUKS device ----------
# Raw output avoids tree characters from lsblk (e.g. `-nvme0n1p2)
LUKS_DEV="$(lsblk -nrpo NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')"

if [[ -z "${LUKS_DEV:-}" ]]; then
    error "No LUKS device found!"
    exit 1
fi

if [[ ! -b "$LUKS_DEV" ]]; then
    error "Invalid LUKS device: $LUKS_DEV"
    exit 1
fi

log "LUKS device: $LUKS_DEV"

# ---------- Existing TPM enrollment handling ----------
# Re-run safe: wipe old TPM2 slot before enrolling a new one
if cryptsetup luksDump "$LUKS_DEV" | grep -q "systemd-tpm2"; then
    warn "Existing TPM2 enrollment detected. Replacing it..."
    systemd-cryptenroll "$LUKS_DEV" --wipe-slot=tpm2 || {
        error "Failed to wipe existing TPM2 slot"
        exit 1
    }
fi

# ---------- PIN flow ----------
echo
echo "Choose a TPM2 PIN."
echo "You will be asked to type it again by systemd-cryptenroll."
read -rsp "TPM2 PIN: " TPM_PIN
echo
read -rsp "Repeat TPM2 PIN: " TPM_PIN2
echo

if [[ -z "${TPM_PIN:-}" ]]; then
    error "PIN cannot be empty"
    exit 1
fi

if [[ "$TPM_PIN" != "$TPM_PIN2" ]]; then
    error "PINs do not match"
    unset TPM_PIN TPM_PIN2
    exit 1
fi

log "TPM PIN confirmed."
log "When prompted next, enter the same TPM2 PIN you just chose."

# ---------- Enroll TPM ----------
log "Enrolling TPM (PCR 7 + PIN)..."
set +e
ENROLL_OUTPUT="$(
    systemd-cryptenroll "$LUKS_DEV" \
        --tpm2-device=auto \
        --tpm2-pcrs=7 \
        --tpm2-with-pin=yes 2>&1
)"
ENROLL_RC=$?
set -e

# Show command output to user
echo "$ENROLL_OUTPUT"

if [[ $ENROLL_RC -ne 0 ]]; then
    error "TPM enrollment failed"
    unset TPM_PIN TPM_PIN2
    exit 1
fi

# Surface SHA1 fallback as warning if present
if echo "$ENROLL_OUTPUT" | grep -qi "falling back to SHA1"; then
    warn "TPM is using SHA1 PCR bank fallback (lower security than SHA256)."
fi

ok "TPM enrollment complete!"

# ---------- Initramfs / boot config ----------
log "Updating initramfs hooks..."

# Try mkinitcpio first (Arch)
if command -v mkinitcpio >/dev/null 2>&1; then
    mkinitcpio -P || {
        error "mkinitcpio failed"
        unset TPM_PIN TPM_PIN2
        exit 1
    }
# Fallback: dracut (if user uses it)
elif command -v dracut >/dev/null 2>&1; then
    dracut --regenerate-all --force || {
        error "dracut failed"
        unset TPM_PIN TPM_PIN2
        exit 1
    }
else
    warn "No mkinitcpio/dracut found. Skipping initramfs regeneration."
fi

# Clear PIN vars from shell memory
unset TPM_PIN TPM_PIN2

# ---------- Done ----------
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "TPM AUTO-UNLOCK CONFIGURED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "IMPORTANT:"
echo "1. System will auto-unlock on normal boot"
echo "2. If firmware/TPM state changes, you'll need the TPM2 PIN you chose"
echo "3. Keep a recovery password available!"
echo "4. Store your TPM2 PIN securely in a password manager (do not store in plaintext files)"
echo
echo "Next boot will use TPM unlock automatically."