#!/bin/bash
# =============================================
# Laptop 2 Setup Script (AI / Ollama Server)
# Run with: sudo ./scripts/setup-laptop2.sh
# =============================================

set -e

echo "=== Starting Laptop 2 Setup ==="

# --- 1. Docker ---
apt update && apt upgrade -y
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $SUDO_USER
fi

# --- 2. Storage for Ollama ---
echo "Setting up Ollama storage..."
mkdir -p /mnt/storage/ollama/models
chown -R ${PUID:-1000}:${PGID:-1000} /mnt/storage
chmod -R 755 /mnt/storage

# --- 3. Start Services ---
echo "Starting AI services..."
cd "$(dirname "$0")/../laptop2" || exit 1

docker compose pull
docker compose up -d

echo "=== Laptop 2 Setup Complete! ==="
echo "Check Ollama: docker ps | grep ollama"
echo "Pull a model: docker exec -it ollama ollama pull qwen2.5-coder"