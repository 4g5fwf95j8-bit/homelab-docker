#!/bin/bash
# =============================================
# Install media-server maintenance cron jobs
# =============================================
# Idempotent. Safe to re-run from setup-media.sh.
# All jobs go in root's crontab (setup runs via sudo).
#
# Jobs managed here (marker-based, so re-runs don't duplicate):
#   - Nightly Immich + Jellyfin config backup (04:00)
#   - Weekly Docker image prune (Monday 02:00)
#   - Monthly apt upgrade (1st of month 01:00)
#   - Weekly Navidrome data snapshot (Sunday 03:30)
#
# Usage: sudo ./scripts/install-cron.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ROOT_DIR}/backups/logs"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: install-cron.sh must be run as root (sudo)." >&2
    exit 1
fi

mkdir -p "${LOG_DIR}" \
    "${ROOT_DIR}/backups/jellyfin" \
    "${ROOT_DIR}/backups/navidrome"

chmod +x "${SCRIPT_DIR}/backup.sh"

# Prefer ownership of the user who invoked sudo (for easy log reading)
LOGIN_USER="${SUDO_USER:-$USER}"
if [ "${LOGIN_USER}" != "root" ]; then
    chown -R "${LOGIN_USER}:${LOGIN_USER}" "${ROOT_DIR}/backups" 2>/dev/null || true
fi

# --- helpers ---------------------------------------------------------------

# Remove any existing lines that match a marker, then append the new line.
# Marker is a unique substring (usually the script path or a tag).
ensure_root_cron() {
    local marker="$1"
    local line="$2"
    local current
    current="$(crontab -l 2>/dev/null || true)"
    # Drop old lines for this marker
    current="$(printf '%s\n' "${current}" | grep -vF "${marker}" || true)"
    # Append new line
    printf '%s\n' "${current}" "${line}" | sed '/^$/d' | crontab -
}

# --- job definitions -------------------------------------------------------

BACKUP_LINE="0 4 * * * ${SCRIPT_DIR}/backup.sh >> ${LOG_DIR}/cron.log 2>&1"
PRUNE_LINE="0 2 * * 1 docker image prune -af >> ${LOG_DIR}/docker-prune.log 2>&1"
APT_LINE="0 1 1 * * apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade >> ${LOG_DIR}/apt-upgrade.log 2>&1"
NAVIDROME_DATA="${NAVIDROME_DATA_DIR:-/opt/navidrome/data}"
NAVIDROME_LINE="30 3 * * 0 mkdir -p ${ROOT_DIR}/backups/navidrome && tar -czf ${ROOT_DIR}/backups/navidrome/navidrome-\$(date +\\%Y\\%m\\%d).tar.gz -C $(dirname "${NAVIDROME_DATA}") $(basename "${NAVIDROME_DATA}") && find ${ROOT_DIR}/backups/navidrome -name 'navidrome-*.tar.gz' -mtime +28 -delete >> ${LOG_DIR}/navidrome-backup.log 2>&1"

echo "Installing root cron jobs..."

ensure_root_cron "scripts/backup.sh" "${BACKUP_LINE}"
ensure_root_cron "docker image prune" "${PRUNE_LINE}"
ensure_root_cron "apt-get -y upgrade" "${APT_LINE}"
ensure_root_cron "backups/navidrome" "${NAVIDROME_LINE}"

echo "Root crontab now contains:"
crontab -l | sed 's/^/  /'

echo "Cron install complete."
