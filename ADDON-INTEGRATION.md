# Addon Integration Guide

This document describes how to integrate addons with the Arch Server base installation.

## System Architecture

```
Base repo (this)              Addon repo (separate)
├── src/install.sh            ├── addons/
│   (Arch install + LUKS      │   ├── obsidian-web/
│    + Btrfs + boot)           │   ├── backblaze-backup/
├── src/ansible/               │   └── ...
│   (Security, Caddy,          ├── scripts/
│    firewall, monitoring)     │   └── deploy-addons.sh
└── scripts/deploy.sh          └── ansible/
    (Base deployment)              └── playbooks/
```

The base repo handles OS installation, security hardening, and core services.
The addon repo extends functionality without modifying the base.

## Integration Points

### 1. Caddy Web Server (Multi-Domain)

The base Caddyfile is generated from a Jinja2 template and supports multiple domains.
Addons extend the web server by dropping config files into the conf.d directory:

```
/etc/caddy/conf.d/*.caddy     # Addon Caddy configs (auto-imported)
/etc/caddy/Caddyfile           # Base config (do not modify - managed by Ansible)
```

The base Caddyfile includes `import /etc/caddy/conf.d/*.caddy` which automatically
loads any `.caddy` files placed in that directory. This works regardless of whether
domains are configured (HTTP-only mode) or multiple domains are active (HTTPS mode).

**Example: Path-based addon** (works with any domain setup):

```caddy
# /etc/caddy/conf.d/obsidian.caddy
:80 {
    handle /wiki/* {
        root * /srv/obsidian/vault
        file_server
    }
}
```

**Example: Subdomain-based addon** (requires DNS + domain in Caddy):

```caddy
# /etc/caddy/conf.d/obsidian.caddy
wiki.example.com {
    root * /srv/obsidian/vault
    file_server
    encode gzip zstd
}
```

After adding a config, reload Caddy:

```bash
caddy validate --config /etc/caddy/Caddyfile  # Always validate first
systemctl reload caddy
```

### 2. Multi-Domain Configuration

The base supports multiple domains configured via:

- **`DOMAINS` env var**: Comma-separated (e.g., `"a.com,b.com:/srv/blog"`)
- **`domains` list in Ansible inventory**: More flexible, supports per-domain options
- **`DOMAIN` env var**: Legacy single-domain (auto-converted)

Each domain gets its own HTTPS certificate, log file, and optional web root.
Addons can query the `domains` variable in Ansible to adapt their configuration.

### 3. Website Content

```
/srv/www/                      # Default website root (shared across domains without custom root)
/srv/                          # Parent for addon data directories
```

Addons should create their own directories under `/srv/`:

```
/srv/obsidian/                 # Obsidian vault sync target
/srv/git/                      # Git repositories (if cgit addon)
/srv/backups/                  # Backup staging area
/srv/blog/                     # Example: per-domain web root
```

### 3. Systemd Services

Addons that need background services should install systemd units:

```
/etc/systemd/system/           # Addon service files
/usr/local/bin/                # Addon scripts/binaries
```

### 4. Ansible Roles

Addon Ansible roles can be placed in a separate directory and executed
with a custom playbook:

```bash
ansible-playbook -i /root/arch/src/ansible/inventory/hosts.yml \
    /root/arch-addons/ansible/playbooks/addons.yml
```

## Network Prerequisites

The base installation configures NetworkManager with:

- **Ethernet**: route-metric 100 (preferred)
- **WiFi**: route-metric 600 (fallback)

Both connections are always active. Addons requiring network sync
(like Obsidian) should work on either connection type.

## Example: Obsidian Web Addon

An Obsidian-as-website addon would:

1. **Sync mechanism**: Use Syncthing or rsync to sync `.md` files between:
   - Windows PC (Obsidian editor)
   - Android phone (Obsidian mobile)
   - Arch server (`/srv/obsidian/vault/`)

2. **Caddy config**: Serve vault as static site with markdown rendering
   - Drop config in `/etc/caddy/conf.d/obsidian.caddy`

3. **Systemd service**: Background sync daemon
   - Install as `/etc/systemd/system/obsidian-sync.service`

4. **Ansible role**: Automate installation
   ```yaml
   # addons/obsidian-web/tasks/main.yml
   - name: Install Syncthing
     community.general.pacman:
       name: syncthing
       state: present

   - name: Create vault directory
     file:
       path: /srv/obsidian/vault
       state: directory

   - name: Deploy Caddy config
     copy:
       src: obsidian.caddy
       dest: /etc/caddy/conf.d/obsidian.caddy
     notify: Reload Caddy
   ```

## Example: Backblaze B2 Backup Addon

A Backblaze backup addon would:

1. **Install**: `backblaze-b2` CLI tool
2. **Configure**: B2 bucket credentials
3. **Schedule**: systemd timer for periodic backup of:
   - `/srv/` (all addon data)
   - `/etc/caddy/` (web server config)
   - Btrfs snapshots (via `snapper`)
4. **Script**: `/usr/local/bin/b2-backup` for manual runs

## Conventions

| Item | Path | Description |
|------|------|-------------|
| Caddy configs | `/etc/caddy/conf.d/*.caddy` | Auto-imported by base Caddyfile |
| Website root | `/srv/www/` | Base default website |
| Addon data | `/srv/<addon-name>/` | Per-addon data directories |
| Addon scripts | `/usr/local/bin/` | Executable scripts |
| Addon services | `/etc/systemd/system/` | Systemd unit files |
| Addon Ansible | `<addon-repo>/ansible/` | Ansible roles and playbooks |

## Security Notes

- Addons run within the security boundaries set by the base installation
- nftables firewall rules apply to all services (Cloudflare-only mode)
- AppArmor profiles should be created for new services
- Use `systemd` security directives (ProtectSystem, NoNewPrivileges, etc.)
- Never disable base security features from an addon
