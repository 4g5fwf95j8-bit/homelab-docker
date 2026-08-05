#!/bin/bash
# =============================================
# Laptop 2 Setup Script (AI Server)
# =============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Syncing repo from GitHub..."
"${SCRIPT_DIR}/setup-git.sh"

set -e

echo "=== Starting Laptop 2 (AI) Setup ==="

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

# Sync .env symlinks (same as setup-media.sh, kept consistent so any service
# can also be brought up standalone with `cd services/<name> && docker compose up`)
echo "Syncing .env symlinks..."
bash "${SCRIPT_DIR}/auth.sh"

# System & Docker
echo "Updating system..."
apt update && apt upgrade -y

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "${SUDO_USER:-$USER}"
fi

# Storage
mkdir -p /mnt/storage/ollama/models
chown -R "${PUID:-1000}:${PGID:-1000}" /mnt/storage

# Tailscale
echo "Setting up Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

if [ -n "${TAILSCALE_AUTHKEY}" ]; then
    tailscale up --auth-key="${TAILSCALE_AUTHKEY}" \
        --hostname="homelab-ai" \
        --ssh --accept-routes || true
else
    echo "Warning: TAILSCALE_AUTHKEY not set"
fi

# =============================================
# Start services
# =============================================
echo "Starting services..."
cd "${ROOT_DIR}/homelab-ai" || exit 1
docker compose pull
docker compose build
docker compose up -d --remove-orphans

echo "Cleaning up old Docker images..."
docker image prune -f

echo "=== Laptop 2 AI Setup Complete! ==="
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'Not connected')"
echo "Open WebUI: http://localhost:8080"
echo "Pull models: docker exec -it ollama ollama pull qwen2.5-coder:7b"
docker ps
