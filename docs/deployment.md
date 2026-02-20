# Deployment Guide

After installation and reboot, follow these steps to deploy your server.

## Step 1: Login

```bash
# Enter LUKS password at boot
# Login as your configured user
ssh admin@SERVER_IP
```

## Step 2: Run Deployment

```bash
sudo -i
cd /root/arch
./scripts/deploy.sh
```

This will:
- Install Ansible collections
- Run all configuration roles
- Setup web server
- Configure firewall
- Enable snapshots

## Step 3: Verify

```bash
/usr/local/bin/health-check
```

Expected output:
```
✓ Caddy web server
✓ nftables firewall
✓ Snapper timeline
✓ SSH daemon
Score: 95%
```

## Step 4: Setup Cloudflare Tunnel

```bash
./scripts/setup-cloudflare.sh
```

Follow prompts to:
1. Login to Cloudflare
2. Create tunnel
3. Configure domain

## Access Your Server

- **Local**: `http://SERVER_IP`
- **Public**: `https://your-domain.com`

## Troubleshooting

### Caddy not starting
```bash
systemctl status caddy
journalctl -u caddy -n 50
```

### Firewall issues
```bash
nft list ruleset
```

### Snapshot problems
```bash
snapper list-configs
snapper list
```
