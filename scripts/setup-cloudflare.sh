#!/bin/bash
# Cloudflare Tunnel Setup Script for Arch Linux v5.1
# Supports single and multiple domains
# Run this AFTER Ansible deployment completes

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

clear
cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║           CLOUDFLARE TUNNEL SETUP                        ║
║           Arch Linux v5.1 - Multi-Domain                 ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Step 1: Install cloudflared
log "Step 1: Installing cloudflared..."

if command -v cloudflared &>/dev/null; then
    log "✓ Cloudflared already installed"
    cloudflared --version
else
    cd /tmp

    # Download latest cloudflared
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) CF_ARCH="amd64" ;;
        aarch64) CF_ARCH="arm64" ;;
        armv7l) CF_ARCH="arm" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    log "Downloading cloudflared for $CF_ARCH..."
    wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -O cloudflared

    chmod +x cloudflared
    mv cloudflared /usr/local/bin/

    log "✓ Cloudflared installed"
    cloudflared --version
fi

# Step 2: Login to Cloudflare
log ""
log "Step 2: Login to Cloudflare"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "This will open a browser window (or display a URL)"
info "Login with your Cloudflare account and authorize the tunnel"
echo ""
read -r -p "Press Enter to continue..."

cloudflared tunnel login

# Check if login succeeded
if [ ! -f ~/.cloudflared/cert.pem ]; then
    error "Login failed - cert.pem not found"
fi

log "✓ Logged in successfully"

# Step 3: Create tunnel
log ""
log "Step 3: Creating tunnel..."

TUNNEL_NAME="archserver-$(uname -n)"

# Check if tunnel exists
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    warn "Tunnel '$TUNNEL_NAME' already exists"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
else
    cloudflared tunnel create "$TUNNEL_NAME"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
fi

if [ -z "$TUNNEL_ID" ]; then
    error "Failed to get tunnel ID"
fi

log "✓ Tunnel ID: $TUNNEL_ID"

# Step 4: Domain configuration (supports multiple domains)
log ""
log "Step 4: Domain configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "You can configure one or multiple domains for this tunnel."
info "Each domain will be routed to the local Caddy web server."
echo ""

DOMAINS=()

# Check for domains from environment/config
if [ -n "${DOMAINS_ENV:-}" ]; then
    IFS=',' read -ra DOMAINS <<< "$DOMAINS_ENV"
    log "Using domains from environment: ${DOMAINS[*]}"
elif [ -n "${DOMAIN:-}" ]; then
    DOMAINS=("$DOMAIN")
    log "Using single domain from environment: $DOMAIN"
fi

# Interactive domain input if no domains configured
if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo -e "${BOLD}Enter your domain(s). Press Enter with empty input when done.${NC}"
    echo "Examples: example.com, blog.example.com, shop.example.com"
    echo ""

    while true; do
        read -r -p "Domain (empty to finish): " input_domain
        input_domain=$(echo "$input_domain" | xargs)  # trim whitespace

        if [ -z "$input_domain" ]; then
            break
        fi
        # Split by comma to support multiple domains on one line
        IFS=',' read -ra input_parts <<< "$input_domain"
        for part in "${input_parts[@]}"; do
            part=$(echo "$part" | xargs)  # trim whitespace
            if [ -n "$part" ]; then
                DOMAINS+=("$part")
                log "  Added: $part"
            fi
        done
    done
fi

if [ ${#DOMAINS[@]} -eq 0 ]; then
    warn "No domains specified - configuring tunnel-only mode"
fi

# Step 5: Create config
log ""
log "Step 5: Creating configuration..."

mkdir -p /etc/cloudflared

{
    echo "tunnel: $TUNNEL_ID"
    echo "credentials-file: /root/.cloudflared/${TUNNEL_ID}.json"
    echo ""
    echo "ingress:"

    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        if [ -n "$domain" ]; then
            echo "  - hostname: $domain"
            echo "    service: http://localhost:80"
        fi
    done

    # Catch-all rule (required by cloudflared)
    echo "  - service: http_status:404"
} > /etc/cloudflared/config.yml

# Copy credentials
cp /root/.cloudflared/"${TUNNEL_ID}".json /etc/cloudflared/ 2>/dev/null || true

log "✓ Configuration created at /etc/cloudflared/config.yml"

# Show generated config
echo ""
info "Generated ingress rules:"
grep -A 100 "^ingress:" /etc/cloudflared/config.yml | head -30

# Step 6: Route DNS for all domains
if [ ${#DOMAINS[@]} -gt 0 ]; then
    log ""
    log "Step 6: Routing DNS for ${#DOMAINS[@]} domain(s)..."

    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)
        if [ -n "$domain" ]; then
            if cloudflared tunnel route dns "$TUNNEL_NAME" "$domain" 2>/dev/null; then
                log "  ✓ DNS routed: $domain → $TUNNEL_NAME"
            else
                warn "  DNS routing failed for $domain - configure manually in Cloudflare dashboard"
            fi
        fi
    done
fi

# Step 7: Create systemd service
log ""
log "Step 7: Creating systemd service..."

cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/etc/cloudflared

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared
systemctl start cloudflared

log "✓ Service created and started"

# Step 8: Verify
log ""
log "Step 8: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sleep 3

if systemctl is-active cloudflared &>/dev/null; then
    log "✓ Cloudflared service is running"
else
    warn "Cloudflared service not running - check logs"
    journalctl -u cloudflared -n 20 --no-pager
fi

# Summary
cat << EOF

╔══════════════════════════════════════════════════════════╗
║                                                          ║
║         ✓ CLOUDFLARE TUNNEL SETUP COMPLETE!              ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

Tunnel Name: $TUNNEL_NAME
Tunnel ID:   $TUNNEL_ID
EOF

if [ ${#DOMAINS[@]} -gt 0 ]; then
    echo ""
    echo "Your server is now accessible at:"
    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)
        [ -n "$domain" ] && echo "  🌐 https://$domain"
    done
    echo ""
    echo "DNS propagation may take 2-5 minutes."
else
    echo ""
    echo "Your tunnel URL (from Cloudflare dashboard):"
    echo "  cloudflared tunnel info $TUNNEL_NAME"
fi

echo "
Useful commands:
  • Status:  systemctl status cloudflared
  • Logs:    journalctl -u cloudflared -f
  • Info:    cloudflared tunnel info $TUNNEL_NAME
  • List:    cloudflared tunnel list
  • Config:  cat /etc/cloudflared/config.yml

To add more domains later:
  1. Edit /etc/cloudflared/config.yml (add ingress rules)
  2. Route DNS: cloudflared tunnel route dns $TUNNEL_NAME new.example.com
  3. Restart:   systemctl restart cloudflared
"
