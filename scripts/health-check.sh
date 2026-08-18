#!/usr/bin/env bash
# Snapshot system health every run; meant to be cron'd every 5 min.
# Keeps a rolling window of pre-crash evidence, since in-memory state
# and volatile logs vanish the moment you hard-reset.
#
# Install:
#   */5 * * * * /opt/homelab-docker/scripts/health-check.sh

set -uo pipefail

LOG_DIR="/var/log/server-health"
LOG_FILE="${LOG_DIR}/health-$(date +%Y%m%d).log"
RETENTION_DAYS=14

mkdir -p "$LOG_DIR"

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="

  echo "--- memory ---"
  free -h

  echo "--- disk ---"
  df -h / /mnt/seagate_storage 2>/dev/null

  echo "--- seagate mount check ---"
  if mountpoint -q /mnt/seagate_storage; then
    echo "OK: mounted"
  else
    echo "WARNING: /mnt/seagate_storage is NOT mounted"
  fi

  echo "--- top memory consumers ---"
  ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -6

  echo "--- docker container status ---"
  docker ps --format '{{.Names}}: {{.Status}}' 2>/dev/null

  echo "--- kernel warnings in last 5 min (USB / I/O / OOM / exFAT) ---"
  journalctl -k --since "5 min ago" 2>/dev/null \
    | grep -Ei 'usb|i/o error|oom|hung_task|exfat|reset' \
    || echo "none"

  echo
} >> "$LOG_FILE"

# prune old logs so this doesn't grow forever
find "$LOG_DIR" -name 'health-*.log' -mtime +"$RETENTION_DAYS" -delete