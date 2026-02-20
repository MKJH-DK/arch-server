# Arch Server v5.1

Welcome to the Arch Server documentation!

**Arch Server** is an automated deployment system for secure Arch Linux servers featuring full disk encryption, modern bootloader, and comprehensive security hardening.

## Features

- 🔒 **LUKS2 Encryption** - Full disk encryption with Argon2id
- 🚀 **systemd-boot + UKI** - Modern bootloader with Unified Kernel Images
- 📁 **Btrfs Snapshots** - Automatic rollback capability
- 🛡️ **Security Hardening** - nftables, AppArmor, auditd
- 🌐 **Cloudflare Integration** - Zero-trust tunnel access
- 📦 **Containers** - Podman with rootless support

## Quick Start

1. [Installation Guide](installation.md)
2. [Configuration](configuration.md)
3. [Deployment](deployment.md)
4. [Security](security.md)

## Troubleshooting

- [Common Issues & Solutions](troubleshooting.md)
- Run diagnostics: `sudo /usr/local/bin/health-check`

## Requirements

- UEFI-capable system
- 2GB+ RAM
- 20GB+ storage
- Internet connection

## License

MIT License - Copyright (c) 2026 Mike Holmsted (Humethix)
