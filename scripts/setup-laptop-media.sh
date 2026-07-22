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

# Storage - Skip recursive chown on exFAT
echo "Setting up directories..."
mkdir -p /mnt/seagate_storage/{jellyfin,immich} /srv/{homepage,pricebuddy,caddy} /opt/{jellyfin,immich}

# Only chown Docker-related config folders (avoid media library)
chown -R ${PUID:-1000}:${PGID:-1000} /srv /opt/jellyfin /opt/immich 2>/dev/null || true

echo "Storage directories ready. Note: exFAT does not support chown on media files."

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