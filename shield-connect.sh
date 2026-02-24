#!/usr/bin/env bash
# shield-connect.sh — Connect to NVIDIA Shield via ADB
# Unlike the Pixel, the Shield uses a fixed port (5555).

SHIELD_IP="10.10.174.255"
PORT=5555

if adb devices | grep -q "${SHIELD_IP}:${PORT}"; then
    echo "Shield is already connected."
    exit 0
fi

echo "Connecting to Shield at ${SHIELD_IP}..."
adb connect "${SHIELD_IP}:${PORT}"
adb devices | grep "${SHIELD_IP}"
