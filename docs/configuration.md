# Configuration Reference

## config.env

The main configuration file for the installer. Use `src/config-setup.sh` to generate it interactively, or copy from `config.env.basic` / `config.env.advanced`.

### System Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `HOSTNAME` | `archserver` | System hostname |
| `USERNAME` | `admin` | Primary user account |
| `TIMEZONE` | `Europe/Copenhagen` | System timezone |
| `LOCALE` | `da_DK.UTF-8` | System locale |
| `KEYMAP` | `dk` | Console keymap |

### Kernel Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_TYPE` | `hardened` | Kernel variant (hardened/lts/default) |
| `USE_SYSTEMD_BOOT` | `true` | Use systemd-boot |
| `USE_UKI` | `true` | Use Unified Kernel Images |
| `ENABLE_SECURE_BOOT` | `true` | Prepare for Secure Boot |

### Encryption

| Variable | Default | Description |
|----------|---------|-------------|
| `LUKS_PASSWORD` | (generated) | Disk encryption password |
| `ENABLE_TPM_UNLOCK` | `true` | TPM auto-unlock |
| `TPM_USE_PIN` | `true` | Require PIN with TPM |

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_ETHERNET` | `true` | Configure Ethernet (route-metric 100) |
| `ENABLE_WIFI` | `false` | Configure WiFi (route-metric 600) |
| `WIFI_SSID` | - | WiFi network name |
| `WIFI_PASSWORD` | - | WiFi password |
| `STATIC_IP` | - | Static IP (e.g., `192.168.1.100/24`) |
| `STATIC_GATEWAY` | - | Gateway for static IP |
| `STATIC_DNS` | `1.1.1.1,9.9.9.9` | DNS servers |

Ethernet is always prioritized over WiFi via route-metrics. Both connections can be active simultaneously.

### SSH

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_KEY_FILE` | `authorized_keys.pub` | SSH public key path |
| `SSH_GENERATE_IF_MISSING` | `true` | Auto-generate if missing |

### Disk

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_DISK` | - | Target disk (sda, nvme0n1) |
| `EFI_SIZE_MB` | `1024` | EFI partition size |
| `BTRFS_COMPRESSION` | `zstd:3` | Btrfs compression |

### Web Server

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | - | Single domain for auto-SSL (backward compatible) |
| `DOMAINS` | - | Multiple domains, comma-separated |
| `DOMAIN_EMAIL` | - | Email for Let's Encrypt (shared across all domains) |

Caddy is installed from the official Arch repos with multi-domain support. Each domain gets automatic HTTPS via Let's Encrypt.

**Configuration paths:**

- **Caddyfile**: `/etc/caddy/Caddyfile` (Jinja2 template, managed by Ansible)
- **Addon configs**: `/etc/caddy/conf.d/*.caddy`
- **Default website root**: `/srv/www/`
- **Per-domain logs**: `/var/log/caddy/<domain>.log`

**Multi-domain configuration:**

```bash
# config.env - comma-separated, optional webroot after colon
DOMAINS="example.com,blog.example.com:/srv/blog,shop.example.com:/srv/shop"
```

Or in Ansible inventory (`hosts.yml`):

```yaml
domains:
  - { domain: "example.com" }                          # uses /srv/www
  - { domain: "blog.example.com", root: "/srv/blog" }  # custom root
  - { domain: "shop.example.com", root: "/srv/shop" }
```

If no domains are configured, Caddy serves HTTP on port 80 from `/srv/www/`.

**Precedence:** `domains` list in hosts.yml > `DOMAINS` env var > `DOMAIN` env var (legacy)

### Cloudflare

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_CLOUDFLARE` | `false` | Enable Cloudflare integration |
| `CLOUDFLARE_ONLY_MODE` | `false` | Only allow Cloudflare IPs |

## Ansible Variables

See `src/ansible/inventory/hosts.yml` for Ansible-specific variables.

## Addon Integration

See [ADDON-INTEGRATION.md](../ADDON-INTEGRATION.md) for how to extend this installation with addons.
