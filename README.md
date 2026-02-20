# Arch Server

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)

**Secure Arch Linux server deployment with full disk encryption and hardened security.**

## Features

- **LUKS2 Encryption** - Full disk encryption with Argon2id + TPM auto-unlock
- **systemd-boot + UKI** - Modern bootloader with Unified Kernel Images
- **Btrfs Snapshots** - Automatic rollback on failed updates
- **Defense-in-Depth** - nftables + AppArmor + auditd + hardened kernel
- **Cloudflare Ready** - Firewall with Cloudflare-only mode
- **Podman Containers** - Rootless container runtime
- **Caddy Web Server** - Automatic HTTPS with HTTP/3, multi-domain support
- **Dual Network** - Ethernet + WiFi with automatic failover

## Requirements

- UEFI-capable system
- 2GB+ RAM (4GB recommended)
- 20GB+ storage
- Internet connection

## Quick Start

### 1. Prepare SSH Key (Recommended)

```bash
# Copy to project root (installer auto-discovers keys)
cp ~/.ssh/id_ed25519.pub authorized_keys.pub
```

### 2. Setup Configuration

Boot from Arch ISO and run:

```bash
# Download project
curl -L https://github.com/humethix/arch-server/archive/main.tar.gz | tar xz
cd arch-server-main

# Choose configuration level
chmod +x src/config-setup.sh
./src/config-setup.sh

# Run installer
chmod +x src/install.sh
./src/install.sh
```

### 3. Deploy Server (After Reboot)

```bash
sudo -i
cd /root/arch
./scripts/deploy.sh
```

### 4. Setup Cloudflare Tunnel

```bash
./scripts/setup-cloudflare.sh
```

### 5. Verify

```bash
/usr/local/bin/health-check
```

## Project Structure

```
arch-server/
├── src/                       # Core installation files
│   ├── install.sh             # Main installer (run from Arch ISO)
│   ├── config.env.basic       # Basic configuration template
│   ├── config.env.advanced    # Advanced configuration template
│   ├── config-setup.sh        # Interactive config wizard
│   ├── config-validate.sh     # Config validator
│   └── ansible/               # Ansible automation
│       ├── playbooks/
│       │   ├── site.yml       # Main deployment playbook
│       │   └── go-live.yml    # Production verification
│       └── roles/
│           ├── base_hardening/
│           ├── security_stack/
│           ├── webserver/
│           ├── cloudflare/
│           ├── container_runtime/
│           ├── monitoring/
│           └── safe_updates/
├── scripts/                   # Post-install utilities
│   ├── deploy.sh              # Master deployment script
│   ├── setup-cloudflare.sh    # Cloudflare Tunnel setup
│   ├── setup-secure-boot.sh   # Secure Boot enrollment
│   ├── setup-tpm-unlock.sh    # TPM auto-unlock setup
│   └── verify-deployment.sh   # Deployment verification
├── docs/                      # Documentation
├── ADDON-INTEGRATION.md       # Addon integration guide
├── CHANGELOG.md               # Version history
├── LICENSE                    # MIT License
└── README.md
```

## Configuration

### Quick Setup (Recommended)

```bash
./src/config-setup.sh
```

Choose from:
- **Basic**: Essential settings only
- **Advanced**: Full configuration with all security options
- **Custom**: Start basic, add advanced options as needed

### Essential Settings

```bash
HOSTNAME="your-server-name"
USERNAME="your-username"
TIMEZONE="Europe/Copenhagen"

# Passwords (leave empty for auto-generation)
ROOT_PASSWORD=""
USER_PASSWORD=""
LUKS_PASSWORD=""

# Optional
SSH_KEY_FILE="authorized_keys.pub"
DOMAIN="yourdomain.com"         # Single domain
DOMAINS=""                       # Multiple: "a.com,b.com,c.com"
```

### Multi-Domain Setup

Serve multiple domains from one server with automatic HTTPS:

```bash
# Option 1: Environment variable (comma-separated)
DOMAINS="example.com,blog.example.com,shop.example.com:/srv/shop"

# Option 2: Ansible inventory (hosts.yml)
domains:
  - { domain: "example.com" }
  - { domain: "blog.example.com", root: "/srv/blog" }
  - { domain: "shop.example.com", root: "/srv/shop" }
```

Each domain gets its own HTTPS certificate (via Let's Encrypt), log file, and optional web root. Default web root is `/srv/www/`. The Cloudflare tunnel script also supports multiple domains.

## Network

The server supports both Ethernet and WiFi simultaneously:

- **Ethernet** is always preferred (route-metric 100)
- **WiFi** serves as automatic fallback (route-metric 600)

Configure WiFi in `config.env`:

```bash
ENABLE_WIFI=true
WIFI_SSID="your-network"
WIFI_PASSWORD="your-password"
```

## Security

| Feature | Description |
|---------|-------------|
| **LUKS2** | AES-XTS-512 with Argon2id KDF |
| **Secure Boot** | Custom keys with sbctl |
| **Firewall** | nftables with Cloudflare-only mode |
| **SSH** | Key-based auth, rate limiting |
| **AppArmor** | Mandatory access control |
| **Auditd** | Security event logging |
| **Snapshots** | Btrfs snapshots with Snapper |

## Ansible Roles

| Role | Description |
|------|-------------|
| `base_hardening` | Sysctl, SSH, kernel module hardening |
| `security_stack` | nftables, AppArmor, auditd |
| `container_runtime` | Podman with rootless support |
| `cloudflare` | Cloudflare IP allowlisting |
| `webserver` | Caddy web server (official package) |
| `monitoring` | htop, sysstat, journald, Node Exporter |
| `safe_updates` | Snapper Btrfs snapshots |

## Addon Integration

This project is designed as a base that can be extended with a separate addon repository.
See [ADDON-INTEGRATION.md](ADDON-INTEGRATION.md) for details on:

- How to add Caddy configs via `/etc/caddy/conf.d/`
- Directory conventions for addon data
- Example addons (Obsidian web, Backblaze backup)

## Documentation

- [Installation Guide](docs/installation.md)
- [Configuration Reference](docs/configuration.md)
- [Deployment Guide](docs/deployment.md)
- [Security Guide](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

MIT License - Copyright (c) 2026 Mike Holmsted (Humethix)

See [LICENSE](LICENSE) for details.
