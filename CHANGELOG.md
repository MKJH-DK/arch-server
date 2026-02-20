# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- SSH key authentication support with auto-generation option
- Health check script for system verification
- Pre-deployment validation script
- Interactive configuration setup (config-setup.sh)
- Split configuration into basic/advanced templates
- Configuration validation script (config-validate.sh)
- Integration tests for end-to-end functionality
- Enhanced health check with TPM, Secure Boot, performance metrics
- Improved user experience for configuration
- Automatic SSH key discovery from ~/.ssh/

### Security
- Enhanced health checks for advanced security features

### Monitoring
- Added Prometheus Node Exporter support
- Basic Grafana dashboard template
- Enhanced monitoring dashboard script

### Documentation
- Comprehensive troubleshooting guide
- Common issues and recovery procedures

### Error Handling
- Enhanced error handling and rollback capabilities
- Installation phase tracking for recovery
- Automatic cleanup on installation failure

### Changed
- Improved error handling in all Ansible roles
- Better documentation throughout
- Simplified configuration process with guided setup

---

## [5.1.0] - 2026-01-19

### Added
- Complete Arch Linux server installer with LUKS2 encryption
- systemd-boot with Unified Kernel Images (UKI)
- Btrfs filesystem with subvolumes and compression
- TPM 2.0 auto-unlock preparation
- Secure Boot ready configuration
- Ansible automation for server configuration

### Security
- Base hardening with sysctl parameters
- nftables firewall with Cloudflare-only mode
- AppArmor mandatory access control
- Auditd security auditing
- SSH hardening with key-based authentication

### Ansible Roles
- `base_hardening` - System security hardening
- `container_runtime` - Podman rootless containers
- `cloudflare` - Cloudflare IP allowlisting
- `crowdsec` - Threat detection (AUR)
- `security_stack` - nftables, AppArmor, auditd
- `webserver` - Caddy web server
- `monitoring` - System monitoring tools
- `safe_updates` - Snapper Btrfs snapshots

### Scripts
- `install.sh` - Main system installer
- `deploy.sh` - Ansible deployment automation
- `setup-cloudflare.sh` - Cloudflare Tunnel setup
- `verify-deployment.sh` - Deployment verification
- `setup-tpm-unlock.sh` - TPM auto-unlock configuration
- `setup-secure-boot.sh` - Secure Boot enrollment

---

## [5.0.0] - 2026-01-01

### Added
- Initial release
- Basic Arch Linux installation script
- LUKS encryption support
- Btrfs filesystem setup

---

[Unreleased]: https://github.com/humethix/arch-server/compare/v5.1.0...HEAD
[5.1.0]: https://github.com/humethix/arch-server/compare/v5.0.0...v5.1.0
[5.0.0]: https://github.com/humethix/arch-server/releases/tag/v5.0.0
