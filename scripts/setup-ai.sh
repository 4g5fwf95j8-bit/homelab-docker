#!/bin/bash
echo "Syncing repo from GitHub..."
./scripts/setup-git.sh

set -e

echo "=== Starting Laptop 2 (AI) Setup ==="

# Docker
apt update && apt upgrade -y
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ${SUDO_USER:-$USER}
fi

# Storage
mkdir -p /mnt/storage/ollama/models
chown -R ${PUID:-1000}:${PGID:-1000} /mnt/storage

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
if [ -n "${TAILSCALE_AUTHKEY}" ]; then
    tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname="homelab-ai" --ssh --accept-routes || true
fi

# Start services
cd "$(dirname "$0")/../homelab-ai" || exit 1
docker compose pull
docker compose up -d

echo "=== Laptop 2 AI Setup Complete! ==="
echo "Open WebUI: http://localhost:8080"
echo "Pull models: docker exec -it ollama ollama pull qwen2.5-coder:7b"

# Start services
cd "$(dirname "$0")/../homelab-ai" || exit 1
docker compose pull
docker compose up -d

# Clean up dangling images left behind by updates
echo "Cleaning up old Docker images..."
docker image prune -f