#!/bin/bash
# =============================================
# Immich Photo Backup -> Mac (5TB_Server_Backup)
# + local Jellyfin config snapshot
# =============================================
# Pushes new files from the media server's Immich data directory to the
# external drive on the Mac over SSH/rsync. New files only — existing
# files at the destination are never overwritten or deleted, so this is
# safe to run nightly without risk of clobbering the backup.
#
# Also writes a dated tarball of Jellyfin config (not media) under
# backups/jellyfin/ on this host, kept for 14 days.
#
# Runs via cron at 4:00 AM (installed by setup-media.sh).
# Requires passwordless SSH key access from this host to the Mac —
# see the repo README for one-time setup steps.
#
# Usage: ./backup.sh [--dry-run]
#   --dry-run   Test connectivity and preview what would be copied,
#               without actually transferring or deleting anything.

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Load .env ---
if [ -f "${ROOT_DIR}/.env" ]; then
    set -a
    source "${ROOT_DIR}/.env"
    set +a
else
    echo "ERROR: .env file not found at ${ROOT_DIR}/.env" >&2
    exit 1
fi

: "${DIR_PHOTOS:?DIR_PHOTOS must be set in .env}"
: "${MAC_BACKUP_HOST:?MAC_BACKUP_HOST must be set in .env - LAN IP or hostname for the Mac}"
: "${MAC_BACKUP_USER:?MAC_BACKUP_USER must be set in .env (Mac username, e.g. georgesofianos)}"
: "${MAC_BACKUP_PATH:?MAC_BACKUP_PATH must be set in .env (e.g. /Volumes/5TB_Server_Backup)}"

SSH_KEY="${MAC_BACKUP_SSH_KEY:-/home/gsofianos/.ssh/id_ed25519_mac_backup}"
INCLUDE_DB="${MAC_BACKUP_INCLUDE_DB:-true}"
DB_RETENTION_DAYS="${MAC_BACKUP_DB_RETENTION_DAYS:-14}"

LOG_DIR="${ROOT_DIR}/backups/logs"
LOG_FILE="${LOG_DIR}/immich-backup.log"
mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

SSH_OPTS=(-i "${SSH_KEY}" -o BatchMode=yes -o ConnectTimeout=10)
REMOTE="${MAC_BACKUP_USER}@${MAC_BACKUP_HOST}"

log "=== Starting backup ==="

# --- Jellyfin config backup (config only, not media) ---
# Runs locally even if the Mac is unreachable.
JELLYFIN_CONFIG_DIR="/opt/jellyfin/config"
JELLYFIN_BACKUP_DIR="${ROOT_DIR}/backups/jellyfin"
mkdir -p "${JELLYFIN_BACKUP_DIR}"

if [ -d "${JELLYFIN_CONFIG_DIR}" ]; then
    STAMP=$(date +%Y%m%d)
    if [ "${DRY_RUN}" = true ]; then
        log "DRY RUN: would archive ${JELLYFIN_CONFIG_DIR} -> ${JELLYFIN_BACKUP_DIR}/jellyfin-config-${STAMP}.tar.gz"
    else
        tar -czf "${JELLYFIN_BACKUP_DIR}/jellyfin-config-${STAMP}.tar.gz" -C /opt/jellyfin config
        # keep last 14 days of local config backups
        find "${JELLYFIN_BACKUP_DIR}" -name 'jellyfin-config-*.tar.gz' -mtime +14 -delete
        log "Jellyfin config backup written to ${JELLYFIN_BACKUP_DIR}/jellyfin-config-${STAMP}.tar.gz"
    fi
else
    log "NOTE: ${JELLYFIN_CONFIG_DIR} not found — skipping Jellyfin config backup"
fi

if [ ! -d "${DIR_PHOTOS}" ]; then
    log "ERROR: DIR_PHOTOS (${DIR_PHOTOS}) not found on this host. Is the Seagate drive mounted? Aborting."
    exit 1
fi

# Bail out cleanly (not a hang, not a false "success") if the Mac is
# asleep, off the network, or the drive isn't connected. Also creates
# the destination folders on first run.
if ! ssh "${SSH_OPTS[@]}" "${REMOTE}" \
        "mkdir -p '${MAC_BACKUP_PATH}/immich' '${MAC_BACKUP_PATH}/immich-db' && test -d '${MAC_BACKUP_PATH}'" \
        2>>"${LOG_FILE}"; then
    log "ERROR: Could not reach ${MAC_BACKUP_HOST}, or ${MAC_BACKUP_PATH} doesn't exist there. Is the Mac awake and the drive connected? Skipping tonight's Immich backup."
    exit 1
fi

RSYNC_OPTS=(-ahl --ignore-existing --exclude 'thumbs/')
if [ "${DRY_RUN}" = true ]; then
    RSYNC_OPTS+=(--dry-run -v)
    log "DRY RUN: previewing sync, no files will actually be copied"
fi

log "Syncing new files from ${DIR_PHOTOS} to ${REMOTE}:${MAC_BACKUP_PATH}/immich/"

rsync "${RSYNC_OPTS[@]}" \
    -e "ssh -i ${SSH_KEY} -o ConnectTimeout=10" \
    "${DIR_PHOTOS}/" "${REMOTE}:${MAC_BACKUP_PATH}/immich/" 2>&1 | tee -a "${LOG_FILE}"

log "Photo sync complete."

if [ "${INCLUDE_DB}" = "true" ]; then
    if [ "${DRY_RUN}" = true ]; then
        log "DRY RUN: would dump immich_postgres via pg_dumpall and copy it to ${REMOTE}:${MAC_BACKUP_PATH}/immich-db/ (skipped)"
    else
        log "Dumping Immich database..."
        DB_DUMP="/tmp/immich-db-$(date +%Y%m%d-%H%M).sql.gz"
        docker exec immich_postgres pg_dumpall --clean -U "${IMMICH_DB_USERNAME}" | gzip > "${DB_DUMP}"

        scp -i "${SSH_KEY}" -o ConnectTimeout=10 "${DB_DUMP}" \
            "${REMOTE}:${MAC_BACKUP_PATH}/immich-db/" >> "${LOG_FILE}" 2>&1

        rm -f "${DB_DUMP}"

        # Keep the Mac side from filling up with dumps forever
        ssh "${SSH_OPTS[@]}" "${REMOTE}" \
            "find '${MAC_BACKUP_PATH}/immich-db' -name 'immich-db-*.sql.gz' -mtime +${DB_RETENTION_DAYS} -delete" \
            >> "${LOG_FILE}" 2>&1 || true

        log "Database dump complete (keeping last ${DB_RETENTION_DAYS} days)."
    fi
fi

if [ "${DRY_RUN}" = true ]; then
    log "=== Dry run finished — no files were actually copied ==="
else
    log "=== Backup finished successfully ==="
fi
```