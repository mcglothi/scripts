#!/bin/bash

# scripts/rgb-control.sh - Control RGB lights via OpenRGB
# Usage: ./rgb-control.sh {on|off}

PROFILE_DIR="$HOME/.config/OpenRGB"
# OpenRGB appends .orp automatically
PROFILE_NAME="last_state"
PROFILE_PATH="$PROFILE_DIR/$PROFILE_NAME.orp"

mkdir -p "$PROFILE_DIR"

case "$1" in
    off)
        echo "Saving current state to $PROFILE_PATH..."
        openrgb --save-profile "$PROFILE_NAME"
        echo "Turning off all RGB lights..."
        # First try setting color to black (works for Direct/Static modes)
        openrgb --color 000000 >/dev/null 2>&1
        # Then try mode off for devices that support it
        openrgb --mode off >/dev/null 2>&1
        # Explicitly target DRAM as it can be stubborn
        openrgb --device "ENE DRAM" --mode off >/dev/null 2>&1
        ;;
    on)
        if [ -f "$PROFILE_PATH" ]; then
            echo "Restoring last state from $PROFILE_PATH..."
            openrgb --profile "$PROFILE_NAME"
        else
            echo "No last state found. Turning on static white..."
            # Try setting to static white, fallback to just color
            openrgb --mode static --color FFFFFF 2>/dev/null || openrgb --color FFFFFF
        fi
        ;;
    smart-on)
        HOUR=$(date +%H)
        if [ $HOUR -ge 8 ] && [ $HOUR -lt 20 ]; then
            echo "It's daytime ($HOUR:00). Turning lights on..."
            $0 on
        else
            echo "It's night time ($HOUR:00). Staying dark."
        fi
        ;;
    *)
        echo "Usage: $0 {on|off}"
        exit 1
        ;;
esac
