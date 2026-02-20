# Installation Guide

## Prerequisites

- Arch Linux ISO (latest version)
- UEFI boot mode enabled
- Internet connection
- Target disk (all data will be erased)

## Step 1: Boot from Arch ISO

1. Download Arch Linux ISO from [archlinux.org](https://archlinux.org/download/)
2. Create bootable USB with `dd` or Rufus
3. Boot in UEFI mode

## Step 2: Prepare Installation Files

```bash
# Connect to internet
iwctl station wlan0 connect "YourNetwork"

# Download project
curl -L https://github.com/humethix/arch-server/archive/main.tar.gz | tar xz
cd arch-server-main
```

## Step 3: Configure

Edit `src/config.env`:

```bash
nano src/config.env
```

Key settings:
```bash
HOSTNAME="myserver"
USERNAME="admin"
TIMEZONE="Europe/Copenhagen"
TARGET_DISK="sda"  # or nvme0n1
```

## Step 4: Add SSH Key (Recommended)

```bash
# Copy your public key
cp ~/.ssh/id_ed25519.pub authorized_keys.pub
```

## Step 5: Run Installer

```bash
chmod +x src/install.sh
./src/install.sh
```

## Step 6: Reboot

```bash
umount -R /mnt
reboot
```

## Next Steps

After reboot, see [Deployment Guide](deployment.md).
