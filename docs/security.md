# Security Guide

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                          │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Encryption    │ LUKS2 + TPM                       │
│  Layer 2: Boot          │ Secure Boot + UKI                 │
│  Layer 3: Network       │ nftables + Cloudflare-only        │
│  Layer 4: Access        │ SSH keys + rate limiting          │
│  Layer 5: System        │ AppArmor + auditd                 │
│  Layer 6: Recovery      │ Btrfs snapshots                   │
└─────────────────────────────────────────────────────────────┘
```

## Encryption (LUKS2)

- **Algorithm**: AES-XTS-PLAIN64 (512-bit)
- **Hash**: SHA-512
- **KDF**: Argon2id (1GB memory, 4 threads)
- **TPM PCRs**: 7 (Secure Boot state)

### Backup LUKS Header

```bash
cryptsetup luksHeaderBackup /dev/sda2 --header-backup-file luks-backup.bin
```

## Firewall (nftables)

Default policy: **DROP all incoming**

Allowed:
- SSH (port 22) - rate limited
- HTTP/HTTPS (80, 443) - Cloudflare IPs only

### View Rules

```bash
nft list ruleset
```

### Cloudflare-Only Mode

Only Cloudflare IP ranges can access web ports. Updated weekly automatically.

## SSH Hardening

- Root login: `prohibit-password`
- Max auth tries: 3
- X11 forwarding: disabled
- Key authentication: preferred

### Add SSH Key

```bash
cat >> ~/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAA... user@host
EOF
```

## Kernel Hardening

Sysctl parameters:
```
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 2
net.ipv4.tcp_syncookies = 1
```

## Monitoring

### Audit Logs

```bash
ausearch -k identity
ausearch -k sudo_usage
```

### Security Status

```bash
/usr/local/bin/health-check
aa-status  # AppArmor
auditctl -l  # Audit rules
```

## Best Practices

1. **Keep LUKS password secure** - Store offline
2. **Backup LUKS header** - Store on separate media
3. **Use SSH keys** - Disable password auth
4. **Monitor logs** - Check audit logs regularly
5. **Update regularly** - `pacman -Syu` with snapshots
