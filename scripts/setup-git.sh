#!/bin/bash
set -e

echo "=== Setting up GitHub access ==="

# Load .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set -a; source "${ROOT_DIR}/.env"; set +a

# Resolve the real invoking user's home directory, even when this script is
# run via `sudo` (directly, or indirectly via setup-media.sh/setup-ai.sh).
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
SSH_KEY="${REAL_HOME}/.ssh/id_ed25519"

# Point git's ssh invocation directly at that key file instead of relying on
# ssh-agent. Under sudo, SSH_AUTH_SOCK from your shell's agent is normally
# NOT forwarded to the root process, so agent-based auth (ssh-add) silently
# has nothing to add to, and git falls back to root's own (nonexistent)
# identity -> "Permission denied (publickey)". GIT_SSH_COMMAND sidesteps
# the agent entirely and behaves the same whether this runs as you or as root.
if [ -f "${SSH_KEY}" ]; then
    export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${REAL_HOME}/.ssh/known_hosts -o StrictHostKeyChecking=accept-new"
else
    echo "WARNING: SSH key not found at ${SSH_KEY} — git operations will likely fail." >&2
fi

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