#!/usr/bin/env bash
# pixel-connect.sh — Auto-connect to Pixel phone via wireless ADB
#
# The ADB wireless debugging port changes every time WiFi reconnects,
# so this script scans the known range in parallel to find the active port.
#
# Usage: ./pixel-connect.sh [ip]
#   ip  — optional, overrides the default Pixel IP

set -euo pipefail

PIXEL_IP="${1:-10.10.140.4}"
PORT_MIN=37000
PORT_MAX=44000
TIMEOUT=0.3      # seconds per connection attempt
PARALLEL=50      # how many ports to probe simultaneously

# -- Check if already connected ----------------------------------------------

if adb devices 2>/dev/null | grep -q "^${PIXEL_IP}:"; then
    existing=$(adb devices | grep "^${PIXEL_IP}:")
    echo "Already connected: ${existing}"
    exit 0
fi

# -- Make sure ADB server is running -----------------------------------------

adb start-server > /dev/null 2>&1

echo "Scanning ${PIXEL_IP} ports ${PORT_MIN}–${PORT_MAX} for wireless ADB..."
echo "(${PARALLEL} ports at a time, ${TIMEOUT}s timeout each)"

# -- Parallel port scan -------------------------------------------------------
# Probe PARALLEL ports at a time. Use nc to cheaply test TCP reachability
# before wasting adb round-trips. Stop as soon as a working port is found.

probe_port() {
    local ip="$1"
    local port="$2"
    local timeout="$3"

    if nc -z -w 1 "$ip" "$port" 2>/dev/null; then
        result=$(timeout "$timeout" adb connect "${ip}:${port}" 2>/dev/null || true)
        if echo "$result" | grep -q "connected to"; then
            echo "$port"
        fi
    fi
}

export -f probe_port

found_port=$(
    seq "$PORT_MIN" "$PORT_MAX" \
    | xargs -P "$PARALLEL" -I{} bash -c 'probe_port "$@"' _ "$PIXEL_IP" {} "$TIMEOUT" \
    | head -1
)

# -- Result ------------------------------------------------------------------

if [[ -n "$found_port" ]]; then
    echo ""
    echo "Connected: ${PIXEL_IP}:${found_port}"
    adb -s "${PIXEL_IP}:${found_port}" devices
else
    echo ""
    echo "No wireless ADB connection found on ${PIXEL_IP} (ports ${PORT_MIN}–${PORT_MAX})."
    echo ""
    echo "To fix:"
    echo "  1. On the Pixel, go to Settings → Developer Options → Wireless debugging"
    echo "  2. Confirm it is enabled and connected to the same Wi-Fi network"
    echo "  3. The current port is shown on that screen — connect manually with:"
    echo "     adb connect ${PIXEL_IP}:<port>"
    exit 1
fi
