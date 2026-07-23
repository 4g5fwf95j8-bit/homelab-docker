#!/bin/bash
# =============================================
# Laptop 1 Setup Script (Media + Proxy Server)
# =============================================

set -e

echo "=== Starting Laptop 1 Setup ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load .env
if [ -f "${ROOT_DIR}/.env" ]; then
    set -a
    source "${ROOT_DIR}/.env"
    set +a
    echo "Loaded .env variables"
else
    echo "ERROR: .env file not found!"
    exit 1
fi

# Sync .env symlinks
echo "Syncing .env symlinks..."
bash "${SCRIPT_DIR}/run-each-update.sh"

# System & Docker
echo "Updating system..."
apt update && apt upgrade -y

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ${SUDO_USER:-$USER}
fi

# Tailscale
echo "Setting up Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

if [ -n "${TAILSCALE_AUTHKEY}" ]; then
    tailscale up --auth-key="${TAILSCALE_AUTHKEY}" \
        --hostname="laptop1-homelab" \
        --ssh --accept-routes || true
else
    echo "Warning: TAILSCALE_AUTHKEY not set"
fi

# =============================================
# Storage
# =============================================
echo "Setting up storage..."

# --- Dynamically locate the Seagate exFAT drive ---
# No blkid LABEL to match on, so identify it by filesystem type (exfat) +
# a size floor (>1TB) to rule out small partitions (e.g. sdb1, 200M).
# This works on any box the drive is plugged into, no UUID needed in .env.
mkdir -p /mnt/seagate_storage

SEAGATE_DEV=$(lsblk -rbno NAME,FSTYPE,TYPE,SIZE | \
    awk '$2=="exfat" && $3=="part" && $4+0 > 1000000000000 {print "/dev/"$1; exit}')

if [ -z "${SEAGATE_DEV}" ]; then
    echo "ERROR: No exFAT partition >1TB found. Is the Seagate drive connected?"
    exit 1
fi

SEAGATE_UUID=$(blkid -s UUID -o value "${SEAGATE_DEV}")

if [ -z "${SEAGATE_UUID}" ]; then
    echo "ERROR: Could not read UUID for ${SEAGATE_DEV}"
    exit 1
fi

echo "Found Seagate drive: ${SEAGATE_DEV} (UUID=${SEAGATE_UUID})"

# exFAT has no per-file ownership — chown on it is a silent no-op.
# uid/gid must be set as mount options so every file resolves to PUID:PGID.
FSTAB_LINE="UUID=${SEAGATE_UUID} /mnt/seagate_storage exfat defaults,uid=${PUID:-1000},gid=${PGID:-1000},umask=022,nofail,x-systemd.automount,x-systemd.idle-timeout=60 0 0"

# Idempotent: drop any existing entry for this mountpoint before re-adding,
# so re-running the script never produces duplicate fstab lines.
sed -i "\|/mnt/seagate_storage|d" /etc/fstab
echo "${FSTAB_LINE}" | tee -a /etc/fstab > /dev/null
systemctl daemon-reload

if mountpoint -q /mnt/seagate_storage; then
    CURRENT_OPTS=$(findmnt -no OPTIONS /mnt/seagate_storage)
    if [[ "${CURRENT_OPTS}" != *"uid=${PUID:-1000}"* ]]; then
        echo "NOTE: /mnt/seagate_storage is mounted without the new uid/gid options."
        echo "Stop containers using it, then run:"
        echo "  umount /mnt/seagate_storage && mount /mnt/seagate_storage"
        echo "(or reboot) to apply the change."
    else
        echo "Seagate drive already mounted with correct uid/gid options."
    fi
else
    mount /mnt/seagate_storage
fi

# --- Directories on the now-correctly-mounted drive ---
mkdir -p /mnt/seagate_storage/{jellyfin,immich}

# --- Local (ext4) config folders — real chown works fine here ---
mkdir -p /srv/{homepage,pricebuddy,caddy} /opt/{jellyfin,immich}
chown -R ${PUID:-1000}:${PGID:-1000} /srv /opt/jellyfin /opt/immich 2>/dev/null || true

echo "Storage setup complete."

# --- Prepare Caddy Config ---
CADDY_SRC="${ROOT_DIR}/services/public/staticconfig/caddy/Caddyfile"
CADDY_DEST="${ROOT_DIR}/laptop1/config/caddy/Caddyfile"

if [ -f "${CADDY_SRC}" ]; then
    echo "Syncing Caddyfile from static config..."
    mkdir -p "$(dirname "${CADDY_DEST}")"

    # Remove directory if Docker auto-created one during a failed run
    if [ -d "${CADDY_DEST}" ]; then
        rm -rf "${CADDY_DEST}"
    fi

    # Copy template Caddyfile if not already present at destination
    if [ ! -f "${CADDY_DEST}" ]; then
        cp "${CADDY_SRC}" "${CADDY_DEST}"
    fi
fi

# Start services
echo "Starting services..."
cd "${ROOT_DIR}/laptop1" || exit 1
docker compose pull
docker compose up -d

echo "=== Laptop 1 Setup Complete! ==="
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'Not connected')"
docker ps