#!/usr/bin/env bash
# Weekly SMART check on the OS disk and the Seagate external drive.
# Flags failing hardware before it takes the whole box down.
#
# Requires smartmontools: sudo apt install smartmontools
#
# Install:
#   0 3 * * 0 /opt/homelab-docker/scripts/disk-health-check.sh

set -uo pipefail

LOG_FILE="/var/log/server-health/disk-health.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "===== $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG_FILE"

for dev in /dev/sda /dev/sdb; do
  [ -b "$dev" ] || continue
  echo "--- $dev ---" >> "$LOG_FILE"

  # USB-bridged drives often need -d sat to expose SMART data at all;
  # try normal first, fall back to sat.
  if ! smartctl -H -A "$dev" >> "$LOG_FILE" 2>&1; then
    smartctl -d sat -H -A "$dev" >> "$LOG_FILE" 2>&1
  fi

  if tail -n 40 "$LOG_FILE" | grep -Eiq 'FAILED|Reallocated_Sector_Ct|Pending_Sector|Uncorrectable'; then
    echo "!! $dev flagged possible issues — check $LOG_FILE !!" | tee -a "$LOG_FILE"
  fi
done