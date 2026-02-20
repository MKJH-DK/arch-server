# Troubleshooting Guide

This guide helps you diagnose and fix common issues with Arch Server v5.1 deployment.

## Quick Diagnostics

Run the health check script to identify issues:

```bash
sudo /usr/local/bin/health-check
```

Or get JSON output for monitoring:

```bash
sudo /usr/local/bin/health-check --json
```

## Common Issues and Solutions

### Installation Issues

#### 1. "No internet connection" during installation

**Symptoms:** Installation fails with network errors

**Causes:**
- WiFi not configured properly
- Ethernet not connected
- DNS issues

**Solutions:**
```bash
# Check network status
ping -c 3 1.1.1.1
ping -c 3 google.com

# For WiFi issues
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "SSID"

# Check DNS
cat /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
```

#### 2. "config.env not found" error

**Symptoms:** Installation aborts immediately

**Causes:**
- Wrong working directory
- Configuration not set up

**Solutions:**
```bash
# Ensure you're in the project directory
pwd
ls -la src/config.env

# If missing, run setup
chmod +x src/config-setup.sh
./src/config-setup.sh
```

#### 3. Disk partitioning fails

**Symptoms:** "Failed to create partitions" or LUKS errors

**Causes:**
- Disk already has partitions
- Disk doesn't exist
- UEFI not enabled

**Solutions:**
```bash
# Check disk exists
lsblk
fdisk -l /dev/sda  # or whatever disk you specified

# Check UEFI
ls /sys/firmware/efi

# Wipe existing partitions (CAUTION: destroys data)
sgdisk --zap-all /dev/sda
```

### Boot Issues

#### 4. System doesn't boot after installation

**Symptoms:** Black screen or boot menu not shown

**Causes:**
- Secure Boot not configured
- EFI partition not mounted
- systemd-boot not installed correctly

**Solutions:**
```bash
# From live USB, check EFI partition
lsblk
mount /dev/sda1 /mnt  # EFI partition
ls /mnt/EFI

# Reinstall systemd-boot
bootctl install

# Check Secure Boot status
mokutil --sb-state
```

#### 5. LUKS password not accepted

**Symptoms:** "No key available" during boot

**Causes:**
- Wrong password entered
- TPM auto-unlock failed
- LUKS header corrupted

**Solutions:**
```bash
# Emergency recovery from live USB
cryptsetup luksOpen /dev/sda2 cryptroot
mount /dev/mapper/cryptroot /mnt
arch-chroot /mnt

# Inside chroot, check TPM
systemctl status tpm2-unlock

# Reset TPM PIN if needed
tpm2_changeauth -c lockout
```

### Network Issues

#### 6. No network after boot

**Symptoms:** `ip addr` shows no IP address

**Causes:**
- NetworkManager not started
- WiFi credentials wrong
- Firewall blocking

**Solutions:**
```bash
# Check network status
systemctl status NetworkManager
ip addr

# Restart networking
systemctl restart NetworkManager

# Check WiFi
nmcli device wifi list
nmcli device wifi connect "SSID" password "PASSWORD"

# Check firewall
nft list ruleset
systemctl status nftables
```

#### 7. SSH connection refused

**Symptoms:** `ssh: connect to host port 22: Connection refused`

**Causes:**
- SSH service not running
- Firewall blocking port 22
- SSH configured for key-only auth but no key provided

**Solutions:**
```bash
# Check SSH service
systemctl status sshd

# Check firewall rules
nft list chain inet filter input | grep 22

# Check SSH config
grep -E "(PermitRootLogin|PasswordAuthentication)" /etc/ssh/sshd_config

# Restart SSH
systemctl restart sshd
```

### Web Server Issues

#### 8. Web server not responding

**Symptoms:** Browser shows "connection refused" or timeout

**Causes:**
- Caddy not started
- Wrong port/firewall
- SSL certificate issues

**Solutions:**
```bash
# Check Caddy status
systemctl status caddy
journalctl -u caddy -n 20

# Check listening ports
ss -tlnp | grep :80
ss -tlnp | grep :443

# Check Caddy config
caddy validate --config /etc/caddy/Caddyfile

# Reload Caddy
systemctl reload caddy
```

#### 9. SSL certificate errors

**Symptoms:** Browser shows certificate warnings

**Causes:**
- Domain not configured
- Let's Encrypt failed
- DNS not pointing to server

**Solutions:**
```bash
# Check DNS resolution
nslookup yourdomain.com

# Check Caddy logs for LE errors
journalctl -u caddy | grep -i "challenge\|certificate"

# Force certificate renewal
caddy reload
```

### Security Issues

#### 10. AppArmor denying access

**Symptoms:** Applications failing with permission errors

**Causes:**
- AppArmor profiles missing or incorrect
- System not enforcing AppArmor

**Solutions:**
```bash
# Check AppArmor status
systemctl status apparmor
aa-status

# Check audit logs for denials
journalctl | grep "apparmor.*DENIED"

# Reload profiles
apparmor_parser -r /etc/apparmor.d/
```

#### 11. Firewall blocking legitimate traffic

**Symptoms:** Services work locally but not remotely

**Causes:**
- Cloudflare-only mode blocking direct access
- nftables rules too restrictive

**Solutions:**
```bash
# Check current rules
nft list ruleset

# Temporarily disable firewall for testing
systemctl stop nftables

# Check if Cloudflare mode is enabled
grep "CLOUDFLARE_ONLY" /etc/nftables.conf

# Add temporary rule
nft add rule inet filter input tcp dport 22 accept
```

### Performance Issues

#### 12. System running slow

**Symptoms:** High load, slow response times

**Causes:**
- Memory pressure
- Disk I/O issues
- Service conflicts

**Solutions:**
```bash
# Check system load
uptime
top -b -n1 | head -20

# Check memory
free -h
ps aux --sort=-%mem | head

# Check disk I/O
iotop -b -n 1
df -h

# Check systemd-analyze
systemd-analyze blame
systemd-analyze critical-chain
```

#### 13. High memory usage

**Symptoms:** System swapping, OOM kills

**Causes:**
- Memory leaks
- Too many services
- Large logs

**Solutions:**
```bash
# Check memory hogs
ps aux --sort=-%mem | head

# Clear system cache
echo 3 > /proc/sys/vm/drop_caches

# Check journal size
journalctl --disk-usage
journalctl --vacuum-size=100M

# Restart problematic services
systemctl restart servicename
```

### Update Issues

#### 14. Safe updates failing

**Symptoms:** Snapper snapshots not created

**Causes:**
- Btrfs subvolumes not configured
- Snapper not running

**Solutions:**
```bash
# Check Btrfs layout
btrfs subvolume list /

# Check Snapper
systemctl status snapper-timeline
snapper list

# Manual snapshot
snapper create -t single -d "Manual snapshot"

# Check safe-updates service
systemctl status safe-updates
```

### Monitoring Issues

#### 15. Prometheus metrics not available

**Symptoms:** Grafana shows no data

**Causes:**
- Node Exporter not running
- Firewall blocking metrics port
- Prometheus not configured

**Solutions:**
```bash
# Check Node Exporter
systemctl status prometheus-node-exporter
ss -tlnp | grep 9100

# Check Prometheus
systemctl status prometheus
ss -tlnp | grep 9090

# Check firewall
nft list chain inet filter input | grep 9100
```

## Recovery Procedures

### Emergency Console Access

If the system becomes completely unresponsive:

1. Boot from Arch ISO in UEFI mode
2. Mount your encrypted root:
```bash
cryptsetup luksOpen /dev/sda2 cryptroot
mount /dev/mapper/cryptroot /mnt
mount /dev/sda1 /mnt/efi  # if separate EFI
arch-chroot /mnt
```
3. Fix issues from within chroot
4. Reboot: `exit && umount -R /mnt && reboot`

### Backup Recovery

If you need to restore from backup:

```bash
# List available snapshots
snapper list

# Mount snapshot for recovery
mount -o subvol=@snapshots/123/snapshot /mnt/recovery

# Copy files back
cp -a /mnt/recovery/path/to/file /path/to/file
```

## Getting Help

If these solutions don't work:

1. Check the logs: `journalctl -b -p err`
2. Run diagnostics: `sudo /usr/local/bin/health-check`
3. Check GitHub issues: https://github.com/humethix/arch-server/issues
4. Join the discussion: [Forum link]

## Prevention

To avoid issues:

- Always run `health-check` after changes
- Keep system updated: `pacman -Syu`
- Monitor logs regularly: `journalctl -f`
- Backup configuration: `cp /root/arch/src/config.env /root/config.env.backup`
- Test changes in a VM first