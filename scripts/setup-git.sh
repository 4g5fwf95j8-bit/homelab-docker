#!/bin/bash
set -e

echo "=== Setting up GitHub access ==="

# Load .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set -a; source "${ROOT_DIR}/.env"; set +a

# Ensure SSH key is added
ssh-add ~/.ssh/id_ed25519 2>/dev/null || true

# Clone or pull repo
if [ ! -d "${ROOT_DIR}/.git" ]; then
    echo "Cloning repo..."
    git clone -b ${GIT_BRANCH} ${GITHUB_REPO} "${ROOT_DIR}"
else
    echo "Pulling latest changes..."
    cd "${ROOT_DIR}"
    git fetch origin
    git reset --hard origin/${GIT_BRANCH}
    git clean -fd
fi

echo "Git sync complete."