#!/bin/bash
# =============================================
# UFW Firewall Sync Script
# Opens ports required by the docker-compose stack and removes any
# previously-managed rule that's no longer needed. Only rules tagged
# with the "homelab-managed" comment are ever touched — anything you
# add by hand (or SSH) is left alone.
#
# Ports bound only to 127.0.0.1 are intentionally skipped — they are
# not reachable from the network, so they do not need UFW rules.
#
# Usage:
#   bash setup-ufw.sh            # apply changes
#   bash setup-ufw.sh --dry-run  # show what would change, do nothing
# =============================================
set -e

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN — no ufw rules will be changed ==="
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${ROOT_DIR}/homelab-media"
UFW_TAG="homelab-managed"

if ! command -v ufw &> /dev/null; then
    echo "ufw not installed, skipping firewall sync."
    exit 0
fi

if ! command -v jq &> /dev/null; then
    if [ "${DRY_RUN}" = true ]; then
        echo "[dry-run] Would install jq (needed to parse compose config)"
    else
        echo "Installing jq (needed to parse compose config)..."
        apt-get install -y jq
    fi
fi

echo "=== Syncing UFW rules with docker-compose ports ==="

# --- Baseline rules this script will NEVER remove (lockout protection) ---
if [ "${DRY_RUN}" = true ]; then
    echo "[dry-run] Would ensure baseline rules: OpenSSH, 41641/udp (Tailscale)"
else
    ufw allow OpenSSH comment "${UFW_TAG}-baseline" > /dev/null 2>&1 || true
    ufw allow 41641/udp comment "${UFW_TAG}-baseline" > /dev/null 2>&1 || true
fi

# --- Desired ports: only those NOT bound exclusively to 127.0.0.1 ---
# docker compose config JSON has host_ip when a specific bind address is set.
# Skip anything whose host_ip is 127.0.0.1 / ::1.
DESIRED_PORTS=$(cd "${COMPOSE_DIR}" && docker compose config --format json | \
    jq -r '
      .services[].ports[]? |
      select((.host_ip // "") != "127.0.0.1" and (.host_ip // "") != "::1") |
      (.published|tostring) + "/" + (.protocol // "tcp")
    ' | sort -u)

# --- Ports this script currently manages, read back from ufw itself ---
CURRENT_MANAGED=$(ufw show added | \
    grep "comment '${UFW_TAG}'" | \
    sed -E "s/.*allow ([0-9]+(:[0-9]+)?\/(tcp|udp)).*/\1/" | \
    sort -u)

# --- Add anything desired but not yet open ---
for port in ${DESIRED_PORTS}; do
    if ! grep -qx "${port}" <<< "${CURRENT_MANAGED}"; then
        if [ "${DRY_RUN}" = true ]; then
            echo "[dry-run] Would open ${port}"
        else
            echo "Opening ${port}"
            ufw allow "${port}" comment "${UFW_TAG}"
        fi
    fi
done

# --- Remove anything managed but no longer needed ---
for port in ${CURRENT_MANAGED}; do
    if ! grep -qx "${port}" <<< "${DESIRED_PORTS}"; then
        if [ "${DRY_RUN}" = true ]; then
            echo "[dry-run] Would close stale port ${port}"
        else
            echo "Closing stale port ${port}"
            ufw --force delete allow "${port}" comment "${UFW_TAG}"
        fi
    fi
done

if [ "${DRY_RUN}" = true ]; then
    echo "=== Dry run complete — current ufw state unchanged ==="
    ufw status verbose
else
    ufw --force enable > /dev/null 2>&1
    echo "UFW sync complete:"
    ufw status verbose
fi
