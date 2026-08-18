#!/usr/bin/env bash
# One-time setup: hardware watchdog + persistent journald logging.
# Run once with sudo. If the box has a true full-system hang (kernel
# stuck, USB bus wedged, etc.) this is what actually reboots it
# without you walking over and holding the power button.

set -euo pipefail

echo "Checking for a hardware watchdog device..."
if [ -e /dev/watchdog ]; then
  echo "Found /dev/watchdog"
else
  echo "No /dev/watchdog found — loading iTCO_wdt (Intel chipset watchdog)..."
  modprobe iTCO_wdt || echo "Could not load iTCO_wdt; this laptop's chipset may not expose a watchdog"
fi

if [ -e /dev/watchdog ]; then
  echo "Enabling systemd's runtime watchdog..."
  if ! grep -q '^RuntimeWatchdogSec=' /etc/systemd/system.conf 2>/dev/null; then
    echo "RuntimeWatchdogSec=30s" >> /etc/systemd/system.conf
  fi
  if ! grep -q '^RebootWatchdogSec=' /etc/systemd/system.conf 2>/dev/null; then
    echo "RebootWatchdogSec=10min" >> /etc/systemd/system.conf
  fi
  systemctl daemon-reexec
  echo "Watchdog armed: systemd will reboot the box if it stops responding for 30s+"
  echo "Make iTCO_wdt load on every boot:"
  echo "iTCO_wdt" | tee -a /etc/modules-load.d/watchdog.conf > /dev/null
else
  echo "Skipping watchdog config — no watchdog device available on this hardware"
fi

echo "Enabling persistent journald logging..."
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald
echo "Done. 'journalctl --list-boots' will now survive a hard reset,"
echo "so after the next freeze you can run:"
echo "  journalctl -b -1 -k --since '-15 min'"
echo "to see the last 15 minutes of kernel logs before it went down."