#!/usr/bin/env bash
# Disables USB autosuspend for the Seagate Desktop HDD 5TB (0bc2:331a)
# on server1-media. Autosuspend can put the drive to sleep mid-I/O;
# the kernel doesn't always recover cleanly from that, which can
# cascade into the whole box looking unresponsive.
#
# Run once with sudo.

set -euo pipefail

VENDOR="0bc2"
PRODUCT="331a"
RULE_FILE="/etc/udev/rules.d/50-usb-power-control.rules"

echo "Installing udev rule to keep ${VENDOR}:${PRODUCT} (Seagate HDD) always-on..."
cat > "$RULE_FILE" <<EOF
# Disable USB autosuspend for Seagate Desktop HDD 5TB on server1-media.
# Prevents the drive from being suspended mid-I/O, a suspected cause
# of full-system hangs requiring a hard reset.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${VENDOR}", ATTR{idProduct}=="${PRODUCT}", TEST=="power/control", ATTR{power/control}="on"
EOF

echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

echo "Applying immediately to the currently-connected device (no replug needed)..."
FOUND=0
for dev in /sys/bus/usb/devices/*/; do
  if [ -f "${dev}idVendor" ] && [ -f "${dev}idProduct" ]; then
    v=$(cat "${dev}idVendor" 2>/dev/null || true)
    p=$(cat "${dev}idProduct" 2>/dev/null || true)
    if [ "$v" = "$VENDOR" ] && [ "$p" = "$PRODUCT" ] && [ -f "${dev}power/control" ]; then
      echo on > "${dev}power/control"
      echo "Set power/control=on for ${dev}"
      FOUND=1
    fi
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "Device not currently connected — rule is installed and will apply on next plug-in/boot."
fi

echo "Done. Verify anytime with:"
echo "  grep -r . /sys/bus/usb/devices/*/idVendor 2>/dev/null | grep ${VENDOR}"