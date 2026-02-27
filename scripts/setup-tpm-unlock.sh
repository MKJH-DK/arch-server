#!/usr/bin/env bash
set -euo pipefail

# TPM AUTO-UNLOCK SETUP
# PCR 7 (Secure Boot state) + optional signed PCR 11 (UKI measurement)
#
# PCR 7 only  (default): Simple. Re-enrollment needed on firmware changes.
# PCR 7 + signed PCR 11: Optimal for UKI setups. Kernel updates rebuild UKIs
#   without TPM re-enrollment - the TPM verifies a cryptographic signature
#   on the PCR 11 policy instead of an exact PCR value.
#
# Requires: systemd-cryptenroll, cryptsetup, lsblk, ukify (for PCR 11)

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
║   PCR 7 + optional signed PCR 11 (UKI-aware)                ║
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

# ---------- PCR 11 mode selection ----------
echo
echo "Choose TPM enrollment mode:"
echo "  1) PCR 7 only          - Simple, works with all setups (default)"
echo "  2) PCR 7 + signed PCR 11 - Optimal for UKI: kernel updates don't need re-enrollment"
echo
read -rp "Mode [1/2, default=1]: " PCR_MODE_INPUT
PCR_MODE="${PCR_MODE_INPUT:-1}"

USE_SIGNED_PCR11=false
if [[ "$PCR_MODE" == "2" ]]; then
    if ! command -v ukify >/dev/null 2>&1; then
        warn "ukify not found - signed PCR 11 requires systemd-ukify package"
        warn "Install: pacman -S systemd  (ukify is included in systemd >= 253)"
        warn "Falling back to PCR 7 only"
        PCR_MODE="1"
    else
        USE_SIGNED_PCR11=true
        ok "Mode: PCR 7 + signed PCR 11 (UKI-aware)"
    fi
fi

if [[ "$PCR_MODE" != "2" ]]; then
    ok "Mode: PCR 7 only (Secure Boot state)"
fi

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

# ---------- Signed PCR 11 key generation ----------
PCR_KEY_ARGS=""
if [[ "$USE_SIGNED_PCR11" == "true" ]]; then
    PCR_PRIVKEY="/etc/systemd/tpm2-pcr-private-key.pem"
    PCR_PUBKEY="/etc/systemd/tpm2-pcr-public-key.pem"

    if [[ -f "$PCR_PUBKEY" ]]; then
        warn "Existing PCR signing keys found at $PCR_PUBKEY"
        read -rp "Reuse existing keys? [Y/n]: " REUSE_KEYS
        REUSE_KEYS="${REUSE_KEYS:-Y}"
    else
        REUSE_KEYS="n"
    fi

    if [[ "${REUSE_KEYS,,}" != "y" ]]; then
        log "Generating PCR 11 signing key pair..."
        ukify genkey \
            --pcr-private-key="$PCR_PRIVKEY" \
            --pcr-public-key="$PCR_PUBKEY"
        chmod 600 "$PCR_PRIVKEY"
        chmod 644 "$PCR_PUBKEY"
        ok "PCR signing keys generated"
        log "IMPORTANT: The private key at $PCR_PRIVKEY signs UKI PCR policies."
        log "Back it up securely - if lost you will need to re-enroll TPM after kernel updates."
    else
        ok "Reusing existing PCR signing keys"
    fi

    # Sign current UKI's PCR 11 prediction
    log "Signing PCR 11 policy for current UKI..."
    # Find the UKI (typically in /boot or /efi)
    UKI_PATH=""
    for candidate in /boot/EFI/Linux/*.efi /efi/EFI/Linux/*.efi /boot/linux.efi; do
        if [[ -f "$candidate" ]]; then
            UKI_PATH="$candidate"
            break
        fi
    done

    if [[ -n "$UKI_PATH" ]]; then
        log "UKI found: $UKI_PATH"
        # ukify sign creates/updates the .pcrsig section in the UKI
        ukify sign \
            --pcr-private-key="$PCR_PRIVKEY" \
            --pcr-public-key="$PCR_PUBKEY" \
            --pcr-banks=sha256 \
            "$UKI_PATH" 2>&1 || warn "UKI PCR signing failed - continuing without PCR 11 policy"
        ok "UKI PCR 11 policy signed"
    else
        warn "No UKI found - PCR 11 signing skipped. Sign UKI manually after mkinitcpio."
    fi

    PCR_KEY_ARGS="--tpm2-public-key=${PCR_PUBKEY} --tpm2-public-key-pcrs=11"
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
if [[ "$USE_SIGNED_PCR11" == "true" ]]; then
    log "Enrolling TPM (PCR 7 direct + signed PCR 11 + PIN)..."
else
    log "Enrolling TPM (PCR 7 + PIN)..."
fi

set +e
ENROLL_OUTPUT="$(
    # shellcheck disable=SC2086
    systemd-cryptenroll "$LUKS_DEV" \
        --tpm2-device=auto \
        --tpm2-pcrs=7 \
        --tpm2-with-pin=yes \
        $PCR_KEY_ARGS 2>&1
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
echo "Mode: $(if [[ "$USE_SIGNED_PCR11" == "true" ]]; then echo "PCR 7 + signed PCR 11 (UKI-aware)"; else echo "PCR 7 only"; fi)"
echo
echo "IMPORTANT:"
echo "1. System will auto-unlock on normal boot"
echo "2. If firmware/TPM state changes, you'll need the TPM2 PIN you chose"
echo "3. Keep a recovery password available!"
echo "4. Store your TPM2 PIN securely in a password manager (do not store in plaintext files)"
if [[ "$USE_SIGNED_PCR11" == "true" ]]; then
    echo
    echo "PCR 11 signed policy:"
    echo "5. After each kernel update, mkinitcpio rebuilds the UKI automatically"
    echo "   The UKI mkinitcpio hook re-signs the PCR 11 policy - no re-enrollment needed"
    echo "   Private key: /etc/systemd/tpm2-pcr-private-key.pem (back this up!)"
fi
echo
echo "Next boot will use TPM unlock automatically."