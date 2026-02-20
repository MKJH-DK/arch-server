#!/bin/bash
# Pre-deployment check script for Arch Linux v5.1
# Run this to validate the setup before deployment

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

check() {
    if eval "$1" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        ((ERRORS++))
    fi
}

warn() {
    if eval "$1" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${YELLOW}!${NC} $2 (warning)"
    fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ARCH LINUX v5.1 PRE-DEPLOYMENT CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Determine ansible directory (new or legacy structure)
if [ -d "$PROJECT_DIR/src/ansible" ]; then
    ANSIBLE_DIR="$PROJECT_DIR/src/ansible"
else
    ANSIBLE_DIR="$PROJECT_DIR/ansible"
fi

echo -e "${BLUE}[FILES]${NC}"
check "test -f $ANSIBLE_DIR/ansible.cfg" "ansible.cfg exists"
check "test -f $ANSIBLE_DIR/inventory/hosts.yml" "inventory/hosts.yml exists"
check "test -f $ANSIBLE_DIR/playbooks/site.yml" "playbooks/site.yml exists"
check "test -d $ANSIBLE_DIR/roles/base_hardening" "roles/base_hardening exists"
check "test -d $ANSIBLE_DIR/roles/webserver" "roles/webserver exists"
check "test -d $ANSIBLE_DIR/roles/security_stack" "roles/security_stack exists"
check "test -f $ANSIBLE_DIR/roles/base_hardening/files/health-check" "health-check script exists"
echo ""

echo -e "${BLUE}[SYSTEM]${NC}"
check "test -f /etc/arch-release" "Running on Arch Linux"
check "command -v systemctl" "Systemd available"
check "test $EUID -eq 0" "Running as root"
echo ""

echo -e "${BLUE}[PACKAGES]${NC}"
warn "command -v ansible-playbook" "Ansible installed"
warn "command -v python" "Python available"
warn "command -v pacman" "Pacman available"
echo ""

echo -e "${BLUE}[NETWORK]${NC}"
warn "ping -c 1 -W 2 archlinux.org" "Internet connectivity"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed - ready for deployment${NC}"
    echo ""
    echo "Run deployment with:"
    echo "  $PROJECT_DIR/scripts/deploy.sh"
    echo ""
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) found - fix before deployment${NC}"
    exit 1
fi
