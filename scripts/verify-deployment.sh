#!/bin/bash
# Deployment Verification Script for Arch Linux v5.1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
TOTAL=0

check() {
    ((TOTAL++))
    if eval "$1" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $2"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $2"
        ((FAILED++))
    fi
}

warn_check() {
    ((TOTAL++))
    if eval "$1" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $2"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} $2 (optional)"
        ((PASSED++))  # Don't count optional as failed
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   ARCH LINUX v5.1 DEPLOYMENT VERIFICATION            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

echo -e "${BLUE}[SYSTEM]${NC}"
check "test -f /etc/arch-release" "Arch Linux"
check "command -v systemctl" "Systemd"
check "mount | grep -q btrfs" "Btrfs filesystem"
check "lsblk -o TYPE | grep -q crypt" "LUKS encryption"
echo ""

echo -e "${BLUE}[SERVICES]${NC}"
check "systemctl is-active caddy" "Caddy web server"
check "nft list ruleset 2>/dev/null | grep -q table" "nftables firewall"
check "systemctl is-active sshd" "SSH daemon"
warn_check "systemctl is-active apparmor" "AppArmor"
warn_check "systemctl is-active auditd" "Audit daemon"
warn_check "systemctl is-active snapper-timeline.timer" "Snapper timeline"
warn_check "systemctl is-active snapper-cleanup.timer" "Snapper cleanup"
echo ""

echo -e "${BLUE}[NETWORK]${NC}"
check "ss -tlnp | grep -q ':80 '" "Port 80 listening"
check "curl -sf -o /dev/null http://localhost/" "Web server responding"
check "ping -c 1 -W 2 1.1.1.1" "Internet connectivity"
echo ""

echo -e "${BLUE}[CONTAINERS]${NC}"
check "command -v podman" "Podman installed"
warn_check "podman info" "Podman accessible"
echo ""

echo -e "${BLUE}[SNAPSHOTS]${NC}"
check "command -v snapper" "Snapper installed"
warn_check "snapper list" "Snapper configured"
echo ""

echo -e "${BLUE}[CLOUDFLARE TUNNEL]${NC}"
if command -v cloudflared &>/dev/null; then
    check "command -v cloudflared" "Cloudflared installed"
    warn_check "systemctl is-active cloudflared" "Cloudflared service"
    warn_check "cloudflared tunnel list | grep -q archserver" "Tunnel exists"
else
    echo -e "${YELLOW}!${NC} Cloudflared not installed (run /root/arch/scripts/setup-cloudflare.sh)"
fi
echo ""

# Summary
SCORE=$((PASSED * 100 / TOTAL))

echo "╔══════════════════════════════════════════════════════╗"
echo "║   VERIFICATION SUMMARY                               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo -e "  Passed: ${GREEN}${PASSED}${NC}/${TOTAL}"
echo -e "  Score:  ${GREEN}${SCORE}%${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "  ${GREEN}✓ All checks passed - system is ready!${NC}"
else
    echo -e "  ${RED}✗ Some checks failed - review above${NC}"
fi
echo ""

# Show next steps
if ! command -v cloudflared &>/dev/null; then
    echo -e "${BLUE}[NEXT STEPS]${NC}"
    echo "  1. Setup Cloudflare Tunnel:"
    echo "     /root/arch/scripts/setup-cloudflare.sh"
    echo ""
    echo "  2. Run health check:"
    echo "     /usr/local/bin/health-check"
    echo ""
fi

exit $FAILED
