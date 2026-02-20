#!/bin/bash
# ============================================================================
# NETWORK DIAGNOSTICS v5.1
# Post-reboot network troubleshooting and repair
# ============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}>>${NC} $1"; }
success() { echo -e "${GREEN}OK${NC} $1"; }
warning() { echo -e "${YELLOW}!!${NC} $1"; }
error_msg() { echo -e "${RED}FAIL${NC} $1"; }
info() { echo -e "${CYAN}--${NC} $1"; }

cat << "EOF"
+--------------------------------------------------------------+
|   NETWORK DIAGNOSTICS v5.1                                    |
|   Post-reboot network troubleshooting                         |
+--------------------------------------------------------------+
EOF

echo ""
ISSUES_FOUND=0
FIXES_APPLIED=0

# ============================================================================
# 1. Check NetworkManager status
# ============================================================================

log "Checking NetworkManager..."

if systemctl is-active --quiet NetworkManager; then
    success "NetworkManager is running"
else
    error_msg "NetworkManager is NOT running"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    log "Attempting to start NetworkManager..."
    if systemctl start NetworkManager; then
        success "NetworkManager started"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        sleep 3
    else
        error_msg "Failed to start NetworkManager"
        info "Try: systemctl enable --now NetworkManager"
    fi
fi

# ============================================================================
# 2. Check network interfaces
# ============================================================================

log "Checking network interfaces..."

INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$")

if [[ -z "$INTERFACES" ]]; then
    error_msg "No network interfaces found (other than loopback)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo ""
    for iface in $INTERFACES; do
        STATE=$(ip -o link show "$iface" | grep -oP 'state \K\w+')
        IP=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -1)

        if [[ "$STATE" == "UP" ]] && [[ -n "$IP" ]]; then
            success "  $iface: $STATE - IP: $IP"
        elif [[ "$STATE" == "UP" ]]; then
            warning "  $iface: $STATE - No IP address"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            warning "  $iface: $STATE (down)"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    done
    echo ""
fi

# ============================================================================
# 3. Check for IP address (DHCP or static)
# ============================================================================

log "Checking IP configuration..."

HAS_IP=false
DEFAULT_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')

if [[ -n "$DEFAULT_IP" ]]; then
    success "Default route IP: $DEFAULT_IP"
    HAS_IP=true
else
    error_msg "No default route - no internet connectivity"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    # Try to bring up interfaces
    log "Attempting to activate connections..."
    for conn in $(nmcli -t -f NAME con show 2>/dev/null); do
        info "  Activating: $conn"
        nmcli con up "$conn" 2>/dev/null && FIXES_APPLIED=$((FIXES_APPLIED + 1))
    done

    # Wait and re-check
    sleep 5
    DEFAULT_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')
    if [[ -n "$DEFAULT_IP" ]]; then
        success "Network recovered! IP: $DEFAULT_IP"
        HAS_IP=true
    fi
fi

# ============================================================================
# 4. Check DNS resolution
# ============================================================================

log "Checking DNS resolution..."

if [[ "$HAS_IP" == "true" ]]; then
    if host archlinux.org &>/dev/null || nslookup archlinux.org &>/dev/null 2>&1; then
        success "DNS resolution working"
    else
        error_msg "DNS resolution failed"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))

        # Try to fix DNS
        log "Attempting DNS fix..."
        if [[ -f /etc/resolv.conf ]]; then
            if ! grep -q "nameserver" /etc/resolv.conf; then
                echo "nameserver 1.1.1.1" >> /etc/resolv.conf
                echo "nameserver 9.9.9.9" >> /etc/resolv.conf
                success "Added fallback DNS servers"
                FIXES_APPLIED=$((FIXES_APPLIED + 1))
            fi
        fi
    fi
fi

# ============================================================================
# 5. Check internet connectivity
# ============================================================================

log "Checking internet connectivity..."

if [[ "$HAS_IP" == "true" ]]; then
    if ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
        success "Internet connectivity OK (ping 1.1.1.1)"
    else
        error_msg "Cannot reach internet (ping 1.1.1.1 failed)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))

        # Check if firewall is blocking
        if systemctl is-active --quiet nftables; then
            warning "nftables firewall is active - may be blocking outbound traffic"
            info "Try: nft list ruleset | grep -i drop"
        fi
    fi
fi

# ============================================================================
# 6. Check SSH service
# ============================================================================

log "Checking SSH service..."

if systemctl is-active --quiet sshd; then
    SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | grep -oP ':\K\d+' | head -1)
    success "SSH running on port ${SSH_PORT:-22}"
else
    error_msg "SSH service is NOT running"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    log "Attempting to start SSH..."
    if systemctl start sshd; then
        success "SSH started"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
    fi
fi

# ============================================================================
# 7. Check firewall status
# ============================================================================

log "Checking firewall..."

if systemctl is-active --quiet nftables; then
    RULE_COUNT=$(nft list ruleset 2>/dev/null | grep -c "accept\|drop\|reject" || echo "0")
    info "nftables active ($RULE_COUNT rules)"

    # Check if SSH is allowed
    if nft list ruleset 2>/dev/null | grep -q "tcp dport 22 accept\|ssh"; then
        success "SSH allowed through firewall"
    else
        warning "SSH may not be allowed through firewall"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    info "Firewall (nftables) not active"
fi

# ============================================================================
# 8. VirtualBox-specific checks
# ============================================================================

VIRT_TYPE="none"
if command -v systemd-detect-virt &>/dev/null; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
fi

if [[ "$VIRT_TYPE" == "oracle" ]]; then
    echo ""
    log "VirtualBox-specific diagnostics..."

    # Check adapter type
    if ip link show | grep -q "enp0s3"; then
        success "VirtualBox NAT adapter detected (enp0s3)"
    elif ip link show | grep -q "enp0s8"; then
        info "VirtualBox Host-Only adapter detected (enp0s8)"
    fi

    # Check if guest additions networking is working
    if lsmod | grep -q "vboxguest"; then
        success "VirtualBox Guest Additions loaded"
    else
        warning "VirtualBox Guest Additions not loaded"
        info "Install with: pacman -S virtualbox-guest-utils"
    fi

    echo ""
    info "VirtualBox network tips:"
    echo "    - NAT: Guest can access internet, host cannot reach guest"
    echo "    - Bridged: Guest gets IP on same network as host"
    echo "    - Host-Only: Guest and host can communicate, no internet"
    echo "    - NAT + Port Forward: Add rule for port 22 to SSH from host"
fi

# ============================================================================
# 9. Quick fix attempts
# ============================================================================

if [[ "$ISSUES_FOUND" -gt 0 ]] && [[ "$HAS_IP" != "true" ]]; then
    echo ""
    log "Attempting automatic fixes..."

    # Try DHCP request
    for iface in $INTERFACES; do
        STATE=$(ip -o link show "$iface" | grep -oP 'state \K\w+')
        if [[ "$STATE" != "UP" ]]; then
            ip link set "$iface" up 2>/dev/null
        fi
    done

    # Restart NetworkManager
    systemctl restart NetworkManager 2>/dev/null
    sleep 5

    # Re-check
    DEFAULT_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')
    if [[ -n "$DEFAULT_IP" ]]; then
        success "Network recovered after fixes! IP: $DEFAULT_IP"
        HAS_IP=true
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "================================================================"
echo "  NETWORK DIAGNOSTICS SUMMARY"
echo "================================================================"
echo ""

if [[ "$ISSUES_FOUND" -eq 0 ]]; then
    echo -e "  ${GREEN}All checks passed - network is healthy${NC}"
else
    echo -e "  ${YELLOW}Issues found: $ISSUES_FOUND${NC}"
    echo -e "  ${GREEN}Fixes applied: $FIXES_APPLIED${NC}"
fi

echo ""

if [[ "$HAS_IP" == "true" ]]; then
    echo "  Status: ONLINE"
    echo "  IP: $DEFAULT_IP"
    echo ""
    echo "  SSH access: ssh $(whoami)@$DEFAULT_IP"
else
    echo -e "  ${RED}Status: OFFLINE${NC}"
    echo ""
    echo "  Manual recovery steps:"
    echo "    1. Check cable/adapter: ip link"
    echo "    2. Restart network: systemctl restart NetworkManager"
    echo "    3. Manual DHCP: nmcli device connect enp0s3"
    echo "    4. Static IP: nmcli con add type ethernet ifname enp0s3 \\"
    echo "         ipv4.addresses 192.168.1.100/24 \\"
    echo "         ipv4.gateway 192.168.1.1 \\"
    echo "         ipv4.dns '1.1.1.1' ipv4.method manual"
fi

echo ""
echo "================================================================"

exit $ISSUES_FOUND
