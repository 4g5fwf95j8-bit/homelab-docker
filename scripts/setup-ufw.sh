#!/bin/bash
# =============================================
# UFW Firewall Sync Script
# Opens ports required by the docker-compose stack — scoped to the
# Tailscale range and the local LAN only — and removes any
# previously-managed rule that's no longer needed. Only rules tagged
# with the "homelab-managed" comment are ever touched — anything you
# add by hand (or SSH) is left alone.
#
# Ports bound only to 127.0.0.1 are intentionally skipped — they are
# not reachable from the network, so they do not need UFW rules.
#
# Every other published port is allowed ONLY from the two ranges below.
# Nothing is ever opened to the public internet by this script.
#
# Usage:
#   bash setup-ufw.sh [homelab-media|homelab-ai] [--dry-run]
#   (compose project defaults to homelab-media if omitted, for
#   backwards compatibility with the media-server setup script)
# =============================================
set -e

# --- Allowed source ranges — only these can reach any published port ---
TAILSCALE_CIDR="100.64.0.0/10"
LAN_CIDR="192.168.68.0/24"
ALLOWED_CIDRS=("${TAILSCALE_CIDR}" "${LAN_CIDR}")

DRY_RUN=false
COMPOSE_PROJECT="homelab-media"
for arg in "$@"; do
    case "${arg}" in
        --dry-run)
            DRY_RUN=true
            echo "=== DRY RUN — no ufw rules will be changed ==="
            ;;
        *)
            COMPOSE_PROJECT="${arg}"
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${ROOT_DIR}/${COMPOSE_PROJECT}"
UFW_TAG="homelab-managed"

if [ ! -d "${COMPOSE_DIR}" ]; then
    echo "ERROR: compose project directory not found: ${COMPOSE_DIR}"
    echo "Usage: bash setup-ufw.sh [homelab-media|homelab-ai] [--dry-run]"
    exit 1
fi

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

echo "=== Syncing UFW rules with docker-compose ports (${COMPOSE_PROJECT}) ==="

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

# --- Desired rules: one per (port, allowed source) combination ---
DESIRED_RULES=()
for port in ${DESIRED_PORTS}; do
    for cidr in "${ALLOWED_CIDRS[@]}"; do
        DESIRED_RULES+=("${cidr}|${port}")
    done
done

# --- Rules this script currently manages, read back from ufw itself ---
# ufw renders each as: ufw allow from <cidr> to any port <port> proto <proto> comment '...'
CURRENT_MANAGED=$(ufw show added | \
    grep "comment '${UFW_TAG}'" | \
    sed -E "s/.*allow from ([0-9.\/]+) to any port ([0-9]+(:[0-9]+)?) proto (tcp|udp).*/\1|\2\/\4/" | \
    sort -u)

# --- Add anything desired but not yet open ---
for rule in "${DESIRED_RULES[@]}"; do
    if ! grep -qxF "${rule}" <<< "${CURRENT_MANAGED}"; then
        cidr="${rule%%|*}"
        port="${rule##*|}"
        if [ "${DRY_RUN}" = true ]; then
            echo "[dry-run] Would open ${port} from ${cidr}"
        else
            echo "Opening ${port} from ${cidr}"
            ufw allow from "${cidr}" to any port "${port%%/*}" proto "${port##*/}" comment "${UFW_TAG}"
        fi
    fi
done

# --- Remove anything managed but no longer needed ---
while IFS= read -r rule; do
    [ -z "${rule}" ] && continue
    if ! printf '%s\n' "${DESIRED_RULES[@]}" | grep -qxF "${rule}"; then
        cidr="${rule%%|*}"
        port="${rule##*|}"
        if [ "${DRY_RUN}" = true ]; then
            echo "[dry-run] Would close stale rule: ${port} from ${cidr}"
        else
            echo "Closing stale rule: ${port} from ${cidr}"
            ufw --force delete allow from "${cidr}" to any port "${port%%/*}" proto "${port##*/}" comment "${UFW_TAG}"
        fi
    fi
done <<< "${CURRENT_MANAGED}"

if [ "${DRY_RUN}" = true ]; then
    echo "=== Dry run complete — current ufw state unchanged ==="
    ufw status verbose
else
    ufw --force enable > /dev/null 2>&1
    echo "UFW sync complete:"
    ufw status verbose
fi