#!/bin/bash
# Master Deployment Script for Arch Linux v5.1
# Run this after install.sh and reboot

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Recovery function for common issues
recover_service() {
    local service="$1"
    local description="$2"

    # Check if the service unit exists before attempting recovery
    if ! systemctl list-unit-files "${service}.service" 2>/dev/null | grep -q "${service}"; then
        warn "⚠ $description is not installed (service unit not found) - skipping recovery"
        return 1
    fi

    info "Attempting to recover $description..."

    # Try to restart the service
    if systemctl restart "$service" 2>/dev/null; then
        sleep 2
        if systemctl is-active "$service" &>/dev/null; then
            log "✓ Successfully recovered $description"
            return 0
        fi
    fi

    # If restart didn't work, try reload/reload-or-restart
    if systemctl reload-or-restart "$service" 2>/dev/null; then
        sleep 2
        if systemctl is-active "$service" &>/dev/null; then
            log "✓ Successfully recovered $description (reload)"
            return 0
        fi
    fi

    warn "⚠ Could not recover $description automatically"
    return 1
}

clear
cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     ARCH LINUX v5.1 - DEPLOYMENT SCRIPT                  ║
║                                                          ║
║     This will configure your server with:                ║
║     • Security hardening                                 ║
║     • Caddy web server                                   ║
║     • nftables firewall                                  ║
║     • Btrfs snapshots                                    ║
║     • Container runtime                                  ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Find project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$PROJECT_DIR/src/ansible" ]; then
    # Try common locations
    for try_dir in "/root/arch" "/root/arch-v5.1" "$(pwd)"; do
        if [ -d "$try_dir/src/ansible" ]; then
            PROJECT_DIR="$try_dir"
            break
        elif [ -d "$try_dir/ansible" ]; then
            PROJECT_DIR="$try_dir"
            ANSIBLE_DIR="$PROJECT_DIR/ansible"
            break
        fi
    done
    
    if [ ! -d "$PROJECT_DIR/src/ansible" ] && [ ! -d "${ANSIBLE_DIR:-}" ]; then
        error "Cannot find ansible directory. Run from project root or /root/arch"
    fi
fi

# Set ansible directory
ANSIBLE_DIR="${ANSIBLE_DIR:-$PROJECT_DIR/src/ansible}"

log "Project directory: $PROJECT_DIR"

# Phase 1: Prerequisites
log ""
log "Phase 1: Checking prerequisites..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for git and base-devel (required for AUR/paru builds)
if ! command -v git &>/dev/null || ! pacman -Qq base-devel &>/dev/null 2>&1; then
    log "Installing git and base-devel (required for AUR packages)..."
    pacman -Sy --noconfirm --needed git base-devel
fi
log "✓ Build tools installed (git, base-devel)"

# Check for ansible
if ! command -v ansible-playbook &>/dev/null; then
    log "Installing Ansible..."
    pacman -Sy --noconfirm --needed ansible python
fi
log "✓ Ansible installed"

# Install ansible collection
log "Installing Ansible community.general collection..."
ansible-galaxy collection install community.general --force 2>/dev/null || true
log "✓ Ansible collections installed"

# Phase 2: Run Ansible
log ""
log "Phase 2: Running Ansible deployment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$ANSIBLE_DIR"

# Fix locale: fresh Arch installs often have LANG set to a locale that hasn't
# been generated yet, which causes Python/Ansible to abort with
# "could not initialize the preferred locale" or "locale encoding must be UTF-8".
# C.UTF-8 is a built-in glibc locale (no locale-gen required) that satisfies
# Ansible's UTF-8 encoding requirement on any system with glibc >= 2.26.
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Run playbook
log "Executing site.yml playbook..."
echo ""

# Run with more verbose output and error capture
if ansible-playbook playbooks/site.yml -v; then
    log "✓ Ansible deployment complete"
else
    warn "Ansible had some issues - checking what failed"
    
    # Get detailed error information
    echo ""
    info "Checking Ansible logs..."
    
    # Check for common issues
    if systemctl is-active caddy &>/dev/null; then
        log "✓ Caddy service is running"
    else
        warn "⚠ Caddy service is not running"
        info "Caddy service status:"
        systemctl status caddy --no-pager -l || true
        echo ""
        
        # Try to recover Caddy
        if recover_service "caddy" "Caddy web server"; then
            log "✓ Caddy recovery successful"
        else
            info "Caddy journal logs:"
            journalctl -u caddy --no-pager -n 10 || true
            echo ""
        fi
    fi
    
    # nftables is a oneshot service - check if rules are loaded instead
    if nft list ruleset 2>/dev/null | grep -q "table"; then
        log "✓ Firewall rules are loaded"
    else
        warn "⚠ Firewall rules not loaded"
        info "nftables status:"
        systemctl status nftables --no-pager -l || true
        echo ""
        
        # Try to recover nftables
        info "Attempting to load nftables rules manually..."
        if nft -f /etc/nftables.conf 2>/dev/null; then
            log "✓ nftables rules loaded successfully"
        else
            warn "⚠ Failed to load nftables rules"
            info "nftables journal logs:"
            journalctl -u nftables --no-pager -n 10 || true
            echo ""
        fi
    fi
    
    # Check other critical services
    for service in apparmor auditd; do
        if systemctl is-active "$service" &>/dev/null; then
            log "✓ $service service is running"
        elif [[ "$service" == "apparmor" ]] && systemctl show -p ConditionResult apparmor 2>/dev/null | grep -q "no"; then
            warn "⚠ AppArmor: kernel LSM parameter not set — reboot required for 'lsm=...apparmor...' to take effect"
        else
            warn "⚠ $service service is not running"
            systemctl status "$service" --no-pager -l || true
            echo ""

            # Try to recover the service
            recover_service "$service" "$service security service"
        fi
    done
    
    warn "Continuing with verification..."
fi

# Phase 3: Verification
log ""
log "Phase 3: Verifying deployment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify key programs are installed after Ansible
info "Verifying installed programs..."
MISSING_PROGRAMS=()
declare -A PROG_CHECKS=(
    ["caddy"]="caddy"
    ["nft"]="nft"
    ["auditctl"]="auditctl"
    ["apparmor_status"]="apparmor_status"
    ["podman"]="podman"
    ["snapper"]="snapper"
    ["paru"]="paru"
)
for cmd in "${!PROG_CHECKS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        log "✓ ${PROG_CHECKS[$cmd]} installed"
    else
        warn "⚠ ${PROG_CHECKS[$cmd]} not found"
        MISSING_PROGRAMS+=("${PROG_CHECKS[$cmd]}")
    fi
done
# CrowdSec uses cscli as its CLI tool
if command -v cscli &>/dev/null; then
    log "✓ crowdsec (cscli) installed"
else
    warn "⚠ crowdsec (cscli) not found"
    MISSING_PROGRAMS+=("crowdsec")
fi
if [ ${#MISSING_PROGRAMS[@]} -gt 0 ]; then
    warn "Missing programs after deployment: ${MISSING_PROGRAMS[*]}"
    warn "Try re-running: ansible-playbook $ANSIBLE_DIR/playbooks/site.yml -v"
fi
echo ""

# Run health check if available
if [ -x /usr/local/bin/health-check ]; then
    /usr/local/bin/health-check || true
else
    # Basic checks
    info "Running basic verification..."

    if systemctl is-active caddy &>/dev/null; then
        log "✓ Caddy web server running"
    else
        warn "Caddy not running"
    fi

    # nftables is a oneshot service - check if rules are loaded instead
    if nft list ruleset 2>/dev/null | grep -q "table"; then
        log "✓ Firewall active (nftables rules loaded)"
    else
        warn "Firewall rules not loaded"
    fi

    if curl -sf http://localhost/ &>/dev/null; then
        log "✓ Web server responding"
    else
        warn "Web server not responding"
    fi
fi

# Phase 4: Summary
log ""
log "Phase 4: Deployment Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get IP
IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

cat << EOF

╔══════════════════════════════════════════════════════════╗
║                                                          ║
║         ✓ DEPLOYMENT COMPLETE!                           ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

Server Information:
  • IP Address: ${IP:-N/A}
  • Web: http://${IP:-localhost}

Services Status:
  • Caddy:    $(systemctl is-active caddy 2>/dev/null || echo 'inactive')
  • nftables: $(nft list ruleset 2>/dev/null | grep -q "table" && echo 'rules loaded' || echo 'no rules')
  • SSH:      $(systemctl is-active sshd 2>/dev/null || echo 'inactive')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NEXT STEPS:

  1. Setup Cloudflare Tunnel (for public access):
     $PROJECT_DIR/scripts/setup-cloudflare.sh

  2. Verify deployment:
     /usr/local/bin/health-check

  3. View web server:
     curl http://localhost/

  4. Check logs:
     journalctl -u caddy -f

EOF
