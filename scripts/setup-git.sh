#!/bin/bash
set -e

echo "=== Setting up GitHub access ==="

# Load .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set -a; source "${ROOT_DIR}/.env"; set +a

# Resolve the real invoking user's home directory, even when this script is
# run via `sudo` (directly, or indirectly via setup-media.sh/setup-ai.sh).
# Without this, `~` resolves to /root under sudo and the SSH key lookup
# silently fails, since the deploy key lives in your user's home, not root's.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

# Ensure SSH key is added
ssh-add "${REAL_HOME}/.ssh/id_ed25519" 2>/dev/null || true

# Clone or pull repo
if [ ! -d "${ROOT_DIR}/.git" ]; then
    echo "Cloning repo..."
    git clone -b "${GIT_BRANCH}" "${GITHUB_REPO}" "${ROOT_DIR}"
else
    echo "Pulling latest changes..."
    cd "${ROOT_DIR}"
    git fetch origin
    git reset --hard "origin/${GIT_BRANCH}"
    git clean -fd
fi

# Reapply permissions to run scripts. Try without sudo first (works whether
# we're already root via an inherited sudo, or a non-root user who owns the
# repo files); only escalate if that's not enough.
if ! chmod +x "${ROOT_DIR}"/scripts/* 2>/dev/null; then
    sudo chmod +x "${ROOT_DIR}"/scripts/*
fi

echo "Git sync complete."
