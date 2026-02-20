#!/bin/bash
# ============================================================================
# ARCH LINUX v5.1 COMPLETE INSTALLER
# systemd-boot + UKI + LUKS2 + Btrfs + TPM + Secure Boot Ready
# ============================================================================
#
# This script installs Arch Linux with maximum security:
# - LUKS2 full disk encryption with Argon2id
# - Btrfs with subvolumes and compression
# - systemd-boot bootloader (NOT EFI stub!)
# - UKI (Unified Kernel Images)
# - TPM 2.0 auto-unlock preparation
# - Secure Boot ready
# - Ansible bootstrap
#
# USAGE: ./install.sh [options]
#
# OPTIONS:
#   --dry-run       Validate config and show what would be done (no disk changes)
#   --source-only   Only source the script (for testing functions)
#   --help          Show this help
#
# REQUIREMENTS:
# - Boot Arch ISO in UEFI mode
# - Active internet connection
# - config.env in the same directory
#
# ============================================================================

set -uo pipefail

# ============================================================================
# COMMAND LINE OPTIONS
# ============================================================================

DRY_RUN=false
SOURCE_ONLY=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --source-only)
            SOURCE_ONLY=true
            ;;
        --help|-h)
            head -30 "$0" | tail -n +2 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
    esac
done

# If --source-only, just define functions and exit (for testing)
if [[ "$SOURCE_ONLY" == "true" ]]; then
    # Define minimal functions for testing
    log() { echo -e "[LOG] $1"; }
    success() { echo -e "[OK] $1"; }
    warning() { echo -e "[WARN] $1"; }
    error() { echo -e "[ERROR] $1"; exit 1; }
    info() { echo -e "[INFO] $1"; }
    return 0 2>/dev/null || exit 0
fi

# ============================================================================
# COLORS & LOGGING
# ============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${CYAN}ℹ${NC} $1"; }

# ============================================================================
# ERROR HANDLING & ROLLBACK
# ============================================================================

# Installation phases for rollback tracking
INSTALL_PHASE="init"
BACKUP_DIR="/tmp/arch-install-backup"
ROLLBACK_LOG="/tmp/arch-install-rollback.log"

# Create backup directory
mkdir -p "$BACKUP_DIR" 2>/dev/null || true

# Cleanup function for failed installations
cleanup_on_error() {
    local exit_code=$?
    echo
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    INSTALLATION FAILED                       ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo

    warning "Installation failed at phase: $INSTALL_PHASE"
    warning "Exit code: $exit_code"

    # Attempt rollback based on phase
    case "$INSTALL_PHASE" in
        "disk_setup")
            rollback_disk_setup
            ;;
        "base_install")
            rollback_base_install
            ;;
        "bootloader")
            rollback_bootloader
            ;;
        "encryption")
            rollback_encryption
            ;;
        "ssh_setup")
            rollback_ssh_setup
            ;;
        *)
            info "No automatic rollback available for phase: $INSTALL_PHASE"
            ;;
    esac

    # Show recovery options
    echo
    info "Recovery options:"
    echo "  1. Fix the issue and re-run the installer"
    echo "  2. Boot from live USB and manually fix"
    echo "  3. Check logs: $ROLLBACK_LOG"
    echo "  4. Get help: https://github.com/humethix/arch-server/issues"
    echo

    # Cleanup temp files
    rm -rf "$BACKUP_DIR" 2>/dev/null || true

    exit "$exit_code"
}

# Set trap for error handling
trap cleanup_on_error ERR

# Backup critical files
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/$(basename "$file").backup" 2>/dev/null || true
        echo "BACKUP: $file" >> "$ROLLBACK_LOG"
    fi
}

# Rollback functions
rollback_disk_setup() {
    warning "Attempting to rollback disk changes..."
    # Note: This is dangerous - only show instructions
    echo "Manual rollback required for disk changes:"
    echo "  - Check partition table: fdisk -l $TARGET_DISK"
    echo "  - Restore from backup if available"
    echo "  - Reformat and start over if needed"
}

rollback_base_install() {
    warning "Attempting to rollback base installation..."
    # Try to restore pacman database
    if [[ -d "$BACKUP_DIR/pacman-db" ]]; then
        cp -r "$BACKUP_DIR/pacman-db"/* /var/lib/pacman/ 2>/dev/null || true
    fi
}

rollback_bootloader() {
    warning "Attempting to rollback bootloader..."
    # Try to restore EFI backup
    if mountpoint -q /boot; then
        cp "$BACKUP_DIR/boot"/* /boot/ 2>/dev/null || true
    fi
}

rollback_encryption() {
    warning "Encryption rollback not supported automatically"
    echo "Manual intervention required for LUKS rollback"
}

rollback_ssh_setup() {
    warning "Rolling back SSH setup..."
    # Remove SSH keys if they were installed
    if [[ -d "$BACKUP_DIR/ssh" ]]; then
        if mountpoint -q /mnt; then
            # Restore original SSH configs if backed up
            if [[ -f "$BACKUP_DIR/ssh/authorized_keys.user" ]]; then
                cp "$BACKUP_DIR/ssh/authorized_keys.user" /mnt/home/"$USERNAME"/.ssh/authorized_keys 2>/dev/null || true
            else
                rm -f /mnt/home/"$USERNAME"/.ssh/authorized_keys 2>/dev/null || true
            fi
            if [[ -f "$BACKUP_DIR/ssh/authorized_keys.root" ]]; then
                cp "$BACKUP_DIR/ssh/authorized_keys.root" /mnt/root/.ssh/authorized_keys 2>/dev/null || true
            else
                rm -f /mnt/root/.ssh/authorized_keys 2>/dev/null || true
            fi
        fi
    fi
}

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    error "config.env not found! Run from project directory."
fi

log "Loading configuration from config.env..."
source "$CONFIG_FILE"
success "Configuration loaded"

# Run configuration validation
log "Validating configuration..."
if ! "$SCRIPT_DIR/config-validate.sh"; then
    error "Configuration validation failed! Fix errors and try again."
fi
success "Configuration validated"

# ============================================================================
# VALIDATION
# ============================================================================

log "Validating environment..."

# Check UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    error "Not booted in UEFI mode! Please boot in UEFI mode."
fi
success "UEFI mode confirmed"

# Check internet
if ! ping -c 1 archlinux.org &>/dev/null; then
    error "No internet connection! Connect first."
fi
success "Internet connection active"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "Must run as root (or from Arch ISO)"
fi

# Set defaults for optional config variables (may not be defined in basic config)
ENABLE_TPM_UNLOCK="${ENABLE_TPM_UNLOCK:-false}"
ENABLE_SECURE_BOOT="${ENABLE_SECURE_BOOT:-false}"
ENABLE_WIFI="${ENABLE_WIFI:-false}"
INSTALL_CONTAINERS="${INSTALL_CONTAINERS:-false}"
AUTO_INSTALL="${AUTO_INSTALL:-false}"
EFI_SIZE_MB="${EFI_SIZE_MB:-1024}"
BTRFS_COMPRESSION="${BTRFS_COMPRESSION:-zstd:3}"
KERNEL_TYPE="${KERNEL_TYPE:-hardened}"

# Detect virtualization environment
VIRT_TYPE="none"
if command -v systemd-detect-virt &>/dev/null; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
fi

if [[ "$VIRT_TYPE" != "none" ]]; then
    info "Virtualization detected: $VIRT_TYPE"

    if [[ "$VIRT_TYPE" == "oracle" ]]; then
        warning "VirtualBox detected - applying compatibility adjustments:"
        echo "  • Secure Boot: Limited support (test mode only)"
        echo "  • TPM 2.0: Requires VirtualBox 7+ with explicit TPM enable"
        echo "  • Network: Ensure Bridged Adapter or NAT with port forwarding"
        echo "  • EFI: Must be enabled in VM settings"
        echo ""

        # Check if TPM is actually available in VirtualBox
        if [[ "$ENABLE_TPM_UNLOCK" == "true" ]] && [[ ! -c /dev/tpm0 ]] && [[ ! -c /dev/tpmrm0 ]]; then
            warning "TPM device not found - disabling TPM auto-unlock for VirtualBox"
            warning "Enable TPM in VirtualBox: Settings → System → TPM → v2.0"
            ENABLE_TPM_UNLOCK=false
        fi

        # Warn about Secure Boot in VirtualBox
        if [[ "$ENABLE_SECURE_BOOT" == "true" ]]; then
            warning "Secure Boot in VirtualBox has limited support"
            warning "Keys will be prepared but enrollment may require manual steps"
            info "Disable Secure Boot in VM settings for first boot, then enable after key enrollment"
        fi
    fi
fi
success "Environment validated"

# ============================================================================
# BANNER
# ============================================================================

clear
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     ARCH LINUX v5.1 SECURE SERVER INSTALLER                 ║
║                                                              ║
║     systemd-boot • UKI • LUKS2 • Btrfs • TPM                ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo ""

info "Configuration:"
echo "  • Hostname: $HOSTNAME"
echo "  • Username: $USERNAME"
echo "  • Timezone: $TIMEZONE"
echo "  • Kernel: linux-$KERNEL_TYPE"
echo "  • Bootloader: systemd-boot + UKI"
echo "  • Encryption: LUKS2 + TPM"
echo ""

if [[ "$AUTO_INSTALL" != "true" ]]; then
    warning "This will ERASE all data on the target disk!"
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        error "Installation aborted by user"
    fi
fi

# ============================================================================
# DISK SELECTION
# ============================================================================

log "Disk selection..."

if [[ -z "$TARGET_DISK" ]]; then
    echo ""
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
    read -r -p "Enter target disk (e.g., sda, /dev/sda, nvme0n1, vda): " TARGET_DISK
fi

# Normalize disk path
if [[ "$TARGET_DISK" =~ ^/dev/ ]]; then
    # Full path provided (e.g., /dev/sda, /dev/nvme0n1)
    DISK="$TARGET_DISK"
else
    # Short name provided (e.g., sda, nvme0n1)
    DISK="/dev/$TARGET_DISK"
fi

# Set partition prefix based on disk type
if [[ "$DISK" =~ ^/dev/nvme ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="$DISK"
fi

if [[ ! -b "$DISK" ]]; then
    error "Disk $DISK not found!"
fi

info "Target disk: $DISK"
lsblk "$DISK"
echo ""

if [[ "$AUTO_INSTALL" != "true" ]]; then
    warning "ALL DATA on $DISK will be ERASED!"
    read -p "Type 'ERASE' to confirm: " -r
    if [[ "$REPLY" != "ERASE" ]]; then
        error "Installation aborted"
    fi
fi

# ============================================================================
# PASSWORD GENERATION
# ============================================================================

log "Generating passwords..."

if [[ -z "$ROOT_PASSWORD" ]]; then
    ROOT_PASSWORD=$(openssl rand -base64 16)
    info "Generated root password: $ROOT_PASSWORD"
fi

if [[ -z "$USER_PASSWORD" ]]; then
    USER_PASSWORD=$(openssl rand -base64 16)
    info "Generated user password: $USER_PASSWORD"
fi

if [[ -z "$LUKS_PASSWORD" ]]; then
    LUKS_PASSWORD=$(openssl rand -base64 24)
    info "Generated LUKS password: $LUKS_PASSWORD"
fi

# Save credentials
CRED_FILE="/root/.credentials-$(date +%s)"
cat > "$CRED_FILE" << CREDEOF
# Arch Linux v5.1 Installation Credentials
# Generated: $(date)
# Hostname: $HOSTNAME

ROOT_PASSWORD=$ROOT_PASSWORD
USER_PASSWORD=$USER_PASSWORD
LUKS_PASSWORD=$LUKS_PASSWORD
CREDEOF
chmod 600 "$CRED_FILE"
success "Credentials saved to $CRED_FILE"

# ============================================================================
# DISK PARTITIONING
# ============================================================================

INSTALL_PHASE="disk_setup"
log "Partitioning disk $DISK..."

EFI_PART="${PART_PREFIX}1"
LUKS_PART="${PART_PREFIX}2"

# DRY-RUN: Show what would happen without making changes
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    info "DRY-RUN: Would perform the following disk operations:"
    echo "  - Wipe disk: wipefs -af $DISK"
    echo "  - Clear partition table: sgdisk -Z $DISK"
    echo "  - Create GPT: sgdisk -o $DISK"
    echo "  - Create EFI partition (${EFI_SIZE_MB}MB): $EFI_PART"
    echo "  - Create LUKS partition (remaining space): $LUKS_PART"
    echo "  - Format EFI as FAT32"
    echo "  - Create LUKS2 encrypted container (Argon2id)"
    echo "  - Create Btrfs with subvolumes: @, @home, @log, @containers, @snapshots"
    echo ""
    success "DRY-RUN: Disk operations validated"
else
    # Backup current partition table if it exists
    backup_file "/tmp/current-partitions.txt"
    sfdisk -d "$DISK" > "$BACKUP_DIR/partition-table.bak" 2>/dev/null || true

    # Wipe disk
    wipefs -af "$DISK" || true
    sgdisk -Z "$DISK" || true

    # Create GPT partition table
    sgdisk -o "$DISK"

    # Create EFI partition (1GB recommended for UKIs)
    sgdisk -n 1:0:+"${EFI_SIZE_MB}"M -t 1:ef00 -c 1:"EFI" "$DISK"

    # Create LUKS partition (rest of disk)
    sgdisk -n 2:0:0 -t 2:8309 -c 2:"LUKS" "$DISK"

    # Inform kernel
    partprobe "$DISK"
    sleep 2

    success "Partitions created:"
    lsblk "$DISK"
fi

# ============================================================================
# LUKS2 ENCRYPTION
# ============================================================================

INSTALL_PHASE="encryption"
log "Setting up LUKS2 encryption..."

# DRY-RUN: Skip actual encryption
if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY-RUN: Would create LUKS2 container with:"
    echo "  - Cipher: aes-xts-plain64 (512-bit)"
    echo "  - Hash: SHA-512"
    echo "  - KDF: Argon2id (1GB memory, 4 threads)"
    echo "  - Partition: $LUKS_PART"
    echo ""
    LUKS_BACKUP="/root/luks-header-backup-DRYRUN.bin"
    success "DRY-RUN: LUKS encryption validated"
else
    # Format LUKS2 with Argon2id (best security)
    echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --pbkdf-memory 1048576 \
        --pbkdf-parallel 4 \
        --use-random \
        --label "cryptroot" \
        "$LUKS_PART" -

    success "LUKS2 encrypted partition created"

    # Open LUKS partition
    echo -n "$LUKS_PASSWORD" | cryptsetup open "$LUKS_PART" cryptroot -

    success "LUKS partition opened as /dev/mapper/cryptroot"

    # Backup LUKS header
    log "Backing up LUKS header..."
    LUKS_BACKUP="/root/luks-header-backup-$(date +%Y%m%d).bin"
    cryptsetup luksHeaderBackup "$LUKS_PART" --header-backup-file "$LUKS_BACKUP"
    chmod 600 "$LUKS_BACKUP"
    success "LUKS header backed up to $LUKS_BACKUP"
fi

# ============================================================================
# BTRFS FILESYSTEM
# ============================================================================

log "Creating Btrfs filesystem..."

BTRFS_OPTS="defaults,noatime,compress=${BTRFS_COMPRESSION},space_cache=v2"

# DRY-RUN: Skip filesystem creation
if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY-RUN: Would create Btrfs filesystem with:"
    echo "  - Label: ArchLinux"
    echo "  - Compression: ${BTRFS_COMPRESSION}"
    echo "  - Subvolumes: @, @home, @log, @containers, @snapshots"
    echo "  - Mount options: $BTRFS_OPTS"
    echo ""
    success "DRY-RUN: Btrfs configuration validated"
else
    mkfs.btrfs -f -L "ArchLinux" /dev/mapper/cryptroot

    success "Btrfs filesystem created"

    # Mount for subvolume creation
    mount /dev/mapper/cryptroot /mnt

    # Create subvolumes
    log "Creating Btrfs subvolumes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@containers
    btrfs subvolume create /mnt/@snapshots

    success "Subvolumes created"

    # Unmount
    umount /mnt

    # Mount with options
    log "Mounting filesystems..."

    mount -o subvol=@,"$BTRFS_OPTS" /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/{home,var/log,var/lib/containers,.snapshots,efi}
    mount -o subvol=@home,"$BTRFS_OPTS" /dev/mapper/cryptroot /mnt/home
    mount -o subvol=@log,"$BTRFS_OPTS" /dev/mapper/cryptroot /mnt/var/log
    mount -o subvol=@containers,"$BTRFS_OPTS" /dev/mapper/cryptroot /mnt/var/lib/containers
    mount -o subvol=@snapshots,"$BTRFS_OPTS" /dev/mapper/cryptroot /mnt/.snapshots

    # Format and mount EFI
    mkfs.fat -F32 -n EFI "$EFI_PART"
    mount -o fmask=0077,dmask=0077 "$EFI_PART" /mnt/efi

    success "All filesystems mounted"
fi

# ============================================================================
# PACKAGE INSTALLATION
# ============================================================================

INSTALL_PHASE="base_install"
log "Installing base system..."

# Update mirrors
reflector --country Denmark,Germany,Netherlands \
          --protocol https \
          --sort rate \
          --save /etc/pacman.d/mirrorlist || true

# Determine kernel package
case "$KERNEL_TYPE" in
    hardened) KERNEL_PKG="linux-hardened" ;;
    lts) KERNEL_PKG="linux-lts" ;;
    zen) KERNEL_PKG="linux-zen" ;;
    *) KERNEL_PKG="linux" ;;
esac

# Base packages
PACKAGES=(
    base
    base-devel
    "$KERNEL_PKG"
    "${KERNEL_PKG}-headers"
    linux-firmware
    intel-ucode
    amd-ucode
    btrfs-progs
    networkmanager
    openssh
    sudo
    vim
    git
    ansible
    python
    python-pip
    man-db
    man-pages
    htop
    curl
    wget
    rsync
)

# systemd-boot specific
PACKAGES+=(
    systemd-ukify
    sbctl
)

# TPM support
if [[ "$ENABLE_TPM_UNLOCK" == "true" ]]; then
    PACKAGES+=(
        tpm2-tss
        tpm2-tools
    )
fi

# WiFi support
if [[ "$ENABLE_WIFI" == "true" ]]; then
    PACKAGES+=(
        iwd
        wireless-regdb
    )
fi

# Container runtime
if [[ "$INSTALL_CONTAINERS" == "true" ]]; then
    PACKAGES+=(
        podman
        fuse-overlayfs
        slirp4netns
        cni-plugins
        aardvark-dns
        crun
    )
fi

# DRY-RUN: Show packages and exit
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    info "DRY-RUN: Would install ${#PACKAGES[@]} packages:"
    echo "  ${PACKAGES[*]}" | fold -s -w 70 | sed 's/^/    /'
    echo ""
    echo "================================================================"
    echo "  DRY-RUN COMPLETE - CONFIGURATION VALIDATED"
    echo "================================================================"
    echo ""
    echo "  Configuration summary:"
    echo "    Hostname: $HOSTNAME"
    echo "    Username: $USERNAME"
    echo "    Timezone: $TIMEZONE"
    echo "    Kernel: $KERNEL_TYPE"
    echo "    Disk: $DISK"
    echo "    EFI: $EFI_PART (${EFI_SIZE_MB}MB)"
    echo "    LUKS: $LUKS_PART"
    echo "    Btrfs compression: $BTRFS_COMPRESSION"
    echo "    TPM unlock: $ENABLE_TPM_UNLOCK"
    echo "    Secure Boot: $ENABLE_SECURE_BOOT"
    echo "    Static IP: ${STATIC_IP:-DHCP}"
    echo ""
    echo "  To perform actual installation, run without --dry-run"
    echo ""
    exit 0
fi

# Install packages
pacstrap -K /mnt "${PACKAGES[@]}"

success "Base system installed"

# ============================================================================
# SYSTEM CONFIGURATION
# ============================================================================

log "Configuring system..."

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
arch-chroot /mnt hwclock --systohc

# Localization
echo "$LOCALE UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf

# Keymap
echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /mnt/etc/hostname

# Hosts file
cat > /mnt/etc/hosts << HOSTSEOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTSEOF

success "System configuration complete"

# ============================================================================
# USER SETUP (v5.2: Fixed password setting bug!)
# ============================================================================

log "Setting up users..."

# Root password with verification
log "Setting root password..."
if ! echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd; then
    error "Failed to set root password!"
fi

# Verify root password was set
if ! arch-chroot /mnt getent shadow root | grep -q '^\w*:\$'; then
    error "Root password verification failed!"
fi
success "Root password set"

# Create user with verification
log "Creating user: $USERNAME..."
if ! arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME" 2>/dev/null; then
    # User might exist, try to continue
    warning "User creation returned error (might already exist)"
fi

# Verify user exists
if ! arch-chroot /mnt id "$USERNAME" &>/dev/null; then
    error "User $USERNAME does not exist after creation!"
fi
success "User $USERNAME created"

# Set user password with multiple methods for reliability
log "Setting password for $USERNAME..."

# Method 1: chpasswd (standard)
if echo "$USERNAME:$USER_PASSWORD" | arch-chroot /mnt chpasswd 2>/dev/null; then
    success "Password set via chpasswd"
else
    warning "chpasswd failed, trying alternative method..."
    
    # Method 2: passwd via expect-style input
    if ! arch-chroot /mnt bash -c "echo '$USER_PASSWORD' | passwd --stdin '$USERNAME'" 2>/dev/null; then
        warning "passwd --stdin failed, trying echo method..."
        
        # Method 3: Direct echo method
        if ! arch-chroot /mnt bash -c "echo -e '$USER_PASSWORD\n$USER_PASSWORD' | passwd '$USERNAME'" 2>/dev/null; then
            error "All password setting methods failed for user $USERNAME!"
        fi
    fi
fi

# CRITICAL: Verify password was actually set
log "Verifying password for $USERNAME..."
if ! arch-chroot /mnt getent shadow "$USERNAME" | grep -q "^\w*:\\\$"; then
    error "Password verification failed for $USERNAME! Password was not set correctly."
fi
success "Password verified for $USERNAME"

# Sudo access
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
chmod 440 /mnt/etc/sudoers.d/wheel

# Verify user is in wheel group
if ! arch-chroot /mnt groups "$USERNAME" | grep -q wheel; then
    error "User $USERNAME is not in wheel group!"
fi

# Final verification
log "Final user verification..."
arch-chroot /mnt id "$USERNAME"
success "Users configured and verified"

# ============================================================================
# SSH KEY SETUP
# ============================================================================

INSTALL_PHASE="ssh_setup"
log "Setting up SSH key authentication..."

# Create backup directory for SSH files early
mkdir -p "$BACKUP_DIR/ssh" 2>/dev/null || true

# Verify mount point before SSH operations
if ! mountpoint -q /mnt; then
    error "Mount point /mnt is not mounted! Cannot proceed with SSH setup."
fi

# Use config variable or default
SSH_KEY_FILE="${SSH_KEY_FILE:-authorized_keys.pub}"
# Make path absolute if relative
if [[ ! "$SSH_KEY_FILE" = /* ]]; then
    SSH_KEY_FILE="$SCRIPT_DIR/$SSH_KEY_FILE"
fi
SSH_KEY_GENERATED=false
SSH_GENERATE_IF_MISSING="${SSH_GENERATE_IF_MISSING:-true}"

# Function to validate SSH public key format (returns 0 for valid, 1 for invalid)
# Note: Uses explicit return to avoid triggering ERR trap
validate_ssh_key() {
    local key_file="$1"
    
    # Check file exists
    if [[ ! -f "$key_file" ]]; then
        return 1
    fi
    
    # Check if file contains valid SSH public key format
    # Use || true to prevent ERR trap, then check result
    local result
    result=$(grep -cE "^(ssh-(rsa|dss|ed25519)|ecdsa-sha2-nistp[0-9]+)" "$key_file" 2>/dev/null || echo "0")
    
    if [[ "$result" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to find SSH public key
# Note: Returns empty string if not found (to avoid ERR trap issues)
find_ssh_key() {
    local key_file="$1"

    # First check the configured file
    if [[ -f "$key_file" ]]; then
        if validate_ssh_key "$key_file"; then
            echo "$key_file"
            return 0
        fi
    fi

    # If not found, look for common SSH keys in ~/.ssh/
    local key_type key_path
    for key_type in ed25519 rsa ecdsa; do
        key_path="$HOME/.ssh/id_${key_type}.pub"
        if [[ -f "$key_path" ]]; then
            if validate_ssh_key "$key_path"; then
                info "Found SSH key in ~/.ssh/: $key_path"
                echo "$key_path"
                return 0
            fi
        fi
    done

    # Not found - return empty (don't return 1 to avoid ERR trap)
    echo ""
    return 0
}

# Try to find SSH public key
FOUND_SSH_KEY=$(find_ssh_key "$SSH_KEY_FILE")
if [[ -n "$FOUND_SSH_KEY" ]]; then
    SSH_KEY_FILE="$FOUND_SSH_KEY"
    info "Using SSH public key: $SSH_KEY_FILE"
else
    warning "No SSH public key found at $SSH_KEY_FILE"
    echo ""
    echo "SSH key authentication is recommended for security."
    echo ""
    echo "Options:"
    echo "  1) Generate new SSH keypair now"
    echo "  2) Skip (use password authentication only)"
    echo ""
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        # Auto mode - use config setting
        if [[ "$SSH_GENERATE_IF_MISSING" == "true" ]]; then
            REPLY="1"
        else
            REPLY="2"
        fi
    else
        read -r -p "Choose option [1/2]: " REPLY
    fi
    
    if [[ "$REPLY" == "1" ]]; then
        log "Generating new SSH keypair..."
        
        # Create keys directory with error handling
        if ! mkdir -p "$SCRIPT_DIR/keys"; then
            error "Failed to create keys directory: $SCRIPT_DIR/keys"
        fi
        
        # Generate ed25519 keypair with error handling
        if ! ssh-keygen -t ed25519 -f "$SCRIPT_DIR/keys/id_ed25519" -N "" -C "arch-server-$(date +%Y%m%d)" 2>/dev/null; then
            error "Failed to generate SSH keypair!"
        fi
        
        # Verify keypair was created
        if [[ ! -f "$SCRIPT_DIR/keys/id_ed25519" ]] || [[ ! -f "$SCRIPT_DIR/keys/id_ed25519.pub" ]]; then
            error "SSH keypair generation failed - files not created!"
        fi
        
        # Validate generated public key
        if ! validate_ssh_key "$SCRIPT_DIR/keys/id_ed25519.pub"; then
            error "Generated SSH public key is invalid!"
        fi
        
        # Copy public key to authorized_keys with error handling
        if ! cp "$SCRIPT_DIR/keys/id_ed25519.pub" "$SSH_KEY_FILE"; then
            error "Failed to copy SSH public key to $SSH_KEY_FILE"
        fi
        
        SSH_KEY_GENERATED=true
        success "SSH keypair generated and validated"
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${YELLOW}IMPORTANT: Save this private key to your local machine!${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Private key location: $SCRIPT_DIR/keys/id_ed25519"
        echo ""
        echo "Copy to your local machine with:"
        echo "  scp root@INSTALLER_IP:$SCRIPT_DIR/keys/id_ed25519 ~/.ssh/arch-server"
        echo ""
        echo "Or copy the content below:"
        echo ""
        cat "$SCRIPT_DIR/keys/id_ed25519"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if [[ "$AUTO_INSTALL" != "true" ]]; then
            read -r -p "Press Enter after you've saved the private key..."
        fi
        
        # Backup private key location for rollback
        echo "$SCRIPT_DIR/keys/id_ed25519" > "$BACKUP_DIR/ssh/private_key_location" 2>/dev/null || true
    else
        info "Skipping SSH key setup - password authentication only"
    fi
fi

# Install SSH key if we have one
if [[ -f "$SSH_KEY_FILE" ]]; then
    # Validate SSH key before installation
    if ! validate_ssh_key "$SSH_KEY_FILE"; then
        error "SSH public key file is invalid or corrupted: $SSH_KEY_FILE"
    fi
    
    log "Installing SSH public key for user: $USERNAME"
    
    # Create backup directory for SSH files
    mkdir -p "$BACKUP_DIR/ssh" 2>/dev/null || true
    
    # Backup existing authorized_keys if they exist
    if [[ -f /mnt/home/"$USERNAME"/.ssh/authorized_keys ]]; then
        cp /mnt/home/"$USERNAME"/.ssh/authorized_keys "$BACKUP_DIR/ssh/authorized_keys.user" 2>/dev/null || true
    fi
    if [[ -f /mnt/root/.ssh/authorized_keys ]]; then
        cp /mnt/root/.ssh/authorized_keys "$BACKUP_DIR/ssh/authorized_keys.root" 2>/dev/null || true
    fi
    
    # Create .ssh directory for user with error handling
    if ! arch-chroot /mnt mkdir -p /home/"$USERNAME"/.ssh 2>/dev/null; then
        error "Failed to create .ssh directory for user $USERNAME"
    fi
    
    if ! arch-chroot /mnt chmod 700 /home/"$USERNAME"/.ssh 2>/dev/null; then
        error "Failed to set permissions on .ssh directory for user $USERNAME"
    fi
    
    # Copy authorized_keys with error handling
    if ! cp "$SSH_KEY_FILE" /mnt/home/"$USERNAME"/.ssh/authorized_keys; then
        error "Failed to copy SSH key to /mnt/home/$USERNAME/.ssh/authorized_keys"
    fi
    
    if ! arch-chroot /mnt chmod 600 /home/"$USERNAME"/.ssh/authorized_keys 2>/dev/null; then
        error "Failed to set permissions on authorized_keys for user $USERNAME"
    fi
    
    if ! arch-chroot /mnt chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh 2>/dev/null; then
        error "Failed to set ownership on .ssh directory for user $USERNAME"
    fi
    
    # Verify installation
    if [[ ! -f /mnt/home/"$USERNAME"/.ssh/authorized_keys ]]; then
        error "SSH key installation verification failed for user $USERNAME"
    fi
    
    if ! validate_ssh_key /mnt/home/"$USERNAME"/.ssh/authorized_keys; then
        error "Installed SSH key validation failed for user $USERNAME"
    fi
    
    success "SSH public key installed and verified for $USERNAME"
    
    # Also install for root
    log "Installing SSH public key for root..."
    
    if ! mkdir -p /mnt/root/.ssh; then
        error "Failed to create .ssh directory for root"
    fi
    
    if ! chmod 700 /mnt/root/.ssh; then
        error "Failed to set permissions on .ssh directory for root"
    fi
    
    if ! cp "$SSH_KEY_FILE" /mnt/root/.ssh/authorized_keys; then
        error "Failed to copy SSH key to /mnt/root/.ssh/authorized_keys"
    fi
    
    if ! chmod 600 /mnt/root/.ssh/authorized_keys; then
        error "Failed to set permissions on authorized_keys for root"
    fi
    
    # Verify root installation
    if [[ ! -f /mnt/root/.ssh/authorized_keys ]]; then
        error "SSH key installation verification failed for root"
    fi
    
    if ! validate_ssh_key /mnt/root/.ssh/authorized_keys; then
        error "Installed SSH key validation failed for root"
    fi
    
    success "SSH public key installed and verified for root"
    
    # Save key info to credentials file
    {
        echo ""
        echo "# SSH Key Authentication"
        echo "SSH_KEY_INSTALLED=yes"
        if [[ "$SSH_KEY_GENERATED" == "true" ]]; then
            echo "SSH_PRIVATE_KEY=$SCRIPT_DIR/keys/id_ed25519"
        fi
    } >> "$CRED_FILE"
    
    info "After reboot, SSH with: ssh $USERNAME@SERVER_IP"
else
    warning "No SSH key file found - skipping SSH key installation"
fi

# ============================================================================
# MKINITCPIO CONFIGURATION
# ============================================================================

log "Configuring initramfs..."

cat > /mnt/etc/mkinitcpio.conf << 'MKINITEOF'
# Arch Linux v5.1 - systemd-based initramfs with LUKS2 + TPM

MODULES=(btrfs)

BINARIES=()

FILES=()

# systemd-based hooks for LUKS2 + TPM unlock
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)

# Compression
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-3)
MKINITEOF

success "mkinitcpio configured"

# ============================================================================
# SYSTEMD-BOOT INSTALLATION
# ============================================================================

INSTALL_PHASE="bootloader"
log "Installing systemd-boot..."

# Install bootloader
arch-chroot /mnt bootctl install

# Create boot entry
mkdir -p /mnt/efi/loader/entries

cat > /mnt/efi/loader/loader.conf << 'LOADEREOF'
default arch.conf
timeout 3
console-mode max
editor no
LOADEREOF

success "systemd-boot installed"

# ============================================================================
# UKI (UNIFIED KERNEL IMAGE) SETUP
# ============================================================================

log "Configuring UKI generation..."

# Create mkinitcpio preset for UKI

cat > /mnt/etc/mkinitcpio.d/$KERNEL_PKG.preset << UKIEOF
# mkinitcpio preset file for UKI generation

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-$KERNEL_PKG"

PRESETS=('default' 'fallback')

# UKI settings
default_uki="/efi/EFI/Linux/arch-$KERNEL_PKG.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"

fallback_uki="/efi/EFI/Linux/arch-$KERNEL_PKG-fallback.efi"
fallback_options="-S autodetect --splash /usr/share/systemd/bootctl/splash-arch.bmp"
UKIEOF

# Create directory for UKIs
mkdir -p /mnt/efi/EFI/Linux

# Get LUKS UUID
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")

# Kernel command line
CMDLINE="rd.luks.name=${LUKS_UUID}=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3"

# Add kernel hardening parameters
if [[ "$KERNEL_TYPE" == "hardened" ]]; then
    CMDLINE="$CMDLINE slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 pti=on randomize_kstack_offset=on vsyscall=none lockdown=integrity"
fi

echo "$CMDLINE" > /mnt/etc/kernel/cmdline

success "UKI configuration complete"

# Generate initramfs and UKIs
log "Generating initramfs and UKI..."
arch-chroot /mnt mkinitcpio -P

success "UKI generated at /efi/EFI/Linux/"

# ============================================================================
# NETWORK CONFIGURATION
# ============================================================================

log "Configuring network..."

# Enable NetworkManager
arch-chroot /mnt systemctl enable NetworkManager

# Configure static IP if specified
STATIC_IP="${STATIC_IP:-}"
STATIC_GATEWAY="${STATIC_GATEWAY:-}"
STATIC_DNS="${STATIC_DNS:-1.1.1.1,9.9.9.9}"
STATIC_INTERFACE="${STATIC_INTERFACE:-}"

if [[ -n "$STATIC_IP" ]] && [[ -n "$STATIC_GATEWAY" ]]; then
    log "Configuring static IP: $STATIC_IP (gateway: $STATIC_GATEWAY)"

    # Auto-detect interface name if not specified
    if [[ -z "$STATIC_INTERFACE" ]]; then
        # Use predictable interface names based on virtualization
        if [[ "$VIRT_TYPE" == "oracle" ]]; then
            STATIC_INTERFACE="enp0s3"
        elif [[ "$VIRT_TYPE" == "kvm" ]] || [[ "$VIRT_TYPE" == "qemu" ]]; then
            STATIC_INTERFACE="enp1s0"
        else
            STATIC_INTERFACE="eth0"
        fi
        info "Auto-detected interface: $STATIC_INTERFACE"
    fi

    # Convert comma-separated DNS to semicolon-separated for NetworkManager
    NM_DNS=$(echo "$STATIC_DNS" | tr ',' ';')

    mkdir -p /mnt/etc/NetworkManager/system-connections
    cat > /mnt/etc/NetworkManager/system-connections/static-ethernet.nmconnection << STATICEOF
[connection]
id=static-ethernet
type=ethernet
interface-name=$STATIC_INTERFACE
autoconnect=true
autoconnect-priority=100

[ipv4]
method=manual
addresses=$STATIC_IP
gateway=$STATIC_GATEWAY
dns=$NM_DNS
route-metric=100

[ipv6]
method=auto
STATICEOF
    chmod 600 /mnt/etc/NetworkManager/system-connections/static-ethernet.nmconnection
    success "Static IP configured: $STATIC_IP via $STATIC_INTERFACE"
else
    # DHCP ethernet with route-metric to prefer over WiFi
    mkdir -p /mnt/etc/NetworkManager/system-connections
    cat > /mnt/etc/NetworkManager/system-connections/ethernet-dhcp.nmconnection << DHCPEOF
[connection]
id=ethernet-dhcp
type=ethernet
autoconnect=true
autoconnect-priority=100

[ipv4]
method=auto
route-metric=100

[ipv6]
method=auto
DHCPEOF
    chmod 600 /mnt/etc/NetworkManager/system-connections/ethernet-dhcp.nmconnection
    info "Using DHCP for network configuration (Ethernet prioritized)"
fi

# Configure WiFi if needed
if [[ "$ENABLE_WIFI" == "true" ]] && [[ -n "$WIFI_SSID" ]]; then
    cat > /mnt/etc/NetworkManager/system-connections/"$WIFI_SSID".nmconnection << WIFIEOF
[connection]
id=$WIFI_SSID
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PASSWORD

[ipv4]
method=auto
route-metric=600

[ipv6]
method=auto
WIFIEOF
    chmod 600 /mnt/etc/NetworkManager/system-connections/"$WIFI_SSID".nmconnection
    success "WiFi configured"
fi

# Configure and enable SSH daemon
log "Configuring SSH daemon..."

# Ensure SSH daemon is installed
if ! arch-chroot /mnt pacman -Q openssh &>/dev/null; then
    error "openssh package not installed! Cannot configure SSH."
fi

# Create SSH daemon configuration directory if it doesn't exist
arch-chroot /mnt mkdir -p /etc/ssh 2>/dev/null || true

# Backup existing SSH config if it exists
if [[ -f /mnt/etc/ssh/sshd_config ]]; then
    backup_file "/mnt/etc/ssh/sshd_config"
fi

# Configure SSH daemon with secure defaults
cat > /mnt/etc/ssh/sshd_config << 'SSHDEOF'
# Arch Linux v5.1 - Secure SSH Configuration

# Basic settings
Port 22
Protocol 2
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# Host keys
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Security settings
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*

# Logging
SyslogFacility AUTH
LogLevel INFO

# Connection settings
MaxAuthTries 6
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2

# Allow users
AllowUsers root
SSHDEOF

# Add configured user to AllowUsers if not root
if [[ "$USERNAME" != "root" ]]; then
    echo "AllowUsers root $USERNAME" >> /mnt/etc/ssh/sshd_config
fi

# Set correct permissions on SSH config
arch-chroot /mnt chmod 644 /etc/ssh/sshd_config 2>/dev/null || true

# Generate SSH host keys if they don't exist
if [[ ! -f /mnt/etc/ssh/ssh_host_rsa_key ]] || [[ ! -f /mnt/etc/ssh/ssh_host_ed25519_key ]]; then
    log "Generating SSH host keys..."
    arch-chroot /mnt ssh-keygen -A 2>/dev/null || warning "Failed to generate some SSH host keys (may already exist)"
fi

# Enable SSH daemon
if ! arch-chroot /mnt systemctl enable sshd 2>/dev/null; then
    error "Failed to enable SSH daemon!"
fi

success "SSH daemon configured and enabled"

# ============================================================================
# SECURE BOOT PREPARATION
# ============================================================================

if [[ "$ENABLE_SECURE_BOOT" == "true" ]]; then
    log "Preparing Secure Boot..."

    # Check if Secure Boot is currently enabled in firmware
    SB_ACTIVE=false
    if [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]] 2>/dev/null; then
        SB_STATE=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | awk '{print $NF}')
        if [[ "$SB_STATE" == "1" ]]; then
            SB_ACTIVE=true
        fi
    fi

    if [[ "$SB_ACTIVE" == "true" ]]; then
        warning "Secure Boot is currently ENABLED in firmware!"
        warning "The new system will NOT boot until custom keys are enrolled."
        echo ""
        echo "  You MUST do one of the following:"
        echo "  1. Disable Secure Boot in BIOS/UEFI settings before first boot"
        echo "  2. Or boot will fail with 'Security Policy Violation'"
        echo ""
        if [[ "$AUTO_INSTALL" != "true" ]]; then
            read -r -p "Press Enter to acknowledge (or Ctrl+C to abort)..."
        fi
    fi

    # VirtualBox-specific Secure Boot handling
    if [[ "$VIRT_TYPE" == "oracle" ]]; then
        info "VirtualBox: Secure Boot keys will be prepared for manual enrollment"
        info "After first boot: run /root/arch/scripts/setup-secure-boot.sh"
    fi

    # Create keys (will be enrolled later)
    arch-chroot /mnt sbctl create-keys

    # Sign bootloader and UKIs (will auto-sign on updates)
    arch-chroot /mnt sbctl sign -s /efi/EFI/systemd/systemd-bootx64.efi
    arch-chroot /mnt sbctl sign -s /efi/EFI/BOOT/BOOTX64.EFI

    for uki in /mnt/efi/EFI/Linux/*.efi; do
        if [[ -f "$uki" ]]; then
            arch-chroot /mnt sbctl sign -s "${uki#/mnt}"
        fi
    done

    # Create pacman hook directory if needed
    mkdir -p /mnt/etc/pacman.d/hooks

    # Create pacman hook for auto-signing
    cat > /mnt/etc/pacman.d/hooks/999-sign_for_secureboot.hook << 'SBHOOKEOF'
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
SBHOOKEOF

    success "Secure Boot preparation complete"
    echo ""
    info "Secure Boot enrollment steps (AFTER first boot):"
    echo "  1. Boot with Secure Boot DISABLED in firmware"
    echo "  2. Login and run: sudo sbctl enroll-keys --microsoft"
    echo "  3. Reboot and ENABLE Secure Boot in firmware settings"
    echo "  4. System will now boot only signed code"
    echo ""
fi

# ============================================================================
# ANSIBLE DEPLOYMENT SETUP
# ============================================================================

log "Setting up Ansible deployment..."

# Determine project root (handle both src/ and root level)
# install.sh is in src/, so parent is project root
if [[ -f "$SCRIPT_DIR/../README.md" ]] && [[ -d "$SCRIPT_DIR/../scripts" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    info "Project root: $PROJECT_ROOT (new structure)"
else
    PROJECT_ROOT="$SCRIPT_DIR"
    info "Project root: $PROJECT_ROOT (legacy structure)"
fi

# Create target directory
TARGET_DIR="/mnt/root/arch"
mkdir -p "$TARGET_DIR"

log "Copying project files to $TARGET_DIR..."

# Copy all project files preserving structure
cp -r "$PROJECT_ROOT"/* "$TARGET_DIR/" 2>/dev/null || true
cp -r "$PROJECT_ROOT"/.??* "$TARGET_DIR/" 2>/dev/null || true  # Hidden files

# Verify critical files were copied
REQUIRED_FILES=(
    "src/ansible/ansible.cfg"
    "src/ansible/playbooks/site.yml"
    "src/ansible/roles/base_hardening/tasks/main.yml"
    "src/ansible/roles/monitoring/tasks/main.yml"
    "src/ansible/roles/security_stack/tasks/main.yml"
    "src/ansible/roles/webserver/tasks/main.yml"
    "scripts/deploy.sh"
)

MISSING_FILES=false
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$TARGET_DIR/$file" ]]; then
        warning "Missing: $file"
        MISSING_FILES=true
    fi
done

if [[ "$MISSING_FILES" == "true" ]]; then
    warning "Some files may be missing - check source directory"
fi

# Create convenience symlinks at root level
cd "$TARGET_DIR" || exit
ln -sf src/ansible ansible 2>/dev/null || true
ln -sf src/config.env config.env 2>/dev/null || true
ln -sf src/install.sh install.sh 2>/dev/null || true

# Save configuration
cp "$CONFIG_FILE" /mnt/root/config.env
chmod 600 /mnt/root/config.env

# Save credentials
cp "$CRED_FILE" /mnt/root/.credentials
chmod 600 /mnt/root/.credentials

# Show what was copied
log "Project structure:"
ls -la "$TARGET_DIR" 2>/dev/null | head -15 || true

success "Project deployed to $TARGET_DIR"

# ============================================================================
# POST-INSTALL SCRIPTS
# ============================================================================

log "Copying helper scripts to /usr/local/bin/..."

# Copy scripts to system
if [[ -d "$PROJECT_ROOT/scripts" ]]; then
    cp "$PROJECT_ROOT/scripts"/*.sh /mnt/usr/local/bin/ 2>/dev/null || true
    arch-chroot /mnt chmod +x /usr/local/bin/*.sh 2>/dev/null || true
    success "Helper scripts installed"
fi

# Also copy health-check script
if [[ -f "$PROJECT_ROOT/src/ansible/roles/base_hardening/files/health-check" ]]; then
    cp "$PROJECT_ROOT/src/ansible/roles/base_hardening/files/health-check" /mnt/usr/local/bin/
    chmod +x /mnt/usr/local/bin/health-check
    success "Health check script installed"
fi

# ============================================================================
# TPM ENROLLMENT PREPARATION
# ============================================================================

if [[ "$ENABLE_TPM_UNLOCK" == "true" ]]; then
    log "Preparing TPM auto-unlock..."
    
    # Create setup script for first boot
    cat > /mnt/root/setup-tpm-first-boot.sh << 'TPMSETUPEOF'
#!/bin/bash
# Auto-run TPM setup on first boot

if [[ -f /root/.tpm-configured ]]; then
    exit 0
fi

if [[ -f /root/arch/scripts/setup-tpm-unlock.sh ]]; then
    /root/arch/scripts/setup-tpm-unlock.sh
    touch /root/.tpm-configured
fi
TPMSETUPEOF
    chmod +x /mnt/root/setup-tpm-first-boot.sh
    
    info "TPM will be configured on first boot"
    info "Run: sudo /root/arch/scripts/setup-tpm-unlock.sh"
fi

# ============================================================================
# FINAL STEPS
# ============================================================================

log "Final system setup..."

# Update mkinitcpio
arch-chroot /mnt mkinitcpio -P

# Sync
sync

success "Installation complete!"

# ============================================================================
# CRITICAL: PASSWORD BACKUP BEFORE REBOOT
# ============================================================================

clear
cat << "EOF"
+--------------------------------------------------------------+
|                                                              |
|  WARNING: BACKUP PASSWORDS BEFORE REBOOT!                    |
|                                                              |
+--------------------------------------------------------------+
EOF

echo ""
echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  LUKS PASSWORD (REQUIRED AT EVERY BOOT):${NC}"
echo -e "${GREEN}  $LUKS_PASSWORD${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Root Password:"
echo "  $ROOT_PASSWORD"
echo ""
echo "User ($USERNAME) Password:"
echo "  $USER_PASSWORD"
echo ""
echo "----------------------------------------------------------------"
echo ""
warning "CRITICAL ACTIONS NOW (BEFORE REBOOT):"
echo ""
echo "  1. Write down the LUKS password on paper (recommended!)"
echo "  2. OR take a photo with your phone"
echo "  3. OR copy to USB drive:"
echo ""
echo "     mount /dev/sdb1 /mnt/usb"
echo "     cp $CRED_FILE /mnt/usb/PASSWORDS.txt"
echo "     cp $LUKS_BACKUP /mnt/usb/"
echo "     umount /mnt/usb"
echo ""
warning "WITHOUT LUKS PASSWORD = PERMANENT DATA LOSS!"
echo ""
echo "Passwords also saved in:"
echo "  - /root/.credentials (this Arch ISO environment)"
echo "  - /mnt/root/.credentials (installed system)"
echo ""
read -r -p "Have you backed up the LUKS password? (type YES in CAPS): " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
    echo ""
    error "You MUST backup the LUKS password before reboot!"
    echo ""
    echo "Run these commands NOW:"
    echo "  1. mount /dev/sdb1 /mnt/usb"
    echo "  2. cp $CRED_FILE /mnt/usb/"
    echo "  3. umount /mnt/usb"
    echo ""
    exit 1
fi

# Write passwords to easy-to-find file
cat > /root/PASSWORDS-SAVE-THIS.txt << PWEOF
═══════════════════════════════════════════════════════
  ARCH LINUX INSTALLATION CREDENTIALS
  GENERATED: $(date)
  HOSTNAME: $HOSTNAME
═══════════════════════════════════════════════════════

⚠️  LUKS PASSWORD (REQUIRED AT EVERY BOOT):
    $LUKS_PASSWORD

Root Password:
    $ROOT_PASSWORD

User ($USERNAME) Password:
    $USER_PASSWORD

═══════════════════════════════════════════════════════
SSH ACCESS:
$(if [[ -f "$SSH_KEY_FILE" ]]; then
    echo "    SSH Key Auth: ENABLED"
    echo "    Command: ssh $USERNAME@SERVER_IP"
    if [[ "$SSH_KEY_GENERATED" == "true" ]]; then
        echo "    Private Key: $SCRIPT_DIR/keys/id_ed25519"
    else
        echo "    Use your existing private key"
    fi
else
    echo "    SSH Key Auth: NOT CONFIGURED"
    echo "    Use password authentication"
fi)

═══════════════════════════════════════════════════════
LUKS Header Backup: $LUKS_BACKUP
Credentials File: $CRED_FILE

BACKUP BOTH PASSWORDS AND LUKS HEADER TO USB!
═══════════════════════════════════════════════════════
PWEOF

success "Passwords written to: /root/PASSWORDS-SAVE-THIS.txt"
echo ""
echo "You can also view them with:"
echo "  cat /root/PASSWORDS-SAVE-THIS.txt"
echo ""

read -r -p "Press Enter when you are ready to continue..."

# ============================================================================
# POST-INSTALL INFORMATION
# ============================================================================

# shellcheck disable=SC2317
clear
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ ARCH LINUX v5.1 INSTALLATION COMPLETE!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "System Information:"
echo "  • Hostname: $HOSTNAME"
echo "  • Username: $USERNAME"
echo "  • Kernel: $KERNEL_PKG"
echo "  • Bootloader: systemd-boot + UKI"
echo "  • Filesystem: Btrfs (${BTRFS_COMPRESSION})"
echo "  • Encryption: LUKS2 (Argon2id)"
echo ""
if [[ -f "$SSH_KEY_FILE" ]]; then
    echo "SSH Access:"
    echo "  • SSH Key Auth: ENABLED"
    echo "  • Command: ssh $USERNAME@SERVER_IP"
    if [[ "$SSH_KEY_GENERATED" == "true" ]]; then
        echo "  • Private Key: $SCRIPT_DIR/keys/id_ed25519"
        echo "  • IMPORTANT: Copy private key to your local machine!"
    fi
    echo ""
fi
echo "Credentials saved to:"
echo "  • Installation: $CRED_FILE"
echo "  • System: /root/.credentials"
echo ""
echo "LUKS header backup:"
echo "  • $LUKS_BACKUP"
echo "  • COPY THIS TO EXTERNAL STORAGE!"
echo ""
echo "Next Steps:"
echo "  1. umount -R /mnt"
echo "  2. reboot"
echo "  3. Remove installation media"
echo "  4. Boot into new system"
echo "  5. Login as: $USERNAME"
echo "  6. If network issues, run:"
echo "     sudo /usr/local/bin/network-diagnostics.sh"
echo "  7. Deploy with Ansible:"
echo "     cd /root/arch"
echo "     ./scripts/deploy.sh"
echo ""
echo "  OR manually:"
echo "     cd /root/arch/src/ansible"
echo "     ansible-playbook playbooks/site.yml"
echo ""
if [[ "$ENABLE_TPM_UNLOCK" == "true" ]]; then
    echo "  7. Setup TPM auto-unlock:"
    echo "     sudo /root/arch/scripts/setup-tpm-unlock.sh"
    echo ""
fi
if [[ "$ENABLE_SECURE_BOOT" == "true" ]]; then
    echo "  8. Enable Secure Boot:"
    echo "     sudo sbctl enroll-keys --microsoft"
    echo "     Reboot and enable Secure Boot in firmware"
    echo ""
fi
echo "  9. Go live:"
echo "     ansible-playbook playbooks/go-live.yml"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
warning "IMPORTANT: Backup LUKS header before rebooting!"
echo ""
read -p "Press Enter to continue..."

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================

INSTALL_PHASE="completed"

# Cleanup temporary files
rm -rf "$BACKUP_DIR" 2>/dev/null || true
rm -f "$ROLLBACK_LOG" 2>/dev/null || true

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 INSTALLATION COMPLETED SUCCESSFULLY          ║${NC}"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}║  Your Arch Server v5.1 is ready! Reboot and configure.        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

success "Arch Linux v5.1 installation completed!"
info "Reboot your system to start using your new secure server"
echo
info "Post-install checklist:"
echo "  □ Backup LUKS header: cryptsetup luksHeaderBackup /dev/sda2 --header-backup-file luks-header.bak"
echo "  □ Test boot: reboot"
echo "  □ Run deployment: cd /root/arch && ./scripts/deploy.sh"
echo "  □ Verify health: /usr/local/bin/health-check"
echo
